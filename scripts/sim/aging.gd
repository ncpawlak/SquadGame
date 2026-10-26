class_name Aging
extends RefCounted
## Offseason aging: everyone gets a year older, and once a stat group is past its peak age its
## stats decline every year (more the further past the peak). Caps drop with them, so lost
## ratings can't simply be trained back.

## Last age before a group starts to decline.
const PEAK_AGE := {
	Stats.PHYSICALITY: 28,
	Stats.DURABILITY: 29,
	Stats.ACCURACY: 30,
	Stats.HANDLING: 31,
	Stats.MENTALITY: 33,
	Stats.OBJECTIVE: 31,
}
const MAX_LOSS_PER_STAT := 6


## Expected yearly loss per stat for a group `years_past` years beyond its peak.
static func decline_rate(years_past: int) -> float:
	if years_past <= 0:
		return 0.0
	return minf(1.0 + 0.75 * (years_past - 1), float(MAX_LOSS_PER_STAT))


## Ages one soldier by a year. Returns {soldier, age, changes: group -> rating change (<= 0)}.
static func age_soldier(s: Soldier, rng: RandomNumberGenerator) -> Dictionary:
	s.age += 1
	var changes := {}
	var stat_changes := {}
	var ovr_before := s.best_ovr()
	for g in Stats.GROUP_ORDER:
		var rate := decline_rate(s.age - int(PEAK_AGE[g]))
		if rate <= 0.0:
			continue
		var before := s.group_rating(g)
		for st in Stats.group_stats(g):
			var loss := mini(MAX_LOSS_PER_STAT, roundi(rate * rng.randf_range(0.5, 1.5)))
			var old: int = s.stats[st]
			s.stats[st] = Stats.clamp_rating(s.stats[st] - loss)
			stat_changes[st] = int(s.stats[st]) - old
		var delta := s.group_rating(g) - before
		if delta != 0:
			changes[g] = delta
		if s.group_caps.has(g):
			s.group_caps[g] = maxi(s.group_rating(g), int(s.group_caps[g]) + delta)
	s.log_progress("Age decline (turned %d)" % s.age, stat_changes, ovr_before)
	return {"soldier": s, "age": s.age, "changes": changes}


## Ages every rostered soldier and free agent in the league. Returns the reports of rostered
## soldiers who declined.
static func age_league(league: League, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for t in league.teams:
		for s in t.roster:
			var r := age_soldier(s, rng)
			r["team"] = t
			if not r["changes"].is_empty():
				out.append(r)
	for s in league.free_agents:
		age_soldier(s, rng)
	return out

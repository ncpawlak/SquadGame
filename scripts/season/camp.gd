class_name Camp
extends RefCounted
## Offseason training camp (after free agency, before Week 1): one drill per rating group.
## Each team sends one soldier to each drill and a soldier can attend only one drill per camp.
## A drill hands the soldier a pool of points (rolled from his potential) that is spread at
## random over the group's stats (max MAX_STAT_GAIN per stat, 99 max). Drills respect the
## group caps: a capped group can't be drilled and points stop landing at the cap. The
## Durability drill (no cap) is the only way to raise Injury/Toughness.

const DRILLS := {
	Stats.ACCURACY: {"name": "Marksmanship Range", "blurb": "Live-fire lanes at every distance."},
	Stats.HANDLING: {"name": "Weapons Lab", "blurb": "Reload and recoil-control reps under the clock."},
	Stats.PHYSICALITY: {"name": "Combine Gauntlet", "blurb": "Sprints, cone drills, sled pushes and the ruck march."},
	Stats.MENTALITY: {"name": "War Room", "blurb": "Film, comms and high-pressure decision drills."},
	Stats.OBJECTIVE: {"name": "Hill Assault", "blurb": "Capture, hold and retake reps on a live point."},
	Stats.DURABILITY: {"name": "Iron Conditioning", "blurb": "Prehab, contact work and pain tolerance."},
}
## Point pool [min, max] per potential grade (F..A).
const POINT_POOLS := [[2, 4], [3, 6], [5, 8], [7, 10], [9, 13]]
const MAX_STAT_GAIN := 4

var year := 0
## Team -> { group -> {soldier, gains (stat -> points), before (stat -> rating), points, ovr_before, ovr_after} }
var results := {}
## Soldier id -> group attended.
var attended := {}


static func make(camp_year: int) -> Camp:
	var c := Camp.new()
	c.year = camp_year
	return c


static func drill_name(group: StringName) -> String:
	return DRILLS[group]["name"]


static func pool_range(potential: int) -> Array:
	return POINT_POOLS[clampi(potential, 0, POINT_POOLS.size() - 1)]


func team_results(team: Team) -> Dictionary:
	return results.get(team, {})


func result_for(team: Team, group: StringName) -> Dictionary:
	return team_results(team).get(group, {})


func has_run(team: Team, group: StringName) -> bool:
	return team_results(team).has(group)


func has_attended(s: Soldier) -> bool:
	return attended.has(s.id)


func drills_left(team: Team) -> int:
	return DRILLS.size() - team_results(team).size()


## "" if `s` can run `group` for `team`, otherwise the reason.
func check(team: Team, group: StringName, s: Soldier) -> String:
	if not DRILLS.has(group):
		return "Unknown drill."
	if has_run(team, group):
		return "%s has already been run." % drill_name(group)
	if not team.roster.has(s):
		return "%s isn't on your roster." % s.full_name()
	if has_attended(s):
		return "%s already attended %s." % [s.full_name(), drill_name(attended[s.id])]
	if s.is_injured():
		return "%s is injured." % s.full_name()
	if s.group_caps.has(group) and s.group_headroom(group) <= 0:
		return "%s is capped at %d %s." % [s.full_name(), s.group_cap(group), Stats.GROUP_LABELS[group]]
	return ""


## Runs the drill. Returns the result dictionary (empty if refused).
func run(team: Team, group: StringName, s: Soldier, rng: RandomNumberGenerator) -> Dictionary:
	if check(team, group, s) != "":
		return {}
	var pool: Array = pool_range(s.potential)
	var rolled := rng.randi_range(pool[0], pool[1])
	var points := 0
	var capped := s.group_caps.has(group)
	var cap := s.group_cap(group)
	var members: Array = Stats.group_stats(group)
	var before := {}
	var gains := {}
	for st in members:
		before[st] = s.stats[st]
		gains[st] = 0
	var ovr_before := s.best_ovr()
	var blocked := {}
	for i in rolled:
		var open: Array = []
		for st in members:
			if not blocked.has(st) and gains[st] < MAX_STAT_GAIN and s.stats[st] < Stats.MAX_RATING:
				open.append(st)
		if open.is_empty():
			break
		var pick := Progression.pick_gain_stat(open, func(st): return s.stats[st], rng)
		s.stats[pick] += 1
		if capped and s.group_rating(group) > cap:
			s.stats[pick] -= 1
			blocked[pick] = true
			continue
		gains[pick] += 1
		points += 1
	s.log_progress("Training camp: %s" % drill_name(group), gains, ovr_before)
	var res := {"soldier": s, "group": group, "gains": gains, "before": before, "points": points, "rolled": rolled,
		"ovr_before": ovr_before, "ovr_after": s.best_ovr()}
	if not results.has(team):
		results[team] = {}
	results[team][group] = res
	attended[s.id] = group
	return res


## AI camp: each drill goes to the healthy soldier who'd gain the most OVR from it at his
## position, preferring young high-potential players.
func ai_run(team: Team, rng: RandomNumberGenerator) -> void:
	for g in DRILLS:
		if has_run(team, g):
			continue
		var best: Soldier = null
		var best_v := -INF
		for s in team.roster:
			if check(team, g, s) != "":
				continue
			var slot := team.slot_of(s)
			var role := team.scheme.role_for_slot(slot) if slot != &"" else Scheme.best_role(s.stats)
			var v := Progression.group_value(role, g) * 10.0 + s.potential * 2.0 - maxf(0.0, s.age - 26.0) + rng.randf()
			if team.starters().has(s):
				v += 3.0
			if v > best_v:
				best_v = v
				best = s
		if best != null:
			run(team, g, best, rng)

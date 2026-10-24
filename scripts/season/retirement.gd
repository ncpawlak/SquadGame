class_name Retirement
extends RefCounted
## End-of-season retirements (right after the final, before re-signing and the draft):
## - Rostered soldiers and free agents retire between 35 and 39 (everyone by 40), less often
##   if they're still good and more often if they've fallen off.
## - Free agents who sat unsigned for a whole season retire if they're under FA_MIN_OVR or at
##   least FA_MAX_AGE; the pool is also trimmed to FA_POOL_LIMIT (worst first), so it keeps churning.

## Chance to retire by age (39+ always retires).
const AGE_CHANCE := {35: 0.15, 36: 0.35, 37: 0.6, 38: 0.85}
const ALWAYS_AGE := 39
const FA_MIN_OVR := 55
const FA_MAX_AGE := 33
const FA_POOL_LIMIT := 30

const REASON_AGE := "Age"
const REASON_UNSIGNED := "Unsigned"


static func chance(s: Soldier) -> float:
	if s.age >= ALWAYS_AGE:
		return 1.0
	var c: float = AGE_CHANCE.get(s.age, 0.0)
	var ovr := s.best_ovr()
	if ovr >= 78:
		c *= 0.6
	elif ovr <= 60:
		c *= 1.4
	return minf(c, 1.0)


## Retires soldiers for the season that just ended. Returns the new records:
## {soldier, team (null = free agent), year, age, ovr, role, reason, matches, kills, awards}.
static func run(season: Season, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for t in season.league.teams:
		for s in t.roster.duplicate():
			if rng.randf() < chance(s):
				out.append(_retire(season, s, t, REASON_AGE))
	var pool := season.league.free_agents
	for s in pool.duplicate():
		if rng.randf() < chance(s):
			out.append(_retire(season, s, null, REASON_AGE))
		elif s.fa_since < season.year and (s.best_ovr() < FA_MIN_OVR or s.age >= FA_MAX_AGE):
			out.append(_retire(season, s, null, REASON_UNSIGNED))
	if pool.size() > FA_POOL_LIMIT:
		var ranked: Array = pool.duplicate()
		ranked.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() < b.best_ovr())
		for s in ranked.slice(0, pool.size() - FA_POOL_LIMIT):
			out.append(_retire(season, s, null, REASON_UNSIGNED))
	return out


static func _retire(season: Season, s: Soldier, team: Team, reason: String) -> Dictionary:
	var awards: Array = []
	for rev: SeasonReview in season.review_history:
		for a in rev.award_for(s):
			awards.append("%d %s" % [rev.year, a])
	var rec := {"soldier": s, "team": team, "year": season.year, "age": s.age, "ovr": s.best_ovr(),
		"role": Scheme.best_role(s.stats), "reason": reason, "matches": s.career["matches"],
		"kills": s.career["kills"], "awards": awards}
	if team != null:
		team.release(s)
	season.league.free_agents.erase(s)
	season.fa.offers = season.fa.offers.filter(func(o): return o["soldier"] != s)
	s.contract = null
	s.retired_year = season.year
	return rec

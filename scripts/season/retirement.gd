class_name Retirement
extends RefCounted
## Retirements happen at two points in the year:
## - Right after the final (run): rostered soldiers and free agents may retire from 35, and
##   everyone has retired by ALWAYS_AGE. Age alone rarely ends a career: a soldier who is still
##   good, and above all still starting, nearly always plays on until he's fallen off.
## - When the offseason closes (run_unsigned): free agents who went a full year unsigned (a whole
##   season plus the offseason after it) may retire, the more likely the lower their OVR. Then
##   the pool is trimmed to FA_POOL_LIMIT (worst first, again only from those a full year
##   unsigned), so it keeps churning.

## Base chance to retire by age, before the OVR and role factors (ALWAYS_AGE+ always retires).
const AGE_CHANCE := {35: 0.10, 36: 0.20, 37: 0.35, 38: 0.55, 39: 0.75}
const ALWAYS_AGE := 40
## Chance factor by OVR: the first band the soldier's best OVR reaches applies.
const OVR_FACTOR := [[80, 0.15], [75, 0.35], [70, 0.6], [60, 1.0], [0, 1.6]]
const STARTER_FACTOR := 0.6
const FREE_AGENT_FACTOR := 1.3

## Free agents a full year unsigned: never retire at FA_KEEP_OVR+, always below FA_MIN_OVR, and
## in between the chance rises as OVR falls (a bit more from FA_VETERAN_AGE).
const FA_MIN_OVR := 55
const FA_KEEP_OVR := 70
const FA_VETERAN_AGE := 33
const FA_VETERAN_FACTOR := 1.5
const FA_POOL_LIMIT := 36

const REASON_AGE := "Age"
const REASON_UNSIGNED := "Unsigned"


## Chance `s` retires for age after the season. `starter`: he's in his club's lineup;
## `free_agent`: he's in the pool.
static func chance(s: Soldier, starter := false, free_agent := false) -> float:
	if s.age >= ALWAYS_AGE:
		return 1.0
	var c: float = AGE_CHANCE.get(s.age, 0.0)
	if c <= 0.0:
		return 0.0
	c *= ovr_factor(s.best_ovr())
	if starter:
		c *= STARTER_FACTOR
	elif free_agent:
		c *= FREE_AGENT_FACTOR
	return minf(c, 1.0)


static func ovr_factor(ovr: int) -> float:
	for band in OVR_FACTOR:
		if ovr >= int(band[0]):
			return float(band[1])
	return float(OVR_FACTOR[-1][1])


## Chance a free agent a full year unsigned retires when the offseason closes.
static func unsigned_chance(s: Soldier) -> float:
	var ovr := s.best_ovr()
	if ovr >= FA_KEEP_OVR:
		return 0.0
	if ovr < FA_MIN_OVR:
		return 1.0
	var c := float(FA_KEEP_OVR - ovr) / float(FA_KEEP_OVR - FA_MIN_OVR)
	if s.age >= FA_VETERAN_AGE:
		c *= FA_VETERAN_FACTOR
	return minf(c, 1.0)


## True once `s` has been in the pool for a full season and the offseason after it.
static func unsigned_full_year(season: Season, s: Soldier) -> bool:
	return s.fa_since < season.year


## Age retirements for the season that just ended. Returns the new records:
## {soldier, team (null = free agent), year, age, ovr, role, reason, matches, kills, awards}.
static func run(season: Season, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for t in season.league.teams:
		var starters := t.starters()
		for s in t.roster.duplicate():
			if rng.randf() < chance(s, starters.has(s)):
				out.append(_retire(season, s, t, REASON_AGE))
	for s in season.league.free_agents.duplicate():
		if rng.randf() < chance(s, false, true):
			out.append(_retire(season, s, null, REASON_AGE))
	return out


## Unsigned retirements as the offseason closes (after the last free-agent calls). Returns
## records like run().
static func run_unsigned(season: Season, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var pool := season.league.free_agents
	for s in pool.duplicate():
		if unsigned_full_year(season, s) and rng.randf() < unsigned_chance(s):
			out.append(_retire(season, s, null, REASON_UNSIGNED))
	if pool.size() > FA_POOL_LIMIT:
		var ranked: Array = pool.filter(func(s: Soldier): return unsigned_full_year(season, s))
		ranked.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() < b.best_ovr())
		for s in ranked.slice(0, mini(ranked.size(), pool.size() - FA_POOL_LIMIT)):
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
	s.clear_extension()
	s.retired_year = season.year
	return rec
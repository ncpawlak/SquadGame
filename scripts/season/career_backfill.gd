class_name CareerBackfill
extends RefCounted
## Gives a brand-new league a past: every soldier older than ROOKIE_AGE gets a made-up career line
## for each earlier season, so careers, records and the Hall of Fame have depth from day one.
##
## The lines carry no club (team ""), so they never count toward a club's records or a retired
## callsign. Per-match rates follow what the sim really produces by overall rating (measured
## from a simulated season), with a per-season form roll and noise on top.

## Soldiers this age or younger have no pro seasons behind them.
const ROOKIE_AGE := 21
const MAX_SEASONS := 9
## A full-time starter's matches in a season, and the overall below which a soldier did not play.
const FULL_MATCHES := 11
const BENCH_OVR := 60.0
const STARTER_OVR := 75.0
## Overall rating gained per year below PRIME_AGE, so younger seasons were a little worse.
const PRIME_AGE := 27
const GROWTH_PER_YEAR := 1.6
const GAMES_PER_MATCH := 2.12


## Writes the past onto every soldier in the league. Deterministic for a given rng.
static func run(league: League, start_year: int, rng: RandomNumberGenerator) -> void:
	for so: Soldier in league.all_soldiers():
		var seasons := clampi(so.age - ROOKIE_AGE, 0, MAX_SEASONS)
		for i in seasons:
			var year := start_year - seasons + i
			var line := season_line(so, so.age - (start_year - year), rng)
			if line.is_empty():
				continue
			so.season_lines[year] = line
			for k in Soldier.STAT_LINE_KEYS:
				so.career[k] = int(so.career[k]) + int(line[k])


## One made-up season for `so` at `age_then`, or {} if he did not play.
static func season_line(so: Soldier, age_then: int, rng: RandomNumberGenerator) -> Dictionary:
	var ovr := float(so.best_ovr()) - maxf(0.0, float(PRIME_AGE - age_then)) * GROWTH_PER_YEAR + rng.randf_range(-2.0, 2.0)
	if ovr < BENCH_OVR:
		return {}
	var matches := roundi(FULL_MATCHES * clampf((ovr - BENCH_OVR) / 15.0, 0.25, 1.0)) + rng.randi_range(-1, 1)
	if matches < 1:
		return {}
	var d := ovr - STARTER_OVR
	var form := rng.randf_range(0.88, 1.14)
	var m := float(matches)
	var kills := roundi(m * maxf(3.0, 7.8 + 0.16 * d) * form)
	var line := {"team": "", "matches": matches,
		"kills": kills,
		"deaths": roundi(m * maxf(4.0, 9.2 - 0.12 * d) * rng.randf_range(0.92, 1.08)),
		"assists": roundi(m * maxf(4.0, 11.4 + 0.33 * d) * form),
		"damage": roundi(m * maxf(400.0, 840.0 + 12.0 * d) * form),
		"headshots": roundi(kills * rng.randf_range(0.58, 0.66)),
		"shots": roundi(m * (245.0 + 1.5 * d)),
		"hits": roundi(m * (40.0 + 0.9 * d)),
		"saves": roundi(m * maxf(0.2, 0.4 + 0.01 * d)),
		"wipes": roundi(m * maxf(0.5, 1.4 + 0.04 * d)),
		"hill_s": roundi(m * maxf(10.0, 33.0 + 1.2 * d)),
		"caps": roundi(m * maxf(0.2, 0.8 + 0.02 * d)),
		"rounds": roundi(m * 0.7),
		"games": roundi(m * GAMES_PER_MATCH),
		"mvps": _count(m * clampf(0.09 + 0.004 * d, 0.02, 0.2), rng),
		"clutches": _count(m * clampf(0.0035 * (ovr - 72.0), 0.0, 0.06), rng)}
	return line


## An expected count rounded up or down at random, so small rates still land sometimes.
static func _count(expected: float, rng: RandomNumberGenerator) -> int:
	var whole := int(expected)
	return whole + (1 if rng.randf() < expected - whole else 0)

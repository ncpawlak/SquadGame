class_name Combine
extends RefCounted
## Player mode phase 2 (#100/#101): the combine. Each drill (see Camp.DRILLS) is a run of short skill tasks, one per
## rating, each scoring 0..1. A drill can be run up to TRIES times and the best score per stat counts.
##
## A score turns into a *band* of ratings, not a single number: the centre moves from FLOOR (score 0) to the
## archetype's ceiling for that stat (score 1), and the band is BAND_HALF either side, clipped to FLOOR..ceiling.
## The player sees the bands. His true rating is a hidden point inside each band, placed by his talent (dev stars)
## and luck, so a great run raises the band but cannot promise the top of it.
##
## Starting OVR is capped (Archetypes.START_OVR_CAP): if the *top* of the bands would put him above the cap, every
## band is pulled toward FLOOR by one common factor, which keeps his true ratings under the cap without the cap
## leaking where inside the bands he landed.

const TRIES := 3
const BAND_HALF := 5
## Score-to-rating curve exponent: above 1 makes the top of the range harder to reach.
const CURVE := 1.3
## Order of the drills, matching the camp.
const DRILL_ORDER: Array[StringName] = [Stats.ACCURACY, Stats.HANDLING, Stats.PHYSICALITY, Stats.MENTALITY, Stats.OBJECTIVE]

## Per drill, the tasks to run. Each entry: stat (the rating it scores), task (a CombineTasks type), a label and the
## task's own parameters. Hill Assault uses simple stand-in tasks until its scenario mini-game exists.
const TASKS := {
	Stats.ACCURACY: [
		{"stat": Stats.SHORT_ACC, "task": &"targets", "label": "Short range", "size": 96.0, "life": 1.5, "count": 8},
		{"stat": Stats.MEDIUM_ACC, "task": &"targets", "label": "Medium range", "size": 64.0, "life": 1.25, "count": 8},
		{"stat": Stats.LONG_ACC, "task": &"targets", "label": "Long range", "size": 40.0, "life": 1.1, "count": 8},
	],
	Stats.HANDLING: [
		{"stat": Stats.RELOAD, "task": &"timing", "label": "Reload", "zone": 0.16, "speed": 1.0, "rounds": 5},
		{"stat": Stats.GROUPING, "task": &"recoil", "label": "Burst grouping", "shots": 8},
		{"stat": Stats.SWAY, "task": &"track", "label": "Hold steady", "radius": 64.0, "drift": 70.0, "push": 0.0, "secs": 10.0},
	],
	Stats.PHYSICALITY: [
		{"stat": Stats.SPEED, "task": &"mash", "label": "Sprint", "mode": &"alt", "secs": 6.0, "goal": 48.0},
		{"stat": Stats.AGILITY, "task": &"quick", "label": "Cone course", "kind": &"arrows", "count": 12, "limit": 1.0},
		{"stat": Stats.STRENGTH, "task": &"mash", "label": "Sled push", "mode": &"lift", "secs": 10.0, "goal": 1.0},
		{"stat": Stats.ENDURANCE, "task": &"pace", "label": "Ruck march", "secs": 15.0},
	],
	Stats.MENTALITY: [
		{"stat": Stats.AWARENESS, "task": &"recall", "label": "Map recall", "n": 5, "show": 2.5, "rounds": 3},
		{"stat": Stats.COMPOSURE, "task": &"quick", "label": "Under pressure", "kind": &"colors", "count": 12, "limit": 1.6},
		{"stat": Stats.TEAMWORK, "task": &"sequence", "label": "Callouts", "start": 3, "rounds": 5},
	],
	Stats.OBJECTIVE: [
		{"stat": Stats.ANCHOR, "task": &"track", "label": "Hold the point", "radius": 52.0, "drift": 100.0, "push": 160.0, "secs": 10.0},
		{"stat": Stats.BREACH, "task": &"timing", "label": "Breach timing", "zone": 0.09, "speed": 1.5, "rounds": 5},
		{"stat": Stats.OBJ_IQ, "task": &"quick", "label": "Hill calls", "kind": &"calls", "count": 6, "limit": 6.0},
	],
}

var archetype: StringName = &""
## His age when he took the combine: younger means lower ceilings (Archetypes.age_offset).
var age := Archetypes.AGE_MAX
## stat -> best score so far (0..1).
var best := {}
## drill group -> tries used.
var tries := {}


static func make(archetype_id: StringName, start_age := Archetypes.AGE_MAX) -> Combine:
	var c := Combine.new()
	c.archetype = archetype_id
	c.age = start_age
	return c


static func drill_tasks(group: StringName) -> Array:
	return TASKS[group]


## True for a stat some drill scores.
static func is_drilled(stat: StringName) -> bool:
	for g in DRILL_ORDER:
		for t in TASKS[g]:
			if t["stat"] == stat:
				return true
	return false


func tries_left(group: StringName) -> int:
	return TRIES - int(tries.get(group, 0))


func has_run(group: StringName) -> bool:
	return int(tries.get(group, 0)) > 0


func is_complete() -> bool:
	for g in DRILL_ORDER:
		if not has_run(g):
			return false
	return true


## Records one try of a drill: `scores` maps each of the drill's stats to 0..1. The best per stat is kept.
## Returns false (and records nothing) when the drill has no tries left.
func record_try(group: StringName, scores: Dictionary) -> bool:
	if tries_left(group) <= 0:
		return false
	for t in TASKS[group]:
		var stat: StringName = t["stat"]
		var v := clampf(float(scores.get(stat, 0.0)), 0.0, 1.0)
		best[stat] = maxf(float(best.get(stat, 0.0)), v)
	tries[group] = int(tries.get(group, 0)) + 1
	return true


## Centre rating for a score and a ceiling, before the band and the cap.
static func center(score: float, ceiling: int) -> float:
	return float(Archetypes.FLOOR) + pow(clampf(score, 0.0, 1.0), CURVE) * float(ceiling - Archetypes.FLOOR)


## One stat's band before the cap: Vector2i(low, high).
static func raw_band(score: float, ceiling: int) -> Vector2i:
	var c := center(score, ceiling)
	return Vector2i(clampi(roundi(c - BAND_HALF), Archetypes.FLOOR, ceiling), clampi(roundi(c + BAND_HALF), Archetypes.FLOOR, ceiling))


## stat -> Vector2i(low, high) for every drilled stat, with the start cap applied. A drill never run scores 0.
func bands() -> Dictionary:
	var ceil := Archetypes.ceilings(archetype, age)
	var raw := {}
	for stat in ceil:
		raw[stat] = raw_band(float(best.get(stat, 0.0)), int(ceil[stat]))
	var k := cap_factor(raw, Archetypes.role_of(archetype))
	if k >= 1.0:
		return raw
	var out := {}
	for stat in raw:
		out[stat] = Vector2i(_pull(raw[stat].x, k), _pull(raw[stat].y, k))
	return out


static func _pull(v: int, k: float) -> int:
	return clampi(roundi(float(Archetypes.FLOOR) + float(v - Archetypes.FLOOR) * k), Archetypes.FLOOR, Stats.MAX_RATING)


## The common factor (<= 1) that brings the *top* of the bands to the start cap at the role's OVR.
static func cap_factor(raw: Dictionary, role: Scheme.Role) -> float:
	if _top_ovr(raw, role, 1.0) <= Archetypes.START_OVR_CAP:
		return 1.0
	var lo := 0.0
	var hi := 1.0
	for i in 20:
		var mid := (lo + hi) / 2.0
		if _top_ovr(raw, role, mid) <= Archetypes.START_OVR_CAP:
			lo = mid
		else:
			hi = mid
	return lo


static func _top_ovr(raw: Dictionary, role: Scheme.Role, k: float) -> int:
	var stats := {}
	for s in Stats.ALL:
		stats[s] = Archetypes.FLOOR
	stats.merge(Archetypes.FIXED_STATS, true)
	for stat in raw:
		stats[stat] = _pull(raw[stat].y, k)
	return Scheme.ovr_for_role(stats, role)


## OVR range of the bands: Vector2i(low, high), at the archetype's role.
func ovr_range() -> Vector2i:
	var b := bands()
	var lo := {}
	var hi := {}
	for s in Stats.ALL:
		lo[s] = Archetypes.FLOOR
		hi[s] = Archetypes.FLOOR
	lo.merge(Archetypes.FIXED_STATS, true)
	hi.merge(Archetypes.FIXED_STATS, true)
	for stat in b:
		lo[stat] = b[stat].x
		hi[stat] = b[stat].y
	var role := Archetypes.role_of(archetype)
	return Vector2i(Scheme.ovr_for_role(lo, role), Scheme.ovr_for_role(hi, role))


## Locks the combine in: rolls the hidden talent (dev stars) and a true rating inside each band, sets the growth caps,
## and writes it all to the soldier. Returns the bands (what the player is shown). `rng` makes it reproducible.
func finalize(s: Soldier, rng: RandomNumberGenerator) -> Dictionary:
	var b := bands()
	# The hidden talent roll (1-4): it leans where inside a band he lands and sets his growth caps. His dev stars
	# are separate and earned: everyone starts at 1 star (see WeeklyPlan).
	var talent := PlayerGenerator.roll_dev(rng, s.age)
	s.dev = talent
	var lean := (float(talent) - 2.5) * 0.08
	for stat in b:
		var u := clampf(rng.randfn(0.5 + lean, 0.25), 0.0, 1.0)
		s.stats[stat] = roundi(lerpf(float(b[stat].x), float(b[stat].y), u))
	s.stats.merge(Archetypes.FIXED_STATS, true)
	PlayerGenerator.roll_caps(s, rng)
	s.talent = talent
	s.dev = Soldier.DEV_MIN
	return b

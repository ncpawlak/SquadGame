class_name Soldier
extends RefCounted
## A single player/soldier. Ratings live in `stats`. `potential` is an A-F grade that scales XP
## gain; each upgradable stat group also has a hidden cap in `group_caps` (rolled at random but
## larger for higher potential): skill points can't raise a group past its cap.

const INTENSITY_REST := &"rest"
const INTENSITY_LIGHT := &"light"
const INTENSITY_NORMAL := &"normal"
const INTENSITY_HEAVY := &"heavy"

## Potential grades, worst to best (index = Soldier.potential).
const POTENTIAL_LETTERS := ["F", "D", "C", "B", "A"]
const POTENTIAL_A := 4

var id: int
var first_name: String
var last_name: String
var age: int
var stats: Dictionary = {}
## group id -> cap (0-99) for each of Stats.UPGRADABLE_GROUPS.
var group_caps: Dictionary = {}
## 0 (F) .. 4 (A). Scales XP gain; moves with end-of-season performance and age.
var potential: int = 2
## Year he was drafted (0 = not a draftee). Used for Rookie of the Year.
var draft_year: int = 0

# Contract / free agency
## Current deal (null = free agent, retired, or a debug soldier).
var contract: Contract = null
## Season year he entered the free-agent pool (free agents only).
var fa_since: int = 0
## Free agents lower their asking price the longer they go unsigned (1.0 = full market value).
var ask_mult: float = 1.0
## Year he retired (0 = active).
var retired_year: int = 0

# Progression (levels are internal: each one just grants skill points)
var level: int = 1
var xp: int = 0
var skill_points: int = 0
## Per-stat "usage" accumulated from match actions since the last level-up.
## Nudges how the AI spends skill points.
var usage: Dictionary = {}

# Condition
## 0-100. Builds from matches and training, recovers each week. Hurts performance above ~50
## and raises injury chance.
var fatigue: float = 0.0
## Weekly training intensity (Soldier.INTENSITY_*).
var intensity: StringName = INTENSITY_NORMAL
## Weeks left on the injury list (0 = healthy).
var injury_weeks: int = 0
var injury_name: String = ""

## Nickname shown on cards, rows and the kill feed (unique within the league; "" = none yet).
var callsign: String = ""

# Morale
## 0-100 (75 = neutral). Below 75 each 5-point step drops a random stat by 1-3; above 85 each
## 5-point step boosts one. Driven by playing time, results and contract fairness.
var morale: float = MORALE_NEUTRAL
var _mods_key := -999
var _mods: Dictionary = {}

const MORALE_NEUTRAL := 75.0
const MORALE_BOOST_START := 85.0
## Morale never touches the durability stats.
const MORALE_EXCLUDED: Array[StringName] = [&"injury", &"toughness"]

# Career totals
const STAT_LINE_KEYS: Array[String] = ["matches", "rounds", "kills", "deaths", "assists", "damage", "saves",
	"headshots", "shots", "hits", "mvps", "clutches"]
var career := {"matches": 0, "rounds": 0, "kills": 0, "deaths": 0, "assists": 0, "damage": 0, "saves": 0,
	"headshots": 0, "shots": 0, "hits": 0, "mvps": 0, "clutches": 0}
## Season year -> totals with the same keys as `career` (plus "team" abbrev).
var season_lines: Dictionary = {}


func _init() -> void:
	for s in Stats.ALL:
		usage[s] = 0.0


func full_name() -> String:
	return "%s %s" % [first_name, last_name]


func short_name() -> String:
	return "%s. %s" % [first_name.left(1), last_name]


## Jared "Ghost" Barrett.
func display_name() -> String:
	if callsign == "":
		return full_name()
	return "%s \"%s\" %s" % [first_name, callsign, last_name]


## GHOST (or the short name before a callsign is given).
func tag() -> String:
	return callsign.to_upper() if callsign != "" else short_name()


# --- morale -------------------------------------------------------------------

## Signed number of morale steps: -N below neutral, +N above the boost line, 0 in between.
func morale_steps() -> int:
	if morale < MORALE_NEUTRAL:
		return -int((MORALE_NEUTRAL - morale) / 5.0)
	if morale > MORALE_BOOST_START:
		return int((morale - (MORALE_BOOST_START - 5.0)) / 5.0)
	return 0


## stat -> temporary delta from morale. Deterministic per soldier and step.
func morale_mods() -> Dictionary:
	var steps := morale_steps()
	if steps == _mods_key:
		return _mods
	_mods_key = steps
	_mods = {}
	var pool: Array[StringName] = []
	for s in Stats.ALL:
		if not MORALE_EXCLUDED.has(s):
			pool.append(s)
	var dir := 1 if steps > 0 else -1
	var rng := RandomNumberGenerator.new()
	for i in absi(steps):
		rng.seed = hash([id, i, dir])
		var stat: StringName = pool[rng.randi_range(0, pool.size() - 1)]
		_mods[stat] = int(_mods.get(stat, 0)) + dir * rng.randi_range(1, 3)
	return _mods


func eff_stat(stat: StringName) -> int:
	return clampi(int(stats[stat]) + int(morale_mods().get(stat, 0)), Stats.MIN_RATING, Stats.MAX_RATING)


## Ratings with morale applied (what the match sim uses).
func effective_stats() -> Dictionary:
	var mods := morale_mods()
	if mods.is_empty():
		return stats
	var out := stats.duplicate()
	for s in mods:
		out[s] = clampi(int(out[s]) + int(mods[s]), Stats.MIN_RATING, Stats.MAX_RATING)
	return out


func effective_ovr_at_role(role: Scheme.Role) -> int:
	return Scheme.ovr_for_role(effective_stats(), role)


## Morale's effect on an OVR at a role (e.g. -4 shows as "69 (-4)").
func morale_ovr_delta(role: Scheme.Role) -> int:
	return effective_ovr_at_role(role) - ovr_at_role(role)


func add_morale(amount: float) -> void:
	morale = clampf(morale + amount, 0.0, 100.0)


static func morale_label(m: float) -> String:
	if m >= 90.0:
		return "Ecstatic"
	if m >= 80.0:
		return "Happy"
	if m >= 70.0:
		return "Content"
	if m >= 55.0:
		return "Unhappy"
	return "Furious"


func get_stat(stat: StringName) -> int:
	return stats[stat]


func ovr_at_role(role: Scheme.Role) -> int:
	return Scheme.ovr_for_role(stats, role)


func best_ovr() -> int:
	return ovr_at_role(Scheme.best_role(stats))


func group_rating(group: StringName) -> int:
	return Stats.group_rating(stats, group)


func group_cap(group: StringName) -> int:
	return int(group_caps.get(group, group_rating(group)))


## Group upgrades left before the cap (0 = capped).
func group_headroom(group: StringName) -> int:
	return maxi(0, group_cap(group) - group_rating(group))


func is_injured() -> bool:
	return injury_weeks > 0


func potential_letter() -> String:
	return POTENTIAL_LETTERS[clampi(potential, 0, POTENTIAL_A)]


## Ratings if every upgradable group reached its cap (each stat raised by the group's headroom).
func potential_stats() -> Dictionary:
	var out := stats.duplicate()
	for g in Stats.UPGRADABLE_GROUPS:
		var room := group_headroom(g)
		for s in Stats.group_stats(g):
			out[s] = mini(Stats.MAX_RATING, int(stats[s]) + room)
	return out


## Best-role OVR at full potential.
func potential_ovr() -> int:
	var p := potential_stats()
	return Scheme.ovr_for_role(p, Scheme.best_role(p))


func add_usage(stat: StringName, amount: float) -> void:
	usage[stat] += amount

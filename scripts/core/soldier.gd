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

# Career totals
var career := {"matches": 0, "rounds": 0, "kills": 0, "deaths": 0, "assists": 0, "damage": 0}


func _init() -> void:
	for s in Stats.ALL:
		usage[s] = 0.0


func full_name() -> String:
	return "%s %s" % [first_name, last_name]


func short_name() -> String:
	return "%s. %s" % [first_name.left(1), last_name]


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

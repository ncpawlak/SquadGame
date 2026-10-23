class_name Soldier
extends RefCounted
## A single player/soldier. Ratings live in `stats`; each stat has a hidden cap in `caps`
## (their potential) that progression can never push past.

var id: int
var first_name: String
var last_name: String
var age: int
var stats: Dictionary = {}
var caps: Dictionary = {}

# Progression
var level: int = 1
var xp: int = 0
var skill_points: int = 0
## Per-stat "usage" accumulated from match actions and training focus since the last level-up.
## Biases which stat gets the random breakthrough on level-up and how the AI spends points.
var usage: Dictionary = {}

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


func headroom(stat: StringName) -> int:
	return caps[stat] - stats[stat]


## Average of caps at the soldier's best role: a rough "potential" OVR.
func potential_ovr() -> int:
	return Scheme.ovr_for_role(caps, Scheme.best_role(caps))


func add_usage(stat: StringName, amount: float) -> void:
	usage[stat] += amount

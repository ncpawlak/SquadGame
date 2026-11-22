class_name FpsCombineDrills
extends RefCounted
## Which 3D drill scene measures which combine stat. The combine screen runs the 3D drill for a stat when one exists and
## falls back to the 2D mini-game when it does not. Speed and agility share one obstacle course (it scores both).

const SCENES := {
	Stats.SHORT_ACC: "res://scenes/fps/drills/range_short.tscn",
	Stats.MEDIUM_ACC: "res://scenes/fps/drills/range_medium.tscn",
	Stats.LONG_ACC: "res://scenes/fps/drills/range_long.tscn",
	Stats.RELOAD: "res://scenes/fps/drills/reload.tscn",
	Stats.GROUPING: "res://scenes/fps/drills/grouping.tscn",
	Stats.SWAY: "res://scenes/fps/drills/sway.tscn",
	Stats.SPEED: "res://scenes/fps/drills/course.tscn",
	Stats.AGILITY: "res://scenes/fps/drills/course.tscn",
	Stats.STRENGTH: "res://scenes/fps/drills/sled.tscn",
	Stats.ENDURANCE: "res://scenes/fps/drills/ruck.tscn",
	Stats.AWARENESS: "res://scenes/fps/drills/maze.tscn",
	Stats.COMPOSURE: "res://scenes/fps/drills/composure.tscn",
	Stats.TEAMWORK: "res://scenes/fps/drills/callouts.tscn",
	Stats.ANCHOR: "res://scenes/fps/drills/hold.tscn",
	Stats.BREACH: "res://scenes/fps/drills/breach.tscn",
	Stats.OBJ_IQ: "res://scenes/fps/drills/defense.tscn",
}


## The scene path for a stat, or "" when there is no 3D drill for it (yet).
static func scene_for(stat: StringName) -> String:
	var path: String = SCENES.get(stat, "")
	if path != "" and ResourceLoader.exists(path):
		return path
	return ""


static func available(stat: StringName) -> bool:
	return scene_for(stat) != ""


## How many of the combine's drilled stats have a 3D drill right now.
static func coverage() -> Array:
	var have := 0
	var total := 0
	for g in Combine.DRILL_ORDER:
		for t in Combine.drill_tasks(g):
			total += 1
			if available(t["stat"]):
				have += 1
	return [have, total]

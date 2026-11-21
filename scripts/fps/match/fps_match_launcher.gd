class_name FpsMatchLauncher
extends RefCounted
## Builds a playable hill match from two existing Team rosters.

const MAP_SCENE := "res://scenes/fps/match/hill_map.tscn"


## Adds the map and match under `parent`, starts it, and returns the FpsHillMatch.
## Connect to its match_finished(result) signal; result.box is keyed by soldier id.
static func launch(parent: Node, team_a: Team, team_b: Team, seed_value := 1, options := {}) -> FpsHillMatch:
	var map: Node3D = load(MAP_SCENE).instantiate()
	parent.add_child(map)
	var m := FpsHillMatch.new()
	m.hold_to_win = float(options.get("hold_to_win", FpsHillRules.HOLD_TO_WIN_S))
	m.round_s = float(options.get("round_s", FpsHillRules.ROUND_S))
	m.respawn_s = float(options.get("respawn_s", FpsHillRules.RESPAWN_S))
	parent.add_child(m)
	m.start(team_a, team_b, map, seed_value)
	return m

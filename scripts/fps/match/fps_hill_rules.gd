class_name FpsHillRules
extends RefCounted
## Pure hill rules: no nodes, so tests can drive them directly.
## Same model as the numeric sim: only a team alone on the point banks time; both on it = contested.

enum Zone { EMPTY, TEAM0, TEAM1, CONTESTED }

const HOLD_TO_WIN_S := 120.0
const ROUND_S := 300.0
const RESPAWN_S := 6.0


static func zone_state(on0: int, on1: int) -> Zone:
	if on0 > 0 and on1 > 0:
		return Zone.CONTESTED
	if on0 > 0:
		return Zone.TEAM0
	if on1 > 0:
		return Zone.TEAM1
	return Zone.EMPTY


## Team index that banks time this step, or -1 (empty or contested).
static func scoring_team(zone: Zone) -> int:
	if zone == Zone.TEAM0:
		return 0
	if zone == Zone.TEAM1:
		return 1
	return -1


## New holder after this step. A contested or empty point keeps the previous holder; only a lone team takes it.
static func next_holder(prev_holder: int, zone: Zone) -> int:
	var t := scoring_team(zone)
	return t if t >= 0 else prev_holder


## Adds dt seconds to the scoring team. Returns a new array.
static func step_score(scores: Array, zone: Zone, dt: float) -> Array:
	var out := scores.duplicate()
	var t := scoring_team(zone)
	if t >= 0:
		out[t] = float(out[t]) + dt
	return out


## -1 while running, 0/1 for a winner, 2 for a draw. Hold target wins early; at time up, higher score wins.
static func winner(scores: Array, time_left: float, hold_to_win := HOLD_TO_WIN_S) -> int:
	var a := float(scores[0])
	var b := float(scores[1])
	if a >= hold_to_win or b >= hold_to_win:
		if is_equal_approx(a, b):
			return 2
		return 0 if a > b else 1
	if time_left > 0.0:
		return -1
	if is_equal_approx(a, b):
		return 2
	return 0 if a > b else 1


static func respawn_ready(dead_for: float, delay := RESPAWN_S) -> bool:
	return dead_for >= delay


static func new_box(soldier_id: int, team: int, slot: StringName) -> Dictionary:
	return {"soldier": soldier_id, "team": team, "slot": slot, "kills": 0, "deaths": 0, "assists": 0,
		"caps": 0, "hill_s": 0.0, "contest_s": 0.0}

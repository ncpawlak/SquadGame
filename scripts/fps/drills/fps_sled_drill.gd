class_name FpsSledDrill
extends FpsDrill
## Sled push (STRENGTH): tap Space in rhythm. Force decays all the time, every tap adds force, and the resistance rises
## along the lane; the sled only moves while force is above the resistance. Score: time to the end against a par (a
## finished push is always worth more than a stalled one); out of time you get a little credit for distance.

const LANE_LENGTH := 20.0
const MAX_FORCE := 100.0
const TAP_FORCE := 10.0
## Force lost per second is DECAY * force (exponential), so only steady tapping holds it up.
const DECAY := 0.8
const RESIST_START := 30.0
const RESIST_END := 80.0
## Metres per second per unit of force above the resistance.
const PUSH_GAIN := 0.1
const PAR_TIME := 9.0
const FINISH_BASE := 0.35
const STALL_CREDIT := 0.3

var distance := 0.0
var force := 0.0
var finished_push := false
var finish_time := 0.0
var _sled: StaticBody3D


func _init() -> void:
	super()
	stat = Stats.STRENGTH
	title = "Sled push"
	instructions = "Tap SPACE in rhythm to keep your force above the rising resistance."
	duration = 30.0
	lock_player = true
	player_spawn = Vector3(0, 0.1, 0)


# ---- pure rules -----------------------------------------------------------------------------------------------------

## Resistance at `dist` metres along the lane.
static func resistance_at(dist: float) -> float:
	return lerpf(RESIST_START, RESIST_END, clampf(dist / LANE_LENGTH, 0.0, 1.0))


## Force after `delta` seconds of decay.
static func decay_force(f: float, delta: float) -> float:
	return maxf(f * exp(-DECAY * delta), 0.0)


## Force after one tap.
static func tap_force(f: float) -> float:
	return minf(f + TAP_FORCE, MAX_FORCE)


## Sled speed (m/s): only the force above the resistance moves it.
static func sled_speed(f: float, resist: float) -> float:
	return maxf(f - resist, 0.0) * PUSH_GAIN


## 1 at par or faster, 0 at the time limit; a finished push scores FINISH_BASE..1, an unfinished one at most STALL_CREDIT.
static func sled_score(is_finished: bool, secs: float, dist: float, time_limit: float) -> float:
	if is_finished:
		return FpsDrill.clamp01(FINISH_BASE + (1.0 - FINISH_BASE) * FpsDrill.time_score(secs, PAR_TIME, time_limit))
	var p := FpsDrill.clamp01(dist / LANE_LENGTH)
	return FpsDrill.clamp01(STALL_CREDIT * p * p)


# ---- drill ----------------------------------------------------------------------------------------------------------

func _build() -> void:
	# Lane walls and finish line.
	add_box(Vector3(-2.2, 0.6, -LANE_LENGTH * 0.5 - 1.5), Vector3(0.3, 1.2, LANE_LENGTH + 6.0), Color(0.4, 0.4, 0.45))
	add_box(Vector3(2.2, 0.6, -LANE_LENGTH * 0.5 - 1.5), Vector3(0.3, 1.2, LANE_LENGTH + 6.0), Color(0.4, 0.4, 0.45))
	var line := add_box(Vector3(0, 0.03, -LANE_LENGTH - 2.0), Vector3(4.0, 0.06, 0.5), Color(0.95, 0.95, 0.95))
	line.collision_layer = 0
	_sled = add_box(Vector3(0, 0.45, -1.5), Vector3(2.0, 0.9, 1.4), Color(0.45, 0.3, 0.2))


func _begin() -> void:
	distance = 0.0
	force = 0.0
	finished_push = false
	finish_time = 0.0
	_apply_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		tap()


## One tap of the key: adds force while the drill is running.
func tap() -> void:
	if state != State.RUNNING:
		return
	force = tap_force(force)


func _run(delta: float) -> void:
	force = decay_force(force, delta)
	distance = minf(distance + sled_speed(force, resistance_at(distance)) * delta, LANE_LENGTH)
	_apply_position()
	if distance >= LANE_LENGTH and not finished_push:
		finished_push = true
		finish_time = elapsed
		finish(_final_score())


func _apply_position() -> void:
	if _sled != null:
		_sled.position.z = -1.5 - distance
	if player != null:
		player.position.z = player_spawn.z - distance


func _final_score() -> float:
	return FpsSledDrill.sled_score(finished_push, finish_time if finished_push else elapsed, distance, duration)


func _hud_extra() -> String:
	var res := resistance_at(distance)
	return "Force %d  Resistance %d  %s\n%d / %d m" % [roundi(force), roundi(res), "PUSHING" if force > res else "stalled", roundi(distance), roundi(LANE_LENGTH)]

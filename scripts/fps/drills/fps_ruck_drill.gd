class_name FpsRuckDrill
extends FpsDrill
## Ruck run (ENDURANCE): run a ring of checkpoints for a fixed time on the real stamina system (sprinting drains it,
## walking recovers it, running dry forces a walk until some stamina is back). Score: distance covered against a par and an
## elite distance, so good pacing beats flat-out sprinting only if it covers more ground.

const RING_CENTRE := Vector3(0, 0, -25)
const RING_RADIUS := 22.0
const CHECKPOINTS_PER_LAP := 16
const LAPS := 3
const PASS_RADIUS := 3.5
## Distance (metres) in the run time that scores 0.6 (par) and 1.0 (elite).
const PAR_DISTANCE := 230.0
const ELITE_DISTANCE := 280.0
const PAR_SCORE := 0.6

var next_checkpoint := 0
var passed := 0
var _beacon: StaticBody3D


func _init() -> void:
	super()
	stat = Stats.ENDURANCE
	title = "Ruck run"
	instructions = "Run the ring through the checkpoints. Sprinting tires you out: pace yourself."
	duration = 45.0
	player_spawn = FpsRuckDrill.checkpoint_pos(0) + Vector3(0, 0.1, 0)


# ---- pure rules -----------------------------------------------------------------------------------------------------

static func total_checkpoints() -> int:
	return CHECKPOINTS_PER_LAP * LAPS


## Ring point of checkpoint `i` (checkpoint 0 is where the player starts; they run anticlockwise seen from above).
static func checkpoint_pos(i: int) -> Vector3:
	var a := TAU * float(i) / float(CHECKPOINTS_PER_LAP)
	return RING_CENTRE + Vector3(sin(a), 0.0, cos(a)) * RING_RADIUS


## Straight distance between consecutive checkpoints.
static func segment_length() -> float:
	return checkpoint_pos(0).distance_to(checkpoint_pos(1))


## Distance covered: passed checkpoints plus the fraction of the current segment already closed.
static func distance_covered(passed_count: int, dist_to_next: float) -> float:
	var seg := segment_length()
	var partial := clampf(1.0 - dist_to_next / seg, 0.0, 1.0) * seg if passed_count < total_checkpoints() else 0.0
	return float(passed_count) * seg + partial


## 0 at no distance, PAR_SCORE at par, 1 at elite or beyond.
static func pace_score(dist: float, par: float = PAR_DISTANCE, elite: float = ELITE_DISTANCE) -> float:
	if dist <= 0.0:
		return 0.0
	if dist < par:
		return FpsDrill.clamp01(PAR_SCORE * dist / maxf(par, 0.001))
	if elite <= par:
		return 1.0
	return FpsDrill.clamp01(PAR_SCORE + (1.0 - PAR_SCORE) * (dist - par) / (elite - par))


# ---- drill ----------------------------------------------------------------------------------------------------------

func _build() -> void:
	for i in CHECKPOINTS_PER_LAP:
		var m := add_box(checkpoint_pos(i) + Vector3(0, 0.03, 0), Vector3(1.6, 0.06, 1.6), Color(0.3, 0.6, 0.9))
		m.collision_layer = 0
	_beacon = add_box(checkpoint_pos(1) + Vector3(0, 2.0, 0), Vector3(0.4, 4.0, 0.4), Color(0.95, 0.8, 0.1))
	_beacon.collision_layer = 0
	# A pillar in the middle so the ring reads as a course.
	add_box(RING_CENTRE + Vector3(0, 2.0, 0), Vector3(4, 4, 4), Color(0.5, 0.35, 0.25))


func _begin() -> void:
	passed = 0
	next_checkpoint = 1
	_move_beacon()


func _run(_delta: float) -> void:
	if player == null:
		return
	if passed >= total_checkpoints():
		finish(_final_score())
		return
	if Vector2(player.global_position.x - checkpoint_pos(next_checkpoint).x, player.global_position.z - checkpoint_pos(next_checkpoint).z).length() <= PASS_RADIUS:
		check_in()


## The player reached the next checkpoint (also callable by tests).
func check_in() -> void:
	if state != State.RUNNING:
		return
	passed += 1
	next_checkpoint = (next_checkpoint + 1) % CHECKPOINTS_PER_LAP
	_move_beacon()
	if passed >= total_checkpoints():
		finish(_final_score())


func _move_beacon() -> void:
	if _beacon != null:
		_beacon.position = checkpoint_pos(next_checkpoint) + Vector3(0, 2.0, 0)


func distance_now() -> float:
	var to_next := 0.0
	if player != null:
		var c := checkpoint_pos(next_checkpoint)
		to_next = Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length()
	else:
		to_next = segment_length()
	return distance_covered(passed, to_next)


func _final_score() -> float:
	return pace_score(distance_now())


func _hud_extra() -> String:
	var stam := ""
	if player != null and player.has_method(&"stamina_fraction"):
		stam = "   Stamina %d%%" % roundi(float(player.call(&"stamina_fraction")) * 100.0)
	return "%d m   checkpoint %d%s" % [roundi(distance_now()), passed, stam]

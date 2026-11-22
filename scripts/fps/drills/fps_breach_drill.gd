class_name FpsBreachDrill
extends FpsDrill
## Door breach (BREACH): stacked at a locked door, time the breach on a charge bar, then clear the room against the clock.
## The charge bar cycles forever (driven by drill time); `breach()` inside the green window is a clean breach. The door opens,
## the player is free to move and a handful of targets stand up inside, some behind cover. Score = timing quality of the
## breach (like the 2D Timing drill) plus how fast and cleanly the room was cleared.

const WALL_Z := -4.0
const DOOR_WIDTH := 1.6
const CYCLE := 1.8              ## seconds for the charge bar to fill
const ZONE := 0.16              ## width of the green window as a fraction of the bar
const BREACH_LIMIT := 14.0      ## no breach by now ends the drill with nothing
const ROOM_TARGETS := 6
const TARGET_LIFE := 2.4
const CLEAR_PAR := 4.0          ## seconds after the breach that still score full speed
const CLEAR_LIMIT := 10.0
const BAR_WIDTH := 2.0
const W_TIMING := 0.4

var targets: Array = []
var breached := false
var breach_time := 0.0
var timing_quality := 0.0
var hits := 0
var headshots := 0
var room_shots := 0
var popped := 0
var clear_secs := 0.0
var slot_points: Array = []
var _centers: Array = []
var _schedule: Array = []
var _next := 0
var _door: StaticBody3D
var _fill: MeshInstance3D
var _window: MeshInstance3D


func _init() -> void:
	super()
	stat = Stats.BREACH
	title = "Door breach"
	instructions = "Press E or fire inside the green window to breach, then clear the room fast."
	lock_player = true
	duration = 40.0
	player_spawn = Vector3(0, 0.1, 0)
	# Accuracy 99 so the clear score is your aim, not the soldier's rating.
	loadout = {Stats.SHORT_ACC: 99, Stats.MEDIUM_ACC: 99, Stats.LONG_ACC: 99}
	for i in ROOM_TARGETS:
		slot_points.append(Vector3((i - (ROOM_TARGETS - 1) / 2.0) * 1.6, 0.0, WALL_Z - 6.0 - float(i % 2) * 2.0))


# ---- pure scoring rules ---------------------------------------------------------------------------------------------

## Timing quality of one breach: 1 dead centre of the window, falling to 0.75 at its edge and to 0 a zone-width outside.
static func timing_value(offset: float, zone: float) -> float:
	var d := absf(offset)
	var half := zone / 2.0
	if d <= half:
		return 1.0 - 0.25 * (d / maxf(half, 0.0001))
	return clampf(0.5 - (d - half) / maxf(zone, 0.0001), 0.0, 0.5) * 0.9


## Clearing the room: share of targets hit, weighted by speed (secs since the breach) and precision (hits per shot).
static func clear_score(hits_made: int, shots_fired: int, targets_n: int, secs: float) -> float:
	if targets_n <= 0:
		return 0.0
	var h := mini(hits_made, targets_n)
	var ratio := float(h) / float(targets_n)
	var precision := float(h) / float(maxi(shots_fired, maxi(h, 1)))
	var speed := FpsDrill.time_score(secs, CLEAR_PAR, CLEAR_LIMIT)
	return FpsDrill.clamp01(ratio * (0.55 + 0.25 * speed + 0.2 * precision))


## The drill score from the breach timing (negative = never breached) and the clear score.
static func combine(timing: float, clear: float) -> float:
	if timing < 0.0:
		return 0.0
	return FpsDrill.clamp01(W_TIMING * timing + (1.0 - W_TIMING) * clear)


# ---- geometry -------------------------------------------------------------------------------------------------------

func _build() -> void:
	var wall_col := Color(0.5, 0.48, 0.45)
	var half_w := 30.0
	var side := half_w - DOOR_WIDTH / 2.0
	add_box(Vector3(-(DOOR_WIDTH / 2.0 + side / 2.0), 1.5, WALL_Z), Vector3(side, 3.0, 0.4), wall_col)
	add_box(Vector3(DOOR_WIDTH / 2.0 + side / 2.0, 1.5, WALL_Z), Vector3(side, 3.0, 0.4), wall_col)
	add_box(Vector3(0, 2.75, WALL_Z), Vector3(DOOR_WIDTH, 0.5, 0.4), wall_col)
	_door = add_box(Vector3(0, 1.25, WALL_Z), Vector3(DOOR_WIDTH, 2.5, 0.2), Color(0.45, 0.28, 0.12))
	# Room: back wall and side walls.
	add_box(Vector3(0, 1.5, WALL_Z - 14.0), Vector3(14, 3.0, 0.4), wall_col)
	add_box(Vector3(-7.0, 1.5, WALL_Z - 7.0), Vector3(0.4, 3.0, 14), wall_col)
	add_box(Vector3(7.0, 1.5, WALL_Z - 7.0), Vector3(0.4, 3.0, 14), wall_col)
	# Cover in front of some of the targets (guarded).
	add_box(Vector3(-1.6, 0.4, WALL_Z - 5.0), Vector3(1.2, 0.8, 0.3), Color(0.3, 0.3, 0.35))
	add_box(Vector3(2.4, 0.4, WALL_Z - 6.0), Vector3(1.2, 0.8, 0.3), Color(0.3, 0.3, 0.35))
	# Charge bar on the wall: dark backing, green window, white fill.
	_bar_part(Vector3(BAR_WIDTH, 0.22, 0.02), Vector3(0, 2.0, WALL_Z + 0.21), Color(0.1, 0.12, 0.16))
	_window = _bar_part(Vector3(ZONE * BAR_WIDTH, 0.26, 0.02), Vector3(0, 2.0, WALL_Z + 0.22), Color(0.13, 0.77, 0.37))
	_fill = _bar_part(Vector3(BAR_WIDTH, 0.12, 0.02), Vector3(-BAR_WIDTH / 2.0, 2.0, WALL_Z + 0.23), Color.WHITE)
	_fill.scale.x = 0.0
	for p in slot_points:
		var t := FpsDrillTarget.new()
		t.position = p
		t.hit.connect(_on_target_hit.bind(t))
		add_child(t)
		targets.append(t)


func _bar_part(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return mi


# ---- charge bar -----------------------------------------------------------------------------------------------------

func cycle_index() -> int:
	return int(floorf(elapsed / CYCLE))


## 0..1 position of the charge bar now.
func phase() -> float:
	return fposmod(elapsed, CYCLE) / CYCLE


## Centre (0..1) of the green window in the current cycle. Seeded, so a seed gives the same sequence of windows.
func window_center() -> float:
	var c := cycle_index()
	while _centers.size() <= c:
		_centers.append(rng.randf_range(0.35, 0.85))
	return float(_centers[c])


func _begin() -> void:
	_centers.clear()
	_schedule.clear()
	_next = 0
	breached = false
	breach_time = 0.0
	timing_quality = 0.0
	hits = 0
	headshots = 0
	room_shots = 0
	popped = 0
	clear_secs = 0.0
	for t in targets:
		t.set_up(false)
	if _door != null:
		_door.collision_layer = 1
		_door.visible = true
	window_center()


## The breach. Returns the timing quality (0..1), or -1 when it is not allowed (not running, or already breached).
func breach() -> float:
	if state != State.RUNNING or breached:
		return -1.0
	var v := FpsBreachDrill.timing_value(phase() - window_center(), ZONE)
	breached = true
	breach_time = elapsed
	timing_quality = v
	if _door != null:
		_door.collision_layer = 0
		_door.visible = false
	if player != null and "lock_movement" in player:
		player.set("lock_movement", false)
	# Order the room: every target stands up, staggered, in a seeded order.
	var order: Array = range(targets.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var at := breach_time + 0.3
	for k in order:
		_schedule.append({"slot": k, "at": at})
		at += rng.randf_range(0.25, 0.5)
	_next = 0
	_emit_hud()
	return v


func _unhandled_input(event: InputEvent) -> void:
	if state != State.RUNNING or breached:
		return
	var fire := false
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		fire = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		fire = true
	if fire:
		breach()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func _run(_delta: float) -> void:
	window_center()
	_update_bar()
	if not breached:
		if elapsed >= BREACH_LIMIT:
			finish(_final_score())
		return
	while _next < _schedule.size() and float(_schedule[_next]["at"]) <= elapsed:
		var t: FpsDrillTarget = targets[int(_schedule[_next]["slot"])]
		t.pop(float(_schedule[_next]["at"]), TARGET_LIFE)
		popped += 1
		_next += 1
	var any_up := false
	for t in targets:
		if t.up and t.expires <= elapsed:
			t.set_up(false)
		if t.up:
			any_up = true
	if _next >= _schedule.size() and not any_up:
		clear_secs = elapsed - breach_time
		finish(_final_score())


func _update_bar() -> void:
	if _fill == null:
		return
	if breached:
		_fill.scale.x = 1.0
		_fill.position.x = 0.0
		return
	var p := phase()
	_fill.scale.x = maxf(p, 0.0001)
	_fill.position.x = -BAR_WIDTH / 2.0 + p * BAR_WIDTH / 2.0
	_window.position.x = (window_center() - 0.5) * BAR_WIDTH


func _on_target_hit(head: bool, _t: FpsDrillTarget = null) -> void:
	if state != State.RUNNING or not breached:
		return
	hits += 1
	if head:
		headshots += 1


func _shot(_hit: Dictionary) -> void:
	if breached:
		room_shots += 1


func _final_score() -> float:
	if not breached:
		return 0.0
	var secs := clear_secs if clear_secs > 0.0 else elapsed - breach_time
	return FpsBreachDrill.combine(timing_quality, FpsBreachDrill.clear_score(hits, room_shots, targets.size(), secs))


func _hud_extra() -> String:
	if not breached:
		return "Breach: press E / fire in the green  (%d%%)" % roundi(phase() * 100.0)
	return "Breach %d%%   Down %d / %d" % [roundi(timing_quality * 100.0), hits, targets.size()]


func _end() -> void:
	for t in targets:
		t.set_up(false)

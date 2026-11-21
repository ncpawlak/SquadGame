class_name FpsDrill
extends Node3D
## Base of every 3D combine drill. Same contract as the 2D CombineTask: a short countdown, a run, then `finished(score)`
## exactly once with a score clamped to 0..1. Time is advanced by `advance(delta)` (called from _process), so tests can
## drive a drill with no scene tree. All scoring rules are static functions so they can be tested with plain numbers.
##
## Contract with the core session: `player` is an FpsPlayer (CharacterBody3D) with `shot_fired(hit: Dictionary)`; targets
## are in group `damageable` and implement take_damage(amount, hit).

signal finished(score: float)
## Fired whenever the HUD text changes (countdown, time left, progress). The hall shows it in a label.
signal hud_changed(text: String)

enum State { IDLE, COUNTDOWN, RUNNING, DONE }

const COUNTDOWN_SECS := 3.0
const GROUP_DRILL_TARGET := &"fps_drill_target"

## Which combine stat this drill scores (Stats id) and its display name; subclasses set both in _init.
var stat: StringName = &""
var title := "Drill"
var instructions := ""
## Length of the run in seconds (after the countdown). The drill finishes by itself when it runs out.
var duration := 30.0
var rng := RandomNumberGenerator.new()
var state: State = State.IDLE
var elapsed := 0.0
var countdown_left := COUNTDOWN_SECS
var score := 0.0
var player: Node3D
var player_spawn := Vector3(0, 0.1, 0)
var shots := 0
var _built := false


func _init() -> void:
	rng.seed = 1


## The stats this run scores, as {stat: 0..1}. Most drills score one; the obstacle course scores two.
func stat_scores() -> Dictionary:
	return {stat: score}


## Start the drill with `p` (may be null in tests). Builds the arena once, places the player and begins the countdown.
func start(p: Node3D = null, seed_value: int = -1) -> void:
	if state != State.IDLE:
		return
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	if not _built:
		_built = true
		_build_arena()
		_build()
	player = p
	if player != null:
		if player.get_parent() == null:
			add_child(player)
		player.position = player_spawn
		if player.has_signal(&"shot_fired") and not player.is_connected(&"shot_fired", _on_shot_fired):
			player.connect(&"shot_fired", _on_shot_fired)
	state = State.COUNTDOWN
	countdown_left = COUNTDOWN_SECS
	elapsed = 0.0
	shots = 0
	_emit_hud()


func _process(delta: float) -> void:
	advance(delta)


## Move time forward. Safe to call at any rate and after the drill is done (it then does nothing).
func advance(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			countdown_left -= delta
			if countdown_left <= 0.0:
				var spill := -countdown_left
				state = State.RUNNING
				_begin()
				_emit_hud()
				if spill > 0.0:
					advance(spill)
			else:
				_emit_hud()
		State.RUNNING:
			var step := minf(delta, maxf(duration - elapsed, 0.0))
			elapsed += step
			_run(step)
			if state == State.RUNNING:
				if elapsed >= duration:
					finish(_final_score())
				else:
					_emit_hud()


## End the drill with `value`. Only the first call counts; the score is clamped to 0..1.
func finish(value: float) -> void:
	if state == State.DONE:
		return
	state = State.DONE
	score = clamp01(value)
	_end()
	finished.emit(score)


## Give up: finishes with whatever the drill has scored so far.
func abort() -> void:
	if state == State.DONE:
		return
	finish(_final_score() if state == State.RUNNING else 0.0)


func time_left() -> float:
	return maxf(duration - elapsed, 0.0)


func hud_text() -> String:
	match state:
		State.COUNTDOWN:
			return "%s\n%s\nGet ready: %d" % [title, instructions, int(ceil(countdown_left))]
		State.RUNNING:
			return "%s  %.1fs\n%s" % [title, time_left(), _hud_extra()]
		State.DONE:
			return "%s: %d%%" % [title, roundi(score * 100.0)]
	return title


func _emit_hud() -> void:
	hud_changed.emit(hud_text())


func _on_shot_fired(hit: Dictionary) -> void:
	if state == State.RUNNING:
		shots += 1
		_shot(hit)


# ---- hooks for subclasses -------------------------------------------------------------------------------------------

## Build drill-specific geometry (called once, on first start).
func _build() -> void:
	pass

## The countdown ended: the run begins.
func _begin() -> void:
	pass

## Per-step logic while running; delta is already trimmed so elapsed never passes duration.
func _run(_delta: float) -> void:
	pass

## A shot was fired while running.
func _shot(_hit: Dictionary) -> void:
	pass

## Score to use when time runs out (or on abort).
func _final_score() -> float:
	return 0.0

func _hud_extra() -> String:
	return ""

func _end() -> void:
	pass


# ---- arena helpers --------------------------------------------------------------------------------------------------

func _build_arena() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.75)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	add_box(Vector3(0, -0.5, -30), Vector3(60, 1, 120), Color(0.35, 0.4, 0.35))


## A solid coloured box (visual + collision). Returns the StaticBody3D.
func add_box(center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


## The direction the player is aiming (camera forward), or -Z when there is no camera.
func aim_direction() -> Vector3:
	if player != null and player.is_inside_tree():
		var cam := player.get_viewport().get_camera_3d()
		if cam != null:
			return -cam.global_transform.basis.z
		return -player.global_transform.basis.z
	return Vector3.FORWARD


func aim_origin() -> Vector3:
	if player != null and player.is_inside_tree():
		var cam := player.get_viewport().get_camera_3d()
		if cam != null:
			return cam.global_position
		return player.global_position + Vector3(0, 1.6, 0)
	return Vector3(0, 1.6, 0)


# ---- pure scoring helpers -------------------------------------------------------------------------------------------

static func clamp01(v: float) -> float:
	if is_nan(v):
		return 0.0
	return clampf(v, 0.0, 1.0)


## 1 at or under `par` seconds, 0 at or over `limit`, a straight line between.
static func time_score(secs: float, par: float, limit: float) -> float:
	if limit <= par:
		return 1.0 if secs <= par else 0.0
	return clamp01(1.0 - (secs - par) / (limit - par))


## Popup range: hit share of the targets shown, trimmed by shot precision, with a small headshot bonus.
static func range_score(hits: int, headshots: int, shots_fired: int, targets: int) -> float:
	if targets <= 0:
		return 0.0
	var h := mini(hits, targets)
	var ratio := float(h) / float(targets)
	var precision := float(h) / float(maxi(shots_fired, maxi(h, 1)))
	var heads := float(mini(headshots, h)) / float(targets)
	return clamp01(ratio * (0.75 + 0.25 * precision) + 0.1 * heads)


## Burst grouping: shots that landed close together score high however far the group is off centre.
## `points` are hit positions on the target plane; `fired` is the burst size; `ref_spread` is the spread (metres, mean
## distance from the group's centre) that scores 0.
static func grouping_score(points: Array, fired: int, ref_spread: float) -> float:
	if fired <= 0 or points.is_empty():
		return 0.0
	var centre := Vector3.ZERO
	for p in points:
		centre += p
	centre /= float(points.size())
	var spread := 0.0
	for p in points:
		spread += (p as Vector3).distance_to(centre)
	spread /= float(points.size())
	var tight := clamp01(1.0 - spread / maxf(ref_spread, 0.001))
	var landed := clampf(float(points.size()) / float(fired), 0.0, 1.0)
	return clamp01(tight * landed)


## Scope sway: half the score is how long the aim stayed inside the ring, half is the closing shot
## (`shot_dist` < 0 means no shot was taken).
static func sway_score(on_target: float, held: float, shot_dist: float, ring: float) -> float:
	var hold := clamp01(on_target / maxf(held, 0.001))
	var shot := 0.0
	if shot_dist >= 0.0:
		shot = clamp01(1.0 - shot_dist / maxf(ring, 0.001))
	return clamp01(0.5 * hold + 0.5 * shot)


## Hold the point: presence in the zone weighs most, shooting the intruders the rest.
static func hold_score(in_zone: float, total: float, kills: int, intruders: int) -> float:
	var presence := clamp01(in_zone / maxf(total, 0.001))
	var shooting := 1.0 if intruders <= 0 else clamp01(float(kills) / float(intruders))
	return clamp01(0.65 * presence + 0.35 * shooting)


## Deterministic popup schedule: `count` entries {slot, at, life}, never the same slot twice in a row.
static func make_schedule(seed_value: int, count: int, slots: int, first_at: float, gap_min: float, gap_max: float, life: float) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var out: Array = []
	var t := first_at
	var last := -1
	for i in maxi(count, 0):
		var slot := 0
		if slots > 1:
			slot = r.randi_range(0, slots - 1)
			if slot == last:
				slot = (slot + 1 + r.randi_range(0, slots - 2)) % slots
		out.append({"slot": slot, "at": t, "life": life})
		last = slot
		t += r.randf_range(gap_min, gap_max)
	return out

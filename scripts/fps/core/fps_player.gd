class_name FpsPlayer
extends CharacterBody3D
## First-person player: mouse look, WASD, sprint, crouch, jump, stamina, health and a weapon.
## Builds its collision, head, camera and weapon in code, so a bare FpsPlayer node in a scene works.
## Feel comes from a Soldier's ratings through the static derive_movement() (see setup()).
##
## Damage contract: in group "damageable"; take_damage(amount, hit) and is_headshot(world_pos).

signal shot_fired(hit: Dictionary)
signal damaged(amount: float, source)
signal died(source)

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const EYE_OFFSET := 0.15  ## eyes this far below the top of the capsule
const SPRINT_MULT := 1.6
const CROUCH_MULT := 0.55
const JUMP_VELOCITY := 4.6

@export var mouse_sensitivity: float = 0.0022
@export var max_health: float = 100.0
@export var weapon_id: StringName = &"rifle"
@export var capture_mouse: bool = true
@export var infinite_reserve: bool = false

var soldier: Soldier = null
var weapon: FpsWeapon
var health: float = 100.0
var stamina: float = 100.0
var move: Dictionary = {}  ## result of derive_movement()
var dead: bool = false
var controls_enabled: bool = true
var sprinting: bool = false
var crouching: bool = false
var recovering_stamina: bool = false  ## true after hitting 0 until stamina recovers a bit

var head: Node3D
var camera: Camera3D
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _look_pitch: float = 0.0
var _stamina_delay: float = 0.0
var _gravity: float = 9.8
var _stats: Dictionary = {}


func _init() -> void:
	add_to_group(&"damageable")
	add_to_group(&"fps_player")
	move = derive_movement({})
	stamina = move["stamina_max"]


func _ready() -> void:
	ensure_input_actions()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	health = max_health
	_build()
	weapon.setup(camera, _stats, self)
	weapon.infinite_reserve = infinite_reserve
	weapon.equip(weapon_id)
	weapon.fired.connect(func(r: Dictionary) -> void: shot_fired.emit(r))
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build() -> void:
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.35
	_capsule.height = STAND_HEIGHT
	_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "CollisionShape3D"
		add_child(_shape)
	_shape.shape = _capsule
	_shape.position.y = STAND_HEIGHT * 0.5
	head = get_node_or_null("Head") as Node3D
	if head == null:
		head = Node3D.new()
		head.name = "Head"
		add_child(head)
	head.position.y = STAND_HEIGHT - EYE_OFFSET
	camera = head.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.fov = 80.0
		camera.current = true
		head.add_child(camera)
	weapon = get_node_or_null("Weapon") as FpsWeapon
	if weapon == null:
		weapon = FpsWeapon.new()
		weapon.name = "Weapon"
		add_child(weapon)


# ---------------------------------------------------------------- stat mapping

## Ratings -> feel. Pure function so tests (and the HUD) need no scene.
## SPEED -> walk speed, AGILITY -> acceleration, ENDURANCE -> stamina size and recovery.
static func derive_movement(stats: Dictionary) -> Dictionary:
	var spd := clampf(float(stats.get(Stats.SPEED, 50)) / 99.0, 0.0, 1.0)
	var agi := clampf(float(stats.get(Stats.AGILITY, 50)) / 99.0, 0.0, 1.0)
	var end := clampf(float(stats.get(Stats.ENDURANCE, 50)) / 99.0, 0.0, 1.0)
	var walk := lerpf(3.4, 5.4, spd)
	return {
		"walk_speed": walk,
		"sprint_speed": walk * SPRINT_MULT,
		"crouch_speed": walk * CROUCH_MULT,
		"accel": lerpf(8.0, 22.0, agi),
		"air_accel": lerpf(1.5, 4.0, agi),
		"stamina_max": lerpf(60.0, 140.0, end),
		"stamina_regen": lerpf(8.0, 24.0, end),
		"stamina_drain": 18.0,
		"stamina_delay": lerpf(1.6, 0.6, end),
	}


## One stamina step. Returns the new {stamina, sprinting_allowed, delay}.
static func step_stamina(cur: float, mv: Dictionary, wants_sprint: bool, locked: bool, delay: float,
		delta: float) -> Dictionary:
	var mx: float = mv["stamina_max"]
	var s := cur
	var d := delay
	var lock := locked
	if wants_sprint and not lock:
		s = maxf(0.0, s - float(mv["stamina_drain"]) * delta)
		d = float(mv["stamina_delay"])
		if s <= 0.0:
			lock = true
	else:
		d = maxf(0.0, d - delta)
		if d <= 0.0:
			s = minf(mx, s + float(mv["stamina_regen"]) * delta)
	if lock and s >= mx * 0.25:
		lock = false
	return {"stamina": s, "locked": lock, "delay": d}


func setup(p_soldier: Soldier) -> void:
	soldier = p_soldier
	_stats = soldier.stats if soldier else {}
	move = derive_movement(_stats)
	stamina = move["stamina_max"]
	if weapon:
		weapon.apply_stats(_stats)


func stamina_fraction() -> float:
	return stamina / maxf(float(move["stamina_max"]), 0.001)


# ---------------------------------------------------------------- input

static func ensure_input_actions() -> void:
	var keys := {
		&"fps_forward": KEY_W, &"fps_back": KEY_S, &"fps_left": KEY_A, &"fps_right": KEY_D,
		&"fps_sprint": KEY_SHIFT, &"fps_crouch": KEY_CTRL, &"fps_jump": KEY_SPACE,
		&"fps_reload": KEY_R, &"fps_fire_mode": KEY_V,
		&"fps_weapon_1": KEY_1, &"fps_weapon_2": KEY_2, &"fps_weapon_3": KEY_3, &"fps_weapon_4": KEY_4,
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)
	if not InputMap.has_action(&"fps_fire"):
		InputMap.add_action(&"fps_fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(&"fps_fire", mb)


func _unhandled_input(event: InputEvent) -> void:
	if dead or not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton and event.pressed and capture_mouse \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Rotate the view by a mouse delta (pixels).
func look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	_look_pitch = clampf(_look_pitch - relative.y * mouse_sensitivity, deg_to_rad(-89.0), deg_to_rad(89.0))


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if dead:
		return
	var input_dir := Vector2.ZERO
	var want_sprint := false
	var want_crouch := false
	var want_jump := false
	if controls_enabled:
		input_dir = Input.get_vector("fps_left", "fps_right", "fps_forward", "fps_back")
		want_sprint = Input.is_action_pressed("fps_sprint")
		want_crouch = Input.is_action_pressed("fps_crouch")
		want_jump = Input.is_action_just_pressed("fps_jump")
		weapon.set_trigger(Input.is_action_pressed("fps_fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
		if Input.is_action_just_pressed("fps_reload"):
			weapon.reload()
		if Input.is_action_just_pressed("fps_fire_mode"):
			weapon.cycle_fire_mode()
		for i in 4:
			if Input.is_action_just_pressed("fps_weapon_%d" % (i + 1)):
				var ids := FpsWeaponDefs.ids()
				if i < ids.size():
					weapon.equip(ids[i])
	simulate(delta, input_dir, want_sprint, want_crouch, want_jump)


## Movement step, separated from input so tests and scripted drills can drive the player.
func simulate(delta: float, input_dir: Vector2, want_sprint: bool, want_crouch: bool, want_jump: bool) -> void:
	_set_crouch(want_crouch, delta)
	var moving := input_dir.length() > 0.1
	var can_sprint := want_sprint and moving and not crouching and is_on_floor() and input_dir.y <= 0.1
	var st := step_stamina(stamina, move, can_sprint and not recovering_stamina, recovering_stamina,
			_stamina_delay, delta)
	stamina = st["stamina"]
	recovering_stamina = st["locked"]
	_stamina_delay = st["delay"]
	sprinting = can_sprint and not recovering_stamina
	var speed: float = move["walk_speed"]
	if crouching:
		speed = move["crouch_speed"]
	elif sprinting:
		speed = move["sprint_speed"]
	var wish := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized() * speed \
			if moving else Vector3.ZERO
	var accel: float = move["accel"] if is_on_floor() else move["air_accel"]
	velocity.x = move_toward(velocity.x, wish.x, accel * delta * speed * 0.5 + accel * delta)
	velocity.z = move_toward(velocity.z, wish.z, accel * delta * speed * 0.5 + accel * delta)
	if is_on_floor():
		if want_jump and not crouching:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	# weapon context + view
	var horiz := Vector2(velocity.x, velocity.z).length()
	weapon.move_fraction = clampf(horiz / float(move["sprint_speed"]), 0.0, 1.0)
	weapon.crouched = crouching
	weapon.airborne = not is_on_floor()
	head.rotation.x = _look_pitch
	camera.rotation = Vector3(deg_to_rad(weapon.recoil.x + weapon.sway_offset.x), \
			deg_to_rad(weapon.recoil.y + weapon.sway_offset.y), 0.0)


func _set_crouch(want: bool, delta: float) -> void:
	if want:
		crouching = true
	elif crouching and not _blocked_above():
		crouching = false
	var target := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	_capsule.height = move_toward(_capsule.height, target, 6.0 * delta)
	_shape.position.y = _capsule.height * 0.5
	head.position.y = _capsule.height - EYE_OFFSET


func _blocked_above() -> bool:
	if not is_inside_tree():
		return false
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, CROUCH_HEIGHT - 0.1, 0),
			global_position + Vector3(0, STAND_HEIGHT + 0.05, 0), collision_mask, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ---------------------------------------------------------------- damage

func take_damage(amount: float, hit: Dictionary = {}) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var applied := minf(amount, health)
	health -= applied
	var source = hit.get("source", null)
	damaged.emit(applied, source)
	if health <= 0.0:
		dead = true
		weapon.set_trigger(false)
		died.emit(source)
	return applied


func is_headshot(world_pos: Vector3) -> bool:
	return world_pos.y >= global_position.y + _capsule.height - 0.3


func heal(amount: float) -> void:
	if not dead:
		health = minf(max_health, health + amount)


func respawn(at: Vector3 = Vector3.INF) -> void:
	dead = false
	health = max_health
	stamina = move["stamina_max"]
	recovering_stamina = false
	velocity = Vector3.ZERO
	if at != Vector3.INF:
		global_position = at
	weapon.refill()

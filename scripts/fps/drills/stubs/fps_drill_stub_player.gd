class_name FpsDrillStubPlayer
extends CharacterBody3D
## STUB, used only when the core session's FpsPlayer is not in the project. Just enough of the contract
## (setup, shot_fired, a camera, walk + look + hitscan) to run the drills by hand. Delete once core is merged;
## the hall prefers the real FpsPlayer automatically.

signal shot_fired(hit: Dictionary)
signal damaged
signal died

const WALK := 5.0
const SPRINT := 8.5
const SENS := 0.0025

var weapon = null
var soldier = null
var _cam: Camera3D
var _pitch := 0.0
var _cooldown := 0.0


func _init() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_cam = Camera3D.new()
	_cam.position.y = 1.6
	add_child(_cam)


func _ready() -> void:
	_cam.make_current()


func setup(s) -> void:
	soldier = s


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENS)
		_pitch = clampf(_pitch - event.relative.y * SENS, -1.4, 1.4)
		_cam.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir.z -= 1
	if Input.is_key_pressed(KEY_S): dir.z += 1
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1
	var speed := SPRINT if Input.is_key_pressed(KEY_SHIFT) else WALK
	var v := (global_transform.basis * dir).normalized() * speed
	velocity = Vector3(v.x, velocity.y - 20.0 * delta if not is_on_floor() else 0.0, v.z)
	move_and_slide()
	_cooldown -= delta
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _cooldown <= 0.0:
		_cooldown = 0.09
		_fire()


func _fire() -> void:
	var from := _cam.global_position
	var to := from - _cam.global_transform.basis.z * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var info := {"hit": false, "collider": null, "position": to, "distance": 200.0, "headshot": false, "damage": 0.0}
	if not r.is_empty():
		info["hit"] = true
		info["collider"] = r["collider"]
		info["position"] = r["position"]
		info["distance"] = from.distance_to(r["position"])
		info["damage"] = 25.0
		var c = r["collider"]
		if c != null and c.is_in_group(&"damageable") and c.has_method(&"take_damage"):
			c.take_damage(25.0, info)
	shot_fired.emit(info)

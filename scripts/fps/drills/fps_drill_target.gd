class_name FpsDrillTarget
extends StaticBody3D
## A pop-up target for drills. Stands up for a while, falls when shot. Body and head are separate colliders so the
## core weapon can report `headshot`; both forward take_damage to this target. Group `damageable` per the core contract.

signal hit(headshot: bool)
signal knocked_down

var up := false
var expires := 0.0
## Drill time the target last stood up (for reaction time).
var popped_at := 0.0
## Where the last hit landed (world), and the bullseye (target-local) it is measured from.
var last_hit_pos := Vector3.ZERO
const BULLSEYE := Vector3(0.0, 0.6, 0.0)
const BULLSEYE_RADIUS := 0.3
## A sticky target stays up when hit (the grouping ring): the drill decides when a hit counts.
var sticky := false
var _mat: StandardMaterial3D
var _head: StaticBody3D


func _init() -> void:
	add_to_group(&"damageable")
	add_to_group(FpsDrill.GROUP_DRILL_TARGET)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.25, 0.2)
	_mat = mat
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 1.0, 0.1)
	bm.material = mat
	mi.mesh = bm
	mi.position.y = 0.5
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 1.0, 0.1)
	cs.shape = shape
	cs.position.y = 0.5
	add_child(cs)
	# Bullseye rings on the front face (the player stands on the +Z side looking toward -Z).
	for ring in [[0.3, Color.WHITE], [0.2, Color(0.9, 0.1, 0.1)], [0.1, Color.WHITE]]:
		var rm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = ring[0]
		cm.bottom_radius = ring[0]
		cm.height = 0.01
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = ring[1]
		cm.material = rmat
		rm.mesh = cm
		rm.rotation.x = PI * 0.5
		rm.position = BULLSEYE + Vector3(0, 0, 0.056 + (0.3 - float(ring[0])) * 0.01)
		add_child(rm)
	_head = _HeadPart.new()
	_head.owner_target = self
	var hs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.15
	hs.shape = sph
	_head.add_child(hs)
	var hm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	sm.material = mat
	hm.mesh = sm
	_head.add_child(hm)
	_head.position.y = 1.15
	add_child(_head)
	set_up(false)


func set_up(value: bool) -> void:
	up = value
	visible = value
	var layer := 1 if value else 0
	collision_layer = layer
	_head.collision_layer = layer


## Stand up until `now + life` (drill time).
func pop(now: float, life: float) -> void:
	popped_at = now
	expires = now + life
	set_up(true)


## Tint the body (the grouping ring greys a target that is not ready for its next shot).
func set_tint(color: Color) -> void:
	if _mat != null:
		_mat.albedo_color = color


## 1 on the bullseye, 0 at BULLSEYE_RADIUS or further: how close a world-space hit is to the centre of the target.
func closeness(world_pos: Vector3) -> float:
	var local := global_transform.affine_inverse() * world_pos if is_inside_tree() else world_pos - position
	var d := Vector2(local.x - BULLSEYE.x, local.y - BULLSEYE.y).length()
	return clampf(1.0 - d / BULLSEYE_RADIUS, 0.0, 1.0)


## Where a world-space hit landed on the target's face, relative to the bullseye (metres, x right, y up).
func face_offset(world_pos: Vector3) -> Vector2:
	var local := global_transform.affine_inverse() * world_pos if is_inside_tree() else world_pos - position
	return Vector2(local.x - BULLSEYE.x, local.y - BULLSEYE.y)


func take_damage(_amount: float, info: Dictionary = {}) -> void:
	if not up:
		return
	var head := bool(info.get("headshot", false))
	var base := global_position if is_inside_tree() else position
	last_hit_pos = info.get("position", base + BULLSEYE)
	if not sticky:
		set_up(false)
	hit.emit(head)
	if not sticky:
		knocked_down.emit()


class _HeadPart extends StaticBody3D:
	var owner_target: FpsDrillTarget

	func _init() -> void:
		add_to_group(&"damageable")

	func take_damage(amount: float, info: Dictionary = {}) -> void:
		var i := info.duplicate()
		i["headshot"] = true
		if owner_target != null:
			owner_target.take_damage(amount, i)

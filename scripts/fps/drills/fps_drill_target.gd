class_name FpsDrillTarget
extends StaticBody3D
## A pop-up target for drills. Stands up for a while, falls when shot. Body and head are separate colliders so the
## core weapon can report `headshot`; both forward take_damage to this target. Group `damageable` per the core contract.

signal hit(headshot: bool)
signal knocked_down

var up := false
var expires := 0.0
var _head: StaticBody3D


func _init() -> void:
	add_to_group(&"damageable")
	add_to_group(FpsDrill.GROUP_DRILL_TARGET)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.25, 0.2)
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
	expires = now + life
	set_up(true)


func take_damage(_amount: float, info: Dictionary = {}) -> void:
	if not up:
		return
	var head := bool(info.get("headshot", false))
	set_up(false)
	hit.emit(head)
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

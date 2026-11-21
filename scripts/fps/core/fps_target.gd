class_name FpsTarget
extends StaticBody3D
## A static shooting target. Pop it up and down with pop_up()/knock_down(). Builds its own body
## and head collision if it has no children.
##
## Damage contract: group "damageable", take_damage(amount, hit). hit["headshot"] marks a head hit.
## Optional contract: is_headshot(world_pos) -> bool, asked by FpsWeapon to classify a hit.

signal hit(headshot: bool)
signal knocked_down

@export var max_health: float = 100.0
@export var head_height: float = 1.45  ## height over the target's feet at/above which a hit is a headshot
@export var start_up: bool = true
## Seconds after a knock-down before it pops back up on its own; 0 = stay down.
@export var auto_reset_time: float = 0.0

var health: float = 100.0
var up: bool = true
var hits_taken: int = 0
var headshots_taken: int = 0
var _pivot: Node3D
var _base_layer: int = 1


func _init() -> void:
	add_to_group(&"damageable")
	add_to_group(&"fps_target")


func _ready() -> void:
	health = max_health
	_base_layer = collision_layer if collision_layer != 0 else 1
	if get_child_count() == 0:
		_build()
	_pivot = get_node_or_null("Pivot") as Node3D
	if not start_up:
		knock_down(false)


func _build() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 1.1, 0.15)
	body.mesh = bm
	body.position = Vector3(0, 0.7, 0)
	body.material_override = _mat(Color(0.85, 0.25, 0.2))
	_pivot.add_child(body)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	head.mesh = sm
	head.position = Vector3(0, 1.62, 0)
	head.material_override = _mat(Color(0.95, 0.8, 0.25))
	_pivot.add_child(head)
	var bs := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(0.6, 1.1, 0.15)
	bs.shape = bb
	bs.position = Vector3(0, 0.7, 0)
	add_child(bs)
	var hs := CollisionShape3D.new()
	var hsh := SphereShape3D.new()
	hsh.radius = 0.18
	hs.shape = hsh
	hs.position = Vector3(0, 1.62, 0)
	add_child(hs)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


## Headshot rule: a world-space point at or above head_height over the target's feet.
func is_headshot(world_pos: Vector3) -> bool:
	var feet_y := global_position.y if is_inside_tree() else position.y
	return world_pos.y - feet_y >= head_height


func take_damage(amount: float, hit_info: Dictionary = {}) -> float:
	if not up or amount <= 0.0:
		return 0.0
	var headshot := bool(hit_info.get("headshot", false))
	var applied := minf(amount, health)
	health -= applied
	hits_taken += 1
	if headshot:
		headshots_taken += 1
	hit.emit(headshot)
	if health <= 0.0:
		knock_down()
	return applied


func knock_down(animate: bool = true) -> void:
	if not up:
		return
	up = false
	collision_layer = 0
	if animate and is_inside_tree() and _pivot:
		create_tween().tween_property(_pivot, "rotation:x", -PI * 0.5, 0.18)
	elif _pivot:
		_pivot.rotation.x = -PI * 0.5
	knocked_down.emit()
	if auto_reset_time > 0.0 and is_inside_tree():
		get_tree().create_timer(auto_reset_time).timeout.connect(pop_up)


func pop_up() -> void:
	if up:
		return
	up = true
	health = max_health
	collision_layer = _base_layer
	if _pivot:
		if is_inside_tree():
			create_tween().tween_property(_pivot, "rotation:x", 0.0, 0.15)
		else:
			_pivot.rotation.x = 0.0


func reset_stats() -> void:
	hits_taken = 0
	headshots_taken = 0

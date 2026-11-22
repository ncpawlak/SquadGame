class_name StubFpsWeapon
extends Node3D
## STAND-IN for the core session's FpsWeapon (same try_fire contract). Delete or ignore after merge:
## FpsBot prefers res://scripts/fps/core/fps_weapon.gd when it exists.

var damage := 20.0
var range_m := 80.0
var fire_interval := 0.25
var spread_deg := 1.0
var _cooldown := 0.0
var owner_body: CollisionObject3D = null


func setup(soldier) -> void:
	pass


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func try_fire() -> Dictionary:
	var out := {"hit": false, "collider": null, "position": Vector3.ZERO, "distance": 0.0, "headshot": false, "damage": 0.0}
	if _cooldown > 0.0 or not is_inside_tree():
		return out
	_cooldown = fire_interval
	var from := global_position
	var dir := -global_transform.basis.z
	dir = dir.rotated(global_transform.basis.x, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	dir = dir.rotated(global_transform.basis.y, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * range_m)
	if owner_body:
		q.exclude = [owner_body.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return out
	out["hit"] = true
	out["collider"] = r["collider"]
	out["position"] = r["position"]
	out["distance"] = from.distance_to(r["position"])
	out["damage"] = damage
	return out

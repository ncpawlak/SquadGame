class_name FpsWeapon
extends Node
## Hitscan weapon. Add as a child of the shooter, call setup(camera, stats, shooter) and drive it
## with set_trigger()/try_fire()/reload() plus tick(delta) (done by _process when in the tree).
##
## Damage contract: the hit node (or an ancestor) in group "damageable" gets
## take_damage(amount, hit_dict). hit_dict: {hit, collider, target, position, normal, distance,
## headshot, damage, source, fired}.
## Headshot: collider meta "headshot"==true, or target/collider is_headshot(world_pos) -> true.
##
## Rules live in static functions (accuracy_factor, spread_for, ...) so tests need no scene.

signal fired(result: Dictionary)
signal reload_started(duration: float)
signal reloaded
signal ammo_changed(ammo: int, reserve: int)
signal empty
signal weapon_changed(id: StringName)

var weapon_id: StringName = &"rifle"
var def: Dictionary = {}
var stats: Dictionary = {}
var shooter: Node = null
var camera: Camera3D = null
## Optional Callable() -> Transform3D giving the aim origin/basis (bots use this; default is the camera).
var aim_source: Callable = Callable()
var exclude: Array[RID] = []
var collision_mask: int = 0xFFFFFFFF

var ammo: int = 0
var reserve: int = 0
var infinite_reserve: bool = false
var auto_reload: bool = true
var fire_mode: StringName = &"auto"

## Context set by the owner each frame; they widen spread.
var move_fraction: float = 0.0  ## 0 standing still .. 1 full sprint speed
var crouched: bool = false
var airborne: bool = false

var bloom: float = 0.0  ## extra spread degrees from sustained fire
var recoil: Vector2 = Vector2.ZERO  ## (pitch up, yaw) degrees the camera is kicked by
var sway_offset: Vector2 = Vector2.ZERO  ## idle sway degrees (pitch, yaw)

var reloading: bool = false
var reload_left: float = 0.0
var trigger_held: bool = false
var _cooldown: float = 0.0
var _burst_left: int = 0
var _trigger_released: bool = true
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	equip(&"rifle")


func seed_rng(s: int) -> void:
	_rng.seed = s


# ---------------------------------------------------------------- static rules

## Accuracy rating (0-99) -> spread multiplier. 99 is about 0.35x, 0 about 1.8x, 50 about 1.07x.
static func accuracy_factor(rating: float) -> float:
	return lerpf(1.8, 0.35, clampf(rating / 99.0, 0.0, 1.0))


static func band_for(distance: float) -> StringName:
	if distance < FpsWeaponDefs.SHORT_MAX:
		return &"short"
	if distance < FpsWeaponDefs.MEDIUM_MAX:
		return &"medium"
	return &"long"


static func accuracy_stat_for(distance: float) -> StringName:
	match band_for(distance):
		&"short":
			return Stats.SHORT_ACC
		&"medium":
			return Stats.MEDIUM_ACC
	return Stats.LONG_ACC


static func _stat(stats: Dictionary, id: StringName) -> float:
	return float(stats.get(id, 50))


## Base cone half-angle (degrees) for a weapon + stats at a distance, standing still, no bloom.
static func base_spread(weapon_def: Dictionary, stats: Dictionary, distance: float) -> float:
	var band := band_for(distance)
	var raw: float = float(weapon_def.get("spread_" + String(band), 1.0))
	return raw * accuracy_factor(_stat(stats, accuracy_stat_for(distance)))


## GROUPING -> recoil/bloom multiplier: 1.0 at 0, 0.4 at 99.
static func recoil_control(stats: Dictionary) -> float:
	return lerpf(1.0, 0.4, clampf(_stat(stats, Stats.GROUPING) / 99.0, 0.0, 1.0))


## SWAY -> multiplier on idle sway and on the accuracy lost to movement: 1.5 at 0, 0.3 at 99.
static func sway_factor(stats: Dictionary) -> float:
	return lerpf(1.5, 0.3, clampf(_stat(stats, Stats.SWAY) / 99.0, 0.0, 1.0))


## Idle sway amplitude in degrees.
static func sway_amplitude(weapon_def: Dictionary, stats: Dictionary) -> float:
	return float(weapon_def.get("sway", 0.2)) * sway_factor(stats)


## RELOAD -> reload time in seconds: 1.4x base at 0, 0.7x at 99.
static func reload_time(weapon_def: Dictionary, stats: Dictionary) -> float:
	var f := lerpf(1.4, 0.7, clampf(_stat(stats, Stats.RELOAD) / 99.0, 0.0, 1.0))
	return float(weapon_def.get("reload_time", 2.0)) * f


## Full spread (cone half-angle, degrees) including bloom, movement, crouch and idle sway.
static func compute_spread(weapon_def: Dictionary, stats: Dictionary, distance: float, p_bloom: float = 0.0,
		p_move: float = 0.0, p_crouched: bool = false, p_airborne: bool = false) -> float:
	var s := base_spread(weapon_def, stats, distance)
	var sf := sway_factor(stats)
	s *= 1.0 + p_move * 1.2 * sf
	if p_airborne:
		s *= 1.0 + 2.0 * sf
	if p_crouched:
		s *= 0.8
	return s + p_bloom + sway_amplitude(weapon_def, stats) * 0.25


## Damage at a distance with falloff, before headshot.
static func damage_at(weapon_def: Dictionary, distance: float) -> float:
	var d := float(weapon_def.get("damage", 20.0))
	var a := float(weapon_def.get("falloff_start", 30.0))
	var b := float(weapon_def.get("falloff_end", 80.0))
	var t := clampf((distance - a) / maxf(b - a, 0.001), 0.0, 1.0)
	return d * lerpf(1.0, float(weapon_def.get("min_damage_mult", 0.6)), t)


## Final damage: falloff, then the headshot multiplier.
static func final_damage(weapon_def: Dictionary, distance: float, headshot: bool) -> float:
	var d := damage_at(weapon_def, distance)
	if headshot:
		d *= float(weapon_def.get("headshot_mult", 2.0))
	return d


# ---------------------------------------------------------------- setup

func setup(p_camera: Camera3D, p_stats: Dictionary, p_shooter: Node = null) -> void:
	camera = p_camera
	stats = p_stats
	shooter = p_shooter
	if shooter is CollisionObject3D:
		exclude = [(shooter as CollisionObject3D).get_rid()]


func apply_stats(p_stats: Dictionary) -> void:
	stats = p_stats


func equip(id: StringName) -> void:
	weapon_id = id
	def = FpsWeaponDefs.get_def(id)
	fire_mode = def.get("mode", &"semi")
	ammo = int(def["mag_size"])
	reserve = int(def["reserve"])
	reloading = false
	reload_left = 0.0
	_cooldown = 0.0
	_burst_left = 0
	bloom = 0.0
	recoil = Vector2.ZERO
	weapon_changed.emit(id)
	ammo_changed.emit(ammo, reserve)


func cycle_fire_mode() -> void:
	var modes: Array = def.get("modes", [fire_mode])
	if modes.size() <= 1:
		return
	fire_mode = modes[(modes.find(fire_mode) + 1) % modes.size()]


func refill() -> void:
	ammo = int(def["mag_size"])
	reserve = int(def["reserve"])
	ammo_changed.emit(ammo, reserve)


# ---------------------------------------------------------------- state

func reload_duration() -> float:
	return reload_time(def, stats)


func can_fire() -> bool:
	return not reloading and ammo > 0 and _cooldown <= 0.0


func current_spread(distance: float = 20.0) -> float:
	return compute_spread(def, stats, distance, bloom, move_fraction, crouched, airborne)


func reload() -> bool:
	if reloading or ammo >= int(def["mag_size"]):
		return false
	if reserve <= 0 and not infinite_reserve:
		return false
	reloading = true
	_burst_left = 0
	reload_left = reload_duration()
	reload_started.emit(reload_left)
	return true


func _finish_reload() -> void:
	reloading = false
	reload_left = 0.0
	var need := int(def["mag_size"]) - ammo
	if infinite_reserve:
		ammo += need
	else:
		var take := mini(need, reserve)
		ammo += take
		reserve -= take
	ammo_changed.emit(ammo, reserve)
	reloaded.emit()


## Hold/release the trigger. Semi needs a fresh press per shot, burst fires a burst per press.
func set_trigger(pressed: bool) -> void:
	if pressed and not trigger_held:
		_trigger_released = true
	trigger_held = pressed
	if not pressed:
		_trigger_released = true


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	# bloom and recoil recover
	bloom = maxf(0.0, bloom - float(def.get("bloom_recover", 4.0)) * delta)
	var rate := float(def.get("recoil_recover", 6.0)) * (1.5 - 0.5 * recoil_control(stats))
	var mag := recoil.length()
	if mag > 0.0:
		var step := (rate + mag * 2.0) * delta
		recoil = recoil.move_toward(Vector2.ZERO, step)
	var amp := sway_amplitude(def, stats)
	sway_offset = Vector2(sin(_time * 1.3) * amp, sin(_time * 0.9 + 1.7) * amp) * 0.5
	if reloading:
		reload_left -= delta
		if reload_left <= 0.0:
			_finish_reload()
		return
	# queued burst shots
	if _burst_left > 0 and ammo <= 0:
		_burst_left = 0
	if _burst_left > 0 and _cooldown <= 0.0:
		_burst_left -= 1
		_shoot()
		_cooldown = 60.0 / float(def.get("burst_rpm", 900.0))
		if _burst_left == 0:
			_cooldown = maxf(_cooldown, 60.0 / float(def.get("rpm", 600.0)))
		return
	if trigger_held and _burst_left == 0:
		match fire_mode:
			&"auto":
				try_fire()
			_:
				if _trigger_released:
					_trigger_released = false
					try_fire()


# ---------------------------------------------------------------- firing

func _aim_transform() -> Transform3D:
	if aim_source.is_valid():
		return aim_source.call()
	if camera and camera.is_inside_tree():
		return camera.global_transform
	return Transform3D.IDENTITY


func _space() -> PhysicsDirectSpaceState3D:
	var n3: Node3D = camera if camera else (shooter as Node3D)
	if n3 and n3.is_inside_tree():
		return n3.get_world_3d().direct_space_state
	return null


## Fire one shot now if allowed. Returns {fired, hit, collider, target, position, normal,
## distance, headshot, damage}. In burst mode this starts the burst (the rest follow in tick).
func try_fire() -> Dictionary:
	if reloading or _cooldown > 0.0:
		return _empty_result()
	if ammo <= 0:
		empty.emit()
		if auto_reload:
			reload()
		return _empty_result()
	var result := _shoot()
	if fire_mode == &"burst":
		_burst_left = mini(int(def.get("burst_count", 3)), ammo + 1) - 1
		_cooldown = 60.0 / float(def.get("burst_rpm", 900.0))
	else:
		_cooldown = 60.0 / float(def.get("rpm", 600.0))
	return result


## Same as try_fire() but aimed from an explicit transform (forward is -Z).
func try_fire_from(xform: Transform3D) -> Dictionary:
	var prev := aim_source
	aim_source = func() -> Transform3D: return xform
	var r := try_fire()
	aim_source = prev
	return r


static func _empty_result() -> Dictionary:
	return {"fired": false, "hit": false, "collider": null, "target": null, "position": Vector3.ZERO,
		"normal": Vector3.ZERO, "distance": 0.0, "headshot": false, "damage": 0.0}


func _shoot() -> Dictionary:
	ammo -= 1
	var xf := _aim_transform()
	var origin := xf.origin
	var fwd := -xf.basis.z.normalized()
	var rng_len := float(def.get("range", 250.0))
	var space := _space()
	# Find what we are aiming at to pick the distance band, then scatter the real ray.
	var aim_dist := rng_len
	if space:
		var probe := _ray(space, origin, origin + fwd * rng_len)
		if not probe.is_empty():
			aim_dist = origin.distance_to(probe["position"])
	var spread := current_spread(aim_dist)
	var dir := _scatter(xf.basis, spread)
	var result := _empty_result()
	result["fired"] = true
	if space:
		var h := _ray(space, origin, origin + dir * rng_len)
		if not h.is_empty():
			var pos: Vector3 = h["position"]
			var collider = h["collider"]
			var dist := origin.distance_to(pos)
			var target := find_damageable(collider)
			var head := is_headshot_hit(collider, target, pos)
			var dmg := final_damage(def, dist, head)
			result["hit"] = true
			result["collider"] = collider
			result["target"] = target
			result["position"] = pos
			result["normal"] = h["normal"]
			result["distance"] = dist
			result["headshot"] = head
			result["damage"] = dmg
			if target and target.has_method("take_damage"):
				var info := result.duplicate()
				info["source"] = shooter
				target.take_damage(dmg, info)
	_apply_kick()
	ammo_changed.emit(ammo, reserve)
	fired.emit(result)
	return result


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude)
	return space.intersect_ray(q)


func _scatter(basis: Basis, spread_deg: float) -> Vector3:
	var a := deg_to_rad(spread_deg) * sqrt(_rng.randf())
	var t := _rng.randf() * TAU
	var local := Vector3(sin(a) * cos(t), sin(a) * sin(t), -cos(a))
	return (basis * local).normalized()


func _apply_kick() -> void:
	var control := recoil_control(stats)
	var kick_p := float(def.get("recoil_pitch", 0.8)) * control
	var kick_y := _rng.randf_range(-1.0, 1.0) * float(def.get("recoil_yaw", 0.3)) * control
	var mx := float(def.get("recoil_max", 10.0))
	recoil = Vector2(clampf(recoil.x + kick_p, 0.0, mx), clampf(recoil.y + kick_y, -mx, mx))
	bloom = minf(float(def.get("bloom_max", 2.5)), bloom + float(def.get("bloom_per_shot", 0.25)) * control)


## Walks up from a ray collider to the first node in group "damageable".
static func find_damageable(collider) -> Node:
	var n: Node = collider as Node
	while n:
		if n.is_in_group(&"damageable"):
			return n
		n = n.get_parent()
	return null


static func is_headshot_hit(collider, target: Node, world_pos: Vector3) -> bool:
	if collider is Node and (collider as Node).has_meta(&"headshot") and bool((collider as Node).get_meta(&"headshot")):
		return true
	if target and target.has_method("is_headshot"):
		return bool(target.is_headshot(world_pos))
	if collider is Node and (collider as Node).has_method("is_headshot"):
		return bool(collider.is_headshot(world_pos))
	return false

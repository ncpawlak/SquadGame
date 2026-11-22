class_name FpsBot
extends CharacterBody3D
## AI soldier. Same weapon/damage contract as FpsPlayer: signals shot_fired/damaged/died, `weapon`, `health`,
## and take_damage(amount, hit) in group "damageable". Decisions come from FpsBotBrain.
## It talks to its world (FpsHillMatch, or anything with the same methods) through `world`:
##   enemies_of(team_id), allies_of(team_id) -> Array, hill_center() -> Vector3, hill_radius() -> float,
##   zone_name_for(team_id) -> String, count_on_point(team_id) -> int, cover_points() -> Array

signal shot_fired(hit)
signal damaged(amount, source)
signal died(source)

const CORE_WEAPON := "res://scripts/fps/core/fps_weapon.gd"
const EYE_HEIGHT := 1.5
const MAX_HEALTH := 100.0
const BASE_AIM_ERROR_DEG := 0.8

## If the core weapon already applies damage to what it hits, set false (the stub weapon does not).
var apply_damage_itself := true

var soldier: Soldier
var team_id := 0
var role: int = Scheme.Role.FLEX
var slot: StringName = &""
var tun: Dictionary = {}
var health := MAX_HEALTH
var alive := true
var weapon  # FpsWeapon (core) or StubFpsWeapon
var world: Object = null
var state: StringName = FpsBotBrain.HOLD
var state_time := 0.0
var target: Node3D = null
var rng := RandomNumberGenerator.new()

var _nav: NavigationAgent3D
var _head: Node3D
var _since_damaged := 99.0
var _target_seen_t := 0.0
var _scan_t := 0.0
var _think_t := 0.0
var _trade_pos := Vector3.ZERO
var _trade_age := -1.0
var _goal := Vector3.ZERO
var _cover_goal := Vector3.INF
var _offset := Vector3.ZERO
var _last_visible := 0

## Role mode (the world offers arena_map()): FpsRoleBrain drives goals, cover bounding and peek/duck like the 2D sim.
const BURST := 3
var brain: FpsRoleBrain = null
var crouched := false
var mode_override: StringName = &""
var _arena: ArenaMap = null
var _goal2 := Vector2.INF
var _wp := Vector2.INF
var _wp_goal := Vector2.INF
var _repath_t := 0.0
var _stuck_t := 0.0
var _last_pos2 := Vector2.INF
var _burst_n := 0
var _settle_t := 0.0
var _col: CollisionShape3D
var _mesh: MeshInstance3D


func setup(p_soldier: Soldier, p_team_id: int, p_role = Scheme.Role.FLEX) -> void:
	soldier = p_soldier
	team_id = p_team_id
	role = int(p_role)
	tun = FpsBotBrain.tuning(soldier, role)
	add_to_group(StringName("fps_team_%d" % team_id))
	if _nav == null:
		_build_nodes()
	if weapon is FpsWeapon:
		# The core weapon: it aims from the bot's head, uses his ratings for spread, recoil and reload, and deals the
		# damage itself (so the bot must not apply it a second time).
		var fw := weapon as FpsWeapon
		fw.setup(null, soldier.stats if soldier != null else {}, self)
		fw.aim_source = func() -> Transform3D: return _head.global_transform
		fw.infinite_reserve = true
		fw.equip(&"rifle")
		apply_damage_itself = false
	elif weapon.has_method("setup"):
		weapon.setup(soldier)
	rng.seed = (soldier.id if soldier != null else 0) * 7919 + team_id


func _build_nodes() -> void:
	add_to_group(&"damageable")
	add_to_group(&"fps_bot")
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.35
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	_col = col
	var mesh := MeshInstance3D.new()
	_mesh = mesh
	var cm := CapsuleMesh.new()
	cm.height = 1.8
	cm.radius = 0.35
	mesh.mesh = cm
	mesh.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.3, 0.25) if team_id == 1 else Color(0.25, 0.5, 0.95)
	mesh.material_override = mat
	add_child(mesh)
	_head = Node3D.new()
	_head.position.y = EYE_HEIGHT
	add_child(_head)
	if ResourceLoader.exists(CORE_WEAPON):
		weapon = load(CORE_WEAPON).new()
	else:
		weapon = StubFpsWeapon.new()
		weapon.owner_body = self
	_head.add_child(weapon)
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.8
	_nav.target_desired_distance = 1.2
	_nav.radius = 0.4
	add_child(_nav)


## Shot at (a bullet went close): the same composure shake the player gets.
func suppress(amount: float) -> void:
	if alive and weapon != null and weapon.has_method("suppress"):
		weapon.suppress(amount)
	_since_damaged = minf(_since_damaged, 1.0)


func rating_stats() -> Dictionary:
	return soldier.stats if soldier != null else {}


func move_fraction_now() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / 6.0, 0.0, 1.0)


func eye_pos() -> Vector3:
	return global_position + Vector3(0, _head.position.y if _head != null else EYE_HEIGHT, 0)


func hp_frac() -> float:
	return clampf(health / MAX_HEALTH, 0.0, 1.0)


func respawn(at: Vector3) -> void:
	global_position = at
	health = MAX_HEALTH
	alive = true
	target = null
	state = FpsBotBrain.HOLD
	state_time = 0.0
	_trade_age = -1.0
	_since_damaged = 99.0
	velocity = Vector3.ZERO
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	if brain != null:
		_role_refresh_mode()
		brain.reset_life()
	_goal2 = Vector2.INF
	_wp = Vector2.INF
	_burst_n = 0
	_settle_t = 0.0
	_set_crouch(false)


func take_damage(amount: float, hit: Dictionary = {}) -> void:
	if not alive:
		return
	# Nobody can be shot in their own spawn zone (the sim's rule).
	if _arena != null and ArenaMap.in_spawn_zone(team_id, Vector2(global_position.x, global_position.z)):
		return
	var src = hit.get("source", null)
	if brain != null and src is Node3D and is_instance_valid(src):
		brain.shot_at(Vector2(global_position.x, global_position.z), _arena, Vector2(src.global_position.x, src.global_position.z))
	# Strength absorbs damage; on the hill, anchor does too (same rating map as the player).
	var st: Dictionary = soldier.stats if soldier != null else {}
	amount *= FpsRatings.damage_taken_mult(st)
	if FpsHill.on_hill(global_position):
		amount *= FpsRatings.anchor_damage_mult(st)
	if weapon != null and weapon.has_method("suppress"):
		weapon.suppress(minf(1.0, amount / 25.0))
	health -= amount
	_since_damaged = 0.0
	damaged.emit(amount, src)
	if health <= 0.0:
		alive = false
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		died.emit(src)


## A teammate died; the world tells teammates where the killer was.
func notify_teammate_down(killer_pos: Vector3) -> void:
	_trade_pos = killer_pos
	_trade_age = 0.0


func build_ctx() -> Dictionary:
	var center: Vector3 = world.hill_center()
	var flat := Vector3(global_position.x - center.x, 0, global_position.z - center.z)
	var dist := flat.length()
	return {
		"state": state, "state_time": state_time, "hp_frac": hp_frac(), "since_damaged": _since_damaged,
		"visible_enemies": _last_visible, "on_point": dist <= world.hill_radius(),
		"zone": world.zone_name_for(team_id),
		"allies_on_point": world.count_on_point(team_id), "enemies_on_point": world.count_on_point(1 - team_id),
		"allies_near": _allies_near(), "dist_to_point": dist, "trade_age": _trade_age,
		"trade_roll": rng.randf(), "tun": tun,
	}


func _allies_near() -> int:
	var n := 0
	for a in world.allies_of(team_id):
		if a != self and a.alive and a.global_position.distance_to(global_position) <= tun["stack_dist"] * 2.0:
			n += 1
	return n


func has_los(to: Node3D) -> bool:
	var to_pos: Vector3 = to.global_position + Vector3(0, EYE_HEIGHT * 0.8, 0)
	var q := PhysicsRayQueryParameters3D.create(eye_pos(), to_pos)
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return r.is_empty() or r["collider"] == to


func _scan() -> void:
	var best: Node3D = null
	var best_d := INF
	var count := 0
	for e in world.enemies_of(team_id):
		if not e.alive:
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d > tun["spot_range"] or not has_los(e):
			continue
		count += 1
		if d < best_d:
			best_d = d
			best = e
	_last_visible = count
	if best != target:
		target = best
		_target_seen_t = 0.0


func _physics_process(delta: float) -> void:
	if not alive or world == null:
		return
	if brain == null and _arena == null and world.has_method("arena_map"):
		_role_init()
	if brain != null:
		_role_process(delta)
		return
	state_time += delta
	_since_damaged += delta
	if _trade_age >= 0.0:
		_trade_age += delta
		if _trade_age > FpsBotBrain.TRADE_WINDOW_S + 1.0:
			_trade_age = -1.0
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.2
		_scan()
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.25
		var next := FpsBotBrain.decide(build_ctx())
		if next != state:
			state = next
			state_time = 0.0
			_cover_goal = Vector3.INF
			_offset = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * minf(world.hill_radius() * 0.7, tun["stack_dist"])
		_goal = _pick_goal()
	_move(delta)
	_aim_and_shoot(delta)


func _pick_goal() -> Vector3:
	var center: Vector3 = world.hill_center()
	match state:
		FpsBotBrain.PUSH, FpsBotBrain.ROTATE:
			return center + _offset
		FpsBotBrain.TRADE:
			return _trade_pos
		FpsBotBrain.COVER:
			if _cover_goal == Vector3.INF:
				_cover_goal = _find_cover()
			return _cover_goal
		_:
			# HOLD: near the point, drifting toward the nearest teammate when teamwork is high.
			var g := center + _offset * 1.6
			if tun["stack_dist"] < 8.0:
				var near: Node3D = null
				for a in world.allies_of(team_id):
					if a != self and a.alive and (near == null or a.global_position.distance_to(global_position) < near.global_position.distance_to(global_position)):
						near = a
				if near != null:
					g = g.lerp(near.global_position, 0.3)
			return g


func _find_cover() -> Vector3:
	var best := global_position
	var best_score := INF
	for p in world.cover_points():
		var score: float = global_position.distance_to(p)
		if target != null:
			# prefer spots farther from the threat than we are now
			score -= ((p - target.global_position).length() - (global_position - target.global_position).length()) * 0.5
		if score < best_score:
			best_score = score
			best = p
	return best


func _move(delta: float) -> void:
	var speed: float = tun["move_speed"] * (1.15 if state == FpsBotBrain.COVER else 1.0)
	_nav.target_position = _goal
	var dest := _goal
	if not _nav.is_navigation_finished():
		dest = _nav.get_next_path_position()
	var dir := dest - global_position
	dir.y = 0
	var arrived := Vector2(_goal.x - global_position.x, _goal.z - global_position.z).length() < 1.2
	if dir.length() > 0.1 and not arrived:
		dir = dir.normalized()
		var s := speed * (0.55 if target != null and state == FpsBotBrain.HOLD else 1.0)
		velocity.x = dir.x * s
		velocity.z = dir.z * s
	else:
		velocity.x = move_toward(velocity.x, 0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 20.0 * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()


func _aim_and_shoot(delta: float) -> void:
	var look_at_pos: Vector3
	if target != null and is_instance_valid(target):
		_target_seen_t += delta
		look_at_pos = target.global_position + Vector3(0, EYE_HEIGHT * 0.8, 0)
	elif velocity.length() > 0.5:
		look_at_pos = global_position + Vector3(velocity.x, 0, velocity.z) + Vector3(0, EYE_HEIGHT, 0)
	else:
		return
	var flat := look_at_pos - global_position
	flat.y = 0
	if flat.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(1.0, 10.0 * delta))
	var to_t := look_at_pos - _head.global_position
	var pitch := atan2(to_t.y, Vector2(to_t.x, to_t.z).length())
	_head.rotation.x = lerp_angle(_head.rotation.x, pitch, minf(1.0, 12.0 * delta))
	if target == null or _target_seen_t < tun["reaction_s"]:
		return
	# Composure: aim error is worse for a couple of seconds after being hit.
	var err_mult: float = tun["fire_error_mult"] if _since_damaged < 2.0 else 1.0
	var err := deg_to_rad(BASE_AIM_ERROR_DEG * err_mult)
	var saved := _head.rotation
	_head.rotation += Vector3(rng.randf_range(-err, err), 0, 0)
	var res: Dictionary = weapon.try_fire()
	_head.rotation = saved
	if res.get("hit", false):
		var c = res.get("collider")
		if apply_damage_itself and c != null and c.is_in_group(&"damageable") and c.has_method("take_damage"):
			res["source"] = self
			c.take_damage(res.get("damage", 0.0), res)
		shot_fired.emit(res)


# --- role mode: the sim's tactics in 3D (FpsRoleBrain) ------------------------------------------
# World interface used here: arena_map() -> ArenaMap, game_mode() -> StringName, scheme_of(team_id) -> Scheme,
# enemies_of(team_id), allies_of(team_id). Nothing else (no hill_* / zone_* / cover_points) is needed.

func set_mode_context(mode: StringName) -> void:
	mode_override = mode
	if brain != null:
		_role_refresh_mode()


func cover_spot_2d() -> Vector2:
	return brain.cover_spot if brain != null else Vector2.INF


func goes_point_now() -> bool:
	return brain != null and brain.goes_point


func _pos2() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func _role_init() -> void:
	_arena = world.arena_map()
	_arena.ensure_built()
	brain = FpsRoleBrain.new()
	var sch: Scheme = world.scheme_of(team_id) if world.has_method("scheme_of") else null
	brain.setup(soldier, team_id, role, slot, sch, rng)
	_role_refresh_mode()
	brain.reset_life()


func _role_refresh_mode() -> void:
	var mode: StringName = mode_override
	if mode == &"" and world != null and world.has_method("game_mode"):
		mode = world.game_mode()
	brain.set_koth(mode == MatchEngine.MODE_KOTH)


func _set_crouch(down: bool) -> void:
	if down == crouched or _col == null:
		return
	crouched = down
	var h := 1.0 if down else 1.8
	(_col.shape as CapsuleShape3D).height = h
	_col.position.y = h * 0.5
	(_mesh.mesh as CapsuleMesh).height = h
	_mesh.position.y = h * 0.5
	_head.position.y = 0.85 if down else EYE_HEIGHT


func _unit(n) -> Dictionary:
	var r = n.get("role")
	return {
		"pos": Vector2(n.global_position.x, n.global_position.z), "alive": n.alive,
		"role": int(r) if r != null else -1,
		"cover": n.cover_spot_2d() if n.has_method("cover_spot_2d") else Vector2.INF,
		"goes": n.goes_point_now() if n.has_method("goes_point_now") else false,
		"hp": n.hp_frac() * 100.0 if n.has_method("hp_frac") else 100.0,
	}


func _aim_height(n: Node3D) -> float:
	var down = n.get("crouched")
	if down == null:
		down = n.get("crouching")
	return 0.55 if down else EYE_HEIGHT * 0.8


func _role_scan() -> void:
	var best: Node3D = null
	var best_d := INF
	var count := 0
	var from := global_position + Vector3(0, EYE_HEIGHT, 0)  # a ducked soldier still reads the field when he peeks
	var other := 1 - team_id
	for e in world.enemies_of(team_id):
		if not e.alive:
			continue
		var ep := Vector2(e.global_position.x, e.global_position.z)
		if ArenaMap.in_spawn_zone(other, ep):
			continue  # untouchable in his spawn zone
		var d: float = e.global_position.distance_to(global_position)
		if d > tun["spot_range"]:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, e.global_position + Vector3(0, _aim_height(e), 0))
		q.exclude = [get_rid()]
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not (r.is_empty() or r["collider"] == e):
			continue
		count += 1
		if d < best_d:
			best_d = d
			best = e
	_last_visible = count
	if best != target:
		target = best
		_target_seen_t = 0.0
	if best != null:
		brain.note_visible(Vector2(best.global_position.x, best.global_position.z))


func _role_tick() -> void:
	var pos2 := _pos2()
	var allies: Array = []
	var enemies: Array = []
	for a in world.allies_of(team_id):
		if a != self:
			allies.append(_unit(a))
	var other := 1 - team_id
	for e in world.enemies_of(team_id):
		var u := _unit(e)
		if not ArenaMap.in_spawn_zone(other, u["pos"]):
			enemies.append(u)
	_role_refresh_mode()
	if brain.koth:
		var squad := allies.duplicate()
		var me := _unit(self)
		me["self"] = true
		squad.append(me)
		brain.point_decisions(pos2, health, squad, enemies)
	_goal2 = brain.goal(pos2, _arena, allies, enemies, weapon.reloading if "reloading" in weapon else false)
	state = brain.posture
	_set_crouch(brain.ducked(pos2))


func _role_process(delta: float) -> void:
	state_time += delta
	_since_damaged += delta
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.2
		_role_scan()
	var ticks := brain.advance(delta)
	if ticks > 0 or _goal2 == Vector2.INF:
		_role_tick()
	_role_move(delta)
	_role_aim(delta)


func _role_move(delta: float) -> void:
	var pos2 := _pos2()
	var stop := brain.ducked(pos2) or pos2.distance_to(_goal2) < 0.45
	var dir := Vector2.ZERO
	if not stop:
		_repath_t -= delta
		if _wp == Vector2.INF or _wp_goal == Vector2.INF or _goal2.distance_squared_to(_wp_goal) > 4.0 \
				or _repath_t <= 0.0 or pos2.distance_squared_to(_wp) < 0.25:
			_wp = _arena.next_waypoint(pos2, _goal2)
			_wp_goal = _goal2
			_repath_t = 2.0
		var to := _wp - pos2
		if to.length() < 0.001:
			stop = true
		else:
			dir = to.normalized()
	if stop:
		velocity.x = move_toward(velocity.x, 0, 25.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 25.0 * delta)
		_stuck_t = 0.0
	else:
		var speed: float = tun["move_speed"]
		if brain.posture == FpsRoleBrain.POSTURE_BOUND or brain.posture == FpsRoleBrain.POSTURE_FALLBACK:
			speed *= 1.15
		elif target != null and brain.posture != FpsRoleBrain.POSTURE_POINT:
			speed *= 0.75  # fighting while closing
		velocity.x = dir.x * speed
		velocity.z = dir.y * speed
		if Vector2(velocity.x, velocity.z).length() > 0.5 and _last_pos2 != Vector2.INF and pos2.distance_to(_last_pos2) < speed * delta * 0.15:
			_stuck_t += delta
			if _stuck_t > 0.6:
				_stuck_t = 0.0
				_repath_t = 0.0
		else:
			_stuck_t = 0.0
	_last_pos2 = pos2
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if weapon is FpsWeapon:
		weapon.move_fraction = move_fraction_now()
		weapon.crouched = crouched


func _role_aim(delta: float) -> void:
	var look_at_pos: Vector3
	var has_target := target != null and is_instance_valid(target)
	if has_target:
		_target_seen_t += delta
		look_at_pos = target.global_position + Vector3(0, _aim_height(target), 0)
	elif Vector2(velocity.x, velocity.z).length() > 0.5:
		look_at_pos = global_position + Vector3(velocity.x, 0, velocity.z) + Vector3(0, EYE_HEIGHT, 0)
	else:
		return
	var flat := look_at_pos - global_position
	flat.y = 0
	if flat.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(1.0, 12.0 * delta))
	var to_t := look_at_pos - _head.global_position
	var pitch := atan2(to_t.y, Vector2(to_t.x, to_t.z).length())
	_head.rotation.x = lerp_angle(_head.rotation.x, pitch, minf(1.0, 12.0 * delta))
	if not has_target or _target_seen_t < tun["reaction_s"]:
		return
	var pos2 := _pos2()
	if brain.in_cover(pos2) and not brain.peeking:
		return  # head down behind cover until the next peek
	if _settle_t > 0.0:
		_settle_t -= delta
		return
	var err_mult: float = tun["fire_error_mult"] if _since_damaged < 2.0 else 1.0
	var err := deg_to_rad(BASE_AIM_ERROR_DEG * err_mult)
	var saved := _head.rotation
	_head.rotation += Vector3(rng.randf_range(-err, err), 0, 0)
	var res: Dictionary = weapon.try_fire()
	_head.rotation = saved
	if res.get("fired", res.get("hit", false)):
		_burst_n += 1
		if _burst_n >= BURST:
			_burst_n = 0
			_settle_t = 0.45 + rng.randf() * 0.5
	if res.get("hit", false):
		var c = res.get("collider")
		if apply_damage_itself and c != null and c.is_in_group(&"damageable") and c.has_method("take_damage"):
			res["source"] = self
			c.take_damage(res.get("damage", 0.0), res)
		shot_fired.emit(res)

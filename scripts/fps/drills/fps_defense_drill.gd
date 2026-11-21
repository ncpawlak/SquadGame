class_name FpsDefenseDrill
extends FpsDrill
## Hill defense (OBJ_IQ): a first-person tower defense, translated from the 2D Defense task. Enemies walk a path to the hill;
## walk the field and press E near a build pad to place a turret (coins), press E again to upgrade it. Turrets shoot enemies in
## range, kills pay coins, waves get tougher. Your own rifle also hurts enemies, but the turrets are the point.
## Every step is plain code (advance, build_turret, upgrade_turret, damage_enemy) so tests drive it with no input or scene.

const FIELD_W := 36.0
const FIELD_D := 28.0
## Same layout as the 2D task (0..1 coordinates), mapped onto the field: x across, z away from the player.
const PATH_N := [Vector2(0.0, 0.28), Vector2(0.36, 0.28), Vector2(0.36, 0.74), Vector2(0.7, 0.74), Vector2(0.7, 0.36), Vector2(0.9, 0.36)]
const PADS_N := [Vector2(0.18, 0.5), Vector2(0.2, 0.08), Vector2(0.5, 0.5), Vector2(0.52, 0.93), Vector2(0.58, 0.55), Vector2(0.84, 0.6), Vector2(0.8, 0.14), Vector2(0.54, 0.15)]
const TURRET_RANGE := 8.0
const RANGE_PER_LEVEL := 0.2
const TURRET_COOLDOWN := 0.55
const MAX_LEVEL := 3
const START_COINS := 60
const COST := 25
const UPGRADE_COST := 20
const BOUNTY := 6
const HILL_HP := 10
const WAVES := 5
const PER_WAVE := 6
const INTERACT_RANGE := 3.0

var path: Array = []             # Vector3 corners
var pads: Array = []             # Vector3 per pad
var coins := 0
var hill_hp := HILL_HP
var kills := 0
var leaked := 0
var total_enemies := 0
var enemies: Array = []          # Enemy nodes
var turrets := {}                # pad index -> {lvl, cd}
var spawns: Array = []           # {t, hp, speed}
var path_len := 1.0
var _spawn_idx := 0
var _pad_nodes: Array = []       # {turret: MeshInstance3D, label: Label3D}


func _init() -> void:
	super()
	stat = Stats.OBJ_IQ
	title = "Hill defense"
	instructions = "Stop the enemies reaching the hill. E near a pad builds a turret (%d coins), E again upgrades it (%d)." % [COST, UPGRADE_COST]
	lock_player = false
	# Your own gun is a helper: standard ratings everywhere.
	loadout = {}
	for p in PATH_N:
		path.append(Vector3((p.x - 0.5) * FIELD_W, 0.0, -p.y * FIELD_D))
	for p in PADS_N:
		pads.append(Vector3((p.x - 0.5) * FIELD_W, 0.0, -p.y * FIELD_D))
	path_len = FpsDefenseDrill.path_length(path)
	spawns = FpsDefenseDrill.make_spawns(WAVES, PER_WAVE)
	total_enemies = spawns.size()
	duration = float(spawns[spawns.size() - 1]["t"]) + path_len / 3.2 + 2.0
	player_spawn = Vector3(0, 0.1, 3.0)


# ---- pure rules -----------------------------------------------------------------------------------------------------

## Total length of a corner path.
static func path_length(corners: Array) -> float:
	var total := 0.0
	for i in corners.size() - 1:
		total += (corners[i] as Vector3).distance_to(corners[i + 1])
	return total


## Where an enemy that has walked `d` metres along the path is (the last corner once it has arrived).
static func pos_at(corners: Array, d: float) -> Vector3:
	var left := maxf(d, 0.0)
	for i in corners.size() - 1:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[i + 1]
		var seg := a.distance_to(b)
		if left <= seg:
			return a.lerp(b, left / maxf(seg, 0.0001))
		left -= seg
	return corners[corners.size() - 1]


## The spawn list: {t, hp, speed}. A wave's enemies are tougher and quicker than the last, spaced a little tighter.
static func make_spawns(waves: int, per_wave: int) -> Array:
	var out: Array = []
	var t := 1.5
	for w in waves:
		for k in per_wave:
			out.append({"t": t, "hp": 2 + w * 2, "speed": 3.2 + 0.8 * float(w)})
			t += 0.95 - 0.07 * float(w)
		t += 3.0
	return out


static func turret_range(level: int) -> float:
	return TURRET_RANGE * (1.0 + RANGE_PER_LEVEL * float(level - 1))


## Score: mostly the share of enemies killed, plus hill health. A fallen hill caps it lower.
static func defense_score(kills_made: int, total: int, hp: int, max_hp: int) -> float:
	if total <= 0:
		return 0.0
	var frac := clampf(float(kills_made) / float(total), 0.0, 1.0)
	if hp > 0:
		return FpsDrill.clamp01(0.7 * frac + 0.3 * clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0))
	return FpsDrill.clamp01(0.6 * frac)


# ---- economy --------------------------------------------------------------------------------------------------------

func can_build(pad: int) -> bool:
	return state == State.RUNNING and pad >= 0 and pad < pads.size() and not turrets.has(pad) and coins >= COST


func can_upgrade(pad: int) -> bool:
	return state == State.RUNNING and turrets.has(pad) and int(turrets[pad]["lvl"]) < MAX_LEVEL and coins >= UPGRADE_COST


func build_turret(pad: int) -> bool:
	if not can_build(pad):
		return false
	coins -= COST
	turrets[pad] = {"lvl": 1, "cd": 0.0}
	_refresh_pad(pad)
	return true


func upgrade_turret(pad: int) -> bool:
	if not can_upgrade(pad):
		return false
	coins -= UPGRADE_COST
	turrets[pad]["lvl"] = int(turrets[pad]["lvl"]) + 1
	_refresh_pad(pad)
	return true


func turret_level(pad: int) -> int:
	return int(turrets[pad]["lvl"]) if turrets.has(pad) else 0


## Index of the pad closest to `pos` (XZ) within `max_dist`, or -1.
func nearest_pad(pos: Vector3, max_dist: float = INTERACT_RANGE) -> int:
	var best := -1
	var best_d := max_dist
	for i in pads.size():
		var d := Vector2(pos.x - (pads[i] as Vector3).x, pos.z - (pads[i] as Vector3).z).length()
		if d <= best_d:
			best_d = d
			best = i
	return best


## Build or upgrade the pad nearest the player. Returns true when coins were spent.
func interact() -> bool:
	if player == null:
		return false
	var pos := player.global_position if player.is_inside_tree() else player.position
	var pad := nearest_pad(pos)
	if pad < 0:
		return false
	if turrets.has(pad):
		return upgrade_turret(pad)
	return build_turret(pad)


# ---- geometry -------------------------------------------------------------------------------------------------------

func _build() -> void:
	# Path slabs (flat, no collision), the hill disc and the build pads.
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var mid := (a + b) / 2.0 + Vector3(0, 0.03, 0)
		var sz := Vector3(maxf(absf(b.x - a.x), 2.4), 0.06, maxf(absf(b.z - a.z), 2.4))
		add_box(mid, sz, Color(0.3, 0.27, 0.22)).collision_layer = 0
	var hill_pos: Vector3 = path[path.size() - 1]
	add_box(hill_pos + Vector3(0, 0.05, 0), Vector3(4.0, 0.1, 4.0), Color(0.2, 0.75, 0.3)).collision_layer = 0
	for i in pads.size():
		var p: Vector3 = pads[i]
		add_box(p + Vector3(0, 0.04, 0), Vector3(1.6, 0.08, 1.6), Color(0.85, 0.85, 0.9)).collision_layer = 0
		var tm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 1.0, 0.9)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.7, 0.15)
		bm.material = mat
		tm.mesh = bm
		tm.position = p + Vector3(0, 0.5, 0)
		tm.visible = false
		add_child(tm)
		var lab := Label3D.new()
		lab.position = p + Vector3(0, 2.2, 0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.pixel_size = 0.008
		add_child(lab)
		_pad_nodes.append({"turret": tm, "label": lab})
		_refresh_pad(i)


func _refresh_pad(pad: int) -> void:
	if pad >= _pad_nodes.size():
		return
	var nodes: Dictionary = _pad_nodes[pad]
	var lvl := turret_level(pad)
	var tm: MeshInstance3D = nodes["turret"]
	tm.visible = lvl > 0
	tm.scale = Vector3(1.0, 1.0 + 0.6 * float(maxi(lvl - 1, 0)), 1.0)
	tm.position.y = 0.5 * tm.scale.y
	var lab: Label3D = nodes["label"]
	if lvl == 0:
		lab.text = "Build (%d)" % COST
	elif lvl < MAX_LEVEL:
		lab.text = "Level %d  upgrade (%d)" % [lvl, UPGRADE_COST]
	else:
		lab.text = "Level %d (max)" % lvl


# ---- run ------------------------------------------------------------------------------------------------------------

func _begin() -> void:
	coins = START_COINS
	hill_hp = HILL_HP
	kills = 0
	leaked = 0
	_spawn_idx = 0
	for e in enemies:
		if is_instance_valid(e):
			e.free()
	enemies.clear()
	turrets.clear()
	for i in pads.size():
		_refresh_pad(i)


func _unhandled_input(event: InputEvent) -> void:
	if state != State.RUNNING:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		if interact() and is_inside_tree():
			get_viewport().set_input_as_handled()


func _run(delta: float) -> void:
	while _spawn_idx < spawns.size() and float(spawns[_spawn_idx]["t"]) <= elapsed:
		_spawn(spawns[_spawn_idx])
		_spawn_idx += 1
	for e in enemies.duplicate():
		e.d += e.speed * delta
		if e.d >= path_len:
			_remove_enemy(e)
			hill_hp -= 1
			leaked += 1
		else:
			e.position = FpsDefenseDrill.pos_at(path, e.d) + Vector3(0, 0.9, 0)
	for pad in turrets:
		var tw: Dictionary = turrets[pad]
		tw["cd"] = float(tw["cd"]) - delta
		if float(tw["cd"]) > 0.0:
			continue
		var target := _turret_target(pad, int(tw["lvl"]))
		if target != null:
			tw["cd"] = TURRET_COOLDOWN
			damage_enemy(target, int(tw["lvl"]))
	if hill_hp <= 0 or (_spawn_idx >= spawns.size() and enemies.is_empty()):
		finish(_final_score())


## The enemy farthest along the path inside this turret's range.
func _turret_target(pad: int, lvl: int) -> Enemy:
	var from: Vector3 = pads[pad]
	var r := FpsDefenseDrill.turret_range(lvl)
	var best: Enemy = null
	for e in enemies:
		var p := FpsDefenseDrill.pos_at(path, e.d)
		if Vector2(p.x - from.x, p.z - from.z).length() <= r:
			if best == null or e.d > best.d:
				best = e
	return best


func _spawn(s: Dictionary) -> void:
	var e := Enemy.new()
	e.setup(self, int(s["hp"]), float(s["speed"]))
	e.position = FpsDefenseDrill.pos_at(path, 0.0) + Vector3(0, 0.9, 0)
	add_child(e)
	enemies.append(e)


## Hurt an enemy (turret, player gun or a test). A kill pays the bounty. Returns true on a kill.
func damage_enemy(e, amount: int) -> bool:
	if not is_instance_valid(e) or not enemies.has(e) or amount <= 0:
		return false
	e.hp -= amount
	if e.hp <= 0:
		kills += 1
		coins += BOUNTY
		_remove_enemy(e)
		return true
	return false


func _remove_enemy(e: Enemy) -> void:
	enemies.erase(e)
	e.collision_layer = 0
	e.visible = false
	if e.get_parent() != null:
		e.get_parent().remove_child(e)
	if is_inside_tree():
		e.queue_free()
	else:
		e.free()


func _final_score() -> float:
	return FpsDefenseDrill.defense_score(kills, total_enemies, hill_hp, HILL_HP)


func _hud_extra() -> String:
	return "Coins %d   Hill %d   Kills %d / %d" % [coins, maxi(hill_hp, 0), kills, total_enemies]


func _end() -> void:
	for e in enemies.duplicate():
		_remove_enemy(e)


## One walking enemy: a damageable body so the player's rifle can hit it. A headshot hits for double.
class Enemy extends StaticBody3D:
	var drill: FpsDefenseDrill
	var hp := 2
	var max_hp := 2
	var speed := 3.2
	var d := 0.0

	func setup(owner_drill: FpsDefenseDrill, p_hp: int, p_speed: float) -> void:
		drill = owner_drill
		hp = p_hp
		max_hp = p_hp
		speed = p_speed
		add_to_group(&"damageable")
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = 1.8
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.2, 0.2)
		cm.material = mat
		mi.mesh = cm
		add_child(mi)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.8
		cs.shape = cap
		add_child(cs)

	func take_damage(_amount: float, info: Dictionary = {}) -> void:
		if drill != null:
			drill.damage_enemy(self, 2 if bool(info.get("headshot", false)) else 1)

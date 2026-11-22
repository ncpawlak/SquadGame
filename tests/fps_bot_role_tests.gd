extends SceneTree
## Role-driven FpsBot: pure FpsRoleBrain rules (ported from MatchEngine) and bots driven headless on a plain
## StaticBody3D box scene built from the legacy ArenaMap field, with a tiny fake world object.
## Run: godot --headless --path . --script tests/fps_bot_role_tests.gd

var _failures := 0
var _passes := 0
var _current := ""


class FakeWorld:
	extends Node3D
	var field: ArenaMap
	var mode: StringName = &"tdm"
	var teams: Array = []
	var bots: Array = [[], []]

	func arena_map() -> ArenaMap:
		return field

	func game_mode() -> StringName:
		return mode

	func scheme_of(team_id: int) -> Scheme:
		return teams[team_id].scheme

	func enemies_of(team_id: int) -> Array:
		return bots[1 - team_id]

	func allies_of(team_id: int) -> Array:
		return bots[team_id]


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var tests: Array = []
	for method in get_method_list():
		if String(method["name"]).begins_with("test_"):
			tests.append(String(method["name"]))
	for t in tests:
		_current = t
		var before := _failures
		await call(t)
		if _failures == before:
			_passes += 1
			print("  PASS  %s" % t)
		else:
			print("  FAIL  %s" % t)
	print("\n%d passed, %d failed" % [_passes, tests.size() - _passes])
	quit(0 if _passes == tests.size() else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("    [%s] %s" % [_current, msg])


func _soldier(id: int, v: int) -> Soldier:
	var s := Soldier.new()
	s.id = id
	s.age = 24
	s.stats = Stats.make_uniform(v)
	return s


func _team(id: int, first_id: int, v: int) -> Team:
	var t := Team.new()
	t.id = id
	t.abbrev = "T%d" % id
	for i in 5:
		t.roster.append(_soldier(first_id + i, v))
	t.auto_lineup()
	return t


func _brain(team: int, slot_role: int, slot: StringName, koth := false, v := 70) -> FpsRoleBrain:
	var b := FpsRoleBrain.new()
	var tm := _team(1, 10, v)
	b.rng.seed = 5
	b.koth = koth
	b.setup(_soldier(1, v), team, slot_role, slot, tm.scheme)
	return b


func _slot_of_role(tm: Team, role: int) -> StringName:
	for s: Soldier in tm.starters():
		var slot: StringName = tm.slot_of(s)
		if Scheme.SLOT_ROLES.get(slot, -1) == role:
			return slot
	return &""


func _unit(pos: Vector2, role := -1, alive := true) -> Dictionary:
	return {"pos": pos, "alive": alive, "role": role, "cover": Vector2.INF, "goes": false, "hp": 100.0}


# --- pure brain ---

func test_standoffs() -> void:
	var tm := _team(1, 10, 70)
	var f := _brain(0, Scheme.Role.FRONTMAN, _slot_of_role(tm, Scheme.Role.FRONTMAN))
	var c := _brain(0, Scheme.Role.CENTER, _slot_of_role(tm, Scheme.Role.CENTER))
	var x := _brain(0, Scheme.Role.FLEX, _slot_of_role(tm, Scheme.Role.FLEX))
	check(is_equal_approx(f.standoff(), 12.0), "frontman standoff 12 m")
	check(is_equal_approx(c.standoff(), 30.0), "center standoff 30 m")
	check(is_equal_approx(x.standoff(), 0.0), "flex runs the flank first (no standoff)")
	x.flank_progress = 1.0
	check(is_equal_approx(x.standoff(), 17.0), "flanked flex standoff 17 m")


func test_role_goals_tdm() -> void:
	var tm := _team(1, 10, 70)
	var fslot := _slot_of_role(tm, Scheme.Role.FRONTMAN)
	var f := _brain(0, Scheme.Role.FRONTMAN, fslot)
	var lane := tm.scheme.hold_of(fslot, false).y
	check(f.role_goal(Vector2(-40, 0), [], []).is_equal_approx(Vector2(1.0, lane)), "team 0 frontman holds x+1 at his lane")
	var f1 := _brain(1, Scheme.Role.FRONTMAN, fslot)
	check(f1.role_goal(Vector2(40, 0), [], []).is_equal_approx(Vector2(-1.0, -lane)), "team 1 is the point reflection")
	var cs := _brain(0, Scheme.Role.CENTER, _slot_of_role(tm, Scheme.Role.CENTER))
	var line := [_unit(Vector2(10, 0), Scheme.Role.FRONTMAN), _unit(Vector2(14, 5), Scheme.Role.FRONTMAN)]
	check(is_equal_approx(cs.role_goal(Vector2(-30, 0), line, []).x, -3.0), "center holds 9 m behind the frontman line (clamped to -3)")
	line = [_unit(Vector2(-20, 0), Scheme.Role.FRONTMAN)]
	check(is_equal_approx(cs.role_goal(Vector2(-30, 0), line, []).x, -29.0), "center follows the line back")
	var fx := _brain(0, Scheme.Role.FLEX, _slot_of_role(tm, Scheme.Role.FLEX))
	fx.flank_progress = 0.0
	check(fx.role_goal(Vector2(-40, 0), [], []).is_equal_approx(ArenaMap.world(0, ArenaMap.flank_point(0.0, fx.flank_right)) - Vector2(FpsRoleBrain.FLANK_LANE_TRAIL if fx.flank_lane > 0 else 0.0, 0.0)), "flex heads for the start of the flank route")
	fx.flank_progress = 1.0
	check(fx.role_goal(Vector2(-10, 20), [], [_unit(Vector2(5, 3))]).is_equal_approx(Vector2(5, 3)), "flanked flex collapses on the nearest enemy")


func test_flank_progress_advances() -> void:
	var tm := _team(1, 10, 70)
	var fx := _brain(0, Scheme.Role.FLEX, _slot_of_role(tm, Scheme.Role.FLEX))
	var t := 0.0
	while fx.flank_progress < 1.0 and t < 60.0:
		fx.advance(0.1)
		t += 0.1
	check(fx.flank_progress >= 1.0 and t > 6.0 and t < 25.0, "flank completes in roughly 10 s (%.1f s)" % t)


func test_koth_goals_and_goes_point() -> void:
	var tm := _team(1, 10, 70)
	var c := _brain(0, Scheme.Role.CENTER, _slot_of_role(tm, Scheme.Role.CENTER), true)
	c.reset_life()
	check(c.goes_point and ArenaMap.HILL.has_point(c.hill_spot), "KOTH center goes to a spot on the hill")
	var field := ArenaMap.legacy()
	field.ensure_built()
	var g := c.goal(Vector2(-10, 0), field, [], [])
	check(g == c.hill_spot and c.posture == FpsRoleBrain.POSTURE_POINT, "near the hill a goer stands on his spot")
	var f := _brain(0, Scheme.Role.FRONTMAN, _slot_of_role(tm, Scheme.Role.FRONTMAN), true)
	check(not f.goes_point, "frontman starts off the point")
	check(absf(f.role_goal(Vector2(-30, 0), [], []).x - 7.0) < 0.001, "KOTH frontman sits in front of the point")
	# Nobody on the point: a frontman eventually steps in.
	var got := false
	for i in 200:
		f.point_decisions(Vector2(0, 8), 100.0, [{"pos": Vector2(0, 8), "alive": true, "role": Scheme.Role.FRONTMAN, "goes": false, "hp": 100.0, "self": true}], [])
		if f.goes_point:
			got = true
			break
	check(got, "frontman takes an empty point")


func test_hunting_after_lull_and_contact_memory() -> void:
	var tm := _team(1, 10, 70)
	var f := _brain(0, Scheme.Role.FRONTMAN, _slot_of_role(tm, Scheme.Role.FRONTMAN))
	var field := ArenaMap.legacy()
	field.ensure_built()
	var enemy := [_unit(Vector2(30, 5))]
	f.tick = 100
	f.last_contact_tick = 100
	f.note_visible(Vector2(20, 0))
	f.tick = 100 + FpsRoleBrain.CONTACT_MEMORY
	f.goal(Vector2(5, 0), field, [], enemy)
	check(f.threat_pos != Vector2.INF and not f.hunting, "contact is remembered for 8 s")
	f.tick = 100 + FpsRoleBrain.CONTACT_MEMORY + 1
	var want := f.goal(Vector2(1, 0), field, [], enemy)
	check(not f.hunting, "just after the memory lapses he has not started hunting yet")
	f.tick += 80
	want = f.goal(Vector2(1, 0), field, [], enemy)
	check(f.hunting and want.is_equal_approx(Vector2(30, 5)), "a long lull sends him hunting the nearest enemy")


func test_peek_duck_rhythm_and_bounding() -> void:
	var tm := _team(1, 10, 90)
	var field := ArenaMap.legacy()
	field.ensure_built()
	var f := _brain(0, Scheme.Role.FRONTMAN, _slot_of_role(tm, Scheme.Role.FRONTMAN), false, 90)
	var spot: Vector2 = field.cover_spots[0]
	f.cover_spot = spot
	f.threat_pos = Vector2(-spot.x, -spot.y)
	f.peeking = true
	f.phase_end = 0
	var seen_peek := false
	var seen_duck := false
	var bounded := false
	for i in 80:
		f.tick += 1
		f.threat_tick = f.tick
		f.goal(spot, field, [], [_unit(f.threat_pos)])
		if f.posture == FpsRoleBrain.POSTURE_PEEK:
			seen_peek = true
		elif f.posture == FpsRoleBrain.POSTURE_DUCK:
			seen_duck = true
			check(f.ducked(spot), "ducked posture means ducked()")
		elif f.posture == FpsRoleBrain.POSTURE_BOUND:
			bounded = true
			break
	check(seen_peek and seen_duck, "in cover he alternates peek and duck")
	# Reloading forces a duck.
	f.cover_spot = spot
	f.peeking = true
	f.phase_end = 0
	f.tick += 1
	f.threat_tick = f.tick
	f.goal(spot, field, [], [_unit(f.threat_pos)], true)
	check(f.ducked(spot), "reloading ducks")
	# A pre-planning soldier far from the line picks a cover spot on the way when he knows where the enemy is.
	var p := _brain(0, Scheme.Role.FRONTMAN, _slot_of_role(tm, Scheme.Role.FRONTMAN), false, 99)
	p.note_visible(Vector2(10, 0))
	var found := false
	for i in 40:
		p.tick += 3
		p.threat_tick = p.tick
		p.goal(Vector2(-30, 0), field, [], [_unit(Vector2(10, 0))])
		if p.cover_spot != Vector2.INF:
			found = true
			check(p.posture == FpsRoleBrain.POSTURE_BOUND, "moving to planned cover is bounding")
			break
	check(found, "a high-awareness soldier plans a cover spot toward his goal")


# --- bots on a box scene ---

func _scene(field: ArenaMap, mode: StringName, v := 70) -> FakeWorld:
	var w := FakeWorld.new()
	w.field = field
	w.mode = mode
	root.add_child(w)
	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(ArenaMap.HALF.x * 2.0 + 4.0, 1.0, ArenaMap.HALF.y * 2.0 + 4.0)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position.y = -0.5
	w.add_child(floor_body)
	var rects: Array = []
	for r in field.walls:
		rects.append([r, 3.0])
	for r in field.crates:
		rects.append([r, 1.2])
	for e in rects:
		var r: Rect2 = e[0]
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(r.size.x, e[1], r.size.y)
		cs.shape = bs
		body.add_child(cs)
		body.position = Vector3(r.get_center().x, e[1] * 0.5, r.get_center().y)
		w.add_child(body)
	w.teams = [_team(1, 100, v), _team(2, 200, v)]
	for t in 2:
		for s: Soldier in w.teams[t].starters():
			var slot: StringName = w.teams[t].slot_of(s)
			var bot := FpsBot.new()
			bot.world = w
			w.add_child(bot)
			bot.setup(s, t, Scheme.SLOT_ROLES.get(slot, Scheme.Role.FLEX))
			bot.slot = slot
			var sp := ArenaMap.world(t, w.teams[t].scheme.spawn_of(slot))
			bot.global_position = Vector3(sp.x, 0.1, sp.y)
			bot.rotation.y = -PI * 0.5 if t == 0 else PI * 0.5
			w.bots[t].append(bot)
	return w


func _run_frames(n: int) -> void:
	for i in n:
		await physics_frame


func test_spawn_zone_safety() -> void:
	var w := _scene(ArenaMap.legacy(), &"tdm")
	await _run_frames(3)
	var b: FpsBot = w.bots[0][0]
	check(ArenaMap.in_spawn_zone(0, Vector2(b.global_position.x, b.global_position.z)), "bot spawns in his zone")
	b.take_damage(50.0, {})
	check(is_equal_approx(b.health, 100.0), "no damage in the spawn zone")
	b.global_position = Vector3(0, 0.1, 0)
	b.take_damage(10.0, {})
	check(b.health < 100.0, "damage outside the zone lands")
	w.queue_free()


func test_tdm_roles_in_3d() -> void:
	var w := _scene(ArenaMap.legacy(), &"tdm")
	for t in 2:
		for b: FpsBot in w.bots[t]:
			b.weapon.set("infinite_reserve", true)
	Engine.time_scale = 4.0
	var flex_max_z := 0.0
	var front_min_d := INF
	var center_far := 0.0
	var kills := 0
	var frames := 0
	var f_x := 0.0
	var c_x := 0.0
	var f_n := 0
	var c_n := 0
	for i in 1500:
		await physics_frame
		frames += 1
		for t in 2:
			for b: FpsBot in w.bots[t]:
				if not b.alive:
					continue
				if b.role == Scheme.Role.FLEX:
					flex_max_z = maxf(flex_max_z, absf(b.global_position.z))
		if frames > 30 and frames < 400 and frames % 10 == 0:
			for b: FpsBot in w.bots[0]:
				if not b.alive:
					continue
				if b.role == Scheme.Role.FRONTMAN:
					f_x += b.global_position.x
					f_n += 1
				elif b.role == Scheme.Role.CENTER:
					c_x += b.global_position.x
					c_n += 1
	Engine.time_scale = 1.0
	var alive_total := 0
	var moved := 0
	for t in 2:
		for b: FpsBot in w.bots[t]:
			if b.alive:
				alive_total += 1
			var sp: Vector2 = ArenaMap.world(t, w.teams[t].scheme.spawn_of(b.slot))
			if Vector2(b.global_position.x, b.global_position.z).distance_to(sp) > 6.0:
				moved += 1
	print("    flex max |z| %.1f, moved %d, alive %d, frontman mean x %.1f (n %d), center mean x %.1f (n %d)" % [flex_max_z, moved, alive_total, f_x / maxi(f_n, 1), f_n, c_x / maxi(c_n, 1), c_n])
	check(f_n > 0 and c_n > 0 and c_x / c_n < f_x / f_n, "centers hold behind the frontmen")
	check(moved >= 6, "most bots left their spawn (%d)" % moved)
	check(flex_max_z > 12.0, "flexes ran wide along the flank route (max |z| %.1f)" % flex_max_z)
	w.queue_free()


func test_koth_center_goes_to_hill() -> void:
	var w := _scene(ArenaMap.legacy(), MatchEngine.MODE_KOTH)
	Engine.time_scale = 4.0
	var on_hill := 0
	for i in 1200:
		await physics_frame
	for b: FpsBot in w.bots[0]:
		if b.role == Scheme.Role.CENTER and b.alive and ArenaMap.HILL.grow(3.0).has_point(Vector2(b.global_position.x, b.global_position.z)):
			on_hill += 1
	Engine.time_scale = 1.0
	check(on_hill >= 1 or w.bots[0].any(func(b): return b.role == Scheme.Role.CENTER and not b.alive), "a KOTH center reached the hill (%d)" % on_hill)
	w.queue_free()


func test_duck_lowers_the_bot() -> void:
	var w := _scene(ArenaMap.legacy(), &"tdm")
	await _run_frames(2)
	var b: FpsBot = w.bots[0][0]
	var h0 := b.eye_pos().y - b.global_position.y
	b._set_crouch(true)
	var h1 := b.eye_pos().y - b.global_position.y
	check(h1 < h0 and h1 < 1.1, "crouched head is below hip-high cover (%.2f)" % h1)
	b._set_crouch(false)
	check(is_equal_approx(b.eye_pos().y - b.global_position.y, h0), "standing again restores the eye height")
	w.queue_free()

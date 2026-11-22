extends SceneTree
## FpsArena: every home field builds in 3D (props, nav mesh, hill rect, spawns) and a bot-sized capsule can
## walk from a spawn to the hill centre by following ArenaMap.next_waypoint.
## Run: godot --headless --path . --script tests/fps_arena_tests.gd

var _failures := 0
var _passes := 0
var _current := ""


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


func _arena(f: ArenaMap) -> FpsArena:
	var a := FpsArena.make(f)
	root.add_child(a)
	return a


func _free(a: Node) -> void:
	root.remove_child(a)
	a.free()


func test_hill_rect() -> void:
	FpsHill.clear()
	FpsHill.set_zone(Vector3(10, 0, 0), 3.0)
	check(FpsHill.on_hill(Vector3(11, 0, 0)), "circle on")
	check(not FpsHill.on_hill(Vector3(14, 0, 0)), "circle off")
	FpsHill.set_rect(ArenaMap.HILL)
	check(FpsHill.on_hill(Vector3(4.5, 0, -4.5)), "square corner on")
	check(not FpsHill.on_hill(Vector3(5.5, 0, 0)), "square outside off")
	check(FpsHill.center.is_zero_approx(), "rect centre at origin")
	FpsHill.clear()
	check(not FpsHill.on_hill(Vector3.ZERO), "clear resets")
	FpsHill.set_zone(Vector3.ZERO, 3.0)
	check(not FpsHill.use_rect and FpsHill.on_hill(Vector3(2, 0, 0)), "set_zone after rect is a circle again")
	FpsHill.clear()


func test_helpers() -> void:
	check(FpsArena.to3(Vector2(3, 4), 1.5) == Vector3(3, 1.5, 4), "to3")
	check(FpsArena.to2(Vector3(3, 9, 4)) == Vector2(3, 4), "to2")
	var a := _arena(ArenaMap.legacy())
	check(absf(a.spawn_facing_yaw(0) - (-PI * 0.5)) < 0.001 and absf(a.spawn_facing_yaw(1) - PI * 0.5) < 0.001, "facing")
	var fwd := Basis(Vector3.UP, a.spawn_facing_yaw(0)) * Vector3.FORWARD
	check(fwd.x > 0.99, "team 0 looks +x")
	check(a.hill_rect() == ArenaMap.HILL and a.hill_center().is_zero_approx(), "hill rect/centre")
	check(a.in_spawn_zone(0, Vector3(-40, 0, 0)) and not a.in_spawn_zone(0, Vector3(40, 0, 0)), "spawn zone team 0")
	check(a.in_spawn_zone(1, Vector3(40, 0, 3)), "spawn zone team 1")
	_free(a)


func test_every_field_builds() -> void:
	var abbrevs: Array = ArenaMap.authored()
	check(abbrevs.size() > 0, "authored fields exist")
	for ab in abbrevs:
		var f := ArenaMap.for_team(ab)
		var a := _arena(f)
		var bodies := 0
		for n in a.nav_region.get_children():
			if n is StaticBody3D:
				bodies += 1
		var solid := 0
		for p in f.props:
			if not (ArenaMap.KINDS[p["k"]] as Dictionary).is_empty():
				solid += 1
		check(bodies == solid + 5, "%s prop bodies %d vs %d solid + floor + 4 walls" % [ab, bodies, solid])
		check(a.nav_region.navigation_mesh.get_polygon_count() > 0, "%s nav mesh baked" % ab)
		check(a.cover_points().size() == f.cover_spots.size(), "%s cover points" % ab)
		_free(a)


func test_spawns_valid_for_every_scheme() -> void:
	for ab in ArenaMap.authored():
		var f := ArenaMap.for_team(ab)
		var a := _arena(f)
		for sid in Scheme.IDS:
			var sc := Scheme.by_id(sid)
			for s in sc.slots:
				for team in 2:
					var v := a.spawn_point(team, sc, s["id"])
					var p := FpsArena.to2(v)
					check(ArenaMap.in_bounds(p), "%s %s %s t%d out of bounds" % [ab, sid, s["id"], team])
					check(not f.blocked(p), "%s %s %s t%d spawn in obstacle" % [ab, sid, s["id"], team])
					check(a.in_spawn_zone(team, v), "%s %s %s t%d spawn not in own zone" % [ab, sid, s["id"], team])
					check(is_equal_approx(v.y, 0.1), "spawn y")
		_free(a)


func test_walk_spawn_to_hill() -> void:
	var tried := 0
	var ok := 0
	for ab in ArenaMap.authored():
		if tried >= 4:
			break
		tried += 1
		var f := ArenaMap.for_team(ab)
		var a := _arena(f)
		var sc := Scheme.power_front()
		for slot in [&"CTR", &"LFX"]:
			var team := 0 if slot == &"CTR" else 1
			if await _walk(a, f, a.spawn_point(team, sc, slot)):
				ok += 1
			else:
				check(false, "%s %s could not reach the hill" % [ab, slot])
		_free(a)
	check(ok == tried * 2, "all walks reached (%d/%d)" % [ok, tried * 2])


func _walk(a: FpsArena, f: ArenaMap, start: Vector3) -> bool:
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.35
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	a.add_child(body)
	body.global_position = start
	var goal := a.hill_center()
	var reached := false
	for i in 1500:
		await physics_frame
		var here := FpsArena.to2(body.global_position)
		if here.distance_to(FpsArena.to2(goal)) < 1.5:
			reached = true
			break
		var wp := f.next_waypoint(here, FpsArena.to2(goal))
		var dir := (wp - here).normalized()
		body.velocity = Vector3(dir.x, 0, dir.y) * 7.0 + Vector3(0, -2.0, 0)
		body.move_and_slide()
	body.queue_free()
	return reached

extends SceneTree
## FPS core tests: stat mapping, damage and headshot rules, ammo/reload, FpsTarget knock-down,
## and one real raycast scene test.
## Run: godot --headless --path . --script tests/fps_core_tests.gd   (ONLY=test_a,test_b for a subset)

var _failures := 0
var _passes := 0
var _current := ""


func _init() -> void:
	_run()


func _run() -> void:
	var tests: Array = []
	for method in get_method_list():
		if String(method["name"]).begins_with("test_"):
			tests.append(String(method["name"]))
	var only := OS.get_environment("ONLY")
	if only != "":
		tests = tests.filter(func(x): return only.split(",").has(x))
	for t in tests:
		_current = t
		var before := _failures
		await call(t)
		print("  %s  %s" % ["PASS" if _failures == before else "FAIL", t])
		if _failures == before:
			_passes += 1
	print("\n%d passed, %d failed" % [_passes, tests.size() - _passes])
	quit(0 if _passes == tests.size() else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("    [%s] %s" % [_current, msg])


func _stats(v: int) -> Dictionary:
	var d := {}
	for s in Stats.ALL:
		d[s] = v
	return d


# ------------------------------------------------------------ stat mapping

func test_accuracy_lowers_spread_in_every_band() -> void:
	var def := FpsWeaponDefs.get_def(&"rifle")
	for dist in [5.0, 20.0, 60.0]:
		var lo := FpsWeapon.compute_spread(def, _stats(30), dist)
		var hi := FpsWeapon.compute_spread(def, _stats(90), dist)
		check(hi < lo, "high acc should tighten spread at %s m (%f vs %f)" % [dist, hi, lo])


func test_band_uses_matching_stat() -> void:
	var def := FpsWeaponDefs.get_def(&"rifle")
	var s := _stats(50)
	s[Stats.SHORT_ACC] = 99
	check(FpsWeapon.base_spread(def, s, 5.0) < FpsWeapon.base_spread(def, _stats(50), 5.0), "short acc helps short")
	check(is_equal_approx(FpsWeapon.base_spread(def, s, 20.0), FpsWeapon.base_spread(def, _stats(50), 20.0)),
		"short acc does not help medium")
	check(is_equal_approx(FpsWeapon.base_spread(def, s, 60.0), FpsWeapon.base_spread(def, _stats(50), 60.0)),
		"short acc does not help long")


func test_grouping_and_sway_mapping() -> void:
	var g_lo := {Stats.GROUPING: 20}
	var g_hi := {Stats.GROUPING: 90}
	check(FpsWeapon.recoil_control(g_hi) < FpsWeapon.recoil_control(g_lo), "grouping lowers recoil")
	var def := FpsWeaponDefs.get_def(&"rifle")
	check(FpsWeapon.sway_amplitude(def, {Stats.SWAY: 90}) < FpsWeapon.sway_amplitude(def, {Stats.SWAY: 20}), "sway rating lowers sway")
	var moving_lo := FpsWeapon.compute_spread(def, {Stats.SWAY: 20}, 20.0, 0.0, 1.0)
	var moving_hi := FpsWeapon.compute_spread(def, {Stats.SWAY: 90}, 20.0, 0.0, 1.0)
	check(moving_hi < moving_lo, "sway rating cuts accuracy lost on the move")


func test_reload_rating_shortens_reload() -> void:
	var def := FpsWeaponDefs.get_def(&"rifle")
	check(FpsWeapon.reload_time(def, {Stats.RELOAD: 90}) < FpsWeapon.reload_time(def, {Stats.RELOAD: 20}), "reload time")


func test_endurance_gives_more_stamina() -> void:
	var lo := FpsPlayer.derive_movement({Stats.ENDURANCE: 20})
	var hi := FpsPlayer.derive_movement({Stats.ENDURANCE: 90})
	check(hi["stamina_max"] > lo["stamina_max"], "stamina size")
	check(hi["stamina_regen"] > lo["stamina_regen"], "stamina recovery")


func test_speed_and_agility_mapping() -> void:
	var slow := FpsPlayer.derive_movement({Stats.SPEED: 20, Stats.AGILITY: 20})
	var fast := FpsPlayer.derive_movement({Stats.SPEED: 90, Stats.AGILITY: 90})
	check(fast["walk_speed"] > slow["walk_speed"], "speed")
	check(fast["sprint_speed"] > fast["walk_speed"], "sprint faster than walk")
	check(fast["crouch_speed"] < fast["walk_speed"], "crouch slower than walk")
	check(fast["accel"] > slow["accel"], "agility accel")


func test_stamina_drains_sprinting_and_recovers() -> void:
	var mv := FpsPlayer.derive_movement({})
	var s: float = mv["stamina_max"]
	var st := {"stamina": s, "locked": false, "delay": 0.0}
	for i in 60:
		st = FpsPlayer.step_stamina(st["stamina"], mv, true, st["locked"], st["delay"], 0.1)
	check(st["stamina"] < s, "drains while sprinting")
	check(st["stamina"] == 0.0 and st["locked"], "runs dry and locks sprint")
	for i in 100:
		st = FpsPlayer.step_stamina(st["stamina"], mv, false, st["locked"], st["delay"], 0.1)
	check(st["stamina"] > 0.0 and not st["locked"], "recovers and unlocks")


func test_setup_applies_soldier_stats() -> void:
	var p := FpsPlayer.new()
	var a := Soldier.new()
	a.stats = _stats(90)
	var b := Soldier.new()
	b.stats = _stats(20)
	p.setup(a)
	var hi_stamina: float = p.move["stamina_max"]
	p.setup(b)
	check(hi_stamina > float(p.move["stamina_max"]), "setup maps endurance into stamina")
	check(is_equal_approx(p.stamina, p.move["stamina_max"]), "stamina starts full")
	p.free()


# ------------------------------------------------------------ damage rules

func test_damage_falloff_and_headshot() -> void:
	var def := FpsWeaponDefs.get_def(&"rifle")
	var body := FpsWeapon.final_damage(def, 5.0, false)
	var head := FpsWeapon.final_damage(def, 5.0, true)
	check(is_equal_approx(body, def["damage"]), "full damage up close")
	check(is_equal_approx(head, body * def["headshot_mult"]), "headshot multiplier")
	check(FpsWeapon.final_damage(def, 120.0, false) < body, "falloff at range")
	check(is_equal_approx(FpsWeapon.final_damage(def, 1000.0, false), body * def["min_damage_mult"]), "falloff floors")


func test_health_component() -> void:
	var h := FpsHealth.new(100.0)
	var log := []
	h.died.connect(func(src) -> void: log.append(src))
	check(is_equal_approx(h.take_damage(30.0, {}), 30.0), "applies damage")
	check(is_equal_approx(h.health, 70.0), "health drops")
	check(is_equal_approx(h.take_damage(500.0, {"source": "x"}), 70.0), "overkill capped")
	check(h.dead and log == ["x"], "died once with source")
	check(h.take_damage(10.0) == 0.0, "dead takes no more")
	h.reset()
	check(not h.dead and h.health == 100.0, "reset")
	h.free()


func test_headshot_detection_rules() -> void:
	var t := FpsTarget.new()
	check(t.is_in_group(&"damageable"), "target is damageable")
	check(FpsWeapon.is_headshot_hit(t, t, Vector3(0, 1.6, 0)), "above head height is a headshot")
	check(not FpsWeapon.is_headshot_hit(t, t, Vector3(0, 0.8, 0)), "body is not")
	var n := Node3D.new()
	n.set_meta(&"headshot", true)
	check(FpsWeapon.is_headshot_hit(n, null, Vector3.ZERO), "headshot meta marks a head hitbox")
	t.free()
	n.free()


# ------------------------------------------------------------ ammo and reload

func test_ammo_and_reload() -> void:
	var w := FpsWeapon.new()
	w.setup(null, _stats(50))
	w.equip(&"rifle")
	var mag: int = w.def["mag_size"]
	check(w.ammo == mag, "starts full")
	var r := w.try_fire()
	check(r["fired"] and w.ammo == mag - 1, "firing uses a round")
	check(not w.try_fire()["fired"], "cooldown blocks the next shot")
	w.tick(1.0)
	check(w.try_fire()["fired"], "fires again after cooldown")
	check(w.reload(), "reload starts")
	check(not w.try_fire()["fired"], "cannot fire while reloading")
	var before_reserve := w.reserve
	w.tick(w.reload_duration() + 0.01)
	check(w.ammo == mag, "magazine refilled")
	check(w.reserve == before_reserve - 2, "reserve pays for it")
	check(not w.reload(), "full magazine does not reload")
	w.free()


func test_empty_weapon_and_auto_reload() -> void:
	var w := FpsWeapon.new()
	w.setup(null, _stats(50))
	w.equip(&"marksman")
	w.ammo = 0
	check(not w.try_fire()["fired"], "empty does not fire")
	check(w.reloading, "empty trigger pull starts a reload")
	w.free()


func test_no_reserve_blocks_reload() -> void:
	var w := FpsWeapon.new()
	w.setup(null, _stats(50))
	w.reserve = 0
	w.ammo = 3
	check(not w.reload(), "no reserve, no reload")
	w.infinite_reserve = true
	check(w.reload(), "infinite reserve reloads")
	w.free()


func test_fire_modes() -> void:
	var w := FpsWeapon.new()
	w.setup(null, _stats(50))
	w.equip(&"rifle")
	w.fire_mode = &"semi"
	w.set_trigger(true)
	for i in 30:
		w.tick(0.05)
	check(w.ammo == int(w.def["mag_size"]) - 1, "semi fires once per press")
	w.set_trigger(false)
	w.equip(&"rifle")
	w.fire_mode = &"auto"
	w.set_trigger(true)
	for i in 10:
		w.tick(0.05)
	check(w.ammo < int(w.def["mag_size"]) - 3, "auto keeps firing while held")
	w.set_trigger(false)
	w.equip(&"rifle")
	w.fire_mode = &"burst"
	w.set_trigger(true)
	for i in 40:
		w.tick(0.05)
	check(w.ammo == int(w.def["mag_size"]) - 3, "burst fires exactly a burst per press (ammo %d)" % w.ammo)
	w.free()


func test_recoil_kicks_and_recovers_bloom_builds() -> void:
	var w := FpsWeapon.new()
	w.setup(null, _stats(50))
	w.equip(&"rifle")
	w.try_fire()
	check(w.recoil.x > 0.0, "kick up")
	check(w.bloom > 0.0, "bloom grows")
	var spread_after := w.current_spread()
	for i in 100:
		w.tick(0.1)
	check(w.recoil.length() < 0.001, "recoil recovers")
	check(w.bloom == 0.0, "bloom recovers")
	check(w.current_spread() < spread_after, "spread tightens again")
	w.free()


func test_grouping_reduces_kick() -> void:
	var a := FpsWeapon.new()
	a.setup(null, {Stats.GROUPING: 90})
	var b := FpsWeapon.new()
	b.setup(null, {Stats.GROUPING: 20})
	a.try_fire()
	b.try_fire()
	check(a.recoil.x < b.recoil.x, "better grouping, smaller kick")
	check(a.bloom < b.bloom, "better grouping, less bloom")
	a.free()
	b.free()


func test_weapon_defs_complete() -> void:
	for id in [&"rifle", &"smg", &"marksman"]:
		check(FpsWeaponDefs.DEFS.has(id), "def %s exists" % id)
	for id in FpsWeaponDefs.ids():
		var d: Dictionary = FpsWeaponDefs.DEFS[id]
		for k in ["damage", "rpm", "mag_size", "reload_time", "spread_short", "spread_medium", "spread_long", "mode"]:
			check(d.has(k), "%s has %s" % [id, k])


# ------------------------------------------------------------ FpsTarget

func test_target_knockdown() -> void:
	var t := FpsTarget.new()
	var hits := []
	var downs := [0]
	t.hit.connect(func(hs: bool) -> void: hits.append(hs))
	t.knocked_down.connect(func() -> void: downs[0] += 1)
	check(t.up, "starts up")
	t.take_damage(40.0, {"headshot": false})
	t.take_damage(40.0, {"headshot": true})
	check(hits == [false, true], "hit signal carries headshot flag")
	check(t.up and downs[0] == 0, "still up with health left")
	t.take_damage(40.0, {})
	check(not t.up and downs[0] == 1, "knocked down at zero")
	check(t.take_damage(50.0, {}) == 0.0, "down target ignores damage")
	check(t.collision_layer == 0, "down target is not hittable")
	t.pop_up()
	check(t.up and t.health == t.max_health and t.collision_layer != 0, "pop_up resets")
	t.free()


# ------------------------------------------------------------ real raycast

func test_raycast_hits_target_and_headshot() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var t := FpsTarget.new()
	root.add_child(t)
	t.position = Vector3(0, 0, -10)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 0.7, 0)
	var w := FpsWeapon.new()
	root.add_child(w)
	w.setup(cam, _stats(99))
	w.seed_rng(1)
	await physics_frame
	await physics_frame
	var down_hits := []
	t.hit.connect(func(hs: bool) -> void: down_hits.append(hs))
	var r := w.try_fire()
	check(r["fired"] and r["hit"], "aimed shot hits the target")
	check(r["collider"] == t and r["target"] == t, "reports collider")
	check(absf(r["distance"] - 10.0) < 0.5, "distance about 10 m (%f)" % r["distance"])
	check(not r["headshot"] and is_equal_approx(r["damage"], FpsWeapon.final_damage(w.def, r["distance"], false)), "body shot damage")
	check(t.health < t.max_health, "target took damage")
	w.tick(1.0)
	cam.position = Vector3(0, 1.62, 0)
	var rh := w.try_fire()
	check(rh["hit"] and rh["headshot"], "aimed at head is a headshot")
	check(down_hits == [false, true], "target saw body then headshot")
	# miss: aim away
	w.tick(1.0)
	cam.rotation.y = PI * 0.5
	var rm := w.try_fire()
	check(rm["fired"] and not rm["hit"], "miss reports no hit")
	root.queue_free()
	await process_frame


func test_player_takes_damage_and_dies() -> void:
	var p := FpsPlayer.new()
	var log := []
	p.damaged.connect(func(a: float, _s) -> void: log.append(a))
	p.died.connect(func(s) -> void: log.append(s))
	p.health = 100.0
	p.take_damage(30.0, {"source": "bot"})
	check(is_equal_approx(p.health, 70.0), "player health drops")
	p.weapon = FpsWeapon.new()
	p.take_damage(100.0, {"source": "bot"})
	check(p.dead and log == [30.0, 70.0, "bot"], "died signal fires once with source: %s" % [log])
	p.weapon.free()
	p.free()


func test_hud_spread_math() -> void:
	var a := FpsHud.spread_to_pixels(1.0, 80.0, 900.0)
	var b := FpsHud.spread_to_pixels(3.0, 80.0, 900.0)
	check(b > a and a > 0.0, "crosshair widens with spread")

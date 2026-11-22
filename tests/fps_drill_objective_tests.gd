extends SceneTree
## Objective drills (door breach, hill defense): scoring rules, economy, enemy path, scripted runs, finishing once.
## Run: godot --headless --path . --script res://tests/fps_drill_objective_tests.gd

var _failures := 0
var _passes := 0
var _current := ""
var _done_scores: Array = []


func _init() -> void:
	var tests: Array = []
	for method in get_method_list():
		if String(method["name"]).begins_with("test_"):
			tests.append(String(method["name"]))
	for t in tests:
		_current = t
		var before := _failures
		call(t)
		if _failures == before:
			_passes += 1
			print("ok   ", t)
		else:
			print("FAIL ", t)
	print("%d passed, %d failed" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("  [%s] %s" % [_current, msg])


func _record(score: float) -> void:
	_done_scores.append(score)


func _started(d: FpsDrill, seed_value: int = 42) -> void:
	_done_scores.clear()
	d.finished.connect(_record)
	d.start(null, seed_value)
	d.advance(FpsDrill.COUNTDOWN_SECS + 0.01)


## Step a breach drill until the bar sits `offset` away from the window centre, then breach.
func _breach_at(d: FpsBreachDrill, offset: float) -> float:
	for i in 100000:
		if absf(d.phase() - (d.window_center() + offset)) < 0.004:
			return d.breach()
		d.advance(0.005)
	return -1.0


## Knock down every target as it stands up, with a shot each.
func _clear_room(d: FpsBreachDrill, limit_s: float) -> void:
	var t := 0.0
	while d.state == FpsDrill.State.RUNNING and t < limit_s:
		d.advance(0.05)
		t += 0.05
		for tg in d.targets:
			if tg.up:
				d._on_shot_fired({})
				tg.take_damage(1.0, {})


# ---- breach ------------------------------------------------------------------------------------------------------------

func test_breach_metadata() -> void:
	var d := FpsBreachDrill.new()
	check(d.stat == Stats.BREACH and d.title != "" and d.instructions != "" and d.lock_player, "stat, title, locked")
	check(FpsDrill.standard_stats(d.loadout)[Stats.SHORT_ACC] == 99 and FpsDrill.standard_stats(d.loadout)[Stats.SPEED] == 50, "standard loadout")
	check((load("res://scenes/fps/drills/breach.tscn") as PackedScene).instantiate() is FpsBreachDrill, "scene instantiates")
	check((load("res://scenes/fps/drills/defense.tscn") as PackedScene).instantiate() is FpsDefenseDrill, "defense scene instantiates")
	d.free()


func test_timing_value() -> void:
	var z := FpsBreachDrill.ZONE
	check(FpsBreachDrill.timing_value(0.0, z) == 1.0, "dead centre")
	check(is_equal_approx(FpsBreachDrill.timing_value(z / 2.0, z), 0.75), "edge of the window")
	check(FpsBreachDrill.timing_value(0.02, z) > FpsBreachDrill.timing_value(0.06, z), "closer is better")
	check(FpsBreachDrill.timing_value(0.06, z) > FpsBreachDrill.timing_value(0.3, z), "outside the window falls off")
	check(FpsBreachDrill.timing_value(0.9, z) == 0.0, "far away is nothing")
	check(FpsBreachDrill.timing_value(-0.03, z) == FpsBreachDrill.timing_value(0.03, z), "symmetric")


func test_clear_score() -> void:
	var n := FpsBreachDrill.ROOM_TARGETS
	var best := FpsBreachDrill.clear_score(n, n, n, 2.0)
	check(best > 0.99, "all hit, clean and fast")
	check(FpsBreachDrill.clear_score(n, n, n, 9.0) < best, "slow costs")
	check(FpsBreachDrill.clear_score(n, n * 3, n, 2.0) < best, "spraying costs")
	check(FpsBreachDrill.clear_score(2, 2, n, 2.0) < best, "missed targets cost")
	check(FpsBreachDrill.clear_score(0, 5, n, 2.0) == 0.0 and FpsBreachDrill.clear_score(3, 3, 0, 1.0) == 0.0, "nothing")
	check(FpsBreachDrill.clear_score(99, 1, n, -5.0) <= 1.0, "clamped")
	check(FpsBreachDrill.combine(-1.0, 1.0) == 0.0, "never breached scores 0")
	check(FpsBreachDrill.combine(1.0, 1.0) == 1.0 and FpsBreachDrill.combine(0.0, 0.0) == 0.0, "combine bounds")


func test_breach_window_is_seeded() -> void:
	var a := FpsBreachDrill.new()
	var b := FpsBreachDrill.new()
	a.start(null, 5)
	b.start(null, 5)
	a.advance(3.5)
	b.advance(3.5)
	check(is_equal_approx(a.window_center(), b.window_center()), "same seed, same window")
	a.advance(CYCLE_PROBE)
	check(a.window_center() >= 0.35 and a.window_center() <= 0.85, "window inside the bar")
	a.free()
	b.free()


const CYCLE_PROBE := 2.0


func test_breach_ignored_when_not_running() -> void:
	var d := FpsBreachDrill.new()
	check(d.breach() == -1.0, "idle breach ignored")
	d.start(null, 1)
	check(d.breach() == -1.0 and not d.breached, "countdown breach ignored")
	d.advance(FpsDrill.COUNTDOWN_SECS + 0.01)
	var v := d.breach()
	check(v >= 0.0 and d.breached, "breach while running")
	check(d.breach() == -1.0, "second breach ignored")
	d.free()


func test_good_breach_run_scores_high() -> void:
	var d := FpsBreachDrill.new()
	_started(d)
	check(_breach_at(d, 0.0) > 0.95, "centred breach is near perfect")
	check(d._door.collision_layer == 0, "door open")
	_clear_room(d, 20.0)
	check(_done_scores.size() == 1, "finished once, got %d" % _done_scores.size())
	check(_done_scores[0] > 0.85, "good run scores high: %f" % _done_scores[0])
	check(d.hits == FpsBreachDrill.ROOM_TARGETS, "hit every target")
	d.free()


func test_bad_timing_and_slow_clear_score_lower() -> void:
	var good := FpsBreachDrill.new()
	_started(good)
	_breach_at(good, 0.0)
	_clear_room(good, 20.0)
	var good_score: float = _done_scores[0]
	var sloppy := FpsBreachDrill.new()
	_started(sloppy)
	var v := _breach_at(sloppy, 0.25)
	check(v < 0.5, "late breach is poor, got %f" % v)
	_clear_room(sloppy, 20.0)
	check(_done_scores[0] < good_score, "sloppy timing scores lower")
	good.free()
	sloppy.free()


func test_no_input_breach_scores_zero_and_finishes_once() -> void:
	var d := FpsBreachDrill.new()
	_started(d)
	for i in 4000:
		d.advance(0.05)
	check(_done_scores.size() == 1 and _done_scores[0] == 0.0, "no input scores 0 and finishes once")
	d.finish(9.0)
	d.abort()
	check(_done_scores.size() == 1 and d.score == 0.0, "finish after done ignored")
	d.free()


func test_breach_without_clearing_is_low() -> void:
	var d := FpsBreachDrill.new()
	_started(d)
	_breach_at(d, 0.0)
	for i in 4000:
		d.advance(0.05)
	check(_done_scores.size() == 1 and _done_scores[0] <= FpsBreachDrill.W_TIMING + 0.001, "timing alone is capped: %f" % _done_scores[0])
	check(_done_scores[0] >= 0.0 and _done_scores[0] <= 1.0, "clamped")
	d.free()


# ---- defense -----------------------------------------------------------------------------------------------------------

func test_defense_metadata_and_spawns() -> void:
	var d := FpsDefenseDrill.new()
	check(d.stat == Stats.OBJ_IQ and d.title != "" and d.instructions != "", "stat and title")
	check(d.spawns.size() == FpsDefenseDrill.WAVES * FpsDefenseDrill.PER_WAVE and d.total_enemies == d.spawns.size(), "spawn count")
	check(int(d.spawns[d.spawns.size() - 1]["hp"]) > int(d.spawns[0]["hp"]), "later waves have more hp")
	check(float(d.spawns[d.spawns.size() - 1]["speed"]) > float(d.spawns[0]["speed"]), "later waves are faster")
	check(d.pads.size() == 10 and d.paths.size() == 3, "layout: ten pads, three lanes")
	d.free()


func test_path_progress() -> void:
	var corners: Array = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, -10)]
	check(FpsDefenseDrill.path_length(corners) == 20.0, "length")
	check(FpsDefenseDrill.pos_at(corners, 0.0) == Vector3.ZERO, "start")
	check(FpsDefenseDrill.pos_at(corners, 5.0).is_equal_approx(Vector3(5, 0, 0)), "first leg")
	check(FpsDefenseDrill.pos_at(corners, 15.0).is_equal_approx(Vector3(10, 0, -5)), "second leg")
	check(FpsDefenseDrill.pos_at(corners, 99.0) == Vector3(10, 0, -10), "past the end clamps to the hill")
	check(FpsDefenseDrill.pos_at(corners, -3.0) == Vector3.ZERO, "before the start clamps")


func test_enemies_walk_the_path() -> void:
	var d := FpsDefenseDrill.new()
	_started(d)
	d.advance(2.0)
	check(d.enemies.size() >= 1, "an enemy spawned")
	var e: FpsDefenseDrill.Enemy = d.enemies[0]
	var d0 := e.d
	d.advance(1.0)
	check(e.d > d0 and absf((e.d - d0) - e.speed) < 0.2, "advances at its speed")
	var p := FpsDefenseDrill.pos_at(d.paths[e.lane], e.d)
	check(e.position.is_equal_approx(p + Vector3(0, 0.9, 0)), "body follows the path")
	d.free()


func test_defense_economy() -> void:
	var d := FpsDefenseDrill.new()
	check(not d.build_turret(0), "cannot build before the run")
	_started(d)
	check(d.coins == FpsDefenseDrill.START_COINS, "starting coins")
	check(d.build_turret(2) and d.coins == FpsDefenseDrill.START_COINS - FpsDefenseDrill.COST, "build costs coins")
	check(not d.build_turret(2), "pad already taken")
	check(d.turret_level(2) == 1, "level 1")
	check(d.upgrade_turret(2) and d.turret_level(2) == 2, "upgrade")
	check(d.coins == FpsDefenseDrill.START_COINS - FpsDefenseDrill.COST - FpsDefenseDrill.UPGRADE_COST, "upgrade costs coins")
	check(not d.upgrade_turret(5), "cannot upgrade an empty pad")
	check(not d.build_turret(99) and not d.build_turret(-1), "bad pad index")
	d.coins = 10
	check(not d.build_turret(4), "not enough coins left")
	d.coins = 500
	check(d.upgrade_turret(2) and not d.upgrade_turret(2) and d.turret_level(2) == FpsDefenseDrill.MAX_LEVEL, "max level")
	check(FpsDefenseDrill.turret_range(3) > FpsDefenseDrill.turret_range(1), "upgrades extend range")
	d.free()


func test_three_lanes_merge_on_the_hill() -> void:
	var d := FpsDefenseDrill.new()
	check(d.paths.size() == 3, "three lanes")
	var hill: Vector3 = d.paths[0][d.paths[0].size() - 1]
	var starts := {}
	for lane in d.paths:
		check((lane[lane.size() - 1] as Vector3).is_equal_approx(hill), "every lane ends on the hill")
		starts[(lane[0] as Vector3).x] = true
	check(starts.size() == 3, "three different spawn points")
	var used := {}
	for s in d.spawns:
		used[int(s["lane"])] = true
	check(used.size() == 3, "enemies come down every lane")
	d.free()


func test_kills_pay_bounty() -> void:
	var d := FpsDefenseDrill.new()
	_started(d)
	d.advance(2.0)
	var e: FpsDefenseDrill.Enemy = d.enemies[0]
	var before := d.coins
	check(not d.damage_enemy(e, 1), "first hit does not kill (hp 2)")
	check(d.damage_enemy(e, 5), "second kills")
	check(d.kills == 1 and d.coins == before + FpsDefenseDrill.BOUNTY, "bounty paid")
	check(not d.damage_enemy(e, 5) and d.kills == 1, "a dead enemy pays once")
	var e2: FpsDefenseDrill.Enemy = d.enemies[0] if not d.enemies.is_empty() else null
	if e2 != null:
		e2.take_damage(20.0, {"headshot": true})
		check(e2.hp == e2.max_hp - 2, "player headshot hits for 2")
	d.free()


func test_nearest_pad_and_interact() -> void:
	var d := FpsDefenseDrill.new()
	var pad_pos: Vector3 = d.pads[2]
	check(d.nearest_pad(pad_pos + Vector3(1, 0, 1)) == 2, "near a pad")
	check(d.nearest_pad(Vector3(0, 0, 40)) == -1, "far from every pad")
	var p := Node3D.new()
	d.start(p, 3)
	d.advance(FpsDrill.COUNTDOWN_SECS + 0.01)
	check(not d.interact(), "nothing near the spawn")
	p.position = pad_pos
	check(d.interact() and d.turret_level(2) == 1, "interact builds")
	check(d.interact() and d.turret_level(2) == 2, "interact again upgrades")
	d.free()


func test_turrets_shoot_enemies() -> void:
	var d := FpsDefenseDrill.new()
	_started(d)
	d.build_turret(2)
	d.build_turret(4)
	for i in 400:
		d.advance(0.05)
	check(d.kills > 0, "turrets killed something")
	d.free()


## A scripted good player: spends coins as soon as it can, best pads first.
func _play_greedy(d: FpsDefenseDrill, seconds: float) -> void:
	var order := [4, 2, 0, 5, 7, 6, 1, 3]
	var t := 0.0
	while d.state == FpsDrill.State.RUNNING and t < seconds:
		for pad in order:
			if d.turret_level(pad) == 0 and d.build_turret(pad):
				break
		for pad in order:
			if d.turret_level(pad) > 0 and d.upgrade_turret(pad):
				break
		d.advance(0.05)
		t += 0.05


func test_good_defense_beats_no_input() -> void:
	var good := FpsDefenseDrill.new()
	_started(good)
	_play_greedy(good, 200.0)
	check(_done_scores.size() == 1, "good run finished once")
	var good_score: float = _done_scores[0] if not _done_scores.is_empty() else -1.0
	check(good_score > 0.7, "good defense scores high: %f (kills %d / %d, hill %d)" % [good_score, good.kills, good.total_enemies, good.hill_hp])
	var idle := FpsDefenseDrill.new()
	_started(idle)
	for i in 6000:
		idle.advance(0.05)
	check(_done_scores.size() == 1, "idle run finished once")
	check(_done_scores[0] < 0.1, "no input scores low: %f" % _done_scores[0])
	check(idle.hill_hp <= 0, "the hill fell")
	idle.finish(5.0)
	idle.abort()
	check(_done_scores.size() == 1, "finish after done ignored")
	check(good_score > _done_scores[0] + 0.5, "good beats idle clearly")
	good.free()
	idle.free()


func test_defense_score_bounds() -> void:
	check(FpsDefenseDrill.defense_score(30, 30, 10, 10) == 1.0, "perfect")
	check(FpsDefenseDrill.defense_score(0, 30, 0, 10) == 0.0, "nothing")
	check(FpsDefenseDrill.defense_score(30, 30, 5, 10) < 1.0, "a damaged hill costs")
	check(FpsDefenseDrill.defense_score(15, 30, 0, 10) < FpsDefenseDrill.defense_score(15, 30, 3, 10), "a fallen hill caps the score")
	check(FpsDefenseDrill.defense_score(99, 30, 99, 10) <= 1.0 and FpsDefenseDrill.defense_score(-5, 30, -3, 10) >= 0.0, "clamped")
	check(FpsDefenseDrill.defense_score(5, 0, 5, 10) == 0.0, "no enemies")

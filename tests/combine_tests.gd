extends SceneTree
## Player mode phase 2 tests (the combine: tasks, bands, cap, talent roll, save):
##   godot --headless --path . --script res://tests/combine_tests.gd
## Exits with code 0 if all tests pass, 1 otherwise.

var _failures := 0
var _passes := 0
var _current := ""


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
			print("  PASS  ", t)
		else:
			print("  FAIL  ", t)
	print("\n%d passed, %d failed" % [_passes, tests.size() - _passes])
	quit(0 if _passes == tests.size() else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("    [%s] %s" % [_current, msg])


func _head() -> String:
	var heads: Array = FaceSpec.db()["heads"].keys()
	heads.sort()
	return heads[0]


func _scored(c: Combine, v: float) -> void:
	for g in Combine.DRILL_ORDER:
		var scores := {}
		for t in Combine.drill_tasks(g):
			scores[t["stat"]] = v
		c.record_try(g, scores)


func test_every_drilled_stat_has_exactly_one_task() -> void:
	var seen := {}
	for g in Combine.DRILL_ORDER:
		for t in Combine.drill_tasks(g):
			check(Stats.GROUPS[g].has(t["stat"]), "%s is not in group %s" % [t["stat"], g])
			check(not seen.has(t["stat"]), "%s has two tasks" % t["stat"])
			seen[t["stat"]] = true
			var task := CombineTasks.make(t)
			check(task != null and task.instructions() != "", "no task or no instructions for %s" % t["stat"])
			task.free()
	for stat in Stats.ALL:
		if not Archetypes.FIXED_STATS.has(stat):
			check(seen.has(stat), "%s has no combine task" % stat)


func test_tries_and_best_score() -> void:
	var c := Combine.make(&"sniper")
	var g: StringName = Stats.ACCURACY
	check(c.tries_left(g) == Combine.TRIES, "wrong tries at the start")
	check(c.record_try(g, {Stats.SHORT_ACC: 0.4, Stats.MEDIUM_ACC: 0.9, Stats.LONG_ACC: 0.2}), "try 1 refused")
	check(c.record_try(g, {Stats.SHORT_ACC: 0.7, Stats.MEDIUM_ACC: 0.5, Stats.LONG_ACC: 0.2}), "try 2 refused")
	check(is_equal_approx(c.best[Stats.SHORT_ACC], 0.7) and is_equal_approx(c.best[Stats.MEDIUM_ACC], 0.9), "best score not kept")
	check(c.record_try(g, {}), "try 3 refused")
	check(not c.record_try(g, {Stats.SHORT_ACC: 1.0}), "a fourth try was allowed")
	check(is_equal_approx(c.best[Stats.SHORT_ACC], 0.7), "a refused try changed the scores")
	check(not c.is_complete(), "complete with four drills unrun")


func test_bands_follow_score_and_respect_ceilings() -> void:
	var lo := Combine.make(&"sniper")
	_scored(lo, 0.2)
	var hi := Combine.make(&"sniper")
	_scored(hi, 0.6)
	var ceil := Archetypes.ceilings(&"sniper")
	var bl := lo.bands()
	var bh := hi.bands()
	for stat in ceil:
		check(bh[stat].y >= bl[stat].y, "%s: better score gave a lower band" % stat)
		check(bh[stat].x >= Archetypes.FLOOR and bh[stat].y <= int(ceil[stat]), "%s band outside floor..ceiling" % stat)
		check(bh[stat].x <= bh[stat].y, "%s band is inverted" % stat)


func test_perfect_combine_is_held_to_the_start_cap() -> void:
	for a in Archetypes.all():
		var id := StringName(a["id"])
		var c := Combine.make(id)
		_scored(c, 1.0)
		var r := c.ovr_range()
		check(r.y <= Archetypes.START_OVR_CAP, "%s: top of range %d is over the cap" % [id, r.y])
		check(r.x <= r.y, "%s: range inverted" % id)
		var s := PlayerCareer.create_soldier(1, "A", "B", "C", _head(), 1, id)
		for seed_value in 12:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value + 1
			c.finalize(s, rng)
			var o := s.ovr_at_role(Archetypes.role_of(id))
			check(o <= Archetypes.START_OVR_CAP, "%s seed %d: true OVR %d over the cap" % [id, seed_value, o])


func test_a_middling_combine_is_not_pulled_down() -> void:
	# The cap should only bind for strong runs; a 0.3 score everywhere must pass through untouched.
	var c := Combine.make(&"marksman")
	_scored(c, 0.3)
	var ceil := Archetypes.ceilings(&"marksman")
	var b := c.bands()
	for stat in ceil:
		check(b[stat] == Combine.raw_band(0.3, int(ceil[stat])), "%s was pulled down by the cap" % stat)


func test_true_ratings_sit_inside_the_bands() -> void:
	var c := Combine.make(&"scout")
	_scored(c, 0.6)
	var s := PlayerCareer.create_soldier(1, "A", "B", "C", _head(), 1, &"scout")
	for seed_value in 20:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + 100
		var b := c.finalize(s, rng)
		for stat in b:
			check(s.stats[stat] >= b[stat].x and s.stats[stat] <= b[stat].y, "%s: %d outside %s" % [stat, s.stats[stat], b[stat]])
		check(s.dev >= Soldier.DEV_MIN and s.dev <= Soldier.DEV_MAX, "dev out of range")
		for g in Stats.UPGRADABLE_GROUPS:
			check(s.group_cap(g) >= s.group_rating(g), "cap below rating for %s" % g)


func test_finalize_is_reproducible() -> void:
	var c := Combine.make(&"anchor")
	_scored(c, 0.7)
	var a := PlayerCareer.create_soldier(1, "A", "B", "C", _head(), 1, &"anchor")
	var b := PlayerCareer.create_soldier(1, "A", "B", "C", _head(), 1, &"anchor")
	var r1 := RandomNumberGenerator.new()
	r1.seed = 55
	var r2 := RandomNumberGenerator.new()
	r2.seed = 55
	c.finalize(a, r1)
	c.finalize(b, r2)
	check(a.stats == b.stats and a.dev == b.dev and a.group_caps == b.group_caps, "same seed gave different soldiers")


func test_task_scoring_rules() -> void:
	check(CombineTasks.hit_value(0.0, 40.0, 0.0, 1.0) > CombineTasks.hit_value(30.0, 40.0, 0.0, 1.0), "centre hit should beat an edge hit")
	check(CombineTasks.hit_value(30.0, 40.0, 0.1, 1.0) > CombineTasks.hit_value(30.0, 40.0, 0.9, 1.0), "a quick hit should beat a slow one")
	check(CombineTasks.hit_value(50.0, 40.0, 0.0, 1.0) == 0.0, "a miss must score 0")
	check(CombineTasks.timing_value(0.0, 0.16) == 1.0, "dead centre should be perfect")
	check(CombineTasks.timing_value(0.05, 0.16) > 0.7 and CombineTasks.timing_value(0.4, 0.16) == 0.0, "timing falloff wrong")
	check(CombineTasks.shot_value(0.0, 34.0) == 1.0 and CombineTasks.shot_value(200.0, 34.0) == 0.0, "shot value bounds wrong")
	check(CombineTasks.alt_tap(5, 1, 1) == 5 and CombineTasks.alt_tap(5, 1, 2) == 6, "mashing one key must not count")
	check(CombineTasks.quick_value(1.0, 0.2, 1.0) > CombineTasks.quick_value(1.0, 0.9, 1.0), "a faster answer should score more")
	check(CombineTasks.quick_value(1.0, 1.5, 1.0) == 0.0 and CombineTasks.quick_value(0.0, 0.1, 1.0) == 0.0, "late or wrong must be 0")
	check(CombineTasks.recall_value(0.0) == 1.0 and CombineTasks.recall_value(200.0) == 0.0, "recall bounds wrong")
	check(CombineTasks.pace_score(15.0 * 0.3, 15.0) == 0.0, "a steady jog should score 0")


func test_ruck_march_rewards_pacing_over_flat_out() -> void:
	var flat := _run_pace(func(_st, _gassed, _sp): return true)
	var smart := _run_pace(func(st, gassed, sp): return st > 0.35 or (not gassed and sp > 0.8 and st > 0.15))
	var jog := _run_pace(func(_st, _gassed, _sp): return false)
	check(smart > flat, "pacing (%.2f) should beat holding the whole way (%.2f)" % [smart, flat])
	check(flat > jog, "sprinting even badly should beat jogging")
	check(smart <= 1.0 and jog == 0.0, "score out of range: smart %.2f jog %.2f" % [smart, jog])


func _run_pace(policy: Callable) -> float:
	var dist := 0.0
	var sp := 0.3
	var st := 1.0
	var gassed := false
	for i in 900:
		var r := CombineTasks.pace_step(sp, st, gassed, policy.call(st, gassed, sp), 1.0 / 60.0)
		sp = r[0]
		st = r[1]
		gassed = r[2]
		dist += sp / 60.0
	return CombineTasks.pace_score(dist, 15.0)


func test_combine_survives_save() -> void:
	var season := Season.new_franchise(777)
	season.player_mode = true
	season.player_archetype = &"runner"
	season.player_combine = Combine.make(&"runner")
	_scored(season.player_combine, 0.5)
	season.player_combine_done = true
	var text := SaveSystem.to_text(season)
	var loaded := SaveSystem.from_text(text)
	check(loaded != null and loaded.player_combine != null, "combine lost on load")
	if loaded == null or loaded.player_combine == null:
		return
	check(loaded.player_combine.best == season.player_combine.best and loaded.player_combine.tries == season.player_combine.tries, "combine scores changed")
	check(loaded.player_combine.bands() == season.player_combine.bands(), "bands changed after load")
	check(loaded.player_combine_done, "locked flag lost")
	check(SaveSystem.to_text(loaded) == text, "re-serialization not stable")


func test_toughness_and_injury_start_at_90() -> void:
	var c := Combine.make(&"bruiser")
	_scored(c, 0.5)
	check(not c.bands().has(Stats.TOUGHNESS) and not c.bands().has(Stats.INJURY), "toughness and injury must not get bands")
	var s := PlayerCareer.create_soldier(1, "A", "B", "C", _head(), 1, &"bruiser")
	check(s.stats[Stats.TOUGHNESS] == 90 and s.stats[Stats.INJURY] == 90, "a new soldier should start at 90 / 90")
	for seed_value in 5:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + 7
		c.finalize(s, rng)
		check(s.stats[Stats.TOUGHNESS] == 90 and s.stats[Stats.INJURY] == 90, "finalize changed toughness or injury")

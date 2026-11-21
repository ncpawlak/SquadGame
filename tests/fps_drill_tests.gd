extends SceneTree
## 3D drill framework tests: scoring functions, seeded scheduling, timers finishing once, score clamping.
## Run: godot --headless --path . --script res://tests/fps_drill_tests.gd

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


func _run_out(d: FpsDrill) -> void:
	_done_scores.clear()
	d.finished.connect(_record)
	d.start(null, 42)
	for i in 4000:
		d.advance(0.05)


func test_clamp_and_time_score() -> void:
	check(FpsDrill.clamp01(-3.0) == 0.0 and FpsDrill.clamp01(7.0) == 1.0 and FpsDrill.clamp01(NAN) == 0.0, "clamp01")
	check(FpsDrill.time_score(3.0, 4.0, 10.0) == 1.0, "under par is 1")
	check(FpsDrill.time_score(12.0, 4.0, 10.0) == 0.0, "over limit is 0")
	check(is_equal_approx(FpsDrill.time_score(7.0, 4.0, 10.0), 0.5), "midway is 0.5")
	check(FpsDrill.time_score(5.0, 6.0, 6.0) == 1.0, "degenerate window")


func test_range_score() -> void:
	check(FpsDrill.range_score(10, 0, 10, 10) > 0.99, "all hit, no misses")
	check(FpsDrill.range_score(0, 0, 5, 10) == 0.0, "nothing hit")
	check(FpsDrill.range_score(5, 0, 5, 10) > FpsDrill.range_score(5, 0, 20, 10), "spray scores below precise")
	check(FpsDrill.range_score(5, 5, 5, 10) > FpsDrill.range_score(5, 0, 5, 10), "headshots add")
	check(FpsDrill.range_score(99, 99, 1, 10) <= 1.0 and FpsDrill.range_score(1, 0, 1, 0) == 0.0, "bounds")


func test_grouping_score() -> void:
	var tight: Array = []
	var loose: Array = []
	for i in 10:
		tight.append(Vector3(0.02 * i, 1.6, 0))
		loose.append(Vector3(0.3 * i, 1.6 + 0.2 * i, 0))
	check(FpsDrill.grouping_score(tight, 10, 0.9) > FpsDrill.grouping_score(loose, 10, 0.9), "tight beats loose")
	check(FpsDrill.grouping_score(tight, 20, 0.9) < FpsDrill.grouping_score(tight, 10, 0.9), "missed shots cost")
	check(FpsDrill.grouping_score([], 10, 0.9) == 0.0, "no hits")
	var off: Array = []
	for i in 10:
		off.append(Vector3(3.0 + 0.02 * i, 1.6, 0))
	check(absf(FpsDrill.grouping_score(off, 10, 0.9) - FpsDrill.grouping_score(tight, 10, 0.9)) < 0.01, "offset group is as good")


func test_sway_and_hold_score() -> void:
	check(FpsDrill.sway_score(6.0, 6.0, 0.0, 0.8) > 0.99, "perfect hold and shot")
	check(FpsDrill.sway_score(0.0, 6.0, -1.0, 0.8) == 0.0, "nothing")
	check(FpsDrill.sway_score(6.0, 6.0, -1.0, 0.8) == 0.5, "hold only")
	check(FpsDrill.hold_score(10.0, 10.0, 5, 5) > 0.99, "perfect hold")
	check(FpsDrill.hold_score(5.0, 10.0, 0, 5) < FpsDrill.hold_score(5.0, 10.0, 5, 5), "kills add")
	check(FpsSwayDrill.plane_error(Vector3(0, 1.6, 0), Vector3(0, 0, -1), -40.0, Vector2(0, 1.6)) < 0.001, "aim error on centre")
	check(FpsSwayDrill.plane_error(Vector3.ZERO, Vector3(0, 0, 1), -40.0, Vector2.ZERO) > 100.0, "aim away")


func test_schedule_deterministic() -> void:
	var a := FpsDrill.make_schedule(7, 12, 5, 1.0, 0.5, 1.5, 1.5)
	var b := FpsDrill.make_schedule(7, 12, 5, 1.0, 0.5, 1.5, 1.5)
	var c := FpsDrill.make_schedule(8, 12, 5, 1.0, 0.5, 1.5, 1.5)
	check(a == b, "same seed, same schedule")
	check(a != c, "different seed differs")
	check(a.size() == 12, "count")
	for i in a.size():
		check(int(a[i]["slot"]) >= 0 and int(a[i]["slot"]) < 5, "slot in range")
		if i > 0:
			check(a[i]["slot"] != a[i - 1]["slot"], "no repeated slot")
			check(a[i]["at"] > a[i - 1]["at"], "times increase")
	check(FpsDrill.make_schedule(1, 0, 5, 0, 1, 1, 1).is_empty(), "zero count")


func test_range_drill_runs_once_and_is_seeded() -> void:
	var d := FpsRangeDrill.make(Stats.LONG_ACC)
	_run_out(d)
	check(_done_scores.size() == 1, "finished exactly once, got %d" % _done_scores.size())
	check(_done_scores.size() == 1 and _done_scores[0] == 0.0, "no player, no hits, score 0")
	d.finish(5.0)
	d.abort()
	check(_done_scores.size() == 1, "finish after done is ignored")
	var d2 := FpsRangeDrill.make(Stats.LONG_ACC)
	var d3 := FpsRangeDrill.make(Stats.LONG_ACC)
	d2.start(null, 99)
	d3.start(null, 99)
	d2.advance(10.0)
	d3.advance(10.0)
	check(d2.schedule == d3.schedule and d2.schedule.size() == 10, "same seed gives same drill schedule")
	d2.free()
	d3.free()
	d.free()


func test_scripted_hits_score_high() -> void:
	var d := FpsRangeDrill.make(Stats.SHORT_ACC)
	_done_scores.clear()
	d.finished.connect(_record)
	d.start(null, 3)
	d.advance(FpsDrill.COUNTDOWN_SECS + 0.01)
	var step := 0.05
	for i in 4000:
		for t in d.targets:
			if t.up:
				t.take_damage(25.0, {"headshot": false})
				d._on_shot_fired({"hit": true})
		d.advance(step)
		if d.state == FpsDrill.State.DONE:
			break
	check(d.hits == 10, "all ten targets hit, got %d" % d.hits)
	check(_done_scores.size() == 1 and _done_scores[0] > 0.95, "near-perfect score, got %s" % [_done_scores])
	d.free()


func test_timer_and_countdown() -> void:
	var d := FpsGroupingDrill.new()
	_done_scores.clear()
	d.finished.connect(_record)
	d.start(null, 1)
	check(d.state == FpsDrill.State.COUNTDOWN, "starts in countdown")
	d.advance(1.0)
	check(d.state == FpsDrill.State.COUNTDOWN and d.elapsed == 0.0, "countdown does not eat run time")
	d.advance(100.0)
	check(d.state == FpsDrill.State.DONE and _done_scores.size() == 1, "overshoot finishes once")
	d.advance(10.0)
	check(_done_scores.size() == 1, "advancing after done does nothing")
	check(d.elapsed <= d.duration + 0.0001, "elapsed never passes duration")
	d.free()


func test_grouping_drill_from_shots() -> void:
	var d := FpsGroupingDrill.new()
	_done_scores.clear()
	d.finished.connect(_record)
	d.start(null, 1)
	d.advance(FpsDrill.COUNTDOWN_SECS + 0.1)
	for pass_i in FpsGroupingDrill.PASSES:
		for t in d.targets:
			t.last_hit_pos = t.position + FpsDrillTarget.BULLSEYE + Vector3(0.01 * pass_i, 0.0, 0.0)
			d._on_hit(false, t)
	check(_done_scores.size() == 1 and _done_scores[0] > 0.9, "tight groups on every target score high: %s" % [_done_scores])
	d.free()


func test_grouping_rounds_and_scatter() -> void:
	var d := FpsGroupingDrill.new()
	_done_scores.clear()
	d.finished.connect(_record)
	d.start(null, 1)
	d.advance(FpsDrill.COUNTDOWN_SECS + 0.1)
	var first: FpsDrillTarget = d.targets[0]
	first.last_hit_pos = first.position + FpsDrillTarget.BULLSEYE
	d._on_hit(false, first)
	d._on_hit(false, first)
	check(d.shot_points[0].size() == 1, "a target takes one shot per round")
	d.free()
	check(FpsDrill.group_ring_score([[Vector2(0, 0), Vector2(0.01, 0), Vector2(0, 0.01)]], 0.25) > 0.9, "a tight group scores high")
	check(FpsDrill.group_ring_score([[Vector2(-0.2, 0), Vector2(0.2, 0), Vector2(0, 0.2)]], 0.25) < 0.4, "a loose group scores low")
	check(FpsDrill.group_ring_score([[Vector2(5, 5), Vector2(5.01, 5), Vector2(5, 5.01)]], 0.25) > 0.9, "where the group sits does not matter")


func test_range_value_and_standard_loadout() -> void:
	check(FpsDrill.pop_value(0.0, 2.0, 1.0) == 1.0, "instant bullseye is perfect")
	check(FpsDrill.pop_value(1.0, 2.0, 1.0) < FpsDrill.pop_value(0.2, 2.0, 1.0), "faster is better")
	check(FpsDrill.pop_value(0.2, 2.0, 0.2) < FpsDrill.pop_value(0.2, 2.0, 0.9), "closer to the bullseye is better")
	check(FpsDrill.mean_value([1.0, 1.0], 4) == 0.5, "misses count as zero")
	var std := FpsDrill.standard_stats({Stats.SHORT_ACC: 99})
	check(std[Stats.SHORT_ACC] == 99 and std[Stats.SPEED] == 50 and std.size() == Stats.ALL.size(), "standard loadout is 50 with overrides")
	var r := FpsRangeDrill.make(Stats.MEDIUM_ACC)
	check(r.lock_player and r.loadout[Stats.MEDIUM_ACC] == 99, "range drills are standing drills at accuracy 99")
	r.free()


func test_sway_drill_shot() -> void:
	var d := FpsSwayDrill.new()
	_done_scores.clear()
	d.finished.connect(_record)
	d.start(null, 1)
	d.advance(FpsDrill.COUNTDOWN_SECS + 0.1)
	d._on_shot_fired({"hit": true, "position": Vector3(0, FpsSwayDrill.TARGET_Y, -41.0)})
	check(_done_scores.size() == 1, "an early shot ends it once")
	check(_done_scores.size() == 1 and _done_scores[0] <= 0.5, "jumping the gun cannot score above the hold half")
	d.free()


func test_course_scores() -> void:
	var fast := FpsCourseDrill.leg_scores(4.0, 11.0)
	check(fast[Stats.SPEED] == 1.0 and fast[Stats.AGILITY] == 1.0, "under par is perfect")
	var slow := FpsCourseDrill.leg_scores(20.0, 60.0)
	check(slow[Stats.SPEED] == 0.0 and slow[Stats.AGILITY] == 0.0, "over limit is zero")
	var half := FpsCourseDrill.leg_scores(5.0, -1.0)
	check(half[Stats.AGILITY] == 0.0 and half[Stats.SPEED] > 0.8, "unfinished leg scores 0")
	check(FpsCourseDrill.gate_reached(Vector3(1, 5, -11), Vector3(0, 0, -12), 2.0), "gate ignores height")
	check(not FpsCourseDrill.gate_reached(Vector3(5, 0, -12), Vector3(0, 0, -12), 2.0), "outside the gate")
	var d := FpsCourseDrill.new()
	_run_out(d)
	check(_done_scores.size() == 1 and _done_scores[0] == 0.0, "no runner, score 0, once")
	check(d.stat_scores().has(Stats.SPEED) and d.stat_scores().has(Stats.AGILITY), "scores both stats")
	d.free()


func test_hold_drill_clamped() -> void:
	var d := FpsHoldDrill.new()
	_run_out(d)
	check(_done_scores.size() == 1 and _done_scores[0] >= 0.0 and _done_scores[0] <= 1.0, "score in range")
	d.free()


func test_hall_registry_and_scores_clamped() -> void:
	var ids := FpsDrillHall.drill_ids()
	check(ids.size() >= 5, "hall lists the drills")
	var stats := {}
	for id in ids:
		var e := FpsDrillHall.entry(id)
		check(ResourceLoader.exists(e["scene"]), "scene exists for %s" % id)
		var scene := load(e["scene"]) as PackedScene
		var d := scene.instantiate() as FpsDrill
		check(d != null, "scene root is a FpsDrill: %s" % id)
		if d == null:
			continue
		check(d.stat == e["stat"] or id == &"course", "stat matches registry: %s" % id)
		stats[d.stat] = true
		d.finish(-4.0)
		check(d.score == 0.0, "negative clamped: %s" % id)
		d.free()
	for s in [Stats.SHORT_ACC, Stats.MEDIUM_ACC, Stats.LONG_ACC, Stats.GROUPING, Stats.SWAY, Stats.AGILITY]:
		check(stats.has(s), "a drill feeds %s" % s)
	var hall := FpsDrillHall.new()
	var got: Array = []
	hall.drill_finished.connect(func(st, sc): got.append([st, sc]))
	var course := FpsCourseDrill.new()
	course.finish(9.0)
	hall.report(course)
	check(got.size() == 2, "the course reports two stats, got %d" % got.size())
	for g in got:
		check(g[1] >= 0.0 and g[1] <= 1.0, "reported score in range")
	course.free()
	hall.free()

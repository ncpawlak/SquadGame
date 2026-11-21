extends SceneTree
## Movement drills (maze, sled push, ruck run): maze generation, scoring rules, sled tap logic, ruck pace score,
## finishing once and score clamping.
## Run: godot --headless --path . --script res://tests/fps_drill_movement_tests.gd

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


func _start(d: FpsDrill, seed_value: int = 42) -> void:
	_done_scores.clear()
	d.finished.connect(_record)
	d.start(null, seed_value)
	d.advance(FpsDrill.COUNTDOWN_SECS + 0.01)


# ---- maze -----------------------------------------------------------------------------------------------------------

func test_maze_is_a_perfect_connected_maze() -> void:
	for s in [1, 2, 3, 77, 12345]:
		var m := FpsMazeDrill.generate_maze(s)
		check(m.size() == FpsMazeDrill.COLS * FpsMazeDrill.ROWS, "cell count")
		check(FpsMazeDrill.passage_count(m) == m.size() - 1, "spanning tree has cells-1 passages (seed %d)" % s)
		var centre := FpsMazeDrill.centre_cell()
		for corner in [Vector2i(0, 0), Vector2i(FpsMazeDrill.COLS - 1, 0), Vector2i(0, FpsMazeDrill.ROWS - 1), Vector2i(FpsMazeDrill.COLS - 1, FpsMazeDrill.ROWS - 1)]:
			check(FpsMazeDrill.shortest_path_length(m, corner, centre) > 0, "centre reachable from %s (seed %d)" % [corner, s])
		for y in FpsMazeDrill.ROWS:
			for x in FpsMazeDrill.COLS:
				check(FpsMazeDrill.shortest_path_length(m, Vector2i(0, 0), Vector2i(x, y)) >= 0, "every cell reachable")


func test_maze_deterministic_and_varied() -> void:
	check(FpsMazeDrill.generate_maze(9) == FpsMazeDrill.generate_maze(9), "same seed, same maze")
	check(FpsMazeDrill.generate_maze(9) != FpsMazeDrill.generate_maze(10), "different seed, different maze")


func test_maze_walls_are_symmetric() -> void:
	var m := FpsMazeDrill.generate_maze(5)
	var cols := FpsMazeDrill.COLS
	for y in FpsMazeDrill.ROWS:
		for x in cols:
			var c: int = m[y * cols + x]
			if c & FpsMazeDrill.E != 0:
				check(x + 1 < cols and int(m[y * cols + x + 1]) & FpsMazeDrill.W != 0, "east door has a west side")
			if c & FpsMazeDrill.N != 0:
				check(y > 0 and int(m[(y - 1) * cols + x]) & FpsMazeDrill.S != 0, "north door has a south side")


func test_maze_shortest_path_known() -> void:
	# 3x1 corridor: 0 -E-> 1 -E-> 2
	var cells := [FpsMazeDrill.E, FpsMazeDrill.E | FpsMazeDrill.W, FpsMazeDrill.W]
	check(FpsMazeDrill.shortest_path_length(cells, Vector2i(0, 0), Vector2i(2, 0), 3, 1) == 2, "corridor length 2")
	check(FpsMazeDrill.shortest_path_length(cells, Vector2i(0, 0), Vector2i(0, 0), 3, 1) == 0, "same cell")
	var walled := [FpsMazeDrill.E, FpsMazeDrill.W, 0]
	check(FpsMazeDrill.shortest_path_length(walled, Vector2i(0, 0), Vector2i(2, 0), 3, 1) == -1, "unreachable is -1")


func test_maze_score() -> void:
	var par := FpsMazeDrill.par_time(20)
	check(FpsMazeDrill.maze_score(par * 0.5, 20) == 1.0, "faster than par is 1")
	check(FpsMazeDrill.maze_score(par * FpsMazeDrill.LIMIT_MULT * 1.5, 20) == 0.0, "far over the limit is 0")
	var mid := FpsMazeDrill.maze_score(par * 2.0, 20)
	check(mid > 0.0 and mid < 1.0, "between is partial")
	check(FpsMazeDrill.maze_score(par + 5.0, 20) > FpsMazeDrill.maze_score(par + 15.0, 20), "slower scores lower")
	check(FpsMazeDrill.par_time(30) > FpsMazeDrill.par_time(10), "longer path, longer par")
	check(FpsMazeDrill.mean_score([1.0, 1.0]) < 1.0, "missing mazes count 0")


func test_maze_drill_three_mazes_then_finish_once() -> void:
	var d := FpsMazeDrill.new()
	_start(d)
	check(d.stat == Stats.AWARENESS, "stat")
	var first_maze := d.maze.duplicate()
	d.advance(1.0)
	d.complete_maze()
	check(d.maze_index == 1 and d.state == FpsDrill.State.RUNNING, "second maze begins")
	check(d.maze != first_maze, "a new maze")
	d.complete_maze()
	check(d.state == FpsDrill.State.RUNNING and d.maze_scores.size() == 2, "still running after two")
	d.complete_maze()
	check(d.state == FpsDrill.State.DONE and _done_scores.size() == 1, "finished after three")
	check(_done_scores[0] > 0.9, "instant mazes score about 1")
	d.complete_maze()
	d.advance(500.0)
	check(_done_scores.size() == 1, "finishes once")


func test_maze_drill_timeout_scores_partial_and_clamped() -> void:
	var d := FpsMazeDrill.new()
	_start(d)
	d.complete_maze()
	for i in 4000:
		d.advance(0.1)
	check(d.state == FpsDrill.State.DONE and _done_scores.size() == 1, "timed out once")
	check(_done_scores[0] >= 0.0 and _done_scores[0] <= 1.0 and _done_scores[0] < 0.5, "one maze of three, clamped")


# ---- sled -----------------------------------------------------------------------------------------------------------

func test_sled_rules() -> void:
	check(FpsSledDrill.tap_force(95.0) == FpsSledDrill.MAX_FORCE, "force capped")
	check(FpsSledDrill.decay_force(50.0, 1.0) < 50.0 and FpsSledDrill.decay_force(50.0, 1.0) > 0.0, "force decays")
	check(FpsSledDrill.resistance_at(0.0) < FpsSledDrill.resistance_at(10.0) and FpsSledDrill.resistance_at(10.0) < FpsSledDrill.resistance_at(20.0), "resistance rises")
	check(FpsSledDrill.sled_speed(20.0, 40.0) == 0.0, "below resistance no move")
	check(FpsSledDrill.sled_speed(60.0, 40.0) > 0.0, "above resistance moves")
	check(FpsSledDrill.sled_score(true, 5.0, 20.0, 30.0) == 1.0, "fast finish is 1")
	check(FpsSledDrill.sled_score(true, 30.0, 20.0, 30.0) > FpsSledDrill.sled_score(false, 30.0, 19.0, 30.0), "a finish beats a stall")
	check(FpsSledDrill.sled_score(false, 30.0, 0.0, 30.0) == 0.0, "no distance is 0")
	check(FpsSledDrill.sled_score(false, 30.0, 10.0, 30.0) > 0.0, "partial by distance")
	check(FpsSledDrill.sled_score(true, 12.0, 20.0, 30.0) > FpsSledDrill.sled_score(true, 20.0, 20.0, 30.0), "faster scores higher")


func _sled_run(taps_per_sec: float) -> FpsSledDrill:
	var d := FpsSledDrill.new()
	_start(d)
	var step := 1.0 / 60.0
	var acc := 0.0
	var gap := 1.0 / maxf(taps_per_sec, 0.001)
	for i in 3000:
		if d.state != FpsDrill.State.RUNNING:
			break
		if taps_per_sec > 0.0:
			acc += step
			if acc >= gap:
				acc -= gap
				d.tap()
		d.advance(step)
	return d


func test_sled_tapping_moves_and_finishes() -> void:
	var d := _sled_run(7.0)
	check(d.finished_push and d.state == FpsDrill.State.DONE, "rhythmic tapping finishes")
	check(_done_scores.size() == 1 and _done_scores[0] > 0.5, "good score for a steady tapper (%s)" % str(_done_scores))
	check(d.finish_time < d.duration, "inside the time")
	check(d.lock_player, "player stands still")


func test_sled_idle_and_slow_tapping() -> void:
	var idle := _sled_run(0.0)
	check(idle.distance == 0.0 and not idle.finished_push, "no taps no movement")
	check(_done_scores.size() == 1 and _done_scores[0] == 0.0, "zero for nothing")
	var slow := _sled_run(2.0)
	check(not slow.finished_push and slow.distance < 1.0, "slow tapping cannot beat the resistance")
	var fast := _sled_run(9.0)
	var med := _sled_run(6.0)
	check(fast.finished_push and fast.score >= med.score, "tapping faster is not worse (%.2f vs %.2f, finish %.1f)" % [fast.score, med.score, fast.finish_time])


func test_sled_tap_ignored_before_run_and_after_finish() -> void:
	var d := FpsSledDrill.new()
	d.tap()
	check(d.force == 0.0, "tap ignored while idle")
	d.start(null, 1)
	d.tap()
	check(d.force == 0.0, "tap ignored in countdown")
	d.advance(FpsDrill.COUNTDOWN_SECS + 0.01)
	d.tap()
	check(d.force > 0.0, "tap counts while running")
	d.finish(2.0)
	check(d.score == 1.0, "score clamped")
	var f := d.force
	d.tap()
	check(d.force == f, "tap ignored when done")


# ---- ruck -----------------------------------------------------------------------------------------------------------

func test_ruck_pace_score() -> void:
	check(FpsRuckDrill.pace_score(0.0) == 0.0, "no distance")
	check(is_equal_approx(FpsRuckDrill.pace_score(FpsRuckDrill.PAR_DISTANCE), FpsRuckDrill.PAR_SCORE), "par")
	check(FpsRuckDrill.pace_score(FpsRuckDrill.ELITE_DISTANCE) == 1.0 and FpsRuckDrill.pace_score(9999.0) == 1.0, "elite and beyond")
	check(FpsRuckDrill.pace_score(100.0) < FpsRuckDrill.pace_score(200.0), "monotonic below par")
	check(FpsRuckDrill.pace_score(250.0) < FpsRuckDrill.pace_score(270.0), "monotonic above par")
	check(FpsRuckDrill.pace_score(-5.0) == 0.0, "negative distance")
	check(FpsRuckDrill.pace_score(10.0, 5.0, 5.0) == 1.0, "degenerate window")


func test_ruck_distance_and_checkpoints() -> void:
	var seg := FpsRuckDrill.segment_length()
	check(seg > 5.0 and seg < 12.0, "segment length sane")
	check(is_equal_approx(FpsRuckDrill.distance_covered(3, seg), 3.0 * seg), "no partial when far")
	check(is_equal_approx(FpsRuckDrill.distance_covered(3, 0.0), 4.0 * seg), "full partial at the checkpoint")
	var d := FpsRuckDrill.new()
	_start(d)
	check(d.stat == Stats.ENDURANCE and d.duration > 40.0 and d.duration < 50.0, "stat and about 45 s")
	for i in 5:
		d.check_in()
	check(d.passed == 5, "five checkpoints")
	for i in 3000:
		d.advance(0.1)
	check(d.state == FpsDrill.State.DONE and _done_scores.size() == 1, "finishes once on time")
	check(_done_scores[0] > 0.0 and _done_scores[0] < 1.0, "score in range")
	d.check_in()
	check(d.passed == 5, "no check-in after done")


## Distance a runner covers in `secs` with the real stamina rules: sprint speed while `sprint_until` allows it.
func _run_distance(secs: float, policy: Callable) -> float:
	var mv := FpsPlayer.derive_movement(FpsDrill.standard_stats())
	var stamina: float = mv["stamina_max"]
	var locked := false
	var delay := 0.0
	var dist := 0.0
	var step := 0.05
	var t := 0.0
	while t < secs:
		var want: bool = policy.call(stamina / float(mv["stamina_max"]), locked)
		var st := FpsPlayer.step_stamina(stamina, mv, want and not locked, locked, delay, step)
		stamina = st["stamina"]
		locked = st["locked"]
		delay = st["delay"]
		var sprinting: bool = want and not locked
		dist += (float(mv["sprint_speed"]) if sprinting else float(mv["walk_speed"])) * step
		t += step
	return dist


func test_ruck_pacing_with_real_stamina_rules() -> void:
	var walk := _run_distance(45.0, func(_f: float, _l: bool) -> bool: return false)
	var flat_out := _run_distance(45.0, func(_f: float, _l: bool) -> bool: return true)
	var paced := _run_distance(45.0, func(f: float, l: bool) -> bool: return f > 0.15 if not l else false)
	check(flat_out > walk, "sprinting covers more than walking even with the forced jogs")
	check(paced >= walk, "pacing is never worse than walking")
	check(FpsRuckDrill.pace_score(flat_out * 0.9) > FpsRuckDrill.pace_score(walk * 0.9), "score follows distance")
	check(walk < FpsRuckDrill.PAR_DISTANCE and flat_out > FpsRuckDrill.PAR_DISTANCE, "par sits between walking and flat out (%.0f / %.0f)" % [walk, flat_out])
	check(flat_out < FpsRuckDrill.ELITE_DISTANCE * 1.3, "elite is within reach of the real stamina model (%.0f)" % flat_out)

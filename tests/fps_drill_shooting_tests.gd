extends SceneTree
## Tests for the active-reload, under-fire and squad-callouts drills: scoring rules, seeded determinism, finishing once,
## score clamped, a scripted run versus a no-input run.
## Run: godot --headless --path . --script res://tests/fps_drill_shooting_tests.gd

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


func _start(d: FpsDrill, seed_value: int) -> void:
	_done_scores.clear()
	d.finished.connect(_record)
	d.start(null, seed_value)
	d.advance(FpsDrill.COUNTDOWN_SECS + 0.01)


func _hit(d: FpsDrill, t: FpsDrillTarget) -> void:
	t.take_damage(25.0, {"headshot": false, "position": t.position + FpsDrillTarget.BULLSEYE})
	d._on_shot_fired({"hit": true})


func _run_out(d: FpsDrill, seed_value: int) -> void:
	_done_scores.clear()
	d.finished.connect(_record)
	d.start(null, seed_value)
	for i in 6000:
		d.advance(0.05)


# ---------------------------------------------------------------- active reload

func test_reload_rules() -> void:
	var lo := FpsReloadDrill.SWEET.x
	var hi := FpsReloadDrill.SWEET.y
	check(FpsReloadDrill.tap_quality((lo + hi) * 0.5, lo, hi) == 1.0, "inside the window is perfect")
	check(FpsReloadDrill.tap_quality(lo, lo, hi) == 1.0 and FpsReloadDrill.tap_quality(hi, lo, hi) == 1.0, "edges count")
	check(FpsReloadDrill.tap_quality(lo - 0.05, lo, hi) < 1.0, "a little early is not perfect")
	check(FpsReloadDrill.tap_quality(lo - 0.05, lo, hi) > FpsReloadDrill.tap_quality(lo - 0.2, lo, hi), "closer is better")
	check(FpsReloadDrill.tap_quality(0.0, lo, hi) == 0.0 and FpsReloadDrill.tap_quality(1.0, lo, hi) == 0.0, "far off is 0")
	check(FpsReloadDrill.tap_quality(hi + 0.05, lo, hi) <= 0.5, "outside never above half")
	check(FpsReloadDrill.reload_score([1, 1, 1, 1, 1], 15, 15) > 0.99, "perfect run")
	check(FpsReloadDrill.reload_score([], 15, 15) == 0.0, "nothing reloaded")
	check(FpsReloadDrill.reload_score([1, 1], 15, 15) < FpsReloadDrill.reload_score([1, 1, 1], 15, 15), "unfinished reloads count 0")
	check(FpsReloadDrill.reload_score([1, 1, 1, 1, 1], 0, 15) < FpsReloadDrill.reload_score([1, 1, 1, 1, 1], 15, 15), "hits add a little")
	check(FpsReloadDrill.reload_score([1, 1, 1, 1, 1], 0, 15) > 0.8, "hits are only a small share")
	check(FpsReloadDrill.reload_score([1, 1, 1, 1, 1, 1, 1], 99, 15) <= 1.0, "clamped")
	check(FpsReloadDrill.reload_score([0.2, 0.2, 0.2, 0.2, 0.2], 15, 15) < FpsReloadDrill.reload_score([1, 1, 1, 1, 1], 15, 15), "no press scores below perfect")


func test_reload_drill_no_input_zero_and_once() -> void:
	var d := FpsReloadDrill.new()
	_run_out(d, 5)
	check(_done_scores.size() == 1 and _done_scores[0] == 0.0, "no input scores 0 once: %s" % [_done_scores])
	d.finish(4.0)
	d.abort()
	check(_done_scores.size() == 1, "finish after done ignored")
	check(d.stat == Stats.RELOAD and d.lock_player, "stat and standing drill")
	d.free()


func _scripted_reload(seed_value: int, press_at: float, tap: bool) -> Array:
	var d := FpsReloadDrill.new()
	_start(d, seed_value)
	for i in 6000:
		for t in d.targets:
			if t.up and not d.is_reloading():
				_hit(d, t)
		if tap and d.is_reloading() and d.reload_progress() >= press_at:
			d.press_reload()
		d.advance(0.02)
		if d.state == FpsDrill.State.DONE:
			break
	var out := [d.score, _done_scores.duplicate(), d.qualities.duplicate(), d.hits]
	d.free()
	return out


func test_reload_scripted_perfect_beats_others() -> void:
	var perfect := _scripted_reload(3, 0.6, true)
	check(perfect[1].size() == 1 and perfect[0] > 0.95, "perfect timing scores high: %s" % [perfect[0]])
	check(perfect[2].size() == FpsReloadDrill.RELOADS, "five reloads judged, got %d" % perfect[2].size())
	var early := _scripted_reload(3, 0.1, true)
	var none := _scripted_reload(3, 0.6, false)
	check(early[0] < perfect[0] and none[0] < perfect[0], "early or no press scores lower")
	check(none[0] > 0.0 and none[0] < 0.4, "a normal reload with hits is low but not zero: %s" % [none[0]])
	var again := _scripted_reload(3, 0.6, true)
	check(again[0] == perfect[0], "same seed, same score")


func test_reload_drill_one_press_per_reload_and_seeded() -> void:
	var d := FpsReloadDrill.new()
	_start(d, 8)
	d.press_reload()
	check(d.qualities.is_empty(), "a press with no reload running does nothing")
	var shot := 0
	for i in 600:
		for t in d.targets:
			if t.up and not d.is_reloading() and shot < FpsReloadDrill.MAG:
				_hit(d, t)
				shot += 1
		if d.is_reloading():
			break
		d.advance(0.05)
	check(d.is_reloading(), "an empty mag starts a reload")
	d.advance(1.3)
	d.press_reload()
	d.press_reload()
	d.advance(10.0)
	check(d.qualities.size() == 1, "one reload judged once, got %d" % d.qualities.size())
	check(d.qualities.size() == 1 and d.qualities[0] == 1.0, "mid sweet spot is perfect: %s" % [d.qualities])
	var a := FpsReloadDrill.new()
	var b := FpsReloadDrill.new()
	a.start(null, 21)
	b.start(null, 21)
	a.advance(10.0)
	b.advance(10.0)
	check(a.schedule == b.schedule and a.schedule.size() == 30, "same seed same schedule")
	a.free()
	b.free()
	d.free()


func test_weapon_active_reload_hooks() -> void:
	var w := FpsWeapon.new()
	w.mag_limit = 3
	w.infinite_reserve = true
	w.refill()
	check(w.ammo == 3 and w.mag_size() == 3, "tiny mag")
	w.ammo = 0
	check(w.reload(), "reload starts")
	check(w.reload_total > 0.0 and w.reload_progress() == 0.0, "progress starts at 0")
	w.tick(w.reload_total * 0.5)
	check(absf(w.reload_progress() - 0.5) < 0.01, "progress halfway")
	var taps: Array = []
	w.reload_tapped.connect(func(p: float) -> void: taps.append(p))
	w.reload_tap()
	check(taps.size() == 1 and absf(taps[0] - 0.5) < 0.01, "tap reports progress")
	w.extend_reload(0.5)
	check(w.reload_left > w.reload_total * 0.5 - 0.01, "extended")
	w.finish_reload_early()
	check(not w.reloading and w.ammo == 3, "finished early refills the tiny mag")
	w.reload_tap()
	check(taps.size() == 1, "no tap signal when not reloading")
	w.free()


# ---------------------------------------------------------------- under fire

func test_composure_rules() -> void:
	var counts := FpsComposureDrill.phase_counts()
	var calm: Array = []
	var good: Array = []
	var bad: Array = []
	var worse: Array = []
	for pi in counts.size():
		calm.append([])
		good.append([])
		bad.append([])
		worse.append([])
		for i in int(counts[pi]):
			(calm[pi] as Array).append(0.9 if pi == 0 else 0.0)
			(good[pi] as Array).append(0.9)
			(bad[pi] as Array).append(0.9 if pi == 0 else 0.4)
			(worse[pi] as Array).append(0.9 if pi == 0 else 0.1)
	check(FpsComposureDrill.composure_score(good, counts) > 0.9, "no drop under fire scores high")
	check(FpsComposureDrill.composure_score(bad, counts) < FpsComposureDrill.composure_score(good, counts), "a drop costs")
	check(FpsComposureDrill.composure_score(worse, counts) < FpsComposureDrill.composure_score(bad, counts), "a bigger drop costs more")
	check(FpsComposureDrill.composure_score(calm, counts) == 0.0, "only calm hits, nothing under fire: 0")
	check(FpsComposureDrill.composure_score([], counts) == 0.0, "empty")
	var blown: Array = []
	for pi in counts.size():
		blown.append([5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0])
	check(FpsComposureDrill.composure_score(blown, counts) <= 1.0, "clamped")
	var weak: Array = []
	for pi in counts.size():
		weak.append([0.1])
	check(FpsComposureDrill.composure_score(weak, counts) < 0.2, "weak is weak")


func test_composure_schedule_and_events() -> void:
	var a := FpsComposureDrill.make_phase_schedule(7, 5, 1.0)
	var b := FpsComposureDrill.make_phase_schedule(7, 5, 1.0)
	var c := FpsComposureDrill.make_phase_schedule(8, 5, 1.0)
	check(a == b and a != c, "seeded")
	check(a.size() == FpsComposureDrill.total_targets(), "all waves")
	var gaps := [0.0, 0.0, 0.0, 0.0]
	var n := [0, 0, 0, 0]
	for i in range(1, a.size()):
		check(a[i]["at"] > a[i - 1]["at"] and a[i]["slot"] != a[i - 1]["slot"], "ordered, no repeat")
		if a[i]["phase"] == a[i - 1]["phase"]:
			gaps[a[i]["phase"]] += a[i]["at"] - a[i - 1]["at"]
			n[a[i]["phase"]] += 1
	check(gaps[1] / n[1] > gaps[2] / n[2] and gaps[2] / n[2] > gaps[3] / n[3], "waves come faster")
	var ev := FpsComposureDrill.make_suppress_events(a)
	check(not ev.is_empty(), "there is fire")
	var wave1_start := float(a[int(FpsComposureDrill.PHASES[0]["count"])]["at"])
	check(float(ev[0]["at"]) >= wave1_start - FpsComposureDrill.LEAD - 0.001, "no fire in the calm wave")
	var ordered := true
	for i in range(1, ev.size()):
		ordered = ordered and float(ev[i]["amount"]) >= float(ev[i - 1]["amount"]) and float(ev[i]["at"]) > float(ev[i - 1]["at"])
	check(ordered, "fire gets heavier and stays ordered")


func _scripted_composure(seed_value: int, shoot: bool) -> Array:
	var d := FpsComposureDrill.new()
	_start(d, seed_value)
	for i in 6000:
		if shoot:
			for t in d.targets:
				if t.up:
					_hit(d, t)
		d.advance(0.02)
		if d.state == FpsDrill.State.DONE:
			break
	var out := [d.score, _done_scores.duplicate(), d.suppress_log.size(), d.hits]
	d.free()
	return out


func test_composure_drill_runs() -> void:
	var run := _scripted_composure(4, true)
	check(run[1].size() == 1 and run[0] > 0.95, "instant hits score high: %s" % [run[0]])
	check(run[3] == FpsComposureDrill.total_targets(), "every target hit, got %d" % run[3])
	check(run[2] > 10, "suppressive fire was sent, got %d" % run[2])
	var none := _scripted_composure(4, false)
	check(none[1].size() == 1 and none[0] == 0.0, "no input scores 0 once: %s" % [none[1]])
	check(_scripted_composure(4, true)[0] == run[0], "deterministic by seed")
	var d := FpsComposureDrill.new()
	_run_out(d, 2)
	d.finish(3.0)
	d.abort()
	check(_done_scores.size() == 1 and d.stat == Stats.COMPOSURE and d.lock_player, "once, stat, standing")
	check(d.score >= 0.0 and d.score <= 1.0, "clamped")
	d.free()
	# Slow hits under fire score below the same hits when calm.
	var slow := FpsComposureDrill.new()
	_start(slow, 4)
	for i in 6000:
		for t in slow.targets:
			if t.up and slow.elapsed - t.popped_at >= (0.2 if slow.current_phase() == 0 else 1.0):
				_hit(slow, t)
		slow.advance(0.02)
		if slow.state == FpsDrill.State.DONE:
			break
	check(slow.score < run[0] and slow.score > 0.0, "slower under fire scores lower: %s" % slow.score)
	slow.free()


# ---------------------------------------------------------------- callouts

func test_callouts_rules() -> void:
	check(FpsCalloutsDrill.round_value(5, 5) == 1.0, "all right")
	check(FpsCalloutsDrill.round_value(2, 4) == 0.5, "partial credit")
	check(FpsCalloutsDrill.round_value(0, 4) == 0.0 and FpsCalloutsDrill.round_value(1, 0) == 0.0, "none and degenerate")
	check(FpsCalloutsDrill.round_value(9, 4) == 1.0, "clamped")
	check(FpsCalloutsDrill.callouts_score([1, 1, 1, 1, 1]) == 1.0, "perfect")
	check(is_equal_approx(FpsCalloutsDrill.callouts_score([1, 1]), 0.4), "unreached rounds count 0")
	check(FpsCalloutsDrill.callouts_score([]) == 0.0, "empty")
	var a := FpsCalloutsDrill.make_sequence(3, 0)
	check(a == FpsCalloutsDrill.make_sequence(3, 0) and a != FpsCalloutsDrill.make_sequence(4, 0), "seeded sequences")
	for r in FpsCalloutsDrill.ROUNDS:
		var s := FpsCalloutsDrill.make_sequence(3, r)
		check(s.size() == 3 + r, "round %d grows by one" % r)
		for x in s:
			check(int(x) >= 0 and int(x) < FpsCalloutsDrill.COUNT, "target index in range")


func _scripted_callouts(seed_value: int, mode: String, wrong_at: int = 0) -> Array:
	var d := FpsCalloutsDrill.new()
	_start(d, seed_value)
	for i in 20000:
		if d.phase == FpsCalloutsDrill.Phase.ANSWERING and mode != "none":
			var want := int(d.sequence[d.got])
			if mode == "wrong" and d.got == wrong_at:
				want = (want + 1) % FpsCalloutsDrill.COUNT
			_hit(d, d.targets[want])
		d.advance(0.02)
		if d.state == FpsDrill.State.DONE:
			break
	d.finish(2.0)
	var out := [d.score, _done_scores.duplicate(), d.round_values.duplicate()]
	d.free()
	return out


func test_callouts_drill_runs() -> void:
	var perfect := _scripted_callouts(6, "perfect")
	check(perfect[1].size() == 1 and perfect[0] > 0.99, "repeating every call scores 1: %s" % [perfect[0]])
	check(perfect[2].size() == FpsCalloutsDrill.ROUNDS, "five rounds")
	var wrong := _scripted_callouts(6, "wrong", 0)
	check(wrong[1].size() == 1 and wrong[0] == 0.0, "wrong from the start scores 0: %s" % [wrong[0]])
	var none := _scripted_callouts(6, "none")
	check(none[1].size() == 1 and none[0] == 0.0, "no input scores 0 once: %s" % [none[1]])
	check(_scripted_callouts(6, "perfect")[0] == perfect[0], "deterministic by seed")
	var partial := _scripted_callouts(6, "wrong", 1)
	check(partial[0] > 0.0 and partial[0] < 0.4, "wrong on the second callout earns partial credit: %s" % [partial[0]])
	check(partial[1].size() == 1, "finished once")


func test_callouts_ignores_shots_while_showing() -> void:
	var d := FpsCalloutsDrill.new()
	_start(d, 2)
	check(d.phase != FpsCalloutsDrill.Phase.ANSWERING, "starts by showing")
	_hit(d, d.targets[int(d.sequence[0])])
	check(d.got == 0 and d.round_values.is_empty(), "a shot while the call is playing does nothing")
	d.free()


func test_scenes_are_drills() -> void:
	for pair in [["res://scenes/fps/drills/reload.tscn", Stats.RELOAD], ["res://scenes/fps/drills/composure.tscn", Stats.COMPOSURE], ["res://scenes/fps/drills/callouts.tscn", Stats.TEAMWORK]]:
		check(ResourceLoader.exists(pair[0]), "scene exists %s" % pair[0])
		var scene := load(pair[0]) as PackedScene
		var d := scene.instantiate() as FpsDrill if scene != null else null
		check(d != null, "root is a FpsDrill: %s" % pair[0])
		if d == null:
			continue
		check(d.stat == pair[1] and d.title != "" and d.instructions != "" and d.duration > 0.0, "stat, title, instructions, duration")
		var std := FpsDrill.standard_stats(d.loadout)
		check(std[pair[1]] == 50, "own stat stays standard 50")
		d.finish(-3.0)
		check(d.score == 0.0, "negative clamped")
		d.free()

extends SceneTree
## 3D hill-match tests: pure rules, win condition, box score, bot brain with a fake world, and a short
## seeded smoke match on the real map.
## Run: godot --headless --path . --script tests/fps_match_tests.gd

var _failures := 0
var _passes := 0
var _current := ""

const Z := FpsHillRules.Zone


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


# --- capture and contest rules ---

func test_zone_states() -> void:
	check(FpsHillRules.zone_state(0, 0) == Z.EMPTY, "empty")
	check(FpsHillRules.zone_state(2, 0) == Z.TEAM0, "team 0 alone")
	check(FpsHillRules.zone_state(0, 1) == Z.TEAM1, "team 1 alone")
	check(FpsHillRules.zone_state(1, 4) == Z.CONTESTED, "both on it is a contest, numbers do not matter")


func test_scoring_and_holder() -> void:
	var s := FpsHillRules.step_score([0.0, 0.0], Z.TEAM1, 2.0)
	check(s == [0.0, 2.0], "lone team banks time")
	check(FpsHillRules.step_score(s, Z.CONTESTED, 5.0) == s, "contest banks nothing")
	check(FpsHillRules.step_score(s, Z.EMPTY, 5.0) == s, "empty banks nothing")
	check(FpsHillRules.next_holder(0, Z.CONTESTED) == 0, "contest keeps the previous holder")
	check(FpsHillRules.next_holder(0, Z.TEAM1) == 1, "a lone team takes the hill")
	check(FpsHillRules.next_holder(-1, Z.EMPTY) == -1, "nobody holds an untouched hill")


func test_win_condition() -> void:
	var w := FpsHillRules.HOLD_TO_WIN_S
	check(FpsHillRules.winner([10.0, 20.0], 100.0) == -1, "running")
	check(FpsHillRules.winner([w, 20.0], 100.0) == 0, "hold target wins early")
	check(FpsHillRules.winner([5.0, w + 1.0], 100.0) == 1, "team 1 reaches the target")
	check(FpsHillRules.winner([30.0, 20.0], 0.0) == 0, "timer end: higher score")
	check(FpsHillRules.winner([20.0, 30.0], 0.0) == 1, "timer end: higher score, team 1")
	check(FpsHillRules.winner([20.0, 20.0], 0.0) == 2, "draw on equal score at time")
	check(FpsHillRules.respawn_ready(5.9) == false and FpsHillRules.respawn_ready(6.0), "respawn delay")


# --- match bookkeeping (no scene needed) ---

func test_box_score_fields() -> void:
	var m := FpsHillMatch.new()
	m.init_box(_team(1, 100, 60), _team(2, 200, 60))
	check(m.box.size() == 10, "ten soldiers in the box score")
	var row: Dictionary = m.box[100]
	for k in ["kills", "deaths", "assists", "caps", "hill_s", "contest_s", "team", "slot"]:
		check(row.has(k), "box has %s" % k)
	# same field names as the numeric sim's box
	for k in ["kills", "deaths", "assists", "caps", "hill_s", "contest_s"]:
		check(m.box[200].has(k), "team 1 row has %s" % k)
	m.free()


func test_hill_accounting() -> void:
	var m := FpsHillMatch.new()
	m.init_box(_team(1, 100, 60), _team(2, 200, 60))
	m.advance(1.0, [[100, 101], []])
	check(m.holder == 0 and m.box[100]["caps"] == 1 and m.box[101]["caps"] == 1, "caps credited on capture")
	m.advance(1.0, [[100, 101], []])
	check(m.box[100]["caps"] == 1, "no repeat cap while holding")
	check(is_equal_approx(m.box[100]["hill_s"], 2.0) and is_equal_approx(m.scores[0], 2.0), "hill_s and score")
	m.advance(3.0, [[100], [200]])
	check(is_equal_approx(m.box[100]["contest_s"], 3.0) and is_equal_approx(m.box[200]["contest_s"], 3.0), "contest_s both sides")
	check(is_equal_approx(m.scores[0], 2.0) and m.scores[1] == 0.0, "no score while contested")
	m.advance(1.0, [[], [200]])
	check(m.holder == 1 and m.box[200]["caps"] == 1, "flip credits the new team")
	m.free()


func test_kills_and_assists() -> void:
	var m := FpsHillMatch.new()
	m.init_box(_team(1, 100, 60), _team(2, 200, 60))
	m.record_damage(101, 200, 30.0)
	m.record_damage(102, 200, 10.0)
	m.record_damage(100, 200, 60.0)
	m.record_kill(100, 200)
	check(m.box[100]["kills"] == 1 and m.box[200]["deaths"] == 1, "kill and death")
	check(m.box[101]["assists"] == 1, "assist for 30 damage")
	check(m.box[102]["assists"] == 0, "no assist for 10 damage")
	m.record_kill(-1, 201)
	check(m.box[201]["deaths"] == 1, "world death counts as a death only")
	m.record_kill(100, 101)
	check(m.box[100]["kills"] == 1, "no kill credit for a teammate kill")
	m.free()


func test_match_finishes_with_result() -> void:
	var m := FpsHillMatch.new()
	m.hold_to_win = 5.0
	m.init_box(_team(1, 100, 60), _team(2, 200, 60))
	var got: Array = []
	m.match_finished.connect(func(r): got.append(r))
	for i in 10:
		m.advance(1.0, [[], [200]])
	check(got.size() == 1, "match_finished emitted once")
	var r: Dictionary = got[0]
	check(r["winner"] == 1 and r["scores"][1] >= 5.0, "team 1 wins on hold")
	check(r.has("box") and r["box"][200]["hill_s"] >= 5.0, "result carries the box")
	check(r["teams"][0]["abbrev"] == "T1", "team info present")
	m.free()


# --- bot brain with a fake world ---

func _ctx(sold: Soldier, over := {}) -> Dictionary:
	var c := {"state": FpsBotBrain.HOLD, "state_time": 10.0, "hp_frac": 1.0, "since_damaged": 99.0,
		"visible_enemies": 0, "on_point": false, "zone": "empty", "allies_on_point": 0, "enemies_on_point": 0,
		"allies_near": 0, "dist_to_point": 30.0, "trade_age": -1.0, "trade_roll": 1.0,
		"tun": FpsBotBrain.tuning(sold)}
	c.merge(over, true)
	return c


func test_ratings_drive_tuning() -> void:
	var lo := FpsBotBrain.tuning(_soldier(1, 20))
	var hi := FpsBotBrain.tuning(_soldier(2, 95))
	check(hi["spot_range"] > lo["spot_range"], "awareness widens spotting")
	check(hi["reaction_s"] < lo["reaction_s"], "awareness speeds reaction")
	check(hi["fire_error_mult"] < lo["fire_error_mult"], "composure steadies aim under fire")
	check(hi["stack_dist"] < lo["stack_dist"], "teamwork tightens the stack")
	check(hi["point_value"] > lo["point_value"], "obj iq and anchor raise point value")


func test_state_transitions() -> void:
	var s := _soldier(1, 70)
	check(FpsBotBrain.decide(_ctx(s, {"zone": "empty", "dist_to_point": 30.0})) == FpsBotBrain.ROTATE, "far from empty point: rotate")
	check(FpsBotBrain.decide(_ctx(s, {"zone": "empty", "dist_to_point": 5.0})) == FpsBotBrain.PUSH, "near empty point: push")
	check(FpsBotBrain.decide(_ctx(s, {"zone": "mine", "on_point": true})) == FpsBotBrain.HOLD, "on own point: hold")
	check(FpsBotBrain.decide(_ctx(s, {"zone": "contested", "on_point": true, "allies_near": 2, "enemies_on_point": 1})) == FpsBotBrain.PUSH, "contested with numbers: push")
	check(FpsBotBrain.decide(_ctx(s, {"hp_frac": 0.2, "visible_enemies": 1, "zone": "contested"})) == FpsBotBrain.COVER, "hurt under fire: cover")
	check(FpsBotBrain.decide(_ctx(s, {"state": FpsBotBrain.COVER, "state_time": 0.5, "since_damaged": 1.0})) == FpsBotBrain.COVER, "stays in cover briefly")
	check(FpsBotBrain.decide(_ctx(s, {"state": FpsBotBrain.COVER, "state_time": 5.0, "since_damaged": 9.0, "zone": "mine", "on_point": true})) == FpsBotBrain.HOLD, "calm again: leaves cover")
	check(FpsBotBrain.decide(_ctx(s, {"trade_age": 1.0, "trade_roll": 0.0})) == FpsBotBrain.TRADE, "teammate down, roll under teamwork: trade")
	check(FpsBotBrain.decide(_ctx(s, {"trade_age": 1.0, "trade_roll": 0.99, "zone": "mine", "on_point": true})) == FpsBotBrain.HOLD, "roll above teamwork: no trade")
	check(FpsBotBrain.decide(_ctx(s, {"trade_age": 9.0, "trade_roll": 0.0, "zone": "mine", "on_point": true})) == FpsBotBrain.HOLD, "trade window expired")


func test_obj_iq_changes_choice() -> void:
	var smart := _soldier(1, 95)
	var dumb := _soldier(2, 10)
	var c := {"zone": "mine", "on_point": false, "allies_on_point": 1}
	check(FpsBotBrain.decide(_ctx(smart, c)) == FpsBotBrain.ROTATE, "high obj iq piles onto a thin hold")
	check(FpsBotBrain.decide(_ctx(dumb, c)) == FpsBotBrain.HOLD, "low obj iq stays")


# --- real map smoke match, seeded ---

func test_map_smoke_match() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var a := _team(1, 100, 70)
	var b := _team(2, 200, 70)
	var m := FpsMatchLauncher.launch(holder, a, b, 7, {"round_s": 12.0, "hold_to_win": 60.0})
	var got: Array = []
	m.match_finished.connect(func(r): got.append(r))
	check(m.bots.size() == 2 and m.bots[0].size() == 5 and m.bots[1].size() == 5, "two squads of five")
	Engine.time_scale = 6.0
	var frames := 0
	while got.is_empty() and frames < 4000:
		await physics_frame
		frames += 1
	Engine.time_scale = 1.0
	check(not got.is_empty(), "smoke match finished (frames %d, time_left %.1f)" % [frames, m.time_left])
	if not got.is_empty():
		var r: Dictionary = got[0]
		print("    smoke: scores %s, winner %d, frames %d" % [str(r["scores"]), r["winner"], frames])
		var moved := false
		for bot in m.bots[0]:
			if bot.global_position.distance_to(m.map.spawn_positions(0)[0]) > 3.0:
				moved = true
		check(moved, "bots left their spawn")
	holder.queue_free()

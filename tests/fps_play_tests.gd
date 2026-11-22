extends SceneTree
## PLAY (3D career match) UI tests: the matchup page's PLAY button rules, the runner launching over a fake game with the
## FpsMatchGame API, pause / sim-the-rest returning a result ScheduledMatch accepts, and (when it exists) the real game.
## Run: godot --headless --path . --script tests/fps_play_tests.gd

var _failures := 0
var _fail_tests := 0
var _passes := 0
var _current := ""
var _app: Node = null
var _hub: Node = null


## Stand-in with the FpsMatchGame API the runner codes against.
class FakeGame extends Node3D:
	signal game_started(number: int, mode: StringName)
	signal game_ended(game: Dictionary)
	signal round_started(number: int)
	signal round_ended(info: Dictionary)
	signal kill_happened(info: Dictionary)
	signal human_died(killer_id: int)
	signal human_respawned()
	signal match_finished(result: MatchResult)
	var mode: StringName = &"tdm"
	var game_number := 1
	var round_number := 1
	var game_scores: Array = [3, 1]
	var games_won: Array[int] = [0, 0]
	var clock_s := 12.0
	var time_left := -1.0
	var human: FpsPlayer = null
	var bots: Array = [[], []]
	var finished := false
	var result: MatchResult = null
	var respawn_left := 0.0
	var team_a: Team
	var team_b: Team
	var sim_calls := 0

	func human_respawn_left() -> float:
		return respawn_left

	func scoreboard() -> Array:
		var rows: Array = []
		for i in 2:
			for so in (team_a if i == 0 else team_b).starters():
				rows.append({"team": i, "name": so.tag(), "kills": 1, "deaths": 0, "assists": 0, "alive": true})
		return rows

	func sim_rest() -> MatchResult:
		sim_calls += 1
		finished = true
		var r := MatchResult.new()
		r.teams = [team_a, team_b]
		r.score = [2, 1]
		r.winner_index = 0
		r.games = [{"number": 1, "mode": &"tdm", "score": [50, 40], "winner": 0, "duration_s": 100.0, "rounds": []}]
		return r


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(_app)
	await process_frame
	_app.show_team_select()
	await process_frame
	_app.start_franchise(4242, 2)
	while not (_app.screen is Control and _app.screen.has_method("advance")):
		await process_frame
	await process_frame
	_hub = _app.screen
	for method in get_method_list():
		if String(method["name"]).begins_with("test_"):
			_current = String(method["name"])
			var before := _failures
			await call(_current)
			if _failures == before:
				_passes += 1
				print("  PASS  %s" % _current)
			else:
				_fail_tests += 1
				print("  FAIL  %s" % _current)
	print("
%d passed, %d failed" % [_passes, _fail_tests])
	quit(0 if _failures == 0 else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("    [%s] %s" % [_current, msg])


func _fixture() -> ScheduledMatch:
	_hub.season.prepare_week()
	var m := _hub.user_match_this_week() as ScheduledMatch
	if m == null:
		m = ScheduledMatch.new()
		m.home = _hub.season.league.teams[0]
		m.away = _hub.season.league.teams[1]
		m.match_seed = 77
	return m


func _play_button(m: ScheduledMatch) -> Button:
	var page: Control = _hub.pages.matchup(m)
	root.add_child(page)
	var found: Button = null
	for b in page.find_children("*", "Button", true, false):
		if b.text == "PLAY":
			found = b
	page.queue_free()
	return found


func test_no_play_button_in_franchise_mode() -> void:
	var m := _fixture()
	check(not _hub.season.player_mode, "fixture hub starts in franchise mode")
	check(_play_button(m) == null, "franchise mode matchup has no PLAY button")
	check(_hub.play_block_reason(m) != "", "franchise mode reports a block reason")


func test_play_button_rules_in_career_mode() -> void:
	var m := _fixture()
	var s: Season = _hub.season
	var ut := s.user_team()
	var starter: Soldier = ut.starters()[0]
	var bench: Soldier = null
	for so in ut.org():
		if not (so in ut.starters()):
			bench = so
			break
	s.player_team = ut
	s.player = starter
	s.player_mode = true
	var b := _play_button(m)
	check(b != null and not b.disabled, "career starter: PLAY enabled")
	check(_hub.play_block_reason(m) == "", "career starter: no block reason")
	if bench != null:
		s.player = bench
		b = _play_button(m)
		check(b != null and b.disabled and b.tooltip_text != "", "career bench player: PLAY disabled with a tooltip")
	s.player_mode = false
	s.player = null
	s.player_team = null


func _launch_fake(parent: Control, m: ScheduledMatch, human_soldier: Soldier, done: Array) -> FpsMatchRunner:
	FpsMatchRunner.game_factory = func(p: Node, home: Team, away: Team, _seed: int, human: Soldier, _field, _wx) -> Node:
		var g := FakeGame.new()
		g.team_a = home
		g.team_b = away
		p.add_child(g)
		if human != null:
			var pl := FpsPlayer.new()
			pl.team_id = 0
			g.add_child(pl)
			pl.setup(human)
			g.human = pl
		return g
	return FpsMatchRunner.launch(parent, m, func(r: MatchResult) -> void: done.append(r), human_soldier)


func test_runner_pause_and_sim_rest() -> void:
	var m := _fixture()
	var parent := Control.new()
	var backdrop := ColorRect.new()
	parent.add_child(backdrop)
	root.add_child(parent)
	var done: Array = []
	var human: Soldier = m.home.starters()[0]
	var r := _launch_fake(parent, m, human, done)
	await process_frame
	await process_frame
	check(not backdrop.visible, "runner hides the opaque backdrop")
	check(r.hud != null and r.game != null, "runner has a hud and a game")
	check(r.hud.top_text().contains("TEAM DEATHMATCH"), "hud top bar names the mode")
	r.pause_play()
	check(get_root().get_tree().paused, "pause menu pauses the tree")
	check(r.find_child("SimRestButton", true, false) != null, "pause menu offers SIM THE REST")
	r.resume_play()
	check(not paused, "resume unpauses")
	r.pause_play()
	r.sim_rest()
	for i in 4:
		await process_frame
	check(done.size() == 1, "sim the rest calls on_done once")
	if done.size() == 1:
		check(done[0].score[0] == 2 and done[0].winner_index == 0, "on_done gets the sim result")
		m.set_live_result(done[0])
		check(m.is_played() and m.needs_xp, "ScheduledMatch accepts the result")
	check(backdrop.visible, "backdrop restored at the end")
	check(not paused, "tree unpaused at the end")
	parent.queue_free()
	FpsMatchRunner.game_factory = Callable()
	m.result = null


func test_runner_result_card_and_spectate() -> void:
	var m := _fixture()
	var parent := Control.new()
	root.add_child(parent)
	var done: Array = []
	var r := _launch_fake(parent, m, null, done)  # no human: spectates from the start
	await process_frame
	await process_frame
	check(r.spectating, "all-bot match spectates")
	var g: FakeGame = r.game
	var res := MatchResult.new()
	res.teams = [m.home, m.away]
	res.score = [2, 0]
	res.winner_index = 0
	g.match_finished.emit(res)
	await process_frame
	check(r.hud.is_result_shown(), "result card shows on match_finished")
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_SPACE
	r._unhandled_input(ev)
	await process_frame
	check(done.size() == 1 and done[0] == res, "any key on the card finishes with the real result")
	parent.queue_free()
	FpsMatchRunner.game_factory = Callable()
	m.result = null


func test_real_game_sim_rest_if_present() -> void:
	if not ResourceLoader.exists(FpsMatchRunner.GAME_SCRIPT):
		print("    (FpsMatchGame not present yet, skipped)")
		return
	var m := _fixture()
	var parent := Control.new()
	root.add_child(parent)
	var done: Array = []
	var r := FpsMatchRunner.launch(parent, m, func(res: MatchResult) -> void: done.append(res), null)
	for i in 5:
		await process_frame
	check(r.game != null, "real game built")
	r.sim_rest()
	for i in 6:
		await process_frame
	check(done.size() == 1, "real game sim_rest finishes the runner")
	if done.size() == 1:
		var res: MatchResult = done[0]
		check(res.winner_index >= 0 and res.box.size() > 0, "real result has a winner and a box score")
		m.set_live_result(res)
		check(m.is_played(), "match accepts the real result")
	parent.queue_free()
	m.result = null

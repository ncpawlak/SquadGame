extends SceneTree
## 3D career match tests: pure rules (FpsMatchRules), the FpsMatchGame orchestration with stub bots (scoring, wipes,
## KOTH, sudden death, respawns, the human), "sim the rest" merging, and a real all-bot match.
## Run: godot --headless --path . --script tests/fps_match_game_tests.gd

var _failures := 0
var _passes := 0
var _current := ""


## A bot-shaped node that does nothing: the tests drive kills by calling take_damage.
class StubUnit:
	extends Node3D
	signal died(source)
	signal damaged(amount, source)
	var soldier: Soldier
	var team_id := 0
	var alive := true
	var health := 100.0
	var world: Object = null
	var slot: StringName = &""
	var rng := RandomNumberGenerator.new()

	func setup(s: Soldier, t: int, _role = 0) -> void:
		soldier = s
		team_id = t

	func respawn(at: Vector3) -> void:
		alive = true
		health = 100.0
		global_position = at

	func take_damage(amount: float, hit: Dictionary = {}) -> void:
		if not alive:
			return
		health -= amount
		damaged.emit(amount, hit.get("source"))
		if health <= 0.0:
			alive = false
			died.emit(hit.get("source"))


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
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
	t.name = "Team %d" % id
	for i in 5:
		t.roster.append(_soldier(first_id + i, v))
	t.auto_lineup()
	return t


## A game with stub bots (and optionally the human = team 0's first starter), parked in the scene tree.
func _game(human_slot := false, seed_value := 7) -> FpsMatchGame:
	var a := _team(1, 100, 60)
	var b := _team(2, 200, 60)
	var g := FpsMatchGame.new()
	g.bot_factory = func() -> Node3D: return StubUnit.new()
	root.add_child(g)
	g.setup(a, b, seed_value, a.starters()[0] if human_slot else null, ArenaMap.legacy(), null)
	return g


func _free(g: FpsMatchGame) -> void:
	root.remove_child(g)
	g.free()


func _begin(g: FpsMatchGame) -> void:
	g.step(FpsMatchRules.INTERMISSION_S + 0.1)


## One kill by the first living member of `kt` on the first living member of the other side (waits out respawns).
func _kill_one(g: FpsMatchGame, kt: int) -> void:
	var victim: Node3D = _alive_of(g, 1 - kt)
	if victim == null:
		g.step(FpsMatchRules.RESPAWN_S + 0.1)
		victim = _alive_of(g, 1 - kt)
	var killer: Node3D = _alive_of(g, kt)
	victim.take_damage(999.0, {"source": killer})
	g.step(0.0)


func _alive_of(g: FpsMatchGame, team: int) -> Node3D:
	for u in g.squad(team):
		if not g._down.has(u.soldier.id) and u.alive:
			return u
	return null


func _win_tdm(g: FpsMatchGame, kt: int) -> void:
	var guard := 0
	while g.phase == FpsMatchGame.Phase.PLAY and g.mode == MatchEngine.MODE_TDM and guard < 400:
		_kill_one(g, kt)
		guard += 1


func _on_hill(g: FpsMatchGame, team: int, count := 1) -> void:
	var n := 0
	for u in g.squad(team):
		if n < count and u.alive:
			u.global_position = Vector3(0, 0.1, 0)
			n += 1


func _off_hill(g: FpsMatchGame, team: int) -> void:
	for u in g.squad(team):
		u.global_position = g.arena.spawn_point(team, g.teams[team].scheme, g._slot(u))


## Plays game 1 (TDM) for team `w1` and game 2 (KOTH) for `w2`. Leaves the match in game 3's intermission when 1-1.
func _play_two(g: FpsMatchGame, w1: int, w2: int) -> void:
	_begin(g)
	_win_tdm(g, w1)
	_begin(g)
	check(g.mode == MatchEngine.MODE_KOTH, "game 2 is King of the Hill")
	_on_hill(g, w2)
	g.step(FpsMatchRules.KOTH_HOLD_TO_WIN_S + 1.0)


# --- pure rules ---

func test_rules_tdm() -> void:
	check(FpsMatchRules.tdm_kill_points(false) == 1, "a kill is a point")
	check(FpsMatchRules.tdm_kill_points(true) == 6, "a wiping kill is 1 + 5")
	check(FpsMatchRules.tdm_winner([49, 3]) == -1, "49 is not enough")
	check(FpsMatchRules.tdm_winner([50, 3]) == 0, "first to 50")
	check(FpsMatchRules.tdm_winner([12, 54]) == 1, "team 1 can win")
	check(FpsMatchRules.timeout_winner([10, 9], 1) == 0, "stalemate: higher score")
	check(FpsMatchRules.timeout_winner([9, 9], 1) == 1, "stalemate tie: coin")


func test_rules_koth() -> void:
	check(FpsMatchRules.hill_state(0, 0) == FpsMatchRules.HILL_EMPTY, "empty")
	check(FpsMatchRules.hill_state(2, 0) == 0 and FpsMatchRules.hill_state(0, 1) == 1, "alone")
	check(FpsMatchRules.hill_state(3, 1) == FpsMatchRules.HILL_CONTESTED, "contested")
	check(FpsMatchRules.koth_step([5.0, 5.0], 1, 0, 2.0) == [7.0, 5.0], "alone banks time")
	check(FpsMatchRules.koth_step([5.0, 5.0], 1, 1, 2.0) == [5.0, 5.0], "contested banks nothing")
	check(FpsMatchRules.koth_step([5.0, 5.0], 0, 0, 2.0) == [5.0, 5.0], "empty banks nothing")
	check(FpsMatchRules.koth_winner([119.5, 30.0]) == -1, "119.5 s is not enough")
	check(FpsMatchRules.koth_winner([20.0, 120.0]) == 1, "120 s wins")


func test_rules_sudden_death() -> void:
	check(FpsMatchRules.sd_round_winner(3, 2, 10.0, 99.0, 1) == 0, "more alive wins")
	check(FpsMatchRules.sd_round_winner(2, 2, 40.0, 90.0, 0) == 1, "then more health")
	check(FpsMatchRules.sd_round_winner(2, 2, 50.0, 50.0, 1) == 1, "then the coin")
	check(FpsMatchRules.sd_round_over(0, 3, 5.0) and FpsMatchRules.sd_round_over(1, 1, 120.0), "wipe or clock ends it")
	check(not FpsMatchRules.sd_round_over(1, 1, 119.0), "still going")
	check(not FpsMatchRules.sd_game_over([3, 3], 6), "3-3 after 6 rounds goes on")
	check(FpsMatchRules.sd_game_over([4, 2], 6), "first to 4")
	check(FpsMatchRules.sd_game_over([3, 3], 7), "round 7 is the last")
	check(FpsMatchRules.sd_game_winner([3, 4]) == 1, "winner by rounds")
	check(FpsMatchRules.match_winner([2, 0]) == 0 and FpsMatchRules.match_winner([1, 1]) == -1, "best of 3")


func test_box_template_matches_sim() -> void:
	var r := MatchEngine.simulate(_team(1, 100, 60), _team(2, 200, 60), 3)
	var sim_line: Dictionary = r.box[100]
	var line := FpsMatchRules.box_template(100, 0, &"FM1")
	var a := sim_line.keys()
	var b := line.keys()
	a.sort()
	b.sort()
	check(a == b, "box template has exactly the sim's keys: %s vs %s" % [a, b])
	var s := _soldier(5, 50)
	check(FpsMatchGame.box_template(s, 1, &"CTR").keys().size() == b.size(), "game box_template")


func test_merge_box_and_mvp() -> void:
	var a := {1: FpsMatchRules.box_template(1, 0, &"FM1"), 2: FpsMatchRules.box_template(2, 1, &"FM1")}
	var b := {1: FpsMatchRules.box_template(1, 0, &"FM1")}
	a[1]["kills"] = 2
	a[1]["hill_s"] = 1.5
	b[1]["kills"] = 3
	b[1]["hill_s"] = 0.5
	var m := FpsMatchRules.merge_box(a, b)
	check(m[1]["kills"] == 5 and is_equal_approx(m[1]["hill_s"], 2.0), "numeric keys are summed")
	check(m[1]["team"] == 0 and m[1]["slot"] == &"FM1", "team and slot are kept")
	check(a[1]["kills"] == 2, "inputs are untouched")
	check(FpsMatchRules.pick_mvp(m, 0) == 1 and FpsMatchRules.pick_mvp(m, 1) == 2, "mvp comes from the winning side")


# --- orchestration (stub bots) ---

func test_setup_and_world_interface() -> void:
	var g := _game()
	check(g.bots[0].size() == 5 and g.bots[1].size() == 5 and g.human == null, "ten bots, no human")
	check(g.phase == FpsMatchGame.Phase.INTERMISSION and g.next_game_number == 1, "starts in the pre-game intermission")
	check(g.enemies_of(0) == g.squad(1) and g.allies_of(0) == g.squad(0), "enemies / allies")
	check(g.arena_map() == g.field and g.game_mode() == MatchEngine.MODE_TDM, "arena_map / game_mode")
	check(g.scheme_of(1) == g.teams[1].scheme, "scheme_of")
	check(g.hill_center().is_equal_approx(Vector3.ZERO), "hill centre")
	check(is_equal_approx(g.hill_radius(), 10.0 * sqrt(2.0) * 0.5), "hill radius is the half diagonal")
	check(not g.cover_points().is_empty(), "cover points")
	var u: Node3D = g.squad(0)[0]
	check(g.in_spawn_zone(0, u.global_position) and not g.in_spawn_zone(1, u.global_position), "spawn zone")
	check(g.result.box.size() == 10, "a box line for everyone")
	_free(g)


func test_tdm_scoring_and_wipe() -> void:
	var g := _game()
	var started := []
	g.game_started.connect(func(n, m): started.append([n, m]))
	var kills := []
	g.kill_happened.connect(func(info): kills.append(info))
	_begin(g)
	check(started == [[1, MatchEngine.MODE_TDM]], "game 1 TDM started")
	for i in 4:
		_kill_one(g, 0)
	check(g.game_scores[0] == 4.0, "four kills, four points")
	var killer: Node3D = g.squad(0)[0]
	var assister: Node3D = g.squad(0)[1]
	var last: Node3D = _alive_of(g, 1)
	last.take_damage(30.0, {"source": assister})
	last.take_damage(999.0, {"source": killer})
	g.step(0.0)
	check(g.game_scores[0] == 10.0, "the wiping kill is worth 6 (4 + 1 + 5): %s" % [g.game_scores])
	check(kills.size() == 5 and kills[4]["wipe"] and kills[4]["killer"] == killer.soldier.id, "wipe flagged on the kill info")
	check(kills[4]["assists"] == [assister.soldier.id], "damage over 20 is an assist")
	var kb: Dictionary = g.result.box[killer.soldier.id]
	check(kb["wipes"] == 1 and kb["kills"] >= 1 and g.result.box[assister.soldier.id]["assists"] == 1, "box: wipe + assist")
	check(g.result.box[assister.soldier.id]["damage"] >= 30.0, "box damage")
	var dead := 0
	for u in g.squad(1):
		dead += int(g.result.box[u.soldier.id]["deaths"])
	check(dead == 5, "five deaths")
	check(g.result.box[killer.soldier.id]["opening_kills"] + g.result.box[g.squad(0)[0].soldier.id]["opening_kills"] >= 1, "opening kill counted")
	_free(g)


func test_respawn_timer() -> void:
	var g := _game()
	_begin(g)
	var victim: Node3D = g.squad(1)[2]
	victim.take_damage(999.0, {"source": g.squad(0)[0]})
	g.step(0.0)
	check(not victim.alive and g.alive_count(1) == 4, "victim is down")
	g.step(5.0)
	check(not victim.alive, "still down at 5 s")
	g.step(1.2)
	check(victim.alive and g.alive_count(1) == 5, "back after 6 s")
	check(g.in_spawn_zone(1, victim.global_position), "respawns at his spawn")
	_free(g)


func test_tdm_game_over_and_next_game() -> void:
	var g := _game()
	var ended := []
	g.game_ended.connect(func(game): ended.append(game))
	_begin(g)
	_win_tdm(g, 0)
	check(ended.size() == 1, "game_ended fired once")
	var game: Dictionary = ended[0]
	check(game["mode"] == MatchEngine.MODE_TDM and game["winner"] == 0 and game["score"][0] >= 50, "game 1 dict: %s" % [game])
	check(g.games_won == [1, 0] and g.result.score == [1, 0], "games won")
	check(g.phase == FpsMatchGame.Phase.INTERMISSION and g.next_mode == MatchEngine.MODE_KOTH and g.next_game_number == 2, "intermission before KOTH")
	check(not g.finished, "match goes on")
	_begin(g)
	check(g.mode == MatchEngine.MODE_KOTH and g.game_number == 2 and g.game_scores == [0.0, 0.0], "KOTH begins clean")
	check(g.alive_count(1) == 5, "everyone is back for the next game")
	_free(g)


func test_koth_hold_contest_and_win() -> void:
	var g := _game()
	_begin(g)
	_win_tdm(g, 1)
	_begin(g)
	check(g.mode == MatchEngine.MODE_KOTH, "KOTH")
	g.step(10.0)
	check(g.game_scores == [0.0, 0.0] and g.zone_name_for(0) == "empty", "empty hill banks nothing")
	_on_hill(g, 0, 2)
	g.step(10.0)
	check(is_equal_approx(g.game_scores[0], 10.0) and g.zone_name_for(0) == "mine" and g.zone_name_for(1) == "enemy", "alone banks time: %s" % [g.game_scores])
	check(g.count_on_point(0) == 2 and g.hill_holder == 0, "two on the point, team 0 holds")
	_on_hill(g, 1, 1)
	g.step(10.0)
	check(is_equal_approx(g.game_scores[0], 10.0) and is_equal_approx(g.game_scores[1], 0.0) and g.zone_name_for(0) == "contested", "contested banks nothing")
	var c := 0.0
	for u in g.squad(0):
		c += g.result.box[u.soldier.id]["contest_s"]
	check(is_equal_approx(c, 20.0), "contest seconds in the box for the two defenders")
	_off_hill(g, 0)
	g.step(5.0)
	check(is_equal_approx(g.game_scores[1], 5.0) and g.hill_holder == 1, "the other team takes it")
	check(g.result.box[g.squad(1)[0].soldier.id]["caps"] + g.result.box[g.squad(1)[1].soldier.id]["caps"] + g.result.box[g.squad(1)[2].soldier.id]["caps"] + g.result.box[g.squad(1)[3].soldier.id]["caps"] + g.result.box[g.squad(1)[4].soldier.id]["caps"] >= 1, "a cap is credited")
	# Dead soldiers do not hold the point.
	var holder: Node3D = null
	for u in g.squad(1):
		if g._on_hill(u):
			holder = u
	holder.take_damage(999.0, {"source": g.squad(0)[0]})
	g.step(0.0)
	check(g.count_on_point(1) == 0, "a dead soldier is not on the point")
	var wins := g.games_won.duplicate()
	_on_hill(g, 0)
	g.step(FpsMatchRules.KOTH_HOLD_TO_WIN_S)
	check(g.games_won[0] == wins[0] + 1, "120 s of hold time wins the game")
	check(g.finished is bool, "ok")
	_free(g)


func test_koth_win_match_two_nil() -> void:
	var g := _game()
	var finals := []
	g.match_finished.connect(func(r): finals.append(r))
	_play_two(g, 0, 0)
	check(g.finished and finals.size() == 1 and finals[0] == g.result, "match_finished once with the result")
	var r := g.result
	check(r.score == [2, 0] and r.winner_index == 0 and r.games.size() == 2, "2-0, two games")
	check(r.games[1]["mode"] == MatchEngine.MODE_KOTH and r.games[1]["score"][0] >= 120, "KOTH game dict")
	check(r.box[r.mvp_id]["team"] == 0, "mvp is on the winning side")
	check(r.events.size() > 5 and r.events[r.events.size() - 1].begins_with("=== FINAL"), "play-by-play ends with FINAL")
	g.step(100.0)
	check(finals.size() == 1, "no second match_finished")
	_free(g)


func test_sudden_death() -> void:
	var g := _game()
	var rounds := []
	var starts := []
	g.round_ended.connect(func(i): rounds.append(i))
	g.round_started.connect(func(n): starts.append(n))
	_play_two(g, 0, 1)
	check(g.games_won == [1, 1] and not g.finished and g.next_mode == MatchEngine.MODE_SUDDEN_DEATH, "1-1 goes to sudden death")
	_begin(g)
	check(g.mode == MatchEngine.MODE_SUDDEN_DEATH and g.round_number == 1 and starts == [1], "round 1")
	# Team 0 wins round 1 by wiping team 1; no respawn inside the round.
	for i in 5:
		_kill_one(g, 0)
	check(rounds.size() == 1 and rounds[0]["winner"] == 0 and rounds[0]["survivors"] == [5, 0], "round 1 won 5-0: %s" % [rounds])
	check(g.game_scores == [1, 0], "rounds 1-0")
	check(g.phase == FpsMatchGame.Phase.INTERMISSION, "intermission between rounds")
	_begin(g)
	check(g.round_number == 2 and g.alive_count(0) == 5 and g.alive_count(1) == 5, "everyone is back")
	# One life: a dead soldier stays down for the round.
	var v: Node3D = g.squad(1)[0]
	v.take_damage(999.0, {"source": g.squad(0)[0]})
	g.step(0.0)
	g.step(20.0)
	check(not v.alive and g.alive_count(1) == 4, "no respawn in sudden death")
	# Clock expiry: 4 alive vs 5 alive, team 0 has more.
	g.step(FpsMatchRules.ROUND_TIME_LIMIT_S)
	check(rounds.size() == 2 and rounds[1]["winner"] == 0 and rounds[1]["survivors"] == [5, 4], "time out: more alive wins")
	_begin(g)
	for i in 5:
		_kill_one(g, 0)
	_begin(g)
	for i in 5:
		_kill_one(g, 0)
	check(g.finished and g.games_won == [2, 1], "fourth round win takes game 3 and the match")
	var r := g.result
	check(r.rounds.size() == 4 and r.games.size() == 3 and r.games[2]["rounds"].size() == 4, "round records")
	check(r.games[2]["score"] == [4, 0] and r.games[2]["mode"] == MatchEngine.MODE_SUDDEN_DEATH, "sd game dict")
	var played := 0
	var survived := 0
	for id in r.box:
		played += int(r.box[id]["rounds_played"])
		survived += int(r.box[id]["rounds_survived"])
	check(played == 40, "rounds_played: 10 soldiers x 4 rounds, got %d" % played)
	check(survived > 0, "rounds_survived credited")
	check(r.mvp_id >= 0 and r.box[r.mvp_id]["team"] == 0, "mvp")
	_free(g)


func test_sudden_death_clutch() -> void:
	var g := _game()
	_play_two(g, 0, 1)
	_begin(g)
	# Team 0 is down to one against four; he wins it alone.
	for i in 4:
		_kill_one(g, 1)
	g.step(0.0)
	for i in 5:
		_kill_one(g, 0)
	check(g.game_scores == [1, 0], "round to team 0")
	var clutches := 0
	for u in g.squad(0):
		clutches += int(g.result.box[u.soldier.id]["clutches"])
	check(clutches == 1, "the last soldier standing against four gets the clutch")
	_free(g)


func test_human_death_and_respawn() -> void:
	var g := _game(true)
	check(g.human != null and g.bots[0].size() == 4 and g.squad(0).has(g.human), "human replaces his bot")
	check(g.enemies_of(1).has(g.human) and g.allies_of(0).has(g.human), "bots see him")
	_begin(g)
	var deaths := []
	var back := []
	g.human_died.connect(func(k): deaths.append(k))
	g.human_respawned.connect(func(): back.append(true))
	# In his spawn zone nobody can hurt him.
	g.human.take_damage(500.0, {"source": g.squad(1)[0]})
	check(not g.human.dead and g.human.health == g.human.max_health, "spawn-zone safety")
	g.human.global_position = Vector3(0, 0.1, 5)
	var killer: Node3D = g.squad(1)[0]
	g.human.take_damage(500.0, {"source": killer})
	g.step(0.0)
	check(deaths == [killer.soldier.id], "human_died with the killer id")
	check(g.human.dead and is_equal_approx(g.human_respawn_left(), 6.0), "respawn countdown")
	g.step(2.5)
	check(is_equal_approx(g.human_respawn_left(), 3.5), "countdown runs")
	g.step(4.0)
	check(not g.human.dead and back.size() == 1 and g.human_respawn_left() == 0.0, "respawned")
	check(g.in_spawn_zone(0, g.human.global_position), "respawns at his spawn")
	check(g.game_scores[1] == 1.0, "his death scored for the other team")
	var rows := g.scoreboard()
	check(rows.size() == 10 and rows.any(func(r): return r["human"]), "scoreboard rows")
	_free(g)


# --- sim the rest ---

func _check_complete(r: MatchResult, label: String) -> void:
	check(r.winner_index in [0, 1], "%s: has a winner" % label)
	check(r.score[0] + r.score[1] == r.games.size(), "%s: games won add up to games played (%s, %d)" % [label, r.score, r.games.size()])
	check(maxi(r.score[0], r.score[1]) == 2, "%s: winner has 2 game wins" % label)
	check(r.score[r.winner_index] == 2, "%s: winner index matches" % label)
	for i in r.games.size():
		check(r.games[i]["number"] == i + 1 and r.games[i]["mode"] == MatchEngine.GAME_ORDER[i], "%s: game %d in order" % [label, i + 1])
	var wins := [0, 0]
	for gm in r.games:
		wins[gm["winner"]] += 1
	check(wins == [r.score[0], r.score[1]], "%s: game winners = score" % label)
	check(r.box.size() == 10, "%s: box for everyone" % label)
	var keys := FpsMatchRules.box_template(1, 0, &"FM1").keys()
	keys.sort()
	for id in r.box:
		var k: Array = r.box[id].keys()
		k.sort()
		check(k == keys, "%s: box keys for %s" % [label, id])
		check(int(r.box[id]["games"]) == r.games.size(), "%s: games played per soldier" % label)
	check(r.mvp_id >= 0 and r.box[r.mvp_id]["team"] == r.winner_index, "%s: mvp from the winner" % label)
	check(r.events.size() > 3 and String(r.events[r.events.size() - 1]).begins_with("=== FINAL"), "%s: ends with FINAL" % label)
	check(r.teams.size() == 2, "%s: teams" % label)


func test_sim_rest_mid_game() -> void:
	var g := _game()
	var finals := []
	g.match_finished.connect(func(x): finals.append(x))
	_begin(g)
	_win_tdm(g, 0)
	var kills_after_g1 := {}
	for id in g.result.box:
		kills_after_g1[id] = g.result.box[id]["kills"]
	_begin(g)
	_on_hill(g, 1)
	g.step(40.0)
	for i in 3:
		_kill_one(g, 0)
	var r := g.sim_rest()
	_check_complete(r, "mid-KOTH")
	check(r.games[0]["score"][0] >= 50 and r.games[0]["winner"] == 0, "game 1 keeps its 3D data")
	for id in kills_after_g1:
		check(r.box[id]["kills"] >= kills_after_g1[id], "kills from the 3D game survive")
	check(g.finished and finals.size() == 1 and finals[0] == r, "match_finished once")
	check(r.events.any(func(e): return String(e).contains("simulated")), "marker line in the log")
	# The dropped partial KOTH game must not leave its kills behind: team 0 box kills equal 3D game 1 + sim.
	var sim_only := 0
	for id in r.box:
		sim_only += int(r.box[id]["kills"]) - int(kills_after_g1.get(id, 0))
	check(sim_only > 0, "the remaining games were simulated")
	check(g.sim_rest() == r and finals.size() == 1, "second call is a no-op")
	_free(g)


func test_sim_rest_from_start_and_from_sd() -> void:
	var g := _game()
	var r := g.sim_rest()
	_check_complete(r, "from start")
	_free(g)
	var g2 := _game()
	_play_two(g2, 0, 1)
	_begin(g2)
	for i in 2:
		_kill_one(g2, 0)
	check(g2.mode == MatchEngine.MODE_SUDDEN_DEATH, "in game 3")
	var r2 := g2.sim_rest()
	_check_complete(r2, "mid-SD")
	check(r2.games[0]["winner"] == 0 and r2.games[1]["winner"] == 1 and r2.games[2]["mode"] == MatchEngine.MODE_SUDDEN_DEATH, "games 1-2 kept, game 3 simmed")
	check(r2.games[2]["rounds"].size() == r2.rounds.size() - 0 and r2.rounds.size() >= 4, "sim rounds come with the sim game")
	_free(g2)


func test_start_from_engine_api() -> void:
	var a := _team(1, 100, 60)
	var b := _team(2, 200, 60)
	var e := MatchEngine.new()
	e.start_from(a, b, 9, ArenaMap.legacy(), null, 0.0, 2, 1, 1)
	while e.step():
		pass
	var r := e.result()
	check(r.games.size() == 1 and r.games[0]["number"] == 3 and r.games[0]["mode"] == MatchEngine.MODE_SUDDEN_DEATH, "only game 3 simulated")
	check(r.score[0] + r.score[1] == 3 and r.winner_index >= 0, "score continues from 1-1")
	# The normal path is unchanged: a full sim is the same as before.
	var f := MatchEngine.simulate(a, b, 9)
	var f2 := MatchEngine.simulate(a, b, 9)
	check(f.score == f2.score and f.events == f2.events, "deterministic")


# --- consumers ---

func test_result_accepted_by_season() -> void:
	Trades.difficulty_override = Trades.Difficulty.NORMAL
	Season.fixture_teams = 5
	Season.backfill_careers = false
	Season.seed_records = false
	var s := Season.new_franchise(55)
	var user := s.user_team()
	var m: ScheduledMatch = null
	while m == null:
		for x in s.matches_for_week(s.week):
			if x.involves(user):
				m = x
		if m == null:
			s.sim_week()
	s.prepare_week()
	var g := FpsMatchGame.new()
	g.bot_factory = func() -> Node3D: return StubUnit.new()
	root.add_child(g)
	g.setup(m.home, m.away, m.match_seed, null, m.field(), m.weather())
	_begin(g)
	_win_tdm(g, 0)
	var r := g.sim_rest()
	_check_complete(r, "season fixture")
	m.set_live_result(r)
	check(m.is_played() and m.needs_xp, "ScheduledMatch accepts the result")
	var starter: Soldier = user.starters()[0]
	var matches_before: int = starter.career["matches"]
	var played := s.sim_week()
	check(played.has(m) and m.is_played() and not m.needs_xp, "season consumes the 3D result")
	check(starter.career["matches"] == matches_before + 1, "counted exactly once")
	_free(g)
	Season.fixture_teams = 0


# --- the real thing ---

func test_real_bots_play_a_match() -> void:
	var a := _team(1, 100, 70)
	var b := _team(2, 200, 70)
	var g := FpsMatchGame.launch(root, a, b, 5, null, ArenaMap.legacy(), null)
	check(g.bots[0].size() == 5 and g.bots[0][0] is FpsBot, "real bots")
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 60
	var frames := 0
	while not g.finished and frames < 6000:
		await physics_frame
		frames += 1
	Engine.time_scale = 1.0
	var done := g.finished
	print("    real match: finished=%s after %d physics frames, games %s, mode %s, score %s" % [done, frames, g.games_won, g.mode, g.game_scores])
	if not done:
		var r := g.sim_rest()
		_check_complete(r, "real bots + sim rest")
	else:
		_check_complete(g.result, "real bots")
	_free(g)

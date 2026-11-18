extends SceneTree
## Player mode phase 5 tests (Hall of Fame trajectory, milestones, retirement, recap):
##   godot --headless --path . --script res://tests/player_legacy_tests.gd
## Exits with code 0 if all tests pass, 1 otherwise.

var _failures := 0
var _passes := 0
var _current := ""


func _init() -> void:
	var tests: Array = []
	for method in get_method_list():
		if String(method["name"]).begins_with("test_"):
			tests.append(String(method["name"]))
	var only := OS.get_environment("TEST_ONLY")
	if only != "":
		tests = tests.filter(func(n): return only in n)
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


func _career(seed_value: int, score: float, archetype := &"marksman") -> Season:
	var season := Season.new_franchise(seed_value)
	var heads: Array = FaceSpec.db()["heads"].keys()
	heads.sort()
	season.player_mode = true
	season.player_archetype = archetype
	season.player = PlayerCareer.create_soldier(season.league.next_soldier_id, "Ada", "Stone", "Zzyzx", heads[0], 1, archetype)
	season.league.next_soldier_id += 1
	season.player_combine = Combine.make(archetype)
	for g in Combine.DRILL_ORDER:
		var scores := {}
		for t in Combine.drill_tasks(g):
			scores[t["stat"]] = score
		season.player_combine.record_try(g, scores)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	season.player_combine.finalize(season.player, rng)
	season.player_combine_done = true
	PlayerDraft.begin(season)
	PlayerDraft.run(season)
	if season.player_draft_state == PlayerDraft.STATE_OFFERS:
		PlayerDraft.sign_undrafted(season, PlayerDraft.undrafted_offers(season)[0])
	return season


func test_milestone_definitions() -> void:
	var ids := {}
	var kinds := [&"matches", &"kills", &"mvps", &"ovr", &"grade", &"event", &"honors", &"all_league", &"titles", &"pace"]
	for m in PlayerLegacy.MILESTONES:
		check(not ids.has(m["id"]), "duplicate milestone id %s" % m["id"])
		ids[m["id"]] = true
		check(kinds.has(m["kind"]), "%s has an unknown kind %s" % [m["id"], m["kind"]])
		check(float(m["target"]) > 0.0 and String(m["name"]) != "" and String(m["desc"]) != "", "%s is incomplete" % m["id"])
	check(ids.size() >= 15, "expected a decent list of milestones")


func test_milestones_update_once_and_report_unseen() -> void:
	var s := _career(701, 0.9)
	s.player_milestones.clear()
	var p := s.player
	p.career["matches"] = 1
	var first := PlayerLegacy.update(s)
	check(first.any(func(e): return e["id"] == "debut"), "playing a game should unlock Debut")
	check(PlayerLegacy.update(s).is_empty(), "nothing new on a second check")
	p.career["matches"] = 31
	p.career["kills"] = 120
	var more := PlayerLegacy.update(s)
	var got := more.map(func(e): return e["id"])
	check(got.has("games_30") and got.has("kills_100") and not got.has("debut"), "new milestones only: %s" % [got])
	var unseen := PlayerLegacy.take_unseen(s)
	check(unseen.size() == first.size() + more.size(), "unseen count: %d" % unseen.size())
	check(PlayerLegacy.take_unseen(s).is_empty(), "unseen should be empty after being taken")
	check(not PlayerLegacy.achieved(s, "debut").is_empty() and PlayerLegacy.achieved(s, "perfect").is_empty(), "achieved lookup")
	check(PlayerLegacy.progress_text(s, PlayerLegacy.MILESTONES[5]) != "", "progress text")


func test_trajectory_components_and_pace() -> void:
	var s := _career(702, 0.9)
	var p := s.player
	var t0 := PlayerLegacy.trajectory(s)
	check(not t0["has_pace"] and not t0["eligible"], "a rookie has no pace and is not eligible")
	check(is_equal_approx(float(t0["score"]), float(t0["production"]) + float(t0["awards"]) + float(t0["titles"]) + float(t0["peak"])), "score is the sum of its parts")
	p.career["matches"] = 20
	p.career["kills"] = 400
	p.career["assists"] = 150
	p.career["damage"] = 60000
	p.career["deaths"] = 150
	p.career["clutches"] = 10
	p.career["mvps"] = 4
	p.season_lines[s.year] = {"team": s.user_team().abbrev, "matches": 20, "kills": 400, "deaths": 150, "assists": 150, "damage": 60000}
	var t1 := PlayerLegacy.trajectory(s)
	check(t1["has_pace"] and not t1["eligible"], "20 games: pace yes, eligible no")
	check(float(t1["score"]) > 0.0, "a provisional score exists before 30 games (%.1f)" % t1["score"])
	check(float(t1["pace"]) >= float(t1["score"]), "the projected pace should not be below the current score")
	check(float(t1["threshold"]) == HallOfFame.THRESHOLD, "threshold is the Hall's")
	# Better production never lowers the score.
	p.career["kills"] = 900
	p.career["mvps"] = 12
	check(float(PlayerLegacy.trajectory(s)["score"]) >= float(t1["score"]), "more production, lower score")


func test_forced_retirement_at_the_age_everyone_retires() -> void:
	var s := _career(703, 0.9)
	var team := s.user_team()
	# Make him a roster player so the age pass sees him.
	if team.green_team.has(s.player):
		GreenTeam._move_up(team, s.player)
	s.player.age = 36
	var kept := 0
	for seed_value in 30:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var recs := Retirement.run(s, rng)
		if not recs.any(func(r): return r["soldier"] == s.player):
			kept += 1
	check(kept == 30 and s.player.retired_year == 0, "the age pass must never retire him before 40 (kept %d)" % kept)
	s.player.age = Retirement.ALWAYS_AGE
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 1
	var recs2 := Retirement.run(s, rng2)
	check(recs2.any(func(r): return r["soldier"] == s.player) and s.player.retired_year == s.year, "he retires at %d like everyone" % Retirement.ALWAYS_AGE)


func test_retiring_by_choice() -> void:
	var s := _career(704, 0.9)
	check(PlayerLegacy.retire_error(s) != "", "no retiring mid-season")
	check(PlayerLegacy.retire(s) != "", "retire() must refuse mid-season")
	check(not PlayerLegacy.retired(s), "still active")
	s.sim_to_end_of_season()
	check(PlayerLegacy.retire_error(s) == "", "retiring is allowed in the offseason: %s" % PlayerLegacy.retire_error(s))
	var team := s.user_team()
	var year := s.year
	check(PlayerLegacy.retire(s) == "", "retire failed")
	check(PlayerLegacy.retired(s) and s.player.retired_year == year, "not marked retired")
	check(not team.org().has(s.player) and s.player.contract == null, "he should be off the club with no contract")
	check(s.retirements.any(func(r): return r["soldier"] == s.player), "he should be in the league's retirements")
	check(PlayerLegacy.vote_year(s) == year + HallOfFame.WAIT_SEASONS, "the vote is %d years later" % HallOfFame.WAIT_SEASONS)
	check(PlayerLegacy.verdict(s) == &"waiting", "verdict should be waiting, got %s" % PlayerLegacy.verdict(s))
	check(PlayerLegacy.retire(s) != "", "cannot retire twice")
	check(PlayerCoach.weekly(s) == "", "the coach has nothing to say to a retired player")
	check(s.user_team() == team, "his old club is still the 'user team' for the screens")


func test_recap_rows() -> void:
	var s := _career(705, 0.9)
	for i in 4:
		s.sim_week()
	var r := PlayerLegacy.recap(s)
	check(r.has("seasons") and r.has("totals") and r.has("final") and r.has("verdict"), "recap fields")
	check(r["verdict"] == &"active", "active careers have no verdict yet")
	for row in r["seasons"]:
		check(row["matches"] > 0 and row["team"] != "" and row["letter"] != "", "season row incomplete: %s" % row)
	check(int(r["totals"]["matches"]) == int(s.player.career["matches"]), "totals are the career")


func test_milestones_and_retirement_survive_save() -> void:
	var s := _career(706, 0.9)
	for i in 3:
		s.sim_week()
	PlayerLegacy.update(s)
	s.sim_to_end_of_season()
	PlayerLegacy.retire(s)
	var text := SaveSystem.to_text(s)
	var loaded := SaveSystem.from_text(text)
	check(loaded != null, "load failed")
	if loaded == null:
		return
	check(SaveSystem.to_text(loaded) == text, "re-serialization not stable")
	check(PlayerLegacy.retired(loaded) and loaded.player_milestones.size() == s.player_milestones.size(), "retired state or milestones lost")
	check(PlayerLegacy.verdict(loaded) == &"waiting", "verdict changed on load")


func test_the_real_vote_decides() -> void:
	var s := _career(707, 0.95)
	# A big career so the vote has something to judge.
	var p := s.player
	p.career["matches"] = 200
	p.career["kills"] = 4000
	p.career["assists"] = 1500
	p.career["damage"] = 500000
	p.career["deaths"] = 2000
	p.career["clutches"] = 80
	p.career["mvps"] = 30
	s.sim_to_end_of_season()
	PlayerLegacy.retire(s)
	var v := PlayerLegacy.simulate_to_vote(s)
	check(v == &"inducted" or v == &"not_inducted", "the vote should have happened, got %s" % v)
	check(s.year >= PlayerLegacy.vote_year(s), "the league should have reached the vote year (%d vs %d)" % [s.year, PlayerLegacy.vote_year(s)])
	check((v == &"inducted") == HallOfFame.is_member(s, p), "verdict and the Hall disagree")
	var r := PlayerLegacy.recap(s)
	check(r["verdict"] == v, "recap verdict")
	if v == &"inducted":
		check(not HallOfFame.entry_of(s, p).is_empty() and float(HallOfFame.entry_of(s, p)["score"]) >= HallOfFame.THRESHOLD, "an inductee scored at least the bar")

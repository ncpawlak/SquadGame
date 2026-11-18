extends SceneTree
## Player mode phase 3 tests (draft entry, report, draft night, undrafted path, save):
##   godot --headless --path . --script res://tests/player_draft_tests.gd
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


## A player-mode season with the combine locked in at `score` on every task.
func _season(seed_value: int, score: float, archetype := &"sniper") -> Season:
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
	rng.seed = 11
	season.player_combine.finalize(season.player, rng)
	season.player_combine_done = true
	return season


func test_begin_puts_the_player_in_the_class() -> void:
	var s := _season(2024, 0.8)
	PlayerDraft.begin(s)
	var d := s.player_draft
	check(d != null and s.player_prospect != null, "no draft or prospect")
	check(d.prospects.size() == Draft.CLASS_SIZE + 1, "class is %d, expected %d" % [d.prospects.size(), Draft.CLASS_SIZE + 1])
	check(d.prospects.has(s.player_prospect) and s.player_prospect.soldier == s.player, "player is not in the class")
	check(d.year == s.year - 1, "class year should be last year's")
	check(d.order.size() == Draft.ROUNDS * s.league.teams.size(), "wrong number of picks")
	check(s.player_draft_state == PlayerDraft.STATE_READY, "state should be ready")
	check(s.player_prospect.projected_rank >= 1 and s.player_prospect.projected_rank <= d.prospects.size(), "rank out of range")
	var first := d.prospects.size()
	PlayerDraft.begin(s)
	check(d == s.player_draft and d.prospects.size() == first, "begin must be idempotent")
	check(not s.draft.is_started() and s.draft.year == s.year, "the normal class must be untouched")
	# Worst team picks first.
	check(d.order[0].team_ovr() <= d.order[1].team_ovr(), "the weakest team should pick first")


func test_report_is_consistent() -> void:
	var s := _season(2025, 0.8)
	PlayerDraft.begin(s)
	var r := PlayerDraft.report(s)
	check(int(r["lo"]) <= int(r["rank"]) and int(r["rank"]) <= int(r["hi"]), "rank %s outside range %s-%s" % [r["rank"], r["lo"], r["hi"]])
	check(r["windows"].size() == Stats.UPGRADABLE_GROUPS.size(), "a window per rating group")
	for g in r["windows"]:
		var w: Vector2i = r["windows"][g]
		check(w.x >= 0 and w.y < Draft.TIER_COUNT and w.x <= w.y, "bad tier window %s for %s" % [w, g])
		check(Draft.window_text(g, w) != "", "no text for %s" % g)
	check(String(r["round_text"]) != "", "no projection text")
	check(r["area_grade"] != "", "no area grade")
	# A stronger combine should project at least as high.
	var weak := _season(2025, 0.1)
	PlayerDraft.begin(weak)
	check(PlayerDraft.report(weak)["rank"] >= r["rank"], "a weaker combine projected higher")


func test_a_strong_player_is_drafted_and_lands() -> void:
	var s := _season(2026, 1.0)
	PlayerDraft.begin(s)
	var res := PlayerDraft.run(s)
	check(res["pick"] > 0 and res["team"] != null, "a perfect combine should be drafted (pick %s)" % res["pick"])
	if res["team"] == null:
		return
	var team: Team = res["team"]
	check(s.player_draft_state == PlayerDraft.STATE_DONE and s.player_team == team, "not landed on his club")
	check(team.green_team.has(s.player), "he should start on the Green Team")
	check(s.player_pick == res["pick"] and s.player.draft_pick == res["pick"], "pick not recorded")
	check(s.player.draft_year == s.year - 1, "draft year should be last year's")
	check(s.player.contract != null and s.player.contract.green, "needs a Green Team deal")
	check(s.player.contract.signed_year == s.year, "the deal should run from this season, not last year (%d)" % s.player.contract.signed_year)
	check(s.player.callsign == "Zzyzx", "callsign changed")
	check(s.user_team() == team, "the user's team should be his club")
	var users := 0
	for t in s.league.teams:
		if t.user_controlled:
			users += 1
		check(t.green_team.size() <= Team.GREEN_SIZE, "%s green team is over the limit" % t.abbrev)
	check(users == 1, "exactly one user team, got %d" % users)
	check(s.past_drafts.has(s.player_draft), "draft not filed away")
	check(s.player_draft.is_complete(), "draft not complete")
	# No other soldier may share his callsign.
	var same := 0
	for so in s.league.all_soldiers():
		if so != s.player and so.callsign.to_lower() == "zzyzx":
			same += 1
	check(same == 0, "%d other soldiers share his callsign" % same)
	check(PlayerDraft.story(s) != "", "no story")


func test_a_weak_player_goes_undrafted_and_picks_a_team() -> void:
	var s := _season(2027, 0.0)
	PlayerDraft.begin(s)
	var res := PlayerDraft.run(s)
	check(res["pick"] == 0 and res["team"] == null, "a floor-level combine should go undrafted")
	check(s.player_draft_state == PlayerDraft.STATE_OFFERS, "should be choosing offers")
	check(s.player_team == null, "no club yet")
	var offers := PlayerDraft.undrafted_offers(s)
	check(offers.size() == PlayerDraft.OFFERS, "wrong offer count")
	var seen := {}
	for t in offers:
		seen[t] = true
	check(seen.size() == offers.size(), "duplicate offers")
	check(PlayerDraft.sign_undrafted(s, s.league.teams[0] if not offers.has(s.league.teams[0]) else s.league.teams[1]) != "" or offers.size() == s.league.teams.size(), "signed with a team that made no offer")
	check(s.player_team == null, "a refused signing must not land him")
	var err := PlayerDraft.sign_undrafted(s, offers[1])
	check(err == "", "signing failed: %s" % err)
	check(s.player_team == offers[1] and offers[1].green_team.has(s.player), "not on the Green Team")
	check(s.player_draft_state == PlayerDraft.STATE_DONE and s.user_team() == offers[1], "not done or not the user's team")
	check(s.player_pick == 0, "pick should stay 0")
	check(offers[1].green_team.size() <= Team.GREEN_SIZE, "green team over the limit")
	check(offers[1].green_team.has(s.player), "he was cut by the trim")
	check(PlayerDraft.sign_undrafted(s, offers[0]) != "", "a second signing must be refused")


func test_the_draft_is_reproducible() -> void:
	var a := _season(31, 0.7)
	var b := _season(31, 0.7)
	PlayerDraft.begin(a)
	PlayerDraft.begin(b)
	var ra := PlayerDraft.run(a)
	var rb := PlayerDraft.run(b)
	check(ra["pick"] == rb["pick"], "same seed, different pick: %s vs %s" % [ra["pick"], rb["pick"]])
	check(a.player_prospect.projected_rank == b.player_prospect.projected_rank, "same seed, different projection")


func test_draft_state_survives_save() -> void:
	var s := _season(2028, 0.9)
	PlayerDraft.begin(s)
	PlayerDraft.run(s)
	var text := SaveSystem.to_text(s)
	var loaded := SaveSystem.from_text(text)
	check(loaded != null, "from_text returned null")
	if loaded == null:
		return
	check(SaveSystem.to_text(loaded) == text, "re-serialization not stable")
	check(loaded.player_draft_state == s.player_draft_state and loaded.player_pick == s.player_pick, "draft state lost")
	if s.player_team != null:
		check(loaded.player_team != null and loaded.league.teams.has(loaded.player_team), "player team is not the league's team object")
		check(loaded.player_team.green_team.has(loaded.player), "player not on the loaded team")
	check(loaded.player_prospect != null and loaded.player_prospect.soldier == loaded.player, "prospect lost its soldier")

extends SceneTree
## Player mode phase 4 tests (grades, coach, AI-run club, archetype growth caps, multi-season sim):
##   godot --headless --path . --script res://tests/player_career_tests.gd
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


## A player-mode season past the draft, his combine locked in at `score`.
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


func _next_season(s: Season) -> void:
	s.sim_to_end_of_season()
	var guard := 0
	while s.offseason_stage != Season.OFF_DONE and guard < 30:
		s.advance_offseason()
		guard += 1
	s.start_next_season()


func test_letters() -> void:
	check(PlayerGrade.letter_for(100.0) == "A+" and PlayerGrade.letter_for(97.0) == "A+", "97+ is A+")
	check(PlayerGrade.letter_for(85.0) == "B" or PlayerGrade.letter_for(85.0) == "B+", "85 is a B")
	check(PlayerGrade.letter_for(72.0) == "C-", "72 is C-, got %s" % PlayerGrade.letter_for(72.0))
	check(PlayerGrade.letter_for(59.9) == "F" and PlayerGrade.letter_for(0.0) == "F", "below 60 is F")
	var prev := 101.0
	for sc in range(100, -1, -1):
		var l := PlayerGrade.letter_for(float(sc))
		check(l != "", "no letter for %d" % sc)
		prev = float(sc)
	check(PlayerGrade.bonus_xp(60.0) == 0.0 and PlayerGrade.bonus_xp(100.0) <= PlayerGrade.MAX_BONUS_XP and PlayerGrade.bonus_xp(90.0) > PlayerGrade.bonus_xp(80.0), "bonus xp should rise with the grade and be capped")


func test_impact_rewards_production() -> void:
	var base := {"kills": 5, "deaths": 5, "assists": 2, "damage": 500.0}
	var better := {"kills": 9, "deaths": 3, "assists": 4, "damage": 900.0}
	var worse := {"kills": 2, "deaths": 8, "assists": 0, "damage": 200.0}
	for role in [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]:
		check(PlayerGrade.impact(better, role) > PlayerGrade.impact(base, role), "more production should score higher (role %d)" % role)
		check(PlayerGrade.impact(worse, role) < PlayerGrade.impact(base, role), "less production should score lower (role %d)" % role)


func test_player_is_the_user_but_the_club_is_ai() -> void:
	var s := _career(404, 1.0)
	check(s.player_team != null and s.user_team() == s.player_team, "user_team should be his club")
	for t in s.league.teams:
		check(not t.user_controlled, "%s is user-controlled in player mode" % t.abbrev)
	check(s.player.player_controlled, "player is not flagged")
	check(s.user_roster_error() == "", "no roster error gating the AI-run club")
	check(not Trades.tradeable(s.player), "the AI must not be able to trade him")
	check(s.release_player(s.user_team(), s.player) == 0 and s.user_team().org().has(s.player), "the AI must not release him")


func test_coach_status_and_call_up() -> void:
	var s := _career(405, 1.0)
	var team := s.user_team()
	var st := PlayerCoach.status(s)
	check(st["text"] != "", "no status text")
	check(st["where"] == PlayerCoach.WHERE_GREEN or st["where"] == PlayerCoach.WHERE_BENCH or st["where"] == PlayerCoach.WHERE_STARTER, "unexpected status %s" % st["where"])
	if team.green_team.has(s.player):
		# Make him clearly the best soldier in the club and he gets called up, someone goes down for him.
		for stat in Stats.ALL:
			s.player.stats[stat] = 95
		var before := team.roster.size()
		var line := PlayerCoach.weekly(s)
		check(line != "" and team.roster.has(s.player) and not team.green_team.has(s.player), "he should have been called up: %s" % line)
		check(team.roster.size() <= Team.ROSTER_SIZE, "roster over the limit after the call-up")
		check(s.player_notes.size() == 1, "the call-up should be noted")
		check(before >= 0, "sanity")
	# A weak player stays down, and the status says what it takes.
	var w := _career(406, 0.0)
	var wt := w.user_team()
	var ws := PlayerCoach.status(w)
	if wt.green_team.has(w.player):
		check(ws["where"] == PlayerCoach.WHERE_GREEN and "OVR" in String(ws["text"]), "a Green Team status should name the OVR needed: %s" % ws["text"])
		check(PlayerCoach.weekly(w) == "", "a weak player must not be called up")


func test_growth_caps_follow_the_archetype() -> void:
	var s := _career(407, 1.0, &"sniper")
	var p := s.player
	var caps := Archetypes.growth_caps(&"sniper")
	check(p.stat_caps == caps and not caps.is_empty(), "stat caps not applied")
	check(caps[Stats.SPEED] < caps[Stats.LONG_ACC], "a sniper should cap lower on speed than long range")
	# Spend a lot of skill points on every group: no stat may pass its cap.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for g in Stats.UPGRADABLE_GROUPS:
		p.group_caps[g] = 99
	for round in 400:
		p.skill_points = 50
		for g in Stats.UPGRADABLE_GROUPS:
			Progression.upgrade_group(p, g, rng)
	for stat in caps:
		check(p.stats[stat] <= int(caps[stat]), "%s reached %d, past its cap %d" % [stat, p.stats[stat], caps[stat]])
	check(p.stats[Stats.SPEED] <= int(caps[Stats.SPEED]) and p.stats[Stats.LONG_ACC] > p.stats[Stats.SPEED], "specialty should show in the stats")


func test_ai_never_spends_his_skill_points() -> void:
	var s := _career(408, 1.0)
	s.player.skill_points = 7
	Progression.auto_spend_team(s.user_team())
	check(s.player.skill_points == 7, "auto spend touched the player's points")
	s.player.intensity = Soldier.INTENSITY_HEAVY
	Training.ai_set_intensities(s.user_team())
	check(s.player.intensity == Soldier.INTENSITY_HEAVY, "AI changed the player's training intensity")


func test_two_seasons_with_the_player() -> void:
	var s := _career(409, 0.9)
	var p := s.player
	var team := s.user_team()
	var first_year := s.year
	s.sim_to_end_of_season()
	var log := PlayerGrade.log_for(s, first_year)
	check(log.size() > 0, "no game log after a season")
	var graded := 0
	for e in log:
		check(e.has("reason") and e.has("opp") and e.has("week"), "log entry missing fields")
		if e["played"]:
			graded += 1
			check(e["score"] >= 0.0 and e["score"] <= 100.0 and String(e["letter"]) != "", "bad grade %s" % e)
	var sm := PlayerGrade.summary(log)
	check(sm["games"] == graded, "summary game count")
	check(p.level > 1 or p.skill_points > 0 or p.xp > 0, "no XP after a season")
	check(s.user_team().org().has(p) or s.league.free_agents.has(p) == false, "player vanished during the season")
	check(team.org().has(p), "the AI moved or released the player in season 1")
	# Offseason and a second season.
	var guard := 0
	while s.offseason_stage != Season.OFF_DONE and guard < 30:
		s.advance_offseason()
		guard += 1
	s.start_next_season()
	check(s.year == first_year + 1, "next season did not start")
	check(s.user_team().org().has(p), "the player was released or traded in the offseason")
	check(not s.league.free_agents.has(p), "the player is in free agency")
	check(p.contract != null, "the player has no contract")
	s.sim_to_end_of_season()
	check(PlayerGrade.log_for(s, first_year + 1).size() > 0, "no game log in season 2")
	check(s.user_team().org().has(p), "the player left his club in season 2")


func test_career_survives_save() -> void:
	var s := _career(410, 0.9)
	for i in 3:
		s.sim_week()
	check(s.player_log.size() >= 1, "no log entries after three weeks")
	var text := SaveSystem.to_text(s)
	var loaded := SaveSystem.from_text(text)
	check(loaded != null, "load failed")
	if loaded == null:
		return
	check(SaveSystem.to_text(loaded) == text, "re-serialization not stable")
	check(loaded.player_log.size() == s.player_log.size(), "log lost")
	check(loaded.user_team() == loaded.player_team and loaded.player.player_controlled and not loaded.player.stat_caps.is_empty(), "player state lost")
	for e in loaded.player_log:
		check(loaded.league.teams.has(e["opp"]), "log opponent is not the league's team object")

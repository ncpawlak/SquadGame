extends SceneTree
## Wear tests (#141): the career regression meter, its tiers, caps kept, camp rehab, AI untouched:
##   godot --headless --path . --script res://tests/wear_tests.gd
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


func _soldier(age: int, value := 80, player := true) -> Soldier:
	var s := Soldier.new()
	s.id = 1
	s.first_name = "Test"
	s.last_name = "Soldier"
	s.age = age
	s.stats = Stats.make_uniform(value)
	for g in Stats.UPGRADABLE_GROUPS:
		s.group_caps[g] = 90
	s.player_controlled = player
	return s


func test_tiers_and_group_weights() -> void:
	check(Wear.tier_of(0.0) == Wear.FRESH and Wear.tier_of(34.9) == Wear.FRESH, "under 35 is fresh")
	check(Wear.tier_of(35.0) == Wear.WORN and Wear.tier_of(59.9) == Wear.WORN, "35-59 is worn")
	check(Wear.tier_of(60.0) == Wear.BEATEN and Wear.tier_of(79.9) == Wear.BEATEN, "60-79 is beaten up")
	check(Wear.tier_of(80.0) == Wear.BROKEN, "80+ is broken")
	check(Wear.group_wear(50.0, Stats.PHYSICALITY) > Wear.group_wear(50.0, Stats.MENTALITY), "physical wears before mental")
	# 45 wear: physicality worn (45), mentality still fresh (18).
	check(Wear.tier_of(Wear.group_wear(45.0, Stats.PHYSICALITY)) == Wear.WORN, "physicality worn at 45")
	check(Wear.tier_of(Wear.group_wear(45.0, Stats.MENTALITY)) == Wear.FRESH, "mentality fresh at 45")


func test_season_change_terms() -> void:
	var s := _soldier(23)
	s.wear_weeks = 17
	s.wear_fatigue_sum = 17.0 * 50.0
	s.wear_games = 11
	# Age 23: no age term. Load: 0.08 * 50 + 0.05 * 11 = 4.55. Relief: passive 1.
	check(is_equal_approx(Wear.season_change(s, 0), 4.0 + 0.55 - 1.0), "load minus passive, no age term (got %.2f)" % Wear.season_change(s, 0))
	s.age = 25
	check(is_equal_approx(Wear.season_change(s, 0), 4.0 + 4.55 - 1.0), "the age term starts at 24")
	s.wear_injuries = 1
	check(is_equal_approx(Wear.season_change(s, 0), 4.0 + 4.55 + 5.0 - 1.0), "a major injury adds 5")
	s.wear_spa_sum = 17.0 * 2.0
	check(is_equal_approx(Wear.season_change(s, 0), 4.0 + 4.55 + 5.0 - 1.0 - 6.0), "spa level 2 all season takes off 6")
	s.wear_rehab = 3
	s.wear_spa_sum = 0.0
	check(is_equal_approx(Wear.season_change(s, 2), 4.0 + 4.55 + 5.0 - 1.0 - 3.0 - 2.0), "camp rehab and the lab take off 1 a step")


func test_close_season_resets_counters_and_clamps() -> void:
	var s := _soldier(30)
	s.wear = 98.0
	s.wear_weeks = 10
	s.wear_fatigue_sum = 800.0
	s.wear_games = 11
	s.wear_injuries = 2
	s.wear_rehab = 2
	Wear.close_season(s, 0)
	check(s.wear == Wear.WEAR_MAX, "wear is clamped at 100")
	check(s.wear_weeks == 0 and s.wear_fatigue_sum == 0.0 and s.wear_games == 0 and s.wear_injuries == 0 and s.wear_rehab == 0, "season counters reset")
	s.wear = 1.0
	s.wear_weeks = 1
	Wear.close_season(s, 5)
	check(s.wear == 0.0, "wear never goes below 0")


func test_fresh_players_never_regress_and_caps_are_kept() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var s := _soldier(27)
	s.wear = 10.0
	var before := s.stats.duplicate()
	var r := Wear.regress(s, rng)
	check(r.is_empty() and s.stats == before, "no regression below the worn tier")
	# Broken: all groups at 80+ wear hit hard over many rolls, but the caps do not move.
	var caps := s.group_caps.duplicate()
	s.wear = 100.0
	var hit := 0
	for i in 20:
		var t := _soldier(34)
		t.wear = 100.0
		var b := t.group_rating(Stats.PHYSICALITY)
		Wear.regress(t, rng)
		if t.group_rating(Stats.PHYSICALITY) < b:
			hit += 1
		check(t.group_caps == caps, "caps are untouched by regression")
	check(hit >= 10, "a broken player loses physicality most seasons (%d of 20)" % hit)


func test_age_player_uses_wear_not_age() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	# A 35-year-old with no wear does not decline (the old rule would cut every group).
	var vet := _soldier(35)
	var before := vet.stats.duplicate()
	var r := Aging.age_soldier(vet, rng)
	check(vet.age == 36 and vet.stats == before and r["changes"].is_empty(), "a well-kept veteran holds his ratings")
	# The same age as an AI soldier still declines.
	var ai := _soldier(35, 80, false)
	Aging.age_soldier(ai, rng)
	check(ai.group_rating(Stats.PHYSICALITY) < 80, "AI soldiers keep the old yearly decline")
	check(ai.group_caps[Stats.PHYSICALITY] < 90, "and their caps still fall")


func test_a_trainer_wears_out_slowly_and_spa_helps() -> void:
	# 8 seasons from 24 with a typical load and no spa vs. spa level 2 all year.
	var plain := _soldier(24)
	var spa := _soldier(24)
	for i in 8:
		for s in [plain, spa]:
			s.wear_weeks = 17
			s.wear_fatigue_sum = 17.0 * 45.0
			s.wear_games = 11
		spa.wear_spa_sum = 17.0 * 2.0
		Wear.close_season(plain, 0)
		Wear.close_season(spa, 0)
		plain.age += 1
		spa.age += 1
	check(plain.wear >= 35.0, "a no-spa trainer is worn by 32 (%.1f)" % plain.wear)
	check(spa.wear < plain.wear - 20.0, "spa holds Wear down (%.1f vs %.1f)" % [spa.wear, plain.wear])


func test_record_hooks() -> void:
	var s := _soldier(26)
	s.fatigue = 40.0
	Wear.record_week(s, 2)
	Wear.record_week(s, 0)
	check(s.wear_weeks == 2 and s.wear_spa_sum == 2.0 and s.wear_fatigue_sum == 80.0, "weeks are recorded")
	Wear.record_game(s)
	Wear.record_injury(s, 2)
	Wear.record_injury(s, Wear.MAJOR_INJURY_WEEKS)
	check(s.wear_games == 1 and s.wear_injuries == 1, "only a major injury counts")

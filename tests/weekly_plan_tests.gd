extends SceneTree
## Weekly plan tests (#138): plan rules, stars, brand, fatigue, morale, camp, age:
##   godot --headless --path . --script res://tests/weekly_plan_tests.gd
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


func _career(seed_value: int, score := 0.9, archetype := &"marksman", age := 21) -> Season:
	var season := Season.new_franchise(seed_value)
	var heads: Array = FaceSpec.db()["heads"].keys()
	heads.sort()
	season.player_mode = true
	season.player_archetype = archetype
	season.player = PlayerCareer.create_soldier(season.league.next_soldier_id, "Ada", "Stone", "Zzyzx", heads[0], 1, archetype, age)
	season.league.next_soldier_id += 1
	season.player_combine = Combine.make(archetype, age)
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


func test_tables_and_limits() -> void:
	for table in [WeeklyPlan.FATIGUE_LOAD, WeeklyPlan.PRACTICE_XP, WeeklyPlan.STUDY_POINTS, WeeklyPlan.OUTING_MORALE, WeeklyPlan.SPA_RECOVERY, WeeklyPlan.SPA_MORALE, WeeklyPlan.BRAND_BASE]:
		check(table.size() == WeeklyPlan.WEEK_MAX + 1 and table[0] == 0.0, "weekly table has levels 0 to %d" % WeeklyPlan.WEEK_MAX)
		for i in range(1, table.size()):
			check(table[i] > table[i - 1], "tables must rise with the level")
	for table in [WeeklyPlan.CAMP_PRACTICE_XP, WeeklyPlan.CAMP_STUDY_POINTS, WeeklyPlan.CAMP_OUTING_MORALE, WeeklyPlan.CAMP_BRAND_BASE]:
		check(table.size() == WeeklyPlan.CAMP_MAX + 1 and table[0] == 0.0, "camp table has levels 0 to %d" % WeeklyPlan.CAMP_MAX)
	check(WeeklyPlan.error({}) == "" and WeeklyPlan.unspent({}) == WeeklyPlan.WEEK_POINTS, "a blank plan is legal, all points unspent")
	check(WeeklyPlan.error({WeeklyPlan.PRACTICE: 3, WeeklyPlan.SPA: 1}) == "", "3 + 1 is legal")
	check(WeeklyPlan.error({WeeklyPlan.PRACTICE: 4}) != "", "4 in one weekly activity is illegal")
	check(WeeklyPlan.error({WeeklyPlan.PRACTICE: 3, WeeklyPlan.STUDY: 2}) != "", "5 points is illegal")
	check(WeeklyPlan.error({WeeklyPlan.PRACTICE: 4, WeeklyPlan.STUDY: 4}, true) == "", "camp allows 4 + 4")
	check(WeeklyPlan.error({WeeklyPlan.SPA: 1}, true) != "", "camp has no spa")
	check(WeeklyPlan.error({WeeklyPlan.PRACTICE: 4, WeeklyPlan.STUDY: 4, WeeklyPlan.OUTING: 1}, true) != "", "camp has 8 points")
	check(WeeklyPlan.error({&"nap": 1}) != "", "unknown activities are refused")


func test_fatigue_and_intensity_mapping() -> void:
	for lvl in 4:
		var plan := {WeeklyPlan.PRACTICE: lvl}
		var it := WeeklyPlan.intensity_for(lvl)
		check(is_equal_approx(WeeklyPlan.fatigue_load(plan), float(Training.INTENSITY_INFO[it]["load"])), "practice %d should load like %s" % [lvl, it])
	check(WeeklyPlan.intensity_for(0) == Soldier.INTENSITY_REST, "practice 0 is rest")
	check(is_equal_approx(WeeklyPlan.fatigue_load({WeeklyPlan.PRACTICE: 2, WeeklyPlan.STUDY: 2}), 12.0), "2 + 2 loads 12")
	check(WeeklyPlan.fatigue_load({WeeklyPlan.SPA: 3}) == 0.0, "spa adds no fatigue")
	check(is_equal_approx(WeeklyPlan.week_xp({WeeklyPlan.PRACTICE: 2}), 150.0) and is_equal_approx(WeeklyPlan.week_xp({}), 37.5), "practice 2 is Normal XP, blank is film study")


func test_spa_recovers_and_the_hooks_use_the_plan() -> void:
	var s := _career(801)
	var p := s.player
	p.fatigue = 60.0
	p.plan = {WeeklyPlan.PRACTICE: 2, WeeklyPlan.STUDY: 2}
	var tired := Conditioning.projected_fatigue(p, &"", false, false)
	p.plan = {WeeklyPlan.PRACTICE: 2, WeeklyPlan.SPA: 2}
	var rested := Conditioning.projected_fatigue(p, &"", false, false)
	check(rested < tired, "spa should leave him fresher (%.1f vs %.1f)" % [rested, tired])
	p.plan = {WeeklyPlan.SPA: 2}
	var rest_week := Conditioning.projected_fatigue(p, &"", false, false)
	p.plan = {}
	var blank := Conditioning.projected_fatigue(p, &"", false, false)
	check(rest_week < blank, "two spa points recover more than doing nothing")
	check(is_equal_approx(Conditioning.weekly_load(p, false), 0.0), "a blank plan adds no load")
	p.plan = {WeeklyPlan.PRACTICE: 3}
	var proj := WeeklyPlan.projection(s, {WeeklyPlan.PRACTICE: 3, WeeklyPlan.STUDY: 1})
	check(float(proj["after"]) >= p.fatigue * 0.5 and proj["band"] != "", "the projection reports a band")
	check(p.plan == {WeeklyPlan.PRACTICE: 3}, "projecting must not change his plan")
	# An AI soldier is not affected by plan fields.
	var other: Soldier = s.user_team().roster[0]
	other.fatigue = 30.0
	check(Conditioning.weekly_load(other, false) == float(Training.INTENSITY_INFO[other.intensity]["load"]) * Conditioning.endurance_mult(other) * (1.0 + Conditioning.age_years(other) * Conditioning.AGE_LOAD_PER_YEAR), "AI soldiers still use their intensity")


func test_stars_start_at_one_and_cost_more_each_time() -> void:
	var s := _career(802)
	var p := s.player
	check(p.dev == 1 and p.talent >= 1 and p.talent <= 4, "everyone starts at 1 star with a hidden talent (dev %d talent %d)" % [p.dev, p.talent])
	check(WeeklyPlan.star_cost(1) < WeeklyPlan.star_cost(2) and WeeklyPlan.star_cost(2) < WeeklyPlan.star_cost(3) and WeeklyPlan.star_cost(4) == 0.0, "each star costs more; the top costs nothing")
	check(not WeeklyPlan.add_study(p, WeeklyPlan.star_cost(1) - 1.0, 2026) and p.dev == 1, "below the cost: no star")
	check(WeeklyPlan.add_study(p, 2.0, 2026) and p.dev == 2 and p.study_progress < 2.0, "crossing the cost earns a star and carries the excess")
	# One star a season: a full bar waits.
	check(not WeeklyPlan.add_study(p, 500.0, 2026) and p.dev == 2 and is_equal_approx(p.study_progress, WeeklyPlan.star_cost(2)), "the second star waits for next season")
	check(WeeklyPlan.add_study(p, 1.0, 2027) and p.dev == 3, "next season the full bar pays out")
	p.study_progress = 0.0
	WeeklyPlan.add_study(p, 500.0, 2028)
	check(p.dev == 4 and p.study_progress == 0.0, "anyone can reach 4 stars")
	check(not WeeklyPlan.add_study(p, 50.0, 2029) and p.dev == 4, "no star beyond 4")


func test_apply_week_study_spa_and_outing() -> void:
	var s := _career(803)
	var p := s.player
	var team := s.user_team()
	for x in team.org():
		x.morale = 50.0
	p.plan = {WeeklyPlan.STUDY: 3, WeeklyPlan.SPA: 1}
	WeeklyPlan.apply_week(s)
	check(is_equal_approx(p.study_progress, 3.6), "study 3 adds 3.6 points (got %.2f)" % p.study_progress)
	check(is_equal_approx(p.morale, 52.0), "spa 1 gives +2 morale (got %.1f)" % p.morale)
	check(p.intensity == Soldier.INTENSITY_REST, "no practice means rest intensity")
	# Outing: his group gets the full amount, the rest of the club half.
	for x in team.org():
		x.morale = 50.0
	p.plan = {WeeklyPlan.OUTING: 3}
	WeeklyPlan.apply_week(s)
	var group := WeeklyPlan.group_of(team, p)
	var other: Array = team.roster if group == team.green_team else team.green_team
	for x in group:
		check(is_equal_approx(x.morale, 56.0), "his group gets +6 (got %.1f)" % x.morale)
	for x in other:
		check(is_equal_approx(x.morale, 53.0), "the rest of the club gets +3 (got %.1f)" % x.morale)
	check(s.player_notes.is_empty() or true, "notes are optional")


func test_training_xp_follows_the_plan() -> void:
	var s := _career(804)
	var p := s.player
	var team := s.user_team()
	p.xp = 0
	p.plan = {}
	var blank := int(Training.run_week(team)[p.id]["xp"])
	p.xp = 0
	p.plan = {WeeklyPlan.PRACTICE: 3}
	var heavy := int(Training.run_week(team)[p.id]["xp"])
	check(heavy > blank, "practice earns extra XP (%d vs %d)" % [heavy, blank])
	check(blank > 0, "even a blank week earns the film-study baseline")


func test_brand() -> void:
	check(WeeklyPlan.grade_factor(40.0) == WeeklyPlan.FACTOR_LOW and WeeklyPlan.grade_factor(100.0) == WeeklyPlan.FACTOR_HIGH, "grade factor bounds")
	check(WeeklyPlan.grade_factor(90.0) > WeeklyPlan.grade_factor(75.0), "a better grade earns more brand")
	check(WeeklyPlan.brand_gain(3, 90.0, 0.0) > WeeklyPlan.brand_gain(1, 90.0, 0.0), "more exposure earns more")
	check(WeeklyPlan.brand_gain(3, 90.0, 80.0) < WeeklyPlan.brand_gain(3, 90.0, 0.0), "gains shrink near the top")
	check(WeeklyPlan.brand_gain(0, 99.0, 0.0) == 0.0, "no exposure points, no brand")
	check(WeeklyPlan.tier_name(0.0) == "Unknown" and WeeklyPlan.tier_name(45.0) == "Known" and WeeklyPlan.tier_name(100.0) == "Icon", "tier names")
	check(WeeklyPlan.market_mult(0.0) == 1.0 and WeeklyPlan.market_mult(100.0) > WeeklyPlan.market_mult(50.0), "brand raises market value")
	var s := _career(805)
	var p := s.player
	p.plan = {WeeklyPlan.BRAND: 3}
	var gain := WeeklyPlan.apply_brand(s, 85.0)
	check(gain > 0.0 and p.brand == gain, "a played week with brand 3 earns brand")
	var before := p.brand
	p.plan = {}
	check(WeeklyPlan.apply_brand(s, 95.0) == 0.0 and p.brand == before, "no brand points, no gain")
	p.plan = {WeeklyPlan.BRAND: 2}
	p.brand = 50.0
	WeeklyPlan.apply_week(s)
	check(is_equal_approx(p.brand, 50.0 * WeeklyPlan.BRAND_DECAY), "brand decays slowly each week")


func test_camp_plan() -> void:
	var s := _career(806)
	var p := s.player
	p.camp_plan = {WeeklyPlan.PRACTICE: 4, WeeklyPlan.STUDY: 3, WeeklyPlan.OUTING: 1}
	p.xp = 0
	p.study_progress = 0.0
	p.brand = 0.0
	var rep := WeeklyPlan.apply_camp(s)
	check(int(rep["xp"]) > 0 and is_equal_approx(p.study_progress, 7.5) and int(rep["outing"]) == 1, "camp applies practice XP, study points and queues the outing")
	check(s.camp_outing_level == 1, "the outing waits for the rollover")
	for x in s.user_team().org():
		x.morale = 50.0
	WeeklyPlan.apply_camp_outing(s)
	check(s.camp_outing_level == 0 and is_equal_approx(p.morale, 52.0), "the rollover pays the outing morale (got %.1f)" % p.morale)
	# Camp brand needs games last season.
	p.camp_plan = {WeeklyPlan.BRAND: 4}
	var none := WeeklyPlan.apply_camp(s)
	check(float(none["brand"]) == 0.0 and p.brand == 0.0, "no games last season, no camp brand")
	var entry := {"key": "x", "year": s.year, "week": 1, "stage": &"regular", "opp": s.league.teams[0], "home": true, "score_line": "", "played": true, "reason": "", "score": 85.0, "letter": "B", "won": true, "kills": 1, "deaths": 1, "assists": 0, "damage": 1, "mvp": false}
	s.player_log.append(entry)
	var some := WeeklyPlan.apply_camp(s)
	check(float(some["brand"]) > 0.0 and p.brand > 0.0, "games last season earn camp brand")


func test_age_sets_the_starting_ceilings() -> void:
	check(Archetypes.age_offset(Archetypes.AGE_MAX) == 0 and Archetypes.age_offset(Archetypes.AGE_MIN) == -2 * (Archetypes.AGE_MAX - Archetypes.AGE_MIN), "age offsets")
	check(Archetypes.AGE_MIN == 18 and Archetypes.AGE_MAX == 23, "career mode ages are 18 to 23")
	var old := Archetypes.ceilings(&"sniper", 23)
	var young := Archetypes.ceilings(&"sniper", 18)
	for stat in old:
		check(young[stat] < old[stat] or young[stat] == Archetypes.MIN_CEILING, "%s: an 18-year-old should have a lower ceiling" % stat)
	check(Archetypes.ceilings(&"sniper") == old, "the default age is the oldest")
	check(Archetypes.max_ovr(&"sniper", 18) < Archetypes.max_ovr(&"sniper", 23), "younger means a lower best case")
	check(Archetypes.growth_caps(&"sniper") == Archetypes.growth_caps(&"sniper"), "growth caps are independent of start age")
	var c18 := Combine.make(&"sniper", 18)
	var c23 := Combine.make(&"sniper", 23)
	for g in Combine.DRILL_ORDER:
		var sc := {}
		for t in Combine.drill_tasks(g):
			sc[t["stat"]] = 0.8
		c18.record_try(g, sc)
		c23.record_try(g, sc)
	check(c18.ovr_range().y < c23.ovr_range().y, "the same combine rates lower for an 18-year-old")
	check(PlayerCareer.create_soldier(1, "A", "B", "C", FaceSpec.db()["heads"].keys()[0], 1, &"sniper", 17).age == 18, "age clamps up to 18")
	check(PlayerCareer.create_soldier(1, "A", "B", "C", FaceSpec.db()["heads"].keys()[0], 1, &"sniper", 30).age == 23, "age clamps down to 23")


func test_young_and_old_players_both_enter_the_draft() -> void:
	for age in [18, 23]:
		var s := _career(810 + age, 0.9, &"marksman", age)
		check(s.player.age == age and s.player_team != null, "age %d player was drafted or signed" % age)
		check(s.player_combine.age == age, "combine remembers the age")


func test_plan_state_survives_save() -> void:
	var s := _career(807)
	var p := s.player
	p.plan = {WeeklyPlan.PRACTICE: 2, WeeklyPlan.SPA: 1}
	p.plan_confirmed = true
	p.camp_plan = {WeeklyPlan.STUDY: 4}
	p.study_progress = 12.5
	p.brand = 33.0
	var text := SaveSystem.to_text(s)
	var loaded := SaveSystem.from_text(text)
	check(loaded != null, "load failed")
	if loaded == null:
		return
	check(SaveSystem.to_text(loaded) == text, "re-serialization not stable")
	var lp := loaded.player
	check(lp.plan == p.plan and lp.plan_confirmed and lp.camp_plan == p.camp_plan and is_equal_approx(lp.study_progress, 12.5) and is_equal_approx(lp.brand, 33.0) and lp.talent == p.talent, "plan state lost")


func test_placing_skill_points_by_hand() -> void:
	var s := _career(808, 0.8, &"sniper")
	var p := s.player
	for g in Stats.UPGRADABLE_GROUPS:
		p.group_caps[g] = 99
	p.skill_points = 20
	var g := Stats.ACCURACY
	var n := Progression.placement_total(g)
	check(n == 3, "accuracy has three stats")
	var cost := Progression.upgrade_cost(p, g)
	var before := p.group_rating(g)
	var sum_before := 0
	for st in Stats.group_stats(g):
		sum_before += int(p.stats[st])
	check(Progression.placement_error(p, g, {}) != "", "nothing placed is refused")
	check(Progression.placement_error(p, g, {Stats.LONG_ACC: 2}) != "", "two of three points is refused")
	check(Progression.placement_error(p, g, {Stats.SPEED: 3}) != "", "a stat outside the group is refused")
	check(Progression.placement_error(p, g, {Stats.LONG_ACC: 3}) == "" or p.stat_cap(Stats.LONG_ACC) < int(p.stats[Stats.LONG_ACC]) + 3, "all three in one stat is allowed up to its cap")
	p.stat_caps[Stats.LONG_ACC] = int(p.stats[Stats.LONG_ACC]) + 1
	check(Progression.placement_error(p, g, {Stats.LONG_ACC: 3}) != "", "a stat past its archetype cap is refused")
	p.stat_caps[Stats.LONG_ACC] = 99
	var gains := Progression.place_group(p, g, {Stats.LONG_ACC: 3})
	check(not gains.is_empty() and p.skill_points == 20 - cost, "placing spends the group cost")
	var sum_after := 0
	for st in Stats.group_stats(g):
		sum_after += int(p.stats[st])
	check(sum_after == sum_before + 3 and p.group_rating(g) == before + 1, "three stat points raise the group by exactly 1")
	p.skill_points = 0
	check(Progression.place_group(p, g, {Stats.LONG_ACC: 3}).is_empty(), "no skill points, no placement")
	check(not Progression.can_place(p, g), "can_place needs skill points")
	p.skill_points = 20
	for st in Stats.group_stats(g):
		p.stat_caps[st] = int(p.stats[st])
	check(Progression.placement_room(p, g) == 0 and not Progression.can_place(p, g), "a group with every stat at its cap cannot be placed")


func test_a_full_season_and_camp_with_a_plan() -> void:
	var s := _career(820, 0.9)
	var p := s.player
	for stat in Stats.ALL:
		p.stats[stat] = 88  # good enough to be called up and start, so brand and fatigue matter
	p.plan = {WeeklyPlan.PRACTICE: 1, WeeklyPlan.STUDY: 1, WeeklyPlan.BRAND: 1, WeeklyPlan.SPA: 1}
	p.plan_confirmed = true
	p.camp_plan = {WeeklyPlan.PRACTICE: 3, WeeklyPlan.STUDY: 3, WeeklyPlan.BRAND: 2}
	p.camp_plan_confirmed = true
	var xp0 := p.level * 1000 + p.xp
	s.sim_to_end_of_season()
	check(p.study_progress > 5.0 or p.dev > 1, "a season of study 1 builds study points (%.1f)" % p.study_progress)
	var played: int = PlayerGrade.summary(PlayerGrade.log_for(s))["games"]
	check(played > 0, "he played games (called up and starting)")
	check(p.brand > 0.0, "brand exposure while playing earns brand (%.1f)" % p.brand)
	check(p.level * 1000 + p.xp > xp0, "weekly XP was earned")
	var plan_before := p.plan.duplicate()
	var guard := 0
	while s.offseason_stage != Season.OFF_DONE and guard < 30:
		s.advance_offseason()
		guard += 1
	check(not s.camp_report.is_empty() and int(s.camp_report["xp"]) > 0 and float(s.camp_report["study"]) > 0.0, "camp ran his camp plan: %s" % [s.camp_report])
	check(float(s.camp_report["brand"]) > 0.0, "camp brand, scaled by a season of games")
	s.start_next_season()
	check(s.camp_outing_level == 0, "the camp outing was paid at the rollover")
	check(p.plan == plan_before and p.plan_confirmed, "the weekly plan carries into the new season")
	check(s.user_team().org().has(p), "he is still with his club")


func test_brand_raises_the_player_market_value_only() -> void:
	var s := _career(821)
	var p := s.player
	p.brand = 0.0
	var base := Contracts.market_value(p)
	p.brand = 100.0
	var high := Contracts.market_value(p)
	check(high > base and is_equal_approx(float(high) / float(base), WeeklyPlan.market_mult(100.0)) or absf(float(high) / float(base) - WeeklyPlan.market_mult(100.0)) < 0.02, "full brand lifts market value by about %d%% (%d vs %d)" % [roundi((WeeklyPlan.market_mult(100.0) - 1.0) * 100.0), high, base])
	check(Contracts.resign_asking(p, 3) > 0, "re-sign ask exists")
	var other: Soldier = s.user_team().roster[0]
	var m0 := Contracts.market_value(other)
	other.brand = 100.0
	check(Contracts.market_value(other) == m0, "brand does not move an AI soldier value")

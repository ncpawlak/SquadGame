extends SceneTree
## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 0 if all tests pass, 1 otherwise.

var _failures := 0
var _passes := 0
var _current := ""


func _init() -> void:
	var tests := [
		"test_generator_ranges",
		"test_ovr_depends_on_position",
		"test_auto_lineup_fills_scheme",
		"test_assign_swaps_players",
		"test_match_structure",
		"test_match_is_deterministic",
		"test_different_seeds_vary",
		"test_better_team_wins_more",
		"test_each_combat_stat_matters",
		"test_xp_levels_and_points",
		"test_age_scales_xp",
		"test_spend_respects_caps_and_costs",
		"test_auto_spend_prefers_role_stats",
		"test_training_focus",
		"test_match_awards_xp",
	]
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


# --- helpers ---------------------------------------------------------------

func make_soldier(id: int, value: int, overrides := {}) -> Soldier:
	var s := Soldier.new()
	s.id = id
	s.first_name = "Test"
	s.last_name = "Soldier%d" % id
	s.age = 26
	s.stats = Stats.make_uniform(value)
	for k in overrides:
		s.stats[k] = overrides[k]
	s.caps = Stats.make_uniform(99)
	return s


func make_team(id: int, value: int, overrides := {}) -> Team:
	var t := Team.new()
	t.id = id
	t.name = "Team %d" % id
	t.abbrev = "T%d" % id
	for i in Team.ROSTER_SIZE:
		t.roster.append(make_soldier(id * 100 + i, value, overrides))
	t.auto_lineup()
	return t


func win_rate(a: Team, b: Team, matches: int, seed_base := 1000) -> float:
	var wins := 0
	for i in matches:
		# Alternate sides so slot order in the engine can't bias results.
		if i % 2 == 0:
			wins += 1 if MatchEngine.simulate(a, b, seed_base + i).winner_index == 0 else 0
		else:
			wins += 1 if MatchEngine.simulate(b, a, seed_base + i).winner_index == 1 else 0
	return float(wins) / matches


# --- tests -----------------------------------------------------------------

func test_generator_ranges() -> void:
	var league := League.generate(42)
	check(league.teams.size() == 2, "league should have 2 teams")
	for t in league.teams:
		check(t.roster.size() == Team.ROSTER_SIZE, "%s roster size %d" % [t.name, t.roster.size()])
		check(t.starters().size() == 5, "%s should have 5 starters" % t.name)
		for s in t.roster:
			check(s.age >= PlayerGenerator.MIN_AGE and s.age <= PlayerGenerator.MAX_AGE, "age out of range")
			for stat in Stats.ALL:
				check(s.stats[stat] >= 0 and s.stats[stat] <= 99, "%s out of range" % stat)
				check(s.caps[stat] >= s.stats[stat] and s.caps[stat] <= 99, "cap invalid for %s" % stat)


func test_ovr_depends_on_position() -> void:
	var brawler := make_soldier(1, 50, {&"short_acc": 90, &"strength": 90, &"toughness": 90})
	var sniper := make_soldier(2, 50, {&"awareness": 90, &"medium_acc": 90, &"long_acc": 90, &"teamwork": 90})
	var runner := make_soldier(3, 50, {&"speed": 90, &"agility": 90, &"endurance": 90})
	check(brawler.ovr_at_role(Scheme.Role.FRONTMAN) > brawler.ovr_at_role(Scheme.Role.CENTER), "brawler should rate higher at frontman")
	check(sniper.ovr_at_role(Scheme.Role.CENTER) > sniper.ovr_at_role(Scheme.Role.FLEX), "sniper should rate higher at center")
	check(runner.ovr_at_role(Scheme.Role.FLEX) > runner.ovr_at_role(Scheme.Role.FRONTMAN), "runner should rate higher at flex")
	check(Scheme.ovr_for_role(Stats.make_uniform(70), Scheme.Role.CENTER) == 70, "uniform stats -> same OVR")


func test_auto_lineup_fills_scheme() -> void:
	var t := make_team(1, 50)
	t.roster[7].stats = make_soldier(0, 50, {&"short_acc": 95, &"strength": 95, &"toughness": 95}).stats
	t.roster[6].stats = make_soldier(0, 50, {&"speed": 95, &"agility": 95, &"endurance": 95}).stats
	t.auto_lineup()
	check(t.starters().size() == 5, "5 starters")
	var fm := [t.lineup[&"FM1"], t.lineup[&"FM2"]]
	check(fm.has(t.roster[7]), "best frontman should be at FM")
	check(t.lineup[&"LFX"] == t.roster[6] or t.lineup[&"RFX"] == t.roster[6], "best flex should be at a flex slot")


func test_assign_swaps_players() -> void:
	var t := make_team(1, 50)
	var a: Soldier = t.lineup[&"FM1"]
	var b: Soldier = t.lineup[&"CTR"]
	t.assign(&"FM1", b)
	check(t.lineup[&"FM1"] == b and t.lineup[&"CTR"] == a, "assigning a starter swaps slots")
	var bench_guy: Soldier = t.bench()[0]
	t.assign(&"CTR", bench_guy)
	check(t.lineup[&"CTR"] == bench_guy and t.bench().has(a), "assigning bench player benches the starter")


func test_match_structure() -> void:
	var league := League.generate(7)
	var r := MatchEngine.simulate(league.teams[0], league.teams[1], 99)
	check(r.score[r.winner_index] == MatchEngine.ROUNDS_TO_WIN, "winner must reach 4")
	check(r.score[1 - r.winner_index] < MatchEngine.ROUNDS_TO_WIN, "loser below 4")
	check(r.rounds.size() >= 4 and r.rounds.size() <= 7, "4-7 rounds played")
	check(r.events.size() > 10, "play-by-play has events")
	check(r.mvp_id != -1, "mvp chosen")
	var kills := 0
	var deaths := 0
	for id in r.box:
		kills += r.box[id]["kills"]
		deaths += r.box[id]["deaths"]
		check(r.box[id]["hits"] <= r.box[id]["shots"], "hits <= shots")
		check(r.box[id]["rounds_played"] == r.rounds.size(), "every starter plays every round")
	check(kills == deaths, "kills == deaths (%d vs %d)" % [kills, deaths])
	check(r.box.size() == 10, "10 box score lines")


func test_match_is_deterministic() -> void:
	var league := League.generate(7)
	var a := MatchEngine.simulate(league.teams[0], league.teams[1], 12345)
	var b := MatchEngine.simulate(league.teams[0], league.teams[1], 12345)
	check(a.score == b.score, "same score")
	check(a.events == b.events, "same play-by-play")
	check(str(a.box) == str(b.box), "same box score")


func test_different_seeds_vary() -> void:
	var a := make_team(1, 60)
	var b := make_team(2, 60)
	var outcomes := {}
	for i in 30:
		outcomes[MatchEngine.simulate(a, b, i).score_line()] = true
	check(outcomes.size() > 3, "evenly matched teams should produce varied scorelines (%d)" % outcomes.size())
	var wr := win_rate(a, b, 200)
	check(wr > 0.38 and wr < 0.62, "identical teams ~50%% (got %.2f)" % wr)


func test_better_team_wins_more() -> void:
	var wr := win_rate(make_team(1, 75), make_team(2, 55), 100)
	check(wr > 0.9, "75-rated team should crush 55-rated team (%.2f)" % wr)
	wr = win_rate(make_team(1, 65), make_team(2, 60), 200)
	check(wr > 0.55, "65 should beat 60 more often (%.2f)" % wr)


## Raising any single combat stat (others equal) should improve the win rate.
## Injury is excluded because injuries aren't simulated yet (its win rate should sit near 50%).
## This is the slowest test (~2,600 matches).
func test_each_combat_stat_matters() -> void:
	var report: Array[String] = []
	for stat in Stats.ALL:
		if stat == Stats.INJURY:
			continue
		var wr := win_rate(make_team(1, 45, {stat: 95}), make_team(2, 45), 200, 5000)
		report.append("%s=%.2f" % [Stats.ABBREV[stat], wr])
		check(wr > 0.55, "%s at 95 vs 45 should help (win rate %.2f)" % [stat, wr])
	print("    stat sensitivity: ", ", ".join(report))


func test_xp_levels_and_points() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var s := make_soldier(1, 50)
	s.age = 27  # multiplier 1.0
	var r := Progression.gain_xp(s, Progression.xp_to_next(1) - 1, rng)
	check(r["levels"] == 0 and s.level == 1, "just under threshold: no level")
	r = Progression.gain_xp(s, 1, rng)
	check(r["levels"] == 1 and s.level == 2 and s.xp == 0, "level up exactly at threshold")
	check(s.skill_points == Progression.SKILL_POINTS_PER_LEVEL, "points granted")
	Progression.gain_xp(s, Progression.xp_to_next(2) + Progression.xp_to_next(3), rng)
	check(s.level == 4, "multi-level gain (level %d)" % s.level)


func test_age_scales_xp() -> void:
	var rng := RandomNumberGenerator.new()
	var young := make_soldier(1, 50)
	young.age = 20
	var old := make_soldier(2, 50)
	old.age = 33
	var ry := Progression.gain_xp(young, 100, rng)
	var ro := Progression.gain_xp(old, 100, rng)
	check(ry["xp"] > ro["xp"], "young player gains more xp (%d vs %d)" % [ry["xp"], ro["xp"]])


func test_spend_respects_caps_and_costs() -> void:
	var s := make_soldier(1, 50)
	s.caps[&"speed"] = 51
	s.skill_points = 10
	check(Progression.spend_point(s, &"speed"), "can raise below cap")
	check(s.stats[&"speed"] == 51 and s.skill_points == 9, "raised by 1 for 1 point")
	check(not Progression.spend_point(s, &"speed"), "cannot pass cap")
	s.stats[&"awareness"] = 85
	check(Progression.spend_point(s, &"awareness"), "can raise 85")
	check(s.skill_points == 6, "85 costs 3 points (have %d)" % s.skill_points)
	s.skill_points = 2
	s.stats[&"grouping"] = 95
	check(not Progression.spend_point(s, &"grouping"), "unaffordable upgrade refused")


func test_auto_spend_prefers_role_stats() -> void:
	var s := make_soldier(1, 50)
	s.skill_points = 12
	var raised := Progression.auto_spend(s, Scheme.Role.FRONTMAN)
	check(s.skill_points == 0, "spends all points when possible")
	check(raised.has(&"short_acc"), "frontman spending includes short range acc")
	check(not raised.has(&"long_acc"), "frontman should not spend on long range acc first")
	var capped := make_soldier(2, 50)
	capped.caps = capped.stats.duplicate()
	capped.skill_points = 5
	Progression.auto_spend(capped, Scheme.Role.CENTER)
	check(capped.skill_points == 5, "fully capped player keeps points")


func test_training_focus() -> void:
	var rng := RandomNumberGenerator.new()
	var t := make_team(1, 50)
	for s in t.roster:
		s.age = 27
	var focus_id := t.roster[0].id
	var reports := Training.run_week(t, {focus_id: &"long_acc"}, rng)
	check(reports[focus_id]["xp"] > reports[t.roster[1].id]["xp"], "focus player gains more xp")
	check(t.roster[0].usage[&"long_acc"] > 0.0 or reports[focus_id]["levels"] > 0, "focus stat gets usage")


func test_match_awards_xp() -> void:
	var rng := RandomNumberGenerator.new()
	var league := League.generate(3)
	var a := league.teams[0]
	var b := league.teams[1]
	var before := {}
	for s in a.starters() + b.starters():
		before[s.id] = s.level * 100000 + s.xp
	var r := MatchEngine.simulate(a, b, 1)
	var reports := Progression.award_match_xp(r, rng)
	check(reports.size() == 10, "all 10 starters get xp")
	for s in a.starters() + b.starters():
		check(s.level * 100000 + s.xp > before[s.id], "%s gained xp" % s.full_name())
		check(s.career["matches"] == 1, "career match recorded")
	var w_xp := 0
	var l_xp := 0
	for s in r.winner().starters():
		w_xp += reports[s.id]["xp"]
	for s in r.loser().starters():
		l_xp += reports[s.id]["xp"]
	check(w_xp > l_xp, "winners earn more xp in total")

extends SceneTree
## Career growth tests (#141): cap raises, gear, sponsors, stories and camp specials:
##   godot --headless --path . --script res://tests/career_growth_tests.gd
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



func _capped(season: Season, group: StringName) -> void:
	var p := season.player
	for st in Stats.group_stats(group):
		p.stats[st] = p.stat_cap(st)
	p.group_caps[group] = maxi(p.group_cap(group), p.group_rating(group))


func test_cap_raise_needs_a_capped_group_and_the_offseason() -> void:
	var season := _career(901)
	var p := season.player
	check(CapRaise.window_error(season) != "", "no raise in season")
	season.phase = Season.PHASE_OFFSEASON
	check(CapRaise.window_error(season) == "", "the offseason opens the window")
	check(CapRaise.eligible_groups(season).is_empty(), "nothing is capped on day one")
	_capped(season, Stats.PHYSICALITY)
	check(CapRaise.eligible_groups(season) == [Stats.PHYSICALITY] or CapRaise.eligible_groups(season).has(Stats.PHYSICALITY), "a filled group is eligible")
	check(CapRaise.group_error(season, Stats.MENTALITY) != "", "an unfilled group is not")


func test_cap_raise_size_and_effect() -> void:
	var season := _career(902)
	var p := season.player
	season.phase = Season.PHASE_OFFSEASON
	_capped(season, Stats.PHYSICALITY)
	check(CapRaise.size(season, Stats.PHYSICALITY) == CapRaise.BASE, "base raise is +2")
	p.camp_focus = Stats.PHYSICALITY
	p.cap_story_bonus = 1
	check(CapRaise.size(season, Stats.PHYSICALITY) == CapRaise.BASE + 2, "camp special and a story add 1 each")
	var cap_before := p.group_cap(Stats.PHYSICALITY)
	var stat_cap_before := p.stat_cap(Stats.SPEED)
	var rep := CapRaise.apply(season, Stats.PHYSICALITY)
	check(not rep.is_empty() and int(rep["size"]) == 4, "applied +4")
	check(p.group_cap(Stats.PHYSICALITY) == mini(99, cap_before + 4), "the group cap rose")
	check(p.stat_cap(Stats.SPEED) == mini(99, stat_cap_before + 4), "so did each stat's cap")
	check(p.camp_focus == &"" and p.cap_story_bonus == 0, "the camp special and story points are used up")
	check(CapRaise.apply(season, Stats.PHYSICALITY).is_empty(), "only one raise an offseason")
	check(CapRaise.window_error(season) != "", "the window is closed after a raise")


func test_cap_raise_never_passes_99_or_6() -> void:
	var season := _career(903)
	var p := season.player
	season.phase = Season.PHASE_OFFSEASON
	_capped(season, Stats.ACCURACY)
	for st in Stats.group_stats(Stats.ACCURACY):
		p.stat_caps[st] = 97
		p.stats[st] = 97
	p.group_caps[Stats.ACCURACY] = 97
	p.camp_focus = Stats.ACCURACY
	p.cap_story_bonus = 5
	check(CapRaise.size(season, Stats.ACCURACY) <= CapRaise.MAX_RAISE, "never more than +6")
	CapRaise.apply(season, Stats.ACCURACY)
	check(p.group_cap(Stats.ACCURACY) == 99 and p.stat_cap(Stats.LONG_ACC) == 99, "caps stop at 99")

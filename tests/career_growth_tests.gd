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


func test_gear_bonus_is_additive_and_removable() -> void:
	var season := _career(910)
	var p := season.player
	var base := p.stats.duplicate()
	var ovr0 := p.best_ovr()
	p.set_gear_bonus({Stats.SPEED: 4, Stats.LONG_ACC: 3})
	check(p.stats[Stats.SPEED] == base[Stats.SPEED] + 4 and p.stats[Stats.LONG_ACC] == base[Stats.LONG_ACC] + 3, "gear adds to the effective ratings")
	check(p.base_stat(Stats.SPEED) == base[Stats.SPEED] and p.base_ovr() == ovr0, "base ratings and base OVR ignore gear")
	check(p.best_ovr() >= ovr0, "effective OVR does not drop")
	p.set_gear_bonus({Stats.SPEED: 1})
	check(p.stats[Stats.SPEED] == base[Stats.SPEED] + 1 and p.stats[Stats.LONG_ACC] == base[Stats.LONG_ACC], "swapping gear replaces the old bonus")
	p.set_gear_bonus({})
	check(p.stats == base and p.gear_delta.is_empty(), "removing gear restores the base exactly")


func test_gear_clamps_at_99_and_keeps_the_base() -> void:
	var season := _career(911)
	var p := season.player
	p.stats[Stats.SPEED] = 97
	p.set_gear_bonus({Stats.SPEED: 5})
	check(p.stats[Stats.SPEED] == 99 and p.base_stat(Stats.SPEED) == 97, "clamped at 99, base kept")
	p.set_gear_bonus({})
	check(p.stats[Stats.SPEED] == 97, "and the base comes back")


func test_gear_does_not_eat_skill_point_room() -> void:
	var season := _career(912)
	var p := season.player
	var room := Progression.placement_room(p, Stats.PHYSICALITY)
	p.set_gear_bonus({Stats.SPEED: 4, Stats.AGILITY: 4})
	check(Progression.placement_room(p, Stats.PHYSICALITY) == room, "room counts the base rating, not the gear")


func test_gear_items_follow_the_tier_ladders() -> void:
	var icon := Gear.item(&"cryo", Gear.HELMET)
	check(icon["bonus"].values() == [5, 4, 3, 2] and icon["bonus"].size() == 4, "an Icon helmet is +5 +4 +3 +2 on four stats")
	var rifle := Gear.item(&"sigsawyer", Gear.RIFLE)
	check(rifle["bonus"].values() == [5, 4, 3], "an Icon rifle is specialized: three stats, top values")
	check(Gear.item(&"haynes", Gear.BOOTS)["bonus"].size() == 1, "an Unknown item boosts one stat")
	check(Gear.item(&"overarmour", Gear.VEST)["bonus"].values() == [3, 2, 1], "a Known vest is +3 +2 +1")
	for b in Gear.BRANDS:
		for slot in Gear.SLOTS:
			var it := Gear.item(b["id"], slot)
			check(it["bonus"].size() >= 1 and it["bonus"].size() <= 4, "1-4 stats: %s %s" % [b["id"], slot])
			for st in it["bonus"]:
				check(Gear.SLOT_POOLS[slot].has(st), "%s is in the %s pool" % [st, slot])
	check(Gear.brands_in_tier(0).size() == 3 and Gear.brands_in_tier(4).size() == 3, "three sponsors a tier")
	check(Gear.tier_for_brand(0.0) == 0 and Gear.tier_for_brand(45.0) == 2 and Gear.tier_for_brand(95.0) == 4, "brand unlocks tiers")


func test_gear_equip_set_bonus_and_cap() -> void:
	var season := _career(913)
	var p := season.player
	var base := p.base_ovr()
	check(Gear.equip(p, Gear.item(&"cryo", Gear.HELMET)) != "", "no deal, no gear")
	p.deals.append({"brand": &"cryo", "slots": [Gear.HELMET, Gear.VEST, Gear.BOOTS], "years_left": 2})
	for slot in [Gear.HELMET, Gear.VEST, Gear.BOOTS]:
		check(Gear.equip(p, Gear.item(&"cryo", slot)) == "", "equips with a deal")
	check(p.best_ovr() > base and p.base_ovr() == base, "effective OVR rose, base did not")
	check(Gear.set_text(p.gear_slots).begins_with("Cryo Precision set"), "three items wake the set bonus")
	for stat in p.gear_delta:
		check(int(p.gear_delta[stat]) <= Gear.STAT_CAP, "per-stat gear cap")
	# Ending the deal removes the items and the bonus.
	p.deals.clear()
	Gear.prune(p)
	check(p.gear_slots.is_empty() and p.gear_delta.is_empty() and p.best_ovr() == base, "an ended deal takes its gear back")

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


func test_cap_raise_needs_the_offseason_and_an_open_group() -> void:
	var season := _career(901)
	var p := season.player
	check(CapRaise.window_error(season) != "", "no raise in season")
	season.phase = Season.PHASE_OFFSEASON
	check(CapRaise.window_error(season) == "", "the offseason opens the window")
	check(CapRaise.eligible_groups(season).has(Stats.PHYSICALITY), "a group does not need to be maxed")
	_capped(season, Stats.PHYSICALITY)
	check(CapRaise.eligible_groups(season).has(Stats.PHYSICALITY), "and a maxed one is fine too")


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
	check(icon["bonus"].values() == [10, 8, 6, 4] and icon["bonus"].size() == 4, "an Icon helmet is +10 +8 +6 +4 on four stats")
	var rifle := Gear.item(&"sigsawyer", Gear.RIFLE)
	check(rifle["bonus"].values() == [10, 8, 6], "an Icon rifle is specialized: three stats, top values")
	check(Gear.item(&"haynes", Gear.BOOTS)["bonus"].size() == 1, "an Unknown item boosts one stat")
	check(Gear.item(&"overarmour", Gear.VEST)["bonus"].values() == [6, 4, 2], "a Known vest is +6 +4 +2")
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


func test_sponsors_follow_heat_and_tier() -> void:
	var season := _career(920)
	var p := season.player
	p.brand = 0.0
	season.player_pick = 0
	check(Sponsors.refresh(season) == 0 and p.offers.is_empty(), "no brand, no draft slot, no offers")
	season.player_pick = 3  # a top pick on the Green Team
	var heat := float(Sponsors.heat(season)["heat"])
	check(Sponsors.prospect_value(season) >= 25.0 and Sponsors.tier_ceiling(season) == 1, "a high pick lifts the ceiling one tier")
	p.brand = 70.0
	p.dev = 4
	check(Sponsors.tier_ceiling(season) >= 3, "brand sets the ceiling")
	check(float(Sponsors.heat(season)["heat"]) > heat, "brand adds heat")
	var now := Sponsors.prospect_value(season)
	season.player_log.append({"year": season.year, "week": 1})
	season.year += 3
	check(Sponsors.prospect_value(season) < now, "a draft slot fades over the years")


func test_sponsor_offers_accept_counter_and_overlap() -> void:
	var season := _career(921)
	var p := season.player
	p.brand = 85.0
	p.dev = 3
	season.player_pick = 1
	var n := 0
	for i in 6:
		season.week += 1
		n += Sponsors.refresh(season)
	check(n > 0 and not p.offers.is_empty() and p.offers.size() <= Sponsors.MAX_OFFERS, "a hot player draws offers (got %d)" % n)
	var o: Dictionary = p.offers[0]
	check(o["slots"].size() >= 1 and int(o["money"]) > 0 and int(o["years"]) >= 1, "an offer has slots, money and years")
	var base := p.base_ovr()
	check(Sponsors.accept(season, o) == "", "accepting works")
	check(Sponsors.holds(p, o["brand"]) and p.base_ovr() == base and p.best_ovr() >= base, "a deal equips its gear, base unchanged")
	var keep := {"brand": &"haynes", "slots": [Gear.RIFLE], "money": 4, "years": 1, "floor": 0.0, "style": Sponsors.STYLE_MONEY, "countered": false, "expires": season.year + 1, "reason": ""}
	p.offers = [keep]
	var r := Sponsors.counter(season, keep)
	check(r == "countered" or r == "withdrawn", "a counter resolves")
	if r == "countered":
		check(keep["style"] == Sponsors.STYLE_GEAR and Sponsors.counter(season, keep) == "", "only one counter, and it flips the style")
	var clash := {"brand": &"nyke", "slots": Sponsors.covered(p).duplicate(), "money": 1, "years": 1, "floor": 0.0}
	check(Sponsors.accept_error(p, clash) != "", "overlapping slots are refused")


func test_sponsor_season_end_pays_and_drops() -> void:
	var season := _career(922)
	var p := season.player
	p.brand = 50.0
	p.deals = [{"brand": &"overarmour", "slots": [Gear.HELMET], "money": 30, "years_left": 1, "floor": 30.0, "signed": season.year},
		{"brand": &"pooma", "slots": [Gear.BOOTS], "money": 30, "years_left": 3, "floor": 60.0, "signed": season.year}]
	p.gear_slots[Gear.HELMET] = Gear.item(&"overarmour", Gear.HELMET)
	p.gear_slots[Gear.BOOTS] = Gear.item(&"pooma", Gear.BOOTS)
	Gear.recalc(p)
	var rep := Sponsors.season_end(season)
	check(p.cash == 60 and rep["paid"] == 60, "both deals pay")
	check(p.deals.is_empty(), "one ran out, one broke its brand floor")
	check(p.gear_slots.is_empty() and p.gear_delta.is_empty(), "their gear went with them")


func _entry(score: float) -> Dictionary:
	return {"played": true, "score": score}


func test_group_training_needs_morale_and_a_streak() -> void:
	var season := _career(930)
	var p := season.player
	p.morale = 90.0
	var sp := p.skill_points
	Stories.after_match(season, _entry(70.0), true)
	Stories.after_match(season, _entry(70.0), true)
	check(p.skill_points == sp, "two wins is not a streak")
	Stories.after_match(season, _entry(70.0), true)
	check(p.skill_points >= sp + 2 and p.skill_points <= sp + 4, "a streak with high morale earns 2-4 skill points")
	var after := p.skill_points
	Stories.after_match(season, _entry(70.0), true)
	check(p.skill_points == after, "once a season")
	Stories.after_match(season, _entry(70.0), false)
	check(p.streak == 0, "a loss resets the streak")
	var low := _career(931).player
	low.morale = 50.0


func test_breakthrough_and_media_storm() -> void:
	var season := _career(932)
	var p := season.player
	var m0 := p.morale
	Stories.after_match(season, _entry(96.0), true)
	check(p.cap_story_bonus == 1 and p.morale > m0, "a 95+ grade is a breakthrough: morale and a cap-raise point")
	p.brand = 60.0
	Stories.after_match(season, _entry(50.0), false)
	check(p.stories.size() == 1 and p.stories[0]["kind"] == "storm", "a bad night with a name makes a media storm")
	var b := p.brand
	var msg := Stories.choose(season, p.stories[0], "face")
	check(msg != "" and p.brand == b + 3.0 and p.stories.is_empty(), "facing the press builds brand")


func test_captain_mentor_and_camp_special() -> void:
	var season := _career(933)
	var p := season.player
	season.phase = Season.PHASE_OFFSEASON
	Stories.set_camp_special(season, &"")
	_capped(season, Stats.OBJECTIVE)
	var plain := CapRaise.size(season, Stats.OBJECTIVE)
	check(Stories.set_camp_special(season, Stats.OBJECTIVE) == "" and p.camp_focus == Stats.OBJECTIVE, "a camp special picks a group")
	check(Stories.set_camp_special(season, &"nonsense") != "", "and refuses a bad one")
	check(CapRaise.size(season, Stats.OBJECTIVE) == plain + 1, "the camp special adds one to that group's raise")
	Stories.set_camp_special(season, &"")
	check(CapRaise.size(season, Stats.OBJECTIVE) == plain, "and clearing it takes it away")
	# A mentor story: 2 skill points and a camp special on the chosen group.
	p.stories.append({"kind": "mentor", "title": "Veteran mentor", "text": "", "choices": [], "year": season.year})
	var sp := p.skill_points
	Stories.choose(season, p.stories[0], String(Stats.ACCURACY))
	check(p.skill_points == sp + 2 and p.camp_focus == Stats.ACCURACY, "the mentor teaches one group")
	p.stories.append({"kind": "captain", "title": "Captaincy", "text": "", "choices": [], "year": season.year})
	Stories.choose(season, p.stories[0], "accept")
	check(p.captain, "accepting makes him captain")


func test_cap_raise_window_follows_the_group_peak_age() -> void:
	var season := _career(940)
	var p := season.player
	season.phase = Season.PHASE_OFFSEASON
	for g in [Stats.PHYSICALITY, Stats.MENTALITY, Stats.ACCURACY]:
		for st in Stats.group_stats(g):
			p.stat_caps[st] = 85
			p.stats[st] = 85
		p.group_caps[g] = 85
	p.age = 24  # physicality peak 28: 4 years left = full
	check(CapRaise.size(season, Stats.PHYSICALITY) == CapRaise.BASE, "full base well before the peak")
	p.age = 26  # 2 years left = tapering
	check(CapRaise.size(season, Stats.PHYSICALITY) == CapRaise.TAPER_BASE, "tapering base near the peak")
	p.camp_focus = Stats.PHYSICALITY
	p.cap_story_bonus = 1
	check(CapRaise.size(season, Stats.PHYSICALITY) == 3, "bonuses still count while tapering")
	p.age = 28  # at the peak: bonuses only, max 2
	check(CapRaise.size(season, Stats.PHYSICALITY) == 2, "at the peak only bonuses, capped at +2")
	p.camp_focus = &""
	p.cap_story_bonus = 0
	check(CapRaise.group_error(season, Stats.PHYSICALITY) != "", "at the peak with no bonus there is nothing to raise")
	p.age = 29
	check(CapRaise.group_error(season, Stats.PHYSICALITY).begins_with("Closed"), "past the peak it is closed")
	check(CapRaise.group_error(season, Stats.MENTALITY) == "" and CapRaise.size(season, Stats.MENTALITY) >= CapRaise.TAPER_BASE, "mentality (peak 33) is still open at 29: %s" % CapRaise.group_error(season, Stats.MENTALITY))
	p.age = 30
	check(CapRaise.group_error(season, Stats.ACCURACY) != "" and not CapRaise.group_error(season, Stats.ACCURACY).begins_with("Closed"), "accuracy (peak 30) is bonuses-only at 30")
	p.age = 31
	check(CapRaise.group_error(season, Stats.ACCURACY).begins_with("Closed"), "and closed at 31")


func test_roster_cut_never_loops_on_the_players_own_soldier() -> void:
	# The player's club is AI-run in career mode; a cut-down with him as the lowest keep value used to spin forever.
	var season := _career(940)
	var team := season.user_team()
	var p := season.player
	if not team.roster.has(p):
		team.green_team.erase(p)
		team.roster.append(p)
	check(p.player_controlled and team.roster.has(p), "the player is on the user team")
	var limit := team.roster.size() - 1
	for s in team.roster:
		if s != p:
			s.stats = s.stats.duplicate()
			for st in s.stats:
				s.stats[st] = 99
	var out := season.trades.restructure(season, team, limit)
	check(team.roster.has(p), "the player is never released")
	check(team.roster.size() <= limit or out["cut"].is_empty(), "it finished (cut someone else, or gave up)")


func test_brand_comes_from_performance_and_honors() -> void:
	var season := _career(941)
	var p := season.player
	p.brand = 0.0
	p.plan[WeeklyPlan.BRAND] = 0
	var gain := WeeklyPlan.apply_brand(season, 85.0)
	check(gain > 0.0 and p.brand > 0.0, "a good game earns brand even with the brand plan at zero")
	var low := WeeklyPlan.brand_gain(0, 85.0, 0.0) + WeeklyPlan.BRAND_PASSIVE
	check(WeeklyPlan.apply_brand(season, 95.0) > WeeklyPlan.apply_brand(season, 62.0), "a better grade earns more brand")
	check(low > 0.0, "the passive base is positive")
	p.brand = 10.0
	season.review = SeasonReview.new()
	season.review.awards.append({"award": "Season MVP", "soldier": p, "team": season.user_team(), "line": {}})
	season.review.all_league.append({"soldier": p, "team": season.user_team(), "role": Scheme.Role.FRONTMAN, "line": {}})
	var b := WeeklyPlan.apply_honors(season)
	check(b > 20.0 and p.brand > 30.0, "an MVP and an All-League pick are a big brand jump (got %.1f)" % b)
	p.brand = 99.0
	var top := WeeklyPlan.apply_honors(season)
	check(top < 5.0 and p.brand <= 100.0, "honors shrink near the top")


## A soldier who took the combine with `story` (same scores and rng for every story, so only the story differs).
func _story_soldier(story: StringName, seed_value := 950) -> Soldier:
	var heads: Array = FaceSpec.db()["heads"].keys()
	heads.sort()
	var s := PlayerCareer.create_soldier(-5, "Ada", "Stone", "Zzyzx", heads[0], 1, &"marksman", 21, story)
	var c := Combine.make(&"marksman", 21)
	for g in Combine.DRILL_ORDER:
		var scores := {}
		for t in Combine.drill_tasks(g):
			scores[t["stat"]] = 0.8
		c.record_try(g, scores)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	c.finalize(s, rng)
	return s


func test_backstory_sets_stars_caps_and_extras() -> void:
	var phenom := _story_soldier(Backstory.PHENOM)
	var late := _story_soldier(Backstory.LATE)
	var walk := _story_soldier(Backstory.WALKON)
	var plain := _story_soldier(Backstory.BALANCED)
	check(phenom.backstory == Backstory.PHENOM and plain.talent == phenom.talent, "the story is kept and the talent roll is the same")
	check(phenom.dev == Backstory.start_stars(Backstory.PHENOM, phenom.talent) and phenom.dev >= 2, "a phenom starts high")
	check(late.dev == Backstory.start_stars(Backstory.LATE, late.talent) and late.dev <= 2, "a late bloomer starts low")
	check(phenom.dev >= plain.dev and plain.dev >= late.dev, "stars order: phenom, balanced, late bloomer")
	var cap_p := 0
	var cap_l := 0
	for g in Stats.UPGRADABLE_GROUPS:
		cap_p += phenom.group_cap(g)
		cap_l += late.group_cap(g)
	check(cap_l > cap_p, "a late bloomer has higher ceilings than a phenom")
	check(phenom.brand >= 15.0 and plain.brand == 0.0, "a phenom starts with a name")
	check(walk.skill_points >= 6 and plain.skill_points == 0, "a walk-on starts with extra skill points")
	check(walk.morale > plain.morale, "and a hungrier morale")


func test_backstory_talent_only_ever_takes_a_star_off() -> void:
	check(Backstory.start_stars(Backstory.BALANCED, 4) == 2 and Backstory.start_stars(Backstory.BALANCED, 1) == 1, "a strong talent never adds a star; talent 1 takes one (not below 1)")
	check(Backstory.start_stars(Backstory.PHENOM, 4) == 3 and Backstory.start_stars(Backstory.PHENOM, 1) == 2, "a phenom starts at 3, or 2 after a weak combine")
	check(Backstory.start_stars(Backstory.LATE, 1) == 1 and Backstory.start_stars(Backstory.LATE, 3) == 1, "a late bloomer stays at one star")


func test_backstory_star_cost_and_sponsor_interest() -> void:
	var late := _story_soldier(Backstory.LATE)
	var plain := _story_soldier(Backstory.BALANCED)
	check(is_equal_approx(WeeklyPlan.star_cost(1, late), WeeklyPlan.star_cost(1) * 0.75) and is_equal_approx(WeeklyPlan.star_cost(1, plain), WeeklyPlan.star_cost(1)), "a late bloomer's stars cost 25% fewer study points")
	var phenom := _story_soldier(Backstory.PHENOM)
	var walk := _story_soldier(Backstory.WALKON)
	check(Backstory.heat_bonus(phenom, 0) > 0.0 and Backstory.heat_bonus(walk, 0) < 0.0, "a phenom draws sponsors, a walk-on does not")
	check(Backstory.heat_bonus(phenom, 4) == 0.0, "the story's pull fades after four seasons")
	check(Backstory.effects(Backstory.PHENOM).size() >= 3, "each story lists what it does")


func _log_games(season: Season, year: int, n: int, score: float) -> void:
	for i in n:
		season.player_log.append({"key": "%d:%d" % [year, i], "year": year, "week": i + 1, "stage": "regular", "played": true, "score": score, "reason": ""})


func test_a_stellar_first_roster_season_earns_a_star() -> void:
	var season := _career(960)
	var p := season.player
	p.dev = 2
	p.dev_year = 0
	season.player_log.clear()
	_log_games(season, season.year, 10, 92.0)
	Stories.season_end(season)
	check(p.dev == 3, "a 92 average over 10 games in the first season is a free star")
	Stories.season_end(season)
	check(p.dev == 3, "once")
	# Not on a later season, and not on a merely good one.
	var late := _career(961)
	late.player_log.clear()
	_log_games(late, late.year - 1, 4, 70.0)
	_log_games(late, late.year, 10, 95.0)
	var d := late.player.dev
	Stories.season_end(late)
	check(late.player.dev == d, "no breakout if he already played the year before")
	var ok := _career(962)
	ok.player_log.clear()
	_log_games(ok, ok.year, 10, 80.0)
	var d2 := ok.player.dev
	Stories.season_end(ok)
	check(ok.player.dev == d2, "a good first season is not enough")


func test_strong_seasons_and_honors_move_the_star_bar() -> void:
	var season := _career(963)
	var p := season.player
	p.dev = 2
	p.dev_year = 0
	p.study_progress = 0.0
	season.player_log.clear()
	_log_games(season, season.year - 1, 4, 60.0)  # not a first roster season
	_log_games(season, season.year, 10, 82.0)
	Stories.season_end(season)
	var cost := WeeklyPlan.star_cost(2, p)
	check(is_equal_approx(p.study_progress, cost * Stories.STRONG_SHARE), "a strong season fills part of the star bar")
	var great := _career(964)
	great.player.dev = 2
	great.player.dev_year = 0
	great.player.study_progress = 0.0
	great.player_log.clear()
	_log_games(great, great.year - 1, 4, 60.0)
	_log_games(great, great.year, 10, 86.0)
	Stories.season_end(great)
	check(great.player.study_progress > cost * Stories.STRONG_SHARE, "a great season fills more of it")
	var h := _career(965)
	h.player.dev = 2
	h.player.dev_year = 0
	h.review = SeasonReview.new()
	check(Stories.honors_study(h) == 0.0, "no honors, no change to the meter")
	h.review.all_league.append({"soldier": h.player, "team": h.user_team(), "role": Scheme.Role.FRONTMAN, "line": {}})
	h.player.study_progress = 0.0
	var share := Stories.honors_study(h)
	check(is_equal_approx(share, 0.45) and is_equal_approx(h.player.study_progress, WeeklyPlan.star_cost(2, h.player) * 0.45), "an All-League pick fills 45% of the next star")
	var m := _career(966)
	m.player.dev = 2
	m.player.dev_year = 0
	m.player.study_progress = 0.0
	m.review = SeasonReview.new()
	m.review.awards.append({"award": "Season MVP", "soldier": m.player, "team": m.user_team(), "line": {}})
	Stories.honors_study(m)
	check(m.player.dev == 3, "an MVP season fills the whole bar and earns the star")


func test_the_review_never_moves_the_career_players_stars() -> void:
	var season := _career(970)
	var p := season.player
	p.dev = 3
	p.dev_year = 0
	season.phase = Season.PHASE_OFFSEASON
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 20:
		p.dev_year = 0
		SeasonReview.run(season, rng)
		check(p.dev == 3, "the re-grade leaves the career player's stars alone")
		if p.dev != 3:
			break


func test_warmup_bonus_curve_and_limits() -> void:
	check(WarmUp.bonus_for(0.0, 0, false) == 0 and WarmUp.bonus_for(1.0, 0, false) == WarmUp.MAX_BONUS, "no score no bonus; a perfect run is the maximum")
	check(WarmUp.bonus_for(0.5, 0, false) == 4 and WarmUp.bonus_for(0.8, 0, false) == 10, "half score is +4, 0.8 is +10")
	check(WarmUp.bonus_for(1.0, 3, false) < WarmUp.bonus_for(1.0, 0, false), "repeating the same group pays less")
	check(WarmUp.bonus_for(1.0, 20, false) >= roundi(WarmUp.MAX_BONUS * WarmUp.REPEAT_MIN), "but never below the floor")
	check(WarmUp.bonus_for(1.0, 0, true) < WarmUp.bonus_for(1.0, 0, false), "playoff games are harder")


func _in_match_week(season: Season) -> void:
	# Move to a regular-season week where the user's team plays.
	for i in 40:
		if season.phase == Season.PHASE_REGULAR and WarmUp.opponent(season) != null:
			return
		season.sim_week()


func test_warmup_applies_for_the_match_only_and_clears() -> void:
	var season := _career(980)
	var p := season.player
	var team := season.user_team()
	if not team.roster.has(p):
		team.green_team.erase(p)
		team.roster.append(p)
	_in_match_week(season)
	check(WarmUp.error(season) == "", "he can warm up in a match week (%s)" % WarmUp.error(season))
	var before: Dictionary = p.stats.duplicate()
	var res := WarmUp.submit(season, Stats.ACCURACY, 1.0)
	check(int(res["bonus"]) > 0 and p.stats == before, "the bonus is pending, not on his ratings yet")
	check(WarmUp.submit(season, Stats.HANDLING, 1.0).is_empty() and WarmUp.error(season) != "", "one warm-up a week")
	var opp := WarmUp.opponent(season)
	var m: ScheduledMatch
	for x in season.matches_for_week(season.week):
		if x.involves(team):
			m = x
	WarmUp.begin(m.home, m.away)
	for st in Stats.GROUPS[Stats.ACCURACY]:
		check(int(p.stats[st]) == mini(99, int(before[st]) + int(res["bonus"])) and p.base_stat(st) == int(before[st]), "during the match the group is boosted and base is untouched")
	check(p.base_ovr() == Scheme.ovr_for_role(before, Scheme.best_role(before)), "base OVR ignores the warm-up")
	WarmUp.end(m.home, m.away)
	check(p.stats == before and p.match_delta.is_empty(), "after the match it is gone")
	season.sim_week()
	check(p.warmup.is_empty() and p.stats == before, "and nothing carries into next week")
	check(opp != null, "there was an opponent")


func test_warmup_stacks_on_gear_and_clamps_at_99() -> void:
	var p := _story_soldier(Backstory.BALANCED)
	p.stats[Stats.SPEED] = 95
	p.set_gear_bonus({Stats.SPEED: 2})
	p.set_match_bonus({Stats.SPEED: 10})
	check(p.stats[Stats.SPEED] == 99 and p.base_stat(Stats.SPEED) == 95, "base 95 + gear 2 + warm-up clamps at 99, base stays 95")
	p.set_gear_bonus({Stats.SPEED: 0})
	check(p.base_stat(Stats.SPEED) == 95, "changing gear during a match keeps the base")
	p.set_match_bonus({})
	check(p.stats[Stats.SPEED] == 95, "clearing both restores the base")


func _to_week(season: Season, week: int) -> void:
	while season.phase == Season.PHASE_REGULAR and season.week < week:
		season.sim_week()


func test_trade_request_needs_a_reason_and_the_window() -> void:
	var season := _career(5)
	_to_week(season, 4)
	var p := season.player
	p.morale = 20.0
	check(PlayerRequest.reasons(season).has(&"unhappy"), "low morale is a reason")
	season.week = Trades.DEADLINE_WEEK + 1
	check(PlayerRequest.error(season) != "", "no requests after the deadline")


func test_trade_request_shops_him_and_other_teams_pay() -> void:
	var season := _career(6)
	_to_week(season, 4)
	var p := season.player
	for st in p.stats.keys():
		p.stats[st] = 82
	p.morale = 20.0
	var old := season.user_team()
	var res := PlayerRequest.shop(season)
	check(res["result"] == "offers" or res["result"] == "none", "an unhappy player is shopped (%s)" % res["text"])
	check(res["result"] == "offers", "a strong young player draws offers")
	if res["result"] != "offers":
		return
	var o: Dictionary = res["offers"][0]
	check(o["team"] != old and not o["give"].is_empty(), "a rival team pays with its own assets")
	var pays_players: Array = o["give"].filter(func(a): return not Trades.is_pick(a)).map(func(a): return a["soldier"])
	var out := PlayerRequest.accept(season, o)
	check(out["result"] == "granted", "he takes the deal (%s)" % out["text"])
	check(season.user_team() == o["team"] and o["team"].has_player(p) and not old.has_player(p), "he is on the new club")
	for so in pays_players:
		check(old.has_player(so), "the club got the players back")
	check(p.moved_year == season.year and PlayerRequest.error(season) != "", "one move a season")
	check(not p.trade_request and not p.shopped, "the request flags are cleared by the move")
	check(not Trades.tradeable(p), "the league can never deal for him on its own")


func test_trade_request_refused_without_a_case_costs_morale() -> void:
	var season := _career(7)
	_to_week(season, 4)
	var p := season.player
	p.morale = Soldier.MORALE_NEUTRAL
	if not PlayerRequest.reasons(season).is_empty():
		return
	var m := p.morale
	var res := PlayerRequest.shop(season)
	check(res["result"] == "refused" and p.morale < m, "no case: refused and morale drops")
	check(PlayerRequest.error(season) != "", "he must wait before asking again")

extends SceneTree
## Player ability tests (issue #124): tiers, slots, locking, ranking, hooks and saves.
## Run: godot --headless --path . --script res://tests/ability_tests.gd   (ONLY=test_a,test_b for a subset)
## Uses the generated 5-team league, so the whole file runs in seconds.

var _failures := 0
var _passes := 0
var _current := ""


func _init() -> void:
	# Every test_* method runs, in declaration order: adding a test needs no edit here.
	var tests: Array = []
	for method in get_method_list():
		if String(method["name"]).begins_with("test_"):
			tests.append(String(method["name"]))
	Season.fixture_teams = 5
	Season.backfill_careers = false
	Season.seed_records = false
	var only := OS.get_environment("ONLY")
	if only != "":
		tests = tests.filter(func(x): return only.split(",").has(x))
	for t in tests:
		_current = t
		var before := _failures
		var started := Time.get_ticks_msec()
		call(t)
		var ms := Time.get_ticks_msec() - started
		if _failures == before:
			_passes += 1
			print("  PASS  %s (%d ms)" % [t, ms])
		else:
			print("  FAIL  %s (%d ms)" % [t, ms])
	print("\n%d passed, %d failed" % [_passes, tests.size() - _passes])
	quit(0 if _passes == tests.size() else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("    [%s] %s" % [_current, msg])


## A soldier whose every rating is `v`.
func _flat(v: int) -> Soldier:
	var s := Soldier.new()
	s.id = 1
	s.age = 24
	s.stats = Stats.make_uniform(v)
	return s


func _ids(s: Soldier) -> Array:
	return s.abilities.map(func(e: Dictionary): return e["id"])


func test_tier_cutoffs() -> void:
	check(Abilities.tier_for_level(74) == Abilities.LOCKED, "74 is below bronze")
	check(Abilities.tier_for_level(75) == Abilities.BRONZE and Abilities.tier_for_level(87) == Abilities.BRONZE, "75-87 bronze")
	check(Abilities.tier_for_level(88) == Abilities.SILVER and Abilities.tier_for_level(94) == Abilities.SILVER, "88-94 silver")
	check(Abilities.tier_for_level(95) == Abilities.GOLD and Abilities.tier_for_level(99) == Abilities.GOLD, "95+ gold")
	# The lowest required rating sets the tier.
	var d := Abilities.def(&"frontline_warrior")
	var st := Stats.make_uniform(99)
	st[Stats.GROUPING] = 80
	check(Abilities.level(st, d) == 80 and Abilities.tier_of_stats(st, &"frontline_warrior") == Abilities.BRONZE, "tier follows the weakest rating")


func test_definitions() -> void:
	check(Abilities.DEFS.size() == 25, "25 abilities")
	var seen := {}
	for d: Dictionary in Abilities.DEFS:
		check(not seen.has(d["id"]), "unique id %s" % d["id"])
		seen[d["id"]] = true
		check(d["stats"].size() >= 3, "%s needs three or more ratings" % d["name"])
		var groups := {}
		for st in d["stats"]:
			check(Stats.ALL.has(st), "%s: known rating %s" % [d["name"], st])
			groups[Stats.group_of(st)] = true
		check(groups.size() >= 2, "%s mixes rating groups" % d["name"])
		check(String(d["blurb"]) != "" and int(d["median"]) > 0, "%s has text and a median" % d["name"])
		check(Abilities.def(d["id"]) == d, "def() finds %s" % d["id"])
	check(Abilities.def(&"nope").is_empty() and Abilities.tier(_flat(99), &"nope") == Abilities.LOCKED, "unknown ids are empty")


## Four slots, filled by margin over each ability's league median, then by DEFS order.
func test_fill_and_ranking() -> void:
	var s := _flat(80)
	var changes := Abilities.refresh(s, 2026)
	check(s.abilities.size() == Abilities.MAX_SLOTS and changes.size() == 4, "four slots filled")
	# Medians 63, 63, 64, 64, 64 are the lowest, so those have the most margin at a flat 80.
	check(_ids(s) == [&"flanker", &"point_controller", &"clutch", &"sixth_sense"], "ranked by margin then order: %s" % [_ids(s)])
	for e: Dictionary in s.abilities:
		check(e["tier"] == Abilities.BRONZE and e["year"] == 2026, "bronze, year stamped")
	check(Abilities.refresh(s, 2027).is_empty(), "refresh is idempotent")
	check(Abilities.free_slots(s) == 0 and Abilities.active(s).size() == 4, "no free slots, four active")
	# A soldier below bronze everywhere holds nothing.
	var weak := _flat(74)
	Abilities.refresh(weak, 2026)
	check(weak.abilities.is_empty() and Abilities.free_slots(weak) == 4, "74s earn nothing")


## Earned over time: each new qualifier takes a free slot, in the order it unlocked.
func test_earned_over_time() -> void:
	var s := _flat(70)
	s.stats[Stats.ANCHOR] = 90
	s.stats[Stats.MEDIUM_ACC] = 90
	s.stats[Stats.COMPOSURE] = 90
	Abilities.refresh(s, 2026)
	check(_ids(s) == [&"king_of_the_hill"], "only King of the Hill qualifies: %s" % [_ids(s)])
	check(Abilities.tier(s, &"king_of_the_hill") == Abilities.SILVER, "silver at 88+")
	s.stats[Stats.SPEED] = 80
	s.stats[Stats.AGILITY] = 80
	s.stats[Stats.AWARENESS] = 80
	var ch := Abilities.refresh(s, 2028)
	check(_ids(s).has(&"ghost") and Abilities.entry(s, &"ghost")["year"] == 2028, "Ghost earned in 2028")
	check(ch.any(func(c: Dictionary): return c["id"] == &"ghost" and c["from"] == -1), "reported as newly earned")
	check(Abilities.entry(s, &"king_of_the_hill")["year"] == 2026, "earlier entry keeps its year")


## Tiers move with ratings; below bronze an ability locks but keeps its slot, and can return.
func test_lock_and_recover() -> void:
	var s := _flat(96)
	Abilities.refresh(s, 2026)
	var held := _ids(s)
	check(held.size() == 4 and s.abilities.all(func(e: Dictionary): return e["tier"] == Abilities.GOLD), "four golds")
	var first: StringName = held[0]
	var need: Array = Abilities.def(first)["stats"]
	# Gold to silver is only a lower tier.
	s.stats[need[0]] = 90
	Abilities.refresh(s, 2027)
	check(Abilities.tier(s, first) == Abilities.SILVER, "gold falls to silver")
	check(Abilities.entry(s, first)["tier"] == Abilities.SILVER and Abilities.active(s).size() == 4, "still active")
	# Below bronze it locks.
	s.stats[need[0]] = 60
	var ch := Abilities.refresh(s, 2028)
	check(Abilities.entry(s, first)["tier"] == Abilities.LOCKED and Abilities.tier(s, first) == Abilities.LOCKED, "locked")
	check(ch.any(func(c: Dictionary): return c["id"] == first and c["to"] == Abilities.LOCKED), "lock reported")
	check(s.abilities.size() == 4 and _ids(s) == held, "slot kept, order kept")
	check(Abilities.active(s).size() == 3, "three active")
	# Other abilities qualify at 96 everywhere, but the locked one still holds its slot.
	check(Abilities.free_slots(s) == 0, "nothing inherits the slot")
	# Recovery brings it back.
	s.stats[need[0]] = 89
	Abilities.refresh(s, 2029)
	check(Abilities.tier(s, first) == Abilities.SILVER and _ids(s) == held, "unlocked again at silver")


## Locked abilities fill every slot: a soldier can end up with four locked and earn nothing else.
func test_slots_never_freed() -> void:
	var s := _flat(80)
	Abilities.refresh(s, 2026)
	for st in Stats.ALL:
		s.stats[st] = 50
	Abilities.refresh(s, 2027)
	check(s.abilities.size() == 4 and Abilities.active(s).is_empty(), "four locked")
	for st in Stats.ALL:
		s.stats[st] = 99
	Abilities.refresh(s, 2028)
	check(s.abilities.size() == 4 and Abilities.active(s).size() == 4, "the same four return, nothing new")
	check(s.abilities.all(func(e: Dictionary): return e["year"] == 2026), "still the originals")


## Progress logging (level-ups, camp, aging) refreshes abilities straight away.
func test_log_progress_hook() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var s := PlayerGenerator.generate(rng, 1, Scheme.Role.FLEX, 55.0, 24)
	for st in Stats.ALL:
		s.stats[st] = 70
	Abilities.refresh(s, 2026)
	check(s.abilities.is_empty(), "70s hold nothing")
	var before := s.best_ovr()
	for st in Stats.ALL:
		s.stats[st] = 80
	s.log_progress("Test gains", {Stats.SPEED: 10}, before)
	check(s.abilities.size() == 4, "log_progress earned four abilities")
	# A pure star change (no rating deltas) leaves them alone.
	var snap := s.abilities.duplicate(true)
	s.log_progress("Star", {}, s.best_ovr(), 2, 3)
	check(s.abilities == snap, "no rating change, no change")


func test_league_and_saves() -> void:
	var s := Season.new_franchise(81, 0)
	var held := 0
	var total := 0
	for so: Soldier in s.league.all_soldiers():
		total += 1
		check(so.abilities.size() <= Abilities.MAX_SLOTS, "%s within four slots" % so.full_name())
		held += so.abilities.size()
		for e: Dictionary in so.abilities:
			check(int(e["tier"]) == Abilities.tier_of_stats(so.stats, e["id"]), "%s %s tier matches ratings" % [so.full_name(), e["id"]])
	check(total > 0 and held > 0, "the new league has abilities (%d on %d soldiers)" % [held, total])
	# A save round trip keeps them exactly.
	var star: Soldier = s.league.all_soldiers()[0]
	var want := star.abilities.duplicate(true)
	var back := SaveSystem.from_text(SaveSystem.to_text(s))
	var same: Soldier = null
	for so: Soldier in back.league.all_soldiers():
		if so.id == star.id:
			same = so
	check(same != null and same.abilities == want, "abilities survive a save")
	# An old save has none: they are rebuilt from ratings on load.
	for so: Soldier in s.league.all_soldiers():
		so.abilities = []
	var old := SaveSystem.from_text(SaveSystem.to_text(s))
	var rebuilt := 0
	for so: Soldier in old.league.all_soldiers():
		rebuilt += so.abilities.size()
	check(rebuilt == held, "old saves are backfilled (%d vs %d)" % [rebuilt, held])


# --- effects (phase 4) ---------------------------------------------------------------------

## A started engine with both squads, and every ability cleared so each test sets its own.
func _engine() -> MatchEngine:
	var s := Season.new_franchise(81, 0)
	var a: Team = s.league.teams[0]
	var b: Team = s.league.teams[1]
	a.auto_lineup()
	b.auto_lineup()
	var e := MatchEngine.new()
	e.start(a, b, 7)
	for squad in e.squads:
		for c: MatchEngine.Combatant in squad:
			c.abil = {}
			c.soldier.abilities = []
	return e


func _mult(e: MatchEngine, c: MatchEngine.Combatant, t: MatchEngine.Combatant, band: StringName, fresh := false) -> float:
	var allies: Array = e.squads[c.team]
	var enemies: Array = e.squads[1 - c.team]
	return e._ability_hit_mult(c, t, allies, enemies, band, fresh)


func test_effects_switch() -> void:
	var s := _flat(96)
	Abilities.refresh(s, 2026)
	check(Abilities.active_tiers(s).size() == 4 and Abilities.live_tier(s, s.abilities[0]["id"]) == Abilities.GOLD, "active while on")
	Abilities.effects_enabled = false
	check(Abilities.active_tiers(s).is_empty() and Abilities.live_tier(s, s.abilities[0]["id"]) == 0, "nothing while off")
	var e := _engine()
	var c: MatchEngine.Combatant = e.squads[0][0]
	c.abil = {&"frontline_warrior": 3}
	check(_mult(e, c, e.squads[1][0], &"short") == 1.0, "engine ignores abilities while off")
	Abilities.effects_enabled = true


func test_situational_hit_bonuses() -> void:
	var e := _engine()
	var c: MatchEngine.Combatant = e.squads[0][0]
	var t: MatchEngine.Combatant = e.squads[1][0]
	# Nothing held: no change.
	check(_mult(e, c, t, &"short") == 1.0, "no abilities, no change")
	c.abil = {&"frontline_warrior": Abilities.GOLD}
	check(is_equal_approx(_mult(e, c, t, &"short"), 1.0 + Abilities.POWER[Abilities.GOLD]), "Frontline Warrior at short range")
	check(is_equal_approx(_mult(e, c, t, &"medium"), 1.0 + Abilities.POWER[Abilities.GOLD]), "... and medium")
	check(_mult(e, c, t, &"long") == 1.0, "... but not long")
	c.abil = {&"marksman": Abilities.SILVER}
	check(_mult(e, c, t, &"short") == 1.0 and is_equal_approx(_mult(e, c, t, &"long"), 1.0 + Abilities.POWER[Abilities.SILVER]), "Marksman only at long range")
	c.abil = {&"gunslinger": Abilities.BRONZE}
	check(_mult(e, c, t, &"short", true) > 1.0 and _mult(e, c, t, &"short", false) == 1.0, "Gunslinger only on a fresh burst")
	# Higher tier is stronger.
	var seen: Array = []
	for tier in [Abilities.BRONZE, Abilities.SILVER, Abilities.GOLD]:
		c.abil = {&"frontline_warrior": tier}
		seen.append(_mult(e, c, t, &"short"))
	check(seen[0] < seen[1] and seen[1] < seen[2], "tiers scale %s" % [seen])
	# Many abilities together never pass the cap.
	var all := {}
	for d: Dictionary in Abilities.DEFS:
		all[d["id"]] = Abilities.GOLD
	c.abil = all
	check(_mult(e, c, t, &"short", true) <= Abilities.HIT_CAP + 0.0001, "bonus capped at %.2f" % Abilities.HIT_CAP)


func test_defensive_abilities() -> void:
	var e := _engine()
	var c: MatchEngine.Combatant = e.squads[0][0]
	var t: MatchEngine.Combatant = e.squads[1][0]
	t.abil = {&"ghost": Abilities.GOLD}
	t.prev_pos = t.pos
	check(_mult(e, c, t, &"short") == 1.0, "Ghost does nothing while standing still")
	t.prev_pos = t.pos + Vector2(1.0, 0.0)
	check(is_equal_approx(_mult(e, c, t, &"short"), 1.0 - Abilities.GUARD[Abilities.GOLD]), "Ghost: harder to hit while moving")
	t.abil = {&"ghost": Abilities.GOLD, &"cover_specialist": Abilities.GOLD}
	t.cover_spot = t.pos
	t.peeking = false
	var cut := _mult(e, c, t, &"short")
	check(cut >= Abilities.GUARD_CAP - 0.0001 and cut < 1.0 - Abilities.GUARD[Abilities.GOLD], "stacked cuts are floored at %.2f (%.3f)" % [Abilities.GUARD_CAP, cut])


func test_other_effect_hooks() -> void:
	var e := _engine()
	var c: MatchEngine.Combatant = e.squads[0][0]
	var t: MatchEngine.Combatant = e.squads[1][0]
	# Clutch: only when outnumbered.
	c.abil = {&"clutch": Abilities.GOLD}
	check(_mult(e, c, t, &"short") == 1.0, "Clutch needs a numbers disadvantage")
	for i in range(1, e.squads[0].size()):
		(e.squads[0][i] as MatchEngine.Combatant).alive = false
	check(_mult(e, c, t, &"short") > 1.0, "Clutch when outnumbered")
	# Closer: late in a game.
	var e2 := _engine()
	var c2: MatchEngine.Combatant = e2.squads[0][0]
	c2.abil = {&"closer": Abilities.GOLD}
	var t2: MatchEngine.Combatant = e2.squads[1][0]
	e2._mode = MatchEngine.MODE_TDM
	e2._arena_score = [0.0, 0.0]
	check(_mult(e2, c2, t2, &"short") == 1.0, "Closer: not late at 0-0")
	e2._arena_score = [MatchEngine.TDM_POINTS_TO_WIN * MatchEngine.LATE_SHARE, 0.0]
	check(_mult(e2, c2, t2, &"short") > 1.0, "Closer: late once someone nears the win")
	# King of the Hill only in KOTH and on the point.
	var e3 := _engine()
	var c3: MatchEngine.Combatant = e3.squads[0][0]
	c3.abil = {&"king_of_the_hill": Abilities.GOLD}
	var t3: MatchEngine.Combatant = e3.squads[1][0]
	e3._mode = MatchEngine.MODE_TDM
	c3.pos = ArenaMap.HILL.get_center()
	check(_mult(e3, c3, t3, &"short") == 1.0, "King of the Hill does nothing outside KOTH")
	e3._mode = MatchEngine.MODE_KOTH
	check(_mult(e3, c3, t3, &"short") > 1.0, "King of the Hill on the point")


func test_conditioning_abilities() -> void:
	var s := _flat(80)
	s.fatigue = 50.0
	var base_chance := Conditioning.injury_chance(s, true)
	var base_rec := Conditioning.weekly_recovery(s, false)
	s.abilities = [{"id": &"iron_man", "tier": Abilities.GOLD, "year": 2026}, {"id": &"quick_healer", "tier": Abilities.GOLD, "year": 2026}]
	check(Conditioning.injury_chance(s, true) < base_chance, "Iron Man lowers the injury chance")
	check(Conditioning.weekly_recovery(s, false) > base_rec, "Quick Healer sheds more fatigue")
	s.abilities[0]["tier"] = Abilities.LOCKED
	check(is_equal_approx(Conditioning.injury_chance(s, true), base_chance), "a locked ability does nothing")
	Abilities.effects_enabled = false
	check(is_equal_approx(Conditioning.weekly_recovery(s, false), base_rec), "effects off: no recovery bonus")
	Abilities.effects_enabled = true


## Same seed, same result, with effects on (no hidden randomness in abilities).
func test_effects_are_deterministic() -> void:
	var s := Season.new_franchise(81, 0)
	var a: Team = s.league.teams[0]
	var b: Team = s.league.teams[1]
	a.auto_lineup()
	b.auto_lineup()
	var r1 := MatchEngine.simulate(a, b, 99)
	var r2 := MatchEngine.simulate(a, b, 99)
	check(r1.score == r2.score and r1.events.size() == r2.events.size() and "".join(r1.events) == "".join(r2.events), "abilities keep matches reproducible")
	# And they matter: wiping everyone's abilities changes some match for the same seed.
	var differs := false
	for sd in 8:
		var with_ab := MatchEngine.simulate(a, b, 300 + sd)
		var saved: Array = []
		for so: Soldier in a.starters() + b.starters():
			saved.append([so, so.abilities])
			so.abilities = []
		var without := MatchEngine.simulate(a, b, 300 + sd)
		for e in saved:
			(e[0] as Soldier).abilities = e[1]
		if "".join(with_ab.events) != "".join(without.events):
			differs = true
	check(differs, "abilities change how matches play out")


## Every ability shows the number it applies, growing with the tier; locked shows a dash.
func test_effect_text() -> void:
	var re := RegEx.new()
	re.compile("[0-9]+")
	for d: Dictionary in Abilities.DEFS:
		var nums: Array = []
		for tier in [Abilities.BRONZE, Abilities.SILVER, Abilities.GOLD]:
			var fx := Abilities.effect_of(d["id"], tier)
			check(String(fx["value"]) != "" and String(fx["unit"]) != "", "%s tier %d has text" % [d["name"], tier])
			var m := re.search(String(fx["value"]))
			nums.append(int(m.get_string()) if m != null else -1)
		check(nums[0] >= 0 and nums[0] < nums[1] and nums[1] < nums[2], "%s grows with the tier %s" % [d["name"], nums])
		check(Abilities.effect_of(d["id"], Abilities.LOCKED)["value"] == "-", "%s locked shows a dash" % d["name"])
	check(Abilities.effect_of(&"frontline_warrior", Abilities.GOLD)["value"] == "+14%", "gold Frontline Warrior is +14%")
	check(Abilities.effect_of(&"gunslinger", Abilities.GOLD)["value"] == "+21%", "gold Gunslinger is +21%")

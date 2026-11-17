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

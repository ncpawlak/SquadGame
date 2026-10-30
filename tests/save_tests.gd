extends SceneTree
## Save/load tests:
##   godot --headless --path . --script res://tests/save_tests.gd
## Exits with code 0 if all tests pass, 1 otherwise.

var _failures := 0
var _passes := 0
var _current := ""


func _init() -> void:
	var tests := [
		"test_primitives_round_trip",
		"test_round_trip_identity",
		"test_determinism_after_load",
		"test_news_round_trip",
		"test_newsroom_round_trip",
		"test_history_round_trip",
		"test_retired_callsigns_round_trip",
		"test_hall_of_fame_round_trip",
		"test_load_repairs_callsigns",
		"test_slot_api",
		"test_legacy_potential_migrates",
	]
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


## Old saves stored a single F..A "potential" grade; it maps to dev stars.
func test_legacy_potential_migrates() -> void:
	for pair in [[0, 1], [1, 1], [2, 2], [3, 3], [4, 4]]:
		var so := Soldier.new()
		so._migrate_prop("potential", pair[0])
		check(so.dev == pair[1], "grade %d -> %d stars (got %d)" % [pair[0], pair[1], so.dev])
	var d := {"id": 1, "first": "A", "last": "B", "age": 30, "potential": 4, "stats": {}, "caps": {}}
	check(League.soldier_from_dict(d).dev == Soldier.DEV_MAX, "legacy league.json potential maps to stars")


# --- helpers ---------------------------------------------------------------

func soldier_by_id(s: Season, id: int) -> Soldier:
	for so in s.league.all_soldiers():
		if so.id == id:
			return so
	return null


func team_by_abbrev(s: Season, abbrev: String) -> Team:
	for t in s.league.teams:
		if t.abbrev == abbrev:
			return t
	return null


func standings_text(s: Season) -> String:
	var parts := []
	for r in s.standings():
		parts.append("%s %d-%d %d-%d %d:%d %s" % [r.team.abbrev, r.wins, r.losses, r.games_won, r.games_lost,
			r.points_for, r.points_against, r.streak])
	return ", ".join(parts)


func soldier_text(so: Soldier) -> String:
	return var_to_str([so.id, so.first_name, so.last_name, so.age, so.dev, so.dev_year, so.stats, so.career,
		so.contract.salary if so.contract else -1, so.contract.years if so.contract else -1,
		so.level, so.xp, so.morale, so.fatigue, so.injury_weeks])


func compare_seasons(a: Season, b: Season, what: String) -> void:
	check(a.year == b.year and a.week == b.week and a.phase == b.phase,
		"%s: year/week/phase differ (%d/%d/%s vs %d/%d/%s)" % [what, a.year, a.week, a.phase, b.year, b.week, b.phase])
	check(standings_text(a) == standings_text(b), "%s: standings differ:\n  %s\n  %s" % [what, standings_text(a), standings_text(b)])
	var ca := a.champion.abbrev if a.champion else ""
	var cb := b.champion.abbrev if b.champion else ""
	check(ca == cb, "%s: champion differs (%s vs %s)" % [what, ca, cb])
	var sa := a.league.all_soldiers()
	var sb := b.league.all_soldiers()
	check(sa.size() == sb.size(), "%s: soldier counts differ" % what)
	var mismatched := 0
	for i in mini(sa.size(), sb.size()):
		if soldier_text(sa[i]) != soldier_text(sb[i]):
			mismatched += 1
	check(mismatched == 0, "%s: %d soldiers differ" % [what, mismatched])
	check(SaveSystem.to_text(a) == SaveSystem.to_text(b), "%s: full serialized state differs" % what)


# --- tests -----------------------------------------------------------------

func test_primitives_round_trip() -> void:
	# A bare graph: League with shared soldiers, Object-keyed dicts and value types.
	var l := League.generate(42, 4)
	var t: Team = l.teams[0]
	t.dead_money[l.teams[1]] = 7
	t.color = Color(0.1, 0.2, 0.3, 0.4)
	var s := Season.new()
	s.league = l
	# A started franchise always has its markets seeded (loading seeds older saves), so seed the bare graph too.
	s.market.ensure(s)
	s.injury_log = [t.roster[0], t.roster[0], &"name", Vector2i(3, 4), 1, 1.0, PackedInt32Array([1, 2])]
	s.negotiations = {t: {t.roster[1]: [1.5, "x"]}}
	var s2 := SaveSystem.from_text(SaveSystem.to_text(s))
	check(s2 != null, "from_text returned null")
	if s2 == null:
		return
	var t2: Team = s2.league.teams[0]
	check(t2.roster.is_typed() and t2.roster.get_typed_script() == Soldier, "Team.roster lost its Array[Soldier] type")
	check(t2.color == t.color, "Color changed: %s" % t2.color)
	check(t2.dead_money.has(s2.league.teams[1]) and t2.dead_money[s2.league.teams[1]] == 7, "Object-keyed dict lost")
	var log2 := s2.injury_log
	check(log2[0] == t2.roster[0] and log2[1] == t2.roster[0], "shared soldier reference not preserved")
	check(typeof(log2[2]) == TYPE_STRING_NAME, "StringName became %s" % type_string(typeof(log2[2])))
	check(log2[3] == Vector2i(3, 4), "Vector2i lost")
	check(typeof(log2[4]) == TYPE_INT and typeof(log2[5]) == TYPE_FLOAT, "int/float not distinct")
	check(log2[6] is PackedInt32Array, "PackedInt32Array lost")
	check(s2.negotiations.has(t2) and s2.negotiations[t2].has(t2.roster[1]), "nested object-keyed dicts lost")
	check(s2.league.rng.state == l.rng.state and s2.league.rng.seed == l.rng.seed, "RNG state lost")
	check(s2.league.rng.randi() == l.rng.randi(), "RNG sequence diverged")
	check(SaveSystem.to_text(s2) == SaveSystem.to_text(s), "re-serialization not stable")


func test_round_trip_identity() -> void:
	var s := Season.new_franchise(1234)
	for i in 3:
		s.sim_week()
	var text := SaveSystem.to_text(s)
	var s2 := SaveSystem.from_text(text)
	check(s2 != null, "from_text returned null")
	if s2 == null:
		return
	check(SaveSystem.to_text(s2) == text, "re-serialization not stable")
	check(s2.week == s.week and s2.phase == s.phase and s2.year == s.year, "week/phase/year changed")
	check(s2.user_team() != null and s2.user_team().name == s.user_team().name, "user team lost")
	var all2 := s2.league.all_soldiers()
	var first: Soldier = s2.user_team().roster[0]
	check(all2.has(first), "user roster soldier is not the league's soldier object")
	check(soldier_by_id(s2, first.id) == first, "soldier identity not preserved")
	# Every team referenced by the schedule and results is one of league.teams.
	var bad := 0
	for m in s2.regular_matches() + s2.playoff_matches:
		if not (s2.league.teams.has(m.home) and s2.league.teams.has(m.away)):
			bad += 1
		if m.result != null:
			for tt in m.result.teams:
				if not s2.league.teams.has(tt):
					bad += 1
	check(bad == 0, "%d schedule/result team refs are copies, not shared" % bad)
	for so in s.league.all_soldiers():
		var o := soldier_by_id(s2, so.id)
		if o == null or soldier_text(o) != soldier_text(so):
			check(false, "soldier %d differs after load" % so.id)
			break
	check(standings_text(s) == standings_text(s2), "standings differ")
	check(Soldier.log_year == s2.year, "log stamp not set after load")
	print("    save text %d KB, week %d" % [text.length() / 1024, s.week])


func test_determinism_after_load() -> void:
	var s := Season.new_franchise(777)
	for i in 4:
		s.sim_week()
	var s2 := SaveSystem.from_text(SaveSystem.to_text(s))
	check(s2 != null, "from_text returned null")
	if s2 == null:
		return
	s.sim_to_end_of_season()
	s2.sim_to_end_of_season()
	compare_seasons(s, s2, "end of season")
	# Offseason flows through drafts, FA and camp, all driven by the restored RNGs.
	s.start_next_season()
	s2.start_next_season()
	compare_seasons(s, s2, "next season")
	# A save taken mid-offseason must also continue identically.
	s.sim_to_end_of_season()
	var s3 := SaveSystem.from_text(SaveSystem.to_text(s))
	s.start_next_season()
	s3.start_next_season()
	compare_seasons(s, s3, "offseason save")


## The league wire (offseason stories included) and the recap data survive a save mid-offseason.
func test_news_round_trip() -> void:
	var s := Season.new_franchise(321)
	s.sim_to_end_of_season()
	# Re-signing, three free-agency days and the draft: stories and recap steps exist mid-offseason.
	for i in 5:
		s.advance_offseason()
	check(not s.news.items.is_empty(), "stories exist before the save")
	var s2 := SaveSystem.from_text(SaveSystem.to_text(s))
	check(s2 != null, "from_text returned null")
	if s2 == null:
		return
	check(s2.news.items.size() == s.news.items.size(), "news items lost (%d vs %d)" % [s2.news.items.size(), s.news.items.size()])
	for i in s.news.items.size():
		if s2.news.items[i]["headline"] != s.news.items[i]["headline"]:
			check(false, "news item %d differs after load" % i)
			break
	check(s2.news.digest_steps(s2) == s.news.digest_steps(s), "recap steps differ after load")
	for step in s.news.digest_steps(s):
		check(s2.news.digest_summary(s2, step) == s.news.digest_summary(s, step), "%s recap differs after load" % step)
	check(s2.step_label() == s.step_label(), "step label differs after load")


## The Weekly News archive (and read marker) survive a save; no Season/Team refs linger in it.
func test_newsroom_round_trip() -> void:
	var s := Season.new_franchise(322)
	s.sim_to_end_of_season()
	s.advance_offseason()
	s.newsroom.mark_read(2)
	check(s.newsroom.count() > 5, "issues exist before the save (%d)" % s.newsroom.count())
	check(s.newsroom._s == null and s.newsroom._us == null, "newsroom keeps no season/team refs between issues")
	var s2 := SaveSystem.from_text(SaveSystem.to_text(s))
	check(s2 != null, "from_text returned null")
	if s2 == null:
		return
	check(s2.newsroom.count() == s.newsroom.count(), "issues lost (%d vs %d)" % [s2.newsroom.count(), s.newsroom.count()])
	check(s2.newsroom.read_upto == s.newsroom.read_upto, "read marker lost")
	for i in s.newsroom.count():
		var a: Dictionary = s.newsroom.issue(i)
		var b: Dictionary = s2.newsroom.issue(i)
		if a["headline"] != b["headline"] or a["body"] != b["body"]:
			check(false, "issue %d differs after load" % i)
			break


func test_history_round_trip() -> void:
	var s := Season.new_franchise(323)
	s.sim_to_end_of_season()
	var s2 := SaveSystem.from_text(SaveSystem.to_text(s))
	check(s2 != null and s2.history.size() == 1, "snapshot lost in the round trip")
	if s2 == null or s2.history.size() != 1:
		return
	var a: SeasonSnapshot = s.history[0]
	var b: SeasonSnapshot = s2.history[0]
	check(b.year == a.year and b.champion.abbrev == a.champion.abbrev and b.runner_up.abbrev == a.runner_up.abbrev, "year, champion or runner-up differ after load")
	check(b.standings.size() == a.standings.size() and b.bracket.size() == a.bracket.size(), "table or bracket size differs after load")
	check(b.champion == s2.champion, "snapshot champion is the loaded season's own team object")
	# A save from before history existed: still in the offseason, so the finished season is rebuilt.
	s.history = []
	var old := SaveSystem.from_text(SaveSystem.to_text(s))
	check(old != null and old.history.size() == 1 and old.history[0].champion == old.champion, "old offseason save is backfilled with this season")
	# Mid-season old save: nothing to backfill, history stays empty.
	var mid := Season.new_franchise(324)
	mid.sim_week()
	mid.history = []
	var mid2 := SaveSystem.from_text(SaveSystem.to_text(mid))
	check(mid2 != null and mid2.history.is_empty(), "old mid-season save loads with empty history")


func test_retired_callsigns_round_trip() -> void:
	var s := Season.new_franchise(325)
	var ai: Team = s.league.teams[0] if s.league.teams[0] != s.user_team() else s.league.teams[1]
	var so := ai.roster[0]
	so.callsign = "Hawkeye"
	var mine := s.user_team().roster[0]
	s.league.retired_callsigns.append({"callsign": so.callsign, "soldier": so, "team": ai, "year": 2030, "seasons": 7, "honors": ["2029 Season MVP"]})
	s.league.callsign_proposals.append({"callsign": mine.callsign, "soldier": mine, "team": s.user_team(), "year": 2030, "seasons": 6, "honors": []})
	var s2 := SaveSystem.from_text(SaveSystem.to_text(s))
	check(s2 != null and s2.league.retired_callsigns.size() == 1 and s2.league.callsign_proposals.size() == 1, "retired callsigns lost in the round trip")
	if s2 == null or s2.league.retired_callsigns.size() != 1:
		return
	var e: Dictionary = s2.league.retired_callsigns[0]
	check(e["callsign"] == "Hawkeye" and e["team"] == s2.league.team_by_abbrev(ai.abbrev) and e["soldier"].id == so.id and e["honors"] == ["2029 Season MVP"], "entry fields differ after load")
	check(s2.league.reserved_callsigns().has("hawkeye"), "reserved set is rebuilt from the loaded entries")
	var old := Season.new_franchise(326)
	var old2 := SaveSystem.from_text(SaveSystem.to_text(old))
	check(old2 != null and old2.league.retired_callsigns.is_empty() and old2.league.callsign_proposals.is_empty(), "a save with no retired callsigns loads empty")


func test_hall_of_fame_round_trip() -> void:
	var s := Season.new_franchise(327)
	var team: Team = s.league.teams[0]
	var so := team.roster[0]
	s.hall_of_fame.append({"soldier": so, "year": 2034, "score": 71.5, "club": team, "honors": ["2031 Season MVP"]})
	var s2 := SaveSystem.from_text(SaveSystem.to_text(s))
	check(s2 != null and s2.hall_of_fame.size() == 1, "Hall of Fame lost in the round trip")
	if s2 == null or s2.hall_of_fame.size() != 1:
		return
	var e: Dictionary = s2.hall_of_fame[0]
	check(e["year"] == 2034 and is_equal_approx(e["score"], 71.5) and e["club"] == s2.league.team_by_abbrev(team.abbrev) and e["honors"] == ["2031 Season MVP"], "entry fields differ after load")
	check(HallOfFame.is_member(s2, e["soldier"]) and e["soldier"].id == so.id, "the member is the loaded soldier")
	var old := SaveSystem.from_text(SaveSystem.to_text(Season.new_franchise(328)))
	check(old != null and old.hall_of_fame.is_empty(), "a save with no Hall loads empty")


func test_load_repairs_callsigns() -> void:
	var s := Season.new_franchise(329)
	var a := s.league.teams[0].roster[0]
	var b := s.league.teams[1].roster[0]
	b.callsign = a.callsign
	var c := s.league.teams[2].roster[0]
	s.league.retired_callsigns.append({"callsign": c.callsign, "soldier": c, "team": s.league.teams[2], "year": 2030, "seasons": 7, "honors": []})
	var s2 := SaveSystem.from_text(SaveSystem.to_text(s))
	check(s2 != null, "from_text returned null")
	if s2 == null:
		return
	var seen := {}
	var retired := s2.league.reserved_callsigns()
	var pool: Array = s2.league.all_soldiers()
	pool.append_array(s2.league.free_agents)
	for so: Soldier in pool:
		check(not seen.has(so.callsign.to_lower()), "callsign %s is still worn twice after load" % so.callsign)
		check(not retired.has(so.callsign.to_lower()), "%s still wears a retired callsign after load" % so.callsign)
		seen[so.callsign.to_lower()] = true


func test_slot_api() -> void:
	const SLOT := 2
	var had_backup := SaveSystem.has_slot(SLOT)
	var backup := PackedByteArray()
	if had_backup:
		backup = FileAccess.get_file_as_bytes(SaveSystem.slot_path(SLOT))
	var backup_meta := FileAccess.get_file_as_string(SaveSystem.meta_path(SLOT)) if had_backup else ""
	var s := Season.new_franchise(99)
	for i in 5:
		s.sim_week()
	var err := SaveSystem.save(s, SLOT, "Test save")
	check(err == "", "save failed: %s" % err)
	check(SaveSystem.has_slot(SLOT), "slot not written")
	var info := SaveSystem.slot_info(SLOT)
	check(info.get("team", "") == s.user_team().name, "slot_info missing team name: %s" % info)
	check(info.get("year", 0) == s.year and info.get("label", "") == "Test save", "slot_info header wrong: %s" % info)
	check(info.get("week", "") == s.week_label(s.week), "slot_info week wrong: %s" % info)
	print("    mid-season save: %d KB compressed (text %d KB) %s" % [int(info.get("size", 0)) / 1024,
		SaveSystem.to_text(s).length() / 1024, info])
	var loaded := SaveSystem.load_slot(SLOT)
	check(loaded != null, "load_slot returned null")
	if loaded:
		check(standings_text(loaded) == standings_text(s), "loaded standings differ")
		check(SaveSystem.to_text(loaded) == SaveSystem.to_text(s), "loaded state differs")
	SaveSystem.delete_slot(SLOT)
	check(not SaveSystem.has_slot(SLOT) and SaveSystem.slot_info(SLOT).is_empty(), "delete_slot did not clear")
	check(SaveSystem.load_slot(SLOT) == null, "empty slot loaded")
	check(SaveSystem.save(s, 9) != "", "invalid slot accepted")
	if had_backup:
		var f := FileAccess.open(SaveSystem.slot_path(SLOT), FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
		var mf := FileAccess.open(SaveSystem.meta_path(SLOT), FileAccess.WRITE)
		mf.store_string(backup_meta)
		mf.close()

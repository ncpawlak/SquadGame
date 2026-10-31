extends SceneTree
## Stat ledger tests (issue #11): phase-tagged totals, once-only recording, saves, determinism.
## Run: godot --headless --path . --script res://tests/ledger_tests.gd   (ONLY=test_a,test_b for a subset)
## Uses the generated 5-team league, so the whole file runs in seconds.

var _failures := 0
var _passes := 0
var _current := ""


func _init() -> void:
	var tests := [
		"test_phase_split",
		"test_recorded_once",
		"test_exhibition_not_recorded",
		"test_save_round_trip",
		"test_determinism",
		"test_registry_matches_records",
		"test_line_for_phases",
		"test_format",
	]
	Season.fixture_teams = 5
	Season.backfill_careers = false
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


func _season(seed_value := 81) -> Season:
	var s := Season.new_franchise(seed_value, 0)
	s.sim_to_end_of_season()
	return s


## Every regular-season fixture (`schedule` holds one array of matches per week).
func _regular(s: Season) -> Array:
	var out: Array = []
	for wk: Array in s.schedule:
		out.append_array(wk)
	return out


## Playoff totals are a share of the combined ones, and the ledger counts each phase's matches.
func test_phase_split() -> void:
	var s := _season()
	var regular_played := 0
	for m: ScheduledMatch in _regular(s):
		if m.is_played():
			regular_played += 1
	check(s.ledger.matches_regular == regular_played, "ledger counts regular matches (%d vs %d)" % [s.ledger.matches_regular, regular_played])
	check(s.ledger.matches_playoffs == s.playoff_matches.size(), "ledger counts playoff matches (%d vs %d)" % [s.ledger.matches_playoffs, s.playoff_matches.size()])
	var box_lines := 0
	for m: ScheduledMatch in s.playoff_matches:
		box_lines += m.result.box.size()
	var playoff_total := 0
	for so: Soldier in s.league.all_soldiers():
		for k in so.playoff_career:
			check(int(so.playoff_career[k]) <= int(so.career.get(k, 0)), "%s playoff %s within combined" % [so.full_name(), k])
		playoff_total += int(so.playoff_career.get("matches", 0))
		for year in so.playoff_season_lines:
			var pl: Dictionary = so.playoff_season_lines[year]
			var sl: Dictionary = so.season_lines[year]
			check(int(pl.get("kills", 0)) <= int(sl.get("kills", 0)), "%s season playoff kills within combined" % so.full_name())
			check(pl.get("team", "") == sl.get("team", ""), "playoff line carries the same team")
	check(playoff_total > 0, "someone has playoff matches")
	check(playoff_total == box_lines, "playoff matches on soldiers match the box lines (%d vs %d)" % [playoff_total, box_lines])


## Replaying a match through `play_week_match` does not count it twice.
func test_recorded_once() -> void:
	var s := _season(82)
	var m: ScheduledMatch = _regular(s)[0]
	var before_regular := s.ledger.matches_regular
	var so: Soldier = m.home.starters()[0]
	var before_matches := int(so.career.get("matches", 0))
	s.play_week_match(m)
	check(s.ledger.matches_regular == before_regular, "played match is not recounted")
	check(int(so.career.get("matches", 0)) == before_matches, "played match is not re-added to careers")
	m.needs_xp = true
	s.play_week_match(m)
	check(s.ledger.matches_regular == before_regular + 1, "a watched result owing XP is counted once")
	s.play_week_match(m)
	check(s.ledger.matches_regular == before_regular + 1, "and not again after XP is paid")


## Exhibition matches carry no year or context, so they never touch the season or playoff lines.
func test_exhibition_not_recorded() -> void:
	var s := _season(83)
	var m: ScheduledMatch = _regular(s)[0]
	var so: Soldier = m.home.starters()[0]
	var lines_before := so.season_lines.duplicate(true)
	var playoff_before := so.playoff_career.duplicate(true)
	var ledger_before := s.ledger.matches_regular + s.ledger.matches_playoffs
	Progression.award_match_xp(m.result)
	check(so.season_lines == lines_before, "no season line added without a year")
	check(so.playoff_career == playoff_before, "no playoff totals added without a context")
	check(s.ledger.matches_regular + s.ledger.matches_playoffs == ledger_before, "ledger untouched")


## Playoff data and ledger counts survive a save; a save with no playoff data still loads.
func test_save_round_trip() -> void:
	var s := _season(84)
	var loaded := SaveSystem.from_text(SaveSystem.to_text(s))
	check(loaded != null, "season loads")
	if loaded == null:
		return
	check(loaded.ledger.matches_regular == s.ledger.matches_regular, "regular count kept")
	check(loaded.ledger.matches_playoffs == s.ledger.matches_playoffs, "playoff count kept")
	var a := s.league.all_soldiers()
	var b := loaded.league.all_soldiers()
	check(a.size() == b.size(), "same soldiers")
	for i in mini(a.size(), b.size()):
		check(a[i].playoff_career == b[i].playoff_career, "%s playoff career kept" % a[i].full_name())
		check(a[i].playoff_season_lines == b[i].playoff_season_lines, "%s playoff seasons kept" % a[i].full_name())
	# An old save: every playoff field empty.
	for so: Soldier in s.league.all_soldiers():
		so.playoff_career = {}
		so.playoff_season_lines = {}
	var old := SaveSystem.from_text(SaveSystem.to_text(s))
	check(old != null, "save without playoff data loads")
	if old != null:
		var kills := 0
		for so: Soldier in old.league.all_soldiers():
			check(so.playoff_career.is_empty(), "playoff totals start empty")
			kills += int(so.career.get("kills", 0))
		check(kills > 0, "combined totals are untouched")


## The ledger adds no randomness: the same seed plays out the same.
func test_determinism() -> void:
	var a := _season(555)
	var b := _season(555)
	check(a.champion.abbrev == b.champion.abbrev, "same champion")
	var ra: Array = a.playoff_matches.map(func(m: ScheduledMatch): return m.score_text())
	var rb: Array = b.playoff_matches.map(func(m: ScheduledMatch): return m.score_text())
	check(ra == rb, "same playoff scores")
	check(a.ledger.matches_regular == b.ledger.matches_regular, "same regular count")
	check(a.ledger.matches_playoffs == b.ledger.matches_playoffs, "same playoff count")


## Records reads the registry, so its stat list and values are the registry's.
func test_registry_matches_records() -> void:
	check(Records.PLAYER_STATS == StatRegistry.PLAYER, "records use the registry's stats")
	var kd := {"id": "kd", "kind": "kd"}
	var line := {"matches": 10, "kills": 30, "deaths": 15}
	check(is_equal_approx(Records.value_of(kd, line, 6), 2.0), "kd value")
	check(Records.value_of(kd, line, 30) == -1.0, "kd needs enough matches")
	check(Records.value_of({"id": "kills", "kind": "sum"}, line, 6) == 30.0, "sum value")


## Regular plus playoffs is the combined line, for seasons and careers; without playoff data regular is combined.
func test_line_for_phases() -> void:
	var s := _season(85)
	var with_playoffs := 0
	for so: Soldier in s.league.all_soldiers():
		for scope in [StatRegistry.SCOPE_SEASON, StatRegistry.SCOPE_CAREER]:
			var combined := StatRegistry.line_for(so, scope, StatRegistry.PHASE_COMBINED, s.year)
			var regular := StatRegistry.line_for(so, scope, StatRegistry.PHASE_REGULAR, s.year)
			var playoffs := StatRegistry.line_for(so, scope, StatRegistry.PHASE_PLAYOFFS, s.year)
			if combined.is_empty():
				check(regular.is_empty() and playoffs.is_empty(), "%s no line in any phase" % so.full_name())
				continue
			for k in Soldier.STAT_LINE_KEYS:
				check(int(regular.get(k, 0)) + int(playoffs.get(k, 0)) == int(combined.get(k, 0)),
					"%s %s %s: regular + playoffs = combined" % [so.full_name(), scope, k])
				check(int(regular.get(k, 0)) >= 0, "%s %s regular never negative" % [so.full_name(), k])
			if not playoffs.is_empty():
				with_playoffs += 1
		so.playoff_career = {}
		so.playoff_season_lines = {}
		var old := StatRegistry.line_for(so, StatRegistry.SCOPE_CAREER, StatRegistry.PHASE_REGULAR)
		for k in Soldier.STAT_LINE_KEYS:
			check(int(old.get(k, 0)) == int(so.career.get(k, 0)), "old save: regular is combined")
	check(with_playoffs > 0, "some soldiers have playoff lines")


func test_format() -> void:
	var by_id := {}
	for stat: Dictionary in StatRegistry.LEADERS:
		by_id[stat["id"]] = stat
	check(StatRegistry.format(by_id["kills"], 12.0) == "12", "int format")
	check(StatRegistry.format(by_id["kd"], 1.5) == "1.50", "ratio format")
	check(StatRegistry.format(by_id["hill_s"], 75.0) == MatchEngine._fmt_secs(75.0), "hill time format")

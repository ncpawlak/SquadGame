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
		"test_single_match_book",
		"test_record_events",
		"test_streak_events",
		"test_records_phase",
		"test_record_save_and_news",
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


## A season's worth of matches fills the books: sorted, capped, and the best entry is the best performance.
func test_single_match_book() -> void:
	var s := _season(86)
	var best := {"all": 0.0, "regular": 0.0, "playoffs": 0.0}
	var kills: Dictionary = StatRegistry.SINGLE_MATCH[0]
	var played: Array = _regular(s)
	played.append_array(s.playoff_matches)
	for m: ScheduledMatch in played:
		for sid in m.result.box:
			var v := StatRegistry.match_value(kills, m.result.box[sid])
			var phase := "playoffs" if m.stage != Season.STAGE_REGULAR else "regular"
			best["all"] = maxf(best["all"], v)
			best[phase] = maxf(best[phase], v)
	var all := Records.single_matches(s, kills)
	check(not all.is_empty() and all.size() <= Records.TOP_N, "combined book is filled and capped (%d)" % all.size())
	check(all[0]["value"] == best["all"], "top combined kills is the best box line (%s vs %s)" % [all[0]["value"], best["all"]])
	for i in range(1, all.size()):
		check(all[i - 1]["value"] >= all[i]["value"], "combined book is sorted")
	check(Records.single_matches(s, kills, StatRegistry.PHASE_REGULAR)[0]["value"] == best["regular"], "regular book top")
	check(Records.single_matches(s, kills, StatRegistry.PHASE_PLAYOFFS)[0]["value"] == best["playoffs"], "playoff book top")
	var holder: Dictionary = all[0]
	var club := Records.single_matches(s, kills, StatRegistry.PHASE_COMBINED, holder["team"])
	check(not club.is_empty() and club[0]["value"] == holder["value"], "the holder's franchise book has the same top")
	for t: Team in s.league.teams:
		for e in Records.single_matches(s, kills, StatRegistry.PHASE_COMBINED, t.abbrev):
			check(e["team"] == t.abbrev, "franchise book only holds that club's players")
	var impact: Dictionary = StatRegistry.SINGLE_MATCH[-1]
	check(Records.single_matches(s, impact)[0]["value"] > 0.0, "impact is recorded too")


## Records fire only against a full, mature book; ties and early matches do not count; the best line wins.
func test_record_events() -> void:
	var s := _season(87)
	s.ledger = StatLedger.new()
	var m: ScheduledMatch = _regular(s)[0]
	var so: Soldier = m.home.starters()[0]
	var other: Soldier = m.away.starters()[0]
	var line: Dictionary = m.result.box[so.id]
	var kills_events := func() -> Array:
		return m.records.filter(func(r): return r["stat"] == "kills")
	for i in 5:
		line["kills"] = 30 + i
		s.ledger.record_match(s, m)
	check(kills_events.call().is_empty(), "no record while the league is young")
	s.ledger.matches_regular = StatLedger.MATURE_AFTER
	line["kills"] = 40
	s.ledger.record_match(s, m)
	var ev: Array = kills_events.call()
	check(ev.size() == 1 and ev[0]["id"] == so.id and ev[0]["value"] == 40.0, "a mature, full book reports the record")
	if ev.size() == 1:
		check(ev[0]["previous"]["value"] == 34.0 and ev[0]["phase"] == StatRegistry.PHASE_COMBINED, "it names what it passed")
	line["kills"] = 40
	s.ledger.record_match(s, m)
	check(kills_events.call().is_empty(), "a tie is not a record")
	line["kills"] = 41
	s.ledger.record_match(s, m)
	ev = kills_events.call()
	check(ev.size() == 1 and ev[0]["previous"]["value"] == 40.0, "the next record passes the last")
	var top := s.ledger.top("kills", StatRegistry.PHASE_COMBINED)
	check(top.size() == StatLedger.KEEP and top[0]["value"] == 41.0, "the book keeps the best %d" % StatLedger.KEEP)
	# Two players beating the book in one match: only the better line is the record.
	m.result.box[other.id]["kills"] = 45
	line["kills"] = 44
	s.ledger.record_match(s, m)
	ev = kills_events.call()
	check(ev.size() == 1 and ev[0]["id"] == other.id and ev[0]["value"] == 45.0, "one record per stat per match, the best line")
	# A playoff match that tops the playoff book but not the all-time one is a playoff record.
	m.stage = Season.STAGE_FINAL
	line["kills"] = 12
	m.result.box[other.id]["kills"] = 12
	s.ledger.record_match(s, m)
	check(kills_events.call().is_empty(), "a modest playoff line breaks nothing")
	line["kills"] = 20
	m.result.box[other.id]["kills"] = 12
	s.ledger.record_match(s, m)
	ev = kills_events.call()
	check(ev.size() == 1 and ev[0]["phase"] == StatRegistry.PHASE_PLAYOFFS and ev[0]["value"] == 20.0, "20 tops the playoff book (12s) but not the all-time one (%s)" % [ev])


## A team's streak makes news once it passes every other team's best, and only from the fifth game.
func test_streak_events() -> void:
	var s := _season(88)
	s.ledger = StatLedger.new()
	s.ledger.matches_regular = StatLedger.MATURE_AFTER
	var m: ScheduledMatch = _regular(s)[0]
	m.result.winner_index = 0
	var win := m.home
	var lose := m.away
	var counts := []
	for i in 7:
		s.ledger.record_match(s, m)
		counts.append(m.records.filter(func(r): return r["stat"] == "win_streak" or r["stat"] == "lose_streak").size())
	# Calls 1-4: nothing. From call 5 both a win and a losing streak record, each extended every game.
	check(counts == [0, 0, 0, 0, 2, 2, 2], "streak records start at five (%s)" % [counts])
	check(int(s.ledger.run[win.abbrev]) == 7 and int(s.ledger.run[lose.abbrev]) == -7, "current runs")
	var wins := Records.streaks(s, "win_streak")
	check(wins.size() == 1 and wins[0]["team"] == win and wins[0]["value"] == 7.0, "win streak book")
	check(Records.streaks(s, "lose_streak", lose.abbrev)[0]["value"] == 7.0, "losing streak book for one franchise")
	check(Records.streaks(s, "win_streak", lose.abbrev).is_empty(), "no win streak for the losing club")
	m.result.winner_index = 1
	s.ledger.record_match(s, m)
	check(int(s.ledger.run[win.abbrev]) == -1 and int(s.ledger.run[lose.abbrev]) == 1, "a loss ends the run")
	check(int(s.ledger.best_win[win.abbrev]["length"]) == 7, "the best streak is kept")


## Season and career books take a phase: playoff marks are within the combined ones.
func test_records_phase() -> void:
	var s := _season(89)
	var kills: Dictionary = StatRegistry.PLAYER[0]
	var combined := Records.player_seasons(s, kills)
	var playoffs := Records.player_seasons(s, kills, "", StatRegistry.PHASE_PLAYOFFS)
	var regular := Records.player_seasons(s, kills, "", StatRegistry.PHASE_REGULAR)
	check(not combined.is_empty() and not playoffs.is_empty() and not regular.is_empty(), "every phase has a season book")
	check(playoffs[0]["value"] <= combined[0]["value"] and regular[0]["value"] <= combined[0]["value"], "phase books never beat the combined book")
	for e in playoffs:
		var line := StatRegistry.line_for(e["soldier"], StatRegistry.SCOPE_SEASON, StatRegistry.PHASE_PLAYOFFS, e["year"])
		check(float(line.get("kills", 0)) == e["value"], "playoff season entry matches the playoff line")
	for e in Records.player_careers(s, kills, "", StatRegistry.PHASE_PLAYOFFS):
		check(e["value"] == float(e["soldier"].playoff_career.get("kills", 0)), "playoff career entry matches the playoff career")
	for e in Records.player_careers(s, kills, s.user_team().abbrev, StatRegistry.PHASE_PLAYOFFS):
		check(e["value"] <= float(e["soldier"].playoff_career.get("kills", 0)), "franchise playoff career within the career")
	check(Records.format_value(StatRegistry.SINGLE_MATCH[8], 75.0) == MatchEngine._fmt_secs(75.0), "hill time shows as a time")


## Records stamped on matches and the ledger survive a save; their stories are written once.
func test_record_save_and_news() -> void:
	var s := _season(90)
	s.ledger.matches_regular = StatLedger.MATURE_AFTER
	var m: ScheduledMatch = _regular(s)[0]
	var so: Soldier = m.home.starters()[0]
	m.result.box[so.id]["kills"] = 99
	s.ledger.record_match(s, m)
	var rec: Array = m.records.filter(func(r): return r["stat"] == "kills")
	check(rec.size() == 1, "setup: the match broke the kills record")
	var wire := s.news.items.size()
	s.news._record_stories(s, [m], "Week 1", {})
	var stories: Array = s.news.items.slice(wire).filter(func(n): return n["kind"] == "record_broken")
	check(stories.any(func(n): return n["soldier_id"] == so.id and n["headline"].contains("99")), "a record story names the player and value")
	s.news._record_stories(s, [m], "Week 1", {})
	var kills_stories: Array = s.news.items.filter(func(n): return n["kind"] == "record_broken" and n["soldier_id"] == so.id and n["headline"].contains("99"))
	check(kills_stories.size() == 1, "the same record is written once (%d)" % kills_stories.size())
	var loaded := SaveSystem.from_text(SaveSystem.to_text(s))
	check(loaded != null, "season loads")
	if loaded == null:
		return
	check(loaded.ledger.single_match == s.ledger.single_match, "single-match books kept")
	check(loaded.ledger.run == s.ledger.run and loaded.ledger.best_win == s.ledger.best_win, "streaks kept")
	var lm: ScheduledMatch = _regular(loaded)[0]
	check(lm.records.size() == m.records.size() and lm.records[0]["value"] == m.records[0]["value"], "records on the match kept")

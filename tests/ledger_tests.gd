extends SceneTree
## Stat ledger tests (issue #11): phase-tagged totals, once-only recording, saves, determinism.
## Run: godot --headless --path . --script res://tests/ledger_tests.gd   (ONLY=test_a,test_b for a subset)
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
	var impact: Dictionary = StatRegistry.SINGLE_MATCH.filter(func(d): return d["id"] == "impact")[0]
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


## Team totals add up to the box scores and the standings, by phase, and the leaderboards sort them.
func test_team_totals() -> void:
	var s := _season(98)
	var combined := TeamStats.season_totals(s)
	var regular := TeamStats.season_totals(s, StatRegistry.PHASE_REGULAR)
	var playoffs := TeamStats.season_totals(s, StatRegistry.PHASE_PLAYOFFS)
	var box_kills := 0
	var matches := 0
	for m: ScheduledMatch in _regular(s) + s.playoff_matches:
		matches += 1
		for sid in m.result.box:
			box_kills += int(m.result.box[sid]["kills"])
	var wins := 0
	var losses := 0
	var kills := 0
	var deaths := 0
	for abbrev in combined:
		wins += int(combined[abbrev]["wins"])
		losses += int(combined[abbrev]["losses"])
		kills += int(combined[abbrev]["kills"])
		deaths += int(combined[abbrev]["deaths"])
		for k in combined[abbrev]:
			check(is_equal_approx(float(combined[abbrev][k]), float(regular[abbrev][k]) + float(playoffs[abbrev][k])), "%s: combined is regular plus playoffs (%s)" % [abbrev, k])
	check(kills == box_kills and kills == deaths, "team kills add up to the box scores (%d vs %d)" % [kills, box_kills])
	check(wins == matches and losses == matches, "every match has one winner and one loser")
	for row: StandingRow in s.standings():
		check(int(regular[row.team.abbrev]["wins"]) == row.wins and int(regular[row.team.abbrev]["losses"]) == row.losses, "%s regular record matches the standings" % row.team.abbrev)
	var sum_diff := 0
	for abbrev in combined:
		sum_diff += int(combined[abbrev]["game_diff"])
	check(sum_diff == 0, "game differentials cancel out")
	for stat: Dictionary in TeamStats.LEADERS:
		var rows := TeamStats.top(s, stat)
		check(rows.size() <= TeamStats.TOP_N, "%s list is capped" % stat["id"])
		for i in range(1, rows.size()):
			check(rows[i - 1]["value"] >= rows[i]["value"], "%s list is sorted" % stat["id"])
	var wins_top := TeamStats.top(s, TeamStats.LEADERS[0], StatRegistry.PHASE_REGULAR)
	var most := 0
	for abbrev in regular:
		most = maxi(most, int(regular[abbrev]["wins"]))
	check(not wins_top.is_empty() and wins_top[0]["value"] == float(most), "the wins leader has the most wins")

## Every match lands in one weather bucket and one surface bucket, home or away, and they add up to the career.
func test_weather_splits() -> void:
	var s := _season(96)
	var so: Soldier = s.league.all_soldiers().filter(func(x: Soldier): return x.season_lines.has(s.year))[0]
	var home := 0
	var away := 0
	for m: ScheduledMatch in _regular(s) + s.playoff_matches:
		if m.is_played() and m.result.box.has(so.id):
			if int(m.result.box[so.id]["team"]) == 0:
				home += 1
			else:
				away += 1
	var all := StatRegistry.weather_line(so)
	check(int(all["matches"]) == int(so.career["matches"]) and int(all["kills"]) == int(so.career["kills"]), "weather buckets add up to the career")
	var surfaces := StatRegistry.surface_line(so)
	check(int(surfaces["matches"]) == int(so.career["matches"]) and int(surfaces["damage"]) == int(so.career["damage"]), "surface buckets add up to the career")
	check(int(StatRegistry.weather_line(so, "", -1, "home").get("matches", 0)) == home, "home matches (%d)" % home)
	check(int(StatRegistry.weather_line(so, "", -1, "away").get("matches", 0)) == away, "away matches (%d)" % away)
	# A rainy, sandy match goes to its own buckets.
	var m: ScheduledMatch = _regular(s)[0]
	var r := m.result
	r.weather_kind = Weather.RAIN
	r.weather_level = 2
	r.surface = "sand"
	var star: Soldier = r.teams[1].starters()[0]
	var kills_before := int(StatRegistry.weather_line(star, "rain", 2, "away").get("kills", 0))
	Progression.award_match_xp(r, 0)
	var rain := StatRegistry.weather_line(star, "rain", 2, "away")
	check(int(rain["matches"]) == 1 and int(rain["kills"]) == kills_before + int(r.box[star.id]["kills"]), "a rainy match counts toward rain")
	check(int(StatRegistry.surface_line(star, "sand", "away")["matches"]) == 1, "and toward sand")
	check(StatRegistry.weather_line(star, "snow").is_empty(), "not toward snow")
	var loaded := SaveSystem.from_text(SaveSystem.to_text(s))
	check(loaded != null, "season loads")
	if loaded != null:
		var twin: Soldier = loaded.league.all_soldiers().filter(func(x: Soldier): return x.id == star.id)[0]
		check(twin.split_career == star.split_career, "splits survive a save")


## Playing well or badly in rain or snow needs a real sample in both, and a clear gap.
func test_weather_edges() -> void:
	var so := Soldier.new()
	so.split_career = {
		"wx|clear|0|home": {"matches": 10, "kills": 20, "deaths": 20},
		"wx|rain|1|home": {"matches": 4, "kills": 10, "deaths": 4},
		"wx|rain|2|away": {"matches": 4, "kills": 12, "deaths": 4},
		"wx|snow|1|home": {"matches": 7, "kills": 7, "deaths": 14},
	}
	var edges := StatRegistry.weather_edges(so)
	var by_kind := {}
	for e in edges:
		by_kind[e["kind"]] = e
	check(by_kind.has(&"rain") and by_kind[&"rain"]["well"] and by_kind[&"rain"]["matches"] == 8, "light and inclement rain add up, and he plays well in it")
	check(by_kind.has(&"snow") and not by_kind[&"snow"]["well"], "he struggles in snow")
	so.split_career["wx|clear|0|home"]["matches"] = 5
	check(StatRegistry.weather_edges(so).is_empty(), "too few clear matches says nothing")
	so.split_career["wx|clear|0|home"]["matches"] = 10
	so.split_career["wx|rain|1|home"] = {"matches": 4, "kills": 4, "deaths": 4}
	so.split_career["wx|rain|2|away"] = {"matches": 4, "kills": 4, "deaths": 4}
	check(not StatRegistry.weather_edges(so).any(func(e): return e["kind"] == &"rain"), "an ordinary gap is no edge")

## Telemetry counters in every box line agree with each other and with the match.
func test_telemetry_box() -> void:
	var s := _season(94)
	var moved := 0.0
	var cover := 0.0
	var opening_matches := 0
	var total_matches := 0
	for m: ScheduledMatch in _regular(s):
		var openings := 0
		for sid in m.result.box:
			var b: Dictionary = m.result.box[sid]
			check(int(b["kills_short"]) + int(b["kills_medium"]) + int(b["kills_long"]) == int(b["kills"]), "kills by range add up to kills")
			check(int(b["bursts"]) >= int(b["first_shot_n"]) and (int(b["bursts"]) == 0 or int(b["first_shot_n"]) > 0), "first shots come from bursts")
			check(float(b["fire_dist"]) >= 0.0 and float(b["distance"]) >= 0.0 and float(b["cover_s"]) >= 0.0, "telemetry is never negative")
			if int(b["bursts"]) > 0:
				var avg := float(b["fire_dist"]) / int(b["bursts"])
				check(avg > 0.0 and avg < 150.0, "average engagement range is plausible (%s)" % avg)
			openings += int(b["opening_kills"])
			moved += float(b["distance"])
			cover += float(b["cover_s"])
		total_matches += 1
		opening_matches += 1 if openings >= 1 else 0
	check(opening_matches == total_matches, "every match has an opening kill")
	check(moved > 0.0 and cover > 0.0, "soldiers moved and took cover (%s m, %s s)" % [moved, cover])


## Telemetry flows into season and career lines (rounded per match), then into the registry's readings.
func test_telemetry_lines() -> void:
	var s := _season(95)
	var so: Soldier = s.league.all_soldiers().filter(func(x: Soldier): return x.season_lines.has(s.year))[0]
	var want := {"distance": 0, "kills_long": 0, "opening_kills": 0, "bursts": 0, "first_shot_s": 0}
	for m: ScheduledMatch in _regular(s) + s.playoff_matches:
		if m.is_played() and m.result.box.has(so.id):
			var b: Dictionary = m.result.box[so.id]
			for k in want:
				want[k] += roundi(float(b[k]))
	for k in want:
		check(int(so.career[k]) == want[k] and int(so.season_lines[s.year][k]) == want[k], "%s totals the matches (%s vs %s)" % [k, so.career[k], want[k]])
	var line := {"matches": 10, "kills": 20, "kills_short": 8, "kills_medium": 8, "kills_long": 4, "kill_dist": 400, "bursts": 50, "fire_dist": 1500,
		"first_shot_s": 60, "first_shot_n": 20, "contest_s": 30, "hill_s": 90, "distance": 12345, "cover_s": 75, "opening_kills": 3}
	var rows := {}
	for r in StatRegistry.telemetry_rows(line):
		rows[r[0]] = r[1]
	check(rows["Average kill range"] == "20.0 m" and rows["Average engagement range"] == "30.0 m", "ranges average over tracked kills and bursts")
	check(rows["Distance covered"] == "12345 m" and rows["Time in cover"] == "1:15" and rows["Average time to first shot"] == "3.0 s", "totals and times read well")
	check(rows["Share of hill time contested"] == "25%" and rows["Opening kills"] == "3", "share and count")
	var empty := {}
	for r in StatRegistry.telemetry_rows({"matches": 1}):
		empty[r[0]] = r[1]
	check(empty["Average kill range"] == "-" and empty["Share of hill time contested"] == "-", "nothing to average reads as a dash")
	var avg: Dictionary = StatRegistry.LEADERS.filter(func(d): return d["id"] == "kill_range")[0]
	check(StatRegistry.value_of(avg, line, 5) == 20.0 and StatRegistry.value_of(avg, {"matches": 9}, 5) == -1.0, "average leaders skip lines with nothing tracked")
## Season end names the MVP, and a season that tops the league's single-season book makes news once.
func test_award_stories() -> void:
	var s := _season(91)
	var mvp: Dictionary = s.review.awards.filter(func(a): return a["award"] == "Season MVP")[0]
	var mvp_news: Array = s.news.items.filter(func(n): return n["kind"] == "mvp" and n["year"] == s.year)
	check(mvp_news.size() == 1 and mvp_news[0]["soldier_id"] == mvp["soldier"].id, "the Season MVP makes the wire once")
	var year := s.year
	var kills: Dictionary = StatRegistry.PLAYER[0]
	var rows: Array = s.league.all_soldiers().filter(func(so: Soldier): return so.season_lines.has(year))
	var star: Soldier = rows[0]
	var old: Soldier = rows[1]
	old.season_lines[year - 3] = (old.season_lines[year] as Dictionary).duplicate()
	old.season_lines[year - 3]["kills"] = 400
	star.season_lines[year]["kills"] = 500
	s.news.items = s.news.items.filter(func(n): return n["kind"] != "season_record")
	star.news_tags.erase("season_record")
	s.news._award_stories(s)
	var rec: Array = s.news.items.filter(func(n): return n["kind"] == "season_record" and n["soldier_id"] == star.id)
	check(rec.size() == 1 and rec[0]["headline"].contains("500"), "a new season record is a story naming the value")
	s.news._award_stories(s)
	check(s.news.items.filter(func(n): return n["kind"] == "season_record" and n["soldier_id"] == star.id).size() == 1, "written once a year")
	check(Records.player_seasons(s, kills)[0]["soldier"] == star, "setup: he holds the book")


## A new franchise starts with the same fixed books, a bigger book than the sim's first season, and a
## player can still break them.
func test_seeded_books() -> void:
	Season.seed_records = true
	var a := Season.new_franchise(92, 0)
	var b := Season.new_franchise(93, 1)
	Season.seed_records = false
	check(a.ledger.seeded and b.ledger.seeded, "new franchises are seeded")
	check(str(a.ledger.single_match) == str(b.ledger.single_match) and str(a.ledger.best_win) == str(b.ledger.best_win), "every league starts with the same books")
	for stat: Dictionary in StatRegistry.SINGLE_MATCH:
		if stat["id"] == "hill_s":
			continue
		var all := a.ledger.top(stat["id"], StatRegistry.PHASE_COMBINED)
		var po := a.ledger.top(stat["id"], StatRegistry.PHASE_PLAYOFFS)
		check(all.size() == StatLedger.KEEP and po.size() == StatLedger.KEEP, "%s books are full" % stat["id"])
		check(po[0]["value"] <= all[0]["value"], "%s playoff mark within the all-time mark" % stat["id"])
	for stat: Dictionary in Records.PLAYER_STATS:
		check(Records.player_seasons(a, stat).size() == Records.TOP_N, "%s season book is full" % stat["id"])
		check(Records.player_careers(a, stat).size() == Records.TOP_N, "%s career book is full" % stat["id"])
		check(str(Records.player_seasons(a, stat).map(func(r): return [r["name"], r["value"]])) == str(Records.player_seasons(b, stat).map(func(r): return [r["name"], r["value"]])), "%s season book is the same in both leagues" % stat["id"])
	check(Records.team_seasons(a, Records.TEAM_STATS[0]).size() == Records.TOP_N, "team seasons are seeded")
	check(Records.streaks(a, "win_streak").size() > 0, "streaks are seeded")
	# Early matches are held to the seeded marks: a modest game is not a record, a huge one is.
	var m: ScheduledMatch = _regular(a)[0]
	a.sim_week()
	m = _regular(a)[0]
	check(m.records.is_empty(), "an ordinary week breaks no seeded record")
	var so: Soldier = m.home.starters()[0]
	m.result.box[so.id]["kills"] = 60
	a.ledger.record_match(a, m)
	var rec: Array = m.records.filter(func(r): return r["stat"] == "kills")
	check(rec.size() == 1 and rec[0]["value"] == 60.0 and not rec[0]["previous"].is_empty(), "a player can break a seeded record")
	var scoped := Records.single_matches(a, StatRegistry.SINGLE_MATCH[0], StatRegistry.PHASE_COMBINED, "NYE")
	check(scoped.all(func(r): return r["team"] == "NYE"), "franchise books hold only that club")
	var loaded := SaveSystem.from_text(SaveSystem.to_text(a))
	check(loaded != null and loaded.ledger.seeded and str(loaded.ledger.single_match) == str(a.ledger.single_match), "seeded books survive a save")


## Telemetry stats have record books too: seeded targets that a big match, season or career can pass.
func test_telemetry_records() -> void:
	Season.seed_records = true
	var a := Season.new_franchise(97, 0)
	Season.seed_records = false
	var ids := ["opening_kills", "kills_long", "distance"]
	for id in ids:
		var match_stat: Dictionary = StatRegistry.SINGLE_MATCH.filter(func(d): return d["id"] == id)[0]
		check(Records.single_matches(a, match_stat).size() == Records.TOP_N, "%s single-match book is seeded" % id)
		var player_stat: Dictionary = StatRegistry.PLAYER.filter(func(d): return d["id"] == id)[0]
		check(Records.player_seasons(a, player_stat).size() == Records.TOP_N and Records.player_careers(a, player_stat).size() == Records.TOP_N, "%s season and career books are seeded" % id)
	var dist: Dictionary = StatRegistry.PLAYER.filter(func(d): return d["id"] == "distance")[0]
	check(Records.format_value(dist, 11800.0) == "11800 m", "distance reads in metres")
	a.sim_week()
	var m: ScheduledMatch = _regular(a)[0]
	var so: Soldier = m.home.starters()[0]
	m.result.box[so.id]["kills_long"] = 40
	m.result.box[so.id]["distance"] = 9000.0
	a.ledger.record_match(a, m)
	var hit := m.records.map(func(r): return r["stat"])
	check(hit.has("kills_long") and hit.has("distance"), "a huge match breaks the telemetry records (%s)" % [hit])
	var ev: Dictionary = m.records.filter(func(r): return r["stat"] == "distance")[0]
	check(ev["noun"] == "of ground covered" and not ev["previous"].is_empty(), "it names what it passed")


## Every league match lands in its pair's head-to-head, once, with the last meetings kept.
func test_head_to_head() -> void:
	var s := _season(99)
	var played := 0
	for m: ScheduledMatch in _regular(s) + s.playoff_matches:
		played += 1
	var meetings := 0
	for k in s.ledger.head_to_head:
		var rec: Dictionary = s.ledger.head_to_head[k]
		meetings += int(rec["n"])
		var wins := 0
		for abbrev in rec["w"]:
			wins += int(rec["w"][abbrev])
		check(wins == int(rec["n"]), "%s: wins add up to meetings" % k)
		check((rec["meetings"] as Array).size() == mini(int(rec["n"]), StatLedger.MEETINGS_KEPT), "%s: the last meetings are kept" % k)
		check(rec["last"] == rec["meetings"][-1], "%s: last is the latest meeting" % k)
	check(meetings == played, "every match is in a head-to-head (%d vs %d)" % [meetings, played])
	var m0: ScheduledMatch = _regular(s)[0]
	var rec0 := s.ledger.head_to_head_of(m0.home, m0.away)
	check(not rec0.is_empty() and s.ledger.series_text(m0.home, m0.away) == s.ledger.series_text(m0.away, m0.home), "the series reads the same from either side")
	# A long series keeps only the latest meetings.
	var a: Team = m0.home
	var b: Team = m0.away
	var key := Rivalries.key(a.abbrev, b.abbrev)
	var before := int(s.ledger.head_to_head[key]["n"])
	for i in StatLedger.MEETINGS_KEPT + 3:
		var extra := ScheduledMatch.new()
		extra.week = 1
		extra.stage = Season.STAGE_REGULAR
		extra.home = a
		extra.away = b
		extra.result = MatchResult.new()
		extra.result.teams.assign([a, b])
		extra.result.score.assign([2, 1])
		extra.result.winner_index = 0
		s.ledger.record_match(s, extra)
	var rec1: Dictionary = s.ledger.head_to_head[key]
	check(int(rec1["n"]) == before + StatLedger.MEETINGS_KEPT + 3 and (rec1["meetings"] as Array).size() == StatLedger.MEETINGS_KEPT, "history is capped at %d" % StatLedger.MEETINGS_KEPT)


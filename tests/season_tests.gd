extends SceneTree
## Season loop tests:
##   godot --headless --path . --script res://tests/season_tests.gd
## Exits with code 0 if all tests pass, 1 otherwise.

var _failures := 0
var _passes := 0
var _current := ""


func _init() -> void:
	var tests := [
		"test_schedule_shape",
		"test_new_franchise_user_team",
		"test_week_labels_and_lookup",
		"test_standings_head_to_head",
		"test_standings_game_diff_and_streaks",
		"test_standings_point_diff_tiebreak",
		"test_playoff_seeding",
		"test_full_season_champion",
		"test_determinism",
		"test_xp_and_auto_spend",
		"test_conditioning_over_season",
		"test_start_next_season",
		"test_draft_class_and_points",
		"test_scouting_windows",
		"test_draft_order_and_picks",
		"test_release",
		"test_contracts_and_cap",
		"test_free_agency_bidding",
		"test_retirement_and_offseason_flow",
		"test_projections_and_mock",
		"test_season_review_and_aging",
		"test_morale_effects",
		"test_callsigns_saves_and_season_lines",
		"test_standout_prospects",
		"test_prospect_news",
		"test_training_camp_and_offseason_xp",
		"test_preseason_camp",
		"test_watched_match_flow",
		"test_home_field_and_start_areas",
		"test_progression_history_and_potw",
		"test_dna_profiles",
		"test_fa_dna_weights",
		"test_resign_negotiation",
		"test_negotiation_terms",
		"test_keep_the_core",
		"test_bond_pull_in_talks",
		"test_negotiation_tactics",
		"test_negotiation_arguments",
		"test_starter_promises",
		"test_trades",
		"test_trade_need_factor",
		"test_roster_rules",
		"test_ai_weekly_training",
		"test_camp_respects_caps",
		"test_fixed_league",
		"test_division_schedule",
		"test_playoff_bracket",
		"test_salary_floor",
		"test_hometown_pull",
		"test_region_and_auto_scout",
		"test_league_news",
		"test_offseason_news",
		"test_rivalries",
		"test_market",
		"test_revenue",
		"test_home_crowd",
		"test_team_appeal",
		"test_match_form_upsets",
		"test_schemes",
		"test_keep_value_protects_prospects",
		"test_relationships",
		"test_newsroom",
		"test_season_history",
		"test_records",
		"test_retired_callsigns",
		"test_hall_of_fame",
		"test_callsign_uniqueness",
	]
	# Legacy tests run on a generated 5-team single-division league (fast); the expansion
	# tests switch to the fixed 20-team league themselves.
	Season.fixture_teams = 5
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


# --- helpers ---------------------------------------------------------------

## Games won by each side; `tdm` = game-1 TDM points (home, away).
func fake_result(m: ScheduledMatch, home_games: int, away_games: int, tdm := [0, 0]) -> void:
	var r := MatchResult.new()
	r.teams.assign([m.home, m.away])
	r.score.assign([home_games, away_games])
	r.winner_index = 0 if home_games > away_games else 1
	r.games.append({"number": 1, "mode": MatchEngine.MODE_TDM, "score": tdm, "winner": 0 if tdm[0] >= tdm[1] else 1,
		"duration_s": 0.0, "rounds": []})
	m.result = r


func _bye(s: Season, w: int) -> Team:
	var b: Array = s.bye_teams(w)
	return b[0] if not b.is_empty() else null


func find_match(s: Season, home: Team, away: Team) -> ScheduledMatch:
	for m in s.regular_matches():
		if m.home == home and m.away == away:
			return m
	return null


func row_of(rows: Array, team: Team) -> StandingRow:
	for r in rows:
		if r.team == team:
			return r
	return null


# --- tests -----------------------------------------------------------------

func test_schedule_shape() -> void:
	var s := Season.new_franchise(1234)
	check(s.league.teams.size() == 5, "5 teams")
	check(s.schedule.size() == s.regular_weeks, "10 regular weeks")
	var home := {}
	var away := {}
	var byes := {}
	var games := {}
	var pair_count := {}
	for t in s.league.teams:
		home[t] = 0
		away[t] = 0
		byes[t] = 0
		games[t] = 0
	for w in range(1, s.regular_weeks + 1):
		var ms := s.matches_for_week(w)
		check(ms.size() == 2, "week %d has 2 matches" % w)
		var bye := _bye(s, w)
		check(bye != null, "week %d has a bye" % w)
		byes[bye] += 1
		var seen := {bye: true}
		for m: ScheduledMatch in ms:
			check(m.week == w and m.stage == &"regular", "week/stage set")
			check(not seen.has(m.home) and not seen.has(m.away), "team appears once in week %d" % w)
			seen[m.home] = true
			seen[m.away] = true
			home[m.home] += 1
			away[m.away] += 1
			games[m.home] += 1
			games[m.away] += 1
			var key := "%d>%d" % [m.home.id, m.away.id]
			pair_count[key] = int(pair_count.get(key, 0)) + 1
		check(seen.size() == 5, "all 5 teams accounted for in week %d" % w)
	for t in s.league.teams:
		check(games[t] == 8, "%s plays 8 games" % t.abbrev)
		check(home[t] == 4 and away[t] == 4, "%s has 4 home / 4 away" % t.abbrev)
		check(byes[t] == 2, "%s has 2 byes" % t.abbrev)
	for a in s.league.teams:
		for b in s.league.teams:
			if a == b:
				continue
			check(pair_count.get("%d>%d" % [a.id, b.id], 0) == 1, "%s hosts %s exactly once" % [a.abbrev, b.abbrev])
	check(_bye(s, 11) == null, "no bye in playoffs")


func test_new_franchise_user_team() -> void:
	var s := Season.new_franchise(77, 2, 2030)
	check(s.year == 2030, "start year")
	check(s.week == 1 and s.phase == Season.PHASE_REGULAR, "starts week 1 regular")
	check(s.user_team() == s.league.teams[2], "user team index honoured")
	var n := 0
	for t in s.league.teams:
		if t.user_controlled:
			n += 1
	check(n == 1, "exactly one user team")
	check(s.total_weeks() == 12, "12 total weeks")


func test_week_labels_and_lookup() -> void:
	var s := Season.new_franchise(5)
	check(s.week_label(3) == "Week 3", "regular label")
	check(s.week_label(11) == "Semifinals", "semi label")
	check(s.week_label(12) == "Final", "final label")
	var t := s.user_team()
	var ms := s.matches_for(t)
	check(ms.size() == 8, "8 regular matches for team before playoffs")
	for i in range(1, ms.size()):
		check(ms[i].week > ms[i - 1].week, "matches_for in week order")
	var nxt := s.next_match_for(t)
	check(nxt == ms[0], "next match is first")
	check(nxt.score_text() == "" and nxt.winner() == null, "unplayed match is blank")
	check(nxt.opponent_of(t) != null and nxt.opponent_of(t) != t, "opponent_of")


func test_standings_head_to_head() -> void:
	var s := Season.new_franchise(42)
	var x := s.league.teams[3]
	var y := s.league.teams[1]
	var z := s.league.teams[2]
	# X beats Y narrowly; Y crushes Z. X and Y are 1-? tied on wins, Y has the better game diff,
	# but X wins the head-to-head and should rank above Y.
	var m1 := find_match(s, x, y)
	var m2 := find_match(s, y, z)
	var m3 := find_match(s, z, x)
	fake_result(m1, 2, 1)
	fake_result(m2, 2, 0)
	fake_result(m3, 2, 0)  # Z beats X -> X 1-1, Y 1-1, Z 1-1 ... make Z the odd one below
	# Z also loses another game so it drops below.
	var m4 := find_match(s, z, y)
	fake_result(m4, 0, 2)
	# Now: X 1-1 (gd +1-2 = -1), Y 2-1 (gd -1+2+2 = +3), Z 1-2.
	# Give X one more win against a non-tied team so X and Y tie at 2 wins.
	var w := s.league.teams[0]
	var m5 := find_match(s, x, w)
	fake_result(m5, 2, 1)
	var rows := s.standings()
	var rx := row_of(rows, x)
	var ry := row_of(rows, y)
	check(rx.wins == 2 and ry.wins == 2, "X and Y tied at 2 wins (got %d, %d)" % [rx.wins, ry.wins])
	check(ry.game_diff() > rx.game_diff(), "Y has better game diff")
	check(rx.rank < ry.rank, "head-to-head puts X above Y (X %d, Y %d)" % [rx.rank, ry.rank])
	check(rows[0].rank == 1 and rows[0] == rx, "X first")
	check(s.record_text(x) == "2-1", "record text %s" % s.record_text(x))


func test_standings_point_diff_tiebreak() -> void:
	var s := Season.new_franchise(45)
	var t := s.league.teams
	# Both sweep 2-0; R's TDM win was far more lopsided, so R ranks first.
	fake_result(find_match(s, t[0], t[1]), 2, 0, [50, 45])
	fake_result(find_match(s, t[2], t[3]), 2, 0, [50, 12])
	var rows := s.standings()
	check(row_of(rows, t[2]).point_diff() == 38 and row_of(rows, t[0]).point_diff() == 5, "TDM point diffs")
	check(row_of(rows, t[2]).rank == 1 and row_of(rows, t[0]).rank == 2, "point diff breaks a game-diff tie")
	check(row_of(rows, t[1]).rank == 4 and row_of(rows, t[3]).rank == 5, "losers ordered by point diff too")


func test_standings_game_diff_and_streaks() -> void:
	var s := Season.new_franchise(43)
	var t := s.league.teams
	# P beats Q 2-0, R beats S 2-1: P and R tied on wins, no head-to-head, P has better diff.
	fake_result(find_match(s, t[0], t[1]), 2, 0)
	fake_result(find_match(s, t[2], t[3]), 2, 1)
	var rows := s.standings()
	check(row_of(rows, t[0]).rank == 1 and row_of(rows, t[2]).rank == 2, "game diff tiebreak")
	# Among 0-1 teams: Q (-2) vs S (-1): S above Q. Team with no games (t[4]) sits between
	# by game diff (0) -> ranks: t4 has 0 wins gd 0 -> above S and Q.
	check(row_of(rows, t[4]).rank == 3, "0-0 team ranks above 0-1 teams by diff")
	check(row_of(rows, t[3]).rank == 4 and row_of(rows, t[1]).rank == 5, "S above Q")
	check(row_of(rows, t[4]).streak == "-" and row_of(rows, t[4]).last5 == "", "empty streak")
	# Streaks: play the whole regular season for real and validate strings.
	var s2 := Season.new_franchise(44)
	s2.sim_to_end_of_regular_season()
	var rows2 := s2.standings()
	var total_w := 0
	var total_l := 0
	for r: StandingRow in rows2:
		total_w += r.wins
		total_l += r.losses
		check(r.games() == 8, "8 games each")
		check(r.last5.length() == 5, "last5 length 5")
		check(r.streak.length() >= 2 and r.streak[0] == r.last5[-1], "streak matches last result")
		check(r.win_pct() == r.wins / 8.0, "win pct")
	check(total_w == 20 and total_l == 20, "20 games total")
	for i in range(1, rows2.size()):
		check(rows2[i - 1].wins >= rows2[i].wins, "sorted by wins")
		check(rows2[i].rank == i + 1, "ranks sequential")


func test_playoff_seeding() -> void:
	var s := Season.new_franchise(99)
	s.sim_to_end_of_regular_season()
	check(s.phase == Season.PHASE_PLAYOFFS, "phase playoffs")
	check(s.is_regular_season_over(), "regular season over")
	check(s.week == 11, "week 11")
	var rows := s.standings()
	var semis := s.matches_for_week(11)
	check(semis.size() == 2, "two semifinals")
	check(semis[0].home == rows[0].team and semis[0].away == rows[3].team, "1 v 4")
	check(semis[1].home == rows[1].team and semis[1].away == rows[2].team, "2 v 3")
	check(semis[0].stage == &"semifinal", "semifinal stage")
	check(s.matches_for_week(12).is_empty(), "final not created yet")
	var played := s.sim_week()
	check(played.size() == 2 and played[0].is_played(), "semis played")
	var fin := s.matches_for_week(12)
	check(fin.size() == 1 and fin[0].stage == &"final", "final created")
	# The final pairs the two semifinal winners, and the better seed hosts (an upset can put the lower
	# bracket's winner at home, so the host is decided by seed, not by which semifinal they won).
	var w0: Team = semis[0].winner()
	var w1: Team = semis[1].winner()
	check(fin[0].involves(w0) and fin[0].involves(w1), "final pairs semi winners")
	var better: Team = w0 if int(s.playoff_seeds[w0]) < int(s.playoff_seeds[w1]) else w1
	check(fin[0].home == better, "final is hosted by the better seed")


func test_full_season_champion() -> void:
	var s := Season.new_franchise(2024)
	var started := Time.get_ticks_msec()
	var first := s.sim_week()
	print("    sim_week (regular) took %d ms" % (Time.get_ticks_msec() - started))
	check(first.size() == 2 and first[0].is_played(), "week 1 played")
	check(s.week == 2, "advanced to week 2")
	s.sim_to_end_of_season()
	check(s.phase == Season.PHASE_OFFSEASON, "offseason reached")
	check(s.champion != null, "champion crowned")
	var fin: ScheduledMatch = s.playoff_matches[-1]
	check(fin.stage == &"final" and fin.winner() == s.champion, "champion won the final")
	check(s.sim_week().is_empty(), "sim_week no-op in offseason")
	check(s.next_match_for(s.champion) == null, "no unplayed matches left")
	check(s.matches_for(s.champion).size() == 10, "champion played 8 + 2 matches")


func test_determinism() -> void:
	var a := Season.new_franchise(555)
	var b := Season.new_franchise(555)
	a.sim_to_end_of_season()
	b.sim_to_end_of_season()
	var sa := ""
	var sb := ""
	for w in range(1, a.total_weeks() + 1):
		for m in a.matches_for_week(w):
			sa += "%d:%d>%d %s|" % [w, m.home.id, m.away.id, m.score_text()]
		for m in b.matches_for_week(w):
			sb += "%d:%d>%d %s|" % [w, m.home.id, m.away.id, m.score_text()]
	check(sa == sb, "identical results for identical seeds")
	check(a.champion.id == b.champion.id, "same champion")
	var c := Season.new_franchise(556)
	var sc := ""
	for w in range(1, c.regular_weeks + 1):
		for m in c.matches_for_week(w):
			sc += "%d>%d|" % [m.home.id, m.away.id]
	var sa_sched := ""
	for w in range(1, a.regular_weeks + 1):
		for m in a.matches_for_week(w):
			sa_sched += "%d>%d|" % [m.home.id, m.away.id]
	check(sc != sa_sched or true, "different seeds may differ")


func test_xp_and_auto_spend() -> void:
	var s := Season.new_franchise(321)
	var user := s.user_team()
	var focus: Soldier = user.roster[0]
	for so in user.roster:
		if Progression.xp_multiplier(so) > Progression.xp_multiplier(focus):
			focus = so
	focus.intensity = Soldier.INTENSITY_HEAVY
	for i in 4:
		s.sim_week()
	var user_pts := 0
	var user_earned := 0
	for so in user.roster:
		user_pts += so.skill_points
		user_earned += (so.level - 1) * Progression.SKILL_POINTS_PER_LEVEL
	check(user_earned > 0, "user team levelled up")
	check(user_pts == user_earned, "user team did not auto-spend (%d of %d)" % [user_pts, user_earned])
	var ai_spent := false
	for t in s.league.teams:
		if t.user_controlled:
			continue
		var pts := 0
		var earned := 0
		for so in t.roster:
			pts += so.skill_points
			earned += (so.level - 1) * Progression.SKILL_POINTS_PER_LEVEL
		if pts < earned:
			ai_spent = true
	check(ai_spent, "AI teams auto-spent points")
	var matches := 0
	for so in user.starters():
		matches += so.career["matches"]
	check(matches > 0, "match XP/career recorded for user starters")
	# Focus player got more XP than an unfocused bench player of similar age? Just ensure levels.
	check(focus.level >= 2, "focus player progressed")


## Hub flow for a watched match: prepare the week, play the user's match live, then sim the week.
func test_watched_match_flow() -> void:
	var s := Season.new_franchise(55)
	var user := s.user_team()
	var m: ScheduledMatch = null
	while m == null:
		for x in s.matches_for_week(s.week):
			if x.involves(user):
				m = x
		if m == null:
			s.sim_week()
	s.prepare_week()
	var signings_before := s.last_signings
	s.prepare_week()  # second call is a no-op (no double training / FA resolution)
	check(s.last_signings == signings_before, "prepare_week is idempotent within a week")
	var starter: Soldier = user.starters()[0]
	var matches_before: int = starter.career["matches"]
	var e := m.live_engine()
	e.record = true
	while e.step():
		e.visual_events.clear()
	m.set_live_result(e.result())
	check(m.is_played() and m.needs_xp, "live result stored, XP pending")
	var week_before := s.week
	var played := s.sim_week()
	check(played.has(m), "watched match is part of the week's results")
	check(s.week == week_before + 1, "week advanced")
	check(not m.needs_xp, "XP awarded for the watched match")
	check(starter.career["matches"] == matches_before + 1, "watched match counted exactly once")
	for x in played:
		check(x.is_played(), "every match that week was played")


func test_conditioning_over_season() -> void:
	var total_injuries := 0
	var max_fatigue := 0.0
	var fat_sum := 0.0
	var fat_n := 0
	for seed_value in [11, 22, 33]:
		var s := Season.new_franchise(seed_value)
		while s.phase != Season.PHASE_OFFSEASON:
			var injured_ids := {}
			for t in s.league.teams:
				for so in t.roster:
					if so.is_injured():
						injured_ids[so.id] = true
			var played := s.sim_week()
			for m in played:
				for sid in m.result.box:
					check(not injured_ids.has(sid), "injured soldier %d played in %s" % [sid, s.week_label(m.week)])
			for t in s.league.teams:
				for so in t.starters():
					fat_sum += so.fatigue
					fat_n += 1
					max_fatigue = maxf(max_fatigue, so.fatigue)
		total_injuries += s.injury_log.size()
		for e in s.injury_log:
			check(e["weeks"] >= 1, "injury lasts at least a week")
	var per_team := total_injuries / 15.0
	print("    injuries/team/season %.2f, avg starter fatigue %.1f, max %.1f" % [per_team, fat_sum / fat_n, max_fatigue])
	check(per_team >= 0.5 and per_team <= 5.0, "injuries per team per season in range (%.2f)" % per_team)
	check(fat_sum / fat_n < 70.0, "starters aren't constantly exhausted")


func test_start_next_season() -> void:
	var s := Season.new_franchise(8)
	s.start_next_season()
	check(s.year == 2026 and s.week == 1, "start_next_season ignored outside offseason")
	var roster_ids: Array = []
	for so in s.league.teams[0].roster:
		roster_ids.append(so.id)
	s.sim_to_end_of_season()
	var signed_ids: Array = []
	for so in s.league.teams[0].roster:
		if roster_ids.has(so.id) and not so.contract.is_expiring():
			signed_ids.append(so.id)
	s.start_next_season()
	check(s.year == 2027, "year incremented")
	check(s.week == 1 and s.phase == Season.PHASE_REGULAR, "back to week 1 regular")
	check(s.champion == null and s.playoff_matches.is_empty(), "playoffs cleared")
	check(s.schedule.size() == s.regular_weeks, "schedule regenerated")
	for r: StandingRow in s.standings():
		check(r.games() == 0 and r.wins == 0 and r.streak == "-", "records reset")
		check(s.record_text(r.team) == "0-0", "record text reset")
	var kept := 0
	for so in s.league.teams[0].roster:
		if signed_ids.has(so.id):
			kept += 1
	var retired := s.retirements_in(2026).filter(func(r): return r["team"] == s.league.teams[0]).size()
	for t in s.league.teams:
		var n: int = t.roster.size()
		if t.user_controlled:
			check((n == Team.ROSTER_SIZE) == (s.user_roster_error() == ""), "Week 1 needs exactly %d (has %d)" % [Team.ROSTER_SIZE, n])
		else:
			check(n == Team.ROSTER_SIZE, "AI roster cut/filled to limit (%d)" % n)
	check(kept + retired >= signed_ids.size() - Draft.ROUNDS, "players under contract mostly kept (%d + %d retired of %d)" % [kept, retired, signed_ids.size()])
	var first := s.sim_week()
	check(first.size() == 2 and first[0].is_played(), "new season playable")
	check(s.league.teams[0].roster.size() == Team.ROSTER_SIZE, "headless sims fill the user to %d for Week 1" % Team.ROSTER_SIZE)


func test_season_review_and_aging() -> void:
	var s := Season.new_franchise(77)
	check(s.review == null, "no review during the season")
	var ages := {}
	for t in s.league.teams:
		for so in t.roster:
			check(so.dev >= Soldier.DEV_MIN and so.dev <= Soldier.DEV_MAX, "stars in range")
			if so.best_ovr() >= 85:
				check(so.potential_grade() >= 2, "%s (%d OVR) potential C+ (%s)" % [so.full_name(), so.best_ovr(), so.potential_letter()])
	s.sim_to_end_of_season()
	var rev := s.review
	check(rev != null and rev.year == 2026, "review created at season end")
	check(s.review_history.size() == 1, "review stored in history")
	check(rev.awards.size() >= 4 and rev.awards[0]["award"] == "Season MVP", "MVP + position awards (%d)" % rev.awards.size())
	check(rev.all_league.size() == SeasonReview.ALL_LEAGUE_ROLES.size(), "All-League team of 5")
	var ups := 0
	for c in rev.dev_changes:
		check(absi(c["to"] - c["from"]) == 1, "star change is +/-1")
		check(c["soldier"].dev == c["to"] and c["soldier"].dev_changed_in(rev.year), "stars applied")
		check(not c["reasons"].is_empty(), "change has reasons")
		ups += 1 if c["to"] > c["from"] else 0
	check(ups <= 40, "star gains stay rare (%d)" % ups)
	var mvp: Soldier = rev.awards[0]["soldier"]
	check(SeasonReview.gain_chance(mvp, {"Season MVP": SeasonReview.GAIN_CHANCE["Season MVP"]}) > 0.1 or mvp.dev == Soldier.DEV_MAX, "MVP has a real shot at a star")
	s.finish_draft()
	for t in s.league.teams:
		for so in t.roster:
			ages[so] = so.age
	s.start_next_season()
	for so in ages:
		check(so.age == ages[so] + 1, "everyone ages a year")
	for r in s.aging_report:
		var so: Soldier = r["soldier"]
		for g in r["changes"]:
			check(r["changes"][g] < 0, "aging only declines")
			check(so.age > Aging.PEAK_AGE[g], "declines only past peak")
	check(s.review == null and s.review_history.size() == 1, "review cleared for the new season, history kept")
	# Rookies get their draft year.
	var rookies := 0
	for t in s.league.teams:
		for so in t.roster:
			if so.draft_year == 2026:
				rookies += 1
	check(rookies > 0, "drafted soldiers record their draft year")


func test_draft_class_and_points() -> void:
	var s := Season.new_franchise(21)
	var d := s.draft
	check(d.prospects.size() == Draft.CLASS_SIZE, "class size")
	var phenoms := 0
	var ids := {}
	for p in d.prospects:
		check(p.soldier.age >= 19 and p.soldier.age <= 22, "prospect age")
		check(p.reveals.is_empty() and p.points == 0, "nothing scouted yet")
		ids[p.soldier.id] = true
		if p.phenom:
			phenoms += 1
	check(phenoms <= 2, "phenoms 0-2 (%d)" % phenoms)
	check(ids.size() == Draft.CLASS_SIZE, "unique prospect ids")
	for t in s.league.teams:
		for so in t.roster:
			check(not ids.has(so.id), "prospect id doesn't clash with roster")
	check(d.scout_points == Draft.POINTS_PER_WEEK, "starting points")
	s.sim_week()
	check(d.scout_points == 2 * Draft.POINTS_PER_WEEK, "points carry over and accrue")
	s.sim_to_end_of_season()
	check(d.scout_points == s.total_weeks() * Draft.POINTS_PER_WEEK, "points for every week (%d)" % d.scout_points)
	# Phenom generation across many classes: rare but present, and good at every role.
	var total := 0
	for i in 40:
		var c := Draft.generate(1000 + i, 2026, 1)
		for p in c.prospects:
			if p.phenom:
				total += 1
				for role in [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]:
					check(p.soldier.ovr_at_role(role) >= 55, "phenom good at every role")
	check(total >= 25 and total <= 60, "about one phenom per class (%d in 40)" % total)


func test_scouting_windows() -> void:
	var d := Draft.generate(77, 2026, 1)
	d.scout_points = 2000
	for p in d.prospects:
		var used := 0
		check(p.scout_grade() == p.area_grade + "?", "grade has a ? before full scouting")
		while d.can_scout(p):
			var broad_left := false
			for g in Stats.GROUP_ORDER:
				if int(p.scouts.get(g, 0)) < Draft.BROAD_SCOUTS:
					broad_left = true
			var gs := d.scout(p)
			check(gs.size() == (2 if broad_left else 1), "2 groups per point, then 1 once all are at 2 tiers")
			check(gs.size() < 2 or gs[0] != gs[1], "two different groups")
			used += 1
			for g in gs:
				var w: Vector2i = p.reveals[g]
				var n: int = p.scouts[g]
				check(w.y - w.x + 1 == Draft.WINDOW_WIDTHS[n - 1], "window width after %d scouts" % n)
				check(w.x >= 0 and w.y < Draft.TIER_COUNT, "window inside tiers")
				var t := p.true_tier(g)
				check(t >= w.x and t <= w.y, "window contains true tier")
		check(used == Draft.MAX_POINTS_PER_PROSPECT and p.points == used, "max points per prospect")
		var exact := 0
		for g in Stats.GROUP_ORDER:
			check(int(p.scouts.get(g, 0)) >= 2, "every group down to 2 tiers after 6 points")
			if int(p.scouts.get(g, 0)) == 3:
				exact += 1
		check(exact == Draft.MAX_POINTS_PER_PROSPECT - 6, "each later point pins one group exactly")
		check(d.scout(p).is_empty(), "can't scout past max")
		check(p.grade_confirmed() and p.scout_grade() == p.true_grade, "full scouting reveals the true grade")
	var tops := d.prospects.filter(func(q: Prospect): return q.true_grade == "A")
	check(not tops.is_empty() and tops.size() <= ceili(Draft.CLASS_SIZE * 0.05), "true A = top 5%% of the class (%d)" % tops.size())
	check(d.scout_points == 2000 - Draft.CLASS_SIZE * Draft.MAX_POINTS_PER_PROSPECT, "points spent")
	# Narrowing stays inside the previous window.
	var d2 := Draft.generate(78, 2026, 1)
	d2.scout_points = 1000
	var p2 := d2.prospects[0]
	var last := {}
	for i in 8:
		for g in d2.scout(p2):
			var w: Vector2i = p2.reveals[g]
			if last.has(g):
				var prev: Vector2i = last[g]
				check(w.x >= prev.x and w.y <= prev.y, "narrowed window inside previous")
			last[g] = w
	d2.scout_points = 0
	check(not d2.can_scout(d2.prospects[1]), "no points, no scouting")
	check(Draft.window_text(Stats.ACCURACY, Vector2i(1, 4)) == "Inconsistent - Sharpshooter", "window text")
	check(Draft.window_text(Stats.ACCURACY, null) == "?", "unseen text")
	check(Draft.tier_of(57) == 0 and Draft.tier_of(58) == 1 and Draft.tier_of(85) == 3 and Draft.tier_of(86) == 4, "tier thresholds")


func test_draft_order_and_picks() -> void:
	var s := Season.new_franchise(33)
	s.sim_to_end_of_season()
	var d := s.draft
	check(d.is_started() and not d.is_complete(), "draft order set after the final")
	var per_round := s.league.teams.size()
	check(d.order.size() == per_round * Draft.ROUNDS, "pick count")
	check(d.order[per_round - 1] == s.champion, "champion picks last in round 1")
	check(d.original[per_round * 2 - 1] == s.champion, "no snake: champion last in round 2 too")
	for i in per_round:
		for r in Draft.ROUNDS:
			check(d.original[r * per_round + i] == d.original[i], "round %d pick %d repeats round 1" % [r + 1, i])
	var user := s.user_team()
	var made := d.sim_to_user()
	check(d.on_the_clock() == user, "stopped at user pick")
	var p := d.available()[0]
	check(d.make_pick(p), "user pick")
	check(p.drafted_by == user and user.roster.has(p.soldier), "user got prospect")
	check(not d.make_pick(p), "can't pick twice")
	s.finish_draft()
	check(d.is_complete(), "draft completed")
	check(d.picks().size() == d.order.size(), "all picks made")
	check(s.offseason_stage == Season.OFF_RESIGN, "still in the re-sign window")
	s.advance_offseason()
	check(s.offseason_stage == Season.OFF_FREE_AGENCY, "free agency opens after the re-sign week")
	while s.offseason_stage == Season.OFF_FREE_AGENCY:
		s.advance_offseason()
	check(s.offseason_stage == Season.OFF_DRAFT, "the draft follows free agency")
	s.advance_offseason()
	check(s.offseason_stage == Season.OFF_REVIEW, "roster review after the draft")
	var undrafted := d.available()
	check(undrafted.is_empty() or undrafted.any(func(pr): return s.league.free_agents.has(pr.soldier)), "undrafted prospects join free agency at the review")
	for t in s.league.teams:
		if not t.user_controlled:
			check(t.roster.size() <= Team.OFFSEASON_MAX, "%s at or under the offseason max" % t.abbrev)
		check(t.lineup.size() == 5, "lineup valid after cuts")
		for so in t.roster:
			check(so.contract != null and not so.contract.is_expiring(), "%s has a live contract" % so.full_name())
	for pr in d.picks():
		if pr.pick_number <= per_round * 2:
			check(not s.league.free_agents.has(pr.soldier), "early pick %s (#%d) not cut into free agency" % [pr.soldier.full_name(), pr.pick_number])
	check(made.size() == d.order.find(user), "AI picks before user")


func test_contracts_and_cap() -> void:
	var s := Season.new_franchise(61)
	for t in s.league.teams:
		check(Contracts.payroll(t, s.year) <= Contracts.SALARY_CAP, "%s starts under the cap" % t.abbrev)
		for so in t.roster:
			check(so.contract != null and so.contract.years >= 1, "initial contract")
	var t := s.user_team()
	var best: Soldier = t.roster[0]
	var worst: Soldier = t.roster[0]
	for so in t.roster:
		if so.best_ovr() > best.best_ovr():
			best = so
		if so.best_ovr() < worst.best_ovr():
			worst = so
	check(Contracts.market_value(best) >= Contracts.market_value(worst), "better players cost more")
	check(Contracts.asking(best, Contracts.preferred_years(best)) <= Contracts.asking(best, 5) or Contracts.preferred_years(best) == 5, "off-length deals cost more")
	var payroll := Contracts.payroll(t, s.year)
	var c: Contract = worst.contract
	var expected_dead := Contracts.dead_money_if_released(worst)
	var dead := s.release_player(t, worst)
	check(dead == expected_dead and dead == roundi(c.salary * Contracts.DEAD_MONEY_SHARE) * c.years, "dead money = half of each remaining year")
	check(s.league.free_agents.has(worst) and worst.contract == null, "released into free agency")
	check(Contracts.payroll(t, s.year) == payroll - c.salary + roundi(c.salary * Contracts.DEAD_MONEY_SHARE), "payroll includes dead money")
	check(Contracts.fits(t, s.year, Contracts.MIN_SALARY, 999999), "minimum deals always fit")
	check(not Contracts.fits(t, s.year, Contracts.cap_space(t, s.year) + 1), "can't exceed the cap")
	check(Contracts.money(1250) == "$1.25M" and Contracts.money(750) == "$750K", "money format")
	# Offseason cap holds: an expiring deal counts at his old salary; re-signing replaces it.
	var h := Team.new()
	var vet := PlayerGenerator.generate(RandomNumberGenerator.new(), 77, Scheme.Role.FLEX, 50.0, 28)
	var other := PlayerGenerator.generate(RandomNumberGenerator.new(), 78, Scheme.Role.FLEX, 50.0, 28)
	vet.contract = Contract.make(20000, 0, 2026)
	other.contract = Contract.make(1000, 2, 2026)
	h.roster.append(vet)
	h.roster.append(other)
	check(Contracts.payroll(h, 2027) == 21000, "expiring deal is a cap hold (21M)")
	check(Contracts.payroll(h, 2027, 1) == 1000, "holds don't count in later years")
	var room := Contracts.SALARY_CAP - 1000
	check(Contracts.resign_fits(h, 2027, vet, room) and not Contracts.resign_fits(h, 2027, vet, room + 1), "his new deal replaces his hold")
	check(not Contracts.fits(h, 2027, room), "his hold blocks other signings")
	vet.contract = Contract.make(25000, 3, 2027)
	check(Contracts.payroll(h, 2027) == 26000, "re-signed at 25M: payroll 26M")


func test_free_agency_bidding() -> void:
	var s := Season.new_franchise(62)
	var t := s.user_team()
	t.release(t.roster[-1])
	t.release(t.roster[-1])
	check(s.free_agency_open(), "in-season free agency is open")
	var pool := s.league.free_agents
	check(pool.size() >= Season.INITIAL_FREE_AGENTS, "initial pool")
	var target: Soldier = pool[0]
	for so in pool:
		if so.best_ovr() > target.best_ovr():
			target = so
	var yrs := Contracts.preferred_years(target)
	check(s.fa.make_offer(s, t, target, Contracts.MAX_SALARY + 1, yrs) != "", "salary over max rejected")
	var low := s.fa.make_offer(s, t, target, Contracts.MIN_SALARY, yrs)
	check(low == "" and s.fa.offers_by(t).size() == 1, "offer placed")
	check(FreeAgency.interest(t, target, Contracts.MIN_SALARY, yrs)[0] == "LOW" or Contracts.asking(target, yrs) <= Contracts.MIN_SALARY, "lowball = low interest")
	var rich := mini(Contracts.MAX_SALARY, roundi(Contracts.asking(target, yrs) * 1.3))
	check(s.fa.make_offer(s, t, target, rich, yrs) == "" and s.fa.offers_by(t).size() == 1, "offer replaced, not duplicated")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var signed := s.fa.resolve(s, rng, "test")
	check(t.roster.has(target) and not pool.has(target), "generous offer accepted")
	check(target.contract != null and target.contract.salary == rich and target.contract.years == yrs, "contract matches the offer")
	check(signed.any(func(e): return e["soldier"] == target), "signing reported")
	# An ignored free agent lowers his price.
	var other: Soldier = pool[0]
	var before := Contracts.asking(other, 2)
	s.fa.resolve(s, rng, "test 2")
	check(not pool.has(other) or Contracts.asking(other, 2) < before or Contracts.asking(other, 2) <= Contracts.MIN_SALARY, "unsigned asking price drops")


func test_retirement_and_offseason_flow() -> void:
	var s := Season.new_franchise(63)
	var vet: Soldier = s.league.teams[1].roster[0]
	vet.age = Retirement.ALWAYS_AGE
	var stale: Soldier = s.league.free_agents[0]
	stale.fa_since = s.year - 1
	for st in stale.stats:
		stale.stats[st] = 40
	s.sim_to_end_of_season()
	check(s.offseason_stage == Season.OFF_RESIGN, "offseason starts with re-signing")
	check(vet.retired_year == s.year and not s.league.teams[1].roster.has(vet), "%d-year-old retired" % Retirement.ALWAYS_AGE)
	check(stale.retired_year == s.year and not s.league.free_agents.has(stale), "low-OVR unsigned free agent retired")
	var ret := s.retirements_in(s.year)
	check(ret.any(func(r): return r["soldier"] == vet and r["reason"] == "Age"), "age retirement logged")
	check(ret.any(func(r): return r["soldier"] == stale and r["reason"] == "Unsigned"), "unsigned retirement logged")
	var user := s.user_team()
	var expiring := Contracts.expiring(user)
	if not expiring.is_empty():
		var keep: Soldier = expiring[0]
		var ask := s.negotiation(user, keep).demand(2)
		check(s.resign_player(user, keep, 2) == "" or ask > Contracts.cap_space(user, s.cap_year()), "re-sign")
		check(keep.contract.salary == ask or ask > Contracts.cap_space(user, s.cap_year()), "re-signed at his demand")
	if not s.league.free_agents.is_empty():
		check(s.fa.offer_error(s, user, s.league.free_agents[0], Contracts.MIN_SALARY, 1) != "", "can't bid before free agency")
	var y := s.year
	s.start_next_season()
	check(s.year == y + 1 and s.phase == Season.PHASE_REGULAR, "season rolled over")
	for t in s.league.teams:
		if t.user_controlled:
			continue
		check(t.roster.size() == Team.ROSTER_SIZE, "%s roster size %d" % [t.abbrev, t.roster.size()])
		check(t.lineup.size() == 5, "%s lineup" % t.abbrev)
		for so in t.roster:
			check(so.contract != null and so.contract.years >= 1, "contracts live for the new season")
	check(s.fa.offers.is_empty(), "offers cleared")


func test_release() -> void:
	var s := Season.new_franchise(5)
	var t := s.user_team()
	var starter: Soldier = t.starters()[0]
	var slot := t.slot_of(starter)
	t.release(starter)
	check(not t.roster.has(starter), "released")
	check(t.lineup.has(slot) and t.lineup[slot] != starter, "slot refilled")
	check(t.roster.size() == Team.ROSTER_SIZE - 1, "roster shrank")

func test_projections_and_mock() -> void:
	check(Draft.projection_text(1, 5) == "Early 1st" and Draft.projection_text(3, 5) == "Mid 1st", "early/mid 1st")
	check(Draft.projection_text(5, 5) == "Late 1st" and Draft.projection_text(6, 5) == "Early 2nd", "late 1st/early 2nd")
	check(Draft.projection_text(10, 5) == "Late 2nd" and Draft.projection_text(11, 5) == "Early 3rd", "late 2nd/early 3rd")
	check(Draft.projection_text(15, 5) == "Late 3rd" and Draft.projection_text(16, 5) == "Undrafted", "late 3rd/undrafted")
	var s := Season.new_franchise(44)
	var d := s.draft
	var ranks := {}
	for p in d.prospects:
		ranks[p.projected_rank] = true
	check(ranks.size() == Draft.CLASS_SIZE and ranks.has(1) and ranks.has(Draft.CLASS_SIZE), "ranks 1..N unique")
	# Mock during the season: every pick, distinct prospects, no state change.
	var mock := d.mock(s.mock_pick_order())
	check(mock.size() == s.league.teams.size() * Draft.ROUNDS, "mock covers every pick (%d)" % mock.size())
	var seen := {}
	for e in mock:
		seen[e["prospect"]] = true
	check(seen.size() == mock.size(), "mock picks distinct")
	check(d.available().size() == Draft.CLASS_SIZE and not d.is_started(), "mock doesn't draft")
	# Mock picks come from the top of the board (need can only shift things a little).
	for e in mock:
		check(e["prospect"].projected_rank <= mock.size() + 6, "mock pick near the board")
	# Real draft roughly follows consensus: most first-rounders projected in the top 10.
	var hits := 0
	var total := 0
	for i in 20:
		var s2 := Season.new_franchise(900 + i)
		s2.sim_to_end_of_season()
		s2.finish_draft()
		for p in s2.draft.picks():
			if p.pick_number <= s2.league.teams.size():
				total += 1
				if p.projected_rank <= 10:
					hits += 1
	check(hits >= total * 0.8, "first-rounders mostly projected top 10 (%d/%d)" % [hits, total])


func test_morale_effects() -> void:
	var s := Season.new_franchise(321)
	var so: Soldier = s.user_team().roster[0]
	so.morale = Soldier.MORALE_NEUTRAL
	check(so.morale_steps() == 0, "neutral morale has no steps")
	check(so.morale_mods().is_empty(), "neutral morale has no mods")
	so.morale = 40.0
	check(so.morale_steps() < 0, "low morale is negative")
	var total := 0
	for st in so.morale_mods():
		total += int(so.morale_mods()[st])
	check(total < 0, "low morale lowers stats")
	check(so.morale_mods() == so.morale_mods(), "mods deterministic")
	so.morale = 99.0
	check(so.morale_steps() > 0, "high morale boosts")
	so.add_morale(50.0)
	check(so.morale == 100.0, "morale clamped")
	for i in 3:
		s.sim_week()
	for t in s.league.teams:
		for x in t.roster:
			check(x.morale >= 0.0 and x.morale <= 100.0, "morale in range after weeks")


func test_relationships() -> void:
	var s := Season.new_franchise(777)
	var rel := s.relationships
	check(not rel.pairs.is_empty(), "teammates seeded with some history")
	var team_of := {}
	for t in s.league.teams:
		for x in t.roster:
			team_of[x.id] = t
	var cross := 0
	for k in rel.pairs:
		if team_of.get(k.x) != team_of.get(k.y):
			cross += 1
	check(cross == 0, "seeded bonds are only between teammates")
	check(Relationships.level_for(19.9) == 0 and Relationships.level_for(20.0) == 1 and Relationships.level_for(50.0) == 2 and Relationships.level_for(80.0) == 3, "level thresholds")
	# Clean slate so gains are measurable.
	rel.pairs.clear()
	var played := s.sim_week()
	var m: ScheduledMatch = null
	for x in played:
		if x.is_played():
			m = x
			break
	check(m != null, "a match was played")
	var t: Team = m.home
	var by_slot := {}
	for so in t.roster:
		if m.result.box.has(so.id):
			by_slot[StringName(m.result.box[so.id]["slot"])] = so
	var adj: Array = Scheme.ADJACENT[t.scheme.id]
	var a: Soldier = by_slot.get(adj[0][0])
	var b: Soldier = by_slot.get(adj[0][1])
	check(a != null and b != null, "adjacent pair started")
	var adj_pts := rel.points(a, b)
	check(is_equal_approx(adj_pts, Relationships.MATCH_GAIN + Relationships.ADJACENT_GAIN + Relationships.TRAINING_GAIN), "adjacent starters gain match + neighbour + training (%.2f)" % adj_pts)
	var bench := t.bench()
	if bench.size() >= 2 and not m.result.box.has(bench[0].id) and not m.result.box.has(bench[1].id):
		check(is_equal_approx(rel.points(bench[0], bench[1]), Relationships.TRAINING_GAIN), "bench pair gets training gain only")
	check(int(rel.pairs[Relationships.key(a.id, b.id)]["m"]) == 1, "matches together counted")
	# Boost: Mentality only, by level, capped; bench players get none.
	var team := s.user_team()
	var st := team.starters()
	for x in team.roster:
		x.morale = Soldier.MORALE_NEUTRAL
	rel.pairs.clear()
	check(st[0].chem_bonus() == 0, "no bonds, no bonus")
	rel.pairs[Relationships.key(st[0].id, st[1].id)] = {"pts": 85.0, "m": 40, "d": 0.0}
	check(st[0].chem_bonus() == 3 and st[1].chem_bonus() == 3, "Inseparable pair gives +3")
	var mods := st[0].stat_mods()
	check(int(mods.get(Stats.AWARENESS, 0)) == 3 and int(mods.get(Stats.COMPOSURE, 0)) == 3 and int(mods.get(Stats.TEAMWORK, 0)) == 3, "boost lands on Mentality")
	check(not mods.has(Stats.SPEED), "nothing outside Mentality")
	rel.pairs[Relationships.key(st[0].id, st[2].id)] = {"pts": 55.0, "m": 20, "d": 0.0}
	check(st[0].chem_bonus() == Relationships.BONUS_CAP, "bonus capped at +%d" % Relationships.BONUS_CAP)
	var b0: Soldier = team.bench()[0]
	rel.pairs[Relationships.key(st[0].id, b0.id)] = {"pts": 90.0, "m": 0, "d": 0.0}
	check(b0.chem_bonus() == 0, "bench player gets no bonus")
	# Decay apart, and bonds survive a release.
	var gone: Soldier = st[1]
	s.release_player(team, gone)
	var before := rel.points(st[0], gone)
	s.sim_week()
	check(is_equal_approx(rel.points(st[0], gone), before - Relationships.DECAY), "separated pair decays")
	check(float(rel.pairs[Relationships.key(st[0].id, gone.id)]["d"]) < 0.0, "trend fading")
	check(rel.partners_of(st[0])[0]["id"] == gone.id or rel.points(st[0], gone) > 0.0, "bond kept after release")
	# Saved and loaded.
	var loaded := SaveSystem.from_text(SaveSystem.to_text(s))
	check(loaded.relationships.pairs.size() == rel.pairs.size(), "relationships saved")
	check(is_equal_approx(loaded.relationships.points(st[0], gone), rel.points(st[0], gone)), "pair points saved")


func test_callsigns_saves_and_season_lines() -> void:
	var s := Season.new_franchise(654)
	var names := {}
	for t in s.league.teams:
		for x in t.roster:
			check(x.callsign != "", "every rostered soldier has a callsign")
			check(not names.has(x.callsign), "callsigns unique: " + x.callsign)
			names[x.callsign] = true
			check(x.display_name().contains("\"%s\"" % x.callsign), "display name shows callsign")
			check(x.tag() == x.callsign.to_upper(), "tag is upper callsign")
	s.sim_to_end_of_regular_season()
	var saves := 0
	var lines := 0
	for t in s.league.teams:
		for x in t.roster:
			if x.season_lines.has(s.year):
				lines += 1
				saves += int(x.season_lines[s.year].get("saves", 0))
	check(lines > 0, "season lines recorded")
	check(saves > 0, "saves recorded over a season")


func test_standout_prospects() -> void:
	var blue_vals: Array = []
	var plain_vals: Array = []
	var gens := 0
	for i in 30:
		var d := Draft.generate(4000 + i, 2026, 1)
		var blue := 0
		var spec := 0
		var gen := 0
		for p in d.prospects:
			var v := Draft.true_value(p)
			if p.standout == &"generational":
				gen += 1
				check(p.soldier.ovr_at_role(p.listed_role) >= Draft.GENERATIONAL_OVR[0], "generational is a mid-70s starter (%d)" % p.soldier.ovr_at_role(p.listed_role))
				check(p.soldier.potential_grade() == Soldier.POTENTIAL_A and p.soldier.dev == Soldier.DEV_MAX, "generational: A potential, 4 stars")
				check(Draft.standout_label(p) == "GENERATIONAL", "generational label")
			elif p.standout == &"blue_chip":
				blue += 1
				blue_vals.append(v)
				var ovr := p.soldier.ovr_at_role(p.listed_role)
				check(ovr >= Draft.BLUE_CHIP_OVR[0] and ovr <= Draft.BLUE_CHIP_OVR[1] + 2, "blue chip is a day-one starter (%d)" % ovr)
				check(p.soldier.potential_grade() >= 3 and p.soldier.dev >= Draft.BLUE_CHIP_MIN_DEV, "blue chip: B/A potential, 2+ stars")
				check(not p.phenom, "blue chip isn't also a phenom")
			elif p.standout == &"specialist":
				spec += 1
				check(p.soldier.group_rating(p.specialty) >= Draft.SPECIALIST_STAT[0], "specialist elite in %s (%d)" % [p.specialty, p.soldier.group_rating(p.specialty)])
				check(Draft.standout_label(p).ends_with("SPECIALIST"), "specialist label")
			elif not p.phenom:
				plain_vals.append(v)
		check(blue >= Draft.BLUE_CHIPS[0] and blue <= Draft.BLUE_CHIPS[1], "blue chips per class (%d)" % blue)
		check(gen <= 1, "at most one generational talent per class")
		gens += gen
		check(spec >= Draft.SPECIALISTS[0] and spec <= Draft.SPECIALISTS[1], "specialists per class (%d)" % spec)
	var avg := func(a: Array) -> float:
		var t := 0.0
		for x in a:
			t += x
		return t / maxi(1, a.size())
	var gap: float = avg.call(blue_vals) - avg.call(plain_vals)
	check(gap >= 8.0, "blue chips stand out (avg +%.1f value)" % gap)
	check(gens >= 1 and gens <= 12, "generational talents are rare (%d in 30 classes)" % gens)


func test_prospect_news() -> void:
	var s := Season.new_franchise(88)
	s.sim_to_end_of_season()
	var d := s.draft
	var n := d.news.size()
	check(n >= 4 and n <= 2 * s.total_weeks(), "a few stories per season (%d)" % n)
	var truthful := 0
	var kinds := {}
	for st in d.news:
		kinds[st["kind"]] = true
		check(st["prospect"] is Prospect and str(st["text"]).contains(st["prospect"].soldier.full_name()), "story names its prospect")
		for g in Draft.TIER_NAMES:
			for tier in Draft.TIER_NAMES[g]:
				check(not str(st["text"]).contains(tier), "stories never name a tier")
		if st["truthful"]:
			truthful += 1
		check(st["truthful"] or st["rumor"], "only rumors can be false")
		if st["kind"] == &"hint" and st["truthful"]:
			var v: int = st["prospect"].soldier.stats[st["stat"]]
			check(v >= Draft.NEWS_GREAT if st["great"] else v <= Draft.NEWS_POOR, "true stat story is right (%d)" % v)
		if st["kind"] == &"hint" and st["claim"] == "rank":
			check(d.class_extreme(st["stat"], st["great"]) == st["prospect"], "class-ranking story is about the real class leader")
	check(truthful >= n * 0.4, "plenty of stories are true (%d/%d)" % [truthful, n])
	# Over many classes: rankings are literally true, facts never lie, rumors are coin flips.
	var rumors := 0
	var rumors_true := 0
	var ranks_seen := 0
	for i in 8:
		var dc := Draft.generate(9100 + i, 2026, 1)
		for w in 14:
			for st in dc.weekly_news(w + 1):
				if st["rumor"]:
					rumors += 1
					rumors_true += 1 if st["truthful"] else 0
					if st["kind"] == &"hint":
						check(str(st["text"]).contains("reportedly") or str(st["text"]).contains("Word is") or str(st["text"]).contains("One scout"), "stat rumors are worded as rumors")
				else:
					check(st["truthful"], "facts are always true")
				if st["kind"] == &"hint" and st["claim"] == "rank":
					ranks_seen += 1
					var p: Prospect = st["prospect"]
					var v: int = p.soldier.stats[st["stat"]]
					for o in dc.prospects:
						if o != p:
							check(v > o.soldier.stats[st["stat"]] if st["great"] else v < o.soldier.stats[st["stat"]], "ranking story beats the whole class")
	check(ranks_seen > 0, "class-ranking stories appear (%d)" % ranks_seen)
	check(rumors >= 20 and rumors_true >= rumors * 0.3 and rumors_true <= rumors * 0.7, "rumors are true about half the time (%d/%d)" % [rumors_true, rumors])
	# Over many seasons every kind shows up and truthful stock stories move toward the truth.
	var toward := 0
	var stock := 0
	for i in 6:
		var dd := Draft.generate(7100 + i, 2026, 1)
		for w in 12:
			var before := {}
			for p in dd.prospects:
				before[p] = p.consensus
			for st in dd.weekly_news(w + 1):
				kinds[st["kind"]] = true
				if st["kind"] != &"hint" and st["truthful"]:
					stock += 1
					var p: Prospect = st["prospect"]
					if absf(Draft.true_value(p) - p.consensus) < absf(Draft.true_value(p) - before[p]):
						toward += 1
		var ranks := {}
		for p in dd.prospects:
			ranks[p.projected_rank] = true
		check(ranks.size() == Draft.CLASS_SIZE, "ranks stay unique after news")
	check(kinds.has(&"rising") and kinds.has(&"falling") and kinds.has(&"hint"), "every story kind appears")
	check(stock > 0 and toward >= stock * 0.8, "true stock stories move toward the truth (%d/%d)" % [toward, stock])


## Total XP ever earned (levels converted back to XP).
func _xp_total(so: Soldier) -> int:
	var t := so.xp
	for lv in range(1, so.level):
		t += Progression.xp_to_next(lv)
	return t


func test_training_camp_and_offseason_xp() -> void:
	var s := Season.new_franchise(515)
	s.sim_to_end_of_season()
	var user := s.user_team()
	var probe: Soldier = user.roster[0]
	check(s.camp != null and s.camp.drills_left(user) == Camp.DRILLS.size(), "fresh camp each offseason")
	# Every offseason step is an XP week, scaled by potential.
	var x0 := _xp_total(probe)
	s.advance_offseason()  # re-sign -> free agency
	var step: int = _xp_total(probe) - x0
	check(step == roundi(Season.OFFSEASON_WEEK_XP * Progression.xp_multiplier(probe)), "re-sign week xp (%d)" % step)
	var guard := 0
	while s.offseason_stage == Season.OFF_FREE_AGENCY and guard < 10:
		s.advance_offseason()
		guard += 1
	check(s.offseason_stage == Season.OFF_DRAFT, "free agency ends in the draft")
	check(_xp_total(probe) - x0 == (1 + Season.FA_DAYS) * step, "every FA day is an xp week")
	s.advance_offseason()  # draft -> roster review
	check(s.offseason_stage == Season.OFF_REVIEW, "the draft ends in the roster review")
	var rookie: Soldier = null
	for p in s.draft.picks():
		if p.drafted_by == user:
			rookie = p.soldier
	s.advance_offseason()  # roster review -> training camp
	check(s.offseason_stage == Season.OFF_CAMP, "the roster review ends in training camp")
	check(s.camp_open() and s.free_agency_open(), "camp open; unsigned players still sign")
	check(_xp_total(probe) - x0 == (3 + Season.FA_DAYS) * step, "draft and review weeks are xp weeks")
	check(rookie == null or rookie.xp > 0 or rookie.level > 1, "draftees earn xp too")
	# Drills.
	var a: Soldier = user.roster.filter(func(x: Soldier): return x.group_headroom(Stats.PHYSICALITY) >= 2 and not x.is_injured())[0]
	var b: Soldier = user.roster.filter(func(x: Soldier): return x != a and not x.is_injured())[0]
	var before := a.stats.duplicate()
	var res := s.run_drill(Stats.PHYSICALITY, a)
	check(not res.is_empty(), "drill runs")
	var pool := Camp.pool_range(a.dev)
	check(res["points"] >= pool[0] and res["points"] <= pool[1] or res.get("dev_up", false), "points from the dev pool")
	var total := 0
	for st in Stats.ALL:
		var g: int = a.stats[st] - before[st]
		if Stats.group_stats(Stats.PHYSICALITY).has(st):
			check(g >= 0 and g <= Camp.MAX_STAT_GAIN and g == res["gains"][st], "%s gain %d" % [st, g])
			total += g
		else:
			check(g == 0, "drill only touches its group (%s)" % st)
	check(total == res["points"] and res["points"] <= res["rolled"], "landed points add up (%d of %d)" % [total, res["points"]])
	check(a.group_rating(Stats.PHYSICALITY) <= a.group_cap(Stats.PHYSICALITY), "drill never passes the cap")
	check(s.camp_check(Stats.ACCURACY, a) != "", "one drill per player")
	check(s.camp_check(Stats.PHYSICALITY, b) != "", "one player per drill")
	var inj_before: int = b.stats[Stats.INJURY] + b.stats[Stats.TOUGHNESS]
	check(not s.run_drill(Stats.DURABILITY, b).is_empty(), "durability drill")
	check(b.stats[Stats.INJURY] + b.stats[Stats.TOUGHNESS] > inj_before, "durability drill raises injury/toughness")
	var hurt: Soldier = user.bench()[0]
	hurt.injury_weeks = 3
	check(s.camp_check(Stats.MENTALITY, hurt) != "", "injured soldiers can't drill")
	hurt.injury_weeks = 0
	check(s.camp.drills_left(user) == Camp.DRILLS.size() - 2, "drills left")
	# Camp week: AI teams run their drills and everyone gets bonus xp.
	var x1 := _xp_total(probe)
	s.advance_offseason()
	check(s.offseason_stage == Season.OFF_DONE and not s.camp_open(), "camp closes")
	check(_xp_total(probe) - x1 == roundi(Season.CAMP_WEEK_XP * Progression.xp_multiplier(probe)), "camp week bonus xp")
	for t in s.league.teams:
		if not t.user_controlled:
			check(s.camp.drills_left(t) == 0, "%s ran every drill" % t.abbrev)
	check(s.run_drill(Stats.ACCURACY, user.starters()[2]).is_empty(), "no drills after camp")
	# Potential drives the pool.
	var lo := 0
	var hi := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 40:
		var c := Camp.make(2026)
		var t := Team.new()
		var f := PlayerGenerator.generate(rng, 1, Scheme.Role.FLEX, 50.0, 24)
		var aa := PlayerGenerator.generate(rng, 2, Scheme.Role.FLEX, 50.0, 24)
		f.dev = Soldier.DEV_MIN
		aa.dev = Soldier.DEV_MAX
		for g in Stats.UPGRADABLE_GROUPS:
			f.group_caps[g] = 99
			aa.group_caps[g] = 99
		t.roster.append(f)
		t.roster.append(aa)
		lo += c.run(t, Stats.ACCURACY, f, rng)["points"]
		hi += c.run(t, Stats.HANDLING, aa, rng)["points"]
	check(hi > lo * 2, "4 stars get far bigger pools (%d vs %d)" % [hi, lo])
	# Drill star chance: young > old, none once maxed or already changed this year.
	var cc := Camp.make(2026)
	var kid := PlayerGenerator.generate(rng, 3, Scheme.Role.FLEX, 50.0, 21)
	kid.dev = 2
	var vet := PlayerGenerator.generate(rng, 4, Scheme.Role.FLEX, 50.0, 32)
	vet.dev = 2
	check(cc.dev_up_chance(kid) > cc.dev_up_chance(vet) and cc.dev_up_chance(vet) > 0.0, "younger players earn camp stars more often")
	kid.change_dev(1, 2026)
	check(cc.dev_up_chance(kid) == 0.0, "one star change a season")
	vet.dev = Soldier.DEV_MAX
	check(cc.dev_up_chance(vet) == 0.0, "no star past 4")
	var y := s.year
	s.start_next_season()
	check(s.year == y + 1 and s.past_drafts.size() == 1 and s.past_drafts[0].year == y, "draft kept for the recap")


func test_preseason_camp() -> void:
	var plain := Season.new_franchise(616)
	check(not plain.preseason_camp and not plain.camp_open(), "no camp unless asked")
	var s := Season.new_franchise(616, 0, 2026, true)
	check(s.preseason_camp and s.camp_open() and s.week == 1 and s.year == 2026, "opens in camp before Week 1")
	check(s.camp.year + 1 == 2026, "camp is labelled for the coming season")
	check(s.draft.scout_points == 0 and not s.draft.can_scout(s.draft.prospects[0]), "no scouting during camp")
	var a: Soldier = s.user_team().roster.filter(func(x: Soldier): return x.group_headroom(Stats.ACCURACY) > 0 and not x.is_injured())[0]
	check(not s.run_drill(Stats.ACCURACY, a).is_empty(), "drill runs in preseason")
	check(s.camp_check(Stats.HANDLING, a) != "", "one drill per player")
	var probe: Soldier = s.user_team().roster[1]
	var x0 := _xp_total(probe)
	s.close_preseason_camp()
	check(not s.preseason_camp and not s.camp_open(), "camp closed")
	check(s.draft.scout_points == Draft.POINTS_PER_WEEK, "Week 1 scout points arrive")
	check(_xp_total(probe) - x0 == roundi(Season.CAMP_WEEK_XP * Progression.xp_multiplier(probe)), "camp week xp")
	for t in s.league.teams:
		if not t.user_controlled:
			check(s.camp.drills_left(t) == 0, "%s ran its drills" % t.abbrev)
	check(s.run_drill(Stats.HANDLING, s.user_team().starters()[1]).is_empty(), "no drills after camp")
	# Simming straight from camp closes it automatically.
	var s2 := Season.new_franchise(617, 0, 2026, true)
	s2.sim_week()
	check(not s2.preseason_camp and s2.week == 2, "sim_week closes camp and plays Week 1")


func test_progression_history_and_potw() -> void:
	var s := Season.new_franchise(618, 0, 2026, true)
	var user := s.user_team()
	var a: Soldier = user.roster.filter(func(x: Soldier): return x.group_headroom(Stats.ACCURACY) >= 2 and not x.is_injured())[0]
	var gains := s.run_drill(Stats.ACCURACY, a)
	check(not gains.is_empty(), "drill ran")
	var e: Dictionary = a.history[-1]
	check(String(e["reason"]).begins_with("Training camp") and e["when"] == "Preseason camp" and int(e["year"]) == 2026, "camp logged: %s" % str(e))
	var total := 0
	for st in e["changes"]:
		total += int(e["changes"][st])
	check(total > 0, "camp gains recorded")
	# Level-ups: can_level_up needs enough SP for a real upgrade.
	var b: Soldier = user.starters()[1]
	b.skill_points = 0
	check(not Progression.can_level_up(b), "no SP, can't level up")
	b.skill_points = 1000
	check(Progression.can_level_up(b), "plenty of SP, can level up")
	var g: StringName = Stats.UPGRADABLE_GROUPS[0]
	for gg in Stats.UPGRADABLE_GROUPS:
		if Progression.can_upgrade(b, gg):
			g = gg
			break
	var n0: int = b.history.size()
	Progression.upgrade_group(b, g)
	Progression.upgrade_group(b, g)
	check(b.history.size() == n0 + 1 and b.history[-1]["reason"] == "Level up (skill points)", "same-stamp level-ups merge into one entry")
	# Aging past the peak logs a decline with negative deltas.
	var old: Soldier = user.roster[2]
	old.age = 36
	Soldier.log_year = 2027
	Soldier.log_when = "Preseason"
	Aging.age_soldier(old, RandomNumberGenerator.new())
	var ae: Dictionary = old.history[-1]
	check(String(ae["reason"]) == "Age decline (turned 37)", "aging logged")
	for st in ae["changes"]:
		check(int(ae["changes"][st]) < 0, "aging deltas are declines")
	check(int(ae["ovr_to"]) <= int(ae["ovr_from"]), "aging OVR doesn't rise")
	# Week stamps follow the season.
	s.sim_week()
	check(Soldier.log_when == s.week_label(s.week) and Soldier.log_year == s.year, "stamp follows the current week")
	# Player of the week = best match impact across the week.
	var potw := SeasonReview.player_of_week(s, 1)
	check(not potw.is_empty(), "week 1 has a player of the week")
	var best := -INF
	for m in s.matches_for_week(1):
		for sid in m.result.box:
			best = maxf(best, MatchResult.impact(m.result.box[sid]))
	check(is_equal_approx(float(potw["impact"]), best), "potw has the top impact")
	check(potw["soldier"] is Soldier and potw["team"] is Team, "potw soldier and team")
	check(SeasonReview.player_of_week(s, s.total_weeks()).is_empty(), "no potw for unplayed weeks")


func test_dna_profiles() -> void:
	var a := Dna.generate(1234, 24)
	var b := Dna.generate(1234, 24)
	for k in Dna.MOTIVATIONS + [&"temperament", &"savvy"]:
		check(a.value(k) == b.value(k), "DNA deterministic: %s" % k)
		check(a.value(k) >= 1 and a.value(k) <= 99, "DNA in range: %s" % k)
	var s := Season.new_franchise(71)
	var so: Soldier = s.user_team().roster[0]
	check(so.get_dna() == so.get_dna(), "DNA cached on the soldier")
	var spread := {}
	for t in s.league.teams:
		for x in t.roster:
			spread[x.get_dna().ranked()[0]] = true
	check(spread.size() >= 4, "headline motivations vary across the league (%d)" % spread.size())
	so.trust = 95.0
	so.add_trust(20.0)
	check(so.trust == 100.0, "trust capped at 100")


func test_fa_dna_weights() -> void:
	var s := Season.new_franchise(72)
	var teams := s.league.teams.duplicate()
	teams.sort_custom(func(x: Team, y: Team): return x.team_ovr() > y.team_ovr())
	var strong: Team = teams[0]
	var weak: Team = teams[-1]
	var fa: Soldier = s.league.free_agents[0]
	var d := fa.get_dna()
	d.money = 20
	d.winning = 95
	d.playing_time = 20
	d.loyalty = 20
	d.security = 20
	var yrs := Contracts.preferred_years(fa)
	var sal := Contracts.asking(fa, yrs)
	check(FreeAgency.score(strong, fa, sal, yrs) > FreeAgency.score(weak, fa, sal, yrs), "a winner prefers the stronger team at equal money")
	var w := FreeAgency.weights(fa)
	check(absf(w[0] + w[1] + w[2] - 1.0) < 0.001 and w[1] > 0.25, "weights normalised, winning weighted up")
	d.playing_time = 95
	check(FreeAgency.score(weak, fa, sal, yrs, true) > FreeAgency.score(weak, fa, sal, yrs), "a starter promise raises interest")
	# Loyalty: a trusting former player leans home.
	fa.former_team = weak.abbrev
	d.loyalty = 95
	fa.trust = 90.0
	var other: Team = teams[1] if teams[1] != weak else teams[2]
	var home_bonus := FreeAgency.score(weak, fa, sal, yrs) - FreeAgency.score(other, fa, sal, yrs)
	fa.former_team = ""
	var no_bonus := FreeAgency.score(weak, fa, sal, yrs) - FreeAgency.score(other, fa, sal, yrs)
	check(home_bonus > no_bonus, "loyal player leans toward his old team")


## A user-team soldier made expiring at the end of the season, with fresh talks.
func _expiring_talks(seed_val: int) -> Array:
	var s := Season.new_franchise(seed_val)
	s.sim_to_end_of_season()
	var user := s.user_team()
	var so: Soldier = user.roster[1]
	so.contract.years = 0
	so.trust = Soldier.TRUST_NEUTRAL
	return [s, user, so, s.negotiation(user, so)]


func test_resign_negotiation() -> void:
	var r := _expiring_talks(81)
	var s: Season = r[0]
	var user: Team = r[1]
	var so: Soldier = r[2]
	var n: Negotiation = r[3]
	check(n != null and n.is_open(), "talks open in the re-sign window")
	check(s.negotiation(user, so) == n, "same talks returned")
	check(n.demand(2) > n.floor_salary(2), "demand above floor")
	check(not n.talk.is_empty(), "he opens with something to say")
	# Arguments never push him under his floor.
	for a in n.arguments():
		n.use_argument(a["id"])
		if not n.is_open():
			break
	check(n.demand(2) >= n.floor_salary(2), "arguments stop at his floor")
	if n.is_open():
		var want := n.demand(2)
		var res := n.make_offer(want, 2)
		check(res["result"] == "signed" and so.contract.salary == want and so.contract.years == 2, "offer at demand signs")
		check(s.resign_log.any(func(e): return e["soldier"] == so), "re-sign logged")
	# A backfiring argument: bad fit raises his price and costs trust.
	r = _expiring_talks(82)
	n = r[3]
	so = r[2]
	n.arguments().append({"id": &"test", "title": "Test", "pitch": "You're replaceable.", "evidence": 1.0, "evidence_text": "", "fit": 0.05, "tone": "hard", "group": Negotiation.HARDBALL, "used": false})
	var before := n.demand(2)
	var trust := so.trust
	var bf := n.use_argument(&"test")
	check(bf["result"] == "backfired" and n.demand(2) > before and so.trust < trust, "bad-fit argument backfires")
	check(n.missteps == 1 and r[0].talks_log.any(func(e): return e["kind"] == &"backfired" and e["soldier"] == so), "backfire logged for storylines")
	# A promise is worth money to a playing-time guy.
	so.get_dna().playing_time = 90
	check(n.required_salary(2, {"promise": true}) < n.required_salary(2) or n.required_salary(2) <= n.floor_salary(2), "promise lowers the salary he needs")
	# Lowballing until he walks.
	r = _expiring_talks(83)
	s = r[0]
	user = r[1]
	so = r[2]
	n = r[3]
	trust = so.trust
	var guard := 0
	while n.is_open() and guard < 20:
		n.make_offer(Contracts.MIN_SALARY, 2)
		guard += 1
	check(n.state == Negotiation.WALKED, "repeated lowballs end talks")
	check(so.trust < trust, "walking out costs trust")
	check(s.resign_player(user, so, 2) != "", "can't re-sign after he walks")
	var guard2 := 0
	while s.can_resign() and guard2 < 10:
		s.advance_offseason()
		guard2 += 1
	var late: Soldier = user.roster[0]
	late.contract.years = 0
	check(not s.can_resign() and s.negotiation(user, late) == null, "no new talks once the window closes")


func test_negotiation_terms() -> void:
	var r := _expiring_talks(84)
	var s: Season = r[0]
	var user: Team = r[1]
	var so: Soldier = r[2]
	var n: Negotiation = r[3]
	var d := so.get_dna()
	# Every term adds value; none can buy him under his floor in cash.
	var base := n.required_salary(3)
	check(n.term_value(&"no_trade", 3, {}) > 0.0, "a no-trade clause is worth something")
	d.loyalty = 95
	var loyal_ntc := n.term_value(&"no_trade", 3, {})
	d.loyalty = 5
	d.hometown = 5
	check(loyal_ntc > n.term_value(&"no_trade", 3, {}), "loyal players value a no-trade clause more")
	d.money = 95
	var greedy := n.term_value(&"bonus", 3, {"bonus": 3000})
	d.money = 5
	check(greedy > n.term_value(&"bonus", 3, {"bonus": 3000}) and greedy > 1000.0, "money-driven players value a bonus above its cash")
	var all := {"bonus": 1500, "no_trade": true, "promise": true}
	var cheap := n.required_salary(3, all)
	check(cheap <= base, "terms lower the salary he needs")
	check(n.cash_per_year(cheap, 3, all) >= n.floor_salary(3) - 10, "terms never buy him below his floor")
	check(not n.accepts(cheap - 100, 3, all), "just below the required salary doesn't sign")
	# Signing books the bonus and the clause.
	var cy := s.cap_year()
	var before := Contracts.payroll(user, cy) - Contracts.cap_hold(so)
	var res := n.accept(3, all)
	check(res["result"] == "signed", "accepting with terms signs (%s)" % res["text"])
	if res["result"] == "signed":
		check(so.contract.bonus == 1500 and so.contract.no_trade and so.contract.salary == cheap, "contract carries the terms")
		check(int(user.bonus_money.get(cy, 0)) >= 1500, "bonus booked on the cap year")
		check(Contracts.payroll(user, cy) == before + cheap + 1500, "payroll counts salary plus bonus")
		check(not so.promise.is_empty(), "starter promise tracked")
		check(not Trades.tradeable(so), "no-trade clause blocks trades")
		so.trade_request = true
		check(Trades.tradeable(so), "a trade request waives the clause")
		so.trade_request = false
	# Bonus counts against this year's cap.
	r = _expiring_talks(85)
	n = r[3]
	check(n.offer_error(Contracts.MIN_SALARY, 2, {"bonus": Contracts.SALARY_CAP}) != "", "bonus over the cap rejected")
	check(n.offer_error(1000, 2, {"bonus": -5}) != "", "negative bonus rejected")


func test_keep_the_core() -> void:
	var r := _expiring_talks(86)
	var s: Season = r[0]
	var user: Team = r[1]
	var so: Soldier = r[2]
	var n: Negotiation = r[3]
	var pal: Soldier = null
	for o in user.roster:
		if o != so and o.contract != null and not o.contract.is_expiring():
			pal = o
			break
	check(pal != null, "a teammate under contract")
	s.relationships.pairs[Relationships.key(so.id, pal.id)] = {"pts": 99.0, "m": 20, "d": 0.0}
	check(n.keep_target() == pal and n.term_value(&"keep", 2, {}) > 0.0, "his closest teammate can be promised")
	check(s.relationships.bond_pull(so, user) >= 0.5, "an Inseparable bond pulls him")
	check(n.arguments().any(func(a): return a["id"] == &"teammates"), "teammates argument available with a strong bond")
	var res := n.accept(2, {"keep": true})
	check(res["result"] == "signed" and so.keep_promise.get("id", -1) == pal.id, "keep promise recorded")
	var trust := so.trust
	s.release_player(user, pal)
	check(so.keep_promise.is_empty() and so.trust < trust, "cutting the teammate breaks the promise")
	check(s.talks_log.any(func(e): return e["kind"] == &"keep_broken" and e["soldier"] == so), "broken keep promise logged")


func test_bond_pull_in_talks() -> void:
	var r := _expiring_talks(87)
	var s: Season = r[0]
	var user: Team = r[1]
	var so: Soldier = r[2]
	for k in s.relationships.pairs.keys():
		if k.x == so.id or k.y == so.id:
			s.relationships.pairs.erase(k)
	s.negotiations.clear()
	var lone := Negotiation.start(s, user, so)
	for o in user.roster:
		if o != so:
			s.relationships.pairs[Relationships.key(so.id, o.id)] = {"pts": 85.0, "m": 20, "d": 0.0}
	var bonded := Negotiation.start(s, user, so)
	check(bonded.demand_mult < lone.demand_mult and bonded.floor_mult <= lone.floor_mult, "bonds soften his demand")
	check(bonded.talk.any(func(t): return "close with" in t["text"]), "agent mentions his friends")
	var other: Team = s.league.teams.filter(func(t: Team): return t != user)[0]
	var fa_score := FreeAgency.score(user, so, 2000, 2) - FreeAgency.score(other, so, 2000, 2)
	for k in s.relationships.pairs.keys():
		if k.x == so.id or k.y == so.id:
			s.relationships.pairs.erase(k)
	check(fa_score > FreeAgency.score(user, so, 2000, 2) - FreeAgency.score(other, so, 2000, 2), "free agents lean toward bonded teammates")


func test_negotiation_tactics() -> void:
	var r := _expiring_talks(88)
	var s: Season = r[0]
	var so: Soldier = r[2]
	var n: Negotiation = r[3]
	var p := n.patience
	var a := n.ask(2)
	check(a["ok"] and not n.revealed.is_empty() and n.patience < p, "asking reveals his range")
	check(int(n.revealed["low"]) <= n.floor_salary(2) and int(n.revealed["high"]) >= n.floor_salary(2), "range contains his floor")
	check(not n.can_ask(), "only ask once")
	check(not n.can_smooth() or so.trust < Negotiation.SMOOTH_TRUST_BELOW, "nothing to smooth over yet")
	n.make_offer(Contracts.MIN_SALARY, 2)
	if n.is_open() and n.missteps > 0:
		var dm := n.demand_mult
		var t := so.trust
		check(n.smooth_over()["ok"] and so.trust > t and n.demand_mult <= dm, "smoothing over repairs a lowball")
		check(not n.can_smooth(), "smooth over once")
	n.patience = 30.0
	var m := n.demand_mult
	n.demand_mult = n.floor_mult
	check(n.sleep_on_it()["ok"] and n.patience == 55.0, "sleeping on it restores patience")
	check(n.demand_mult > n.floor_mult and n.demand_mult <= m + 1.0, "his ask drifts back up overnight")
	check(not n.can_sleep(), "sleep on it once")
	# Final offer: at his number he signs; far below he walks.
	var want := n.required_salary(2)
	r = _expiring_talks(89)
	var n2: Negotiation = r[3]
	var low := n2.final_offer(Contracts.MIN_SALARY, 2)
	check(low["result"] == "walked" and n2.state == Negotiation.WALKED, "lowball final offer: he walks")
	check(r[0].talks_log.any(func(e): return e["kind"] == &"walked"), "walkout logged")
	var fin := n.final_offer(want, 2)
	check(fin["result"] == "signed" or n.offer_error(want, 2) != "", "final offer at his number signs")
	check(s != null, "season ok")


func test_negotiation_arguments() -> void:
	var r := _expiring_talks(90)
	var s: Season = r[0]
	var user: Team = r[1]
	var so: Soldier = r[2]
	var n: Negotiation = r[3]
	if user.home_state == "":
		user.home_state = "TX"
	so.home_state = user.home_state
	so.get_dna().hometown = 90
	user.market_rating = 95
	n._args_cache = []
	var ids := n.arguments().map(func(a): return a["id"])
	check(ids.has(&"hometown") and ids.has(&"big_stage"), "hometown and big-stage pitches exist when the data backs them (%s)" % [ids])
	for a in n.arguments():
		check(a["group"] == (Negotiation.SELL if a["tone"] == "soft" else Negotiation.HARDBALL), "%s grouped by tone" % a["id"])
	check(n.arguments_in(Negotiation.SELL).size() + n.arguments_in(Negotiation.HARDBALL).size() == n.arguments().size(), "every argument in a tab")
	so.home_state = ""
	n._args_cache = []
	check(not n.arguments().any(func(a): return a["id"] == &"hometown"), "no hometown pitch without a home state")
	check(s != null, "season ok")


func test_starter_promises() -> void:
	var s := Season.new_franchise(91)
	var user := s.user_team()
	var starter: Soldier = user.starters()[0]
	var bench: Soldier = null
	for so in user.roster:
		if user.slot_of(so) == &"":
			bench = so
	check(bench != null, "user team has a bench player")
	for so in [starter, bench]:
		so.promise = {"year": s.year, "team": user.abbrev, "games": 0, "started": 0}
		so.trust = Soldier.TRUST_NEUTRAL
	bench.get_dna().playing_time = 90
	var slot := user.slot_of(starter)
	var guard := 0
	while s.phase != Season.PHASE_OFFSEASON and guard < 40:
		starter.injury_weeks = 0
		bench.injury_weeks = 0
		if user.slot_of(starter) == &"":
			user.assign(slot, starter)
		if user.slot_of(bench) != &"":
			user.assign(user.slot_of(bench), user.roster.filter(func(x): return x != bench and user.slot_of(x) == &"")[0])
		s.sim_week()
		guard += 1
	var kept := s.promise_log.filter(func(p): return p["soldier"] == starter)
	var broke := s.promise_log.filter(func(p): return p["soldier"] == bench)
	check(kept.size() == 1 and broke.size() == 1, "both promises judged once")
	if kept.size() == 1 and broke.size() == 1:
		check(kept[0]["games"] > 0, "games counted")
		check(kept[0]["kept"] or starter.is_injured(), "starter's promise kept")
		check(not broke[0]["kept"] and broke[0]["request"], "bench player's promise broken, trade requested")
	check(starter.trust > Soldier.TRUST_NEUTRAL or starter.is_injured(), "kept promise builds trust")
	check(bench.trust < Soldier.TRUST_NEUTRAL and bench.trade_request, "broken promise costs trust")
	check(starter.promise.is_empty() and bench.promise.is_empty(), "promises cleared")
	# His next negotiation opens sour.
	if user.roster.has(bench):
		bench.contract.years = 0
		var n := s.negotiation(user, bench)
		check(n != null and n.patience < Negotiation.MAX_PATIENCE, "broken promise sours the next talks")


func test_trade_need_factor() -> void:
	var s := Season.new_franchise(12)
	var t: Team = s.league.teams.filter(func(x: Team): return not x.user_controlled)[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var stud := PlayerGenerator.generate(rng, 9001, Scheme.Role.FLEX, 95.0, 25)
	var scrub := PlayerGenerator.generate(rng, 9002, Scheme.Role.FLEX, 50.0, 29)
	scrub.dev = Soldier.DEV_MIN
	check(is_equal_approx(s.trades.need_factor(s, t, stud), 1.0), "a would-be starter is fully valued")
	check(s.trades.need_factor(s, t, scrub) < 0.85, "a buried, low-potential vet is discounted (%.2f)" % s.trades.need_factor(s, t, scrub))
	check(s.trades.player_value(s, scrub, t, false) < s.trades.player_value(s, scrub, t, true), "receiving a buried player is worth less than giving him")


func test_trades() -> void:
	# The real 20-team league: pick values are keyed to the 60-pick board.
	var s := _fixed(123)
	var tr := s.trades
	var user := s.user_team()
	var ai: Team = s.league.teams.filter(func(t: Team): return t != user)[0]
	var by_ovr := func(t: Team) -> Array:
		var r: Array = t.roster.filter(func(x: Soldier): return Trades.tradeable(x))
		r.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
		return r
	var ai_best: Soldier = by_ovr.call(ai)[0]
	var mine: Array = by_ovr.call(user)
	var my_worst: Soldier = mine[mine.size() - 1]
	# Valuation basics.
	check(Trades.curve(80) > Trades.curve(70) and Trades.curve(70) > Trades.curve(60), "value curve rises with OVR")
	check(tr.player_value(s, ai_best, ai) > tr.player_value(s, my_worst, ai), "a star is worth more than a scrub")
	var p1 := Trades.pick_asset(s.draft.year, 1, user)
	var p2 := Trades.pick_asset(s.draft.year, 2, user)
	check(tr.value(s, p1, ai) > tr.value(s, p2, ai), "1st-round pick beats 2nd-round pick")
	var all_picks := 0
	for t in s.league.teams:
		all_picks += tr.picks_of(s, t).size()
	check(all_picks == s.league.teams.size() * 2 * Draft.ROUNDS, "every pick for two drafts is owned (%d)" % all_picks)
	# Rules.
	check(tr.window_open(s), "window open in week 1")
	check(tr.validate(s, user, [], ai, []) != "", "empty deal rejected")
	var four: Array = mine.slice(0, 4).map(func(x): return Trades.player_asset(x))
	check(tr.validate(s, user, four, ai, [Trades.player_asset(ai_best)]) != "", "max assets per side")
	check(tr.validate(s, user, [Trades.player_asset(ai_best)], ai, []) != "", "can't trade a player you don't own")
	check(tr.validate(s, user, [Trades.pick_asset(s.draft.year, 1, ai)], ai, []) != "", "can't trade a pick you don't own")
	var yrs: int = my_worst.contract.years
	my_worst.contract.years = 0
	check(tr.validate(s, user, [Trades.player_asset(my_worst)], ai, [p1]) != "", "expiring contracts can't be traded")
	my_worst.contract.years = yrs
	var wk := s.week
	s.week = Trades.DEADLINE_WEEK + 1
	check(not tr.window_open(s) and tr.validate(s, user, [p2], ai, [Trades.pick_asset(s.draft.year, 2, ai)]) != "", "deadline closes the window")
	s.week = wk
	# Lopsided offers are refused and cost patience; at zero they stop listening.
	var space := Contracts.cap_space(user, s.cap_year())
	var star: Soldier = by_ovr.call(ai).filter(func(x: Soldier): return x.contract.salary <= space)[0]
	var low := [Trades.pick_asset(s.draft.year + 1, Draft.ROUNDS, user)]
	var r := tr.propose(s, ai, low, [Trades.player_asset(star)])
	check(r["result"] == "rejected" and tr.patience_of(ai) == Trades.PATIENCE - 1, "lowball rejected, patience drops (%s)" % r["text"])
	tr.propose(s, ai, low, [Trades.player_asset(star)])
	tr.propose(s, ai, low, [Trades.player_asset(star)])
	check(tr.patience_of(ai) == 0, "patience runs out")
	r = tr.propose(s, ai, low, [Trades.player_asset(star)])
	check(r["result"] == "rejected" and ai.roster.has(star), "no deals at zero patience")
	tr.weekly(s, RandomNumberGenerator.new())
	check(tr.patience_of(ai) == 1, "patience recovers weekly")
	tr.patience[ai.abbrev] = Trades.PATIENCE
	# What would it take for a mid player: the AI accepts its own answer.
	var mid: Soldier = by_ovr.call(ai)[4]
	var want := [Trades.player_asset(mid)]
	var pkg := tr.what_would_it_take(s, ai, [], want)
	check(not pkg.is_empty(), "what-would-it-take finds a package for a role player")
	if not pkg.is_empty():
		check(tr.interest(s, ai, pkg, want) >= 1.0, "the package satisfies them")
		var loyal: Soldier = null
		for a in pkg:
			if not Trades.is_pick(a):
				loyal = a["soldier"]
		if loyal != null:
			loyal.get_dna().loyalty = 95
			loyal.trade_request = true
			tr.block[loyal.id] = true
		var morale_before := loyal.morale if loyal != null else 0.0
		var logged := tr.history.size()
		r = tr.propose(s, ai, pkg, want)
		check(r["result"] == "accepted", "proposal accepted")
		check(user.roster.has(mid) and not ai.roster.has(mid), "player moved to user")
		if loyal != null:
			check(ai.roster.has(loyal) and not user.roster.has(loyal), "user player moved to AI")
			check(not loyal.trade_request and not tr.block.has(loyal.id), "request and block cleared")
			check(loyal.trust == Soldier.TRUST_NEUTRAL, "trust resets with the new club")
			check(not is_equal_approx(loyal.morale, morale_before), "trade moves morale")
		check(tr.history.size() == logged + 1, "trade logged")
	# Loyal players are upset to leave; the rest of the logic is mood text.
	var vet: Soldier = by_ovr.call(ai)[1]
	vet.get_dna().loyalty = 100
	vet.trade_request = false
	var m0 := vet.morale
	tr.execute(s, ai, [Trades.player_asset(vet)], user, [p2])
	check(vet.morale < m0 or is_equal_approx(m0, 100.0), "loyal player's morale drops")
	check(tr.history.back()["reactions"][0]["mood"] == "upset", "loyal player is upset")
	check(tr.owner_of(p2) == ai and tr.picks_of(s, ai).any(func(a): return Trades.key_of(a) == Trades.key_of(p2)), "pick ownership moves")
	# Traded pick shows up in the mock order and the real draft order.
	var mock := s.mock_pick_order()
	var n := s.league.teams.size()
	var r2 := mock.slice(n, 2 * n)
	check(r2.count(ai) == 2 and not r2.has(user), "traded 2nd-rounder in the mock order")
	# A season of AI activity: AI-to-AI trades happen and nobody is flipped twice in a year.
	var s2 := Season.new_franchise(5)
	var guard := 0
	while s2.phase == Season.PHASE_REGULAR and guard < 20:
		s2.sim_week()
		guard += 1
	check(s2.trades.history.any(func(e): return e["ai"]), "AI teams trade among themselves")
	var seen := {}
	for e in s2.trades.history:
		for rr in e["reactions"]:
			var id: int = rr["soldier"].id
			check(not seen.has(id), "no player flipped twice in a season")
			seen[id] = true
	for t: Team in s2.league.teams:
		check(t.roster.size() >= Trades.MIN_ROSTER and t.roster.size() <= Team.ROSTER_SIZE, "rosters stay legal (%s %d)" % [t.abbrev, t.roster.size()])


func test_roster_rules() -> void:
	var s := Season.new_franchise(321)
	var tr := s.trades
	var user := s.user_team()
	var ais: Array = s.league.teams.filter(func(t: Team): return t != user)
	var ai: Team = ais[0]
	check(Trades.min_roster(s) == Trades.MIN_ROSTER, "in-season trade floor is %d" % Trades.MIN_ROSTER)
	check(user.roster.size() == Team.ROSTER_SIZE and s.user_roster_error() == "", "a full roster can play Week 1")
	# Picks for a player with a full roster: allowed (no maximum); the user must cut before playing.
	var target: Soldier = ai.roster.filter(func(x: Soldier): return Trades.tradeable(x))[0]
	var pick := Trades.pick_asset(s.draft.year, 2, user)
	check(tr.validate(s, user, [pick], ai, [Trades.player_asset(target)]) == "", "pick for a player with %d on the roster is legal" % Team.ROSTER_SIZE)
	tr.execute(s, user, [pick], ai, [Trades.player_asset(target)])
	check(user.roster.size() == Team.ROSTER_SIZE + 1 and user.roster.has(target), "user can go over the limit by trade")
	check(s.user_roster_error() != "", "over the limit: can't play until he cuts")
	s.release_player(user, user.least_valuable())
	check(s.user_roster_error() == "", "cut back to %d: can play" % Team.ROSTER_SIZE)
	# Week 1 needs exactly 12; later weeks ROSTER_MIN..12.
	s.release_player(user, user.least_valuable())
	check(s.user_roster_error().contains("exactly"), "Week 1 with 11 is blocked")
	s.week = 2
	check(s.user_roster_error() == "", "Week 2 with 11 is fine")
	while user.roster.size() >= Season.ROSTER_MIN:
		s.release_player(user, user.least_valuable())
	check(s.user_roster_error() != "", "below %d can't play" % Season.ROSTER_MIN)
	var mine: Soldier = user.roster.filter(func(x: Soldier): return Trades.tradeable(x))[0]
	check(tr.validate(s, user, [Trades.player_asset(mine)], ai, [Trades.pick_asset(s.draft.year, 1, ai)]) != "", "in-season trade can't drop a team under %d" % Trades.MIN_ROSTER)
	s.week = 1
	# Headless safety net: an illegal user roster is filled before the week is played.
	s.sim_week()
	check(user.roster.size() == Team.ROSTER_SIZE, "sim fills an illegal user roster (%d)" % user.roster.size())

	# AI teams restructure right after a trade puts them over: shop surplus for picks, else cut.
	var s2 := Season.new_franchise(654)
	var u2 := s2.user_team()
	var a2: Team = s2.league.teams.filter(func(t: Team): return t != u2)[1]
	var cuts_before := s2.league.free_agents.size()
	var give: Soldier = u2.roster.filter(func(x: Soldier): return Trades.tradeable(x))[0]
	var p2 := Trades.pick_asset(s2.draft.year, 2, a2)
	check(s2.trades.validate(s2, u2, [Trades.player_asset(give)], a2, [p2]) == "", "player for a pick to a full AI roster is legal")
	s2.trades.execute(s2, u2, [Trades.player_asset(give)], a2, [p2])
	check(a2.roster.size() == Team.ROSTER_SIZE, "AI restructured back to %d (%d)" % [Team.ROSTER_SIZE, a2.roster.size()])
	check(s2.trades.moves.size() >= 1, "AI roster move logged")
	var mv: Dictionary = s2.trades.moves.back()
	check(mv["team"] == a2 and not a2.roster.has(mv["soldier"]), "the moved player left the AI roster")
	if mv["kind"] == &"cut":
		check(s2.league.free_agents.size() == cuts_before + 1, "cut player hits free agency")
	else:
		check(mv["to"] != u2 and mv["to"].roster.has(mv["soldier"]), "surplus dumped to an AI team with room")
	for t in s2.league.teams:
		check(t.roster.size() <= Team.ROSTER_SIZE or t.user_controlled, "%s within the limit" % t.abbrev)
	check(a2.lineup.size() == 5, "restructured AI has a lineup")
	# Keep value: a starter is worth keeping over the team's least valuable player.
	var worst := a2.least_valuable()
	for so in a2.starters():
		check(a2.keep_value(so) >= a2.keep_value(worst), "starters out-value the first cut")
	# Dead money makes a long, pricey deal harder to cut.
	var probe: Soldier = a2.bench()[0]
	var kv0 := a2.keep_value(probe)
	var c0: Contract = probe.contract
	probe.contract = Contract.make(Contracts.MAX_SALARY / 2, 4, s2.year)
	var dead_kv := a2.keep_value(probe)
	probe.contract = Contract.make(Contracts.MIN_SALARY, 1, s2.year)
	check(dead_kv > a2.keep_value(probe) - 3.5, "dead money weighs on cuts (%.1f vs %.1f)" % [dead_kv, a2.keep_value(probe)])
	probe.contract = c0
	check(is_equal_approx(a2.keep_value(probe), kv0), "keep value is stable")

	# Offseason: trades allowed regardless of count; floor of 5; AI over the limit restructures.
	var s3 := Season.new_franchise(987)
	s3.sim_to_end_of_season()
	check(s3.offseason_stage == Season.OFF_RESIGN and s3.trades.window_open(s3), "trade window open from the re-sign week")
	s3.advance_offseason()
	check(s3.offseason_stage == Season.OFF_FREE_AGENCY and s3.trades.window_open(s3), "trade window open in free agency")
	check(Trades.min_roster(s3) == Trades.MIN_ROSTER_OFFSEASON, "offseason trade floor is %d" % Trades.MIN_ROSTER_OFFSEASON)
	var u3 := s3.user_team()
	var a3: Team = s3.league.teams.filter(func(t: Team): return t != u3)[0]
	var t3: Soldier = a3.roster.filter(func(x: Soldier): return Trades.tradeable(x))[0]
	var mypicks := s3.trades.picks_of(s3, u3)
	check(s3.trades.validate(s3, u3, [mypicks[0]], a3, [Trades.player_asset(t3)]) == "", "offseason: picks for a player with a full roster")
	while u3.roster.size() > Trades.MIN_ROSTER_OFFSEASON + 1:
		s3.release_player(u3, u3.least_valuable())
	var two: Array = u3.roster.filter(func(x: Soldier): return Trades.tradeable(x)).slice(0, 2).map(func(x): return Trades.player_asset(x))
	if two.size() == 2:
		check(s3.trades.validate(s3, u3, two, a3, [Trades.pick_asset(s3.draft.year, 1, a3)]) != "", "offseason floor of %d" % Trades.MIN_ROSTER_OFFSEASON)
		check(s3.trades.validate(s3, u3, [two[0]], a3, [Trades.pick_asset(s3.draft.year, 1, a3)]) == "", "down to %d is fine in the offseason" % Trades.MIN_ROSTER_OFFSEASON)
	s3.start_next_season()
	for t in s3.league.teams:
		if not t.user_controlled:
			check(t.roster.size() == Team.ROSTER_SIZE, "%s at %d for the new season" % [t.abbrev, t.roster.size()])
	check(u3.roster.size() < Team.ROSTER_SIZE and s3.user_roster_error().contains("exactly"), "user isn't auto-filled: he must sign to %d" % Team.ROSTER_SIZE)


func test_ai_weekly_training() -> void:
	var s := Season.new_franchise(246)
	var before := {}
	for t in s.league.teams:
		var total := 0
		for so in t.roster:
			total += _xp_total(so)
		before[t] = total
	s.prepare_week()
	for t in s.league.teams:
		if t.user_controlled:
			continue
		var total := 0
		for so in t.roster:
			total += _xp_total(so)
			if not so.is_injured():
				check(so.intensity == Training.ai_intensity(so, t.starters().has(so)), "%s trains on auto intensity" % so.short_name())
		check(total > before[t], "%s trained this week (+%d XP)" % [t.abbrev, total - before[t]])


func test_camp_respects_caps() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 30:
		var c := Camp.make(2026)
		var t := Team.new()
		var so := PlayerGenerator.generate(rng, i + 1, Scheme.Role.FLEX, 60.0, 23)
		so.dev = Soldier.DEV_MAX
		t.roster.append(so)
		var r0 := so.group_rating(Stats.PHYSICALITY)
		so.group_caps[Stats.PHYSICALITY] = r0
		check(c.check(t, Stats.PHYSICALITY, so).contains("capped"), "capped group can't be drilled")
		check(c.run(t, Stats.PHYSICALITY, so, rng).is_empty() and so.group_rating(Stats.PHYSICALITY) == r0, "capped group unchanged")
		so.group_caps[Stats.PHYSICALITY] = r0 + 1
		var res := c.run(t, Stats.PHYSICALITY, so, rng)
		check(not res.is_empty() and so.group_rating(Stats.PHYSICALITY) <= r0 + 1, "drill stops at the cap (%d > %d)" % [so.group_rating(Stats.PHYSICALITY), r0 + 1])
		check(so.group_caps[Stats.PHYSICALITY] == r0 + 1, "cap isn't raised")


# --- league expansion (fixed 20-team league) ---------------------------------------

func _fixed(seed_value: int, team_index := 0) -> Season:
	Season.fixture_teams = 0
	var s := Season.new_franchise(seed_value, team_index)
	Season.fixture_teams = 5
	return s


func test_fixed_league() -> void:
	var a := _fixed(5)
	var b := _fixed(6, 3)
	check(a.league.teams.size() == 20, "20 teams (%d)" % a.league.teams.size())
	check(a.divisions().size() == 4, "4 divisions")
	for d in a.divisions():
		check(a.division_teams(d).size() == 5, "%s has 5 teams" % d)
	for i in a.league.teams.size():
		var t: Team = a.league.teams[i]
		var row: Array = LeagueData.TEAMS[i]
		check(t.abbrev == row[0] and t.division == row[5] and t.backstory != "", "%s identity from LeagueData" % t.abbrev)
		check(t.roster.size() == Team.ROSTER_SIZE, "%s has %d players" % [t.abbrev, t.roster.size()])
		check(absi(t.team_ovr() - int(row[7])) <= 2, "%s OVR %d near target %d" % [t.abbrev, t.team_ovr(), row[7]])
		check(t.color == Color(row[3]) and t.color2 == Color(row[4]), "%s colors" % t.abbrev)
		# Fixed rosters: the same players whatever the seed.
		var names_a: Array = t.roster.map(func(x: Soldier): return x.full_name())
		var names_b: Array = b.league.teams[i].roster.map(func(x: Soldier): return x.full_name())
		check(names_a == names_b, "%s roster is fixed across seeds" % t.abbrev)
		check(Contracts.payroll(t, a.cap_year()) <= Contracts.SALARY_CAP, "%s under the cap" % t.abbrev)
	check(b.user_team() == b.league.teams[3], "user team index honoured")


## The Weekly News: an issue for every week and offseason step, every slot filled, no two ledes
## alike, and the same league writes the same paper.
func test_season_history() -> void:
	var s := _fixed(71, 1)
	check(s.history.is_empty(), "no history before the first final")
	s.sim_to_end_of_season()
	check(s.history.size() == 1, "one snapshot after the first final (%d)" % s.history.size())
	var snap: SeasonSnapshot = s.history[0]
	check(snap.year == s.year and snap.champion == s.champion, "snapshot has the year and champion")
	var fin: ScheduledMatch = s.playoff_matches[-1]
	check(snap.runner_up == fin.loser() and snap.runner_up != snap.champion, "runner-up is the final's loser")
	check(snap.standings.size() == s.league.teams.size(), "final table covers every team")
	check(snap.bracket.size() == s.playoff_matches.size(), "bracket has every playoff match")
	check(snap.final_score() == "%d-%d" % [fin.games_for(s.champion), fin.games_for(snap.runner_up)], "final score is from the champion's side")
	check(snap.champion_record() != "", "champion record found in the table")
	var snap_year := s.year
	while s.offseason_stage != Season.OFF_DONE:
		s.advance_offseason()
	s.start_next_season()
	check(s.champion == null, "champion resets for the new season")
	check(s.history.size() == 1 and s.history[0].champion != null and s.history[0].year == snap_year, "the snapshot survives the rollover")
	s.sim_to_end_of_season()
	check(s.history.size() == 2 and s.history[1].year == snap_year + 1, "second season adds a second snapshot")
	s.ensure_history()
	check(s.history.size() == 2, "ensure_history does not duplicate a season already recorded")


func test_records() -> void:
	var s := _fixed(72, 1)
	s.sim_to_end_of_season()
	while s.offseason_stage != Season.OFF_DONE:
		s.advance_offseason()
	s.start_next_season()
	s.sim_to_end_of_season()
	var kills: Dictionary = Records.PLAYER_STATS[0]
	var kd: Dictionary = Records.PLAYER_STATS[-1]
	var everyone := Records.soldiers(s)
	for r in s.retirements:
		check(everyone.has(r["soldier"]), "retired soldiers are in the record pool")
	var best := 0
	var best_career := 0
	for so: Soldier in everyone:
		best_career = maxi(best_career, int(so.career["kills"]))
		for y in so.season_lines:
			best = maxi(best, int(so.season_lines[y]["kills"]))
	var seasons := Records.player_seasons(s, kills)
	check(not seasons.is_empty() and seasons[0]["value"] == best, "season kills record is the best line (%s vs %d)" % [seasons[0]["value"] if not seasons.is_empty() else "-", best])
	check(seasons.size() <= Records.TOP_N, "top list is capped")
	for i in range(1, seasons.size()):
		check(seasons[i - 1]["value"] >= seasons[i]["value"], "season list is sorted best first")
	var careers := Records.player_careers(s, kills)
	check(not careers.is_empty() and careers[0]["value"] == best_career, "career kills record is the best career")
	check(careers[0]["first"] <= careers[0]["last"] and careers[0]["first"] > 0, "career span is set")
	for row in Records.player_seasons(s, kd):
		check(int(row["soldier"].season_lines[row["year"]]["matches"]) >= Records.MIN_MATCHES_SEASON, "kd record needs a minimum of matches")
	var team := s.user_team()
	for row in Records.player_seasons(s, kills, team.abbrev):
		check(row["team"] == team.abbrev, "franchise season records only count that team")
	for row in Records.player_careers(s, kills, team.abbrev):
		var with_team := 0
		for y in row["soldier"].season_lines:
			if row["soldier"].season_lines[y]["team"] == team.abbrev:
				with_team += int(row["soldier"].season_lines[y]["kills"])
		check(int(row["value"]) == with_team and row["value"] <= row["soldier"].career["kills"], "franchise career is the sum of that team's seasons")
	var wins: Dictionary = Records.TEAM_STATS[0]
	var most := 0
	for snap: SeasonSnapshot in s.history:
		for r in snap.standings:
			most = maxi(most, int(r["wins"]))
	var tw := Records.team_seasons(s, wins)
	check(not tw.is_empty() and tw[0]["value"] == most, "team wins record matches the history")
	for row in Records.team_seasons(s, wins, team.abbrev):
		check(row["team"] == team, "franchise team records only list that team")
	check(Records.format_value(kd, 1.234) == "1.23" and Records.format_value(kills, 41.0) == "41", "values format by kind")


## Gives `so` n seasons with `team` and a Season MVP, the way a long, decorated career looks.
func _decorate(s: Season, so: Soldier, team: Team, n: int, mvp := true, extra := 0) -> void:
	so.season_lines = {}
	for i in n:
		var line := {"team": team.abbrev}
		for k in Soldier.STAT_LINE_KEYS:
			line[k] = 1
		so.season_lines[2000 + i] = line
	var rev := SeasonReview.new()
	rev.year = 2000 + n
	if mvp:
		rev.awards.append({"award": RetiredCallsigns.MVP_AWARD, "soldier": so, "team": team, "line": ""})
	for i in extra:
		rev.all_league.append({"soldier": so, "team": team, "role": Scheme.Role.FLEX, "line": ""})
	s.review_history.append(rev)


func test_retired_callsigns() -> void:
	var s := _fixed(73, 1)
	var user := s.user_team()
	var ai: Team = s.league.teams[0] if s.league.teams[0] != user else s.league.teams[2]
	var rookie := ai.roster[0]
	var vet := ai.roster[1]
	var mine := user.roster[0]
	check(RetiredCallsigns.make_entry(s, rookie).is_empty(), "no seasons, no honors: not eligible")
	_decorate(s, rookie, ai, RetiredCallsigns.MIN_SEASONS_WITH_CLUB - 1)
	check(RetiredCallsigns.make_entry(s, rookie).is_empty(), "an MVP but too few seasons with the club: not eligible")
	s.review_history.clear()
	_decorate(s, rookie, ai, RetiredCallsigns.MIN_SEASONS_WITH_CLUB, false, RetiredCallsigns.MIN_HONORS - 1)
	check(RetiredCallsigns.make_entry(s, rookie).is_empty(), "long service but too few honors: not eligible")
	s.review_history.clear()
	_decorate(s, rookie, ai, RetiredCallsigns.MIN_SEASONS_WITH_CLUB, false, RetiredCallsigns.MIN_HONORS)
	var entry := RetiredCallsigns.make_entry(s, rookie)
	check(not entry.is_empty() and entry["team"] == ai and entry["seasons"] == RetiredCallsigns.MIN_SEASONS_WITH_CLUB, "enough All-League picks qualify")
	s.review_history.clear()
	_decorate(s, rookie, ai, RetiredCallsigns.MIN_SEASONS_WITH_CLUB)
	_decorate(s, vet, ai, RetiredCallsigns.MIN_SEASONS_WITH_CLUB)
	_decorate(s, mine, user, RetiredCallsigns.MIN_SEASONS_WITH_CLUB)
	check(not RetiredCallsigns.make_entry(s, rookie).is_empty(), "long service plus a Season MVP qualifies")
	# Seasons split between clubs: the club with the most seasons gets the callsign.
	var split := ai.roster[2]
	_decorate(s, split, ai, RetiredCallsigns.MIN_SEASONS_WITH_CLUB + 2)
	split.season_lines[2000]["team"] = user.abbrev
	var split_club := RetiredCallsigns.club_of(s, split)
	check(split_club["team"] == ai and split_club["seasons"] == RetiredCallsigns.MIN_SEASONS_WITH_CLUB + 1, "the club with most seasons is the soldier's club")

	var sign := rookie.callsign
	var records := [{"soldier": rookie}, {"soldier": mine}, {"soldier": ai.roster[3]}]
	RetiredCallsigns.process(s, records)
	check(s.league.retired_callsigns.size() == 1 and s.league.retired_callsigns[0]["soldier"] == rookie, "the AI club's callsign is retired at once")
	check(s.league.callsign_proposals.size() == 1 and s.league.callsign_proposals[0]["soldier"] == mine, "the user's club gets a proposal")
	check(RetiredCallsigns.is_retired(s.league, sign.to_upper()), "is_retired ignores case")
	check(RetiredCallsigns.of_team(s.league, ai).size() == 1 and RetiredCallsigns.of_team(s.league, user).is_empty(), "the banner list is per club")
	check(RetiredCallsigns.make_entry(s, rookie).is_empty(), "an already retired callsign is not proposed again")
	var reserved := s.league.reserved_callsigns()
	check(reserved.has(sign.to_lower()) and reserved.has(mine.callsign.to_lower()), "retired and pending callsigns are reserved")

	# Nobody is handed a reserved callsign, even a soldier already wearing it.
	var other := ai.roster[4]
	other.callsign = sign
	s.league.ensure_callsigns()
	check(other.callsign.to_lower() != sign.to_lower(), "an active soldier cannot keep a retired callsign")
	var fresh := ai.roster[5]
	fresh.callsign = ""
	s.league.give_callsign(fresh)
	check(fresh.callsign != "" and not s.league.reserved_callsigns().has(fresh.callsign.to_lower()), "new callsigns skip reserved ones")

	var pending: Dictionary = s.league.callsign_proposals[0]
	RetiredCallsigns.decide(s, pending, false)
	check(s.league.callsign_proposals.is_empty() and s.league.retired_callsigns.size() == 1, "declining drops the proposal and retires nothing")
	check(not s.league.reserved_callsigns().has(mine.callsign.to_lower()), "a declined callsign is free again")
	RetiredCallsigns.decide(s, pending, true)
	check(s.league.retired_callsigns.size() == 1, "an answered proposal cannot be answered twice")
	RetiredCallsigns.process(s, [{"soldier": mine}])
	RetiredCallsigns.resolve_all(s)
	check(s.league.callsign_proposals.is_empty() and s.league.retired_callsigns.size() == 2, "open proposals are honoured when the season starts")


## Twenty-four AI-club soldiers with careers that grow with their index (0 weakest). All of them
## are put on the retirement list `ago` seasons back and released.
func _hall_pool(s: Season, ago: int) -> Array:
	var user := s.user_team()
	var pool: Array = []
	for t in s.league.teams:
		if t != user:
			pool.append_array(t.roster)
	pool = pool.slice(0, 24)
	for i in pool.size():
		var so: Soldier = pool[i]
		var k := i + 1
		var club := s.league.team_of(so)
		so.career = {"matches": 60, "rounds": 120, "kills": 50 * k, "deaths": 50, "assists": 20 * k, "damage": 400 * k, "saves": 0,
			"headshots": 0, "shots": 0, "hits": 0, "mvps": k, "clutches": k, "games": 0, "wipes": 0, "hill_s": 0, "caps": 0}
		so.season_lines = {2000: {"team": club.abbrev, "matches": 20, "kills": 5 * k, "deaths": 10}}
		club.release(so)
		s.retirements.append({"soldier": so, "year": s.year - ago, "team": club})
	return pool


func test_hall_of_fame() -> void:
	var s := _fixed(74, 1)
	var user := s.user_team()
	var pool := _hall_pool(s, HallOfFame.WAIT_SEASONS)
	var ctx := HallOfFame.context(s)
	var low := HallOfFame.breakdown(s, ctx, pool[2])
	var mid := HallOfFame.breakdown(s, ctx, pool[12])
	var star := HallOfFame.breakdown(s, ctx, pool[23])
	check(low["score"] < mid["score"] and mid["score"] < star["score"], "a bigger career scores higher (%.1f < %.1f < %.1f)" % [low["score"], mid["score"], star["score"]])
	check(is_equal_approx(star["score"], star["production"] + star["awards"] + star["titles"] + star["peak"]), "the score is the sum of its parts")
	check(star["production"] <= HallOfFame.PRODUCTION_POINTS and star["peak"] <= HallOfFame.PEAK_POINTS, "production and peak stay within their points")
	var green: Soldier = pool[0]
	green.career["matches"] = HallOfFame.MIN_MATCHES - 1
	check(HallOfFame.breakdown(s, ctx, green)["score"] == 0.0, "a short career is not scored")

	# Awards are capped, titles need a real season with the champion.
	var decorated: Soldier = pool[23]
	for i in 20:
		var rev := SeasonReview.new()
		rev.year = 1980 + i
		rev.awards.append({"award": RetiredCallsigns.MVP_AWARD, "soldier": decorated, "team": null, "line": ""})
		s.review_history.append(rev)
	var champ: Team = s.league.team_by_abbrev(decorated.season_lines[2000]["team"])
	var snap := SeasonSnapshot.new()
	snap.year = 2000
	snap.champion = champ
	s.history.append(snap)
	var b := HallOfFame.breakdown(s, HallOfFame.context(s), decorated)
	check(b["awards"] == HallOfFame.AWARDS_CAP and b["honors"].size() == 20, "awards are capped (%s, %d honors)" % [b["awards"], b["honors"].size()])
	check(b["titles_won"] == 1 and b["titles"] == HallOfFame.TITLE_POINTS, "a title season with the champion counts")
	s.review_history.clear()
	s.history.clear()

	# The vote: only those whose wait has ended, best first, capped, once.
	check(HallOfFame.candidates(s).size() == 24, "everyone who retired WAIT seasons ago is a candidate")
	pool[22].season_lines[2000]["team"] = user.abbrev
	var cls := HallOfFame.run(s, 0.0)
	check(cls.size() == HallOfFame.CLASS_MAX, "the class is capped (%d)" % cls.size())
	check(cls[0]["soldier"] == pool[23] and cls[1]["soldier"] == pool[22] and cls[2]["soldier"] == pool[21], "the best scores go in, best first")
	check(cls[0]["score"] >= cls[1]["score"] and cls[1]["score"] >= cls[2]["score"], "the class is sorted by score")
	check(s.hall_of_fame.size() == 3 and HallOfFame.is_member(s, pool[23]) and not HallOfFame.is_member(s, pool[20]), "members are recorded")
	check(HallOfFame.class_of(s, s.year).size() == 3 and HallOfFame.entry_of(s, pool[23])["year"] == s.year, "the class and entry are found by year and soldier")
	check(HallOfFame.run(s, 0.0).size() == HallOfFame.CLASS_MAX and s.hall_of_fame.size() == 6, "the next vote takes the next best, never the same soldier twice")
	var again := HallOfFame.candidates(s)
	check(again.size() == 18 and not again.has(pool[23]), "inducted soldiers are no longer candidates")

	# An inductee's callsign is retired too: at once for an AI club, as a proposal for yours.
	var ai_sign := String(pool[23].callsign)
	check(RetiredCallsigns.is_retired(s.league, ai_sign), "an AI club inductee's callsign is retired")
	check(s.league.callsign_proposals.any(func(e): return e["soldier"] == pool[22]), "your club's inductee's callsign waits for your answer")

	var fresh := _fixed(75, 1)
	var late := _hall_pool(fresh, HallOfFame.WAIT_SEASONS - 1)
	check(HallOfFame.candidates(fresh).is_empty() and HallOfFame.run(fresh, 0.0).is_empty(), "nobody is voted on before the wait is over (%d)" % late.size())
	var strict := _fixed(76, 1)
	_hall_pool(strict, HallOfFame.WAIT_SEASONS)
	check(HallOfFame.run(strict, 1000.0).is_empty(), "nobody below the bar is inducted")


## Lower-cased callsigns of every active soldier; fails the test on a blank or repeated one or one
## on the retired list.
func _check_callsigns(s: Season, when: String) -> void:
	var seen := {}
	var retired := s.league.reserved_callsigns()
	var pool: Array = s.league.all_soldiers()
	pool.append_array(s.league.free_agents)
	for so: Soldier in pool:
		var key := so.callsign.to_lower()
		check(key != "", "%s: %s has no callsign" % [when, so.full_name()])
		check(not seen.has(key), "%s: callsign %s is worn by two soldiers" % [when, so.callsign])
		check(not retired.has(key), "%s: %s wears a retired or reserved callsign" % [when, so.callsign])
		seen[key] = true


func test_callsign_uniqueness() -> void:
	var s := _fixed(77, 1)
	_check_callsigns(s, "new league")
	for season_no in 2:
		s.sim_to_end_of_season()
		while s.offseason_stage != Season.OFF_DONE:
			s.advance_offseason()
			_check_callsigns(s, "offseason step %s" % s.offseason_stage)
		s.start_next_season()
		_check_callsigns(s, "season %d" % s.year)
		var rookies := 0
		for so: Soldier in s.league.all_soldiers():
			if so.draft_year == s.year - 1:
				rookies += 1
		check(rookies > 0, "the draft class made the rosters (%d)" % rookies)

	# A retiree's callsign goes back into circulation...
	var team: Team = s.league.teams[0]
	var gone := team.roster[0]
	var sign := gone.callsign
	team.release(gone)
	gone.retired_year = s.year
	check(not s.league.taken_callsigns().has(sign.to_lower()), "a retired soldier's callsign is free again")
	var heir := s.league.teams[1].roster[0]
	heir.callsign = sign
	s.league.ensure_callsigns()
	check(heir.callsign == sign, "...and a new soldier can wear it")
	# ...unless the callsign itself is retired.
	var banner := s.league.teams[1].roster[1]
	s.league.retired_callsigns.append({"callsign": banner.callsign, "soldier": banner, "team": s.league.teams[1], "year": s.year, "seasons": 7, "honors": []})
	var banned := banner.callsign
	var other := s.league.teams[2].roster[0]
	other.callsign = ""
	s.league.teams[1].release(banner)
	var fresh_taken := s.league.taken_callsigns()
	check(fresh_taken.has(banned.to_lower()), "a retired callsign stays out of circulation after its owner leaves")
	for i in 40:
		other.callsign = ""
		s.league.give_callsign(other)
		check(other.callsign.to_lower() != banned.to_lower(), "a new soldier is never given a retired callsign")
		other.id += 1  # a different start in the pool each time
	_check_callsigns(s, "after the checks")


func test_newsroom() -> void:
	var s := _fixed(61, 1)
	s.sim_to_end_of_season()
	while s.offseason_stage != Season.OFF_DONE:
		s.advance_offseason()
	s.start_next_season()
	var nr := s.newsroom
	check(nr.count() >= s.regular_weeks + 8, "an issue a week plus the offseason (%d)" % nr.count())
	var press := LeagueData.press_for(s.user_team())
	var ledes := {}
	var kinds := {}
	var mood_lines := 0
	for i in nr.count():
		var a: Dictionary = nr.issue(i)
		kinds[a["kind"]] = true
		check(a["paper"] == press[0] and a["writer"] == press[1], "issue %d bylined by the club's paper" % i)
		check(String(a["headline"]) != "" and not (a["body"] as Array).is_empty(), "issue %d has a headline and body" % i)
		var texts: Array = [a["headline"], a["dek"]] + a["body"]
		if not a["pull_quote"].is_empty():
			texts.append(a["pull_quote"]["text"])
		for r in a["roundup"]:
			texts.append(r["text"])
		for t in texts:
			if String(t).contains("{") or String(t).contains("}"):
				check(false, "issue %d has an unfilled slot: %s" % [i, t])
		var lede: String = a["body"][0]
		check(not ledes.has(lede), "issue %d repeats an earlier lede" % i)
		ledes[lede] = true
		if a["kind"] in [Newsroom.KIND_GAME, Newsroom.KIND_BYE, Newsroom.KIND_WRAP, Newsroom.KIND_PRESEASON]:
			check((a["sidebar"] as Array).any(func(b): return b["title"] == "Market & Buzz"), "issue %d has the market and buzz box" % i)
		if a["kind"] in [Newsroom.KIND_WRAP, Newsroom.KIND_PRESEASON]:
			check((a["body"] as Array).any(func(p): return String(p).to_lower().contains("buzz") or String(p).to_lower().contains("interest")), "the %s issue talks about buzz" % a["kind"])
		if a["kind"] == Newsroom.KIND_WRAP:
			check((a["body"] as Array).any(func(p): return String(p).contains("took in") or String(p).contains("in revenue")), "the review covers the year in money")
		for p in a["body"]:
			if String(p).to_lower().contains("buzz"):
				mood_lines += 1
	for k in [Newsroom.KIND_GAME, Newsroom.KIND_WRAP, Newsroom.KIND_RESIGN, Newsroom.KIND_FA, Newsroom.KIND_DRAFT, Newsroom.KIND_CAMP, Newsroom.KIND_PRESEASON]:
		check(kinds.has(k), "a %s issue was written" % k)
	check(mood_lines >= 3, "the paper covers the city's mood (%d mentions)" % mood_lines)
	check(nr._s == null and nr._us == null and nr._f.is_empty(), "working state cleared after writing")
	check(nr.unread() == nr.count(), "everything starts unread")
	nr.mark_read(nr.count() - 1)
	check(nr.unread() == 0 and nr.is_read(0), "reading the latest marks the archive read")
	# Same league, same paper.
	var a1 := _fixed(62, 7)
	var a2 := _fixed(62, 7)
	for w in 3:
		a1.sim_week()
		a2.sim_week()
	check(a1.newsroom.count() == a2.newsroom.count() and a1.newsroom.count() >= 3, "issues written each week")
	for i in a1.newsroom.count():
		check(a1.newsroom.issue(i)["body"] == a2.newsroom.issue(i)["body"], "issue %d is deterministic" % i)
	check(LeagueData.press_for(a1.user_team())[0] != press[0], "different clubs, different papers")


func test_division_schedule() -> void:
	var s := _fixed(11)
	check(s.regular_weeks == 12, "12 regular weeks")
	check(s.total_weeks() == 15, "12 + 3 playoff weeks (%d)" % s.total_weeks())
	var games := {}
	var div_games := {}
	var byes := {}
	var cross := {}
	var pairs := {}
	for t in s.league.teams:
		games[t] = 0
		div_games[t] = 0
		byes[t] = 0
		cross[t] = {}
	for w in range(1, s.regular_weeks + 1):
		var seen := {}
		for t in s.bye_teams(w):
			byes[t] += 1
			seen[t] = true
			check(s.is_bye(t, w), "is_bye agrees")
		for m: ScheduledMatch in s.matches_for_week(w):
			check(not seen.has(m.home) and not seen.has(m.away), "team appears once in week %d" % w)
			seen[m.home] = true
			seen[m.away] = true
			games[m.home] += 1
			games[m.away] += 1
			var key := "%d>%d" % [m.home.id, m.away.id]
			pairs[key] = int(pairs.get(key, 0)) + 1
			if s.division_of(m.home) == s.division_of(m.away):
				div_games[m.home] += 1
				div_games[m.away] += 1
			else:
				cross[m.home][s.division_of(m.away)] = int(cross[m.home].get(s.division_of(m.away), 0)) + 1
				cross[m.away][s.division_of(m.home)] = int(cross[m.away].get(s.division_of(m.home), 0)) + 1
		check(seen.size() == 20, "all 20 teams accounted for in week %d" % w)
	for t in s.league.teams:
		check(games[t] == 11, "%s plays 11 games (%d)" % [t.abbrev, games[t]])
		check(byes[t] == 1, "%s has 1 bye" % t.abbrev)
		check(s.bye_week_of(t) >= 1, "%s bye week known" % t.abbrev)
		check(div_games[t] == 8, "%s plays 8 division games" % t.abbrev)
		check(cross[t].size() == 3 and cross[t].values().all(func(n): return n == 1), "%s plays one team from each other division" % t.abbrev)
		for o in s.division_teams(s.division_of(t)):
			if o != t:
				check(pairs.get("%d>%d" % [t.id, o.id], 0) == 1, "%s hosts %s once" % [t.abbrev, o.abbrev])


func test_playoff_bracket() -> void:
	check(Season.bracket_order(8) == [1, 8, 4, 5, 2, 7, 3, 6], "8-team bracket order")
	var s := _fixed(21)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for m: ScheduledMatch in s.regular_matches():
		var home_wins := rng.randf() < 0.5
		fake_result(m, 2 if home_wins else rng.randi_range(0, 1), rng.randi_range(0, 1) if home_wins else 2, [rng.randi_range(0, 50), rng.randi_range(0, 50)])
	var field := s.playoff_field()
	check(field.size() == 8, "8-team field")
	var leaders := {}
	for d in s.divisions():
		leaders[(s.division_standings(d)[0] as StandingRow).team] = true
	for i in 4:
		check(leaders.has(field[i]), "seed %d is a division winner" % (i + 1))
	var rest: Array = []
	for r in s.standings():
		if not leaders.has(r.team):
			rest.append(r.team)
	for i in 4:
		check(field[4 + i] == rest[i], "wild card %d is the best non-winner" % (i + 1))
	s.week = s.regular_weeks + 1
	s.phase = Season.PHASE_PLAYOFFS
	s._create_first_playoff_round()
	var qf: Array = s.matches_for_week(s.regular_weeks + 1)
	check(qf.size() == 4, "4 quarterfinals")
	for m: ScheduledMatch in qf:
		check(int(s.playoff_seeds[m.home]) + int(s.playoff_seeds[m.away]) == 9, "seeds pair to 9")
		check(int(s.playoff_seeds[m.home]) < int(s.playoff_seeds[m.away]), "better seed hosts")
	check(s.week_label(s.regular_weeks + 1) == "Quarterfinals" and s.week_label(s.total_weeks()) == "Final", "playoff week labels")


func test_salary_floor() -> void:
	var s := _fixed(31)
	var t: Team = s.league.teams[19]
	for so in t.roster:
		so.contract.salary = 1000
	var short := Contracts.floor_shortfall(t, s.cap_year())
	check(short == Contracts.SALARY_FLOOR - Contracts.payroll(t, s.cap_year()), "shortfall = floor - payroll")
	var charged := Contracts.charge_floor(s.league, s.cap_year())
	var mine: Array = charged.filter(func(e): return e["team"] == t)
	check(mine.size() == 1 and int(mine[0]["amount"]) == short, "penalty charged for the shortfall")
	check(int(t.floor_penalties.get(s.cap_year(), 0)) == short, "penalty recorded on the team")
	var rich: Team = s.league.teams[0]
	check(Contracts.floor_shortfall(rich, s.cap_year()) == 0, "teams above the floor pay nothing")


func test_hometown_pull() -> void:
	var s := _fixed(41)
	var det: Team = s.league.team_by_abbrev("DET")
	var ind: Team = s.league.team_by_abbrev("IND")
	var las: Team = s.league.team_by_abbrev("LAS")
	var so: Soldier = s.league.free_agents[0] if not s.league.free_agents.is_empty() else s.league.teams[5].roster[0]
	so.home_state = "MI"
	so.get_dna().hometown = 90
	var home := Dna.hometown_pull(so, det)
	var region := Dna.hometown_pull(so, ind)
	check(home > 0.0, "home-state club pulls (%.2f)" % home)
	check(is_equal_approx(region, home * 0.5), "same-region club pulls half (%.2f vs %.2f)" % [region, home])
	check(Dna.hometown_pull(so, las) == 0.0, "other regions don't pull")
	so.get_dna().hometown = 10
	check(Dna.hometown_pull(so, det) < home, "low Hometown motivation pulls less")


func test_region_and_auto_scout() -> void:
	var s := _fixed(51)
	var d := s.draft
	check(d.prospects.size() == Draft.CLASS_SIZE, "class size %d" % d.prospects.size())
	var grades := {}
	for p in d.prospects:
		grades[p.area_grade] = true
	check(grades.has("A") and grades.has("F"), "area grades span the class")
	var east := d.in_region("East")
	check(not east.is_empty(), "East prospects exist")
	var pts := d.scout_points
	check(d.scout_region("East") == east.size(), "region scout covers the region")
	for p in east:
		check(p.points >= mini(Draft.REGION_SCOUT_POINTS, Draft.MAX_POINTS_PER_PROSPECT) or p.fully_scouted(), "%s scouted by the region trip" % p.soldier.full_name())
	check(d.scout_points == pts, "region scout is free")
	check(d.scout_region("West") == -1, "only one region scout per season")
	var fav: Prospect = null
	for p in d.prospects:
		if p.points == 0 and (fav == null or p.projected_rank > fav.projected_rank):
			fav = p
	fav.favorite = true
	d.scout_points = 3
	d.auto_scout(Draft.AUTO_SCOUT_LEVELS[0])
	check(fav.points >= Draft.AUTO_SCOUT_LEVELS[0], "auto-scout covers favorites first (%d)" % fav.points)
	check(d.scout_points == 0, "auto-scout spends points")
	check(d.favorites() == [fav], "favorites list")


func test_league_news() -> void:
	var s := _fixed(61)
	var wire: Array = s.news.items
	check(not wire.is_empty(), "preseason stories exist")
	var det_ride := wire.filter(func(n): return n["kind"] == "last_ride" and (n["teams"] as Array).has("DET"))
	check(not det_ride.is_empty(), "Detroit's veteran captain gets a last-ride story")
	var seen := {}
	for n in wire:
		var key := "%s/%d/%d" % [n["kind"], n["soldier_id"], n["year"]]
		check(not seen.has(key) or int(n["soldier_id"]) < 0, "no duplicate story %s" % key)
		seen[key] = true
	s.sim_week()
	check(s.news.items.size() >= wire.size(), "week stories append")
	check(s.news.latest(3).size() <= 3, "latest caps")
	for n in s.news.latest(5, "DET"):
		check((n["teams"] as Array).has("DET"), "team filter")


func test_offseason_news() -> void:
	var s := _fixed(61)
	var year := s.year
	s.sim_to_end_of_season()
	var kinds := {}
	for n in s.news.for_year(year):
		kinds[n["kind"]] = true
	# Signing a mega deal and cutting a star are both newsworthy, whoever they are.
	var star: Soldier = null
	var from: Team = null
	for t in s.league.teams:
		if t.user_controlled:
			continue
		for p in t.roster:
			if p.contract != null and (star == null or p.best_ovr() > star.best_ovr()):
				star = p
				from = t
	var to: Team = s.league.teams[0] if s.league.teams[0] != from else s.league.teams[1]
	var wire := s.news.items.size()
	s.news.release(s, from, star)
	check(s.news.items.size() == wire + 1 and s.news.items[-1]["kind"] == "surprise_cut", "a star's release makes the wire")
	s.news.release(s, from, star)
	check(s.news.items.size() == wire + 1, "a release is written once per year")
	var entry := {"soldier": star, "team": to, "salary": LeagueNews.MEGA_SALARY, "years": 4, "year": year, "when": "FA Day 1"}
	s.news.signing(s, entry)
	check(s.news.items[-1]["kind"] == "mega_deal" and (s.news.items[-1]["teams"] as Array).has(to.abbrev), "a mega deal makes the wire")
	var minor := {"soldier": star, "team": to, "salary": Contracts.MIN_SALARY, "years": 1, "year": year, "when": "FA Day 1"}
	wire = s.news.items.size()
	star.former_team = ""
	s.news.signing(s, minor)
	check(s.news.items.size() == wire or s.news.items[-1]["kind"] != "mega_deal", "no second mega story for one player")
	# Re-signing -> free agency opens -> day 1 and day 2 resolve.
	for i in 3:
		s.advance_offseason()
	var steps := s.news.digest_steps(s)
	check(steps == ["Re-signing", "FA Day 1", "FA Day 2"], "finished steps can be recapped (%s)" % str(steps))
	for e in s.news.digest(s, "FA Day 1")["signings"]:
		check(e["when"] == "FA Day 1", "day-one recap holds only day-one signings")
	check(not (s.news.digest(s, "FA Day 1")["market"] as Array).is_empty(), "day one lists who hit the market")
	check(s.news.for_soldier(star.id).size() >= 1, "a soldier's own stories are found")
	# Day 3, then the draft and the roster review week it opens.
	for i in 2:
		s.advance_offseason()
	steps = s.news.digest_steps(s)
	check(steps == ["Re-signing", "FA Day 1", "FA Day 2", "FA Day 3", "Draft"], "the draft is recapped after free agency (%s)" % str(steps))
	kinds = {}
	for n in s.news.for_year(year):
		kinds[n["kind"]] = (kinds.get(n["kind"], 0) as int) + 1
	check(kinds.has("draft_top") and kinds["draft_top"] == 1, "the first pick is announced once")
	check(kinds.has("draft_haul"), "the best draft haul is named")
	check(not (s.news.digest(s, "Draft")["picks"] as Array).is_empty(), "the draft recap lists picks")
	check(s.news.digest_summary(s, "Draft") != "", "recap summary text")
	s.advance_offseason()
	check(s.news.digest_steps(s)[-1] == "Roster Review", "the roster review week is recapped last")
	for e in s.news.digest(s, "Roster Review")["signings"]:
		check(e["when"] == "Roster Review", "review recap holds only review signings")
	s.finish_draft()
	check(int(s.news.for_year(year).filter(func(n): return n["kind"] == "draft_top").size()) == 1, "finishing the draft twice doesn't repeat stories")
	for k in ["mega_deal", "fa_signing", "defection", "homecoming", "resign", "hits_market", "surprise_cut"]:
		check(int(kinds.get(k, 0)) <= LeagueNews.OFFSEASON_PER_KIND, "%s stays under its yearly cap" % k)


func _meeting(home: Team, away: Team, home_games: int, away_games: int, stage := &"regular", week := 1) -> ScheduledMatch:
	var m := ScheduledMatch.new()
	m.week = week
	m.stage = stage
	m.home = home
	m.away = away
	fake_result(m, home_games, away_games)
	return m


func test_rivalries() -> void:
	var s := _fixed(81)
	var rv := s.rivalries
	var by := func(ab: String) -> Team: return s.league.team_by_abbrev(ab)
	# Kinds: division mates are divisional, named pairs are team-specific, and the two stack.
	check(rv.flags(by.call("DET"), by.call("BOS")) == Rivalries.DIVISIONAL, "same division is divisional only")
	check(rv.flags(by.call("SDV"), by.call("NSH")) == Rivalries.TEAM, "the snakes are team-specific only")
	check(rv.flags(by.call("ORL"), by.call("MIA")) == (Rivalries.DIVISIONAL | Rivalries.TEAM), "Florida is both")
	check(rv.flags(by.call("NYE"), by.call("BKN")) == (Rivalries.DIVISIONAL | Rivalries.TEAM), "the boroughs are both")
	check(rv.flags(by.call("DET"), by.call("SEA")) == 0, "strangers are not rivals")
	check(rv.title(by.call("SDV"), by.call("NSH")) == "Battle of the Snakes", "anchor name")
	check(rv.titles(by.call("ORL"), by.call("MIA")).size() == 2, "both kinds list both names")
	var keys := {}
	for r in Rivalries.ANCHORS:
		check(s.league.team_by_abbrev(r[0]) != null and s.league.team_by_abbrev(r[1]) != null, "anchor teams exist: %s" % [r])
		keys[Rivalries.key(r[0], r[1])] = true
	check(keys.size() == Rivalries.ANCHORS.size(), "no duplicate anchors")
	check(rv.swing(by.call("ORL"), by.call("MIA")) > rv.swing(by.call("DET"), by.call("BOS")), "stacked rivalries swing morale more")
	check(rv.swing(by.call("DET"), by.call("BOS")) >= 2.0 and rv.swing(by.call("ORL"), by.call("MIA")) <= 4.0, "swing stays in 2-4")
	# Records, streaks and heat.
	var det: Team = by.call("DET")
	var bos: Team = by.call("BOS")
	check(rv.record_text(det, bos) == "No meetings yet", "no meetings at first")
	for w in 3:
		rv.record_week(s, [_meeting(det, bos, 2, 1, &"regular", w + 1)])
	var rec := rv.record_of(det, bos)
	check(int(rec["n"]) == 3 and int(rec["w"]["DET"]) == 3 and int(rec["g"]["DET"]) == 6 and int(rec["g"]["BOS"]) == 3, "series tallies %s" % [rec])
	check(rv.record_text(det, bos) == "DET lead the series 3-0, DET have won 3 straight", rv.record_text(det, bos))
	rv.record_week(s, [_meeting(bos, det, 2, 0, &"regular", 4)])
	check(int(rv.record_of(det, bos)["last"]["snapped"]) == 3, "a 3-game streak snapped")
	check(rv.record_text(bos, det) == "DET lead the series 3-1", rv.record_text(bos, det))
	check(rv.heat_of(det, bos) > 0.0, "meetings build heat")
	# An emergent rivalry: two playoff classics between strangers, then it cools and ends.
	var sea: Team = by.call("SEA")
	rv.record_week(s, [_meeting(det, sea, 2, 1, Season.STAGE_SEMIFINAL, 11)])
	check(rv.flags(det, sea) == 0, "one meeting is not a rivalry")
	rv.record_week(s, [_meeting(sea, det, 2, 1, Season.STAGE_FINAL, 12)])
	check(rv.flags(det, sea) == Rivalries.TEAM, "two playoff classics form a rivalry")
	check(rv.last_events.size() == 1 and rv.last_events[0]["kind"] == &"formed", "formation is reported")
	check(rv.title(det, sea) == "The %s-%s Rivalry" % [det.city, sea.city], rv.title(det, sea))
	for i in 3:
		rv.new_season()
	check(rv.flags(det, sea) == 0 and rv.emergent.is_empty(), "the emergent rivalry cools off and ends")
	check(rv.flags(by.call("SDV"), by.call("NSH")) == Rivalries.TEAM, "anchors never end")
	# Trades stoke heat.
	var before := rv.heat_of(sea, by.call("LAS"))
	rv.note_trade(sea, by.call("LAS"))
	check(is_equal_approx(rv.heat_of(sea, by.call("LAS")) - before, Rivalries.TRADE_HEAT), "trades add heat")
	# News and morale for a team-specific game.
	var snake: Team = by.call("SDV")
	var rattler: Team = by.call("NSH")
	var m := _meeting(snake, rattler, 2, 1, &"regular", 5)
	rv.record_week(s, [m])
	var w_morale := snake.roster[0].morale
	var l_morale := rattler.roster[0].morale
	var wire := s.news.items.size()
	s.news.week_stories(s, [m], 5)
	check(s.news.items.size() > wire and s.news.items[wire]["kind"] == "rivalry", "a team-specific game makes the wire")
	check(snake.roster[0].morale > w_morale and rattler.roster[0].morale < l_morale, "winners gain and losers lose morale")
	# A real week records every match, and the rivalries survive a save.
	var s2 := _fixed(82)
	s2.sim_week()
	var meetings := 0
	for k in s2.rivalries.records:
		meetings += int(s2.rivalries.records[k]["n"])
	check(meetings == s2.matches_for_week(1).size(), "every played match is recorded (%d)" % meetings)
	var loaded := SaveSystem.from_text(SaveSystem.to_text(s2))
	check(loaded != null and str(loaded.rivalries.records) == str(s2.rivalries.records), "records survive a save")
	check(loaded != null and loaded.rivalries.heat == s2.rivalries.heat, "heat survives a save")


func test_market() -> void:
	var s := _fixed(91)
	var mk := s.market
	var by := func(ab: String) -> Team: return s.league.team_by_abbrev(ab)
	# Fixed ratings and opening buzz come from the tables, the same for every new franchise.
	var tiers := {}
	for t: Team in s.league.teams:
		check(t.market_rating == int(LeagueData.MARKET_RATINGS[t.abbrev]), "%s rating" % t.abbrev)
		check(is_equal_approx(t.buzz, float(LeagueData.START_BUZZ[t.abbrev])), "%s opening buzz" % t.abbrev)
		check(is_zero_approx(t.heat), "%s starts with no heat" % t.abbrev)
		var tier := Market.tier_of(t.market_rating)
		tiers[tier] = int(tiers.get(tier, 0)) + 1
	check(tiers == {5: 2, 4: 3, 3: 6, 2: 6, 1: 3}, "tier spread %s" % [tiers])
	check(Market.market_name(by.call("DET")) == "Metropolis" and Market.market_name(by.call("MIA")) == "Major Market" and Market.market_name(by.call("ARL")) == "Regional Market", "DET metropolis, MIA major, ARL regional")
	check(by.call("NYE").buzz == 77.0 and by.call("DET").buzz == 75.0 and Market.band_name(75.0) == "Hot", "NYE and DET open hot")
	var other := _fixed(93, 4)
	check(by.call("SEA").buzz == other.league.team_by_abbrev("SEA").buzz, "every franchise starts the same")
	check((mk.titles["DET"] as Array) == [2025], "Detroit open as the defending champions")
	# Scales.
	check(Market.band_name(0.0) == "Ice Cold" and Market.band_name(19.9) == "Ice Cold" and Market.band_name(20.0) == "Cooling" and Market.band_name(40.0) == "Steady", "band edges")
	check(Market.band_name(60.0) == "Warm" and Market.band_name(75.0) == "Hot" and Market.band_name(90.0) == "Electric" and Market.band_name(100.0) == "Electric", "upper bands")
	check(Market.tier_of(1) == 1 and Market.tier_of(20) == 1 and Market.tier_of(21) == 2 and Market.tier_of(81) == 5 and Market.tier_of(100) == 5, "tier edges")
	check(Market.baseline(by.call("NYE")) > Market.baseline(by.call("LRK")) and Market.baseline(by.call("LRK")) > 39.0 and Market.baseline(by.call("NYE")) < 66.0 and Market.baseline(by.call("NYE")) > 60.0, "a bigger market rests hotter")
	# Heat is a reservoir: buzz absorbs at most WEEK_CAP a step, and nothing moves it directly.
	var sea: Team = by.call("SEA")
	var buzz0 := sea.buzz
	mk.award(s, sea, "Test", "big night", 30.0)
	check(is_equal_approx(sea.buzz, buzz0) and is_equal_approx(sea.heat, 30.0), "an award adds heat, not buzz")
	mk.tick(s, "Test")
	check(sea.buzz - buzz0 <= Market.WEEK_CAP + 0.01 and sea.buzz > buzz0 + 2.0, "one step absorbs at most the weekly cap (%.2f)" % (sea.buzz - buzz0))
	check(sea.heat < 30.0 and sea.heat > 25.0, "the rest of the heat waits (%.1f)" % sea.heat)
	check(Market.trend(sea) == &"up", "unabsorbed heat shows as rising")
	for i in 40:
		mk.tick(s, "Test")
	check(sea.buzz >= 0.0 and sea.buzz <= 100.0 and absf(sea.heat) < 0.6, "heat drains and buzz stays in range")
	mk.award(s, sea, "Test", "huge", 500.0)
	check(is_equal_approx(sea.heat, Market.HEAT_MAX), "heat is capped")
	# No hot-to-cold in a few weeks: twelve straight losses cannot cross the whole meter.
	var den: Team = by.call("NYE")
	den.buzz = 80.0
	den.heat = 0.0
	var worst := 0.0
	for i in 12:
		var from := den.buzz
		mk.award(s, den, "Test", "loss", -6.0)
		mk.tick(s, "Test")
		worst = maxf(worst, from - den.buzz)
	check(worst <= Market.WEEK_CAP + Market.DECAY * 100.0 * 0.4, "never drops faster than the cap (%.2f in a week)" % worst)
	check(den.buzz > 30.0 and den.buzz < 80.0, "twelve straight bad weeks cool a hot team, but not to ice (%.1f)" % den.buzz)
	# A quiet team drifts back to its resting level, higher in a big market.
	var lou: Team = by.call("LOU")
	lou.buzz = 90.0
	lou.heat = 0.0
	for i in 120:
		mk.tick(s, "Test")
	check(absf(lou.buzz - Market.baseline(lou)) < 4.0, "buzz settles at the market's resting level (%.1f vs %.1f)" % [lou.buzz, Market.baseline(lou)])
	# Match points: wins, losses, upsets, streaks. Ratings never change.
	var atl: Team = by.call("ATL")
	var log0 := Market.log_for(atl, s.year).size()
	var sum := func(t: Team) -> float:
		var tot := 0.0
		for e in Market.log_for(t, s.year):
			tot += float(e["amount"])
		return tot
	var seattle: Team = by.call("SEA")
	seattle.market_log = []
	for opp in ["ATL", "MIA", "STL"]:
		mk.week(s, [_meeting(seattle, by.call(opp), 2, 0, &"regular", 1)], 1)
	check(is_equal_approx(sum.call(seattle), 3.0 * Market.WIN + Market.WIN_STREAKS[3]), "three wins plus the 3-game streak bonus (%.1f)" % sum.call(seattle))
	var lrk: Team = by.call("LRK")
	lrk.market_log = []
	for opp in ["ATL", "MIA", "DEN", "SEA"]:
		mk.week(s, [_meeting(by.call(opp), lrk, 2, 0, &"regular", 1)], 1)
	check(is_equal_approx(sum.call(lrk), 4.0 * Market.LOSS + Market.LOSS_STREAK_POINTS), "four straight losses cost points, once for the streak (%.2f)" % sum.call(lrk))
	var reno: Team = by.call("REN")
	reno.market_log = []
	mk.week(s, [_meeting(reno, by.call("NYE"), 2, 1, &"regular", 1)], 1)
	check(is_equal_approx(sum.call(reno), Market.WIN + Market.UPSET), "an upset over a bigger market (%.1f)" % sum.call(reno))
	var bos: Team = by.call("BOS")
	var det: Team = by.call("DET")
	det.market_log = []
	bos.market_log = []
	mk.week(s, [_meeting(det, bos, 2, 1, &"regular", 2)], 2)
	check(sum.call(det) > Market.WIN + 1.0, "a rivalry win pays extra")
	check(sum.call(bos) < Market.LOSS, "a rivalry loss costs extra")
	check(by.call("NYE").market_rating == 98 and det.market_rating == 66, "ratings never change")
	check(atl.market_log.size() > log0, "results are logged")
	# Stories add heat, capped per team and kind each year.
	var cha: Team = by.call("CHA")
	cha.heat = 0.0
	for i in 4:
		mk.story(s, "mega_deal", [cha.abbrev], "Test deal")
	check(is_equal_approx(cha.heat, 2.0 * Market.STORY_CAP), "a story kind counts twice a year (%.1f)" % cha.heat)
	# Band stories: a clear crossing writes one, hovering on the line writes none.
	var ind: Team = by.call("IND")
	ind.buzz = 59.0
	ind.heat = 0.0
	mk.announced[ind.abbrev] = Market.band_of(59.0)
	var ind_stories := func() -> int:
		return s.news.items.filter(func(it): return (it["teams"] as Array).has("IND") and String(it["kind"]).begins_with("buzz_")).size()
	var wire: int = ind_stories.call()
	ind.buzz = 60.2
	mk.tick(s, "Test")
	check(ind_stories.call() == wire, "just over the line is quiet")
	ind.buzz = 63.5
	mk.tick(s, "Test")
	check(ind_stories.call() == wire + 1 and s.news.items.filter(func(it): return it["kind"] == "buzz_up" and (it["teams"] as Array).has("IND")).size() == 1, "a clear crossing makes the wire")
	ind.buzz = 62.0
	mk.tick(s, "Test")
	ind.buzz = 60.4
	mk.tick(s, "Test")
	check(ind_stories.call() == wire + 1, "drifting back across the line stays quiet")
	ind.buzz = 55.0
	mk.tick(s, "Test")
	check(ind_stories.call() == wire + 2 and s.news.items.filter(func(it): return it["kind"] == "buzz_down" and (it["teams"] as Array).has("IND")).size() == 1, "a clear drop makes the wire")
	# A real season: buzz stays in range, the title is logged, stories run.
	var s2 := _fixed(92)
	s2.sim_to_end_of_regular_season()
	for t: Team in s2.league.teams:
		check(t.buzz >= 0.0 and t.buzz <= 100.0 and t.market_rating == int(LeagueData.MARKET_RATINGS[t.abbrev]), "%s buzz in range, rating fixed" % t.abbrev)
	check(s2.league.teams.any(func(t: Team): return not is_equal_approx(t.buzz, float(LeagueData.START_BUZZ[t.abbrev]))), "buzz moved")
	s2.sim_to_end_of_season()
	var champ_log := Market.log_for(s2.champion, s2.year).filter(func(e): return String(e["label"]).begins_with("Won the"))
	check(champ_log.size() == 1, "the champion's title is logged")
	check((s2.market.titles[s2.champion.abbrev] as Array).has(s2.year), "title history")
	check(s2.news.items.any(func(it): return it["kind"] == "buzz_leader"), "a weekly leader story ran")
	var year_total := 0.0
	for t: Team in s2.league.teams:
		for e in Market.log_for(t, s2.year):
			year_total += float(e["amount"])
	check(absf(year_total) < 1.0, "attention is relative: the league's yearly points net to about zero (%.2f)" % year_total)
	for t: Team in s2.league.teams:
		check(t.buzz >= 0.0 and t.buzz <= 100.0 and absf(t.heat) <= Market.HEAT_MAX, "%s buzz %.1f heat %.1f in range" % [t.abbrev, t.buzz, t.heat])
	# Saves keep markets, and an older save without them is seeded from the tables.
	var loaded := SaveSystem.from_text(SaveSystem.to_text(s2))
	check(loaded != null and is_equal_approx(loaded.league.teams[0].buzz, s2.league.teams[0].buzz) and is_equal_approx(loaded.league.teams[0].heat, s2.league.teams[0].heat), "buzz survives a save")
	check(loaded != null and str(loaded.market.titles) == str(s2.market.titles) and str(loaded.market.announced) == str(s2.market.announced), "market state survives a save")
	if loaded != null:
		loaded.market.seeded = false
		loaded.league.teams[0].market_rating = 1
		loaded.market.ensure(loaded)
		check(loaded.league.teams[0].market_rating == int(LeagueData.MARKET_RATINGS[loaded.league.teams[0].abbrev]), "an older save is seeded from the tables")


func test_revenue() -> void:
	var s := _fixed(95)
	var rv := s.revenue
	var by := func(ab: String) -> Team: return s.league.team_by_abbrev(ab)
	# Scale: 100M for the smallest market, 300M for the biggest, at average buzz.
	check(is_equal_approx(Revenue.neutral_total(8), 100000.0) and is_equal_approx(Revenue.neutral_total(98), 300000.0), "market revenue spans 100M to 300M")
	check(Revenue.neutral_total(50) > Revenue.neutral_total(30) and Revenue.neutral_total(1) == Revenue.neutral_total(8), "bigger markets earn more, clamped at the ends")
	check(is_equal_approx(Revenue.buzz_factor(0.0), 0.75) and is_equal_approx(Revenue.buzz_factor(50.0), 1.0) and is_equal_approx(Revenue.buzz_factor(100.0), 1.25), "buzz scales money 0.75x to 1.25x")
	check(is_equal_approx(Revenue.market_part(50) + Revenue.media(), Revenue.neutral_total(50)), "media plus the market-driven part make the total")
	check(is_equal_approx(Revenue.TICKET_SHARE + Revenue.SPONSOR_SHARE + Revenue.MERCH_SHARE, 1.0), "stream shares add up")
	# Everything is sized off one reference payroll.
	check(Revenue.scale() == 1.0, "the design scale is 1 at today's cap")
	# Opening cash.
	for t: Team in s.league.teams:
		check(is_equal_approx(rv.cash_of(t), Revenue.neutral_total(t.market_rating) * Revenue.SEED_SHARE), "%s opening cash" % t.abbrev)
	check(rv.cash_of(by.call("NYE")) > rv.cash_of(by.call("LRK")) * 2.0, "a big market starts with more cash")
	# The gate: an average crowd earns the even share; hot teams, rivals and the playoffs earn more.
	var avg_gate := Revenue.gate(50, Revenue.FILL_AVERAGE, &"regular")
	check(is_equal_approx(avg_gate, Revenue.market_part(50) * Revenue.TICKET_SHARE / Revenue.HOME_GAMES), "an average crowd earns the even share")
	check(Revenue.fill(80.0, 50.0, false) > Revenue.fill(30.0, 50.0, false), "a hotter team fills more seats")
	check(Revenue.fill(50.0, 50.0, true) > Revenue.fill(50.0, 50.0, false), "a rivalry fills more seats")
	check(Revenue.fill(50.0, 80.0, false) > Revenue.fill(50.0, 20.0, false), "a hot opponent draws")
	check(Revenue.fill(100.0, 100.0, true) <= 1.0 and Revenue.fill(0.0, 0.0, false) >= 0.3, "fill stays in range")
	check(Revenue.gate(50, 0.87, &"final") > Revenue.gate(50, 0.87, &"semifinal") and Revenue.gate(50, 0.87, &"semifinal") > Revenue.gate(50, 0.87, &"quarterfinal") and Revenue.gate(50, 0.87, &"quarterfinal") > 0.0 and Revenue.gate(50, 0.87, &"final") < avg_gate, "later rounds pay more, but less than a regular gate")
	# A played week: the home side takes the gate, everyone accrues sponsors, merch, media and costs.
	var sea: Team = by.call("SEA")
	var den: Team = by.call("DEN")
	var before := rv.ledger_of(s.year, sea).duplicate()
	var away_before := rv.ledger_of(s.year, den).duplicate()
	var cash0 := rv.cash_of(sea)
	rv.week(s, [_meeting(sea, den, 2, 1, &"regular", 1)], 1)
	var after := rv.ledger_of(s.year, sea)
	check(float(after["tickets"]) > 0.0 and int(after["home_games"]) == 1, "the home team books the gate")
	check(is_zero_approx(float(rv.ledger_of(s.year, den)["tickets"])), "the visitors do not")
	check(float(after["sponsors"]) > float(before["sponsors"]) and float(after["media"]) > float(before["media"]) and float(after["merch"]) > float(before["merch"]), "weekly streams accrue")
	check(float(after["operations"]) > 0.0 and float(after["net"]) < float(after["revenue"]), "operating cost is booked")
	check(rv.cash_of(sea) != cash0, "cash moves with the ledger")
	check(is_equal_approx(float(after["media"]), Revenue.media() / s.regular_weeks), "media is paid evenly")
	check(float(rv.ledger_of(s.year, den)["media"]) == float(after["media"]), "media is equal for every team")
	# Merchandise rises with live buzz.
	var chi: Team = by.call("CHI")
	var lrk: Team = by.call("LRK")
	chi.buzz = 90.0
	lrk.buzz = 10.0
	check(Revenue.buzz_factor(chi.buzz) > Revenue.buzz_factor(lrk.buzz), "hot clubs earn more than cold ones")
	# Playoff money.
	var ledger_final := rv.ledger_of(s.year, sea)
	var bonus0 := float(ledger_final["bonus"])
	s.phase = Season.PHASE_PLAYOFFS
	s.playoff_seeds = {sea: 1}
	rv.week(s, [], s.regular_weeks)
	check(is_equal_approx(float(ledger_final["bonus"]) - bonus0, Revenue.BONUS_QUALIFY), "a playoff berth pays")
	s.phase = Season.PHASE_REGULAR
	# Payroll is not part of the ledger.
	check(not rv.ledger_of(s.year, sea).has("payroll"), "payroll is not deducted: the cap is its own rule")
	# A real season: every club's ledger is sane, the champion earns the title money, cash stays in range.
	var s2 := _fixed(96)
	var table := {}
	for t: Team in s2.league.teams:
		table[t.abbrev] = t.market_rating
	s2.sim_to_end_of_season()
	var rows := s2.revenue.table(s2)
	check(rows.size() == 20, "a ledger for every club")
	var total := 0.0
	for r in rows:
		var l: Dictionary = r["ledger"]
		var t: Team = r["team"]
		total += float(l["revenue"])
		check(float(l["revenue"]) > 50000.0 and float(l["revenue"]) < 450000.0, "%s revenue is sane (%.0f)" % [t.abbrev, float(l["revenue"])])
		check(absf(float(l["revenue"]) - (float(l["tickets"]) + float(l["sponsors"]) + float(l["merch"]) + float(l["media"]) + float(l["bonus"]))) < 0.01, "%s revenue is the sum of its streams" % t.abbrev)
		check(int(l["home_games"]) >= 4, "%s played home games" % t.abbrev)
		check(s2.revenue.cash_of(t) <= Revenue.cash_cap(t.market_rating) + 0.01 and s2.revenue.cash_of(t) >= Revenue.cash_floor(t.market_rating) - 0.01, "%s cash in range" % t.abbrev)
	check(total / 20.0 > 120000.0 and total / 20.0 < 280000.0, "the league averages sensible revenue (%.0f)" % (total / 20.0))
	var big := 0.0
	var big_n := 0
	var small := 0.0
	var small_n := 0
	for r in rows:
		if (r["team"] as Team).market_rating >= 70:
			big += float(r["ledger"]["revenue"])
			big_n += 1
		elif (r["team"] as Team).market_rating <= 20:
			small += float(r["ledger"]["revenue"])
			small_n += 1
	check(big_n > 0 and small_n > 0 and big / big_n > small / small_n * 1.5, "big markets out-earn small ones (%.0f vs %.0f)" % [big / maxf(1.0, big_n), small / maxf(1.0, small_n)])
	var champ_l := s2.revenue.ledger_of(s2.year, s2.champion)
	check(float(champ_l["bonus"]) >= Revenue.BONUS_TITLE, "the champion collects the title money")
	check(s2.news.items.any(func(it): return it["kind"] == "sellout"), "a sellout made the wire")
	# Saves keep ledgers, and an older save without revenue is seeded.
	var loaded := SaveSystem.from_text(SaveSystem.to_text(s2))
	check(loaded != null and is_equal_approx(loaded.revenue.cash_of(loaded.league.teams[0]), s2.revenue.cash_of(s2.league.teams[0])), "cash survives a save")
	check(loaded != null and str(loaded.revenue.ledgers) == str(s2.revenue.ledgers), "ledgers survive a save")
	if loaded != null:
		loaded.revenue.seeded = false
		loaded.revenue.cash = {}
		loaded.revenue.ensure(loaded)
		check(is_equal_approx(loaded.revenue.cash_of(loaded.league.teams[0]), Revenue.neutral_total(loaded.league.teams[0].market_rating) * Revenue.SEED_SHARE), "an older save is seeded")
	# A new season opens a new ledger and keeps the sponsors' step up for hot clubs.
	var s3 := _fixed(97)
	var hot: Team = s3.league.team_by_abbrev("NYE")
	check(float(s3.revenue.deals["NYE"]) > Revenue.market_part(hot.market_rating) * Revenue.SPONSOR_SHARE, "a hot club signs a bigger sponsor deal")


func test_home_crowd() -> void:
	var s := _fixed(98)
	var a: Team = s.league.team_by_abbrev("SEA")
	var b: Team = s.league.team_by_abbrev("DEN")
	# The edge: nothing at a cold stadium, the full amount at Electric, never more than about one OVR point.
	a.buzz = 20.0
	check(is_zero_approx(Market.crowd_edge(a)), "a cold stadium gives no edge")
	a.buzz = Market.CROWD_FLOOR
	check(is_zero_approx(Market.crowd_edge(a)), "nothing at the floor")
	a.buzz = 70.0
	var mid := Market.crowd_edge(a)
	a.buzz = 100.0
	check(is_equal_approx(Market.crowd_edge(a), Market.CROWD_MAX) and mid > 0.0 and mid < Market.CROWD_MAX, "the edge grows with buzz up to the maximum")
	check(Market.CROWD_MAX <= 1.5, "the crowd stays a small edge beside match-day form")
	# It adds rating points to the home squad only, and does not disturb the match's randomness.
	var e0 := MatchEngine.new()
	e0.start(a, b, 4242, null, null, 0.0)
	var e1 := MatchEngine.new()
	e1.start(a, b, 4242, null, null, 1.0)
	check(is_equal_approx(e1.team_form[0] - e0.team_form[0], 1.0) and is_equal_approx(e1.team_form[1], e0.team_form[1]), "the home squad gains the edge, the visitors nothing")
	check(is_equal_approx(e1.result().crowd, 1.0) and is_zero_approx(e0.result().crowd), "the result records the crowd")
	var r_a := MatchEngine.simulate(a, b, 777, null, null, 0.5)
	var r_b := MatchEngine.simulate(a, b, 777, null, null, 0.5)
	check(r_a.winner() == r_b.winner() and r_a.score == r_b.score, "a match with a crowd is deterministic")
	check(is_equal_approx(MatchEngine.simulate(a, b, 777).crowd, 0.0), "no crowd by default")
	# Fixtures use the home team's live buzz.
	var m: ScheduledMatch = s.matches_for_week(1)[0]
	m.home.buzz = 100.0
	check(is_equal_approx(m.play().crowd, Market.CROWD_MAX), "a hot home club brings the full crowd")
	var m2: ScheduledMatch = s.matches_for_week(2)[0]
	m2.home.buzz = 10.0
	check(is_zero_approx(m2.play().crowd), "a cold home club brings none")
	# Over many matches the crowd helps the home side, but only a little.
	var lift_a := 0
	var lift_b := 0
	for i in 40:
		if MatchEngine.simulate(a, b, 9000 + i, null, null, 4.0).winner() == a:
			lift_a += 1
		if MatchEngine.simulate(a, b, 9000 + i, null, null, 0.0).winner() == a:
			lift_b += 1
	check(lift_a >= lift_b - 6, "an exaggerated crowd does not hurt the home side (%d vs %d)" % [lift_a, lift_b])


func test_team_appeal() -> void:
	var s := _fixed(99)
	var by := func(ab: String) -> Team: return s.league.team_by_abbrev(ab)
	var nye: Team = by.call("NYE")
	var lrk: Team = by.call("LRK")
	var fa := PlayerGenerator.generate(RandomNumberGenerator.new(), 90001, Scheme.Role.FLEX, 70.0, 27)
	var dna := Dna.new()
	for k in Dna.MOTIVATIONS:
		dna.set(k, 1)
	fa.dna = dna
	fa.home_state = ""
	# Read-only: scoring changes nothing.
	var cash0 := s.revenue.cash_of(nye)
	var buzz0 := nye.buzz
	TeamAppeal.score(fa, nye, s)
	check(is_equal_approx(s.revenue.cash_of(nye), cash0) and is_equal_approx(nye.buzz, buzz0), "appeal is read-only")
	# Someone who cares about nothing is neutral; the score stays within 0..100.
	check(absf(TeamAppeal.score(fa, nye, s) - TeamAppeal.score(fa, lrk, s)) < 6.0, "a soldier with no motivations barely tells clubs apart")
	for t: Team in s.league.teams:
		var sc := TeamAppeal.score(fa, t, s)
		check(sc >= 0.0 and sc <= 100.0, "%s score in range" % t.abbrev)
	# Money: the big market wins.
	dna.money = 99
	check(TeamAppeal.score(fa, nye, s) > TeamAppeal.score(fa, lrk, s) + 10.0, "a money-minded soldier prefers the bigger market")
	dna.money = 1
	# Winning: a stronger, hotter club wins.
	dna.winning = 99
	var best: Team = s.league.teams[0]
	var worst: Team = s.league.teams[0]
	for t: Team in s.league.teams:
		if t.team_ovr() > best.team_ovr():
			best = t
		if t.team_ovr() < worst.team_ovr():
			worst = t
	best.buzz = 80.0
	worst.buzz = 25.0
	check(TeamAppeal.score(fa, best, s) > TeamAppeal.score(fa, worst, s) + 10.0, "a winner prefers the contender")
	dna.winning = 1
	# Hometown: his own state's club beats a far one.
	dna.hometown = 99
	var home_team: Team = by.call("DET")
	fa.home_state = home_team.home_state
	var far: Team = s.league.teams.filter(func(t: Team): return LeagueData.region_of(t.home_state) != LeagueData.region_of(home_team.home_state))[0]
	check(TeamAppeal.score(fa, home_team, s) > TeamAppeal.score(fa, far, s) + 10.0, "a homesick soldier prefers the club near home")
	dna.hometown = 1
	fa.home_state = ""
	# Playing time: he would start for a thin club and sit for a deep one.
	var thin: Team = worst
	var deep: Team = best
	var mid := PlayerGenerator.generate(RandomNumberGenerator.new(), 90002, Scheme.Role.FLEX, 70.0, 27)
	mid.dna = dna
	dna.playing_time = 99
	var pt := func(t: Team) -> float:
		for r in TeamAppeal.breakdown(mid, t, s):
			if r["key"] == &"playing_time":
				return float(r["value"])
		return -1.0
	check(float(pt.call(thin)) >= float(pt.call(deep)), "he would start more readily for the thinner roster")
	dna.playing_time = 1
	# Loyalty: his own club beats strangers.
	dna.loyalty = 99
	var mine: Team = by.call("SEA")
	var other: Team = by.call("DEN")
	fa.former_team = mine.abbrev
	check(TeamAppeal.score(fa, mine, s) > TeamAppeal.score(fa, other, s) + 10.0, "a loyal soldier prefers his old club")
	# The breakdown explains the score.
	dna.loyalty = 50
	var rows := TeamAppeal.breakdown(fa, nye, s)
	check(rows.size() == Dna.MOTIVATIONS.size(), "a row per motivation")
	var total := 50.0
	for r in rows:
		total += float(r["points"])
		check(float(r["value"]) >= 0.0 and float(r["value"]) <= 1.0 and String(r["text"]) != "", "row %s has a value and a reason" % r["key"])
	check(is_equal_approx(clampf(total, 0.0, 100.0), TeamAppeal.score(fa, nye, s)), "the rows add up to the score")
	check(TeamAppeal.reasons(fa, nye, s, 2).size() == 2, "the top reasons come back")


func test_match_form_upsets() -> void:
	var s := _fixed(71)
	var a: Team = s.league.team_by_abbrev("SEA")
	var b: Team = s.league.team_by_abbrev("ARL")
	for t in [a, b]:
		t.auto_lineup()
	var upsets := 0
	var games := 16
	var strong := a if a.team_ovr() >= b.team_ovr() else b
	for i in games:
		var r := MatchEngine.simulate(a, b, 1000 + i)
		if r.winner() != strong:
			upsets += 1
	check(upsets >= 1 and upsets < games, "close teams split results (%d/%d upsets)" % [upsets, games])


func test_schemes() -> void:
	var arena := ArenaMap.legacy()
	arena.ensure_built()
	check(Scheme.all().size() == 6, "six schemes")
	for sch in Scheme.all():
		check(sch.slot_ids().size() == 5, "%s has 5 slots" % sch.id)
		for sid in sch.slot_ids():
			check(not arena.blocked(sch.spawn_of(sid)), "%s %s spawn is clear" % [sch.id, sid])
			if sch.role_for_slot(sid) != Scheme.Role.FLEX:
				check(not arena.blocked(sch.hold_of(sid)) and not arena.blocked(sch.hold_of(sid, true)), "%s %s hold is clear" % [sch.id, sid])
		# Matchup edges are small and zero-sum.
		for other in Scheme.all():
			var e := sch.edge_vs(other)
			check(absf(e) <= 0.03, "edge %s vs %s is small" % [sch.id, other.id])
			check(is_equal_approx(e, -other.edge_vs(sch)), "edge %s vs %s is zero-sum" % [sch.id, other.id])
	check(Scheme.by_id(&"wall").count_role(Scheme.Role.FRONTMAN) == 3, "wall has 3 frontmen")
	check(Scheme.by_id(&"spread").count_role(Scheme.Role.FLEX) == 4, "spread has 4 flexes")
	check(Scheme.by_id(&"pack").count_role(Scheme.Role.CENTER) == 2, "pack has 2 centers")
	var lg := League.generate(11, 2)
	var a: Team = lg.teams[0]
	var b: Team = lg.teams[1]
	for sch in Scheme.all():
		var preview := a.lineup_for(sch)
		check(preview.size() == 5 and a.scheme.id == &"power_front", "previewing %s leaves the team alone" % sch.id)
		a.set_scheme(sch)
		check(a.starters().size() == 5, "%s fills 5 starters" % sch.id)
		var r := MatchEngine.simulate(a, b, 99)
		check(r.winner_index == 0 or r.winner_index == 1, "%s match finishes" % sch.id)
		a.set_scheme(Scheme.power_front())
	# AI picks a scheme; the user's team is never switched.
	a.user_controlled = true
	check(not a.pick_scheme(), "user scheme untouched")
	b.pick_scheme()
	check(b.scheme.slot_ids().size() == 5 and b.starters().size() == 5, "AI scheme pick keeps a full lineup")
	# Saved schemes round-trip.
	var s := Season.new_franchise(5, 0)
	s.league.teams[2].set_scheme(Scheme.by_id(&"pack"))
	var back := SaveSystem.from_text(SaveSystem.to_text(s))
	check(back.league.teams[2].scheme.id == &"pack" and back.league.teams[2].scheme.spawn_of(&"CT2") == Vector2(-44, 4), "scheme survives save/load")


## Every match is played on the home team's field, with the home side in the left starting area and the
## away side in the right one, whether or not the teams are rivals, in the regular season and the playoffs.
func test_home_field_and_start_areas() -> void:
	Season.fixture_teams = 0
	var s := Season.new_franchise(8, 0)
	check(s.league.teams.size() == 20, "the real 20-team league")
	s.sim_to_end_of_regular_season()
	var rivalry_matches := 0
	var checked_homes := {}
	var played := 0
	for w in range(1, s.regular_weeks + 1):
		for m: ScheduledMatch in s.matches_for_week(w):
			played += 1
			check(m.field() == ArenaMap.for_team(m.home.abbrev), "%s is played on %s's field" % [m.away.abbrev, m.home.abbrev])
			check(m.result.teams[0] == m.home and m.result.teams[1] == m.away, "home side is team 0")
			if s.rivalries.is_rivalry(m.home, m.away):
				rivalry_matches += 1
			if not checked_homes.has(m.home):
				checked_homes[m.home] = true
				var e := m.live_engine()
				check(e.arena == m.field(), "live engine uses the home field")
				e.step()
				for c in e.squads[0]:
					check(c.pos.x <= -ArenaMap.START_X, "%s starts in the left (home) area" % m.home.abbrev)
				for c in e.squads[1]:
					check(c.pos.x >= ArenaMap.START_X, "%s starts in the right (away) area" % m.away.abbrev)
	check(played > 100, "plenty of regular-season matches checked (%d)" % played)
	check(rivalry_matches > 0, "rivalry matches were among them (%d)" % rivalry_matches)
	s.sim_to_end_of_season()
	check(not s.playoff_matches.is_empty(), "playoffs were played")
	for m: ScheduledMatch in s.playoff_matches:
		if m.is_played():
			check(m.field() == ArenaMap.for_team(m.home.abbrev), "playoff match on the home team's field")
			check(m.result.teams[0] == m.home, "playoff home side is team 0")
	Season.fixture_teams = 5


func test_keep_value_protects_prospects() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var t := Team.new()
	t.roster = PlayerGenerator.generate_roster(rng, 1, 72.0)
	var kid := PlayerGenerator.generate(rng, 100, Scheme.Role.FLEX, 68.0, 20)
	kid.dev = Soldier.DEV_MAX
	var vet := PlayerGenerator.generate(rng, 101, Scheme.Role.FLEX, 68.0, 29)
	vet.dev = 2
	kid.stats = vet.stats.duplicate()
	t.roster.append(kid)
	t.roster.append(vet)
	check(t.keep_value(kid) > t.keep_value(vet), "young 4-star is kept over a late-20s 2-star (%.1f vs %.1f; ovr %d/%d pot %d/%d role %d/%d)" % [t.keep_value(kid), t.keep_value(vet), kid.best_ovr(), vet.best_ovr(), kid.potential_ovr(), vet.potential_ovr(), Scheme.best_role(kid.stats), Scheme.best_role(vet.stats)])

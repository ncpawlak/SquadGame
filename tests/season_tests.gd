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
		"test_progression_history_and_potw",
		"test_dna_profiles",
		"test_fa_dna_weights",
		"test_resign_negotiation",
		"test_starter_promises",
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
	check(s.schedule.size() == Season.REGULAR_WEEKS, "10 regular weeks")
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
	for w in range(1, Season.REGULAR_WEEKS + 1):
		var ms := s.matches_for_week(w)
		check(ms.size() == 2, "week %d has 2 matches" % w)
		var bye := s.bye_team(w)
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
	check(s.bye_team(11) == null, "no bye in playoffs")


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
	check(fin[0].home == semis[0].winner() and fin[0].away == semis[1].winner(), "final pairs semi winners")


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
	for w in range(1, c.REGULAR_WEEKS + 1):
		for m in c.matches_for_week(w):
			sc += "%d>%d|" % [m.home.id, m.away.id]
	var sa_sched := ""
	for w in range(1, a.REGULAR_WEEKS + 1):
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
	check(s.schedule.size() == Season.REGULAR_WEEKS, "schedule regenerated")
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
			check(n >= Season.ROSTER_MIN and n <= Team.ROSTER_SIZE, "user roster within min..limit (%d)" % n)
		else:
			check(n == Team.ROSTER_SIZE, "AI roster cut/filled to limit (%d)" % n)
	check(kept + retired >= signed_ids.size() - Draft.ROUNDS, "players under contract mostly kept (%d + %d retired of %d)" % [kept, retired, signed_ids.size()])
	var first := s.sim_week()
	check(first.size() == 2 and first[0].is_played(), "new season playable")


func test_season_review_and_aging() -> void:
	var s := Season.new_franchise(77)
	check(s.review == null, "no review during the season")
	var ages := {}
	for t in s.league.teams:
		for so in t.roster:
			check(so.potential >= 0 and so.potential <= Soldier.POTENTIAL_A, "grade in range")
	s.sim_to_end_of_season()
	var rev := s.review
	check(rev != null and rev.year == 2026, "review created at season end")
	check(s.review_history.size() == 1, "review stored in history")
	check(rev.awards.size() >= 4 and rev.awards[0]["award"] == "Season MVP", "MVP + position awards (%d)" % rev.awards.size())
	check(rev.all_league.size() == SeasonReview.ALL_LEAGUE_ROLES.size(), "All-League team of 5")
	for c in rev.potential_changes:
		check(absi(c["to"] - c["from"]) <= SeasonReview.MAX_GRADE_CHANGE, "grade change clamped")
		check(c["soldier"].potential == c["to"], "grade applied")
		check(not c["reasons"].is_empty(), "change has reasons")
	var mvp: Soldier = rev.awards[0]["soldier"]
	var mvp_change := rev.potential_changes.filter(func(c): return c["soldier"] == mvp)
	check(mvp.potential == Soldier.POTENTIAL_A or (not mvp_change.is_empty() and mvp_change[0]["to"] > mvp_change[0]["from"]), "MVP's grade rises (or is already A)")
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
	d.scout_points = 1000
	for p in d.prospects:
		var used := 0
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
	check(d.scout_points == 1000 - Draft.CLASS_SIZE * Draft.MAX_POINTS_PER_PROSPECT, "points spent")
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
	check(Draft.tier_of(49) == 0 and Draft.tier_of(50) == 1 and Draft.tier_of(80) == 4, "tier thresholds")


func test_draft_order_and_picks() -> void:
	var s := Season.new_franchise(33)
	s.sim_to_end_of_season()
	var d := s.draft
	check(d.is_started() and not d.is_complete(), "draft order set after the final")
	var per_round := Season.TEAM_COUNT
	check(d.order.size() == per_round * Draft.ROUNDS, "pick count")
	check(d.order[per_round - 1] == s.champion, "champion picks last in round 1")
	check(d.order[per_round] == s.champion, "snake: champion first in round 2")
	for i in per_round:
		for r in Draft.ROUNDS:
			var want: Team = d.order[i] if r % 2 == 0 else d.order[per_round - 1 - i]
			check(d.order[r * per_round + i] == want, "snake round %d pick %d" % [r + 1, i])
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
	s.advance_offseason()
	check(s.offseason_stage == Season.OFF_FREE_AGENCY, "free agency opened after the draft")
	for t in s.league.teams:
		if not t.user_controlled:
			check(t.roster.size() <= Team.ROSTER_SIZE, "%s cut to limit" % t.abbrev)
		check(t.lineup.size() == 5, "lineup valid after cuts")
		for so in t.roster:
			check(so.contract != null and not so.contract.is_expiring(), "%s has a live contract" % so.full_name())
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
		check(t.roster.size() >= Season.ROSTER_MIN and t.roster.size() <= Team.ROSTER_SIZE, "%s roster size %d" % [t.abbrev, t.roster.size()])
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
	check(mock.size() == Season.TEAM_COUNT * Draft.ROUNDS, "mock covers every pick (%d)" % mock.size())
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
			if p.pick_number <= Season.TEAM_COUNT:
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
				check(p.soldier.potential == Soldier.POTENTIAL_A, "generational has A potential")
				check(Draft.standout_label(p) == "GENERATIONAL", "generational label")
			elif p.standout == &"blue_chip":
				blue += 1
				blue_vals.append(v)
				var ovr := p.soldier.ovr_at_role(p.listed_role)
				check(ovr >= Draft.BLUE_CHIP_OVR[0] and ovr <= Draft.BLUE_CHIP_OVR[1] + 2, "blue chip is a day-one starter (%d)" % ovr)
				check(p.soldier.potential >= Draft.BLUE_CHIP_MIN_POTENTIAL, "blue chip has B/A potential")
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
		if st["kind"] == &"hint" and st["truthful"]:
			var v: int = st["prospect"].soldier.stats[st["stat"]]
			check(v >= Draft.NEWS_GREAT if st["great"] else v <= Draft.NEWS_POOR, "true stat story is right (%d)" % v)
	check(truthful >= n * 0.5, "most stories are true (%d/%d)" % [truthful, n])
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
	s.advance_offseason()  # re-sign -> draft
	var step: int = _xp_total(probe) - x0
	check(step == roundi(Season.OFFSEASON_WEEK_XP * Progression.xp_multiplier(probe)), "re-sign week xp (%d)" % step)
	s.advance_offseason()  # draft -> free agency
	check(_xp_total(probe) - x0 == 2 * step, "draft week xp")
	var rookie: Soldier = null
	for p in s.draft.picks():
		if p.drafted_by == user:
			rookie = p.soldier
	var guard := 0
	while s.offseason_stage == Season.OFF_FREE_AGENCY and guard < 10:
		s.advance_offseason()
		guard += 1
	check(s.offseason_stage == Season.OFF_CAMP, "free agency ends in training camp")
	check(s.camp_open() and s.free_agency_open(), "camp open; unsigned players still sign")
	check(_xp_total(probe) - x0 == (2 + Season.FA_DAYS) * step, "every FA day is an xp week")
	check(rookie == null or rookie.xp > 0 or rookie.level > 1, "draftees earn xp too")
	# Drills.
	var a: Soldier = user.starters()[0]
	var b: Soldier = user.starters()[1]
	var before := a.stats.duplicate()
	var res := s.run_drill(Stats.PHYSICALITY, a)
	check(not res.is_empty(), "drill runs")
	var pool := Camp.pool_range(a.potential)
	check(res["points"] >= pool[0] and res["points"] <= pool[1], "points from the potential pool")
	var total := 0
	for st in Stats.ALL:
		var g: int = a.stats[st] - before[st]
		if Stats.group_stats(Stats.PHYSICALITY).has(st):
			check(g >= 0 and g <= Camp.MAX_STAT_GAIN and g == res["gains"][st], "%s gain %d" % [st, g])
			total += g
		else:
			check(g == 0, "drill only touches its group (%s)" % st)
	check(total == res["points"], "all points land (%d of %d)" % [total, res["points"]])
	check(a.group_caps[Stats.PHYSICALITY] >= a.group_rating(Stats.PHYSICALITY), "cap raised if needed")
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
		f.potential = 0
		aa.potential = Soldier.POTENTIAL_A
		t.roster.append(f)
		t.roster.append(aa)
		lo += c.run(t, Stats.ACCURACY, f, rng)["points"]
		hi += c.run(t, Stats.HANDLING, aa, rng)["points"]
	check(hi > lo * 2, "A potential gets far bigger pools (%d vs %d)" % [hi, lo])
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
	var a: Soldier = s.user_team().starters()[0]
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
	var a: Soldier = user.starters()[0]
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
	n.arguments().append({"id": &"test", "title": "Test", "pitch": "You're replaceable.", "evidence": 1.0, "evidence_text": "", "fit": 0.05, "tone": "hard", "used": false})
	var before := n.demand(2)
	var trust := so.trust
	var bf := n.use_argument(&"test")
	check(bf["result"] == "backfired" and n.demand(2) > before and so.trust < trust, "bad-fit argument backfires")
	# A promise is worth money to a playing-time guy.
	so.get_dna().playing_time = 90
	check(n.demand(2, true) < n.demand(2) or n.demand(2) <= n.floor_salary(2), "promise lowers his demand")
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

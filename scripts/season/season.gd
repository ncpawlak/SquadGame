class_name Season
extends RefCounted
## Franchise season loop (Madden/FIFA career style). The franchise league is the fixed 20-team
## league (League.load_fixed): four divisions of five, a 12-week regular season (home and away
## against each division rival, one game against a team from each other division, one bye),
## then an 8-team bracket - the four division winners (seeds 1-4 by record) and four wild cards
## (seeds 5-8) - 1v8, 4v5, 2v7, 3v6, quarterfinals to the final. The compact test fixture
## (`fixture_teams` > 0: one generated division, double round robin, top 4) still works.
##
## Weekly flow (sim_week): AI teams set training intensity and lineups (resting tired/injured
## soldiers; the user's injured starters are auto-replaced), every team trains at each soldier's
## intensity, the week's matches are simulated and match XP awarded, then fatigue/injuries are
## updated (Conditioning) and AI teams auto-spend skill points. Records and standings are
## derived from the played fixtures, so there is no separate record state.

const DIVISION_NAME := "Premier Division"
const TEAM_COUNT := 20
const DIVISION_WEEKS := 12
const DIVISION_PLAYOFF_TEAMS := 8
const FIXTURE_PLAYOFF_TEAMS := 4
## Tests: > 0 makes new_franchise build a generated single-division league of this many teams.
static var fixture_teams := 0
const PHASE_REGULAR := &"regular"
const PHASE_PLAYOFFS := &"playoffs"
const PHASE_OFFSEASON := &"offseason"
const STAGE_REGULAR := &"regular"
const STAGE_QUARTERFINAL := &"quarterfinal"
const STAGE_SEMIFINAL := &"semifinal"
const STAGE_FINAL := &"final"
## Offseason stages: re-sign your expiring players (awards and retirements are in), then free
## agency (FA_DAYS bidding rounds), then the draft, then a roster-review week (undrafted
## prospects join free agency; get under the cap), then training camp (Camp drills), then the
## next season. Every offseason step is a "week" for XP: rostered soldiers earn
## OFFSEASON_WEEK_XP (scaled by potential), and the training-camp week pays CAMP_WEEK_XP instead.
const OFF_RESIGN := &"resign"
const OFF_FREE_AGENCY := &"free_agency"
const OFF_DRAFT := &"draft"
const OFF_REVIEW := &"review"
const OFF_CAMP := &"camp"
const OFF_DONE := &"done"
const OFFSEASON_WEEK_XP := 100.0
const CAMP_WEEK_XP := 250.0
const FA_DAYS := 3
## Roster rules: Week 1 is played with exactly Team.ROSTER_SIZE; after that a team plays with
## ROSTER_MIN..ROSTER_SIZE. Trades may push a team over the limit (or, before Week 1, down to
## Trades.MIN_ROSTER_OFFSEASON); it must be fixed before the team's next match. AI teams fix it
## at once (Trades.restructure); the user is held at the hub (user_roster_error).
const ROSTER_MIN := 8
const INITIAL_FREE_AGENTS := 18
## Only the best undrafted prospects turn pro as free agents; the rest go home.
const UNDRAFTED_TO_FA := 12

var league: League
## Regular-season length and playoff field (set from the league's shape when the franchise starts).
var regular_weeks := DIVISION_WEEKS
var playoff_teams := DIVISION_PLAYOFF_TEAMS
## Seed of every playoff team this season (Team -> 1..playoff_teams).
var playoff_seeds := {}
## Salary-floor penalties charged at the end of the most recent season: [{team, amount}].
var last_floor_penalties: Array = []
var news := LeagueNews.new()
## The Weekly News: the user's beat writer's feature on every week and offseason step.
var newsroom := Newsroom.new()
var year: int = 2026:
	set(v):
		year = v
		Team.year_now = v
var week: int = 1
var phase: StringName = PHASE_REGULAR
var champion: Team = null
## Injuries from the most recent sim_week, and every injury this season.
## Each is {soldier, team, weeks, name, week, year}.
var last_injuries: Array = []
var injury_log: Array = []
## schedule[w - 1] is the Array of ScheduledMatch for regular-season week w.
var schedule: Array = []
## Semifinals (created when the regular season ends) and the final (created after the semis).
var playoff_matches: Array = []
## This year's draft class: scouted during the season, drafted in the offseason.
var draft: Draft
## Awards and potential changes, set when the final is played (null during the season).
var review: SeasonReview = null
## Every past review, oldest first (includes `review` once the season is over).
var review_history: Array = []
## One SeasonSnapshot per finished season (champion, runner-up, final table, bracket), oldest first.
var history: Array = []
## Hall of Fame members, oldest induction first (see HallOfFame).
var hall_of_fame: Array = []
## Who declined with age at the start of this season: Array of Aging.age_soldier reports.
var aging_report: Array = []
## Current offseason stage (OFF_*; "" during the season) and free-agency day (1..FA_DAYS).
var offseason_stage: StringName = &""
var fa_day := 0
## Offseason step being advanced right now (see step_label); "" otherwise.
var _step := ""
## Free-agent offers and signing history.
var fa := FreeAgency.new()
## League-wide teammate chemistry (DNA module).
var relationships := Relationships.new()
## Divisional and team-specific rivalries: heat, head-to-head records and emergent rivalries.
var rivalries := Rivalries.new()
## Team market (a fixed rating) and the buzz that moves with results.
var market := Market.new()
## Club revenue and cash (behind the scenes: nothing in contracts or the cap reads it).
var revenue := Revenue.new()
var trades := Trades.new()
## Signings from the most recent resolution (free-agency day or week).
var last_signings: Array = []
## Every retirement, oldest first: Retirement.run records.
var retirements: Array = []
## Every re-signing: {soldier, team, salary, years, year}.
var resign_log: Array = []
## Your re-signing talks this offseason: soldier id -> Negotiation.
var negotiations: Dictionary = {}
## Resolved starter promises: {soldier, team, year, games, started, kept, request}.
var promise_log: Array = []
## Contract-talk flashpoints for storylines: {year, when, soldier, team, kind, text}. Kinds:
## &"walked", &"insulted", &"backfired", &"keep_broken", &"keep_kept".
var talks_log: Array = []
## Expiring soldiers who left their team when free agency opened: {soldier, team, year}.
var departures: Array = []
## This offseason's training camp (null until the first offseason).
var camp: Camp = null
## True while a new franchise's opening (preseason) training camp is open, before Week 1.
var preseason_camp := false
## Completed drafts, oldest first (the current one stays in `draft` until the next season).
var past_drafts: Array = []
## Prospect stories from the most recent sim_week.
var last_prospect_news: Array = []
## Regular-season week w -> the teams on bye (Array).
var _byes: Array = []
var _week_prepared := false
## Week key (see _week_key) of the user's last weekly training.
var user_trained_key := -1
## soldier_id -> Training report from the user's most recent weekly training.
var user_training_report := {}
var _rng := RandomNumberGenerator.new()


## With `with_camp`, the franchise opens in preseason training camp (close_preseason_camp starts Week 1).
static func new_franchise(seed_value: int, user_team_index := 0, start_year := 2026, with_camp := false) -> Season:
	var s := Season.new()
	s.year = start_year
	var crng := RandomNumberGenerator.new()
	crng.seed = _mix([seed_value, start_year, 0xC0475])
	if fixture_teams > 0:
		s.league = League.generate(seed_value, fixture_teams)
		Contracts.assign_initial(s.league, start_year, crng)
		var roles := [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]
		for i in INITIAL_FREE_AGENTS:
			var so := PlayerGenerator.generate(crng, s.league.next_soldier_id, roles[i % roles.size()], crng.randf_range(60.0, 74.0))
			s.league.next_soldier_id += 1
			s.league.add_free_agent(so, start_year - 1)
	else:
		s.league = League.load_fixed(seed_value)
	for i in s.league.teams.size():
		s.league.teams[i].user_controlled = (i == user_team_index)
	s._configure()
	var mrng := RandomNumberGenerator.new()
	mrng.seed = _mix([seed_value, start_year, 0x307A1E])
	for so in s.league.all_soldiers():
		so.morale = mrng.randf_range(68.0, 84.0)
	var rrng := RandomNumberGenerator.new()
	rrng.seed = _mix([seed_value, start_year, 0xC4E3])
	s.relationships.seed_league(s.league, rrng)
	s._begin_season()
	if s.has_divisions():
		s._apply_opening_pick_trades()
	if with_camp:
		s.camp = Camp.make(start_year - 1)
		s.preseason_camp = true
		# Scouting opens in Week 1: the first week's points arrive when camp closes.
		s.draft.scout_points = 0
	s._stamp_log()
	return s


## Points new progression-history entries (Soldier.log_progress) at the current week / stage.
func _stamp_log() -> void:
	Relationships.active = relationships
	Relationships.league_now = league
	Soldier.log_year = year
	if preseason_camp:
		Soldier.log_when = "Preseason camp"
	elif phase == PHASE_OFFSEASON:
		Soldier.log_when = "Offseason"
	else:
		Soldier.log_when = week_label(week)


## Season shape from the league: divisions -> the division format, otherwise a double round robin.
func _configure() -> void:
	if has_divisions():
		regular_weeks = DIVISION_WEEKS
		playoff_teams = DIVISION_PLAYOFF_TEAMS
	else:
		var n := league.teams.size()
		regular_weeks = 2 * (n - 1 if n % 2 == 0 else n)
		playoff_teams = mini(FIXTURE_PLAYOFF_TEAMS, n)


func has_divisions() -> bool:
	return divisions().size() > 1


## Division names in display order ([DIVISION_NAME] for a single-division league).
func divisions() -> Array:
	var out: Array = []
	for d in LeagueData.DIVISIONS:
		for t in league.teams:
			if t.division == d:
				out.append(d)
				break
	return out if not out.is_empty() else [DIVISION_NAME]


func division_of(team: Team) -> String:
	return team.division if team.division != "" else DIVISION_NAME


func division_teams(div: String) -> Array:
	return league.teams.filter(func(t: Team): return division_of(t) == div)


## The division table: standings() rows of that division, in order.
func division_standings(div: String) -> Array:
	return standings().filter(func(r: StandingRow): return division_of(r.team) == div)


## Opening-day pick trades from the league's backstory (Louisville and Little Rock stockpiled picks).
func _apply_opening_pick_trades() -> void:
	for pt in LeagueData.OPENING_PICK_TRADES:
		var owner := league.team_by_abbrev(pt[3])
		if owner != null and league.team_by_abbrev(pt[2]) != null:
			trades.pick_owner["%d:%d:%s" % [year + int(pt[0]), int(pt[1]), pt[2]]] = owner


func user_team() -> Team:
	for t in league.teams:
		if t.user_controlled:
			return t
	return null


func total_weeks() -> int:
	return regular_weeks + playoff_rounds()


## Number of knockout rounds for the playoff field (8 -> quarters, semis, final = 3).
func playoff_rounds() -> int:
	var rounds := 0
	var n := playoff_teams
	while n > 1:
		n = ceili(n / 2.0)
		rounds += 1
	return rounds


func week_label(w: int) -> String:
	if w <= regular_weeks:
		return "Week %d" % w
	var from_end := total_weeks() - w
	match from_end:
		0:
			return "Final"
		1:
			return "Semifinals"
		2:
			return "Quarterfinals"
	return "Playoffs Round %d" % (w - regular_weeks)


func stage_for_week(w: int) -> StringName:
	if w <= regular_weeks:
		return STAGE_REGULAR
	if w == total_weeks():
		return STAGE_FINAL
	return STAGE_SEMIFINAL if w == total_weeks() - 1 else STAGE_QUARTERFINAL


func matches_for_week(w: int) -> Array:
	if w >= 1 and w <= schedule.size():
		return schedule[w - 1]
	var out: Array = []
	for m in playoff_matches:
		if m.week == w:
			out.append(m)
	return out


## Teams on bye in regular-season week w (empty in the playoffs).
func bye_teams(w: int) -> Array:
	if w >= 1 and w <= _byes.size():
		return _byes[w - 1]
	return []


func is_bye(team: Team, w: int) -> bool:
	return bye_teams(w).has(team)


## The week `team` is on bye (0 = none).
func bye_week_of(team: Team) -> int:
	for w in _byes.size():
		if _byes[w].has(team):
			return w + 1
	return 0


func next_match_for(team: Team) -> ScheduledMatch:
	for m in matches_for(team):
		if not m.is_played():
			return m
	return null


func matches_for(team: Team) -> Array:
	var out: Array = []
	for wk in schedule:
		for m in wk:
			if m.involves(team):
				out.append(m)
	for m in playoff_matches:
		if m.involves(team):
			out.append(m)
	return out


func regular_matches() -> Array:
	var out: Array = []
	for wk in schedule:
		out.append_array(wk)
	return out


func standings() -> Array:
	var rows := {}
	for t in league.teams:
		var r := StandingRow.new()
		r.team = t
		rows[t] = r
	var h2h := {}  # Team -> { opponent Team -> wins }
	for t in league.teams:
		h2h[t] = {}
	var results := {}  # Team -> Array[String] "W"/"L" in chronological order
	for t in league.teams:
		results[t] = []
	for m in regular_matches():
		if not m.is_played():
			continue
		for t: Team in [m.home, m.away]:
			var row: StandingRow = rows[t]
			var opp: Team = m.opponent_of(t)
			row.games_won += m.games_for(t)
			row.games_lost += m.games_for(opp)
			row.points_for += m.points_for(t)
			row.points_against += m.points_for(opp)
			var div_game := t.division != "" and t.division == opp.division
			if m.winner() == t:
				row.wins += 1
				if div_game:
					row.div_wins += 1
				h2h[t][opp] = int(h2h[t].get(opp, 0)) + 1
				results[t].append("W")
			else:
				row.losses += 1
				if div_game:
					row.div_losses += 1
				results[t].append("L")
	for t in league.teams:
		var row: StandingRow = rows[t]
		var res: Array = results[t]
		row.last5 = "".join(PackedStringArray(res.slice(maxi(0, res.size() - 5))))
		if res.is_empty():
			row.streak = "-"
		else:
			var last: String = res[-1]
			var n := 0
			for i in range(res.size() - 1, -1, -1):
				if res[i] != last:
					break
				n += 1
			row.streak = "%s%d" % [last, n]
	# Tiebreakers: head-to-head wins among the teams tied on wins, then division record, then
	# round (game) differential, then point differential.
	var h2h_score := {}
	for t in league.teams:
		var score := 0
		var my_wins: int = rows[t].wins
		for opp in h2h[t]:
			if rows[opp].wins == my_wins:
				score += int(h2h[t][opp])
		h2h_score[t] = score
	var list: Array = rows.values()
	list.sort_custom(func(a: StandingRow, b: StandingRow) -> bool:
		if a.wins != b.wins:
			return a.wins > b.wins
		if h2h_score[a.team] != h2h_score[b.team]:
			return h2h_score[a.team] > h2h_score[b.team]
		if a.div_wins != b.div_wins:
			return a.div_wins > b.div_wins
		if a.game_diff() != b.game_diff():
			return a.game_diff() > b.game_diff()
		if a.point_diff() != b.point_diff():
			return a.point_diff() > b.point_diff()
		return a.team.id < b.team.id)
	for i in list.size():
		list[i].rank = i + 1
	return list


func record_text(team: Team) -> String:
	for r in standings():
		if r.team == team:
			return "%d-%d" % [r.wins, r.losses]
	return "0-0"


func is_regular_season_over() -> bool:
	return phase != PHASE_REGULAR


## Pre-match half of a week: closes camp, resolves FA bids, sets lineups and runs training.
## Called by `sim_week` automatically; call it early to show/watch the week's matchups first.
func prepare_week() -> void:
	if phase == PHASE_OFFSEASON or _week_prepared:
		return
	close_preseason_camp()
	_stamp_log()
	last_signings = fa.resolve(self, _rng, week_label(week))
	_fix_rosters()
	_prepare_lineups()
	for t in league.teams:
		if t.user_controlled:
			train_user_team()
		else:
			Training.run_week(t)
	_week_prepared = true


## The user's weekly training: run on demand from the Weekly Training screen, or automatically
## (at the set intensities) when the week is played. Once per week.

func _week_key() -> int:
	return year * 1000 + week


func can_train_user_team() -> bool:
	return phase != PHASE_OFFSEASON and not preseason_camp


func user_trained() -> bool:
	return user_trained_key == _week_key()


## Runs the user's training for this week now (no-op if already done). Returns the report.
func train_user_team() -> Dictionary:
	if not can_train_user_team():
		return {}
	if not user_trained():
		_stamp_log()
		user_training_report = Training.run_week(user_team())
		user_trained_key = _week_key()
	return user_training_report


## Team's keep-value statics (draft-bonus year, picks per round) follow whichever season acts.
func sync_team_statics() -> void:
	Team.year_now = year
	Team.league_size = league.teams.size()
	Relationships.active = relationships
	Relationships.league_now = league


func sim_week() -> Array:
	if phase == PHASE_OFFSEASON:
		return []
	for m in begin_week():
		play_week_match(m)
	return finish_week()


## Fixtures of the week in progress (between begin_week and finish_week).
var _week_matches: Array = []


## Step 1 of sim_week (split so the UI can show progress between steps): prepares the week
## and returns its fixtures. Follow with play_week_match for each, then finish_week.
func begin_week() -> Array:
	if phase == PHASE_OFFSEASON:
		return []
	sync_team_statics()
	prepare_week()
	_stamp_log()
	_week_prepared = false
	_week_matches = matches_for_week(week)
	return _week_matches


## Step 2 of sim_week: plays one fixture (unless it was watched live) and awards its XP.
func play_week_match(m: ScheduledMatch) -> void:
	if not m.is_played():
		m.play()
		Progression.award_match_xp(m.result, year)
	elif m.needs_xp:
		Progression.award_match_xp(m.result, year)
	m.needs_xp = false


## Step 3 of sim_week: injuries, morale, news, awards and trades, then advances the week.
## Returns the week's fixtures.
func finish_week() -> Array:
	if phase == PHASE_OFFSEASON:
		return []
	var played := _week_matches
	_week_matches = []
	for m in played:
		play_week_match(m)
	var played_ids := {}
	var playing_teams := {}
	for m in played:
		for t: Team in [m.home, m.away]:
			playing_teams[t] = true
			for so in t.starters():
				played_ids[so.id] = true
	last_injuries = []
	for t in league.teams:
		# Teams without a match this week (bye, or knocked out of the playoffs) recover extra.
		var bye := not playing_teams.has(t)
		for inj in Conditioning.end_week(t, played_ids, bye, _rng):
			inj["team"] = t
			inj["week"] = week
			inj["year"] = year
			last_injuries.append(inj)
			injury_log.append(inj)
	_track_promises(played)
	for t in league.teams:
		Progression.auto_spend_team(t, _rng)
	Morale.update_week(league, played)
	relationships.week(league, played)
	rivalries.record_week(self, played)
	var news_week := week
	_advance()
	market.week(self, played, news_week)
	revenue.week(self, played, news_week)
	news.week_stories(self, played, news_week)
	if phase == PHASE_OFFSEASON:
		newsroom.publish_wrap(self, news_week)
	else:
		newsroom.publish_week(self, news_week)
	if phase == PHASE_OFFSEASON:
		_resolve_promises()
		negotiations.clear()
	_stamp_log()
	last_prospect_news = []
	if phase != PHASE_OFFSEASON:
		last_prospect_news = draft.weekly_news(news_week)
		draft.scout_points += Draft.POINTS_PER_WEEK
		fa.ai_offers(self, _rng, true)
	_trade_tick()
	return played


## Weekly trade activity on its own RNG so trades never shift match or injury rolls.
func _trade_tick() -> void:
	var trng := RandomNumberGenerator.new()
	trng.seed = _mix([league.league_seed, year, week, String(offseason_stage).hash(), fa_day, 0x7DADE])
	trades.weekly(self, trng)


## Counts this week's matches toward starter promises. Weeks a soldier sat out injured don't count.
func _track_promises(played: Array) -> void:
	for m in played:
		if not m.is_played():
			continue
		for t: Team in [m.home, m.away]:
			for so in t.roster:
				if so.promise.is_empty() or so.promise["team"] != t.abbrev or int(so.promise["year"]) != year:
					continue
				var started: bool = m.result.box.has(so.id)
				if not started and so.is_injured():
					continue
				so.promise["games"] += 1
				if started:
					so.promise["started"] += 1


## End of season: every promise for this year is judged. Kept builds trust; broken costs trust and
## morale, and players who need to start or take it personally ask for a trade.
func _resolve_promises() -> void:
	for t in league.teams:
		for so in t.roster:
			if so.promise.is_empty() or int(so.promise["year"]) != year:
				continue
			var games := int(so.promise["games"])
			var started := int(so.promise["started"])
			var kept := games == 0 or float(started) / games >= Soldier.PROMISE_SHARE
			var d := so.get_dna()
			var request := false
			if kept:
				so.add_trust(12.0)
				so.add_morale(5.0)
			else:
				so.add_trust(-25.0)
				so.add_morale(-10.0)
				request = d.playing_time >= 60 or d.temperament <= 35
				so.trade_request = so.trade_request or request
			promise_log.append({"soldier": so, "team": t, "year": year, "games": games, "started": started, "kept": kept, "request": request})
			so.promise = {}
		for so in t.roster:
			if so.keep_promise.is_empty() or int(so.keep_promise["year"]) != year:
				continue
			so.add_trust(6.0)
			log_talk(so, t, &"keep_kept", "%s's club kept its word: %s stayed." % [so.full_name(), so.keep_promise["name"]])
			so.keep_promise = {}


## AI teams pick intensities and rest tired/injured starters; every team (including the user's)
## gets injured starters swapped out so a match is never played by an injured soldier.
func _prepare_lineups() -> void:
	sync_team_statics()
	for t in league.teams:
		if t.user_controlled:
			t.fill_injured()
		else:
			t.pick_scheme()
			t.auto_lineup(true)
			Training.ai_set_intensities(t)


## Why the user can't play this week yet ("" = he can): Week 1 needs exactly Team.ROSTER_SIZE
## players; later weeks need ROSTER_MIN..ROSTER_SIZE.
func user_roster_error() -> String:
	if phase == PHASE_OFFSEASON:
		return ""
	var n := user_team().roster.size()
	var first := phase == PHASE_REGULAR and week == 1
	if n > Team.ROSTER_SIZE:
		var extra := n - Team.ROSTER_SIZE
		return "You have %d players. Release %d (or trade them away) to get down to %d before %s." % [
			n, extra, Team.ROSTER_SIZE, "Week 1" if first else "your next match"]
	var lo := Team.ROSTER_SIZE if first else ROSTER_MIN
	if n < lo:
		var short := lo - n
		if first:
			return "Week 1 needs exactly %d players. You have %d: sign %d more free agent%s." % [lo, n, short, "" if short == 1 else "s"]
		return "You need at least %d players to play. You have %d: sign %d more." % [lo, n, short]
	return ""


## Answers the user's pending free-agent offers now (he needs players before he can play).
## Only soldiers he bid on decide. Returns the signings.
func resolve_user_offers() -> Array:
	var user := user_team()
	if fa.offers_by(user).is_empty():
		return []
	_stamp_log()
	var when := "Preseason" if preseason_camp or (phase == PHASE_REGULAR and week == 1) else week_label(week)
	var out := fa.resolve(self, _rng, when, user)
	last_signings = out
	return out


## Safety net before a week is played: AI teams over the limit restructure and short-handed
## AI teams sign free agents; an illegal user roster (only reachable outside the hub, e.g.
## headless sims) is cut/filled automatically.
func _fix_rosters() -> void:
	for t in league.teams:
		if t.user_controlled:
			if user_roster_error() != "":
				for s in t.cut_to_limit():
					Contracts.charge_release(t, s, cap_year())
					league.add_free_agent(s, year)
				fa.fill_roster(self, t, Team.ROSTER_SIZE if week == 1 and phase == PHASE_REGULAR else ROSTER_MIN, week_label(week))
			continue
		if t.is_over_roster_limit():
			trades.restructure(self, t)
		if t.roster.size() < ROSTER_MIN:
			fa.fill_roster(self, t, Team.ROSTER_SIZE, week_label(week))


func sim_to_end_of_regular_season() -> void:
	while phase == PHASE_REGULAR:
		sim_week()


func sim_to_end_of_season() -> void:
	while phase != PHASE_OFFSEASON:
		sim_week()


func start_next_season() -> void:
	if phase != PHASE_OFFSEASON:
		push_warning("start_next_season() is only valid in the offseason.")
		return
	sync_team_statics()
	_stamp_log()
	while offseason_stage != OFF_DONE:
		advance_offseason()
	RetiredCallsigns.resolve_all(self)
	# Last call for free agency: pending offers (the user's too) are answered. The user's roster
	# is left as is - he must reach exactly ROSTER_SIZE before Week 1 (user_roster_error).
	fa.resolve(self, _rng, "Preseason")
	for t in league.teams:
		if t.user_controlled:
			continue
		trades.restructure(self, t)
		fa.fill_roster(self, t, Team.ROSTER_SIZE, "Preseason")
	fa.offers.clear()
	negotiations.clear()
	var arng := RandomNumberGenerator.new()
	arng.seed = _mix([league.league_seed, year, 0xA6E])
	Soldier.log_year = year + 1
	Soldier.log_when = "Preseason"
	aging_report = Aging.age_league(league, arng)
	var active_ids := {}
	for so in league.all_soldiers():
		active_ids[so.id] = true
	for so in league.free_agents:
		active_ids[so.id] = true
	relationships.prune(active_ids)
	year += 1
	for t in league.teams:
		Conditioning.reset(t)
		for so in t.roster:
			so.morale = lerpf(so.morale, Soldier.MORALE_NEUTRAL, 0.5)
		if t.user_controlled:
			t.fill_injured()
		elif not t.pick_scheme():
			t.auto_lineup()
	_begin_season()


## The season whose cap applies right now: this season, or next season during the offseason.
func cap_year() -> int:
	return year + (1 if phase == PHASE_OFFSEASON else 0)


## Offers can be made in-season and once the re-signing window closes (through the draft,
## roster review and camp; offers outside FA days are answered when the review week ends).
func free_agency_open() -> bool:
	return phase != PHASE_OFFSEASON or offseason_stage in [OFF_FREE_AGENCY, OFF_DRAFT, OFF_REVIEW, OFF_CAMP, OFF_DONE]


## Picks `team` still has to make in this offseason's draft (0 once it's done or in-season).
func pending_picks(team: Team) -> int:
	if phase != PHASE_OFFSEASON or draft == null or not draft.is_started() or draft.is_complete():
		return 0
	return draft.picks_left_for(team)


## Rookie-scale money `team` will owe for its remaining picks this offseason.
func rookie_reserve(team: Team) -> int:
	if pending_picks(team) == 0:
		return 0
	var total := 0
	for i in range(draft.next_pick, draft.order.size()):
		if draft.order[i] == team:
			total += Contracts.rookie_contract(i + 1, draft.order.size(), year).salary
	return total


## Why the user can't leave the roster-review week yet ("" = he can): payroll must be under
## the cap before training camp (rookie deals always sign, so a team can end up over).
func user_cap_error() -> String:
	if phase != PHASE_OFFSEASON or offseason_stage != OFF_REVIEW:
		return ""
	var over := -Contracts.cap_space(user_team(), cap_year())
	if over <= 0:
		return ""
	return "You're %s over the cap. Release or trade players to get under it before training camp." % Contracts.money(over)


func camp_open() -> bool:
	return preseason_camp or (phase == PHASE_OFFSEASON and offseason_stage == OFF_CAMP)


## Ends the opening preseason camp: AI teams run their drills and everyone gets camp-week XP.
func close_preseason_camp() -> void:
	if not preseason_camp:
		return
	for t in league.teams:
		if not t.user_controlled:
			camp.ai_run(t, _rng)
	_camp_star_news()
	offseason_xp(CAMP_WEEK_XP)
	preseason_camp = false
	draft.scout_points += Draft.POINTS_PER_WEEK


## Sends `s` to the user's `group` drill. Returns the Camp result ({} if refused; see camp_check).
func run_drill(group: StringName, s: Soldier) -> Dictionary:
	if not camp_open() or camp == null:
		return {}
	var res := camp.run(user_team(), group, s, _rng)
	if res.get("dev_up", false):
		news.camp_star(self, user_team(), s, Camp.drill_name(group))
	return res


## Wire stories for every camp drill that earned a dev star (each soldier at most once a year).
func _camp_star_news() -> void:
	for t in league.teams:
		var by_group: Dictionary = camp.team_results(t)
		for g in by_group:
			var r: Dictionary = by_group[g]
			if r.get("dev_up", false):
				news.camp_star(self, t, r["soldier"], Camp.drill_name(g))


func camp_check(group: StringName, s: Soldier) -> String:
	if not camp_open() or camp == null:
		return "Training camp opens after the roster review."
	return camp.check(user_team(), group, s)


func can_resign() -> bool:
	return phase == PHASE_OFFSEASON and offseason_stage == OFF_RESIGN


## Moves the offseason one step: re-sign (AI teams re-sign) -> free agency (expiring soldiers
## hit the pool) -> each free-agency day resolves offers -> draft (finished with AI picks if it
## isn't done) -> roster review (undrafted prospects join the pool, AI teams cut down and get
## under the cap) -> pending offers are answered -> training camp (AI teams run their drills,
## bonus XP) -> done. Each step is an XP week. Returns new signings.
func advance_offseason() -> Array:
	if phase != PHASE_OFFSEASON:
		return []
	_step = step_label()
	var label := _step
	var signed := _advance_offseason_step()
	_step = ""
	market.tick(self, label)
	newsroom.publish_offseason(self, label)
	return signed


## Label of the offseason step in progress ("Re-signing", "FA Day 2", "Draft", "Roster Review", "Camp",
## "Preseason").
## Signings, cuts, trades and stories are filed under it so each step can be recapped
## (LeagueNews.digest). While a step is being advanced it stays that step's label.
func step_label() -> String:
	if _step != "":
		return _step
	match offseason_stage:
		OFF_RESIGN:
			return "Re-signing"
		OFF_DRAFT:
			return "Draft"
		OFF_FREE_AGENCY:
			return "FA Day %d" % fa_day
		OFF_REVIEW:
			return "Roster Review"
		OFF_CAMP:
			return "Camp"
	return "Preseason"


func _advance_offseason_step() -> Array:
	sync_team_statics()
	var signed: Array = []
	match offseason_stage:
		OFF_RESIGN:
			_ai_resign()
			# Free agency opens: the market, the AI cut-downs and day one's bids belong to Day 1.
			_step = "FA Day 1"
			_open_free_agency()
		OFF_FREE_AGENCY:
			last_signings = fa.resolve(self, _rng, "FA Day %d" % fa_day)
			signed = last_signings
			if fa_day >= FA_DAYS:
				offseason_stage = OFF_DRAFT
				if not draft.is_started():
					draft.set_order(draft_order())
					trades.apply_owners(self)
			else:
				fa_day += 1
				fa.ai_offers(self, _rng)
		OFF_DRAFT:
			finish_draft()
			# The review week's cut-downs and bids are recapped under their own step.
			_step = "Roster Review"
			_open_roster_review()
		OFF_REVIEW:
			last_signings = fa.resolve(self, _rng, "Roster Review")
			signed = last_signings
			for t in league.teams:
				_cut_to_cap(t)
			offseason_stage = OFF_CAMP
		OFF_CAMP:
			for t in league.teams:
				if not t.user_controlled:
					camp.ai_run(t, _rng)
			_camp_star_news()
			offseason_xp(CAMP_WEEK_XP)
			offseason_stage = OFF_DONE
			relationships.offseason_week(league)
			_trade_tick()
			return []
		_:
			return []
	offseason_xp(OFFSEASON_WEEK_XP)
	relationships.offseason_week(league)
	_trade_tick()
	return signed


## One offseason week of XP for every rostered soldier (potential-scaled); AI teams spend it.
## Returns soldier_id -> gain_xp report.
func offseason_xp(base_xp: float) -> Dictionary:
	var reports := {}
	for t in league.teams:
		for so in t.roster:
			reports[so.id] = Progression.gain_xp(so, base_xp)
		Progression.auto_spend_team(t, _rng)
	return reports


## Talks with one of `team`'s expiring soldiers (started on first use, kept for the offseason).
## null when he can't be re-signed right now.
func negotiation(team: Team, s: Soldier) -> Negotiation:
	if negotiations.has(s.id):
		return negotiations[s.id]
	if not can_resign() or s.contract == null or not s.contract.is_expiring() or not team.roster.has(s):
		return null
	var n := Negotiation.start(self, team, s)
	negotiations[s.id] = n
	return n


## Re-signs one of `team`'s expiring soldiers at his current demand. Returns "" or the reason it failed.
func resign_player(team: Team, s: Soldier, years: int, terms := {}) -> String:
	if not can_resign():
		return "Re-signing is open from the end of the season until free agency."
	var n := negotiation(team, s)
	if n == null:
		return "%s isn't an expiring player on your roster." % s.full_name()
	if n.state == Negotiation.WALKED:
		return "%s broke off talks. He's headed to free agency." % s.full_name()
	if n.state == Negotiation.SIGNED:
		return "%s already re-signed." % s.full_name()
	var salary := n.required_salary(years, terms)
	var err := n.offer_error(salary, years, terms)
	if err != "":
		return "%s He wants %s." % [err, Contracts.money(salary)] if err.begins_with("Not enough") else err
	n.accept(years, terms)
	return ""


## `team` just traded or released `gone`: every teammate it promised to keep him around is let
## down (trust, morale, maybe a trade request) and the storyline log notes it.
func break_keep_promises(team: Team, gone: Soldier) -> void:
	for so in team.roster:
		if so == gone or so.keep_promise.is_empty() or so.keep_promise["team"] != team.abbrev or int(so.keep_promise["id"]) != gone.id:
			continue
		var d := so.get_dna()
		so.add_trust(-15.0)
		so.add_morale(-10.0)
		if d.temperament <= 35 or d.loyalty >= 70:
			so.trade_request = true
		so.keep_promise = {}
		log_talk(so, team, &"keep_broken", "%s was promised %s would stay. He's gone." % [so.full_name(), gone.full_name()])


## Adds a storyline flashpoint to talks_log.
func log_talk(s: Soldier, team: Team, kind: StringName, text: String) -> void:
	talks_log.append({"year": year, "when": Trades._when(self), "soldier": s, "team": team, "kind": kind, "text": text})


## Releases a soldier into free agency, booking dead money for what's left on his deal.
## Returns the dead money.
func release_player(team: Team, s: Soldier) -> int:
	news.release(self, team, s)
	break_keep_promises(team, s)
	var dead := Contracts.charge_release(team, s, cap_year())
	team.release(s)
	league.add_free_agent(s, year)
	return dead


func retirements_in(y: int) -> Array:
	return retirements.filter(func(r): return r["year"] == y)


func _ai_resign() -> void:
	for t in league.teams:
		if t.user_controlled:
			continue
		var ovrs: Array = t.roster.map(func(x: Soldier): return x.best_ovr())
		ovrs.sort()
		ovrs.reverse()
		var bar: int = ovrs[mini(8, ovrs.size() - 1)] if not ovrs.is_empty() else 0
		var exp := Contracts.expiring(t)
		exp.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
		for s in exp:
			var keep := s.age <= 33 and (s.best_ovr() >= bar - 2 or (s.age <= 25 and s.potential_grade() >= 3))
			var yrs := Contracts.preferred_years(s)
			var salary := Contracts.resign_asking(s, yrs)
			if keep and Contracts.resign_fits(t, cap_year(), s, salary):
				s.contract = Contract.make(salary, yrs, year)
				resign_log.append({"soldier": s, "team": t, "salary": salary, "years": yrs, "year": year})
				news.resign(self, t, s, salary, yrs)


func _open_free_agency() -> void:
	offseason_stage = OFF_FREE_AGENCY
	fa_day = 1
	_release_expiring()
	news.free_agency_opens(self)
	for t in league.teams:
		if t.user_controlled:
			continue
		trades.restructure(self, t, Team.OFFSEASON_MAX)
	fa.ai_offers(self, _rng)


## Expiring soldiers who weren't re-signed leave their teams for the free-agent pool.
func _release_expiring() -> void:
	for t in league.teams:
		for s in Contracts.expiring(t):
			departures.append({"soldier": s, "team": t, "year": year})
			t.release(s)
			league.add_free_agent(s, year)


## After the draft: the best undrafted prospects turn pro as free agents, AI teams trim to the
## offseason max and get under the cap, and they bid on the new pool.
func _open_roster_review() -> void:
	offseason_stage = OFF_REVIEW
	# Saves from the old order (draft before free agency) may still hold expiring deals.
	_release_expiring()
	var undrafted: Array = draft.available()
	undrafted.sort_custom(func(a: Prospect, b: Prospect): return Draft.true_value(a) > Draft.true_value(b))
	for p in undrafted.slice(0, UNDRAFTED_TO_FA):
		league.add_free_agent(p.soldier, year)
	for t in league.teams:
		if t.user_controlled:
			continue
		# Offseason rosters may run to OFFSEASON_MAX (final cut-down to ROSTER_SIZE comes at the
		# end of camp, in start_next_season); only extreme surpluses are shopped or cut now.
		trades.restructure(self, t, Team.OFFSEASON_MAX)
		_cut_to_cap(t)
	fa.ai_offers(self, _rng)


## Releases soldiers until `team`'s payroll is under the cap (each cut still leaves dead money):
## from its less valuable half, the cheapest-to-lose player whose savings clear the overage,
## else the one who saves the most. For the user this only runs as a safety net (headless
## sims); the hub holds him in the review week until he fixes it himself (user_cap_error).
func _cut_to_cap(team: Team) -> void:
	while Contracts.cap_space(team, cap_year()) < 0 and team.roster.size() > Trades.MIN_ROSTER_OFFSEASON:
		var over := -Contracts.cap_space(team, cap_year())
		var kv := {}
		for s in team.roster:
			kv[s] = team.keep_value(s)
		var order: Array = team.roster.duplicate()
		order.sort_custom(func(a: Soldier, b: Soldier): return kv[a] < kv[b])
		var pool: Array = order.slice(0, maxi(1, order.size() / 2))
		var cut: Soldier = null
		var best_save := 0
		for s: Soldier in pool:
			var save := _cap_savings(s)
			if save >= over:
				cut = s
				break
			if save > best_save:
				best_save = save
				cut = s
		if cut == null:
			break
		release_player(team, cut)
		trades.moves.append({"year": year, "when": "Offseason", "team": team, "soldier": cut, "kind": &"cut", "to": null})
	if team.roster.size() >= team.scheme.slot_ids().size():
		team.auto_lineup()


## Cap-year money freed by releasing `s` (his salary minus the dead money it leaves).
static func _cap_savings(s: Soldier) -> int:
	if s.contract == null or s.contract.years <= 0:
		return 0
	return s.contract.salary - roundi(s.contract.salary * Contracts.DEAD_MONEY_SHARE)


## Draft order (the same every round): teams that missed the playoffs first (worst record
## first), then playoff teams by how far they went (worst record first within a round), the
## runner-up, and the champion last.
func draft_order() -> Array:
	var finish := {}
	for t in league.teams:
		finish[t] = 0
	for m in playoff_matches:
		if not m.is_played():
			continue
		var rnd: int = m.week - regular_weeks
		for t: Team in [m.home, m.away]:
			finish[t] = maxi(finish[t], rnd)
		if m.stage == STAGE_FINAL:
			finish[m.winner()] = rnd + 1
	var rows := standings()
	rows.reverse()
	var teams: Array = []
	for r in rows:
		teams.append(r.team)
	var rank := {}
	for i in teams.size():
		rank[teams[i]] = i
	teams.sort_custom(func(a: Team, b: Team) -> bool:
		if finish[a] != finish[b]:
			return finish[a] < finish[b]
		return rank[a] < rank[b])
	return teams


## Every pick of the draft, for the mock draft: the real order once set, otherwise projected
## from the current standings and playoff results.
func mock_pick_order() -> Array:
	if draft.is_started():
		return draft.order
	return trades.owned_order(draft.year, draft_order())


## Completes the draft (AI picks for everyone still on the clock, including the user).
## Roster cut-downs happen when the roster review opens. Safe to call more than once.
func finish_draft() -> void:
	if phase != PHASE_OFFSEASON:
		return
	sync_team_statics()
	if not draft.is_started():
		draft.set_order(draft_order())
		trades.apply_owners(self)
	draft.sim_to_end()
	news.draft_stories(self)


# --- internals -------------------------------------------------------------

func _begin_season() -> void:
	if draft != null and draft.is_complete():
		past_drafts.append(draft)
	last_prospect_news = []
	week = 1
	phase = PHASE_REGULAR
	champion = null
	review = null
	offseason_stage = &""
	fa_day = 0
	last_signings = []
	playoff_matches = []
	last_injuries = []
	injury_log = []
	_rng.seed = _mix([league.league_seed, year, 0x5EA5])
	playoff_seeds = {}
	_build_schedule()
	trades.new_season(self)
	rivalries.new_season()
	draft = Draft.generate(_mix([league.league_seed, year, 0xD2AF]), year, league.next_soldier_id)
	draft.league = league
	league.next_soldier_id += Draft.CLASS_SIZE
	draft.scout_points = Draft.POINTS_PER_WEEK
	league.ensure_callsigns()
	market.begin_season(self)
	revenue.begin_season(self)
	news.begin_season(self)
	newsroom.publish_preseason(self)
	_stamp_log()


func _advance() -> void:
	week += 1
	if phase == PHASE_REGULAR:
		if week > regular_weeks:
			phase = PHASE_PLAYOFFS
			_create_first_playoff_round()
		return
	# Playoffs: create the next round from this round's winners, or crown the champion.
	var last_round := matches_for_week(week - 1)
	if last_round.size() == 1:
		champion = last_round[0].winner()
		phase = PHASE_OFFSEASON
		history.append(SeasonSnapshot.capture(self))
		var rrng := RandomNumberGenerator.new()
		rrng.seed = _mix([league.league_seed, year, 0x4E71])
		Soldier.log_year = year
		Soldier.log_when = "Season review"
		review = SeasonReview.run(self, rrng)
		review_history.append(review)
		var retire_rng := RandomNumberGenerator.new()
		retire_rng.seed = _mix([league.league_seed, year, 0x2E71])
		var retired := Retirement.run(self, retire_rng)
		retirements.append_array(retired)
		RetiredCallsigns.process(self, retired)
		HallOfFame.run(self)
		last_floor_penalties = Contracts.charge_floor(league, year)
		news.end_season(self, last_floor_penalties)
		news.dev_changes(self, review.dev_changes)
		Contracts.rollover(league)
		offseason_stage = OFF_RESIGN
		fa_day = 0
		camp = Camp.make(year)
		draft.set_order(draft_order())
		trades.apply_owners(self)
		return
	var winners: Array = []
	for m in last_round:
		winners.append(m.winner())
	_create_round(winners)


## Saves from before `history` existed: if this season is already over, snapshot it now. Earlier
## seasons were never recorded and stay missing.
func ensure_history() -> void:
	if phase != PHASE_OFFSEASON or champion == null:
		return
	for snap: SeasonSnapshot in history:
		if snap.year == year:
			return
	history.append(SeasonSnapshot.capture(self))


## The playoff field in seed order: with divisions, the division winners (seeded by record) then
## the best remaining records as wild cards; otherwise the top of the table.
func playoff_field() -> Array:
	var rows := standings()
	var field: Array = []
	if has_divisions():
		var led := {}
		for r in rows:
			if not led.has(r.team.division):
				led[r.team.division] = true
				field.append(r.team)
		for r in rows:
			if field.size() >= playoff_teams:
				break
			if not field.has(r.team):
				field.append(r.team)
	else:
		for r in rows.slice(0, playoff_teams):
			field.append(r.team)
	return field


## Bracket slots by seed for a field of n: 4 -> [1,4,2,3], 8 -> [1,8,4,5,2,7,3,6].
static func bracket_order(n: int) -> Array:
	var order: Array = [1]
	var size := 1
	while size < n:
		size *= 2
		var next: Array = []
		for s in order:
			next.append(s)
			next.append(size + 1 - s)
		order = next
	return order


func _create_first_playoff_round() -> void:
	var field := playoff_field()
	playoff_seeds = {}
	for i in field.size():
		playoff_seeds[field[i]] = i + 1
	var slots: Array = []
	for seed in bracket_order(field.size()):
		slots.append(field[seed - 1])
	_create_round(slots)


## `teams` in bracket order: slot 2k plays slot 2k+1, the better seed at home. Winners keep
## bracket order, so the bracket halves never cross until the final.
func _create_round(teams: Array) -> void:
	for i in teams.size() / 2:
		var a: Team = teams[2 * i]
		var b: Team = teams[2 * i + 1]
		var m := ScheduledMatch.new()
		m.week = week
		m.stage = stage_for_week(week)
		var a_top := int(playoff_seeds.get(a, 99)) <= int(playoff_seeds.get(b, 99))
		m.home = a if a_top else b
		m.away = b if a_top else a
		m.match_seed = _match_seed(week, i)
		playoff_matches.append(m)


func _build_schedule() -> void:
	schedule = []
	_byes = []
	if has_divisions():
		_build_division_schedule()
	else:
		_build_round_robin()


## The division format (4 divisions of 5): each division plays a home-and-away round robin (10
## rounds; each team sits out 2). In the first leg the four teams sitting out meet across
## divisions (pairing A-B / C-D); in the second leg they take their bye. Two more full rounds
## pair the remaining division matchups (A-C / B-D, A-D / B-C), so every team plays 8 division
## games, one game against each other division, and has exactly one bye in 12 weeks.
## Cross-division opponents are shuffled (rivalries don't shape the schedule). Week order is shuffled per league seed + year.
func _build_division_schedule() -> void:
	var srng := RandomNumberGenerator.new()
	srng.seed = _mix([league.league_seed, year, 0x5C4E])
	var divs := divisions()
	var members := {}
	for d in divs:
		var ts: Array = division_teams(d)
		_shuffle(ts, srng)
		members[d] = ts
	var pairings: Array = [[[0, 1], [2, 3]], [[0, 2], [1, 3]], [[0, 3], [1, 2]]]
	_shuffle(pairings, srng)
	var rounds: Array = []  # each: {pairs: [[home, away]], byes: []}
	# Division round robin, circle method on 5 + a dummy slot.
	var div_rounds := {}  # div -> Array of {pairs, sitting}
	for d in divs:
		var order: Array = members[d].duplicate()
		order.append(null)
		var n := order.size()
		var legs: Array = []
		for r in n - 1:
			var pairs: Array = []
			var sitting: Team = null
			for i in n / 2:
				var a: Team = order[i]
				var b: Team = order[n - 1 - i]
				if a == null or b == null:
					sitting = b if a == null else a
					continue
				pairs.append([a, b] if (r + i) % 2 == 0 else [b, a])
			legs.append({"pairs": pairs, "sitting": sitting})
			order.insert(1, order.pop_back())
		div_rounds[d] = legs
	var bye_pairing: Array = pairings[0]
	for leg in 2:
		for r in 5:
			var pairs: Array = []
			var byes: Array = []
			var sitting := {}
			for d in divs:
				var rd: Dictionary = div_rounds[d][r]
				for p in rd["pairs"]:
					pairs.append(p if leg == 0 else [p[1], p[0]])
				sitting[d] = rd["sitting"]
			if leg == 0:
				for dp in bye_pairing:
					var a: Team = sitting[divs[dp[0]]]
					var b: Team = sitting[divs[dp[1]]]
					pairs.append([a, b] if srng.randf() < 0.5 else [b, a])
			else:
				for d in divs:
					byes.append(sitting[d])
			rounds.append({"pairs": pairs, "byes": byes})
	for k in [1, 2]:
		var pairs: Array = []
		for dp in pairings[k]:
			var a_list: Array = members[divs[dp[0]]]
			var b_list: Array = members[divs[dp[1]]].duplicate()
			_shuffle(b_list, srng)
			for i in a_list.size():
				pairs.append([a_list[i], b_list[i]] if srng.randf() < 0.5 else [b_list[i], a_list[i]])
		rounds.append({"pairs": pairs, "byes": []})
	_shuffle(rounds, srng)
	for w in rounds.size():
		var wk: Array = []
		var pairs: Array = rounds[w]["pairs"]
		for k in pairs.size():
			var m := ScheduledMatch.new()
			m.week = w + 1
			m.stage = STAGE_REGULAR
			m.home = pairs[k][0]
			m.away = pairs[k][1]
			m.match_seed = _match_seed(w + 1, k)
			wk.append(m)
		schedule.append(wk)
		_byes.append(rounds[w]["byes"])


static func _shuffle(arr: Array, srng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := srng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Single-division fixture: circle-method round robin (dummy BYE slot for odd counts); second
## half mirrors the first with home/away swapped. Team order shuffled per league seed + year.
func _build_round_robin() -> void:
	var order: Array = league.teams.duplicate()
	var srng := RandomNumberGenerator.new()
	srng.seed = _mix([league.league_seed, year, 0x5C4E])
	for i in range(order.size() - 1, 0, -1):
		var j := srng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	if order.size() % 2 == 1:
		order.append(null)
	var n := order.size()
	var half_weeks := n - 1
	var first_half: Array = []  # Array of Array[[home, away]]
	var first_byes: Array = []
	for r in half_weeks:
		var pairs: Array = []
		var bye: Team = null
		for i in n / 2:
			var a: Team = order[i]
			var b: Team = order[n - 1 - i]
			if a == null or b == null:
				bye = b if a == null else a
				continue
			# Alternate home/away by round (and flip the anchor pairing) to balance venues.
			if (r + i) % 2 == 0:
				pairs.append([a, b])
			else:
				pairs.append([b, a])
		first_half.append(pairs)
		first_byes.append([bye] if bye != null else [])
		# Rotate all but the first slot.
		var last = order.pop_back()
		order.insert(1, last)
	var rounds_needed := regular_weeks
	var w := 0
	while w < rounds_needed:
		var leg := w / half_weeks
		var idx := w % half_weeks
		var wk: Array = []
		var pairs: Array = first_half[idx]
		for k in pairs.size():
			var m := ScheduledMatch.new()
			m.week = w + 1
			m.stage = STAGE_REGULAR
			var p: Array = pairs[k]
			m.home = p[0] if leg % 2 == 0 else p[1]
			m.away = p[1] if leg % 2 == 0 else p[0]
			m.match_seed = _match_seed(w + 1, k)
			wk.append(m)
		schedule.append(wk)
		_byes.append(first_byes[idx])
		w += 1


func _match_seed(w: int, index: int) -> int:
	return _mix([league.league_seed, year, w, index])


static func _mix(parts: Array) -> int:
	var h := 1469598103934665603
	for p in parts:
		h = (h ^ int(p)) * 1099511628211
	return absi(h) % 2147483647

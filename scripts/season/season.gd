class_name Season
extends RefCounted
## Franchise season loop (Madden/FIFA career style): one division, double round robin
## regular season, top-N playoffs, then the offseason draft (see Draft).
##
## Weekly flow (sim_week): AI teams set training intensity and lineups (resting tired/injured
## soldiers; the user's injured starters are auto-replaced), every team trains at each soldier's
## intensity, the week's matches are simulated and match XP awarded, then fatigue/injuries are
## updated (Conditioning) and AI teams auto-spend skill points. Records and standings are
## derived from the played fixtures, so there is no separate record state.

const DIVISION_NAME := "Premier Division"
const TEAM_COUNT := 5
const REGULAR_WEEKS := 10
const PLAYOFF_TEAMS := 4
const PHASE_REGULAR := &"regular"
const PHASE_PLAYOFFS := &"playoffs"
const PHASE_OFFSEASON := &"offseason"
const STAGE_REGULAR := &"regular"
const STAGE_SEMIFINAL := &"semifinal"
const STAGE_FINAL := &"final"
## Offseason stages (Madden-style): re-sign your expiring players, run the draft, then free
## agency (FA_DAYS bidding rounds), then training camp (Camp drills), then the next season.
## Every offseason step is a "week" for XP: rostered soldiers earn OFFSEASON_WEEK_XP (scaled by
## potential), and the training-camp week pays CAMP_WEEK_XP instead.
const OFF_RESIGN := &"resign"
const OFF_DRAFT := &"draft"
const OFF_FREE_AGENCY := &"free_agency"
const OFF_CAMP := &"camp"
const OFF_DONE := &"done"
const OFFSEASON_WEEK_XP := 100.0
const CAMP_WEEK_XP := 250.0
const FA_DAYS := 3
## The user needs at least this many soldiers to start a season (AI teams fill to ROSTER_SIZE).
const ROSTER_MIN := 10
const INITIAL_FREE_AGENTS := 18
## Only the best undrafted prospects turn pro as free agents; the rest go home.
const UNDRAFTED_TO_FA := 12

var league: League
var year: int = 2026
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
## Who declined with age at the start of this season: Array of Aging.age_soldier reports.
var aging_report: Array = []
## Current offseason stage (OFF_*; "" during the season) and free-agency day (1..FA_DAYS).
var offseason_stage: StringName = &""
var fa_day := 0
## Free-agent offers and signing history.
var fa := FreeAgency.new()
## Signings from the most recent resolution (free-agency day or week).
var last_signings: Array = []
## Every retirement, oldest first: Retirement.run records.
var retirements: Array = []
## Every re-signing: {soldier, team, salary, years, year}.
var resign_log: Array = []
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
## Regular-season week w -> the team on bye.
var _byes: Array = []
var _rng := RandomNumberGenerator.new()


## With `with_camp`, the franchise opens in preseason training camp (close_preseason_camp starts Week 1).
static func new_franchise(seed_value: int, user_team_index := 0, start_year := 2026, with_camp := false) -> Season:
	var s := Season.new()
	s.league = League.generate(seed_value, TEAM_COUNT)
	for i in s.league.teams.size():
		s.league.teams[i].user_controlled = (i == user_team_index)
	s.year = start_year
	var crng := RandomNumberGenerator.new()
	crng.seed = _mix([seed_value, start_year, 0xC0475])
	Contracts.assign_initial(s.league, start_year, crng)
	var roles := [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]
	for i in INITIAL_FREE_AGENTS:
		var so := PlayerGenerator.generate(crng, s.league.next_soldier_id, roles[i % roles.size()], crng.randf_range(50.0, 64.0))
		s.league.next_soldier_id += 1
		s.league.add_free_agent(so, start_year - 1)
	var mrng := RandomNumberGenerator.new()
	mrng.seed = _mix([seed_value, start_year, 0x307A1E])
	for so in s.league.all_soldiers():
		so.morale = mrng.randf_range(68.0, 84.0)
	s._begin_season()
	if with_camp:
		s.camp = Camp.make(start_year - 1)
		s.preseason_camp = true
		# Scouting opens in Week 1: the first week's points arrive when camp closes.
		s.draft.scout_points = 0
	return s


func user_team() -> Team:
	for t in league.teams:
		if t.user_controlled:
			return t
	return null


func total_weeks() -> int:
	return REGULAR_WEEKS + playoff_rounds()


## Number of knockout rounds needed for PLAYOFF_TEAMS (4 -> semis + final = 2).
func playoff_rounds() -> int:
	var rounds := 0
	var n := PLAYOFF_TEAMS
	while n > 1:
		n = ceili(n / 2.0)
		rounds += 1
	return rounds


func week_label(w: int) -> String:
	if w <= REGULAR_WEEKS:
		return "Week %d" % w
	var from_end := total_weeks() - w
	match from_end:
		0:
			return "Final"
		1:
			return "Semifinals"
		2:
			return "Quarterfinals"
	return "Playoffs Round %d" % (w - REGULAR_WEEKS)


func stage_for_week(w: int) -> StringName:
	if w <= REGULAR_WEEKS:
		return STAGE_REGULAR
	return STAGE_FINAL if w == total_weeks() else STAGE_SEMIFINAL


func matches_for_week(w: int) -> Array:
	if w >= 1 and w <= schedule.size():
		return schedule[w - 1]
	var out: Array = []
	for m in playoff_matches:
		if m.week == w:
			out.append(m)
	return out


func bye_team(w: int) -> Team:
	if w >= 1 and w <= _byes.size():
		return _byes[w - 1]
	return null


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
			row.rounds_won += m.rounds_for(t)
			row.rounds_lost += m.rounds_for(opp)
			if m.winner() == t:
				row.wins += 1
				h2h[t][opp] = int(h2h[t].get(opp, 0)) + 1
				results[t].append("W")
			else:
				row.losses += 1
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
	# Head-to-head wins among the teams tied on wins.
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
		if a.round_diff() != b.round_diff():
			return a.round_diff() > b.round_diff()
		if a.rounds_won != b.rounds_won:
			return a.rounds_won > b.rounds_won
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


func sim_week() -> Array:
	if phase == PHASE_OFFSEASON:
		return []
	close_preseason_camp()
	var played := matches_for_week(week)
	last_signings = fa.resolve(self, _rng, week_label(week))
	_prepare_lineups()
	for t in league.teams:
		Training.run_week(t)
	var played_ids := {}
	var playing_teams := {}
	for m in played:
		if not m.is_played():
			m.play()
			Progression.award_match_xp(m.result, year)
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
	for t in league.teams:
		Progression.auto_spend_team(t, _rng)
	Morale.update_week(league, played)
	var news_week := week
	_advance()
	last_prospect_news = []
	if phase != PHASE_OFFSEASON:
		last_prospect_news = draft.weekly_news(news_week)
		draft.scout_points += Draft.POINTS_PER_WEEK
		fa.ai_offers(self, _rng, true)
	return played


## AI teams pick intensities and rest tired/injured starters; every team (including the user's)
## gets injured starters swapped out so a match is never played by an injured soldier.
func _prepare_lineups() -> void:
	for t in league.teams:
		if t.user_controlled:
			t.fill_injured()
		else:
			t.auto_lineup(true)
			Training.ai_set_intensities(t)


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
	while offseason_stage != OFF_DONE:
		advance_offseason()
	for t in league.teams:
		for s in t.cut_to_limit():
			Contracts.charge_release(t, s, cap_year())
			league.add_free_agent(s, year)
		fa.fill_roster(self, t, ROSTER_MIN if t.user_controlled else Team.ROSTER_SIZE, "Preseason")
	fa.offers.clear()
	var arng := RandomNumberGenerator.new()
	arng.seed = _mix([league.league_seed, year, 0xA6E])
	aging_report = Aging.age_league(league, arng)
	year += 1
	for t in league.teams:
		Conditioning.reset(t)
		for so in t.roster:
			so.morale = lerpf(so.morale, Soldier.MORALE_NEUTRAL, 0.5)
		if t.user_controlled:
			t.fill_injured()
		else:
			t.auto_lineup()
	_begin_season()


## The season whose cap applies right now: this season, or next season during the offseason.
func cap_year() -> int:
	return year + (1 if phase == PHASE_OFFSEASON else 0)


## Offers can be made in-season and once the offseason reaches free agency.
func free_agency_open() -> bool:
	return phase != PHASE_OFFSEASON or offseason_stage in [OFF_FREE_AGENCY, OFF_CAMP, OFF_DONE]


func camp_open() -> bool:
	return preseason_camp or (phase == PHASE_OFFSEASON and offseason_stage == OFF_CAMP)


## Ends the opening preseason camp: AI teams run their drills and everyone gets camp-week XP.
func close_preseason_camp() -> void:
	if not preseason_camp:
		return
	for t in league.teams:
		if not t.user_controlled:
			camp.ai_run(t, _rng)
	offseason_xp(CAMP_WEEK_XP)
	preseason_camp = false
	draft.scout_points += Draft.POINTS_PER_WEEK


## Sends `s` to the user's `group` drill. Returns the Camp result ({} if refused; see camp_check).
func run_drill(group: StringName, s: Soldier) -> Dictionary:
	if not camp_open() or camp == null:
		return {}
	return camp.run(user_team(), group, s, _rng)


func camp_check(group: StringName, s: Soldier) -> String:
	if not camp_open() or camp == null:
		return "Training camp opens after free agency."
	return camp.check(user_team(), group, s)


func can_resign() -> bool:
	return phase == PHASE_OFFSEASON and (offseason_stage == OFF_RESIGN or offseason_stage == OFF_DRAFT)


## Moves the offseason one step: re-sign -> draft (AI teams re-sign) -> free agency (expiring
## and undrafted soldiers hit the pool, AI teams cut down) -> each free-agency day resolves
## offers -> training camp (AI teams run their drills, bonus XP) -> done. Finishes the draft
## with AI picks if it isn't done. Each step is an XP week. Returns new signings.
func advance_offseason() -> Array:
	if phase != PHASE_OFFSEASON:
		return []
	var signed: Array = []
	match offseason_stage:
		OFF_RESIGN:
			_ai_resign()
			offseason_stage = OFF_DRAFT
		OFF_DRAFT:
			finish_draft()
			_open_free_agency()
		OFF_FREE_AGENCY:
			last_signings = fa.resolve(self, _rng, "FA Day %d" % fa_day)
			signed = last_signings
			if fa_day >= FA_DAYS:
				offseason_stage = OFF_CAMP
			else:
				fa_day += 1
				fa.ai_offers(self, _rng)
		OFF_CAMP:
			for t in league.teams:
				if not t.user_controlled:
					camp.ai_run(t, _rng)
			offseason_xp(CAMP_WEEK_XP)
			offseason_stage = OFF_DONE
			return []
		_:
			return []
	offseason_xp(OFFSEASON_WEEK_XP)
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


## Re-signs one of `team`'s expiring soldiers at his asking price. Returns "" or the reason it failed.
func resign_player(team: Team, s: Soldier, years: int) -> String:
	if not can_resign():
		return "Re-signing is open from the end of the season until free agency."
	if s.contract == null or not s.contract.is_expiring() or not team.roster.has(s):
		return "%s isn't an expiring player on your roster." % s.full_name()
	if years < 1 or years > Contracts.MAX_YEARS:
		return "Deals run 1-%d years." % Contracts.MAX_YEARS
	var salary := Contracts.resign_asking(s, years)
	if not Contracts.fits(team, cap_year(), salary):
		return "Not enough cap space: he wants %s and you have %s." % [Contracts.money(salary), Contracts.money(Contracts.cap_space(team, cap_year()))]
	s.contract = Contract.make(salary, years, year)
	s.morale = maxf(s.morale, 82.0)
	resign_log.append({"soldier": s, "team": team, "salary": salary, "years": years, "year": year})
	return ""


## Releases a soldier into free agency, booking dead money for what's left on his deal.
## Returns the dead money.
func release_player(team: Team, s: Soldier) -> int:
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
			var keep := s.age <= 33 and (s.best_ovr() >= bar - 2 or (s.age <= 25 and s.potential >= 3))
			var yrs := Contracts.preferred_years(s)
			var salary := Contracts.resign_asking(s, yrs)
			if keep and Contracts.fits(t, cap_year(), salary):
				s.contract = Contract.make(salary, yrs, year)
				resign_log.append({"soldier": s, "team": t, "salary": salary, "years": yrs, "year": year})


func _open_free_agency() -> void:
	offseason_stage = OFF_FREE_AGENCY
	fa_day = 1
	for t in league.teams:
		for s in Contracts.expiring(t):
			departures.append({"soldier": s, "team": t, "year": year})
			t.release(s)
			league.add_free_agent(s, year)
	var undrafted: Array = draft.available()
	undrafted.sort_custom(func(a: Prospect, b: Prospect): return Draft.true_value(a) > Draft.true_value(b))
	for p in undrafted.slice(0, UNDRAFTED_TO_FA):
		league.add_free_agent(p.soldier, year)
	for t in league.teams:
		if t.user_controlled:
			continue
		# AI teams keep a spot open to bid on free agents (filled in preseason if they miss).
		for s in t.cut_to_limit(Team.ROSTER_SIZE - 1):
			Contracts.charge_release(t, s, cap_year())
			league.add_free_agent(s, year)
	fa.ai_offers(self, _rng)


## Round-1 draft order: teams that missed the playoffs first (worst record first), then
## semifinal losers, the runner-up, and the champion last.
func draft_order() -> Array:
	var finish := {}
	for t in league.teams:
		finish[t] = 0
	for m in playoff_matches:
		if not m.is_played():
			continue
		for t: Team in [m.home, m.away]:
			finish[t] = maxi(finish[t], 1)
		if m.stage == STAGE_FINAL:
			finish[m.opponent_of(m.winner())] = 2
			finish[m.winner()] = 3
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
	return Draft.snake(draft_order())


## Completes the draft (AI picks for everyone still on the clock, including the user).
## Roster cut-downs happen when free agency opens. Safe to call more than once.
func finish_draft() -> void:
	if phase != PHASE_OFFSEASON:
		return
	if not draft.is_started():
		draft.set_order(draft_order())
	draft.sim_to_end()


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
	_build_schedule()
	draft = Draft.generate(_mix([league.league_seed, year, 0xD2AF]), year, league.next_soldier_id)
	draft.league = league
	league.next_soldier_id += Draft.CLASS_SIZE
	draft.scout_points = Draft.POINTS_PER_WEEK
	league.ensure_callsigns()


func _advance() -> void:
	week += 1
	if phase == PHASE_REGULAR:
		if week > REGULAR_WEEKS:
			phase = PHASE_PLAYOFFS
			_create_first_playoff_round()
		return
	# Playoffs: create the next round from this round's winners, or crown the champion.
	var last_round := matches_for_week(week - 1)
	if last_round.size() == 1:
		champion = last_round[0].winner()
		phase = PHASE_OFFSEASON
		var rrng := RandomNumberGenerator.new()
		rrng.seed = _mix([league.league_seed, year, 0x4E71])
		review = SeasonReview.run(self, rrng)
		review_history.append(review)
		var retire_rng := RandomNumberGenerator.new()
		retire_rng.seed = _mix([league.league_seed, year, 0x2E71])
		retirements.append_array(Retirement.run(self, retire_rng))
		Contracts.rollover(league)
		offseason_stage = OFF_RESIGN
		fa_day = 0
		camp = Camp.make(year)
		draft.set_order(draft_order())
		return
	var winners: Array = []
	for m in last_round:
		winners.append(m.winner())
	_create_round(winners)


func _create_first_playoff_round() -> void:
	var seeds: Array = []
	for r in standings().slice(0, PLAYOFF_TEAMS):
		seeds.append(r.team)
	_create_round(seeds)


## `teams` ordered by seed (best first); pairs 1 v N, 2 v N-1, ... with the better seed at home.
## For later rounds the winners keep bracket order, so slot i plays slot N-1-i.
func _create_round(teams: Array) -> void:
	var n := teams.size()
	for i in n / 2:
		var m := ScheduledMatch.new()
		m.week = week
		m.stage = stage_for_week(week)
		m.home = teams[i]
		m.away = teams[n - 1 - i]
		m.match_seed = _match_seed(week, i)
		playoff_matches.append(m)


## Circle-method round robin (dummy BYE slot for odd counts); second half mirrors the first
## with home/away swapped. Team order is shuffled deterministically per league seed + year.
func _build_schedule() -> void:
	schedule = []
	_byes = []
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
		first_byes.append(bye)
		# Rotate all but the first slot.
		var last = order.pop_back()
		order.insert(1, last)
	var rounds_needed := REGULAR_WEEKS
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

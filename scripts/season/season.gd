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
## Regular-season week w -> the team on bye.
var _byes: Array = []
var _rng := RandomNumberGenerator.new()


static func new_franchise(seed_value: int, user_team_index := 0, start_year := 2026) -> Season:
	var s := Season.new()
	s.league = League.generate(seed_value, TEAM_COUNT)
	for i in s.league.teams.size():
		s.league.teams[i].user_controlled = (i == user_team_index)
	s.year = start_year
	s._begin_season()
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
	var played := matches_for_week(week)
	_prepare_lineups()
	for t in league.teams:
		Training.run_week(t)
	var played_ids := {}
	var playing_teams := {}
	for m in played:
		if not m.is_played():
			m.play()
			Progression.award_match_xp(m.result)
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
	_advance()
	if phase != PHASE_OFFSEASON:
		draft.scout_points += Draft.POINTS_PER_WEEK
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
	finish_draft()
	year += 1
	for t in league.teams:
		Conditioning.reset(t)
	_begin_season()


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


## Completes the draft (AI picks for everyone still on the clock, including the user) and cuts
## every roster down to Team.ROSTER_SIZE. Safe to call more than once.
func finish_draft() -> void:
	if phase != PHASE_OFFSEASON:
		return
	if not draft.is_started():
		draft.set_order(draft_order())
	draft.sim_to_end()
	for t in league.teams:
		t.cut_to_limit()


# --- internals -------------------------------------------------------------

func _begin_season() -> void:
	week = 1
	phase = PHASE_REGULAR
	champion = null
	playoff_matches = []
	last_injuries = []
	injury_log = []
	_rng.seed = _mix([league.league_seed, year, 0x5EA5])
	_build_schedule()
	draft = Draft.generate(_mix([league.league_seed, year, 0xD2AF]), year, league.next_soldier_id)
	league.next_soldier_id += Draft.CLASS_SIZE
	draft.scout_points = Draft.POINTS_PER_WEEK


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

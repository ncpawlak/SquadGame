class_name LeagueNews
extends RefCounted
## League-wide news wire. Stories are templates fired by conditions, never by names, so the same
## story finds whoever fits it in any season (today's Detroit captain, a different contender's
## veteran three years on). Every story is true to the numbers it quotes, and most carry a light
## effect:
##   last_ride        veteran (33+, 85+ OVR, final contract year or 35+) on a contender.
##                    Preseason story, morale +4; reaching the playoffs adds morale +6.
##   hometown         a starter playing for his home-state club wins a home game. Morale +4.
##   contract_year    final-year player (31 or younger) up 3+ OVR since the season began. Morale +3.
##   rookie_starter   last offseason's draftee starts one of his team's first three games. Morale +4.
##   bust             a top-3 pick, 24+ and 3+ years in, still below 80 OVR. Morale -3.
##   trade_request    a player's trade request goes public. Morale -3.
##   rivalry          a rivalry game: the winners +2 morale, the losers -2 (+/-3 for the marquee).
##   champion / floor season-end headlines (title, salary-floor penalties).
## Per-player stories fire once (a season for seasonal ones, a career for the rest; tracked in
## Soldier.news_tags), and at most MAX_PER_KIND of a kind run in one week.

const MAX_ITEMS := 600
const MAX_PER_KIND := 3
const LAST_RIDE_AGE := 33
const LAST_RIDE_OVR := 85
const CONTENDERS := 6
const BREAKOUT_GAIN := 3
const BUST_OVR := 80

## Newest last: {year, when, kind, headline, body, teams: [abbrev], soldier_id}.
var items: Array = []
## Soldier id -> best OVR when this season began (for contract-year breakouts).
var start_ovr := {}
var _counts := {}


func latest(n: int, team_abbrev := "") -> Array:
	var out: Array = []
	for i in range(items.size() - 1, -1, -1):
		if team_abbrev == "" or items[i]["teams"].has(team_abbrev):
			out.append(items[i])
			if out.size() >= n:
				break
	return out


func for_year(y: int) -> Array:
	return items.filter(func(it): return it["year"] == y)


## Preseason: snapshot OVRs and write the last-ride stories.
func begin_season(season: Season) -> void:
	start_ovr = {}
	for s in season.league.all_soldiers():
		start_ovr[s.id] = s.best_ovr()
	var contenders := season.league.teams.duplicate()
	contenders.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	contenders = contenders.slice(0, CONTENDERS)
	var count := 0
	for t: Team in contenders:
		for s in t.roster:
			if count >= MAX_PER_KIND:
				break
			var final_year := s.contract != null and s.contract.years <= 1
			if s.age < LAST_RIDE_AGE or s.best_ovr() < LAST_RIDE_OVR or not (final_year or s.age >= 35):
				continue
			if not _tag(s, "last_ride", season.year):
				continue
			count += 1
			s.add_morale(4.0)
			var why := "with his contract up after this season" if final_year else "at %d" % s.age
			_add(season, "Preseason", "last_ride", [t.abbrev], s.id,
				"%s wants one more ring before he hangs it up" % s.display_name(),
				"%s (%d OVR) enters what could be his final season %s. \"I want to bring a championship home to %s before I'm done.\" The %s are a contender, and the room is rallying around him." % [
					s.full_name(), s.best_ovr(), why, t.city, t.nickname])


## After a week is played: rivalry results, then player stories.
func week_stories(season: Season, played: Array, wk: int) -> void:
	var when := season.week_label(wk)
	_counts = {}
	var counts := _counts
	var winners := {}
	for m: ScheduledMatch in played:
		if not m.is_played():
			continue
		winners[m.winner()] = m
		if LeagueData.rivals(m.home.abbrev, m.away.abbrev):
			_rivalry(season, m, when)
	var home_winners := {}
	for t in winners:
		if winners[t].home == t:
			home_winners[t] = true
	for t: Team in season.league.teams:
		var starters := t.starters()
		for s in t.roster:
			# Hometown hero: a starter for his home-state club, in a home win.
			if home_winners.has(t) and s.home_state != "" and s.home_state == t.home_state \
					and starters.has(s) and _room(counts, "hometown") and _tag(s, "hometown:" + t.abbrev, season.year):
				s.add_morale(4.0)
				_add(season, when, "hometown", [t.abbrev], s.id,
					"Hometown kid %s delivers for %s" % [s.display_name(), t.city],
					"%s grew up in %s and starts for the %s. Today's home win in front of family and friends was one he'll remember." % [
						s.full_name(), LeagueData.state_name(s.home_state), t.nickname])
			# Contract-year breakout.
			if wk >= 5 and s.contract != null and s.contract.years == 1 and s.age <= 31 and start_ovr.has(s.id) \
					and s.best_ovr() - int(start_ovr[s.id]) >= BREAKOUT_GAIN and _room(counts, "contract_year") \
					and _tag(s, "contract_year", season.year):
				s.add_morale(3.0)
				_add(season, when, "contract_year", [t.abbrev], s.id,
					"%s is playing for his next contract" % s.display_name(),
					"In the last year of his deal, %s has climbed from %d to %d OVR this season. His agent will be busy this offseason." % [
						s.full_name(), int(start_ovr[s.id]), s.best_ovr()])
			# Rookie wins a starting job.
			if wk <= 3 and s.draft_year == season.year - 1 and starters.has(s) and _played(t, played):
				if _room(counts, "rookie_starter") and _tag(s, "rookie_starter", 0):
					s.add_morale(4.0)
					var pick := ("the #%d pick" % s.draft_pick) if s.draft_pick > 0 else "a rookie"
					_add(season, when, "rookie_starter", [t.abbrev], s.id,
						"Rookie %s wins a starting job" % s.display_name(),
						"%s, %s in %d, has cracked the %s starting five at %d OVR." % [
							s.full_name(), pick, s.draft_year, t.nickname, s.best_ovr()])
			# Former top pick bust.
			if s.draft_pick >= 1 and s.draft_pick <= 3 and s.age >= 24 and season.year - s.draft_year >= 3 \
					and s.best_ovr() < BUST_OVR and _room(counts, "bust") and _tag(s, "bust", 0):
				s.add_morale(-3.0)
				_add(season, when, "bust", [t.abbrev], s.id,
					"Is %s the biggest miss of the %d draft?" % [s.display_name(), s.draft_year],
					"Taken #%d overall in %d, %s is %d and still sits at %d OVR. Patience is running out." % [
						s.draft_pick, s.draft_year, s.full_name(), s.age, s.best_ovr()])
			# Public trade request.
			if s.trade_request and _room(counts, "trade_request") and _tag(s, "trade_request", season.year):
				s.add_morale(-3.0)
				_add(season, when, "trade_request", [t.abbrev], s.id,
					"%s asks %s for a trade" % [s.display_name(), t.city],
					"%s (%d OVR) has gone public: he wants out of %s. The %s say they will listen to offers." % [
						s.full_name(), s.best_ovr(), t.city, t.nickname])
	# The playoffs begin: last-ride veterans whose teams made it get a lift.
	if season.phase == Season.PHASE_PLAYOFFS and wk == season.regular_weeks:
		for t in season.playoff_seeds:
			for s in t.roster:
				if int(s.news_tags.get("last_ride", 0)) == season.year and _tag(s, "last_ride_playoffs", season.year):
					s.add_morale(6.0)
					_add(season, season.week_label(season.regular_weeks + 1), "last_ride", [t.abbrev], s.id,
						"%s's last ride reaches the playoffs" % s.display_name(),
						"The %s are the #%d seed, and %s gets one more shot at a title." % [
							t.nickname, int(season.playoff_seeds[t]), s.full_name()])


## Season-end headlines: the champion (and any last ride that ended with a ring), floor penalties.
func end_season(season: Season, penalties: Array) -> void:
	var champ := season.champion
	if champ != null:
		var runner: Team = null
		for m in season.playoff_matches:
			if m.stage == Season.STAGE_FINAL:
				runner = m.loser()
		_add(season, "Final", "champion", [champ.abbrev], 0,
			"%s win the %d championship" % [champ.name, season.year],
			"The %s beat %s in the final to lift the title." % [champ.nickname, runner.name if runner else "their rival"])
		for s in champ.roster:
			if int(s.news_tags.get("last_ride", 0)) == season.year:
				_add(season, "Final", "last_ride", [champ.abbrev], s.id,
					"%s gets his ring" % s.display_name(),
					"%s chased one more title and got it. Whatever he decides next, he goes out a champion." % s.full_name())
	for p in penalties:
		var t: Team = p["team"]
		_add(season, "Offseason", "floor", [t.abbrev], 0,
			"%s fined for spending under the salary floor" % t.name,
			"The %s finished under the %s floor and owe the %s shortfall next season." % [
				t.nickname, Contracts.money(Contracts.SALARY_FLOOR), Contracts.money(p["amount"])])


func _rivalry(season: Season, m: ScheduledMatch, when: String) -> void:
	var w := m.winner()
	var l := m.loser()
	var marquee := LeagueData.is_marquee(m.home.abbrev, m.away.abbrev)
	var swing := 3.0 if marquee else 2.0
	for s in w.roster:
		s.add_morale(swing)
	for s in l.roster:
		s.add_morale(-swing)
	var games := "%d-%d" % [m.games_for(w), m.games_for(l)]
	_add(season, when, "rivalry", [w.abbrev, l.abbrev], 0,
		"%s take the %s rivalry game %s" % [w.name, "marquee" if marquee else l.city, games],
		"Bragging rights to the %s. The %s will hear about this one until the rematch." % [w.nickname, l.nickname])


func _played(t: Team, played: Array) -> bool:
	for m in played:
		if m.is_played() and m.involves(t):
			return true
	return false


func _room(counts: Dictionary, kind: String) -> bool:
	return int(counts.get(kind, 0)) < MAX_PER_KIND


## Marks story `kind` as written about `s` (`yr` = 0 for once-a-career). False if already written.
func _tag(s: Soldier, kind: String, yr: int) -> bool:
	if s.news_tags.has(kind) and (yr == 0 or int(s.news_tags[kind]) == yr):
		return false
	s.news_tags[kind] = yr if yr > 0 else 1
	return true


func _add(season: Season, when: String, kind: String, teams: Array, soldier_id: int, headline: String, body: String) -> void:
	items.append({"year": season.year, "when": when, "kind": kind, "headline": headline, "body": body,
		"teams": teams, "soldier_id": soldier_id})
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	if items.size() > MAX_ITEMS:
		items = items.slice(items.size() - MAX_ITEMS)

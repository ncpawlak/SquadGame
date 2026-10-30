class_name Market
extends RefCounted
## A team's market and its buzz (issue #8, phase 1; revenue comes later).
##
## Market rating (Team.market_rating, 1-100) is fixed: the size and money of the city. Nobody's city
## shrinks because the team is bad. It is shown as a tier (Small, Regional, Major, Metropolis, Mega).
##
## Buzz (Team.buzz, 0-100) is the part that moves: how much the city and the league care about the club,
## in the bands Ice Cold, Cooling, Steady, Warm, Hot and Electric. Results and events never move it
## directly. They add heat (Team.heat), a reservoir that buzz absorbs at WEEK_CAP points a week at most,
## so a team cannot go from hot to cold in a few weeks (and it gets harder to push toward either end): four straight losses start the cooling, and a
## collapse takes a month or more to cross a band. Buzz also drifts back toward its resting level, which
## is higher in a bigger market (baseline). Offseason steps drain heat too.
##
## Points use no RNG. Every event is logged on the team (Team.market_log) so the UI and news can say why
## buzz moved. Later phases make revenue roughly market rating x buzz.

const TIER_NAMES := ["Small Market", "Regional Market", "Major Market", "Metropolis", "Mega Market"]
const BAND_NAMES := ["Ice Cold", "Cooling", "Steady", "Warm", "Hot", "Electric"]
## Lowest buzz of each band.
const BAND_STARTS := [0.0, 20.0, 40.0, 60.0, 75.0, 90.0]
## Resting buzz: BASELINE_BASE plus BASELINE_PER_RATING per rating point (about 40 for the smallest
## market, 65 for the biggest).
const BASELINE_BASE := 38.0
const BASELINE_PER_RATING := 0.28
## Most buzz absorbed from heat in one week (or offseason step), the share of the heat absorbed, how much
## of the gap to the baseline closes, and the heat reservoir limit.
const WEEK_CAP := 3.0
const ABSORB := 0.5
const DECAY := 0.03
const HEAT_MAX := 40.0
## A band story needs buzz this far past the line, so a team hovering on a boundary stays quiet.
const BAND_MARGIN := 2.0
const BAND_STORIES_PER_TICK := 3
## Pushes toward an end of the scale shrink once within HEADROOM_SPAN of it, down to HEADROOM_MIN.
const HEADROOM_SPAN := 25.0
const HEADROOM_MIN := 0.25
## Entries kept in a team's log (about three seasons).
const LOG_MAX := 240

## Home crowd: the home squad's rating points at a given buzz. Nothing at CROWD_FLOOR buzz or below, the full
## CROWD_MAX at buzz 100 (about one OVR point, small beside match-day form). Set CROWD_MAX to 0 to switch it off.
const CROWD_MAX := 1.0
const CROWD_FLOOR := 40.0

# In-season points.
const WIN := 1.0
const LOSS := -0.75
const RIVAL_LOSS := -1.0
const POTW := 2.0
const UPSET := 1.0
const WIN_STREAKS := {3: 2.0, 5: 3.0, 8: 4.0}
const LOSS_STREAK := 4
const LOSS_STREAK_POINTS := -2.0
# Season close-out.
const MAKE_PLAYOFFS := 5.0
const MISS_PLAYOFFS := -3.0
const UNDER_500 := -2.0
const SWEPT_BY_RIVAL := -2.0
const PLAYOFF_WIN := 4.0
const REACH_FINAL := 6.0
const TITLE := 12.0
const BACK_TO_BACK := 4.0
const DROUGHT_YEARS := 5
const DROUGHT := -1.0
const SEED_OUT := -2.0
## Beating or missing expectations: 0.4 a place, up to 4. A bigger market is expected to finish
## higher: EXPECT_PER_TIER places per tier above Major.
const EXPECT_STEP := 0.4
const EXPECT_MAX := 4.0
const EXPECT_PER_TIER := 1.5
const SUPERSTAR_OVR := 90
const STAR_OVR := 80
const SUPERSTAR_POINTS := 1.5
const STAR_POINTS := 0.5
const STAR_CAP := 4.0
const HOMETOWN_STARTERS := 3
const HOMETOWN_POINTS := 1.0
const MVP_POINTS := 3.0
const AWARD_POINTS := 1.0
## A weekly leader story needs at least this many points earned in a week.
const BUZZ_MIN := 3.0
## Opening championship history (Detroit are the defending champions).
const OPENING_TITLES := {"DET": [2025]}
## Story kind -> [points for the first team, points for the second]. A kind counts at most STORY_CAP
## times a year per team.
const STORY_POINTS := {
	"mega_deal": [2.0, 0.0], "fa_signing": [2.0, 0.0], "homecoming": [1.0, 0.0], "resign": [1.0, 0.0],
	"defection": [1.0, -1.0], "draft_top": [2.0, 0.0], "draft_slide": [2.0, 0.0], "draft_haul": [2.0, 0.0],
	"surprise_cut": [-1.0, 0.0], "trade_request": [-1.0, 0.0], "hits_market": [-1.0, 0.0],
}
const STORY_CAP := 2

var seeded := false
## Abbrev -> 1..n by team OVR when this season began.
var preseason_rank := {}
## Abbrev -> current streak (+wins, -losses) this regular season.
var streak := {}
## "ABC|XYZ" -> {n, wins: {abbrev: count}} for rivalry meetings this season.
var series := {}
## Abbrev -> buzz when this season began (for the year-in-review).
var start_buzz := {}
## Abbrev -> points earned in the latest week (for the weekly leader).
var week_gain := {}
## Abbrev -> the band index last written about.
var announced := {}
## "ABC:kind:year" -> story points handed out (STORY_CAP).
var story_counts := {}
## Abbrev -> Array[int] championship years.
var titles := {}


# --- scales ---------------------------------------------------------------------------

## 1 (Small) .. 5 (Mega) for a market rating.
static func tier_of(rating: int) -> int:
	return clampi(1 + (rating - 1) / 20, 1, TIER_NAMES.size())


static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, 1, TIER_NAMES.size()) - 1]


## "Mega Market".
static func market_name(team: Team) -> String:
	return tier_name(tier_of(team.market_rating))


## 0 (Ice Cold) .. 5 (Electric) for a buzz value.
static func band_of(value: float) -> int:
	var idx := 0
	for i in BAND_STARTS.size():
		if value >= BAND_STARTS[i]:
			idx = i
	return idx


static func band_name(value: float) -> String:
	return BAND_NAMES[band_of(value)]


## Rating points the home crowd adds to `team`'s squad at its current buzz.
static func crowd_edge(team: Team) -> float:
	return CROWD_MAX * clampf((team.buzz - CROWD_FLOOR) / (100.0 - CROWD_FLOOR), 0.0, 1.0)


## Where a team's buzz settles with no news: higher in a bigger market.
static func baseline(team: Team) -> float:
	return BASELINE_BASE + BASELINE_PER_RATING * team.market_rating


## &"up" or &"down" while the heat that buzz has yet to absorb is large, else &"flat".
static func trend(team: Team) -> StringName:
	if team.heat >= 1.5:
		return &"up"
	if team.heat <= -1.5:
		return &"down"
	return &"flat"


## "Mega Market  98" for a card line.
static func market_text(team: Team) -> String:
	return "%s  %d" % [market_name(team), team.market_rating]


## "Hot  77  rising" for a card line.
static func buzz_text(team: Team) -> String:
	var t := trend(team)
	return "%s  %d%s" % [band_name(team.buzz), roundi(team.buzz), "  rising" if t == &"up" else ("  cooling" if t == &"down" else "")]


## This year's log entries for `team`, newest first.
static func log_for(team: Team, year: int) -> Array:
	var out: Array = []
	for i in range(team.market_log.size() - 1, -1, -1):
		if int(team.market_log[i]["year"]) == year:
			out.append(team.market_log[i])
	return out


## The biggest logged events of `year` for `team`: gains (sign > 0) or drops (sign < 0), largest first.
## Each is {label, amount}; the league-average adjustment is left out.
static func drivers(team: Team, year: int, sign: int, n: int) -> Array:
	var out: Array = []
	for e in log_for(team, year):
		var a := float(e["amount"])
		if signf(a) == float(sign) and not String(e["label"]).begins_with("League average"):
			out.append(e)
	out.sort_custom(func(x, y): return absf(float(x["amount"])) > absf(float(y["amount"])))
	return out.slice(0, n)


# --- setup ----------------------------------------------------------------------------

## Ratings, opening buzz and championship history. Also runs on loading an older save that predates markets.
func ensure(season: Season) -> void:
	if seeded:
		return
	seeded = true
	for t: Team in season.league.teams:
		t.market_rating = int(LeagueData.MARKET_RATINGS.get(t.abbrev, 50))
		t.buzz = float(LeagueData.START_BUZZ.get(t.abbrev, baseline(t)))
		t.heat = 0.0
		t.market_log = []
		announced[t.abbrev] = band_of(t.buzz)
	for ab in OPENING_TITLES:
		titles[ab] = (OPENING_TITLES[ab] as Array).duplicate()


func begin_season(season: Season) -> void:
	ensure(season)
	var ranked := season.league.teams.duplicate()
	ranked.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	preseason_rank = {}
	for i in ranked.size():
		preseason_rank[(ranked[i] as Team).abbrev] = i + 1
	streak = {}
	series = {}
	week_gain = {}
	start_buzz = {}
	for t: Team in season.league.teams:
		start_buzz[t.abbrev] = t.buzz


# --- points ---------------------------------------------------------------------------

## Adds heat (the reservoir buzz absorbs from) and logs why.
func award(season: Season, team: Team, when: String, label: String, amount: float) -> void:
	if team == null or is_zero_approx(amount):
		return
	team.heat = clampf(team.heat + amount, -HEAT_MAX, HEAT_MAX)
	team.market_log.append({"year": season.year, "when": when, "label": label, "amount": snappedf(amount, 0.05)})
	if team.market_log.size() > LOG_MAX:
		team.market_log = team.market_log.slice(team.market_log.size() - LOG_MAX)
	week_gain[team.abbrev] = float(week_gain.get(team.abbrev, 0.0)) + amount


## A story (LeagueNews kinds) adds heat for the teams it names.
func story(season: Season, kind: String, teams: Array, headline: String) -> void:
	ensure(season)
	if not STORY_POINTS.has(kind):
		return
	var pts: Array = STORY_POINTS[kind]
	for i in mini(teams.size(), 2):
		var t := season.league.team_by_abbrev(teams[i])
		if t == null or is_zero_approx(float(pts[i])):
			continue
		var key := "%s:%s:%d" % [t.abbrev, kind, season.year]
		if int(story_counts.get(key, 0)) >= STORY_CAP:
			continue
		story_counts[key] = int(story_counts.get(key, 0)) + 1
		award(season, t, season.step_label() if season.phase == Season.PHASE_OFFSEASON else season.week_label(season.week), "In the news: %s" % headline, float(pts[i]))


## After a week is played and the calendar has advanced (phase and week are already the next ones).
func week(season: Season, played: Array, w: int) -> void:
	ensure(season)
	week_gain = {}
	var when := season.week_label(w)
	for m: ScheduledMatch in played:
		if m.is_played():
			_match(season, m, when)
	var potw := SeasonReview.player_of_week(season, w)
	if not potw.is_empty():
		award(season, potw["team"], when, "Player of the week (%s)" % (potw["soldier"] as Soldier).display_name(), POTW)
	if season.phase == Season.PHASE_PLAYOFFS and w == season.regular_weeks:
		_regular_season_over(season, when)
	elif season.phase == Season.PHASE_OFFSEASON:
		_season_over(season)
	tick(season, when)
	if season.phase != Season.PHASE_OFFSEASON:
		_leader(season, when)


## Buzz absorbs heat (at most WEEK_CAP) and drifts toward its resting level. Runs every week and every
## offseason step; writes the band-change stories.
func tick(season: Season, when: String) -> void:
	ensure(season)
	var changed: Array = []
	for t: Team in season.league.teams:
		var step := t.heat
		if absf(step) > 0.5:
			step = clampf(t.heat * ABSORB, -WEEK_CAP, WEEK_CAP)
		t.heat -= step
		t.buzz = clampf(t.buzz + step * _headroom(t.buzz, step) + (baseline(t) - t.buzz) * DECAY, 0.0, 100.0)
		var idx := band_of(t.buzz)
		var was := int(announced.get(t.abbrev, idx))
		if idx > was and t.buzz >= BAND_STARTS[idx] + BAND_MARGIN:
			changed.append({"team": t, "band": idx, "was": was})
		elif idx < was and t.buzz <= BAND_STARTS[was] - BAND_MARGIN:
			changed.append({"team": t, "band": idx, "was": was})
	changed.sort_custom(func(a, b): return absi(int(a["band"]) - int(a["was"])) > absi(int(b["band"]) - int(b["was"])))
	for c in changed.slice(0, BAND_STORIES_PER_TICK):
		var t: Team = c["team"]
		announced[t.abbrev] = int(c["band"])
		season.news.buzz_band(season, when, t, int(c["band"]) > int(c["was"]))


## Diminishing returns at the ends: the closer buzz is to 100 (or 0) the less a push toward it moves it.
static func _headroom(value: float, step: float) -> float:
	var room := (100.0 - value) if step > 0.0 else value
	return clampf(room / HEADROOM_SPAN, HEADROOM_MIN, 1.0)


func _match(season: Season, m: ScheduledMatch, when: String) -> void:
	var w := m.winner()
	var l := m.loser()
	var postseason := m.stage != Season.STAGE_REGULAR
	if not postseason:
		award(season, w, when, "Win over %s" % l.abbrev, WIN)
		award(season, l, when, "Loss to %s" % w.abbrev, LOSS)
		_streaks(season, w, l, when)
	if tier_of(l.market_rating) > tier_of(w.market_rating):
		award(season, w, when, "Upset win over %s (%s)" % [l.abbrev, market_name(l)], UPSET)
	if season.rivalries.is_rivalry(w, l):
		award(season, w, when, "Rivalry win over %s" % l.abbrev, season.rivalries.swing(w, l))
		award(season, l, when, "Rivalry loss to %s" % w.abbrev, RIVAL_LOSS)
		if not postseason:
			var k := Rivalries.key(w.abbrev, l.abbrev)
			if not series.has(k):
				series[k] = {"n": 0, "wins": {}}
			series[k]["n"] += 1
			series[k]["wins"][w.abbrev] = int(series[k]["wins"].get(w.abbrev, 0)) + 1
	match m.stage:
		Season.STAGE_QUARTERFINAL:
			award(season, w, when, "Playoff win over %s" % l.abbrev, PLAYOFF_WIN)
			if int(season.playoff_seeds.get(l, 99)) <= 3:
				award(season, l, when, "Top-3 seed out in round one", SEED_OUT)
		Season.STAGE_SEMIFINAL:
			award(season, w, when, "Playoff win over %s" % l.abbrev, PLAYOFF_WIN)
			award(season, w, when, "Reached the final", REACH_FINAL)
		Season.STAGE_FINAL:
			award(season, w, when, "Playoff win over %s" % l.abbrev, PLAYOFF_WIN)


func _streaks(season: Season, w: Team, l: Team, when: String) -> void:
	var ws := int(streak.get(w.abbrev, 0))
	ws = ws + 1 if ws > 0 else 1
	streak[w.abbrev] = ws
	if WIN_STREAKS.has(ws):
		award(season, w, when, "%d straight wins" % ws, float(WIN_STREAKS[ws]))
	var ls := int(streak.get(l.abbrev, 0))
	ls = ls - 1 if ls < 0 else -1
	streak[l.abbrev] = ls
	if ls == -LOSS_STREAK:
		award(season, l, when, "%d straight losses" % LOSS_STREAK, LOSS_STREAK_POINTS)


## The regular season just ended: playoff berths, records, expectations, stars and rival sweeps.
func _regular_season_over(season: Season, when: String) -> void:
	var rows := season.standings()
	for i in rows.size():
		var r: StandingRow = rows[i]
		var t := r.team
		if season.playoff_seeds.has(t):
			award(season, t, when, "Made the playoffs (#%d seed)" % int(season.playoff_seeds[t]), MAKE_PLAYOFFS)
		else:
			award(season, t, when, "Missed the playoffs", MISS_PLAYOFFS)
		if r.wins < r.losses:
			award(season, t, when, "Finished under .500 (%d-%d)" % [r.wins, r.losses], UNDER_500)
		if preseason_rank.has(t.abbrev):
			var expected := float(preseason_rank[t.abbrev]) - EXPECT_PER_TIER * (tier_of(t.market_rating) - 3)
			var pts := snappedf(clampf((expected - (i + 1)) * EXPECT_STEP, -EXPECT_MAX, EXPECT_MAX), 0.5)
			if pts > 0.0:
				award(season, t, when, "Beat expectations (finished #%d)" % (i + 1), pts)
			elif pts < 0.0:
				award(season, t, when, "Fell short of expectations (finished #%d)" % (i + 1), pts)
		var star_pts := 0.0
		var hometown := 0
		for s in t.roster:
			if s.best_ovr() >= SUPERSTAR_OVR:
				star_pts += SUPERSTAR_POINTS
			elif s.best_ovr() >= STAR_OVR:
				star_pts += STAR_POINTS
		for s in t.starters():
			if s.home_state != "" and s.home_state == t.home_state:
				hometown += 1
		award(season, t, when, "Star power", minf(star_pts, STAR_CAP))
		if hometown >= HOMETOWN_STARTERS:
			award(season, t, when, "Hometown starters (%d)" % hometown, HOMETOWN_POINTS)
	for k in series:
		var rec: Dictionary = series[k]
		if int(rec["n"]) < 2:
			continue
		var pair: PackedStringArray = (k as String).split("|")
		for ab in pair:
			if int(rec["wins"].get(ab, 0)) == 0:
				var other := pair[1] if ab == pair[0] else pair[0]
				award(season, season.league.team_by_abbrev(ab), when, "Swept by rival %s" % other, SWEPT_BY_RIVAL)


## The final is played: title, droughts and awards.
func _season_over(season: Season) -> void:
	var champ := season.champion
	if champ != null:
		award(season, champ, "Final", "Won the %d championship" % season.year, TITLE)
		if not titles.has(champ.abbrev):
			titles[champ.abbrev] = []
		(titles[champ.abbrev] as Array).append(season.year)
		if (titles[champ.abbrev] as Array).has(season.year - 1):
			award(season, champ, "Final", "Back-to-back titles", BACK_TO_BACK)
	for ab in titles:
		var last := int((titles[ab] as Array).max())
		if season.year - last >= DROUGHT_YEARS and (champ == null or champ.abbrev != ab):
			award(season, season.league.team_by_abbrev(ab), "Final", "Title drought (%d years)" % (season.year - last), DROUGHT)
	if season.review != null:
		for a in season.review.awards:
			var mvp: bool = a["award"] == "Season MVP"
			award(season, a["team"], "Final", "%s (%s)" % [a["award"], (a["soldier"] as Soldier).display_name()], MVP_POINTS if mvp else AWARD_POINTS)
	_share(season)


## Attention is relative: at season's end every team gives back the league's average yearly gain, so the
## league does not inflate and only teams that did better than the pack end the year hotter.
func _share(season: Season) -> void:
	var totals := {}
	var sum := 0.0
	for t: Team in season.league.teams:
		var tot := 0.0
		for e in log_for(t, season.year):
			tot += float(e["amount"])
		totals[t] = tot
		sum += tot
	var mean := sum / maxf(1.0, season.league.teams.size())
	for t: Team in season.league.teams:
		award(season, t, "Final", "League average (%+.1f): attention is shared" % mean, -mean)


## The week's biggest earner makes the wire.
func _leader(season: Season, when: String) -> void:
	var best: Team = null
	var best_gain := BUZZ_MIN
	for t: Team in season.league.teams:
		var g := float(week_gain.get(t.abbrev, 0.0))
		if g > best_gain:
			best = t
			best_gain = g
	if best != null:
		season.news.buzz_leader(season, when, best, best_gain)

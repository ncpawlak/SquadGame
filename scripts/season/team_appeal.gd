class_name TeamAppeal
extends RefCounted
## How attractive a club is to one soldier (issue #8). Read-only and not wired into anything yet: the
## negotiation rework (#5) and the pay revamp (#41) are meant to call it for re-signing and free agency.
##
## Each of his DNA motivations scores the club 0..1, and his motivation strengths weigh them, so a
## money-minded soldier cares about the market, a winner about results, and so on:
##   money         the club's market rating (pay and endorsements follow the city)
##   winning       how the club is actually doing (record, or roster strength before games are played) and
##                 its buzz
##   playing_time  whether he would start: where he ranks on the club's roster
##   loyalty       his own club (a soldier on the roster, or whose last club it was) over strangers
##   security      a financially steady club (cash against its yearly revenue)
##   hometown      his home state's club, then his home region's
## The score is 50 plus how far each motivation pulls it (strength x how the club does against an even 0.5,
## scaled by DEVIATION_SCALE), kept within 0..100, so a soldier who barely cares about anything scores
## about 50 for every club. `breakdown` says why.

const NEUTRAL := 0.5
## Roster ranks (by OVR) that start.
const STARTERS := 5
const LOYAL_HOME := 1.0
const LOYAL_STRANGER := 0.3
## The sum of motivation strengths a typical soldier has (about six at 0.5): a club that is perfect on
## everything he cares about moves the score by roughly 100 x 0.5 x that sum / DEVIATION_SCALE.
const DEVIATION_SCALE := 4.0
const RESULT_WEIGHT := 0.7


## The 0..100 score of `team` for `s`.
static func score(s: Soldier, team: Team, season: Season) -> float:
	var total := NEUTRAL * 100.0
	for r in breakdown(s, team, season):
		total += float(r["points"])
	return clampf(total, 0.0, 100.0)


## One row per motivation, biggest pull first: {key, label, weight, value, points, text}. `weight` is how much he
## cares (0..1), `value` how well the club does on it (0..1), `points` what it adds to (or takes from) 50,
## `text` a short reason.
static func breakdown(s: Soldier, team: Team, season: Season) -> Array:
	var d := s.get_dna()
	var rows: Array = []
	for key in Dna.MOTIVATIONS:
		var v := _value(key, s, team, season)
		var pts := 100.0 * d.n(key) * (float(v[0]) - NEUTRAL) / DEVIATION_SCALE
		rows.append({"key": key, "label": Dna.LABELS[key], "weight": d.n(key), "value": v[0], "points": pts, "text": v[1]})
	rows.sort_custom(func(a, b): return absf(float(a["points"])) > absf(float(b["points"])))
	return rows


## The strongest reasons a soldier likes (or dislikes) a club, as short sentences, for the UI.
static func reasons(s: Soldier, team: Team, season: Season, n := 3) -> Array:
	var rows := breakdown(s, team, season)
	rows.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	var out: Array = []
	for r in rows.slice(0, n):
		out.append(String(r["text"]))
	return out


static func _value(key: StringName, s: Soldier, team: Team, season: Season) -> Array:
	match key:
		&"money":
			var rating := team.market_rating
			return [clampf(rating / 100.0, 0.0, 1.0), "a %s (%d)" % [Market.market_name(team).to_lower(), rating]]
		&"winning":
			var results := _results(team, season)
			var v := RESULT_WEIGHT * results + (1.0 - RESULT_WEIGHT) * clampf(team.buzz / 100.0, 0.0, 1.0)
			return [clampf(v, 0.0, 1.0), "%s, %s buzz" % ["a contender" if results >= 0.65 else ("a bubble club" if results >= 0.4 else "a rebuilding club"), Market.band_name(team.buzz).to_lower()]]
		&"playing_time":
			var rank := 1
			for o in team.roster:
				if o != s and o.best_ovr() > s.best_ovr():
					rank += 1
			var v := 1.0 if rank <= STARTERS else clampf(1.0 - 0.2 * float(rank - STARTERS), 0.0, 1.0)
			return [v, "he would start" if rank <= STARTERS else "he would sit (rank %d)" % rank]
		&"loyalty":
			var home := team.roster.has(s) or (s.former_team != "" and s.former_team == team.abbrev)
			return [LOYAL_HOME if home else LOYAL_STRANGER, "his own club" if home else "a new club"]
		&"security":
			var rev := season.revenue
			var steady := clampf(rev.cash_of(team) / maxf(1.0, Revenue.neutral_total(team.market_rating) * 0.5), 0.0, 1.0)
			return [steady, "a steady club" if steady >= 0.5 else "a thin budget"]
		&"hometown":
			var near := 0.0
			if s.home_state != "" and team.home_state != "":
				if team.home_state == s.home_state:
					near = 1.0
				elif LeagueData.region_of(team.home_state) == LeagueData.region_of(s.home_state):
					near = 0.5
			return [near, "close to home" if near >= 1.0 else ("in his home region" if near > 0.0 else "far from home")]
	return [NEUTRAL, ""]


## How the club is doing, 0..1: its win rate once it has played enough, blended with roster strength before.
static func _results(team: Team, season: Season) -> float:
	var ovr_share := 1.0
	var ranked := season.league.teams.duplicate()
	ranked.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	var n := maxi(1, ranked.size() - 1)
	ovr_share = 1.0 - float(ranked.find(team)) / float(n)
	for r in season.standings():
		if r.team == team and r.games() >= 4:
			return 0.5 * ovr_share + 0.5 * r.win_pct()
	return ovr_share

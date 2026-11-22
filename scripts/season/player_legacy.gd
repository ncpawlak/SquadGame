class_name PlayerLegacy
extends RefCounted
## Player mode phase 5 (#100/#101): the long arc. Three things, all on top of the league's existing Hall of Fame:
##
## - Trajectory: the player's live Hall of Fame score, computed with HallOfFame's own formula (so it is the number
##   the real vote will use), plus a "pace" that projects his production over a full career.
## - Milestones: goals along the way (games, kills, grades, honors, ratings). They are derived from his career, so
##   they can be re-checked at any time; `update` records the new ones.
## - Retirement: he picks the moment (or turns 40, like everyone). The league's usual three-season wait then runs and
##   the real vote decides whether he gets in.

## Games a career is projected to last when working out the pace (about ten seasons).
const PROJECT_MATCHES := 120
## Games needed before a pace means anything.
const MIN_GAMES_FOR_PACE := 6
## The note the coach logs on a call-up, which the "Called Up" milestone looks for.
const CALL_UP_NOTE := "The coach called you up"

## id, name, description, kind (what is measured) and target. `event` ones come from the log of what happened.
const MILESTONES := [
	{"id": "debut", "name": "Debut", "desc": "Play your first game", "kind": &"matches", "target": 1},
	{"id": "call_up", "name": "Called Up", "desc": "Earn a place on the main roster", "kind": &"event", "target": 1},
	{"id": "ovr_75", "name": "75 OVR", "desc": "Reach 75 overall", "kind": &"ovr", "target": 75},
	{"id": "first_a", "name": "Grade A", "desc": "Earn a grade of A- or better in a game", "kind": &"grade", "target": 90},
	{"id": "games_30", "name": "Hall Eligible", "desc": "Play 30 games: your career can be voted on", "kind": &"matches", "target": 30},
	{"id": "kills_100", "name": "100 Kills", "desc": "100 career kills", "kind": &"kills", "target": 100},
	{"id": "first_mvp", "name": "Match MVP", "desc": "Be named MVP of a match", "kind": &"mvps", "target": 1},
	{"id": "ovr_80", "name": "80 OVR", "desc": "Reach 80 overall", "kind": &"ovr", "target": 80},
	{"id": "perfect", "name": "Perfect Game", "desc": "Earn an A+ in a game", "kind": &"grade", "target": 97},
	{"id": "first_honor", "name": "First Honor", "desc": "Win a season award or an All-League spot", "kind": &"honors", "target": 1},
	{"id": "first_title", "name": "Champion", "desc": "Win a championship as a regular", "kind": &"titles", "target": 1},
	{"id": "kills_500", "name": "500 Kills", "desc": "500 career kills", "kind": &"kills", "target": 500},
	{"id": "games_100", "name": "Veteran", "desc": "Play 100 games", "kind": &"matches", "target": 100},
	{"id": "all_league", "name": "All-League", "desc": "Be named All-League", "kind": &"all_league", "target": 1},
	{"id": "ovr_85", "name": "85 OVR", "desc": "Reach 85 overall", "kind": &"ovr", "target": 85},
	{"id": "hof_pace", "name": "Hall of Fame Pace", "desc": "Have a Hall of Fame score above the bar", "kind": &"pace", "target": 65},
	{"id": "kills_1000", "name": "1,000 Kills", "desc": "1,000 career kills", "kind": &"kills", "target": 1000},
	{"id": "games_250", "name": "Iron Soldier", "desc": "Play 250 games", "kind": &"matches", "target": 250},
	{"id": "ovr_90", "name": "90 OVR", "desc": "Reach 90 overall", "kind": &"ovr", "target": 90},
]

static var _cache := {}


# --- state ----------------------------------------------------------------------------------

static func retired(season: Season) -> bool:
	return season.player != null and season.player.retired_year != 0


static func _key(season: Season) -> String:
	var p := season.player
	return "%d:%d:%d:%d:%d:%d" % [season.league.league_seed, season.year, season.week, int(p.career["matches"]), season.player_log.size(), season.review_history.size()]


# --- trajectory -------------------------------------------------------------------------------

## The Hall of Fame picture for the player now: {score (provisional), production, awards, titles, peak, titles_won,
## honors, matches, eligible, threshold, pace (projected score), on_pace, has_pace}.
static func trajectory(season: Season) -> Dictionary:
	var key := _key(season)
	if _cache.get("key", "") == key:
		return _cache["value"]
	var p := season.player
	var ctx := HallOfFame.context(season)
	var b := HallOfFame.breakdown(season, ctx, p, 0)
	var matches := int(p.career["matches"])
	var out := {"score": b["score"], "production": b["production"], "awards": b["awards"], "titles": b["titles"],
		"peak": b["peak"], "titles_won": b["titles_won"], "honors": b["honors"], "matches": matches,
		"eligible": matches >= HallOfFame.MIN_MATCHES, "threshold": HallOfFame.THRESHOLD,
		"pace": b["score"], "has_pace": matches >= MIN_GAMES_FOR_PACE}
	if out["has_pace"] and matches < PROJECT_MATCHES:
		out["pace"] = projected_score(ctx, p, b)
	out["on_pace"] = float(out["pace"]) >= HallOfFame.THRESHOLD
	_cache = {"key": key, "value": out}
	return out


## The score he would have if he kept producing at his current per-game rates for PROJECT_MATCHES games, with his
## honors, titles and best season as they are. Pure production scales; kills per death does not.
static func projected_score(ctx: Dictionary, p: Soldier, b: Dictionary) -> float:
	var matches := maxf(1.0, float(p.career["matches"]))
	var f := maxf(1.0, float(PROJECT_MATCHES) / matches)
	var weight_sum := 0.0
	var pct_sum := 0.0
	for stat in HallOfFame.WEIGHTS:
		weight_sum += HallOfFame.WEIGHTS[stat]
		var v := HallOfFame._career_value(p, stat)
		if stat != "kd":
			v *= f
		pct_sum += HallOfFame.WEIGHTS[stat] * HallOfFame._percentile(ctx["career"][stat], v)
	var production: float = HallOfFame.PRODUCTION_POINTS * pct_sum / weight_sum
	return production + float(b["awards"]) + float(b["titles"]) + float(b["peak"])


# --- milestones -------------------------------------------------------------------------------

## How far he is on a milestone (compared with its target).
static func value_of(season: Season, m: Dictionary) -> float:
	var p := season.player
	match m["kind"]:
		&"matches": return float(p.career["matches"])
		&"kills": return float(p.career["kills"])
		&"mvps": return float(p.career.get("mvps", 0))
		&"ovr": return float(p.base_ovr())  # gear never counts toward milestones
		&"grade":
			var best := 0.0
			for e in season.player_log:
				if e["played"]:
					best = maxf(best, float(e["score"]))
			return best
		&"event":
			var team := season.user_team()
			if team != null and team.roster.has(p):
				return 1.0  # on the main roster, however he got there
			for n in season.player_notes:
				if String(n["text"]).begins_with(CALL_UP_NOTE):
					return 1.0
			return 0.0
		&"honors": return float(trajectory(season)["honors"].size())
		&"all_league":
			return float(trajectory(season)["honors"].filter(func(h: String) -> bool: return h.ends_with("All-League")).size())
		&"titles": return float(trajectory(season)["titles_won"])
		&"pace": return float(trajectory(season)["pace"]) if trajectory(season)["has_pace"] else 0.0
	return 0.0


static func achieved(season: Season, id: String) -> Dictionary:
	for e in season.player_milestones:
		if e["id"] == id:
			return e
	return {}


## Records every milestone he has reached since the last check. Returns the new entries.
static func update(season: Season) -> Array:
	if not season.player_mode or season.player == null:
		return []
	var out: Array = []
	for m in MILESTONES:
		if not achieved(season, m["id"]).is_empty():
			continue
		if value_of(season, m) >= float(m["target"]):
			var e := {"id": m["id"], "name": m["name"], "year": season.year, "week": season.week, "seen": false}
			season.player_milestones.append(e)
			out.append(e)
	return out


## New milestones the player has not been told about yet (marks them told).
static func take_unseen(season: Season) -> Array:
	var out: Array = []
	for e in season.player_milestones:
		if not bool(e.get("seen", true)):
			e["seen"] = true
			out.append(e)
	return out


## "12 / 30" style progress for a milestone not yet reached.
static func progress_text(season: Season, m: Dictionary) -> String:
	if m["kind"] == &"event":
		return "Not yet"
	if m["kind"] == &"grade":
		return "Best %d / %d" % [roundi(value_of(season, m)), m["target"]]
	if m["kind"] == &"pace":
		var t := trajectory(season)
		return "%d / %d" % [roundi(float(t["pace"])), m["target"]] if t["has_pace"] else "Play %d games" % MIN_GAMES_FOR_PACE
	return "%d / %d" % [mini(roundi(value_of(season, m)), int(m["target"])), m["target"]]


# --- retirement -------------------------------------------------------------------------------

## Why he cannot retire right now ("" = he can). Retirement happens in the offseason, like everyone's.
static func retire_error(season: Season) -> String:
	if not season.player_mode or season.player == null:
		return "Not in player mode."
	if retired(season):
		return "You have already retired."
	if season.phase != Season.PHASE_OFFSEASON:
		return "You can only retire in the offseason, once the season is over."
	return ""


## Retires him: he leaves his club, joins the league's retirees and waits for the Hall of Fame vote. Returns "" or why not.
static func retire(season: Season) -> String:
	var err := retire_error(season)
	if err != "":
		return err
	var p := season.player
	var team := season.user_team()
	var rec := Retirement._retire(season, p, team if team != null and team.org().has(p) else null, Retirement.REASON_PLAYER)
	season.retirements.append(rec)
	RetiredCallsigns.process(season, [rec])
	update(season)
	_cache = {}
	return ""


## The year the Hall votes on him (the league's wait after retiring).
static func vote_year(season: Season) -> int:
	return season.player.retired_year + HallOfFame.WAIT_SEASONS if retired(season) else 0


## Where the Hall of Fame stands for him: &"active", &"waiting", &"inducted" or &"not_inducted".
static func verdict(season: Season) -> StringName:
	if HallOfFame.is_member(season, season.player):
		return &"inducted"
	if not retired(season):
		return &"active"
	if season.year > vote_year(season) or (season.year == vote_year(season) and season.phase == Season.PHASE_OFFSEASON):
		return &"not_inducted"
	return &"waiting"


## What a final score would be if the vote were held now (career over or not).
static func final_score(season: Season) -> Dictionary:
	return HallOfFame.breakdown(season, HallOfFame.context(season), season.player, HallOfFame.MIN_MATCHES)


## Plays the league forward until the Hall of Fame has voted on him. Blocking: the hub does the same loop a week at
## a time behind a loading screen. Returns the verdict.
static func simulate_to_vote(season: Season) -> StringName:
	var target := vote_year(season)
	var guard := 0
	while guard < 40 and verdict(season) == &"waiting":
		guard += 1
		if season.phase != Season.PHASE_OFFSEASON:
			season.sim_to_end_of_season()
			continue
		if season.year >= target:
			break
		var g2 := 0
		while season.offseason_stage != Season.OFF_DONE and g2 < 30:
			season.advance_offseason()
			g2 += 1
		season.start_next_season()
	return verdict(season)


# --- recap ------------------------------------------------------------------------------------

## The career in rows: {seasons: [{year, team, age, matches, kills, deaths, assists, damage, games, letter}], totals,
## honors, titles, verdict, vote_year, final (HallOfFame breakdown), threshold}.
static func recap(season: Season) -> Dictionary:
	var p := season.player
	var rows: Array = []
	var years: Array = p.season_lines.keys()
	years.sort()
	for y in years:
		var line: Dictionary = p.season_lines[y]
		if int(line.get("matches", 0)) <= 0:
			continue
		var sm := PlayerGrade.summary(PlayerGrade.log_for(season, int(y)))
		rows.append({"year": int(y), "team": String(line.get("team", "")), "age": p.age - (season.year - int(y)),
			"matches": int(line.get("matches", 0)), "kills": int(line.get("kills", 0)), "deaths": int(line.get("deaths", 0)),
			"assists": int(line.get("assists", 0)), "damage": int(line.get("damage", 0)), "games": sm["games"], "letter": sm["letter"]})
	var fin := final_score(season) if retired(season) or int(p.career["matches"]) >= HallOfFame.MIN_MATCHES else trajectory(season)
	return {"seasons": rows, "totals": p.career.duplicate(), "honors": trajectory(season)["honors"], "titles": trajectory(season)["titles_won"],
		"verdict": verdict(season), "vote_year": vote_year(season), "final": fin, "threshold": HallOfFame.THRESHOLD,
		"milestones": season.player_milestones.size()}

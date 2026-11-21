class_name PlayerGrade
extends RefCounted
## Player mode phase 4 (#100/#101): the letter grade for one match, and the game log it goes into.
##
## Everyone in the match gets an "impact" number from the box score, weighted a little by role. The player's
## impact is compared with the other nine players in the same match (so a low-scoring game isn't a bad grade for
## anyone), and a win helps. That gives a 0-100 score and a letter.

## Score for an average showing, points per standard deviation above it, and the result swing.
const BASE := 72.0
const PER_Z := 14.0
const WIN_BONUS := 3.0
const LOSS_PENALTY := -2.0
## Floor for the spread so one lopsided player does not make everyone else look the same.
const MIN_STD := 1.0
## Extra XP a good game earns, per grade point above BASE (none below it).
const XP_PER_POINT := 6.0
const MAX_BONUS_XP := 180.0

## (minimum score, letter) from best to worst.
const LETTERS := [
	[97, "A+"], [93, "A"], [90, "A-"], [87, "B+"], [83, "B"], [80, "B-"], [77, "C+"], [73, "C"], [70, "C-"],
	[67, "D+"], [63, "D"], [60, "D-"],
]


static func letter_for(score: float) -> String:
	for row in LETTERS:
		if score >= float(row[0]):
			return row[1]
	return "F"


## A grade's colour for the UI: green for A and B, amber for C, red below.
static func letter_color(letter: String) -> Color:
	match letter.left(1):
		"A": return UiKit.GOOD
		"B": return Color("#84cc16")
		"C": return UiKit.GOLD
		"D": return Color("#f97316")
	return UiKit.BAD


## One soldier's impact in a match from his box-score line and role.
static func impact(b: Dictionary, role: Scheme.Role) -> float:
	var v := float(b.get("kills", 0)) + 0.5 * float(b.get("assists", 0)) - 0.7 * float(b.get("deaths", 0))
	v += float(b.get("damage", 0.0)) / 100.0 * 0.6
	v += 2.0 * float(b.get("clutches", 0)) + 0.5 * float(b.get("saves", 0))
	v += 1.5 * float(b.get("caps", 0)) + float(b.get("hill_s", 0.0)) / 20.0 * 0.5
	v += 0.8 * float(b.get("opening_kills", 0))
	match role:
		Scheme.Role.FRONTMAN:
			v += 0.7 * float(b.get("opening_kills", 0)) + 0.2 * float(b.get("kills_short", 0))
		Scheme.Role.CENTER:
			v += 0.3 * float(b.get("kills_long", 0)) + 0.3 * float(b.get("assists", 0)) + 0.1 * float(b.get("rounds_survived", 0))
		Scheme.Role.FLEX:
			v += 0.7 * float(b.get("caps", 0)) + float(b.get("hill_s", 0.0)) / 20.0 * 0.3 + float(b.get("distance", 0.0)) / 1000.0 * 0.2
	return v


## The player's grade for a played match, or {} if he did not play. {score, letter, z, won, kills, deaths, assists,
## damage, mvp}. `role_of` maps a soldier id to the role he played (the lineup slot's role).
static func grade(result: MatchResult, player: Soldier, team: Team) -> Dictionary:
	if not result.box.has(player.id):
		return {}
	var role_for := func(sid: int, b: Dictionary) -> Scheme.Role:
		var t: Team = result.teams[int(b["team"])]
		return t.scheme.role_for_slot(StringName(b["slot"]))
	var impacts := {}
	var total := 0.0
	for sid in result.box:
		var b: Dictionary = result.box[sid]
		impacts[sid] = impact(b, role_for.call(sid, b))
		total += impacts[sid]
	var n := float(impacts.size())
	var mean := total / n
	var var_sum := 0.0
	for sid in impacts:
		var_sum += pow(impacts[sid] - mean, 2.0)
	var std := maxf(MIN_STD, sqrt(var_sum / n))
	var z: float = (float(impacts[player.id]) - mean) / std
	var mine: Dictionary = result.box[player.id]
	var won := result.winner() == team
	var tied := result.winner() == null
	var score := clampf(BASE + PER_Z * z + (0.0 if tied else (WIN_BONUS if won else LOSS_PENALTY)), 0.0, 100.0)
	return {"score": score, "letter": letter_for(score), "z": z, "won": won,
		"kills": int(mine.get("kills", 0)), "deaths": int(mine.get("deaths", 0)), "assists": int(mine.get("assists", 0)),
		"damage": int(round(float(mine.get("damage", 0.0)))), "mvp": result.mvp_id == player.id}


## Bonus XP a graded game earns the player.
static func bonus_xp(score: float) -> float:
	return clampf((score - BASE) * XP_PER_POINT, 0.0, MAX_BONUS_XP)


## Adds this match to the season's player log (once) and pays the XP. Called when the match has been played.
## Entry: {year, week, stage, opp (Team), home (bool), played (bool), reason, score_line, won, + the grade's fields}.
static func record(season: Season, m: ScheduledMatch) -> void:
	if not season.player_mode or season.player == null or m.result == null or PlayerLegacy.retired(season):
		return
	var team := season.user_team()
	if team == null or not m.involves(team):
		return
	var key := "%d:%d:%d" % [season.year, m.week, m.stage.hash()]
	for e in season.player_log:
		if e.get("key", "") == key:
			return
	var entry := {"key": key, "year": season.year, "week": m.week, "stage": m.stage, "opp": m.away if m.home == team else m.home,
		"home": m.home == team, "score_line": m.result.score_line(), "played": false, "reason": ""}
	var g := grade(m.result, season.player, team)
	if g.is_empty():
		entry["reason"] = PlayerCoach.reason_for_absence(season)
	else:
		entry["played"] = true
		entry.merge(g, true)
		Progression.gain_xp(season.player, bonus_xp(float(g["score"])))
		entry["brand"] = WeeklyPlan.apply_brand(season, float(g["score"]))
		Wear.record_game(season.player)
		Sponsors.after_match(season, entry)
		CapMeters.after_match(season, m.result.box[season.player.id], float(g["score"]))
	season.player_log.append(entry)
	Stories.after_match(season, entry, m.winner() == team)
	PlayerLegacy.update(season)


## The log entries for one season (default the current), oldest first.
static func log_for(season: Season, year := 0) -> Array:
	var y := year if year != 0 else season.year
	return season.player_log.filter(func(e: Dictionary) -> bool: return int(e["year"]) == y)


## Games played, average score and the best/worst letter-bearing entries for a list of log entries.
static func summary(entries: Array) -> Dictionary:
	var played := entries.filter(func(e: Dictionary) -> bool: return bool(e["played"]))
	var total := 0.0
	for e in played:
		total += float(e["score"])
	var avg := total / float(played.size()) if not played.is_empty() else 0.0
	return {"games": played.size(), "missed": entries.size() - played.size(),
		"avg": avg, "letter": letter_for(avg) if not played.is_empty() else "-"}

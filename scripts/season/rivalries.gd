class_name Rivalries
extends RefCounted
## Team rivalries. Two kinds, either of which can apply to a pair (both stack):
##   DIVISIONAL  every team in a division is a rival of the other four.
##   TEAM        a named rivalry: the ANCHORS below (permanent, they can cool but never vanish)
##               plus emergent ones that boil over between any two teams.
## Every meeting adds heat to the pair (more for a three-game series and a playoff meeting, and a
## trade between the two adds some too); heat decays weekly and more over the offseason. Once a
## pair's heat passes FORM_HEAT it becomes an emergent TEAM rivalry, and it ends when the heat
## falls below FADE_HEAT. Intensity (base for the kinds + heat) scales the morale swing.
## Head-to-head records, streaks and last meetings live here for now and move into the stat
## ledger (issue #11) once that exists.

const DIVISIONAL := 1
const TEAM := 2

## abbrev, abbrev, name. Permanent team-specific rivalries.
const ANCHORS := [
	["SDV", "NSH", "Battle of the Snakes"],
	["IND", "LOU", "Battle of the Horses"],
	["NYE", "LAS", "Battle of the Coastal Powerhouses"],
	["ORL", "MIA", "Battle for Florida"],
	["BKN", "NYE", "Battle of the Boroughs"],
	["BOS", "LAS", "Old Money vs. New Money"],
	["DET", "STL", "Battle of the Bulwarks"],
	["CHI", "SEA", "Battle of the Weather"],
	["ARL", "REN", "Wild West Showdown"],
	["MIA", "CHA", "Crown and Crossbones"],
	["LRK", "NSH", "Battle of the Mid-South"],
]

const MEETING_HEAT := 2.0
## Extra heat when the series went the distance (2-1).
const CLOSE_HEAT := 2.0
const PLAYOFF_HEAT := 14.0
const TRADE_HEAT := 6.0
const WEEK_DECAY := 0.97
const SEASON_DECAY := 0.75
const FORM_HEAT := 35.0
const FADE_HEAT := 15.0
const MAX_HEAT := 100.0
const INTENSITY_DIVISIONAL := 20.0
const INTENSITY_TEAM := 35.0
const INTENSITY_BOTH := 45.0
const HEAT_WEIGHT := 0.55
## A streak this long makes a story when it is snapped.
const STREAK_STORY := 3

## "ABC|XYZ" (abbrevs, sorted) -> heat 0..MAX_HEAT.
var heat := {}
## "ABC|XYZ" -> year the emergent team rivalry formed.
var emergent := {}
## "ABC|XYZ" -> {n: meetings, w: {abbrev: wins}, g: {abbrev: games won}, streak_team, streak, last}.
## `last` is {year, week, stage, winner, score, snapped} (snapped = the length of a streak it ended).
var records := {}
## {kind: &"formed" | &"ended", a, b} from the most recent record_week (read by LeagueNews).
var last_events: Array = []


static func key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


## The anchor rivalry's name for a pair of abbrevs ("" if it is not one).
static func anchor_name(a: String, b: String) -> String:
	for r in ANCHORS:
		if (r[0] == a and r[1] == b) or (r[0] == b and r[1] == a):
			return r[2]
	return ""


## DIVISIONAL and/or TEAM for a pair (0 if they are not rivals).
func flags(a: Team, b: Team) -> int:
	if a == null or b == null or a == b:
		return 0
	var f := 0
	if a.division != "" and a.division == b.division:
		f |= DIVISIONAL
	if anchor_name(a.abbrev, b.abbrev) != "" or emergent.has(key(a.abbrev, b.abbrev)):
		f |= TEAM
	return f


func is_rivalry(a: Team, b: Team) -> bool:
	return flags(a, b) != 0


func heat_of(a: Team, b: Team) -> float:
	return float(heat.get(key(a.abbrev, b.abbrev), 0.0))


## 0-100: how much this pairing matters (0 for non-rivals).
func intensity(a: Team, b: Team) -> float:
	var f := flags(a, b)
	if f == 0:
		return 0.0
	var base := INTENSITY_DIVISIONAL
	if f == TEAM:
		base = INTENSITY_TEAM
	elif f == DIVISIONAL | TEAM:
		base = INTENSITY_BOTH
	return minf(100.0, base + heat_of(a, b) * HEAT_WEIGHT)


## Morale swing for the winners (+) and losers (-) of a rivalry game.
func swing(a: Team, b: Team) -> float:
	return snappedf(clampf(1.0 + intensity(a, b) / 25.0, 2.0, 4.0), 0.1)


## Every rivalry name that applies to the pair (team-specific first).
func titles(a: Team, b: Team) -> Array[String]:
	var out: Array[String] = []
	var f := flags(a, b)
	if f & TEAM:
		var n := anchor_name(a.abbrev, b.abbrev)
		out.append(n if n != "" else "The %s-%s Rivalry" % [a.city, b.city])
	if f & DIVISIONAL:
		out.append("%s Division Rivalry" % a.division)
	return out


func title(a: Team, b: Team) -> String:
	var t := titles(a, b)
	return t[0] if not t.is_empty() else ""


## The pair's head-to-head, or {} if they have never met.
func record_of(a: Team, b: Team) -> Dictionary:
	return records.get(key(a.abbrev, b.abbrev), {})


## "DET lead the series 5-3, and have won 2 straight" / "Series tied 2-2" / "No meetings yet".
func record_text(a: Team, b: Team) -> String:
	var rec := record_of(a, b)
	if rec.is_empty():
		return "No meetings yet"
	var wa := int(rec["w"].get(a.abbrev, 0))
	var wb := int(rec["w"].get(b.abbrev, 0))
	var text := "Series tied %d-%d" % [wa, wb]
	if wa > wb:
		text = "%s lead the series %d-%d" % [a.abbrev, wa, wb]
	elif wb > wa:
		text = "%s lead the series %d-%d" % [b.abbrev, wb, wa]
	if int(rec["streak"]) >= 2:
		text += ", %s have won %d straight" % [rec["streak_team"], int(rec["streak"])]
	return text


## Folds a week of results into the records and heat, then forms or ends emergent rivalries.
func record_week(season: Season, played: Array) -> void:
	last_events = []
	for k in heat.keys():
		heat[k] = float(heat[k]) * WEEK_DECAY
		if heat[k] < 0.5:
			heat.erase(k)
	for m: ScheduledMatch in played:
		if not m.is_played():
			continue
		var w := m.winner()
		var l := m.loser()
		var k := key(m.home.abbrev, m.away.abbrev)
		var rec := _rec(k, m.home, m.away)
		var ended_streak := 0
		if rec["streak_team"] == l.abbrev:
			ended_streak = int(rec["streak"])
		rec["n"] += 1
		rec["w"][w.abbrev] += 1
		rec["g"][w.abbrev] += m.games_for(w)
		rec["g"][l.abbrev] += m.games_for(l)
		if rec["streak_team"] == w.abbrev:
			rec["streak"] += 1
		else:
			rec["streak_team"] = w.abbrev
			rec["streak"] = 1
		rec["last"] = {"year": season.year, "week": m.week, "stage": m.stage, "winner": w.abbrev,
			"score": "%d-%d" % [m.games_for(w), m.games_for(l)], "snapped": ended_streak}
		var gain := MEETING_HEAT
		if m.games_for(l) > 0:
			gain += CLOSE_HEAT
		if m.stage != Season.STAGE_REGULAR:
			gain += PLAYOFF_HEAT
		_add_heat(k, gain)
	for k in heat.keys():
		var ab := String(k).split("|")
		if float(heat[k]) >= FORM_HEAT and not emergent.has(k) and anchor_name(ab[0], ab[1]) == "":
			emergent[k] = season.year
			last_events.append({"kind": &"formed", "a": ab[0], "b": ab[1]})
	_cool_off()


## A trade between two clubs stokes things: front offices that deal with each other talk.
func note_trade(a: Team, b: Team) -> void:
	_add_heat(key(a.abbrev, b.abbrev), TRADE_HEAT)


## Offseason: heat drops hard and cooled emergent rivalries end.
func new_season() -> void:
	for k in heat.keys():
		heat[k] = float(heat[k]) * SEASON_DECAY
		if heat[k] < 0.5:
			heat.erase(k)
	_cool_off()


func _cool_off() -> void:
	for k in emergent.keys():
		if float(heat.get(k, 0.0)) < FADE_HEAT:
			emergent.erase(k)
			var ab := String(k).split("|")
			last_events.append({"kind": &"ended", "a": ab[0], "b": ab[1]})


func _add_heat(k: String, amount: float) -> void:
	heat[k] = minf(MAX_HEAT, float(heat.get(k, 0.0)) + amount)


func _rec(k: String, a: Team, b: Team) -> Dictionary:
	if not records.has(k):
		records[k] = {"n": 0, "w": {a.abbrev: 0, b.abbrev: 0}, "g": {a.abbrev: 0, b.abbrev: 0},
			"streak_team": "", "streak": 0, "last": {}}
	return records[k]

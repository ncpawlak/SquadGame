class_name Storylines
extends RefCounted
## The season-long narrative layer (issue #104). A story is a small state machine over real league
## state: it is seeded (at season start) or triggered, moves through stages as the season plays out,
## and ends. Stories only read state the game already keeps (rivalries, schedule, results); phase 1
## has no player choices and no stat effects, it only tells the story.
##
## Kinds today: RIVALRY_RUN (arc). The catalog in issue #104 lists the rest.
## Each story is a plain Dictionary so the generic save serializer handles it:
##   id, kind, year, team (user abbrev), rival (abbrev), title (rivalry name), total (regular-season
##   meetings), results [{week, won, score}], stage, status, ended_week.

const RIVALRY_RUN := &"rivalry_run"

## How many stories may run at once, and how many arcs among them.
const MAX_ACTIVE := 3
const MAX_ARCS := 1
const ARCS: Array[StringName] = [RIVALRY_RUN]

const STAGE_SETUP := 0
const STAGE_ESCALATION := 1
const STAGE_SHOWDOWN := 2
const STAGE_RESOLVED := 3
const STAGE_NAMES: Array[String] = ["Setup", "Escalation", "Showdown", "Resolved"]

const STATUS_ACTIVE := &"active"
const STATUS_WON := &"won"
const STATUS_LOST := &"lost"
const STATUS_SPLIT := &"split"

const MAX_FINISHED := 60

var active: Array = []
var finished: Array = []
var next_id := 1
## Beats that happened in the most recent seed / week: [{story, headline, body}]. The newsroom reads
## these once for the issue it is writing (and the league wire gets them as items).
var last_beats: Array = []


# --- lifecycle -------------------------------------------------------------------------------

## Season start (after the schedule is built): closes last season's loose ends, then seeds arcs.
func begin_season(season: Season) -> void:
	last_beats = []
	for st in active.duplicate():
		_end(st, _verdict(st), season.week)
	var user := season.user_team()
	if user == null or active.size() >= MAX_ACTIVE:
		return
	var rival := _pick_rival(season, user)
	if rival == null:
		return
	var st := _new_rivalry_run(season, user, rival)
	active.append(st)
	last_beats.append(_beat(st, "seed", season))
	_publish(season, "Preseason")


## After a week is played: advances every active story and posts the beats.
func week(season: Season, played: Array, wk: int) -> void:
	last_beats = []
	for st in active.duplicate():
		match st["kind"]:
			RIVALRY_RUN:
				_week_rivalry_run(season, st, played, wk)
	_publish(season, season.week_label(wk))


# --- queries ---------------------------------------------------------------------------------

func stage_name(st: Dictionary) -> String:
	return STAGE_NAMES[clampi(int(st["stage"]), 0, STAGE_NAMES.size() - 1)]


## The user's active stories, arcs first.
func user_stories() -> Array:
	return active.duplicate()


func is_arc(kind: StringName) -> bool:
	return ARCS.has(kind)


## "2-1" style tally from the user's side: meetings won - meetings lost.
func tally(st: Dictionary) -> String:
	var w := 0
	for r in st["results"]:
		if r["won"]:
			w += 1
	return "%d-%d" % [w, st["results"].size() - w]


## One-line status for the Home to-do and the story page.
func status_line(st: Dictionary, season: Season) -> String:
	var rival := season.league.team_by_abbrev(st["rival"])
	var rn := rival.nickname if rival != null else String(st["rival"])
	if st["status"] != STATUS_ACTIVE:
		match st["status"]:
			STATUS_WON:
				return "Won the series %s vs the %s" % [tally(st), rn]
			STATUS_LOST:
				return "Lost the series %s vs the %s" % [tally(st), rn]
			_:
				return "Split the series %s vs the %s" % [tally(st), rn]
	if st["results"].is_empty():
		return "%d meetings vs the %s still to come" % [st["total"], rn]
	return "Series %s vs the %s  -  %d of %d played" % [tally(st), rn, st["results"].size(), st["total"]]


## All of a finished season's stories (for the season-end summary), newest first.
func finished_in(year: int) -> Array:
	return finished.filter(func(st): return int(st["year"]) == year)


# --- Rivalry Run -----------------------------------------------------------------------------

## The user's most heated rival among the clubs they play in the regular season: intensity first,
## then the more meetings, then the abbrev (so the pick is deterministic).
func _pick_rival(season: Season, user: Team) -> Team:
	var meetings := {}
	for m: ScheduledMatch in season.matches_for(user):
		if m.stage == Season.STAGE_REGULAR:
			var o := m.opponent_of(user)
			meetings[o] = int(meetings.get(o, 0)) + 1
	var best: Team = null
	var best_key := [0.0, 0, ""]
	for o: Team in meetings:
		var intensity := season.rivalries.intensity(user, o)
		if intensity <= 0.0:
			continue
		var key := [intensity, int(meetings[o]), o.abbrev]
		if best == null or key[0] > best_key[0] or (key[0] == best_key[0] and (key[1] > best_key[1] or (key[1] == best_key[1] and key[2] < best_key[2]))):
			best = o
			best_key = key
	return best


func _new_rivalry_run(season: Season, user: Team, rival: Team) -> Dictionary:
	var total := 0
	for m: ScheduledMatch in season.matches_for(user):
		if m.stage == Season.STAGE_REGULAR and m.opponent_of(user) == rival:
			total += 1
	var title := season.rivalries.title(user, rival)
	if title == "":
		title = "The %s-%s Rivalry" % [user.city, rival.city]
	var st := {"id": next_id, "kind": RIVALRY_RUN, "year": season.year, "team": user.abbrev, "rival": rival.abbrev,
		"title": title, "total": total, "results": [], "stage": STAGE_SETUP, "status": STATUS_ACTIVE, "ended_week": 0}
	next_id += 1
	return st


func _week_rivalry_run(season: Season, st: Dictionary, played: Array, wk: int) -> void:
	var user := season.league.team_by_abbrev(st["team"])
	var rival := season.league.team_by_abbrev(st["rival"])
	if user == null or rival == null:
		_end(st, STATUS_SPLIT, wk)
		return
	var met := false
	for m: ScheduledMatch in played:
		if not m.is_played() or m.stage != Season.STAGE_REGULAR or not (m.involves(user) and m.involves(rival)):
			continue
		met = true
		st["results"].append({"week": wk, "won": m.winner() == user,
			"score": "%d-%d" % [m.games_for(user), m.games_for(rival)]})
	if not met:
		return
	var n: int = st["results"].size()
	if n >= int(st["total"]):
		st["stage"] = STAGE_RESOLVED
		_end(st, _verdict(st), wk)
		last_beats.append(_beat(st, "resolve", season))
	else:
		st["stage"] = STAGE_SHOWDOWN if n == int(st["total"]) - 1 else STAGE_ESCALATION
		last_beats.append(_beat(st, "showdown" if st["stage"] == STAGE_SHOWDOWN else "meeting", season))


func _verdict(st: Dictionary) -> StringName:
	var w := 0
	for r in st["results"]:
		if r["won"]:
			w += 1
	var l: int = st["results"].size() - w
	if w > l:
		return STATUS_WON
	return STATUS_LOST if l > w else STATUS_SPLIT


func _end(st: Dictionary, status: StringName, wk: int) -> void:
	st["status"] = status
	st["stage"] = STAGE_RESOLVED
	st["ended_week"] = wk
	active.erase(st)
	finished.push_front(st)
	if finished.size() > MAX_FINISHED:
		finished.resize(MAX_FINISHED)


# --- beats (the words) -----------------------------------------------------------------------

func _beat(st: Dictionary, what: String, season: Season) -> Dictionary:
	var user := season.league.team_by_abbrev(st["team"])
	var rival := season.league.team_by_abbrev(st["rival"])
	var un := user.nickname
	var rn := rival.nickname
	var title: String = st["title"]
	var n: int = st["results"].size()
	var last: Dictionary = st["results"][-1] if n > 0 else {}
	var head := ""
	var body := ""
	match what:
		"seed":
			var plural := "meetings" if int(st["total"]) != 1 else "meeting"
			head = "%s: the %s and %s have %d %s on the calendar" % [title, un, rn, st["total"], plural]
			body = "%s is the story to watch in %s. The %s and %s meet %d time%s this regular season, and the series decides who owns the town." % [
				title, st["year"], un, rn, st["total"], "" if int(st["total"]) == 1 else "s"]
		"meeting":
			if last["won"]:
				head = "%s: the %s take round %d, %s" % [title, un, n, last["score"]]
			else:
				head = "%s: the %s hit back, %s" % [title, rn, last["score"]]
			body = "The series stands %s from the %s' side, with %d meeting%s to play." % [tally(st), un, int(st["total"]) - n, "" if int(st["total"]) - n == 1 else "s"]
		"showdown":
			head = "%s: one meeting left, series %s" % [title, tally(st)]
			body = "The %s and %s have played %d of %d. Next time they meet settles the series." % [un, rn, n, st["total"]]
		"resolve":
			match st["status"]:
				STATUS_WON:
					head = "%s: the %s win the series %s" % [title, un, tally(st)]
					body = "The %s closed the %s series %s over the %s. Bragging rights are theirs until next year." % [un, title, tally(st), rn]
				STATUS_LOST:
					head = "%s: the %s take the series %s" % [title, rn, tally(st)]
					body = "The %s went down %s to the %s in the %s series. The rematch next season already has a date in people's heads." % [un, tally(st), rn, title]
				_:
					head = "%s: the series ends level at %s" % [title, tally(st)]
					body = "Nothing settled. The %s and %s split the series, and both sides know it." % [un, rn]
	return {"story": st["id"], "kind": st["kind"], "headline": head, "body": body}


## Puts the beats on the league wire (the newsroom reads last_beats itself).
func _publish(season: Season, when: String) -> void:
	for b in last_beats:
		var st := _find(int(b["story"]))
		var teams: Array = [st["team"], st["rival"]] if not st.is_empty() else []
		season.news.add_story_item(season, when, teams, b["headline"], b["body"])


func _find(id: int) -> Dictionary:
	for st in active:
		if int(st["id"]) == id:
			return st
	for st in finished:
		if int(st["id"]) == id:
			return st
	return {}

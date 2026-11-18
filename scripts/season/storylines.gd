class_name Storylines
extends RefCounted
## The season-long narrative layer (issue #104). A story is a small state machine over real league
## state: it is seeded (at season start) or triggered (by what the club and its players are doing),
## moves through stages as the season plays out, and ends. Stories only read state the game already
## keeps (rivalries, schedule, results, contracts, trust); a story can wait on a player decision
## (see StoryDefs), and the effects of a choice are applied by choose() and, when the story ends,
## by _finish().
##
## Kinds:
##   RIVALRY_RUN         arc: your hottest rival, decided over the regular-season meetings.
##   ROOKIE_RISE         arc: your best young prospect, decided by how many matches he starts.
##   REVENGE_GAME        spotlight: one match, a player facing his old club.
##   CONTRACT_STANDOFF   conditional: a star in his final contract year with low trust.
## Each story is a plain Dictionary so the generic save serializer handles it. Common keys: id,
## kind, year, team (user abbrev), title, stage, status, ended_week, choice (&"" until decided),
## open (a decision is waiting), applied (effect lines for the story page). Per kind: rival, total,
## results (Rivalry Run); soldier (id), name, age, dev, need, started, played, total (Rookie's Rise);
## soldier, name, rival, start_week (the spotlight and conditional stories).

const RIVALRY_RUN := &"rivalry_run"
const ROOKIE_RISE := &"rookie_rise"
const REVENGE_GAME := &"revenge_game"
const CONTRACT_STANDOFF := &"contract_standoff"
const CINDERELLA := &"cinderella"
const DERBY_WEEK := &"derby_week"
const BENCH_GRUMBLE := &"bench_grumble"

## How many stories may run at once, and how many of them may be arcs.
const MAX_ACTIVE := 3
const MAX_ARCS := 2
const ARCS: Array[StringName] = [RIVALRY_RUN, ROOKIE_RISE, CINDERELLA]
const SPOTLIGHTS: Array[StringName] = [REVENGE_GAME, DERBY_WEEK]

const STAGE_SETUP := 0
const STAGE_ESCALATION := 1
const STAGE_SHOWDOWN := 2
const STAGE_RESOLVED := 3
const STAGE_NAMES: Array[String] = ["Setup", "Escalation", "Showdown", "Resolved"]

const STATUS_ACTIVE := &"active"
const STATUS_WON := &"won"
const STATUS_LOST := &"lost"
const STATUS_SPLIT := &"split"
## The story fell through (the player left, was not in the lineup...): no effects.
const STATUS_FIZZLED := &"fizzled"

const MAX_FINISHED := 60

## Rookie's Rise: who counts as a prospect, and the share of matches he must start.
const ROOKIE_MAX_AGE := 23
const ROOKIE_MIN_DEV := 3
const ROOKIE_START_SHARE := 0.75
## Revenge Game: a starter good enough to make a story of.
const REVENGE_MIN_OVR := 70
## Contract Standoff: the player is one of the club's best, trust is at or below this, and the story
## starts no earlier than this week.
const STANDOFF_TOP := 3
const STANDOFF_TRUST := 55.0
const STANDOFF_FROM_WEEK := 3
## Weeks the standoff decision stays open (counting the week it starts).
const STANDOFF_WINDOW := 2
## Trust at or above this settles a standoff; below STANDOFF_LOST_TRUST it is lost; in between it is
## left unresolved (no effects).
const STANDOFF_WON_TRUST := 62.0
const STANDOFF_LOST_TRUST := 30.0

## Cinderella: a club ranked in the bottom third by team OVR; "wins" means a .500+ record.
const CINDERELLA_FROM_RANK := 14
## Bench Grumble: a healthy bench player this unhappy, from this week; the window is two weeks.
const GRUMBLE_MORALE := 55.0
const GRUMBLE_FROM_WEEK := 2
const GRUMBLE_WINDOW := 2

var active: Array = []
var finished: Array = []
var next_id := 1
## "kind:year" -> true: spotlight and conditional stories that already ran this season.
var fired: Dictionary = {}
## Beats that happened in the most recent seed / week: [{story, kind, headline, body}]. The newsroom
## reads these once for the issue it is writing; the league wire gets them as items.
var last_beats: Array = []
## Beats made between weeks (a story that starts when the week opens), shown in the next issue.
var carry: Array = []


# --- lifecycle -------------------------------------------------------------------------------

## Season start (after the schedule is built): closes last season's loose ends, then seeds arcs.
func begin_season(season: Season) -> void:
	last_beats = []
	carry = []
	for st in active.duplicate():
		_end(st, _verdict(st) if st["kind"] == RIVALRY_RUN else STATUS_FIZZLED, season.week)
	var user := season.user_team()
	if user == null:
		return
	if active.size() < MAX_ACTIVE and _arc_count() < MAX_ARCS:
		var rival := _pick_rival(season, user)
		if rival != null:
			var st := _new_rivalry_run(season, user, rival)
			active.append(st)
			last_beats.append(_beat(st, "seed", season))
	# An underdog club's story takes a slot before the prospect does.
	if active.size() < MAX_ACTIVE and _arc_count() < MAX_ARCS and _is_underdog(season, user):
		var st := _new_cinderella(season, user)
		active.append(st)
		last_beats.append(_beat(st, "seed", season))
	if active.size() < MAX_ACTIVE and _arc_count() < MAX_ARCS:
		var rookie := _pick_rookie(user)
		if rookie != null:
			var st := _new_rookie_rise(season, user, rookie)
			active.append(st)
			last_beats.append(_beat(st, "seed", season))
	_publish(season, "Preseason", last_beats)


## Before a week is played: stories that start when the week opens (a spotlight match, a standoff).
func prepare_week(season: Season) -> void:
	if season.phase != Season.PHASE_REGULAR or season.preseason_camp or season.week > season.regular_weeks:
		return
	var user := season.user_team()
	if user == null:
		return
	var made: Array = []
	if active.size() < MAX_ACTIVE and not fired.has("%s:%d" % [REVENGE_GAME, season.year]):
		var st := _try_revenge_game(season, user)
		if not st.is_empty():
			made.append(_beat(st, "seed", season))
	if active.size() < MAX_ACTIVE and not fired.has("%s:%d" % [CONTRACT_STANDOFF, season.year]):
		var st := _try_standoff(season, user)
		if not st.is_empty():
			made.append(_beat(st, "seed", season))
	if active.size() < MAX_ACTIVE and not _has_spotlight() and not fired.has("%s:%d" % [DERBY_WEEK, season.year]):
		var st := _try_derby(season, user)
		if not st.is_empty():
			made.append(_beat(st, "seed", season))
	if active.size() < MAX_ACTIVE and not fired.has("%s:%d" % [BENCH_GRUMBLE, season.year]):
		var st := _try_grumble(season, user)
		if not st.is_empty():
			made.append(_beat(st, "seed", season))
	if not made.is_empty():
		carry.append_array(made)
		_publish(season, season.week_label(season.week), made)


## After a week is played: advances every active story and posts the beats.
func week(season: Season, played: Array, wk: int) -> void:
	last_beats = carry
	carry = []
	for st in active.duplicate():
		match st["kind"]:
			RIVALRY_RUN:
				_week_rivalry_run(season, st, played, wk)
			ROOKIE_RISE:
				_week_rookie_rise(season, st, played, wk)
			REVENGE_GAME:
				_week_revenge_game(season, st, played, wk)
			CONTRACT_STANDOFF:
				_week_standoff(season, st, wk)
			CINDERELLA:
				_week_cinderella(season, st, played, wk)
			DERBY_WEEK:
				_week_derby(season, st, played, wk)
			BENCH_GRUMBLE:
				_week_grumble(season, st, played, wk)
	_publish(season, season.week_label(wk), last_beats.filter(func(b): return not b.get("published", false)))


# --- queries ---------------------------------------------------------------------------------

func stage_name(st: Dictionary) -> String:
	return STAGE_NAMES[clampi(int(st["stage"]), 0, STAGE_NAMES.size() - 1)]


func is_arc(kind: StringName) -> bool:
	return ARCS.has(kind)


func _has_spotlight() -> bool:
	return active.any(func(st): return SPOTLIGHTS.has(st["kind"]))


func _arc_count() -> int:
	return active.filter(func(st): return ARCS.has(st["kind"])).size()


## "2-1" style tally from the user's side: meetings won - meetings lost.
func tally(st: Dictionary) -> String:
	var w := 0
	for r in st["results"]:
		if r["won"]:
			w += 1
	return "%d-%d" % [w, st["results"].size() - w]


## One-line status for the story list.
func status_line(st: Dictionary, season: Season) -> String:
	var name := String(st.get("name", ""))
	var verdict := String(st["status"])
	match st["kind"]:
		RIVALRY_RUN:
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
		ROOKIE_RISE:
			if st["status"] != STATUS_ACTIVE:
				return "%s: %s  -  started %d of %d" % [name, verdict.capitalize(), st["started"], st["played"]]
			return "%s: started %d of %d  -  needs %d" % [name, st["started"], st["played"], st["need"]]
		REVENGE_GAME:
			var opp := season.league.team_by_abbrev(st["rival"])
			var on := opp.nickname if opp != null else String(st["rival"])
			if st["status"] != STATUS_ACTIVE:
				return "%s vs the %s: %s" % [name, on, verdict.capitalize()]
			return "%s faces an old club, the %s: %s" % [name, on, season.week_label(st["start_week"])]
		CONTRACT_STANDOFF:
			if st["status"] != STATUS_ACTIVE:
				return "%s: %s" % [name, verdict.capitalize()]
			var s := find_soldier(season, st)
			return "%s  -  trust %s" % [name, Soldier.trust_label(s.trust) if s != null else "?"]
		CINDERELLA:
			if st["status"] != STATUS_ACTIVE:
				return "Underdog run: %s  -  %d-%d" % [verdict.capitalize(), st["wins"], st["played"] - st["wins"]]
			return "Underdog run: %d-%d  -  needs %d wins" % [st["wins"], st["played"] - st["wins"], st["need"]]
		DERBY_WEEK:
			var dopp := season.league.team_by_abbrev(st["rival"])
			var don := dopp.nickname if dopp != null else String(st["rival"])
			if st["status"] != STATUS_ACTIVE:
				return "Derby vs the %s: %s" % [don, verdict.capitalize()]
			return "Derby vs the %s: %s" % [don, season.week_label(st["start_week"])]
		BENCH_GRUMBLE:
			if st["status"] != STATUS_ACTIVE:
				return "%s: %s" % [name, verdict.capitalize()]
			var gs := find_soldier(season, st)
			return "%s  -  morale %s" % [name, Soldier.morale_label(gs.morale) if gs != null else "?"]
	return ""


## All of a season's finished stories, newest first.
func finished_in(year: int) -> Array:
	return finished.filter(func(st): return int(st["year"]) == year)


## A decision is open while the story is active, nothing has been picked and its window has not
## closed. Past that point the story plays out on its own (StoryDefs.STAY).
static func decision_open(st: Dictionary) -> bool:
	return st["status"] == STATUS_ACTIVE and st["choice"] == &"" and bool(st.get("open", st.get("results", []).is_empty()))


## Stories that are waiting on the player.
func pending_decisions() -> Array:
	return active.filter(func(st): return decision_open(st))


## The featured player, if he is still with the user's club (roster or Green Team).
static func find_soldier(season: Season, st: Dictionary) -> Soldier:
	var id := int(st.get("soldier", 0))
	if id == 0:
		return null
	var user := season.league.team_by_abbrev(st["team"])
	if user == null:
		return null
	for s in user.roster:
		if s.id == id:
			return s
	for s in user.green_team:
		if s.id == id:
			return s
	return null


# --- choices and effects ---------------------------------------------------------------------

## Locks in an option for a story. Returns "" on success, else why it cannot be done.
func choose(season: Season, id: int, option: StringName) -> String:
	var st := _find(id)
	if st.is_empty() or not decision_open(st):
		return "That decision is no longer open."
	var label := ""
	for o: Dictionary in StoryDefs.decision(st)["options"]:
		if o["id"] == option:
			label = String(o["label"])
	if label == "":
		return "Unknown option."
	st["choice"] = option
	_apply(season, st, StoryDefs.now_effects(st, option), "You chose: %s" % label.to_lower())
	return ""


## Applies an effect dictionary (see StoryDefs) and records what happened on the story.
func _apply(season: Season, st: Dictionary, e: Dictionary, label: String) -> void:
	var user := season.league.team_by_abbrev(st["team"])
	if user == null:
		return
	if e.is_empty():
		# A choice with nothing right away still goes on the record; an empty result does not.
		if label.begins_with("You chose"):
			st["applied"].append(label)
		return
	if e.has("heat") and st.has("rival"):
		var rival := season.league.team_by_abbrev(st["rival"])
		if rival != null:
			season.rivalries.stoke(user, rival, float(e["heat"]))
	if e.has("buzz"):
		season.market.ensure(season)
		season.market.award(season, user, season.week_label(season.week), "%s: %s" % [st["title"], label], float(e["buzz"]))
	var everyone: Array = user.roster.duplicate()
	everyone.append_array(user.green_team)
	for s in everyone:
		if e.has("morale"):
			s.add_morale(float(e["morale"]))
		if e.has("xp"):
			Progression.gain_xp(s, float(e["xp"]))
	var t := find_soldier(season, st)
	if t != null:
		if e.has("t_morale"):
			t.add_morale(float(e["t_morale"]))
		if e.has("t_xp"):
			Progression.gain_xp(t, float(e["t_xp"]))
		if e.has("t_sp"):
			t.skill_points += roundi(float(e["t_sp"]))
		if e.has("t_trust"):
			t.add_trust(float(e["t_trust"]))
		if e.has("t_request"):
			t.trade_request = true
	var who := " (roster and Green Team)" if StoryDefs.reaches_players([e]) else ""
	st["applied"].append("%s  -  %s%s" % [label, StoryDefs.effect_text(e, st), who])


## Ends a story with a verdict, applies what that verdict earns for the choice made, and writes the beat.
func _finish(season: Season, st: Dictionary, status: StringName, wk: int) -> void:
	if st["choice"] == &"":
		st["choice"] = StoryDefs.STAY
	st["open"] = false
	_end(st, status, wk)
	if status != STATUS_FIZZLED:
		_apply(season, st, StoryDefs.end_effects(st, st["choice"], status), "Result: %s" % String(status))
	last_beats.append(_beat(st, "resolve", season))


## Closes a decision window; an undecided story falls back to STAY.
func _close_window(st: Dictionary) -> void:
	st["open"] = false
	if st["choice"] == &"":
		st["choice"] = StoryDefs.STAY


func _end(st: Dictionary, status: StringName, wk: int) -> void:
	st["status"] = status
	st["stage"] = STAGE_RESOLVED
	st["ended_week"] = wk
	active.erase(st)
	finished.push_front(st)
	if finished.size() > MAX_FINISHED:
		finished.resize(MAX_FINISHED)


func _base(season: Season, kind: StringName, user: Team, title: String) -> Dictionary:
	var st := {"id": next_id, "kind": kind, "year": season.year, "team": user.abbrev, "title": title,
		"stage": STAGE_SETUP, "status": STATUS_ACTIVE, "ended_week": 0, "choice": &"", "open": true, "applied": [],
		"results": [], "start_week": season.week}
	next_id += 1
	return st


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
	var st := _base(season, RIVALRY_RUN, user, title)
	st["rival"] = rival.abbrev
	st["total"] = total
	return st


func _week_rivalry_run(season: Season, st: Dictionary, played: Array, wk: int) -> void:
	var user := season.league.team_by_abbrev(st["team"])
	var rival := season.league.team_by_abbrev(st["rival"])
	if user == null or rival == null:
		_end(st, STATUS_FIZZLED, wk)
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
	_close_window(st)
	var n: int = st["results"].size()
	if n >= int(st["total"]):
		_finish(season, st, _verdict(st), wk)
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


# --- Rookie's Rise ---------------------------------------------------------------------------

## The best young prospect: roster players first, then the Green Team; highest development, then OVR.
func _pick_rookie(user: Team) -> Soldier:
	for pool: Array in [user.roster, user.green_team]:
		var best: Soldier = null
		for s: Soldier in pool:
			if s.age > ROOKIE_MAX_AGE or s.dev < ROOKIE_MIN_DEV:
				continue
			if best == null or s.dev > best.dev or (s.dev == best.dev and s.best_ovr() > best.best_ovr()):
				best = s
		if best != null:
			return best
	return null


func _new_rookie_rise(season: Season, user: Team, s: Soldier) -> Dictionary:
	var total := 0
	for m: ScheduledMatch in season.matches_for(user):
		if m.stage == Season.STAGE_REGULAR:
			total += 1
	var st := _base(season, ROOKIE_RISE, user, "%s's Rise" % s.short_name())
	st["soldier"] = s.id
	st["name"] = s.short_name()
	st["age"] = s.age
	st["dev"] = s.dev
	st["total"] = total
	st["need"] = ceili(ROOKIE_START_SHARE * total)
	st["started"] = 0
	st["played"] = 0
	return st


func _week_rookie_rise(season: Season, st: Dictionary, played: Array, wk: int) -> void:
	var user := season.league.team_by_abbrev(st["team"])
	var s := find_soldier(season, st)
	if s == null:
		_close_window(st)
		_end(st, STATUS_FIZZLED, wk)
		return
	var played_now := false
	for m: ScheduledMatch in played:
		if not m.is_played() or m.stage != Season.STAGE_REGULAR or not m.involves(user):
			continue
		played_now = true
		st["played"] += 1
		if m.result.box.has(s.id):
			st["started"] += 1
	if not played_now:
		return
	_close_window(st)
	var n: int = st["played"]
	var total: int = st["total"]
	if n >= total:
		var verdict := STATUS_WON if (st["choice"] == StoryDefs.SLOW or st["started"] >= st["need"]) else STATUS_LOST
		_finish(season, st, verdict, wk)
	elif n * 3 >= total * 2 and st["stage"] < STAGE_SHOWDOWN:
		st["stage"] = STAGE_SHOWDOWN
		last_beats.append(_beat(st, "showdown", season))
	elif n * 3 >= total and st["stage"] < STAGE_ESCALATION:
		st["stage"] = STAGE_ESCALATION
		last_beats.append(_beat(st, "meeting", season))


# --- Revenge Game ----------------------------------------------------------------------------

## True if the soldier has played for the club `abbrev` before (a season line there, or it let him go).
static func played_for(s: Soldier, abbrev: String) -> bool:
	if s.former_team == abbrev:
		return true
	for year in s.season_lines:
		if String(s.season_lines[year].get("team", "")) == abbrev:
			return true
	return false


func _try_revenge_game(season: Season, user: Team) -> Dictionary:
	var m: ScheduledMatch = null
	for x: ScheduledMatch in season.matches_for_week(season.week):
		if x.involves(user) and not x.is_played():
			m = x
	if m == null or m.stage != Season.STAGE_REGULAR:
		return {}
	var opp := m.opponent_of(user)
	var best: Soldier = null
	for s: Soldier in user.starters():
		if s.best_ovr() < REVENGE_MIN_OVR or s.is_injured() or not played_for(s, opp.abbrev):
			continue
		if best == null or s.best_ovr() > best.best_ovr():
			best = s
	if best == null:
		return {}
	var st := _base(season, REVENGE_GAME, user, "%s vs the %s" % [best.short_name(), opp.nickname])
	st["soldier"] = best.id
	st["name"] = best.short_name()
	st["rival"] = opp.abbrev
	active.append(st)
	fired["%s:%d" % [REVENGE_GAME, season.year]] = true
	return st


func _week_revenge_game(season: Season, st: Dictionary, played: Array, wk: int) -> void:
	var user := season.league.team_by_abbrev(st["team"])
	var m: ScheduledMatch = null
	for x: ScheduledMatch in played:
		if x.is_played() and x.involves(user) and x.opponent_of(user).abbrev == st["rival"]:
			m = x
	if m == null:
		# The week passed without the game (a bye): the story is over.
		if wk > int(st["start_week"]):
			_close_window(st)
			_end(st, STATUS_FIZZLED, wk)
		return
	_close_window(st)
	var s := find_soldier(season, st)
	if s == null or not m.result.box.has(s.id):
		_finish(season, st, STATUS_FIZZLED, wk)
		return
	_finish(season, st, STATUS_WON if m.winner() == user else STATUS_LOST, wk)


# --- Contract Standoff -----------------------------------------------------------------------

func _try_standoff(season: Season, user: Team) -> Dictionary:
	if season.week < STANDOFF_FROM_WEEK:
		return {}
	var ranked: Array = user.roster.duplicate()
	ranked.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	for s: Soldier in ranked.slice(0, STANDOFF_TOP):
		if s.contract == null or s.contract.rookie or s.contract.green or s.contract.years > 1 or s.has_extension():
			continue
		if s.trust > STANDOFF_TRUST or s.trade_request:
			continue
		var st := _base(season, CONTRACT_STANDOFF, user, "%s's Contract" % s.short_name())
		st["soldier"] = s.id
		st["name"] = s.short_name()
		active.append(st)
		fired["%s:%d" % [CONTRACT_STANDOFF, season.year]] = true
		return st
	return {}


func _week_standoff(season: Season, st: Dictionary, wk: int) -> void:
	if wk >= int(st["start_week"]) + STANDOFF_WINDOW - 1:
		_close_window(st)
	var s := find_soldier(season, st)
	if s == null:
		_finish(season, st, STATUS_FIZZLED, wk)
		return
	if s.has_extension() or (s.contract != null and s.contract.years > 1):
		_finish(season, st, STATUS_WON, wk)
		return
	if s.trade_request or s.trust < STANDOFF_LOST_TRUST:
		_finish(season, st, STATUS_LOST, wk)
		return
	if wk >= season.regular_weeks:
		_finish(season, st, STATUS_WON if s.trust >= STANDOFF_WON_TRUST else STATUS_SPLIT, wk)
		return
	if wk > int(st["start_week"]) and st["stage"] < STAGE_ESCALATION:
		st["stage"] = STAGE_ESCALATION


# --- Cinderella ------------------------------------------------------------------------------

func _is_underdog(season: Season, user: Team) -> bool:
	var rank := 1
	for t: Team in season.league.teams:
		if t != user and t.team_ovr() > user.team_ovr():
			rank += 1
	return rank >= CINDERELLA_FROM_RANK


func _new_cinderella(season: Season, user: Team) -> Dictionary:
	var total := 0
	for m: ScheduledMatch in season.matches_for(user):
		if m.stage == Season.STAGE_REGULAR:
			total += 1
	var st := _base(season, CINDERELLA, user, "The %s Underdog Run" % user.nickname)
	st["total"] = total
	st["need"] = ceili(total / 2.0)
	st["wins"] = 0
	st["played"] = 0
	return st


func _week_cinderella(season: Season, st: Dictionary, played: Array, wk: int) -> void:
	var user := season.league.team_by_abbrev(st["team"])
	var played_now := false
	for m: ScheduledMatch in played:
		if not m.is_played() or m.stage != Season.STAGE_REGULAR or not m.involves(user):
			continue
		played_now = true
		st["played"] += 1
		if m.winner() == user:
			st["wins"] += 1
	if not played_now:
		return
	_close_window(st)
	var n: int = st["played"]
	var total: int = st["total"]
	if n >= total:
		_finish(season, st, STATUS_WON if st["wins"] >= st["need"] else STATUS_LOST, wk)
	elif n * 3 >= total * 2 and st["stage"] < STAGE_SHOWDOWN:
		st["stage"] = STAGE_SHOWDOWN
		last_beats.append(_beat(st, "showdown", season))
	elif n * 3 >= total and st["stage"] < STAGE_ESCALATION:
		st["stage"] = STAGE_ESCALATION
		last_beats.append(_beat(st, "meeting", season))


# --- Derby Week ------------------------------------------------------------------------------

## This week's regular-season match against a division mate or a heated rival.
func _try_derby(season: Season, user: Team) -> Dictionary:
	var m: ScheduledMatch = null
	for x: ScheduledMatch in season.matches_for_week(season.week):
		if x.involves(user) and not x.is_played():
			m = x
	if m == null or m.stage != Season.STAGE_REGULAR:
		return {}
	var opp := m.opponent_of(user)
	if season.division_of(opp) != season.division_of(user) and season.rivalries.intensity(user, opp) <= 0.0:
		return {}
	var st := _base(season, DERBY_WEEK, user, "Derby Week: %s vs %s" % [user.nickname, opp.nickname])
	st["rival"] = opp.abbrev
	active.append(st)
	fired["%s:%d" % [DERBY_WEEK, season.year]] = true
	return st


func _week_derby(season: Season, st: Dictionary, played: Array, wk: int) -> void:
	var user := season.league.team_by_abbrev(st["team"])
	var m: ScheduledMatch = null
	for x: ScheduledMatch in played:
		if x.is_played() and x.involves(user) and x.opponent_of(user).abbrev == st["rival"]:
			m = x
	if m == null:
		if wk > int(st["start_week"]):
			_close_window(st)
			_end(st, STATUS_FIZZLED, wk)
		return
	_close_window(st)
	_finish(season, st, STATUS_WON if m.winner() == user else STATUS_LOST, wk)


# --- Bench Grumble ---------------------------------------------------------------------------

func _try_grumble(season: Season, user: Team) -> Dictionary:
	if season.week < GRUMBLE_FROM_WEEK:
		return {}
	var worst: Soldier = null
	for s: Soldier in user.bench():
		if s.is_injured() or s.trade_request or s.morale >= GRUMBLE_MORALE:
			continue
		if worst == null or s.morale < worst.morale:
			worst = s
	if worst == null:
		return {}
	var st := _base(season, BENCH_GRUMBLE, user, "%s Wants Minutes" % worst.short_name())
	st["soldier"] = worst.id
	st["name"] = worst.short_name()
	st["played"] = 0
	st["started"] = 0
	active.append(st)
	fired["%s:%d" % [BENCH_GRUMBLE, season.year]] = true
	return st


## Two matches after the story opens: a promise is kept if the player started one of them; otherwise
## the player is judged on whether morale has come back above the floor.
func _week_grumble(season: Season, st: Dictionary, played: Array, wk: int) -> void:
	var user := season.league.team_by_abbrev(st["team"])
	var s := find_soldier(season, st)
	if s == null:
		_close_window(st)
		_finish(season, st, STATUS_FIZZLED, wk)
		return
	var played_now := false
	for m: ScheduledMatch in played:
		if not m.is_played() or m.stage != Season.STAGE_REGULAR or not m.involves(user):
			continue
		played_now = true
		st["played"] += 1
		if m.result.box.has(s.id):
			st["started"] += 1
	if not played_now:
		return
	_close_window(st)
	if st["choice"] == StoryDefs.MINUTES and st["started"] > 0:
		_finish(season, st, STATUS_WON, wk)
	elif st["played"] >= GRUMBLE_WINDOW:
		var ok: bool = st["started"] > 0 or s.morale >= GRUMBLE_MORALE
		_finish(season, st, STATUS_WON if ok else STATUS_LOST, wk)


# --- beats (the words) -----------------------------------------------------------------------

func _beat(st: Dictionary, what: String, season: Season) -> Dictionary:
	var user := season.league.team_by_abbrev(st["team"])
	var un := user.nickname
	var title: String = st["title"]
	var name := String(st.get("name", ""))
	var head := ""
	var body := ""
	match st["kind"]:
		RIVALRY_RUN:
			var rival := season.league.team_by_abbrev(st["rival"])
			var rn := rival.nickname
			var n: int = st["results"].size()
			var last: Dictionary = st["results"][-1] if n > 0 else {}
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
		ROOKIE_RISE:
			match what:
				"seed":
					head = "%s: the %s have a young talent to bring through" % [title, un]
					body = "%s (%d) is the %s' best young prospect and the league wants to know how much rope the club will give. Starts or patience: that call is the story of the season." % [name, st["age"], un]
				"meeting":
					head = "%s: %d of %d starts so far" % [title, st["started"], st["played"]]
					body = "%s has started %d of the %s' first %d matches. The club needs %d by the end of the season." % [name, st["started"], un, st["played"], st["need"]]
				"showdown":
					head = "%s: the final stretch" % title
					body = "%s sits on %d starts from %d matches, with %d needed. The last third of the schedule decides it." % [name, st["started"], st["played"], st["need"]]
				"resolve":
					match st["status"]:
						STATUS_WON:
							head = "%s: it worked" % title
							body = "%s finished with %d starts in %d matches. Whatever the %s were building, it is real." % [name, st["started"], st["played"], un]
						STATUS_LOST:
							head = "%s: the starts never came" % title
							body = "%s was supposed to be given a real run and started only %d of %d. The promise of the season went unspent." % [name, st["started"], st["played"]]
						_:
							head = "%s: the story ends" % title
							body = "%s is no longer part of the %s' plans, and the Rise ends there." % [name, un]
		REVENGE_GAME:
			var opp := season.league.team_by_abbrev(st["rival"])
			var on := opp.nickname if opp != null else String(st["rival"])
			match what:
				"seed":
					head = "%s: homecoming of a kind" % title
					body = "%s walks into the %s' building this week as a visitor. Everyone in the room knows what this one means." % [name, on]
				"resolve":
					match st["status"]:
						STATUS_WON:
							head = "%s: %s gets the win" % [title, name]
							body = "%s beat the old club and the %s took the game. Some games are about more than the standings." % [name, un]
						STATUS_LOST:
							head = "%s: the old club wins" % title
							body = "The %s took it, and %s walked off with nothing to show for a week of build-up." % [on, name]
						_:
							head = "%s: not this time" % title
							body = "%s did not play against the %s, and the grudge match went on without them." % [name, on]
		CONTRACT_STANDOFF:
			match what:
				"seed":
					head = "%s: a standoff is brewing" % title
					body = "%s is on an expiring deal and trust in the front office is running thin. Without a move from the %s, this ends in free agency or a trade request." % [name, un]
				"resolve":
					match st["status"]:
						STATUS_WON:
							head = "%s: the standoff is settled" % title
							body = "%s and the %s have found common ground. The talk of leaving has stopped, for now." % [name, un]
						STATUS_LOST:
							head = "%s: the standoff turns sour" % title
							body = "%s and the %s never got on the same page, and the relationship is worse for it." % [name, un]
						_:
							head = "%s: the story ends" % title
							body = "%s is no longer with the %s, and so the standoff is over." % [name, un]
		CINDERELLA:
			match what:
				"seed":
					head = "%s: nobody expects much from the %s" % [title, un]
					body = "The %s are projected near the bottom of the league in %s. A winning record would turn that into a story." % [un, st["year"]]
				"meeting":
					head = "%s: %d-%d so far" % [title, st["wins"], st["played"] - st["wins"]]
					body = "The %s have won %d of %d. They need %d wins from %d matches." % [un, st["wins"], st["played"], st["need"], st["total"]]
				"showdown":
					head = "%s: the final stretch" % title
					body = "The %s sit at %d-%d with %d wins needed. The last third of the season decides whether the run is real." % [un, st["wins"], st["played"] - st["wins"], st["need"]]
				"resolve":
					if st["status"] == STATUS_WON:
						head = "%s: the underdogs deliver" % title
						body = "The %s finished %d-%d, well above where anybody had them. The league has noticed." % [un, st["wins"], st["played"] - st["wins"]]
					else:
						head = "%s: the run falls short" % title
						body = "The %s finished %d-%d. Nobody expected more, and the season ends quietly." % [un, st["wins"], st["played"] - st["wins"]]
		DERBY_WEEK:
			var dopp := season.league.team_by_abbrev(st["rival"])
			var don := dopp.nickname if dopp != null else String(st["rival"])
			match what:
				"seed":
					head = "%s: derby week" % title
					body = "The %s face the %s this week, and the whole region is talking about it." % [un, don]
				"resolve":
					if st["status"] == STATUS_WON:
						head = "%s: the %s take the derby" % [title, un]
						body = "The %s beat the %s, and the town will not stop talking about it." % [un, don]
					else:
						head = "%s: the %s win the derby" % [title, don]
						body = "The %s took the bragging rights from the %s this week." % [don, un]
		BENCH_GRUMBLE:
			match what:
				"seed":
					head = "%s: unhappy on the bench" % title
					body = "%s is not getting the minutes %s expected, and the mood in the room is starting to show." % [name, name]
				"resolve":
					match st["status"]:
						STATUS_WON:
							head = "%s: sorted" % title
							body = "%s got a run in the lineup and the grumbling has stopped." % name
						STATUS_LOST:
							head = "%s: still unhappy" % title
							body = "%s is no closer to the lineup, and the relationship with the %s is strained." % [name, un]
						_:
							head = "%s: the story ends" % title
							body = "%s is no longer with the %s, and so the story is over." % [name, un]
	return {"story": st["id"], "kind": st["kind"], "headline": head, "body": body}


## Puts beats on the league wire (the newsroom reads last_beats itself). A beat is only posted once.
func _publish(season: Season, when: String, beats: Array) -> void:
	for b in beats:
		if b.get("published", false):
			continue
		b["published"] = true
		var st := _find(int(b["story"]))
		var teams: Array = [st["team"]] if not st.is_empty() else []
		if not st.is_empty() and st.has("rival"):
			teams.append(st["rival"])
		season.news.add_story_item(season, when, teams, b["headline"], b["body"])


func _find(id: int) -> Dictionary:
	for st in active:
		if int(st["id"]) == id:
			return st
	for st in finished:
		if int(st["id"]) == id:
			return st
	return {}

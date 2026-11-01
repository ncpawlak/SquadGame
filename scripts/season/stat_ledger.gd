class_name StatLedger
extends RefCounted
## What the league remembers beyond the per-season lines on each soldier (issue #11): match counts by
## phase, single-match records and team streaks. Fed once per league match from `Season.play_week_match`,
## which also stamps the records that match broke on `ScheduledMatch.records`.
##
## Single-match records are counted from the first match played with the ledger; older results are not
## kept per match, so a save from before it starts with an empty book. `seed_records` fills the books
## with the fixed marks of RecordSeed, so every league starts with the same targets.

## Meetings kept per pair of teams in its head-to-head history.
const MEETINGS_KEPT := 10
## Entries kept per record list (the same depth as the season and career books).
const KEEP := 5
## A record only makes news once its list is full and this many matches are on the books, so the first
## matches of a new league (or of a save from before the ledger) are not all "records".
const MATURE_AFTER := 100
## A streak must reach this long to be news.
const MIN_STREAK_EVENT := 5

## True once the books hold RecordSeed's marks; a seeded book is mature from the first match.
var seeded := false
## Matches recorded so far, split by phase.
var matches_regular := 0
var matches_playoffs := 0
## "stat|phase|scope" -> best first, at most KEEP snapshots {value, id, name, callsign, team, year, week,
## stage, opp}. Scope is "" for the whole league or a team abbrev for that franchise.
var single_match := {}
## Team abbrev -> current run (wins positive, losses negative).
var run := {}
## Team abbrev -> its longest {length, year, week} (the week it was reached).
var best_win := {}
var best_lose := {}
## "ABC|XYZ" (abbrevs, sorted) -> the pair's head-to-head: {n: meetings, w: {abbrev: wins}, g: {abbrev: games won},
## streak_team, streak, last, meetings}. `last` is {year, week, stage, winner, score, snapped} (snapped = the length of a
## streak it ended); `meetings` is the last MEETINGS_KEPT of those, oldest first.
var head_to_head := {}


## Records one finished league match and stamps the records it broke on `m.records`.
func record_match(season: Season, m: ScheduledMatch) -> void:
	var playoffs := m.stage != Season.STAGE_REGULAR
	var mature := seeded or matches_regular + matches_playoffs >= MATURE_AFTER
	if playoffs:
		matches_playoffs += 1
	else:
		matches_regular += 1
	m.records = []
	var r := m.result
	var phases: Array = [StatRegistry.PHASE_COMBINED, StatRegistry.PHASE_PLAYOFFS if playoffs else StatRegistry.PHASE_REGULAR]
	var by_id := {}
	for t: Team in r.teams:
		for so: Soldier in t.roster:
			by_id[so.id] = so
	# Records are measured against the books as they stood before this match, and only the best
	# performance per stat is reported (two players in one match do not each "break" it).
	var before := {}
	var best := {}
	for sid in r.box:
		var so: Soldier = by_id.get(sid)
		if so == null:
			continue
		var line: Dictionary = r.box[sid]
		var team: Team = r.teams[int(line["team"])]
		var opp: Team = r.teams[1 - int(line["team"])]
		for stat: Dictionary in StatRegistry.SINGLE_MATCH:
			var v := StatRegistry.match_value(stat, line)
			if v <= 0.0:
				continue
			var snap := {"value": v, "id": so.id, "name": so.full_name(), "callsign": so.callsign, "team": team.abbrev,
				"year": season.year, "week": m.week, "stage": String(m.stage), "opp": opp.abbrev}
			for phase: String in phases:
				for scope: String in ["", team.abbrev]:
					var key := "%s|%s|%s" % [stat["id"], phase, scope]
					if not before.has(key):
						var list: Array = single_match.get(key, [])
						before[key] = {"full": list.size() >= KEEP, "prev": list[0] if not list.is_empty() else {}}
					_offer(key, snap)
					if not (mature and scope == "" and phase != StatRegistry.PHASE_REGULAR and before[key]["full"]):
						continue
					var ck := "%s|%s" % [stat["id"], phase]
					if v > float(before[key]["prev"]["value"]) and v > float(best.get(ck, {}).get("value", 0.0)):
						best[ck] = _event(stat, phase, v, so.id, so.full_name(), team.abbrev, before[key]["prev"])
	for stat: Dictionary in StatRegistry.SINGLE_MATCH:
		var all_time: Dictionary = best.get("%s|%s" % [stat["id"], StatRegistry.PHASE_COMBINED], {})
		var playoff: Dictionary = best.get("%s|%s" % [stat["id"], StatRegistry.PHASE_PLAYOFFS], {})
		# One story per record: a playoff match that beat the all-time mark is reported as that.
		if not all_time.is_empty():
			m.records.append(all_time)
		elif not playoff.is_empty():
			m.records.append(playoff)
	_streaks(season, m)
	_head_to_head(season, m)


## Saves from before the ledger existed load with it empty and get the seeded marks; head-to-head records that
## older saves kept on `Rivalries` move here.
func ensure(season: Season) -> void:
	if Season.seed_records:
		seed_records()
	if season.rivalries != null and not season.rivalries.records.is_empty():
		for k in season.rivalries.records:
			if not head_to_head.has(k):
				var rec: Dictionary = season.rivalries.records[k]
				rec["meetings"] = [] if (rec["last"] as Dictionary).is_empty() else [rec["last"]]
				head_to_head[k] = rec
		season.rivalries.records = {}


## Puts RecordSeed's single-match marks and streaks on the books (once).
func seed_records() -> void:
	if seeded:
		return
	seeded = true
	for stat: Dictionary in StatRegistry.SINGLE_MATCH:
		for snap: Dictionary in RecordSeed.match_snaps(stat["id"]):
			var phases: Array = [StatRegistry.PHASE_COMBINED, StatRegistry.PHASE_REGULAR if snap["stage"] == "regular" else StatRegistry.PHASE_PLAYOFFS]
			for phase: String in phases:
				for scope: String in ["", snap["team"]]:
					_offer("%s|%s|%s" % [stat["id"], phase, scope], snap)
	for kind: String in ["win_streak", "lose_streak"]:
		var best: Dictionary = best_win if kind == "win_streak" else best_lose
		for e: Dictionary in RecordSeed.streak_rows(kind):
			if int(e["length"]) > int(best.get(e["team"], {}).get("length", 0)):
				best[e["team"]] = {"length": e["length"], "year": e["year"], "week": e["week"]}


## Best first: the stored snapshots for one record, or [].
func top(stat_id: String, phase: String, abbrev := "") -> Array:
	return single_match.get("%s|%s|%s" % [stat_id, phase, abbrev], [])


## Teams' longest streaks, best first: [{team: abbrev, value, year, week}]. `abbrev` limits it to one team.
func streaks(kind: String, abbrev := "") -> Array:
	var src: Dictionary = best_win if kind == "win_streak" else best_lose
	var rows: Array = []
	for t in src:
		if abbrev == "" or t == abbrev:
			rows.append({"team": t, "value": float(src[t]["length"]), "year": int(src[t]["year"]), "week": int(src[t]["week"])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if a["value"] != b["value"]:
			return a["value"] > b["value"]
		if a["year"] != b["year"]:
			return a["year"] < b["year"]
		return a["team"] < b["team"])
	return rows.slice(0, KEEP)


## Puts `snap` in a list if it beats an entry (a tie never displaces anyone). Returns its place or -1.
func _offer(key: String, snap: Dictionary) -> int:
	var list: Array = single_match.get(key, [])
	var at := list.size()
	for i in list.size():
		if snap["value"] > list[i]["value"]:
			at = i
			break
	if at >= KEEP:
		return -1
	list.insert(at, snap)
	if list.size() > KEEP:
		list.resize(KEEP)
	single_match[key] = list
	return at


## The pair's head-to-head, or {} if they have never met.
func head_to_head_of(a: Team, b: Team) -> Dictionary:
	return head_to_head.get(Rivalries.key(a.abbrev, b.abbrev), {})


## "DET lead the series 5-3, and have won 2 straight" / "Series tied 2-2" / "No meetings yet".
func series_text(a: Team, b: Team) -> String:
	var rec := head_to_head_of(a, b)
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


## "DET won 2-1 in the 2026 Final" for the pair's latest meeting ("" before the first).
func last_meeting_text(a: Team, b: Team) -> String:
	var last: Dictionary = head_to_head_of(a, b).get("last", {})
	if last.is_empty():
		return ""
	var where := "%d Week %d" % [int(last["year"]), int(last["week"])]
	if StringName(last["stage"]) != Season.STAGE_REGULAR:
		where = "the %d %s" % [int(last["year"]), String(last["stage"]).capitalize()]
	return "%s won %s in %s" % [last["winner"], last["score"], where]


func _event(stat: Dictionary, phase: String, v: float, id: int, who: String, team: String, previous: Dictionary) -> Dictionary:
	return {"stat": stat["id"], "label": stat["label"], "noun": stat["noun"], "fmt": stat["fmt"], "phase": phase,
		"value": v, "id": id, "name": who, "team": team, "previous": previous}


func _streaks(season: Season, m: ScheduledMatch) -> void:
	var win: Team = m.winner()
	var lose: Team = m.loser()
	if win == null or lose == null:
		return
	run[win.abbrev] = maxi(1, int(run.get(win.abbrev, 0)) + 1)
	run[lose.abbrev] = mini(-1, int(run.get(lose.abbrev, 0)) - 1)
	_extend(season, m, win.abbrev, int(run[win.abbrev]), best_win, StatRegistry.STREAKS[0])
	_extend(season, m, lose.abbrev, -int(run[lose.abbrev]), best_lose, StatRegistry.STREAKS[1])


## Folds one finished match into its pair's head-to-head.
func _head_to_head(season: Season, m: ScheduledMatch) -> void:
	var w := m.winner()
	var l := m.loser()
	if w == null or l == null:
		return
	var k := Rivalries.key(m.home.abbrev, m.away.abbrev)
	if not head_to_head.has(k):
		head_to_head[k] = {"n": 0, "w": {m.home.abbrev: 0, m.away.abbrev: 0}, "g": {m.home.abbrev: 0, m.away.abbrev: 0},
			"streak_team": "", "streak": 0, "last": {}, "meetings": []}
	var rec: Dictionary = head_to_head[k]
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
	var meetings: Array = rec["meetings"]
	meetings.append(rec["last"])
	if meetings.size() > MEETINGS_KEPT:
		meetings.remove_at(0)


## Notes `abbrev`'s run of `length` and, when it passes every team's best, stamps a record on the match.
func _extend(season: Season, m: ScheduledMatch, abbrev: String, length: int, best: Dictionary, stat: Dictionary) -> void:
	if length <= int(best.get(abbrev, {}).get("length", 0)):
		return
	var league_best := 0
	var holder := ""
	for t in best:
		if int(best[t]["length"]) > league_best:
			league_best = int(best[t]["length"])
			holder = t
	best[abbrev] = {"length": length, "year": season.year, "week": m.week}
	if length > league_best and length >= MIN_STREAK_EVENT and (seeded or matches_regular + matches_playoffs >= MATURE_AFTER):
		var prev := {"value": float(league_best), "team": holder, "name": holder} if league_best > 0 else {}
		var nickname := season.league.team_by_abbrev(abbrev).nickname
		m.records.append(_event(stat, StatRegistry.PHASE_COMBINED, float(length), -1, nickname, abbrev, prev))

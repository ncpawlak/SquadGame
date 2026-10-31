class_name StatLedger
extends RefCounted
## What the league remembers beyond the per-season lines on each soldier (issue #11): match counts by
## phase, single-match records and team streaks. Fed once per league match from `Season.play_week_match`,
## which also stamps the records that match broke on `ScheduledMatch.records`.
##
## Single-match records are counted from the first match played with the ledger; older results are not
## kept per match, so a save from before it starts with an empty book.

## Entries kept per record list (the same depth as the season and career books).
const KEEP := 5
## A record only makes news once its list is full and this many matches are on the books, so the first
## matches of a new league (or of a save from before the ledger) are not all "records".
const MATURE_AFTER := 100
## A streak must reach this long to be news.
const MIN_STREAK_EVENT := 5

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


## Records one finished league match and stamps the records it broke on `m.records`.
func record_match(season: Season, m: ScheduledMatch) -> void:
	var playoffs := m.stage != Season.STAGE_REGULAR
	var mature := matches_regular + matches_playoffs >= MATURE_AFTER
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


## Saves from before the ledger existed load with it empty; nothing to rebuild.
func ensure(_season: Season) -> void:
	pass


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
	if length > league_best and length >= MIN_STREAK_EVENT and matches_regular + matches_playoffs >= MATURE_AFTER:
		var prev := {"value": float(league_best), "team": holder, "name": holder} if league_best > 0 else {}
		var nickname := season.league.team_by_abbrev(abbrev).nickname
		m.records.append(_event(stat, StatRegistry.PHASE_COMBINED, float(length), -1, nickname, abbrev, prev))

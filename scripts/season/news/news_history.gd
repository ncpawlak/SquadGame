class_name NewsHistory
extends RefCounted
## What the Weekly News remembers about people across weeks: Player of the Week winners, runs of match-MVP
## games, and the recent lines of our own soldiers. It is a plain Dictionary on the Newsroom (`history`) so
## it saves with the Season; every function here is static and takes it as `h`. Fed once per played week by
## `record_week`, which is safe to call twice for the same week.
##   {stamp, potw: [{y, w, id, team, k, d, a}], mvp: {id: {n, y, w}}, log: {id: [{y, w, k, d, a, imp, won, mvp}]}}

const KEEP_POTW := 80
const KEEP_LOG := 12


## Records the matches of week `wk`: the league's Player of the Week, MVP runs and our soldiers' lines.
static func record_week(h: Dictionary, season: Season, wk: int) -> void:
	var stamp := season.year * 100 + wk
	if int(h.get("stamp", -1)) == stamp:
		return
	h["stamp"] = stamp
	var us := season.user_team()
	var mvp: Dictionary = h.get("mvp", {})
	var log: Dictionary = h.get("log", {})
	var playing := {}
	var mvp_now := {}
	for m in season.matches_for_week(wk):
		if not m.is_played():
			continue
		var r: MatchResult = m.result
		for sid in r.box:
			var line: Dictionary = r.box[sid]
			var key := str(sid)
			playing[key] = true
			var is_mvp: bool = int(sid) == r.mvp_id
			if is_mvp:
				mvp_now[key] = true
			if us != null and r.teams[int(line["team"])] == us:
				var rows: Array = log.get(key, [])
				rows.append({"y": season.year, "w": wk, "k": int(line["kills"]), "d": int(line["deaths"]), "a": int(line["assists"]),
					"imp": snappedf(MatchResult.impact(line), 0.1), "won": r.winner_index == int(line["team"]), "mvp": is_mvp})
				if rows.size() > KEEP_LOG:
					rows = rows.slice(rows.size() - KEEP_LOG)
				log[key] = rows
	for key in playing:
		if mvp_now.has(key):
			var prev: Dictionary = mvp.get(key, {})
			mvp[key] = {"n": int(prev.get("n", 0)) + 1, "y": season.year, "w": wk}
		else:
			mvp.erase(key)
	var best := SeasonReview.player_of_week(season, wk)
	var potw: Array = h.get("potw", [])
	if not best.is_empty():
		var ln: Dictionary = best["line"]
		potw.append({"y": season.year, "w": wk, "id": (best["soldier"] as Soldier).id, "team": (best["team"] as Team).abbrev,
			"k": int(ln["kills"]), "d": int(ln["deaths"]), "a": int(ln["assists"])})
		if potw.size() > KEEP_POTW:
			potw = potw.slice(potw.size() - KEEP_POTW)
	h["potw"] = potw
	h["mvp"] = mvp
	h["log"] = log


## Consecutive games (his team's matches) he has been the match MVP, as of the last recorded week.
static func mvp_run(h: Dictionary, id: int) -> int:
	return int((h.get("mvp", {}) as Dictionary).get(str(id), {}).get("n", 0))


## Times he has been Player of the Week in `year`.
static func potw_count(h: Dictionary, id: int, year: int) -> int:
	var n := 0
	for e: Dictionary in h.get("potw", []):
		if int(e["id"]) == id and int(e["y"]) == year:
			n += 1
	return n


## True when his two latest Player of the Week awards came in consecutive weeks of one season.
static func potw_back_to_back(h: Dictionary, id: int) -> bool:
	var mine: Array = (h.get("potw", []) as Array).filter(func(e): return int(e["id"]) == id)
	if mine.size() < 2:
		return false
	var a: Dictionary = mine[-2]
	var b: Dictionary = mine[-1]
	return int(a["y"]) == int(b["y"]) and int(b["w"]) - int(a["w"]) == 1


## The Player of the Week award for `wk` of `year`, or {} (the entry as recorded).
static func potw_of(h: Dictionary, year: int, wk: int) -> Dictionary:
	for e: Dictionary in h.get("potw", []):
		if int(e["y"]) == year and int(e["w"]) == wk:
			return e
	return {}


## His recorded lines for our team, oldest first, limited to `year` when given.
static func recent(h: Dictionary, id: int, year := -1) -> Array:
	var rows: Array = (h.get("log", {}) as Dictionary).get(str(id), [])
	if year < 0:
		return rows
	return rows.filter(func(e): return int(e["y"]) == year)

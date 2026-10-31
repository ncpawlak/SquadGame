class_name Records
extends RefCounted
## League and franchise record books, computed on demand from what soldiers and seasons already
## store: `Soldier.season_lines` / `career` for players, `Season.history` for teams. Nothing is
## cached or saved. Single-game and playoff-only records need the stat ledger (#11).
##
## Every record list is the top N entries, best first. A franchise scope (`abbrev` != "") counts only
## seasons a soldier spent with that team; the career records then sum those seasons.

const TOP_N := 5
## Minimum matches for a ratio stat to qualify (a hot two-match season is not a record).
const MIN_MATCHES_SEASON := 6
const MIN_MATCHES_CAREER := 30

## Player stats with a record list. kind "sum" adds a stat-line key; "kd" is kills per death.
const PLAYER_STATS := StatRegistry.PLAYER

## Team season stats, read from the history snapshots.
const TEAM_STATS := [
	{"id": "wins", "label": "Wins in a season"},
	{"id": "point_diff", "label": "Point differential in a season"},
]


## Every soldier with a stat line: rosters, free agents and the retired.
static func soldiers(season: Season) -> Array:
	var out: Array = season.league.all_soldiers()
	for so in season.league.free_agents:
		if not out.has(so):
			out.append(so)
	for r in season.retirements:
		if not out.has(r["soldier"]):
			out.append(r["soldier"])
	return out


## The stat's value for one stat line, or -1 if the line does not qualify.
static func value_of(stat: Dictionary, line: Dictionary, min_matches: int) -> float:
	return StatRegistry.value_of(stat, line, min_matches)


## Best single seasons: Array of {soldier, team: abbrev, year, value}.
static func player_seasons(season: Season, stat: Dictionary, abbrev := "") -> Array:
	var rows: Array = []
	for so: Soldier in soldiers(season):
		for year in so.season_lines:
			var line: Dictionary = so.season_lines[year]
			if abbrev != "" and line.get("team", "") != abbrev:
				continue
			var v := value_of(stat, line, MIN_MATCHES_SEASON)
			if v > 0.0:
				rows.append({"soldier": so, "team": line.get("team", ""), "year": int(year), "value": v})
	return _top(rows)


## Best careers (with `abbrev`: best spells at that franchise): Array of {soldier, first, last, value}.
static func player_careers(season: Season, stat: Dictionary, abbrev := "") -> Array:
	var rows: Array = []
	for so: Soldier in soldiers(season):
		var line: Dictionary = so.career
		var first := 0
		var last := 0
		if abbrev != "":
			line = {}
			for year in so.season_lines:
				var sl: Dictionary = so.season_lines[year]
				if sl.get("team", "") != abbrev:
					continue
				for k in Soldier.STAT_LINE_KEYS:
					line[k] = int(line.get(k, 0)) + int(sl.get(k, 0))
		for year in so.season_lines:
			if abbrev == "" or so.season_lines[year].get("team", "") == abbrev:
				first = int(year) if first == 0 else mini(first, int(year))
				last = maxi(last, int(year))
		if line.is_empty():
			continue
		var v := value_of(stat, line, MIN_MATCHES_CAREER)
		if v > 0.0:
			rows.append({"soldier": so, "first": first, "last": last, "value": v})
	return _top(rows)


## Best team seasons from finished seasons: Array of {team, year, value}.
static func team_seasons(season: Season, stat: Dictionary, abbrev := "") -> Array:
	var rows: Array = []
	for snap: SeasonSnapshot in season.history:
		for r in snap.standings:
			var t: Team = r["team"]
			if abbrev != "" and t.abbrev != abbrev:
				continue
			var v := float(r["wins"] if stat["id"] == "wins" else r["point_diff"])
			if v > 0.0:
				rows.append({"team": t, "year": snap.year, "value": v})
	return _top(rows)


## Sorted best-first and cut to TOP_N. Ties go to the earlier season, then the lower soldier id,
## then the team abbreviation, so the order never depends on the sort.
static func _top(rows: Array) -> Array:
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if a["value"] != b["value"]:
			return a["value"] > b["value"]
		var ya: int = a.get("year", a.get("last", 0))
		var yb: int = b.get("year", b.get("last", 0))
		if ya != yb:
			return ya < yb
		var ia: int = a["soldier"].id if a.has("soldier") else 0
		var ib: int = b["soldier"].id if b.has("soldier") else 0
		if ia != ib:
			return ia < ib
		return _abbrev(a) < _abbrev(b))
	return rows.slice(0, TOP_N)


static func _abbrev(row: Dictionary) -> String:
	var t = row.get("team")
	return t.abbrev if t is Team else str(t)


static func format_value(stat: Dictionary, v: float) -> String:
	if stat.get("kind", "") == "kd":
		return "%.2f" % v
	return str(roundi(v))

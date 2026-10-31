class_name StatRegistry
extends RefCounted
## The stats the league can rank, as definitions: adding a stat is adding an entry here.
## kind "sum" adds a stat-line key; "kd" is kills per death and needs a minimum number of matches.

const PLAYER := [
	{"id": "kills", "label": "Kills", "kind": "sum"},
	{"id": "assists", "label": "Assists", "kind": "sum"},
	{"id": "damage", "label": "Damage", "kind": "sum"},
	{"id": "mvps", "label": "Match MVPs", "kind": "sum"},
	{"id": "clutches", "label": "Clutches", "kind": "sum"},
	{"id": "headshots", "label": "Headshots", "kind": "sum"},
	{"id": "kd", "label": "Kills per death", "kind": "kd"},
]


## The leaderboard categories (League Leaders), in display order. `short` heads the value column and
## `fmt` is how the value reads: "int", "secs" (hill time) or "ratio".
const LEADERS := [
	{"id": "kills", "label": "KILLS", "short": "K", "kind": "sum", "fmt": "int"},
	{"id": "assists", "label": "ASSISTS", "short": "A", "kind": "sum", "fmt": "int"},
	{"id": "saves", "label": "SAVES", "short": "SAV", "kind": "sum", "fmt": "int"},
	{"id": "damage", "label": "DAMAGE", "short": "DMG", "kind": "sum", "fmt": "int"},
	{"id": "mvps", "label": "MVP AWARDS", "short": "MVP", "kind": "sum", "fmt": "int"},
	{"id": "headshots", "label": "HEADSHOTS", "short": "HS", "kind": "sum", "fmt": "int"},
	{"id": "wipes", "label": "TEAM WIPES", "short": "WIPE", "kind": "sum", "fmt": "int"},
	{"id": "hill_s", "label": "HILL TIME", "short": "TIME", "kind": "sum", "fmt": "secs"},
	{"id": "caps", "label": "HILL CAPTURES", "short": "CAPS", "kind": "sum", "fmt": "int"},
	{"id": "kd", "label": "KILLS PER DEATH", "short": "K/D", "kind": "kd", "fmt": "ratio"},
]

## Single-match records. `noun` finishes a sentence ("31 kills", "2:15 of hill time"); impact is
## MatchResult.impact of the match line.
const SINGLE_MATCH := [
	{"id": "kills", "label": "Kills in a match", "noun": "kills", "fmt": "int"},
	{"id": "assists", "label": "Assists in a match", "noun": "assists", "fmt": "int"},
	{"id": "damage", "label": "Damage in a match", "noun": "damage", "fmt": "int"},
	{"id": "saves", "label": "Saves in a match", "noun": "saves", "fmt": "int"},
	{"id": "headshots", "label": "Headshots in a match", "noun": "headshots", "fmt": "int"},
	{"id": "clutches", "label": "Clutches in a match", "noun": "clutches", "fmt": "int"},
	{"id": "wipes", "label": "Team wipes in a match", "noun": "team wipes", "fmt": "int"},
	{"id": "caps", "label": "Hill captures in a match", "noun": "hill captures", "fmt": "int"},
	{"id": "hill_s", "label": "Hill time in a match", "noun": "of hill time", "fmt": "secs"},
	{"id": "impact", "label": "Impact in a match", "noun": "impact points", "fmt": "int"},
]

## Team streak records, kept by the ledger.
const STREAKS := [
	{"id": "win_streak", "label": "Longest win streak", "noun": "straight wins", "fmt": "int"},
	{"id": "lose_streak", "label": "Longest losing streak", "noun": "straight losses", "fmt": "int"},
]

const SCOPE_SEASON := "season"
const SCOPE_CAREER := "career"
const PHASE_COMBINED := "combined"
const PHASE_REGULAR := "regular"
const PHASE_PLAYOFFS := "playoffs"


## The stat's value for one stat line, or -1 if the line does not qualify.
static func value_of(stat: Dictionary, line: Dictionary, min_matches: int) -> float:
	if stat["kind"] == "kd":
		if int(line.get("matches", 0)) < min_matches:
			return -1.0
		return float(line.get("kills", 0)) / maxf(1.0, float(line.get("deaths", 0)))
	return float(line.get(stat["id"], 0))


## A single-match stat's value for one box line.
static func match_value(stat: Dictionary, line: Dictionary) -> float:
	if stat["id"] == "impact":
		return roundf(MatchResult.impact(line))
	return roundf(float(line.get(stat["id"], 0)))


## One soldier's stat line for a scope (SCOPE_SEASON for `year`, or SCOPE_CAREER) and phase. Combined is the
## stored line, playoffs the playoff share, regular the difference. {} when he has no such line.
static func line_for(so: Soldier, scope: String, phase: String, year := 0) -> Dictionary:
	var combined: Dictionary = so.career if scope == SCOPE_CAREER else so.season_lines.get(year, {})
	if combined.is_empty() or phase == PHASE_COMBINED:
		return combined
	var playoff: Dictionary = so.playoff_career if scope == SCOPE_CAREER else so.playoff_season_lines.get(year, {})
	if phase == PHASE_PLAYOFFS:
		return playoff
	var out := combined.duplicate()
	for k in Soldier.STAT_LINE_KEYS:
		out[k] = int(combined.get(k, 0)) - int(playoff.get(k, 0))
	return out


## Conditions on the player page: [weather kind, level, label]; clear has level 0.
const CONDITIONS := [
	[&"clear", 0, "Clear"], [&"rain", 1, "Light rain"], [&"rain", 2, "Inclement rain"],
	[&"snow", 1, "Light snow"], [&"snow", 2, "Inclement snow"],
]
## A condition needs this many matches (and so does clear weather) before it says anything about a player.
const MIN_SPLIT_MATCHES := 6
## Kills per death in a condition over his clear-weather ratio: at or above EDGE_WELL he plays well in it, at or
## below EDGE_POORLY he struggles.
const EDGE_WELL := 1.25
const EDGE_POORLY := 0.8


## A soldier's career line over the matches in one weather: `kind` "" is any, `level` -1 is any, `site` "" is
## home and away. Sums the stored buckets; {} when none match.
static func weather_line(so: Soldier, kind := "", level := -1, site := "") -> Dictionary:
	var parts: Array = []
	for key: String in so.split_career:
		var p := key.split("|")
		if p[0] == "wx" and (kind == "" or p[1] == kind) and (level < 0 or int(p[2]) == level) and (site == "" or p[3] == site):
			parts.append(so.split_career[key])
	return _merge(parts)


## The same over the home field's surface ("" is any surface), by home/away.
static func surface_line(so: Soldier, surface := "", site := "") -> Dictionary:
	var parts: Array = []
	for key: String in so.split_career:
		var p := key.split("|")
		if p[0] == "sf" and (surface == "" or p[1] == surface) and (site == "" or p[2] == site):
			parts.append(so.split_career[key])
	return _merge(parts)


static func _merge(parts: Array) -> Dictionary:
	if parts.is_empty():
		return {}
	var out := {}
	for d: Dictionary in parts:
		for k in d:
			out[k] = int(out.get(k, 0)) + int(d[k])
	return out


static func _kd(line: Dictionary) -> float:
	return float(line.get("kills", 0)) / maxf(1.0, float(line.get("deaths", 0)))


## Rain and snow where he stands out: [{kind, well: bool, kd, base_kd, matches}], only with enough matches in
## the weather and in clear weather to say so.
static func weather_edges(so: Soldier) -> Array:
	var out: Array = []
	var base := weather_line(so, "clear")
	if int(base.get("matches", 0)) < MIN_SPLIT_MATCHES:
		return out
	var base_kd := _kd(base)
	for kind in [&"rain", &"snow"]:
		var line := weather_line(so, kind)
		if int(line.get("matches", 0)) < MIN_SPLIT_MATCHES:
			continue
		var ratio := _kd(line) / maxf(0.01, base_kd)
		if ratio >= EDGE_WELL or ratio <= EDGE_POORLY:
			out.append({"kind": kind, "well": ratio >= EDGE_WELL, "kd": _kd(line), "base_kd": base_kd, "matches": int(line["matches"])})
	return out


## The value as shown: whole numbers, "m:ss" hill time, or two decimals for a ratio.
static func format(stat: Dictionary, v: float) -> String:
	match stat.get("fmt", "int"):
		"secs":
			return MatchEngine._fmt_secs(v)
		"ratio":
			return "%.2f" % v
	return str(int(v))

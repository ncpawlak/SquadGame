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
	{"id": "opening_kills", "label": "OPENING KILLS", "short": "OPEN", "kind": "sum", "fmt": "int"},
	{"id": "kills_long", "label": "LONG-RANGE KILLS", "short": "LONG", "kind": "sum", "fmt": "int"},
	{"id": "distance", "label": "DISTANCE COVERED", "short": "DIST", "kind": "sum", "fmt": "metres"},
	{"id": "cover_s", "label": "TIME IN COVER", "short": "TIME", "kind": "sum", "fmt": "secs"},
	{"id": "kill_range", "label": "AVG KILL RANGE", "short": "RNG", "kind": "avg", "num": "kill_dist", "den": ["kills_short", "kills_medium", "kills_long"], "fmt": "metres1"},
	{"id": "engage_range", "label": "AVG ENGAGEMENT RANGE", "short": "RNG", "kind": "avg", "num": "fire_dist", "den": "bursts", "fmt": "metres1"},
]

## Next Gen telemetry shown on the player page: a label and how to read it from a stat line (see `telemetry_rows`).
## "sum" is a line key, "avg" is num / den (a key or a list of keys to add up), "share" is num / (num + den).
const NEXT_GEN := [
	{"label": "Opening kills", "kind": "sum", "id": "opening_kills", "fmt": "int"},
	{"label": "Kills at short range", "kind": "sum", "id": "kills_short", "fmt": "int"},
	{"label": "Kills at medium range", "kind": "sum", "id": "kills_medium", "fmt": "int"},
	{"label": "Kills at long range", "kind": "sum", "id": "kills_long", "fmt": "int"},
	{"label": "Average kill range", "kind": "avg", "num": "kill_dist", "den": ["kills_short", "kills_medium", "kills_long"], "fmt": "metres1"},
	{"label": "Average engagement range", "kind": "avg", "num": "fire_dist", "den": "bursts", "fmt": "metres1"},
	{"label": "Distance covered", "kind": "sum", "id": "distance", "fmt": "metres"},
	{"label": "Time in cover", "kind": "sum", "id": "cover_s", "fmt": "secs"},
	{"label": "Average time to first shot", "kind": "avg", "num": "first_shot_s", "den": "first_shot_n", "fmt": "secs1"},
	{"label": "Time contesting the hill", "kind": "sum", "id": "contest_s", "fmt": "secs"},
	{"label": "Share of hill time contested", "kind": "share", "num": "contest_s", "den": "hill_s", "fmt": "pct"},
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
	if stat["kind"] == "avg":
		var den := _total(line, stat["den"])
		if int(line.get("matches", 0)) < min_matches or den <= 0.0:
			return -1.0
		return float(line.get(stat["num"], 0)) / den
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


## The value as shown: whole numbers, "m:ss" hill time, or two decimals for a ratio.
static func format(stat: Dictionary, v: float) -> String:
	match stat.get("fmt", "int"):
		"secs":
			return MatchEngine._fmt_secs(v)
		"ratio":
			return "%.2f" % v
		"metres":
			return "%d m" % roundi(v)
		"metres1":
			return "%.1f m" % v
		"secs1":
			return "%.1f s" % v
		"pct":
			return "%d%%" % roundi(v * 100.0)
	return str(int(v))


## A line's value for a key, or the sum over a list of keys (kills are only counted by range from telemetry on).
static func _total(line: Dictionary, keys: Variant) -> float:
	if keys is Array:
		var t := 0.0
		for k in keys:
			t += float(line.get(k, 0))
		return t
	return float(line.get(keys, 0))


## The Next Gen rows for one stat line: [[label, text]], with "-" where a line has nothing to average.
static func telemetry_rows(line: Dictionary) -> Array:
	var rows: Array = []
	for d: Dictionary in NEXT_GEN:
		var text := "-"
		match d["kind"]:
			"sum":
				text = format(d, float(line.get(d["id"], 0)))
			"avg":
				var den := _total(line, d["den"])
				if den > 0.0:
					text = format(d, float(line.get(d["num"], 0)) / den)
			"share":
				var num := float(line.get(d["num"], 0))
				var total := num + _total(line, d["den"])
				if total > 0.0:
					text = format(d, num / total)
		rows.append([d["label"], text])
	return rows

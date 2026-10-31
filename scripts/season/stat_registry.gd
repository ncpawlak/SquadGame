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


## The stat's value for one stat line, or -1 if the line does not qualify.
static func value_of(stat: Dictionary, line: Dictionary, min_matches: int) -> float:
	if stat["kind"] == "kd":
		if int(line.get("matches", 0)) < min_matches:
			return -1.0
		return float(line.get("kills", 0)) / maxf(1.0, float(line.get("deaths", 0)))
	return float(line.get(stat["id"], 0))

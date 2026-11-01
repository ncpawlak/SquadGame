class_name RecordSeed
extends RefCounted
## The league's record books before the first match: made-up marks from earlier years, so a new franchise
## always starts with the same targets and its players can break them (issue #11). Only the numbers are
## written down; who set each one, for which club and when is drawn from a fixed generator, so the book is
## identical in every league and every run and never touches the league's own random numbers.
##
## Values are best first. The same list is the regular-season and combined book; playoff books are the same
## marks scaled by PLAYOFF_SHARE. Hill time is left out: a match caps it, so it cannot be beaten.

const NAMES := [
	["Marcus Hale", "Anvil"], ["Dario Voss", "Wraith"], ["Teodor Brandt", "Hex"], ["Isaiah Crane", "Tempest"],
	["Nikolai Orlov", "Sable"], ["Callum Reyes", "Ember"], ["Jonas Lindqvist", "Frost"], ["Ravi Castellan", "Viper"],
	["Declan Mercer", "Ghost"], ["Silas Whitaker", "Havoc"], ["Andre Okafor", "Bishop"], ["Tobias Kline", "Rook"],
	["Mateo Duarte", "Flint"], ["Elias Vandermeer", "Cipher"], ["Rhett Sorensen", "Grit"], ["Kai Nakamura", "Specter"],
	["Beau Lachance", "Torque"], ["Anders Holm", "Reaper"], ["Cyrus Delacroix", "Nomad"], ["Wes Albright", "Jackal"],
]
## Clubs of the fixed league (a club missing from a custom league just reads as its abbreviation).
const TEAMS := ["NYE", "DET", "LAS", "BOS", "SEA", "ARL", "CHI", "STL", "CHA", "SDV",
	"REN", "ATL", "IND", "MIA", "DEN", "BKN", "NSH", "LOU", "ORL", "LRK"]
const FIRST_YEAR := 2009
const LAST_YEAR := 2024
const STREAK_SEED := 0x5EED

## Playoff marks as a share of the regular ones.
const PLAYOFF_SHARE := 0.85
const PLAYOFF_SHARE_TOTALS := 0.3
const PLAYOFF_SHARE_CAREER := 0.25
const PLAYOFF_SHARE_RATIO := 0.85

const MATCH := {
	"kills": [47, 44, 42, 41, 39],
	"assists": [58, 55, 53, 51, 50],
	"damage": [4020, 3910, 3790, 3680, 3590],
	"saves": [8, 7, 7, 6, 6],
	"headshots": [36, 34, 33, 31, 30],
	"clutches": [3, 2, 2, 2, 2],
	"wipes": [11, 10, 10, 9, 9],
	"caps": [10, 9, 9, 8, 8],
	"impact": [7600, 7450, 7300, 7150, 7000],
	"opening_kills": [5, 4, 4, 4, 3],
	"kills_long": [14, 13, 12, 11, 10],
	"distance": [2050, 1960, 1880, 1800, 1730],
}
const SEASON := {
	"kills": [262, 248, 236, 229, 221],
	"assists": [352, 338, 326, 317, 309],
	"damage": [25400, 24300, 23500, 22800, 22100],
	"mvps": [8, 7, 7, 7, 6],
	"clutches": [3, 3, 2, 2, 2],
	"headshots": [172, 165, 158, 152, 147],
	"kd": [3.62, 3.41, 3.28, 3.15, 3.05],
	"opening_kills": [14, 13, 12, 11, 10],
	"kills_long": [46, 43, 41, 39, 37],
	"distance": [11800, 11300, 10900, 10500, 10200],
}
const CAREER := {
	"kills": [1480, 1410, 1355, 1310, 1270],
	"assists": [2140, 2050, 1960, 1890, 1820],
	"damage": [138000, 131000, 126000, 121500, 117500],
	"mvps": [24, 22, 20, 19, 18],
	"clutches": [10, 9, 8, 8, 7],
	"headshots": [840, 800, 765, 735, 710],
	"kd": [1.62, 1.55, 1.50, 1.46, 1.43],
	"opening_kills": [62, 58, 55, 52, 49],
	"kills_long": [210, 196, 186, 176, 168],
	"distance": [78000, 74000, 71000, 68000, 65000],
}
const TEAM_SEASON := {
	"wins": [12, 11, 11, 11, 10],
	"point_diff": [340, 315, 298, 276, 261],
}
const STREAK := {
	"win_streak": [14, 12, 11, 10, 9],
	"lose_streak": [10, 9, 8, 8, 7],
}


## Single-match snapshots for the ledger (see StatLedger): regular-season marks and their playoff cousins.
static func match_snaps(stat_id: String) -> Array:
	var out: Array = []
	if not MATCH.has(stat_id):
		return out
	var rng := _rng("match|" + stat_id)
	var regular: Array = MATCH[stat_id]
	for i in regular.size():
		out.append(_snap(rng, float(regular[i]), "regular"))
	for i in regular.size():
		out.append(_snap(rng, maxf(1.0, roundf(float(regular[i]) * PLAYOFF_SHARE)), "final"))
	return out


## Player rows for `Records`: {soldier: null, name, team, year (season) or first/last (career), value}.
## `kind` is "season" or "career"; `phase` a StatRegistry phase; `abbrev` limits it to one club.
static func player_rows(kind: String, stat: Dictionary, abbrev: String, phase: String) -> Array:
	var table: Dictionary = SEASON if kind == "season" else CAREER
	var out: Array = []
	if not table.has(stat["id"]):
		return out
	var rng := _rng("%s|%s" % [kind, stat["id"]])
	var ratio: bool = stat.get("kind", "") == "kd"
	var share := 1.0
	if phase == StatRegistry.PHASE_PLAYOFFS:
		share = PLAYOFF_SHARE_RATIO if ratio else (PLAYOFF_SHARE_CAREER if kind == "career" else PLAYOFF_SHARE_TOTALS)
	for v in table[stat["id"]]:
		var who := _who(rng)
		var year := rng.randi_range(FIRST_YEAR + 4, LAST_YEAR)
		var span := rng.randi_range(5, 9)
		var value := float(v) * share
		if not ratio and share != 1.0:
			value = maxf(1.0, roundf(value))
		if abbrev != "" and who["team"] != abbrev:
			continue
		var row := {"soldier": null, "name": who["name"], "team": who["team"], "value": value}
		if kind == "season":
			row["year"] = year
		else:
			row["first"] = year - span
			row["last"] = year
		out.append(row)
	return out


## Team season rows: {team: abbrev, year, value}.
static func team_rows(stat_id: String, abbrev: String) -> Array:
	var out: Array = []
	if not TEAM_SEASON.has(stat_id):
		return out
	var rng := _rng("team|" + stat_id)
	for v in TEAM_SEASON[stat_id]:
		var who := _who(rng)
		var year := rng.randi_range(FIRST_YEAR, LAST_YEAR)
		if abbrev == "" or who["team"] == abbrev:
			out.append({"team": who["team"], "year": year, "value": float(v)})
	return out


## Streak marks for the ledger: [{team, length, year, week}] best first, each club at most once.
static func streak_rows(kind: String) -> Array:
	var out: Array = []
	var rng := _rng("streak|" + kind)
	var used := {}
	for v in STREAK.get(kind, []):
		var who := _who(rng)
		while used.has(who["team"]):
			who = _who(rng)
		used[who["team"]] = true
		out.append({"team": who["team"], "length": int(v), "year": rng.randi_range(FIRST_YEAR, LAST_YEAR), "week": rng.randi_range(4, 12)})
	return out


static func _snap(rng: RandomNumberGenerator, value: float, stage: String) -> Dictionary:
	var who := _who(rng)
	var opp: String = who["team"]
	while opp == who["team"]:
		opp = TEAMS[rng.randi() % TEAMS.size()]
	return {"value": value, "id": -1, "name": who["name"], "callsign": who["callsign"], "team": who["team"],
		"year": rng.randi_range(FIRST_YEAR, LAST_YEAR), "week": rng.randi_range(1, 12), "stage": stage, "opp": opp}


static func _who(rng: RandomNumberGenerator) -> Dictionary:
	var n: Array = NAMES[rng.randi() % NAMES.size()]
	return {"name": n[0], "callsign": n[1], "team": TEAMS[rng.randi() % TEAMS.size()]}


## A generator seeded from `key` alone, so every call gives the same sequence.
static func _rng(key: String) -> RandomNumberGenerator:
	var h := STREAK_SEED
	for c in key.to_utf8_buffer():
		h = (h * 31 + c) & 0x7FFFFFFF
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	return rng

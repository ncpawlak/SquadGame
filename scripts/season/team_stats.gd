class_name TeamStats
extends RefCounted
## Team totals for the current season, summed from the box scores of the matches played (issue #11).
## Nothing is stored: every call reads the schedule, so it always agrees with the results.

const TOP_N := 5
## Leaderboard categories, shaped like StatRegistry.LEADERS so StatRegistry.value_of / format read them.
const LEADERS := [
	{"id": "wins", "label": "WINS", "short": "W", "kind": "sum", "fmt": "int"},
	{"id": "game_diff", "label": "GAME DIFFERENTIAL", "short": "+/-", "kind": "sum", "fmt": "int"},
	{"id": "kills", "label": "KILLS", "short": "K", "kind": "sum", "fmt": "int"},
	{"id": "kd", "label": "KILLS PER DEATH", "short": "K/D", "kind": "kd", "fmt": "ratio"},
	{"id": "damage", "label": "DAMAGE", "short": "DMG", "kind": "sum", "fmt": "int"},
	{"id": "assists", "label": "ASSISTS", "short": "A", "kind": "sum", "fmt": "int"},
	{"id": "saves", "label": "SAVES", "short": "SAV", "kind": "sum", "fmt": "int"},
	{"id": "headshots", "label": "HEADSHOTS", "short": "HS", "kind": "sum", "fmt": "int"},
	{"id": "wipes", "label": "TEAM WIPES", "short": "WIPE", "kind": "sum", "fmt": "int"},
	{"id": "hill_s", "label": "HILL TIME", "short": "TIME", "kind": "sum", "fmt": "secs"},
	{"id": "caps", "label": "HILL CAPTURES", "short": "CAPS", "kind": "sum", "fmt": "int"},
]
## Box-score keys summed over a team's players.
const BOX_KEYS := ["kills", "deaths", "assists", "damage", "saves", "headshots", "wipes", "hill_s", "caps"]


## Team abbrev -> {matches, wins, losses, game_diff, kills, deaths, ...} over the played matches of `phase`
## (a StatRegistry phase). Every team has an entry, with zeros when it has played nothing.
static func season_totals(season: Season, phase := StatRegistry.PHASE_COMBINED) -> Dictionary:
	var out := {}
	for t: Team in season.league.teams:
		var line := {"matches": 0, "wins": 0, "losses": 0, "game_diff": 0}
		for k in BOX_KEYS:
			line[k] = 0
		out[t.abbrev] = line
	var played: Array = []
	if phase != StatRegistry.PHASE_PLAYOFFS:
		played.append_array(season.regular_matches())
	if phase != StatRegistry.PHASE_REGULAR:
		played.append_array(season.playoff_matches)
	for m: ScheduledMatch in played:
		if not m.is_played():
			continue
		var r := m.result
		for i in 2:
			var line: Dictionary = out.get(r.teams[i].abbrev, {})
			if line.is_empty():
				continue
			line["matches"] += 1
			line["wins" if r.winner_index == i else "losses"] += 1
			line["game_diff"] += r.score[i] - r.score[1 - i]
		for sid in r.box:
			var b: Dictionary = r.box[sid]
			var line: Dictionary = out.get(r.teams[int(b["team"])].abbrev, {})
			for k in BOX_KEYS:
				line[k] += roundi(float(b.get(k, 0)))
	return out


## One category's best teams: [{team: Team, value}], best first (ties by abbreviation). Teams with no value are left out.
static func top(season: Season, stat: Dictionary, phase := StatRegistry.PHASE_COMBINED, totals := {}) -> Array:
	if totals.is_empty():
		totals = season_totals(season, phase)
	var most := 0
	for abbrev in totals:
		most = maxi(most, int(totals[abbrev]["matches"]))
	var min_matches := maxi(1, ceili(most / 2.0))
	var rows: Array = []
	for t: Team in season.league.teams:
		var v := StatRegistry.value_of(stat, totals[t.abbrev], min_matches)
		if v > 0.0:
			rows.append({"team": t, "value": v})
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if a["value"] != b["value"]:
			return a["value"] > b["value"]
		return a["team"].abbrev < b["team"].abbrev)
	return rows.slice(0, TOP_N)

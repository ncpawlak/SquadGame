class_name StatsPages
extends RefCounted
## League Leaders as a configuration of the stat ledger: scope (this season or career) and phase
## (combined, regular season or playoffs) chips over the StatRegistry categories. Built by the hub's
## League pane; reads the soldiers' stored lines fresh every time.

const TOP_N := 5
const SCOPES := [[StatRegistry.SCOPE_SEASON, "SEASON"], [StatRegistry.SCOPE_CAREER, "CAREER"]]
const PHASES := [[StatRegistry.PHASE_COMBINED, "COMBINED"], [StatRegistry.PHASE_REGULAR, "REGULAR SEASON"], [StatRegistry.PHASE_PLAYOFFS, "PLAYOFFS"]]

var hub: Control  # hub.gd
var pages: FranchisePages
var scope := StatRegistry.SCOPE_SEASON
var phase := StatRegistry.PHASE_COMBINED


func leaders() -> Control:
	var s: Season = hub.season
	var v := pages._vbox(14)
	v.add_child(_chips())
	var pool := _pool(s)
	if pool.is_empty():
		v.add_child(UiKit.label("No matches recorded here yet.", 18, UiKit.MUTED))
		return v
	# A ratio needs half the most games anyone has played, so one hot match is not a leader.
	var most := 0
	for p in pool:
		most = maxi(most, int(p["line"].get("matches", 0)))
	var min_matches := maxi(1, ceili(most / 2.0))
	var user_abbrev := s.user_team().abbrev
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 20)
	flow.add_theme_constant_override("v_separation", 20)
	for stat: Dictionary in StatRegistry.LEADERS:
		var rows: Array = []
		var hl := {}
		var targets: Array = []
		for r in _top(pool, stat, min_matches):
			if r["team"] == user_abbrev:
				hl[rows.size()] = UiKit.MINE
			targets.append(r["soldier"])
			rows.append([rows.size() + 1, r["soldier"].tag(), r["team"], StatRegistry.format(stat, r["value"])])
		var col := pages._vbox(6)
		col.add_child(pages._section(stat["label"]))
		col.add_child(UiKit.table(["#", "PLAYER", "TM", stat["short"]], rows, [24, 170, 50, 60], hl, {},
			func(i: int): pages.open_player(targets[i])))
		flow.add_child(col)
	v.add_child(flow)
	return v


func _chips() -> Control:
	var row := pages._row(8)
	for o in SCOPES:
		var val: String = o[0]
		row.add_child(pages._seg(o[1], scope == val, func():
			scope = val
			hub._fill_league_box(), 14))
	var gap := Control.new()
	gap.custom_minimum_size.x = 24
	row.add_child(gap)
	for o in PHASES:
		var val: String = o[0]
		row.add_child(pages._seg(o[1], phase == val, func():
			phase = val
			hub._fill_league_box(), 14))
	return row


## Everyone with a stat line for the chosen scope and phase: [{soldier, line, team: abbrev}].
func _pool(s: Season) -> Array:
	var club := {}
	for t: Team in s.league.teams:
		for so: Soldier in t.roster:
			club[so] = t.abbrev
	var out: Array = []
	for so: Soldier in Records.soldiers(s):
		var line := StatRegistry.line_for(so, scope, phase, s.year)
		if line.is_empty() or int(line.get("matches", 0)) <= 0:
			continue
		out.append({"soldier": so, "line": line, "team": _team_abbrev(so, club, line)})
	return out


## A season line names its club; a career line is shown with his current club, else his last one.
func _team_abbrev(so: Soldier, club: Dictionary, line: Dictionary) -> String:
	if scope == StatRegistry.SCOPE_SEASON and line.has("team"):
		return line["team"]
	if club.has(so):
		return club[so]
	var last := 0
	for y in so.season_lines:
		last = maxi(last, int(y))
	return so.season_lines[last].get("team", "-") if last > 0 else "-"


func _top(pool: Array, stat: Dictionary, min_matches: int) -> Array:
	var rows: Array = []
	for p in pool:
		var v := StatRegistry.value_of(stat, p["line"], min_matches)
		if v > 0.0:
			rows.append({"soldier": p["soldier"], "team": p["team"], "value": v})
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if a["value"] != b["value"]:
			return a["value"] > b["value"]
		return a["soldier"].id < b["soldier"].id)
	return rows.slice(0, TOP_N)

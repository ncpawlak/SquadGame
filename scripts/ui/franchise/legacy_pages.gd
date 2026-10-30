class_name LegacyPages
extends RefCounted
## The Legacy page: league history in tabs (champions, awards). Built by the hub like the other
## detail pages; reads Season.history and Season.review_history fresh every time.

const TABS := [["champions", "Champions"], ["awards", "Awards"]]

var hub: Control  # hub.gd
var pages: FranchisePages
var tab := "champions"


func _season() -> Season:
	return hub.season


func legacy() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	for o in TABS:
		var val: String = o[0]
		var b := pages._seg(o[1], tab == val, func():
			tab = val
			hub.replace("Legacy", legacy), 15)
		b.custom_minimum_size.x = 150
		nav.add_child(b)
	v.add_child(nav)
	match tab:
		"awards":
			v.add_child(_awards())
		_:
			v.add_child(_champions())
	return v


# --- champions ------------------------------------------------------------------------

func _champions() -> Control:
	var s := _season()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var snaps: Array = s.history.duplicate()
	snaps.reverse()
	if snaps.is_empty():
		v.add_child(UiKit.label("No champions yet. The first one is crowned when the final is played.", 15, UiKit.MUTED))
		return v
	v.add_child(pages._section("CHAMPIONS BY YEAR"))
	var rows: Array = []
	var hl := {}
	for i in snaps.size():
		var snap: SeasonSnapshot = snaps[i]
		rows.append([snap.year, snap.champion, snap.champion_record(), snap.runner_up if snap.runner_up != null else "-", snap.final_score()])
		if snap.champion != null and snap.champion.user_controlled:
			hl[i] = UiKit.MINE
	v.add_child(UiKit.table(["YEAR", "CHAMPION", "RECORD", "RUNNER-UP", "FINAL"], rows, [70, 260, 80, 260, 70], hl, {},
		func(i: int):
			var snap: SeasonSnapshot = snaps[i]
			hub.open("%d Season" % snap.year, func(): return season_page(snap))))
	v.add_child(UiKit.label("Click a year for its final table and bracket.", 13, UiKit.MUTED))

	var titles := {}  # Team -> [years]
	for snap: SeasonSnapshot in s.history:
		if snap.champion != null:
			if not titles.has(snap.champion):
				titles[snap.champion] = []
			titles[snap.champion].append(snap.year)
	var order: Array = titles.keys()
	order.sort_custom(func(a: Team, b: Team):
		if titles[a].size() != titles[b].size():
			return titles[a].size() > titles[b].size()
		return titles[a][-1] > titles[b][-1])
	v.add_child(pages._section("TITLES"))
	var trows: Array = []
	var thl := {}
	for i in order.size():
		var t: Team = order[i]
		var years: Array = titles[t].map(func(y): return str(y))
		trows.append([t, titles[t].size(), ", ".join(years)])
		if t.user_controlled:
			thl[i] = UiKit.MINE
	v.add_child(UiKit.table(["TEAM", "TITLES", "YEARS"], trows, [260, 80, 420], thl, {},
		func(i: int):
			var t: Team = order[i]
			hub.open(t.name, func(): return pages.team_roster(t))))
	return v


## One past season: the final table and the playoff bracket.
func season_page(snap: SeasonSnapshot) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var champ := "-" if snap.champion == null else snap.champion.name
	var runner := "-" if snap.runner_up == null else snap.runner_up.name
	v.add_child(pages._section("%d SEASON  -  champion %s over %s (%s)" % [snap.year, champ, runner, snap.final_score()]))
	v.add_child(pages._section("PLAYOFFS"))
	var rows: Array = []
	for m in snap.bracket:
		var home_won: bool = m["winner"] == m["home"]
		rows.append([m["round"], m["home"], "%d-%d" % [m["home_games"], m["away_games"]], m["away"], "W" if home_won else "L"])
	v.add_child(UiKit.table(["ROUND", "HOME", "SCORE", "AWAY", ""], rows, [140, 230, 70, 230, 40]))
	v.add_child(pages._section("FINAL TABLE"))
	var srows: Array = []
	var hl := {}
	for i in snap.standings.size():
		var r: Dictionary = snap.standings[i]
		srows.append([i + 1, r["team"], "%d-%d" % [r["wins"], r["losses"]], r["game_diff"], r["point_diff"], str(r["seed"]) if r["seed"] > 0 else "-"])
		if r["team"].user_controlled:
			hl[i] = UiKit.MINE
	v.add_child(UiKit.table(["#", "TEAM", "RECORD", "GD", "PD", "SEED"], srows, [40, 260, 80, 60, 70, 60], hl, {},
		func(i: int):
			var t: Team = snap.standings[i]["team"]
			hub.open(t.name, func(): return pages.team_roster(t))))
	return v


# --- awards ---------------------------------------------------------------------------

func _awards() -> Control:
	var s := _season()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	if s.review_history.is_empty():
		v.add_child(UiKit.label("No awards yet. They are handed out after the final.", 15, UiKit.MUTED))
		return v

	v.add_child(pages._section("MOST DECORATED"))
	var tally := {}  # Soldier -> {awards, mvps, all_league}
	for rev: SeasonReview in s.review_history:
		for a in rev.awards:
			var t := _tally(tally, a["soldier"])
			t["awards"] += 1
			if a["award"] == "Season MVP":
				t["mvps"] += 1
		for a in rev.all_league:
			_tally(tally, a["soldier"])["all_league"] += 1
	var order: Array = tally.keys()
	order.sort_custom(func(a: Soldier, b: Soldier):
		var ta: Dictionary = tally[a]
		var tb: Dictionary = tally[b]
		if ta["awards"] != tb["awards"]:
			return ta["awards"] > tb["awards"]
		if ta["all_league"] != tb["all_league"]:
			return ta["all_league"] > tb["all_league"]
		return a.id < b.id)
	var top: Array = order.slice(0, 10)
	var rows: Array = []
	for so: Soldier in top:
		var t: Dictionary = tally[so]
		var team := s.league.team_of(so)
		rows.append([so.full_name(), team.abbrev if team != null else "retired", t["awards"], t["mvps"], t["all_league"]])
	v.add_child(UiKit.table(["SOLDIER", "TEAM", "AWARDS", "MVPS", "ALL-LEAGUE"], rows, [240, 90, 80, 80, 110], {}, {},
		func(i: int): pages.open_player(top[i])))

	v.add_child(pages._section("AWARDS BY YEAR"))
	var arows: Array = []
	var targets: Array = []
	for i in range(s.review_history.size() - 1, -1, -1):
		var rev: SeasonReview = s.review_history[i]
		for a in rev.awards:
			arows.append([rev.year, a["award"], a["soldier"].full_name(), a["team"].abbrev if a["team"] != null else "-", a["line"]])
			targets.append(a["soldier"])
	v.add_child(UiKit.table(["YEAR", "AWARD", "SOLDIER", "TEAM", "SEASON"], arows, [70, 200, 220, 70, 330], {}, {},
		func(i: int): pages.open_player(targets[i])))
	v.add_child(UiKit.label("The full All-League teams are on the Awards page.", 13, UiKit.MUTED))
	return v


func _tally(tally: Dictionary, so: Soldier) -> Dictionary:
	if not tally.has(so):
		tally[so] = {"awards": 0, "mvps": 0, "all_league": 0}
	return tally[so]

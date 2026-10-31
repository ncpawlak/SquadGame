class_name LegacyPages
extends RefCounted
## The Legacy page: league history in tabs (champions, awards). Built by the hub like the other
## detail pages; reads Season.history and Season.review_history fresh every time.

const TABS := [["champions", "Champions"], ["awards", "Awards"], ["records", "Records"], ["callsigns", "Callsigns"], ["hall", "Hall of Fame"]]

var hub: Control  # hub.gd
var pages: FranchisePages
var tab := "champions"
## Records scope: a team abbrev for one franchise, "" for the whole league.
var records_team := ""


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
		"records":
			v.add_child(_records())
		"callsigns":
			v.add_child(_callsigns())
		"hall":
			v.add_child(_hall())
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


# --- records --------------------------------------------------------------------------

func _records() -> Control:
	var s := _season()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var scope := HBoxContainer.new()
	scope.add_theme_constant_override("separation", 12)
	scope.add_child(UiKit.label("Record book:", 16, UiKit.MUTED))
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(260, 44)
	UiKit.style_button(pick)
	pick.add_item("Whole league")
	for t: Team in s.league.teams:
		pick.add_item(t.name)
		if t.abbrev == records_team:
			pick.select(pick.item_count - 1)
	pick.item_selected.connect(func(i: int):
		records_team = "" if i == 0 else s.league.teams[i - 1].abbrev
		hub.replace("Legacy", legacy))
	scope.add_child(pick)
	v.add_child(scope)
	var abbrev := records_team
	var who := "LEAGUE" if abbrev == "" else s.league.team_by_abbrev(abbrev).name.to_upper()
	v.add_child(UiKit.label("The best mark in each category. Click a row for the top %d. Counts every season played, including this one." % Records.TOP_N, 13, UiKit.MUTED))

	v.add_child(pages._section("%s SEASON RECORDS" % who))
	v.add_child(_holders(Records.PLAYER_STATS, func(stat): return Records.player_seasons(s, stat, abbrev), "season"))
	v.add_child(pages._section("%s CAREER RECORDS" % who))
	v.add_child(_holders(Records.PLAYER_STATS, func(stat): return Records.player_careers(s, stat, abbrev), "career"))
	v.add_child(pages._section("%s TEAM RECORDS" % who))
	v.add_child(_holders(Records.TEAM_STATS, func(stat): return Records.team_seasons(s, stat, abbrev), "team"))
	return v


## One row per stat showing its record holder. `rows_for` returns the stat's top list.
func _holders(stats: Array, rows_for: Callable, kind: String) -> Control:
	var rows: Array = []
	var lists: Array = []
	for stat: Dictionary in stats:
		var top: Array = rows_for.call(stat)
		lists.append(top)
		if top.is_empty():
			rows.append([stat["label"], "-", "-", "", ""])
		else:
			rows.append([stat["label"], Records.format_value(stat, top[0]["value"])] + _holder_cells(top[0], kind))
	return UiKit.table(["RECORD", "VALUE", "HOLDER", "TEAM", "YEAR"], rows, [260, 80, 240, 70, 110], {}, {},
		func(i: int):
			if lists[i].is_empty():
				return
			var stat: Dictionary = stats[i]
			hub.open(stat["label"], func(): return record_page(stat, lists[i], kind)))


## The HOLDER, TEAM and YEAR cells of a record entry.
func _holder_cells(e: Dictionary, kind: String) -> Array:
	match kind:
		"team":
			return [e["team"], "", str(e["year"])]
		"career":
			var so: Soldier = e["soldier"]
			return [so.full_name(), "", str(e["first"]) if e["first"] == e["last"] else "%d-%d" % [e["first"], e["last"]]]
		_:
			var so: Soldier = e["soldier"]
			return [so.full_name(), e["team"] if e["team"] != "" else "-", str(e["year"])]


## The top entries of one record.
func record_page(stat: Dictionary, top: Array, kind: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var span := "CAREER" if kind == "career" else "SINGLE SEASON"
	v.add_child(pages._section("%s  -  %s" % [stat["label"].to_upper(), span]))
	var rows: Array = []
	for i in top.size():
		rows.append([i + 1, Records.format_value(stat, top[i]["value"])] + _holder_cells(top[i], kind))
	v.add_child(UiKit.table(["#", "VALUE", "HOLDER", "TEAM", "YEAR"], rows, [40, 80, 260, 70, 110], {}, {},
		func(i: int):
			if kind == "team":
				var t: Team = top[i]["team"]
				hub.open(t.name, func(): return pages.team_roster(t))
			else:
				pages.open_player(top[i]["soldier"])))
	return v


# --- retired callsigns ----------------------------------------------------------------

func _callsigns() -> Control:
	var s := _season()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var rule := "A callsign is retired when its soldier gave one club %d or more seasons and won a Season MVP or %d or more honors. Nobody in the league is given it again." % [
		RetiredCallsigns.MIN_SEASONS_WITH_CLUB, RetiredCallsigns.MIN_HONORS]
	var note := UiKit.label(rule, 13, UiKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	if not s.league.callsign_proposals.is_empty():
		v.add_child(pages._section("WAITING ON YOU"))
		var b := UiKit.button("Decide on %d retired callsign%s" % [s.league.callsign_proposals.size(), "" if s.league.callsign_proposals.size() == 1 else "s"], hub.open_callsign_proposals, 16)
		UiKit.style_primary(b)
		b.custom_minimum_size.x = 360
		v.add_child(b)
	var list: Array = s.league.retired_callsigns.duplicate()
	list.reverse()
	v.add_child(pages._section("RETIRED CALLSIGNS"))
	if list.is_empty():
		v.add_child(UiKit.label("None yet. They are retired after a career-ending season.", 15, UiKit.MUTED))
		return v
	var rows: Array = []
	var hl := {}
	for i in list.size():
		var e: Dictionary = list[i]
		rows.append(["\"%s\"" % String(e["callsign"]).to_upper(), e["soldier"].full_name(), e["team"], e["seasons"], e["year"], e["honors"].size()])
		if e["team"].user_controlled:
			hl[i] = UiKit.MINE
	v.add_child(UiKit.table(["CALLSIGN", "SOLDIER", "CLUB", "SEASONS", "RETIRED", "HONORS"], rows, [180, 220, 230, 90, 90, 90], hl, {},
		func(i: int): pages.open_player(list[i]["soldier"])))
	return v


## The user's open proposals, each with a yes/no.
func callsign_proposals() -> Control:
	var s := _season()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var open_list: Array = s.league.callsign_proposals
	if open_list.is_empty():
		v.add_child(UiKit.label("Nothing to decide.", 16, UiKit.MUTED))
		return v
	var help := UiKit.label("Retiring a callsign takes it out of the league for good: it hangs from your banner row and nobody is given it again. Anything you leave open is retired when the next season starts.", 14, UiKit.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)
	for e: Dictionary in open_list.duplicate():
		var card := UiKit.panel()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		var m := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 14)
		card.add_child(m)
		m.add_child(box)
		var so: Soldier = e["soldier"]
		box.add_child(UiKit.display("\"%s\"  -  %s" % [String(e["callsign"]).to_upper(), so.full_name()], 24, Color.WHITE))
		var honors: Array = e["honors"]
		var detail := UiKit.label("%d seasons with %s. Honors: %s" % [e["seasons"], e["team"].name, ", ".join(PackedStringArray(honors))], 15, UiKit.MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(detail)
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 12)
		var yes := UiKit.button("Retire the callsign", func():
			RetiredCallsigns.decide(s, e, true)
			hub.replace("Retired Callsigns", callsign_proposals), 16)
		UiKit.style_primary(yes)
		btns.add_child(yes)
		btns.add_child(UiKit.button("Keep it in play", func():
			RetiredCallsigns.decide(s, e, false)
			hub.replace("Retired Callsigns", callsign_proposals), 16))
		box.add_child(btns)
		v.add_child(card)
	return v


## A line of a club's retired callsigns for its team page, or null if it has none.
func banner_row(team: Team) -> Control:
	var list := RetiredCallsigns.of_team(_season().league, team)
	if list.is_empty():
		return null
	var parts: PackedStringArray = []
	for e: Dictionary in list:
		parts.append("\"%s\" (%s, %d)" % [String(e["callsign"]).to_upper(), e["soldier"].last_name, e["year"]])
	var l := UiKit.label("RETIRED CALLSIGNS   " + "   -   ".join(parts), 14, UiKit.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# --- hall of fame ---------------------------------------------------------------------

func _hall() -> Control:
	var s := _season()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var rule := "Retired soldiers are scored on their careers (production against the rest of the league, awards, titles and their best season). %d seasons after retiring the best of them above the bar are inducted, at most %d a year. An inducted callsign is retired too." % [
		HallOfFame.WAIT_SEASONS, HallOfFame.CLASS_MAX]
	var note := UiKit.label(rule, 13, UiKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	if s.hall_of_fame.is_empty():
		v.add_child(UiKit.label("Nobody has been inducted yet.", 15, UiKit.MUTED))
		return v
	var years: Array = []
	for e in s.hall_of_fame:
		if not years.has(e["year"]):
			years.append(e["year"])
	years.sort()
	years.reverse()
	for y in years:
		var members: Array = HallOfFame.class_of(s, y)
		v.add_child(pages._section("CLASS OF %d" % y))
		var rows: Array = []
		var hl := {}
		for i in members.size():
			var e: Dictionary = members[i]
			var so: Soldier = e["soldier"]
			var first := 0
			var last := 0
			for year in so.season_lines:
				first = int(year) if first == 0 else mini(first, int(year))
				last = maxi(last, int(year))
			var span := "" if first == 0 else (str(first) if first == last else "%d-%d" % [first, last])
			rows.append([so.full_name(), "\"%s\"" % so.callsign.to_upper() if so.callsign != "" else "-", e["club"] if e["club"] != null else "-", span, e["honors"].size(), "%.1f" % e["score"]])
			if e["club"] != null and e["club"].user_controlled:
				hl[i] = UiKit.MINE
		v.add_child(UiKit.table(["SOLDIER", "CALLSIGN", "CLUB", "CAREER", "HONORS", "SCORE"], rows, [230, 150, 230, 110, 90, 80], hl, {},
			func(i: int): pages.open_player(members[i]["soldier"])))
	return v

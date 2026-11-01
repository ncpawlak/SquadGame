class_name ClubPages
extends RefCounted
## Club tab pages (issue #8): the club's finances, its market and buzz, and its facilities (issue #38). Each
## returns a Control that the hub wraps in a titled, scrollable frame. Pages read Season state fresh every time
## they are built. Only the Facilities page changes the league (it buys upgrades). Revenue is a ledger the board
## reads; cash is the club fund, filled by the yearly board grant (issue #50) and spent on signing bonuses, the
## luxury tax and facilities.

var hub: Control  # hub.gd; a Node, so no RefCounted cycle


func _season() -> Season:
	return hub.season


func _vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _section(text: String) -> Label:
	if text.length() <= 40 and not text.contains("  -  "):
		return UiKit.display(text.to_upper(), 21, UiKit.TEXT)
	return UiKit.label(text, 15, UiKit.MUTED)


static func _money(k: float) -> String:
	return Contracts.money(roundi(k))


static func _trend_text(t: Team) -> String:
	match Market.trend(t):
		&"up":
			return "rising"
		&"down":
			return "cooling"
	return "steady"


# --- finances -------------------------------------------------------------------------

func finances() -> Control:
	var s := _season()
	var us := s.user_team()
	var rv := s.revenue
	var v := _vbox(14)
	var l := rv.ledger_of(s.year, us)
	v.add_child(_section("%s  -  %d SEASON  -  money earned, and the club fund" % [us.name.to_upper(), s.year]))
	if l.is_empty():
		v.add_child(UiKit.label("No ledger yet.", 16, UiKit.MUTED))
		return v
	var table_rows := rv.table(s)
	var rank := 0
	for i in table_rows.size():
		if table_rows[i]["team"] == us:
			rank = i + 1
	var net := float(l["net"])
	var fund := rv.cash_of(us)
	v.add_child(UiKit.rich("REVENUE [color=white]%s[/color]   -   OPERATING COST [color=white]%s[/color]   -   NET [color=%s]%s[/color]   -   CLUB FUND [color=%s]%s[/color]   -   #%d of %d in revenue" % [
		_money(float(l["revenue"])), _money(float(l["operations"])), UiKit.hex(UiKit.GOOD if net >= 0.0 else UiKit.BAD), _money(net),
		UiKit.hex(UiKit.BAD if fund < 0.0 else Color.WHITE), _money(fund), rank, table_rows.size()], 18))
	v.add_child(UiKit.rich("SPENT IN %d   signing bonuses [color=white]%s[/color]   -   luxury tax [color=white]%s[/color]   -   facilities [color=white]%s[/color]   -   facility upkeep [color=white]%s[/color]" % [
		s.year, _money(float(rv.bonuses_paid(s.year, us))), _money(float(rv.tax_paid(s.year, us))),
		_money(float(s.facilities.purchases_of(s.year, us))), _money(float(s.facilities.upkeep_of(s.year, us)))], 16))
	v.add_child(UiKit.label("The club fund is filled once a year by the board grant and pays signing bonuses, the luxury tax and facilities (upgrades and their yearly upkeep). It carries over with no limit. Revenue doesn't go into it: the board reads it. Player pay comes under the salary cap and is not taken from this money; a signing bonus is paid from the fund in full when he signs and never counts on the cap (at most half the deal's total salary).%s" % (
		"  While the fund is below $0 the board freezes spending: no bonuses, and no deal may take payroll over the tax line." if fund < 0.0 else ""), 14, UiKit.BAD if fund < 0.0 else UiKit.MUTED))
	var fb := UiKit.button("Facilities", func(): hub.open("Facilities", facilities), 15)
	fb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(fb)
	_board_section(v, s, us)

	v.add_child(_section("WHERE IT COMES FROM"))
	var n := float(table_rows.size())
	var avg := {}
	for key in ["tickets", "sponsors", "merch", "media", "bonus", "revenue"]:
		var tot := 0.0
		for r in table_rows:
			tot += float(r["ledger"][key])
		avg[key] = tot / maxf(1.0, n)
	var streams := [["Tickets", "tickets", "%d home games, %s average crowd" % [int(l["home_games"]), "%d" % (int(l["attendance"]) / maxi(1, int(l["home_games"])))]],
		["Sponsors", "sponsors", "this year's deal: %s" % _money(float(l["deal"]))], ["Merchandise", "merch", "buzz and star power"],
		["Media", "media", "equal league share"], ["Playoff bonuses", "bonus", "berth, wins, title"]]
	var rows: Array = []
	for st in streams:
		var amount := float(l[st[1]])
		rows.append([st[0], _money(amount), "%d%%" % roundi(100.0 * amount / maxf(1.0, float(l["revenue"]))), _money(avg[st[1]]), st[2]])
	rows.append(["Total revenue", _money(float(l["revenue"])), "100%", _money(avg["revenue"]), "%d sellouts" % int(l["sellouts"])])
	v.add_child(UiKit.table(["STREAM", "THIS YEAR", "SHARE", "LEAGUE AVG", "NOTE"], rows, [190, 120, 80, 130, 340]))

	v.add_child(_section("YEAR BY YEAR"))
	var years: Array = rv.ledgers.keys()
	years.sort()
	years.reverse()
	var hist: Array = []
	for y in years.slice(0, 8):
		var yl: Dictionary = rv.ledger_of(int(y), us)
		if not yl.is_empty():
			hist.append([str(y), _money(float(yl["revenue"])), _money(float(yl["net"])), "%d" % int(yl["sellouts"])])
	v.add_child(UiKit.table(["YEAR", "REVENUE", "NET", "SELLOUTS"], hist, [90, 140, 140, 110]))

	v.add_child(_section("THE LEAGUE'S MONEY"))
	var lrows: Array = []
	var hl := {}
	var colors := {}
	for i in table_rows.size():
		var t: Team = table_rows[i]["team"]
		var tl: Dictionary = table_rows[i]["ledger"]
		lrows.append([i + 1, t, Market.market_name(t), Market.band_name(t.buzz), _money(float(tl["revenue"])), _money(float(tl["tickets"])),
			_money(float(tl["sponsors"])), _money(float(tl["merch"])), _money(float(tl["net"])), _money(rv.cash_of(t))])
		if t.user_controlled:
			hl[i] = UiKit.MINE
		colors[i] = {3: UiKit.buzz_color(t.buzz)}
	v.add_child(UiKit.table(["#", "TEAM", "MARKET", "BUZZ", "REVENUE", "TICKETS", "SPONSORS", "MERCH", "NET", "FUND"], lrows,
		[30, 230, 160, 90, 100, 100, 100, 90, 100, 100], hl, colors,
		func(i: int): hub.open((table_rows[i]["team"] as Team).name, func(): return hub.pages.team_roster(table_rows[i]["team"]))))
	return v


## The latest board review (season end): each term of the grant, plus this year's grant preview terms.
func _board_section(v: VBoxContainer, s: Season, us: Team) -> void:
	var rv := s.revenue
	v.add_child(_section("BOARD REVIEW"))
	var years: Array = rv.grants.keys()
	years.sort()
	if years.is_empty():
		v.add_child(UiKit.label("The board reviews the season after the Final and grants next season's money: market size, results against the preseason expectation (#%d), playoff wins, awards, player development and unused cap room. A fund below $0 or three straight seasons below expectations cut the grant." % int(s.market.preseason_rank.get(us.abbrev, 0)), 14, UiKit.MUTED))
		return
	var y := int(years[-1])
	var r := rv.grant_of(y, us)
	if r.is_empty():
		return
	var rows := [["Market size", _money(float(r["market"])), "%s (rating %d)" % [Market.market_name(us), us.market_rating]],
		["Results", _money(float(r["results"])), "expected #%d, finished #%d" % [int(r["expected"]), int(r["finish"])]],
		["Playoffs", _money(float(r["playoffs"])), "$5M per playoff win, $15M for the title"],
		["Awards", _money(float(r["awards"])), "$2M per award or All-League pick"],
		["Development", _money(float(r["development"])), "$1M per dev-star gain or rookie beating his slot"],
		["Cap savings", _money(float(r["savings"])), "5% of room under the soft cap"],
		["Confidence", "x%.2f" % float(r["confidence"]), "fund below $0 (x0.90) or 3 straight seasons below expectations (x0.75)"],
		["Grant", _money(float(r["grant"])), "fund before: %s" % _money(float(r["cash_before"]))]]
	var colors := {1: {1: UiKit.GOOD if float(r["results"]) >= 0.0 else UiKit.BAD}, 6: {1: UiKit.BAD if float(r["confidence"]) < 1.0 else UiKit.MUTED}, 7: {1: UiKit.GOOD}}
	v.add_child(UiKit.label("After the %d season" % y, 15, Color.WHITE))
	v.add_child(UiKit.table(["TERM", "AMOUNT", "WHY"], rows, [170, 120, 520], {}, colors))


# --- facilities -----------------------------------------------------------------------

## Facilities (issue #38): the eight upgrades, what each level does, and buying the next one.
func facilities() -> Control:
	var s := _season()
	var us := s.user_team()
	var fx := s.facilities
	var v := _vbox(14)
	var offseason := s.phase == Season.PHASE_OFFSEASON
	var fund := s.revenue.cash_of(us)
	v.add_child(_section("%s  -  FACILITIES" % us.name.to_upper()))
	v.add_child(UiKit.rich("CLUB FUND [color=%s]%s[/color]   -   INVESTED [color=white]%s[/color]   -   UPKEEP [color=white]%s[/color] a year   -   %s" % [
		UiKit.hex(UiKit.BAD if fund < 0.0 else Color.WHITE), _money(fund), _money(float(Facilities.invested(us))),
		_money(float(Facilities.upkeep_due(s, us))),
		("UPGRADES LEFT [color=white]%d of %d[/color] this offseason" % [fx.upgrades_left(s, us), Facilities.MAX_UPGRADES]) if offseason else "upgrades open in the offseason"], 18))
	var last := s.year if offseason else s.year - 1
	var paid := fx.upkeep_of(last, us)
	var dropped := fx.drop_of(last, us)
	if dropped != &"":
		v.add_child(UiKit.label("The %d board review: the fund couldn't cover upkeep, so the %s lost a level." % [last, Facilities.facility_name(dropped)], 15, UiKit.BAD))
	elif paid > 0:
		v.add_child(UiKit.label("The %d board review took %s in upkeep." % [last, _money(float(paid))], 15, UiKit.MUTED))
	var help := UiKit.label("Upgrades are bought in the offseason from the club fund and work at once. One level per facility and %d upgrades a club each offseason. Upkeep is %d%% of everything invested (your starting levels count), at most %d%% of the year's board grant, and is charged right after the grant. If the fund can't cover it, a facility loses a level instead." % [
		Facilities.MAX_UPGRADES, roundi(100.0 * Facilities.UPKEEP_SHARE), roundi(100.0 * Facilities.UPKEEP_GRANT_CAP)], 14, UiKit.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)
	for id in Facilities.IDS:
		var lvl := Facilities.level(us, id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var name_l := UiKit.label(Facilities.facility_name(id), 17, Color.WHITE)
		name_l.custom_minimum_size.x = 230
		row.add_child(name_l)
		var lvl_l := UiKit.label("LEVEL %d" % lvl, 16, UiKit.GOOD if lvl >= Facilities.MAX_LEVEL else UiKit.TEXT)
		lvl_l.custom_minimum_size.x = 90
		row.add_child(lvl_l)
		var nxt := "[color=#8b97ab]top level[/color]" if lvl >= Facilities.MAX_LEVEL else "[color=#8b97ab]next:[/color] [color=white]%s[/color] for %s" % [
			Facilities.effect_text(id, lvl + 1), _money(float(Facilities.next_price(us, id)))]
		var fx_l := UiKit.rich("%s\n%s" % [Facilities.effect_text(id, lvl), nxt], 14)
		fx_l.custom_minimum_size.x = 560
		fx_l.fit_content = true
		row.add_child(fx_l)
		var err := fx.upgrade_error(s, us, id)
		var b := UiKit.button("Upgrade", _buy.bind(id), 15)
		b.disabled = err != ""
		b.tooltip_text = err
		row.add_child(b)
		v.add_child(row)
	return v


func _buy(id: StringName) -> void:
	var s := _season()
	var us := s.user_team()
	var e := s.facilities.upgrade(s, us, id)
	hub.app.toast(e if e != "" else "%s upgraded to level %d." % [Facilities.facility_name(id), Facilities.level(us, id)])
	hub.replace("Facilities", facilities)


# --- market and buzz ------------------------------------------------------------------

func market_buzz() -> Control:
	var s := _season()
	var us := s.user_team()
	var v := _vbox(14)
	v.add_child(_section("%s  -  %d SEASON  -  the city and how much it cares" % [us.name.to_upper(), s.year]))
	v.add_child(UiKit.market_meters(us, 18, 260))
	v.add_child(UiKit.label("Market size is fixed: a bad team still plays in a big city. Buzz moves with results, rivalries, streaks, the playoffs and big stories, but never fast. It drifts back to a resting level of %d for this market." % roundi(Market.baseline(us)), 14, UiKit.MUTED))

	v.add_child(_section("WHAT MOVED YOUR BUZZ THIS YEAR"))
	var log_rows: Array = []
	var colors := {}
	for e in Market.log_for(us, s.year).slice(0, 30):
		var a := float(e["amount"])
		log_rows.append([String(e["when"]), String(e["label"]), "%+.1f" % a])
		colors[log_rows.size() - 1] = {2: UiKit.GOOD if a > 0.0 else UiKit.BAD}
	if log_rows.is_empty():
		v.add_child(UiKit.label("Nothing yet this season.", 15, UiKit.MUTED))
	else:
		v.add_child(UiKit.table(["WHEN", "WHAT", "POINTS"], log_rows, [140, 520, 90], {}, colors))
	v.add_child(UiKit.label("Points go into a reservoir that buzz absorbs a little at a time; the league's average gain is shared out at season's end, so buzz is relative.", 13, UiKit.MUTED))

	v.add_child(_section("THE LEAGUE'S BUZZ"))
	var teams: Array = s.league.teams.duplicate()
	teams.sort_custom(func(a: Team, b: Team): return a.buzz > b.buzz)
	var rows: Array = []
	var hl := {}
	var tcolors := {}
	for i in teams.size():
		var t: Team = teams[i]
		rows.append([i + 1, t, Market.market_name(t), t.market_rating, Market.band_name(t.buzz), roundi(t.buzz), _trend_text(t)])
		if t.user_controlled:
			hl[i] = UiKit.MINE
		tcolors[i] = {4: UiKit.buzz_color(t.buzz), 6: UiKit.GOOD if Market.trend(t) == &"up" else (UiKit.BAD if Market.trend(t) == &"down" else UiKit.MUTED)}
	v.add_child(UiKit.table(["#", "TEAM", "MARKET", "RATING", "BUZZ", "", "TREND"], rows, [30, 230, 160, 70, 100, 50, 90], hl, tcolors,
		func(i: int): hub.open((teams[i] as Team).name, func(): return hub.pages.team_roster(teams[i]))))
	return v

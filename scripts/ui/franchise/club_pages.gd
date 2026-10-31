class_name ClubPages
extends RefCounted
## Club tab pages (issue #8): the club's finances and its market and buzz. Each returns a Control that
## the hub wraps in a titled, scrollable frame. Pages read Season state fresh every time they are built.
## Nothing here changes the league: the money shown is not connected to the salary cap or contracts.

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
	v.add_child(_section("%s  -  %d SEASON  -  money earned, and the club budget" % [us.name.to_upper(), s.year]))
	if l.is_empty():
		v.add_child(UiKit.label("No ledger yet.", 16, UiKit.MUTED))
		return v
	var table_rows := rv.table(s)
	var rank := 0
	for i in table_rows.size():
		if table_rows[i]["team"] == us:
			rank = i + 1
	var net := float(l["net"])
	v.add_child(UiKit.rich("REVENUE [color=white]%s[/color]   -   OPERATING COST [color=white]%s[/color]   -   NET [color=%s]%s[/color]   -   CASH [color=white]%s[/color]   -   #%d of %d in revenue" % [
		_money(float(l["revenue"])), _money(float(l["operations"])), UiKit.hex(UiKit.GOOD if net >= 0.0 else UiKit.BAD), _money(net),
		_money(rv.cash_of(us)), rank, table_rows.size()], 18))
	v.add_child(UiKit.label("Cash is the club budget: unspent for now (facilities and upgrades are not in yet). Player pay comes under the salary cap and is not taken from this money.", 14, UiKit.MUTED))

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
	v.add_child(UiKit.table(["#", "TEAM", "MARKET", "BUZZ", "REVENUE", "TICKETS", "SPONSORS", "MERCH", "NET", "CASH"], lrows,
		[30, 230, 160, 90, 100, 100, 100, 90, 100, 100], hl, colors,
		func(i: int): hub.open((table_rows[i]["team"] as Team).name, func(): return hub.pages.team_roster(table_rows[i]["team"]))))
	return v


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

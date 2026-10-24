extends Control
## Madden/CFB-style franchise hub: team header with Advance button, bumper-switched tabs
## (Home / Team / League / Personnel / Settings) of scrollable tile rows, and a page stack for
## detail screens (Esc / B goes back).

const TABS := ["Home", "Team", "League", "Personnel", "Settings"]
const HERO := Vector2(600, 240)
const TILE := Vector2(290, 170)
const SMALL := Vector2(290, 120)

var app: Control
var season: Season
var pages: FranchisePages

var tab_index := 0
## Each entry: {"title": String, "build": Callable -> Control}. Empty = showing tab tiles.
var page_stack: Array = []

var _header: PanelContainer
var _tab_bar: HBoxContainer
var _content: MarginContainer
var _scroll: ScrollContainer


func _ready() -> void:
	pages = FranchisePages.new()
	pages.hub = self
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_header = PanelContainer.new()
	_header.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, 0))
	root.add_child(_header)

	var tab_wrap := PanelContainer.new()
	var tsb := UiKit.flat(UiKit.BG.lightened(0.03), 0)
	tsb.content_margin_top = 6
	tsb.content_margin_bottom = 6
	tab_wrap.add_theme_stylebox_override("panel", tsb)
	root.add_child(tab_wrap)
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 8)
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_wrap.add_child(_tab_bar)

	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		_content.add_theme_constant_override("margin_" + side, 40)
	_content.add_theme_constant_override("margin_top", 18)
	_content.add_theme_constant_override("margin_bottom", 8)
	root.add_child(_content)

	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, 0))
	var hints := UiKit.label(
		"[Arrows/WASD/D-pad] Move     [Enter/A] Select     [Esc/B] Back     [Q/E or LB/RB] Tabs     [Space/Y] Advance     [Mouse wheel / drag] Scroll",
		14, UiKit.MUTED)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(hints)
	root.add_child(footer)

	refresh()


func _unhandled_input(event: InputEvent) -> void:
	var advance_key: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE
	var advance_pad: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y
	if advance_key or advance_pad:
		advance()
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN] and _scroll:
		_scroll.scroll_vertical += (-1 if event.keycode == KEY_PAGEUP else 1) * int(_scroll.size.y * 0.8)
		accept_event()


func _process(delta: float) -> void:
	# Right stick scrolls long pages (box scores, tables) like the console games.
	if _scroll and Input.get_connected_joypads().size() > 0:
		var y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
		if absf(y) > 0.25:
			_scroll.scroll_vertical += int(y * 1400.0 * delta)


# --- navigation ---------------------------------------------------------------

func refresh() -> void:
	_build_header()
	_build_tabs()
	_show_current()


func cycle_tab(dir: int) -> void:
	select_tab(wrapi(tab_index + dir, 0, TABS.size()))


func select_tab(i: int) -> void:
	tab_index = i
	page_stack.clear()
	_build_tabs()
	_show_current()


func open(title: String, build: Callable) -> void:
	page_stack.append({"title": title, "build": build})
	_show_current()


## Replace the top page (e.g. paging between weeks or refreshing after an action) without
## growing the back stack. Keeps the scroll position and the focused item.
func replace(title: String, build: Callable) -> void:
	var focus_index := -1
	var scroll_pos := 0
	if _scroll and is_instance_valid(_scroll):
		scroll_pos = _scroll.scroll_vertical
		focus_index = app.focusables(_content).find(get_viewport().gui_get_focus_owner())
	if not page_stack.is_empty():
		page_stack.pop_back()
	page_stack.append({"title": title, "build": build})
	_show_current(focus_index, scroll_pos)


func go_back() -> bool:
	if page_stack.is_empty():
		return false
	page_stack.pop_back()
	_show_current()
	return true


func coming_soon(title: String, bullets: Array) -> void:
	open(title, func(): return pages.coming_soon(title, bullets))


func advance() -> void:
	if season.phase == Season.PHASE_OFFSEASON:
		if not draft_done():
			open_draft_room()
			app.toast("Finish the draft (and any roster cuts) before starting the next season.")
			return
		season.start_next_season()
		page_stack.clear()
		tab_index = 0
		refresh()
		app.toast("Welcome to the %d season." % season.year)
		return
	var label := season.week_label(season.week)
	var played: Array = season.sim_week()
	page_stack.clear()
	_build_header()
	_build_tabs()
	open("%s Results" % label, func(): return pages.week_results(label, played))


func _show_current(focus_index := -1, scroll_pos := 0) -> void:
	for c in _content.get_children():
		c.queue_free()
	_scroll = null
	var view: Control
	if page_stack.is_empty():
		view = _tab_view(tab_index)
	else:
		var top: Dictionary = page_stack[-1]
		view = _page_frame(top["title"], top["build"].call())
	_content.add_child(view)
	_settle_focus(view, focus_index, scroll_pos)


## Focus once layout has settled. Autowrapped text is very tall before its first layout pass
## (and the web build can take more than one frame), so follow_focus stays off until then -
## otherwise long pages jumped to the bottom on open or after a Scout/refresh.
func _settle_focus(view: Control, focus_index: int, scroll_pos: int) -> void:
	var scroll := _scroll
	for i in 2:
		await get_tree().process_frame
		if not is_instance_valid(view) or not view.is_inside_tree():
			return
		if scroll:
			scroll.scroll_vertical = scroll_pos
	var list: Array[Control] = app.focusables(view)
	if focus_index >= 0 and not list.is_empty():
		list[mini(focus_index, list.size() - 1)].grab_focus()
	else:
		app.focus_first(view)
	if scroll:
		scroll.scroll_vertical = scroll_pos
		await get_tree().process_frame
		if is_instance_valid(scroll):
			scroll.scroll_vertical = scroll_pos
			scroll.follow_focus = true


func _page_frame(title: String, body: Control) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var back := UiKit.button("< Back", go_back)
	back.set_meta(&"skip_autofocus", true)
	head.add_child(back)
	var crumbs := "%s  /  " % TABS[tab_index].to_upper()
	for i in page_stack.size() - 1:
		crumbs += "%s  /  " % page_stack[i]["title"]
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(UiKit.label(crumbs, 12, UiKit.MUTED))
	tv.add_child(UiKit.label(title.to_upper(), 28, Color.WHITE))
	head.add_child(tv)
	_scroll = _make_scroll()
	v.add_child(_scroll)
	_scroll.add_child(body)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _make_scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.follow_focus = false  # enabled by _settle_focus once the page has laid out
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s


# --- header & tabs -------------------------------------------------------------

func _build_header() -> void:
	for c in _header.get_children():
		c.queue_free()
	var team := season.user_team()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	_header.add_child(hb)

	var logo := PanelContainer.new()
	logo.add_theme_stylebox_override("panel", UiKit.flat(team.color, 10))
	logo.custom_minimum_size = Vector2(72, 72)
	var ab := UiKit.label(team.abbrev, 24, Color.WHITE)
	ab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logo.add_child(ab)
	hb.add_child(logo)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	info.add_child(UiKit.label(team.name.to_upper(), 30, Color.WHITE))
	var rank := _rank_of(team)
	info.add_child(UiKit.label("%s   -   %s in %s   -   Team OVR %d" % [
		season.record_text(team), UiKit.ordinal(rank), Season.DIVISION_NAME, team.team_ovr()], 16, UiKit.MUTED))

	var when := VBoxContainer.new()
	when.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(when)
	var season_l := UiKit.label("%d SEASON" % season.year, 14, UiKit.MUTED)
	season_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	when.add_child(season_l)
	var week_l := UiKit.label(_phase_text(), 22, UiKit.ACCENT)
	week_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	when.add_child(week_l)

	var adv := UiKit.button(_advance_text(), advance, 20)
	adv.custom_minimum_size = Vector2(260, 64)
	adv.set_meta(&"skip_autofocus", true)
	UiKit.style_button(adv, UiKit.ACCENT.darkened(0.45), Color.WHITE, 10)
	hb.add_child(adv)


func _build_tabs() -> void:
	for c in _tab_bar.get_children():
		c.queue_free()
	_tab_bar.add_child(UiKit.label("Q / LB", 13, UiKit.MUTED))
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i].to_upper()
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size = Vector2(170, 44)
		b.focus_mode = Control.FOCUS_NONE
		var active := i == tab_index
		UiKit.style_button(b, UiKit.ACCENT.darkened(0.35) if active else UiKit.PANEL, UiKit.ACCENT, 8)
		if active:
			b.add_theme_color_override("font_color", Color.WHITE)
		var idx := i
		b.pressed.connect(func(): select_tab(idx))
		_tab_bar.add_child(b)
	_tab_bar.add_child(UiKit.label("E / RB", 13, UiKit.MUTED))


func _phase_text() -> String:
	match season.phase:
		Season.PHASE_OFFSEASON:
			return "OFFSEASON"
		Season.PHASE_PLAYOFFS:
			return "PLAYOFFS - %s" % season.week_label(season.week).to_upper()
	return "WEEK %d of %d" % [season.week, Season.REGULAR_WEEKS]


func _advance_text() -> String:
	if season.phase == Season.PHASE_OFFSEASON:
		if not draft_done():
			return "%d DRAFT  >>" % season.year
		return "START %d SEASON  >>" % (season.year + 1)
	var m := season.next_match_for(season.user_team())
	if m and m.week == season.week:
		return "PLAY %s  >>" % season.week_label(season.week).to_upper()
	return "SIM %s  >>" % season.week_label(season.week).to_upper()


func _rank_of(team: Team) -> int:
	for row in season.standings():
		if row.team == team:
			return row.rank
	return 0


# --- tab tile layouts ------------------------------------------------------------

func _tab_view(i: int) -> Control:
	_scroll = _make_scroll()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)
	var sections: Array = [_home_sections, _team_sections, _league_sections, _personnel_sections, _settings_sections][i].call()
	for sec in sections:
		v.add_child(UiKit.label(sec[0], 15, UiKit.MUTED))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 14)
		flow.add_theme_constant_override("v_separation", 14)
		for t in sec[1]:
			flow.add_child(t)
		v.add_child(flow)
		var gap := Control.new()
		gap.custom_minimum_size.y = 10
		v.add_child(gap)
	return _scroll


func _home_sections() -> Array:
	var team := season.user_team()
	var this_week: Array = []
	this_week.append(_next_match_tile(team))
	this_week.append(UiKit.tile(_advance_text().replace("  >>", ""), _advance_blurb(), Vector2(290, 240), UiKit.ACCENT, advance))
	var last := _last_played(team)
	if last:
		var won := last.winner() == team
		var body := "[font_size=34][color=%s]%s[/color] %s[/font_size]\n%s %s\n%s" % [
			UiKit.hex(UiKit.GOOD if won else UiKit.BAD), "W" if won else "L", _score_for(last, team),
			"vs" if last.home == team else "@", UiKit.esc(last.opponent_of(team).name), season.week_label(last.week)]
		this_week.append(UiKit.tile("Last Result", body, Vector2(290, 240), UiKit.INFO,
			func(): open("Match Recap", func(): return pages.recap(last))))
	else:
		this_week.append(UiKit.tile("Last Result", "No matches played yet.", Vector2(290, 240), UiKit.INFO,
			func(): app.toast("Play a match first.")))

	var league_tiles: Array = []
	league_tiles.append(UiKit.tile("Standings", _mini_standings(), TILE, Color("#a855f7"), open_standings))
	league_tiles.append(UiKit.tile("League News", _headline(), TILE, Color("#14b8a6"),
		func(): open("League News", pages.news)))
	league_tiles.append(UiKit.tile("League Leaders", _leader_blurb(), TILE, Color("#eab308"),
		func(): open("League Leaders", pages.leaders)))
	league_tiles.append(UiKit.tile("Playoff Picture", _playoff_blurb(), TILE, Color("#f43f5e"),
		func(): open("Playoff Picture", pages.playoffs)))

	var sp := 0
	var tired := 0
	var total_fat := 0.0
	for s in team.roster:
		if s.skill_points > 0:
			sp += 1
		if s.fatigue >= 50.0 and not s.is_injured():
			tired += 1
		total_fat += s.fatigue
	var hurt := team.injured()
	var hurt_text := "No injuries"
	if not hurt.is_empty():
		hurt_text = "[color=#ef4444]%d injured[/color]: %s" % [hurt.size(), ", ".join(PackedStringArray(hurt.map(func(x: Soldier): return x.short_name())))]
	var team_tiles: Array = [
		UiKit.tile("Roster", "%d players  -  OVR %d" % [team.roster.size(), team.team_ovr()], SMALL, team.color,
			func(): open("Roster", pages.roster)),
		UiKit.tile("Training", "Avg fatigue %d  -  %d tired" % [roundi(total_fat / maxi(1, team.roster.size())), tired],
			SMALL, Color("#22c55e"), func(): open("Training", pages.training)),
		UiKit.tile("Progression", ("[color=#38bdf8]%d players[/color] have skill points" % sp) if sp > 0 else "No skill points to spend",
			SMALL, UiKit.INFO, func(): open("Player Progression", pages.progression)),
		UiKit.tile("Injuries", hurt_text, SMALL, UiKit.BAD, func(): open("Injuries", pages.injuries)),
		UiKit.tile("Scouting", "[color=#38bdf8]%d scout points[/color]  -  %d of %d prospects scouted" % [
			season.draft.scout_points, _scouted_count(), Draft.CLASS_SIZE], SMALL, Color("#06b6d4"), open_scouting),
	]
	return [["THIS WEEK", this_week], ["AROUND THE LEAGUE", league_tiles], ["YOUR TEAM", team_tiles]]


func _scouted_count() -> int:
	var n := 0
	for p in season.draft.prospects:
		if p.points > 0:
			n += 1
	return n


## The offseason can roll over once the draft is done and the user is at the roster limit.
func draft_done() -> bool:
	return season.draft.is_complete() and not season.user_team().is_over_roster_limit()


func open_scouting() -> void:
	open("Scouting", pages.scouting)


func open_draft_room() -> void:
	open("Draft Room", pages.draft_room)


func open_mock_draft() -> void:
	open("Mock Draft", pages.mock_draft)


func _team_sections() -> Array:
	var team := season.user_team()
	return [
		["SQUAD", [
			UiKit.tile("Roster", "View every soldier, ratings and levels.", TILE, team.color, func(): open("Roster", pages.roster)),
			UiKit.tile("Lineup", "Set your Power Front starters:\n2 Frontmen, Center, 2 Flex.", TILE, Color("#f97316"), func(): open("Lineup", pages.lineup)),
			UiKit.tile("Player Progression", "Spend skill points on stat groups.", TILE, UiKit.INFO, func(): open("Player Progression", pages.progression)),
			UiKit.tile("Training", "Set each soldier's training intensity and watch fatigue.", TILE, Color("#22c55e"), func(): open("Training", pages.training)),
			UiKit.tile("Injuries", "Injury report for your team and the league.", TILE, UiKit.BAD, func(): open("Injuries", pages.injuries)),
		]],
		["PERFORMANCE", [
			UiKit.tile("Team Stats", "Season totals for your soldiers.", TILE, Color("#eab308"), func(): open("Team Stats", pages.team_stats)),
			UiKit.tile("Schedule", "Your matches, results and byes.", TILE, Color("#a855f7"), func(): open("Schedule", pages.schedule)),
		]],
		["ORGANISATION", [
			UiKit.tile("Scheme & Strategy", "Formations and round tactics.", TILE, UiKit.MUTED,
				func(): coming_soon("Scheme & Strategy", ["Alternate formations", "Aggression / pace sliders", "Per-mode round plans"]), "SOON"),
			UiKit.tile("Coaching Staff", "Hire coaches that boost training.", TILE, UiKit.MUTED,
				func(): coming_soon("Coaching Staff", ["Head coach and position coaches", "Training and progression boosts", "Staff contracts"]), "SOON"),
			UiKit.tile("Facilities", "Upgrade training grounds and medical.", TILE, UiKit.MUTED,
				func(): coming_soon("Facilities", ["Training facility upgrades", "Medical centre (injury recovery)", "Costs from the yearly money pool"]), "SOON"),
		]],
	]


func _league_sections() -> Array:
	return [
		["SEASON", [
			UiKit.tile("Standings", _mini_standings(), TILE, Color("#a855f7"), open_standings),
			UiKit.tile("Schedule", "Full league schedule by week.", TILE, Color("#6366f1"),
				func(): open("Scores & Schedule", func(): return pages.scores(clampi(season.week, 1, season.total_weeks())))),
			UiKit.tile("Scores", "Results from around the division.", TILE, UiKit.INFO,
				func(): open("Scores & Schedule", func(): return pages.scores(_last_week_with_results()))),
			UiKit.tile("Playoff Picture", _playoff_blurb(), TILE, Color("#f43f5e"), func(): open("Playoff Picture", pages.playoffs)),
		]],
		["STATS", [
			UiKit.tile("League Leaders", _leader_blurb(), TILE, Color("#eab308"), func(): open("League Leaders", pages.leaders)),
			UiKit.tile("Team Rankings", "Every team by OVR and record.", TILE, Color("#22c55e"), func(): open("Team Rankings", pages.team_rankings)),
			UiKit.tile("League News", _headline(), TILE, Color("#14b8a6"), func(): open("League News", pages.news)),
		]],
		["HISTORY", [
			UiKit.tile("Records & History", "Past champions and records.", TILE, UiKit.MUTED,
				func(): coming_soon("Records & History", ["Past champions by year", "Single-season and career records", "Hall of Fame"]), "SOON"),
			UiKit.tile("Awards", _awards_blurb(), TILE, Color("#f59e0b"), func(): open("Awards & Development", pages.awards)),
		]],
	]


func _personnel_sections() -> Array:
	var soon := func(title: String, sub: String, color: Color, bullets: Array) -> Button:
		return UiKit.tile(title, sub, TILE, color, func(): coming_soon(title, bullets), "SOON")
	return [
		["TRADES", [
			soon.call("Trade Center", "Propose trades with other teams.", Color("#f97316"), ["Player-for-player and multi-player trades", "AI trade evaluation", "In-season trade deadline"]),
			soon.call("Trade Block", "Shop your players around the league.", Color("#f97316"), ["List players for trade", "Receive AI offers"]),
		]],
		["CONTRACTS", [
			soon.call("Contracts & Payroll", "Salaries against the yearly money pool.", Color("#22c55e"), ["Contract length and salary", "Yearly money pool", "Payroll overview"]),
			soon.call("Re-sign Players", "Extend expiring contracts.", Color("#22c55e"), ["Expiring contracts list", "Player demands from OVR, age and potential", "Negotiation"]),
			soon.call("Free Agency", "Sign available soldiers.", Color("#22c55e"), ["Free agent pool", "Bidding against AI teams", "Release / cut players"]),
		]],
		["DRAFT", [
			UiKit.tile("Scouting", "Spend scout points to uncover the %d draft class.\n[color=#38bdf8]%d points available[/color]" % [
				season.draft.year, season.draft.scout_points], TILE, Color("#06b6d4"), open_scouting),
			UiKit.tile("Draft Room", _draft_blurb(), TILE, UiKit.INFO, open_draft_room),
			UiKit.tile("Mock Draft", "Where the league projects every pick, based on %s." % [
				"the draft order" if season.draft.is_started() else "current standings"], TILE, Color("#a855f7"), open_mock_draft),
		]],
	]


func _draft_blurb() -> String:
	var d := season.draft
	if not d.is_started():
		return "%d rounds after the Final. Worst finish picks first, snake order." % Draft.ROUNDS
	if d.is_complete():
		if season.user_team().is_over_roster_limit():
			return "[color=#ef4444]Cut your roster to %d.[/color]" % Team.ROSTER_SIZE
		return "Draft complete."
	var t := d.on_the_clock()
	return "[color=%s]On the clock: %s[/color]\nPick %d of %d" % [
		"#f59e0b" if t.user_controlled else "#8b97ab", UiKit.esc(t.name), d.next_pick + 1, d.order.size()]


func _settings_sections() -> Array:
	return [
		["FRANCHISE", [
			UiKit.tile("Sim Options", "Sim a week, to the playoffs, or the whole season.", TILE, UiKit.ACCENT, func(): open("Sim Options", pages.sim_options)),
			UiKit.tile("Save Franchise", "Save your progress.", TILE, UiKit.MUTED, func(): app.toast("Save / load is coming in a later milestone."), "SOON"),
			UiKit.tile("Load Franchise", "Load a saved franchise.", TILE, UiKit.MUTED, func(): app.toast("Save / load is coming in a later milestone."), "SOON"),
			UiKit.tile("Franchise Settings", "Difficulty, injuries, trade logic.", TILE, UiKit.MUTED,
				func(): coming_soon("Franchise Settings", ["Sim difficulty", "Injuries on/off and frequency", "Trade AI strictness", "Salary cap rules"]), "SOON"),
		]],
		["SYSTEM", [
			UiKit.tile("Debug Sim Tools", "The milestone 1 sandbox: single matches, batch sims, raw ratings.", TILE, Color("#64748b"), app.open_debug),
			UiKit.tile("Main Menu", "Back to the title screen. Your franchise stays loaded.", TILE, Color("#64748b"), app.show_title),
		]],
	]


func open_standings() -> void:
	open("Standings", pages.standings)


# --- tile text helpers -------------------------------------------------------------

func _next_match_tile(team: Team) -> Button:
	if season.phase == Season.PHASE_OFFSEASON:
		var champ := season.champion
		var body := "[font_size=30][color=white]%s[/color][/font_size]\n%d champions.\n\n%s" % [
			UiKit.esc(champ.name if champ else "-"), season.year,
			"Draft day is here: scout the class, then make your picks." if not draft_done() else "Draft complete. Start the next season when ready."]
		return UiKit.tile("Season Complete", body, HERO, UiKit.ACCENT, open_draft_room)
	var m := season.next_match_for(team)
	if m == null:
		var out := "Your season is over."
		if season.phase == Season.PHASE_PLAYOFFS:
			out = "Eliminated. The playoffs continue without you."
		return UiKit.tile("Next Match", out, HERO, UiKit.MUTED, func(): open("Playoff Picture", pages.playoffs))
	if m.week != season.week:
		var bye := "[font_size=30][color=white]BYE WEEK[/color][/font_size]\nNo match in %s. Your squad still trains.\n\nUp next: %s %s %s" % [
			season.week_label(season.week), season.week_label(m.week), "vs" if m.home == team else "@", UiKit.esc(m.opponent_of(team).name)]
		return UiKit.tile("This Week", bye, HERO, UiKit.MUTED, func(): open("Match Preview", func(): return pages.preview(m)))
	var opp := m.opponent_of(team)
	var body := "[font_size=34][color=white]%s %s[/color][/font_size]\n%s   -   %s\n\n%s  OVR %d   vs   %s  OVR %d\nRecord %s   vs   %s" % [
		"vs" if m.home == team else "@", UiKit.esc(opp.name), season.week_label(m.week),
		"Home" if m.home == team else "Away",
		team.abbrev, team.team_ovr(), opp.abbrev, opp.team_ovr(),
		season.record_text(team), season.record_text(opp)]
	return UiKit.tile("Next Match", body, HERO, opp.color, func(): open("Match Preview", func(): return pages.preview(m)))


func _advance_blurb() -> String:
	if season.phase == Season.PHASE_OFFSEASON:
		if not draft_done():
			return "Open the Draft Room: make your picks and cut down to %d." % Team.ROSTER_SIZE
		return "Roll over to next season with your drafted rookies."
	return "Train, play every match this week and award XP.\n\n[color=white]Space / Y[/color]"


func _last_played(team: Team) -> ScheduledMatch:
	var last: ScheduledMatch = null
	for m in season.matches_for(team):
		if m.is_played():
			last = m
	return last


func _score_for(m: ScheduledMatch, team: Team) -> String:
	return "%d-%d" % [m.rounds_for(team), m.rounds_for(m.opponent_of(team))]


func _mini_standings() -> String:
	var lines: Array[String] = []
	for row in season.standings():
		var c := "white" if row.team.user_controlled else "#8b97ab"
		lines.append("[color=%s]%d. %s  %d-%d[/color]" % [c, row.rank, row.team.abbrev, row.wins, row.losses])
	return "\n".join(lines)


func _headline() -> String:
	var news := pages.headlines(1)
	return news[0] if not news.is_empty() else "Preseason: %d teams chase the %s title." % [season.league.teams.size(), Season.DIVISION_NAME]


func _leader_blurb() -> String:
	var top := pages.season_totals()
	if top.is_empty():
		return "Kills, assists and damage leaders."
	top.sort_custom(func(a, b): return a["kills"] > b["kills"])
	var s: Soldier = top[0]["soldier"]
	return "Kills leader:\n[color=white]%s[/color] (%s)  %d K" % [UiKit.esc(s.full_name()), top[0]["team"].abbrev, top[0]["kills"]]


func _awards_blurb() -> String:
	if season.review != null and not season.review.awards.is_empty():
		var mvp: Dictionary = season.review.awards[0]
		return "%d MVP:\n[color=white]%s[/color] (%s)" % [season.review.year, UiKit.esc(mvp["soldier"].full_name()), mvp["team"].abbrev]
	return "MVP race, position awards, potential changes and aging."


func _playoff_blurb() -> String:
	if season.phase == Season.PHASE_REGULAR:
		var rows := season.standings()
		var cut: StandingRow = rows[Season.PLAYOFF_TEAMS - 1]
		return "Top %d make the playoffs.\nCurrently #%d: %s (%d-%d)" % [Season.PLAYOFF_TEAMS, Season.PLAYOFF_TEAMS, cut.team.abbrev, cut.wins, cut.losses]
	if season.champion:
		return "Champion: [color=white]%s[/color]" % UiKit.esc(season.champion.name)
	return "Playoffs underway: %s" % season.week_label(season.week)


func _last_week_with_results() -> int:
	var w := 1
	for i in range(1, season.total_weeks() + 1):
		for m in season.matches_for_week(i):
			if m.is_played():
				w = i
	return w

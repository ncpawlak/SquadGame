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
		_advance_offseason()
		return
	var label := season.week_label(season.week)
	var played: Array = season.sim_week()
	page_stack.clear()
	_build_header()
	_build_tabs()
	open("%s Results" % label, func(): return pages.week_results(label, played))


## Set when the user was warned about unused camp drills (advancing again skips them).
var _camp_skip_warned := false


## Offseason steps: re-sign window -> draft -> free agency days -> training camp -> next season.
func _advance_offseason() -> void:
	match season.offseason_stage:
		Season.OFF_RESIGN:
			season.advance_offseason()
			_rebuild_and_open("Draft Room", pages.draft_room)
			app.toast("Re-signing window closed. The %d draft is on." % season.draft.year)
		Season.OFF_DRAFT:
			if not season.draft.is_complete():
				_rebuild_and_open("Draft Room", pages.draft_room)
				app.toast("Make your picks (or sim the rest of the draft) first.")
				return
			season.advance_offseason()
			_rebuild_and_open("Free Agents", pages.free_agents)
			app.toast("Free agency is open: %d soldiers available. Offers are answered each FA day." % season.league.free_agents.size())
		Season.OFF_FREE_AGENCY:
			var label := "FA Day %d" % season.fa_day
			var signed: Array = season.advance_offseason()
			_camp_skip_warned = false
			_rebuild_and_open("%s Results" % label, func(): return pages.signings(label, signed))
			if season.camp_open():
				app.toast("Free agency is over. Training camp is open: send a player to each drill.")
		_:
			var user := season.user_team()
			if user.is_over_roster_limit():
				_rebuild_and_open("Contracts & Payroll", pages.contracts)
				app.toast("Can't start the season with %d players: release down to %d (player > Contract tab > Release)." % [user.roster.size(), Team.ROSTER_SIZE])
				return
			if season.camp_open() and season.camp.drills_left(user) > 0 and not _camp_skip_warned:
				_camp_skip_warned = true
				_rebuild_and_open("Training Camp", pages.training_camp)
				app.toast("%d camp drill%s unused. Advance again to skip them and start the season." % [
					season.camp.drills_left(user), "" if season.camp.drills_left(user) == 1 else "s"])
				return
			season.start_next_season()
			page_stack.clear()
			tab_index = 0
			refresh()
			app.toast("Welcome to the %d season." % season.year)


func _rebuild_and_open(title: String, build: Callable) -> void:
	page_stack.clear()
	_build_header()
	_build_tabs()
	open(title, build)


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
			match season.offseason_stage:
				Season.OFF_RESIGN:
					return "OFFSEASON - RE-SIGN"
				Season.OFF_DRAFT:
					return "OFFSEASON - DRAFT"
				Season.OFF_FREE_AGENCY:
					return "OFFSEASON - FREE AGENCY"
				Season.OFF_CAMP:
					return "OFFSEASON - TRAINING CAMP"
			return "OFFSEASON - PRESEASON"
		Season.PHASE_PLAYOFFS:
			return "PLAYOFFS - %s" % season.week_label(season.week).to_upper()
	return "WEEK %d of %d" % [season.week, Season.REGULAR_WEEKS]


func _advance_text() -> String:
	if season.phase == Season.PHASE_OFFSEASON:
		match season.offseason_stage:
			Season.OFF_RESIGN:
				return "TO THE DRAFT  >>"
			Season.OFF_DRAFT:
				return "%d DRAFT  >>" % season.year if not season.draft.is_complete() else "FREE AGENCY  >>"
			Season.OFF_FREE_AGENCY:
				return "FA DAY %d of %d  >>" % [season.fa_day, Season.FA_DAYS]
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
	if i == 0:
		v.add_child(_home_top())
		var gap0 := Control.new()
		gap0.custom_minimum_size.y = 6
		v.add_child(gap0)
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


## Home (2K / Madden style): big current-match pane up top, a row of this week's actions,
## then league news tiles.
func _home_sections() -> Array:
	var team := season.user_team()
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
	var unhappy := team.roster.filter(func(x: Soldier): return x.morale < Soldier.MORALE_NEUTRAL)
	var actions: Array = [
		UiKit.tile("Set Training", "Avg fatigue %d  -  %d tired" % [roundi(total_fat / maxi(1, team.roster.size())), tired],
			SMALL, Color("#22c55e"), func(): open("Training", pages.training)),
		UiKit.tile("Progress Players", ("[color=#38bdf8]%d players[/color] have skill points" % sp) if sp > 0 else "No skill points to spend",
			SMALL, UiKit.INFO, func(): open("Player Progression", pages.progression)),
		UiKit.tile("Adjust Lineup", "Swing  -  Team OVR %d%s" % [team.team_ovr(),
			("\n[color=#ef4444]%d injured[/color]" % hurt.size()) if not hurt.is_empty() else ""], SMALL, Color("#f97316"), func(): open("Lineup", pages.lineup)),
		UiKit.tile("Roster", "%d players%s" % [team.roster.size(),
			("  -  [color=#f97316]%d unhappy[/color]" % unhappy.size()) if not unhappy.is_empty() else "  -  morale good"], SMALL, team.color, func(): open("Roster", pages.roster)),
		UiKit.tile("Scout", "[color=#38bdf8]%d scout points[/color]  -  %d of %d scouted" % [
			season.draft.scout_points, _scouted_count(), Draft.CLASS_SIZE], SMALL, Color("#06b6d4"), open_scouting),
		UiKit.tile("Free Agents", "%d available%s" % [season.league.free_agents.size(),
			("  -  [color=#38bdf8]%d offers out[/color]" % season.fa.offers_by(team).size()) if not season.fa.offers_by(team).is_empty() else ""],
			SMALL, Color("#14b8a6"), open_free_agents),
		UiKit.tile("Contracts", "Cap space %s" % Contracts.money(Contracts.cap_space(team, season.cap_year())), SMALL, Color("#eab308"), open_contracts),
	]
	var league_tiles: Array = [
		UiKit.tile("Standings", _mini_standings(), TILE, Color("#a855f7"), open_standings),
		UiKit.tile("League Leaders", _leader_blurb(), TILE, Color("#eab308"), func(): open("League Leaders", pages.leaders)),
		UiKit.tile("Playoff Picture", _playoff_blurb(), TILE, Color("#f43f5e"), func(): open("Playoff Picture", pages.playoffs)),
	]
	if season.camp_open():
		actions.insert(0, UiKit.tile("Training Camp", "[color=#38bdf8]%d of %d drills left[/color]\nOne player per drill" % [
			season.camp.drills_left(team), Camp.DRILLS.size()], SMALL, Color("#22c55e"), open_camp))
	var out: Array = [["THIS WEEK", actions]]
	if season.phase == Season.PHASE_OFFSEASON:
		out.append(["OFFSEASON", _offseason_tiles()])
	out.append(["LEAGUE NEWS", _news_tiles()])
	out.append(["AROUND THE LEAGUE", league_tiles])
	return out


## Big pane: next match with both teams side by side, a stat comparison and impact players.
## Offseason / bye / eliminated fall back to the status tile, next to Advance and Last Result.
func _home_top() -> Control:
	var team := season.user_team()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var m := season.next_match_for(team) if season.phase != Season.PHASE_OFFSEASON else null
	if m != null and m.week == season.week:
		h.add_child(_match_pane(m, team))
	else:
		var t := _next_match_tile(team)
		t.custom_minimum_size = Vector2(900, 330)
		h.add_child(t)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 14)
	side.add_child(UiKit.tile(_advance_text().replace("  >>", ""), _advance_blurb(), Vector2(300, 158), UiKit.ACCENT, advance))
	var last := _last_played(team)
	if last:
		var won := last.winner() == team
		var body := "[font_size=28][color=%s]%s[/color] %s[/font_size]  %s %s\n%s" % [
			UiKit.hex(UiKit.GOOD if won else UiKit.BAD), "W" if won else "L", _score_for(last, team),
			"vs" if last.home == team else "@", UiKit.esc(last.opponent_of(team).abbrev), season.week_label(last.week)]
		side.add_child(UiKit.tile("Last Result", body, Vector2(300, 158), UiKit.INFO,
			func(): open("Match Recap", func(): return pages.recap(last))))
	else:
		side.add_child(UiKit.tile("Last Result", "No matches played yet.", Vector2(300, 158), UiKit.INFO,
			func(): app.toast("Play a match first.")))
	h.add_child(side)
	var cuts := _roster_cut_banner(team)
	if cuts == null:
		return h
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.add_child(cuts)
	v.add_child(h)
	return v


## Offseason rosters can run over the limit (draft picks, extra signings); the season can't
## start until the user cuts back down.
func _roster_cut_banner(team: Team) -> Control:
	if not team.is_over_roster_limit():
		return null
	var extra := team.roster.size() - Team.ROSTER_SIZE
	var body := "[color=white]%d / %d players.[/color]  Release [color=#ef4444]%d player%s[/color] before you can advance to Week 1 of the %d season.  Open a player > Contract tab > Release." % [
		team.roster.size(), Team.ROSTER_SIZE, extra, "" if extra == 1 else "s", season.year + (1 if season.phase == Season.PHASE_OFFSEASON else 0)]
	var t := UiKit.tile("Roster Cuts Required", body, Vector2(1214, 86), UiKit.BAD, open_contracts)
	t.name = "RosterCutBanner"
	return t


func _match_pane(m: ScheduledMatch, team: Team) -> Control:
	var opp := m.opponent_of(team)
	var pane := PanelContainer.new()
	var sb := UiKit.flat(UiKit.PANEL, 14, 1, UiKit.LINE)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	pane.add_theme_stylebox_override("panel", sb)
	pane.custom_minimum_size = Vector2(900, 330)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pane.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var wk := UiKit.label("%s   ·   %s" % [season.week_label(m.week).to_upper(), ("HOME vs " if m.home == team else "AWAY @ ") + opp.name.to_upper()], 14, UiKit.MUTED)
	wk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(wk)
	top.add_child(UiKit.button("Match Preview", func(): open("Match Preview", func(): return pages.preview(m)), 14))
	v.add_child(top)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.add_child(_team_block(team, false))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	var vs := UiKit.label("VS", 22, UiKit.MUTED)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(vs)
	for cmp in _compare_rows(team, opp):
		mid.add_child(_compare_bar(cmp[0], cmp[1], cmp[2], team.color, opp.color))
	row.add_child(mid)
	row.add_child(_team_block(opp, true))
	v.add_child(row)

	var imp := HBoxContainer.new()
	imp.add_theme_constant_override("separation", 10)
	imp.add_child(UiKit.label("IMPACT PLAYERS", 12, UiKit.MUTED))
	for t in [team, opp]:
		for so in _impact_players(t, 2):
			imp.add_child(_impact_chip(t, so))
	v.add_child(imp)
	return pane


func _team_block(t: Team, right: bool) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 210
	v.add_theme_constant_override("separation", 2)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	chip_row.add_child(UiKit.team_chip(t, 20))
	v.add_child(chip_row)
	var n := UiKit.label(t.name.to_upper(), 20, Color.WHITE)
	n.horizontal_alignment = align
	n.clip_text = true
	v.add_child(n)
	var o := UiKit.label(str(t.team_ovr()), 54, UiKit.ovr_color(t.team_ovr()))
	o.horizontal_alignment = align
	v.add_child(o)
	var r := UiKit.label("%s   ·   #%d" % [season.record_text(t), _rank_of(t)], 15, UiKit.MUTED)
	r.horizontal_alignment = align
	v.add_child(r)
	return v


## [label, ours, theirs] from each side's starters.
func _compare_rows(a: Team, b: Team) -> Array:
	var rows: Array = []
	for g in Stats.GROUP_ORDER:
		if g == Stats.DURABILITY:
			continue
		rows.append([Stats.GROUP_LABELS[g].to_upper(), _avg(a, func(x: Soldier): return x.group_rating(g)), _avg(b, func(x: Soldier): return x.group_rating(g))])
	rows.append(["MORALE", _avg(a, func(x: Soldier): return x.morale), _avg(b, func(x: Soldier): return x.morale)])
	rows.append(["ENERGY", _avg(a, func(x: Soldier): return 100.0 - x.fatigue), _avg(b, func(x: Soldier): return 100.0 - x.fatigue)])
	return rows


func _avg(t: Team, f: Callable) -> int:
	var list := t.starters()
	if list.is_empty():
		return 0
	var total := 0.0
	for s in list:
		total += float(f.call(s))
	return roundi(total / list.size())


func _compare_bar(title: String, ours: int, theirs: int, c1: Color, c2: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UiKit.label(str(ours), 16, Color.WHITE if ours >= theirs else UiKit.MUTED)
	l.custom_minimum_size.x = 30
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(l)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 1)
	var t := UiKit.label(title, 11, UiKit.MUTED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(t)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	var total := maxf(1.0, float(ours + theirs))
	var left := ColorRect.new()
	left.color = c1.lightened(0.1)
	left.custom_minimum_size.y = 6
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = ours / total
	bar.add_child(left)
	var right := ColorRect.new()
	right.color = c2.lightened(0.1)
	right.custom_minimum_size.y = 6
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = theirs / total
	bar.add_child(right)
	mid.add_child(bar)
	h.add_child(mid)
	var r := UiKit.label(str(theirs), 16, Color.WHITE if theirs >= ours else UiKit.MUTED)
	r.custom_minimum_size.x = 30
	h.add_child(r)
	return h


## Starters with the highest OVR at their slot.
func _impact_players(t: Team, n: int) -> Array:
	var list: Array = t.starters()
	list.sort_custom(func(a: Soldier, b: Soldier): return t.ovr_in_slot(a, t.slot_of(a)) > t.ovr_in_slot(b, t.slot_of(b)))
	return list.slice(0, n)


func _impact_chip(t: Team, s: Soldier) -> Control:
	var b := Button.new()
	UiKit.style_button(b, UiKit.PANEL_HI, UiKit.ACCENT, 8)
	b.custom_minimum_size = Vector2(186, 56)
	b.pressed.connect(func(): pages.open_player(s))
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Portrait.new(s.id, 42, t.color))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(UiKit.label(s.tag(), 15, Color.WHITE))
	var slot := t.slot_of(s)
	var o := t.ovr_in_slot(s, slot)
	var r := UiKit.rich("[color=#8b97ab]%s %s[/color]  [color=%s]%d[/color]" % [t.abbrev, slot, UiKit.hex(UiKit.ovr_color(o)), o], 13)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.custom_minimum_size.x = 120
	v.add_child(r)
	h.add_child(v)
	b.add_child(h)
	return b


## League news: last week's results (with MVPs), awards, signings, injuries and retirements.
func _news_tiles() -> Array:
	var out: Array = []
	var week := _last_week_with_results()
	for m: ScheduledMatch in season.matches_for_week(week):
		if not m.is_played():
			continue
		var win := m.winner()
		var mvp := pages._soldier(m.result.mvp_id)
		var line: Dictionary = m.result.box.get(m.result.mvp_id, {})
		var body := "[color=white]%s %d - %d %s[/color]" % [win.abbrev, m.rounds_for(win), m.rounds_for(m.loser()), m.loser().abbrev]
		if mvp != null and not line.is_empty():
			body += "\nMVP [color=#f59e0b]%s[/color]  %d K  %d SV" % [UiKit.esc(mvp.tag()), line["kills"], line.get("saves", 0)]
		var mm := m
		out.append(UiKit.tile("Final  ·  " + season.week_label(m.week), body, SMALL, win.color, func(): open("Match Recap", func(): return pages.recap(mm))))
	if season.review != null and not season.review.awards.is_empty():
		var a: Dictionary = season.review.awards[0]
		out.append(UiKit.tile("%d MVP" % season.review.year, "[color=white]%s[/color] (%s)" % [UiKit.esc(a["soldier"].display_name()), a["team"].abbrev],
			SMALL, UiKit.ACCENT, func(): open("Season Awards", pages.awards)))
	var hist: Array = season.fa.history
	for i in range(hist.size() - 1, maxi(-1, hist.size() - 4), -1):
		var e: Dictionary = hist[i]
		var so: Soldier = e["soldier"]
		out.append(UiKit.tile("Signing", "[color=white]%s[/color] (%d OVR) to %s\n%s x %d yr" % [UiKit.esc(so.display_name()), so.best_ovr(),
			e["team"].abbrev, Contracts.money(e["salary"]), e["years"]], SMALL, Color("#14b8a6"), func(): pages.open_player(so)))
	for inj in season.last_injuries.slice(0, 2):
		var so: Soldier = inj["soldier"]
		out.append(UiKit.tile("Injury", "[color=white]%s[/color] (%s)\n%s, out %d wk%s" % [UiKit.esc(so.tag()), inj["team"].abbrev, inj["name"],
			inj["weeks"], "" if inj["weeks"] == 1 else "s"], SMALL, UiKit.BAD, func(): open("Injuries", pages.injuries)))
	for n in season.last_prospect_news:
		var pr: Prospect = n["prospect"]
		var kind: StringName = n["kind"]
		var col: Color = UiKit.GOOD if kind == &"rising" else (UiKit.BAD if kind == &"falling" else Color("#06b6d4"))
		var head := "Stock Up" if kind == &"rising" else ("Stock Down" if kind == &"falling" else "Prospect Watch")
		out.append(UiKit.tile(head, "[color=white]%s[/color]\n[font_size=13]%s[/font_size]" % [
			UiKit.esc(pr.soldier.full_name()), UiKit.esc(n["text"])], SMALL, col,
			func(): open(pr.soldier.full_name(), func(): return pages.prospect(pr))))
	if draft_done() and season.draft.is_complete():
		var top: Prospect = season.draft.picks()[0]
		out.append(UiKit.tile("%d Draft" % season.draft.year, "[color=white]%s[/color] went #1 to %s\nSee the full recap" % [
			UiKit.esc(top.soldier.full_name()), top.drafted_by.abbrev], SMALL, UiKit.INFO, open_draft_recap))
	var ret := season.retirements_in(season.year)
	for r in ret.slice(0, 2):
		var so: Soldier = r["soldier"]
		out.append(UiKit.tile("Retirement", "[color=white]%s[/color] retires at %d\n%s" % [UiKit.esc(so.display_name()), r["age"],
			r["team"].abbrev if r["team"] != null else "free agent"], SMALL, Color("#94a3b8"), open_retirements))
	if out.is_empty():
		out.append(UiKit.tile("League News", _headline(), SMALL, Color("#14b8a6"), func(): open("League News", pages.news)))
	out.append(UiKit.tile("All News", "Every result and headline this season.", SMALL, Color("#14b8a6"), func(): open("League News", pages.news)))
	return out


func _offseason_tiles() -> Array:
	var team := season.user_team()
	var expiring := Contracts.expiring(team)
	var resign_text := "No expiring contracts."
	if not expiring.is_empty():
		resign_text = "[color=#f59e0b]%d expiring[/color]: %s" % [expiring.size(), ", ".join(PackedStringArray(expiring.map(func(x: Soldier): return x.short_name())))]
		if not season.can_resign():
			resign_text = "Window closed."
	var fa_text := "Opens after the draft.\n%d soldiers in the pool." % season.league.free_agents.size()
	if season.free_agency_open():
		fa_text = "%d available  -  [color=#38bdf8]%d pending offers[/color]\nCap space %s" % [
			season.league.free_agents.size(), season.fa.offers_by(team).size(), Contracts.money(Contracts.cap_space(team, season.cap_year()))]
	var ret := season.retirements_in(season.year)
	var mine := ret.filter(func(r): return r["team"] == team)
	var camp_text := "Opens after free agency.\n%d drills, one player each." % Camp.DRILLS.size()
	if season.camp_open():
		camp_text = "[color=#38bdf8]%d of %d drills left[/color]\nSend a player to each drill." % [season.camp.drills_left(team), Camp.DRILLS.size()]
	elif season.offseason_stage == Season.OFF_DONE:
		camp_text = "Camp is done."
	var draft_text := "Recap after the draft."
	if season.draft.is_complete():
		draft_text = "Every pick, ratings revealed."
	return [
		UiKit.tile("Re-sign Players", resign_text, SMALL, Color("#22c55e"), open_resign),
		UiKit.tile("Draft Recap", draft_text, SMALL, UiKit.INFO, open_draft_recap if season.draft.is_complete() else open_draft_room),
		UiKit.tile("Training Camp", camp_text, SMALL, Color("#22c55e"), open_camp),
		UiKit.tile("Free Agents", fa_text, SMALL, Color("#14b8a6"), open_free_agents),
		UiKit.tile("Retirements", "%d retired league-wide\n%d from your team" % [ret.size(), mine.size()], SMALL, Color("#94a3b8"), open_retirements),
		UiKit.tile("Contracts & Payroll", "Payroll %s of %s" % [Contracts.money(Contracts.payroll(team, season.cap_year())), Contracts.money(Contracts.SALARY_CAP)],
			SMALL, Color("#eab308"), open_contracts),
	]


func open_camp() -> void:
	open("Training Camp", pages.training_camp)


func open_draft_recap() -> void:
	var d := season.draft
	open("Draft Recap", func(): return pages.draft_recap(d))


func open_resign() -> void:
	open("Re-sign Players", pages.resign)


func open_free_agents() -> void:
	open("Free Agents", pages.free_agents)


func open_retirements() -> void:
	open("Retirements", pages.retirements)


func open_contracts() -> void:
	open("Contracts & Payroll", pages.contracts)


func _scouted_count() -> int:
	var n := 0
	for p in season.draft.prospects:
		if p.points > 0:
			n += 1
	return n


## The draft is finished (free agency or later).
func draft_done() -> bool:
	return season.phase == Season.PHASE_OFFSEASON and season.offseason_stage in [Season.OFF_FREE_AGENCY, Season.OFF_CAMP, Season.OFF_DONE]


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
			UiKit.tile("Lineup", "Set your Swing starters:\n2 Frontmen, Center, 2 Flex.", TILE, Color("#f97316"), func(): open("Lineup", pages.lineup)),
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
			UiKit.tile("Retirements", "Soldiers who hung up their boots, by season.\n[color=white]%d[/color] all-time" % season.retirements.size(),
				TILE, Color("#94a3b8"), open_retirements),
		]],
		["PLAYERS", [
			UiKit.tile("Teams", "Every team's roster, payroll and cap space.", TILE, Color("#6366f1"), func(): open("Teams", pages.teams)),
			UiKit.tile("Free Agents", "%d unsigned soldiers. Full ratings, no scouting needed.%s" % [season.league.free_agents.size(),
				"" if season.free_agency_open() else "\n[color=#8b97ab]Bidding reopens after the draft.[/color]"], TILE, Color("#14b8a6"), open_free_agents),
		]],
	]


func _personnel_sections() -> Array:
	var soon := func(title: String, sub: String, color: Color, bullets: Array) -> Button:
		return UiKit.tile(title, sub, TILE, color, func(): coming_soon(title, bullets), "SOON")
	var team := season.user_team()
	var n_exp := Contracts.expiring(team).size()
	return [
		["TRADES", [
			soon.call("Trade Center", "Propose trades with other teams.", Color("#f97316"), ["Player-for-player and multi-player trades", "AI trade evaluation", "In-season trade deadline", "Trades must fit under the salary cap"]),
			soon.call("Trade Block", "Shop your players around the league.", Color("#f97316"), ["List players for trade", "Receive AI offers"]),
		]],
		["CONTRACTS", [
			UiKit.tile("Contracts & Payroll", "Payroll [color=white]%s[/color] of %s\nCap space [color=%s]%s[/color]\nRelease players (dead money applies)." % [
				Contracts.money(Contracts.payroll(team, season.cap_year())), Contracts.money(Contracts.SALARY_CAP),
				"#22c55e" if Contracts.cap_space(team, season.cap_year()) >= 0 else "#ef4444", Contracts.money(Contracts.cap_space(team, season.cap_year()))],
				TILE, Color("#22c55e"), open_contracts),
			UiKit.tile("Re-sign Players", ("[color=#f59e0b]%d expiring[/color] contracts.\n" % n_exp if n_exp > 0 else "No expiring contracts.\n")
				+ ("Re-sign window is open." if season.can_resign() else "Opens after the Final, closes when free agency starts."), TILE, Color("#22c55e"), open_resign),
			UiKit.tile("Free Agency", "Bid on unsigned soldiers against the AI.\n%d available  -  %d of your offers pending" % [
				season.league.free_agents.size(), season.fa.offers_by(team).size()], TILE, Color("#14b8a6"), open_free_agents),
			soon.call("Negotiation", "Haggle over salary, years and bonuses.", UiKit.MUTED, ["Back-and-forth contract talks", "Signing bonuses, incentives and options", "Agent personalities and holdouts"]),
		]],
		["DRAFT", [
			UiKit.tile("Scouting", "Spend scout points to uncover the %d draft class.\n[color=#38bdf8]%d points available[/color]" % [
				season.draft.year, season.draft.scout_points], TILE, Color("#06b6d4"), open_scouting),
			UiKit.tile("Draft Room", _draft_blurb(), TILE, UiKit.INFO, open_draft_room),
			UiKit.tile("Mock Draft", "Where the league projects every pick, based on %s." % [
				"the draft order" if season.draft.is_started() else "current standings"], TILE, Color("#a855f7"), open_mock_draft),
			_draft_history_tile(),
		]],
	]


## The latest finished draft's recap (this offseason's, or last year's during the season).
func _draft_history_tile() -> Button:
	var d: Draft = season.draft if season.draft.is_complete() else (season.past_drafts[-1] if not season.past_drafts.is_empty() else null)
	if d == null:
		return UiKit.tile("Draft Recap", "Every pick with ratings and potential revealed, after the first draft.", TILE, UiKit.MUTED,
			func(): app.toast("No draft has been held yet."))
	return UiKit.tile("Draft Recap", "The %d draft: every pick with ratings and potential revealed." % d.year, TILE, UiKit.INFO,
		func(): open("Draft Recap", func(): return pages.draft_recap(d)))


func _draft_blurb() -> String:
	var d := season.draft
	if not d.is_started():
		return "%d rounds after the Final. Worst finish picks first, snake order." % Draft.ROUNDS
	if season.offseason_stage == Season.OFF_RESIGN:
		return "Re-signing window first.\nThe draft starts when you advance."
	if d.is_complete():
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
		var next_step := ""
		var target := open_draft_room
		match season.offseason_stage:
			Season.OFF_RESIGN:
				next_step = "Re-sign your expiring players, then advance to the draft."
				target = open_resign
			Season.OFF_DRAFT:
				next_step = "Draft day is here: scout the class, then make your picks."
			Season.OFF_FREE_AGENCY:
				next_step = "Free agency, day %d of %d: bid on soldiers before they sign elsewhere." % [season.fa_day, Season.FA_DAYS]
				target = open_free_agents
			Season.OFF_CAMP:
				next_step = "Training camp: send one player to each drill (%d left), then start the season." % season.camp.drills_left(team)
				target = open_camp
			_:
				next_step = "Free agency is over. Set your roster (%d-%d) and start the season." % [Season.ROSTER_MIN, Team.ROSTER_SIZE]
				target = open_contracts
		var body := "[font_size=30][color=white]%s[/color][/font_size]\n%d champions.\n\n%s" % [
			UiKit.esc(champ.name if champ else "-"), season.year, next_step]
		return UiKit.tile("Season Complete", body, HERO, UiKit.ACCENT, target)
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
		match season.offseason_stage:
			Season.OFF_RESIGN:
				return "Close the re-signing window. Unsigned expiring players hit free agency after the draft."
			Season.OFF_DRAFT:
				return "Make your picks in the Draft Room, then open free agency." if not season.draft.is_complete() else "Expiring players and undrafted prospects hit the market."
			Season.OFF_FREE_AGENCY:
				return "Players answer this round of offers. Best offer (money, team, playing time) wins." + (
					"\nTraining camp follows." if season.fa_day >= Season.FA_DAYS else "")
		if season.user_team().is_over_roster_limit():
			return "[color=#ef4444]Cut to %d players first[/color] (you have %d)." % [Team.ROSTER_SIZE, season.user_team().roster.size()]
		if season.camp_open() and season.camp.drills_left(season.user_team()) > 0:
			return "Close camp ([color=#f59e0b]%d drills unused[/color]) and start the %d season." % [season.camp.drills_left(season.user_team()), season.year + 1]
		return "Roll over to the %d season. Roster must be %d-%d." % [season.year + 1, Season.ROSTER_MIN, Team.ROSTER_SIZE]
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

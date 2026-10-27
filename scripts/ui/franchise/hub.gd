extends Control
## Madden/CFB-style franchise hub: team header with Advance button, bumper-switched tabs
## (Home / Team / League / Personnel / Settings) of scrollable tile rows, and a page stack for
## detail screens (Esc / B goes back).

const TABS := ["Home", "Team", "League", "Personnel", "Settings"]
const HERO := Vector2(600, 240)
const TILE := Vector2(290, 170)
const SMALL := Vector2(290, 120)
## League tiles that list a division or several leaders.
const TALL := Vector2(290, 236)

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
var _root: VBoxContainer
## Live match viewer overlay while watching the user's match (hub root hidden meanwhile).
var viewer: MatchViewer = null
## True while Sim To is running (input to advance is ignored).
var simming := false


func _ready() -> void:
	pages = FranchisePages.new()
	pages.hub = self
	var root := VBoxContainer.new()
	_root = root
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
	if viewer or simming:
		return
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
	if viewer:
		return
	select_tab(wrapi(tab_index + dir, 0, TABS.size()))


func select_tab(i: int) -> void:
	tab_index = i
	page_stack.clear()
	_build_tabs()
	_show_current()


## `no_back`: the page has its own exit (e.g. Continue), so the header hides "< Back".
func open(title: String, build: Callable, no_back := false) -> void:
	page_stack.append({"title": title, "build": build, "no_back": no_back})
	_show_current()


## Replace the top page (e.g. paging between weeks or refreshing after an action) without
## growing the back stack. Keeps the scroll position and the focused item.
func replace(title: String, build: Callable, no_back := false) -> void:
	var focus_index := -1
	var scroll_pos := 0
	if _scroll and is_instance_valid(_scroll):
		scroll_pos = _scroll.scroll_vertical
		focus_index = app.focusables(_content).find(get_viewport().gui_get_focus_owner())
	if not page_stack.is_empty():
		page_stack.pop_back()
	page_stack.append({"title": title, "build": build, "no_back": no_back})
	_show_current(focus_index, scroll_pos)


func go_back() -> bool:
	if viewer:
		viewer.toggle_pause()
		return true
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
	if season.preseason_camp:
		_close_preseason_camp()
		return
	if _roster_blocked():
		return
	var m := user_match_this_week()
	if m and not m.is_played() and not _on_matchup_page():
		season.prepare_week()
		_rebuild_and_open(season.week_label(season.week), func(): return pages.matchup(m))
		page_stack[-1]["kind"] = "matchup"
		return
	sim_week()


## The user's unplayed-or-played fixture in the current week (null on a bye / when eliminated).
func user_match_this_week() -> ScheduledMatch:
	if season.phase == Season.PHASE_OFFSEASON or season.preseason_camp:
		return null
	for m in season.matches_for_week(season.week):
		if m.involves(season.user_team()):
			return m
	return null


func _on_matchup_page() -> bool:
	return not page_stack.is_empty() and page_stack[-1].get("kind", "") == "matchup"


## Watch the user's match live; when the viewer finishes, the rest of the week is simmed.
func watch_match(m: ScheduledMatch) -> void:
	if viewer or m.is_played() or _roster_blocked():
		return
	viewer = MatchViewer.new()
	viewer.setup(m)
	viewer.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewer.finished.connect(_on_viewer_finished.bind(m))
	_root.visible = false
	add_child(viewer)


func _on_viewer_finished(r: MatchResult, m: ScheduledMatch) -> void:
	m.set_live_result(r)
	viewer.queue_free()
	viewer = null
	_root.visible = true
	sim_week()


## Sim the rest of the week (the user's match too, unless it was already watched) and show results.
func sim_week() -> void:
	if _roster_blocked():
		return
	var label := season.week_label(season.week)
	var played: Array = season.sim_week()
	_autosave()
	page_stack.clear()
	_build_header()
	_build_tabs()
	open("%s Results" % label, func(): return pages.week_results(label, played))


## The user's roster must be legal before he plays (exactly ROSTER_SIZE for Week 1, ROSTER_MIN..
## ROSTER_SIZE after). Short-handed with offers out, those offers are answered first. Returns true
## (and sends him to fix it) when he can't play yet.
func _roster_blocked() -> bool:
	var err := season.user_roster_error()
	if err == "":
		return false
	var user := season.user_team()
	var signed: Array = []
	if user.roster.size() < Team.ROSTER_SIZE:
		signed = season.resolve_user_offers()
		err = season.user_roster_error()
	if not signed.is_empty():
		var names: Array = signed.map(func(e): return e["soldier"].display_name())
		_rebuild_and_open("Signings", func(): return pages.signings("Your offers", signed))
		app.toast("Signed %s.%s" % [", ".join(names), (" " + err) if err != "" else " Roster set: advance to play."])
		return true
	if user.is_over_roster_limit():
		_rebuild_and_open("Contracts & Payroll", pages.contracts)
	else:
		_rebuild_and_open("Free Agents", pages.free_agents)
	app.toast(err)
	return true


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
			if season.camp_open() and season.camp.drills_left(user) > 0 and not _camp_skip_warned:
				_camp_skip_warned = true
				_rebuild_and_open("Training Camp", pages.training_camp)
				app.toast("%d camp drill%s unused. Advance again to skip them and start the season." % [
					season.camp.drills_left(user), "" if season.camp.drills_left(user) == 1 else "s"])
				return
			season.start_next_season()
			_autosave()
			page_stack.clear()
			tab_index = 0
			refresh()
			var err := season.user_roster_error()
			app.toast("Welcome to the %d season.%s" % [season.year, (" " + err) if err != "" else ""])


## "Sim to" choices available now: [[key, label], ...]. Empty in the offseason and camp.
func sim_to_targets() -> Array:
	if season.phase == Season.PHASE_OFFSEASON or season.preseason_camp:
		return []
	var out: Array = [[&"week", "Next week (sim %s)" % season.week_label(season.week)]]
	if season.phase == Season.PHASE_REGULAR:
		if season.week < Trades.DEADLINE_WEEK:
			out.append([&"deadline", "Trade deadline (start of Week %d)" % Trades.DEADLINE_WEEK])
		out.append([&"regular", "End of regular season"])
	out.append([&"season", "End of season (through the Final)"])
	return out


## Sims week after week (the user's matches included) until `target`. Stops early when the
## user's roster isn't legal to play.
## Full-screen "Simming..." overlay with a progress bar (meta: bar, label). Blocks input.
func _progress_overlay() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, 10))
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var label := UiKit.label("Simming...", 22, Color.WHITE)
	v.add_child(label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(520, 28)
	bar.show_percentage = true
	v.add_child(bar)
	dim.set_meta("bar", bar)
	dim.set_meta("label", label)
	add_child(dim)
	return dim


func sim_to(target: StringName) -> void:
	if target == &"week":
		sim_week()
		return
	var keep_going := func() -> bool:
		match target:
			&"deadline":
				return season.phase == Season.PHASE_REGULAR and season.week < Trades.DEADLINE_WEEK
			&"regular":
				return season.phase == Season.PHASE_REGULAR
		return season.phase != Season.PHASE_OFFSEASON
	var end_week := season.total_weeks()
	match target:
		&"deadline":
			end_week = Trades.DEADLINE_WEEK - 1
		&"regular":
			end_week = season.regular_weeks
	var start_week := season.week
	var overlay := _progress_overlay()
	var bar: ProgressBar = overlay.get_meta("bar")
	var label: Label = overlay.get_meta("label")
	bar.max_value = maxi(1, end_week - start_week + 1)
	var weeks := 0
	simming = true
	var blocked := false
	while keep_going.call():
		if _roster_blocked():
			blocked = true
			break
		label.text = "Simming %s...  (%d of %d)" % [season.week_label(season.week), weeks + 1, int(bar.max_value)]
		bar.value = weeks
		# Two frames so the overlay actually draws before the (blocking) week runs.
		await get_tree().process_frame
		await get_tree().process_frame
		season.sim_week()
		weeks += 1
	simming = false
	overlay.queue_free()
	if blocked:
		_build_header()
		return
	_autosave()
	page_stack.clear()
	tab_index = 0
	refresh()
	match target:
		&"deadline":
			app.toast("Simmed %d week%s. Trade deadline week: last chance to deal." % [weeks, "" if weeks == 1 else "s"])
		&"regular":
			app.toast("Regular season complete. %s" % ("You made the playoffs!" if season.playoff_seeds.has(season.user_team()) else "Your season is over."))
		_:
			app.toast("%s win the title." % (season.champion.name if season.champion else "-"))


## Opening camp of a new franchise: warn once about unused drills, then close it and go to Week 1.
func _close_preseason_camp() -> void:
	var user := season.user_team()
	if season.camp.drills_left(user) > 0 and not _camp_skip_warned:
		_camp_skip_warned = true
		_rebuild_and_open("Training Camp", pages.training_camp)
		app.toast("%d camp drill%s unused. Advance again to skip them and start the season." % [
			season.camp.drills_left(user), "" if season.camp.drills_left(user) == 1 else "s"])
		return
	season.close_preseason_camp()
	_autosave()
	_camp_skip_warned = false
	page_stack.clear()
	tab_index = 0
	refresh()
	app.toast("Training camp is over. Welcome to the %d season." % season.year)


## Autosave slot, written after every week and at the start of each season. Failures only toast.
func _autosave() -> void:
	var err := SaveSystem.autosave(season)
	if err != "":
		app.toast("Autosave failed: " + err)


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
	if not page_stack[-1].get("no_back", false):
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

	hb.add_child(UiKit.team_logo(team, 80))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	info.add_child(UiKit.label(team.name.to_upper(), 30, Color.WHITE))
	var rank := _rank_of(team)
	var where := "%s in %s" % [UiKit.ordinal(rank), Season.DIVISION_NAME]
	if season.has_divisions():
		var div := season.division_of(team)
		var drank := 0
		var drows: Array = season.division_standings(div)
		for i in drows.size():
			if (drows[i] as StandingRow).team == team:
				drank = i + 1
		where = "%s in the %s   -   %s in the league" % [UiKit.ordinal(drank), div, UiKit.ordinal(rank)]
	info.add_child(UiKit.label("%s   -   %s   -   Team OVR %d" % [
		season.record_text(team), where, team.team_ovr()], 16, UiKit.MUTED))

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
	var sim_targets := sim_to_targets()
	if not sim_targets.is_empty():
		var mb := MenuButton.new()
		mb.name = "SimToMenu"
		mb.text = "SIM TO  v"
		mb.flat = false
		mb.focus_mode = Control.FOCUS_ALL
		mb.custom_minimum_size = Vector2(140, 64)
		mb.add_theme_font_size_override("font_size", 18)
		mb.set_meta(&"skip_autofocus", true)
		UiKit.style_button(mb, UiKit.PANEL_HI, UiKit.ACCENT, 10)
		var pop := mb.get_popup()
		pop.add_theme_font_size_override("font_size", 18)
		for i in sim_targets.size():
			pop.add_item(sim_targets[i][1], i)
		pop.id_pressed.connect(func(id: int): sim_to(sim_targets[id][0]))
		hb.add_child(mb)
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
	if season.preseason_camp:
		return "PRESEASON - TRAINING CAMP"
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
	if season.is_bye(season.user_team(), season.week):
		return "WEEK %d of %d - BYE" % [season.week, season.regular_weeks]
	return "WEEK %d of %d" % [season.week, season.regular_weeks]


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
	if season.preseason_camp:
		return "START %d SEASON  >>" % season.year
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
		v.add_child(_home_feed())
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


## Done this week -> the results; otherwise the intensity screen (Confirm & Train).
func open_weekly_training() -> void:
	if season.user_trained():
		open("Training Results", pages.training_results, true)
	else:
		open("Training", pages.training)


## Home: to-dos left, current week right, then the news / playoff feed (all in _home_top).
func _home_sections() -> Array:
	return []


## A to-do tile. Done: greyed out with a check. Urgent: orange with a "!" in the corner.
func _todo(title: String, body: String, accent: Color, cb: Callable, done := false, urgent := false) -> Button:
	var t := UiKit.tile(("\u2713  " if done else "") + title, body, SMALL, UiKit.MUTED.darkened(0.3) if done else (Color("#f97316") if urgent else accent), cb)
	t.set_meta("todo_done", done)
	t.set_meta("todo_urgent", urgent)
	if done:
		t.modulate = Color(1, 1, 1, 0.45)
	if urgent:
		var bang := UiKit.label("!", 30, Color("#f97316"))
		bang.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bang.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		bang.offset_left = -34
		bang.offset_top = 6
		t.add_child(bang)
	return t


## This week's to-dos, ordered urgent > open > done.
func _todo_tiles(team: Team) -> Array:
	var out: Array = []
	var off := season.phase == Season.PHASE_OFFSEASON
	var roster := _roster_status(team)
	if not roster.is_empty():
		out.append(_todo(roster["title"], roster["body"], UiKit.BAD, roster["cb"], false, true))
	if not season.trades.offers.is_empty():
		var n := season.trades.offers.size()
		out.append(_todo("Trade Offers", "[color=#f59e0b]%d team%s[/color] want to deal.\nOffers expire at week's end." % [n, "" if n == 1 else "s"],
			Color("#f97316"), func(): open("Trade Offers", pages.trade_offers), false, true))
	if off:
		var expiring := Contracts.expiring(team)
		if season.can_resign() or season.offseason_stage == Season.OFF_RESIGN:
			out.append(_todo("Re-sign Players", ("[color=#f59e0b]%d expiring[/color]: %s" % [expiring.size(),
				", ".join(PackedStringArray(expiring.map(func(x: Soldier): return x.short_name())))]) if not expiring.is_empty() else "No expiring contracts.",
				Color("#22c55e"), open_resign, expiring.is_empty()))
		if season.offseason_stage == Season.OFF_DRAFT:
			var d := season.draft
			out.append(_todo("Draft Room", "Every pick is in." if d.is_complete() else "[color=#38bdf8]Your picks:[/color] %d left" % d.picks_left_for(team),
				UiKit.INFO, open_draft_room, d.is_complete()))
		if season.free_agency_open():
			var offers := season.fa.offers_by(team).size()
			out.append(_todo("Free Agency", "%d available  -  [color=#38bdf8]%d pending offer%s[/color]\nCap space %s" % [season.league.free_agents.size(), offers,
				"" if offers == 1 else "s", Contracts.money(Contracts.cap_space(team, season.cap_year()))], Color("#14b8a6"), open_free_agents))
	if season.camp_open():
		var left := season.camp.drills_left(team)
		out.append(_todo("Training Camp", ("[color=#38bdf8]%d of %d drills left[/color]\nOne player per drill" % [left, Camp.DRILLS.size()]) if left > 0 else "All drills done.",
			Color("#22c55e"), open_camp, left == 0))
	if not off and not season.preseason_camp:
		var tired := 0
		var total_fat := 0.0
		for s in team.roster:
			if s.fatigue >= 50.0 and not s.is_injured():
				tired += 1
			total_fat += s.fatigue
		var trained := season.user_trained()
		out.append(_todo("Weekly Training", "%s\nAvg fatigue %d  -  %d tired" % ["Done this week" if trained else (
			"[color=#38bdf8]Ready to train[/color]" if season.can_train_user_team() else "Not available this week"),
			roundi(total_fat / maxi(1, team.roster.size())), tired], Color("#22c55e"), open_weekly_training, trained or not season.can_train_user_team()))
	var sp := 0
	for s in team.roster:
		if Progression.can_level_up(s):
			sp += 1
	if sp > 0:
		out.append(_todo("Upgrade Players", "[color=#38bdf8]%d player%s[/color] can level up" % [sp, "" if sp == 1 else "s"],
			UiKit.INFO, func(): open("Player Progression", pages.progression)))
	if not off and not season.preseason_camp:
		var pts := season.draft.scout_points
		out.append(_todo("Scout", ("[color=#38bdf8]%d scout points[/color]\n%d of %d prospects scouted" % [pts, _scouted_count(), Draft.CLASS_SIZE]) if pts > 0
			else "All points spent.\n%d of %d prospects scouted" % [_scouted_count(), Draft.CLASS_SIZE], Color("#06b6d4"), open_scouting, pts <= 0))
	var hurt_starters := team.starters().filter(func(x: Soldier): return x.is_injured())
	var hurt := team.injured()
	out.append(_todo("Adjust Lineup", "%s  -  Team OVR %d%s" % [team.scheme.display_name, team.team_ovr(),
		("\n[color=#ef4444]%d injured starter%s[/color]" % [hurt_starters.size(), "" if hurt_starters.size() == 1 else "s"]) if not hurt_starters.is_empty() else (
			("\n%d injured on the bench" % hurt.size()) if not hurt.is_empty() else "\nLineup is set.")],
		Color("#f97316"), func(): open("Lineup", pages.lineup), hurt_starters.is_empty(), not hurt_starters.is_empty()))
	var rank := func(t: Button) -> int:
		return 0 if t.get_meta("todo_urgent") else (2 if t.get_meta("todo_done") else 1)
	var keyed: Array = []
	for i in out.size():
		keyed.append([rank.call(out[i]), i, out[i]])
	keyed.sort()
	return keyed.map(func(k): return k[2])


## Week shown on Home: 0 = the current week, else a week browsed with the arrows on the week label.
var home_week := 0
var _home_anchor := ""


## Top of Home: this week's to-dos stacked on the left; on the right the week browser (arrows,
## advance button) over the shown week (match pane, final score or status).
func _home_top() -> Control:
	var team := season.user_team()
	var anchor := "%d|%d|%s|%s|%s" % [season.year, season.week, season.phase, season.offseason_stage, season.preseason_camp]
	if anchor != _home_anchor:
		_home_anchor = anchor
		home_week = 0
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new()
	left.name = "TodoColumn"
	left.add_theme_constant_override("separation", 10)
	left.add_child(UiKit.label("THIS WEEK", 15, UiKit.MUTED))
	for t in _todo_tiles(team):
		left.add_child(t)
	top.add_child(left)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	var view := _home_week_view(team)
	right.add_child(_week_nav(view.get_meta(&"has_play", false)))
	right.add_child(view)
	top.add_child(right)
	return top


## The week Home shows when not browsing: the current week in season, 0 in preseason camp
## (Week 1 is next) and one past the final in the offseason.
func _now_week() -> int:
	if season.preseason_camp:
		return 0
	if season.phase == Season.PHASE_OFFSEASON:
		return season.total_weeks() + 1
	return season.week


func _shown_week() -> int:
	return home_week if home_week != 0 else _now_week()


func browse_week(dir: int) -> void:
	var w := clampi(_shown_week() + dir, 1, season.total_weeks())
	home_week = 0 if w == _now_week() else w
	select_tab(0)


## "< WEEK 3 of 12 >" plus, unless the match pane carries it, the advance button.
func _week_nav(pane_has_play: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "WeekNav"
	row.add_theme_constant_override("separation", 10)
	var w := _shown_week()
	var prev := UiKit.button("  <  ", func(): browse_week(-1), 18)
	prev.name = "WeekPrev"
	prev.disabled = w <= 1
	prev.tooltip_text = "Previous week"
	row.add_child(prev)
	var text := _phase_text()
	if home_week != 0:
		text = ("WEEK %d of %d" % [w, season.regular_weeks]) if w <= season.regular_weeks else "PLAYOFFS - %s" % season.week_label(w).to_upper()
	var lbl := UiKit.label(text, 17, Color.WHITE if home_week == 0 else UiKit.INFO)
	lbl.custom_minimum_size.x = 300
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_vertical = Control.SIZE_FILL
	row.add_child(lbl)
	var next := UiKit.button("  >  ", func(): browse_week(1), 18)
	next.name = "WeekNext"
	next.disabled = w >= season.total_weeks()
	next.tooltip_text = "Next week"
	row.add_child(next)
	if home_week != 0:
		row.add_child(UiKit.button("Back to %s" % ("this week" if _now_week() >= 1 and _now_week() <= season.total_weeks() else "today"), func():
			home_week = 0
			select_tab(0), 14))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	if not pane_has_play:
		row.add_child(_play_button())
	return row


## The accent advance button ("PLAY WEEK 3 >>", "START 2027 SEASON >>", ...).
func _play_button() -> Button:
	var b := UiKit.button(_advance_text(), advance, 17)
	b.name = "PlayButton"
	UiKit.style_button(b, UiKit.ACCENT.darkened(0.45), UiKit.ACCENT, 8)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.custom_minimum_size = Vector2(240, 42)
	b.tooltip_text = _advance_blurb().replace("[color=white]", "").replace("[color=#f59e0b]", "").replace("[color=#ef4444]", "").replace("[/color]", "")
	return b


## The shown week's pane (900 x 330). Meta has_play: the pane carries the advance button.
func _home_week_view(team: Team) -> Control:
	var view: Control
	if home_week == 0:
		var m := season.next_match_for(team) if season.phase != Season.PHASE_OFFSEASON and not season.preseason_camp else null
		if m != null and m.week == season.week:
			view = _match_pane(m, team)
			view.set_meta(&"has_play", true)
		else:
			view = _next_match_tile(team)
			view.custom_minimum_size = Vector2(900, 330)
		return view
	var w := home_week
	var mine: ScheduledMatch = null
	for x in season.matches_for_week(w):
		if x.involves(team):
			mine = x
	if mine != null and mine.is_played():
		return _result_pane(mine, team)
	if mine != null:
		return _match_pane(mine, team)
	var body := ""
	if w <= season.regular_weeks:
		body = "[font_size=30][color=white]BYE WEEK[/color][/font_size]\nNo match in %s. The squad trains." % season.week_label(w)
	elif season.matches_for_week(w).is_empty():
		body = "[font_size=30][color=white]TO BE DECIDED[/color][/font_size]\n%s matchups are set by earlier playoff results." % season.week_label(w)
	else:
		body = "[font_size=30][color=white]NO MATCH[/color][/font_size]\n%s goes on without you." % season.week_label(w)
	var t := UiKit.tile(season.week_label(w), body, Vector2(900, 330), UiKit.MUTED, func(): open("Scores & Schedule", func(): return pages.scores(w)))
	return t


## A played week on Home: final score, game-by-game results, MVP and a Box Score button.
func _result_pane(m: ScheduledMatch, team: Team) -> Control:
	var opp := m.opponent_of(team)
	var won := m.winner() == team
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
	var wk := UiKit.label("%s   ·   FINAL   ·   %s" % [season.week_label(m.week).to_upper(), ("HOME vs " if m.home == team else "AWAY @ ") + opp.name.to_upper()], 14, UiKit.MUTED)
	wk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(wk)
	var box := UiKit.button("Box Score", func(): open("Match Recap", func(): return pages.recap(m)), 14)
	box.name = "BoxScoreButton"
	top.add_child(box)
	v.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.add_child(_team_block(team, false))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 4)
	var res := UiKit.label("VICTORY" if won else "DEFEAT", 22, UiKit.GOOD if won else UiKit.BAD)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(res)
	var sc := UiKit.label("%d  -  %d" % [m.games_for(team), m.games_for(opp)], 54, Color.WHITE)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(sc)
	for g in m.result.games:
		var gw: Team = m.result.teams[g["winner"]]
		var gl := UiKit.rich("[center][color=#8b97ab]GAME %d  %s[/color]   [color=white]%s %s %s[/color]   [color=%s]%s[/color][/center]" % [
			g["number"], MatchEngine.MODE_SHORT[g["mode"]], team.abbrev, MatchResult.game_score_text(g, m.result.teams[0] != team), opp.abbrev,
			UiKit.hex(UiKit.GOOD if gw == team else UiKit.BAD), gw.abbrev], 15)
		mid.add_child(gl)
	row.add_child(mid)
	row.add_child(_team_block(opp, true))
	v.add_child(row)
	var mvp := pages._soldier(m.result.mvp_id)
	if mvp != null:
		var mt := pages._team_of(mvp)
		v.add_child(UiKit.rich("[color=#8b97ab]MVP[/color]   [color=#f59e0b]%s[/color]%s" % [UiKit.esc(mvp.display_name()), ("  (%s)" % mt.abbrev) if mt else ""], 15))
	return pane


## Rosters can run over the limit (trades, draft picks, extra signings) or short (trades,
## expiring deals). Week 1 needs exactly ROSTER_SIZE, later matches ROSTER_MIN..ROSTER_SIZE.
## Returns {} when legal, else {title, body, cb} for an urgent to-do.
func _roster_status(team: Team) -> Dictionary:
	var n := team.roster.size()
	var before_week1 := season.phase == Season.PHASE_OFFSEASON or season.preseason_camp or (season.phase == Season.PHASE_REGULAR and season.week == 1)
	var lo := Team.ROSTER_SIZE if before_week1 else Season.ROSTER_MIN
	if n <= Team.ROSTER_SIZE and n >= lo:
		return {}
	# Early offseason: the roster is still taking shape (expiring deals leave, picks arrive).
	if season.phase == Season.PHASE_OFFSEASON and n < lo and season.offseason_stage in [Season.OFF_RESIGN, Season.OFF_DRAFT]:
		return {}
	# Offseason rosters may carry up to OFFSEASON_MAX until camp ends.
	if season.phase == Season.PHASE_OFFSEASON and n > Team.ROSTER_SIZE and season.offseason_stage in [Season.OFF_RESIGN, Season.OFF_DRAFT, Season.OFF_FREE_AGENCY]:
		return {}
	var when := "Week 1" if before_week1 else "your next match"
	if n > Team.ROSTER_SIZE:
		var extra := n - Team.ROSTER_SIZE
		return {"title": "Roster Cuts", "body": "[color=white]%d / %d players.[/color] Release or trade [color=#ef4444]%d[/color] before %s." % [
			n, Team.ROSTER_SIZE, extra, when], "cb": open_contracts}
	var short := lo - n
	return {"title": "Roster Spots Open", "body": "[color=white]%d / %d players.[/color] Sign [color=#f59e0b]%d free agent%s[/color] before %s." % [
		n, Team.ROSTER_SIZE, short, "" if short == 1 else "s", when], "cb": open_free_agents}


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
	if m.week == season.week and not m.is_played() and season.phase != Season.PHASE_OFFSEASON and not season.preseason_camp:
		top.add_child(_play_button())
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
	for cmp in compare_rows(team, opp):
		mid.add_child(compare_bar(cmp, team.color, opp.color))
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
	var logo_row := HBoxContainer.new()
	logo_row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	logo_row.add_theme_constant_override("separation", 12)
	var o := UiKit.label(str(t.team_ovr()), 50, UiKit.ovr_color(t.team_ovr()))
	o.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if right:
		logo_row.add_child(o)
	logo_row.add_child(UiKit.team_logo(t, 100))
	if not right:
		logo_row.add_child(o)
	v.add_child(logo_row)
	# Full name under the logo; wraps to a second line instead of clipping.
	var n := UiKit.label(t.name.to_upper(), 18, Color.WHITE)
	n.horizontal_alignment = align
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 210
	v.add_child(n)
	var r := UiKit.label("%s   ·   #%d" % [season.record_text(t), _rank_of(t)], 15, UiKit.MUTED)
	r.horizontal_alignment = align
	v.add_child(r)
	return v


## Season team stats per game with league rank: {label, a, b, a_text, b_text, lower_better}.
## Before either side has played, falls back to the starters' group ratings.
func compare_rows(a: Team, b: Team) -> Array:
	var agg: Dictionary = pages.team_aggregates()
	var rows: Array = []
	if int(agg[a]["gp"]) == 0 and int(agg[b]["gp"]) == 0:
		for g in Stats.GROUP_ORDER:
			if g == Stats.DURABILITY:
				continue
			var x := _avg(a, func(s: Soldier): return s.group_rating(g))
			var y := _avg(b, func(s: Soldier): return s.group_rating(g))
			rows.append({"label": Stats.GROUP_LABELS[g].to_upper() + " (RATING)", "a": x, "b": y, "a_text": str(x), "b_text": str(y), "lower": false})
		return rows
	var per := func(k: String) -> Callable:
		return func(r: Dictionary) -> float: return float(r[k]) / maxi(1, int(r["gp"]))
	var defs: Array = [
		["KILLS / GAME", per.call("kills"), "%.1f", false],
		["DEATHS / GAME", per.call("deaths"), "%.1f", true],
		["ASSISTS / GAME", per.call("assists"), "%.1f", false],
		["CAPTURES / GAME", per.call("caps"), "%.1f", false],
		["HILL TIME / GAME", per.call("hill_s"), "secs", false],
		["K/D", func(r: Dictionary) -> float: return float(r["kills"]) / maxi(1, int(r["deaths"])), "%.2f", false],
		["WIN %", func(r: Dictionary) -> float: return 100.0 * float(r["w"]) / maxi(1, int(r["gp"])), "%d%%", false],
	]
	var played: Array = agg.values().filter(func(r: Dictionary): return int(r["gp"]) > 0)
	for d in defs:
		var f: Callable = d[1]
		var lower: bool = d[3]
		var vals: Array = played.map(func(r: Dictionary): return f.call(r))
		var fmt := func(t: Team) -> String:
			var r: Dictionary = agg[t]
			if int(r["gp"]) == 0:
				return "-"
			var x: float = f.call(r)
			var rank := 1
			for o in vals:
				if (o < x if lower else o > x):
					rank += 1
			var txt: String = MatchEngine._fmt_secs(x) if d[2] == "secs" else (d[2] % (roundi(x) if d[2] == "%d%%" else x))
			return "%s (#%d)" % [txt, rank]
		rows.append({"label": d[0], "a": f.call(agg[a]), "b": f.call(agg[b]), "a_text": fmt.call(a), "b_text": fmt.call(b), "lower": lower})
	return rows


func _avg(t: Team, f: Callable) -> int:
	var list := t.starters()
	if list.is_empty():
		return 0
	var total := 0.0
	for s in list:
		total += float(f.call(s))
	return roundi(total / list.size())


func compare_bar(row: Dictionary, c1: Color, c2: Color) -> Control:
	var title: String = row["label"]
	var lower: bool = row["lower"]
	var ours := float(row["a"])
	var theirs := float(row["b"])
	var ours_better := ours <= theirs if lower else ours >= theirs
	var theirs_better := theirs <= ours if lower else theirs >= ours
	if lower:
		var tmp := ours
		ours = theirs
		theirs = tmp
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UiKit.label(row["a_text"], 16, Color.WHITE if ours_better else UiKit.MUTED)
	l.custom_minimum_size.x = 92
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
	var r := UiKit.label(row["b_text"], 16, Color.WHITE if theirs_better else UiKit.MUTED)
	r.custom_minimum_size.x = 92
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
	h.add_child(Portrait.new(s, 42, t.color, t))
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


## News feed: one row per story. cat: &"league" (results, wire, signings, trades, injuries,
## retirements, player stories), &"prospect" (draft class) or &"upcoming" (matches ahead).
func _feed_items() -> Array:
	var team := season.user_team()
	var out: Array = []
	var add := func(cat: StringName, tag: String, body: String, accent: Color, cb: Callable):
		out.append({"cat": cat, "tag": tag, "body": body, "accent": accent, "cb": cb})
	# Upcoming: your next matches, then the rest of this week's slate.
	if season.phase != Season.PHASE_OFFSEASON:
		var mine: Array = []
		for w in range(season.week, season.total_weeks() + 1):
			for m: ScheduledMatch in season.matches_for_week(w):
				if not m.is_played() and (m.home == team or m.away == team) and mine.size() < 3:
					mine.append(m)
		for m: ScheduledMatch in mine:
			var opp := m.opponent_of(team)
			var mm := m
			add.call(&"upcoming", "YOUR MATCH  ·  " + season.week_label(m.week).to_upper(), "%s %s[color=white]%s[/color] (%s)" % [
				"vs" if m.home == team else "@", UiKit.logo_bb(opp, 26), UiKit.esc(opp.name), season.record_text(opp)], UiKit.ACCENT,
				func(): open("Match Preview", func(): return pages.preview(mm)))
		for m: ScheduledMatch in season.matches_for_week(season.week):
			if m.is_played() or m.home == team or m.away == team:
				continue
			var mm := m
			add.call(&"upcoming", season.week_label(m.week).to_upper(), "%s[color=white]%s[/color] (%s)  @  %s[color=white]%s[/color] (%s)" % [
				UiKit.logo_bb(m.away, 26), UiKit.esc(m.away.name), season.record_text(m.away), UiKit.logo_bb(m.home, 26), UiKit.esc(m.home.name),
				season.record_text(m.home)], m.home.color, func(): open("Match Preview", func(): return pages.preview(mm)))
	# Around the league.
	var week := _last_week_with_results()
	var potw := SeasonReview.player_of_week(season, week)
	if not potw.is_empty():
		var ps: Soldier = potw["soldier"]
		var pl: Dictionary = potw["line"]
		add.call(&"league", "PLAYER OF THE WEEK", UiKit.logo_bb(potw["team"], 26) + "[color=white]%s[/color] (%s)  ·  %s   %d K  %d A  %d SV  %d dmg" % [
			UiKit.esc(ps.tag()), potw["team"].abbrev, season.week_label(week), pl["kills"], pl["assists"], pl.get("saves", 0), pl["damage"]],
			UiKit.ACCENT, func(): pages.open_player(ps))
	if season.review != null and not season.review.awards.is_empty():
		var a: Dictionary = season.review.awards[0]
		add.call(&"league", "%d MVP" % season.review.year, UiKit.logo_bb(a["team"], 26) + "[color=white]%s[/color] (%s)" % [
			UiKit.esc(a["soldier"].display_name()), a["team"].abbrev], UiKit.ACCENT, func(): open("Season Awards", pages.awards))
	for m: ScheduledMatch in season.matches_for_week(week):
		if not m.is_played():
			continue
		var win := m.winner()
		var mvp := pages._soldier(m.result.mvp_id)
		var line: Dictionary = m.result.box.get(m.result.mvp_id, {})
		var body := "%s[color=white]%s %d - %d %s[/color] %s   [font_size=13]%s[/font_size]" % [UiKit.logo_bb(win, 26), UiKit.esc(win.name), m.games_for(win),
			m.games_for(m.loser()), UiKit.esc(m.loser().name), UiKit.logo_bb(m.loser(), 26), pages._games_brief(m.result)]
		if mvp != null and not line.is_empty():
			body += "\nMVP [color=#f59e0b]%s[/color]  %d K  %d SV" % [UiKit.esc(mvp.tag()), line["kills"], line.get("saves", 0)]
		var mm := m
		add.call(&"league", "FINAL  ·  " + season.week_label(m.week).to_upper(), body, win.color, func(): open("Match Recap", func(): return pages.recap(mm)))
	for n in season.news.latest(12):
		var accent := Color("#14b8a6")
		var wire_logo := ""
		for ab in n.get("teams", []):
			var nt := season.league.team_by_abbrev(ab)
			if nt != null:
				accent = nt.color
				wire_logo = UiKit.logo_bb(nt, 26)
				break
		add.call(&"league", "LEAGUE WIRE  ·  %s" % String(n.get("when", "")).to_upper(), wire_logo + "[color=white]%s[/color]\n[font_size=13]%s[/font_size]" % [
			UiKit.esc(String(n["headline"])), UiKit.esc(String(n["body"]))], accent, func(): open("League News", pages.news))
	for e in season.trades.last_trades:
		add.call(&"league", "TRADE", "%s[color=white]%s[/color] <-> %s[color=white]%s[/color]\n[font_size=13]%s for %s[/font_size]" % [UiKit.logo_bb(e["a"], 26), e["a"].abbrev,
			UiKit.logo_bb(e["b"], 26), e["b"].abbrev, UiKit.esc(pages._join_or_nothing(e["a_gave"])), UiKit.esc(pages._join_or_nothing(e["b_gave"]))],
			Color("#f97316"), func(): open("Trade Log", pages.trade_log))
	var hist: Array = season.fa.history
	for i in range(hist.size() - 1, maxi(-1, hist.size() - 9), -1):
		var e: Dictionary = hist[i]
		var so: Soldier = e["soldier"]
		add.call(&"league", "SIGNING", UiKit.logo_bb(e["team"], 26) + "[color=white]%s[/color] (%d OVR) to %s  ·  %s x %d yr" % [UiKit.esc(so.display_name()), so.best_ovr(),
			UiKit.esc(e["team"].name), Contracts.money(e["salary"]), e["years"]], Color("#14b8a6"), func(): pages.open_player(so))
	for inj in season.last_injuries:
		var so: Soldier = inj["soldier"]
		add.call(&"league", "INJURY", UiKit.logo_bb(inj["team"], 26) + "[color=white]%s[/color] (%s)  ·  %s, out %d wk%s" % [UiKit.esc(so.tag()), inj["team"].abbrev,
			inj["name"], inj["weeks"], "" if inj["weeks"] == 1 else "s"], UiKit.BAD, func(): pages.open_player(so))
	for h in pages._relations_news():
		add.call(&"league", "PLAYER STORY", h, Color("#a855f7"), func(): open("League News", pages.news))
	for r in season.retirements_in(season.year).slice(0, 6):
		var so: Soldier = r["soldier"]
		add.call(&"league", "RETIREMENT", (UiKit.logo_bb(r["team"], 26) if r["team"] != null else "") + "[color=white]%s[/color] retires at %d  ·  %s" % [
			UiKit.esc(so.display_name()), r["age"], UiKit.esc(r["team"].name) if r["team"] != null else "free agent"], Color("#94a3b8"), open_retirements)
	# Prospects.
	if draft_done() and season.draft.is_complete():
		var top: Prospect = season.draft.picks()[0]
		add.call(&"prospect", "%d DRAFT" % season.draft.year, "[color=white]%s[/color] went #1 to %s  ·  see the full recap" % [
			UiKit.esc(top.soldier.full_name()), UiKit.esc(top.drafted_by.name)], UiKit.INFO, open_draft_recap)
	var stories: Array = season.draft.news.slice(maxi(0, season.draft.news.size() - 12))
	stories.reverse()
	for n in stories:
		var pr: Prospect = n["prospect"]
		var kind: StringName = n["kind"]
		var col: Color = UiKit.GOOD if kind == &"rising" else (UiKit.BAD if kind == &"falling" else Color("#06b6d4"))
		var head := "STOCK UP" if kind == &"rising" else ("STOCK DOWN" if kind == &"falling" else "PROSPECT WATCH")
		add.call(&"prospect", "%s  ·  %s" % [head, season.week_label(n["week"]).to_upper()], "[color=white]%s[/color]  [color=#8b97ab]%s, proj. %s[/color]\n[font_size=13]%s[/font_size]" % [
			UiKit.esc(pr.soldier.full_name()), Scheme.ROLE_NAMES[pr.listed_role], Draft.projection_text(pr.projected_rank), UiKit.esc(n["text"])], col,
			func(): open(pr.soldier.full_name(), func(): return pages.prospect(pr)))
	return out


const FEED_FILTERS := [[&"all", "All"], [&"league", "Around the League"], [&"prospect", "Prospect News"], [&"upcoming", "Upcoming Matches"]]
const FEED_SIZE := Vector2(1204, 440)
var feed_filter: StringName = &"all"
var feed_pane := 0  # 0 news, 1 playoff picture
var _feed_box: VBoxContainer


## The playoff picture pane unlocks once the trade deadline passes.
func _playoff_pane_open() -> bool:
	return season.phase == Season.PHASE_PLAYOFFS or (season.phase == Season.PHASE_REGULAR and season.week > Trades.DEADLINE_WEEK)


## Bottom of Home: the filterable news box; after the deadline, arrows flip to the playoff picture.
func _home_feed() -> Control:
	_feed_box = VBoxContainer.new()
	_feed_box.name = "HomeFeed"
	_feed_box.add_theme_constant_override("separation", 8)
	_fill_feed()
	return _feed_box


func _fill_feed() -> void:
	for c in _feed_box.get_children():
		_feed_box.remove_child(c)
		c.queue_free()
	var pane := feed_pane if _playoff_pane_open() else 0
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.custom_minimum_size.x = FEED_SIZE.x
	var title := UiKit.label("PLAYOFF PICTURE" if pane == 1 else "NEWS", 15, UiKit.MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _playoff_pane_open():
		var prev := UiKit.button("  <  ", func(): _flip_feed(), 15)
		prev.name = "FeedPrev"
		head.add_child(prev)
		head.add_child(title)
		var nxt := UiKit.button("  >  ", func(): _flip_feed(), 15)
		nxt.name = "FeedNext"
		head.add_child(nxt)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(spacer)
		title.size_flags_horizontal = Control.SIZE_FILL
	else:
		head.add_child(title)
	if pane == 0:
		for f in FEED_FILTERS:
			var key: StringName = f[0]
			var b := UiKit.button(f[1], func(): _set_feed_filter(key), 14)
			b.toggle_mode = true
			b.button_pressed = feed_filter == key
			b.name = "Feed_" + String(key)
			head.add_child(b)
	else:
		head.add_child(UiKit.button("Full Bracket", func(): open("Playoff Picture", pages.playoffs), 14))
	_feed_box.add_child(head)
	var frame := PanelContainer.new()
	var sb := UiKit.flat(UiKit.PANEL, 12, 1, UiKit.LINE)
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size = FEED_SIZE
	_feed_box.add_child(frame)
	if pane == 1:
		var c := CenterContainer.new()
		c.add_child(pages.bracket_view(true))
		frame.add_child(c)
		return
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = FEED_SIZE - Vector2(28, 20)
	frame.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var n := 0
	for it in _feed_items():
		if feed_filter == &"all" or it["cat"] == feed_filter:
			list.add_child(_feed_row(it))
			n += 1
	if n == 0:
		list.add_child(UiKit.label("Nothing here yet.", 16, UiKit.MUTED))


func _set_feed_filter(key: StringName) -> void:
	feed_filter = key
	_fill_feed()


func _flip_feed() -> void:
	feed_pane = 1 - feed_pane
	_fill_feed()


func _feed_row(it: Dictionary) -> Button:
	var b := Button.new()
	UiKit.style_button(b, UiKit.PANEL_HI, it["accent"], 8)
	b.custom_minimum_size = Vector2(0, 62)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	b.pressed.connect(it["cb"])
	var strip := ColorRect.new()
	strip.color = it["accent"]
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	strip.offset_right = 5
	b.add_child(strip)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.offset_right = -14
	h.offset_top = 8
	h.offset_bottom = -6
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var tag := UiKit.label(it["tag"], 13, UiKit.MUTED)
	tag.custom_minimum_size.x = 210
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(tag)
	var body := UiKit.rich(it["body"], 15)
	body.add_theme_color_override("default_color", UiKit.MUTED)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(body)
	return b


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
			UiKit.tile("Lineup", "Pick a scheme and set your %s starters:\n%s." % [team.scheme.display_name, team.scheme.shape_text()], TILE, Color("#f97316"), func(): open("Lineup", pages.lineup)),
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
			UiKit.tile("Standings", _mini_standings(), TALL, Color("#a855f7"), open_standings),
			UiKit.tile("Schedule", "Full league schedule by week.", TILE, Color("#6366f1"),
				func(): open("Scores & Schedule", func(): return pages.scores(clampi(season.week, 1, season.total_weeks())))),
			UiKit.tile("Scores", "Results from around the league.", TILE, UiKit.INFO,
				func(): open("Scores & Schedule", func(): return pages.scores(_last_week_with_results()))),
			UiKit.tile("Playoff Picture", _playoff_blurb(), TALL, Color("#f43f5e"), func(): open("Playoff Picture", pages.playoffs)),
		]],
		["STATS", [
			UiKit.tile("League Leaders", _leader_blurb(), TALL, Color("#eab308"), func(): open("League Leaders", pages.leaders)),
			UiKit.tile("League Stats", "Every soldier's season stats, sortable by any column.", TILE, Color("#0ea5e9"), func(): open("League Stats", pages.league_stats)),
			UiKit.tile("Team Stats", "Every team's season totals: K/D, damage, accuracy, hill time.", TILE, Color("#10b981"), func(): open("League Team Stats", pages.league_team_stats)),
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


func _trade_tiles() -> Array:
	var tr := season.trades
	var open := tr.window_open(season)
	var team := season.user_team()
	var on_block := team.roster.filter(func(x: Soldier): return tr.block.has(x.id)).size()
	return [
		UiKit.tile("Trade Center", "Build deals with any team (up to %d assets a side).
Window: [color=%s]%s[/color]" % [Trades.MAX_ASSETS,
			"#22c55e" if open else "#ef4444", tr.window_text(season)], TILE, Color("#f97316"), func(): pages.open_trade()),
		UiKit.tile("Trade Offers", ("[color=#f59e0b]%d offer%s[/color] waiting." % [tr.offers.size(), "" if tr.offers.size() == 1 else "s"]) if not tr.offers.is_empty()
			else "No offers right now.", TILE, Color("#f97316"), func(): open("Trade Offers", pages.trade_offers)),
		UiKit.tile("Trade Block", "%d of your players on the block.
AI teams send offers for them." % on_block, TILE, Color("#f97316"), func(): open("Trade Block", pages.trade_block)),
		UiKit.tile("Trade Log", "%d trades so far." % tr.history.size(), TILE, Color("#f97316"), func(): open("Trade Log", pages.trade_log)),
	]


func _personnel_sections() -> Array:
	var soon := func(title: String, sub: String, color: Color, bullets: Array) -> Button:
		return UiKit.tile(title, sub, TILE, color, func(): coming_soon(title, bullets), "SOON")
	var team := season.user_team()
	var n_exp := Contracts.expiring(team).size()
	return [
		["TRADES", _trade_tiles()],
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
		return "%d rounds after the Final. Worst finish picks first every round." % Draft.ROUNDS
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
			UiKit.tile("Save Franchise", "%d save slots. The autosave updates every week." % SaveSystem.SLOTS, TILE, Color("#22c55e"),
				func(): open("Save Franchise", func(): return pages.save_load(true))),
			UiKit.tile("Load Franchise", "Load a saved franchise or the autosave.", TILE, UiKit.INFO,
				func(): open("Load Franchise", func(): return pages.save_load(false))),
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
				next_step = "Free agency is over. Week 1 needs exactly %d players (you have %d). Start the season when ready." % [Team.ROSTER_SIZE, team.roster.size()]
				target = open_contracts
		var body := "[font_size=30][color=white]%s[/color][/font_size]\n%d champions.\n\n%s" % [
			UiKit.esc(champ.name if champ else "-"), season.year, next_step]
		return UiKit.tile("Season Complete", body, HERO, UiKit.ACCENT, target)
	if season.preseason_camp:
		var first := season.next_match_for(team)
		var opener := ""
		if first != null:
			opener = "\n\nWeek 1: %s %s" % ["vs" if first.home == team else "@", UiKit.esc(first.opponent_of(team).name)]
		return UiKit.tile("Preseason", "[font_size=30][color=white]TRAINING CAMP[/color][/font_size]\nThe %d season starts after camp.\n\nSend one player to each drill ([color=#38bdf8]%d left[/color]), then start the season.%s" % [
			season.year, season.camp.drills_left(team), opener], HERO, UiKit.ACCENT, open_camp)
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
	var tile := UiKit.tile("Next Match", "", HERO, opp.color, func(): open("Match Preview", func(): return pages.preview(m)))
	var box: VBoxContainer = tile.get_child(1)
	box.get_child(1).queue_free()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_matchup_side(team))
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := UiKit.label("VS" if m.home == team else "@", 34, Color.WHITE)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(vs)
	var wk := UiKit.label("%s\n%s" % [season.week_label(m.week), "Home" if m.home == team else "Away"], 14, UiKit.MUTED)
	wk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(wk)
	row.add_child(mid)
	row.add_child(_matchup_side(opp))
	box.add_child(row)
	return tile


## One side of the next-match tile: logo, full name (wraps rather than clipping) and OVR / record.
func _matchup_side(t: Team) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 210
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo := UiKit.team_logo(t, 96)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(logo)
	var nm := UiKit.label(t.name, 17, Color.WHITE)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size.x = 210
	v.add_child(nm)
	var o := t.team_ovr()
	var info := UiKit.rich("[center][color=%s]%d OVR[/color]  [color=#8b97ab]%s[/color][/center]" % [UiKit.hex(UiKit.ovr_color(o)), o, season.record_text(t)], 14)
	v.add_child(info)
	return v


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
		if season.camp_open() and season.camp.drills_left(season.user_team()) > 0:
			return "Close camp ([color=#f59e0b]%d drills unused[/color]) and start the %d season." % [season.camp.drills_left(season.user_team()), season.year + 1]
		var n := season.user_team().roster.size()
		var note := "" if n == Team.ROSTER_SIZE else "  [color=#f59e0b]You have %d: get to %d before Week 1.[/color]" % [n, Team.ROSTER_SIZE]
		return "Roll over to the %d season. Week 1 needs exactly %d players.%s" % [season.year + 1, Team.ROSTER_SIZE, note]
	if season.preseason_camp:
		if season.camp.drills_left(season.user_team()) > 0:
			return "Close camp ([color=#f59e0b]%d drills unused[/color]) and go to Week 1." % season.camp.drills_left(season.user_team())
		return "Close camp and go to Week 1."
	var err := season.user_roster_error()
	if err != "":
		return "[color=#ef4444]%s[/color]" % err
	return "Train, play every match this week and award XP.\n\n[color=white]Space / Y[/color]"


## The user's division (or the whole league when there are no divisions).
func _mini_standings() -> String:
	var lines: Array[String] = []
	var rows: Array = season.standings()
	if season.has_divisions():
		var div := season.division_of(season.user_team())
		lines.append("[color=#8b97ab]%s DIVISION[/color]" % div.to_upper())
		rows = season.division_standings(div)
	for i in rows.size():
		var row: StandingRow = rows[i]
		var c := "white" if row.team.user_controlled else "#8b97ab"
		lines.append("[color=%s]%d. %s%s  %d-%d[/color]" % [c, i + 1, UiKit.logo_bb(row.team, 18), row.team.abbrev, row.wins, row.losses])
	return "[font_size=15]%s[/font_size]" % "\n".join(lines)


func _headline() -> String:
	var news := pages.headlines(1)
	if news.is_empty():
		var wire: Array = season.news.latest(1)
		if not wire.is_empty():
			return String(wire[0]["headline"])
	return news[0] if not news.is_empty() else "Preseason: %d teams chase the %s title." % [season.league.teams.size(), Season.DIVISION_NAME]


func _leader_blurb() -> String:
	var top := pages.season_totals()
	if top.is_empty():
		return "Kills, assists and damage leaders."
	# Rate stats need a real sample: at least half the games of the busiest player.
	var most := 0
	for t in top:
		most = maxi(most, int(t["matches"]))
	var qualified := top.filter(func(t): return int(t["matches"]) * 2 >= most)
	var cats: Array = [
		["K", top, func(t): return float(t["kills"]), func(t): return str(t["kills"])],
		["A", top, func(t): return float(t["assists"]), func(t): return str(t["assists"])],
		["CAP", top, func(t): return float(t["caps"]), func(t): return str(t["caps"])],
		["K/D", qualified, func(t): return float(t["kills"]) / maxi(1, int(t["deaths"])), func(t): return "%.2f" % (float(t["kills"]) / maxi(1, int(t["deaths"])))],
		["HIT%", qualified, func(t): return float(t["hits"]) / maxi(1, int(t["shots"])), func(t): return "%d%%" % roundi(100.0 * t["hits"] / maxi(1, int(t["shots"])))],
	]
	var lines: Array[String] = []
	for c in cats:
		var pool: Array = c[1]
		if pool.is_empty():
			continue
		var f: Callable = c[2]
		var best: Dictionary = pool[0]
		for t in pool:
			if f.call(t) > f.call(best):
				best = t
		var so: Soldier = best["soldier"]
		lines.append("[color=#8b97ab]%s[/color]  [color=white]%s[/color] %s  [color=#eab308]%s[/color]" % [
			c[0], UiKit.esc(so.callsign), best["team"].abbrev, c[3].call(best)])
	return "[font_size=15]%s[/font_size]" % "\n".join(lines)


func _awards_blurb() -> String:
	if season.review != null and not season.review.awards.is_empty():
		var mvp: Dictionary = season.review.awards[0]
		return "%d MVP:\n[color=white]%s[/color] (%s)" % [season.review.year, UiKit.esc(mvp["soldier"].full_name()), mvp["team"].abbrev]
	return "MVP race, position awards, potential changes and aging."


func _playoff_blurb() -> String:
	if season.phase == Season.PHASE_REGULAR:
		var field := season.playoff_field()
		var last: Team = field[-1]
		var user := season.user_team()
		var mine := field.find(user)
		return "%d teams make the playoffs.\nYou: %s\nLast seed in: %s (%s)" % [season.playoff_teams,
			("[color=#22c55e]seed %d[/color]" % (mine + 1)) if mine >= 0 else "[color=#ef4444]outside[/color]", last.abbrev, season.record_text(last)]
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

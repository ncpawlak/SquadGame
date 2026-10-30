extends Control
## Madden/CFB-style franchise hub: team header with Advance button, bumper-switched tabs
## (Home / Team / League / Personnel / Settings) of scrollable tile rows, and a page stack for
## detail screens (Esc / B goes back).

const TABS := ["Home", "Team", "League", "Personnel", "Settings"]
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
var _tab_wrap: PanelContainer
## Team-tinted gradient + logo watermark behind everything (rebuilt by _apply_team_theme).
var _bg: Control
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
	_bg = Control.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	var root := VBoxContainer.new()
	_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_header = PanelContainer.new()
	_header.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	root.add_child(_header)

	_tab_wrap = PanelContainer.new()
	root.add_child(_tab_wrap)
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 8)
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_wrap.add_child(_tab_bar)

	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		_content.add_theme_constant_override("margin_" + side, 40)
	_content.add_theme_constant_override("margin_top", 18)
	_content.add_theme_constant_override("margin_bottom", 8)
	root.add_child(_content)

	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", UiKit.flat(Color(0, 0, 0, 0.45), 0))
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
	_apply_team_theme()
	_build_header()
	_build_tabs()
	_show_current()


## Re-theme to the user's team: accent colours, app theme and the backdrop (team-tinted gradient
## with a faint logo watermark).
func _apply_team_theme() -> void:
	var team := season.user_team()
	UiKit.set_team(team)
	if app:
		app.theme = UiKit.theme()
	for c in _bg.get_children():
		c.queue_free()
	var g := UiKit.gradient_rect(UiKit.TEAM_DARK.darkened(0.6), UiKit.BG)
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.add_child(g)
	var tex := UiKit.logo_tex(team.abbrev)
	if tex != null:
		var wm := TextureRect.new()
		wm.texture = tex
		wm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		wm.modulate = Color(1, 1, 1, 0.04)
		wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wm.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		wm.offset_left = -780
		wm.offset_top = -780
		wm.offset_right = 80
		wm.offset_bottom = 80
		_bg.add_child(wm)


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
	# Personnel screens also live inline on the Personnel tab: refresh the pane in place.
	if page_stack.is_empty() and tab_index == 3 and is_instance_valid(_pers_box) and _personnel_view_for(title) >= 0:
		personnel_view = _personnel_view_for(title)
		_fill_personnel_box(true)
		return
	var focus_index := -1
	var scroll_pos := 0
	if _scroll and is_instance_valid(_scroll):
		scroll_pos = _scroll.scroll_vertical
		focus_index = app.focusables(_content).find(get_viewport().gui_get_focus_owner())
	if not page_stack.is_empty():
		page_stack.pop_back()
	page_stack.append({"title": title, "build": build, "no_back": no_back})
	_show_current(focus_index, scroll_pos, false)


## Refresh a page after an action. Roster and Lineup also live inline on the Team tab: there only
## the team pane rebuilds (keeping its scroll and focus); as a pushed page it is replaced.
func page_refresh(title: String, build: Callable) -> void:
	if page_stack.is_empty() and tab_index == 1 and is_instance_valid(_team_box):
		_fill_team_box(true)
	else:
		replace(title, build)


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


## Offseason steps: re-sign window -> free agency days -> draft -> roster review -> training camp -> next season.
func _advance_offseason() -> void:
	match season.offseason_stage:
		Season.OFF_RESIGN:
			season.advance_offseason()
			_rebuild_and_open("Free Agents", pages.free_agents)
			app.toast("Re-signing window closed. Free agency is open: %d soldiers available. Offers are answered each FA day." % season.league.free_agents.size())
		Season.OFF_FREE_AGENCY:
			var label := "FA Day %d" % season.fa_day
			var signed: Array = season.advance_offseason()
			_rebuild_and_open("%s Results" % label, func(): return pages.signings(label, signed))
			if season.offseason_stage == Season.OFF_DRAFT:
				app.toast("Free agency is over. The %d draft is on: open the Draft Room." % season.draft.year)
		Season.OFF_DRAFT:
			if not season.draft.is_complete():
				_rebuild_and_open("Draft Room", pages.draft_room)
				app.toast("Make your picks (or sim the rest of the draft) first.")
				return
			season.advance_offseason()
			_rebuild_and_open("Contracts & Payroll", pages.contracts)
			app.toast("Roster review: undrafted prospects joined free agency. Set your roster and get under the cap before camp.")
		Season.OFF_REVIEW:
			var err := season.user_cap_error()
			if err != "":
				_rebuild_and_open("Contracts & Payroll", pages.contracts)
				app.toast(err)
				return
			var signed: Array = season.advance_offseason()
			_camp_skip_warned = false
			_rebuild_and_open("Roster Review Results", func(): return pages.signings("Roster Review", signed))
			if season.camp_open():
				app.toast("Training camp is open: send a player to each drill.")
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


## `animate`: fade the new view in and slide it up (off for in-place refreshes).
func _show_current(focus_index := -1, scroll_pos := 0, animate := true) -> void:
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
	if animate:
		_slide_in(view)
	_settle_focus(view, focus_index, scroll_pos)


var _slide_tw: Tween


func _slide_in(view: Control) -> void:
	if not is_inside_tree():
		return
	if _slide_tw and _slide_tw.is_valid():
		_slide_tw.kill()
	view.modulate.a = 0.0
	_content.add_theme_constant_override("margin_top", 44)
	_slide_tw = create_tween().set_parallel()
	_slide_tw.tween_property(view, "modulate:a", 1.0, 0.22)
	_slide_tw.tween_method(func(x: float): _content.add_theme_constant_override("margin_top", roundi(x)), 44.0, 18.0, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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
	if app.mouse_mode:
		pass
	elif focus_index >= 0 and not list.is_empty():
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
	head.add_theme_constant_override("separation", 20)
	v.add_child(head)
	if not page_stack[-1].get("no_back", false):
		var back := UiKit.button("< Back", go_back, 17)
		UiKit.style_skewed(back)
		back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		back.custom_minimum_size.y = 42
		back.set_meta(&"skip_autofocus", true)
		head.add_child(back)
	var crumbs := "%s  /  " % TABS[tab_index].to_upper()
	for i in page_stack.size() - 1:
		crumbs += "%s  /  " % page_stack[i]["title"]
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(UiKit.label(crumbs.to_upper(), 13, UiKit.MUTED))
	tv.add_child(UiKit.display(title.to_upper(), 40, Color.WHITE, true))
	var line := Panel.new()
	var lsb := UiKit.flat(UiKit.ACCENT, 1)
	lsb.skew = Vector2(UiKit.SKEW * 2.0, 0)
	line.add_theme_stylebox_override("panel", lsb)
	line.custom_minimum_size = Vector2(90, 4)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(line)
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

## Broadcast banner: team-colour backdrop with an accent stripe, logo, big team name and a
## score-bug chip (season + phase). Advancing lives on Home (Play / Sim To) and the Space key.
func _build_header() -> void:
	for c in _header.get_children():
		c.queue_free()
	var team := season.user_team()
	_header.add_child(UiKit.backdrop(UiKit.TEAM_DARK, Color(UiKit.PANEL, 0.7), true, UiKit.ACCENT))
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 28)
	mc.add_theme_constant_override("margin_right", 34)
	mc.add_theme_constant_override("margin_top", 10)
	mc.add_theme_constant_override("margin_bottom", 12)
	_header.add_child(mc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	mc.add_child(hb)

	hb.add_child(UiKit.logo_disc(team, 86))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(info)
	info.add_child(UiKit.display(team.name.to_upper(), 44, Color.WHITE, true))
	var rank := _rank_of(team)
	var where := "%s in %s" % [UiKit.ordinal(rank), Season.DIVISION_NAME]
	if season.has_divisions():
		var div := season.division_of(team)
		var drank := 0
		var drows: Array = season.division_standings(div)
		for i in drows.size():
			if (drows[i] as StandingRow).team == team:
				drank = i + 1
		where = "%s in the %s   ·   %s in the league" % [UiKit.ordinal(drank), div, UiKit.ordinal(rank)]
	info.add_child(UiKit.label("%s   ·   %s   ·   Team OVR %d" % [
		season.record_text(team), where, team.team_ovr()], 16, Color(1, 1, 1, 0.72)))
	hb.add_child(_score_bug())


## "2026 | WEEK 3 of 12" chip, slanted like a TV score bug.
func _score_bug() -> Control:
	var bug := HBoxContainer.new()
	bug.add_theme_constant_override("separation", 0)
	bug.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mk := func(bg: Color, border: Color, text: String, size: int, color: Color) -> PanelContainer:
		var p := PanelContainer.new()
		var sb := UiKit.flat(bg, 2, 1, border)
		sb.skew = Vector2(UiKit.SKEW, 0)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		p.add_theme_stylebox_override("panel", sb)
		p.add_child(UiKit.display(text, size, color))
		return p
	bug.add_child(mk.call(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.12), "%d" % season.year, 24, Color(1, 1, 1, 0.8)))
	var a := UiKit.ACCENT
	bug.add_child(mk.call(Color.from_hsv(a.h, clampf(a.s, 0.0, 0.9), 0.45), a, _phase_text(), 24, Color.WHITE))
	return bug


func _build_tabs() -> void:
	for c in _tab_bar.get_children():
		c.queue_free()
	var tsb := UiKit.flat(Color(0, 0, 0, 0.4), 0)
	tsb.border_width_bottom = 2
	tsb.border_color = Color(UiKit.ACCENT, 0.55)
	tsb.content_margin_top = 8
	tsb.content_margin_bottom = 8
	_tab_wrap.add_theme_stylebox_override("panel", tsb)
	_tab_bar.add_child(UiKit.label("Q / LB", 13, UiKit.MUTED))
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i].to_upper()
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(170, 42)
		if i == tab_index:
			UiKit.style_primary(b)
		else:
			UiKit.style_skewed(b, Color(UiKit.PANEL, 0.75))
			b.add_theme_color_override("font_color", UiKit.MUTED)
		b.focus_mode = Control.FOCUS_NONE
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
				Season.OFF_FREE_AGENCY:
					return "OFFSEASON - FREE AGENCY"
				Season.OFF_DRAFT:
					return "OFFSEASON - DRAFT"
				Season.OFF_REVIEW:
					return "OFFSEASON - ROSTER REVIEW"
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
				return "FREE AGENCY  >>"
			Season.OFF_FREE_AGENCY:
				return "FA DAY %d of %d  >>" % [season.fa_day, Season.FA_DAYS]
			Season.OFF_DRAFT:
				return "%d DRAFT  >>" % season.year if not season.draft.is_complete() else "ROSTER REVIEW  >>"
			Season.OFF_REVIEW:
				return "TRAINING CAMP  >>"
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
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)
	if i == 0:
		v.add_child(_home_top())
		var gap0 := Control.new()
		gap0.custom_minimum_size.y = 8
		v.add_child(gap0)
		v.add_child(_home_feed())
	elif i == 1:
		v.add_child(_team_top())
		v.add_child(_team_cards())
		v.add_child(_soon_strip())
	elif i == 2:
		v.add_child(_league_top())
		v.add_child(_league_cards())
		v.add_child(_league_strip())
	elif i == 3:
		v.add_child(_personnel_top())
		v.add_child(_personnel_cards())
		v.add_child(_personnel_strip())
	elif i == 4:
		_settings_view(v)
	var sections: Array = [_home_sections, _team_sections, _league_sections, _personnel_sections, _settings_sections][i].call()
	var n := 0
	for sec in sections:
		v.add_child(UiKit.heading(sec[0], 22))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 14)
		flow.add_theme_constant_override("v_separation", 14)
		for t in sec[1]:
			flow.add_child(t)
			UiKit.fade_in(t, minf(0.5, 0.03 * n), 0.25)
			n += 1
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


## A to-do tile in the team trim colour. Done: greyed out with a check. Urgent: orange with a "!" in the corner.
func _todo(title: String, body: String, _accent: Color, cb: Callable, done := false, urgent := false) -> Button:
	var t := UiKit.tile(("\u2713  " if done else "") + title, body, SMALL, UiKit.MUTED.darkened(0.3) if done else (Color("#f97316") if urgent else UiKit.TRIM), cb)
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
		if season.offseason_stage == Season.OFF_RESIGN:
			if season.review != null and not season.review.awards.is_empty():
				var mvp: Dictionary = season.review.awards[0]
				out.append(_todo("Season Awards", "%d MVP: [color=white]%s[/color] (%s)" % [season.review.year, UiKit.esc(mvp["soldier"].short_name()), mvp["team"].abbrev],
					Color("#f59e0b"), func(): open("Awards & Development", pages.awards)))
			var rets := season.retirements_in(season.year)
			out.append(_todo("Retirements", ("[color=white]%d[/color] soldier%s hung it up this year." % [rets.size(), "" if rets.size() == 1 else "s"]) if not rets.is_empty() else "Nobody retired this year.",
				Color("#94a3b8"), open_retirements))
			var hof := _todo("Hall of Fame", "Coming soon: this year's inductees.", UiKit.MUTED,
				func(): coming_soon("Hall of Fame", ["This year's inductees", "Career numbers and honours", "The full Hall by class"]))
			hof.modulate = Color(1, 1, 1, 0.6)
			hof.set_meta("todo_done", true)
			out.append(hof)
		if season.offseason_stage == Season.OFF_DRAFT:
			var d := season.draft
			out.append(_todo("Draft Room", "Every pick is in." if d.is_complete() else "[color=#38bdf8]Your picks:[/color] %d left" % d.picks_left_for(team),
				UiKit.INFO, open_draft_room, d.is_complete()))
		if season.offseason_stage == Season.OFF_REVIEW:
			var space := Contracts.cap_space(team, season.cap_year())
			if space < 0:
				out.append(_todo("Over the Cap", "[color=#ef4444]%s over[/color] the cap.\nRelease or trade players before training camp." % Contracts.money(-space),
					UiKit.BAD, open_contracts, false, true))
			else:
				out.append(_todo("Roster Review", "%d / %d players  -  cap space %s\nMake your cuts and moves before camp." % [team.roster.size(), Team.ROSTER_SIZE, Contracts.money(space)],
					Color("#f97316"), open_contracts))
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
	var news_tile := _news_todo()
	if news_tile != null:
		out.append(news_tile)
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


## Top of Home: this week's to-dos stacked on the left; on the right the week card (header strip
## with week arrows and the Preview / Sim To / Play actions over the matchup, result or status).
func _home_top() -> Control:
	var team := season.user_team()
	var anchor := "%d|%d|%s|%s|%s" % [season.year, season.week, season.phase, season.offseason_stage, season.preseason_camp]
	if anchor != _home_anchor:
		_home_anchor = anchor
		home_week = 0
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	var left := VBoxContainer.new()
	left.name = "TodoColumn"
	left.add_theme_constant_override("separation", 10)
	left.add_child(UiKit.heading("This Week", 22))
	var i := 0
	for t in _todo_tiles(team):
		left.add_child(t)
		UiKit.fade_in(t, 0.05 * i, 0.25)
		i += 1
	top.add_child(left)
	var card := _week_card(team)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(card)
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


## The shown week's match (the user's), or null for byes, TBD playoff rounds and off-weeks.
func _shown_match(team: Team) -> ScheduledMatch:
	if home_week == 0:
		if season.phase == Season.PHASE_OFFSEASON or season.preseason_camp:
			return null
		var nm := season.next_match_for(team)
		return nm if nm != null and nm.week == season.week else null
	for x in season.matches_for_week(home_week):
		if x.involves(team):
			return x
	return null


## Home's main card: a two-tone team-colour backdrop (your colours left, the opponent's right),
## the header strip, then the matchup, the final or a status panel.
func _week_card(team: Team) -> Control:
	var m := _shown_match(team)
	var opp: Team = m.opponent_of(team) if m != null else null
	var card := PanelContainer.new()
	card.name = "WeekCard"
	var sb := UiKit.flat(UiKit.PANEL, 2, 1, Color(1, 1, 1, 0.1))
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 0)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(900, 450)
	card.clip_contents = true
	var bd: UiKit.Backdrop
	if opp != null:
		bd = UiKit.backdrop(UiKit.banner_of(team), UiKit.banner_of(opp), true, UiKit.ACCENT)
		bd.two_tone = true
		bd.mid = UiKit.PANEL.darkened(0.3)
	else:
		bd = UiKit.backdrop(UiKit.TEAM_DARK, UiKit.PANEL.darkened(0.3), true, UiKit.ACCENT)
	card.add_child(bd)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	card.add_child(v)
	v.add_child(_card_header(m, team))
	var body: Control
	if m != null and m.is_played():
		body = _result_body(m, team)
	elif m != null:
		body = _match_body(m, team)
	else:
		body = _status_body(team)
	var mc := MarginContainer.new()
	mc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mc.add_theme_constant_override("margin_left", 30)
	mc.add_theme_constant_override("margin_right", 30)
	mc.add_theme_constant_override("margin_top", 18)
	mc.add_theme_constant_override("margin_bottom", 20)
	mc.add_child(body)
	v.add_child(mc)
	UiKit.fade_in(mc, 0.08, 0.3)
	return card


## "< WEEK 3 of 12 >" (plus "Back to this week" while browsing), then the card's actions:
## Match Preview / Box Score, Sim To and the Play button.
func _card_header(m: ScheduledMatch, team: Team) -> Control:
	var strip := PanelContainer.new()
	var sb := UiKit.flat(Color(0, 0, 0, 0.5), 0)
	sb.border_width_bottom = 2
	sb.border_color = Color(UiKit.ACCENT, 0.7)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	strip.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.name = "WeekNav"
	row.add_theme_constant_override("separation", 10)
	strip.add_child(row)
	var w := _shown_week()
	var arrow := func(text: String, dir: int, nm: String, tip: String, off: bool) -> Button:
		var b := UiKit.button(text, func(): browse_week(dir), 20)
		UiKit.style_skewed(b, Color(0, 0, 0, 0.45))
		b.name = nm
		b.tooltip_text = tip
		b.disabled = off
		b.custom_minimum_size = Vector2(56, 42)
		return b
	row.add_child(arrow.call("<", -1, "WeekPrev", "Previous week", w <= 1))
	var text := _phase_text()
	if home_week != 0:
		text = ("WEEK %d of %d" % [w, season.regular_weeks]) if w <= season.regular_weeks else "PLAYOFFS - %s" % season.week_label(w).to_upper()
	if m != null and m.is_played():
		text += "   ·   FINAL"
	var lbl := UiKit.display(text, 24, Color.WHITE if home_week == 0 else UiKit.INFO)
	lbl.custom_minimum_size.x = 290
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_vertical = Control.SIZE_FILL
	row.add_child(lbl)
	row.add_child(arrow.call(">", 1, "WeekNext", "Next week", w >= season.total_weeks()))
	if home_week != 0:
		var back := UiKit.button("Back to %s" % ("this week" if _now_week() >= 1 and _now_week() <= season.total_weeks() else "today"), func():
			home_week = 0
			select_tab(0), 15)
		UiKit.style_skewed(back, Color(0, 0, 0, 0.45))
		row.add_child(back)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	if m != null and m.is_played():
		var box := UiKit.button("Box Score", func(): open("Match Recap", func(): return pages.recap(m)), 17)
		box.name = "BoxScoreButton"
		UiKit.style_skewed(box, Color(0, 0, 0, 0.45))
		row.add_child(box)
	elif m != null:
		var pv := UiKit.button("Match Preview", func(): open("Match Preview", func(): return pages.preview(m)), 17)
		pv.name = "PreviewButton"
		UiKit.style_skewed(pv, Color(0, 0, 0, 0.45))
		row.add_child(pv)
	var st := _sim_to_button()
	if st != null:
		row.add_child(st)
	row.add_child(_play_button())
	return strip


## "SIM TO" drop-down (next phase milestones), or null when there is nowhere to sim to.
func _sim_to_button() -> Button:
	var targets := sim_to_targets()
	if targets.is_empty():
		return null
	var mb := MenuButton.new()
	mb.name = "SimToMenu"
	mb.text = "SIM TO  \u25BE"
	mb.flat = false
	mb.custom_minimum_size = Vector2(0, 42)
	mb.add_theme_font_size_override("font_size", 18)
	mb.set_meta(&"skip_autofocus", true)
	UiKit.style_skewed(mb, Color(0, 0, 0, 0.45))
	var pop := mb.get_popup()
	pop.add_theme_font_size_override("font_size", 18)
	for i in targets.size():
		pop.add_item(targets[i][1], i)
	pop.id_pressed.connect(func(id: int): sim_to(targets[id][0]))
	return mb


## The accent advance button ("PLAY WEEK 3 >>", "START 2027 SEASON >>", ...).
func _play_button() -> Button:
	var b := UiKit.primary_button(_advance_text(), advance, 20)
	b.name = "PlayButton"
	b.custom_minimum_size = Vector2(250, 42)
	b.tooltip_text = _advance_blurb().replace("[color=white]", "").replace("[color=#f59e0b]", "").replace("[color=#ef4444]", "").replace("[/color]", "")
	return b


## A played week on the card: VICTORY/DEFEAT, the big series score, game-by-game lines and the MVP.
func _result_body(m: ScheduledMatch, team: Team) -> Control:
	var opp := m.opponent_of(team)
	var won := m.winner() == team
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_team_block(team, false))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 2)
	var res := UiKit.display("VICTORY" if won else "DEFEAT", 30, UiKit.GOOD if won else UiKit.BAD, true)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(res)
	var sc := UiKit.display("%d  -  %d" % [m.games_for(team), m.games_for(opp)], 84, Color.WHITE, true)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(sc)
	for g in m.result.games:
		var gw: Team = m.result.teams[g["winner"]]
		var gl := UiKit.rich("[center][color=#c3cad6]GAME %d  %s[/color]   [color=white]%s %s %s[/color]   [color=%s]%s[/color][/center]" % [
			g["number"], MatchEngine.MODE_SHORT[g["mode"]], team.abbrev, MatchResult.game_score_text(g, m.result.teams[0] != team), opp.abbrev,
			UiKit.hex(UiKit.GOOD if gw == team else UiKit.BAD), gw.abbrev], 16)
		mid.add_child(gl)
	row.add_child(mid)
	row.add_child(_team_block(opp, true))
	v.add_child(row)
	var mvp := pages._soldier(m.result.mvp_id)
	if mvp != null:
		var mt := pages._team_of(mvp)
		v.add_child(UiKit.rich("[color=#c3cad6]MVP[/color]   [color=#f59e0b]%s[/color]%s" % [UiKit.esc(mvp.display_name()), ("  (%s)" % mt.abbrev) if mt else ""], 17))
	return v


## Rosters can run over the limit (trades, draft picks, extra signings) or short (trades,
## expiring deals). Week 1 needs exactly ROSTER_SIZE, later matches ROSTER_MIN..ROSTER_SIZE.
## Returns {} when legal, else {title, body, cb} for an urgent to-do.
func _roster_status(team: Team) -> Dictionary:
	var n := team.roster.size()
	var before_week1 := season.phase == Season.PHASE_OFFSEASON or season.preseason_camp or (season.phase == Season.PHASE_REGULAR and season.week == 1)
	var lo := Team.ROSTER_SIZE if before_week1 else Season.ROSTER_MIN
	if n <= Team.ROSTER_SIZE and n >= lo:
		return {}
	# Early offseason: the roster is still taking shape (expiring deals leave, signings and picks arrive).
	if season.phase == Season.PHASE_OFFSEASON and n < lo and season.offseason_stage in [Season.OFF_RESIGN, Season.OFF_FREE_AGENCY, Season.OFF_DRAFT]:
		return {}
	# Offseason rosters may carry up to OFFSEASON_MAX until the roster review.
	if season.phase == Season.PHASE_OFFSEASON and n > Team.ROSTER_SIZE and season.offseason_stage in [Season.OFF_RESIGN, Season.OFF_FREE_AGENCY, Season.OFF_DRAFT]:
		return {}
	var when := "Week 1" if before_week1 else "your next match"
	if n > Team.ROSTER_SIZE:
		var extra := n - Team.ROSTER_SIZE
		return {"title": "Roster Cuts", "body": "[color=white]%d / %d players.[/color] Release or trade [color=#ef4444]%d[/color] before %s." % [
			n, Team.ROSTER_SIZE, extra, when], "cb": open_contracts}
	var short := lo - n
	return {"title": "Roster Spots Open", "body": "[color=white]%d / %d players.[/color] Sign [color=#f59e0b]%d free agent%s[/color] before %s." % [
		n, Team.ROSTER_SIZE, short, "" if short == 1 else "s", when], "cb": open_free_agents}


## Rivalry names, head-to-head and intensity for the badge's tooltip.
func _rivalry_tip(a: Team, b: Team) -> String:
	var lines: Array[String] = []
	lines.append_array(season.rivalries.titles(a, b))
	lines.append(season.rivalries.record_text(a, b))
	lines.append("Intensity %d" % roundi(season.rivalries.intensity(a, b)))
	return "\n".join(lines)


## This week's (or a browsed) matchup: big team blocks, centred stat bars and impact players.
func _match_body(m: ScheduledMatch, team: Team) -> Control:
	var opp := m.opponent_of(team)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_team_block(team, false))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 7)
	var rv_flags := season.rivalries.flags(team, opp)
	if rv_flags != 0:
		# Rivalry games swap the big VS / @ for the rivalry icons, keeping a small VS / @ tag.
		var badge := RivalryBadge.new()
		badge.setup(rv_flags, UiKit.accent_of(team), UiKit.accent_of(opp), _rivalry_tip(team, opp))
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mid.add_child(badge)
		var tag := UiKit.display("VS" if m.home == team else "@", 16, Color(1, 1, 1, 0.7), true)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(tag)
	else:
		var vs := UiKit.display("VS" if m.home == team else "@", 34, Color(1, 1, 1, 0.9), true)
		vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(vs)
	var chip := _weather_chip(m)
	if chip != null:
		mid.add_child(chip)
	var i := 0
	for cmp in compare_rows(team, opp):
		mid.add_child(compare_bar(cmp, UiKit.accent_of(team), UiKit.accent_of(opp), 0.15 + 0.05 * i))
		i += 1
	row.add_child(mid)
	row.add_child(_team_block(opp, true))
	v.add_child(row)

	var imp := HBoxContainer.new()
	imp.add_theme_constant_override("separation", 12)
	imp.alignment = BoxContainer.ALIGNMENT_CENTER
	var ih := UiKit.heading("Impact Players", 17)
	ih.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	imp.add_child(ih)
	for t in [team, opp]:
		for so in _impact_players(t, 2):
			imp.add_child(_impact_chip(t, so))
	v.add_child(imp)
	return v


## Weather chip for a fixture. Only this week's unplayed matches show it (the forecast stays a surprise
## until match week); a played one shows what it was in the recap instead. Null when clear.
func _weather_chip(m: ScheduledMatch) -> Control:
	if m.is_played() or m.week != season.week:
		return null
	return UiKit.weather_chip(m.weather())


func _team_block(t: Team, right: bool) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 250
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	var logo_row := HBoxContainer.new()
	logo_row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	logo_row.add_theme_constant_override("separation", 14)
	var ov := VBoxContainer.new()
	ov.alignment = BoxContainer.ALIGNMENT_CENTER
	ov.add_theme_constant_override("separation", -6)
	var o := UiKit.display("", 62, UiKit.ovr_color(t.team_ovr()), true)
	o.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.count_up(o, t.team_ovr())
	ov.add_child(o)
	var cap := UiKit.display("TEAM OVR", 13, Color(1, 1, 1, 0.6))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov.add_child(cap)
	if right:
		logo_row.add_child(ov)
	logo_row.add_child(UiKit.logo_disc(t, 132))
	if not right:
		logo_row.add_child(ov)
	v.add_child(logo_row)
	# Full name under the logo; wraps to a second line instead of clipping.
	var n := UiKit.display(t.name.to_upper(), 28, Color.WHITE)
	n.horizontal_alignment = align
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 250
	v.add_child(n)
	var r := UiKit.label("%s   ·   #%d" % [season.record_text(t), _rank_of(t)], 16, Color(1, 1, 1, 0.7))
	r.horizontal_alignment = align
	v.add_child(r)
	return v


## Season team stats per game with league rank: {label, a, b, a_text, b_text, lower, a_rank,
## b_rank, n}. Rank 0 = no games yet. Before either side has played, falls back to the starters'
## group ratings (ranked across every team).
func compare_rows(a: Team, b: Team) -> Array:
	var agg: Dictionary = pages.team_aggregates()
	var rows: Array = []
	if int(agg[a]["gp"]) == 0 and int(agg[b]["gp"]) == 0:
		var teams: Array = season.league.teams
		for g in Stats.GROUP_ORDER:
			if g == Stats.DURABILITY:
				continue
			var gf := func(s: Soldier): return s.group_rating(g)
			var all: Array = teams.map(func(t: Team): return _avg(t, gf))
			var x := _avg(a, gf)
			var y := _avg(b, gf)
			rows.append({"label": Stats.GROUP_LABELS[g].to_upper() + " (RATING)", "a": x, "b": y,
				"a_text": str(x), "b_text": str(y), "lower": false,
				"a_rank": _rank_in(all, x, false), "b_rank": _rank_in(all, y, false), "n": teams.size()})
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
		var rank_of := func(t: Team) -> int:
			var r: Dictionary = agg[t]
			return 0 if int(r["gp"]) == 0 else _rank_in(vals, f.call(r), lower)
		var fmt := func(t: Team) -> String:
			var r: Dictionary = agg[t]
			if int(r["gp"]) == 0:
				return "-"
			var x: float = f.call(r)
			var rank: int = rank_of.call(t)
			var txt: String = MatchEngine._fmt_secs(x) if d[2] == "secs" else (d[2] % (roundi(x) if d[2] == "%d%%" else x))
			return "%s (#%d)" % [txt, rank]
		rows.append({"label": d[0], "a": f.call(agg[a]), "b": f.call(agg[b]), "a_text": fmt.call(a), "b_text": fmt.call(b), "lower": lower,
			"a_rank": rank_of.call(a), "b_rank": rank_of.call(b), "n": vals.size()})
	return rows


## 1-based league rank of `x` within `vals` (ties share the better rank).
func _rank_in(vals: Array, x: float, lower: bool) -> int:
	var rank := 1
	for o in vals:
		if (o < x if lower else o > x):
			rank += 1
	return rank


func _avg(t: Team, f: Callable) -> int:
	var list := t.starters()
	if list.is_empty():
		return 0
	var total := 0.0
	for s in list:
		total += float(f.call(s))
	return roundi(total / list.size())


## One stat row: values either side and two bars growing out from the centre. Each bar fills by
## league rank: #1 of N is full, #k is (N - k + 1) / N, no games = empty. `delay` staggers the grow.
func compare_bar(row: Dictionary, c1: Color, c2: Color, delay := 0.0) -> Control:
	var title: String = row["label"]
	var lower: bool = row["lower"]
	var ours := float(row["a"])
	var theirs := float(row["b"])
	var ours_better := ours <= theirs if lower else ours >= theirs
	var theirs_better := theirs <= ours if lower else theirs >= ours
	var n := maxi(1, int(row.get("n", 1)))
	var rank_frac := func(k: int) -> float: return 0.0 if k <= 0 else float(n - k + 1) / n
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := UiKit.display(row["a_text"], 18, Color.WHITE if ours_better else Color(1, 1, 1, 0.5))
	l.custom_minimum_size.x = 96
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(l)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	var t := UiKit.label(title, 12, Color(1, 1, 1, 0.62))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(t)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.add_child(_half_bar(c1, rank_frac.call(int(row.get("a_rank", 0))), false, delay))
	bar.add_child(_half_bar(c2, rank_frac.call(int(row.get("b_rank", 0))), true, delay))
	mid.add_child(bar)
	h.add_child(mid)
	var r := UiKit.display(row["b_text"], 18, Color.WHITE if theirs_better else Color(1, 1, 1, 0.5))
	r.custom_minimum_size.x = 96
	h.add_child(r)
	return h


## Half of a compare bar: a faint track with the fill anchored at the centre line.
func _half_bar(c: Color, frac: float, from_left: bool, delay: float) -> Control:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 0)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.07)
	track.custom_minimum_size.y = 8
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_stretch_ratio = maxf(0.001, 1.0 - frac)
	var fill := ColorRect.new()
	fill.color = c
	fill.custom_minimum_size.y = 8
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if from_left:
		h.add_child(fill)
		h.add_child(track)
	else:
		h.add_child(track)
		h.add_child(fill)
	UiKit.grow(fill, frac, delay)
	return h


## Starters with the highest OVR at their slot.
func _impact_players(t: Team, n: int) -> Array:
	var list: Array = t.starters()
	list.sort_custom(func(a: Soldier, b: Soldier): return t.ovr_in_slot(a, t.slot_of(a)) > t.ovr_in_slot(b, t.slot_of(b)))
	return list.slice(0, n)


func _impact_chip(t: Team, s: Soldier) -> Control:
	var b := Button.new()
	UiKit.style_button(b, Color(0, 0, 0, 0.45), UiKit.accent_of(t), 4)
	b.custom_minimum_size = Vector2(232, 66)
	b.pressed.connect(func(): pages.open_player(s))
	var stripe := ColorRect.new()
	stripe.color = UiKit.accent_of(t)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_right = 4
	b.add_child(stripe)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -8
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Portrait.new(s, 50, t.color, t))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(UiKit.display(s.tag(), 19, Color.WHITE))
	var slot := t.slot_of(s)
	var o := t.ovr_in_slot(s, slot)
	var r := UiKit.rich("[color=#c3cad6]%s %s[/color]  [color=%s][b]%d[/b][/color]" % [t.abbrev, slot, UiKit.hex(UiKit.ovr_color(o)), o], 14)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.custom_minimum_size.x = 140
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
	# After each offseason step, a card that opens its recap.
	if season.phase == Season.PHASE_OFFSEASON or season.preseason_camp:
		var steps := season.news.digest_steps(season)
		if not steps.is_empty():
			var step: String = steps[-1]
			add.call(&"league", "OFFSEASON RECAP  ·  %s" % step.to_upper(), "[color=white]What happened in %s[/color]\n[font_size=13]%s[/font_size]" % [
				UiKit.esc(step), UiKit.esc(season.news.digest_summary(season, step))], Color("#f59e0b"), open_offseason_recap)
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
const FEED_H := 460
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
	var title := UiKit.heading("Playoff Picture" if pane == 1 else "News", 22)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _playoff_pane_open():
		for d in [["<", "FeedPrev"], [">", "FeedNext"]]:
			var b := UiKit.button(d[0], func(): _flip_feed(), 18)
			UiKit.style_skewed(b)
			b.name = d[1]
			b.custom_minimum_size = Vector2(52, 38)
			if d[0] == "<":
				head.add_child(b)
				head.add_child(title)
			else:
				head.add_child(b)
	else:
		head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	if pane == 0:
		for f in FEED_FILTERS:
			var key: StringName = f[0]
			var b := UiKit.button(f[1], func(): _set_feed_filter(key), 15)
			UiKit.style_skewed(b, Color(UiKit.PANEL, 0.8))
			b.toggle_mode = true
			b.button_pressed = feed_filter == key
			if b.button_pressed:
				UiKit.style_primary(b)
			b.name = "Feed_" + String(key)
			head.add_child(b)
	else:
		var full := UiKit.button("Full Bracket", func(): open("Playoff Picture", pages.playoffs), 15)
		UiKit.style_skewed(full)
		head.add_child(full)
	_feed_box.add_child(head)
	var frame := PanelContainer.new()
	var sb := UiKit.flat(Color(UiKit.PANEL, 0.85), 4, 1, Color(1, 1, 1, 0.08))
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size.y = FEED_H
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed_box.add_child(frame)
	if pane == 1:
		var c := CenterContainer.new()
		c.add_child(pages.bracket_view(true))
		frame.add_child(c)
		return
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = FEED_H - 20
	frame.add_child(sc)
	var list := GridContainer.new()
	list.columns = 2
	list.add_theme_constant_override("h_separation", 10)
	list.add_theme_constant_override("v_separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var n := 0
	for it in _feed_items():
		if feed_filter == &"all" or it["cat"] == feed_filter:
			var row := _feed_row(it)
			list.add_child(row)
			if n < 16:
				UiKit.fade_in(row, 0.02 * n, 0.22)
			n += 1
	if n == 0:
		list.add_child(UiKit.label("Nothing here yet.", 16, UiKit.MUTED))


func _set_feed_filter(key: StringName) -> void:
	feed_filter = key
	_fill_feed()


func _flip_feed() -> void:
	feed_pane = 1 - feed_pane
	_fill_feed()


## A compact news card: team-colour stripe and tint, a coloured kicker and the story.
func _feed_row(it: Dictionary) -> Button:
	var accent: Color = it["accent"]
	var bright := UiKit.MUTED if accent.s < 0.12 else Color.from_hsv(accent.h, clampf(accent.s, 0.4, 0.9), maxf(accent.v, 0.85))
	var b := Button.new()
	UiKit.style_button(b, Color(UiKit.PANEL_HI, 0.8), bright, 4)
	b.custom_minimum_size = Vector2(0, 76)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	b.pressed.connect(it["cb"])
	var tint := UiKit.gradient_rect(Color(bright, 0.16), Color(bright, 0.0), false)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(tint)
	var strip := ColorRect.new()
	strip.color = bright
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	strip.offset_right = 5
	b.add_child(strip)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_right = -12
	v.offset_top = 7
	v.offset_bottom = -7
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	v.add_child(UiKit.display(it["tag"], 15, bright))
	var body := UiKit.rich(it["body"], 15)
	body.add_theme_color_override("default_color", Color("#c3cad6"))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	v.minimum_size_changed.connect(func():
		if is_instance_valid(b) and is_instance_valid(v):
			b.custom_minimum_size.y = maxf(76.0, v.get_combined_minimum_size().y + 14.0))
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


## Opens the recap of the latest finished offseason step.
func open_offseason_recap() -> void:
	pages._recap_step = ""
	open("Offseason Recap", pages.offseason_recap)


## Weekly News: the latest issue's headline from the club's paper; done once it has been read.
func _news_todo() -> Button:
	var nr := season.newsroom
	if nr.count() == 0:
		return null
	var a := nr.latest()
	var fresh := nr.unread()
	var body := "[color=white]%s[/color]\n%s" % [UiKit.esc(String(a["headline"])), UiKit.esc(String(a["when"]))]
	if fresh > 1:
		body += "  -  [color=#38bdf8]%d new issues[/color]" % fresh
	return _todo("Weekly News", body, Color("#e2e8f0"), func(): open_news(), fresh == 0)


## Opens a Weekly News issue (index into newsroom.issues; -1 = the latest) and marks it read.
func open_news(i := -1) -> void:
	var nr := season.newsroom
	if nr.count() == 0:
		return
	if i < 0 or i >= nr.count():
		i = nr.count() - 1
	nr.mark_read(i)
	open("Weekly News", func(): return pages.news_article(i))


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


## The draft is finished (roster review or later).
func draft_done() -> bool:
	return season.phase == Season.PHASE_OFFSEASON and season.offseason_stage in [Season.OFF_REVIEW, Season.OFF_CAMP, Season.OFF_DONE]


func open_scouting() -> void:
	open("Scouting", pages.scouting)


func open_draft_room() -> void:
	open("Draft Room", pages.draft_room)


func open_mock_draft() -> void:
	open("Mock Draft", pages.mock_draft)


## The Team tab is a custom layout (see _tab_view): the Roster / Lineup pane, live cards, a
## coming-soon strip. No tile sections.
func _team_sections() -> Array:
	return []


const TEAM_VIEWS := ["Roster", "Lineup"]
const TEAM_PANE_H := 840  # Roster scrolls inside this; Lineup sizes to fit (field + bench) and never scrolls
var team_view := 0  # 0 roster, 1 lineup
var _team_box: VBoxContainer


## Top of the Team tab: one big pane whose arrows flip between the full Roster and Lineup screens.
func _team_top() -> Control:
	_team_box = VBoxContainer.new()
	_team_box.name = "TeamPane"
	_team_box.add_theme_constant_override("separation", 8)
	_fill_team_box()
	return _team_box


func _flip_team_view(dir: int) -> void:
	team_view = wrapi(team_view + dir, 0, TEAM_VIEWS.size())
	_fill_team_box()


## `keep`: an in-place refresh (sort, swap, scheme change) - keep the pane's scroll and focus.
func _fill_team_box(keep := false) -> void:
	var scroll_pos := 0
	var focus_index := -1
	if keep:
		var old := _team_box.find_child("TeamPaneScroll", true, false) as ScrollContainer
		if old:
			scroll_pos = old.scroll_vertical
		focus_index = app.focusables(_team_box).find(get_viewport().gui_get_focus_owner())
	for c in _team_box.get_children():
		_team_box.remove_child(c)
		c.queue_free()
	var team := season.user_team()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := UiKit.heading(TEAM_VIEWS[team_view], 22)
	title.custom_minimum_size.x = 90
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for d in [["<", -1, "TeamPrev"], [">", 1, "TeamNext"]]:
		var dir: int = d[1]
		var b := UiKit.button(d[0], func(): _flip_team_view(dir), 18)
		UiKit.style_skewed(b)
		b.name = d[2]
		b.custom_minimum_size = Vector2(52, 38)
		head.add_child(b)
		if dir < 0:
			head.add_child(title)
	var other := UiKit.label("%s  >" % TEAM_VIEWS[1 - team_view].to_upper(), 13, UiKit.MUTED)
	other.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(other)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var info := UiKit.rich("[right]%s[/right]" % _team_pane_info(team), 15)
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.custom_minimum_size.x = 640
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(info)
	_team_box.add_child(head)
	var frame := PanelContainer.new()
	var sb := UiKit.flat(Color(UiKit.PANEL, 0.85), 4, 1, Color(1, 1, 1, 0.08))
	sb.border_width_top = 3
	sb.border_color = UiKit.ACCENT
	sb.set_content_margin_all(16)
	frame.add_theme_stylebox_override("panel", sb)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_team_box.add_child(frame)
	var sc := ScrollContainer.new()
	sc.name = "TeamPaneScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = TEAM_PANE_H if team_view == 0 else 0
	if team_view == 1:
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(sc)
	var body: Control = pages.roster() if team_view == 0 else pages.lineup()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	if keep:
		_restore_pane(sc, scroll_pos, focus_index, _team_box)
	else:
		UiKit.fade_in(body, 0.0, 0.2)
		sc.follow_focus = true


func _restore_pane(sc: ScrollContainer, pos: int, focus_index: int, box: Control) -> void:
	for i in 2:
		await get_tree().process_frame
		if not is_instance_valid(sc):
			return
		sc.scroll_vertical = pos
	if not is_instance_valid(box):
		return
	var list: Array[Control] = app.focusables(box)
	if not app.mouse_mode and focus_index >= 0 and focus_index < list.size():
		list[focus_index].grab_focus()
	sc.scroll_vertical = pos
	sc.follow_focus = true


func _team_pane_info(team: Team) -> String:
	var dot := "   [color=#8b97ab]·[/color]   "
	if team_view == 1:
		return "[color=#8b97ab]SCHEME[/color] %s%s[color=#8b97ab]TEAM OVR[/color] [color=%s]%d[/color]" % [
			team.scheme.display_name, dot, UiKit.hex(UiKit.ovr_color(team.team_ovr())), team.team_ovr()]
	var age := 0.0
	for s in team.roster:
		age += s.age
	return "%d [color=#8b97ab]SOLDIERS[/color]%s[color=#8b97ab]AVG AGE[/color] %.1f%s[color=#8b97ab]PAYROLL[/color] %s" % [
		team.roster.size(), dot, age / maxi(1, team.roster.size()), dot, Contracts.money(Contracts.payroll(team, season.cap_year()))]


## Under the pane: one live card per Team screen - a headline number, a detail line and an alert
## chip when something needs doing.
func _team_cards() -> Control:
	var team := season.user_team()
	var row := HBoxContainer.new()
	row.name = "TeamCards"
	row.add_theme_constant_override("separation", 14)
	var cards: Array = []
	var off := season.phase == Season.PHASE_OFFSEASON

	var up := 0
	var sp := 0
	for s in team.roster:
		sp += s.skill_points
		if Progression.can_level_up(s):
			up += 1
	cards.append(_stat_card("Player Progression", str(up), "CAN LEVEL UP", "%d skill point%s banked" % [sp, "" if sp == 1 else "s"],
		UiKit.INFO, func(): open("Player Progression", pages.progression), "LEVEL UP" if up > 0 else ""))

	var fat := 0.0
	var tired := 0
	for s in team.roster:
		fat += s.fatigue
		if s.fatigue >= 50.0 and not s.is_injured():
			tired += 1
	var can_train := not off and not season.preseason_camp and season.can_train_user_team() and not season.user_trained()
	var tstate := "Done this week" if season.user_trained() else ("[color=#38bdf8]Ready to train[/color]" if can_train else "Not available")
	cards.append(_stat_card("Training", str(roundi(fat / maxi(1, team.roster.size()))), "AVG FATIGUE",
		"%s\n%s" % [tstate, ("[color=#f97316]%d tired[/color]" % tired) if tired > 0 else "No one tired"],
		Color("#22c55e"), func(): open("Training", pages.training), "TRAIN" if can_train else ""))

	var hurt := team.injured()
	var hurt_starters := team.starters().filter(func(x: Soldier): return x.is_injured())
	var names := PackedStringArray(hurt.slice(0, 2).map(func(x: Soldier): return "%s (%dw)" % [x.short_name(), x.injury_weeks]))
	cards.append(_stat_card("Injuries", str(hurt.size()), "OUT", ", ".join(names) + (" +%d" % (hurt.size() - 2) if hurt.size() > 2 else "") if not hurt.is_empty() else "Fully healthy",
		UiKit.BAD, func(): open("Injuries", pages.injuries), "STARTER OUT" if not hurt_starters.is_empty() else ""))

	var agg: Dictionary = pages.team_aggregates()
	var mine: Dictionary = agg[team]
	if int(mine["gp"]) > 0:
		var kd := func(r: Dictionary) -> float: return float(r["kills"]) / maxi(1, int(r["deaths"]))
		var vals: Array = agg.values().filter(func(r: Dictionary): return int(r["gp"]) > 0).map(kd)
		cards.append(_stat_card("Team Stats", "%.2f" % kd.call(mine), "K/D  #%d" % _rank_in(vals, kd.call(mine), false),
			"%.1f kills  ·  %.1f deaths / game" % [float(mine["kills"]) / int(mine["gp"]), float(mine["deaths"]) / int(mine["gp"])],
			Color("#eab308"), func(): open("Team Stats", pages.team_stats)))
	else:
		cards.append(_stat_card("Team Stats", "-", "K/D", "No games played yet", Color("#eab308"), func(): open("Team Stats", pages.team_stats)))

	var lines := PackedStringArray()
	var played: Array = season.matches_for(team).filter(func(m: ScheduledMatch): return m.is_played())
	if not played.is_empty():
		var lm: ScheduledMatch = played[-1]
		var o := lm.opponent_of(team)
		lines.append("Last: [color=%s]%s[/color] %d-%d %s %s" % [UiKit.hex(UiKit.GOOD if lm.winner() == team else UiKit.BAD), "W" if lm.winner() == team else "L",
			lm.games_for(team), lm.games_for(o), "vs" if lm.home == team else "@", o.abbrev])
	var nm := season.next_match_for(team)
	if nm:
		lines.append("Next: %s %s %s" % [season.week_label(nm.week), "vs" if nm.home == team else "@", nm.opponent_of(team).abbrev])
	cards.append(_stat_card("Schedule", season.record_text(team), "RECORD", "\n".join(lines) if not lines.is_empty() else "Season complete",
		Color("#a855f7"), func(): open("Schedule", pages.schedule)))

	var n := 0
	for c in cards:
		row.add_child(c)
		UiKit.fade_in(c, 0.04 * n, 0.25)
		n += 1
	return row


func _stat_card(title: String, big: String, caption: String, detail: String, accent: Color, cb: Callable, alert := "") -> Button:
	# Every card wears the team trim; colour only means something on the alert chip.
	var chip_color := UiKit.GOLD
	accent = UiKit.MUTED if accent == UiKit.MUTED else UiKit.TRIM
	var b := UiKit.tile(title, "", Vector2(0, 146), accent, cb)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var foot := HBoxContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_left = 18
	foot.offset_right = -18
	foot.offset_top = -96
	foot.offset_bottom = -12
	foot.add_theme_constant_override("separation", 10)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(foot)
	var d := UiKit.rich(detail, 14)
	d.add_theme_color_override("default_color", UiKit.MUTED)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.size_flags_vertical = Control.SIZE_SHRINK_END
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(d)
	var num := VBoxContainer.new()
	num.add_theme_constant_override("separation", -6)
	num.size_flags_vertical = Control.SIZE_SHRINK_END
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := UiKit.display(big, 48, accent.lightened(0.15), true)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.add_child(bl)
	var cl := UiKit.label(caption, 12, UiKit.MUTED)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.add_child(cl)
	foot.add_child(num)
	if alert != "":
		var chip := PanelContainer.new()
		var cs := UiKit.flat(chip_color, 4)
		cs.content_margin_left = 10
		cs.content_margin_right = 10
		cs.content_margin_top = 2
		cs.content_margin_bottom = 2
		cs.skew = Vector2(UiKit.SKEW, 0)
		chip.add_theme_stylebox_override("panel", cs)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(UiKit.display(alert, 14, Color(0.03, 0.04, 0.08), true))
		chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		chip.offset_right = -14
		chip.offset_top = 16
		b.add_child(chip)
		UiKit.pulse(chip)
	return b


## Not-yet-built Team screens as a thin, dimmed strip.
func _soon_strip() -> Control:
	var h := HBoxContainer.new()
	h.name = "SoonStrip"
	h.add_theme_constant_override("separation", 10)
	h.modulate = Color(1, 1, 1, 0.6)
	var l := UiKit.display("COMING SOON", 15, UiKit.MUTED)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	for d in [["Scheme & Strategy", ["Alternate formations", "Aggression / pace sliders", "Per-mode round plans"]],
			["Coaching Staff", ["Head coach and position coaches", "Training and progression boosts", "Staff contracts"]],
			["Facilities", ["Training facility upgrades", "Medical centre (injury recovery)", "Costs from the yearly money pool"]]]:
		var title: String = d[0]
		var bullets: Array = d[1]
		var b := UiKit.button(title, func(): coming_soon(title, bullets), 14)
		UiKit.style_skewed(b, Color(UiKit.PANEL, 0.6))
		h.add_child(b)
	return h


## The League tab is a custom layout (see _tab_view): the Standings / Scores / Leaders / Playoffs
## pane, live cards, a link strip. No tile sections.
func _league_sections() -> Array:
	return []


const LEAGUE_VIEWS := ["Standings", "Scores", "League Leaders", "Playoff Picture"]
const LEAGUE_PANE_H := 660
var league_view := 0
var league_week := 0  # Scores view week; 0 = the latest week with results
var _league_box: VBoxContainer


func _league_top() -> Control:
	_league_box = VBoxContainer.new()
	_league_box.name = "LeaguePane"
	_league_box.add_theme_constant_override("separation", 8)
	_fill_league_box()
	return _league_box


func _flip_league_view(dir: int) -> void:
	league_view = wrapi(league_view + dir, 0, LEAGUE_VIEWS.size())
	_fill_league_box()


func _fill_league_box() -> void:
	for c in _league_box.get_children():
		_league_box.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := UiKit.heading(LEAGUE_VIEWS[league_view], 22)
	title.custom_minimum_size.x = 170  # fits the widest view name, so the arrows never move
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for d in [["<", -1, "LeaguePrev"], [">", 1, "LeagueNext"]]:
		var dir: int = d[1]
		var b := UiKit.button(d[0], func(): _flip_league_view(dir), 18)
		UiKit.style_skewed(b)
		b.name = d[2]
		b.custom_minimum_size = Vector2(52, 38)
		head.add_child(b)
		if dir < 0:
			head.add_child(title)
	var other := UiKit.label("%s  >" % LEAGUE_VIEWS[wrapi(league_view + 1, 0, LEAGUE_VIEWS.size())].to_upper(), 13, UiKit.MUTED)
	other.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(other)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var info := UiKit.rich("[right]%s[/right]" % _league_pane_info(), 15)
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.custom_minimum_size.x = 640
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(info)
	_league_box.add_child(head)
	var frame := PanelContainer.new()
	var sb := UiKit.flat(Color(UiKit.PANEL, 0.85), 4, 1, Color(1, 1, 1, 0.08))
	sb.border_width_top = 3
	sb.border_color = UiKit.ACCENT
	sb.set_content_margin_all(16)
	frame.add_theme_stylebox_override("panel", sb)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_league_box.add_child(frame)
	var sc := ScrollContainer.new()
	sc.name = "LeaguePaneScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = LEAGUE_PANE_H
	sc.follow_focus = true
	frame.add_child(sc)
	var body: Control
	match league_view:
		0: body = _league_standings()
		1: body = _league_scores()
		2: body = pages.leaders()
		_: body = _league_playoffs()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	UiKit.fade_in(body, 0.0, 0.2)


func _league_pane_info() -> String:
	var dot := "   [color=#8b97ab]·[/color]   "
	var team := season.user_team()
	var field := season.playoff_field() if season.phase == Season.PHASE_REGULAR else []
	var seed := field.find(team)
	var where := ("[color=#22c55e]SEED %d[/color]" % (seed + 1)) if seed >= 0 else ("[color=#ef4444]OUTSIDE[/color]" if season.phase == Season.PHASE_REGULAR else "-")
	return "[color=#8b97ab]%s[/color]%s[color=#8b97ab]YOU[/color] %s  %s%s[color=#8b97ab]PLAYOFF SPOTS[/color] %d" % [
		season.week_label(clampi(season.week, 1, season.total_weeks())).to_upper(), dot, season.record_text(team), where, dot, season.playoff_teams]


## Standings: four division cards in a 2x2 grid (or one whole-league table).
func _league_standings() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var field := season.playoff_field()
	var seeds := {}
	for i in field.size():
		seeds[field[i]] = i + 1
	var n_div := season.divisions().size() if season.has_divisions() else 0
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	if n_div > 0:
		for o in [["div", "Divisions"], ["league", "Whole league"]]:
			var val: String = o[0]
			var b := pages._seg(o[1], pages.standings_view == val, func():
				pages.standings_view = val
				_fill_league_box(), 15)
			b.custom_minimum_size.x = 150
			nav.add_child(b)
	var key := UiKit.rich("[color=%s]■[/color] [color=#8b97ab]division leader[/color]    [color=%s]■[/color] [color=#8b97ab]wild card[/color]    [color=#8b97ab]%d make the playoffs  ·  seeds if the season ended today[/color]" % [
		UiKit.hex(UiKit.ACCENT), UiKit.hex(UiKit.INFO), season.playoff_teams], 14)
	key.autowrap_mode = TextServer.AUTOWRAP_OFF
	key.fit_content = true
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.add_child(key)
	v.add_child(nav)
	if n_div == 0 or pages.standings_view == "league":
		v.add_child(pages._standings_table(season.standings(), seeds, false))
		return v
	var grid := GridContainer.new()
	grid.name = "DivisionGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	for d in season.divisions():
		grid.add_child(_division_card(d, seeds, n_div))
	v.add_child(grid)
	return v


func _division_card(div: String, seeds: Dictionary, n_div: int) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UiKit.flat(Color(0, 0, 0, 0.28), 4, 1, Color(1, 1, 1, 0.06))
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var cols := [["W-L", 70], ["GW-GL", 80], ["DIFF", 60], ["STRK", 60], ["SEED", 70]]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var dl := UiKit.display(div.to_upper() + " DIVISION", 19, Color.WHITE, true)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(dl)
	for c in cols:
		var l := UiKit.label(c[0], 12, UiKit.MUTED)
		l.custom_minimum_size.x = c[1]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		head.add_child(l)
	col.add_child(head)
	var rows: Array = season.division_standings(div)
	for i in rows.size():
		var r: StandingRow = rows[i]
		var t := r.team
		var seed := int(seeds.get(t, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var bar := ColorRect.new()
		bar.color = t.color
		bar.custom_minimum_size = Vector2(4, 0)
		row.add_child(bar)
		var rk := UiKit.label(str(i + 1), 15, UiKit.MUTED)
		rk.custom_minimum_size.x = 18
		rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(rk)
		var logo := UiKit.team_logo(t, 30)
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(logo)
		var nm := UiKit.label(t.name, 17, Color.WHITE if seed > 0 else UiKit.TEXT)
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(nm)
		var gd := r.game_diff()
		var seed_col := UiKit.ACCENT if seed > 0 and seed <= n_div else (UiKit.INFO if seed > 0 else UiKit.MUTED)
		var vals := [["%d-%d" % [r.wins, r.losses], Color.WHITE], ["%d-%d" % [r.games_won, r.games_lost], UiKit.TEXT],
			["%+d" % gd, UiKit.GOOD if gd > 0 else (UiKit.BAD if gd < 0 else UiKit.MUTED)],
			[r.streak, UiKit.GOOD if r.streak.begins_with("W") else (UiKit.BAD if r.streak.begins_with("L") else UiKit.MUTED)],
			[("%d %s" % [seed, "DIV" if seed <= n_div else "WC"]) if seed > 0 else "-", seed_col]]
		for k in vals.size():
			var l := UiKit.label(vals[k][0], 16, vals[k][1])
			l.custom_minimum_size.x = cols[k][1]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(l)
		var b := pages._click_wrap(row, func(): open(t.name, func(): return pages.team_roster(t)), 42)
		b.name = "Div_%s_%d" % [div, i]
		if t.user_controlled:
			b.add_theme_stylebox_override("normal", UiKit.flat(UiKit.MINE, 6, 2, UiKit.ACCENT.darkened(0.15)))
		col.add_child(b)
	return card


## Scores: one week of results (or fixtures) with week arrows.
func _league_scores() -> Control:
	var w := league_week if league_week > 0 else _last_week_with_results()
	w = clampi(w, 1, season.total_weeks())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	for d in [["< Prev week", -1], ["Next week >", 1]]:
		var dir: int = d[1]
		var b := UiKit.button(d[0], func():
			league_week = clampi(w + dir, 1, season.total_weeks())
			_fill_league_box(), 15)
		UiKit.style_skewed(b)
		b.disabled = (w <= 1) if dir < 0 else (w >= season.total_weeks())
		nav.add_child(b)
		if dir < 0:
			var lbl := UiKit.display(season.week_label(w).to_upper(), 22, Color.WHITE, true)
			lbl.custom_minimum_size.x = 240
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			nav.add_child(lbl)
	v.add_child(nav)
	var matches: Array = season.matches_for_week(w)
	if matches.is_empty():
		v.add_child(UiKit.label("Matchups not set yet - decided by earlier playoff results.", 16, UiKit.MUTED))
	for m in matches:
		v.add_child(pages._score_line(m))
	var byes: Array = season.bye_teams(w)
	if not byes.is_empty():
		v.add_child(UiKit.label("BYE: %s" % ", ".join(PackedStringArray(byes.map(func(t: Team): return t.name))), 15, UiKit.MUTED))
	return v


func _league_playoffs() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	if season.phase == Season.PHASE_REGULAR:
		v.add_child(UiKit.label("If the season ended today. The better seed is at home; the bracket is fixed (no reseeding).", 15, UiKit.MUTED))
	v.add_child(pages.bracket_view(false))
	var more := UiKit.button("Full playoff picture", func(): open("Playoff Picture", pages.playoffs), 14)
	UiKit.style_skewed(more)
	more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(more)
	return v


## Under the pane: live cards for the other League screens.
func _league_cards() -> Control:
	var team := season.user_team()
	var row := HBoxContainer.new()
	row.name = "LeagueCards"
	row.add_theme_constant_override("separation", 14)
	var cards: Array = []

	var teams: Array = season.league.teams.duplicate()
	teams.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	var top: Team = teams[0]
	cards.append(_stat_card("Team Rankings", "#%d" % (teams.find(team) + 1), "YOUR OVR RANK",
		"You: OVR %d\nTop: %s (%d)" % [team.team_ovr(), top.abbrev, top.team_ovr()], Color("#22c55e"),
		func(): open("Team Rankings", pages.team_rankings)))

	var totals := pages.season_totals()
	if totals.is_empty():
		cards.append(_stat_card("League Stats", "-", "KILLS LEADER", "No games played yet", Color("#0ea5e9"), func(): open("League Stats", pages.league_stats)))
	else:
		var best: Dictionary = totals[0]
		for t in totals:
			if int(t["kills"]) > int(best["kills"]):
				best = t
		cards.append(_stat_card("League Stats", str(best["kills"]), "KILLS LEADER", "[color=white]%s[/color]\n%s  ·  %d games" % [
			UiKit.esc(best["soldier"].short_name()), best["team"].abbrev, best["matches"]], Color("#0ea5e9"), func(): open("League Stats", pages.league_stats)))

	var heads := pages.headlines(1)
	cards.append(_stat_card("League News", str(season.news.items.size()), "STORIES", _headline(), Color("#14b8a6"),
		func(): open("League News", pages.news), "NEW" if not heads.is_empty() and season.phase == Season.PHASE_REGULAR and season.week > 1 else ""))

	if season.review != null and not season.review.awards.is_empty():
		var mvp: Dictionary = season.review.awards[0]
		cards.append(_stat_card("Awards", mvp["team"].abbrev, "%d MVP" % season.review.year, "[color=white]%s[/color]" % UiKit.esc(mvp["soldier"].full_name()),
			Color("#f59e0b"), func(): open("Awards & Development", pages.awards)))
	else:
		var fav := {}
		for t in totals:
			if int(t["matches"]) < SeasonReview.MIN_MATCHES:
				continue
			if fav.is_empty() or float(t["impact"]) / int(t["matches"]) > float(fav["impact"]) / int(fav["matches"]):
				fav = t
		if fav.is_empty():
			cards.append(_stat_card("Awards", "-", "MVP RACE", "Needs %d games played" % SeasonReview.MIN_MATCHES, Color("#f59e0b"), func(): open("Awards & Development", pages.awards)))
		else:
			cards.append(_stat_card("Awards", fav["team"].abbrev, "MVP FAVOURITE", "[color=white]%s[/color]\n%d match MVPs  ·  %d games" % [
				UiKit.esc(fav["soldier"].short_name()), fav["mvps"], fav["matches"]], Color("#f59e0b"), func(): open("Awards & Development", pages.awards)))

	var fas: Array = season.league.free_agents
	var bfa: Soldier = null
	for s in fas:
		if bfa == null or s.best_ovr() > bfa.best_ovr():
			bfa = s
	var open_fa := season.free_agency_open()
	cards.append(_stat_card("Free Agents", str(fas.size()), "AVAILABLE", ("Best: [color=white]%s[/color] (%d)\n" % [UiKit.esc(bfa.short_name()), bfa.best_ovr()] if bfa else "")
		+ ("Bidding open" if open_fa else "Bidding opens after re-signing"), Color("#14b8a6"), open_free_agents, "BIDDING" if open_fa else ""))

	var n := 0
	for c in cards:
		row.add_child(c)
		UiKit.fade_in(c, 0.04 * n, 0.25)
		n += 1
	return row


## The remaining League screens as a second row of cards.
func _league_strip() -> Control:
	var team := season.user_team()
	var cards: Array = []
	var wk := clampi(season.week, 1, season.total_weeks())
	var games: Array = season.matches_for_week(wk)
	var played := games.filter(func(m: ScheduledMatch): return m.is_played()).size()
	var nm := season.next_match_for(team)
	var next_txt := ("Next: %s %s (%s)" % ["vs" if nm.home == team else "@", nm.opponent_of(team).abbrev, season.week_label(nm.week)]) if nm else "No games left"
	cards.append(_stat_card("Schedule", str(wk), ("OF %d" % season.regular_weeks) if wk <= season.regular_weeks else season.week_label(wk).to_upper(),
		"%s\n%d of %d matches played this week" % [next_txt, played, games.size()],
		Color("#6366f1"), func(): open("Scores & Schedule", func(): return pages.scores(wk))))

	var kills := {}
	for t in pages.season_totals():
		kills[t["team"]] = int(kills.get(t["team"], 0)) + int(t["kills"])
	if kills.is_empty():
		cards.append(_stat_card("Team Stats", "-", "KILLS RANK", "No games played yet", Color("#3b82f6"), func(): open("League Team Stats", pages.league_team_stats)))
	else:
		var order: Array = kills.keys()
		order.sort_custom(func(a: Team, b: Team): return kills[a] > kills[b])
		cards.append(_stat_card("Team Stats", "#%d" % (order.find(team) + 1), "KILLS RANK", "You: %d kills\nTop: %s (%d)" % [int(kills.get(team, 0)), order[0].abbrev, kills[order[0]]],
			Color("#3b82f6"), func(): open("League Team Stats", pages.league_team_stats)))

	cards.append(_stat_card("Teams", str(season.league.teams.size()), "TEAMS", "Every roster, logo and record\n%d make the playoffs" % season.playoff_teams,
		Color("#a855f7"), func(): open("Teams", pages.teams)))

	var rets: Array = season.retirements
	var last: Dictionary = rets[-1] if not rets.is_empty() else {}
	cards.append(_stat_card("Retirements", str(rets.size()), "RETIRED", ("Latest: [color=white]%s[/color] at %d" % [UiKit.esc(last["soldier"].short_name()), last["age"]]) if not last.is_empty() else "Nobody has retired yet",
		Color("#94a3b8"), open_retirements))

	cards.append(_soon_card("Records & History", "Champions, records, Hall of Fame", ["Past champions by year", "Single-season and career records", "Hall of Fame"]))
	return _card_row("LeagueMore", cards, 5)


## A dimmed card for a screen that is not built yet.
func _soon_card(title: String, detail: String, bullets: Array) -> Button:
	var c := _stat_card(title, "SOON", "", detail, UiKit.MUTED, func(): coming_soon(title, bullets))
	c.modulate = Color(1, 1, 1, 0.6)
	return c


## A row of cards, padded with empty slots to `cols` so it lines up with the row above.
func _card_row(row_name: String, cards: Array, cols: int) -> Control:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 14)
	var n := 0
	for c in cards:
		row.add_child(c)
		UiKit.fade_in(c, 0.04 * n, 0.25)
		n += 1
	for i in range(cards.size(), cols):
		var pad := Control.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pad)
	return row


## The Personnel tab is a custom layout (see _tab_view): the Contracts / Trades / Draft pane,
## live cards, a second row of cards. No tile sections.
func _personnel_sections() -> Array:
	return []


const PERS_PANE_H := 660
var personnel_view := 0
var _personnel_key := ""  # phase the view was picked for; a new phase re-picks the default
var _pers_box: VBoxContainer


## Page titles of the pane's views (the pages refresh themselves with hub.replace(title, ...)).
## The Draft Room joins only while the draft is running.
func _personnel_views() -> Array:
	var v := ["Contracts & Payroll", "Trades"]
	if _draft_live():
		v.append("Draft Room")
	return v


func _personnel_view_names() -> Array:
	var v := ["Contracts", "Trades"]
	if _draft_live():
		v.append("Draft Room")
	return v


func _draft_live() -> bool:
	return season.draft.is_started() and not draft_done()


## Pane view a refreshing page title belongs to (-1: not a pane page). The Trades view is built
## from the Trade Offers and Trade Block pages, which refresh under their own titles.
func _personnel_view_for(title: String) -> int:
	if title in ["Trade Offers", "Trade Block"]:
		return 1
	return _personnel_views().find(title)


## The view that matters most right now: the draft on draft day, trades in season, contracts otherwise.
func _personnel_default() -> int:
	if season.phase == Season.PHASE_OFFSEASON:
		return 2 if season.offseason_stage == Season.OFF_DRAFT and _draft_live() else 0
	if season.preseason_camp:
		return 0
	return 1


func _personnel_top() -> Control:
	var key := "%d|%s|%s" % [season.year, season.phase, season.offseason_stage]
	if key != _personnel_key:
		_personnel_key = key
		personnel_view = _personnel_default()
	_pers_box = VBoxContainer.new()
	_pers_box.name = "PersonnelPane"
	_pers_box.add_theme_constant_override("separation", 8)
	_fill_personnel_box()
	return _pers_box


func _flip_personnel_view(dir: int) -> void:
	personnel_view = wrapi(personnel_view + dir, 0, _personnel_views().size())
	_fill_personnel_box()


## `keep`: an in-place refresh (sort, offer, pick) - keep the pane's scroll and focus.
func _fill_personnel_box(keep := false) -> void:
	var scroll_pos := 0
	var focus_index := -1
	if keep:
		var old := _pers_box.find_child("PersonnelPaneScroll", true, false) as ScrollContainer
		if old:
			scroll_pos = old.scroll_vertical
		focus_index = app.focusables(_pers_box).find(get_viewport().gui_get_focus_owner())
	for c in _pers_box.get_children():
		_pers_box.remove_child(c)
		c.queue_free()
	var names := _personnel_view_names()
	personnel_view = clampi(personnel_view, 0, names.size() - 1)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := UiKit.heading(names[personnel_view], 22)
	title.custom_minimum_size.x = 150  # fits the widest view name, so the arrows never move
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for d in [["<", -1, "PersonnelPrev"], [">", 1, "PersonnelNext"]]:
		var dir: int = d[1]
		var b := UiKit.button(d[0], func(): _flip_personnel_view(dir), 18)
		UiKit.style_skewed(b)
		b.name = d[2]
		b.custom_minimum_size = Vector2(52, 38)
		head.add_child(b)
		if dir < 0:
			head.add_child(title)
	var other := UiKit.label("%s  >" % String(names[wrapi(personnel_view + 1, 0, names.size())]).to_upper(), 13, UiKit.MUTED)
	other.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(other)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var info := UiKit.rich("[right]%s[/right]" % _personnel_pane_info(), 15)
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.custom_minimum_size.x = 640
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(info)
	_pers_box.add_child(head)
	var frame := PanelContainer.new()
	var sb := UiKit.flat(Color(UiKit.PANEL, 0.85), 4, 1, Color(1, 1, 1, 0.08))
	sb.border_width_top = 3
	sb.border_color = UiKit.ACCENT
	sb.set_content_margin_all(16)
	frame.add_theme_stylebox_override("panel", sb)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pers_box.add_child(frame)
	var sc := ScrollContainer.new()
	sc.name = "PersonnelPaneScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = PERS_PANE_H
	frame.add_child(sc)
	var body: Control
	match personnel_view:
		0: body = pages.contracts()
		1: body = pages.trade_hub()
		_: body = pages.draft_room()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	if keep:
		_restore_pane(sc, scroll_pos, focus_index, _pers_box)
	else:
		UiKit.fade_in(body, 0.0, 0.2)
		sc.follow_focus = true


func _personnel_pane_info() -> String:
	var dot := "   [color=#8b97ab]·[/color]   "
	var team := season.user_team()
	var cy := season.cap_year()
	var space := Contracts.cap_space(team, cy)
	return "[color=#8b97ab]PAYROLL[/color] %s [color=#8b97ab]of %s[/color]%s[color=#8b97ab]CAP SPACE[/color] [color=%s]%s[/color]%s[color=#8b97ab]ROSTER[/color] [color=%s]%d / %d[/color]" % [
		Contracts.money(Contracts.payroll(team, cy)), Contracts.money(Contracts.SALARY_CAP), dot,
		UiKit.hex(UiKit.GOOD if space >= 0 else UiKit.BAD), Contracts.money(space), dot,
		UiKit.hex(UiKit.BAD if team.is_over_roster_limit() else Color.WHITE), team.roster.size(), Team.ROSTER_SIZE]


## Under the pane: live cards for the other Personnel screens.
func _personnel_cards() -> Control:
	var team := season.user_team()
	var row := HBoxContainer.new()
	row.name = "PersonnelCards"
	row.add_theme_constant_override("separation", 14)
	var cards: Array = []

	var fa_stage := season.phase == Season.PHASE_OFFSEASON and season.offseason_stage == Season.OFF_FREE_AGENCY
	var bids: int = season.fa.offers_by(team).size()
	var fa_detail := ("Day %d of %d" % [season.fa_day, Season.FA_DAYS]) if fa_stage else \
		("Opens after re-signing" if not season.free_agency_open() else "Bidding open")
	if bids > 0:
		fa_detail += "\n%d offer%s out" % [bids, "" if bids == 1 else "s"]
	cards.append(_stat_card("Free Agency", str(season.league.free_agents.size()), "AVAILABLE", fa_detail,
		Color("#f97316"), open_free_agents, "FA DAY %d" % season.fa_day if fa_stage else ""))

	# In season the contracts that expire are the ones in their final year.
	var off := season.phase == Season.PHASE_OFFSEASON
	var exp: Array = Contracts.expiring(team) if off else team.roster.filter(func(x: Soldier): return x.contract != null and x.contract.years == 1)
	cards.append(_stat_card("Re-sign Players", str(exp.size()), "EXPIRING" if off else "IN FINAL YEAR", "Window open" if season.can_resign() else "Window opens after the Final",
		Color("#22c55e"), open_resign, "RE-SIGN" if season.can_resign() and not exp.is_empty() else ""))

	var d := season.draft
	var order: Array = season.mock_pick_order()
	var mine: Array = []
	for i in range(d.next_pick if d.is_started() else 0, order.size()):
		if order[i] == team:
			mine.append(i + 1)
	if d.is_complete() or mine.is_empty():
		cards.append(_stat_card("Mock Draft", "-", "YOUR NEXT PICK", "Draft complete" if d.is_complete() else "No picks left", UiKit.INFO, open_mock_draft))
	else:
		var per := maxi(1, order.size() / Draft.ROUNDS)
		cards.append(_stat_card("Mock Draft", "#%d" % mine[0], "YOUR NEXT PICK", "Round %d  ·  %d pick%s left\n%s" % [
			(mine[0] - 1) / per + 1, mine.size(), "" if mine.size() == 1 else "s", "Real order" if d.is_started() else "From current standings"],
			UiKit.INFO, open_mock_draft, "ON THE CLOCK" if d.is_started() and d.on_the_clock() == team else ""))

	var pts := d.scout_points
	cards.append(_stat_card("Scouting", str(pts), "SCOUT POINTS", "%d of %d prospects scouted\n+%d per week" % [_scouted_count(), Draft.CLASS_SIZE, Draft.POINTS_PER_WEEK],
		Color("#06b6d4"), open_scouting, "SPEND" if pts > 0 and not d.is_started() else ""))

	var n := 0
	for c in cards:
		row.add_child(c)
		UiKit.fade_in(c, 0.04 * n, 0.25)
		n += 1
	return row


## The remaining Personnel screens as a second row of cards.
func _personnel_strip() -> Control:
	var team := season.user_team()
	var cards: Array = []
	var hist: Array = season.trades.history
	var mine := hist.filter(func(e): return e["a"] == team or e["b"] == team).size()
	var lt: Dictionary = hist[-1] if not hist.is_empty() else {}
	cards.append(_stat_card("Trade Log", str(hist.size()), "LEAGUE TRADES", ("%d involving you\nLatest: %s - %s" % [mine, lt["a"].abbrev, lt["b"].abbrev]) if not lt.is_empty() else "No trades yet",
		Color("#f97316"), func(): open("Trade Log", pages.trade_log)))

	var d: Draft = season.draft if season.draft.is_complete() else (season.past_drafts[-1] if not season.past_drafts.is_empty() else null)
	if d == null:
		cards.append(_stat_card("Draft Recap", "-", "NO DRAFT YET", "Every pick and grade after the first draft", UiKit.INFO, func(): coming_soon("Draft Recap", ["Available once the first draft is done"])))
	else:
		var picks: Array = d.picks()
		var ours: Array = picks.filter(func(p: Prospect): return p.drafted_by == team)
		var top: Prospect = picks[0]
		cards.append(_stat_card("Draft Recap", str(ours.size()), "%d PICKS MADE" % d.year, "#1: [color=white]%s[/color] (%s)" % [UiKit.esc(top.soldier.short_name()), top.drafted_by.abbrev]
			+ ("\nYour first: %s" % UiKit.esc(ours[0].soldier.short_name()) if not ours.is_empty() else ""), UiKit.INFO, func(): open("Draft Recap", func(): return pages.draft_recap(d))))

	var nr := season.newsroom
	var la := nr.latest()
	cards.append(_stat_card("Weekly News", str(nr.count()), "ISSUES", ("[color=white]%s[/color]\n%s" % [UiKit.esc(String(la["headline"])), UiKit.esc(String(la["paper"]))]) if not la.is_empty()
		else "No issues yet", Color("#e2e8f0"), func(): open("News Archive", pages.news_archive), "NEW" if nr.unread() > 0 else ""))

	cards.append(_soon_card("Negotiation", "Back-and-forth contract talks", ["Back-and-forth contract talks", "Signing bonuses, incentives and options", "Agent personalities and holdouts"]))
	return _card_row("PersonnelMore", cards, 4)


## The Settings tab is a custom layout (see _tab_view): two rows of cards. No tile sections.
func _settings_sections() -> Array:
	return []


func _settings_view(v: VBoxContainer) -> void:
	var offseason := season.phase == Season.PHASE_OFFSEASON
	var used := 0
	for s in range(1, SaveSystem.SLOTS + 1):
		if SaveSystem.has_slot(s):
			used += 1
	var auto := SaveSystem.slot_info(SaveSystem.AUTO_SLOT)
	var latest := {}
	for s in range(0, SaveSystem.SLOTS + 1):
		var info := SaveSystem.slot_info(s)
		if not info.is_empty() and str(info.get("saved_at", "")) > str(latest.get("saved_at", "")):
			latest = info
	var sim := _stat_card("Sim Options", "OFF" if offseason else "W%d" % season.week, "SEASON %d" % season.year,
		"Sim a week, to the playoffs, or the whole season", UiKit.TRIM, func(): open("Sim Options", pages.sim_options))
	var save := _stat_card("Save Franchise", "%d/%d" % [used, SaveSystem.SLOTS], "SLOTS USED",
		("Autosave: [color=white]%s %s[/color]" % [auto.get("year", ""), auto.get("week", "")]) if not auto.is_empty() else "The autosave updates every week",
		UiKit.TRIM, func(): open("Save Franchise", func(): return pages.save_load(true)))
	var load_c := _stat_card("Load Franchise", str(used + (0 if auto.is_empty() else 1)), "SAVES",
		("Latest: [color=white]%s[/color] · %s %s" % [UiKit.esc(str(latest.get("label", "")) if str(latest.get("label", "")) != "" else "Slot %d" % int(latest.get("slot", 0))), latest.get("abbrev", ""), latest.get("week", "")]) if not latest.is_empty() else "No saves yet",
		UiKit.TRIM, func(): open("Load Franchise", func(): return pages.save_load(false)))
	var fs := _soon_card("Franchise Settings", "Difficulty, injuries, trade logic", ["Sim difficulty", "Injuries on/off and frequency", "Trade AI strictness", "Salary cap rules"])
	v.add_child(UiKit.heading("FRANCHISE", 22))
	v.add_child(_card_row("SettingsFranchise", [sim, save, load_c, fs], 4))
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	v.add_child(gap)
	var dbg := _stat_card("Debug Sim Tools", "M1", "SANDBOX", "Single matches, batch sims, raw ratings", UiKit.TRIM, app.open_debug)
	var menu := _stat_card("Main Menu", "◂", "TITLE", "Back to the title screen. Your franchise stays loaded", UiKit.TRIM, app.show_title)
	v.add_child(UiKit.heading("SYSTEM", 22))
	v.add_child(_card_row("SettingsSystem", [dbg, menu], 4))


func open_standings() -> void:
	open("Standings", pages.standings)


# --- tile text helpers -------------------------------------------------------------

## What the week card says when there is no match to show: {kicker, title, body, cta_text, cta, team}.
func _status_info(team: Team) -> Dictionary:
	var w := _shown_week()
	if home_week != 0:
		var info := {"kicker": season.week_label(w), "cta_text": "Scores & Schedule", "team": team,
			"cta": func(): open("Scores & Schedule", func(): return pages.scores(w))}
		if w <= season.regular_weeks:
			info.merge({"title": "Bye Week", "body": "No match in %s. The squad trains." % season.week_label(w)})
		elif season.matches_for_week(w).is_empty():
			info.merge({"title": "To Be Decided", "body": "%s matchups are set by earlier playoff results." % season.week_label(w)})
		else:
			info.merge({"title": "No Match", "body": "%s goes on without you." % season.week_label(w)})
		return info
	if season.phase == Season.PHASE_OFFSEASON:
		var champ := season.champion
		var next_step := ""
		var target := open_draft_room
		var cta := "Draft Room"
		match season.offseason_stage:
			Season.OFF_RESIGN:
				next_step = "Re-sign your expiring players and catch up on the awards and retirements, then advance to free agency."
				target = open_resign
				cta = "Re-sign Players"
			Season.OFF_FREE_AGENCY:
				next_step = "Free agency, day %d of %d: bid on soldiers before they sign elsewhere. The draft follows." % [season.fa_day, Season.FA_DAYS]
				target = open_free_agents
				cta = "Free Agents"
			Season.OFF_DRAFT:
				next_step = "Draft day is here: make your picks."
			Season.OFF_REVIEW:
				var over := -Contracts.cap_space(team, season.cap_year())
				next_step = "Roster review: undrafted prospects are in free agency. Make your cuts and moves%s, then advance to training camp." % (
					(" ([color=#ef4444]%s over the cap[/color])" % Contracts.money(over)) if over > 0 else "")
				target = open_contracts
				cta = "Contracts & Payroll"
			Season.OFF_CAMP:
				next_step = "Training camp: send one player to each drill ([color=#38bdf8]%d left[/color]), then start the season." % season.camp.drills_left(team)
				target = open_camp
				cta = "Training Camp"
			_:
				next_step = "Free agency is over. Week 1 needs exactly %d players (you have %d). Start the season when ready." % [Team.ROSTER_SIZE, team.roster.size()]
				target = open_contracts
				cta = "Contracts & Payroll"
		return {"kicker": "%d champions" % season.year, "title": champ.name if champ else "Season Complete", "team": champ if champ else team,
			"body": "The %d season is in the books.\n\n%s" % [season.year, next_step], "cta_text": cta, "cta": target}
	if season.preseason_camp:
		var first := season.next_match_for(team)
		var opener := ""
		if first != null:
			opener = "\n\nWeek 1: %s [color=white]%s[/color]" % ["vs" if first.home == team else "@", UiKit.esc(first.opponent_of(team).name)]
		return {"kicker": "Preseason", "title": "Training Camp", "team": team, "cta_text": "Training Camp", "cta": open_camp,
			"body": "The %d season starts after camp. Send one player to each drill ([color=#38bdf8]%d left[/color]), then start the season.%s" % [
				season.year, season.camp.drills_left(team), opener]}
	var m := season.next_match_for(team)
	if m == null:
		var playoffs := season.phase == Season.PHASE_PLAYOFFS
		return {"kicker": "Playoffs" if playoffs else "Season over", "title": "Eliminated" if playoffs else "Season Over", "team": team,
			"body": "The playoffs continue without you." if playoffs else "Your season is over.",
			"cta_text": "Playoff Picture", "cta": func(): open("Playoff Picture", pages.playoffs)}
	var opp := m.opponent_of(team)
	return {"kicker": season.week_label(season.week), "title": "Bye Week", "team": team, "cta_text": "Next Match Preview",
		"cta": func(): open("Match Preview", func(): return pages.preview(m)),
		"body": "No match this week. Your squad still trains.\n\nUp next: %s  %s %s[color=white]%s[/color]" % [
			season.week_label(m.week), "vs" if m.home == team else "@", UiKit.logo_bb(opp, 26), UiKit.esc(opp.name)]}


func _status_body(team: Team) -> Control:
	var info := _status_info(team)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var logo := UiKit.logo_disc(info["team"], 210)
	row.add_child(logo)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(UiKit.display(String(info["kicker"]).to_upper(), 22, UiKit.ACCENT))
	var title := UiKit.display(String(info["title"]).to_upper(), 60, Color.WHITE, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var body := UiKit.rich(info["body"], 19)
	body.add_theme_color_override("default_color", Color("#c3cad6"))
	col.add_child(body)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	col.add_child(gap)
	var cta := UiKit.button(info["cta_text"], info["cta"], 18)
	UiKit.style_skewed(cta, Color(0, 0, 0, 0.45))
	cta.custom_minimum_size.y = 44
	cta.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(cta)
	row.add_child(col)
	return row


func _advance_blurb() -> String:
	if season.phase == Season.PHASE_OFFSEASON:
		match season.offseason_stage:
			Season.OFF_RESIGN:
				return "Close the re-signing window. Unsigned expiring players hit free agency."
			Season.OFF_FREE_AGENCY:
				return "Players answer this round of offers. Best offer (money, team, playing time) wins." + (
					"\nThe draft follows." if season.fa_day >= Season.FA_DAYS else "")
			Season.OFF_DRAFT:
				return "Make your picks in the Draft Room." if not season.draft.is_complete() else "Undrafted prospects hit the market. Then a week to review your roster."
			Season.OFF_REVIEW:
				var err := season.user_cap_error()
				if err != "":
					return "[color=#ef4444]%s[/color]" % err
				return "Pending offers are answered, then training camp opens."
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

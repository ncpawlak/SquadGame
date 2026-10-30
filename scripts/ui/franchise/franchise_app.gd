extends Control
## Franchise mode root: title screen -> team select -> hub. Owns global input
## (WASD navigation, Q/E or LB/RB tab switching, Esc/B back) and the debug tools overlay.

const DEBUG_SCENE := preload("res://scenes/main.tscn")
const HubScript := preload("res://scripts/ui/franchise/hub.gd")

var season: Season
var screen: Control
var debug_layer: Control
var preview_seed := 0
var _toast: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	randomize()
	UiKit.install_fonts()
	theme = UiKit.theme()
	_free_space_key()
	show_title()


## Space is the franchise "advance week" key, so it must not also activate the focused button.
static func _free_space_key() -> void:
	for ev in InputMap.action_get_events(&"ui_accept"):
		if ev is InputEventKey and (ev.keycode == KEY_SPACE or ev.physical_keycode == KEY_SPACE):
			InputMap.action_erase_event(&"ui_accept", ev)


# --- screens ----------------------------------------------------------------

func _set_screen(c: Control) -> void:
	if screen:
		screen.queue_free()
	screen = c
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	if _toast:
		move_child(_toast, -1)
	focus_first.call_deferred(c)


func show_title() -> void:
	UiKit.reset_team()
	theme = UiKit.theme()
	var wrap := Control.new()
	var g := UiKit.gradient_rect(Color("#1a2640").darkened(0.3), UiKit.BG)
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(g)
	var root := CenterContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size.x = 440
	root.add_child(col)
	var title := UiKit.display("SQUAD LEAGUE", 96, Color.WHITE, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var bar := Panel.new()
	var bsb := UiKit.flat(UiKit.ACCENT, 1)
	bsb.skew = Vector2(UiKit.SKEW * 2.0, 0)
	bar.add_theme_stylebox_override("panel", bsb)
	bar.custom_minimum_size = Vector2(220, 5)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(bar)
	var sub := UiKit.display("FRANCHISE", 28, UiKit.ACCENT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(_spacer(24))
	if season:
		col.add_child(_menu_button("Resume Franchise", show_hub))
	col.add_child(_menu_button("New Franchise", show_team_select))
	col.add_child(_menu_button("Load Franchise", show_load_menu))
	col.add_child(_menu_button("Exhibition Match", func(): toast("Exhibition mode is coming soon. Use Debug Sim Tools for now.")))
	col.add_child(_menu_button("Debug Sim Tools", open_debug))
	if not OS.has_feature("web"):
		col.add_child(_menu_button("Quit", func(): get_tree().quit()))
	col.add_child(_spacer(16))
	var hint := UiKit.label("Arrows / WASD / D-pad to move  -  Enter / A to select", 14, UiKit.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var i := 0
	for c in col.get_children():
		UiKit.fade_in(c, 0.04 * i, 0.3)
		i += 1
	_set_screen(wrap)


func show_team_select() -> void:
	if preview_seed == 0:
		preview_seed = randi_range(1, 999999)
	var preview := Season.new_franchise(preview_seed, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	var margin := _margin(root, 22)

	var head := HBoxContainer.new()
	root.add_child(head)
	var back := UiKit.button("< Back", show_title, 18)
	UiKit.style_skewed(back)
	back.custom_minimum_size = Vector2(120, 48)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.set_meta(&"skip_autofocus", true)
	head.add_child(back)
	head.add_child(_spacer_w(16))
	var tt := VBoxContainer.new()
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tt.add_child(UiKit.display("CHOOSE YOUR TEAM", 44, Color.WHITE, true))
	var bar := ColorRect.new()
	bar.color = UiKit.ACCENT
	bar.custom_minimum_size = Vector2(90, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tt.add_child(bar)
	tt.add_child(UiKit.label("%d teams  -  %d divisions  -  %s season  -  hover a team for its scouting report, click to take over" % [
		preview.league.teams.size(), preview.divisions().size(), preview.year], 15, UiKit.MUTED))
	head.add_child(tt)

	var pane := PanelContainer.new()
	pane.custom_minimum_size.y = 250
	root.add_child(pane)

	var ranked := preview.league.teams.duplicate()
	ranked.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 18)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)
	var first: Button = null
	for d in preview.divisions():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 18)
		line.size_flags_vertical = Control.SIZE_EXPAND_FILL
		line.add_child(_division_badge(d))
		var div_teams: Array = preview.division_teams(d)
		div_teams.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
		for t: Team in div_teams:
			var idx := preview.league.teams.find(t)
			var rank := ranked.find(t) + 1
			var b := _team_tile(t, rank, ranked.size())
			var show := func(): _fill_team_pane(pane, preview, t, rank, ranked.size())
			b.mouse_entered.connect(show)
			b.focus_entered.connect(show)
			b.pressed.connect(func(): start_franchise(preview_seed, idx))
			line.add_child(b)
			if first == null:
				first = b
		grid.add_child(line)
	_fill_team_pane(pane, preview, ranked[0], 1, ranked.size())
	_set_screen(margin)


## Narrow division badge with the name stacked vertically ("E A S T").
func _division_badge(d: String) -> Control:
	var p := PanelContainer.new()
	var sb := UiKit.flat(UiKit.PANEL_HI, 4)
	sb.border_width_left = 4
	sb.border_color = UiKit.ACCENT
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.x = 52
	var l := UiKit.display("\n".join(d.to_upper().split("")), 17, UiKit.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("line_spacing", -6)
	p.add_child(l)
	return p


## A team-select tile: name, the logo on a dark disc inside a ring filled to the team OVR, the OVR and
## an expectation tag. Muted team tint at rest; full team colour on hover/focus.
func _team_tile(t: Team, rank: int, count: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	var acc := UiKit.accent_of(t)
	UiKit.style_button(b, UiKit.banner_of(t), acc, 6)
	var rest := UiKit.flat(UiKit.PANEL.lerp(UiKit.banner_of(t), 0.28), 6)
	rest.set_border_width_all(0)
	rest.border_width_bottom = 4
	rest.border_color = acc
	b.add_theme_stylebox_override("normal", rest)
	var hv := UiKit.flat(UiKit.banner_of(t), 6, 2, acc)
	hv.shadow_color = Color(acc, 0.35)
	hv.shadow_size = 10
	b.add_theme_stylebox_override("hover", hv)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var nm := UiKit.label(t.name, 18, Color.WHITE)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var o := t.team_ovr()
	# Three columns: OVR | ring (dead centre) | tag. The side columns share the width equally.
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", -6)
	var ovr := UiKit.display(str(o), 40, UiKit.ovr_color(o), true)
	ovr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovr.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	ovr.add_theme_constant_override("outline_size", 5)
	left.add_child(ovr)
	var cap := UiKit.display("OVR", 13, Color(1, 1, 1, 0.6), true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(cap)
	_ignore_mouse_tree(left)
	line.add_child(left)
	var ring := RingGauge.new(o, 100, UiKit.ovr_color(o), str(o), 104, 4.0)
	ring.logo = UiKit.logo_tex(t.abbrev)
	ring.disc = Color(0.02, 0.03, 0.06, 0.72)
	line.add_child(ring)
	var side := CenterContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag: Array = _expectation_tag(rank, count)
	var chip := PanelContainer.new()
	var csb := UiKit.flat(Color(0, 0, 0, 0.55), 3, 1, tag[1])
	csb.content_margin_left = 8
	csb.content_margin_right = 8
	csb.content_margin_top = 1
	csb.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", csb)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(UiKit.display(tag[0], 14, tag[1], true))
	side.add_child(chip)
	_ignore_mouse_tree(side)
	line.add_child(side)
	col.add_child(line)
	b.add_child(col)
	return b


## The big team-select pane: identity, OVR, backstory, average group ratings and the top 3 players.
func _fill_team_pane(pane: PanelContainer, preview: Season, t: Team, rank: int, count: int) -> void:
	for c in pane.get_children():
		c.queue_free()
	var sb := UiKit.flat(UiKit.PANEL, 4, 2, UiKit.accent_of(t))
	sb.set_content_margin_all(2)
	pane.add_theme_stylebox_override("panel", sb)
	pane.clip_contents = true
	# Dark on the left (behind the logo), team colour fading in toward the right.
	pane.add_child(UiKit.backdrop(UiKit.PANEL.darkened(0.35), UiKit.PANEL.lerp(UiKit.banner_of(t), 0.55), true, UiKit.accent_of(t)))
	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 22)
	pm.add_theme_constant_override("margin_right", 22)
	pm.add_theme_constant_override("margin_top", 16)
	pm.add_theme_constant_override("margin_bottom", 18)
	pane.add_child(pm)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	pm.add_child(hb)

	hb.add_child(UiKit.logo_disc(t, 210))

	# Identity column: name, OVR and expectations.
	var id_col := VBoxContainer.new()
	id_col.custom_minimum_size.x = 300
	id_col.add_theme_constant_override("separation", 4)
	hb.add_child(id_col)
	# City on one line, nickname on the next.
	var city := t.city
	var nick := t.nickname
	if city == "" or nick == "":
		var cut := t.name.rfind(" ")
		city = t.name.substr(0, cut) if cut > 0 else ""
		nick = t.name.substr(cut + 1) if cut > 0 else t.name
	if city != "":
		var cl := UiKit.display(city.to_upper(), 24, Color(1, 1, 1, 0.75), true)
		cl.add_theme_constant_override("line_spacing", -4)
		id_col.add_child(cl)
	var nm := UiKit.display(nick.to_upper(), 40, Color.WHITE, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	id_col.add_child(nm)
	id_col.add_child(UiKit.label("%s Division  ·  %s" % [t.division, LeagueData.state_name(t.home_state)], 15, Color(1, 1, 1, 0.7)))
	id_col.add_child(UiKit.rich("[font_size=46][color=%s]%d[/color][/font_size] OVR   [color=#8b97ab]preseason #%d of %d[/color]" % [
		UiKit.hex(UiKit.ovr_color(t.team_ovr())), t.team_ovr(), rank, count], 16))
	id_col.add_child(UiKit.market_meters(t, 13, 80))
	var space := Contracts.cap_space(t, preview.cap_year())
	id_col.add_child(UiKit.rich("Cap space [color=%s]%s[/color]   -   avg age [color=white]%.1f[/color]" % [
		"#22c55e" if space >= 0 else "#ef4444", Contracts.money(space), _avg_age(t)], 15))
	var et: Array = _expectation_tag(rank, count)
	id_col.add_child(UiKit.label(_expectation(rank, count), 16, et[1]))

	# Backstory + group ratings.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	hb.add_child(mid)
	var story := UiKit.label(t.backstory, 17, UiKit.TEXT)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Fixed 5-line box so hovering teams with longer stories doesn't resize the pane.
	story.custom_minimum_size.y = 24 * 5
	story.max_lines_visible = 5
	story.clip_text = true
	story.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	mid.add_child(story)
	mid.add_child(UiKit.label("STARTERS' AVERAGE GROUP RATINGS", 13, UiKit.MUTED))
	var groups := GridContainer.new()
	groups.columns = 2
	groups.add_theme_constant_override("h_separation", 24)
	groups.add_theme_constant_override("v_separation", 4)
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(groups)
	var starters := t.starters()
	for g in Stats.GROUP_ORDER:
		var total := 0
		for s in starters:
			total += s.group_rating(g)
		var avg := roundi(float(total) / maxi(1, starters.size()))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var gl := UiKit.label(Stats.GROUP_LABELS[g], 15, UiKit.TEXT)
		gl.custom_minimum_size.x = 104
		row.add_child(gl)
		var bar := ProgressBar.new()
		bar.min_value = 40
		bar.max_value = 99
		bar.value = avg
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(70, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", UiKit.flat(UiKit.LINE, 4))
		bar.add_theme_stylebox_override("fill", UiKit.flat(UiKit.ovr_color(avg), 4))
		row.add_child(bar)
		var vl := UiKit.label(str(avg), 16, UiKit.ovr_color(avg))
		vl.custom_minimum_size.x = 34
		row.add_child(vl)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		groups.add_child(row)

	# Top 3 players.
	var top_col := VBoxContainer.new()
	top_col.custom_minimum_size.x = 300
	top_col.add_theme_constant_override("separation", 6)
	hb.add_child(top_col)
	top_col.add_child(UiKit.label("TOP PLAYERS", 13, UiKit.MUTED))
	var best: Array = t.roster.duplicate()
	best.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	for s: Soldier in best.slice(0, 3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(Portrait.new(s, 58, t.color2, t))
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.add_child(UiKit.label(s.full_name(), 17, Color.WHITE))
		info.add_child(UiKit.rich("[color=%s]%d OVR[/color]  [color=#8b97ab]%s  -  age %d[/color]" % [
			UiKit.hex(UiKit.ovr_color(s.best_ovr())), s.best_ovr(), Scheme.ROLE_NAMES[Scheme.best_role(s.stats)], s.age], 14))
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		top_col.add_child(row)


func show_load_menu() -> void:
	var root := CenterContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	root.add_child(col)
	col.add_child(UiKit.label("LOAD FRANCHISE", 34, Color.WHITE))
	for slot in range(SaveSystem.AUTO_SLOT, SaveSystem.SLOTS + 1):
		col.add_child(FranchisePages.save_slot_tile(slot, false, self, show_load_menu))
	var back := UiKit.button("< Back", show_title)
	col.add_child(back)
	_set_screen(root)


func start_franchise(seed_value: int, team_index: int) -> void:
	season = Season.new_franchise(seed_value, team_index, 2026, true)
	preview_seed = 0
	show_hub()


func show_hub() -> void:
	var hub: Control = HubScript.new()
	hub.app = self
	hub.season = season
	_set_screen(hub)


func open_debug() -> void:
	if debug_layer:
		return
	debug_layer = Control.new()
	debug_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(debug_layer)
	var dbg: Control = DEBUG_SCENE.instantiate()
	debug_layer.add_child(dbg)
	var close := UiKit.button("Close Debug Tools (Esc)", close_debug, 14)
	close.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	close.position = Vector2(-260, -48)
	close.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	close.grow_vertical = Control.GROW_DIRECTION_BEGIN
	debug_layer.add_child(close)
	if screen:
		screen.visible = false


func close_debug() -> void:
	if not debug_layer:
		return
	debug_layer.queue_free()
	debug_layer = null
	if screen:
		screen.visible = true
		focus_first.call_deferred(screen)


## Small message at the bottom of the screen for laid-out-but-not-built features.
func toast(text: String) -> void:
	if _toast:
		_toast.queue_free()
	_toast = UiKit.panel(UiKit.PANEL_HI, 10)
	_toast.add_child(UiKit.label(text, 16, Color.WHITE))
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.position.y -= 70
	add_child(_toast)
	var t: WeakRef = weakref(_toast)
	get_tree().create_timer(2.5).timeout.connect(func():
		var node: Node = t.get_ref()
		if node != null:
			node.queue_free())


# --- input ------------------------------------------------------------------

const WASD := {KEY_W: &"ui_up", KEY_S: &"ui_down", KEY_A: &"ui_left", KEY_D: &"ui_right"}


## True while the mouse was the last input device. Focus rings (and the autofocus that keyboard and
## gamepad navigation need) stay hidden until a key or pad button is pressed.
static var mouse_mode := Input.get_connected_joypads().is_empty()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if not mouse_mode:
			mouse_mode = true
			_drop_focus()
		elif event is InputEventMouseButton and not event.pressed:
			# After the click is handled (a button needs focus to stay pressed until release).
			_drop_focus.call_deferred()
	elif mouse_mode and ((event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventJoypadButton and event.pressed)):
		mouse_mode = false
		var root: Node = screen.get_node_or_null("ConfirmModal") if screen else null
		if root == null:
			root = screen
		if root != null and get_viewport().gui_get_focus_owner() == null:
			focus_first(root)
		# The waking press only shows where focus is; it doesn't also move it.
		if event is InputEventKey and (WASD.has(event.keycode) or event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]):
			get_viewport().set_input_as_handled()


func _drop_focus() -> void:
	var o := get_viewport().gui_get_focus_owner()
	if o != null and not (o is LineEdit or o is TextEdit or o is SpinBox):
		o.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if debug_layer:
		if event.is_action_pressed(&"ui_cancel"):
			close_debug()
			accept_event()
		return
	if event is InputEventKey and event.pressed and WASD.has(event.keycode):
		_fire_action(WASD[event.keycode])
		accept_event()
	elif _is_key_or_button(event, KEY_Q, JOY_BUTTON_LEFT_SHOULDER):
		if screen and screen.has_method("cycle_tab"):
			screen.cycle_tab(-1)
		accept_event()
	elif _is_key_or_button(event, KEY_E, JOY_BUTTON_RIGHT_SHOULDER):
		if screen and screen.has_method("cycle_tab"):
			screen.cycle_tab(1)
		accept_event()
	elif event.is_action_pressed(&"ui_cancel") or _is_key_or_button(event, KEY_BACKSPACE, JOY_BUTTON_B):
		if screen and screen.has_method("go_back"):
			screen.go_back()
		accept_event()


func _is_key_or_button(event: InputEvent, key: Key, joy: JoyButton) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.keycode == key
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == joy
	return false


func _fire_action(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


static func focus_first(c: Node) -> void:
	if mouse_mode or not is_instance_valid(c):
		return
	var target := _find_focusable(c)
	if target:
		target.grab_focus()


static func _find_focusable(n: Node) -> Control:
	if _is_focusable(n):
		return n
	for ch in n.get_children():
		var f := _find_focusable(ch)
		if f:
			return f
	return null


static func _is_focusable(n: Node) -> bool:
	return n is Control and n.is_visible_in_tree() and n.focus_mode == Control.FOCUS_ALL \
			and not (n is BaseButton and n.disabled) and not n.has_meta(&"skip_autofocus")


## Every autofocus-eligible control under `n`, in tree order.
static func focusables(n: Node, out: Array[Control] = []) -> Array[Control]:
	if _is_focusable(n):
		out.append(n)
	for ch in n.get_children():
		focusables(ch, out)
	return out


# --- helpers ------------------------------------------------------------------

func _menu_button(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text, cb, 24)
	UiKit.style_skewed(b)
	b.custom_minimum_size = Vector2(440, 58)
	return b


func _margin(child: Control, m: int) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	mc.add_child(child)
	return mc


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


func _spacer_w(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = w
	return c


func _avg_age(t: Team) -> float:
	var total := 0
	for s in t.roster:
		total += s.age
	return float(total) / max(1, t.roster.size())


## Short tile tag and colour for a team's preseason rank.
func _expectation_tag(rank: int, count: int) -> Array:
	if rank <= 3:
		return ["TITLE FAVORITE", UiKit.GOLD]
	if rank <= 6:
		return ["CONTENDER", UiKit.GOOD]
	if rank <= Season.DIVISION_PLAYOFF_TEAMS:
		return ["PLAYOFF TEAM", Color("#38bdf8")]
	if rank <= count - 5:
		return ["BUBBLE", Color("#cbd5e1")]
	return ["REBUILD", Color("#fb923c")]


func _ignore_mouse_tree(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		if ch is Control:
			_ignore_mouse_tree(ch)


func _expectation(rank: int, count: int) -> String:
	if rank <= 3:
		return "Expectation: Win the title"
	if rank <= 6:
		return "Expectation: Contender"
	if rank <= Season.DIVISION_PLAYOFF_TEAMS:
		return "Expectation: Make the playoffs"
	if rank <= count - 5:
		return "Expectation: Fight for a playoff spot"
	return "Expectation: Rebuild"
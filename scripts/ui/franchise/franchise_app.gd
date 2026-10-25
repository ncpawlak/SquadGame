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
	var root := CenterContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size.x = 420
	root.add_child(col)
	var title := UiKit.label("SQUAD LEAGUE", 64, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UiKit.label("FRANCHISE", 22, UiKit.ACCENT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(_spacer(24))
	if season:
		col.add_child(_menu_button("Resume Franchise", show_hub))
	col.add_child(_menu_button("New Franchise", show_team_select))
	col.add_child(_menu_button("Load Franchise", func(): toast("Save / load is coming in a later milestone.")))
	col.add_child(_menu_button("Exhibition Match", func(): toast("Exhibition mode is coming soon. Use Debug Sim Tools for now.")))
	col.add_child(_menu_button("Debug Sim Tools", open_debug))
	if not OS.has_feature("web"):
		col.add_child(_menu_button("Quit", func(): get_tree().quit()))
	col.add_child(_spacer(16))
	var hint := UiKit.label("Arrows / WASD / D-pad to move  -  Enter / A to select", 14, UiKit.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	_set_screen(root)


func show_team_select() -> void:
	if preview_seed == 0:
		preview_seed = randi_range(1, 999999)
	var preview := Season.new_franchise(preview_seed, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	var margin := _margin(root, 48)

	var head := HBoxContainer.new()
	root.add_child(head)
	var back := UiKit.button("< Back", show_title)
	back.set_meta(&"skip_autofocus", true)
	head.add_child(back)
	head.add_child(_spacer_w(16))
	var tt := VBoxContainer.new()
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tt.add_child(UiKit.label("CHOOSE YOUR TEAM", 34, Color.WHITE))
	tt.add_child(UiKit.label("%s  -  %d teams  -  %s season  -  league seed %d" % [
		Season.DIVISION_NAME, preview.league.teams.size(), preview.year, preview_seed], 16, UiKit.MUTED))
	head.add_child(tt)
	var reroll := UiKit.button("Reroll League", func():
		preview_seed = randi_range(1, 999999)
		show_team_select())
	reroll.set_meta(&"skip_autofocus", true)
	head.add_child(reroll)

	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 18)
	row.add_theme_constant_override("v_separation", 18)
	scroll.add_child(row)
	var ranked := preview.league.teams.duplicate()
	ranked.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	for i in preview.league.teams.size():
		var t: Team = preview.league.teams[i]
		var star: Soldier = null
		for s in t.roster:
			if star == null or s.best_ovr() > star.best_ovr():
				star = s
		var rank := ranked.find(t) + 1
		var body := "[font_size=44][color=%s]%d[/color][/font_size] OVR\n\n" % [UiKit.hex(UiKit.ovr_color(t.team_ovr())), t.team_ovr()]
		body += "Preseason rank: [color=white]%s[/color]\n" % UiKit.ordinal(rank)
		body += "Star: [color=white]%s[/color] (%d)\n" % [UiKit.esc(star.full_name()), star.best_ovr()]
		body += "Avg age: [color=white]%.1f[/color]\n\n" % _avg_age(t)
		body += "[color=%s]%s[/color]" % [UiKit.hex(UiKit.ACCENT), _expectation(rank, ranked.size())]
		var idx := i
		var card := UiKit.tile(t.name, body, Vector2(280, 300), t.color, func(): start_franchise(preview_seed, idx))
		row.add_child(card)
	_set_screen(margin)


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
	if not is_instance_valid(c):
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
	var b := UiKit.button(text, cb, 22)
	b.custom_minimum_size = Vector2(420, 58)
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


func _expectation(rank: int, count: int) -> String:
	if rank == 1:
		return "Expectation: Win the title"
	if rank <= 2:
		return "Expectation: Contender"
	if rank <= Season.PLAYOFF_TEAMS - 1:
		return "Expectation: Make the playoffs"
	if rank < count:
		return "Expectation: Fight for a playoff spot"
	return "Expectation: Rebuild"

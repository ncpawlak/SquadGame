class_name HelpPopup
extends Control
## The Help overlay: a topic list on the left and the stashed explanatory copy (HelpText) on the right.
## Opened from the "?" tab-bar button or F1; Esc / B / clicking outside closes it.

## [label, key prefixes] per topic.
const TOPICS := [
	["Controls", ["global."]],
	["Home and Weekly Flow", ["hub.", "career.", "training.", "progression."]],
	["Team and Roster", ["team.", "scouting."]],
	["Personnel", ["personnel.", "franchise_pages.", "fantasy_draft_pages."]],
	["League", ["league.", "legacy_pages.", "stats_pages.", "story_pages."]],
	["Club", ["club.", "club_pages."]],
	["Player Career", ["player_pages.", "player_plan_pages.", "player_gear_pages.", "player_create.", "combine_screen.", "player_draft_pages.", "player_warmup_pages.", "player_request_pages."]],
]

var _body: VBoxContainer


## Shows the popup on `host`, opened on the topic that matches `tab_hint` (a prefix like "team.").
static func open(host: Control, tab_hint := "global.") -> void:
	var existing := host.get_node_or_null("HelpPopup")
	if existing:
		existing.queue_free()
		return
	var p := HelpPopup.new()
	p.name = "HelpPopup"
	host.add_child(p)
	p._build(tab_hint)


func _build(tab_hint: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_parent_area_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1120, 640)
	panel.add_theme_stylebox_override("panel", UiKit.flat(Color(0.05, 0.06, 0.09, 0.98), 12, 1, Color(UiKit.ACCENT, 0.6)))
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(m)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	m.add_child(root)
	var head := HBoxContainer.new()
	head.add_child(UiKit.display("HELP", 34, Color.WHITE, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UiKit.button("Close  (Esc)", func(): queue_free(), 18)
	head.add_child(close)
	root.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 280
	list.add_theme_constant_override("separation", 4)
	cols.add_child(list)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(sc)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	var buttons: Array = []
	var start := 0
	for i in TOPICS.size():
		var idx := i
		var b := Button.new()
		b.text = String(TOPICS[i][0]).to_upper()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(func():
			_show(idx)
			for j in buttons.size():
				UiKit.style_tab(buttons[j], j == idx, 18))
		list.add_child(b)
		buttons.append(b)
		for pre: String in TOPICS[i][1]:
			if tab_hint.begins_with(pre) or pre.begins_with(tab_hint):
				start = i
	_show(start)
	for j in buttons.size():
		UiKit.style_tab(buttons[j], j == start, 18)


func _show(topic: int) -> void:
	for c in _body.get_children():
		c.queue_free()
	var any := false
	for pre: String in TOPICS[topic][1]:
		for t in HelpText.for_screen(pre):
			var txt := String(t)
			if txt.length() < 25 or _is_dev_note(txt):
				continue
			any = true
			var r := UiKit.rich(txt, 17)
			r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_body.add_child(r)
	if not any:
		_body.add_child(FrontEnd.empty_note("Nothing to explain here yet."))


## The stash also holds format templates and developer notes; only player-facing prose belongs in Help.
static func _is_dev_note(t: String) -> bool:
	for bad in ["%", "()", "COMING SOON", "stashed", "_help", "tooltip", "Per-row"]:
		if t.contains(bad):
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_F1):
		queue_free()
		get_viewport().set_input_as_handled()

class_name ModeScreen
extends Control
## What Career or Franchise opens: the mode's identity and its text actions (Continue, New) on the left; the last
## played preview and every save slot on the right. Slots load straight from here.

var app: Control
var mode := "career"

var _accent := FrontEnd.CAREER


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var career := mode == "career"
	_accent = FrontEnd.CAREER if career else FrontEnd.FRANCHISE
	var info := FrontEnd.mode_info(app, mode)
	var has_save: bool = int(info["slot"]) != -2
	add_child(FrontEnd.Scene.new())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 96)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 70)
	margin.add_child(root)

	# --- left: identity + actions -----------------------------------------------------------
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 600
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	var back := MenuText.new("< Back", 26, UiKit.MUTED, "", 160)
	back.rest_alpha = 0.55
	back.pressed.connect(app.show_title)
	back.set_meta(&"skip_autofocus", true)
	left.add_child(back)
	var gap := Control.new()
	gap.custom_minimum_size.y = 28
	left.add_child(gap)
	left.add_child(UiKit.display("LIVE THE CAREER" if career else "RUN THE CLUB", 22, _accent))
	left.add_child(UiKit.display("CAREER" if career else "FRANCHISE", 104, Color.WHITE, true))
	var tag := UiKit.label(
		"One soldier, from the combine to the Hall of Fame. Earn your spot, grow your ratings, build a legend." if career
		else "Take over one of 20 teams. Roster, cap, draft and a dynasty to build, season after season.", 19, Color("#b4bfd0"))
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size.x = 520
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(tag)
	var pad := Control.new()
	pad.custom_minimum_size.y = 8
	left.add_child(pad)
	left.add_child(FrontEnd.chips(["COMBINE", "DRAFT", "TRAINING", "HALL OF FAME"] if career else ["ROSTER", "CAP", "DRAFT", "TRADES", "SCOUTING"], _accent, 520))
	var grow := Control.new()
	grow.custom_minimum_size.y = 56
	left.add_child(grow)

	var cont := MenuText.new("Continue", 54, _accent, String(info["label"]) if has_save else "No save yet", 600)
	cont.disabled = not has_save
	cont.pressed.connect(func(): _continue(int(info["slot"])))
	left.add_child(cont)
	var create := MenuText.new("New Career" if career else "New Franchise", 54, _accent, "Create a soldier" if career else "Pick a team", 600)
	create.pressed.connect(app.show_player_create if career else app.show_team_select)
	left.add_child(create)
	var hints := FrontEnd.footer([["Arrows / WASD / D-pad", "Move"], ["Enter / A", "Select"], ["Esc / B", "Back"]])
	var hp := Control.new()
	hp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(hp)
	left.add_child(hints)
	if has_save:
		create.set_meta(&"skip_autofocus", true)

	# --- right: last played + slots ---------------------------------------------------------
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	root.add_child(right)
	var top := Control.new()
	top.custom_minimum_size.y = 40
	right.add_child(top)
	right.add_child(_last_played(info, career))
	var sp2 := Control.new()
	sp2.custom_minimum_size.y = 14
	right.add_child(sp2)
	var head := UiKit.display("SAVE SLOTS", 22, UiKit.MUTED)
	right.add_child(head)
	for slot in range(SaveSystem.AUTO_SLOT, SaveSystem.SLOTS + 1):
		var h := SaveSystem.slot_info(slot)
		if not h.is_empty() and String(h.get("mode", "franchise")) != mode:
			continue
		right.add_child(_slot_row(slot, h))

	UiKit.fade_in(root, 0.0, 0.3)


func _continue(slot: int) -> void:
	if slot == -1:
		app.show_hub()
	elif slot >= 0:
		app.load_franchise(slot)


## Circular preview (soldier or crest) beside the newest save's headline.
func _last_played(info: Dictionary, career: bool) -> Control:
	var has_save: bool = int(info["slot"]) != -2
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var abbrev := String(info["abbrev"]) if has_save else FrontEnd.daily_team()
	var art: Control
	if career:
		art = FrontEnd.disc_art(_accent, FrontEnd.head_texture(), 210, true)
	else:
		art = FrontEnd.disc_art(FrontEnd.team_accent(abbrev), UiKit.logo_tex(abbrev), 210, false)
	row.add_child(art)
	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(UiKit.display("LAST PLAYED" if has_save else "NO SAVE YET", 18, _accent))
	var big := UiKit.display(String(info["title"]) if has_save else ("Your career starts here" if career else "Your franchise starts here"), 40, Color.WHITE, true)
	big.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	big.custom_minimum_size.x = 380
	col.add_child(big)
	if has_save:
		var sub := String(info["when"])
		if career and String(info["title"]) != String(info["team"]):
			sub = String(info["team"]) + "  ·  " + sub
		col.add_child(UiKit.label(sub, 17, Color("#b4bfd0")))
	return row


## One save slot: crest, headline, details, slot name and save time. Empty slots are dim and inert.
func _slot_row(slot: int, h: Dictionary) -> Control:
	var empty := h.is_empty()
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 86)
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = empty
	var mk := func(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
		return UiKit.flat(bg, 12, bw, border)
	b.add_theme_stylebox_override("normal", mk.call(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.07), 1))
	var hv: StyleBoxFlat = mk.call(Color(_accent, 0.16), _accent, 2)
	hv.shadow_color = Color(_accent, 0.3)
	hv.shadow_size = 10
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("focus", hv)
	b.add_theme_stylebox_override("pressed", mk.call(Color(_accent, 0.25), Color.WHITE, 2))
	b.add_theme_stylebox_override("disabled", mk.call(Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.05), 1))
	if not empty:
		b.pressed.connect(func(): app.load_franchise(slot))
		b.mouse_entered.connect(func(): b.grab_focus())

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_right = -20
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var slot_name := "AUTOSAVE" if slot == SaveSystem.AUTO_SLOT else "SLOT %d" % slot
	if empty:
		row.modulate = Color(1, 1, 1, 0.5)
		row.add_child(UiKit.display(slot_name, 22, UiKit.MUTED))
		var e := UiKit.label("Empty slot", 16, UiKit.MUTED)
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(e)
		return b
	var tex := UiKit.logo_tex(String(h.get("abbrev", "")))
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(54, 54)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)
	var who := String(h.get("player", "")) if mode == "career" and String(h.get("player", "")) != "" else String(h.get("team", ""))
	var t := UiKit.display(who, 26, Color.WHITE)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(t)
	var detail := "%s season  ·  %s" % [str(h.get("year", "?")), String(h.get("week", ""))]
	if mode == "career" and who != String(h.get("team", "")):
		detail = String(h.get("team", "")) + "  ·  " + detail
	mid.add_child(UiKit.label(detail, 16, Color("#b4bfd0")))
	var side := VBoxContainer.new()
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	side.add_theme_constant_override("separation", 2)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(side)
	var sn := UiKit.display(slot_name, 20, _accent)
	sn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(sn)
	var when := UiKit.label(String(h.get("saved_at", "")).replace("T", " ").left(16), 14, UiKit.MUTED)
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(when)
	return b


## Esc / B from the app's global input.
func go_back() -> bool:
	app.show_title()
	return true

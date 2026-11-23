class_name HomeScreen
extends Control
## The game's front door: a text-only menu down the left (Exhibition Match, Career, Franchise, Settings) over a
## drifting crest-wall backdrop. Whatever is highlighted (hover, thumbstick, D-pad) swaps the preview on the right.
## Career and Franchise open their own mode screen (ModeScreen); Settings opens SettingsScreen.

var app: Control

var _items: Array = []  # [{button, preview}]
var _shown := -1
var _preferred := 1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(FrontEnd.Scene.new())
	var career := FrontEnd.mode_info(app, "career")
	var franchise := FrontEnd.mode_info(app, "franchise")

	# Previews live on the right half; one is visible at a time.
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.anchor_left = 0.5
	stage.offset_left = 0
	stage.offset_right = -90
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 96)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	margin.add_child(col)
	col.add_child(FrontEnd.wordmark(46))
	var tagline := UiKit.label("CAREER  ·  FRANCHISE  ·  EXHIBITION", 15, UiKit.MUTED)
	tagline.custom_minimum_size.x = 400
	col.add_child(tagline)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grow)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 6)
	col.add_child(menu)
	var defs := [
		["Exhibition Match", FrontEnd.FRANCHISE, _preview_exhibition(), func(): app.toast("Exhibition mode is coming soon. Use Debug Sim Tools in Settings for now.")],
		["Career", FrontEnd.CAREER, _preview_mode("career", career), app.show_mode.bind("career")],
		["Franchise", FrontEnd.FRANCHISE, _preview_mode("franchise", franchise), app.show_mode.bind("franchise")],
		["Settings", FrontEnd.FRANCHISE, _preview_settings(), app.show_settings],
	]
	for d in defs:
		var b := MenuText.new(d[0], 64, d[1], "", 560)
		if d[0] == "Exhibition Match":
			b.set_value("SOON", 20)
		b.pressed.connect(d[3])
		menu.add_child(b)
		var pv: Control = d[2]
		pv.visible = false
		stage.add_child(pv)
		_items.append({"button": b, "preview": pv})
		b.focus_entered.connect(_show.bind(_items.size() - 1))

	var grow2 := Control.new()
	grow2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grow2)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 30)
	col.add_child(bottom)
	if not OS.has_feature("web"):
		var quit := MenuText.new("Quit", 26, UiKit.MUTED, "", 140)
		quit.rest_alpha = 0.45
		quit.pressed.connect(func(): get_tree().quit())
		quit.set_meta(&"skip_autofocus", true)
		bottom.add_child(quit)
	var hints := FrontEnd.footer([["Arrows / WASD / D-pad", "Move"], ["Enter / A", "Select"]])
	hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(hints)

	# The mode you last played takes the initial focus.
	var f_running: bool = int(franchise["slot"]) == -1
	var c_running: bool = int(career["slot"]) == -1
	var newer: bool = String(franchise["saved_at"]) > String(career["saved_at"])
	_preferred = 2 if (f_running or (not c_running and newer) or int(career["slot"]) == -2) else 1
	for i in _items.size():
		if i != _preferred:
			_items[i]["button"].set_meta(&"skip_autofocus", true)
	_show(_preferred)
	UiKit.fade_in(col, 0.0, 0.35)


## Fade the right-hand preview for menu item `i` in and the others out.
func _show(i: int) -> void:
	if i == _shown:
		return
	_shown = i
	for k in _items.size():
		var pv: Control = _items[k]["preview"]
		if k == i:
			pv.visible = true
			if Fx.is_reduced():
				pv.modulate.a = 1.0
			else:
				pv.modulate.a = 0.0
				pv.create_tween().tween_property(pv, "modulate:a", 1.0, 0.25)
		else:
			pv.visible = false


# --- previews ---------------------------------------------------------------------------------

func _stage(art: Control, eyebrow: String, headline: String, body: String, chip_items: Array, accent: Color, status: String) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 520
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(art)
	var pad := Control.new()
	pad.custom_minimum_size.y = 14
	col.add_child(pad)
	col.add_child(UiKit.display(eyebrow, 20, accent))
	col.add_child(UiKit.display(headline, 54, Color.WHITE, true))
	var t := UiKit.label(body, 19, Color("#b4bfd0"))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 500
	col.add_child(t)
	if not chip_items.is_empty():
		col.add_child(FrontEnd.chips(chip_items, accent, 500))
	if status != "":
		var s := UiKit.display(status, 22, accent.lightened(0.25))
		s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		s.custom_minimum_size.x = 500
		col.add_child(s)
	return center


func _preview_mode(mode: String, info: Dictionary) -> Control:
	var has_save: bool = int(info["slot"]) != -2
	if mode == "career":
		var art := FrontEnd.disc_art(FrontEnd.CAREER, FrontEnd.head_texture(), 300, true)
		return _stage(art, "LIVE THE CAREER", "One soldier. One legend.",
			"From the combine to the Hall of Fame. Earn your spot, grow your ratings and write your own story.",
			["COMBINE", "DRAFT", "TRAINING", "HALL OF FAME"], FrontEnd.CAREER,
			("CONTINUE  ·  " + String(info["label"])) if has_save else "No career yet. Start your first.")
	var abbrev := String(info["abbrev"]) if has_save else FrontEnd.daily_team()
	var crest := FrontEnd.team_accent(abbrev)
	var art2 := FrontEnd.disc_art(crest, UiKit.logo_tex(abbrev), 300, false)
	return _stage(art2, "RUN THE CLUB", "Build a dynasty.",
		"Take over one of 20 teams. Manage the roster, the cap, the draft and the trade market, season after season.",
		["ROSTER", "CAP", "DRAFT", "TRADES", "SCOUTING"], FrontEnd.FRANCHISE,
		("CONTINUE  ·  " + String(info["label"])) if has_save else "No franchise yet. Pick a team.")


func _preview_exhibition() -> Control:
	var a := FrontEnd.daily_team()
	var b := "NYE" if a != "NYE" else "BOS"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -40)
	row.add_child(FrontEnd.disc_art(FrontEnd.team_accent(a), UiKit.logo_tex(a), 200, false))
	row.add_child(FrontEnd.disc_art(FrontEnd.team_accent(b), UiKit.logo_tex(b), 200, false))
	return _stage(row, "QUICK MATCH", "Pick two squads.",
		"Jump straight into a single match between any two teams. No season, no commitments.",
		["COMING SOON"], FrontEnd.FRANCHISE, "")


func _preview_settings() -> Control:
	var disc := PanelContainer.new()
	var sb := UiKit.flat(Color(FrontEnd.FRANCHISE.darkened(0.7), 0.9), 300, 3, FrontEnd.FRANCHISE)
	sb.shadow_color = Color(FrontEnd.FRANCHISE, 0.35)
	sb.shadow_size = 30
	sb.set_content_margin_all(70)
	disc.add_theme_stylebox_override("panel", sb)
	disc.custom_minimum_size = Vector2(300, 300)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bars := VBoxContainer.new()
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	bars.add_theme_constant_override("separation", 22)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for fill in [0.7, 0.35, 0.55]:
		var track := Panel.new()
		track.add_theme_stylebox_override("panel", UiKit.flat(Color(1, 1, 1, 0.14), 6))
		track.custom_minimum_size = Vector2(0, 12)
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var on := Panel.new()
		on.add_theme_stylebox_override("panel", UiKit.flat(FrontEnd.FRANCHISE, 6))
		on.set_anchors_preset(Control.PRESET_FULL_RECT)
		on.anchor_right = fill
		on.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(on)
		bars.add_child(track)
	disc.add_child(bars)
	return _stage(disc, "YOUR GAME, YOUR WAY", "Settings.",
		"Trade difficulty, animations and the developer tools.", [], FrontEnd.FRANCHISE, "")

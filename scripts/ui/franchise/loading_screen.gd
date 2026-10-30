class_name LoadingScreen
extends Control
## Full-screen loading screen for blocking work (week sims, new season, new franchise, loading a
## save): the user's team colours and logo, a title, a progress bar and a line saying what is
## being worked on. Opaque and input-blocking; callers hide what's behind it so focus can't wander.
##
##   var ls := LoadingScreen.make(team, "WEEK 5")
##   add_child(ls)
##   await ls.step("Playing ARL vs BOS", 3, 9)

var _title: Label
var _reason: Label
var _count: Label
var _bar: ProgressBar


## `team` sets the colours and logo (null = neutral gold); `abbrev` picks a logo when the team
## isn't loaded yet (loading a save).
static func make(team: Team, title: String, abbrev := "") -> LoadingScreen:
	var ls := LoadingScreen.new()
	ls._build(team, title, abbrev)
	return ls


func _build(team: Team, title: String, abbrev: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var accent := UiKit.accent_of(team) if team else UiKit.GOLD
	var banner := UiKit.banner_of(team) if team else UiKit.PANEL_HI
	var bg := UiKit.backdrop(banner.darkened(0.35), UiKit.BG, true, accent)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)

	var logo: Control = null
	if team:
		logo = UiKit.logo_disc(team, 220)
	elif abbrev != "" and UiKit.logo_tex(abbrev) != null:
		logo = _abbrev_disc(abbrev, 220, accent)
	if logo:
		v.add_child(logo)
		UiKit.pulse(logo, 0.75, 1.6)

	_title = UiKit.display(title.to_upper(), 44, Color.WHITE, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(560, 22)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.add_theme_stylebox_override("background", UiKit.flat(Color(0, 0, 0, 0.5), 6, 1, Color(accent, 0.4)))
	_bar.add_theme_stylebox_override("fill", UiKit.flat(accent, 6))
	v.add_child(_bar)

	var line := HBoxContainer.new()
	line.custom_minimum_size.x = 560
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(line)
	_reason = UiKit.label("", 18, UiKit.TEXT)
	_reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reason.clip_text = true
	line.add_child(_reason)
	_count = UiKit.label("", 16, UiKit.MUTED)
	line.add_child(_count)


func _abbrev_disc(abbrev: String, size: int, accent: Color) -> Control:
	var p := PanelContainer.new()
	var sb := UiKit.flat(Color(0.02, 0.03, 0.06, 0.85), size, maxi(2, size / 50), accent)
	var inner := int(size * 0.76)
	sb.set_content_margin_all((size - inner) / 2.0)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := TextureRect.new()
	r.texture = UiKit.logo_tex(abbrev)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(inner, inner)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(r)
	return p


## Show what's being worked on and how far along (`done` of `total` finished), then wait two
## frames so it draws before the caller's next blocking chunk.
func step(reason: String, done: float, total: float) -> void:
	_reason.text = reason
	_bar.max_value = maxf(total, 0.001)
	_bar.value = done
	_count.text = "%d%%" % roundi(100.0 * clampf(done / _bar.max_value, 0.0, 1.0))
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame

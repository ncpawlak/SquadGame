class_name UiKit
extends RefCounted
## Shared look for the franchise menus: palette, styleboxes, tiles, tables.
## Everything is built in code so it works the same in the editor, desktop and web.

const BG := Color("#070b14")
const PANEL := Color("#101827")
const PANEL_HI := Color("#1a2640")
const LINE := Color("#243049")
const ACCENT := Color("#f59e0b")
const TEXT := Color("#e5e7eb")
const MUTED := Color("#8b97ab")
const GOOD := Color("#22c55e")
const BAD := Color("#ef4444")
const INFO := Color("#38bdf8")


static func flat(color: Color, radius := 8, border := 0, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func rich(text: String, size := 16) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = text
	return r


static func panel(color := PANEL, radius := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(color, radius))
	return p


## Apply the standard focus/hover look to any button. Focus gets a bright accent border so
## keyboard/controller users always know where they are.
static func style_button(b: Button, base := PANEL_HI, accent := ACCENT, radius := 8) -> void:
	b.add_theme_stylebox_override("normal", flat(base, radius, 2, LINE))
	b.add_theme_stylebox_override("hover", flat(base.lightened(0.08), radius, 2, accent.darkened(0.3)))
	b.add_theme_stylebox_override("pressed", flat(base.darkened(0.15), radius, 2, accent))
	b.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT, radius, 3, accent))
	b.add_theme_stylebox_override("disabled", flat(base.darkened(0.3), radius, 2, LINE))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.focus_mode = Control.FOCUS_ALL


static func button(text: String, cb: Callable, size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	style_button(b)
	b.pressed.connect(cb)
	return b


## Madden-style menu tile: accent strip on top, title, subtitle and an optional badge
## ("SOON" for laid-out-but-not-built features).
static func tile(title: String, subtitle: String, size: Vector2, accent: Color, cb: Callable, badge := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.clip_contents = true
	style_button(b, PANEL, accent, 12)
	b.pressed.connect(cb)

	var strip := ColorRect.new()
	strip.color = accent
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = 5
	b.add_child(strip)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_right = -18
	box.offset_top = 18
	box.offset_bottom = -14
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	b.add_child(box)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var t := label(title.to_upper(), 20 if size.y >= 180 else 17)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if badge != "":
		var bp := PanelContainer.new()
		var bs := flat(LINE, 6)
		bs.content_margin_top = 2
		bs.content_margin_bottom = 2
		bs.content_margin_left = 8
		bs.content_margin_right = 8
		bp.add_theme_stylebox_override("panel", bs)
		bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bp.add_child(label(badge, 12, MUTED))
		head.add_child(bp)

	var sub := rich(subtitle, 15 if size.y < 180 else 17)
	sub.add_theme_color_override("default_color", MUTED)
	sub.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sub)
	return b


## Table: header row + one focusable button per data row (so keyboard/controller can scroll
## through it and select rows). highlight_rows: row index -> bg colour.
## cell_colors: row index -> {col index -> colour}. on_row: optional Callable(row_index).
static func table(headers: Array, rows: Array, col_widths: Array, highlight_rows := {}, cell_colors := {},
		on_row := Callable()) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var width := 28
	for w in col_widths:
		width += int(w) + 10
	var header := PanelContainer.new()
	var hsb := flat(PANEL_HI, 4)
	hsb.content_margin_top = 6
	hsb.content_margin_bottom = 6
	header.add_theme_stylebox_override("panel", hsb)
	header.custom_minimum_size.x = width
	header.add_child(_cells(headers, col_widths, MUTED, 14))
	v.add_child(header)
	for i in rows.size():
		var bg: Color = highlight_rows.get(i, PANEL if i % 2 == 0 else PANEL.lightened(0.035))
		var b := Button.new()
		style_button(b, bg, ACCENT, 4)
		b.custom_minimum_size = Vector2(width, 36)
		var hb := _cells(rows[i], col_widths, TEXT, 16)
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 14
		hb.offset_right = -14
		b.add_child(hb)
		if cell_colors.has(i):
			var colors: Dictionary = cell_colors[i]
			for col in colors:
				var l := hb.get_child(col) as Label
				if l != null:
					l.add_theme_color_override("font_color", colors[col])
		if on_row.is_valid():
			var idx := i
			b.pressed.connect(func(): on_row.call(idx))
		v.add_child(b)
	return v


static func _cells(cells: Array, col_widths: Array, color: Color, size: int) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in cells.size():
		if cells[c] is Team:
			# Team cell: small logo + name.
			var t: Team = cells[c]
			var th := HBoxContainer.new()
			th.add_theme_constant_override("separation", 6)
			th.custom_minimum_size.x = col_widths[c] if c < col_widths.size() else 60
			th.clip_contents = true
			th.mouse_filter = Control.MOUSE_FILTER_IGNORE
			th.add_child(team_logo(t, size + 10))
			var tl := label(t.name if th.custom_minimum_size.x >= 140 else t.abbrev, size, color)
			tl.clip_text = true
			tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			th.add_child(tl)
			hb.add_child(th)
			continue
		var l := label(str(cells[c]), size, color)
		l.custom_minimum_size.x = col_widths[c] if c < col_widths.size() else 60
		l.clip_text = true
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_FILL
		if c > 1:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(l)
	return hb


static func ovr_color(v: int) -> Color:
	if v >= 82:
		return Color("#22c55e")
	if v >= 72:
		return Color("#84cc16")
	if v >= 62:
		return Color("#eab308")
	if v >= 52:
		return Color("#f97316")
	return Color("#ef4444")


static func esc(s: String) -> String:
	return s.replace("[", "[lb]")


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


static var _logos := {}


## Team logo texture (assets/logos/<ABBR>.png), or null when the team has none.
static func logo_tex(abbrev: String) -> Texture2D:
	if not _logos.has(abbrev):
		var path := "res://assets/logos/%s.png" % abbrev
		_logos[abbrev] = load(path) if ResourceLoader.exists(path) else null
	return _logos[abbrev]


## Inline logo for rich text ("" when the team has none).
static func logo_bb(team: Team, size := 22) -> String:
	if team == null or logo_tex(team.abbrev) == null:
		return ""
	return "[img=%dx%d]res://assets/logos/%s.png[/img] " % [size, size, team.abbrev]


## Square team logo; falls back to the coloured chip when the team has no logo.
static func team_logo(team: Team, size := 48) -> Control:
	var tex := logo_tex(team.abbrev)
	if tex == null:
		return team_chip(team, maxi(12, size / 3), false)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Logo followed by the coloured abbreviation chip.
static func team_badge(team: Team, size := 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(team_logo(team, int(size * 1.9)))
	h.add_child(team_chip(team, size, false))
	return h


## Coloured team chip: abbreviation on the team colour (with a small logo in front by default).
static func team_chip(team: Team, size := 16, with_logo := true) -> Control:
	if with_logo and logo_tex(team.abbrev) != null:
		return team_badge(team, size)
	var p := PanelContainer.new()
	var sb := flat(team.color.darkened(0.25), 6)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label(team.abbrev, size, Color.WHITE))
	return p

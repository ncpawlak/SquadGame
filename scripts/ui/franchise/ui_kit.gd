class_name UiKit
extends RefCounted
## Shared look for the franchise menus: palette, fonts, styleboxes, tiles, tables and motion.
## Sports-broadcast style: condensed display type, slanted "score bug" buttons and banners, and
## an accent colour taken from the user's team (set_team). Everything is built in code so it
## works the same in the editor, desktop and web.

const BG := Color("#070b14")
const PANEL := Color("#101827")
const PANEL_HI := Color("#1a2640")
const LINE := Color("#243049")
const TEXT := Color("#e5e7eb")
const MUTED := Color("#8b97ab")
const GOOD := Color("#22c55e")
const BAD := Color("#ef4444")
const INFO := Color("#38bdf8")
## The league-default accent (used before a team is picked, and for grey/white teams).
const GOLD := Color("#f59e0b")
const SKEW := 0.22

## Accent colour: a bright version of the user's team colour (see set_team).
static var ACCENT := GOLD
## Row background for the user's own team / players in league-wide tables (tables also give it an accent border).
static var MINE := Color("#3d2c08")
## Deep version of the user's team colour for banners and backdrops.
static var TEAM_DARK := Color("#1a2640")

static var font_body: Font
static var font_bold: Font
static var font_display: Font
static var font_heavy: Font
static var _theme: Theme


# --- team colours ----------------------------------------------------------------

## Re-theme the UI to a team: accent, "mine" rows and banners. Call theme() again afterwards.
static func set_team(t: Team) -> void:
	if t == null:
		return
	var a := accent_of(t)
	var banner := banner_of(t)
	if a == ACCENT and banner == TEAM_DARK and _theme != null:
		return
	ACCENT = a
	MINE = Color.from_hsv(a.h, clampf(a.s, 0.5, 0.9), 0.24)
	TEAM_DARK = banner
	_theme = null


## Back to the neutral gold look (title screen, team select).
static func reset_team() -> void:
	if ACCENT == GOLD and _theme != null:
		return
	ACCENT = GOLD
	MINE = Color("#3d2c08")
	TEAM_DARK = Color("#1a2640")
	_theme = null


## A bright, readable version of the more vivid of a team's two colours.
static func accent_of(t: Team) -> Color:
	var best: Color = t.color
	var score := -1.0
	for c in [t.color, t.color2]:
		var sc: float = c.s * (0.35 + c.v)
		if sc > score:
			score = sc
			best = c
	if best.s < 0.12:
		return GOLD
	return Color.from_hsv(best.h, clampf(best.s, 0.5, 0.95), clampf(best.v, 0.82, 1.0))


## A deep, saturated team colour for banners (white or near-black primaries fall back).
static func banner_of(t: Team) -> Color:
	for c in [t.color, t.color2]:
		if c.v > 0.18 and c.v < 0.8 and c.s > 0.15:
			return Color.from_hsv(c.h, minf(c.s, 0.85), clampf(c.v, 0.32, 0.5))
	var a := accent_of(t)
	return Color.from_hsv(a.h, a.s * 0.85, 0.38)


# --- fonts & theme ----------------------------------------------------------------

## Barlow (body) and Barlow Condensed (display) with the built-in font and DejaVu Sans chained
## in as glyph fallbacks (series pips, sort arrows, stars) - web builds have no system fonts.
static func install_fonts() -> void:
	if font_body != null:
		return
	var fb: Array[Font] = []
	var base := ThemeDB.fallback_font
	if base != null:
		fb.append(base)
	var sym: Font = load("res://assets/fonts/DejaVuSans.ttf")
	if sym != null:
		fb.append(sym)
	font_body = _font("Barlow-Medium", fb, base)
	font_bold = _font("Barlow-Bold", fb, font_body)
	font_display = _font("BarlowCondensed-Bold", fb, font_body)
	font_heavy = _font("BarlowCondensed-ExtraBold", fb, font_display)
	ThemeDB.fallback_font = font_body


static func install_symbol_font() -> void:
	install_fonts()


static func _font(file: String, fb: Array[Font], fallback: Font) -> Font:
	var path := "res://assets/fonts/%s.ttf" % file
	var f: FontFile = load(path) if ResourceLoader.exists(path) else null
	if f == null:
		return fallback
	f.fallbacks = fb
	return f


## The app-wide theme: fonts, tooltips, popup menus and slim accent scrollbars.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	install_fonts()
	var th := Theme.new()
	th.default_font = font_body
	th.default_font_size = 16
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_bold)
	var tip := flat(PANEL_HI, 6, 1, ACCENT.darkened(0.3))
	tip.content_margin_top = 6
	tip.content_margin_bottom = 6
	th.set_stylebox("panel", "TooltipPanel", tip)
	th.set_color("font_color", "TooltipLabel", TEXT)
	th.set_font_size("font_size", "TooltipLabel", 15)
	th.set_stylebox("panel", "PopupMenu", flat(PANEL_HI, 6, 1, LINE))
	var ph := flat(ACCENT.darkened(0.45), 3)
	ph.content_margin_top = 4
	ph.content_margin_bottom = 4
	th.set_stylebox("hover", "PopupMenu", ph)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	th.set_constant("v_separation", "PopupMenu", 12)
	th.set_font("font", "PopupMenu", font_display)
	for t in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", t, _bar(Color(1, 1, 1, 0.03)))
		th.set_stylebox("scroll_focus", t, _bar(Color(1, 1, 1, 0.03)))
		th.set_stylebox("grabber", t, _bar(LINE.lightened(0.2)))
		th.set_stylebox("grabber_highlight", t, _bar(ACCENT.darkened(0.25)))
		th.set_stylebox("grabber_pressed", t, _bar(ACCENT))
	_theme = th
	return th


static func _bar(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(4)
	s.set_content_margin_all(3)
	return s


# --- basic widgets ----------------------------------------------------------------

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


## Plain label. Big sizes switch to the condensed broadcast face (24+ bold, 40+ extra bold).
static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size >= 24:
		install_fonts()
		l.add_theme_font_override("font", font_heavy if size >= 40 else font_display)
	return l


## Condensed broadcast label (titles, scores, tile and section heads).
static func display(text: String, size := 20, color := TEXT, heavy := false) -> Label:
	var l := label(text, size, color)
	install_fonts()
	l.add_theme_font_override("font", font_heavy if heavy else font_display)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func rich(text: String, size := 16) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Story text still says "#f59e0b" for highlights; show it in the team accent.
	r.text = text.replace("#f59e0b", hex(ACCENT)) if ACCENT != GOLD else text
	return r


static func panel(color := PANEL, radius := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(color, radius))
	return p


## Section heading: a slanted accent bar then the title in the condensed face.
static func heading(text: String, size := 20, color := TEXT) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := Panel.new()
	var sb := flat(ACCENT, 1)
	sb.skew = Vector2(SKEW * 1.5, 0)
	bar.add_theme_stylebox_override("panel", sb)
	bar.custom_minimum_size = Vector2(7, size)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	h.add_child(display(text.to_upper(), size, color))
	return h


## Apply the standard look to any button: subtle rim, accent border and glow on hover/focus,
## and a small scale "pop" (see _hook_pop). accent defaults to the team accent.
static func style_button(b: Button, base := PANEL_HI, accent := Color.TRANSPARENT, radius := 6, pop := true) -> void:
	if accent.a == 0.0:
		accent = ACCENT
	b.add_theme_stylebox_override("normal", flat(base, radius, 1, base.lightened(0.1)))
	var hv := flat(base.lightened(0.1), radius, 2, accent)
	hv.shadow_color = Color(accent, 0.3)
	hv.shadow_size = 8
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", flat(base.darkened(0.15), radius, 2, accent))
	var fc := flat(Color.TRANSPARENT, radius, 2, accent)
	fc.shadow_color = Color(accent, 0.35)
	fc.shadow_size = 10
	b.add_theme_stylebox_override("focus", fc)
	b.add_theme_stylebox_override("disabled", flat(base.darkened(0.3), radius, 1, LINE))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.focus_mode = Control.FOCUS_ALL
	if pop:
		_hook_pop(b)


## Slanted broadcast button in the accent colour (Play, primary actions, active tab).
static func style_primary(b: Button, color := Color.TRANSPARENT, skewed := true) -> void:
	if color.a == 0.0:
		color = ACCENT
	var deep := Color.from_hsv(color.h, clampf(color.s, 0.0, 0.9), 0.5)
	var mk := func(bg: Color, border: Color, bw: int, glow: float) -> StyleBoxFlat:
		var s := flat(bg, 3, bw, border)
		if skewed:
			s.skew = Vector2(SKEW, 0)
		s.content_margin_left = 26
		s.content_margin_right = 26
		if glow > 0.0:
			s.shadow_color = Color(color, glow)
			s.shadow_size = 12
		return s
	b.add_theme_stylebox_override("normal", mk.call(deep, color.lightened(0.15), 1, 0.0))
	b.add_theme_stylebox_override("hover", mk.call(Color.from_hsv(color.h, clampf(color.s, 0.0, 0.9), 0.62), Color.WHITE, 2, 0.45))
	b.add_theme_stylebox_override("pressed", mk.call(deep.darkened(0.2), Color.WHITE, 2, 0.2))
	b.add_theme_stylebox_override("focus", mk.call(Color.TRANSPARENT, Color.WHITE, 2, 0.5))
	b.add_theme_stylebox_override("disabled", mk.call(deep.darkened(0.45), LINE, 1, 0.0))
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	b.add_theme_constant_override("shadow_offset_x", 1)
	b.add_theme_constant_override("shadow_offset_y", 2)
	install_fonts()
	b.add_theme_font_override("font", font_display)
	b.focus_mode = Control.FOCUS_ALL
	_hook_pop(b)


## Slanted secondary button (week arrows, Sim To, Back).
static func style_skewed(b: Button, base := PANEL_HI) -> void:
	style_button(b, base, ACCENT, 3)
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s: StyleBoxFlat = b.get_theme_stylebox(k)
		s.skew = Vector2(SKEW, 0)
		s.content_margin_left = 22
		s.content_margin_right = 22
	install_fonts()
	b.add_theme_font_override("font", font_display)


static func button(text: String, cb: Callable, size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	style_button(b)
	b.pressed.connect(cb)
	return b


static func primary_button(text: String, cb: Callable, size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	style_primary(b)
	b.pressed.connect(cb)
	return b


## Madden-style menu tile: accent swoosh on top, a soft accent glow, title, subtitle and an
## optional badge ("SOON" for laid-out-but-not-built features).
static func tile(title: String, subtitle: String, size: Vector2, accent: Color, cb: Callable, badge := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.clip_contents = true
	style_button(b, PANEL, accent, 10)
	b.pressed.connect(cb)

	var glow := gradient_rect(Color(accent, 0.16), Color(accent, 0.0))
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(glow)
	var strip := gradient_rect(accent, Color(accent, 0.0), false)
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = 4
	b.add_child(strip)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_right = -18
	box.offset_top = 16
	box.offset_bottom = -14
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	b.add_child(box)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var t := display(title.to_upper(), 26 if size.y >= 180 else 22, Color.WHITE)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if badge != "":
		var bp := PanelContainer.new()
		var bs := flat(LINE, 4)
		bs.content_margin_top = 2
		bs.content_margin_bottom = 2
		bs.content_margin_left = 8
		bs.content_margin_right = 8
		bs.skew = Vector2(SKEW, 0)
		bp.add_theme_stylebox_override("panel", bs)
		bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bp.add_child(display(badge, 14, MUTED))
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
	var hsb := flat(PANEL_HI, 3)
	hsb.content_margin_top = 6
	hsb.content_margin_bottom = 6
	hsb.border_width_bottom = 2
	hsb.border_color = ACCENT
	header.add_theme_stylebox_override("panel", hsb)
	header.custom_minimum_size.x = width
	var hc := _cells(headers, col_widths, Color("#aab4c5"), 15)
	install_fonts()
	for l in hc.get_children():
		if l is Label:
			l.add_theme_font_override("font", font_display)
	header.add_child(hc)
	v.add_child(header)
	for i in rows.size():
		var bg: Color = highlight_rows.get(i, PANEL if i % 2 == 0 else PANEL.lightened(0.035))
		var b := Button.new()
		style_button(b, bg, ACCENT, 3)
		var mine := bg == MINE
		if mine:
			b.add_theme_stylebox_override("normal", flat(MINE, 3, 2, ACCENT.darkened(0.1)))
		b.custom_minimum_size = Vector2(width, 36)
		var hb := _cells(rows[i], col_widths, Color.WHITE if mine else TEXT, 16)
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
		if i < 24:
			fade_in(b, 0.02 * i)
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
## The team logo on a dark disc ringed in the team accent, `size` px across, so it reads on any
## background (team-colour banners included).
static func logo_disc(team: Team, size := 120, glow := true) -> Control:
	var p := PanelContainer.new()
	var acc := accent_of(team)
	var sb := flat(Color(0.02, 0.03, 0.06, 0.85), size, maxi(2, size / 50), acc)
	var logo := int(size * 0.76)
	sb.set_content_margin_all((size - logo) / 2.0)
	if glow:
		sb.shadow_color = Color(acc, 0.25)
		sb.shadow_size = maxi(4, size / 12)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(team_logo(team, logo))
	return p


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


# --- backdrops & motion -----------------------------------------------------------

## A TextureRect filled with a two-colour gradient (vertical by default). Ignores the mouse.
static func gradient_rect(c1: Color, c2: Color, vertical := true) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, c2)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 64
	gt.fill_from = Vector2.ZERO
	gt.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Broadcast backdrop drawn behind a panel's content. Two-tone: left colour fading into a dark
## centre band and the right colour, split on a slant (the matchup card). Otherwise a left-to-right
## gradient. Gloss adds a soft highlight on the top half; stripe a bottom accent line.
class Backdrop extends Control:
	var left := Color.BLACK
	var right := Color.BLACK
	var mid := Color.BLACK
	var two_tone := false
	var slant := 46.0
	var gloss := true
	var stripe := Color.TRANSPARENT

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		if two_tone:
			var lw := w * 0.36
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(lw + slant, 0), Vector2(lw - slant, h), Vector2(0, h)]),
				PackedColorArray([left, mid, mid, left.darkened(0.25)]))
			draw_polygon(PackedVector2Array([Vector2(lw + slant, 0), Vector2(w - lw + slant, 0), Vector2(w - lw - slant, h), Vector2(lw - slant, h)]),
				PackedColorArray([mid, mid, mid, mid]))
			draw_polygon(PackedVector2Array([Vector2(w - lw + slant, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - lw - slant, h)]),
				PackedColorArray([mid, right, right.darkened(0.25), mid]))
			for x in [lw, w - lw]:
				draw_line(Vector2(x + slant, 0), Vector2(x - slant, h), Color(1, 1, 1, 0.06), 2.0, true)
		else:
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
				PackedColorArray([left, right, right, left.darkened(0.2)]))
		if gloss:
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.5), Vector2(0, h * 0.5)]),
				PackedColorArray([Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)]))
		if stripe.a > 0.0:
			draw_polygon(PackedVector2Array([Vector2(0, h - 3), Vector2(w, h - 3), Vector2(w, h), Vector2(0, h)]),
				PackedColorArray([stripe, Color(stripe, 0.0), Color(stripe, 0.0), stripe]))


static func backdrop(l: Color, r: Color, gloss := true, stripe := Color.TRANSPARENT) -> Backdrop:
	var d := Backdrop.new()
	d.left = l
	d.right = r
	d.gloss = gloss
	d.stripe = stripe
	return d


## Run cb once the control is in the tree (tweens need a SceneTree).
static func _when_ready(c: Node, cb: Callable) -> void:
	if c.is_inside_tree():
		cb.call()
	else:
		c.tree_entered.connect(cb, CONNECT_ONE_SHOT)


## Fade a control in (from transparent to its current alpha) after `delay` seconds.
static func fade_in(c: CanvasItem, delay := 0.0, dur := 0.22) -> void:
	var target := c.modulate.a
	c.modulate.a = 0.0
	_when_ready(c, func():
		if not is_instance_valid(c):
			return
		var tw := c.create_tween()
		tw.tween_property(c, "modulate:a", target, dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))


## Count a label up from 0 to `to` (fmt holds one %d). The final text is set up front for layout.
static func count_up(l: Label, to: int, fmt := "%d", dur := 0.7) -> void:
	l.text = fmt % to
	_when_ready(l, func():
		if not is_instance_valid(l) or to <= 0:
			return
		var tw := l.create_tween()
		tw.tween_method(func(x: float): l.text = fmt % roundi(x), 0.0, float(to), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))


## Grow a bar's stretch ratio from 0 (bars in an HBox fill in).
static func grow(c: Control, ratio: float, delay := 0.0, dur := 0.6) -> void:
	c.size_flags_stretch_ratio = 0.001
	_when_ready(c, func():
		if not is_instance_valid(c):
			return
		var tw := c.create_tween()
		tw.tween_property(c, "size_flags_stretch_ratio", maxf(0.001, ratio), dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))


## Hover/focus "pop": scale up a touch (less for wide controls), press in on button_down.
static func _hook_pop(b: Control) -> void:
	if b.has_meta(&"_pop"):
		return
	b.set_meta(&"_pop", true)
	var to := func(k: float, dur: float):
		if not is_instance_valid(b) or not b.is_inside_tree():
			return
		b.pivot_offset = b.size / 2.0
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(k, k), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var up := func(on: bool):
		if on and b is BaseButton and (b as BaseButton).disabled:
			on = false
		to.call(1.0 + minf(0.04, 7.0 / maxf(b.size.x, 1.0)) if on else 1.0, 0.12)
	b.mouse_entered.connect(func(): up.call(true))
	b.mouse_exited.connect(func(): up.call(b.has_focus()))
	b.focus_entered.connect(func(): up.call(true))
	b.focus_exited.connect(func(): up.call(b is BaseButton and (b as BaseButton).is_hovered()))
	if b is BaseButton:
		(b as BaseButton).button_down.connect(func(): to.call(0.97, 0.06))
		(b as BaseButton).button_up.connect(func(): up.call(true))

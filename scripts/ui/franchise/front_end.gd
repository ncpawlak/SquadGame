class_name FrontEnd
extends RefCounted
## Shared pieces of the front-end screens (home, mode, settings): the living backdrop, the circular art,
## chips and key hints, and the save-slot lookups.

const CAREER := Color("#38bdf8")
const FRANCHISE := Color("#f59e0b")

## The league. Its emblem lives at LOGO_PATH (see tools/prep_psl_logo.py); until it exists a drawn placeholder shows.
const LEAGUE_NAME := "PRO SQUAD LEAGUE"
const LEAGUE_SHORT := "PSL"
const LOGO_PATH := "res://assets/branding/psl_logo.png"
const PSL_NAVY := Color("#0b2150")
const PSL_RED := Color("#b8001a")


## Tilted wall of every team crest drifting slowly, a warm key light, a cool fill and a vignette, with a dark
## scrim on the left so the text menu always reads.
class Scene extends Control:
	var _wall: Control
	var _drift: Tween

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := ColorRect.new()
		bg.color = UiKit.BG
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		_wall = Control.new()
		_wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wall.size = Vector2(3200, 1900)
		_wall.pivot_offset = _wall.size / 2.0
		_wall.rotation = -0.2
		_wall.modulate = Color(1, 1, 1, 0.085)
		add_child(_wall)
		var abbrevs: Array = []
		for t in LeagueData.TEAMS:
			abbrevs.append(t[0])
		var i := 0
		for r in 9:
			for c in 13:
				var tex := UiKit.logo_tex(abbrevs[(c * 3 + r * 7 + i) % abbrevs.size()])
				i += 1
				if tex == null:
					continue
				var tr := TextureRect.new()
				tr.texture = tex
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.size = Vector2(170, 170)
				tr.position = Vector2(c * 255 + (r % 2) * 127, r * 205)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_wall.add_child(tr)
		add_child(FrontEnd.radial(Color(FRANCHISE, 0.20), Color(FRANCHISE, 0.0), Vector2(0.18, 0.1), Vector2(0.75, 0.1)))
		add_child(FrontEnd.radial(Color(CAREER, 0.16), Color(CAREER, 0.0), Vector2(0.85, 0.95), Vector2(0.85, 0.35)))
		add_child(FrontEnd.radial(Color(0, 0, 0, 0.0), Color(0.01, 0.02, 0.05, 0.88), Vector2(0.5, 0.5), Vector2(1.05, 0.5)))
		var scrim := UiKit.gradient_rect(Color(0.02, 0.03, 0.06, 0.88), Color(0.02, 0.03, 0.06, 0.0), false)
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		scrim.anchor_right = 0.6
		scrim.offset_right = 0
		add_child(scrim)
		resized.connect(_layout)
		_layout.call_deferred()

	func _layout() -> void:
		if size.x <= 0.0:
			return
		var home := (size - _wall.size) / 2.0
		_wall.position = home
		if _drift != null:
			_drift.kill()
		if not Fx.is_reduced():
			_drift = _wall.create_tween().set_loops()
			_drift.tween_property(_wall, "position", home + Vector2(-90, -24), 38.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_drift.tween_property(_wall, "position", home + Vector2(90, 24), 38.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func radial(inner: Color, outer: Color, from: Vector2, to: Vector2) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = from
	gt.fill_to = to
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The PSL emblem at `size` px: the real artwork when present, else a drawn hexagon badge.
static func league_emblem(size: float) -> Control:
	if ResourceLoader.exists(LOGO_PATH):
		var tr := TextureRect.new()
		tr.texture = load(LOGO_PATH)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(size, size)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.tooltip_text = LEAGUE_NAME
		return tr
	return Emblem.new(size)


## Placeholder badge in the emblem's colours (navy hexagon, white keyline, red field) until the artwork file exists.
class Emblem extends Control:
	func _init(s: float) -> void:
		custom_minimum_size = Vector2(s, s)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _hex(inset: float) -> PackedVector2Array:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 * (1.0 - inset)
		var pts := PackedVector2Array()
		for i in 6:
			var a := deg_to_rad(-90.0 + 60.0 * i)
			pts.append(c + Vector2(cos(a) * r * 0.9, sin(a) * r))
		return pts

	func _draw() -> void:
		draw_colored_polygon(_hex(0.0), FrontEnd.PSL_NAVY)
		draw_colored_polygon(_hex(0.1), Color.WHITE)
		var inner := _hex(0.15)
		draw_colored_polygon(inner, FrontEnd.PSL_NAVY)
		# red field on the right, cut by a slant
		var red := PackedVector2Array([inner[0], inner[1], inner[2], Vector2(lerpf(inner[3].x, inner[2].x, 0.0) - size.x * 0.1, inner[2].y + size.y * 0.1), Vector2(size.x * 0.58, inner[1].y + size.y * 0.1)])
		draw_colored_polygon(red, FrontEnd.PSL_RED)
		var font := get_theme_default_font()
		var fs := int(size.y * 0.3)
		var w := font.get_string_size(FrontEnd.LEAGUE_SHORT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(size.x / 2.0 - w / 2.0, size.y * 0.58), FrontEnd.LEAGUE_SHORT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## The "PRO SQUAD LEAGUE" wordmark: emblem, name, and PSL.
static func wordmark(size := 46) -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	bar.add_child(league_emblem(size * 2.5))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(UiKit.display(LEAGUE_NAME, size, Color.WHITE, true))
	col.add_child(UiKit.display(LEAGUE_SHORT, int(size * 0.5), PSL_RED.lightened(0.25)))
	bar.add_child(col)
	return bar


# --- art --------------------------------------------------------------------------------------

## A portrait seated in a circle: the head is scaled to ~88%, centred on the face (the cutouts are not centred in
## their own image) and bottom-aligned, so the whole head sits inside the ring and the shoulders are cut along its
## lower arc. The mask uses the control's local position, so it is measured against the disc, not the photo.
class DiscPic extends Control:
	const FIT := 0.88
	static var _shader: Shader
	static var _face_x := {}  # texture path/id -> horizontal centre of the head, 0..1
	var tex: Texture2D

	func _init(t: Texture2D) -> void:
		tex = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _shader == null:
			_shader = Shader.new()
			_shader.code = "shader_type canvas_item;
uniform vec2 disc = vec2(100.0);
varying vec2 lp;
void vertex() { lp = VERTEX; }
void fragment() { float d = length(lp / disc - vec2(0.5)); COLOR.a *= 1.0 - smoothstep(0.494, 0.5, d); }"
		material = ShaderMaterial.new()
		(material as ShaderMaterial).shader = _shader
		resized.connect(queue_redraw)

	## Centre of the opaque pixels in the head rows (top ~55% of the image).
	func _centre() -> float:
		var key := tex.get_rid().get_id()
		if _face_x.has(key):
			return _face_x[key]
		var cx := 0.5
		var img := tex.get_image()
		if img != null:
			var w := img.get_width()
			var h := img.get_height()
			var sum := 0.0
			var n := 0
			for y in range(int(h * 0.08), int(h * 0.55), 2):
				for x in range(0, w, 2):
					if img.get_pixel(x, y).a > 0.5:
						sum += x
						n += 1
			if n > 0:
				cx = (sum / n) / float(w)
		_face_x[key] = cx
		return cx

	func _draw() -> void:
		(material as ShaderMaterial).set_shader_parameter("disc", size)
		var w := float(tex.get_width())
		var dw := size.x * FIT
		var shift := (0.5 - _centre()) * dw
		var dst := Rect2(Vector2(size.x * (1.0 - FIT) / 2.0 + shift, size.y * (1.0 - FIT)), Vector2(dw, size.y * FIT))
		draw_texture_rect_region(tex, dst, Rect2(0, 0, w, minf(w, float(tex.get_height()))))


## Ringed, glowing disc holding a portrait (cropped to the circle) or a crest (inset).
static func disc_art(accent: Color, tex: Texture2D, d: int, portrait: bool) -> Control:
	var disc := PanelContainer.new()
	var sb := UiKit.flat(Color(accent.darkened(0.7), 0.9), d, 3, accent)
	sb.shadow_color = Color(accent, 0.35)
	sb.shadow_size = maxi(10, d / 10)
	sb.set_content_margin_all(6 if portrait else int(d * 0.16))
	disc.add_theme_stylebox_override("panel", sb)
	disc.custom_minimum_size = Vector2(d, d)
	disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null and portrait:
		disc.add_child(DiscPic.new(tex))
	elif tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(tr)
	return disc


## A baked head cutout, rotating daily so the front door is not always the same face.
static func head_texture() -> Texture2D:
	var heads: Array = FaceSpec.db()["heads"].keys()
	heads.sort()
	if heads.is_empty():
		return null
	var path := "%s%s.webp" % [FaceSpec.HEADS_DIR, heads[(int(Time.get_date_dict_from_system()["day"]) * 3) % heads.size()]]
	return load(path) if ResourceLoader.exists(path) else null


static func team_row(abbrev: String) -> Array:
	for t in LeagueData.TEAMS:
		if t[0] == abbrev:
			return t
	return []


## A team colour that reads on dark: the primary unless it is washed out or near-black.
static func team_accent(abbrev: String) -> Color:
	var row := team_row(abbrev)
	if row.is_empty():
		return FRANCHISE
	var c := Color(row[3])
	if c.s < 0.3 or c.get_luminance() < 0.2:
		c = Color(row[4])
	while c.get_luminance() < 0.4:
		c = c.lightened(0.2)
	return c


static func daily_team() -> String:
	var all: Array = []
	for t in LeagueData.TEAMS:
		all.append(t[0])
	return all[int(Time.get_date_dict_from_system()["day"]) % all.size()]


# --- small widgets ----------------------------------------------------------------------------

static func chip(text: String, accent: Color) -> Control:
	var p := PanelContainer.new()
	var s := UiKit.flat(Color(accent, 0.14), 4, 1, Color(accent, 0.45))
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(UiKit.display(text, 15, accent.lightened(0.35)))
	return p


static func chips(items: Array, accent: Color, width := 380) -> Control:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.custom_minimum_size = Vector2(width, 0)
	f.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for t in items:
		f.add_child(chip(String(t), accent))
	return f


static func keycap(text: String) -> Control:
	var p := PanelContainer.new()
	var s := UiKit.flat(Color(1, 1, 1, 0.06), 5, 1, Color(1, 1, 1, 0.18))
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(UiKit.label(text, 14, UiKit.TEXT))
	return p


static func footer(hints: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for h in hints:
		row.add_child(keycap(h[0]))
		row.add_child(UiKit.label(h[1], 15, UiKit.MUTED))
		var gap := Control.new()
		gap.custom_minimum_size.x = 14
		row.add_child(gap)
	return row


# --- career-flow building blocks ---------------------------------------------------------------

## Puts a career-flow screen's content over the crest-wall backdrop.
static func backdrop_wrap(inner: Control) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(Scene.new())
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(inner)
	return root


static func margin(child: Control, m := 40, top := -1) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	mc.add_theme_constant_override("margin_top", m if top < 0 else top)
	mc.add_child(child)
	return mc


## Eyebrow (small, accent) over a big heavy title.
static func title_block(eyebrow: String, title: String, accent := CAREER, size := 56) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UiKit.display(eyebrow, 19, accent))
	v.add_child(UiKit.display(title, size, Color.WHITE, true))
	return v


## Translucent dark card used on the career-flow screens.
static func glass(pad := 18, accent := Color.TRANSPARENT) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiKit.flat(Color(0.05, 0.08, 0.14, 0.78), 14, 1, Color(accent, 0.55) if accent.a > 0.0 else Color(1, 1, 1, 0.09))
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


## "< Back" as quiet text.
static func back_link(cb: Callable) -> Button:
	var b := MenuText.new("< Back", 24, UiKit.MUTED, "", 130)
	b.rest_alpha = 0.55
	b.pressed.connect(cb)
	b.set_meta(&"skip_autofocus", true)
	return b


## A text option in a row of choices: muted text, white with an accent underline when selected.
static func pick(text: String, selected: bool, cb: Callable, size := 19) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = Vector2(0, 38)
	UiKit.style_tab(b, selected, size)
	b.pressed.connect(cb)
	return b


## Text input that is visible at rest, with a clear focus ring.
static func style_input(e: LineEdit, placeholder := "") -> void:
	var mk := func(border: Color, bw: int) -> StyleBoxFlat:
		var s := UiKit.flat(Color(1, 1, 1, 0.08), 8, bw, border)
		s.content_margin_left = 14
		s.content_margin_right = 14
		return s
	e.add_theme_stylebox_override("normal", mk.call(Color(1, 1, 1, 0.28), 1))
	e.add_theme_stylebox_override("focus", mk.call(CAREER, 2))
	e.add_theme_stylebox_override("read_only", mk.call(Color(1, 1, 1, 0.1), 1))
	e.add_theme_color_override("font_color", Color.WHITE)
	e.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.32))
	e.add_theme_font_size_override("font_size", 20)
	e.placeholder_text = placeholder
	e.custom_minimum_size.y = 44


## Centered dim line for "nothing here yet" states.
static func empty_state(text: String) -> Control:
	var c := CenterContainer.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := UiKit.display(text, 24, Color(1, 1, 1, 0.35))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(l)
	return c


## In-page "nothing here yet" note: centered, dim, with breathing room. The one empty state for lists inside pages.
static func empty_note(text: String) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 28)
	m.add_theme_constant_override("margin_bottom", 28)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := UiKit.label(text, 18, Color(1, 1, 1, 0.4))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.add_child(l)
	return m


## A rating range drawn on the 0-99 scale (lo..hi filled).
class RangeBar extends Control:
	var lo := 0
	var hi := 0
	var color := FrontEnd.CAREER

	func _init(l: int, h: int, c := FrontEnd.CAREER) -> void:
		lo = l
		hi = h
		color = c
		custom_minimum_size = Vector2(120, 22)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := size.y / 2.0 - 4.0
		draw_rect(Rect2(0, y, size.x, 8), Color(1, 1, 1, 0.1))
		var x0 := size.x * float(lo) / 99.0
		var x1 := maxf(x0 + 4.0, size.x * float(hi) / 99.0)
		draw_rect(Rect2(x0, y, x1 - x0, 8), color)
		for v in [25, 50, 75]:
			var x: float = size.x * float(v) / 99.0
			draw_line(Vector2(x, y), Vector2(x, y + 8), Color(0, 0, 0, 0.45), 1.0)


# --- saves ------------------------------------------------------------------------------------

## Everything the front end knows about `mode` ("career" / "franchise"):
## slot (-2 none, -1 the running season, else a save slot), label, abbrev, saved_at, count,
## slots (header dictionaries of this mode's saves, newest first), title (player or team name).
static func mode_info(app: Control, mode: String) -> Dictionary:
	var info := {"count": 0, "slot": -2, "slots": [], "label": "", "abbrev": "", "saved_at": "", "title": "", "team": "", "when": ""}
	var found: Array = []
	for slot in range(SaveSystem.AUTO_SLOT, SaveSystem.SLOTS + 1):
		var h := SaveSystem.slot_info(slot)
		if h.is_empty() or String(h.get("mode", "franchise")) != mode:
			continue
		found.append(h)
	found.sort_custom(func(a, b): return String(a.get("saved_at", "")) > String(b.get("saved_at", "")))
	info["slots"] = found
	info["count"] = found.size()
	if not found.is_empty():
		var h: Dictionary = found[0]
		var who := String(h.get("player", "")) if mode == "career" and String(h.get("player", "")) != "" else String(h.get("team", ""))
		info["slot"] = int(h.get("slot", 0))
		info["saved_at"] = String(h.get("saved_at", ""))
		info["abbrev"] = String(h.get("abbrev", ""))
		info["team"] = String(h.get("team", ""))
		info["title"] = who
		info["when"] = "%s  ·  %s" % [str(h.get("year", "")), String(h.get("week", ""))]
		info["label"] = "%s  ·  %s" % [who, info["when"]]
	var s: Season = app.season
	if s != null and s.player_mode == (mode == "career"):
		var t := s.user_team()
		var who2 := t.name
		if mode == "career" and s.player != null:
			who2 = s.player.display_name()
		var when := "Offseason" if s.phase == &"offseason" else s.week_label(s.week)
		info["slot"] = -1
		info["abbrev"] = t.abbrev
		info["team"] = t.name
		info["title"] = who2
		info["when"] = "%d  ·  %s" % [s.year, when]
		info["label"] = "%s  ·  %s" % [who2, info["when"]]
	return info

class_name FrontEnd
extends RefCounted
## Shared pieces of the front-end screens (home, mode, settings): the living backdrop, the circular art,
## chips and key hints, and the save-slot lookups.

const CAREER := Color("#38bdf8")
const FRANCHISE := Color("#f59e0b")


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


## The "SQUAD LEAGUE" wordmark with its amber slash.
static func wordmark(size := 46) -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	var slash := Panel.new()
	var ss := UiKit.flat(FRANCHISE, 2)
	ss.skew = Vector2(UiKit.SKEW * 2.0, 0)
	slash.add_theme_stylebox_override("panel", ss)
	slash.custom_minimum_size = Vector2(12, size)
	slash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(slash)
	bar.add_child(UiKit.display("SQUAD LEAGUE", size, Color.WHITE, true))
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

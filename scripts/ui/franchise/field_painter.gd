class_name FieldPainter
extends RefCounted
## Top-down drawing of a field (floor surface, centre logo, props) on any CanvasItem. Screen position
## is `origin + metres * scale`, so the match viewer and previews share it.

const FLOORS := {
	"asphalt": Color("#2d3037"), "concrete": Color("#5a5f67"), "turf": Color("#2f5d34"), "sand": Color("#c4b184"),
}
const CONTAINER_COLORS := [Color("#8b3a2b"), Color("#2f5f8a"), Color("#2f6b4a"), Color("#b8892f")]
const LOGO_METRES := 26.0
## Floor textures are generated once per surface (px per metre).
const TEX_PPM := 8
static var _floor_tex: Dictionary = {}
## Draw order of decals (lower first).
const DECAL_Z := {&"water": 0, &"grass": 0, &"dirt": 0, &"boards": 0, &"pad": 1}
## Compact props drawn as a row when their footprint is long (a skin swap can stretch them).
const TILED: Array[StringName] = [&"barrels", &"hay", &"planter", &"crate", &"tree", &"table", &"cabana"]


static func _rect(field_rect: Rect2, origin: Vector2, sc: float) -> Rect2:
	return Rect2(origin + field_rect.position * sc, field_rect.size * sc)


static func _outline(c: CanvasItem, r: Rect2, col: Color, w := 2.0) -> void:
	c.draw_rect(r, col, false, w)


## Procedural surface texture: mottling and grain for every surface, dune ripples for sand and oil
## stains for asphalt. Built once and cached.
static func _surface_texture(surface: String) -> Texture2D:
	if _floor_tex.has(surface):
		return _floor_tex[surface]
	var w := int(ArenaMap.HALF.x * 2.0) * TEX_PPM
	var h := int(ArenaMap.HALF.y * 2.0) * TEX_PPM
	var coarse := FastNoiseLite.new()
	coarse.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	coarse.frequency = 0.011
	coarse.seed = 11
	var fine := FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fine.frequency = 0.5
	fine.seed = 7
	var blob := FastNoiseLite.new()
	blob.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	blob.frequency = 0.02
	blob.seed = 3
	var cd := coarse.get_image(w, h, false, false, true).get_data()
	var fd := fine.get_image(w, h, false, false, true).get_data()
	var bd := blob.get_image(w, h, false, false, true).get_data()
	var base: Color = FLOORS.get(surface, FLOORS["concrete"])
	var mottle := 0.07
	var grain := 0.07
	match surface:
		"concrete":
			mottle = 0.05
			grain = 0.06
		"sand":
			mottle = 0.10
			grain = 0.08
		"turf":
			mottle = 0.10
			grain = 0.05
	var out := PackedByteArray()
	out.resize(w * h * 3)
	var i := 0
	for y in h:
		for x in w:
			var idx := y * w + x
			var cv := cd[idx] / 255.0 - 0.5
			var fv := fd[idx] / 255.0 - 0.5
			var shade := 1.0 + cv * mottle * 2.0 + fv * grain * 2.0
			if surface == "sand":
				shade += 0.035 * sin(x * 0.42 + cv * 16.0)
			elif surface == "asphalt":
				if bd[idx] > 190:
					shade *= 0.93
			out[i] = clampi(int(base.r * shade * 255.0), 0, 255)
			out[i + 1] = clampi(int(base.g * shade * 255.0), 0, 255)
			out[i + 2] = clampi(int(base.b * shade * 255.0), 0, 255)
			i += 3
	var tex := ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGB8, out))
	_floor_tex[surface] = tex
	return tex


## Floor texture and turf mowing stripes.
static func draw_floor(c: CanvasItem, field: ArenaMap, origin: Vector2, sc: float) -> void:
	var arena := _rect(Rect2(-ArenaMap.HALF, ArenaMap.HALF * 2.0), origin, sc)
	c.draw_texture_rect(_surface_texture(field.surface), arena, false)
	if field.surface == "turf":
		var x := -ArenaMap.HALF.x
		var i := 0
		while x < ArenaMap.HALF.x:
			if i % 2 == 0:
				c.draw_rect(_rect(Rect2(x, -ArenaMap.HALF.y, 6.0, ArenaMap.HALF.y * 2.0), origin, sc), Color(1, 1, 1, 0.045))
			x += 6.0
			i += 1


## Floor decals (in DECAL_Z order), the centre logo on top of them, then low props, then tall ones.
static func draw_props(c: CanvasItem, field: ArenaMap, origin: Vector2, sc: float, logo: Texture2D = null) -> void:
	for z in 2:
		for p in field.props:
			var kind: StringName = p["k"]
			if DECAL_Z.get(kind, -1) == z:
				_draw_prop(c, p, _rect(p["rect"], origin, sc), sc)
	if logo != null:
		var s := LOGO_METRES * sc
		c.draw_texture_rect(logo, Rect2(origin - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, 0.4))
	for pass_i in 2:
		for p in field.props:
			var kind: StringName = p["k"]
			if DECAL_Z.has(kind):
				continue
			var tall: bool = ArenaMap.KINDS[kind].get("tall", false)
			if (1 if tall else 0) == pass_i:
				_draw_prop(c, p, _rect(p["rect"], origin, sc), sc)


static func _draw_prop(c: CanvasItem, p: Dictionary, r: Rect2, sc: float) -> void:
	var kind: StringName = p["k"]
	var horiz := r.size.x >= r.size.y
	var long := r.size.x if horiz else r.size.y
	var short := r.size.y if horiz else r.size.x
	var ctr := r.get_center()
	if kind in TILED and long > short * 1.7:
		var n := roundi(long / short)
		for i in n:
			var cell := Vector2(long / n, r.size.y) if horiz else Vector2(r.size.x, long / n)
			var at := r.position + (Vector2(i * cell.x, 0.0) if horiz else Vector2(0.0, i * cell.y))
			_draw_prop(c, p, Rect2(at, cell), sc)
		return
	match kind:
		&"pad":
			c.draw_rect(r, Color(0.78, 0.68, 0.5, 0.10))
		&"grass":
			c.draw_rect(r, Color(0.24, 0.42, 0.25, 0.92))
		&"dirt":
			c.draw_rect(r, Color(0.54, 0.43, 0.28, 0.95))
		&"boards":
			c.draw_rect(r, Color("#8a6a45"))
			var t := sc * 0.55
			while t < short:
				if horiz:
					c.draw_line(r.position + Vector2(0, t), r.position + Vector2(r.size.x, t), Color("#5e4529"), 1.0)
				else:
					c.draw_line(r.position + Vector2(t, 0), r.position + Vector2(t, r.size.y), Color("#5e4529"), 1.0)
				t += sc * 0.55
			_outline(c, r, Color("#5e4529"), 1.5)
		&"water":
			c.draw_rect(r, Color(0.17, 0.42, 0.56, 0.92))
			var t := sc * 1.6
			while t < short:
				if horiz:
					c.draw_line(r.position + Vector2(sc, t), r.position + Vector2(r.size.x - sc, t), Color(1, 1, 1, 0.10), 1.0)
				else:
					c.draw_line(r.position + Vector2(t, sc), r.position + Vector2(t, r.size.y - sc), Color(1, 1, 1, 0.10), 1.0)
				t += sc * 1.6
		&"wall":
			c.draw_rect(r, Color("#11141a"))
			c.draw_rect(r.grow(-maxf(1.0, sc * 0.18)), Color("#4a5160"))
		&"pillar":
			c.draw_rect(r, Color("#4a5160"))
			_outline(c, r, Color("#101318"))
			c.draw_line(r.position, r.end, Color("#101318"), 1.0)
			c.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color("#101318"), 1.0)
		&"container":
			var col: Color = CONTAINER_COLORS[int(absf(p["rect"].position.x * 7.0 + p["rect"].position.y * 13.0)) % CONTAINER_COLORS.size()]
			c.draw_rect(r, col)
			_outline(c, r, col.darkened(0.45))
			var rib := sc * 0.8
			var t := rib
			while t < long:
				if horiz:
					c.draw_line(r.position + Vector2(t, 0), r.position + Vector2(t, r.size.y), col.darkened(0.25), 1.0)
				else:
					c.draw_line(r.position + Vector2(0, t), r.position + Vector2(r.size.x, t), col.darkened(0.25), 1.0)
				t += rib
		&"bleachers":
			c.draw_rect(r, Color("#7d838f"))
			_outline(c, r, Color("#3f444d"))
			var t := sc * 0.9
			while t < short:
				if horiz:
					c.draw_line(r.position + Vector2(0, t), r.position + Vector2(r.size.x, t), Color("#575c66"), 1.5)
				else:
					c.draw_line(r.position + Vector2(t, 0), r.position + Vector2(t, r.size.y), Color("#575c66"), 1.5)
				t += sc * 0.9
		&"car":
			_draw_car(c, r, horiz, _color(p, "#888888"))
		&"truck":
			var col := _color(p, "#888888")
			var cab := long * 0.28
			if horiz:
				c.draw_rect(Rect2(r.position + Vector2(cab, 0), Vector2(r.size.x - cab, r.size.y)), Color("#d9dce2"))
				_outline(c, Rect2(r.position + Vector2(cab, 0), Vector2(r.size.x - cab, r.size.y)), Color("#6b7079"), 1.5)
				_draw_car(c, Rect2(r.position, Vector2(cab, r.size.y)), true, col)
			else:
				c.draw_rect(Rect2(r.position + Vector2(0, cab), Vector2(r.size.x, r.size.y - cab)), Color("#d9dce2"))
				_outline(c, Rect2(r.position + Vector2(0, cab), Vector2(r.size.x, r.size.y - cab)), Color("#6b7079"), 1.5)
				_draw_car(c, Rect2(r.position, Vector2(r.size.x, cab)), false, col)
		&"bus":
			var col := _color(p, "#e0b83a")
			c.draw_rect(r, col)
			_outline(c, r, col.darkened(0.5))
			var t := long * 0.1
			while t < long * 0.9:
				var w := Rect2(r.position + (Vector2(t, short * 0.18) if horiz else Vector2(short * 0.18, t)), Vector2(long * 0.06, short * 0.64) if horiz else Vector2(short * 0.64, long * 0.06))
				c.draw_rect(w, Color("#1d2630"))
				t += long * 0.12
		&"dumpster":
			c.draw_rect(r, Color("#2f6b45"))
			_outline(c, r, Color("#173523"))
			if horiz:
				c.draw_line(Vector2(ctr.x, r.position.y), Vector2(ctr.x, r.end.y), Color("#173523"), 1.5)
			else:
				c.draw_line(Vector2(r.position.x, ctr.y), Vector2(r.end.x, ctr.y), Color("#173523"), 1.5)
		&"barrels":
			c.draw_circle(ctr, short / 2.0, Color("#8a4b2a"))
			c.draw_arc(ctr, short / 2.0, 0.0, TAU, 20, Color("#3d1f10"), 1.5)
			c.draw_arc(ctr, short / 4.0, 0.0, TAU, 14, Color("#3d1f10"), 1.0)
		&"sandbags":
			c.draw_rect(r, Color("#b49a68"))
			_outline(c, r, Color("#6b5a38"), 1.5)
			var t := sc * 0.8
			while t < long:
				if horiz:
					c.draw_line(r.position + Vector2(t, 0), r.position + Vector2(t, r.size.y), Color("#6b5a38"), 1.0)
				else:
					c.draw_line(r.position + Vector2(0, t), r.position + Vector2(r.size.x, t), Color("#6b5a38"), 1.0)
				t += sc * 0.8
		&"barrier":
			c.draw_rect(r, Color("#a8abb2"))
			_outline(c, r, Color("#5c6068"), 1.5)
			var t := sc * 0.6
			while t < long - sc * 0.3:
				var a := r.position + (Vector2(t, 0) if horiz else Vector2(0, t))
				var b := a + (Vector2(sc * 0.4, r.size.y) if horiz else Vector2(r.size.x, sc * 0.4))
				c.draw_line(a, b, Color("#e07b2a"), 2.0)
				t += sc * 1.4
		&"stall":
			c.draw_rect(r, Color("#e9e4d3"))
			var n := 5
			for i in n:
				if i % 2 == 0:
					var s := Rect2(r.position + (Vector2(long / n * i, 0) if horiz else Vector2(0, long / n * i)),
						Vector2(long / n, r.size.y) if horiz else Vector2(r.size.x, long / n))
					c.draw_rect(s, Color("#c2402f"))
			_outline(c, r, Color("#5a2a22"), 1.5)
		&"crate":
			c.draw_rect(r, Color("#7a5a36"))
			_outline(c, r, Color("#7a5a36").darkened(0.4))
			c.draw_line(r.position, r.end, Color("#7a5a36").darkened(0.25), 1.0)
			c.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color("#7a5a36").darkened(0.25), 1.0)
		&"planter":
			c.draw_circle(ctr, short / 2.0, Color("#2f5a35"))
			c.draw_circle(ctr, short / 3.0, Color("#3f8a4d"))
			c.draw_arc(ctr, short / 2.0, 0.0, TAU, 20, Color("#16301b"), 1.5)
		&"dugout":
			c.draw_rect(r, Color("#5b4a35"))
			_outline(c, r, Color("#2c2318"), 2.0)
			c.draw_rect(r.grow(-sc * 0.35), Color("#74603f"))
		&"boat":
			var pts := PackedVector2Array()
			if horiz:
				pts = PackedVector2Array([r.position, Vector2(r.end.x - long * 0.2, r.position.y), Vector2(r.end.x, ctr.y), Vector2(r.end.x - long * 0.2, r.end.y), Vector2(r.position.x, r.end.y)])
			else:
				pts = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - long * 0.2), Vector2(ctr.x, r.end.y), Vector2(r.position.x, r.end.y - long * 0.2)])
			c.draw_colored_polygon(pts, Color("#e8e4d8"))
			c.draw_polyline(PackedVector2Array(pts) + PackedVector2Array([pts[0]]), Color("#4a5560"), 1.5)
			c.draw_rect(r.grow(-short * 0.28), Color("#9aa4b0"))
		&"cabana":
			c.draw_rect(r, Color("#e9e4d3"))
			var h := r.size / 2.0
			c.draw_rect(Rect2(r.position, h), Color("#d9573f"))
			c.draw_rect(Rect2(ctr, h), Color("#d9573f"))
			_outline(c, r, Color("#6b2f22"), 1.5)
		&"tree":
			var rad := short / 2.0
			c.draw_circle(ctr + Vector2(rad * 0.12, rad * 0.12), rad, Color(0, 0, 0, 0.25))
			c.draw_circle(ctr, rad, Color("#255a2b"))
			c.draw_circle(ctr + Vector2(-rad * 0.2, -rad * 0.2), rad * 0.62, Color("#2f7a38"))
			c.draw_circle(ctr + Vector2(-rad * 0.35, -rad * 0.35), rad * 0.3, Color("#3f9448"))
		&"hedge":
			c.draw_rect(r, Color("#1f4d27"))
			c.draw_rect(r.grow(-maxf(1.0, sc * 0.15)), Color("#2b6a34"))
		&"hay":
			c.draw_circle(ctr, short / 2.0, Color("#c9a64b"))
			c.draw_arc(ctr, short / 2.0, 0.0, TAU, 20, Color("#7a5f1e"), 1.5)
			c.draw_arc(ctr, short / 3.2, 0.0, TAU, 14, Color("#9a7d2c"), 1.0)
		&"table":
			c.draw_rect(r, Color("#7a5a36"))
			_outline(c, r, Color("#3d2b18"), 1.5)
			if horiz:
				c.draw_line(Vector2(r.position.x, ctr.y), Vector2(r.end.x, ctr.y), Color("#3d2b18"), 1.0)
			else:
				c.draw_line(Vector2(ctr.x, r.position.y), Vector2(ctr.x, r.end.y), Color("#3d2b18"), 1.0)
		&"fence":
			if horiz:
				c.draw_line(Vector2(r.position.x, ctr.y), Vector2(r.end.x, ctr.y), Color(0.82, 0.84, 0.88, 0.85), 2.0)
				var t := 0.0
				while t <= long:
					c.draw_circle(Vector2(r.position.x + t, ctr.y), 1.6, Color("#9aa0aa"))
					t += sc * 2.0
			else:
				c.draw_line(Vector2(ctr.x, r.position.y), Vector2(ctr.x, r.end.y), Color(0.82, 0.84, 0.88, 0.85), 2.0)
				var t := 0.0
				while t <= long:
					c.draw_circle(Vector2(ctr.x, r.position.y + t), 1.6, Color("#9aa0aa"))
					t += sc * 2.0
		_:
			c.draw_rect(r, Color("#a8825a"))


static func _color(p: Dictionary, fallback: String) -> Color:
	var s: String = p.get("color", "")
	return Color(s if s != "" else fallback)


## A car from above: body, windshield, rear window and a lighter roof.
static func _draw_car(c: CanvasItem, r: Rect2, horiz: bool, col: Color) -> void:
	c.draw_rect(r, col)
	_outline(c, r, col.darkened(0.55), 1.5)
	var dark := Color("#1d2630")
	if horiz:
		var w := r.size.x
		c.draw_rect(Rect2(r.position + Vector2(w * 0.62, r.size.y * 0.14), Vector2(w * 0.14, r.size.y * 0.72)), dark)
		c.draw_rect(Rect2(r.position + Vector2(w * 0.14, r.size.y * 0.14), Vector2(w * 0.12, r.size.y * 0.72)), dark)
		c.draw_rect(Rect2(r.position + Vector2(w * 0.28, r.size.y * 0.16), Vector2(w * 0.32, r.size.y * 0.68)), col.lightened(0.18))
	else:
		var h := r.size.y
		c.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.14, h * 0.62), Vector2(r.size.x * 0.72, h * 0.14)), dark)
		c.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.14, h * 0.14), Vector2(r.size.x * 0.72, h * 0.12)), dark)
		c.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.16, h * 0.28), Vector2(r.size.x * 0.68, h * 0.32)), col.lightened(0.18))


## The colour a team's starting area is tinted with: its primary or its secondary, whichever stands out
## more against the floor (a black team on asphalt uses its gold instead).
static func start_tint(team: Team, surface: String) -> Color:
	var floor_col: Color = FLOORS.get(surface, FLOORS["concrete"])
	var d1 := Vector3(team.color.r - floor_col.r, team.color.g - floor_col.g, team.color.b - floor_col.b).length()
	var d2 := Vector3(team.color2.r - floor_col.r, team.color2.g - floor_col.g, team.color2.b - floor_col.b).length()
	return team.color if d1 >= d2 else team.color2


## Each team's starting area: a tinted strip behind a vertical line, where the formations spawn.
static func draw_start_areas(c: CanvasItem, origin: Vector2, sc: float, colors: Array, labels: Array, font: Font) -> void:
	for i in 2:
		var x0 := -ArenaMap.HALF.x if i == 0 else ArenaMap.START_X
		var x1 := -ArenaMap.START_X if i == 0 else ArenaMap.HALF.x
		var zone := _rect(Rect2(x0, -ArenaMap.HALF.y, x1 - x0, ArenaMap.HALF.y * 2.0), origin, sc)
		c.draw_rect(zone, Color(colors[i], 0.14))
		var lx := origin.x + (x1 if i == 0 else x0) * sc
		c.draw_line(Vector2(lx, zone.position.y), Vector2(lx, zone.end.y), Color(1, 1, 1, 0.75), 3.0)
		if font != null:
			var text: String = labels[i]
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			c.draw_string(font, Vector2(zone.get_center().x - w / 2.0, zone.position.y + 18.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))

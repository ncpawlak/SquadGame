class_name Portrait
extends Control
## Procedural profile picture: a head-and-shoulders soldier built from the soldier's Look
## (skin, headgear, eyewear, face and lower-face gear). Headgear, masks and uniform use the
## team's primary colour; straps, frames, brims and trim use its secondary colour. Soldiers
## without a team (free agents, prospects) wear neutral khaki/gray.
##
## Everything is drawn in "head units": the origin is the centre of the face and 1.0 is the
## face's half-width-ish radius, so the same art scales from list icons to the player pane.

const NEUTRAL_PRIMARY := Color("#8a7d5c")
const NEUTRAL_SECONDARY := Color("#5b6470")
const INK := Color("#141414")
const GEAR_DARK := Color("#24282d")
const PAINT_OLIVE := Color(0.29, 0.34, 0.16, 0.92)
const PAINT_BLACK := Color(0.07, 0.07, 0.07, 0.9)

## Head unit size and head-centre offset, as fractions of the portrait radius.
const UNIT := 0.37
const HEAD_Y := -0.06
## Unit-space circle the portrait is clipped to.
const CLIP_CENTER := Vector2(0, -HEAD_Y / UNIT)
const CLIP_RADIUS := 0.97 / UNIT

var soldier: Soldier
var look: Look
var _p: Color
var _s: Color
var _ring: Color
var _skin: Color
var _hair: Color
var _clip: PackedVector2Array
var _face: PackedVector2Array


func _init(s: Soldier, diameter := 48, ring := UiKit.LINE, team: Team = null) -> void:
	soldier = s
	look = s.get_look()
	_ring = ring
	_p = team.color.darkened(0.12) if team != null else NEUTRAL_PRIMARY
	_s = team.color2 if team != null else NEUTRAL_SECONDARY
	_skin = Look.SKIN[look.skin]
	_hair = look.hair_at(s.age)
	_clip = _ell(CLIP_CENTER, Vector2(CLIP_RADIUS, CLIP_RADIUS), 48)
	_face = _ell(Vector2.ZERO, Vector2(0.82, 1.0))
	custom_minimum_size = Vector2(diameter, diameter)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var d: float = minf(size.x, size.y)
	var r := d / 2.0
	var c := Vector2(size.x / 2.0, size.y / 2.0)
	draw_circle(c, r, _p.darkened(0.78).lerp(Color("#111827"), 0.35))
	draw_set_transform(c + Vector2(0, HEAD_Y * r), 0.0, Vector2.ONE * (UNIT * r))
	_draw_body()
	_draw_head_base()
	_draw_face_details()
	_draw_lower()
	_draw_eyes()
	_draw_headgear()
	draw_set_transform(Vector2.ZERO)
	draw_arc(c, r - 1.0, 0.0, TAU, 48, _ring, 2.0, true)


## Fabric gear (balaclava, bandana, shemagh): the team primary, muted so it reads as cloth.
func _cloth() -> Color:
	return _p.darkened(0.3).lerp(Color("#2a2a2a"), 0.15)


# --- body ---------------------------------------------------------------------------------

func _draw_body() -> void:
	var shirt := _p.darkened(0.55)
	_fill(_ell(Vector2(0, 2.95), Vector2(2.3, 1.55)), shirt, _clip)
	# Plate-carrier shoulder straps and a collar trim in the accent colour.
	var vest := _p.darkened(0.3)
	for sx in [-1.0, 1.0]:
		_fill(PackedVector2Array([Vector2(0.55 * sx, 1.45), Vector2(1.15 * sx, 1.42), Vector2(1.35 * sx, 3.4), Vector2(0.7 * sx, 3.4)]), vest, _clip)
	var neck_col := _cloth() if look.face == Look.Face.BALACLAVA else _skin.darkened(0.12)
	draw_rect(Rect2(-0.4, 0.55, 0.8, 1.1), neck_col)
	draw_polyline(_arc_pts(Vector2(0, 1.3), Vector2(0.62, 0.32), 0.15, PI - 0.15), _s, 0.12, true)


# --- head ---------------------------------------------------------------------------------

func _draw_head_base() -> void:
	var balaclava := look.face == Look.Face.BALACLAVA
	var base := _cloth() if balaclava else _skin
	# Ears
	for sx in [-1.0, 1.0]:
		draw_colored_polygon(_ell(Vector2(0.8 * sx, 0.02), Vector2(0.14, 0.22), 16), base.darkened(0.12))
	draw_colored_polygon(_face, base.darkened(0.14))
	draw_colored_polygon(_ell(Vector2(-0.04, -0.03), Vector2(0.76, 0.95)), base)
	if balaclava:
		# Eye opening of the balaclava.
		var hole := _rounded_rect(Rect2(-0.62, -0.34, 1.24, 0.44), 0.18)
		draw_colored_polygon(hole, _skin)
		draw_polyline(_closed(hole), _p.darkened(0.4), 0.06, true)
		return
	# Hair (bare head shows the style; under headgear only the sides peek out).
	if look.hair_style != 3:
		var hair_top := -0.5 if look.hair_style == 0 else -0.42
		var hair := _ell(Vector2(0, -0.08), Vector2(0.88, 1.08))
		_fill(hair, _hair, _above(hair_top))
		for sx in [-1.0, 1.0]: # sideburns
			draw_rect(Rect2(0.7 * sx - 0.08, -0.45, 0.16, 0.38), _hair)
		if look.hair_style == 2 and look.head == Look.Head.HAIR: # swept fringe
			draw_colored_polygon(PackedVector2Array([Vector2(-0.7, -0.55), Vector2(0.2, -0.95), Vector2(0.75, -0.6), Vector2(0.1, -0.38)]), _hair)
		elif look.hair_style == 1 and look.head == Look.Head.HAIR:
			draw_polyline(PackedVector2Array([Vector2(-0.6, -0.48), Vector2(-0.2, -0.4), Vector2(0.2, -0.43), Vector2(0.6, -0.47)]), _hair.darkened(0.25), 0.06, true)
	elif look.head == Look.Head.HAIR:
		draw_colored_polygon(_ell(Vector2(0.25, -0.62), Vector2(0.18, 0.08), 12), Color(1, 1, 1, 0.18)) # scalp shine


func _draw_face_details() -> void:
	if look.face == Look.Face.BALACLAVA:
		return
	var masked := look.is_masked()
	if look.face == Look.Face.FACE_PAINT:
		# Diagonal olive/black camo bands clipped to the face.
		var bands := [[-0.85, PAINT_OLIVE], [-0.35, PAINT_BLACK], [0.15, PAINT_OLIVE], [0.65, PAINT_BLACK]]
		for b in bands:
			var y0: float = b[0]
			var band := PackedVector2Array([Vector2(-1, y0 + 0.25), Vector2(1, y0 - 0.15), Vector2(1, y0 + 0.07), Vector2(-1, y0 + 0.47)])
			_fill(band, b[1], _face)
	elif look.face == Look.Face.EYE_BLACK:
		for sx in [-1.0, 1.0]:
			draw_colored_polygon(_rounded_rect(Rect2(0.33 * sx - 0.17, 0.07, 0.34, 0.11), 0.05), PAINT_BLACK)
	# Eyebrows
	for sx in [-1.0, 1.0]:
		draw_line(Vector2(0.18 * sx, -0.27), Vector2(0.5 * sx, -0.3 + 0.03), _hair.darkened(0.25), 0.09, true)
	if not masked:
		# Nose and mouth
		draw_polyline(PackedVector2Array([Vector2(0.02, 0.0), Vector2(0.1, 0.27), Vector2(-0.05, 0.3)]), _skin.darkened(0.3), 0.06, true)
		draw_line(Vector2(-0.2, 0.56), Vector2(0.2, 0.56), _skin.darkened(0.5), 0.07, true)


func _draw_lower() -> void:
	var beard := _hair.darkened(0.1)
	match look.lower:
		Look.Lower.SHAVED:
			_fill(_jaw_region(0.3), Color(beard, 0.12), _face)
		Look.Lower.GOATEE:
			draw_colored_polygon(PackedVector2Array([Vector2(-0.28, 0.5), Vector2(0, 0.42), Vector2(0.28, 0.5), Vector2(0.25, 0.56), Vector2(-0.25, 0.56)]), beard)
			_fill(_ell(Vector2(0, 0.8), Vector2(0.22, 0.22), 16), beard, _face)
			draw_line(Vector2(-0.26, 0.5), Vector2(-0.18, 0.72), beard, 0.08, true)
			draw_line(Vector2(0.26, 0.5), Vector2(0.18, 0.72), beard, 0.08, true)
			draw_line(Vector2(-0.14, 0.59), Vector2(0.14, 0.59), _skin.darkened(0.5), 0.06, true)
		Look.Lower.SHORT_BEARD:
			_fill(_jaw_region(0.32), beard, _ell(Vector2(0, 0.02), Vector2(0.84, 1.06)))
			_mouth_on_beard()
		Look.Lower.BIG_BEARD:
			var jaw := Geometry2D.intersect_polygons(_jaw_region(0.3), _ell(Vector2(0, 0.05), Vector2(0.86, 1.08)))
			var chin := _ell(Vector2(0, 1.0), Vector2(0.66, 0.7))
			draw_colored_polygon(chin, beard)
			for poly in jaw:
				draw_colored_polygon(poly, beard)
			draw_polyline(PackedVector2Array([Vector2(-0.3, 1.1), Vector2(-0.2, 1.4)]), beard.darkened(0.25), 0.05, true)
			draw_polyline(PackedVector2Array([Vector2(0.25, 1.15), Vector2(0.15, 1.45)]), beard.darkened(0.25), 0.05, true)
			_mouth_on_beard()
		Look.Lower.BANDANA:
			var bandana := PackedVector2Array([Vector2(-0.88, 0.1), Vector2(0.88, 0.1), Vector2(0.78, 0.75), Vector2(0, 1.42), Vector2(-0.78, 0.75)])
			draw_colored_polygon(bandana, _cloth())
			draw_line(Vector2(-0.88, 0.12), Vector2(0.88, 0.12), _p.darkened(0.3), 0.1, true)
			for pt in [Vector2(-0.5, 0.4), Vector2(0, 0.35), Vector2(0.5, 0.4), Vector2(-0.25, 0.75), Vector2(0.25, 0.75), Vector2(0, 1.1)]:
				draw_circle(pt, 0.07, _s)
		Look.Lower.HALF_MASK:
			var shell := _p.darkened(0.3)
			for sx in [-1.0, 1.0]:
				draw_line(Vector2(0.55 * sx, 0.35), Vector2(0.84 * sx, 0.05), GEAR_DARK, 0.08, true)
			_fill(_ell(Vector2(0, 0.55), Vector2(0.62, 0.55)), shell, _below(0.12))
			draw_rect(Rect2(-0.1, 0.45, 0.2, 0.4), shell.darkened(0.3))
			for sx in [-1.0, 1.0]:
				draw_circle(Vector2(0.45 * sx, 0.68), 0.2, _s)
				draw_circle(Vector2(0.45 * sx, 0.68), 0.11, _s.darkened(0.35))
		Look.Lower.SHEMAGH:
			var wrap := PackedVector2Array([Vector2(-0.88, 0.1), Vector2(0.88, 0.1), Vector2(0.9, 0.75), Vector2(0.95, 1.55),
				Vector2(-0.95, 1.55), Vector2(-0.9, 0.75)])
			draw_colored_polygon(wrap, _cloth().lightened(0.1))
			var check := Color(_s, 0.6)
			for i in 9:
				var x := -1.2 + i * 0.3
				for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(x, 0.0), Vector2(x + 0.3, 1.8)]), wrap):
					draw_polyline(seg, check, 0.05)
				var y := 0.25 + i * 0.16
				for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(-1.3, y), Vector2(1.3, y)]), wrap):
					draw_polyline(seg, check, 0.05)
			draw_polyline(_arc_pts(Vector2(0, 0.35), Vector2(0.9, 0.35), 0.2, PI - 0.2), _p.darkened(0.25), 0.08, true)
			draw_polyline(_arc_pts(Vector2(0, 0.95), Vector2(0.9, 0.3), 0.2, PI - 0.2), _p.darkened(0.25), 0.08, true)


func _mouth_on_beard() -> void:
	draw_line(Vector2(-0.17, 0.58), Vector2(0.17, 0.58), _skin.darkened(0.55), 0.07, true)


## Lower face below the cheekbones (beard/stubble area).
func _jaw_region(top: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-0.9, -0.05), Vector2(-0.6, top), Vector2(-0.2, top + 0.08), Vector2(0.2, top + 0.08),
		Vector2(0.6, top), Vector2(0.9, -0.05), Vector2(0.9, 1.3), Vector2(-0.9, 1.3)])


# --- eyes ---------------------------------------------------------------------------------

func _draw_eyes() -> void:
	match look.eyes:
		Look.Eyes.NORMAL:
			_normal_eyes()
		Look.Eyes.SUNGLASSES:
			var frame := _s.darkened(0.35)
			draw_line(Vector2(-0.5, -0.12), Vector2(-0.84, -0.06), frame, 0.06, true)
			draw_line(Vector2(0.5, -0.12), Vector2(0.84, -0.06), frame, 0.06, true)
			draw_line(Vector2(-0.12, -0.12), Vector2(0.12, -0.12), frame, 0.07, true)
			for sx in [-1.0, 1.0]:
				var lens := _ell(Vector2(0.32 * sx, -0.06), Vector2(0.23, 0.15), 20)
				draw_colored_polygon(lens, Color("#0d0f12"))
				draw_polyline(_closed(lens), frame, 0.05, true)
				draw_line(Vector2(0.32 * sx - 0.12, -0.13), Vector2(0.32 * sx - 0.02, -0.17), Color(1, 1, 1, 0.35), 0.04, true)
		Look.Eyes.GOGGLES_CLEAR, Look.Eyes.GOGGLES_TINTED:
			var clear := look.eyes == Look.Eyes.GOGGLES_CLEAR
			if clear:
				_normal_eyes()
			_goggles(Vector2(0, -0.1), 1.0, Color(0.75, 0.92, 1.0, 0.3) if clear else Look.TINTS[look.tint], true)
		Look.Eyes.NIGHT_VISION:
			pass # drawn with the helmet it mounts on


func _normal_eyes() -> void:
	var iris: Color = Look.EYE_COLORS[look.eye_color]
	for sx in [-1.0, 1.0]:
		var p := Vector2(0.32 * sx, -0.08)
		draw_colored_polygon(_ell(p, Vector2(0.15, 0.085), 16), Color("#f2efe8"))
		draw_circle(p, 0.075, iris)
		draw_circle(p, 0.035, INK)
		draw_circle(p + Vector2(-0.025, -0.025), 0.018, Color(1, 1, 1, 0.9))
		draw_line(p + Vector2(-0.16, -0.05), p + Vector2(0.16, -0.05), _skin.darkened(0.45), 0.045, true)


## Ballistic goggles centred at `at`. `strap` draws the head strap out to the sides.
func _goggles(at: Vector2, scale_by: float, lens: Color, strap: bool) -> void:
	var w := 0.8 * scale_by
	var h := 0.27 * scale_by
	if strap:
		draw_line(at + Vector2(-0.92, 0), at + Vector2(0.92, 0), _s.darkened(0.2), 0.16 * scale_by, true)
	var frame := _rounded_rect(Rect2(at.x - w, at.y - h, w * 2.0, h * 2.0), h * 0.9)
	draw_colored_polygon(frame, _s)
	var inner := _rounded_rect(Rect2(at.x - w + 0.08, at.y - h + 0.07, w * 2.0 - 0.16, h * 2.0 - 0.14), h * 0.7)
	draw_colored_polygon(inner, lens)
	draw_rect(Rect2(at.x - 0.07 * scale_by, at.y + h * 0.15, 0.14 * scale_by, h * 0.85), _s) # nose bridge
	draw_line(at + Vector2(-w * 0.6, -h * 0.35), at + Vector2(-w * 0.25, -h * 0.55), Color(1, 1, 1, 0.45), 0.05, true)


# --- headgear -----------------------------------------------------------------------------

func _draw_headgear() -> void:
	match look.head:
		Look.Head.HELMET, Look.Head.HELMET_GOGGLES:
			_helmet()
			if look.head == Look.Head.HELMET_GOGGLES:
				_goggles(Vector2(0, -0.66), 0.85, Look.TINTS[look.tint], false)
		Look.Head.BEANIE, Look.Head.BEANIE_HEADSET:
			var dome := _ell(Vector2(0, -0.28), Vector2(0.95, 0.95))
			_fill(dome, _p, _above(-0.28))
			for i in 7:
				var x := -0.75 + i * 0.25
				draw_line(Vector2(x, -0.48), Vector2(x * 0.6, -1.05), _p.darkened(0.15), 0.04, true)
			_fill(dome, _s, _band(-0.52, -0.26)) # folded cuff
			if look.head == Look.Head.BEANIE_HEADSET:
				draw_polyline(_arc_pts(Vector2(0, -0.1), Vector2(1.0, 1.08), PI, TAU), GEAR_DARK, 0.13, true)
				for sx in [-1.0, 1.0]:
					draw_colored_polygon(_ell(Vector2(0.95 * sx, 0.02), Vector2(0.22, 0.32), 16), GEAR_DARK)
					draw_colored_polygon(_ell(Vector2(0.95 * sx, 0.02), Vector2(0.12, 0.2), 12), _s)
				draw_polyline(PackedVector2Array([Vector2(-0.95, 0.25), Vector2(-0.8, 0.55), Vector2(-0.4, 0.66)]), GEAR_DARK, 0.06, true)
				draw_circle(Vector2(-0.34, 0.66), 0.08, GEAR_DARK)
		Look.Head.CAP_FORWARD:
			_fill(_ell(Vector2(0, -0.32), Vector2(0.92, 0.85)), _p, _above(-0.32))
			draw_line(Vector2(0, -1.15), Vector2(0, -0.35), _p.darkened(0.2), 0.04, true)
			_fill(_face, Color(0, 0, 0, 0.18), _band(-0.32, -0.12)) # brim shadow
			_fill(_ell(Vector2(0, -0.33), Vector2(1.02, 0.22)), _s, _below(-0.34))
			draw_circle(Vector2(0, -0.72), 0.13, _s)
		Look.Head.CAP_BACKWARD:
			_fill(_ell(Vector2(0, -1.08), Vector2(0.62, 0.17)), _s, _above(-1.08)) # brim poking up behind
			_fill(_ell(Vector2(0, -0.32), Vector2(0.92, 0.85)), _p, _above(-0.36))
			# Snapback opening over the forehead.
			_fill(_ell(Vector2(0, -0.36), Vector2(0.24, 0.24), 16), _hair if look.hair_style != 3 else _skin, _above(-0.36))
			draw_line(Vector2(-0.24, -0.46), Vector2(0.24, -0.46), _s, 0.07, true)
		Look.Head.BOONIE:
			var brim := _ell(Vector2(0, -0.42), Vector2(1.5, 0.27))
			for sx in [-1.0, 1.0]:
				draw_line(Vector2(1.05 * sx, -0.3), Vector2(0.55 * sx, 0.95), _s.darkened(0.2), 0.04, true) # chin cord
			draw_colored_polygon(brim, _p.darkened(0.12))
			draw_polyline(_closed(brim), _p.darkened(0.35), 0.05, true)
			_fill(_ell(Vector2(0, -0.45), Vector2(0.82, 0.72)), _p, _above(-0.45))
			_fill(_ell(Vector2(0, -0.45), Vector2(0.82, 0.72)), _s.darkened(0.15), _band(-0.62, -0.45))
		Look.Head.HAIR:
			pass


func _helmet() -> void:
	var shell := PackedVector2Array()
	for p in _arc_pts(Vector2(0, -0.22), Vector2(1.1, 1.0), PI, TAU, 24):
		shell.append(p)
	shell.append_array(PackedVector2Array([Vector2(1.1, 0.12), Vector2(0.9, 0.12), Vector2(0.86, -0.3),
		Vector2(-0.86, -0.3), Vector2(-0.9, 0.12), Vector2(-1.1, 0.12)]))
	for sx in [-1.0, 1.0]: # chin strap
		draw_polyline(PackedVector2Array([Vector2(1.0 * sx, 0.1), Vector2(0.62 * sx, 0.82), Vector2(0, 1.02)]), _s.darkened(0.25), 0.07, true)
	draw_colored_polygon(shell, _p)
	_fill(shell, _s, _band(-0.62, -0.5)) # cover band
	draw_polyline(PackedVector2Array([Vector2(-1.1, 0.12), Vector2(-0.9, 0.12), Vector2(-0.86, -0.3), Vector2(0.86, -0.3), Vector2(0.9, 0.12), Vector2(1.1, 0.12)]),
		_p.darkened(0.4), 0.07, true)
	if look.eyes == Look.Eyes.NIGHT_VISION:
		draw_colored_polygon(_rounded_rect(Rect2(-0.24, -0.92, 0.48, 0.3), 0.06), _s) # NVG shroud
		draw_rect(Rect2(-0.11, -0.66, 0.22, 0.46), GEAR_DARK.lightened(0.1)) # mount arm
		draw_colored_polygon(_rounded_rect(Rect2(-0.36, -0.28, 0.72, 0.26), 0.08), GEAR_DARK)
		for sx in [-1.0, 1.0]:
			var p := Vector2(0.34 * sx, -0.08)
			draw_circle(p, 0.29, GEAR_DARK.lightened(0.12))
			draw_circle(p, 0.2, Color("#0e1113"))
			draw_circle(p, 0.12, Color(0.3, 1.0, 0.45, 0.9))
			draw_circle(p + Vector2(-0.04, -0.04), 0.04, Color(0.85, 1.0, 0.85, 0.9))
	else:
		draw_rect(Rect2(-0.18, -0.95, 0.36, 0.22), _s.darkened(0.1)) # velcro patch


# --- geometry helpers ---------------------------------------------------------------------

func _fill(poly: PackedVector2Array, color: Color, clip: PackedVector2Array) -> void:
	for part in Geometry2D.intersect_polygons(poly, clip):
		if part.size() >= 3:
			draw_colored_polygon(part, color)


static func _above(y: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-5, -5), Vector2(5, -5), Vector2(5, y), Vector2(-5, y)])


static func _below(y: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-5, y), Vector2(5, y), Vector2(5, 5), Vector2(-5, 5)])


static func _band(y0: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-5, y0), Vector2(5, y0), Vector2(5, y1), Vector2(-5, y1)])


static func _ell(center: Vector2, radii: Vector2, points := 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points:
		var a := TAU * i / points
		out.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return out


static func _arc_pts(center: Vector2, radii: Vector2, from: float, to: float, points := 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points + 1:
		var a := lerpf(from, to, float(i) / points)
		out.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return out


static func _rounded_rect(rect: Rect2, radius: float) -> PackedVector2Array:
	var rr := minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	var out := PackedVector2Array()
	var corners := [[rect.end - Vector2(rr, rr), 0.0], [Vector2(rect.position.x + rr, rect.end.y - rr), PI / 2.0],
		[rect.position + Vector2(rr, rr), PI], [Vector2(rect.end.x - rr, rect.position.y + rr), PI * 1.5]]
	for cn in corners:
		for i in 5:
			var a: float = cn[1] + (PI / 2.0) * i / 4.0
			out.append(cn[0] + Vector2(cos(a), sin(a)) * rr)
	return out


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.append(poly[0])
	return out

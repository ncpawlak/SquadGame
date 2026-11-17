class_name AbilityEmblem
extends Control
## A round tier emblem for an ability (issue #124): bronze = one star, silver = two, gold = three, in the
## tier's colour; locked = a grey padlock; empty = an open ring (a free slot). Drawn in code, any size.

const COLORS := [Color("#6b7280"), Color("#cd7f32"), Color("#c3ccd8"), Color("#f5c542")]
const INK := Color("#0b1220")

var tier := 0
var empty := false


func _init(tier_value := 0, px := 40.0, is_empty := false) -> void:
	tier = clampi(tier_value, 0, 3)
	empty = is_empty
	custom_minimum_size = Vector2(px, px)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if empty:
		draw_arc(c, r - 2.0, 0.0, TAU, 48, UiKit.LINE, 2.0, true)
		return
	var col: Color = COLORS[tier]
	draw_circle(c, r, col.darkened(0.4))
	draw_circle(c, r - r * 0.09, col)
	draw_arc(c, r * 0.78, 0.0, TAU, 48, col.lightened(0.5), maxf(1.0, r * 0.06), true)
	if tier == 0:
		_lock(c, r)
		return
	var spots: Array[Vector2] = []
	var outer := r * 0.48
	match tier:
		1:
			spots = [Vector2.ZERO]
		2:
			spots = [Vector2(-0.3, 0.0) * r, Vector2(0.3, 0.0) * r]
			outer = r * 0.3
		_:
			spots = [Vector2(0.0, -0.28) * r, Vector2(-0.3, 0.2) * r, Vector2(0.3, 0.2) * r]
			outer = r * 0.27
	for p in spots:
		_star(c + p, outer)


func _star(at: Vector2, outer: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2.0 + i * PI / 5.0
		var rad := outer if i % 2 == 0 else outer * 0.42
		pts.append(at + Vector2(cos(ang), sin(ang)) * rad)
	draw_colored_polygon(pts, INK)


func _lock(c: Vector2, r: float) -> void:
	var body := Rect2(c.x - r * 0.3, c.y - r * 0.02, r * 0.6, r * 0.46)
	draw_arc(Vector2(c.x, c.y - r * 0.02), r * 0.2, PI, TAU, 16, Color(1, 1, 1, 0.9), maxf(1.5, r * 0.1), true)
	draw_rect(body, Color(1, 1, 1, 0.9))

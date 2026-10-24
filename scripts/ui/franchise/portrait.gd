class_name Portrait
extends Control
## Placeholder profile picture: a circle with a head-and-shoulders silhouette whose skin,
## headgear and uniform are picked deterministically from the soldier id.

const SKIN := [Color("#f1c9a5"), Color("#e0ac85"), Color("#c68d63"), Color("#a46c45"), Color("#7a4e2f"), Color("#553522")]
const HEADGEAR := [Color("#4b5320"), Color("#2b2b2b"), Color("#6b5b3e"), Color("#3a3f4a"), Color("#1f3a5f"), Color("#5c4033"), Color("#c2a878")]
const UNIFORM := [Color("#556b2f"), Color("#3b3b3b"), Color("#8a7a5a"), Color("#2f4f4f"), Color("#283b5b"), Color("#4a4a2a")]
const BACKDROP := [Color("#1e293b"), Color("#22313f"), Color("#2a2438"), Color("#1f3330"), Color("#33291f")]

var _skin: Color
var _gear: Color
var _uniform: Color
var _bg: Color
var _ring: Color
var _helmet: bool


func _init(id: int, diameter := 48, ring := UiKit.LINE) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id * 7919 + 17)
	_skin = SKIN[rng.randi_range(0, SKIN.size() - 1)]
	_gear = HEADGEAR[rng.randi_range(0, HEADGEAR.size() - 1)]
	_uniform = UNIFORM[rng.randi_range(0, UNIFORM.size() - 1)]
	_bg = BACKDROP[rng.randi_range(0, BACKDROP.size() - 1)]
	_helmet = rng.randf() < 0.6
	_ring = ring
	custom_minimum_size = Vector2(diameter, diameter)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var d: float = minf(size.x, size.y)
	var r := d / 2.0
	var c := Vector2(size.x / 2.0, size.y / 2.0)
	var clip := _ellipse(c, Vector2(r, r) * 0.97)
	draw_circle(c, r, _bg)
	var head := c + Vector2(0, -r * 0.14)
	draw_rect(Rect2(head.x - r * 0.14, head.y, r * 0.28, r * 0.6), _skin.darkened(0.15))
	# Shoulders: a wide ellipse at the bottom, clipped to the circle.
	for poly in Geometry2D.intersect_polygons(clip, _ellipse(c + Vector2(0, r * 0.92), Vector2(r * 0.8, r * 0.58))):
		draw_colored_polygon(poly, _uniform)
	draw_circle(head, r * 0.34, _skin)
	# Helmet or hair: the top part of a slightly larger circle around the head.
	var cap_r := r * (0.4 if _helmet else 0.36)
	var cap_cut := head.y - r * (0.02 if _helmet else 0.12)
	var above := PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, cap_cut), Vector2(0, cap_cut)])
	for poly in Geometry2D.intersect_polygons(_ellipse(head, Vector2(cap_r, cap_r)), above):
		draw_colored_polygon(poly, _gear)
	if _helmet:
		draw_line(Vector2(head.x - cap_r, cap_cut), Vector2(head.x + cap_r, cap_cut), _gear.darkened(0.3), maxf(1.5, r * 0.06))
	draw_arc(c, r - 1.0, 0.0, TAU, 48, _ring, 2.0, true)


static func _ellipse(center: Vector2, radii: Vector2, points := 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points:
		var a := TAU * i / points
		out.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return out

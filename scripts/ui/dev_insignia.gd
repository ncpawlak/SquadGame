class_name DevInsignia
extends Control
## Dev-star insignia, drawn like military rank stars: 1 star, 2 side by side, 3 in a triangle,
## 4 in a 2x2 square. Always sized for the 2x2 formation so rows of insignia line up.

const GOLD := Color("#f5c542")
const SHADOW := Color(0, 0, 0, 0.55)
## Center spacing between stars, as a multiple of the star size.
const SPACING := 1.08
## Unit offsets (0..1 on each axis of the 2x2 grid) per star count.
const FORMATIONS := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.0, 0.5), Vector2(1.0, 0.5)],
	3: [Vector2(0.5, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0)],
	4: [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0)],
}

var stars := 1
var star_size := 12.0
var color := GOLD


static func make(n: int, size := 12.0, col := GOLD) -> DevInsignia:
	var d := DevInsignia.new()
	d.stars = clampi(n, Soldier.DEV_MIN, Soldier.DEV_MAX)
	d.star_size = size
	d.color = col
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.custom_minimum_size = box_size(size)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.tooltip_text = "%d-star developer" % d.stars
	return d


static func box_size(size: float) -> Vector2:
	var side := size * (1.0 + SPACING) + 2.0
	return Vector2(side, side)


## Star centers inside a box of `box` for `n` stars.
static func centers(n: int, size: float, box: Vector2) -> Array[Vector2]:
	var gap := size * SPACING
	var origin := (box - Vector2(gap, gap)) / 2.0
	var out: Array[Vector2] = []
	for u in FORMATIONS[clampi(n, Soldier.DEV_MIN, Soldier.DEV_MAX)]:
		out.append(origin + u * gap)
	return out


## A five-point star (10 vertices, point up) of outer radius `r` around `c`.
static func star_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var rad := r if i % 2 == 0 else r * 0.42
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	return pts


func _draw() -> void:
	var r := star_size / 2.0
	for c in centers(stars, star_size, size):
		draw_colored_polygon(star_points(c + Vector2(1, 1), r), SHADOW)
		draw_colored_polygon(star_points(c, r), color)

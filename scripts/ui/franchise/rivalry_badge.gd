class_name RivalryBadge
extends Control
## The mark between the two teams on a rivalry matchup: a flame for a team-specific rivalry, two
## clashing chevrons (in the teams' colours) for a divisional one, stacked when both apply.

const ICON := 56.0
const GAP := 2.0
const FLAME := Color("#f97316")
const FLAME_CORE := Color("#fde68a")

## Outline points of the flame, relative to its centre (the core is the same shape, scaled).
const FLAME_POINTS: Array[Vector2] = [
	Vector2(1, -26), Vector2(9, -13), Vector2(16, -2), Vector2(16, 10), Vector2(9, 21), Vector2(0, 25),
	Vector2(-9, 21), Vector2(-16, 10), Vector2(-15, -1), Vector2(-9, -7), Vector2(-7, -16),
]
## The left chevron of the clash (the right one is its mirror).
const CHEVRON_POINTS: Array[Vector2] = [
	Vector2(-25, -19), Vector2(-12, -19), Vector2(1, 0), Vector2(-12, 19), Vector2(-25, 19), Vector2(-12, 0),
]

var _flags := 0
var _left := Color.WHITE
var _right := Color.WHITE


## `flags` is Rivalries.DIVISIONAL and/or Rivalries.TEAM; the colours are the two teams' accents.
func setup(flags: int, left: Color, right: Color, tip := "") -> void:
	_flags = flags
	_left = left
	_right = right
	tooltip_text = tip
	mouse_filter = Control.MOUSE_FILTER_STOP if tip != "" else Control.MOUSE_FILTER_IGNORE
	var icons := _icon_count()
	custom_minimum_size = Vector2(ICON + 24.0, ICON * icons + GAP * (icons - 1))
	queue_redraw()


func _icon_count() -> int:
	return (1 if _flags & Rivalries.TEAM else 0) + (1 if _flags & Rivalries.DIVISIONAL else 0)


func _draw() -> void:
	var cx := size.x * 0.5
	var y := ICON * 0.5
	if _flags & Rivalries.TEAM:
		_draw_flame(Vector2(cx, y))
		y += ICON + GAP
	if _flags & Rivalries.DIVISIONAL:
		_draw_clash(Vector2(cx, y))


func _draw_flame(c: Vector2) -> void:
	draw_colored_polygon(_moved(FLAME_POINTS, c, 1.0), FLAME)
	draw_colored_polygon(_moved(FLAME_POINTS, c + Vector2(0, 7), 0.5), FLAME_CORE)


func _draw_clash(c: Vector2) -> void:
	var left := _moved(CHEVRON_POINTS, c + Vector2(-3, 0), 1.0)
	var right := PackedVector2Array()
	for p in CHEVRON_POINTS:
		right.append(c + Vector2(3 - p.x, p.y))
	right.reverse()
	draw_colored_polygon(left, _left)
	draw_colored_polygon(right, _right)


static func _moved(points: Array[Vector2], c: Vector2, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(c + p * scale)
	return out

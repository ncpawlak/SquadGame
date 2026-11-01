class_name CapBar
extends Control
## Thin 0-99 group-rating bar for the Player Progression screen: filled up to the rating, black up
## to the cap (headroom), greyed past the cap (locked), with dividers every 5 points and the cap
## labelled above its tick. `preview` brightens the next +1 slice (hovering an upgradable group).

const BAR_H := 8.0
const LABEL_H := 16.0
const HEADROOM := Color("#05070c")
const LOCKED := Color("#5d6678")

var rating: int
## -1 = no cap (view-only groups).
var cap: int
var color: Color
var preview := false:
	set(v):
		preview = v
		queue_redraw()


func _init(group_rating: int, group_cap: int, fill: Color) -> void:
	rating = clampi(group_rating, 0, Stats.MAX_RATING)
	cap = clampi(group_cap, rating, Stats.MAX_RATING) if group_cap >= 0 else -1
	color = fill
	custom_minimum_size = Vector2(240, LABEL_H + BAR_H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _x(v: float) -> float:
	return size.x * v / float(Stats.MAX_RATING)


func _draw() -> void:
	var y := size.y - BAR_H
	draw_rect(Rect2(0, y, size.x, BAR_H), HEADROOM)
	draw_rect(Rect2(0, y, _x(rating), BAR_H), color)
	if cap >= 0 and cap < Stats.MAX_RATING:
		draw_rect(Rect2(_x(cap), y, size.x - _x(cap), BAR_H), LOCKED)
	if preview and cap > rating:
		draw_rect(Rect2(_x(rating), y, _x(1), BAR_H), Color(color.lightened(0.35), 0.85))
	for v in range(5, Stats.MAX_RATING, 5):
		var x := roundf(_x(v))
		draw_line(Vector2(x, y), Vector2(x, y + BAR_H), Color(0, 0, 0, 0.55), 1.0)
	if cap < 0:
		return
	var cx := _x(cap)
	draw_line(Vector2(cx, y - 3), Vector2(cx, y + BAR_H), Color.WHITE, 2.0)
	var font := get_theme_default_font()
	var fs := 12
	var text := "CAP %d" % cap
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tx := clampf(cx - w / 2.0, 0.0, maxf(0.0, size.x - w))
	draw_string(font, Vector2(tx, y - 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.MUTED)

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
## Rating drawn right now (tweens up to `rating` after an upgrade).
var _shown := -1.0
## Left-to-right highlight sweep, 0..1 across the bar (-1 = off) and the glow on the new slice.
var _sweep := -1.0
var _glow := 0.0
var _from := 0
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


## Play an upgrade from `old` to the current rating: a bright band sweeps left to right across the
## filled part, the fill then grows to the new rating and the new slice glows before settling.
func play_gain(old: int) -> void:
	if Fx.is_reduced() or old >= rating:
		return
	_from = old
	_shown = float(old)
	queue_redraw()
	Fx.after_layout(self, func():
		Fx.cue(&"rating_up")
		var tw := Fx.tween(self, true)
		tw.tween_method(func(x: float):
			_sweep = x
			queue_redraw(), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_method(func(x: float):
			_shown = x
			queue_redraw(), float(old), float(rating), 0.45).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(x: float):
			_glow = x
			queue_redraw(), 1.0, 0.0, 0.55).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func():
			_shown = -1.0
			_sweep = -1.0
			_glow = 0.0
			queue_redraw()))


func _x(v: float) -> float:
	return size.x * v / float(Stats.MAX_RATING)


func _draw() -> void:
	var y := size.y - BAR_H
	draw_rect(Rect2(0, y, size.x, BAR_H), HEADROOM)
	var shown: float = float(rating) if _shown < 0.0 else _shown
	draw_rect(Rect2(0, y, _x(shown), BAR_H), color)
	if _glow > 0.0:
		draw_rect(Rect2(_x(_from), y - 2, maxf(_x(rating - _from), 4.0), BAR_H + 4), Color(1, 1, 1, 0.6 * _glow))
	if _sweep >= 0.0 and _sweep <= 1.0:
		var band := maxf(24.0, size.x * 0.12)
		var sx := (_x(maxf(float(rating), 1.0)) + band) * _sweep - band
		var x0 := clampf(sx, 0.0, _x(shown))
		var x1 := clampf(sx + band, 0.0, _x(shown))
		if x1 > x0:
			draw_rect(Rect2(x0, y, x1 - x0, BAR_H), Color(1, 1, 1, 0.7))
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

class_name RingGauge
extends Control
## Circular gauge (Madden player-card style): a track ring, a coloured arc filled to
## value / max_value, and the value text in the middle.

var _fraction := 0.0
var _color: Color
var _text: String
var _thickness: float
var logo: Texture2D


func _init(value: float, max_value: float, color: Color, text: String, diameter := 84) -> void:
	_fraction = clampf(value / maxf(0.001, max_value), 0.0, 1.0)
	_color = color
	_text = text
	_thickness = maxf(4.0, diameter * 0.09)
	custom_minimum_size = Vector2(diameter, diameter)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var d := minf(size.x, size.y)
	var r := d / 2.0 - _thickness / 2.0 - 1.0
	var c := size / 2.0
	draw_arc(c, r, 0.0, TAU, 64, UiKit.LINE, _thickness, true)
	if _fraction > 0.0:
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * _fraction, 64, _color, _thickness, true)
	if logo != null:
		var inner := (r - _thickness / 2.0) * 2.0 * 0.86
		draw_texture_rect(logo, Rect2(c - Vector2(inner, inner) / 2.0, Vector2(inner, inner)), false)
		return
	var font := get_theme_default_font()
	var fs := int(d * 0.3)
	var w := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - w / 2.0, c.y + fs * 0.36), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

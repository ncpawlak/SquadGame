class_name TierBar
extends Control
## Five-segment class-tier bar for a scouted stat group: segments inside the revealed window are lit in
## their tier colour (bright outline on the window's ends), the rest are dark. A group that has not been
## scouted yet is all dark with a "?".

const COLORS: Array[Color] = [Color("#ef4444"), Color("#f97316"), Color("#e5e7eb"), Color("#38bdf8"), Color("#22c55e")]
const GAP := 4.0

## Vector2i(low_tier, high_tier), or null when never scouted.
var window: Variant = null


func _init(w: Variant = null, height := 22.0) -> void:
	window = w
	custom_minimum_size = Vector2(60, height)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var n := COLORS.size()
	var seg_w := (size.x - GAP * (n - 1)) / n
	for t in n:
		var rect := Rect2(t * (seg_w + GAP), 0, seg_w, size.y)
		var lit: bool = window != null and t >= (window as Vector2i).x and t <= (window as Vector2i).y
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.bg_color = COLORS[t] if lit else UiKit.LINE
		if lit:
			sb.set_border_width_all(1)
			sb.border_color = COLORS[t].lightened(0.35)
		draw_style_box(sb, rect)
	if window == null:
		var font := get_theme_default_font()
		var fs := int(size.y * 0.7)
		var w := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - w) / 2.0, size.y * 0.78), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.MUTED)

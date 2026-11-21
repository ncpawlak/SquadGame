class_name FpsHud
extends CanvasLayer
## Crosshair that widens with spread, ammo, health, stamina and a hit marker.
## Everything is built in code; call bind(player) (or set `player`) to hook it up.

var player: FpsPlayer = null
var overlay: Control
var ammo_label: Label
var mode_label: Label
var health_bar: ProgressBar
var stamina_bar: ProgressBar
var _hit_t: float = 0.0
var _hit_color := Color.WHITE
var _spread_px: float = 8.0


func _ready() -> void:
	layer = 10
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	ammo_label = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-220, -70), 32)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mode_label = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-220, -100), 16)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health_bar = _bar(Vector2(30, -70), Color(0.85, 0.2, 0.2))
	stamina_bar = _bar(Vector2(30, -40), Color(0.95, 0.8, 0.25))
	if player:
		bind(player)


func _label(preset: Control.LayoutPreset, offset: Vector2, size: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.position = offset
	l.size = Vector2(200, 40)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	overlay.add_child(l)
	return l


func _bar(offset: Vector2, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	b.position = offset
	b.size = Vector2(260, 18)
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	overlay.add_child(b)
	return b


func bind(p: FpsPlayer) -> void:
	player = p
	if not is_inside_tree() or overlay == null:
		return
	if not p.shot_fired.is_connected(_on_shot):
		p.shot_fired.connect(_on_shot)


func _on_shot(result: Dictionary) -> void:
	if not result.get("hit", false):
		return
	var t = result.get("target", null)
	if t == null:
		return
	show_hit_marker(bool(result.get("headshot", false)))


func show_hit_marker(headshot: bool = false) -> void:
	_hit_t = 0.25
	_hit_color = Color(1.0, 0.25, 0.2) if headshot else Color.WHITE


## Crosshair radius in pixels for a cone half-angle (degrees) and camera fov (degrees, vertical).
static func spread_to_pixels(spread_deg: float, fov_deg: float, viewport_h: float) -> float:
	return tan(deg_to_rad(spread_deg)) / tan(deg_to_rad(fov_deg) * 0.5) * viewport_h * 0.5


func _process(delta: float) -> void:
	_hit_t = maxf(0.0, _hit_t - delta)
	if player and is_instance_valid(player) and player.weapon:
		var w := player.weapon
		var ammo_txt := "%d / %s" % [w.ammo, "∞" if w.infinite_reserve else str(w.reserve)]
		ammo_label.text = "RELOAD..." if w.reloading else ammo_txt
		mode_label.text = "%s  [%s]" % [w.def.get("name", ""), String(w.fire_mode).to_upper()]
		health_bar.value = player.health / maxf(player.max_health, 1.0)
		stamina_bar.value = player.stamina_fraction()
		var target_px := spread_to_pixels(w.current_spread(), player.camera.fov, get_viewport().get_visible_rect().size.y)
		_spread_px = lerpf(_spread_px, target_px, clampf(delta * 18.0, 0.0, 1.0))
	overlay.queue_redraw()


func _draw_overlay() -> void:
	var c := overlay.size * 0.5
	var gap := maxf(4.0, _spread_px)
	var col := Color(1, 1, 1, 0.9)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		overlay.draw_line(c + d * gap, c + d * (gap + 10.0), col, 2.0)
	overlay.draw_circle(c, 1.5, col)
	if _hit_t > 0.0:
		var a := _hit_t / 0.25
		var hc := Color(_hit_color, a)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			overlay.draw_line(c + d * 7.0, c + d * 15.0, hc, 3.0)

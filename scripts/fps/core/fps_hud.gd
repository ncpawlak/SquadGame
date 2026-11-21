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
var _hits: Array = []  # recent hits taken: {pos, t}


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
	if not p.damaged.is_connected(_on_damaged):
		p.damaged.connect(_on_damaged)


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
	for h in _hits:
		h["t"] = float(h["t"]) - delta * 1.2
	_hits = _hits.filter(func(h): return float(h["t"]) > 0.0)
	if player and is_instance_valid(player) and player.weapon:
		var w := player.weapon
		var ammo_txt := "%d / %s" % [w.ammo, "∞" if w.infinite_reserve else str(w.reserve)]
		ammo_label.text = "RELOAD..." if w.reloading else ammo_txt
		mode_label.text = "%s  [%s]" % [w.def.get("name", ""), String(w.fire_mode).to_upper()]
		health_bar.value = player.health / maxf(player.max_health, 1.0)
		stamina_bar.value = player.stamina_fraction()
		var target_px := spread_to_pixels(w.current_spread(), player.camera.fov, get_viewport().get_visible_rect().size.y)
		_spread_px = lerpf(_spread_px, target_px, clampf(delta * 30.0, 0.0, 1.0))
	overlay.queue_redraw()


## The crosshair's offset from the screen centre in pixels: recoil climb, sway and flinch move the crosshair, not the camera.
static func aim_to_pixels(aim_deg: Vector2, fov_deg: float, viewport_h: float) -> Vector2:
	var k := viewport_h * 0.5 / tan(deg_to_rad(fov_deg) * 0.5)
	return Vector2(-tan(deg_to_rad(aim_deg.y)) * k, -tan(deg_to_rad(aim_deg.x)) * k)


func _on_damaged(_amount: float, source) -> void:
	var pos := Vector3.INF
	if source is Node3D and is_instance_valid(source):
		pos = (source as Node3D).global_position
	_hits.append({"pos": pos, "t": 1.0})


## Bearing of a world point from the camera's forward direction, in radians (0 = ahead, positive = right).
func _bearing(world_pos: Vector3) -> float:
	var local := player.camera.global_transform.basis.inverse() * (world_pos - player.camera.global_position)
	return atan2(local.x, -local.z)


func _ring_point(c: Vector2, bearing: float, radius: float) -> Vector2:
	return c + Vector2(sin(bearing), -cos(bearing)) * radius


## Opacity of the white "you are being shot at" vignette for a suppression value (0 none .. 1.5 heavy): 0 up to ~0.6.
static func vignette_alpha(suppression: float) -> float:
	return clampf(suppression, 0.0, 1.0) * 0.6


## White edges that fade inward. Drawn while he is being shot at (hit or shot near), so the screen reads as under fire.
func _draw_vignette() -> void:
	if player == null or not is_instance_valid(player) or player.weapon == null:
		return
	var a := vignette_alpha(player.weapon.suppression)
	if a <= 0.01:
		return
	var sz := overlay.size
	var t := minf(sz.x, sz.y) * 0.22
	var edge := Color(1, 1, 1, a)
	var clear := Color(1, 1, 1, 0.0)
	var strips := [
		[PackedVector2Array([Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, t), Vector2(0, t)]), [edge, edge, clear, clear]],
		[PackedVector2Array([Vector2(0, sz.y), Vector2(sz.x, sz.y), Vector2(sz.x, sz.y - t), Vector2(0, sz.y - t)]), [edge, edge, clear, clear]],
		[PackedVector2Array([Vector2(0, 0), Vector2(0, sz.y), Vector2(t, sz.y), Vector2(t, 0)]), [edge, edge, clear, clear]],
		[PackedVector2Array([Vector2(sz.x, 0), Vector2(sz.x, sz.y), Vector2(sz.x - t, sz.y), Vector2(sz.x - t, 0)]), [edge, edge, clear, clear]],
	]
	for st in strips:
		overlay.draw_polygon(st[0], PackedColorArray(st[1]))


func _draw_overlay() -> void:
	_draw_vignette()
	var centre := overlay.size * 0.5
	var c := centre
	var w: FpsWeapon = null
	if player and is_instance_valid(player) and player.weapon:
		w = player.weapon
		c = centre + aim_to_pixels(w.aim_offset(), player.camera.fov, get_viewport().get_visible_rect().size.y)
	var gap := maxf(4.0, _spread_px)
	var col := Color(1, 1, 1, 0.9)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		overlay.draw_line(c + d * gap, c + d * (gap + 10.0), col, 2.0)
	overlay.draw_circle(c, 1.5, col)
	# Reload meter: a ring around the crosshair that fills as the reload completes (faster with the Reload rating).
	if w != null and w.reloading:
		var total := maxf(0.01, w.reload_duration())
		var frac := clampf(1.0 - w.reload_left / total, 0.0, 1.0)
		var r := gap + 26.0
		overlay.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.18), 4.0)
		overlay.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color(1.0, 0.8, 0.25, 0.95), 4.0)
	if _hit_t > 0.0:
		var a := _hit_t / 0.25
		var hc := Color(_hit_color, a)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			overlay.draw_line(c + d * 7.0, c + d * 15.0, hc, 3.0)
	if player == null or not is_instance_valid(player) or player.camera == null:
		return
	_draw_awareness(centre)
	_draw_hits(centre)
	_draw_hill(centre)


## Awareness: ticks on a ring around the centre point toward enemies inside the player's sensing radius (never a wallhack:
## only a bearing, brighter the closer they are). Higher Awareness senses further.
func _draw_awareness(centre: Vector2) -> void:
	var radius := FpsRatings.awareness_radius(player.rating_stats())
	var ring := 120.0
	for group in [&"fps_bot", &"fps_player"]:
		for n in get_tree().get_nodes_in_group(group):
			if n == player or not (n is Node3D):
				continue
			if n.get("team_id") != null and n.get("team_id") == player.team_id:
				continue
			if n.get("alive") == false or n.get("dead") == true:
				continue
			var d := player.global_position.distance_to((n as Node3D).global_position)
			if d > radius:
				continue
			var b := _bearing((n as Node3D).global_position)
			var near := 1.0 - d / radius
			var p1 := _ring_point(centre, b, ring)
			var p2 := _ring_point(centre, b, ring + 8.0 + 8.0 * near)
			overlay.draw_line(p1, p2, Color(1.0, 0.35, 0.3, 0.3 + 0.6 * near), 3.0)


## Where recent hits came from: a red arc on the ring toward the shooter, fading out.
func _draw_hits(centre: Vector2) -> void:
	for h in _hits:
		if h["pos"] == Vector3.INF:
			continue
		var b := _bearing(h["pos"])
		var a := clampf(float(h["t"]), 0.0, 1.0)
		var r := 140.0
		overlay.draw_arc(centre, r, b - PI * 0.5 - 0.3, b - PI * 0.5 + 0.3, 12, Color(1.0, 0.15, 0.1, a), 6.0)


## Objective IQ sets what the hill readout tells you: 0 a bearing and distance, 1 plus who holds it, 2 plus the timers.
func _draw_hill(centre: Vector2) -> void:
	if not FpsHill.active:
		return
	var font := ThemeDB.fallback_font
	var level := FpsRatings.intel_level(player.rating_stats())
	var dist := Vector2(player.global_position.x - FpsHill.center.x, player.global_position.z - FpsHill.center.z).length()
	var b := _bearing(FpsHill.center)
	overlay.draw_line(_ring_point(centre, b, 150.0), _ring_point(centre, b, 164.0), Color(0.3, 0.9, 0.4, 0.9), 4.0)
	var text := "HILL  %d m" % roundi(dist)
	var st := FpsHill.state
	if level >= 1 and not st.is_empty():
		var holder := int(st.get("holder", -1))
		var zone := int(st.get("zone", 0))
		var who := "NOBODY"
		if zone == int(FpsHillRules.Zone.CONTESTED):
			who = "CONTESTED"
		elif holder >= 0:
			who = "YOUR TEAM" if holder == player.team_id else "ENEMY"
		text += "   ·   %s" % who
	if level >= 2 and not st.is_empty():
		var sc: Array = st.get("scores", [0.0, 0.0])
		var win := float(st.get("hold_to_win", 120.0))
		var mine := float(sc[player.team_id]) if player.team_id < sc.size() else 0.0
		var theirs := float(sc[1 - player.team_id]) if sc.size() > 1 else 0.0
		var left := float(st.get("time_left", 0.0))
		text += "   ·   %d / %d   vs   %d / %d   ·   %d:%02d left" % [roundi(mine), roundi(win), roundi(theirs), roundi(win), int(left) / 60, int(left) % 60]
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	overlay.draw_string(font, Vector2(centre.x - size.x * 0.5, 34.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))

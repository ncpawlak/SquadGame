extends Node3D
## Test arena glue: gives the player a mid-career soldier, a HUD, and R-on-Backspace target reset.
## Keys: WASD move, Shift sprint, Ctrl crouch, Space jump, LMB fire, R reload, V fire mode,
## 1-4 weapons, Backspace pops all targets back up, Esc frees the mouse.
## Rating presets (all 18 ratings): F1 = 20, F2 = 60, F3 = 95. X = get shot at (feel composure), H = toggle a hill here
## (feel anchor, breach and the objective-IQ readout), G = tire out (feel endurance).

@onready var player: FpsPlayer = $Player
@onready var hud: FpsHud = $FpsHud


var _label: Label


func _ready() -> void:
	_apply_preset(60)
	player.infinite_reserve = true
	player.weapon.infinite_reserve = true
	hud.bind(player)
	player.died.connect(func(_src) -> void: player.respawn(Vector3(0, 0.1, 0)))
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_label)
	_refresh_label()


func _apply_preset(rating: int) -> void:
	var s := Soldier.new()
	for st in Stats.ALL:
		s.stats[st] = rating
	player.setup(s)
	_preset = rating
	if _label:
		_refresh_label()


var _preset := 60


func _refresh_label() -> void:
	_label.text = "Ratings %d   (F1 20, F2 60, F3 95)   X shot at   G tired   H hill %s" % [_preset, "ON" if FpsHill.active else "off"]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.physical_keycode:
		KEY_F1:
			_apply_preset(20)
		KEY_F2:
			_apply_preset(60)
		KEY_F3:
			_apply_preset(95)
		KEY_X:
			player.suppress(0.9)
		KEY_G:
			player.fatigue = 1.0
		KEY_H:
			if FpsHill.active:
				FpsHill.clear()
			else:
				FpsHill.set_zone(Vector3(0, 0, -12), 5.0)
				FpsHill.state = {"holder": 1, "zone": FpsHillRules.Zone.TEAM1, "scores": [20.0, 45.0], "time_left": 200.0, "hold_to_win": 120.0}
			_refresh_label()
		KEY_BACKSPACE:
			for t in get_tree().get_nodes_in_group(&"fps_target"):
				(t as FpsTarget).pop_up()

extends Node3D
## Test arena glue: gives the player a mid-career soldier, a HUD, and R-on-Backspace target reset.
## Keys: WASD move, Shift sprint, Ctrl crouch, Space jump, LMB fire, R reload, V fire mode,
## 1-4 weapons, Backspace pops all targets back up, Esc frees the mouse.

@onready var player: FpsPlayer = $Player
@onready var hud: FpsHud = $FpsHud


func _ready() -> void:
	var s := Soldier.new()
	for st in Stats.ALL:
		s.stats[st] = 60
	player.infinite_reserve = true
	player.setup(s)
	player.weapon.infinite_reserve = true
	hud.bind(player)
	player.died.connect(func(_src) -> void: player.respawn(Vector3(0, 0.1, 0)))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_BACKSPACE:
		for t in get_tree().get_nodes_in_group(&"fps_target"):
			(t as FpsTarget).pop_up()

class_name FpsCombineRunner
extends Control
## Runs one 3D combine drill full screen over the combine screen: builds the drill and a first-person player on the
## standard loadout, shows the crosshair HUD and the drill's text, and hands back {stat: score} when it ends.
## Esc quits the drill and keeps whatever it scored so far (the combine keeps the try, as with the 2D mini-games).
##
## Usage: FpsCombineRunner.launch(parent, stat, func(scores: Dictionary): ...)

signal finished(scores: Dictionary)

var drill: FpsDrill
var player: Node3D
var hud: Node
var _label: Label
var _result: Label
var _on_done: Callable
var _ended := false
var _scores := {}
var _hidden: Array = []  # opaque backdrops hidden while the 3D scene shows (restored at the end)


static func launch(parent: Node, stat: StringName, on_done: Callable) -> FpsCombineRunner:
	var r := FpsCombineRunner.new()
	r._on_done = on_done
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	r._hide_backdrops(parent)
	r.start(stat)
	return r


## The app draws an opaque background (a ColorRect) over the whole window, which would hide the 3D scene behind it. Hide any
## full-screen colour rectangles among the parent's children while a drill runs.
func _hide_backdrops(parent: Node) -> void:
	for c in parent.get_children():
		if c is ColorRect and c.visible and c != self:
			c.visible = false
			_hidden.append(c)


func start(stat: StringName) -> void:
	var path := FpsCombineDrills.scene_for(stat)
	if path == "":
		_finish_with({})
		return
	drill = (load(path) as PackedScene).instantiate() as FpsDrill
	add_child(drill)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	_result = Label.new()
	_result.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_result.position.y = 120
	_result.add_theme_font_size_override("font_size", 40)
	_result.add_theme_color_override("font_outline_color", Color.BLACK)
	_result.add_theme_constant_override("outline_size", 8)
	add_child(_result)
	drill.hud_changed.connect(func(t: String) -> void: _label.text = t)
	drill.finished.connect(_on_drill_finished, CONNECT_ONE_SHOT)
	player = FpsDrillHall.make_player(null)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	drill.start(player)
	if player is FpsPlayer:
		var h := FpsHud.new()
		h.player = player as FpsPlayer
		add_child(h)
		hud = h


func _unhandled_input(event: InputEvent) -> void:
	if _ended or drill == null:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		drill.abort()
	elif drill.state == FpsDrill.State.DONE and (event is InputEventKey and event.pressed or event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		_finish_with(_scores)


func _on_drill_finished(score: float) -> void:
	_scores = drill.stat_scores()
	var parts: PackedStringArray = []
	for st in _scores:
		parts.append("%s %d%%" % [Stats.LABELS.get(st, String(st)), roundi(float(_scores[st]) * 100.0)])
	_result.text = "%s    (press any key)" % ", ".join(parts) if not parts.is_empty() else "%d%%" % roundi(score * 100.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player is FpsPlayer:
		(player as FpsPlayer).controls_enabled = false


func _finish_with(scores: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	for c in _hidden:
		if is_instance_valid(c):
			c.visible = true
	_hidden.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	finished.emit(scores)
	if _on_done.is_valid():
		_on_done.call(scores)
	queue_free()

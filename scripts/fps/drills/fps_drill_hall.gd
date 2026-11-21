class_name FpsDrillHall
extends Control
## Lists the 3D drills, runs one with a first-person player, and reports each scored stat through
## `drill_finished(stat, score)` (score 0..1, same meaning as the 2D combine tasks). The obstacle course emits twice
## (SPEED then AGILITY). `hall_closed` fires when the user leaves the hall.
##
## Usage: add the scene, optionally set `soldier`, connect `drill_finished`.

signal drill_finished(stat: StringName, score: float)
signal hall_closed

## Registry: id, title, the stat(s) it feeds, and the scene.
const DRILLS := [
	{"id": &"range_short", "title": "Short range targets", "stat": Stats.SHORT_ACC, "scene": "res://scenes/fps/drills/range_short.tscn"},
	{"id": &"range_medium", "title": "Medium range targets", "stat": Stats.MEDIUM_ACC, "scene": "res://scenes/fps/drills/range_medium.tscn"},
	{"id": &"range_long", "title": "Long range targets", "stat": Stats.LONG_ACC, "scene": "res://scenes/fps/drills/range_long.tscn"},
	{"id": &"grouping", "title": "Burst grouping", "stat": Stats.GROUPING, "scene": "res://scenes/fps/drills/grouping.tscn"},
	{"id": &"sway", "title": "Hold steady (sway)", "stat": Stats.SWAY, "scene": "res://scenes/fps/drills/sway.tscn"},
	{"id": &"course", "title": "Obstacle course", "stat": Stats.AGILITY, "scene": "res://scenes/fps/drills/course.tscn"},
	{"id": &"hold", "title": "Hold the point", "stat": Stats.ANCHOR, "scene": "res://scenes/fps/drills/hold.tscn"},
	{"id": &"reload", "title": "Active reload", "stat": Stats.RELOAD, "scene": "res://scenes/fps/drills/reload.tscn"},
	{"id": &"composure", "title": "Under fire", "stat": Stats.COMPOSURE, "scene": "res://scenes/fps/drills/composure.tscn"},
	{"id": &"callouts", "title": "Squad callouts", "stat": Stats.TEAMWORK, "scene": "res://scenes/fps/drills/callouts.tscn"},
	{"id": &"breach", "title": "Door breach", "stat": Stats.BREACH, "scene": "res://scenes/fps/drills/breach.tscn"},
	{"id": &"defense", "title": "Hill defense", "stat": Stats.OBJ_IQ, "scene": "res://scenes/fps/drills/defense.tscn"},
	{"id": &"maze", "title": "Maze", "stat": Stats.AWARENESS, "scene": "res://scenes/fps/drills/maze.tscn"},
	{"id": &"sled", "title": "Sled push", "stat": Stats.STRENGTH, "scene": "res://scenes/fps/drills/sled.tscn"},
	{"id": &"ruck", "title": "Ruck run", "stat": Stats.ENDURANCE, "scene": "res://scenes/fps/drills/ruck.tscn"},
]
const FPS_PLAYER_CLASS := "FpsPlayer"
const STUB_PLAYER := "res://scripts/fps/drills/stubs/fps_drill_stub_player.gd"

## The soldier whose ratings drive the player (optional; passed to player.setup).
var soldier = null
## Best score per stat from this visit.
var results: Dictionary = {}
var current: FpsDrill
var _menu: VBoxContainer
var _hud: Label
var _result: Label
var _viewport_holder: Node


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_show_menu()


static func drill_ids() -> Array:
	var out: Array = []
	for d in DRILLS:
		out.append(d["id"])
	return out


static func entry(id: StringName) -> Dictionary:
	for d in DRILLS:
		if d["id"] == id:
			return d
	return {}


## Make the player: the real FpsPlayer when core is in the project, else the stub.
static func make_player(s = null) -> Node3D:
	var script_path := ""
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == FPS_PLAYER_CLASS:
			script_path = c["path"]
			break
	if script_path == "":
		script_path = STUB_PLAYER
	var p: Node3D = (load(script_path) as GDScript).new()
	if p.has_method(&"setup"):
		p.call(&"setup", s)
	return p


func _build_ui() -> void:
	_menu = VBoxContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.custom_minimum_size = Vector2(360, 0)
	add_child(_menu)
	_hud = Label.new()
	_hud.position = Vector2(20, 20)
	_hud.add_theme_font_size_override("font_size", 22)
	add_child(_hud)
	_result = Label.new()
	_result.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_result.position.y = 80
	add_child(_result)


func _show_menu() -> void:
	for c in _menu.get_children():
		c.queue_free()
	_hud.text = ""
	_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var head := Label.new()
	head.text = "Drill hall"
	_menu.add_child(head)
	for d in DRILLS:
		var b := Button.new()
		var best: String = "" if not results.has(d["stat"]) else "   best %d%%" % roundi(float(results[d["stat"]]) * 100.0)
		b.text = String(d["title"]) + best
		b.pressed.connect(run_drill.bind(d["id"]))
		_menu.add_child(b)
	var close := Button.new()
	close.text = "Leave"
	close.pressed.connect(func(): hall_closed.emit())
	_menu.add_child(close)


## Start a drill by id. Returns the drill (or null for an unknown id). Cancels a run in progress.
func run_drill(id: StringName) -> FpsDrill:
	var e := FpsDrillHall.entry(id)
	if e.is_empty():
		return null
	_end_current()
	var scene := load(e["scene"]) as PackedScene
	var d := scene.instantiate() as FpsDrill
	current = d
	_menu.visible = false
	_result.text = ""
	add_child(d)
	d.hud_changed.connect(func(t: String): _hud.text = t)
	d.finished.connect(_on_finished.bind(d), CONNECT_ONE_SHOT)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	d.start(FpsDrillHall.make_player(soldier))
	return d


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and current != null:
		current.abort()
		get_viewport().set_input_as_handled()


func _on_finished(score: float, d: FpsDrill) -> void:
	if d != current:
		return
	report(d)
	_result.text = "%s: %d%%  (Esc / click a drill to go again)" % [d.title, roundi(score * 100.0)]
	var t := get_tree().create_timer(2.0)
	t.timeout.connect(func():
		if current == d:
			_end_current()
			_show_menu())


## Emit drill_finished for each stat the finished drill scored and remember the best.
func report(d: FpsDrill) -> void:
	var scores := d.stat_scores()
	for s in scores:
		var v := FpsDrill.clamp01(float(scores[s]))
		results[s] = maxf(v, float(results.get(s, 0.0)))
		drill_finished.emit(s, v)


func _end_current() -> void:
	if current != null:
		current.queue_free()
		current = null

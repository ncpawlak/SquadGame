class_name CombineTask
extends Control
## Base of every combine mini-game (#101). A task shows a short "Ready" beat, runs, then emits `finished(score)` once
## with a score in 0..1. Subclasses (see CombineTasks) override `_run`, `_draw_task`, and the input hooks. The scoring
## rules live in static functions on CombineTasks so tests can check them without a scene.

signal finished(score: float)

const READY_SECS := 0.9
const FIELD := Vector2(900, 460)

var spec: Dictionary = {}
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var _ready_left := READY_SECS
var _done := false
var score := 0.0


func _init() -> void:
	custom_minimum_size = FIELD
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	rng.randomize()


## One line telling the player what to do (shown on the briefing).
func instructions() -> String:
	return ""


func is_done() -> bool:
	return _done


func finish(value: float) -> void:
	if _done:
		return
	_done = true
	score = clampf(value, 0.0, 1.0)
	queue_redraw()
	finished.emit(score)


func _process(delta: float) -> void:
	if _done:
		return
	if _ready_left > 0.0:
		_ready_left -= delta
		if _ready_left <= 0.0:
			_start()
		queue_redraw()
		return
	elapsed += delta
	_run(delta)
	queue_redraw()


func _start() -> void:
	pass


func _run(_delta: float) -> void:
	pass


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b1220"))
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.LINE, false, 2.0)
	if _ready_left > 0.0:
		_text(spec.get("label", ""), Vector2(size.x / 2.0, size.y / 2.0 - 10), 34, Color.WHITE, true)
		_text("Get ready...", Vector2(size.x / 2.0, size.y / 2.0 + 34), 20, UiKit.MUTED, true)
		return
	_draw_task()


func _draw_task() -> void:
	pass


## Draws text; `centered` puts the string's middle at `at`.
func _text(t: String, at: Vector2, font_size: int, color: Color, centered := false) -> void:
	var font := ThemeDB.fallback_font
	var p := at
	if centered:
		p.x -= font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2.0
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## A small HUD line in the top-left corner.
func _hud(t: String) -> void:
	_text(t, Vector2(16, 28), 18, UiKit.MUTED)

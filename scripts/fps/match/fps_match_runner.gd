class_name FpsMatchRunner
extends Control
## Plays one career fixture in 3D: builds the FpsMatchGame for a ScheduledMatch with the same seed / field / weather the 2D viewer
## uses, puts the crosshair HUD and the match HUD on top, spectates a teammate while the player is dead, and offers an Esc pause
## menu (RESUME / SIM THE REST). The 3D result (or the sim-the-rest merge) goes to `on_done(result: MatchResult)`.
##
## Usage: FpsMatchRunner.launch(parent, m, func(r: MatchResult): ..., human_soldier_or_null)

signal finished(result: MatchResult)

const GAME_SCRIPT := "res://scripts/fps/match/fps_match_game.gd"

## Tests can swap the game builder: func(parent, home, away, seed, human, field, wx) -> Node.
static var game_factory: Callable = Callable()

var match_info: ScheduledMatch
var game: Node = null
var hud: FpsMatchHud = null
var crosshair: Node = null
var human_soldier: Soldier = null
var result: MatchResult = null
var paused_menu := false
var spectating := false

var _on_done: Callable
var _ended := false
var _hidden: Array = []
var _world: Node3D
var _spec_cam: Camera3D
var _spec_idx := 0
var _menu: PanelContainer
var _menu_label: Label
var _busy := false


static func launch(parent: Node, m: ScheduledMatch, on_done: Callable, human: Soldier = null) -> FpsMatchRunner:
	var r := FpsMatchRunner.new()
	r._on_done = on_done
	r.match_info = m
	r.human_soldier = human
	r.process_mode = Node.PROCESS_MODE_ALWAYS
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	r._hide_backdrops(parent)
	if parent.get_parent() != null:
		r._hide_backdrops(parent.get_parent())
	r.start()
	return r


## The app draws an opaque ColorRect over the window, which would hide the 3D scene; hide those while the match runs.
func _hide_backdrops(parent: Node) -> void:
	for c in parent.get_children():
		if c is ColorRect and c.visible and c != self:
			c.visible = false
			_hidden.append(c)


func start() -> void:
	var m := match_info
	WarmUp.begin(m.home, m.away)  # taken off again by ScheduledMatch.set_live_result
	_world = Node3D.new()
	_world.name = "World"
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE  # the runner is ALWAYS (for the menu); the match itself must pause
	add_child(_world)
	var human: Soldier = human_soldier
	if human != null and not (human in m.home.starters() or human in m.away.starters()):
		human = null
	game = _build_game(_world, m, human)
	if game == null:
		push_error("FpsMatchRunner: no match game available")
		_finish(_empty_result())
		return
	var team_id := 0
	var hp = game.get("human")
	if hp != null:
		team_id = int(hp.get("team_id"))
		var ch := FpsHud.new()
		ch.player = hp as FpsPlayer
		add_child(ch)
		crosshair = ch
	elif human != null:
		team_id = 0 if human in m.home.starters() else 1
	hud = FpsMatchHud.make(game, m.home, m.away, team_id)
	add_child(hud)
	_build_menu()
	_spec_cam = Camera3D.new()
	_spec_cam.fov = 75.0
	_world.add_child(_spec_cam)
	if game.has_signal("match_finished"):
		game.connect("match_finished", _on_match_finished)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_game(parent: Node, m: ScheduledMatch, human: Soldier) -> Node:
	if game_factory.is_valid():
		return game_factory.call(parent, m.home, m.away, m.match_seed, human, m.field(), m.weather())
	if not ResourceLoader.exists(GAME_SCRIPT):
		return null
	var g = load(GAME_SCRIPT)
	return g.launch(parent, m.home, m.away, m.match_seed, human, m.field(), m.weather())


func _empty_result() -> MatchResult:
	var r := MatchResult.new()
	r.match_seed = match_info.match_seed
	r.teams = [match_info.home, match_info.away]
	return r


func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.position = Vector2(-160, -100)
	_menu.custom_minimum_size = Vector2(320, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_menu.add_child(v)
	_menu_label = Label.new()
	_menu_label.text = "PAUSED"
	_menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_label.add_theme_font_size_override("font_size", 28)
	v.add_child(_menu_label)
	var resume := Button.new()
	resume.name = "ResumeButton"
	resume.text = "RESUME"
	resume.custom_minimum_size.y = 48
	resume.pressed.connect(resume_play)
	v.add_child(resume)
	var sim := Button.new()
	sim.name = "SimRestButton"
	sim.text = "SIM THE REST"
	sim.custom_minimum_size.y = 48
	sim.tooltip_text = "Stop playing and simulate the rest of the match. Games already played keep their result."
	sim.pressed.connect(sim_rest)
	v.add_child(sim)
	_menu.visible = false
	add_child(_menu)


func pause_play() -> void:
	if _ended or _busy or paused_menu or (hud != null and hud.is_result_shown()):
		return
	paused_menu = true
	get_tree().paused = true
	_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume_play() -> void:
	if not paused_menu:
		return
	paused_menu = false
	_menu.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Stops the 3D play and finishes the rest of the match with the numeric sim; hands the merged result back.
func sim_rest() -> void:
	if _ended or _busy:
		return
	_busy = true
	_menu_label.text = "SIMULATING..."
	for b in _menu.find_children("*", "Button", true, false):
		(b as Button).disabled = true
	_menu.visible = true
	if is_inside_tree():
		await get_tree().process_frame
	var r: MatchResult = null
	if game != null and game.has_method("sim_rest"):
		r = game.sim_rest()
	if r == null:
		r = result if result != null else _empty_result()
	_finish(r)


func _on_match_finished(r: MatchResult) -> void:
	if _ended or _busy:
		return
	result = r
	if hud != null:
		hud.show_result(r)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if _ended or game == null:
		return
	var showing_card := hud != null and hud.is_result_shown()
	if not paused_menu and not showing_card and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _busy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # a focus change or stray click can release it
	if hud != null:
		hud.set_scoreboard_visible(Input.is_key_pressed(KEY_TAB) and not paused_menu)
	_update_spectator(delta)


func _alive(n: Object) -> bool:
	if not is_instance_valid(n):
		return false
	if n.get("alive") != null:
		return bool(n.get("alive"))
	if n.get("dead") != null:
		return not bool(n.get("dead"))
	return true


func _spectate_targets() -> Array:
	var out: Array = []
	var hp = game.get("human")
	var team := hud.human_team if hud != null else 0
	var bots = game.get("bots")
	if bots is Array and bots.size() > team:
		for b in bots[team]:
			if b != hp and _alive(b):
				out.append(b)
	if out.is_empty() and bots is Array:
		for arr in bots:
			for b in arr:
				if b != hp and _alive(b):
					out.append(b)
	return out


func _update_spectator(delta: float) -> void:
	var hp = game.get("human")
	var want: bool = hp == null or (is_instance_valid(hp) and hp.get("dead") == true)
	if want != spectating:
		spectating = want
		if not spectating and hp != null and hp.get("camera") != null:
			(hp.camera as Camera3D).make_current()
		if spectating and hud != null:
			_spec_idx = 0
	if not spectating:
		if hud != null:
			hud.spectate_text = ""
		return
	var targets := _spectate_targets()
	if targets.is_empty():
		if hud != null:
			hud.spectate_text = ""
		return
	_spec_idx = posmod(_spec_idx, targets.size())
	var t: Node3D = targets[_spec_idx]
	var tpos := t.global_position + Vector3(0, 1.3, 0)
	var back := t.global_transform.basis.z
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	var want_pos := tpos + back * 3.4 + Vector3(0, 1.2, 0)
	if not _spec_cam.current:
		_spec_cam.make_current()
		_spec_cam.global_position = want_pos
	_spec_cam.global_position = _spec_cam.global_position.lerp(want_pos, clampf(delta * 8.0, 0.0, 1.0))
	if _spec_cam.global_position.distance_to(tpos) > 0.1:
		_spec_cam.look_at(tpos)
	if hud != null:
		var nm := ""
		var s = t.get("soldier")
		if s is Soldier:
			nm = (s as Soldier).tag()
		hud.spectate_text = "SPECTATING %s   (click / Q E to switch)" % nm


func _cycle(step: int) -> void:
	if spectating:
		_spec_idx += step


func _unhandled_input(event: InputEvent) -> void:
	if _ended or _busy:
		return
	if hud != null and hud.is_result_shown():
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			get_viewport().set_input_as_handled()
			_finish(result)
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if paused_menu:
			resume_play()
		else:
			pause_play()
		return
	if paused_menu:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_cycle(1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_cycle(1)
		elif event.keycode == KEY_Q:
			_cycle(-1)


func _finish(r: MatchResult) -> void:
	if _ended:
		return
	_ended = true
	if r == null:
		r = _empty_result()
	result = r
	get_tree().paused = false
	paused_menu = false
	for c in _hidden:
		if is_instance_valid(c):
			c.visible = true
	_hidden.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	finished.emit(r)
	if _on_done.is_valid():
		_on_done.call(r)
	queue_free()

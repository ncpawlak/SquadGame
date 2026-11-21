class_name CombineTasks
extends RefCounted
## The combine mini-games (#101) and their scoring rules. `make(spec)` builds the task a Combine.TASKS entry asks for.
## Scoring is in plain static functions so it can be tested without a scene; the inner classes only handle input and
## drawing. Every task ends with a score in 0..1.

const COLORS := {
	"RED": Color("#ef4444"), "BLUE": Color("#38bdf8"), "GREEN": Color("#22c55e"), "YELLOW": Color("#facc15"),
}
const COLOR_NAMES := ["RED", "BLUE", "GREEN", "YELLOW"]
const ARROWS := ["<", "^", ">", "v"]
const ARROW_KEYS := [KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN]

## Hill calls: a situation, three answers and how good each is (1 best). Shuffled each run.
const CALLS := [
	{"t": "Your team holds the point, 2 up. One enemy is flanking left.",
		"o": [["Hold and cover the left", 1.0], ["Rush the flanker", 0.4], ["Leave the point", 0.0]]},
	{"t": "You are alone near the point, 3 enemies approach, a teammate is 10s away.",
		"o": [["Fall back to your teammate", 1.0], ["Hold the point alone", 0.3], ["Charge them", 0.0]]},
	{"t": "Point is contested, you are low on health, your team is winning.",
		"o": [["Take cover and trade", 1.0], ["Push in to finish the point", 0.4], ["Wait out of sight", 0.5]]},
	{"t": "Enemy is on the point. Your squad is stacked and ready.",
		"o": [["Breach together on a count", 1.0], ["Go in one at a time", 0.2], ["Wait for them to leave", 0.4]]},
	{"t": "Hill timer is about to swap. You hold the high ground.",
		"o": [["Rotate early to the next spot", 1.0], ["Stay put until it swaps", 0.5], ["Chase a kill", 0.1]]},
	{"t": "Your teammate calls a smoke push. You see a clear lane.",
		"o": [["Follow the call", 1.0], ["Take the clear lane alone", 0.3], ["Ignore it", 0.0]]},
]


static func make(spec: Dictionary) -> CombineTask:
	var t: CombineTask
	match spec["task"]:
		&"targets": t = Targets.new()
		&"recoil": t = Recoil.new()
		&"timing": t = Timing.new()
		&"track": t = Track.new()
		&"mash": t = Mash.new()
		&"pace": t = Pace.new()
		&"quick": t = Quick.new()
		&"recall": t = Recall.new()
		&"steady": t = Steady.new()
		&"maze": t = Maze.new()
		&"rhythm": t = Rhythm.new()
		&"defense": t = Defense.new()
		&"sequence": t = Sequence.new()
		_: t = Timing.new()
	t.spec = spec
	return t


# --- scoring rules (pure) ---------------------------------------------------------------------

## A target hit: better near the centre and for a quick click.
static func hit_value(dist: float, radius: float, age: float, life: float) -> float:
	if dist > radius:
		return 0.0
	return lerpf(1.0, 0.55, clampf(dist / radius, 0.0, 1.0)) * lerpf(1.0, 0.8, clampf(age / life, 0.0, 1.0))


## One recoil-burst shot: `dist` px from the centre of a target of `radius`.
static func shot_value(dist: float, radius: float) -> float:
	return clampf(1.0 - dist / (radius * 2.5), 0.0, 1.0)


## A timing stop: `offset` is the marker's distance from the zone centre, both as fractions of the bar.
static func timing_value(offset: float, zone: float) -> float:
	var d := absf(offset)
	var half := zone / 2.0
	if d <= half:
		return 1.0 - 0.25 * (d / half)
	return clampf(0.5 - (d - half) / zone, 0.0, 0.5) * 0.9


## Sprint taps count only when the key changes: returns the new tap count.
static func alt_tap(taps: int, last_side: int, side: int) -> int:
	return taps + (1 if side != last_side else 0)


## One step of the sled push bar: it decays, a press adds to it.
static func lift_step(bar: float, dt: float, pressed: bool) -> float:
	var b := bar - 0.35 * dt
	if pressed:
		b += 0.09
	return clampf(b, 0.0, 1.0)


## The sled push threshold the bar must stay above, rising over the run (t in 0..1).
static func lift_threshold(t: float) -> float:
	return lerpf(0.2, 0.7, clampf(t, 0.0, 1.0))


## One step of the ruck march: [speed, stamina, gassed]. Holding sprints and burns stamina; resting recovers it. Running
## dry means a jog until stamina comes back.
static func pace_step(speed: float, stamina: float, gassed: bool, held: bool, dt: float) -> Array:
	var sprint := held and not gassed and stamina > 0.0
	if sprint:
		speed = lerpf(speed, 1.0, clampf(3.0 * dt, 0.0, 1.0))
		stamina -= 0.25 * dt
		if stamina <= 0.0:
			stamina = 0.0
			gassed = true
	else:
		# Running dry is worse than a jog: he stumbles until his wind is back.
		speed = lerpf(speed, 0.15 if gassed else 0.3, clampf(2.0 * dt, 0.0, 1.0))
		stamina = minf(1.0, stamina + 0.14 * dt)
		if gassed and stamina >= 0.4:
			gassed = false
	return [speed, stamina, gassed]


## Score of a ruck march: average speed mapped so a steady jog scores 0 and a well-paced run scores 1.
static func pace_score(distance: float, secs: float) -> float:
	return clampf((distance / secs - 0.3) / (0.75 - 0.3), 0.0, 1.0)


## A quick-choice answer: wrong or late is 0; right is worth `value`, a little less the slower it was.
static func quick_value(value: float, elapsed_s: float, limit: float) -> float:
	if elapsed_s > limit or value <= 0.0:
		return 0.0
	return value * lerpf(1.0, 0.75, clampf(elapsed_s / limit, 0.0, 1.0))


## A recalled map position: full marks on the spot, nothing 120 px away.
static func recall_value(dist: float) -> float:
	return clampf(1.0 - dist / 120.0, 0.0, 1.0)


# --- helpers --------------------------------------------------------------------------------

static func _rand_in(rng: RandomNumberGenerator, size: Vector2, margin: float) -> Vector2:
	return Vector2(rng.randf_range(margin, size.x - margin), rng.randf_range(margin + 30.0, size.y - margin))


# --- tasks ----------------------------------------------------------------------------------

## Shoot popping targets. Smaller and quicker at long range.
class Targets extends CombineTask:
	var _spawned := 0
	var _pos := Vector2.ZERO
	var _born := 0.0
	var _gap := 0.0
	var _up := false
	var _total := 0.0
	var _flash := 0.0

	func instructions() -> String:
		return "Click each target before it vanishes. Closer to the centre and quicker scores more."

	func _run(delta: float) -> void:
		_flash = maxf(0.0, _flash - delta)
		var count: int = spec["count"]
		if _up:
			if elapsed - _born > float(spec["life"]):
				_up = false
				_gap = 0.35
		else:
			_gap -= delta
			if _gap <= 0.0:
				if _spawned >= count:
					finish(_total / float(count))
					return
				_spawned += 1
				_pos = CombineTasks._rand_in(rng, size, float(spec["size"]))
				_born = elapsed
				_up = true

	func _gui_input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0 or not _up:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var r: float = float(spec["size"]) / 2.0
			var v := CombineTasks.hit_value(event.position.distance_to(_pos), r, elapsed - _born, float(spec["life"]))
			if v > 0.0:
				_total += v
				_up = false
				_gap = 0.35
				_flash = 0.15

	func _draw_task() -> void:
		_hud("%s   target %d / %d" % [spec["label"], _spawned, spec["count"]])
		if _up:
			var r: float = float(spec["size"]) / 2.0
			draw_circle(_pos, r, Color("#ef4444"))
			draw_circle(_pos, r * 0.66, Color.WHITE)
			draw_circle(_pos, r * 0.33, Color("#ef4444"))


## Fire a burst while the recoil kicks the shots upward. Aim low to bring them back to the centre.
class Recoil extends CombineTask:
	const RADIUS := 34.0
	var _shots := 0
	var _kick := 0.0
	var _holes: Array[Vector2] = []
	var _total := 0.0

	func instructions() -> String:
		return "Click to fire at the target. Each shot kicks the next one upward, so aim lower as you go."

	func _run(delta: float) -> void:
		_kick = maxf(0.0, _kick - 22.0 * delta)

	func _gui_input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var hit: Vector2 = event.position + Vector2(0, -_kick)
			_holes.append(hit)
			_total += CombineTasks.shot_value(hit.distance_to(size / 2.0), RADIUS)
			_kick += 16.0
			_shots += 1
			if _shots >= int(spec["shots"]):
				finish(_total / float(spec["shots"]))

	func _draw_task() -> void:
		_hud("%s   shot %d / %d" % [spec["label"], _shots, spec["shots"]])
		var c := size / 2.0
		draw_circle(c, RADIUS * 2.5, Color("#1f2937"))
		draw_circle(c, RADIUS * 1.6, Color("#ef4444", 0.7))
		draw_circle(c, RADIUS, Color.WHITE)
		draw_circle(c, RADIUS * 0.4, Color("#ef4444"))
		for h in _holes:
			draw_circle(h, 5.0, Color("#facc15"))
		draw_arc(get_local_mouse_position(), 14.0, 0.0, TAU, 24, Color.WHITE, 2.0)
		draw_rect(Rect2(size.x - 30, size.y - 20 - _kick * 4.0, 14, _kick * 4.0), Color("#f97316"))


## Stop a moving marker inside the zone.
class Timing extends CombineTask:
	var _round := 0
	var _marker := 0.0
	var _dir := 1.0
	var _zone_c := 0.5
	var _total := 0.0
	var _last := -1.0

	func instructions() -> String:
		return "Click (or press Space) to stop the marker inside the green zone."

	func _start() -> void:
		_new_round()

	func _new_round() -> void:
		_zone_c = rng.randf_range(0.2, 0.8)
		_marker = 0.0
		_dir = 1.0

	func _run(delta: float) -> void:
		_marker += _dir * float(spec["speed"]) * delta
		if _marker >= 1.0:
			_marker = 1.0
			_dir = -1.0
		elif _marker <= 0.0:
			_marker = 0.0
			_dir = 1.0

	func _stop() -> void:
		var v := CombineTasks.timing_value(_marker - _zone_c, float(spec["zone"]))
		_total += v
		_last = v
		_round += 1
		if _round >= int(spec["rounds"]):
			finish(_total / float(spec["rounds"]))
		else:
			_new_round()

	func _gui_input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_stop()

	func _input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0 or not is_visible_in_tree():
			return
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
			_stop()
			get_viewport().set_input_as_handled()

	func _draw_task() -> void:
		_hud("%s   round %d / %d" % [spec["label"], mini(_round + 1, int(spec["rounds"])), spec["rounds"]])
		var bar := Rect2(80, size.y / 2.0 - 20, size.x - 160, 40)
		draw_rect(bar, Color("#1f2937"))
		var zw: float = float(spec["zone"]) * bar.size.x
		draw_rect(Rect2(bar.position.x + _zone_c * bar.size.x - zw / 2.0, bar.position.y, zw, bar.size.y), Color("#22c55e", 0.85))
		var mx := bar.position.x + _marker * bar.size.x
		draw_rect(Rect2(mx - 4, bar.position.y - 12, 8, bar.size.y + 24), Color.WHITE)
		if _last >= 0.0:
			_text("last: %d%%" % roundi(_last * 100.0), Vector2(size.x / 2.0, size.y / 2.0 + 90), 22, UiKit.MUTED, true)


## Keep the cursor inside a circle that drifts (and, for the Anchor test, gets knocked around).
class Track extends CombineTask:
	var _pos := Vector2.ZERO
	var _goal := Vector2.ZERO
	var _knock := Vector2.ZERO
	var _next_push := 1.5
	var _inside := 0.0

	func instructions() -> String:
		return "Keep your cursor inside the circle for the whole run. It drifts%s." % (" and gets knocked" if float(spec["push"]) > 0.0 else "")

	func _start() -> void:
		_pos = size / 2.0
		_goal = CombineTasks._rand_in(rng, size, 100.0)
		mouse_default_cursor_shape = Control.CURSOR_CROSS

	func _run(delta: float) -> void:
		var to_goal := _goal - _pos
		if to_goal.length() < 12.0:
			_goal = CombineTasks._rand_in(rng, size, 100.0)
		else:
			_pos += to_goal.normalized() * float(spec["drift"]) * delta
		if float(spec["push"]) > 0.0:
			_next_push -= delta
			if _next_push <= 0.0:
				_next_push = rng.randf_range(1.2, 2.4)
				_knock = Vector2.from_angle(rng.randf() * TAU) * float(spec["push"]) * 2.0
		_pos += _knock * delta
		_knock *= exp(-3.0 * delta)
		_pos = _pos.clamp(Vector2(60, 90), size - Vector2(60, 60))
		if get_local_mouse_position().distance_to(_pos) <= float(spec["radius"]):
			_inside += delta
		if elapsed >= float(spec["secs"]):
			finish(_inside / float(spec["secs"]))

	func _draw_task() -> void:
		_hud("%s   %.0f%% on target" % [spec["label"], 100.0 * _inside / maxf(0.01, elapsed)])
		var on := get_local_mouse_position().distance_to(_pos) <= float(spec["radius"])
		draw_circle(_pos, float(spec["radius"]), Color("#22c55e", 0.35) if on else Color("#ef4444", 0.35))
		draw_arc(_pos, float(spec["radius"]), 0.0, TAU, 40, Color("#22c55e") if on else Color("#ef4444"), 3.0)
		draw_arc(get_local_mouse_position(), 8.0, 0.0, TAU, 16, Color.WHITE, 2.0)
		draw_rect(Rect2(0, size.y - 6, size.x * clampf(elapsed / float(spec["secs"]), 0.0, 1.0), 6), UiKit.ACCENT)


## Sprint (alternate A/D or Left/Right) or sled push (tap Space to hold the bar above the rising line).
class Mash extends CombineTask:
	var _taps := 0
	var _side := 0
	var _bar := 0.4
	var _above := 0.0

	func instructions() -> String:
		if spec["mode"] == &"alt":
			return "Alternate A and D (or Left and Right) as fast as you can."
		return "Tap Space to keep the bar above the rising line."

	func _run(delta: float) -> void:
		if spec["mode"] == &"lift":
			_bar = CombineTasks.lift_step(_bar, delta, false)
			if _bar >= CombineTasks.lift_threshold(elapsed / float(spec["secs"])):
				_above += delta
		if elapsed >= float(spec["secs"]):
			if spec["mode"] == &"alt":
				finish(float(_taps) / float(spec["goal"]))
			else:
				finish(_above / float(spec["secs"]))

	func _input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0 or not is_visible_in_tree():
			return
		if not (event is InputEventKey and event.pressed and not event.echo):
			return
		if spec["mode"] == &"alt":
			var s := 0
			if event.keycode == KEY_A or event.keycode == KEY_LEFT:
				s = 1
			elif event.keycode == KEY_D or event.keycode == KEY_RIGHT:
				s = 2
			if s != 0:
				_taps = CombineTasks.alt_tap(_taps, _side, s)
				_side = s
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			_bar = CombineTasks.lift_step(_bar, 0.0, true)
			get_viewport().set_input_as_handled()

	func _draw_task() -> void:
		var left := maxf(0.0, float(spec["secs"]) - elapsed)
		if spec["mode"] == &"alt":
			_hud("%s   %d steps   %.1fs" % [spec["label"], _taps, left])
			draw_rect(Rect2(80, size.y / 2.0 - 20, size.x - 160, 40), Color("#1f2937"))
			draw_rect(Rect2(80, size.y / 2.0 - 20, (size.x - 160) * clampf(float(_taps) / float(spec["goal"]), 0.0, 1.0), 40), UiKit.ACCENT)
			_text("A / D", Vector2(size.x / 2.0, size.y / 2.0 + 90), 30, Color.WHITE, true)
		else:
			_hud("%s   %.1fs" % [spec["label"], left])
			var bar := Rect2(size.x / 2.0 - 40, 70, 80, size.y - 130)
			draw_rect(bar, Color("#1f2937"))
			var h := bar.size.y * _bar
			draw_rect(Rect2(bar.position.x, bar.end.y - h, bar.size.x, h), UiKit.ACCENT)
			var ty := bar.end.y - bar.size.y * CombineTasks.lift_threshold(elapsed / float(spec["secs"]))
			draw_line(Vector2(bar.position.x - 20, ty), Vector2(bar.end.x + 20, ty), Color("#ef4444"), 4.0)


## Hold Space (or the mouse) to sprint; release to recover. Go dry and you jog until your wind comes back.
class Pace extends CombineTask:
	var _speed := 0.3
	var _stamina := 1.0
	var _gassed := false
	var _dist := 0.0

	func instructions() -> String:
		return "Hold Space (or the mouse button) to sprint and release to recover. Do not run dry."

	func _run(delta: float) -> void:
		var held := Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var st := CombineTasks.pace_step(_speed, _stamina, _gassed, held, delta)
		_speed = st[0]
		_stamina = st[1]
		_gassed = st[2]
		_dist += _speed * delta
		if elapsed >= float(spec["secs"]):
			finish(CombineTasks.pace_score(_dist, float(spec["secs"])))

	func _draw_task() -> void:
		_hud("%s   %.1fs" % [spec["label"], maxf(0.0, float(spec["secs"]) - elapsed)])
		draw_rect(Rect2(80, 120, size.x - 160, 30), Color("#1f2937"))
		draw_rect(Rect2(80, 120, (size.x - 160) * _stamina, 30), Color("#ef4444") if _gassed else Color("#22c55e"))
		_text("stamina" + ("  - GASSED" if _gassed else ""), Vector2(80, 112), 16, UiKit.MUTED)
		draw_rect(Rect2(80, 240, size.x - 160, 30), Color("#1f2937"))
		draw_rect(Rect2(80, 240, (size.x - 160) * _speed, 30), UiKit.ACCENT)
		_text("speed", Vector2(80, 232), 16, UiKit.MUTED)
		_text("distance %.1f" % _dist, Vector2(size.x / 2.0, 340), 26, Color.WHITE, true)


## Pick the right answer fast: arrows (cone course), colours (name vs ink) or hill calls (situations).
class Quick extends CombineTask:
	var _items: Array = []
	var _i := 0
	var _shown_at := 0.0
	var _total := 0.0
	var _buttons := HBoxContainer.new()
	var _value_for: Array = []

	func instructions() -> String:
		match spec["kind"]:
			&"arrows": return "Press the arrow key that matches each prompt, as fast as you can."
			&"colors": return "Pick the COLOUR of the word, not what it says. Click or press 1-4."
			_: return "Pick the best call for each situation. Click or press 1-3."

	func _start() -> void:
		var n: int = spec["count"]
		for k in n:
			_items.append(_make_item(k))
		_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		_buttons.add_theme_constant_override("separation", 12)
		# Buttons are added after this is placed, so the row must grow upward from the bottom edge (it used to grow down and
		# sit half off screen).
		_buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 24)
		_buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN
		add_child(_buttons)
		_show_item()

	func _make_item(k: int) -> Dictionary:
		match spec["kind"]:
			&"arrows":
				return {"correct": rng.randi_range(0, 3)}
			&"colors":
				var word := rng.randi_range(0, 3)
				var ink := (word + rng.randi_range(1, 3)) % 4
				return {"word": word, "ink": ink}
			_:
				var pool := CombineTasks.CALLS.duplicate()
				var base = pool[k % pool.size()]
				var opts: Array = base["o"].duplicate()
				opts.shuffle()
				return {"t": base["t"], "o": opts}

	func _limit() -> float:
		var lim := float(spec["limit"])
		if spec["kind"] == &"colors":
			lim *= 1.0 - 0.35 * float(_i) / float(maxi(1, _items.size() - 1))
		return lim

	func _show_item() -> void:
		for c in _buttons.get_children():
			c.queue_free()
		_shown_at = elapsed
		_value_for = []
		var it: Dictionary = _items[_i]
		match spec["kind"]:
			&"arrows":
				for a in 4:
					_add_button(CombineTasks.ARROWS[a], a, 1.0 if a == it["correct"] else 0.0)
			&"colors":
				for c in 4:
					_add_button(CombineTasks.COLOR_NAMES[c], c, 1.0 if c == it["ink"] else 0.0)
			_:
				for o in 3:
					_add_button(String(it["o"][o][0]), o, float(it["o"][o][1]))

	func _add_button(text: String, idx: int, value: float) -> void:
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(120 if spec["kind"] != &"calls" else 250, 54)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func(): _answer(value))
		_buttons.add_child(b)
		_value_for.append(value)

	func _answer(value: float) -> void:
		if _done:
			return
		_total += CombineTasks.quick_value(value, elapsed - _shown_at, _limit())
		_next()

	func _next() -> void:
		_i += 1
		if _i >= _items.size():
			finish(_total / float(_items.size()))
		else:
			_show_item()

	func _run(_delta: float) -> void:
		if elapsed - _shown_at > _limit():
			_next()

	func _input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0 or _i >= _items.size() or not is_visible_in_tree():
			return
		if not (event is InputEventKey and event.pressed and not event.echo):
			return
		var idx := -1
		if spec["kind"] == &"arrows":
			idx = CombineTasks.ARROW_KEYS.find(event.keycode)
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			idx = event.keycode - KEY_1
		if idx >= 0 and idx < _value_for.size():
			get_viewport().set_input_as_handled()
			_answer(_value_for[idx])

	func _draw_task() -> void:
		if _i >= _items.size():
			return
		_hud("%s   %d / %d" % [spec["label"], _i + 1, _items.size()])
		var it: Dictionary = _items[_i]
		var c := Vector2(size.x / 2.0, size.y / 2.0 - 30)
		match spec["kind"]:
			&"arrows":
				_text(CombineTasks.ARROWS[it["correct"]], c + Vector2(0, 40), 110, Color.WHITE, true)
			&"colors":
				_text(CombineTasks.COLOR_NAMES[it["word"]], c + Vector2(0, 30), 90, CombineTasks.COLORS[CombineTasks.COLOR_NAMES[it["ink"]]], true)
			_:
				_text(String(it["t"]), Vector2(size.x / 2.0, c.y), 24, Color.WHITE, true)
		var frac := clampf((elapsed - _shown_at) / _limit(), 0.0, 1.0)
		draw_rect(Rect2(0, size.y - 6, size.x * (1.0 - frac), 6), UiKit.ACCENT)


## Memorise numbered dots on a map, then click where each one was, in order.
class Recall extends CombineTask:
	var _round := 0
	var _dots: Array[Vector2] = []
	var _phase := 0 # 0 show, 1 answer
	var _t := 0.0
	var _picks: Array[Vector2] = []
	var _total := 0.0
	var _count := 0

	func instructions() -> String:
		return "Memorise where the numbered dots are. They disappear. Then click where each one was, in order."

	func _start() -> void:
		_new_round()

	func _new_round() -> void:
		_dots.clear()
		_picks.clear()
		var n: int = int(spec["n"]) + _round
		for i in n:
			_dots.append(CombineTasks._rand_in(rng, size, 50.0))
		_phase = 0
		_t = 0.0

	func _run(delta: float) -> void:
		if _phase == 0:
			_t += delta
			if _t >= float(spec["show"]):
				_phase = 1

	func _gui_input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0 or _phase != 1:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var i := _picks.size()
			_picks.append(event.position)
			_total += CombineTasks.recall_value(event.position.distance_to(_dots[i]))
			_count += 1
			if _picks.size() >= _dots.size():
				_round += 1
				if _round >= int(spec["rounds"]):
					finish(_total / float(_count))
				else:
					_new_round()

	func _draw_task() -> void:
		_hud("%s   round %d / %d" % [spec["label"], mini(_round + 1, int(spec["rounds"])), spec["rounds"]])
		if _phase == 0:
			for i in _dots.size():
				draw_circle(_dots[i], 18.0, UiKit.ACCENT)
				_text(str(i + 1), _dots[i] + Vector2(0, 7), 20, Color.BLACK, true)
			draw_rect(Rect2(0, size.y - 6, size.x * (1.0 - _t / float(spec["show"])), 6), UiKit.ACCENT)
		else:
			_text("Click dot %d" % (_picks.size() + 1), Vector2(size.x / 2.0, 70), 24, Color.WHITE, true)
			for i in _picks.size():
				draw_circle(_picks[i], 10.0, Color("#38bdf8"))
				_text(str(i + 1), _picks[i] + Vector2(0, -14), 16, Color.WHITE, true)


## Callouts: watch a sequence of pads light up, then repeat it. Each round is one pad longer.
class Sequence extends CombineTask:
	const PAD := Vector2(150, 150)
	var _round := 0
	var _seq: Array[int] = []
	var _show_i := 0
	var _show_t := 0.0
	var _phase := 0 # 0 playing, 1 answering
	var _got := 0
	var _total := 0.0
	var _lit := -1
	var _lit_for := 0.0

	func instructions() -> String:
		return "Watch the pads light up, then repeat the order by clicking or pressing 1-4."

	func _start() -> void:
		_new_round()

	func _new_round() -> void:
		_seq.clear()
		for i in int(spec["start"]) + _round:
			_seq.append(rng.randi_range(0, 3))
		_phase = 0
		_show_i = 0
		_show_t = -0.5
		_got = 0

	func _run(delta: float) -> void:
		_lit_for = maxf(0.0, _lit_for - delta)
		if _lit_for <= 0.0:
			_lit = -1
		if _phase != 0:
			return
		_show_t += delta
		if _show_t >= 0.7:
			_show_t = 0.0
			if _show_i >= _seq.size():
				_phase = 1
				return
			_lit = _seq[_show_i]
			_lit_for = 0.45
			_show_i += 1

	func _pad_rect(i: int) -> Rect2:
		var origin := Vector2(size.x / 2.0 - PAD.x - 10, size.y / 2.0 - PAD.y - 10)
		return Rect2(origin + Vector2((i % 2) * (PAD.x + 20), (i / 2) * (PAD.y + 20)), PAD)

	func _press(i: int) -> void:
		if _done or _phase != 1:
			return
		_lit = i
		_lit_for = 0.2
		if i == _seq[_got]:
			_got += 1
			if _got >= _seq.size():
				_end_round(1.0)
		else:
			_end_round(float(_got) / float(_seq.size()))

	func _end_round(v: float) -> void:
		_total += v
		_round += 1
		if _round >= int(spec["rounds"]):
			finish(_total / float(spec["rounds"]))
		else:
			_new_round()

	func _gui_input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in 4:
				if _pad_rect(i).has_point(event.position):
					_press(i)

	func _input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0 or not is_visible_in_tree():
			return
		if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_4:
			_press(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()

	func _draw_task() -> void:
		_hud("%s   round %d / %d   length %d" % [spec["label"], mini(_round + 1, int(spec["rounds"])), spec["rounds"], _seq.size()])
		var cols := [Color("#ef4444"), Color("#38bdf8"), Color("#22c55e"), Color("#facc15")]
		for i in 4:
			var c: Color = cols[i]
			draw_rect(_pad_rect(i), c if i == _lit else c.darkened(0.65))
			_text(str(i + 1), _pad_rect(i).get_center() + Vector2(0, 10), 32, Color.WHITE, true)
		_text("Watch..." if _phase == 0 else "Your turn", Vector2(size.x / 2.0, size.y - 24), 22, UiKit.MUTED, true)


## Steady aim: a scope that sways. Hold Space (or the right mouse button) to hold your breath and steady it, but the breath
## runs out. Click to shoot each target that appears.
class Steady extends CombineTask:
	var _target := Vector2.ZERO
	var _shots := 0
	var _total := 0.0
	var _breath := 1.0
	var _winded := false
	var _t := 0.0
	var _calm := 1.0  # 1 = full sway, small = steadied
	var _target_age := 0.0
	var _marks: Array = []

	func instructions() -> String:
		return "Your scope sways. Hold Space (or the right mouse button) to steady it, but your breath runs out. Click to shoot each target."

	func _start() -> void:
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		_next_target()

	func _next_target() -> void:
		_target = CombineTasks._rand_in(rng, size, 90.0)
		_target_age = 0.0

	func _holding() -> bool:
		return not _winded and _breath > 0.0 and (Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))

	func _sway() -> Vector2:
		var a := float(spec["sway"]) * _calm * (1.6 if _winded else 1.0)
		return Vector2(sin(_t * 1.7) + 0.5 * sin(_t * 3.1 + 1.0), cos(_t * 1.3) + 0.5 * cos(_t * 2.7)) * a

	func _reticle() -> Vector2:
		return get_local_mouse_position() + _sway()

	func _run(delta: float) -> void:
		_t += delta
		_target_age += delta
		var holding := _holding()
		if holding:
			_breath = maxf(0.0, _breath - 0.3 * delta)
			if _breath <= 0.0:
				_winded = true
		else:
			_breath = minf(1.0, _breath + 0.22 * delta)
			if _winded and _breath >= 0.4:
				_winded = false
		_calm = lerpf(_calm, 0.15 if holding else 1.0, clampf(8.0 * delta, 0.0, 1.0))
		if _target_age > 4.0:
			_shoot_at(Vector2(-9999, -9999))

	func _gui_input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_shoot_at(_reticle())

	func _shoot_at(p: Vector2) -> void:
		var r := float(spec["radius"])
		_total += CombineTasks.shot_value(p.distance_to(_target), r)
		_marks.append(p)
		_shots += 1
		if _shots >= int(spec["shots"]):
			finish(_total / float(_shots))
		else:
			_next_target()

	func _draw_task() -> void:
		_hud("%s   shot %d / %d" % [spec["label"], mini(_shots + 1, int(spec["shots"])), spec["shots"]])
		var r := float(spec["radius"])
		for k in 3:
			draw_arc(_target, r * (1.0 - 0.33 * k), 0.0, TAU, 32, Color("#ef4444").lerp(Color.WHITE, 0.33 * k), 3.0)
		draw_circle(_target, 4.0, Color("#ef4444"))
		var rt := _reticle()
		var c := Color("#22c55e") if _holding() else (Color("#ef4444") if _winded else Color.WHITE)
		draw_arc(rt, 22.0, 0.0, TAU, 28, c, 2.0)
		draw_line(rt + Vector2(-34, 0), rt + Vector2(34, 0), c, 1.5)
		draw_line(rt + Vector2(0, -34), rt + Vector2(0, 34), c, 1.5)
		var bar := Rect2(size.x - 170, 14, 150, 14)
		draw_rect(bar, Color("#1f2937"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _breath, bar.size.y)), Color("#ef4444") if _winded else Color("#38bdf8"))
		_text("BREATH" + ("  WINDED" if _winded else ""), Vector2(bar.position.x, bar.position.y + 32), 14, UiKit.MUTED)


## Map run: a small maze. Get from the edge to the marked centre as fast as you can (arrow keys or WASD).
class Maze extends CombineTask:
	const N := 1
	const E := 2
	const S := 4
	const W := 8
	var _cols := 15
	var _rows := 9
	var _cells: Array = []  # open-passage bitmask per cell
	var _pos := Vector2i.ZERO
	var _goal := Vector2i.ZERO
	var _round := 0
	var _round_t := 0.0
	var _par := 8.0
	var _cool := 0.0
	var _total := 0.0
	var _cs := 40.0
	var _origin := Vector2.ZERO

	func instructions() -> String:
		return "Run the maze to the centre as fast as you can. Arrow keys or WASD. Three mazes."

	func _start() -> void:
		_cols = int(spec["cols"])
		_rows = int(spec["rows"])
		_new_maze()

	func _idx(c: Vector2i) -> int:
		return c.y * _cols + c.x

	func _new_maze() -> void:
		_cells = []
		_cells.resize(_cols * _rows)
		_cells.fill(0)
		var seen := {}
		var stack: Array[Vector2i] = [Vector2i(rng.randi_range(0, _cols - 1), rng.randi_range(0, _rows - 1))]
		seen[stack[0]] = true
		var dirs := [[N, Vector2i(0, -1), S], [E, Vector2i(1, 0), W], [S, Vector2i(0, 1), N], [W, Vector2i(-1, 0), E]]
		while not stack.is_empty():
			var cur: Vector2i = stack[-1]
			var opts: Array = []
			for d in dirs:
				var nx: Vector2i = cur + d[1]
				if nx.x >= 0 and nx.y >= 0 and nx.x < _cols and nx.y < _rows and not seen.has(nx):
					opts.append([d, nx])
			if opts.is_empty():
				stack.pop_back()
				continue
			var pick: Array = opts[rng.randi_range(0, opts.size() - 1)]
			_cells[_idx(cur)] |= int(pick[0][0])
			_cells[_idx(pick[1])] |= int(pick[0][2])
			seen[pick[1]] = true
			stack.append(pick[1])
		_goal = Vector2i(_cols / 2, _rows / 2)
		var corners := [Vector2i(0, 0), Vector2i(_cols - 1, 0), Vector2i(0, _rows - 1), Vector2i(_cols - 1, _rows - 1)]
		_pos = corners[rng.randi_range(0, 3)]
		_par = float(_shortest(_pos, _goal)) * 0.11 + 2.0
		_round_t = 0.0
		_cs = minf((size.x - 60.0) / _cols, (size.y - 90.0) / _rows)
		_origin = Vector2((size.x - _cs * _cols) / 2.0, (size.y - _cs * _rows) / 2.0 + 18.0)

	func _shortest(a: Vector2i, b: Vector2i) -> int:
		var dist := {a: 0}
		var q: Array[Vector2i] = [a]
		var dirs := [[N, Vector2i(0, -1)], [E, Vector2i(1, 0)], [S, Vector2i(0, 1)], [W, Vector2i(-1, 0)]]
		while not q.is_empty():
			var cur: Vector2i = q.pop_front()
			if cur == b:
				return int(dist[cur])
			for d in dirs:
				if int(_cells[_idx(cur)]) & int(d[0]) != 0:
					var nx: Vector2i = cur + d[1]
					if not dist.has(nx):
						dist[nx] = int(dist[cur]) + 1
						q.append(nx)
		return 30

	func _run(delta: float) -> void:
		_round_t += delta
		_cool -= delta
		if _round_t > _par * 3.5:
			_end_round(0.0)
			return
		if _cool > 0.0:
			return
		var d := Vector2i.ZERO
		var bit := 0
		if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
			d = Vector2i(0, -1)
			bit = N
		elif Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
			d = Vector2i(0, 1)
			bit = S
		elif Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
			d = Vector2i(-1, 0)
			bit = W
		elif Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
			d = Vector2i(1, 0)
			bit = E
		if bit != 0 and int(_cells[_idx(_pos)]) & bit != 0:
			_pos += d
			_cool = 0.085
			if _pos == _goal:
				_end_round(clampf(1.0 - (_round_t - _par) / (_par * 2.5), 0.0, 1.0))

	func _end_round(v: float) -> void:
		_total += v
		_round += 1
		if _round >= int(spec["rounds"]):
			finish(_total / float(spec["rounds"]))
		else:
			_new_maze()

	func _draw_task() -> void:
		_hud("%s   maze %d / %d   %.1fs" % [spec["label"], mini(_round + 1, int(spec["rounds"])), spec["rounds"], _round_t])
		var wall := Color("#94a3b8")
		for y in _rows:
			for x in _cols:
				var o := _origin + Vector2(x, y) * _cs
				var m := int(_cells[y * _cols + x])
				if m & N == 0:
					draw_line(o, o + Vector2(_cs, 0), wall, 2.0)
				if m & W == 0:
					draw_line(o, o + Vector2(0, _cs), wall, 2.0)
				if y == _rows - 1:
					draw_line(o + Vector2(0, _cs), o + Vector2(_cs, _cs), wall, 2.0)
				if x == _cols - 1:
					draw_line(o + Vector2(_cs, 0), o + Vector2(_cs, _cs), wall, 2.0)
		var g := _origin + (Vector2(_goal) + Vector2(0.5, 0.5)) * _cs
		draw_circle(g, _cs * 0.38, Color("#22c55e", 0.35))
		draw_arc(g, _cs * 0.38, 0.0, TAU, 24, Color("#22c55e"), 3.0)
		var p := _origin + (Vector2(_pos) + Vector2(0.5, 0.5)) * _cs
		draw_circle(p, _cs * 0.28, UiKit.ACCENT)
		var frac := clampf(_round_t / (_par * 3.5), 0.0, 1.0)
		draw_rect(Rect2(0, size.y - 6, size.x * (1.0 - frac), 6), UiKit.ACCENT if frac < 0.7 else Color("#ef4444"))


## Under pressure: notes fall down four lanes and you hit the matching arrow as each reaches the line. It speeds up.
class Rhythm extends CombineTask:
	const LANE_W := 120.0
	const WINDOW := 0.2
	var _notes: Array = []  # {lane, hit, travel, value, done}
	var _scored := 0.0
	var _combo := 0
	var _best_combo := 0
	var _flash := ""
	var _flash_t := 0.0
	var _lit := [0.0, 0.0, 0.0, 0.0]

	func instructions() -> String:
		return "Notes fall down four lanes. Hit the matching arrow key (or A W D S) as each one reaches the line. It gets faster and faster."

	func _start() -> void:
		var n := int(spec["count"])
		var t := 1.6
		for k in n:
			var f := float(k) / float(maxi(1, n - 1))
			t += lerpf(0.85, 0.3, f)
			_notes.append({"lane": rng.randi_range(0, 3), "hit": t, "travel": lerpf(1.7, 0.7, f), "value": 0.0, "done": false})

	func _hit_y() -> float:
		return size.y - 74.0

	func _lane_x(l: int) -> float:
		return size.x / 2.0 + (float(l) - 1.5) * LANE_W

	static func lane_value(offset: float) -> float:
		var d := absf(offset)
		if d <= 0.06:
			return 1.0
		if d <= 0.11:
			return 0.75
		if d <= 0.16:
			return 0.5
		return 0.25 if d <= 0.2 else 0.0

	func _press(lane: int) -> void:
		_lit[lane] = 0.15
		var best := -1
		var best_off := 9.0
		for i in _notes.size():
			var nt: Dictionary = _notes[i]
			if nt["done"] or int(nt["lane"]) != lane:
				continue
			var off := elapsed - float(nt["hit"])
			if absf(off) <= WINDOW and absf(off) < absf(best_off):
				best = i
				best_off = off
		if best < 0:
			_combo = 0
			return
		var v := lane_value(best_off)
		_notes[best]["done"] = true
		_notes[best]["value"] = v
		_scored += v
		_combo += 1
		_best_combo = maxi(_best_combo, _combo)
		_flash = "PERFECT" if v >= 1.0 else ("GOOD" if v >= 0.75 else "OK")
		_flash_t = 0.4

	func _run(delta: float) -> void:
		_flash_t = maxf(0.0, _flash_t - delta)
		for l in 4:
			_lit[l] = maxf(0.0, float(_lit[l]) - delta)
		var open := 0
		for nt in _notes:
			if nt["done"]:
				continue
			if elapsed > float(nt["hit"]) + WINDOW:
				nt["done"] = true
				_combo = 0
				_flash = "MISS"
				_flash_t = 0.4
			else:
				open += 1
		if open == 0:
			finish(_scored / float(_notes.size()))

	func _input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0 or not is_visible_in_tree():
			return
		if not (event is InputEventKey and event.pressed and not event.echo):
			return
		var lane := CombineTasks.ARROW_KEYS.find(event.keycode)
		if lane < 0:
			lane = [KEY_A, KEY_W, KEY_D, KEY_S].find(event.keycode)
		if lane >= 0:
			get_viewport().set_input_as_handled()
			_press(lane)

	func _arrow(c: Vector2, lane: int, r: float, col: Color, filled: bool) -> void:
		var dir := [Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)][lane] as Vector2
		var side := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([c + dir * r, c - dir * r * 0.7 + side * r * 0.9, c - dir * r * 0.7 - side * r * 0.9])
		if filled:
			draw_colored_polygon(pts, col)
		else:
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), col, 3.0)

	func _draw_task() -> void:
		var cols := [Color("#ef4444"), Color("#38bdf8"), Color("#22c55e"), Color("#facc15")]
		var done := 0
		for nt in _notes:
			if nt["done"]:
				done += 1
		_hud("%s   combo %d   %d / %d" % [spec["label"], _combo, done, _notes.size()])
		for l in 4:
			var x := _lane_x(l)
			draw_rect(Rect2(x - LANE_W / 2.0 + 4, 0, LANE_W - 8, size.y), Color(1, 1, 1, 0.04))
			var lit := float(_lit[l]) > 0.0
			_arrow(Vector2(x, _hit_y()), l, 30.0, cols[l], lit)
		draw_line(Vector2(_lane_x(0) - LANE_W / 2.0, _hit_y() + 40), Vector2(_lane_x(3) + LANE_W / 2.0, _hit_y() + 40), Color(1, 1, 1, 0.2), 2.0)
		for nt in _notes:
			if nt["done"]:
				continue
			var u := 1.0 - (float(nt["hit"]) - elapsed) / float(nt["travel"])
			if u < 0.0:
				continue
			var y := _hit_y() * u
			_arrow(Vector2(_lane_x(int(nt["lane"])), y), int(nt["lane"]), 28.0, cols[int(nt["lane"])], true)
		if _flash_t > 0.0:
			_text(_flash, Vector2(size.x / 2.0, 90.0), 36, Color.WHITE if _flash != "MISS" else Color("#ef4444"), true)


## Hill defense: a small tower defense. Click a pad to build a turret, click a turret to upgrade it. Stop the enemies
## reaching the hill. Kills earn coins.
class Defense extends CombineTask:
	const PATH := [Vector2(0.0, 0.28), Vector2(0.36, 0.28), Vector2(0.36, 0.74), Vector2(0.7, 0.74), Vector2(0.7, 0.36), Vector2(0.9, 0.36)]
	const PADS := [Vector2(0.18, 0.5), Vector2(0.2, 0.08), Vector2(0.5, 0.5), Vector2(0.52, 0.93), Vector2(0.58, 0.55), Vector2(0.84, 0.6), Vector2(0.8, 0.14), Vector2(0.54, 0.15)]
	const RANGE := 125.0
	var _enemies: Array = []
	var _spawn: Array = []  # {t, hp, speed}
	var _towers := {}  # pad index -> {lvl, cd}
	var _coins := 0
	var _hp := 0
	var _kills := 0
	var _total_enemies := 0
	var _len := 1.0
	var _beams: Array = []

	func instructions() -> String:
		return "Stop the enemies reaching the hill. Click a pad to build a turret (%d coins), click a turret to upgrade it (%d). Kills earn coins." % [int(spec["cost"]), int(spec["upgrade"])]

	func _pt(i: int) -> Vector2:
		return (PATH[i] as Vector2) * size

	func _start() -> void:
		_coins = int(spec["coins"])
		_hp = int(spec["hp"])
		_len = 0.0
		for i in PATH.size() - 1:
			_len += _pt(i).distance_to(_pt(i + 1))
		var t := 1.5
		for w in int(spec["waves"]):
			for k in int(spec["per_wave"]):
				_spawn.append({"t": t, "hp": 2 + w * 2, "speed": 70.0 + 18.0 * w})
				t += 0.95 - 0.07 * w
			t += 3.0
		_total_enemies = _spawn.size()

	func _at(d: float) -> Vector2:
		var left := d
		for i in PATH.size() - 1:
			var seg := _pt(i).distance_to(_pt(i + 1))
			if left <= seg:
				return _pt(i).lerp(_pt(i + 1), left / seg)
			left -= seg
		return _pt(PATH.size() - 1)

	func _run(delta: float) -> void:
		while not _spawn.is_empty() and float(_spawn[0]["t"]) <= elapsed:
			var s: Dictionary = _spawn.pop_front()
			_enemies.append({"d": 0.0, "hp": int(s["hp"]), "max": int(s["hp"]), "speed": float(s["speed"])})
		for e in _enemies:
			e["d"] = float(e["d"]) + float(e["speed"]) * delta
		for e in _enemies.duplicate():
			if float(e["d"]) >= _len:
				_enemies.erase(e)
				_hp -= 1
		_beams = _beams.filter(func(b): return float(b[2]) > 0.0)
		for b in _beams:
			b[2] = float(b[2]) - delta
		for pad in _towers:
			var tw: Dictionary = _towers[pad]
			tw["cd"] = float(tw["cd"]) - delta
			if float(tw["cd"]) > 0.0:
				continue
			var from := (PADS[pad] as Vector2) * size
			var target: Dictionary = {}
			for e in _enemies:
				if _at(float(e["d"])).distance_to(from) <= RANGE * (1.0 + 0.2 * float(int(tw["lvl"]) - 1)):
					if target.is_empty() or float(e["d"]) > float(target["d"]):
						target = e
			if not target.is_empty():
				target["hp"] = int(target["hp"]) - int(tw["lvl"])
				tw["cd"] = 0.55
				_beams.append([from, _at(float(target["d"])), 0.08])
				if int(target["hp"]) <= 0:
					_enemies.erase(target)
					_kills += 1
					_coins += int(spec["bounty"])
		if _hp <= 0 or (_spawn.is_empty() and _enemies.is_empty()):
			var frac := float(_kills) / float(_total_enemies)
			finish(0.7 * frac + 0.3 * clampf(float(_hp) / float(spec["hp"]), 0.0, 1.0) if _hp > 0 else 0.6 * frac)

	func _gui_input(event: InputEvent) -> void:
		if _done or _ready_left > 0.0:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in PADS.size():
				if event.position.distance_to((PADS[i] as Vector2) * size) <= 26.0:
					if _towers.has(i):
						var tw: Dictionary = _towers[i]
						if int(tw["lvl"]) < 3 and _coins >= int(spec["upgrade"]):
							_coins -= int(spec["upgrade"])
							tw["lvl"] = int(tw["lvl"]) + 1
					elif _coins >= int(spec["cost"]):
						_coins -= int(spec["cost"])
						_towers[i] = {"lvl": 1, "cd": 0.0}
					return

	func _draw_task() -> void:
		_hud("%s   coins %d   hill %d   kills %d / %d" % [spec["label"], _coins, maxi(0, _hp), _kills, _total_enemies])
		for i in PATH.size() - 1:
			draw_line(_pt(i), _pt(i + 1), Color("#334155"), 30.0)
		for i in PATH.size() - 1:
			draw_line(_pt(i), _pt(i + 1), Color("#1e293b"), 22.0)
		var hill := _pt(PATH.size() - 1)
		draw_circle(hill, 26.0, Color("#22c55e", 0.35))
		draw_arc(hill, 26.0, 0.0, TAU, 24, Color("#22c55e"), 3.0)
		_text("HILL", hill + Vector2(0, -34), 14, Color("#22c55e"), true)
		for i in PADS.size():
			var c := (PADS[i] as Vector2) * size
			if _towers.has(i):
				var lvl := int(_towers[i]["lvl"])
				draw_arc(c, RANGE * (1.0 + 0.2 * float(lvl - 1)), 0.0, TAU, 40, Color(1, 1, 1, 0.07), 1.0)
				draw_rect(Rect2(c - Vector2(16, 16), Vector2(32, 32)), UiKit.ACCENT)
				_text(str(lvl), c + Vector2(0, 7), 20, Color.BLACK, true)
			else:
				draw_arc(c, 24.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5 if _coins >= int(spec["cost"]) else 0.2), 2.0)
				_text("+", c + Vector2(0, 8), 24, Color(1, 1, 1, 0.5), true)
		for b in _beams:
			draw_line(b[0], b[1], Color("#facc15"), 3.0)
		for e in _enemies:
			var p := _at(float(e["d"]))
			draw_circle(p, 11.0, Color("#ef4444"))
			draw_rect(Rect2(p + Vector2(-12, -20), Vector2(24.0 * float(e["hp"]) / float(e["max"]), 4)), Color("#22c55e"))

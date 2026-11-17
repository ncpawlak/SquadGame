class_name Fx
extends RefCounted
## Shared motion for the franchise menus: floating "+N" text, value tweens, flashes, stamps and
## wobbles. Everything honours the "Reduce animations" setting (helpers that would animate just
## apply their end state) and any tween registered as skippable snaps to its end on a click or key.
##
## Audio is not wired yet: moments call Fx.cue(&"name") and a future sound system sets cue_handler.

const CFG_PATH := "user://settings.cfg"

static var _loaded := false
static var _reduced := false
static var _skippable: Array[Tween] = []
## Set by a future audio system: func(cue: StringName). Cues used so far: xp_tick, level_up,
## rating_up, signed, award, pick, count_tick.
static var cue_handler := Callable()


# --- setting ----------------------------------------------------------------------

static func is_reduced() -> bool:
	if not _loaded:
		_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(CFG_PATH) == OK:
			_reduced = bool(cfg.get_value("interface", "reduce_animations", false))
	return _reduced


static func set_reduced(on: bool) -> void:
	_loaded = true
	_reduced = on
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("interface", "reduce_animations", on)
	cfg.save(CFG_PATH)


## A duration, or 0 when animations are reduced.
static func dur(d: float) -> float:
	return 0.0 if is_reduced() else d


static func cue(name: StringName) -> void:
	if cue_handler.is_valid():
		cue_handler.call(name)


# --- tweens -----------------------------------------------------------------------

## A tween on `node`. `skippable` tweens finish instantly when skip_all() runs (results screens).
static func tween(node: Node, skippable := false) -> Tween:
	var tw := node.create_tween()
	if skippable:
		_skippable = _skippable.filter(func(t: Tween): return t != null and t.is_valid())
		_skippable.append(tw)
	return tw


## Jump every skippable tween to its end state. Called from the app on a click or key press.
static func skip_all() -> void:
	if _skippable.is_empty():
		return
	var list := _skippable
	_skippable = []
	for tw in list:
		if tw != null and tw.is_valid() and tw.is_running():
			tw.custom_step(1000.0)


## True while a skippable tween is still running.
static func busy() -> bool:
	for tw in _skippable:
		if tw != null and tw.is_valid() and tw.is_running():
			return true
	return false


## Run cb once `c` is in the tree and has had two layout passes (sizes and positions are real).
static func after_layout(c: Control, cb: Callable) -> void:
	if not c.is_inside_tree():
		await c.tree_entered
	await c.get_tree().process_frame
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	await c.get_tree().process_frame
	if is_instance_valid(c) and c.is_inside_tree():
		cb.call()


# --- remembered values -------------------------------------------------------------

static var _memo := {}


## Store `value` under `key` and return what was there before (null the first time).
static func memo(key: String, value: Variant) -> Variant:
	var old: Variant = _memo.get(key, null)
	_memo[key] = value
	return old


## A number that animates when it differs from the last time it was shown: counts from the old value,
## flashes and floats the change ("+3" / "-3"). `polarity` colours the change: 1 = up is good, -1 = down
## is good, 0 = neutral. `intro` counts up from 0 the first time it is shown.
static func count_memo(l: Label, key: String, to: int, fmt := "%d", intro := false, polarity := 0) -> void:
	var old: Variant = memo(key, to)
	var from := to
	if old == null:
		if intro:
			from = 0
	else:
		from = int(old)
	count_between(l, from, to, fmt, 0.6, 0.1)
	if from == to or old == null or is_reduced():
		return
	var up := to > from
	var color := UiKit.TEXT
	if polarity != 0:
		color = UiKit.GOOD if up == (polarity > 0) else UiKit.BAD
	rise_text(l, "%+d" % (to - from), color, 18, Vector2(6, -6), 0.15, 26.0, true)
	flash(l, 0.6, 0.7, 0.1)


# --- effects ----------------------------------------------------------------------

## A "+N" that floats up from `at` (offset from its top-left) and fades out. Drawn above the
## page and ignored by layout, so it can sit next to any control.
static func rise_text(at: Control, text: String, color: Color, font_size := 20, offset := Vector2.ZERO, delay := 0.0, rise := 30.0, at_right := false) -> void:
	if is_reduced():
		return
	after_layout(at, func():
		var l := UiKit.display(text, font_size, color)
		l.top_level = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.z_index = 50
		l.modulate.a = 0.0
		at.add_child(l)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 5)
		l.global_position = at.global_position + offset + (Vector2(at.size.x, 0) if at_right else Vector2.ZERO)
		var tw := l.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(l, "modulate:a", 1.0, 0.12)
		tw.parallel().tween_property(l, "global_position:y", l.global_position.y - rise, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.12 + 0.55)
		tw.tween_callback(l.queue_free))


## Count a label from `from` to `to` (fmt has one %d). Final text is set first so layout is stable.
static func count_between(l: Label, from: int, to: int, fmt := "%d", dur_s := 0.5, delay := 0.0) -> void:
	l.text = fmt % to
	if is_reduced() or from == to:
		return
	l.text = fmt % from
	UiKit._when_ready(l, func():
		if not is_instance_valid(l):
			return
		var tw := tween(l, true)
		tw.tween_interval(delay)
		tw.tween_method(func(x: float): l.text = fmt % roundi(x), float(from), float(to), dur_s).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): l.text = fmt % to))


## Count a two-number label (a score) from 0-0 to a-b. fmt holds two %d.
static func count_pair(l: Label, a: int, b: int, fmt := "%d  -  %d", dur_s := 0.7, delay := 0.0) -> void:
	l.text = fmt % [a, b]
	if is_reduced() or (a == 0 and b == 0):
		return
	l.text = fmt % [0, 0]
	UiKit._when_ready(l, func():
		if not is_instance_valid(l):
			return
		var tw := tween(l, true)
		tw.tween_interval(delay)
		tw.tween_method(func(x: float): l.text = fmt % [roundi(a * x), roundi(b * x)], 0.0, 1.0, dur_s).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): l.text = fmt % [a, b]))


## Brighten a control and ease back. Colour multiplies the control's own modulate.
static func flash(c: CanvasItem, boost := 0.8, dur_s := 0.55, delay := 0.0) -> void:
	if is_reduced():
		return
	UiKit._when_ready(c, func():
		if not is_instance_valid(c):
			return
		var base := c.modulate
		var hot := Color(base.r + boost, base.g + boost, base.b + boost, base.a)
		var tw := tween(c, true)
		tw.tween_interval(delay)
		tw.tween_property(c, "modulate", hot, dur_s * 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate", base, dur_s * 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func(): c.modulate = base))


## Scale a control in from big and transparent with a small overshoot (badges, stamps).
## The control must already be in the tree when this runs, or it waits for it.
static func stamp(c: Control, delay := 0.0, from_scale := 1.9) -> void:
	if is_reduced():
		return
	c.modulate.a = 0.0
	after_layout(c, func():
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(from_scale, from_scale)
		var tw := tween(c, true)
		tw.tween_interval(delay)
		tw.tween_property(c, "modulate:a", 1.0, 0.12)
		tw.parallel().tween_property(c, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func():
			c.scale = Vector2.ONE
			c.modulate.a = 1.0))


## Quick settle: a control starts slightly big and eases to size (number changes, tiles).
static func pop(c: Control, k := 1.12, dur_s := 0.28) -> void:
	if is_reduced():
		return
	after_layout(c, func():
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(k, k)
		var tw := tween(c)
		tw.tween_property(c, "scale", Vector2.ONE, dur_s).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## A short left-right rocking of a control (warnings). Uses rotation so containers don't undo it.
static func wobble(c: Control, amount := 0.04, delay := 0.0) -> void:
	if is_reduced():
		return
	after_layout(c, func():
		c.pivot_offset = c.size / 2.0
		var tw := tween(c)
		tw.tween_interval(delay)
		for k in [1.0, -0.8, 0.5, -0.25, 0.0]:
			tw.tween_property(c, "rotation", amount * k, 0.07).set_trans(Tween.TRANS_SINE))


## Fade and slide a control in from `from` pixels to the side/below its place. Containers own
## position, so this only moves a control's draw via a translated modulate-safe offset: it fades
## and scales from a slightly smaller size instead.
static func reveal(c: Control, delay := 0.0, dur_s := 0.3) -> void:
	if is_reduced():
		return
	c.modulate.a = 0.0
	after_layout(c, func():
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(0.92, 0.92)
		var tw := tween(c, true)
		tw.tween_interval(delay)
		tw.tween_property(c, "modulate:a", 1.0, dur_s)
		tw.parallel().tween_property(c, "scale", Vector2.ONE, dur_s).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func():
			c.scale = Vector2.ONE
			c.modulate.a = 1.0))


## Tint a control's background-ish colour: briefly overlay a coloured wash that fades out.
static func wash(c: Control, color: Color, dur_s := 0.8, delay := 0.0) -> void:
	if is_reduced():
		return
	after_layout(c, func():
		var r := ColorRect.new()
		r.color = Color(color, 0.0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.top_level = true
		r.z_index = 40
		c.add_child(r)
		r.global_position = c.global_position
		r.size = c.size
		var tw := r.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(r, "color:a", color.a, dur_s * 0.2)
		tw.tween_property(r, "color:a", 0.0, dur_s * 0.8)
		tw.tween_callback(r.queue_free))

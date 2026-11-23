class_name MenuText
extends Button
## Text-only menu entry: no plate and no outline at rest. Hover or focus (thumbstick / D-pad) slides the
## label right, lights it white with an accent glow and draws an accent slash at its left edge. Optional small
## caption under the label and a right-aligned value ("Normal", "SOON"). The front-end's standard button.

var accent := Color("#f59e0b")
var rest_alpha := 0.62
## 0 = at rest, 1 = highlighted (tweened).
var hl := 0.0:
	set(v):
		hl = v
		_apply()

var _lab: Label
var _sub: Label
var _val: Label
var _bar: Panel
var _pad := 26.0
var _text_size := 48


func _init(text: String, size := 48, accent_color := Color("#f59e0b"), caption := "", min_width := 520.0) -> void:
	accent = accent_color
	_text_size = size
	flat = true
	focus_mode = Control.FOCUS_ALL
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	custom_minimum_size = Vector2(min_width, size * 1.28 + (24 if caption != "" else 0))
	for k in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(k, StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_STOP

	_bar = Panel.new()
	var bs := UiKit.flat(accent, 2)
	bs.skew = Vector2(UiKit.SKEW * 2.0, 0)
	_bar.add_theme_stylebox_override("panel", bs)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.anchor_top = 0.5
	_bar.anchor_bottom = 0.5
	_bar.offset_left = 2
	_bar.offset_right = 12
	_bar.offset_top = -size * 0.42 - (10 if caption != "" else 0)
	_bar.offset_bottom = size * 0.42 - (10 if caption != "" else 0)
	_bar.modulate.a = 0.0
	add_child(_bar)

	_lab = UiKit.display(text.to_upper(), size, Color.WHITE, true)
	_lab.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lab.offset_left = _pad
	_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if caption != "":
		_lab.offset_bottom = -22
	add_child(_lab)
	if caption != "":
		_sub = UiKit.label(caption, 16, UiKit.MUTED)
		_sub.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_sub.offset_top = -30
		_sub.offset_left = _pad + 2
		_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		add_child(_sub)

	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	mouse_entered.connect(_on_mouse)
	_apply()


## Right-aligned value text (a setting's current value, a "SOON" tag).
func set_value(text: String, size := 0) -> void:
	if _val == null:
		_val = UiKit.display(text, size if size > 0 else maxi(18, int(_text_size * 0.55)), UiKit.MUTED)
		_val.set_anchors_preset(Control.PRESET_FULL_RECT)
		_val.offset_right = -10
		_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_val)
	_val.text = text


func set_caption(text: String) -> void:
	if _sub != null:
		_sub.text = text


func _on_mouse() -> void:
	if not disabled and not has_focus():
		grab_focus()


func _on_focus(on: bool) -> void:
	var to := 1.0 if on else 0.0
	if Fx.is_reduced():
		hl = to
		return
	create_tween().tween_property(self, "hl", to, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _apply() -> void:
	if _lab == null:
		return
	var base := rest_alpha if not disabled else 0.28
	var c := Color(1, 1, 1, lerpf(base, 1.0, hl))
	_lab.add_theme_color_override("font_color", c)
	_lab.offset_left = _pad + 16.0 * hl
	if _sub != null:
		_sub.offset_left = _pad + 2.0 + 16.0 * hl
		_sub.add_theme_color_override("font_color", UiKit.MUTED.lerp(Color("#cbd5e1"), hl))
	_lab.add_theme_color_override("font_shadow_color", Color(accent, 0.38 * hl))
	_lab.add_theme_constant_override("shadow_outline_size", int(6 * hl))
	_lab.add_theme_constant_override("shadow_offset_y", 0)
	_bar.modulate.a = hl
	_bar.offset_left = -6 + 8.0 * hl
	_bar.offset_right = 4 + 8.0 * hl
	if _val != null:
		_val.add_theme_color_override("font_color", UiKit.MUTED.lerp(Color.WHITE, hl))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
		_apply()

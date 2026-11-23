class_name SettingsScreen
extends Control
## Front-end settings: the global trade difficulty and animation options, plus the developer tools (Data Edit,
## Debug Sim Tools). Text rows with the current value on the right; the highlighted row explains itself on the right.

var app: Control

var _desc_title: Label
var _desc_body: Label
var _trade: MenuText
var _anim: MenuText


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(FrontEnd.Scene.new())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 96)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 90)
	margin.add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 760
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	var back := MenuText.new("< Back", 26, UiKit.MUTED, "", 160)
	back.rest_alpha = 0.55
	back.pressed.connect(app.show_title)
	back.set_meta(&"skip_autofocus", true)
	left.add_child(back)
	var gap := Control.new()
	gap.custom_minimum_size.y = 28
	left.add_child(gap)
	left.add_child(UiKit.display("YOUR GAME, YOUR WAY", 22, FrontEnd.FRANCHISE))
	left.add_child(UiKit.display("SETTINGS", 104, Color.WHITE, true))
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 30
	left.add_child(gap2)

	var rows := {}
	_trade = MenuText.new("Trade Difficulty", 44, FrontEnd.FRANCHISE, "", 760)
	_trade.pressed.connect(_cycle_trade)
	left.add_child(_trade)
	rows[_trade] = ["TRADE DIFFICULTY", "How hard the AI bargains. Easy: it can be fleeced. Normal: fair swaps. Hard: it wants an edge. Press to switch."]
	_anim = MenuText.new("Animations", 44, FrontEnd.FRANCHISE, "", 760)
	_anim.pressed.connect(_toggle_anim)
	left.add_child(_anim)
	rows[_anim] = ["ANIMATIONS", "Reduced skips menu motion, count-ups and the drifting backdrop. Press to switch."]
	_refresh()

	var gap3 := Control.new()
	gap3.custom_minimum_size.y = 26
	left.add_child(gap3)
	left.add_child(UiKit.display("DEVELOPER", 18, UiKit.MUTED))
	var data := MenuText.new("Data Edit", 36, FrontEnd.FRANCHISE, "", 760)
	data.pressed.connect(app.show_data_edit)
	left.add_child(data)
	rows[data] = ["DATA EDIT", "Edit teams, soldiers and league data directly."]
	var dbg := MenuText.new("Debug Sim Tools", 36, FrontEnd.FRANCHISE, "", 760)
	dbg.pressed.connect(app.open_debug)
	left.add_child(dbg)
	rows[dbg] = ["DEBUG SIM TOOLS", "Single matches, batch sims and raw ratings sandbox."]

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(grow)

	# Right: the highlighted row explains itself.
	var right := CenterContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(right)
	var card := VBoxContainer.new()
	card.custom_minimum_size.x = 440
	card.add_theme_constant_override("separation", 12)
	right.add_child(card)
	card.add_child(UiKit.display("ABOUT THIS OPTION", 18, UiKit.MUTED))
	_desc_title = UiKit.display("", 52, Color.WHITE, true)
	card.add_child(_desc_title)
	_desc_body = UiKit.label("", 20, Color("#b4bfd0"))
	_desc_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_body.custom_minimum_size.x = 440
	card.add_child(_desc_body)
	for b in rows:
		var d: Array = rows[b]
		b.focus_entered.connect(func():
			_desc_title.text = d[0]
			_desc_body.text = d[1])
	_trade.set_meta(&"first", true)
	_trade.focus_entered.emit()
	UiKit.fade_in(root, 0.0, 0.3)


func _refresh() -> void:
	_trade.set_value(String(Trades.DIFFICULTY_NAMES[Trades.difficulty()]).to_upper())
	_anim.set_value("REDUCED" if Fx.is_reduced() else "ON")


func _cycle_trade() -> void:
	Trades.set_difficulty((Trades.difficulty() + 1) % Trades.DIFFICULTY_NAMES.size())
	_refresh()


func _toggle_anim() -> void:
	Fx.set_reduced(not Fx.is_reduced())
	_refresh()


## Esc / B from the app's global input.
func go_back() -> bool:
	app.show_title()
	return true

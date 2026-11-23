## Fit check: opens every tab/sub-tab/mode at 1600x900, saves a screenshot of each and lists scroll containers that overflow.
## Only pane bodies (lists inside a sub-tab) may scroll. Run windowed:  godot --path . --windowed --script res://tools/fit_check.gd -- <out dir>
extends SceneTree
# Opens every tab / sub-tab / mode, screenshots it, and lists scroll containers whose content overflows.
var out := "."
var hub
func _init() -> void:
	out = OS.get_cmdline_user_args()[0]
	var app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(app)
	for i in 30: await process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	for i in 30: await process_frame
	var season := Season.new_franchise(777, 3)
	for i in 4: season.sim_week()
	app.season = season
	app.show_hub()
	for i in 40: await process_frame
	hub = app.screen
	for t in [0, 4, 5]:
		hub.go_home(); hub.select_tab(t); await _s(); await _rep("tab%d" % t)
	hub.select_tab(1)
	for v in 4:
		hub.team_view = v; hub._pick_team_view(v); await _s(); await _rep("team%d" % v)
	hub.select_tab(2)
	for v in 4:
		hub.personnel_view = v; hub._pers_mode.clear()
		var n: int = hub._personnel_modes(v).size()
		for m in n:
			hub._pers_mode[v] = m; hub._pick_personnel_view(v); await _s(); await _rep("pers%d_%d" % [v, m])
	hub.select_tab(3)
	for v in 7:
		hub.league_view = v; hub._league_mode.clear()
		var n: int = hub._league_modes(v).size()
		for m in n:
			hub._league_mode[v] = m; hub._pick_league_view(v); await _s(); await _rep("league%d_%d" % [v, m])
	quit(0)
func _s() -> void:
	for i in 40: await process_frame
func _rep(n: String) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	var bad: Array = []
	_walk(root, bad)
	print("%s: %s" % [n, "fits" if bad.is_empty() else ", ".join(bad)])
func _walk(n: Node, bad: Array) -> void:
	if n is ScrollContainer and n.is_visible_in_tree():
		var sc: ScrollContainer = n
		var bar := sc.get_v_scroll_bar()
		if bar.max_value > bar.page + 2.0 and sc.size.y > 40:
			bad.append("%s[%d>%d h%d]" % [sc.get_parent().name if sc.get_parent() else "?", int(bar.max_value), int(bar.page), int(sc.size.y)])
	for c in n.get_children():
		_walk(c, bad)

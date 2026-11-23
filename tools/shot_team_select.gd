## Screenshots the Choose Your Team screen.  godot --path . --windowed --script res://tools/shot_team_select.gd -- <out dir> [WxH]
extends SceneTree
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(app)
	for i in 30: await process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var wh := args[1].split("x") if args.size() > 1 else PackedStringArray(["1920", "1080"])
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	for i in 30: await process_frame
	app.show_team_select()
	for i in 60: await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[0] + "/team_select.png")
	quit(0)

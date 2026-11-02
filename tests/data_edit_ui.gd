extends SceneTree
## Opens Data Edit and its picture picker, optionally saving screenshots (windowed run): 
##   godot --path . --script res://tests/data_edit_ui.gd -- out_dir
var app: Control
var out := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(app)
	run.call_deferred()


func shot(name: String) -> void:
	if out == "":
		return
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func run() -> void:
	await process_frame
	app.show_data_edit()
	for i in 5:
		await process_frame
	var de: DataEdit = app.screen
	print("list rows: ", de._row_btns.size(), " cur: ", de._cur)
	await shot("1_edit")
	de._reroll(0)
	await process_frame
	de._open_picker()
	for i in 5:
		await process_frame
	await shot("2_picker")
	print("picker open: ", de._picker != null)
	de._close_picker()
	de.go_back()
	await process_frame
	print("dirty: ", de.ed.dirty_count(), " modal: ", de.get_node_or_null("ConfirmModal") != null)
	await shot("3_modal")
	quit()

extends SceneTree
## Renders sample portraits to PNG (needs a display): godot --path . --script res://tests/portrait_preview.gd -- out.png
## Not part of run_tests.gd.

const NAMES := [["Jalen", "Brooks"], ["Luca", "Novak"], ["Max", "Stone"], ["Tyler", "Hart"], ["Kenji", "Tanaka"], ["Diego", "Reyes"],
	["Malik", "Okafor"], ["Owen", "Brennan"], ["Omar", "Haddad"], ["Isaiah", "Grant"], ["Finn", "Lindqvist"], ["Santiago", "Mendez"]]
const COLORS := ["#b02830", "#1e6e46", "#ecaa1e", "#5a3c96", "#1482aa", "#e66e28"]


func _init() -> void:
	var out := "res://work_portraits.png"
	for a in OS.get_cmdline_user_args():
		out = a
	var vp := SubViewport.new()
	vp.size = Vector2i(1200, 560)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color("#070b14")
	bg.size = Vector2(1200, 560)
	vp.add_child(bg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in NAMES.size():
		var s := PlayerGenerator.generate(rng, 100 + i, Scheme.Role.FLEX, 60.0, 26)
		s.first_name = NAMES[i][0]
		s.last_name = NAMES[i][1]
		var t := Team.new()
		t.color = Color(COLORS[i % COLORS.size()])
		t.color2 = Color("#e5e7eb")
		var p := Portrait.new(s, 170, t.color2, t)
		p.position = Vector2(10 + (i % 6) * 195, 10 + (i / 6) * 270)
		vp.add_child(p)
		var l := Label.new()
		l.text = "%s %s [%s]" % [s.first_name, s.last_name, s.get_face().group]
		l.position = p.position + Vector2(0, 175)
		vp.add_child(l)
	for p in 4:
		var s := PlayerGenerator.generate(rng, 300 + p, Scheme.Role.FLEX, 60.0, 26)
		var sizes := [34, 44, 58, 88]
		var pt := Portrait.new(s, sizes[p], UiKit.LINE, null)
		pt.position = Vector2(10 + p * 110, 500 - sizes[p] / 2.0 * 0)
		vp.add_child(pt)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit()

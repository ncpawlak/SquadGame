extends SceneTree
## Dev tool: screenshots the player-mode screens added for the weekly plan (#138). Needs a display:
##   godot --path . --script res://tools/ui_shot_plan.gd -- <out_dir>
## Writes create.png, home.png, plan.png, camp.png, placement.png and my_player.png.

var out := "."


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	var app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.show_player_create()
	await _settle()
	_shot("create")
	var season := Season.new_franchise(8081)
	var heads: Array = FaceSpec.db()["heads"].keys()
	heads.sort()
	season.player_mode = true
	season.player_archetype = &"sniper"
	season.player = PlayerCareer.create_soldier(season.league.next_soldier_id, "Ada", "Stone", "Zzyzx", heads[2], 3, &"sniper", 19)
	season.league.next_soldier_id += 1
	season.player_combine = Combine.make(&"sniper", 19)
	for g in Combine.DRILL_ORDER:
		var sc := {}
		for t in Combine.drill_tasks(g):
			sc[t["stat"]] = 0.85
		season.player_combine.record_try(g, sc)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	season.player_combine.finalize(season.player, rng)
	season.player_combine_done = true
	PlayerDraft.begin(season)
	PlayerDraft.run(season)
	if season.player_draft_state == PlayerDraft.STATE_OFFERS:
		PlayerDraft.sign_undrafted(season, PlayerDraft.undrafted_offers(season)[0])
	var p := season.player
	p.plan = {WeeklyPlan.PRACTICE: 2, WeeklyPlan.STUDY: 1, WeeklyPlan.SPA: 1}
	p.plan_confirmed = true
	p.skill_points = 9
	p.study_progress = 12.0
	p.brand = 24.0
	p.fatigue = 42.0
	app.season = season
	app.show_hub()
	await _settle()
	var hub = app.screen
	_shot("home")
	hub.player_ui.open_plan(false)
	await _settle()
	_shot("plan")
	hub.go_back()
	hub.player_ui.open_plan(true)
	await _settle()
	_shot("camp")
	hub.go_back()
	hub.player_ui.open_placement(Stats.ACCURACY)
	await _settle()
	_shot("placement")
	hub.go_back()
	hub.player_ui.open_my_player()
	await _settle()
	_shot("my_player")
	quit(0)


func _settle() -> void:
	for i in 8:
		await process_frame


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("saved ", name, " ", img.get_size())

extends SceneTree
## Dev tool: screenshots the player-mode screens added for the weekly plan (#138). Needs a display:
##   godot --path . --script res://tools/ui_shot_warmup.gd -- <out_dir>
## Writes warmup_home.png, warmup.png and warmup_done.png (copy of ui_shot_plan.gd's setup).

var out := "."


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	var app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(app)
	await process_frame
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
	var team := season.user_team()
	if not team.roster.has(p):
		team.green_team.erase(p)
		team.roster.append(p)
	p.plan = {WeeklyPlan.PRACTICE: 2, WeeklyPlan.STUDY: 1, WeeklyPlan.SPA: 1}
	p.plan_confirmed = true
	p.brand = 24.0
	for i in 40:
		if season.phase == Season.PHASE_REGULAR and WarmUp.opponent(season) != null:
			break
		season.sim_week()
	app.season = season
	app.show_hub()
	await _settle()
	var hub = app.screen
	_shot("warmup_home")
	hub.player_ui.open_warmup()
	await _settle()
	_shot("warmup")
	WarmUp.submit(season, Stats.ACCURACY, 0.8)
	hub.go_back()
	hub.player_ui.open_warmup()
	await _settle()
	_shot("warmup_done")
	quit(0)


func _settle() -> void:
	for i in 8:
		await process_frame


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("saved ", name, " ", img.get_size())

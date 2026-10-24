extends SceneTree
## Headless smoke test for the franchise menus: walks every tab and page through a full season.
##   godot --headless --path . --script res://tests/franchise_smoke.gd

var ok := true


func _init() -> void:
	var app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(app)
	await process_frame

	app.show_team_select()
	await process_frame
	app.start_franchise(4242, 2)
	await process_frame
	var hub = app.screen
	_check(hub.season.user_team() == hub.season.league.teams[2], "picked team is user team")
	_check(hub.season.league.teams.size() == 5, "5 teams")

	# Every tab builds, with tiles.
	for i in hub.TABS.size():
		hub.select_tab(i)
		await process_frame
		_check(hub._content.get_child_count() > 0, "tab %s builds" % hub.TABS[i])
	hub.cycle_tab(1)
	_check(hub.tab_index == 0, "tab cycling wraps")

	await _visit_pages(hub, "preseason")
	hub.open("Training", hub.pages.training)
	hub.season.user_team().roster[0].intensity = Soldier.INTENSITY_HEAVY
	hub.replace("Training", hub.pages.training)
	await process_frame

	# Play the season week by week through the hub.
	var guard := 0
	while hub.season.phase != Season.PHASE_OFFSEASON and guard < 20:
		hub.advance()
		await process_frame
		guard += 1
		if guard == 3:
			await _visit_pages(hub, "midseason")
	_check(hub.season.champion != null, "season finished with a champion")
	await _visit_pages(hub, "offseason")

	var player: Soldier = hub.season.user_team().roster[0]
	hub.open(player.full_name(), func(): return hub.pages.player(player))
	await process_frame
	_check(hub.go_back(), "back pops page")
	_check(not hub.go_back(), "back at tab root does nothing")

	hub.advance()  # start next season
	await process_frame
	_check(hub.season.year == 2027 and hub.season.phase == Season.PHASE_REGULAR, "next season started")

	app.open_debug()
	await process_frame
	_check(app.debug_layer != null, "debug tools open")
	app.close_debug()
	await process_frame
	app.show_title()
	await process_frame

	print("Franchise smoke: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _visit_pages(hub, phase: String) -> void:
	var p = hub.pages
	var builders := {
		"standings": p.standings, "schedule": p.schedule, "roster": p.roster, "progression": p.progression,
		"lineup": p.lineup, "training": p.training, "team_stats": p.team_stats, "leaders": p.leaders,
		"playoffs": p.playoffs, "rankings": p.team_rankings, "news": p.news, "sim_options": p.sim_options,
		"injuries": p.injuries,
	}
	for key in builders:
		hub.open(key, builders[key])
		await process_frame
		_check(hub._content.get_child_count() > 0, "%s page builds (%s)" % [key, phase])
		hub.go_back()
	for w in [1, hub.season.week, hub.season.total_weeks()]:
		hub.open("Scores", func(): return p.scores(w))
		await process_frame
		hub.go_back()
	for m in hub.season.matches_for(hub.season.user_team()):
		var mm = m
		hub.open("m", func(): return p.recap(mm) if mm.is_played() else p.preview(mm))
		await process_frame
		hub.go_back()
	for i in hub.TABS.size():
		hub.select_tab(i)
		await process_frame
	hub.select_tab(0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		ok = false
		printerr("  FAIL: ", msg)

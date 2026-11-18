extends SceneTree
## Headless smoke test for player mode's hub: the player Home, Career tab, pages, a week and an offseason.
##   godot --headless --path . --script res://tests/player_hub_smoke.gd

var ok := true


func _check(cond: bool, msg: String) -> void:
	if not cond:
		ok = false
		printerr("  FAIL: ", msg)


func _init() -> void:
	var app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(app)
	await process_frame

	# A player-mode season past the draft.
	var season := Season.new_franchise(8080)
	var heads: Array = FaceSpec.db()["heads"].keys()
	heads.sort()
	season.player_mode = true
	season.player_archetype = &"sniper"
	season.player = PlayerCareer.create_soldier(season.league.next_soldier_id, "Ada", "Stone", "Zzyzx", heads[0], 1, &"sniper")
	season.league.next_soldier_id += 1
	season.player_combine = Combine.make(&"sniper")
	for g in Combine.DRILL_ORDER:
		var sc := {}
		for t in Combine.drill_tasks(g):
			sc[t["stat"]] = 0.9
		season.player_combine.record_try(g, sc)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	season.player_combine.finalize(season.player, rng)
	season.player_combine_done = true
	PlayerDraft.begin(season)
	PlayerDraft.run(season)
	if season.player_draft_state == PlayerDraft.STATE_OFFERS:
		PlayerDraft.sign_undrafted(season, PlayerDraft.undrafted_offers(season)[0])
	app.season = season
	app.show_player_landing()
	await process_frame
	var begin: Button = null
	for b in app.screen.find_children("*", "Button", true, false):
		if b.text == "Begin your rookie season":
			begin = b
	_check(begin != null, "landing has a begin button")
	begin.pressed.emit()
	await process_frame
	await process_frame
	var hub = app.screen
	_check(hub.has_method("advance"), "begin opens the hub")

	# Tabs: manager tabs are hidden; Team is renamed Career.
	_check(hub.visible_tabs() == [hub.Tab.HOME, hub.Tab.TEAM, hub.Tab.LEAGUE, hub.Tab.SETTINGS], "player mode shows four tabs")
	_check(hub.tab_label(hub.Tab.TEAM) == "Career", "Team tab is renamed Career")
	var labels: Array = []
	for b in hub._tab_bar.get_children():
		if b is Button:
			labels.append(b.text)
	_check(labels == ["HOME", "CAREER", "LEAGUE", "SETTINGS"], "tab bar shows %s" % [labels])
	for i in hub.visible_tabs():
		hub.select_tab(i)
		await process_frame
		_check(hub._content.get_child_count() > 0, "tab %s builds" % hub.tab_label(i))
	hub.select_tab(hub.Tab.HOME)
	await process_frame
	_check(hub.tab_index == hub.Tab.HOME, "home selected")
	var col: Node = hub._content.find_child("TodoColumn", true, false)
	_check(col != null, "player home has its left column")
	var texts: Array = []
	for l in hub._content.find_children("*", "Label", true, false):
		texts.append(l.text)
	_check(texts.any(func(t): return t == "YOU" or t == "You"), "home has a You section: %s" % [texts.slice(0, 12)])
	var head_texts: Array = []
	for l in hub._header.find_children("*", "Label", true, false):
		head_texts.append(l.text)
	_check(head_texts.any(func(t): return "ZZYZX" in t), "the header names the player: %s" % [head_texts])
	_check(not head_texts.any(func(t): return t == season.user_team().name.to_upper()), "the header should not lead with the team name")
	hub.cycle_tab(1)
	_check(hub.tab_index == hub.Tab.TEAM, "tab cycling goes Home -> Career")
	hub.cycle_tab(1)
	hub.cycle_tab(1)
	hub.cycle_tab(1)
	_check(hub.tab_index == hub.Tab.HOME, "tab cycling wraps over the four tabs")

	# Pages.
	for pg in [["My Player", hub.player_ui.my_player], ["Game Log", hub.player_ui.game_log], ["Contract", hub.player_ui.contract]]:
		hub.open(pg[0], pg[1])
		await process_frame
		_check(hub._content.get_child_count() > 0, "%s page builds" % pg[0])
		hub.go_back()
	# Spend skill points and change training from My Player.
	var p: Soldier = season.player
	p.skill_points = 30
	for g in Stats.UPGRADABLE_GROUPS:
		p.group_caps[g] = 99
	hub.open("My Player", hub.player_ui.my_player)
	await process_frame
	var before := p.skill_points
	for b in hub._content.find_children("*", "Button", true, false):
		if not b.disabled and b.custom_minimum_size.y == 78:
			b.pressed.emit()
			break
	await process_frame
	_check(p.skill_points < before, "clicking a group spends skill points")
	for b in hub._content.find_children("*", "Button", true, false):
		if String(b.text).begins_with("Heavy"):
			b.pressed.emit()
			break
	await process_frame
	_check(p.intensity == Soldier.INTENSITY_HEAVY, "training intensity can be changed")
	hub.go_back()
	hub.page_stack.clear()
	hub._show_current()

	# A week: the grade shows up on Home.
	var w0 := season.week
	hub.sim_week()
	while hub.simming:
		await process_frame
	await process_frame
	_check(season.week == w0 + 1, "a week was played")
	_check(season.player_log.size() == 1, "one log entry after a week, got %d" % season.player_log.size())
	hub.select_tab(hub.Tab.HOME)
	await process_frame
	_check(hub._content.get_child_count() > 0, "home rebuilds after a week")
	hub.open("Game Log", hub.player_ui.game_log)
	await process_frame
	_check(hub._content.get_child_count() > 0, "game log with a game builds")
	hub.go_back()

	# The offseason runs itself.
	season.sim_to_end_of_season()
	hub.page_stack.clear()
	hub._build_header()
	hub._build_tabs()
	hub.select_tab(hub.Tab.HOME)
	await process_frame
	_check(hub._advance_text().begins_with("START"), "advance offers the next season")
	var year := season.year
	hub.advance()
	while hub.simming:
		await process_frame
	await process_frame
	await process_frame
	_check(season.year == year + 1 and season.phase == Season.PHASE_REGULAR, "the next season started (year %d phase %s)" % [season.year, season.phase])
	_check(season.user_team().org().has(season.player), "the player is still with his club")
	_check(hub._content.get_child_count() > 0, "home builds in the new season")

	print("Player hub smoke: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

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
	# A new franchise opens in preseason training camp.
	_check(hub.season.preseason_camp and hub.season.camp_open() and hub.season.week == 1, "new franchise starts in training camp")
	_check(hub._advance_text().begins_with("START 2026"), "advance button starts the season")
	var pre_guy: Soldier = hub.season.user_team().starters()[0]
	_check(not hub.season.run_drill(Stats.MENTALITY, pre_guy).is_empty(), "preseason drill runs")
	hub.open("Drill", func(): return hub.pages.drill_result(Stats.MENTALITY))
	await process_frame
	hub.advance()  # warns about the unused drills
	_check(hub.season.preseason_camp, "unused preseason drills warning holds camp")
	hub.advance()  # closes camp
	await process_frame
	_check(not hub.season.preseason_camp and hub.season.week == 1 and hub.season.phase == Season.PHASE_REGULAR, "camp closed, Week 1 next")
	for t in hub.season.league.teams:
		if not t.user_controlled:
			_check(hub.season.camp.drills_left(t) == 0, "%s ran preseason drills" % t.abbrev)
	# Scouting: press Scout buttons, then open a scouting report.
	hub.open("Scouting", hub.pages.scouting)
	await process_frame
	for i in 3:
		_check(_press(hub, "Scout"), "scout button")
		await process_frame
	var scouted: Prospect = null
	for pr in hub.season.draft.prospects:
		if pr.points > 0:
			scouted = pr
	_check(scouted != null and scouted.points == 3 and hub.season.draft.scout_points == Draft.POINTS_PER_WEEK - 3, "scouting spent points")
	hub.open("p", func(): return hub.pages.prospect(scouted))
	await process_frame
	_check(_press(hub, "Scout ("), "report scout button")
	await process_frame
	_check(scouted.points == 4, "scouted from report")
	hub.page_stack.clear()
	hub.refresh()
	# Auto-progress all.
	for so in hub.season.user_team().roster:
		so.skill_points += 3
	hub.open("Player Progression", hub.pages.progression)
	await process_frame
	_check(_press(hub, "Auto-progress all"), "auto-progress button")
	await process_frame
	var left := 0
	for so in hub.season.user_team().roster:
		left += so.skill_points
	_check(left < 3 * Team.ROSTER_SIZE, "auto-progress spent SP")
	hub.page_stack.clear()
	hub.refresh()
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

	hub.advance()  # offseason: re-sign window -> draft
	await process_frame
	_check(hub.season.phase == Season.PHASE_OFFSEASON, "can't skip the draft")
	_check(hub.season.offseason_stage == Season.OFF_DRAFT, "re-sign window closed into the draft")
	var d: Draft = hub.season.draft
	var user: Team = hub.season.user_team()
	var before_draft := user.roster.size()
	_check(d.is_started() and not d.is_complete(), "draft is open")
	hub.advance()  # blocked while picks remain
	await process_frame
	_check(hub.season.offseason_stage == Season.OFF_DRAFT, "advance blocked until the draft is done")
	while not d.is_complete():
		if d.on_the_clock() == user:
			_check(_press(hub, "Draft"), "draft button")
		else:
			_check(_press(hub, "Sim "), "sim to pick button")
		await process_frame
	_check(user.roster.size() == before_draft + Draft.ROUNDS, "user drafted %d" % Draft.ROUNDS)
	await _visit_pages(hub, "post-draft")
	hub.advance()  # open free agency
	await process_frame
	_check(hub.season.offseason_stage == Season.OFF_FREE_AGENCY, "free agency open")
	for t in hub.season.league.teams:
		if t != user:
			_check(t.roster.size() <= Team.ROSTER_SIZE, "AI cut to limit")
	_check(not hub.season.league.free_agents.is_empty(), "free agent pool")
	var fa_target: Soldier = hub.season.league.free_agents[0]
	hub.pages.open_offer(fa_target)
	await process_frame
	await _visit_pages(hub, "free agency")
	while user.is_over_roster_limit():
		var cut: Soldier = user.bench().back()
		hub.pages.open_player(cut, 2)
		await process_frame
		_check(_press(hub, "Release"), "release button")
		await process_frame
		_check(_press(hub, "Confirm"), "confirm release")
		await process_frame
	_check(user.lineup.size() == 5, "user lineup intact after cuts")
	var guard2 := 0
	while hub.season.offseason_stage != Season.OFF_CAMP and guard2 < 10:
		hub.advance()
		await process_frame
		guard2 += 1
	_check(hub.season.offseason_stage == Season.OFF_CAMP, "free agency days finished into training camp")
	var drill_guy: Soldier = user.starters()[0]
	var ovr_before := drill_guy.best_ovr()
	var res: Dictionary = hub.season.run_drill(Stats.ACCURACY, drill_guy)
	_check(not res.is_empty() and res["points"] > 0, "user ran the accuracy drill")
	_check(hub.season.run_drill(Stats.HANDLING, drill_guy).is_empty(), "one drill per player")
	_check(drill_guy.best_ovr() >= ovr_before, "drill doesn't lower OVR")
	hub.open("Drill", func(): return hub.pages.drill_result(Stats.ACCURACY))
	await process_frame
	_check(hub._content.get_child_count() > 0, "drill result page builds")
	hub.go_back()
	await _visit_pages(hub, "training camp")
	hub.advance()  # warns about unused drills
	await process_frame
	_check(hub.season.offseason_stage == Season.OFF_CAMP and hub.season.year == 2026, "unused drills warning holds the season")
	hub.advance()  # start next season
	await process_frame
	for t in hub.season.league.teams:
		if t != user:
			_check(hub.season.camp.drills_left(t) < Camp.DRILLS.size(), "AI %s ran camp drills" % t.abbrev)
	_check(hub.season.year == 2027 and hub.season.phase == Season.PHASE_REGULAR, "next season started")
	_check(hub.season.draft.year == 2027 and hub.season.draft.scout_points == Draft.POINTS_PER_WEEK, "new draft class")
	await _visit_pages(hub, "new season")

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
		"injuries": p.injuries, "scouting": p.scouting, "draft_room": p.draft_room, "mock_draft": p.mock_draft,
		"awards": p.awards, "teams": p.teams, "free_agents": p.free_agents, "contracts": p.contracts,
		"resign": p.resign, "retirements": p.retirements, "offer": p.offer,
		"other_roster": func(): return p.team_roster(hub.season.league.teams[1]),
		"signings": func(): return p.signings("Test", hub.season.fa.history.slice(-5)),
		"training_camp": p.training_camp,
	}
	for g in Camp.DRILLS:
		var gg: StringName = g
		builders["drill_pick_" + str(g)] = func(): return p.drill_pick(gg)
	var recap_draft: Draft = hub.season.draft if hub.season.draft.is_complete() else (hub.season.past_drafts[-1] if not hub.season.past_drafts.is_empty() else null)
	if recap_draft != null:
		builders["draft_recap"] = func(): return p.draft_recap(recap_draft)
	if not hub.season.draft.news.is_empty():
		var np: Prospect = hub.season.draft.news[-1]["prospect"]
		builders["news_prospect"] = func(): return p.prospect(np)
	if not hub.season.league.free_agents.is_empty():
		var fa_s: Soldier = hub.season.league.free_agents[0]
		builders["fa_player"] = func(): return p.player(fa_s)
	if not hub.season.retirements.is_empty():
		var r_s: Soldier = hub.season.retirements[0]["soldier"]
		builders["retired_player"] = func(): return p.player(r_s)
	p.retire_scope_team = false
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


## Presses the first enabled button in the current page whose text starts with `prefix`.
func _press(hub, prefix: String) -> bool:
	var b := _find_button(hub._content, prefix)
	if b == null:
		return false
	b.pressed.emit()
	return true


func _find_button(n: Node, prefix: String) -> Button:
	if n is Button and not n.disabled and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var found := _find_button(c, prefix)
		if found != null:
			return found
	return null


func _check(cond: bool, msg: String) -> void:
	if not cond:
		ok = false
		printerr("  FAIL: ", msg)

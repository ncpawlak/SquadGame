extends SceneTree
## UI smoke test for the Fantasy Draft Room and the Set Roster tile.
##   godot --headless --path . --script res://tests/fantasy_draft_ui.gd
## Uses the real engine (Season.start_fantasy_draft) when it exists, else tests/fantasy_draft_stub.gd.

var ok := true


func _init() -> void:
	var app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.season = Season.new_franchise(4242, 2, 2026, true)
	var season: Season = app.season
	if season.has_method("start_fantasy_draft"):
		season.start_fantasy_draft()
	else:
		if not ("fantasy_draft_state" in season):
			print("Fantasy draft UI: SKIP (no Season.fantasy_draft_state in this tree)")
			quit(0)
			return
		season.set("fantasy_draft", load("res://tests/fantasy_draft_stub.gd").make(season.league, season.user_team()))
		season.set("fantasy_draft_state", &"drafting")
	app.show_hub()
	await process_frame
	var hub = app.screen
	await process_frame
	var d = season.get("fantasy_draft")
	var user := season.user_team()

	# Opens automatically on a hub that starts mid-draft.
	_check(hub.page_stack.size() == 1 and hub.page_stack[-1]["title"] == "Fantasy Draft", "draft room opens on load")
	_check(_btn(hub, "Sim Next Pick") != null and _btn(hub, "Draft Selected Player") != null, "draft room buttons")

	# Home shows only the Fantasy Draft tile while drafting.
	hub.page_stack.clear()
	hub.select_tab(0)
	await process_frame
	_check(_tile(hub, "Fantasy Draft") != null, "home has a Fantasy Draft tile")
	_check(_tile(hub, "Adjust Lineup") == null and _tile(hub, "Set Roster") == null, "other tiles hidden during the draft")
	_tile(hub, "Fantasy Draft").pressed.emit()
	await process_frame
	_check(hub.page_stack[-1]["title"] == "Fantasy Draft", "tile opens the room")

	# Sim to the user's pick, suggest, select, draft.
	if not d.user_on_clock():
		_btn(hub, "Sim to My Next Pick").pressed.emit()
		await process_frame
	_check(d.user_on_clock(), "sim to my next pick lands on the user")
	_check(_btn(hub, "Draft Selected Player").disabled, "draft disabled with no selection")
	_btn(hub, "Suggested Pick").pressed.emit()
	await process_frame
	_check(not _btn(hub, "Draft Selected Player").disabled, "suggest selects a player")
	var mine_before: int = d.team_picks(user).size()
	_btn(hub, "Draft Selected Player").pressed.emit()
	await process_frame
	_check(d.team_picks(user).size() == mine_before + 1, "drafted the selected player")
	_check(not d.user_on_clock(), "clock moves on")
	var n_before: int = d.results().size()
	_btn(hub, "Sim Next Pick").pressed.emit()
	await process_frame
	_check(d.results().size() == n_before + 1, "sim next pick")

	# Search narrows the board; sort and filter rebuild without errors.
	var le: LineEdit = hub.find_children("FantasySearch", "LineEdit", true, false)[0]
	le.text_changed.emit("zzzzqq")
	await process_frame
	_check(hub.fantasy._board_list().is_empty(), "search filters the board")
	le.text_changed.emit("")
	hub.fantasy.sort_key = &"age"
	hub.fantasy.role_filter = Scheme.Role.CENTER
	hub.fantasy._refresh()
	await process_frame
	var board: Array = hub.fantasy._board_list()
	_check(not board.is_empty() and board.all(func(x: Soldier): return Scheme.best_role(x.stats) == Scheme.Role.CENTER), "role filter")
	hub.fantasy.role_filter = -1
	hub.fantasy._refresh()
	await process_frame

	# Sim to end shows the final board and Continue.
	_btn(hub, "Sim to End").pressed.emit()
	await process_frame
	_check(d.is_complete(), "sim to end completes the draft")
	var cont := _btn(hub, "Continue")
	_check(cont != null, "Continue button")
	if cont != null:
		cont.pressed.emit()
		await process_frame
		_check(not FantasyDraftPages.is_drafting(season), "Continue finishes the draft")
		_check(hub.tab_index == 0 and hub.page_stack.is_empty(), "Continue routes Home")

	# Set Roster tile only while roster_set_open.
	season.set("roster_set_open", false)
	hub.select_tab(0)
	await process_frame
	_check(_tile(hub, "Set Roster") == null, "no Set Roster tile when closed")
	season.set("roster_set_open", true)
	hub.select_tab(0)
	await process_frame
	var tile := _tile(hub, "Set Roster")
	_check(tile != null, "Set Roster tile when open")
	if tile != null:
		tile.pressed.emit()
		await process_frame
		_check(hub.page_stack[-1]["title"] == "Set Roster", "tile opens Set Roster")
	user.green_team.pop_back()
	var r0 := user.roster.size()
	var g0 := user.green_team.size()
	var guy: Soldier = user.roster[-1]
	_check(FantasyDraftPages.move(season, user, guy, true) == "", "move to green")
	_check(user.roster.size() == r0 - 1 and user.green_team.size() == g0 + 1 and user.green_team.has(guy), "move updated both lists")
	_check(FantasyDraftPages.move(season, user, guy, false) == "", "move back to roster")
	while user.green_team.size() < Team.GREEN_SIZE:
		user.green_team.append(user.roster.pop_back())
	_check(FantasyDraftPages.move(season, user, user.roster[0], true) != "", "green cap enforced")
	while user.roster.size() < Team.ROSTER_SIZE:
		user.roster.append(user.green_team.pop_back())
	_check(FantasyDraftPages.move(season, user, user.green_team[0], false) != "", "roster cap enforced")
	hub.replace("Set Roster", hub.fantasy.set_roster)
	await process_frame
	_check(hub.page_stack[-1]["title"] == "Set Roster", "Set Roster page rebuilds")
	season.set("roster_set_open", false)
	_check(FantasyDraftPages.move(season, user, user.roster[0], true) != "", "moves refused when closed")

	print("Fantasy draft UI: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


## A button by its text (action buttons).
func _btn(node: Node, text: String) -> Button:
	for b in node.find_children("*", "Button", true, false):
		if b.visible and b.text.strip_edges() == text:
			return b
	return null


## A to-do tile by its title (tiles carry the title in a label).
func _tile(node: Node, title: String) -> Button:
	for b in node.find_children("*", "Button", true, false):
		if not b.visible:
			continue
		for l in b.find_children("*", "Label", true, false):
			if (l as Label).text == title.to_upper():
				return b
	return null


func _check(cond: bool, msg: String) -> void:
	if not cond:
		ok = false
		printerr("  FAIL: ", msg)

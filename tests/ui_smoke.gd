extends SceneTree
## Headless UI smoke test: drives the debug UI's main actions and fails on script errors.
##   godot --headless --path . --script res://tests/ui_smoke.gd

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var ok := true
	ok = _check(main.league.teams.size() == 2, "2 teams") and ok

	main._sim_match()
	await process_frame
	ok = _check(main.log_text.text.contains("FINAL"), "play-by-play rendered") and ok
	ok = _check(main.box_tree.get_root() != null, "box score rendered") and ok
	ok = _check(main.progress_text.text.contains("XP"), "progression report rendered") and ok

	var user: Team = main._user_team()
	var s: Soldier = user.roster[0]
	s.intensity = Soldier.INTENSITY_HEAVY
	main._train_week()
	await process_frame
	ok = _check(main.progress_text.text.contains("(Heavy)"), "training intensity shown") and ok

	s.skill_points = 50
	main.selected = s
	main._refresh_card()
	var before: int = s.group_rating(Stats.ACCURACY)
	Progression.upgrade_group(s, Stats.ACCURACY, main.rng)
	ok = _check(s.group_rating(Stats.ACCURACY) == before + 1 or Progression.is_capped(s, Stats.ACCURACY), "group upgrade") and ok

	var bench: Soldier = user.bench()[0]
	user.assign(&"CTR", bench)
	main._refresh_roster()
	ok = _check(user.lineup[&"CTR"] == bench, "lineup assign") and ok

	main._batch_sim()
	await process_frame
	ok = _check(main.batch_text.text.contains("win rate"), "batch sim rendered") and ok

	main._new_league()
	await process_frame
	ok = _check(main.week == 1, "new league resets") and ok

	print("UI smoke: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("  FAIL: ", msg)
	return cond

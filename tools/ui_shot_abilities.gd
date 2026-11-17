extends SceneTree
## Dev tool: screenshots the player Overview (ability cards) for a few soldiers. Needs a display:
##   godot --path . --script res://tools/ui_shot_abilities.gd -- <out_dir>
## Writes player_elite.png, player_young.png and player_locked.png (one soldier with a locked ability).


func _init() -> void:
	var out := "."
	for a in OS.get_cmdline_user_args():
		out = a
	var app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.start_franchise(4242, 2)
	while not (app.screen is Control and app.screen.has_method("advance")):
		await process_frame
	await process_frame
	var hub = app.screen
	var team: Team = hub.season.user_team()
	var roster: Array = team.roster.duplicate()
	roster.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	var young: Soldier = roster.filter(func(s: Soldier): return s.age <= 23)[0] if not roster.filter(func(s: Soldier): return s.age <= 23).is_empty() else roster[-1]
	var weak: Soldier = roster[-1]
	# A locked ability: drop one of his required ratings below bronze.
	var locked: Soldier = roster[2]
	if not locked.abilities.is_empty():
		var first: Dictionary = locked.abilities[0]
		locked.stats[Abilities.def(first["id"])["stats"][0]] = 60
		Abilities.refresh(locked)
	var shots := {"player_elite": roster[0], "player_young": young, "player_locked": locked, "player_weak": weak}
	for k in shots:
		# Overview (medals on the right), then the Ratings tab (expanded cards).
		for tab in [0, 1]:
			hub.pages.open_player(shots[k], tab)
			for i in 6:
				await process_frame
			await _shoot(out, "%s_%s_top" % [k, "overview" if tab == 0 else "ratings"])
			var sc := _first_scroll(hub)
			if sc != null:
				var head: Control = null
				for l: Label in hub.find_children("*", "Label", true, false):
					if l.text == "ABILITIES":
						head = l
				if head != null:
					sc.scroll_vertical = maxi(0, int(head.global_position.y - sc.global_position.y + sc.scroll_vertical - 10))
					await _shoot(out, "%s_%s_cards" % [k, "overview" if tab == 0 else "ratings"])
				sc.scroll_vertical = 100000
				await _shoot(out, "%s_%s_bottom" % [k, "overview" if tab == 0 else "ratings"])
		print("saved ", k, " ", shots[k].full_name(), " abilities=", shots[k].abilities.map(func(e): return "%s:%d" % [e["id"], e["tier"]]))
	quit()


## The page's scroll container (the biggest one).
func _first_scroll(hub: Node) -> ScrollContainer:
	var best: ScrollContainer = null
	for n: ScrollContainer in hub.find_children("*", "ScrollContainer", true, false):
		if best == null or n.size.y > best.size.y:
			best = n
	return best


func _shoot(out: String, name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])

class_name CombineScreen
extends RefCounted
## Player mode phase 2 (#101): the combine screens. `make` is the drill hub plus the mini-game runner; `results` is the
## report of the rating bands once the combine is locked in. Rules live in Combine; the tasks in CombineTasks.


## on_done: Callable() once the player locks the combine in. on_back: Callable() to leave without locking.
static func make(season: Season, on_done: Callable, on_back: Callable) -> Control:
	var combine: Combine = season.player_combine
	var root := VBoxContainer.new()
	root.name = "CombineScreen"
	root.add_theme_constant_override("separation", 10)
	var wrap := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		wrap.add_theme_constant_override("margin_" + side, 22)
	wrap.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var back := UiKit.button("< Back", on_back, 18)
	UiKit.style_skewed(back)
	back.custom_minimum_size = Vector2(120, 48)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.set_meta(&"skip_autofocus", true)
	head.add_child(back)
	var sp := Control.new()
	sp.custom_minimum_size.x = 16
	head.add_child(sp)
	var tt := VBoxContainer.new()
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tt.add_child(UiKit.display("THE COMBINE", 44, Color.WHITE, true))
	var bar := ColorRect.new()
	bar.color = UiKit.ACCENT
	bar.custom_minimum_size = Vector2(90, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tt.add_child(bar)
	tt.add_child(UiKit.label("Run each drill up to %d times. Your best score on every rating counts, and sets the range scouts see." % Combine.TRIES, 15, UiKit.MUTED))
	head.add_child(tt)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left := UiKit.panel(UiKit.PANEL, 12)
	left.custom_minimum_size.x = 360
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	var right := UiKit.panel(UiKit.PANEL, 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var stage := VBoxContainer.new()
	stage.add_theme_constant_override("separation", 10)
	stage.name = "Stage"
	right.add_child(stage)

	var fns := {}
	var clear := func(box: Control):
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()

	fns["list"] = func():
		clear.call(lv)
		lv.add_child(UiKit.display("DRILLS", 22, UiKit.ACCENT, true))
		for g in Combine.DRILL_ORDER:
			var drill: Dictionary = Camp.DRILLS[g]
			var left_n := combine.tries_left(g)
			var status := "Not run" if not combine.has_run(g) else "%d / %d tries used" % [Combine.TRIES - left_n, Combine.TRIES]
			var row := UiKit.panel(UiKit.PANEL_HI, 8)
			var rv := VBoxContainer.new()
			row.add_child(rv)
			rv.add_child(UiKit.display(String(drill["name"]), 20, Color.WHITE, true))
			rv.add_child(UiKit.label(String(drill["blurb"]), 13, UiKit.MUTED))
			rv.add_child(UiKit.label(status, 14, UiKit.GOOD if combine.has_run(g) else UiKit.MUTED))
			var btn := UiKit.action_button("Run drill" if left_n > 0 else "No tries left", func(): fns["drill"].call(g), 16)
			btn.disabled = left_n <= 0
			rv.add_child(btn)
			lv.add_child(row)
		var fin := UiKit.primary_button("Lock in combine", on_done, 20)
		fin.disabled = not combine.is_complete()
		lv.add_child(fin)
		if not combine.is_complete():
			lv.add_child(UiKit.label("Run every drill at least once to finish.", 13, UiKit.MUTED))

	fns["hub"] = func():
		clear.call(stage)
		fns["list"].call()
		stage.add_child(UiKit.display("YOUR RANGES SO FAR", 24, UiKit.ACCENT, true))
		stage.add_child(UiKit.label("Each range is where your rating can land. Where inside it depends on talent you cannot see.", 15, UiKit.MUTED))
		var b := combine.bands()
		var any := false
		for g in Combine.DRILL_ORDER:
			if not combine.has_run(g):
				continue
			any = true
			stage.add_child(UiKit.label(String(Camp.DRILLS[g]["name"]), 16, UiKit.GOLD))
			for t in Combine.drill_tasks(g):
				var stat: StringName = t["stat"]
				var s: float = float(combine.best.get(stat, 0.0))
				stage.add_child(UiKit.label("   %-18s best %3d%%    range %d - %d" % [Stats.LABELS[stat], roundi(s * 100.0), b[stat].x, b[stat].y], 15, UiKit.TEXT))
		if not any:
			stage.add_child(UiKit.label("Run a drill to start.", 17, UiKit.MUTED))
		else:
			var r := combine.ovr_range()
			stage.add_child(UiKit.label("Overall range: %d - %d  (capped at %d)" % [r.x, r.y, Archetypes.START_OVR_CAP], 18, Color.WHITE))

	fns["drill"] = func(group: StringName):
		var tasks: Array = Combine.drill_tasks(group)
		var run := {"i": 0, "scores": {}}
		fns["brief"] = func():
			clear.call(stage)
			var spec: Dictionary = tasks[run["i"]]
			stage.add_child(UiKit.display("%s  -  %s" % [Camp.DRILLS[group]["name"], spec["label"]], 28, Color.WHITE, true))
			stage.add_child(UiKit.label("Task %d of %d" % [run["i"] + 1, tasks.size()], 15, UiKit.MUTED))
			var preview := CombineTasks.make(spec)
			var ins := UiKit.label(preview.instructions(), 18, UiKit.TEXT)
			ins.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			stage.add_child(ins)
			preview.free()
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			stage.add_child(row)
			row.add_child(UiKit.primary_button("Start", func(): fns["play"].call(), 22))
			row.add_child(UiKit.button("Quit drill (keeps your try)", func(): fns["hub"].call(), 16))
		fns["play"] = func():
			clear.call(stage)
			var spec: Dictionary = tasks[run["i"]]
			var task := CombineTasks.make(spec)
			stage.add_child(task)
			task.grab_focus()
			task.finished.connect(func(score: float):
				run["scores"][spec["stat"]] = score
				fns["after"].call(score))
		fns["after"] = func(score: float):
			clear.call(stage)
			var spec: Dictionary = tasks[run["i"]]
			stage.add_child(UiKit.display("%s: %d%%" % [spec["label"], roundi(score * 100.0)], 34, Color.WHITE, true))
			var last: bool = run["i"] >= tasks.size() - 1
			var next := UiKit.primary_button("Finish drill" if last else "Next task", func():
				if last:
					combine.record_try(group, run["scores"])
					fns["hub"].call()
				else:
					run["i"] += 1
					fns["brief"].call(), 22)
			stage.add_child(next)
		fns["brief"].call()

	fns["hub"].call()
	return wrap


## The report once the combine is locked in: the band for every rating and the overall range.
static func results(season: Season, on_continue: Callable) -> Control:
	var combine: Combine = season.player_combine
	var s := season.player
	var b := combine.bands()
	var root := VBoxContainer.new()
	root.name = "CombineResults"
	root.add_theme_constant_override("separation", 6)
	var wrap := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		wrap.add_theme_constant_override("margin_" + side, 30)
	wrap.add_child(root)
	root.add_child(UiKit.display("COMBINE REPORT", 44, Color.WHITE, true))
	root.add_child(UiKit.label("%s \"%s\" %s  -  %s %s" % [s.first_name, s.callsign, s.last_name,
		Archetypes.find(season.player_archetype)["name"], Scheme.ROLE_NAMES[Archetypes.role_of(season.player_archetype)]], 18, UiKit.ACCENT))
	var r := combine.ovr_range()
	root.add_child(UiKit.label("Overall range: %d - %d" % [r.x, r.y], 24, Color.WHITE))
	root.add_child(UiKit.label("Starting OVR is capped at %d. Your true ratings sit inside these ranges." % Archetypes.START_OVR_CAP, 14, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 2)
	root.add_child(grid)
	for g in Combine.DRILL_ORDER:
		var col := VBoxContainer.new()
		col.add_child(UiKit.label(String(Camp.DRILLS[g]["name"]), 17, UiKit.GOLD))
		for t in Combine.drill_tasks(g):
			var stat: StringName = t["stat"]
			col.add_child(UiKit.label("%-18s %3d - %-3d" % [Stats.LABELS[stat], b[stat].x, b[stat].y], 15, UiKit.TEXT))
		grid.add_child(col)
	var story_stars := int(Backstory.find(s.backstory)["stars"])
	var stars_line := "Dev stars: %s" % s.dev_text()
	if s.dev < story_stars:
		stars_line += "   (your story starts at %s, but a weak combine took one off. Earn it back with study.)" % Soldier.dev_stars(story_stars)
	root.add_child(UiKit.label(stars_line, 16, UiKit.GOLD))
	var note := UiKit.label("The draft is next.", 15, UiKit.MUTED)
	root.add_child(note)
	root.add_child(UiKit.primary_button("Continue", on_continue, 22))
	return wrap

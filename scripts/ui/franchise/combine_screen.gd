class_name CombineScreen
extends RefCounted
## Player mode phase 2 (#101): the combine screens. `make` is the drill hub plus the mini-game runner; `results` is the
## report of the rating bands once the combine is locked in. Rules live in Combine; the tasks in CombineTasks.


## Run the 3D drill for every stat that has one (the 2D mini-game stays for the rest). The checkbox on the drill list flips it.
static var use_3d := true


## on_done: Callable() once the player locks the combine in. on_back: Callable() to leave without locking.
static func make(season: Season, on_done: Callable, on_back: Callable) -> Control:
	var combine: Combine = season.player_combine
	var root := VBoxContainer.new()
	root.name = "CombineScreen"
	root.add_theme_constant_override("separation", 10)
	var shell := FrontEnd.backdrop_wrap(FrontEnd.margin(root, 32, 22))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	root.add_child(head)
	head.add_child(FrontEnd.back_link(on_back))
	var tb := FrontEnd.title_block("NEW CAREER  ·  STEP 2 OF 3", "THE COMBINE", FrontEnd.CAREER, 44)
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tb)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left := FrontEnd.glass(14)
	left.custom_minimum_size.x = 420
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	var right := FrontEnd.glass(18)
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
		lv.add_child(UiKit.display("DRILLS", 22, FrontEnd.CAREER, true))
		var cov := FpsCombineDrills.coverage()
		var tg := CheckButton.new()
		tg.text = "3D drills (%d of %d)" % [cov[0], cov[1]]
		tg.button_pressed = CombineScreen.use_3d
		tg.toggled.connect(func(on: bool): CombineScreen.use_3d = on)
		lv.add_child(tg)
		for g in Combine.DRILL_ORDER:
			var drill: Dictionary = Camp.DRILLS[g]
			var left_n := combine.tries_left(g)
			var status := "Not run" if not combine.has_run(g) else "%d / %d tries" % [Combine.TRIES - left_n, Combine.TRIES]
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 64)
			btn.disabled = left_n <= 0
			var done := combine.has_run(g)
			UiKit.style_button(btn, Color(1, 1, 1, 0.06), FrontEnd.CAREER, 10)
			btn.pressed.connect(func(): fns["drill"].call(g))
			var row := HBoxContainer.new()
			row.set_anchors_preset(Control.PRESET_FULL_RECT)
			row.offset_left = 16
			row.offset_right = -16
			row.add_theme_constant_override("separation", 10)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(row)
			var txt := VBoxContainer.new()
			txt.add_theme_constant_override("separation", 0)
			txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
			txt.add_child(UiKit.display(String(drill["name"]).to_upper(), 22, Color.WHITE, true))
			var bl := UiKit.label(String(drill["blurb"]), 14, UiKit.MUTED)
			bl.clip_text = true
			txt.add_child(bl)
			row.add_child(txt)
			var st_l := UiKit.display(("\u2713 " if done else "") + (status if left_n > 0 else "No tries left"), 18, UiKit.GOOD if done else UiKit.MUTED)
			st_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(st_l)
			lv.add_child(btn)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lv.add_child(sp)
		var fin := UiKit.primary_button("Lock in combine", on_done, 20)
		fin.disabled = not combine.is_complete()
		fin.custom_minimum_size.y = 50
		lv.add_child(fin)

	fns["hub"] = func():
		clear.call(stage)
		fns["list"].call()
		stage.add_child(UiKit.display("YOUR RANGES SO FAR", 24, FrontEnd.CAREER, true))
		var b := combine.bands()
		var any := false
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 36)
		grid.add_theme_constant_override("v_separation", 14)
		for g in Combine.DRILL_ORDER:
			if not combine.has_run(g):
				continue
			any = true
			grid.add_child(CombineScreen.drill_card(g, b))
		if not any:
			stage.add_child(FrontEnd.empty_state("Run a drill to see your ranges"))
		else:
			stage.add_child(grid)
			var r := combine.ovr_range()
			var sp2 := Control.new()
			sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
			stage.add_child(sp2)
			stage.add_child(UiKit.display("OVERALL  %d - %d   (capped at %d)" % [r.x, r.y, Archetypes.START_OVR_CAP], 26, Color.WHITE))

	fns["drill"] = func(group: StringName):
		var tasks: Array = Combine.drill_tasks(group)
		var run := {"i": 0, "scores": {}}
		fns["brief"] = func():
			# A 3D drill can score two stats at once (the obstacle course): skip tasks that are already scored.
			while run["scores"].has(tasks[run["i"]]["stat"]) and run["i"] < tasks.size() - 1:
				run["i"] += 1
			if run["scores"].has(tasks[run["i"]]["stat"]):
				combine.record_try(group, run["scores"])
				fns["hub"].call()
				return
			clear.call(stage)
			var spec: Dictionary = tasks[run["i"]]
			var three_d: bool = CombineScreen.use_3d and FpsCombineDrills.available(spec["stat"])
			stage.add_child(UiKit.display("%s  -  %s" % [Camp.DRILLS[group]["name"], spec["label"]], 28, Color.WHITE, true))
			stage.add_child(UiKit.label("Task %d of %d" % [run["i"] + 1, tasks.size()], 15, UiKit.MUTED))
			var ins: Label
			if three_d:
				var probe := (load(FpsCombineDrills.scene_for(spec["stat"])) as PackedScene).instantiate() as FpsDrill
				ins = UiKit.label("3D drill: %s
%s
Mouse to look, click to shoot. Esc quits (and keeps your try)." % [probe.title, probe.instructions], 18, UiKit.TEXT)
				probe.free()
			else:
				var preview := CombineTasks.make(spec)
				ins = UiKit.label(preview.instructions(), 18, UiKit.TEXT)
				preview.free()
			ins.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			stage.add_child(ins)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			stage.add_child(row)
			row.add_child(UiKit.primary_button("Start", func(): fns["play"].call(), 22))
			row.add_child(UiKit.button("Quit drill (keeps your try)", func(): fns["hub"].call(), 16))
		fns["play"] = func():
			var spec: Dictionary = tasks[run["i"]]
			if CombineScreen.use_3d and FpsCombineDrills.available(spec["stat"]):
				# Hide this screen and run the 3D drill full screen; it hands back the stat score(s).
				shell.visible = false
				FpsCombineRunner.launch(shell.get_parent(), spec["stat"], func(scores: Dictionary):
					shell.visible = true
					for st in scores:
						run["scores"][st] = float(scores[st])
					fns["after"].call(float(run["scores"].get(spec["stat"], 0.0))))
				return
			clear.call(stage)
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
	return shell


## One drill's card: its name and a range bar per stat (lo..hi on the 0-99 scale).
static func drill_card(g: StringName, bands: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UiKit.display(String(Camp.DRILLS[g]["name"]).to_upper(), 24, UiKit.GOLD, true))
	for t in Combine.drill_tasks(g):
		var stat: StringName = t["stat"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var nm := UiKit.label(String(Stats.LABELS[stat]), 18, UiKit.TEXT)
		nm.custom_minimum_size.x = 160
		row.add_child(nm)
		row.add_child(FrontEnd.RangeBar.new(bands[stat].x, bands[stat].y))
		var v := UiKit.label("%d - %d" % [bands[stat].x, bands[stat].y], 18, Color.WHITE)
		v.custom_minimum_size.x = 80
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(v)
		col.add_child(row)
	return col


## The report once the combine is locked in: the band for every rating and the overall range.
static func results(season: Season, on_continue: Callable) -> Control:
	var combine: Combine = season.player_combine
	var s := season.player
	var b := combine.bands()
	var root := VBoxContainer.new()
	root.name = "CombineResults"
	root.add_theme_constant_override("separation", 14)
	var shell := FrontEnd.backdrop_wrap(FrontEnd.margin(root, 40, 28))
	var top := HBoxContainer.new()
	root.add_child(top)
	var tb := FrontEnd.title_block("NEW CAREER  ·  STEP 2 OF 3", "COMBINE REPORT")
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tb)
	var r := combine.ovr_range()
	var big := VBoxContainer.new()
	big.add_theme_constant_override("separation", 0)
	var cap := UiKit.display("OVERALL RANGE", 18, UiKit.MUTED)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	big.add_child(cap)
	var num := UiKit.display("%d - %d" % [r.x, r.y], 64, Color.WHITE, true)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	big.add_child(num)
	var capt := UiKit.label("capped at %d" % Archetypes.START_OVR_CAP, 15, UiKit.MUTED)
	capt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	big.add_child(capt)
	top.add_child(big)
	root.add_child(UiKit.display("%s \"%s\" %s  -  %s %s" % [s.first_name, s.callsign, s.last_name,
		Archetypes.find(season.player_archetype)["name"], Scheme.ROLE_NAMES[Archetypes.role_of(season.player_archetype)]], 22, FrontEnd.CAREER))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)
	for g in Combine.DRILL_ORDER:
		var card := FrontEnd.glass(16)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(drill_card(g, b))
		grid.add_child(card)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 20)
	root.add_child(foot)
	var stars := UiKit.display("DEV STARS  %s" % s.dev_text(), 26, UiKit.GOLD)
	stars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(stars)
	var go := UiKit.primary_button("Continue to the draft", on_continue, 22)
	go.custom_minimum_size = Vector2(300, 54)
	foot.add_child(go)
	return shell

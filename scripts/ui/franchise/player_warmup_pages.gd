class_name PlayerWarmupPages
extends RefCounted
## Player mode (#141): the pre-match warm-up page. Pick a stat group, run its combine drill and the score becomes a
## match-only bonus to that group (rules in WarmUp). A small auto-run gives a steady bonus without playing the drill.

var hub: Control


func _season() -> Season:
	return hub.season


func _vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _wrap(text: String, size := 15, color := UiKit.MUTED, width := 980) -> Label:
	var l := UiKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


func warmup_page() -> Control:
	var root := _vbox(10)
	root.custom_minimum_size.x = 1000
	var holder := _vbox(10)
	root.add_child(holder)
	var fns := {}
	fns["render"] = func():
		_clear(holder)
		_fill_hub(holder, fns)
	fns["render"].call()
	return root


func _fill_hub(box: VBoxContainer, fns: Dictionary) -> void:
	var s := _season()
	var p := s.player
	box.add_child(UiKit.display("WARM-UP", 30, Color.WHITE, true))
	var opp := WarmUp.opponent(s)
	var err := WarmUp.error(s)
	if opp != null:
		box.add_child(UiKit.label("This week: %s" % opp.name, 18, UiKit.GOLD))
	if not p.warmup.is_empty() and int(p.warmup.get("key", 0)) == WarmUp.week_key(s):
		var w: Dictionary = p.warmup
		var how := "auto-run" if bool(w.get("auto", false)) else "drill score %d%%" % roundi(float(w["score"]) * 100.0)
		box.add_child(UiKit.label("Done: %s, %s: %s" % [String(Stats.GROUP_LABELS[w["group"]]), how, ("+%d to every rating in the group" % int(w["bonus"])) if int(w["bonus"]) > 0 else "no bonus"], 18, UiKit.GOOD if int(w["bonus"]) > 0 else UiKit.MUTED))
	elif err != "":
		box.add_child(UiKit.label(err, 16, UiKit.MUTED))
	for g in Stats.UPGRADABLE_GROUPS:
		var row := UiKit.panel(UiKit.PANEL_HI, 8)
		var rv := _hbox(14)
		row.add_child(rv)
		var left := _vbox(2)
		left.custom_minimum_size.x = 520
		left.add_child(UiKit.display(String(Stats.GROUP_LABELS[g]), 20, Color.WHITE, true))
		var rep := WarmUp.repeats(p, g)
		var best := WarmUp.bonus_for(1.0, rep, s.phase == Season.PHASE_PLAYOFFS)
		left.add_child(UiKit.label("Rating %d   ·   a perfect run pays +%d%s" % [Stats.group_rating(p.stats, g), best, ("  (you warmed up here %d week%s running)" % [rep, "" if rep == 1 else "s"]) if rep > 0 else ""], 14, UiKit.MUTED))
		rv.add_child(left)
		var run := UiKit.primary_button("Run drill", func(): _run_drill(box, g, fns), 17)
		run.disabled = err != ""
		rv.add_child(run)
		var auto := UiKit.button("Auto-run (+%d)" % WarmUp.bonus_for(WarmUp.AUTO_SCORE, rep, s.phase == Season.PHASE_PLAYOFFS), func():
			var res := WarmUp.submit(s, g, 0.0, true)
			if not res.is_empty():
				hub.app.toast("Warm-up done: +%d %s." % [int(res["bonus"]), String(Stats.GROUP_LABELS[g]).to_lower()])
			fns["render"].call(), 15)
		auto.disabled = err != ""
		rv.add_child(auto)
		box.add_child(row)
	var foot := _hbox(12)
	foot.add_child(UiKit.button("Back", func(): hub.go_back(), 16))
	box.add_child(foot)


## Runs the group's drill task by task; the mean score is the warm-up score.
func _run_drill(box: VBoxContainer, group: StringName, fns: Dictionary) -> void:
	var tasks: Array = Combine.drill_tasks(group)
	var run := {"i": 0, "scores": []}
	var step := {}
	step["brief"] = func():
		_clear(box)
		var spec: Dictionary = tasks[run["i"]]
		box.add_child(UiKit.display("%s  -  %s" % [Camp.DRILLS[group]["name"], spec["label"]], 28, Color.WHITE, true))
		box.add_child(UiKit.label("Task %d of %d" % [run["i"] + 1, tasks.size()], 15, UiKit.MUTED))
		var preview := CombineTasks.make(spec)
		box.add_child(_wrap(preview.instructions(), 18, UiKit.TEXT))
		preview.free()
		var row := _hbox(12)
		box.add_child(row)
		row.add_child(UiKit.primary_button("Start", func(): step["play"].call(), 22))
		row.add_child(UiKit.button("Quit (no bonus)", func(): fns["render"].call(), 16))
	step["play"] = func():
		_clear(box)
		var spec: Dictionary = tasks[run["i"]]
		var task := CombineTasks.make(spec)
		box.add_child(task)
		task.grab_focus()
		task.finished.connect(func(score: float):
			run["scores"].append(score)
			step["after"].call(score))
	step["after"] = func(score: float):
		_clear(box)
		var spec: Dictionary = tasks[run["i"]]
		box.add_child(UiKit.display("%s: %d%%" % [spec["label"], roundi(score * 100.0)], 34, Color.WHITE, true))
		var last: bool = run["i"] >= tasks.size() - 1
		box.add_child(UiKit.primary_button("Finish warm-up" if last else "Next task", func():
			if last:
				var total := 0.0
				for x in run["scores"]:
					total += float(x)
				var res := WarmUp.submit(_season(), group, total / float(maxi(1, run["scores"].size())))
				if not res.is_empty():
					hub.app.toast("Warm-up: %s" % (("+%d %s for this match." % [int(res["bonus"]), String(Stats.GROUP_LABELS[group]).to_lower()]) if int(res["bonus"]) > 0 else "no bonus this time."))
				fns["render"].call()
			else:
				run["i"] += 1
				step["brief"].call(), 22))
	step["brief"].call()

class_name PlayerRequestPages
extends RefCounted
## Player mode (#141): ask the club for a trade. Lists why he may ask, the clubs that would take him, and the answer.

var hub: Control


func _season() -> Season:
	return hub.season


func _vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _wrap(text: String, size := 15, color := UiKit.MUTED, width := 980) -> Label:
	var l := UiKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


func request_page() -> Control:
	var root := _vbox(10)
	root.custom_minimum_size.x = 1000
	var holder := _vbox(10)
	root.add_child(holder)
	var fns := {"answer": ""}
	fns["render"] = func():
		_clear(holder)
		_fill(holder, fns)
	fns["render"].call()
	return root


func _fill(box: VBoxContainer, fns: Dictionary) -> void:
	var s := _season()
	var p := s.player
	box.add_child(UiKit.display("TRADE REQUEST", 30, Color.WHITE, true))
	box.add_child(_wrap("Ask the club to send you somewhere else. You need a real reason, and the club will not let a core player go unless he is unhappy. If it says no you lose a little morale and wait a few weeks. You can change clubs once a season, only while the trade window is open (%s)." % s.trades.window_text(s)))
	if String(fns["answer"]) != "":
		box.add_child(UiKit.label(String(fns["answer"]), 18, UiKit.GOLD))
	box.add_child(UiKit.label("Now with %s" % s.user_team().name, 18, Color.WHITE))
	var err := PlayerRequest.error(s)
	if err != "":
		box.add_child(UiKit.label(err, 16, UiKit.MUTED))
	var why := PlayerRequest.reasons(s)
	if why.is_empty():
		box.add_child(_wrap("Your case: none right now. You are playing, your club is competitive and you are in good spirits."))
	else:
		box.add_child(UiKit.label("Your case", 16, UiKit.GOLD))
		for w in why:
			box.add_child(_wrap("  -  " + String(PlayerRequest.REASON_TEXT[w]), 15, UiKit.TEXT))
	box.add_child(UiKit.label("Clubs that would take you", 16, UiKit.GOLD))
	for d in PlayerRequest.destinations(s):
		var t: Team = d["team"]
		var row := UiKit.panel(UiKit.PANEL_HI, 8)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		var left := _vbox(2)
		left.custom_minimum_size.x = 560
		left.add_child(UiKit.display(t.name, 18, Color.WHITE, true))
		left.add_child(UiKit.label("Ranked %d of %d   ·   %s" % [int(d["rank"]), s.league.teams.size(), "you would start" if d["starts"] else "you would be depth"], 14, UiKit.MUTED))
		h.add_child(left)
		var go := UiKit.primary_button("Ask for a trade here", func():
			var res := PlayerRequest.ask(s, t)
			fns["answer"] = String(res["text"])
			if res["result"] == "granted":
				hub.app.toast("Trade granted: %s" % t.name)
			fns["render"].call(), 16)
		go.disabled = err != ""
		h.add_child(go)
		box.add_child(row)
	var foot := HBoxContainer.new()
	foot.add_child(UiKit.button("Back", func(): hub.go_back(), 16))
	box.add_child(foot)

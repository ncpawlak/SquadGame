class_name StoryPages
extends RefCounted
## The Storylines page (opened from the Home to-do): this season's stories, how far each has got,
## and the meetings played so far. Read-only in phase 1 (no choices yet).


static func page(season: Season) -> Control:
	var v := VBoxContainer.new()
	v.name = "StorylinesPage"
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size.x = 760
	v.add_child(UiKit.display("STORYLINES", 34, Color.WHITE, true))
	var sl := season.storylines
	var shown: Array = sl.active.duplicate()
	shown.append_array(sl.finished_in(season.year))
	if shown.is_empty():
		v.add_child(UiKit.label("No storylines are running right now.", 17, UiKit.MUTED))
		return v
	for st: Dictionary in shown:
		v.add_child(_card(season, st))
	return v


static func _card(season: Season, st: Dictionary) -> Control:
	var sl := season.storylines
	var box := UiKit.panel(UiKit.PANEL, 10)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	var live: bool = st["status"] == Storylines.STATUS_ACTIVE
	var kicker := "ARC  -  %s" % sl.stage_name(st).to_upper() if sl.is_arc(st["kind"]) else sl.stage_name(st).to_upper()
	col.add_child(UiKit.label(kicker, 13, UiKit.GOLD if live else UiKit.MUTED))
	col.add_child(UiKit.display(UiKit.esc(String(st["title"])), 26, Color.WHITE))
	col.add_child(UiKit.rich(UiKit.esc(sl.status_line(st, season)), 16))
	for r: Dictionary in st["results"]:
		var colr := UiKit.hex(UiKit.GOOD if r["won"] else UiKit.BAD)
		col.add_child(UiKit.rich("[color=%s]%s[/color]  Week %d  -  %s" % [colr, "W" if r["won"] else "L", int(r["week"]), UiKit.esc(String(r["score"]))], 15))
	return box

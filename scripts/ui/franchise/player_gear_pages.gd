class_name PlayerGearPages
extends RefCounted
## Player mode (#141): the gear loadout page and the sponsors page. Rules live in Gear and Sponsors; these pages only
## show them and call equip / unequip / accept.

var hub: Control


func _season() -> Season:
	return hub.season


func _label(t: String, size := 16, color := UiKit.TEXT) -> Label:
	var l := UiKit.label(t, size, color)
	return l


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


func _wrap(text: String, size := 15, color := UiKit.MUTED, width := 1000) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


func _bonus_text(bonus: Dictionary) -> String:
	var parts: PackedStringArray = []
	for st in bonus:
		parts.append("+%d %s" % [bonus[st], Stats.LABELS[st]])
	return ", ".join(parts)


# --- loadout ---------------------------------------------------------------------------------------

func loadout_page() -> Control:
	var st := {"open": &""}
	var root := _vbox(10)
	root.custom_minimum_size.x = 1100
	var holder := _vbox(10)
	root.add_child(holder)
	var fns := {}
	fns["render"] = func():
		_clear(holder)
		_fill_loadout(holder, st, fns)
	fns["render"].call()
	return root


func _fill_loadout(box: VBoxContainer, st: Dictionary, fns: Dictionary) -> void:
	var p := _season().player
	box.add_child(_wrap("Gear comes from your sponsor deals. It adds to your ratings, and taking it off takes the bonus away again. It never counts toward Hall of Fame milestones.", 15))
	var base := p.base_ovr()
	var eff := p.best_ovr()
	box.add_child(_label("Base OVR %d   ·   gear %+d   ·   effective OVR %d" % [base, eff - base, eff], 20, Color.WHITE))
	var set_line := Gear.set_text(p.gear_slots)
	if set_line != "":
		box.add_child(_label(set_line, 15, UiKit.GOOD))
	for slot in Gear.SLOTS:
		var row := _hbox(14)
		var name := _label(String(Gear.SLOT_LABELS[slot]), 18, Color.WHITE)
		name.custom_minimum_size.x = 150
		row.add_child(name)
		var cur: Dictionary = p.gear_slots.get(slot, {})
		var desc := _label("%s  (%s)  %s" % [cur["name"], Gear.tier_name(int(cur["tier"])), _bonus_text(cur["bonus"])] if not cur.is_empty() else _empty_reason(p, slot), 15, UiKit.TEXT if not cur.is_empty() else UiKit.MUTED)
		desc.custom_minimum_size.x = 640
		row.add_child(desc)
		if not Gear.available(p, slot).is_empty():
			row.add_child(UiKit.button("Change" if not cur.is_empty() else "Equip", func():
				st["open"] = &"" if st["open"] == slot else slot
				fns["render"].call(), 15))
		if not cur.is_empty():
			row.add_child(UiKit.button("Remove", func():
				Gear.unequip(p, slot)
				fns["render"].call(), 15))
		box.add_child(row)
		if st["open"] == slot:
			for cand in Gear.available(p, slot):
				var trial: Dictionary = p.gear_slots.duplicate()
				trial[slot] = cand
				var after := Gear.preview(p, trial)
				var line := _hbox(12)
				line.add_child(_label("    %s  (%s)  %s   →  OVR %d" % [cand["name"], Gear.tier_name(int(cand["tier"])), _bonus_text(cand["bonus"]), after], 14, UiKit.INFO))
				line.add_child(UiKit.primary_button("Equip", func():
					Gear.equip(p, cand)
					st["open"] = &""
					fns["render"].call(), 14))
				box.add_child(line)
	box.add_child(UiKit.heading("By stat", 18))
	var any := false
	for stat in Stats.ALL:
		var d := int(p.gear_delta.get(stat, 0))
		if d == 0:
			continue
		any = true
		var capped: bool = int(Gear.total_bonus(p.gear_slots).get(stat, 0)) >= Gear.STAT_CAP
		box.add_child(_label("%s:  base %d  +%d gear  =  %d%s" % [Stats.LABELS[stat], p.base_stat(stat), d, int(p.stats[stat]), "   (gear cap %d)" % Gear.STAT_CAP if capped else ""], 15, UiKit.TEXT))
	if not any:
		box.add_child(_label("No gear bonuses yet.", 15, UiKit.MUTED))
	var foot := _hbox(12)
	foot.add_child(UiKit.button("Back", func(): hub.go_back(), 16))
	box.add_child(foot)


func _empty_reason(p: Soldier, slot: StringName) -> String:
	if p.deals.is_empty():
		return "Empty: no sponsor deal yet"
	return "Empty: no deal covers this slot"

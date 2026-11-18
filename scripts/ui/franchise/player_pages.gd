class_name PlayerPages
extends RefCounted
## Player mode phase 4 (#101): the screens that put the player, not the club, in front. The hub swaps these in:
## `header_row` (top bar), `home_left` (Home's left column), `career_tab` (the Team tab, renamed Career), and the
## pages `my_player` (ratings, skill points, training), `game_log` and `contract`.

const COL_W := 437
const STATUS_COLORS := {
	PlayerCoach.WHERE_STARTER: Color("#22c55e"), PlayerCoach.WHERE_BENCH: Color("#f59e0b"),
	PlayerCoach.WHERE_GREEN: Color("#38bdf8"), PlayerCoach.WHERE_INJURED: Color("#ef4444"),
}
const STATUS_NAMES := {
	PlayerCoach.WHERE_STARTER: "STARTING", PlayerCoach.WHERE_BENCH: "BENCH",
	PlayerCoach.WHERE_GREEN: "GREEN TEAM", PlayerCoach.WHERE_INJURED: "INJURED",
}

var hub: Control


func _season() -> Season:
	return hub.season


func _label(t: String, size := 16, color := UiKit.TEXT) -> Label:
	return UiKit.label(t, size, color)


func _vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _wrap(c: Control, margin := 14) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, margin)
	m.add_child(c)
	return m


# --- header ---------------------------------------------------------------------------------

## The top bar's content: portrait, name and a one-line summary of him; `extra` (the score bug) goes on the right.
func header_row(extra: Control) -> HBoxContainer:
	var s := _season()
	var team := s.user_team()
	var p := s.player
	var hb := _hbox(20)
	hb.add_child(Portrait.new(p, 96, UiKit.ACCENT, team))
	var info := _vbox(0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(info)
	info.add_child(UiKit.display(("\"%s\"  %s" % [p.callsign, p.last_name]).to_upper(), 44, Color.WHITE, true))
	var role := Scheme.best_role(p.stats)
	var st := PlayerCoach.status(s)
	info.add_child(_label("%s %s   ·   OVR %d   ·   Age %d   ·   %s" % [
		Archetypes.find(s.player_archetype)["name"], Scheme.ROLE_NAMES[role], p.best_ovr(), p.age, team.name], 16, Color(1, 1, 1, 0.72)))
	info.add_child(_label("%s   ·   %s" % [s.record_text(team), STATUS_NAMES[st["where"]]], 15, STATUS_COLORS[st["where"]]))
	hb.add_child(extra)
	return hb


# --- home -------------------------------------------------------------------------------------

## Home's left column: how you are doing, your last game, your season, and what you can do now.
func home_left() -> Control:
	var s := _season()
	var col := _vbox(10)
	col.name = "TodoColumn"
	col.custom_minimum_size.x = COL_W
	col.add_child(UiKit.heading("You", 22))
	col.add_child(_status_card())
	col.add_child(UiKit.heading("Last Game", 22))
	col.add_child(_last_game_card())
	col.add_child(UiKit.heading("This Season", 22))
	col.add_child(_season_card())
	col.add_child(UiKit.heading("This Week", 22))
	for t in _todos():
		col.add_child(t)
	var i := 0
	for c in col.get_children():
		UiKit.fade_in(c, 0.04 * i, 0.25)
		i += 1
	return col


func _card(accent: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size.x = COL_W
	pc.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, 6, 1, Color(accent, 0.45)))
	return pc


func _status_card() -> Control:
	var s := _season()
	var p := s.player
	var st := PlayerCoach.status(s)
	var color: Color = STATUS_COLORS[st["where"]]
	var card := _card(color)
	var v := _vbox(6)
	card.add_child(_wrap(v))
	var top := _hbox(12)
	top.add_child(UiKit.display(STATUS_NAMES[st["where"]], 26, color, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_label("OVR", 14, UiKit.MUTED))
	top.add_child(UiKit.display(str(p.best_ovr()), 34, UiKit.ovr_color(p.best_ovr()), true))
	v.add_child(top)
	var msg := _label(String(st["text"]), 15, UiKit.TEXT)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size.x = COL_W - 30
	v.add_child(msg)
	if s.player_start_ovr > 0:
		var d := p.best_ovr() - s.player_start_ovr
		v.add_child(_label("%+d OVR since you were drafted (%d)" % [d, s.player_start_ovr], 13, UiKit.GOOD if d > 0 else UiKit.MUTED))
	return card


func _last_game_card() -> Control:
	var s := _season()
	var card := _card(UiKit.MUTED)
	var entries := s.player_log
	if entries.is_empty():
		card.add_child(_wrap(_label("No games yet. Your first one is this week.", 15, UiKit.MUTED)))
		return card
	var e: Dictionary = entries[-1]
	var h := _hbox(16)
	card.add_child(_wrap(h))
	if e["played"]:
		var letter := String(e["letter"])
		h.add_child(UiKit.display(letter, 64, PlayerGrade.letter_color(letter), true))
		var v := _vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_label("%s vs %s" % [s.week_label(int(e["week"])), e["opp"].name], 16, Color.WHITE))
		v.add_child(_label("%s   %s" % ["W" if e["won"] else "L", e["score_line"]], 14, UiKit.GOOD if e["won"] else UiKit.BAD))
		v.add_child(_label("%d K   %d D   %d A   %d dmg%s" % [e["kills"], e["deaths"], e["assists"], e["damage"], "   MVP" if e["mvp"] else ""], 14, UiKit.TEXT))
		h.add_child(v)
	else:
		h.add_child(UiKit.display("DNP", 44, UiKit.MUTED, true))
		var v2 := _vbox(2)
		v2.add_child(_label("%s vs %s" % [s.week_label(int(e["week"])), e["opp"].name], 16, Color.WHITE))
		v2.add_child(_label("Did not play: %s" % e["reason"], 14, UiKit.MUTED))
		h.add_child(v2)
	return card


func _season_card() -> Control:
	var s := _season()
	var card := _card(UiKit.MUTED)
	var sm := PlayerGrade.summary(PlayerGrade.log_for(s))
	var h := _hbox(26)
	card.add_child(_wrap(h))
	for pair in [["GAMES", str(sm["games"])], ["AVG GRADE", sm["letter"]], ["MISSED", str(sm["missed"])]]:
		var c := _vbox(0)
		c.add_child(_label(pair[0], 12, UiKit.MUTED))
		var color := PlayerGrade.letter_color(pair[1]) if pair[0] == "AVG GRADE" and pair[1] != "-" else Color.WHITE
		c.add_child(UiKit.display(pair[1], 34, color, true))
		h.add_child(c)
	return card


func _todos() -> Array:
	var s := _season()
	var p := s.player
	var out: Array = []
	var cost := _cheapest_upgrade(p)
	if cost > 0 and p.skill_points >= cost:
		out.append(_todo("Spend Skill Points", "%d SP ready" % p.skill_points, UiKit.INFO, func(): open_my_player(), true))
	out.append(_todo("Training: %s" % Training.label(p.intensity), "Change this week's intensity", UiKit.TRIM, func(): open_my_player()))
	var notes := s.player_notes
	if not notes.is_empty():
		out.append(_todo("Coach", String(notes[-1]["text"]), UiKit.GOLD, func(): open_game_log()))
	out.append(_todo("Game Log", "Every game and your grade", UiKit.TRIM, func(): open_game_log()))
	return out


func _todo(title: String, sub: String, accent: Color, cb: Callable, urgent := false) -> Button:
	var b := UiKit.tile(title, sub, Vector2(COL_W, 76), Color("#f97316") if urgent else accent, cb)
	return b


## The cheapest group upgrade he could buy (0 if none is possible).
func _cheapest_upgrade(p: Soldier) -> int:
	var best := 0
	for g in Stats.UPGRADABLE_GROUPS:
		if Progression.is_capped(p, g):
			continue
		var c := Progression.upgrade_cost(p, g)
		if best == 0 or c < best:
			best = c
	return best


# --- career tab ---------------------------------------------------------------------------------

## The Team tab in player mode: tiles for you, not the club.
func career_tab(v: VBoxContainer) -> void:
	var s := _season()
	var p := s.player
	v.add_child(UiKit.heading("Your Career", 22))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	flow.add_child(UiKit.tile("My Player", "Ratings, skill points and training\nOVR %d  ·  %d SP" % [p.best_ovr(), p.skill_points], hub.TILE, UiKit.ACCENT, func(): open_my_player()))
	var sm := PlayerGrade.summary(PlayerGrade.log_for(s))
	flow.add_child(UiKit.tile("Game Log", "Grade for every game\n%d played  ·  avg %s" % [sm["games"], sm["letter"]], hub.TILE, UiKit.ACCENT, func(): open_game_log()))
	var cs := "No contract" if p.contract == null else "%s  ·  %d yr" % [Contracts.money(p.contract.salary), p.contract.years]
	flow.add_child(UiKit.tile("Contract", "%s\nGreen Team deal" % cs if p.contract != null and p.contract.green else cs, hub.TILE, UiKit.ACCENT, func(): open_contract()))
	v.add_child(flow)
	var note := _label("The club picks the lineup. Play well, train hard and the coach will move you up.", 15, UiKit.MUTED)
	v.add_child(note)


# --- pages ----------------------------------------------------------------------------------------

func open_my_player() -> void:
	hub.open("My Player", func(): return my_player())


func open_game_log() -> void:
	hub.open("Game Log", func(): return game_log())


func open_contract() -> void:
	hub.open("Contract", func(): return contract())


## Ratings by group with the cap, skill-point spending, and the training intensity.
func my_player() -> Control:
	var s := _season()
	var p := s.player
	var root := _vbox(14)
	root.name = "MyPlayer"
	root.custom_minimum_size.x = 1100
	var head := _hbox(22)
	head.add_child(Portrait.new(p, 130, UiKit.ACCENT, s.user_team()))
	var mid := _vbox(4)
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(_label(p.full_name().to_upper(), 15, UiKit.ACCENT))
	mid.add_child(UiKit.display(("\"%s\"" % p.callsign).to_upper(), 36, Color.WHITE, true))
	var a := Archetypes.find(s.player_archetype)
	mid.add_child(_label("%s %s  ·  Age %d  ·  Level %d" % [a["name"], Scheme.ROLE_NAMES[Scheme.best_role(p.stats)], p.age, p.level], 15, UiKit.MUTED))
	var facts := _hbox(26)
	facts.add_child(_fact("OVR", str(p.best_ovr()), UiKit.ovr_color(p.best_ovr())))
	facts.add_child(_fact("SKILL POINTS", str(p.skill_points), UiKit.INFO))
	facts.add_child(_fact("FATIGUE", "%d" % roundi(p.fatigue), UiKit.GOLD if p.fatigue > 40.0 else UiKit.TEXT))
	mid.add_child(facts)
	head.add_child(mid)
	root.add_child(head)

	var xp: Array = Progression.xp_progress(p)
	root.add_child(_label("XP: %d / %d to the next +%d skill points" % [xp[0], xp[1], Progression.SKILL_POINTS_PER_LEVEL], 15, UiKit.INFO))

	root.add_child(UiKit.heading("Training this week", 20))
	var row := _hbox(10)
	for it in Training.INTENSITIES:
		var info: Dictionary = Training.INTENSITY_INFO[it]
		var b := UiKit.button("%s  ·  %d%% XP" % [info["label"], roundi(float(info["xp"]) * 100.0)], func():
			p.intensity = it
			hub.replace("My Player", func(): return my_player()), 16)
		if p.intensity == it:
			UiKit.style_primary(b)
		row.add_child(b)
	root.add_child(row)
	root.add_child(_label("Harder training earns more XP but tires you out, which costs you in matches.", 13, UiKit.MUTED))

	root.add_child(UiKit.heading("Ratings  (click a group to spend skill points)", 20))
	for g in Stats.GROUP_ORDER:
		root.add_child(_group_row(p, g))
	return root


func _fact(caption: String, value: String, color: Color) -> Control:
	var c := _vbox(0)
	c.add_child(_label(caption, 12, UiKit.MUTED))
	c.add_child(UiKit.display(value, 30, color, true))
	return c


func _group_row(p: Soldier, g: StringName) -> Control:
	var upgradable := Stats.UPGRADABLE_GROUPS.has(g)
	var gr := p.group_rating(g)
	var b := Button.new()
	UiKit.style_button(b, UiKit.PANEL_HI, UiKit.ACCENT, 8, false)
	b.custom_minimum_size.y = 78
	var cost := Progression.upgrade_cost(p, g)
	b.disabled = not Progression.can_upgrade(p, g)
	var box := _vbox(2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_right = -16
	box.offset_top = 6
	box.offset_bottom = -6
	b.add_child(box)
	var line := _hbox(14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label(String(Stats.GROUP_LABELS[g]).to_upper(), 18, Color.WHITE if upgradable else UiKit.MUTED)
	title.custom_minimum_size.x = 150
	line.add_child(title)
	line.add_child(_label(str(gr), 26, UiKit.ovr_color(gr)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(spacer)
	var note := ""
	var note_color := UiKit.MUTED
	if not upgradable:
		note = "AGE / INJURIES ONLY"
	elif Progression.is_capped(p, g):
		note = "CAPPED"
		note_color = UiKit.ACCENT
	elif p.skill_points < cost:
		note = "+1  ·  NEED %d SP" % cost
	else:
		note = "+1  ·  %d SP" % cost
		note_color = UiKit.INFO
	line.add_child(_label(note, 16, note_color))
	box.add_child(line)
	# Each stat with its personal cap: a stat the archetype cannot grow any further shows in red.
	var stats := _hbox(14)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for stat in Stats.GROUPS[g]:
		var cap := p.stat_cap(stat)
		var maxed: bool = int(p.stats[stat]) >= cap and upgradable
		var t := _label("%s %d%s" % [Stats.ABBREV[stat], p.stats[stat], ("/%d" % cap) if p.stat_caps.has(stat) else ""], 13, UiKit.BAD if maxed else UiKit.MUTED)
		stats.add_child(t)
	box.add_child(stats)
	if not b.disabled:
		b.pressed.connect(func():
			var gains := Progression.upgrade_group(p, g)
			if not gains.is_empty():
				var parts: PackedStringArray = []
				for st in gains:
					if gains[st] > 0:
						parts.append("%s +%d" % [Stats.ABBREV[st], gains[st]])
				hub.app.toast("%s %d  (%s)" % [Stats.GROUP_LABELS[g], p.group_rating(g), ", ".join(parts)])
			hub.replace("My Player", func(): return my_player()))
	return b


## Every game of the season: opponent, result, grade and the numbers.
func game_log() -> Control:
	var s := _season()
	var root := _vbox(10)
	root.custom_minimum_size.x = 1100
	var sm := PlayerGrade.summary(PlayerGrade.log_for(s))
	root.add_child(_label("%d played   ·   average grade %s   ·   %d missed" % [sm["games"], sm["letter"], sm["missed"]], 18, UiKit.TEXT))
	var entries := PlayerGrade.log_for(s)
	if entries.is_empty():
		root.add_child(_label("No games yet.", 16, UiKit.MUTED))
		return root
	var rows: Array = []
	var colors := {}
	var n := 0
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if e["played"]:
			rows.append([s.week_label(int(e["week"])), ("vs " if e["home"] else "@ ") + String(e["opp"].abbrev), "%s %s" % ["W" if e["won"] else "L", e["score_line"]],
				String(e["letter"]), "%d / %d / %d" % [e["kills"], e["deaths"], e["assists"]], str(e["damage"]), "MVP" if e["mvp"] else ""])
			colors[n] = {3: PlayerGrade.letter_color(String(e["letter"]))}
		else:
			rows.append([s.week_label(int(e["week"])), ("vs " if e["home"] else "@ ") + String(e["opp"].abbrev), String(e["score_line"]), "DNP", String(e["reason"]), "", ""])
			colors[n] = {3: UiKit.MUTED}
		n += 1
	root.add_child(UiKit.table(["Week", "Opponent", "Result", "Grade", "K / D / A", "Damage", ""], rows, [120, 120, 260, 80, 140, 100, 70], {}, colors))
	return root


func contract() -> Control:
	var s := _season()
	var p := s.player
	var root := _vbox(10)
	root.custom_minimum_size.x = 900
	if p.contract == null:
		root.add_child(_label("You have no contract.", 18, UiKit.MUTED))
		return root
	root.add_child(UiKit.display(Contracts.money(p.contract.salary), 56, Color.WHITE, true))
	root.add_child(_label("%s  ·  %d year%s left" % ["Green Team deal" if p.contract.green else "Main roster deal", p.contract.years, "" if p.contract.years == 1 else "s"], 18, UiKit.TEXT))
	root.add_child(_label("Club: %s" % s.user_team().name, 16, UiKit.MUTED))
	root.add_child(_label("Contract talks and your agent come in a later update. Until then your club re-signs you when your deal ends.", 15, UiKit.MUTED))
	return root

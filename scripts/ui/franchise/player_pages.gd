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
	info.add_child(_label("%s %s   ·   OVR %d   ·   Age %d   ·   %s" % [
		Archetypes.find(s.player_archetype)["name"], Scheme.ROLE_NAMES[role], p.best_ovr(), p.age, team.name], 16, Color(1, 1, 1, 0.72)))
	if PlayerLegacy.retired(s):
		info.add_child(_label("RETIRED  ·  %s" % _verdict_text(s), 15, UiKit.GOLD))
	else:
		var st := PlayerCoach.status(s)
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
	if PlayerLegacy.retired(s):
		return _retired_left(col)
	col.add_child(UiKit.heading("You", 22))
	col.add_child(_status_card())
	col.add_child(UiKit.heading("Last Game", 22))
	col.add_child(_last_game_card())
	col.add_child(UiKit.heading("This Season", 22))
	col.add_child(_season_card())
	col.add_child(UiKit.heading("Hall of Fame", 22))
	col.add_child(_hof_card())
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
	v.add_child(_label("%s   ·   brand %d (%s)   ·   wear %d (%s)" % [_stars_line(p), roundi(p.brand), WeeklyPlan.tier_name(p.brand), roundi(p.wear), Wear.tier_name(p.wear)], 13, UiKit.INFO))
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
	if s.phase == Season.PHASE_OFFSEASON:
		var ready := CapRaise.eligible_groups(s)
		if not ready.is_empty():
			out.append(_todo("Raise a cap", "%d group%s ready: pick one for a higher ceiling" % [ready.size(), "" if ready.size() == 1 else "s"], UiKit.GOLD, func(): open_cap_raise(), true))
		elif p.cap_raise_year == s.year:
			out.append(_todo("Cap raised", "Done for this offseason", UiKit.TRIM, func(): open_cap_raise()))
		else:
			out.append(_todo("Raise a cap", "Fill a group to its ceiling first", UiKit.TRIM, func(): open_cap_raise()))
		if not p.camp_plan_confirmed:
			out.append(_todo("Set your camp plan", "8 points: practice, study, outing, brand", UiKit.GOLD, func(): open_plan(true), true))
		else:
			out.append(_todo("Camp plan", _plan_summary(p.camp_plan, true), UiKit.TRIM, func(): open_plan(true)))
	elif not p.plan_confirmed:
		out.append(_todo("Set your weekly plan", "Your points are wasted until you do", UiKit.GOLD, func(): open_plan(false), true))
	else:
		out.append(_todo("Weekly plan", _plan_summary(p.plan, true), UiKit.TRIM, func(): open_plan(false)))
	var notes := s.player_notes
	if not notes.is_empty():
		out.append(_todo("Coach", String(notes[-1]["text"]), UiKit.GOLD, func(): open_game_log()))
	out.append(_todo("Game Log", "Every game and your grade", UiKit.TRIM, func(): open_game_log()))
	out.append(_todo("Milestones", "%d reached" % s.player_milestones.size(), UiKit.TRIM, func(): open_milestones()))
	if s.phase == Season.PHASE_OFFSEASON:
		out.append(_todo("Retire?", "The season is over: you can hang it up", UiKit.GOLD, func(): open_retire()))
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
	var tr := PlayerLegacy.trajectory(s)
	var pace_text := "on pace" if tr["on_pace"] and tr["has_pace"] else "below pace"
	flow.add_child(UiKit.tile("Hall of Fame Path", "Your score and what drives it\n%d / %d  ·  %s" % [roundi(float(tr["score"])), roundi(float(tr["threshold"])), pace_text], hub.TILE, UiKit.GOLD, func(): open_hof_path()))
	flow.add_child(UiKit.tile("Milestones", "Goals along the way\n%d of %d reached" % [s.player_milestones.size(), PlayerLegacy.MILESTONES.size()], hub.TILE, UiKit.ACCENT, func(): open_milestones()))
	flow.add_child(UiKit.tile("Career Recap", "Every season so far\nand the Hall's verdict", hub.TILE, UiKit.ACCENT, func(): open_recap()))
	if not PlayerLegacy.retired(s):
		flow.add_child(UiKit.tile("Retire", "Hang it up and wait for the Hall's vote\nOffseason only", hub.TILE, UiKit.MUTED, func(): open_retire()))
	v.add_child(flow)
	var note := _label("The club picks the lineup. Play well, train hard and the coach will move you up.", 15, UiKit.MUTED)
	v.add_child(note)


# --- pages ----------------------------------------------------------------------------------------

var plan_ui: PlayerPlanPages


func _plan() -> PlayerPlanPages:
	if plan_ui == null:
		plan_ui = PlayerPlanPages.new()
		plan_ui.hub = hub
	return plan_ui


func open_plan(camp: bool) -> void:
	hub.open("Camp Plan" if camp else "Weekly Plan", func(): return _plan().plan_page(camp))


func open_cap_raise() -> void:
	hub.open("Raise a Cap", func(): return _plan().cap_raise_page())


func open_placement(group: StringName) -> void:
	hub.open("Place Skill Points", func(): return _plan().placement_page(group))


## One line for a plan: "Practice 2, Study 2" (or why it is blank).
func _plan_summary(plan: Dictionary, confirmed: bool) -> String:
	var parts: PackedStringArray = []
	for a in WeeklyPlan.WEEK_ACTIVITIES:
		if WeeklyPlan.level(plan, a) > 0:
			parts.append("%s %d" % [WeeklyPlan.LABELS[a].split(" ")[0], WeeklyPlan.level(plan, a)])
	if parts.is_empty() or not confirmed:
		return "Not set yet"
	return ", ".join(parts) + "  (repeats each week)"


func _stars_line(p: Soldier) -> String:
	if p.dev >= Soldier.DEV_MAX:
		return "%s  ·  top star reached" % p.dev_text()
	return "%s  ·  next star: %d / %d study points" % [p.dev_text(), roundi(p.study_progress), roundi(WeeklyPlan.star_cost(p.dev))]


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

	root.add_child(UiKit.heading("Stars and brand", 20))
	root.add_child(_label(_stars_line(p), 16, UiKit.TEXT))
	root.add_child(_label("Brand %d  ·  %s" % [roundi(p.brand), WeeklyPlan.tier_name(p.brand)], 16, UiKit.TEXT))
	root.add_child(UiKit.heading("Wear", 20))
	root.add_child(_label("Wear %d  ·  %s. It builds with age, games, fatigue and injuries, and spa, camp rehab and the Sports Science Lab take it off. Regression lowers ratings only, never the caps, so skill points win them back." % [roundi(p.wear), Wear.tier_name(p.wear)], 14, UiKit.MUTED))
	for g in Stats.GROUP_ORDER:
		root.add_child(_label("%s:  %s" % [Stats.GROUP_LABELS[g], Wear.risk_text(p.wear, g)], 15, UiKit.TEXT))
	var plan_row := _hbox(12)
	plan_row.add_child(UiKit.primary_button("Weekly plan", func(): open_plan(false), 18))
	root.add_child(plan_row)
	root.add_child(_label(_plan_summary(p.plan, p.plan_confirmed), 14, UiKit.MUTED))

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
	b.disabled = not Progression.can_place(p, g)
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
		b.pressed.connect(func(): open_placement(g))
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
	var bonus := roundi((WeeklyPlan.market_mult(p.brand) - 1.0) * 100.0)
	root.add_child(_label("Brand %d (%s): worth +%d%% on your market value and re-sign price." % [roundi(p.brand), WeeklyPlan.tier_name(p.brand), bonus], 16, UiKit.INFO))
	root.add_child(_label("Market value %s  ·  re-sign ask %s" % [Contracts.money(Contracts.market_value(p)), Contracts.money(Contracts.resign_asking(p, Contracts.preferred_years(p)))], 15, UiKit.MUTED))
	root.add_child(_label("Contract talks and your agent come in a later update. Until then your club re-signs you when your deal ends.", 15, UiKit.MUTED))
	return root


# --- Hall of Fame, milestones, retirement ---------------------------------------------------

func open_hof_path() -> void:
	hub.open("Hall of Fame Path", func(): return hof_path())


func open_milestones() -> void:
	hub.open("Milestones", func(): return milestones())


func open_recap() -> void:
	hub.open("Career Recap", func(): return career_recap())


func open_retire() -> void:
	hub.open("Retire", func(): return retire_page())


func _verdict_text(s: Season) -> String:
	match PlayerLegacy.verdict(s):
		&"inducted": return "Hall of Fame, class of %d" % int(HallOfFame.entry_of(s, s.player)["year"])
		&"not_inducted": return "Not inducted"
		&"waiting": return "Hall of Fame vote in %d" % PlayerLegacy.vote_year(s)
	return "Career in progress"


## A thin progress bar `w` wide: `frac` of it filled in `color`.
func _bar(frac: float, color: Color, w := 260.0, h := 12.0) -> Control:
	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.1)
	back.custom_minimum_size = Vector2(w, h)
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(w * clampf(frac, 0.0, 1.0), h)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	return back


func _hof_card() -> Control:
	var s := _season()
	var t := PlayerLegacy.trajectory(s)
	var card := _card(UiKit.GOLD)
	var v := _vbox(6)
	card.add_child(_wrap(v))
	var top := _hbox(10)
	top.add_child(UiKit.display("%d" % roundi(float(t["score"])), 40, Color.WHITE, true))
	top.add_child(_label("/ %d to be inducted" % roundi(float(t["threshold"])), 14, UiKit.MUTED))
	v.add_child(top)
	v.add_child(_bar(float(t["score"]) / float(t["threshold"]), UiKit.GOLD, COL_W - 40.0))
	if not t["has_pace"]:
		v.add_child(_label("Play %d games to see your pace." % PlayerLegacy.MIN_GAMES_FOR_PACE, 14, UiKit.MUTED))
	else:
		var pace_text := "on a Hall of Fame pace" if t["on_pace"] else "below the bar"
		v.add_child(_label("Pace for a %d-game career: %d  ·  %s" % [PlayerLegacy.PROJECT_MATCHES, roundi(float(t["pace"])), pace_text], 14, UiKit.GOOD if t["on_pace"] else UiKit.TEXT))
	if not t["eligible"]:
		v.add_child(_label("%d / %d games before your career can be voted on" % [t["matches"], HallOfFame.MIN_MATCHES], 13, UiKit.MUTED))
	var recent := s.player_milestones.slice(maxi(0, s.player_milestones.size() - 2))
	if not recent.is_empty():
		v.add_child(_label("Latest: " + ", ".join(recent.map(func(e): return String(e["name"]))), 13, UiKit.INFO))
	return card


## Home's left column once he has retired: the verdict, and what to do next.
func _retired_left(col: VBoxContainer) -> Control:
	var s := _season()
	col.add_child(UiKit.heading("Retired", 22))
	var card := _card(UiKit.GOLD)
	var v := _vbox(8)
	card.add_child(_wrap(v))
	v.add_child(UiKit.display(_verdict_text(s).to_upper(), 28, UiKit.GOLD, true))
	var msg := _label(_retired_message(s), 15, UiKit.TEXT)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size.x = COL_W - 30
	v.add_child(msg)
	col.add_child(card)
	col.add_child(UiKit.heading("Your Career", 22))
	col.add_child(_todo("Career Recap", "Every season and the Hall's verdict", UiKit.TRIM, func(): open_recap()))
	if PlayerLegacy.verdict(s) == &"waiting":
		col.add_child(_todo("Wait for the Hall of Fame vote", "Play the league forward to %d" % PlayerLegacy.vote_year(s), UiKit.GOLD, func(): hub.wait_for_vote(), true))
	col.add_child(_todo("Milestones", "%d reached" % s.player_milestones.size(), UiKit.TRIM, func(): open_milestones()))
	col.add_child(_todo("Back to title", "Start another career from New Franchise", UiKit.MUTED, func(): hub.app.show_title()))
	return col


func _retired_message(s: Season) -> String:
	match PlayerLegacy.verdict(s):
		&"inducted":
			var e := HallOfFame.entry_of(s, s.player)
			return "You were voted into the Hall of Fame with a score of %d. Your career is complete." % roundi(float(e["score"]))
		&"not_inducted":
			var f := PlayerLegacy.final_score(s)
			return "The Hall voted and your score of %d did not reach the bar of %d. Your career is complete." % [roundi(float(f["score"])), roundi(HallOfFame.THRESHOLD)]
	var f2 := PlayerLegacy.final_score(s)
	return "You retired. The Hall waits %d seasons, then votes. Your score today is %d against a bar of %d." % [HallOfFame.WAIT_SEASONS, roundi(float(f2["score"])), roundi(HallOfFame.THRESHOLD)]


## The score's four parts, each with what it measures, and how far you are from the bar.
func hof_path() -> Control:
	var s := _season()
	var t := PlayerLegacy.trajectory(s)
	var root := _vbox(14)
	root.custom_minimum_size.x = 1000
	var top := _hbox(16)
	top.add_child(UiKit.display("%d" % roundi(float(t["score"])), 72, Color.WHITE, true))
	var tv := _vbox(2)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(_label("Hall of Fame score  (bar: %d)" % roundi(float(t["threshold"])), 20, UiKit.TEXT))
	if t["has_pace"]:
		var pace_text := "on a Hall of Fame pace" if t["on_pace"] else "below the bar"
		tv.add_child(_label("Pace for a %d-game career: %d  ·  %s" % [PlayerLegacy.PROJECT_MATCHES, roundi(float(t["pace"])), pace_text], 16, UiKit.GOOD if t["on_pace"] else UiKit.GOLD))
	else:
		tv.add_child(_label("Play %d games to see your pace." % PlayerLegacy.MIN_GAMES_FOR_PACE, 16, UiKit.MUTED))
	var elig := "" if t["eligible"] else ": your career is voted on once you reach %d" % HallOfFame.MIN_MATCHES
	tv.add_child(_label("%d / %d games%s" % [t["matches"], HallOfFame.MIN_MATCHES, elig], 14, UiKit.MUTED))
	top.add_child(tv)
	root.add_child(top)
	root.add_child(_bar(float(t["score"]) / float(t["threshold"]), UiKit.GOLD, 600.0, 16.0))
	var parts := [
		["Production", "production", HallOfFame.PRODUCTION_POINTS, "Career kills, assists, damage, MVPs, clutches and kills per death, ranked against every career in the league."],
		["Awards", "awards", HallOfFame.AWARDS_CAP, "Season MVPs (%d each), other awards (%d) and All-League picks (%d)." % [roundi(HallOfFame.MVP_POINTS), roundi(HallOfFame.AWARD_POINTS), roundi(HallOfFame.ALL_LEAGUE_POINTS)]],
		["Titles", "titles", HallOfFame.TITLES_CAP, "%d points for each season you play for the champion (at least %d games)." % [roundi(HallOfFame.TITLE_POINTS), HallOfFame.MIN_TITLE_MATCHES]],
		["Peak", "peak", HallOfFame.PEAK_POINTS, "Your best single season of kills, ranked against every season in the league."],
	]
	for part in parts:
		var row := _hbox(16)
		var name := _label(String(part[0]), 20, UiKit.GOLD)
		name.custom_minimum_size.x = 130
		row.add_child(name)
		row.add_child(_bar(float(t[part[1]]) / float(part[2]), UiKit.ACCENT, 300.0, 14.0))
		var val := _label("%d / %d" % [roundi(float(t[part[1]])), roundi(float(part[2]))], 18, Color.WHITE)
		val.custom_minimum_size.x = 90
		row.add_child(val)
		var d := _label(String(part[3]), 14, UiKit.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 420
		row.add_child(d)
		root.add_child(row)
	root.add_child(UiKit.heading("Honors", 20))
	var honors: Array = t["honors"]
	if honors.is_empty():
		root.add_child(_label("None yet.", 15, UiKit.MUTED))
	else:
		root.add_child(_label(", ".join(honors), 15, UiKit.TEXT))
	root.add_child(_label("When you retire the Hall waits %d seasons, then votes. At most %d are inducted a year, and you need %d." % [HallOfFame.WAIT_SEASONS, HallOfFame.CLASS_MAX, roundi(HallOfFame.THRESHOLD)], 14, UiKit.MUTED))
	return root


func milestones() -> Control:
	var s := _season()
	var root := _vbox(8)
	root.custom_minimum_size.x = 900
	root.add_child(_label("%d of %d reached" % [s.player_milestones.size(), PlayerLegacy.MILESTONES.size()], 18, UiKit.TEXT))
	root.add_child(UiKit.heading("Reached", 20))
	var any := false
	for m in PlayerLegacy.MILESTONES:
		var e := PlayerLegacy.achieved(s, m["id"])
		if e.is_empty():
			continue
		any = true
		var row := _hbox(14)
		var nm := _label("[x]  " + String(m["name"]), 18, UiKit.GOOD)
		nm.custom_minimum_size.x = 260
		row.add_child(nm)
		row.add_child(_label("%s   ·   %d, %s" % [m["desc"], e["year"], s.week_label(int(e["week"]))], 14, UiKit.MUTED))
		root.add_child(row)
	if not any:
		root.add_child(_label("None yet. Your first game is the first one.", 15, UiKit.MUTED))
	root.add_child(UiKit.heading("Still to come", 20))
	for m in PlayerLegacy.MILESTONES:
		if not PlayerLegacy.achieved(s, m["id"]).is_empty():
			continue
		var row2 := _hbox(14)
		var nm2 := _label(String(m["name"]), 18, Color.WHITE)
		nm2.custom_minimum_size.x = 260
		row2.add_child(nm2)
		var pr := _label(PlayerLegacy.progress_text(s, m), 14, UiKit.INFO)
		pr.custom_minimum_size.x = 120
		row2.add_child(pr)
		row2.add_child(_label(String(m["desc"]), 14, UiKit.MUTED))
		root.add_child(row2)
	return root


func career_recap() -> Control:
	var s := _season()
	var r := PlayerLegacy.recap(s)
	var p := s.player
	var root := _vbox(12)
	root.custom_minimum_size.x = 1000
	root.add_child(UiKit.display(("\"%s\"  %s" % [p.callsign, p.full_name()]).to_upper(), 40, Color.WHITE, true))
	root.add_child(_label("%s %s   ·   %s" % [Archetypes.find(s.player_archetype)["name"], Scheme.ROLE_NAMES[Scheme.best_role(p.stats)], _verdict_text(s)], 18, UiKit.GOLD))
	var rows: Array = []
	var colors := {}
	var n := 0
	for row in r["seasons"]:
		rows.append([str(row["year"]), String(row["team"]), str(row["age"]), str(row["games"]), String(row["letter"]), "%d / %d / %d" % [row["kills"], row["deaths"], row["assists"]], str(row["damage"])])
		if row["letter"] != "-":
			colors[n] = {4: PlayerGrade.letter_color(String(row["letter"]))}
		n += 1
	if rows.is_empty():
		root.add_child(_label("No seasons played yet.", 16, UiKit.MUTED))
	else:
		root.add_child(UiKit.table(["Year", "Club", "Age", "Games", "Grade", "K / D / A", "Damage"], rows, [90, 90, 70, 90, 90, 160, 120], {}, colors))
	var tot: Dictionary = r["totals"]
	root.add_child(_label("Career: %d games   ·   %d kills   ·   %d deaths   ·   %d assists   ·   %d MVPs" % [tot["matches"], tot["kills"], tot["deaths"], tot["assists"], tot.get("mvps", 0)], 16, UiKit.TEXT))
	root.add_child(_label("Honors: %s" % (", ".join(r["honors"]) if not r["honors"].is_empty() else "none"), 15, UiKit.MUTED))
	var f: Dictionary = r["final"]
	root.add_child(UiKit.heading("Hall of Fame", 20))
	root.add_child(_label("Score %d of %d needed   (production %d · awards %d · titles %d · peak %d)" % [roundi(float(f["score"])), roundi(float(r["threshold"])), roundi(float(f["production"])), roundi(float(f["awards"])), roundi(float(f["titles"])), roundi(float(f["peak"]))], 16, UiKit.TEXT))
	if PlayerLegacy.retired(s):
		var m := _label(_retired_message(s), 16, UiKit.GOLD)
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.custom_minimum_size.x = 900
		root.add_child(m)
		if PlayerLegacy.verdict(s) == &"waiting":
			root.add_child(UiKit.primary_button("Wait for the Hall of Fame vote", func(): hub.wait_for_vote(), 20))
	return root


func retire_page() -> Control:
	var s := _season()
	var root := _vbox(12)
	root.custom_minimum_size.x = 800
	var err := PlayerLegacy.retire_error(s)
	var t := PlayerLegacy.trajectory(s)
	root.add_child(_label("Your Hall of Fame score is %d against a bar of %d." % [roundi(float(t["score"])), roundi(float(t["threshold"]))], 20, UiKit.TEXT))
	var body := _label("Retiring ends your career. You leave your club, and the Hall waits %d seasons before it votes. Your career can only be voted on if you have played %d games (you have played %d)." % [HallOfFame.WAIT_SEASONS, HallOfFame.MIN_MATCHES, t["matches"]], 16, UiKit.MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 760
	root.add_child(body)
	if err != "":
		root.add_child(_label(err, 16, UiKit.BAD))
		return root
	root.add_child(UiKit.primary_button("Retire from the game", func():
		var e := PlayerLegacy.retire(s)
		if e != "":
			hub.app.toast(e)
			return
		hub.page_stack.clear()
		hub._build_header()
		hub._build_tabs()
		hub.open("Career Recap", func(): return career_recap()), 22))
	return root

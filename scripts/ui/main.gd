extends Control
## Milestone 1 debug UI: league generation, rosters/lineups, player cards with skill-point
## spending, weekly training focus, single-match sim with play-by-play/box score, and batch sims.

var league: League
var rng := RandomNumberGenerator.new()
## soldier_id -> focus stat for the user's team (max Training.MAX_FOCUS_PLAYERS entries)
var training_focus := {}
var selected: Soldier
var week := 1
var show_caps := false

# Widgets
var league_seed_spin: SpinBox
var match_seed_spin: SpinBox
var team_a_pick: OptionButton
var team_b_pick: OptionButton
var roster_team_pick: OptionButton
var roster_tree: Tree
var card_box: VBoxContainer
var log_text: RichTextLabel
var box_tree: Tree
var progress_text: RichTextLabel
var batch_text: RichTextLabel
var right_tabs: TabContainer
var status_label: Label


func _ready() -> void:
	rng.randomize()
	_build_ui()
	_new_league()


# --- layout ----------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#11151c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	margin.add_child(root)

	# Top bar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	bar.add_child(_label("League seed"))
	league_seed_spin = _spin(1, 999999, 42)
	bar.add_child(league_seed_spin)
	bar.add_child(_button("New League", _new_league))
	bar.add_child(VSeparator.new())
	team_a_pick = OptionButton.new()
	team_b_pick = OptionButton.new()
	bar.add_child(team_a_pick)
	bar.add_child(_label("vs"))
	bar.add_child(team_b_pick)
	bar.add_child(_label("Match seed"))
	match_seed_spin = _spin(1, 999999, 1)
	bar.add_child(match_seed_spin)
	bar.add_child(_button("Random", func(): match_seed_spin.value = rng.randi_range(1, 999999)))
	bar.add_child(_button("Sim Match", _sim_match))
	bar.add_child(VSeparator.new())
	bar.add_child(_button("Train Week", _train_week))
	bar.add_child(_button("Batch x200", _batch_sim))

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	# Left: roster + player card
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	split.add_child(left)
	var roster_bar := HBoxContainer.new()
	left.add_child(roster_bar)
	roster_bar.add_child(_label("Roster:"))
	roster_team_pick = OptionButton.new()
	roster_team_pick.item_selected.connect(func(_i): _refresh_roster())
	roster_bar.add_child(roster_team_pick)
	roster_bar.add_child(_button("Auto Lineup", func():
		_roster_team().auto_lineup()
		_refresh_roster()))
	var caps_check := CheckBox.new()
	caps_check.text = "Show hidden caps (debug)"
	caps_check.toggled.connect(func(on):
		show_caps = on
		_refresh_card())
	roster_bar.add_child(caps_check)
	status_label = _label("")
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	roster_bar.add_child(status_label)

	roster_tree = Tree.new()
	roster_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_tree.hide_root = true
	roster_tree.column_titles_visible = true
	roster_tree.select_mode = Tree.SELECT_ROW
	var cols: Array[String] = ["Slot", "Name", "Age", "Pos OVR", "Best", "Lv", "SP"]
	for s in Stats.ALL:
		cols.append(Stats.ABBREV[s])
	roster_tree.columns = cols.size()
	for i in cols.size():
		roster_tree.set_column_title(i, cols[i])
		roster_tree.set_column_expand(i, i == 1)
		if i != 1:
			roster_tree.set_column_custom_minimum_width(i, 40)
	roster_tree.set_column_custom_minimum_width(0, 90)
	roster_tree.set_column_custom_minimum_width(1, 150)
	roster_tree.item_selected.connect(_on_roster_selected)
	left.add_child(roster_tree)

	var card_scroll := ScrollContainer.new()
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(card_scroll)
	card_box = VBoxContainer.new()
	card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.add_child(card_box)

	# Right: match output
	right_tabs = TabContainer.new()
	right_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_tabs.custom_minimum_size.x = 700
	split.add_child(right_tabs)
	log_text = _rich("Play-by-play")
	right_tabs.add_child(log_text)
	box_tree = Tree.new()
	box_tree.name = "Box Score"
	box_tree.hide_root = true
	box_tree.column_titles_visible = true
	var bcols := ["Slot", "Name", "K", "D", "A", "Dmg", "Shots", "Hit%", "HS", "SV", "CL"]
	var bwidths := [58, 130, 30, 30, 30, 44, 48, 48, 30, 30, 30]
	box_tree.columns = bcols.size()
	for i in bcols.size():
		box_tree.set_column_title(i, bcols[i])
		box_tree.set_column_expand(i, false)
		box_tree.set_column_custom_minimum_width(i, bwidths[i])
	right_tabs.add_child(box_tree)
	progress_text = _rich("Progression")
	right_tabs.add_child(progress_text)
	batch_text = _rich("Batch Sim")
	right_tabs.add_child(batch_text)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.custom_minimum_size.x = 100
	return s


func _rich(tab_name: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.name = tab_name
	r.bbcode_enabled = true
	r.selection_enabled = true
	r.scroll_following = false
	return r


# --- data helpers ----------------------------------------------------------

func _user_team() -> Team:
	return league.teams[0]


func _roster_team() -> Team:
	return league.teams[maxi(roster_team_pick.selected, 0)]


func _team_for(soldier: Soldier) -> Team:
	for t in league.teams:
		if t.roster.has(soldier):
			return t
	return null


static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


func _colorize(line: String) -> String:
	var out := _esc(line)
	for t in league.teams:
		out = out.replace("[lb]%s]" % t.abbrev, "[color=#%s][b][lb]%s][/b][/color]" % [t.color.to_html(false), t.abbrev])
	if line.begins_with("---") or line.begins_with("==="):
		out = "[b]%s[/b]" % out
	elif line.contains("CLUTCH") or line.contains("HEADSHOT"):
		out = "[color=#facc15]%s[/color]" % out
	return out


func _ovr_color(v: int) -> Color:
	if v >= 80:
		return Color("#22c55e")
	if v >= 70:
		return Color("#84cc16")
	if v >= 60:
		return Color("#eab308")
	if v >= 50:
		return Color("#f97316")
	return Color("#ef4444")


# --- actions ---------------------------------------------------------------

func _new_league() -> void:
	league = League.generate(int(league_seed_spin.value))
	training_focus.clear()
	selected = null
	week = 1
	for pick in [team_a_pick, team_b_pick, roster_team_pick]:
		pick.clear()
		for t in league.teams:
			pick.add_item("%s (%d)%s" % [t.name, t.team_ovr(), " (you)" if t.user_controlled else ""])
	team_a_pick.select(0)
	team_b_pick.select(1)
	roster_team_pick.select(0)
	log_text.text = "League generated. Your team: [b]%s[/b]. Pick two teams and press Sim Match." % _user_team().name
	progress_text.text = ""
	box_tree.clear()
	_refresh_roster()
	_update_status()


func _update_status() -> void:
	status_label.text = "Week %d  |  Your team: %s  |  Training focus: %d/%d" % [
		week, _user_team().name, training_focus.size(), Training.MAX_FOCUS_PLAYERS]


func _refresh_team_names() -> void:
	for pick in [team_a_pick, team_b_pick, roster_team_pick]:
		for i in league.teams.size():
			var t := league.teams[i]
			pick.set_item_text(i, "%s (%d)%s" % [t.name, t.team_ovr(), " (you)" if t.user_controlled else ""])


func _sim_match() -> void:
	var a := league.teams[team_a_pick.selected]
	var b := league.teams[team_b_pick.selected]
	if a == b:
		log_text.text = "[color=#ef4444]Pick two different teams.[/color]"
		return
	var seed_value := int(match_seed_spin.value)
	var result := MatchEngine.simulate(a, b, seed_value)
	var reports := Progression.award_match_xp(result, rng)
	for t in [a, b]:
		Progression.auto_spend_team(t)

	var lines: Array[String] = []
	for e in result.events:
		lines.append(_colorize(e))
	log_text.text = "\n".join(lines)
	_fill_box_score(result)
	_show_progress("Match: %s (seed %d)" % [result.score_line(), seed_value], reports)
	right_tabs.current_tab = 0
	match_seed_spin.value = seed_value + 1
	_refresh_team_names()
	_refresh_roster()


func _fill_box_score(result: MatchResult) -> void:
	box_tree.clear()
	var root := box_tree.create_item()
	for ti in 2:
		var team := result.teams[ti]
		var header := box_tree.create_item(root)
		header.set_text(0, "%s %d" % [team.abbrev, result.score[ti]])
		header.set_text(1, team.name + ("  (WIN)" if ti == result.winner_index else ""))
		header.set_custom_color(0, team.color)
		header.set_custom_color(1, team.color)
		for slot_id in team.scheme.slot_ids():
			var s: Soldier = team.lineup[slot_id]
			var line := result.box_for(s)
			var it := box_tree.create_item(root)
			var hit_pct: float = 100.0 * line["hits"] / maxf(1.0, line["shots"])
			var vals := [String(slot_id), s.short_name() + (" MVP" if s.id == result.mvp_id else ""),
				line["kills"], line["deaths"], line["assists"], roundi(line["damage"]), line["shots"],
				"%.0f%%" % hit_pct, line["headshots"], line["rounds_survived"], line["clutches"]]
			for i in vals.size():
				it.set_text(i, str(vals[i]))


func _show_progress(title: String, reports: Dictionary) -> void:
	var lines: Array[String] = ["[b]%s[/b]" % _esc(title)]
	for t in league.teams:
		var team_lines: Array[String] = []
		for s in t.roster:
			if not reports.has(s.id):
				continue
			var r: Dictionary = reports[s.id]
			var txt := "  %s (age %d): +%d XP" % [s.full_name(), s.age, r["xp"]]
			if r.get("focus", false):
				txt += " [color=#38bdf8](focus)[/color]"
			if r["levels"] > 0:
				txt += "  [color=#22c55e]LEVEL UP → %d (+%d SP)[/color]" % [s.level, r["points"]]
			for b in r["breakthroughs"]:
				txt += "  [color=#facc15]Breakthrough: +1 %s[/color]" % Stats.LABELS[b]
			team_lines.append(txt)
		if not team_lines.is_empty():
			lines.append("[color=#%s][b]%s[/b][/color]%s" % [t.color.to_html(false), _esc(t.name),
				"" if not t.user_controlled else "  (your team — spend SP on player cards)"])
			lines.append_array(team_lines)
	progress_text.text = "\n".join(lines)


func _train_week() -> void:
	var all_reports := {}
	for t in league.teams:
		var focus := training_focus if t.user_controlled else _ai_training_focus(t)
		all_reports.merge(Training.run_week(t, focus, rng))
		Progression.auto_spend_team(t)
	_show_progress("Training — week %d" % week, all_reports)
	week += 1
	right_tabs.current_tab = 2
	_refresh_team_names()
	_refresh_roster()
	_update_status()


## AI picks its youngest high-potential players as training focus.
func _ai_training_focus(t: Team) -> Dictionary:
	var sorted := t.roster.duplicate()
	sorted.sort_custom(func(x: Soldier, y: Soldier): return x.potential_ovr() - x.best_ovr() > y.potential_ovr() - y.best_ovr())
	var focus := {}
	for i in mini(Training.MAX_FOCUS_PLAYERS, sorted.size()):
		focus[sorted[i].id] = &""
	return focus


func _batch_sim() -> void:
	var a := league.teams[team_a_pick.selected]
	var b := league.teams[team_b_pick.selected]
	if a == b:
		return
	var n := 200
	var wins := 0
	var scores := {}
	var rounds := 0
	var duration := 0.0
	var bands := {"short": 0, "medium": 0, "long": 0}
	var base := int(match_seed_spin.value)
	for i in n:
		var r := MatchEngine.simulate(a, b, base + i)
		if r.winner_index == 0:
			wins += 1
		var key := "%d-%d" % [r.score[0], r.score[1]]
		scores[key] = scores.get(key, 0) + 1
		for rd in r.rounds:
			rounds += 1
			duration += rd["duration_s"]
		for e in r.events:
			for band in bands:
				if e.contains("(%s)" % band):
					bands[band] += 1
	var lines: Array[String] = [
		"[b]%s vs %s — %d matches (seeds %d..%d), no XP awarded[/b]" % [_esc(a.name), _esc(b.name), n, base, base + n - 1],
		"Team OVR: %d vs %d" % [a.team_ovr(), b.team_ovr()],
		"%s win rate: [b]%.1f%%[/b]" % [_esc(a.abbrev), 100.0 * wins / n],
		"Avg round length: %.1fs" % (duration / rounds),
		"Kills by range: short %d / medium %d / long %d" % [bands["short"], bands["medium"], bands["long"]],
		"", "Scorelines:",
	]
	var keys := scores.keys()
	keys.sort_custom(func(x, y): return scores[x] > scores[y])
	for k in keys:
		lines.append("  %s  ×%d" % [k, scores[k]])
	batch_text.text = "\n".join(lines)
	right_tabs.current_tab = 3


# --- roster & player card --------------------------------------------------

func _refresh_roster() -> void:
	roster_tree.clear()
	var team := _roster_team()
	var root := roster_tree.create_item()
	var ordered: Array[Soldier] = team.starters()
	ordered.append_array(team.bench())
	for s in ordered:
		var it := roster_tree.create_item(root)
		var slot := team.slot_of(s)
		var pos_ovr := team.ovr_in_slot(s, slot) if slot != &"" else -1
		it.set_text(0, team.scheme.label_for_slot(slot) if slot != &"" else "Bench")
		it.set_text(1, s.full_name() + ("  (focus)" if training_focus.has(s.id) and team.user_controlled else ""))
		it.set_text(2, str(s.age))
		it.set_text(3, str(pos_ovr) if pos_ovr >= 0 else "-")
		if pos_ovr >= 0:
			it.set_custom_color(3, _ovr_color(pos_ovr))
		it.set_text(4, "%d %s" % [s.best_ovr(), Scheme.ROLE_NAMES[Scheme.best_role(s.stats)].left(3)])
		it.set_text(5, str(s.level))
		it.set_text(6, str(s.skill_points))
		for i in Stats.ALL.size():
			var v: int = s.stats[Stats.ALL[i]]
			it.set_text(7 + i, str(v))
			it.set_custom_color(7 + i, _ovr_color(v))
		it.set_metadata(0, s.id)
		if selected == s:
			it.select(0)
	if selected == null or _team_for(selected) != team:
		selected = ordered[0] if not ordered.is_empty() else null
	_refresh_card()


func _on_roster_selected() -> void:
	var it := roster_tree.get_selected()
	if it == null:
		return
	var id: int = it.get_metadata(0)
	for s in _roster_team().roster:
		if s.id == id:
			selected = s
	_refresh_card()


func _refresh_card() -> void:
	for c in card_box.get_children():
		c.queue_free()
	if selected == null:
		return
	var s := selected
	var team := _team_for(s)
	var editable := team.user_controlled

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	var slot := team.slot_of(s)
	title.text = "[font_size=20][b]%s[/b][/font_size]  age %d  •  %s  •  %s\nLevel %d  •  XP %d / %d  •  [color=#38bdf8]%d skill points[/color]  •  Best OVR %d  •  Potential %s" % [
		_esc(s.full_name()), s.age, _esc(team.name),
		team.scheme.label_for_slot(slot) if slot != &"" else "Bench",
		s.level, s.xp, Progression.xp_to_next(s.level), s.skill_points, s.best_ovr(), _potential_grade(s)]
	card_box.add_child(title)

	var ovr_line := HBoxContainer.new()
	for role in Scheme.ROLE_NAMES:
		ovr_line.add_child(_label("%s OVR: %d   " % [Scheme.ROLE_NAMES[role], s.ovr_at_role(role)]))
	card_box.add_child(ovr_line)

	if editable:
		var actions := HBoxContainer.new()
		actions.add_child(_label("Move to:"))
		var slot_pick := OptionButton.new()
		for sid in team.scheme.slot_ids():
			var occupant: Soldier = team.lineup.get(sid)
			slot_pick.add_item("%s (%d) — now %s" % [team.scheme.label_for_slot(sid), team.ovr_in_slot(s, sid),
				occupant.short_name() if occupant else "empty"])
		actions.add_child(slot_pick)
		actions.add_child(_button("Assign", func():
			team.assign(team.scheme.slot_ids()[slot_pick.selected], s)
			_refresh_team_names()
			_refresh_roster()))
		actions.add_child(_button("Auto-spend SP", func():
			Progression.auto_spend(s, team.scheme.role_for_slot(slot) if slot != &"" else Scheme.best_role(s.stats))
			_refresh_roster()))
		card_box.add_child(actions)

		var focus_row := HBoxContainer.new()
		var focus_check := CheckBox.new()
		focus_check.text = "Training focus"
		focus_check.button_pressed = training_focus.has(s.id)
		focus_check.disabled = not training_focus.has(s.id) and training_focus.size() >= Training.MAX_FOCUS_PLAYERS
		var focus_stat := OptionButton.new()
		focus_stat.add_item("(any stat)")
		for st in Stats.ALL:
			focus_stat.add_item(Stats.LABELS[st])
		if training_focus.has(s.id) and training_focus[s.id] != &"":
			focus_stat.select(Stats.ALL.find(training_focus[s.id]) + 1)
		var apply_focus := func():
			if focus_check.button_pressed:
				training_focus[s.id] = &"" if focus_stat.selected == 0 else Stats.ALL[focus_stat.selected - 1]
			else:
				training_focus.erase(s.id)
			_update_status()
			_refresh_roster()
		focus_check.toggled.connect(func(_on): apply_focus.call())
		focus_stat.item_selected.connect(func(_i):
			if focus_check.button_pressed:
				apply_focus.call())
		focus_row.add_child(focus_check)
		focus_row.add_child(focus_stat)
		focus_row.add_child(_label("(max %d players; focus = %.1f× XP)" % [Training.MAX_FOCUS_PLAYERS, Training.FOCUS_MULTIPLIER]))
		card_box.add_child(focus_row)
	else:
		card_box.add_child(_label("AI-controlled team: skill points are auto-spent after each match/training."))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	card_box.add_child(grid)
	var role := team.scheme.role_for_slot(slot) if slot != &"" else Scheme.best_role(s.stats)
	var weights: Dictionary = Scheme.ROLE_WEIGHTS[role]
	for st in Stats.ALL:
		var name_l := _label(Stats.LABELS[st] + (" •" if weights.has(st) else ""))
		name_l.custom_minimum_size.x = 170
		grid.add_child(name_l)
		var val := _label(str(s.stats[st]) + ("  / cap %d" % s.caps[st] if show_caps else ""))
		val.add_theme_color_override("font_color", _ovr_color(s.stats[st]))
		val.custom_minimum_size.x = 110
		grid.add_child(val)
		var cost := Progression.point_cost(s.stats[st])
		var plus := _button("+1  (%d SP)" % cost, func():
			Progression.spend_point(s, st)
			_refresh_roster())
		plus.disabled = not editable or not Progression.can_raise(s, st)
		if s.headroom(st) <= 0:
			plus.text = "MAXED"
		grid.add_child(plus)
		grid.add_child(_label("usage %.0f" % s.usage[st]))
	card_box.add_child(_label("• = stat counts toward OVR at current position. Career: %d matches, %d K / %d D / %d A" % [
		s.career["matches"], s.career["kills"], s.career["deaths"], s.career["assists"]]))


## Letter grade for remaining growth room — caps themselves stay hidden like CFB.
func _potential_grade(s: Soldier) -> String:
	var gap := s.potential_ovr() - s.best_ovr()
	if gap >= 12:
		return "A"
	if gap >= 8:
		return "B"
	if gap >= 4:
		return "C"
	if gap >= 2:
		return "D"
	return "F"

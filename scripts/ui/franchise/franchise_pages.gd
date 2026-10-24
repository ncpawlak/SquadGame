class_name FranchisePages
extends RefCounted
## Detail page builders for the franchise hub. Each returns a Control that the hub wraps in a
## titled, scrollable frame. Pages read Season state fresh every time they are built.

var hub: Control  # hub.gd; a Node, so no RefCounted cycle


func _season() -> Season:
	return hub.season


func _vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _section(text: String) -> Label:
	return UiKit.label(text, 15, UiKit.MUTED)


func _row(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


# --- standings / schedule / scores ------------------------------------------------

func standings() -> Control:
	var s := _season()
	var v := _vbox()
	v.add_child(_section("%s  -  %d SEASON  -  top %d qualify for the playoffs" % [Season.DIVISION_NAME.to_upper(), s.year, Season.PLAYOFF_TEAMS]))
	var rows: Array = []
	var hl := {}
	var colors := {}
	var table_rows: Array = s.standings()
	for i in table_rows.size():
		var r: StandingRow = table_rows[i]
		rows.append([r.rank, r.team.name, r.wins, r.losses, "%.3f" % r.win_pct(), r.rounds_won, r.rounds_lost,
			("%+d" % r.round_diff()), r.streak, r.last5 if r.last5 != "" else "-", r.team.team_ovr()])
		if r.team.user_controlled:
			hl[i] = r.team.color.darkened(0.6)
		colors[i] = {0: Color.WHITE if r.rank <= Season.PLAYOFF_TEAMS else UiKit.MUTED, 7: UiKit.GOOD if r.round_diff() > 0 else (UiKit.BAD if r.round_diff() < 0 else UiKit.TEXT)}
	v.add_child(UiKit.table(["#", "TEAM", "W", "L", "PCT", "RW", "RL", "DIFF", "STRK", "LAST 5", "OVR"], rows,
		[30, 260, 50, 50, 70, 50, 50, 60, 60, 90, 50], hl, colors))
	v.add_child(UiKit.label("Tiebreakers: head-to-head, then round differential, then rounds won.", 13, UiKit.MUTED))
	return v


func schedule() -> Control:
	var s := _season()
	var team := s.user_team()
	var v := _vbox()
	v.add_child(_section("%s  -  %d SCHEDULE" % [team.name.to_upper(), s.year]))
	var rows: Array = []
	var colors := {}
	var hl := {}
	var targets: Array = []
	for w in range(1, s.total_weeks() + 1):
		var m: ScheduledMatch = null
		for x in s.matches_for_week(w):
			if x.involves(team):
				m = x
		if m == null:
			if w <= Season.REGULAR_WEEKS and s.bye_team(w) == team:
				rows.append([s.week_label(w), "BYE", "", "", ""])
				colors[rows.size() - 1] = {1: UiKit.MUTED}
				targets.append(null)
			continue
		var opp := m.opponent_of(team)
		var res := "-"
		if m.is_played():
			res = "%s %d-%d" % ["W" if m.winner() == team else "L", m.rounds_for(team), m.rounds_for(opp)]
			colors[rows.size()] = {4: UiKit.GOOD if m.winner() == team else UiKit.BAD}
		rows.append([s.week_label(w), ("vs " if m.home == team else "@ ") + opp.name, s.record_text(opp), opp.team_ovr(), res])
		if w == s.week:
			hl[rows.size() - 1] = UiKit.ACCENT.darkened(0.7)
		targets.append(m)
	v.add_child(UiKit.table(["WEEK", "OPPONENT", "OPP REC", "OPP OVR", "RESULT"], rows, [130, 300, 90, 90, 110], hl, colors,
		func(i: int):
			var m: ScheduledMatch = targets[i]
			if m == null:
				return
			if m.is_played():
				hub.open("Match Recap", func(): return recap(m))
			else:
				hub.open("Match Preview", func(): return preview(m))))
	return v


func scores(w: int) -> Control:
	var s := _season()
	w = clampi(w, 1, s.total_weeks())
	var v := _vbox()
	var nav := _row()
	var prev := UiKit.button("< Prev week", func(): hub.replace("Scores & Schedule", func(): return scores(w - 1)))
	prev.disabled = w <= 1
	nav.add_child(prev)
	var lbl := UiKit.label(s.week_label(w).to_upper(), 24, Color.WHITE)
	lbl.custom_minimum_size.x = 220
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(lbl)
	var next := UiKit.button("Next week >", func(): hub.replace("Scores & Schedule", func(): return scores(w + 1)))
	next.disabled = w >= s.total_weeks()
	nav.add_child(next)
	v.add_child(nav)

	var matches: Array = s.matches_for_week(w)
	if matches.is_empty():
		v.add_child(UiKit.label("Matchups not set yet - decided by earlier playoff results.", 16, UiKit.MUTED))
	for m in matches:
		v.add_child(_score_card(m))
	if w <= Season.REGULAR_WEEKS and s.bye_team(w):
		v.add_child(UiKit.label("BYE: %s" % s.bye_team(w).name, 15, UiKit.MUTED))
	return v


func _score_card(m: ScheduledMatch) -> Button:
	var s := _season()
	var body := ""
	for t in [m.away, m.home]:
		var won: bool = m.is_played() and m.winner() == t
		body += "[color=%s]%s  %s[/color]   [color=%s]%s[/color]\n" % [
			"white" if (won or not m.is_played()) else "#8b97ab", t.abbrev, UiKit.esc(t.name), UiKit.hex(UiKit.ACCENT),
			str(m.rounds_for(t)) if m.is_played() else s.record_text(t)]
	if m.is_played():
		var mvp := _soldier(m.result.mvp_id)
		body += "Final  -  MVP %s" % (UiKit.esc(mvp.short_name()) if mvp else "-")
	else:
		body += "Upcoming  -  %s" % m.stage
	var accent := m.home.color if not m.is_played() else m.winner().color
	return UiKit.tile("%s @ %s" % [m.away.abbrev, m.home.abbrev], body, Vector2(560, 150), accent,
		func():
			if m.is_played():
				hub.open("Match Recap", func(): return recap(m))
			else:
				hub.open("Match Preview", func(): return preview(m)))


func week_results(label: String, played: Array) -> Control:
	var s := _season()
	var v := _vbox()
	var team := s.user_team()
	var mine: ScheduledMatch = null
	for m in played:
		if m.involves(team):
			mine = m
	if mine:
		var won := mine.winner() == team
		var banner := UiKit.rich("[font_size=40][color=%s]%s[/color][/font_size]   [font_size=28]%s %s  %s[/font_size]" % [
			UiKit.hex(UiKit.GOOD if won else UiKit.BAD), "VICTORY" if won else "DEFEAT",
			"vs" if mine.home == team else "@", UiKit.esc(mine.opponent_of(team).name),
			"%d-%d" % [mine.rounds_for(team), mine.rounds_for(mine.opponent_of(team))]], 18)
		v.add_child(banner)
		v.add_child(UiKit.button("View full recap", func(): hub.open("Match Recap", func(): return recap(mine))))
	elif played.is_empty():
		v.add_child(UiKit.label("Nothing to play.", 18, UiKit.MUTED))
	else:
		v.add_child(UiKit.label("Bye week - your squad trained.", 22, Color.WHITE))
	if not s.last_injuries.is_empty():
		v.add_child(_section("INJURIES THIS WEEK"))
		for inj in s.last_injuries:
			var so: Soldier = inj["soldier"]
			var t: Team = inj["team"]
			v.add_child(UiKit.label("%s  %s  -  %s, out %d wk" % [t.abbrev, so.full_name(), inj["name"], inj["weeks"]],
				17, UiKit.BAD if t.user_controlled else UiKit.TEXT))
	v.add_child(_section("AROUND THE LEAGUE  -  %s" % label.to_upper()))
	for m in played:
		v.add_child(_score_card(m))
	if s.champion and s.phase == Season.PHASE_OFFSEASON:
		v.add_child(UiKit.rich("[font_size=30][color=#f59e0b]%s are the %d champions![/color][/font_size]" % [UiKit.esc(s.champion.name), s.year], 18))
	v.add_child(_section("STANDINGS"))
	v.add_child(UiKit.label(hub._mini_standings().replace("[color=white]", "").replace("[color=#8b97ab]", "").replace("[/color]", ""), 16))
	return v


# --- match preview / recap -----------------------------------------------------------

func preview(m: ScheduledMatch) -> Control:
	var s := _season()
	var v := _vbox(16)
	v.add_child(UiKit.label("%s  -  %s" % [s.week_label(m.week).to_upper(), "at " + m.home.name], 16, UiKit.MUTED))
	var h := _row(24)
	for t in [m.away, m.home]:
		var col := _vbox(6)
		col.custom_minimum_size.x = 520
		col.add_child(UiKit.team_chip(t, 22))
		col.add_child(UiKit.label(t.name, 26, Color.WHITE))
		col.add_child(UiKit.label("Record %s   -   OVR %d" % [s.record_text(t), t.team_ovr()], 16, UiKit.MUTED))
		var rows: Array = []
		var colors := {}
		for sid in t.scheme.slot_ids():
			var so: Soldier = t.lineup[sid]
			var ovr: int = t.ovr_in_slot(so, sid)
			colors[rows.size()] = {2: UiKit.ovr_color(ovr)}
			rows.append([sid, so.full_name(), ovr])
		col.add_child(UiKit.table(["SLOT", "STARTER", "OVR"], rows, [60, 240, 60], {}, colors))
		h.add_child(col)
	v.add_child(h)
	if not m.is_played() and m.week == s.week and m.involves(s.user_team()):
		var play := UiKit.button("Play %s  >>" % s.week_label(m.week), hub.advance, 20)
		play.custom_minimum_size = Vector2(300, 56)
		v.add_child(play)
	return v


func recap(m: ScheduledMatch) -> Control:
	var r := m.result
	var v := _vbox(16)
	var head := UiKit.rich("[font_size=36][color=white]%s %d  -  %d %s[/color][/font_size]\n%s  -  winner [color=white]%s[/color]" % [
		m.home.abbrev, m.rounds_for(m.home), m.rounds_for(m.away), m.away.abbrev,
		_season().week_label(m.week), UiKit.esc(m.winner().name)], 16)
	v.add_child(head)

	# Round-by-round strip
	var strip := _row(6)
	for rd in r.rounds:
		var winner_team: Team = r.teams[rd["winner"]]
		var p := UiKit.panel(winner_team.color.darkened(0.45), 6)
		p.add_child(UiKit.label("R%d %s  %ds" % [rd["number"], winner_team.abbrev, int(rd["duration_s"])], 14, Color.WHITE))
		strip.add_child(p)
	v.add_child(strip)

	for t in r.teams:
		v.add_child(_section("%s BOX SCORE" % t.name.to_upper()))
		var rows: Array = []
		var colors := {}
		var ids: Array = []
		for sid in r.box:
			if r.box[sid]["team"] == r.teams.find(t):
				ids.append(sid)
		ids.sort_custom(func(a, b): return MatchResult.impact(r.box[a]) > MatchResult.impact(r.box[b]))
		for sid in ids:
			var line: Dictionary = r.box[sid]
			var so := _soldier(sid)
			var hit: float = 100.0 * line["hits"] / max(1, line["shots"])
			if sid == r.mvp_id:
				colors[rows.size()] = {1: UiKit.ACCENT}
			rows.append([line["slot"], (so.short_name() if so else "?") + (" (MVP)" if sid == r.mvp_id else ""),
				line["kills"], line["deaths"], line["assists"], int(line["damage"]), line["shots"], "%d%%" % hit,
				line["headshots"], line["rounds_survived"], line["clutches"]])
		v.add_child(UiKit.table(["SLOT", "PLAYER", "K", "D", "A", "DMG", "SHOTS", "HIT%", "HS", "SURV", "CLUTCH"], rows,
			[60, 220, 40, 40, 40, 60, 60, 60, 40, 50, 60], {}, colors))

	v.add_child(_section("PLAY-BY-PLAY"))
	var pbp := RichTextLabel.new()
	pbp.bbcode_enabled = true
	pbp.custom_minimum_size = Vector2(0, 420)
	pbp.focus_mode = Control.FOCUS_ALL
	pbp.add_theme_font_size_override("normal_font_size", 15)
	pbp.add_theme_stylebox_override("normal", UiKit.flat(UiKit.PANEL, 8))
	pbp.add_theme_stylebox_override("focus", UiKit.flat(Color.TRANSPARENT, 8, 2, UiKit.ACCENT))
	var lines: Array[String] = []
	for e in r.events:
		var t := UiKit.esc(e)
		if e.begins_with("---") or e.begins_with("==="):
			t = "[color=white][b]%s[/b][/color]" % t
		elif e.contains("HEADSHOT"):
			t = "[color=#f59e0b]%s[/color]" % t
		lines.append(t)
	pbp.text = "\n".join(lines)
	v.add_child(pbp)
	return v


# --- team pages --------------------------------------------------------------------

func roster() -> Control:
	return _roster_table(false)


func progression() -> Control:
	return _roster_table(true)


func _roster_table(progress_view: bool) -> Control:
	var team := _season().user_team()
	var v := _vbox()
	if progress_view:
		v.add_child(_section("SELECT A SOLDIER TO SPEND SKILL POINTS  -  sorted by available SP"))
	var list: Array = team.roster.duplicate()
	if progress_view:
		list.sort_custom(func(a: Soldier, b: Soldier): return a.skill_points > b.skill_points)
	else:
		list.sort_custom(func(a: Soldier, b: Soldier): return _slot_order(team, a) < _slot_order(team, b))
	var rows: Array = []
	var colors := {}
	for s in list:
		var slot := team.slot_of(s)
		var ovr: int = team.ovr_in_slot(s, slot) if slot != &"" else s.best_ovr()
		var cells := [slot if slot != &"" else "BN", s.full_name(), s.age, ovr,
			Scheme.ROLE_NAMES[Scheme.best_role(s.stats)], s.level, "%d/%d" % [s.xp, Progression.xp_to_next(s.level)],
			s.skill_points, _grade(s), roundi(s.fatigue), _status_text(s)]
		var c := {3: UiKit.ovr_color(ovr), 9: fatigue_color(s.fatigue), 10: UiKit.BAD if s.is_injured() else UiKit.MUTED}
		if s.skill_points > 0:
			c[7] = UiKit.INFO
		colors[rows.size()] = c
		rows.append(cells)
	v.add_child(UiKit.table(["SLOT", "NAME", "AGE", "OVR", "BEST POS", "LV", "XP", "SP", "POT", "FAT", "STATUS"], rows,
		[50, 220, 50, 50, 110, 40, 100, 40, 50, 50, 130], {}, colors,
		func(i: int):
			var s: Soldier = list[i]
			hub.open(s.full_name(), func(): return player(s))))
	return v


func _slot_order(team: Team, s: Soldier) -> int:
	var slot := team.slot_of(s)
	var ids := team.scheme.slot_ids()
	return ids.find(slot) if slot != &"" else 100 + team.roster.find(s)


func player(s: Soldier) -> Control:
	var season := _season()
	var team := _team_of(s)
	var editable := team.user_controlled
	var slot := team.slot_of(s)
	var role := team.scheme.role_for_slot(slot) if slot != &"" else Scheme.best_role(s.stats)
	var v := _vbox(14)
	var head := UiKit.rich("[font_size=30][color=white]%s[/color][/font_size]   age %d  -  %s  -  %s\nLevel %d   -   XP %d / %d   -   [color=#38bdf8]%d skill points[/color]   -   Potential %s" % [
		UiKit.esc(s.full_name()), s.age, UiKit.esc(team.name), team.scheme.label_for_slot(slot) if slot != &"" else "Bench",
		s.level, s.xp, Progression.xp_to_next(s.level), s.skill_points, _grade(s)], 16)
	v.add_child(head)
	var ovrs := _row(14)
	for r in Scheme.ROLE_NAMES:
		var o := s.ovr_at_role(r)
		var p := UiKit.panel(UiKit.PANEL_HI if r != role else UiKit.ACCENT.darkened(0.6), 8)
		var rt := UiKit.rich("%s  [font_size=24][color=%s]%d[/color][/font_size]" % [Scheme.ROLE_NAMES[r].to_upper(), UiKit.hex(UiKit.ovr_color(o)), o], 15)
		rt.autowrap_mode = TextServer.AUTOWRAP_OFF
		rt.custom_minimum_size.x = 160
		p.add_child(rt)
		ovrs.add_child(p)
	v.add_child(ovrs)
	if editable:
		var actions := _row()
		actions.add_child(UiKit.button("Auto-spend SP", func():
			Progression.auto_spend(s, role)
			hub.replace(s.full_name(), func(): return player(s))))
		v.add_child(actions)

	var cond := UiKit.rich("CONDITION   Fatigue [color=%s]%d (%s)[/color]   -   %s   -   Training: %s" % [
		UiKit.hex(fatigue_color(s.fatigue)), roundi(s.fatigue), Conditioning.status(s.fatigue),
		("[color=%s]INJURED: %s, out %d wk%s[/color]" % [UiKit.hex(UiKit.BAD), UiKit.esc(s.injury_name), s.injury_weeks, "" if s.injury_weeks == 1 else "s"]) if s.is_injured() else "[color=%s]Healthy[/color]" % UiKit.hex(UiKit.GOOD),
		Training.label(s.intensity)], 16)
	v.add_child(cond)

	v.add_child(_section("RATINGS BY GROUP  -  +1 group = random points across its stats (max +%d each)  -  white stats count toward OVR at %s" % [
		Progression.MAX_STAT_GAIN_PER_UPGRADE, Scheme.ROLE_NAMES[role]]))
	var weights: Dictionary = Scheme.ROLE_WEIGHTS[role]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 14)
	for g in Stats.GROUP_ORDER:
		var box := _vbox(4)
		var head_row := _row(10)
		var gr := s.group_rating(g)
		var upgradable := Stats.UPGRADABLE_GROUPS.has(g)
		var title := UiKit.rich("[font_size=20][color=white]%s[/color][/font_size]  [font_size=24][color=%s]%d[/color][/font_size]%s" % [
			Stats.GROUP_LABELS[g].to_upper(), UiKit.hex(UiKit.ovr_color(gr)), gr,
			("  [color=#8b97ab]cap %d[/color]" % s.group_cap(g)) if upgradable else "  [color=#8b97ab](age / injuries only)[/color]"], 15)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.custom_minimum_size.x = 330
		head_row.add_child(title)
		if editable and upgradable:
			var group := g
			var up := UiKit.button("+1 (%d SP)" % Progression.upgrade_cost(s, g), func():
				Progression.upgrade_group(s, group)
				hub.replace(s.full_name(), func(): return player(s)), 13)
			up.custom_minimum_size.x = 110
			up.disabled = not Progression.can_upgrade(s, g)
			if Progression.is_capped(s, g):
				up.text = "CAPPED"
			head_row.add_child(up)
		box.add_child(head_row)
		for st in Stats.group_stats(g):
			box.add_child(_stat_row(s, st, weights.has(st)))
		grid.add_child(box)
	v.add_child(grid)
	v.add_child(UiKit.label("Career: %d matches  -  %d K / %d D / %d A  -  %d damage" % [
		s.career["matches"], s.career["kills"], s.career["deaths"], s.career["assists"], s.career["damage"]], 15, UiKit.MUTED))
	return v


func _stat_row(s: Soldier, st: StringName, counts: bool) -> Control:
	var cell := _row(10)
	var name_l := UiKit.label("   " + Stats.LABELS[st], 15, Color.WHITE if counts else UiKit.MUTED)
	name_l.custom_minimum_size.x = 190
	cell.add_child(name_l)
	var bar := ProgressBar.new()
	bar.max_value = 99
	bar.value = s.stats[st]
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(180, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UiKit.flat(UiKit.LINE, 4))
	var fill := UiKit.flat(UiKit.ovr_color(s.stats[st]), 4)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("fill", fill)
	cell.add_child(bar)
	var val := UiKit.label(str(s.stats[st]), 16, UiKit.ovr_color(s.stats[st]))
	val.custom_minimum_size.x = 34
	cell.add_child(val)
	return cell


func lineup() -> Control:
	var team := _season().user_team()
	var v := _vbox()
	var top := _row()
	top.add_child(UiKit.label("Team OVR %d" % team.team_ovr(), 22, Color.WHITE))
	top.add_child(UiKit.button("Auto Lineup", func():
		team.auto_lineup()
		hub.replace("Lineup", lineup)))
	v.add_child(top)
	v.add_child(_section("POWER FRONT  -  pick a soldier for each slot (swaps if already starting)"))
	for sid in team.scheme.slot_ids():
		var row := _row(16)
		var slot_l := UiKit.label(team.scheme.label_for_slot(sid), 18, Color.WHITE)
		slot_l.custom_minimum_size.x = 140
		row.add_child(slot_l)
		var pick := OptionButton.new()
		pick.custom_minimum_size = Vector2(420, 44)
		UiKit.style_button(pick)
		var current: Soldier = team.lineup[sid]
		for i in team.roster.size():
			var s: Soldier = team.roster[i]
			var where := team.slot_of(s)
			pick.add_item("%s  -  %d OVR  -  FAT %d%s%s" % [s.full_name(), team.ovr_in_slot(s, sid), roundi(s.fatigue),
				"  - INJURED" if s.is_injured() else "", "  (%s)" % where if where != &"" and where != sid else ""])
			pick.set_item_disabled(i, s.is_injured() and s != current)
			if s == current:
				pick.select(i)
		var slot_id := sid
		pick.item_selected.connect(func(i: int):
			team.assign(slot_id, team.roster[i])
			hub.replace("Lineup", lineup))
		row.add_child(pick)
		var o := team.ovr_in_slot(current, sid)
		row.add_child(UiKit.label(str(o), 22, UiKit.ovr_color(o)))
		row.add_child(UiKit.label(_status_text(current), 16, UiKit.BAD if current.is_injured() else fatigue_color(current.fatigue)))
		v.add_child(row)
	v.add_child(_section("BENCH"))
	for s in team.bench():
		v.add_child(UiKit.label("%s  -  best %s %d  -  %s" % [s.full_name(), Scheme.ROLE_NAMES[Scheme.best_role(s.stats)], s.best_ovr(), _status_text(s)],
			16, UiKit.BAD if s.is_injured() else UiKit.MUTED))
	v.add_child(UiKit.label("Injured starters are swapped for the best healthy bench soldier when the week is played.", 14, UiKit.MUTED))
	return v


func training() -> Control:
	var season := _season()
	var team := season.user_team()
	var v := _vbox()
	var info := "Each soldier trains at their own intensity every week. "
	for it in Training.INTENSITIES:
		var d: Dictionary = Training.INTENSITY_INFO[it]
		info += "%s: %d XP%s.  " % [d["label"], roundi(Training.xp_for(it)),
			", extra recovery" if it == Soldier.INTENSITY_REST else ", +%d fatigue" % roundi(float(d["load"]))]
	var info_lbl := UiKit.label(info, 15, UiKit.MUTED)
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info_lbl)
	var fat_lbl := UiKit.label("Starting a match adds +%d fatigue. Endurance shrinks fatigue gain; age raises it and slows recovery. Above 50 fatigue, accuracy and speed drop (steeply above 75) and injuries get likelier." % roundi(Conditioning.MATCH_LOAD), 15, UiKit.MUTED)
	fat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(fat_lbl)
	var top := _row()
	top.add_child(UiKit.button("Auto-set intensities", func():
		Training.ai_set_intensities(team)
		hub.replace("Training", training)))
	top.add_child(UiKit.button("All Normal", func():
		for so in team.roster:
			so.intensity = Soldier.INTENSITY_NORMAL
		hub.replace("Training", training)))
	v.add_child(top)
	var list: Array = team.roster.duplicate()
	list.sort_custom(func(a: Soldier, b: Soldier): return _slot_order(team, a) < _slot_order(team, b))
	for so: Soldier in list:
		var row := _row(16)
		var slot := team.slot_of(so)
		var name_l := UiKit.label("%s  %s" % [slot if slot != &"" else "BN", so.full_name()], 17, Color.WHITE)
		name_l.custom_minimum_size.x = 270
		row.add_child(name_l)
		var age_l := UiKit.label("age %d" % so.age, 15, UiKit.MUTED)
		age_l.custom_minimum_size.x = 70
		row.add_child(age_l)
		var fat := UiKit.label("FAT %d  %s" % [roundi(so.fatigue), Conditioning.status(so.fatigue)], 16, fatigue_color(so.fatigue))
		fat.custom_minimum_size.x = 170
		row.add_child(fat)
		if so.is_injured():
			row.add_child(UiKit.label("INJURED (%s, %d wk) - rehab, no training" % [so.injury_name, so.injury_weeks], 16, UiKit.BAD))
		else:
			var pick := OptionButton.new()
			pick.custom_minimum_size = Vector2(200, 44)
			UiKit.style_button(pick)
			for it in Training.INTENSITIES:
				pick.add_item(Training.label(it))
			pick.select(Training.INTENSITIES.find(so.intensity))
			var who := so
			pick.item_selected.connect(func(i: int):
				who.intensity = Training.INTENSITIES[i]
				hub.replace("Training", training))
			row.add_child(pick)
		v.add_child(row)
	v.add_child(UiKit.label("Training runs automatically when you advance the week. Spend the skill points earned in Player Progression.", 14, UiKit.MUTED))
	return v


func injuries() -> Control:
	var s := _season()
	var v := _vbox()
	v.add_child(_section("INJURY REPORT  -  chance from the Injury rating and fatigue; time out from Toughness"))
	var rows: Array = []
	var colors := {}
	var hl := {}
	for t in s.league.teams:
		for so in t.injured():
			if t.user_controlled:
				hl[rows.size()] = t.color.darkened(0.6)
			colors[rows.size()] = {4: UiKit.BAD}
			rows.append([t.abbrev, so.full_name(), so.age, so.injury_name, "%d wk" % so.injury_weeks, so.stats[Stats.INJURY], so.stats[Stats.TOUGHNESS]])
	if rows.is_empty():
		v.add_child(UiKit.label("No current injuries.", 18, UiKit.MUTED))
	else:
		v.add_child(UiKit.table(["TEAM", "NAME", "AGE", "INJURY", "OUT", "INJ", "TGH"], rows, [60, 220, 50, 220, 70, 50, 50], hl, colors))
	v.add_child(_section("THIS SEASON"))
	var log_rows: Array = []
	for i in range(s.injury_log.size() - 1, -1, -1):
		var e: Dictionary = s.injury_log[i]
		var so: Soldier = e["soldier"]
		var t: Team = e["team"]
		log_rows.append([s.week_label(e["week"]), t.abbrev, so.full_name(), e["name"], "%d wk" % e["weeks"]])
	if log_rows.is_empty():
		v.add_child(UiKit.label("No injuries yet this season.", 16, UiKit.MUTED))
	else:
		v.add_child(UiKit.table(["WHEN", "TEAM", "NAME", "INJURY", "OUT"], log_rows, [110, 60, 220, 220, 70]))
	return v


func _status_text(s: Soldier) -> String:
	if s.is_injured():
		return "INJ %dw" % s.injury_weeks
	return Conditioning.status(s.fatigue)


static func fatigue_color(f: float) -> Color:
	if f < 50.0:
		return UiKit.GOOD
	if f < 75.0:
		return Color("#eab308")
	return UiKit.BAD


func team_stats() -> Control:
	var team := _season().user_team()
	var v := _vbox()
	var rows: Array = []
	for t in season_totals():
		if t["team"] == team:
			var s: Soldier = t["soldier"]
			rows.append([s.full_name(), t["matches"], t["kills"], t["deaths"], t["assists"], "%.2f" % (float(t["kills"]) / max(1, t["deaths"])),
				int(t["damage"]), "%d%%" % (100.0 * t["hits"] / max(1, t["shots"])), t["mvps"]])
	if rows.is_empty():
		v.add_child(UiKit.label("No matches played yet this season.", 18, UiKit.MUTED))
		return v
	rows.sort_custom(func(a, b): return a[2] > b[2])
	v.add_child(UiKit.table(["PLAYER", "GP", "K", "D", "A", "K/D", "DMG", "HIT%", "MVP"], rows, [220, 40, 50, 50, 50, 60, 70, 60, 50]))
	return v


# --- league pages ------------------------------------------------------------------

func leaders() -> Control:
	var v := _vbox(18)
	var totals := season_totals()
	if totals.is_empty():
		v.add_child(UiKit.label("No matches played yet this season.", 18, UiKit.MUTED))
		return v
	var cats := [["KILLS", "kills"], ["ASSISTS", "assists"], ["DAMAGE", "damage"], ["MVP AWARDS", "mvps"], ["HEADSHOTS", "headshots"]]
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 20)
	flow.add_theme_constant_override("v_separation", 20)
	for cat in cats:
		var key: String = cat[1]
		var sorted := totals.duplicate()
		sorted.sort_custom(func(a, b): return a[key] > b[key])
		var rows: Array = []
		var hl := {}
		for i in mini(5, sorted.size()):
			var s: Soldier = sorted[i]["soldier"]
			var t: Team = sorted[i]["team"]
			if t.user_controlled:
				hl[i] = t.color.darkened(0.6)
			rows.append([i + 1, s.short_name(), t.abbrev, int(sorted[i][key])])
		var col := _vbox(6)
		col.add_child(_section(cat[0]))
		col.add_child(UiKit.table(["#", "PLAYER", "TM", cat[0].left(3)], rows, [24, 170, 50, 60], hl))
		flow.add_child(col)
	v.add_child(flow)
	return v


func playoffs() -> Control:
	var s := _season()
	var v := _vbox(16)
	if s.phase == Season.PHASE_REGULAR:
		v.add_child(_section("IF THE SEASON ENDED TODAY"))
		var rows: Array = s.standings()
		var seeds: Array = rows.slice(0, Season.PLAYOFF_TEAMS)
		for pair in [[0, 3], [1, 2]]:
			var a: StandingRow = seeds[pair[0]]
			var b: StandingRow = seeds[pair[1]]
			var p := UiKit.panel(UiKit.PANEL, 10)
			p.add_child(UiKit.rich("SEMIFINAL   [color=white](%d) %s  %d-%d[/color]   vs   [color=white](%d) %s  %d-%d[/color]" % [
				a.rank, UiKit.esc(a.team.name), a.wins, a.losses, b.rank, UiKit.esc(b.team.name), b.wins, b.losses], 18))
			v.add_child(p)
		var out: Array[String] = []
		for r in rows.slice(Season.PLAYOFF_TEAMS):
			out.append("%s (%d-%d)" % [r.team.name, r.wins, r.losses])
		v.add_child(UiKit.label("On the outside: " + ", ".join(out), 16, UiKit.MUTED))
		v.add_child(UiKit.label("Semifinals in week %d, the Final in week %d." % [Season.REGULAR_WEEKS + 1, Season.REGULAR_WEEKS + 2], 14, UiKit.MUTED))
		return v
	v.add_child(_section("%d PLAYOFF BRACKET" % s.year))
	var bracket := _row(30)
	var semis := _vbox(20)
	var finals := _vbox(20)
	finals.alignment = BoxContainer.ALIGNMENT_CENTER
	for m in s.playoff_matches:
		var card := _score_card(m)
		card.custom_minimum_size = Vector2(480, 150)
		if m.stage == Season.STAGE_FINAL:
			finals.add_child(card)
		else:
			semis.add_child(card)
	if finals.get_child_count() == 0:
		finals.add_child(UiKit.label("FINAL\nWinners of the semifinals", 18, UiKit.MUTED))
	bracket.add_child(semis)
	bracket.add_child(finals)
	v.add_child(bracket)
	if s.champion:
		v.add_child(UiKit.rich("[font_size=34][color=#f59e0b]CHAMPIONS: %s[/color][/font_size]" % UiKit.esc(s.champion.name), 18))
	return v


func team_rankings() -> Control:
	var s := _season()
	var teams: Array = s.league.teams.duplicate()
	teams.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	var rows: Array = []
	var hl := {}
	for i in teams.size():
		var t: Team = teams[i]
		if t.user_controlled:
			hl[i] = t.color.darkened(0.6)
		var best: Soldier = t.roster[0]
		for so in t.roster:
			if so.best_ovr() > best.best_ovr():
				best = so
		rows.append([i + 1, t.name, t.team_ovr(), s.record_text(t), best.full_name(), best.best_ovr()])
	var v := _vbox()
	v.add_child(UiKit.table(["#", "TEAM", "OVR", "RECORD", "BEST PLAYER", "OVR"], rows, [30, 260, 50, 80, 220, 50], hl))
	return v


func news() -> Control:
	var v := _vbox(10)
	var items := headlines(40)
	if items.is_empty():
		v.add_child(UiKit.label("No news yet. Play some matches.", 18, UiKit.MUTED))
	for h in items:
		var p := UiKit.panel(UiKit.PANEL, 8)
		p.add_child(UiKit.rich(h, 17))
		v.add_child(p)
	return v


## Most recent first. Generated from match results.
func headlines(limit: int) -> Array[String]:
	var s := _season()
	var out: Array[String] = []
	for w in range(s.total_weeks(), 0, -1):
		for m in s.matches_for_week(w):
			if not m.is_played():
				continue
			var win: Team = m.winner()
			var lose: Team = m.loser()
			var mvp := _soldier(m.result.mvp_id)
			var line: Dictionary = m.result.box.get(m.result.mvp_id, {})
			var verb := "edge" if m.rounds_for(lose) == 3 else ("sweep" if m.rounds_for(lose) == 0 else "beat")
			var txt := "[color=white]%s %s %s %d-%d[/color]  -  %s" % [UiKit.esc(win.name), verb, UiKit.esc(lose.name),
				m.rounds_for(win), m.rounds_for(lose), s.week_label(w)]
			if mvp and not line.is_empty():
				txt += "\n%s named MVP with %d kills and %d damage." % [UiKit.esc(mvp.full_name()), line["kills"], line["damage"]]
			if m.stage == Season.STAGE_FINAL:
				txt = "[color=#f59e0b]CHAMPIONS![/color] " + txt
			out.append(txt)
			if out.size() >= limit:
				return out
	return out


func sim_options() -> Control:
	var s := _season()
	var v := _vbox(14)
	v.add_child(UiKit.label("Current: %d season, %s" % [s.year, hub._phase_text()], 18, Color.WHITE))
	var b1 := UiKit.button("Sim to end of regular season", func():
		s.sim_to_end_of_regular_season()
		hub.page_stack.clear()
		hub.refresh()
		hub.app.toast("Regular season complete."), 18)
	b1.disabled = s.phase != Season.PHASE_REGULAR
	v.add_child(b1)
	var b2 := UiKit.button("Sim to end of season (through the Final)", func():
		s.sim_to_end_of_season()
		hub.page_stack.clear()
		hub.refresh()
		hub.app.toast("%s win the title." % (s.champion.name if s.champion else "-")), 18)
	b2.disabled = s.phase == Season.PHASE_OFFSEASON
	v.add_child(b2)
	v.add_child(UiKit.label("Your skill points are never auto-spent; AI teams spend theirs each week.", 14, UiKit.MUTED))
	return v


func coming_soon(title: String, bullets: Array) -> Control:
	var v := _vbox(12)
	v.add_child(UiKit.label("%s is laid out but not built yet." % title, 22, Color.WHITE))
	v.add_child(_section("PLANNED"))
	for b in bullets:
		var p := UiKit.panel(UiKit.PANEL, 8)
		p.add_child(UiKit.label("-  " + str(b), 17))
		v.add_child(p)
	var back := UiKit.button("Back", hub.go_back)
	back.custom_minimum_size.x = 160
	v.add_child(back)
	return v


# --- data helpers --------------------------------------------------------------------

## Per-soldier totals for the current season: Array of dicts
## {soldier, team, matches, kills, deaths, assists, damage, shots, hits, headshots, mvps}.
func season_totals() -> Array:
	var s := _season()
	var by_id := {}
	for w in range(1, s.total_weeks() + 1):
		for m in s.matches_for_week(w):
			if not m.is_played():
				continue
			var r: MatchResult = m.result
			for sid in r.box:
				var line: Dictionary = r.box[sid]
				if not by_id.has(sid):
					var so := _soldier(sid)
					if so == null:
						continue
					by_id[sid] = {"soldier": so, "team": r.teams[line["team"]], "matches": 0, "kills": 0, "deaths": 0,
						"assists": 0, "damage": 0, "shots": 0, "hits": 0, "headshots": 0, "mvps": 0}
				var t: Dictionary = by_id[sid]
				t["matches"] += 1
				for k in ["kills", "deaths", "assists", "damage", "shots", "hits", "headshots"]:
					t[k] += line[k]
				if sid == r.mvp_id:
					t["mvps"] += 1
	return by_id.values()


func _soldier(id: int) -> Soldier:
	for t in _season().league.teams:
		for s in t.roster:
			if s.id == id:
				return s
	return null


func _team_of(s: Soldier) -> Team:
	for t in _season().league.teams:
		if t.roster.has(s):
			return t
	return null


func _grade(s: Soldier) -> String:
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

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
		var with_sp := 0
		for s in team.roster:
			if s.skill_points > 0:
				with_sp += 1
		var actions := _row()
		var auto := UiKit.button("Auto-progress all (%d with SP)" % with_sp, func():
			var raised := 0
			var players := 0
			for s in team.roster:
				if s.skill_points <= 0:
					continue
				var slot := team.slot_of(s)
				var role := team.scheme.role_for_slot(slot) if slot != &"" else Scheme.best_role(s.stats)
				var groups: Array = Progression.auto_spend(s, role)
				if not groups.is_empty():
					players += 1
					raised += groups.size()
			hub.app.toast("Auto-progressed %d players (%d group upgrades)." % [players, raised] if players > 0 else "No skill points could be spent.")
			hub.replace("Player Progression", progression))
		auto.disabled = with_sp == 0
		actions.add_child(auto)
		v.add_child(actions)
	var list: Array = team.roster.duplicate()
	if progress_view:
		list.sort_custom(func(a: Soldier, b: Soldier): return a.skill_points > b.skill_points)
	else:
		list.sort_custom(func(a: Soldier, b: Soldier): return _slot_order(team, a) < _slot_order(team, b))
	var table := _vbox(4)
	table.add_child(_roster_header(progress_view))
	for s in list:
		table.add_child(_roster_row(team, s, progress_view))
	v.add_child(table)
	v.add_child(_potential_legend())
	return v


## Roster table layout: portrait, name/age/pos, potential, OVR, one column per stat group,
## (SP in the progression view), then lineup slot / status.
const RCOL_NAME := 190
const RCOL_POT := 44
const RCOL_OVR := 52
const RCOL_GROUP := 104
const RCOL_SP := 44
const RCOL_STATUS := 150


func _roster_cols(progress_view: bool) -> Array:
	var cols := [["", PCOL_PORTRAIT], ["SOLDIER", RCOL_NAME], ["POT", RCOL_POT], ["OVR", RCOL_OVR]]
	for g in Stats.GROUP_ORDER:
		cols.append([Stats.GROUP_LABELS[g].to_upper(), RCOL_GROUP])
	if progress_view:
		cols.append(["SP", RCOL_SP])
	cols.append(["SLOT / STATUS", RCOL_STATUS])
	return cols


func _roster_header(progress_view: bool) -> Control:
	var panel := PanelContainer.new()
	var sb := UiKit.flat(UiKit.PANEL_HI, 4)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left = 14
	panel.add_theme_stylebox_override("panel", sb)
	var hb := _row(PCOL_SEP)
	for c in _roster_cols(progress_view):
		var l := UiKit.label(c[0], 13, UiKit.MUTED)
		l.custom_minimum_size.x = c[1]
		l.clip_text = true
		hb.add_child(l)
	panel.add_child(hb)
	return panel


func _roster_row(team: Team, s: Soldier, progress_view: bool) -> Control:
	var cols := _roster_cols(progress_view)
	var width := 28
	for c in cols:
		width += c[1] + PCOL_SEP
	var info := Button.new()
	UiKit.style_button(info, UiKit.PANEL, UiKit.ACCENT, 6)
	info.custom_minimum_size = Vector2(width, 62)
	info.pressed.connect(func(): hub.open(s.full_name(), func(): return player(s)))
	var hb := _row(PCOL_SEP)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 14
	hb.offset_right = -14
	hb.offset_top = 6
	hb.offset_bottom = -6
	info.add_child(hb)
	hb.add_child(Portrait.new(s.id, PCOL_PORTRAIT))
	hb.add_child(_two_lines(s.full_name(), Color.WHITE,
		"age %d  -  %s" % [s.age, Scheme.ROLE_NAMES[Scheme.best_role(s.stats)]], RCOL_NAME))
	hb.add_child(_big_cell(s.potential_letter(), potential_color(s.potential), RCOL_POT))
	var slot := team.slot_of(s)
	var ovr: int = team.ovr_in_slot(s, slot) if slot != &"" else s.best_ovr()
	hb.add_child(_big_cell(str(ovr), UiKit.ovr_color(ovr), RCOL_OVR))
	for g in Stats.GROUP_ORDER:
		hb.add_child(_rating_cell(s.group_rating(g), RCOL_GROUP))
	if progress_view:
		hb.add_child(_big_cell(str(s.skill_points), UiKit.INFO if s.skill_points > 0 else UiKit.MUTED, RCOL_SP))
	var slot_text := team.scheme.label_for_slot(slot) if slot != &"" else "Bench"
	hb.add_child(_two_lines(slot_text, Color.WHITE if slot != &"" else UiKit.MUTED, _status_text(s), RCOL_STATUS, 15))
	return info


func _big_cell(text: String, color: Color, width: int) -> Control:
	var l := UiKit.label(text, 24, color)
	l.custom_minimum_size.x = width
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A group rating: the number over a thin bar filled to the rating, both in the rating color.
func _rating_cell(value: int, width: int) -> Control:
	var v := _vbox(3)
	v.custom_minimum_size.x = width
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(UiKit.label(str(value), 18, UiKit.ovr_color(value)))
	var bar := _row(0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var full := width - 16
	var lit := ColorRect.new()
	lit.color = UiKit.ovr_color(value)
	lit.custom_minimum_size = Vector2(maxf(1.0, full * value / 99.0), 5)
	lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(lit)
	var rest := ColorRect.new()
	rest.color = UiKit.LINE
	rest.custom_minimum_size = Vector2(full - lit.custom_minimum_size.x, 5)
	rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(rest)
	v.add_child(bar)
	return v


## Potential grades share the scouting grade colors: F red .. A green.
static func potential_color(grade: int) -> Color:
	return TIER_COLORS[clampi(grade, 0, TIER_COLORS.size() - 1)]


func _potential_legend() -> Control:
	var parts: PackedStringArray = []
	for i in range(Soldier.POTENTIAL_A, -1, -1):
		parts.append("[color=%s]%s[/color] %sx" % [UiKit.hex(potential_color(i)), Soldier.POTENTIAL_LETTERS[i], str(Progression.POTENTIAL_XP[i])])
	return UiKit.rich("[color=#8b97ab]POT = potential (XP gain):[/color]   " + "   ".join(parts)
		+ "   [color=#8b97ab]Grades move each offseason with awards, performance and age.[/color]", 14)

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
	var top := _row(16)
	top.add_child(Portrait.new(s.id, 84, team.color))
	var head := UiKit.rich("[font_size=30][color=white]%s[/color][/font_size]   age %d  -  %s  -  %s\nPotential [font_size=22][color=%s]%s[/color][/font_size]   -   [color=#38bdf8]%d skill points[/color]%s" % [
		UiKit.esc(s.full_name()), s.age, UiKit.esc(team.name), team.scheme.label_for_slot(slot) if slot != &"" else "Bench",
		UiKit.hex(potential_color(s.potential)), s.potential_letter(), s.skill_points,
		("   -   [color=#f59e0b]%s[/color]" % ", ".join(_awards_of(s))) if not _awards_of(s).is_empty() else ""], 16)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(head)
	v.add_child(top)
	var bars := _row(30)
	var xp: Array = Progression.xp_progress(s)
	bars.add_child(_meter("XP", float(xp[0]), float(xp[1]), UiKit.INFO,
		"%d / %d  (+%d SP)  -  %sx XP from potential" % [xp[0], xp[1], Progression.SKILL_POINTS_PER_LEVEL, str(Progression.xp_multiplier(s))]))
	bars.add_child(_meter("FATIGUE", s.fatigue, 100.0, fatigue_color(s.fatigue),
		"%d  -  %s" % [roundi(s.fatigue), Conditioning.status(s.fatigue)]))
	v.add_child(bars)
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

	var cond := UiKit.rich("CONDITION   %s   -   Training: %s" % [
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


## A labelled bar: "LABEL  [=====-----]  detail".
func _meter(label: String, value: float, max_value: float, color: Color, detail: String) -> Control:
	var h := _row(10)
	var l := UiKit.label(label, 15, UiKit.MUTED)
	l.custom_minimum_size.x = 76
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.max_value = max_value
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UiKit.flat(UiKit.LINE, 4))
	var fill := UiKit.flat(color, 4)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("fill", fill)
	h.add_child(bar)
	h.add_child(UiKit.label(detail, 15, UiKit.TEXT))
	return h


## Every award a soldier has won, newest first, e.g. "2026 Season MVP".
func _awards_of(s: Soldier) -> Array:
	var out: Array = []
	var history: Array = _season().review_history
	for i in range(history.size() - 1, -1, -1):
		var rev: SeasonReview = history[i]
		for a in rev.award_for(s):
			out.append("%d %s" % [rev.year, a])
	return out


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


# --- scouting & draft --------------------------------------------------------------

const TIER_COLORS := [Color("#ef4444"), Color("#f97316"), Color("#e5e7eb"), Color("#38bdf8"), Color("#22c55e")]

## Position filter shared by the scouting list and the draft room (-1 = all).
var role_filter := -1


func _filter_row(title: String, rebuild: Callable) -> HBoxContainer:
	var row := _row(8)
	var options := [[-1, "All"], [Scheme.Role.FRONTMAN, "Frontman"], [Scheme.Role.CENTER, "Center"], [Scheme.Role.FLEX, "Flex"]]
	for o in options:
		var val: int = o[0]
		var b := UiKit.button(("[ %s ]" % o[1]) if role_filter == val else o[1], func():
			role_filter = val
			hub.replace(title, rebuild), 15)
		b.custom_minimum_size.x = 110
		row.add_child(b)
	return row


func _filtered(list: Array[Prospect]) -> Array[Prospect]:
	var out: Array[Prospect] = []
	for p in list:
		if role_filter == -1 or int(p.listed_role) == role_filter:
			out.append(p)
	return out


## Prospect table layout (shared by Scouting and the Draft Room): portrait, name/age/pos,
## projection, one column per stat group, then the action button.
const PCOL_PORTRAIT := 48
const PCOL_NAME := 180
const PCOL_PROJ := 104
const PCOL_GROUP := 136
const PCOL_ACTION := 96
const PCOL_SEP := 10


func _prospect_header() -> Control:
	var panel := PanelContainer.new()
	var sb := UiKit.flat(UiKit.PANEL_HI, 4)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	var hb := _row(PCOL_SEP)
	var cols := [["", PCOL_PORTRAIT], ["PROSPECT", PCOL_NAME], ["PROJECTED", PCOL_PROJ]]
	for g in Stats.GROUP_ORDER:
		cols.append([Stats.GROUP_LABELS[g].to_upper(), PCOL_GROUP])
	for c in cols:
		var l := UiKit.label(c[0], 13, UiKit.MUTED)
		l.custom_minimum_size.x = c[1]
		l.clip_text = true
		hb.add_child(l)
	panel.add_child(hb)
	return panel


## One grade column: a 5-segment bar (lit where his true grade could be), then the low and
## high grade names, each in its own color.
func _grade_cell(g: StringName, w: Variant) -> Control:
	var v := _vbox(2)
	v.custom_minimum_size.x = PCOL_GROUP
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := _row(2)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in Draft.TIER_COUNT:
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2((PCOL_GROUP - 2 * (Draft.TIER_COUNT - 1)) / float(Draft.TIER_COUNT), 6)
		var lit: bool = w != null and t >= (w as Vector2i).x and t <= (w as Vector2i).y
		seg.color = TIER_COLORS[t] if lit else UiKit.LINE
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(seg)
	v.add_child(bar)
	if w == null:
		v.add_child(UiKit.label("?", 14, UiKit.MUTED))
		return v
	var wv: Vector2i = w
	var hi := UiKit.label(Draft.tier_name(g, wv.y), 14, TIER_COLORS[wv.y])
	hi.clip_text = true
	v.add_child(hi)
	if wv.x != wv.y:
		var lo := UiKit.label(Draft.tier_name(g, wv.x), 14, TIER_COLORS[wv.x])
		lo.clip_text = true
		v.add_child(lo)
	return v


func _two_lines(top: String, top_color: Color, bottom: String, width: int, top_size := 16) -> Control:
	var v := _vbox(2)
	v.custom_minimum_size.x = width
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := UiKit.label(top, top_size, top_color)
	a.clip_text = true
	v.add_child(a)
	var b := UiKit.label(bottom, 13, UiKit.MUTED)
	b.clip_text = true
	v.add_child(b)
	return v


## One prospect row: the row itself opens the scouting report; the action button sits at the end.
func _prospect_row(p: Prospect, action_text: String, action_enabled: bool, action: Callable) -> Control:
	var row := _row(PCOL_SEP)
	var info := Button.new()
	UiKit.style_button(info, UiKit.PANEL, UiKit.ACCENT, 6)
	info.custom_minimum_size = Vector2(PCOL_PORTRAIT + PCOL_NAME + PCOL_PROJ + PCOL_GROUP * Stats.GROUP_ORDER.size()
		+ PCOL_SEP * (2 + Stats.GROUP_ORDER.size()) + 28, 70)
	info.pressed.connect(func(): hub.open(p.soldier.full_name(), func(): return prospect(p)))
	var hb := _row(PCOL_SEP)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 14
	hb.offset_right = -14
	hb.offset_top = 6
	hb.offset_bottom = -6
	info.add_child(hb)
	hb.add_child(Portrait.new(p.soldier.id, PCOL_PORTRAIT))
	hb.add_child(_two_lines(p.soldier.full_name(), Color.WHITE,
		"age %d  -  %s" % [p.soldier.age, Scheme.ROLE_NAMES[p.listed_role]], PCOL_NAME))
	var status := "scouted %d/%d" % [p.points, Draft.MAX_POINTS_PER_PROSPECT]
	if not p.is_available():
		status = "pick %d - %s" % [p.pick_number, p.drafted_by.abbrev]
	hb.add_child(_two_lines(Draft.projection_text(p.projected_rank), UiKit.ACCENT, status, PCOL_PROJ, 15))
	for g in Stats.GROUP_ORDER:
		var cell := _grade_cell(g, p.reveals.get(g))
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(cell)
	row.add_child(info)
	var act := UiKit.button(action_text, action, 15)
	act.custom_minimum_size = Vector2(PCOL_ACTION, 70)
	act.disabled = not action_enabled
	row.add_child(act)
	return row


func _scout_and_toast(p: Prospect) -> void:
	var g := _season().draft.scout(p)
	if g == &"":
		hub.app.toast("Can't scout %s." % p.soldier.short_name())
		return
	hub.app.toast("%s  %s: %s" % [p.soldier.short_name(), Stats.GROUP_LABELS[g], Draft.window_text(g, p.reveals[g])])


## Prospects ordered by the consensus big board (projected rank).
func _by_projection(list: Array[Prospect]) -> Array[Prospect]:
	var out: Array[Prospect] = list.duplicate()
	out.sort_custom(func(a: Prospect, b: Prospect): return a.projected_rank < b.projected_rank)
	return out


func _grade_legend() -> Control:
	var names := ["Poor", "Below average", "Average", "Good", "Elite"]
	var parts: PackedStringArray = []
	for i in names.size():
		parts.append("[color=%s]%s[/color]" % [UiKit.hex(TIER_COLORS[i]), names[i]])
	return UiKit.rich("[color=#8b97ab]Grade colors:[/color]   " + "   ".join(parts) + "   [color=#8b97ab]?  = not scouted yet[/color]", 14)


func scouting() -> Control:
	var d := _season().draft
	var v := _vbox(10)
	v.add_child(UiKit.rich("[font_size=22][color=white]%d DRAFT CLASS[/color][/font_size]     [color=#38bdf8]%d scout points[/color] available  (+%d per week, unspent points carry over)" % [
		d.year, d.scout_points, Draft.POINTS_PER_WEEK], 16))
	var help := UiKit.label("Each point goes to a random stat group: the first point on a group shows a 3-grade range, a second narrows it to 2. Up to %d points per prospect. Projected rounds are the league consensus - potential stays hidden until draft day." % Draft.MAX_POINTS_PER_PROSPECT, 14, UiKit.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)
	v.add_child(_grade_legend())
	var nav := _row()
	nav.add_child(UiKit.button("Mock Draft", hub.open_mock_draft, 15))
	nav.add_child(UiKit.button("Draft Room", hub.open_draft_room, 15))
	v.add_child(nav)
	v.add_child(_filter_row("Scouting", scouting))
	var list := _by_projection(_filtered(d.prospects))
	v.add_child(_section("%d PROSPECTS  -  by projected pick  -  click a row for his full report" % list.size()))
	var rows := _vbox(4)
	rows.add_child(_prospect_header())
	for p in list:
		var prospect_ref := p
		rows.add_child(_prospect_row(p, "Scout", d.can_scout(p), func():
			_scout_and_toast(prospect_ref)
			hub.replace("Scouting", scouting)))
	v.add_child(rows)
	return v


func prospect(p: Prospect) -> Control:
	var d := _season().draft
	var s := p.soldier
	var v := _vbox(14)
	var drafted := ""
	if not p.is_available():
		drafted = "   -   [color=#f59e0b]Drafted by %s, pick %d[/color]" % [UiKit.esc(p.drafted_by.name), p.pick_number]
	v.add_child(UiKit.rich("[font_size=30][color=white]%s[/color][/font_size]   age %d  -  %s prospect%s\nProjected: [color=#f59e0b]%s[/color]   -   Scouted %d / %d   -   Potential: unknown   -   [color=#38bdf8]%d scout points[/color] available" % [
		UiKit.esc(s.full_name()), s.age, Scheme.ROLE_NAMES[p.listed_role], drafted, Draft.projection_text(p.projected_rank), p.points,
		Draft.MAX_POINTS_PER_PROSPECT, d.scout_points], 16))
	var actions := _row()
	var b := UiKit.button("Scout (1 point)", func():
		_scout_and_toast(p)
		hub.replace(s.full_name(), func(): return prospect(p)))
	b.disabled = not d.can_scout(p)
	actions.add_child(b)
	v.add_child(actions)
	v.add_child(_section("SCOUTING REPORT  -  highlighted grades are where his true rating could be"))
	v.add_child(_grade_legend())
	for g in Stats.GROUP_ORDER:
		var times: int = p.scouts.get(g, 0)
		var w: Variant = p.reveals.get(g)
		var head := UiKit.label("%s  -  %s" % [Stats.GROUP_LABELS[g].to_upper(),
			"not scouted" if w == null else ("scouted %d time%s" % [times, "" if times == 1 else "s"])], 15, UiKit.MUTED)
		v.add_child(head)
		var ladder := _row(6)
		for t in Draft.TIER_COUNT:
			var inside: bool = w != null and t >= (w as Vector2i).x and t <= (w as Vector2i).y
			var chip := UiKit.panel(TIER_COLORS[t].darkened(0.55) if inside else UiKit.PANEL, 6)
			chip.custom_minimum_size = Vector2(170, 34)
			var l := UiKit.label(Draft.tier_name(g, t), 15, Color.WHITE if inside else UiKit.MUTED)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip.add_child(l)
			ladder.add_child(chip)
		v.add_child(ladder)
	return v


## Called after every draft-room pick: once the draft ends, AI teams cut down to the roster limit.
func _after_pick() -> void:
	var s := _season()
	if s.draft.is_complete():
		for t in s.league.teams:
			if not t.user_controlled:
				t.cut_to_limit()


func draft_room() -> Control:
	var s := _season()
	var d := s.draft
	var user := s.user_team()
	var v := _vbox(12)
	if not d.is_started():
		v.add_child(UiKit.label("The %d draft is held after the Final." % d.year, 22, Color.WHITE))
		var rules := UiKit.label("%d rounds, snake order: teams that missed the playoffs pick first, the champion picks last. After the draft every team cuts down to %d soldiers. Use your weekly scout points until then." % [
			Draft.ROUNDS, Team.ROSTER_SIZE], 15, UiKit.MUTED)
		rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(rules)
		v.add_child(UiKit.button("Go to Scouting", hub.open_scouting))
		return v
	var refresh := func(): hub.replace("Draft Room", draft_room)
	if not d.is_complete():
		var t := d.on_the_clock()
		var head := "[font_size=24][color=%s]%s[/color][/font_size]   Round %d  -  Pick %d of %d" % [
			"#f59e0b" if t.user_controlled else "white",
			"YOU ARE ON THE CLOCK" if t.user_controlled else ("On the clock: " + UiKit.esc(t.name)),
			d.round_of(d.next_pick), d.next_pick + 1, d.order.size()]
		v.add_child(UiKit.rich(head, 16))
		var actions := _row()
		if t.user_controlled:
			actions.add_child(UiKit.button("Auto-pick for me", func():
				var p := d.ai_pick()
				hub.app.toast("You select %s (%s)." % [p.soldier.full_name(), Scheme.ROLE_NAMES[p.listed_role]])
				_after_pick()
				refresh.call()))
		else:
			var user_left := false
			for i in range(d.next_pick, d.order.size()):
				if d.order[i] == user:
					user_left = true
			actions.add_child(UiKit.button("Sim to my pick" if user_left else "Sim rest of draft", func():
				var made := d.sim_to_user()
				hub.app.toast("%d picks made." % made.size())
				_after_pick()
				refresh.call()))
		actions.add_child(UiKit.button("Scouting", hub.open_scouting))
		actions.add_child(UiKit.button("Mock Draft", hub.open_mock_draft))
		v.add_child(actions)
		if t.user_controlled:
			v.add_child(_filter_row("Draft Room", draft_room))
			var avail := _by_projection(_filtered(d.available()))
			v.add_child(_section("AVAILABLE PROSPECTS  -  by projected pick"))
			var rows := _vbox(4)
			rows.add_child(_prospect_header())
			for p in avail:
				var pick := p
				rows.add_child(_prospect_row(p, "Draft", true, func():
					d.make_pick(pick)
					hub.app.toast("You select %s (%s)." % [pick.soldier.full_name(), Scheme.ROLE_NAMES[pick.listed_role]])
					_after_pick()
					refresh.call()))
			v.add_child(rows)
	elif user.is_over_roster_limit():
		var over := user.roster.size() - Team.ROSTER_SIZE
		v.add_child(UiKit.rich("[font_size=24][color=#ef4444]ROSTER CUTS[/color][/font_size]   Release %d more soldier%s to get down to %d." % [
			over, "" if over == 1 else "s", Team.ROSTER_SIZE], 16))
		var list: Array = user.roster.duplicate()
		list.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() < b.best_ovr())
		for so in list:
			var row := _row(12)
			var cut_ref: Soldier = so
			var rel := UiKit.button("Release", func():
				user.release(cut_ref)
				hub.app.toast("Released %s." % cut_ref.full_name())
				refresh.call(), 15)
			rel.custom_minimum_size.x = 120
			row.add_child(rel)
			var rookie := ""
			for p in d.picks():
				if p.soldier == so:
					rookie = "   -   ROOKIE (pick %d)" % p.pick_number
			var info := UiKit.button("%s   -   age %d   -   OVR %d   -   %s   -   POT %s%s" % [so.full_name(), so.age, so.best_ovr(),
				Scheme.ROLE_NAMES[Scheme.best_role(so.stats)], _grade(so), rookie], func():
					hub.open(cut_ref.full_name(), func(): return player(cut_ref)), 15)
			info.alignment = HORIZONTAL_ALIGNMENT_LEFT
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			v.add_child(row)
	else:
		v.add_child(UiKit.label("The %d draft is complete." % d.year, 22, Color.WHITE))
		v.add_child(UiKit.button("Start the %d season" % (s.year + 1), hub.advance, 18))

	v.add_child(_section("DRAFT ORDER"))
	var rows: Array = []
	var hl := {}
	var colors := {}
	var by_pick := {}
	for p in d.picks():
		by_pick[p.pick_number] = p
	for i in d.order.size():
		var team: Team = d.order[i]
		var p: Prospect = by_pick.get(i + 1)
		var sel := "-"
		var pos := ""
		var proj := ""
		if p != null:
			sel = p.soldier.full_name()
			pos = Scheme.ROLE_NAMES[p.listed_role]
			proj = Draft.projection_text(p.projected_rank)
		elif i == d.next_pick:
			sel = "ON THE CLOCK"
		rows.append([i + 1, team.name, d.round_of(i), sel, pos, proj])
		if team.user_controlled:
			hl[i] = team.color.darkened(0.6)
		if i == d.next_pick and not d.is_complete():
			colors[i] = {3: UiKit.ACCENT}
	v.add_child(UiKit.table(["PICK", "TEAM", "RD", "SELECTION", "POS", "PROJ"], rows, [50, 260, 40, 240, 110, 130], hl, colors,
		func(i: int):
			var p: Prospect = by_pick.get(i + 1)
			if p != null:
				hub.open(p.soldier.full_name(), func(): return prospect(p))))
	return v


func mock_draft() -> Control:
	var s := _season()
	var d := s.draft
	var v := _vbox(12)
	var basis := "the real draft order" if d.is_started() else "current standings"
	v.add_child(UiKit.rich("[font_size=22][color=white]%d MOCK DRAFT[/color][/font_size]     based on %s and the league's big board" % [d.year, basis], 16))
	var help := UiKit.label("Each team takes the best consensus prospect left, leaning toward its weakest position. On draft day teams' boards differ a little, so expect surprises - and the consensus can be wrong about a player.", 14, UiKit.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)
	var nav := _row()
	nav.add_child(UiKit.button("Scouting", hub.open_scouting, 15))
	nav.add_child(UiKit.button("Draft Room", hub.open_draft_room, 15))
	v.add_child(nav)
	var mock := d.mock(s.mock_pick_order())
	if mock.is_empty():
		v.add_child(UiKit.label("The draft is over.", 18))
		return v
	var rows: Array = []
	var hl := {}
	for i in mock.size():
		var e: Dictionary = mock[i]
		var team: Team = e["team"]
		var p: Prospect = e["prospect"]
		var need := " (need)" if Draft.need_bonus(team, p) > 0.0 else ""
		rows.append([e["pick"], team.name, (int(e["pick"]) - 1) / Season.TEAM_COUNT + 1,
			p.soldier.full_name(), Scheme.ROLE_NAMES[p.listed_role] + need, Draft.projection_text(p.projected_rank),
			"%d/%d" % [p.points, Draft.MAX_POINTS_PER_PROSPECT]])
		if team.user_controlled:
			hl[i] = team.color.darkened(0.6)
	v.add_child(UiKit.table(["PICK", "TEAM", "RD", "PROSPECT", "POS", "PROJ", "SCOUTED"], rows, [50, 240, 40, 220, 150, 120, 90], hl, {},
		func(i: int):
			var p: Prospect = mock[i]["prospect"]
			hub.open(p.soldier.full_name(), func(): return prospect(p))))
	return v


# --- awards / development ----------------------------------------------------------

func awards() -> Control:
	var s := _season()
	var v := _vbox(14)
	var latest: SeasonReview = s.review_history[-1] if not s.review_history.is_empty() else null
	if s.review == null:
		v.add_child(_section("%d AWARD RACE  -  awards and potential re-grades are handed out after the final" % s.year))
		v.add_child(_award_race())
	if latest != null:
		v.add_child(_section("%d AWARDS" % latest.year))
		var rows: Array = []
		var targets: Array = []
		for a in latest.awards:
			rows.append([a["award"], a["soldier"].full_name(), a["team"].abbrev if a["team"] != null else "-", a["line"]])
			targets.append(a["soldier"])
		v.add_child(_soldier_table(["AWARD", "SOLDIER", "TEAM", "SEASON"], rows, [200, 220, 70, 330], targets))
		v.add_child(_section("%d ALL-LEAGUE TEAM" % latest.year))
		rows = []
		targets = []
		for a in latest.all_league:
			rows.append([Scheme.ROLE_NAMES[a["role"]], a["soldier"].full_name(), a["team"].abbrev if a["team"] != null else "-", a["line"]])
			targets.append(a["soldier"])
		v.add_child(_soldier_table(["POS", "SOLDIER", "TEAM", "SEASON"], rows, [200, 220, 70, 330], targets))
		v.add_child(_section("%d POTENTIAL CHANGES  -  awards and outplaying your rating raise it; underperforming and age lower it" % latest.year))
		rows = []
		targets = []
		var colors := {}
		for c in latest.potential_changes:
			var so: Soldier = c["soldier"]
			colors[rows.size()] = {3: potential_color(c["from"]), 4: potential_color(c["to"])}
			rows.append([so.full_name(), c["team"].abbrev if c["team"] != null else "-", so.age,
				Soldier.POTENTIAL_LETTERS[c["from"]], Soldier.POTENTIAL_LETTERS[c["to"]], ", ".join(c["reasons"])])
			targets.append(so)
		if rows.is_empty():
			v.add_child(UiKit.label("No changes.", 15, UiKit.MUTED))
		else:
			v.add_child(_soldier_table(["SOLDIER", "TEAM", "AGE", "FROM", "TO", "WHY"], rows, [220, 70, 50, 60, 60, 380], targets, colors))
	if not s.aging_report.is_empty():
		v.add_child(_section("AGING  -  declines at the start of the %d season (groups decline after their peak age)" % s.year))
		var rows: Array = []
		var targets: Array = []
		for r in s.aging_report:
			var so: Soldier = r["soldier"]
			var parts: PackedStringArray = []
			for g in r["changes"]:
				parts.append("%s %d" % [Stats.GROUP_LABELS[g], r["changes"][g]])
			rows.append([so.full_name(), r["team"].abbrev, r["age"], ", ".join(parts)])
			targets.append(so)
		v.add_child(_soldier_table(["SOLDIER", "TEAM", "AGE", "DECLINE"], rows, [220, 70, 50, 480], targets))
	if s.review_history.size() > 1:
		v.add_child(_section("PAST MVPs"))
		var rows: Array = []
		var targets: Array = []
		for i in range(s.review_history.size() - 1, -1, -1):
			var rev: SeasonReview = s.review_history[i]
			if rev.awards.is_empty():
				continue
			rows.append([rev.year, rev.awards[0]["soldier"].full_name(), rev.awards[0]["line"]])
			targets.append(rev.awards[0]["soldier"])
		v.add_child(_soldier_table(["YEAR", "MVP", "SEASON"], rows, [70, 220, 330], targets))
	return v


func _award_race() -> Control:
	var all := season_totals()
	var most := 0
	for t in all:
		most = maxi(most, t["matches"])
	var rows := all.filter(func(t): return t["matches"] >= maxi(1, ceili(most / 2.0)))
	rows.sort_custom(func(a, b): return a["impact"] / a["matches"] > b["impact"] / b["matches"])
	rows = rows.slice(0, 8)
	if rows.is_empty():
		return UiKit.label("No matches played yet.", 15, UiKit.MUTED)
	var cells: Array = []
	var targets: Array = []
	for i in rows.size():
		var t: Dictionary = rows[i]
		cells.append([i + 1, t["soldier"].full_name(), t["team"].abbrev, Scheme.ROLE_NAMES[t["role"]] if t["role"] >= 0 else "-",
			t["matches"], t["kills"], "%.0f" % (t["impact"] / t["matches"])])
		targets.append(t["soldier"])
	return _soldier_table(["#", "SOLDIER", "TEAM", "POS", "GP", "K", "IMP/G"], cells, [40, 220, 70, 110, 50, 50, 80], targets)


func _soldier_table(headers: Array, rows: Array, widths: Array, targets: Array, colors := {}) -> Control:
	var hl := {}
	for i in targets.size():
		var team := _team_of(targets[i])
		if team != null and team.user_controlled:
			hl[i] = team.color.darkened(0.6)
	return UiKit.table(headers, rows, widths, hl, colors, func(i: int):
		var so: Soldier = targets[i]
		if _team_of(so) != null:
			hub.open(so.full_name(), func(): return player(so)))


# --- data helpers --------------------------------------------------------------------

## Per-soldier totals for the current season: Array of dicts
## {soldier, team, matches, kills, deaths, assists, damage, shots, hits, headshots, mvps}.
func season_totals() -> Array:
	return SeasonReview.totals(_season())


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
	return s.potential_letter()

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
		rows.append([r.rank, r.team.name, r.wins, r.losses, "%.3f" % r.win_pct(), r.games_won, r.games_lost,
			("%+d" % r.game_diff()), ("%+d" % r.point_diff()), r.streak, r.last5 if r.last5 != "" else "-", r.team.team_ovr()])
		if r.team.user_controlled:
			hl[i] = r.team.color.darkened(0.6)
		colors[i] = {0: Color.WHITE if r.rank <= Season.PLAYOFF_TEAMS else UiKit.MUTED, 7: UiKit.GOOD if r.game_diff() > 0 else (UiKit.BAD if r.game_diff() < 0 else UiKit.TEXT)}
	v.add_child(UiKit.table(["#", "TEAM", "W", "L", "PCT", "GW", "GL", "G DIFF", "PTS DIFF", "STRK", "LAST 5", "OVR"], rows,
		[30, 260, 50, 50, 70, 50, 50, 70, 80, 60, 90, 50], hl, colors))
	v.add_child(UiKit.label("Matches are best of 3 (TDM, King of the Hill, TDM Sudden Death). Tiebreakers: head-to-head, then game differential, then TDM point differential.", 13, UiKit.MUTED))
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
			res = "%s %d-%d" % ["W" if m.winner() == team else "L", m.games_for(team), m.games_for(opp)]
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
			str(m.games_for(t)) if m.is_played() else s.record_text(t)]
	if m.is_played():
		var mvp := _soldier(m.result.mvp_id)
		body += "Final  -  %s  -  MVP %s" % [_games_brief(m.result), UiKit.esc(mvp.short_name()) if mvp else "-"]
	else:
		body += "Upcoming  -  %s" % m.stage
	var accent := m.home.color if not m.is_played() else m.winner().color
	return UiKit.tile("%s @ %s" % [m.away.abbrev, m.home.abbrev], body, Vector2(560, 150), accent,
		func():
			if m.is_played():
				hub.open("Match Recap", func(): return recap(m))
			else:
				hub.open("Match Preview", func(): return preview(m)))


## "TDM 50-41, KOTH 1:12-2:00, SD 4-2" (home side first).
func _games_brief(r: MatchResult) -> String:
	var parts: Array[String] = []
	for g in r.games:
		parts.append("%s %s" % [MatchEngine.MODE_SHORT[g["mode"]], MatchResult.game_score_text(g)])
	return ", ".join(parts)


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
			"%d-%d" % [mine.games_for(team), mine.games_for(mine.opponent_of(team))]], 18)
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
	if not played.is_empty():
		var potw := SeasonReview.player_of_week(s, (played[0] as ScheduledMatch).week)
		if not potw.is_empty():
			v.add_child(_potw_banner(potw, label))
	v.add_child(_section("AROUND THE LEAGUE  -  %s" % label.to_upper()))
	for m in played:
		v.add_child(_score_card(m))
	if s.champion and s.phase == Season.PHASE_OFFSEASON:
		v.add_child(UiKit.rich("[font_size=30][color=#f59e0b]%s are the %d champions![/color][/font_size]" % [UiKit.esc(s.champion.name), s.year], 18))
		var ret := s.retirements_in(s.year)
		if not ret.is_empty():
			v.add_child(UiKit.button("%d retirement%s announced - view" % [ret.size(), "" if ret.size() == 1 else "s"], hub.open_retirements, 15))
		v.add_child(UiKit.button("Re-sign your expiring players", hub.open_resign, 15))
	if not s.last_signings.is_empty():
		v.add_child(_section("FREE-AGENT SIGNINGS"))
		v.add_child(_signings_table(s.last_signings))
	v.add_child(_section("STANDINGS"))
	v.add_child(UiKit.label(hub._mini_standings().replace("[color=white]", "").replace("[color=#8b97ab]", "").replace("[/color]", ""), 16))
	return v


# --- match preview / recap -----------------------------------------------------------

## Pre-match screen for the user's fixture: both starting fives side by side, Watch or Sim.
func matchup(m: ScheduledMatch) -> Control:
	var s := _season()
	var v := _vbox(18)
	v.add_child(UiKit.label("%s  -  BEST OF 3:  TDM  -  KING OF THE HILL  -  TDM SUDDEN DEATH" % s.week_label(m.week).to_upper(), 16, UiKit.MUTED))
	var h := _row(20)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(_matchup_side(m.home, "HOME"))
	var vs := UiKit.label("VS", 54, UiKit.MUTED)
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vs.custom_minimum_size.x = 90
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(vs)
	h.add_child(_matchup_side(m.away, "AWAY"))
	v.add_child(h)
	var btns := _row(20)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	var watch := UiKit.button("WATCH", func(): hub.watch_match(m), 24)
	watch.custom_minimum_size = Vector2(260, 64)
	watch.tooltip_text = "Watch the match live on the tactical map."
	btns.add_child(watch)
	var sim := UiKit.button("SIM", hub.sim_week, 24)
	sim.custom_minimum_size = Vector2(260, 64)
	sim.tooltip_text = "Simulate the match instantly and go to the week's results."
	btns.add_child(sim)
	v.add_child(btns)
	v.add_child(UiKit.label("Go back (Esc) to adjust your lineup first; Advance again sims the match.", 14, UiKit.MUTED))
	return v


func _matchup_side(t: Team, tag: String) -> Control:
	var s := _season()
	var p := UiKit.panel(UiKit.PANEL, 14)
	p.custom_minimum_size.x = 560
	var col := _vbox(8)
	p.add_child(col)
	var head := _row(12)
	var sw := ColorRect.new()
	sw.color = t.color
	sw.custom_minimum_size = Vector2(10, 64)
	head.add_child(sw)
	var names := _vbox(2)
	names.add_child(UiKit.label(tag, 13, UiKit.MUTED))
	names.add_child(UiKit.label(t.name, 28, Color.WHITE))
	names.add_child(UiKit.label("Record %s   -   OVR %d" % [s.record_text(t), t.team_ovr()], 15, UiKit.MUTED))
	head.add_child(names)
	col.add_child(head)
	for sid in t.scheme.slot_ids():
		var so: Soldier = t.lineup[sid]
		var r := _row(12)
		r.add_child(Portrait.new(so, 56, t.color, t))
		var nv := _vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nv.add_child(UiKit.label(so.tag(), 20, Color.WHITE))
		nv.add_child(UiKit.label("%s  -  %s" % [sid, so.full_name()], 14, UiKit.MUTED))
		r.add_child(nv)
		var ovr: int = t.ovr_in_slot(so, sid)
		var o := UiKit.label(str(ovr), 26, UiKit.ovr_color(ovr))
		o.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(o)
		var pick := so
		col.add_child(_click_wrap(r, func(): open_player(pick), 64))
	return p


## Wraps `content` in a flat button (content ignores the mouse) so the whole row is clickable.
func _click_wrap(content: Control, cb: Callable, height: float) -> Button:
	var b := Button.new()
	UiKit.style_button(b, Color(0, 0, 0, 0), UiKit.ACCENT, 6)
	b.add_theme_stylebox_override("normal", UiKit.flat(Color(0, 0, 0, 0), 6))
	b.add_theme_stylebox_override("hover", UiKit.flat(UiKit.PANEL_HI, 6, 2, UiKit.ACCENT.darkened(0.3)))
	b.custom_minimum_size.y = height
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 4
	content.offset_right = -8
	_ignore_mouse(content)
	b.add_child(content)
	b.pressed.connect(cb)
	return b


func _ignore_mouse(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		if ch is Control:
			_ignore_mouse(ch)

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
		m.home.abbrev, m.games_for(m.home), m.games_for(m.away), m.away.abbrev,
		_season().week_label(m.week), UiKit.esc(m.winner().name)], 16)
	v.add_child(head)

	# Game-by-game strip (sudden death also lists its rounds).
	var strip := _row(10)
	for g in r.games:
		var winner_team: Team = r.teams[g["winner"]]
		var p := UiKit.panel(winner_team.color.darkened(0.45), 10)
		var col := _vbox(4)
		col.add_child(UiKit.label("GAME %d  -  %s" % [g["number"], MatchEngine.mode_name(g["mode"]).to_upper()], 13, UiKit.MUTED))
		col.add_child(UiKit.label("%s %s %s" % [m.home.abbrev, MatchResult.game_score_text(g), m.away.abbrev], 26, Color.WHITE))
		var sub := "%s win  -  %s" % [winner_team.abbrev, MatchEngine._fmt_secs(g["duration_s"])]
		if g["mode"] == MatchEngine.MODE_KOTH:
			sub = "%s win  -  hold time  -  %s" % [winner_team.abbrev, MatchEngine._fmt_secs(g["duration_s"])]
		col.add_child(UiKit.label(sub, 13, Color.WHITE))
		if not g["rounds"].is_empty():
			var rounds := _row(4)
			for rd in g["rounds"]:
				var rp := UiKit.panel(r.teams[rd["winner"]].color.darkened(0.2), 4)
				rp.add_child(UiKit.label("R%d %s" % [rd["number"], r.teams[rd["winner"]].abbrev], 12, Color.WHITE))
				rounds.add_child(rp)
			col.add_child(rounds)
		p.add_child(col)
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
			rows.append([line["slot"], (so.tag() if so else "?") + (" (MVP)" if sid == r.mvp_id else ""),
				line["kills"], line["deaths"], line["assists"], line.get("saves", 0), line.get("wipes", 0),
				MatchEngine._fmt_secs(line.get("hill_s", 0.0)), line.get("caps", 0), int(line["damage"]), "%d%%" % hit,
				line["headshots"], line["clutches"]])
		v.add_child(UiKit.table(["SLOT", "PLAYER", "K", "D", "A", "SAVES", "WIPES", "HILL", "CAPS", "DMG", "HIT%", "HS", "CLUTCH"], rows,
			[60, 220, 40, 40, 40, 56, 56, 56, 50, 60, 56, 40, 60], {}, colors))

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
	return _roster_table(false, null, func(): hub.replace("Roster", roster))


func progression() -> Control:
	return _roster_table(true, null, func(): hub.replace("Player Progression", progression))


## Column sort per table mode: mode -> [key, descending].
var _sort := {}
const DEFAULT_SORT := {&"roster": [&"slot", false], &"progress": [&"sp", true], &"fa": [&"ovr", true], &"contracts": [&"salary", true], &"drill": [&"ovr", true],
	&"team_stats": [&"kills", true], &"league_stats": [&"kills", true], &"prospects": [&"proj", true]}


func _sort_state(mode: StringName) -> Array:
	return _sort.get(mode, DEFAULT_SORT[mode])


func _set_sort(mode: StringName, key: StringName) -> void:
	var cur := _sort_state(mode)
	if cur[0] == key:
		_sort[mode] = [key, not cur[1]]
	else:
		# Names and lineup slots read best ascending; everything else best-first.
		_sort[mode] = [key, not (key in [&"name", &"slot", &"age", &"team", &"role"])]


func _sort_value(s: Soldier, key: StringName, team: Team) -> Variant:
	match key:
		&"name": return s.last_name + " " + s.first_name
		&"age": return s.age
		&"pot": return s.potential
		&"ovr": return _row_ovr(team, s)
		&"sp": return s.skill_points
		&"slot": return _slot_order(team, s) if team != null else 0
		&"morale": return s.morale
		&"fatigue": return s.fatigue
		&"asking": return Contracts.asking(s, Contracts.preferred_years(s))
		&"offers": return _season().fa.offers_for(s).size()
		&"salary": return s.contract.salary if s.contract != null else 0
		&"years": return s.contract.years if s.contract != null else -1
		&"total": return s.contract.remaining_value() if s.contract != null else 0
		&"dead": return Contracts.dead_money_if_released(s)
		&"role": return Scheme.ROLE_NAMES[Scheme.best_role(s.stats)]
		&"status":
			var camp := _season().camp
			return 2 if s.is_injured() else (1 if camp != null and camp.has_attended(s) else 0)
	if Stats.ALL.has(key):
		return s.stats[key]
	if Stats.GROUP_ORDER.has(key):
		return s.group_rating(key)
	return 0


func _sorted(list: Array, mode: StringName, team: Team) -> Array:
	var st := _sort_state(mode)
	var key: StringName = st[0]
	var desc: bool = st[1]
	var out := list.duplicate()
	out.sort_custom(func(a: Soldier, b: Soldier):
		var va: Variant = _sort_value(a, key, team)
		var vb: Variant = _sort_value(b, key, team)
		if va == vb:
			return a.id < b.id
		return va > vb if desc else va < vb)
	return out


## A sortable header row: one flat button per column; the active column shows an arrow.
func _sort_header(mode: StringName, cols: Array, rebuild: Callable) -> Control:
	var panel := PanelContainer.new()
	var sb := UiKit.flat(UiKit.PANEL_HI, 4)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.content_margin_left = 14
	panel.add_theme_stylebox_override("panel", sb)
	var hb := _row(PCOL_SEP)
	var st := _sort_state(mode)
	for c in cols:
		var key: StringName = c[2] if c.size() > 2 else &""
		var active: bool = key != &"" and st[0] == key
		var b := Button.new()
		b.text = c[0] + ((" ▼" if st[1] else " ▲") if active else "")
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(c[1], 30)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", UiKit.ACCENT if active else UiKit.MUTED)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
		b.add_theme_stylebox_override("focus", UiKit.flat(Color.TRANSPARENT, 4, 2, UiKit.ACCENT))
		for state in ["normal", "hover", "pressed"]:
			var f := UiKit.flat(Color.TRANSPARENT if state == "normal" else UiKit.LINE, 4)
			f.content_margin_left = 0
			f.content_margin_right = 0
			f.content_margin_top = 2
			f.content_margin_bottom = 2
			b.add_theme_stylebox_override(state, f)
		b.set_meta(&"skip_autofocus", true)
		if key == &"":
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", UiKit.MUTED)
			b.add_theme_stylebox_override("disabled", UiKit.flat(Color.TRANSPARENT, 4))
		else:
			b.pressed.connect(func():
				_set_sort(mode, key)
				rebuild.call())
		hb.add_child(b)
	panel.add_child(hb)
	return panel


func _roster_table(progress_view: bool, team: Team = null, rebuild := Callable()) -> Control:
	if team == null:
		team = _season().user_team()
	var mode := &"progress" if progress_view else &"roster"
	var v := _vbox()
	if progress_view:
		var with_sp := 0
		for s in team.roster:
			if Progression.can_level_up(s):
				with_sp += 1
		var actions := _row()
		var auto := UiKit.button("Auto-progress all (%d can level up)" % with_sp, func():
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
		actions.add_child(UiKit.label("Select a soldier to spend skill points on his ratings.", 15, UiKit.MUTED))
		v.add_child(actions)
	var list := _sorted(team.roster, mode, team)
	var pane := _player_pane()
	v.add_child(pane)
	if not list.is_empty():
		_fill_pane(pane, list[0], team)
	var table := _vbox(4)
	table.add_child(_sort_header(mode, _roster_cols(mode), rebuild if rebuild.is_valid() else func(): pass))
	for s in list:
		table.add_child(_roster_row(team, s, mode, pane))
	v.add_child(table)
	v.add_child(_potential_legend())
	return v


## Roster table columns: [header, width, sort key]. Rows carry name (with position underneath),
## age, potential, OVR (with the morale effect), one column per stat group, then per mode:
## roster = lineup slot / status; progress = SP + slot / status; fa = asking price + offers.
const RCOL_NAME := 210
const RCOL_AGE := 44
const RCOL_POT := 44
const RCOL_OVR := 84
const RCOL_GROUP := 96
const RCOL_SP := 44
const RCOL_MORALE := 70
const RCOL_STATUS := 150
const RCOL_CONTRACT := 110
const RCOL_OFFERS := 150


func _roster_cols(mode: StringName) -> Array:
	var cols := [["SOLDIER", RCOL_NAME, &"name"], ["AGE", RCOL_AGE, &"age"], ["POT", RCOL_POT, &"pot"], ["OVR", RCOL_OVR, &"ovr"]]
	for g in Stats.GROUP_ORDER:
		cols.append([Stats.GROUP_LABELS[g].to_upper(), RCOL_GROUP, g])
	match mode:
		&"progress":
			cols.append(["SP", RCOL_SP, &"sp"])
			cols.append(["SLOT / STATUS", RCOL_STATUS, &"slot"])
		&"fa":
			cols.append(["ASKING", RCOL_CONTRACT, &"asking"])
			cols.append(["OFFERS", RCOL_OFFERS, &"offers"])
		_:
			cols.append(["MORALE", RCOL_MORALE, &"morale"])
			cols.append(["SLOT / STATUS", RCOL_STATUS, &"slot"])
	return cols


## OVR shown in roster rows: at his lineup slot, else at his best position.
func _row_ovr(team: Team, s: Soldier) -> int:
	var slot := team.slot_of(s) if team != null else &""
	return team.ovr_in_slot(s, slot) if slot != &"" else s.best_ovr()


func _row_role(team: Team, s: Soldier) -> Scheme.Role:
	var slot := team.slot_of(s) if team != null else &""
	return team.scheme.role_for_slot(slot) if slot != &"" else Scheme.best_role(s.stats)


## "69 (-4)": a rating plus the morale effect on it (green boost, red penalty).
static func delta_bb(delta: int, size := 14) -> String:
	if delta == 0:
		return ""
	return " [font_size=%d][color=%s](%s%d)[/color][/font_size]" % [size, UiKit.hex(UiKit.GOOD if delta > 0 else UiKit.BAD), "+" if delta > 0 else "", delta]


func _ovr_cell(value: int, delta: int, width: int, size := 24) -> Control:
	var r := UiKit.rich("[color=%s]%d[/color]%s" % [UiKit.hex(UiKit.ovr_color(value)), value, delta_bb(delta)], size)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.custom_minimum_size.x = width
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


static func morale_color(m: float) -> Color:
	if m >= Soldier.MORALE_BOOST_START:
		return UiKit.GOOD
	if m >= Soldier.MORALE_NEUTRAL:
		return UiKit.INFO
	if m >= 60.0:
		return Color("#f97316")
	return UiKit.BAD


## One soldier row. `team` is null for free agents (mode "fa"), which open the offer page.
## Hovering or focusing a row shows that soldier in the pane above the table.
func _roster_row(team: Team, s: Soldier, mode: StringName, pane: Control = null) -> Control:
	var cols := _roster_cols(mode)
	var width := 28
	for c in cols:
		width += c[1] + PCOL_SEP
	var info := Button.new()
	UiKit.style_button(info, UiKit.PANEL, UiKit.ACCENT, 6)
	info.custom_minimum_size = Vector2(width, 54)
	if mode == &"fa":
		info.pressed.connect(func(): open_offer(s))
	else:
		info.pressed.connect(func(): open_player(s))
	if pane != null:
		var preview_fn := func(): _fill_pane(pane, s, team)
		info.mouse_entered.connect(preview_fn)
		info.focus_entered.connect(preview_fn)
	var hb := _row(PCOL_SEP)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 14
	hb.offset_right = -14
	hb.offset_top = 4
	hb.offset_bottom = -4
	info.add_child(hb)
	hb.add_child(_two_lines(s.display_name(), Color.WHITE, Scheme.ROLE_NAMES[Scheme.best_role(s.stats)], RCOL_NAME))
	hb.add_child(_big_cell(str(s.age), UiKit.TEXT, RCOL_AGE, 18))
	hb.add_child(_big_cell(s.potential_letter(), potential_color(s.potential), RCOL_POT))
	hb.add_child(_ovr_cell(_row_ovr(team, s), s.morale_ovr_delta(_row_role(team, s)), RCOL_OVR))
	for g in Stats.GROUP_ORDER:
		hb.add_child(_rating_cell(s.group_rating(g), RCOL_GROUP))
	if mode == &"fa":
		var yrs := Contracts.preferred_years(s)
		hb.add_child(_two_lines(Contracts.money(Contracts.asking(s, yrs)), Color.WHITE, "%d yr%s" % [yrs, "" if yrs == 1 else "s"], RCOL_CONTRACT, 16))
		var season := _season()
		var mine := season.fa.offer_of(season.user_team(), s)
		var n := season.fa.offers_for(s).size()
		hb.add_child(_two_lines("%d team%s" % [n, "" if n == 1 else "s"], Color.WHITE if n > 0 else UiKit.MUTED,
			("YOUR OFFER %s" % Contracts.money(mine["salary"])) if not mine.is_empty() else ("unsigned since %d" % s.fa_since if s.fa_since < season.year else ""),
			RCOL_OFFERS, 15))
		if not mine.is_empty():
			UiKit.style_button(info, UiKit.INFO.darkened(0.7), UiKit.ACCENT, 6)
		return info
	if mode == &"progress":
		hb.add_child(_big_cell(str(s.skill_points), UiKit.INFO if s.skill_points > 0 else UiKit.MUTED, RCOL_SP))
	else:
		hb.add_child(_big_cell(str(roundi(s.morale)), morale_color(s.morale), RCOL_MORALE, 18))
	var slot := team.slot_of(s)
	var slot_text := team.scheme.label_for_slot(slot) if slot != &"" else "Bench"
	hb.add_child(_two_lines(slot_text, Color.WHITE if slot != &"" else UiKit.MUTED, _status_text(s), RCOL_STATUS, 15))
	return info


## The big "selected player" pane over roster-style tables (Madden / 2K roster screen).
func _player_pane() -> PanelContainer:
	var pane := PanelContainer.new()
	var sb := UiKit.flat(UiKit.PANEL, 12, 1, UiKit.LINE)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	pane.add_theme_stylebox_override("panel", sb)
	pane.custom_minimum_size.y = 196
	return pane


func _fill_pane(pane: Control, s: Soldier, team: Team) -> void:
	if not is_instance_valid(pane) or pane.get_meta(&"sid", -1) == s.id:
		return
	pane.set_meta(&"sid", s.id)
	for c in pane.get_children():
		c.queue_free()
	var color := team.color if team != null else UiKit.MUTED
	var h := _row(26)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Portrait.new(s, 160, color, team))
	var mid := _vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(UiKit.label(s.full_name().to_upper(), 16, UiKit.ACCENT))
	mid.add_child(UiKit.label(("\"%s\"" % s.callsign.to_upper()) if s.callsign != "" else s.last_name.to_upper(), 40, Color.WHITE))
	var slot := team.slot_of(s) if team != null else &""
	var where := ("Starting " + team.scheme.label_for_slot(slot) if slot != &"" else "Bench") if team != null else "Free agent"
	mid.add_child(UiKit.label("%s   ·   AGE %d   ·   %s   ·   LVL %d" % [Scheme.ROLE_NAMES[Scheme.best_role(s.stats)].to_upper(), s.age, where.to_upper(), s.level], 15, UiKit.MUTED))
	var facts := _row(34)
	facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var role := _row_role(team, s)
	var ovr := _row_ovr(team, s)
	facts.add_child(_fact_box("OVR", "[color=%s]%d[/color]%s" % [UiKit.hex(UiKit.ovr_color(ovr)), ovr, delta_bb(s.morale_ovr_delta(role), 16)], false))
	facts.add_child(_fact_box("POT", "[color=%s]%s[/color]" % [UiKit.hex(potential_color(s.potential)), s.potential_letter()], false))
	if s.contract != null:
		facts.add_child(_fact_box("SALARY", Contracts.money(s.contract.salary), false))
		facts.add_child(_fact_box("CONTRACT", "EXPIRING" if s.contract.is_expiring() else "%d YR%s" % [s.contract.years, "" if s.contract.years == 1 else "S"], false))
	elif team == null and s.retired_year == 0:
		var yrs := Contracts.preferred_years(s)
		facts.add_child(_fact_box("ASKING", "%s x %d" % [Contracts.money(Contracts.asking(s, yrs)), yrs], false))
	facts.add_child(_fact_box("STATUS", "[color=%s]%s[/color]" % [UiKit.hex(UiKit.BAD if s.is_injured() else UiKit.GOOD),
		("OUT %d WK" % s.injury_weeks) if s.is_injured() else "HEALTHY"], false))
	mid.add_child(facts)
	h.add_child(mid)
	h.add_child(_ring_block("FATIGUE", s.fatigue, 100.0, fatigue_color(s.fatigue), str(roundi(s.fatigue)), Conditioning.status(s.fatigue)))
	h.add_child(_ring_block("MORALE", s.morale, 100.0, morale_color(s.morale), str(roundi(s.morale)), Soldier.morale_label(s.morale)))
	var groups := _vbox(4)
	groups.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	groups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for g in Stats.GROUP_ORDER:
		var gr := s.group_rating(g)
		var line := UiKit.rich("[color=#8b97ab]%s[/color]  [color=%s]%d[/color]" % [Stats.GROUP_LABELS[g].to_upper(), UiKit.hex(UiKit.ovr_color(gr)), gr], 15)
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.custom_minimum_size.x = 160
		groups.add_child(line)
	h.add_child(groups)
	pane.add_child(h)


func _fact_box(title: String, value_bb: String, boxed := true) -> Control:
	var p: Control = UiKit.panel(UiKit.PANEL_HI, 8) if boxed else MarginContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := _vbox(0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(UiKit.label(title, 12, UiKit.MUTED))
	var r := UiKit.rich("[color=white]%s[/color]" % value_bb, 22)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.custom_minimum_size.x = 90
	box.add_child(r)
	p.add_child(box)
	return p


func _ring_block(title: String, value: float, max_value: float, color: Color, text: String, sub: String, diameter := 84) -> Control:
	var box := _vbox(4)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.x = maxi(diameter, 100)
	var t := UiKit.label(title, 12, UiKit.MUTED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var ring := RingGauge.new(value, max_value, color, text, diameter)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ring)
	var l := UiKit.label(sub, 13, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


func _contract_cell(s: Soldier, width: int) -> Control:
	var c := s.contract
	if c == null:
		return _two_lines("-", UiKit.MUTED, "", width, 16)
	var yrs_text := "EXPIRING" if c.is_expiring() else "%d yr%s left" % [c.years, "" if c.years == 1 else "s"]
	return _two_lines(Contracts.money(c.salary), Color.WHITE, yrs_text + (" (R)" if c.rookie else ""), width, 16)


func _big_cell(text: String, color: Color, width: int, size := 24) -> Control:
	var l := UiKit.label(text, size, color)
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
		parts.append("[color=%s]%s[/color] %sx" % [UiKit.hex(potential_color(i)), Soldier.POTENTIAL_LETTERS[i], str(Progression.AGE_POTENTIAL_XP[0][1][i])])
	return UiKit.rich("[color=#8b97ab]POT = potential (XP gain, age 22 and under; it shrinks with age):[/color]   " + "   ".join(parts)
		+ "   [color=#8b97ab]Grades move each offseason with awards, performance and age.[/color]", 14)

func _slot_order(team: Team, s: Soldier) -> int:
	var slot := team.slot_of(s)
	var ids := team.scheme.slot_ids()
	return ids.find(slot) if slot != &"" else 100 + team.roster.find(s)


## Player page tabs (Madden player card): Overview, Ratings, Contract, Stats, DNA.
const PLAYER_TABS := ["Overview", "Ratings", "Contract", "Stats", "DNA", "Progression"]
var _player_tab := 0
## Stats tab view: true = this season match by match, false = career by season.
var _stats_season := true


func open_player(s: Soldier, tab := 0) -> void:
	_player_tab = tab
	hub.open(s.full_name(), func(): return player(s))


func _player_refresh(s: Soldier, tab := -1) -> void:
	if tab >= 0:
		_player_tab = tab
	hub.replace(s.full_name(), func(): return player(s))


func player(s: Soldier) -> Control:
	var team := _team_of(s)
	var v := _vbox(14)
	v.add_child(_player_header(s, team))
	var tabs := _row(6)
	for i in PLAYER_TABS.size():
		var idx := i
		var b := UiKit.button(PLAYER_TABS[i].to_upper(), func(): _player_refresh(s, idx), 15)
		b.custom_minimum_size = Vector2(140, 40)
		if i == _player_tab:
			UiKit.style_button(b, UiKit.ACCENT.darkened(0.45), Color.WHITE, 6)
		tabs.add_child(b)
	v.add_child(tabs)
	match _player_tab:
		1: v.add_child(_player_ratings(s, team))
		2: v.add_child(_player_contract(s, team))
		3: v.add_child(_player_stats(s))
		4: v.add_child(_player_dna(s, team))
		5: v.add_child(_player_progression(s))
		_: v.add_child(_player_overview(s, team))
	return v


func _player_header(s: Soldier, team: Team) -> Control:
	var color := team.color if team != null else UiKit.MUTED
	var pane := PanelContainer.new()
	var sb := UiKit.flat(UiKit.PANEL, 12, 1, UiKit.LINE)
	sb.border_width_left = 6
	sb.border_color = color
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	pane.add_theme_stylebox_override("panel", sb)
	var h := _row(24)
	h.add_child(Portrait.new(s, 132, color, team))
	var mid := _vbox(4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(UiKit.label(s.full_name().to_upper(), 18, UiKit.TEXT))
	var big := ("\"%s\"" % s.callsign.to_upper()) if s.callsign != "" else s.last_name.to_upper()
	var nm := UiKit.rich("[font_size=42][color=white]%s[/color][/font_size]" % UiKit.esc(big), 20)
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	mid.add_child(nm)
	var where := "Free agent"
	if s.retired_year > 0:
		where = "Retired %d" % s.retired_year
	elif team != null:
		var slot := team.slot_of(s)
		where = "%s  ·  %s" % [team.name, ("Starting " + team.scheme.label_for_slot(slot)) if slot != &"" else "Bench"]
	var yrs_in := maxi(1, _season().year - s.draft_year + 1) if s.draft_year > 0 else 0
	mid.add_child(UiKit.label("%s   ·   AGE %d   ·   %s   ·   LVL %d%s" % [Scheme.ROLE_NAMES[Scheme.best_role(s.stats)].to_upper(), s.age, where.to_upper(), s.level,
		("   ·   YEAR %d" % yrs_in) if yrs_in > 0 else ""], 15, UiKit.MUTED))
	if s.trade_request and team != null and s.retired_year == 0:
		mid.add_child(UiKit.label("⚑ TRADE REQUESTED", 15, UiKit.ACCENT))
	var awards := _awards_of(s)
	if not awards.is_empty():
		var a := UiKit.label("★ " + "   ★ ".join(awards.slice(0, 4)), 14, UiKit.ACCENT)
		a.clip_text = true
		a.custom_minimum_size.x = 400
		mid.add_child(a)
	h.add_child(mid)
	var role := _row_role(team, s)
	var ovr := team.ovr_in_slot(s, team.slot_of(s)) if team != null and team.slot_of(s) != &"" else s.best_ovr()
	h.add_child(_big_badge("OVR", "[color=%s]%d[/color]%s" % [UiKit.hex(UiKit.ovr_color(ovr)), ovr, delta_bb(s.morale_ovr_delta(role), 18)]))
	h.add_child(_big_badge("POT", "[color=%s]%s[/color]" % [UiKit.hex(potential_color(s.potential)), s.potential_letter()]))
	pane.add_child(h)
	return pane


func _big_badge(title: String, value_bb: String) -> Control:
	var p := UiKit.panel(UiKit.PANEL_HI, 10)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := _vbox(0)
	var t := UiKit.label(title, 13, UiKit.MUTED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var r := UiKit.rich("[center][font_size=40]%s[/font_size][/center]" % value_bb, 18)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.custom_minimum_size.x = 110
	box.add_child(r)
	p.add_child(box)
	return p


func _player_overview(s: Soldier, team: Team) -> Control:
	var editable := team != null and team.user_controlled
	var h := _row(22)
	# Left action rail.
	var rail := _vbox(8)
	rail.custom_minimum_size.x = 220
	var add_action := func(text: String, cb: Callable, enabled := true):
		var b := UiKit.button(text, cb, 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 46
		b.disabled = not enabled
		rail.add_child(b)
	if editable:
		add_action.call("View in Lineup", func(): hub.open("Lineup", lineup))
		add_action.call("Upgrade Ratings (%d SP)" % s.skill_points, func(): _player_refresh(s, 1))
		add_action.call("Contract", func(): _player_refresh(s, 2))
		add_action.call("Release", func(): _player_refresh(s, 2))
		var tr := _season().trades
		add_action.call("★ On the Block" if tr.block.has(s.id) else "Put on Trade Block", func():
			if tr.block.has(s.id):
				tr.block.erase(s.id)
			else:
				tr.block[s.id] = true
			_player_refresh(s, 0), Trades.tradeable(s))
		add_action.call("Shop in Trade Center", func(): open_trade(null, {}, Trades.player_asset(s)), Trades.tradeable(s))
	elif team == null and s.retired_year == 0:
		add_action.call("Make Offer", func(): open_offer(s))
		add_action.call("Ratings", func(): _player_refresh(s, 1))
	else:
		if team != null and s.retired_year == 0:
			add_action.call("Trade for Him", func(): open_trade(team, Trades.player_asset(s)), Trades.tradeable(s))
		add_action.call("Ratings", func(): _player_refresh(s, 1))
		add_action.call("Contract", func(): _player_refresh(s, 2))
	add_action.call("Season Stats", func(): _player_refresh(s, 3))
	h.add_child(rail)

	var body := _vbox(16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gauges := _row(18)
	gauges.add_child(_ring_block("MORALE", s.morale, 100.0, morale_color(s.morale), str(roundi(s.morale)), Soldier.morale_label(s.morale), 96))
	if s.is_injured():
		gauges.add_child(_ring_block("HEALTH", 0.0, 100.0, UiKit.BAD, "OUT", "%s, %d wk%s" % [s.injury_name, s.injury_weeks, "" if s.injury_weeks == 1 else "s"], 96))
	else:
		gauges.add_child(_ring_block("HEALTH", 100.0, 100.0, UiKit.GOOD, "100", "Healthy", 96))
	gauges.add_child(_ring_block("ENERGY", 100.0 - s.fatigue, 100.0, fatigue_color(s.fatigue), str(roundi(100.0 - s.fatigue)), Conditioning.status(s.fatigue), 96))
	var xp: Array = Progression.xp_progress(s)
	gauges.add_child(_ring_block("NEXT LEVEL", float(xp[0]), float(xp[1]), UiKit.INFO, "%d%%" % roundi(100.0 * xp[0] / maxf(1.0, xp[1])), "%sx XP" % str(Progression.xp_multiplier(s)), 96))
	var factors := _vbox(4)
	factors.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	factors.add_child(UiKit.label("MORALE FACTORS", 12, UiKit.MUTED))
	var reasons := Morale.factors(s, team)
	if reasons.is_empty():
		reasons.append("Nothing in particular")
	for r in reasons:
		factors.add_child(UiKit.label(r, 15, UiKit.GOOD if r.ends_with("(+)") else (UiKit.BAD if r.ends_with("(-)") else UiKit.TEXT)))
	var steps := s.morale_steps()
	factors.add_child(UiKit.label("Morale effect: %s" % ("none (75-85 is neutral)" if steps == 0 else "%d stat%s %s" % [absi(steps), "" if absi(steps) == 1 else "s",
		"boosted" if steps > 0 else "lowered"]), 14, UiKit.MUTED))
	gauges.add_child(factors)
	body.add_child(gauges)

	body.add_child(_section("POSITION OVR"))
	var cur_role := _row_role(team, s)
	var ovrs := _row(12)
	for r in Scheme.ROLE_NAMES:
		var o := s.ovr_at_role(r)
		var p := UiKit.panel(UiKit.ACCENT.darkened(0.6) if r == cur_role else UiKit.PANEL_HI, 10)
		var box := _vbox(0)
		box.add_child(UiKit.label(Scheme.ROLE_NAMES[r].to_upper(), 13, UiKit.MUTED))
		var rt := UiKit.rich("[font_size=30][color=%s]%d[/color][/font_size]%s" % [UiKit.hex(UiKit.ovr_color(o)), o, delta_bb(s.morale_ovr_delta(r), 16)], 16)
		rt.autowrap_mode = TextServer.AUTOWRAP_OFF
		rt.custom_minimum_size.x = 140
		box.add_child(rt)
		p.add_child(box)
		ovrs.add_child(p)
	body.add_child(ovrs)

	body.add_child(_section("CORE ATTRIBUTES  -  (±n) = today's morale effect"))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var mods := s.morale_mods()
	for st in Stats.ALL:
		grid.add_child(_attr_tile(st, int(s.stats[st]), int(mods.get(st, 0))))
	body.add_child(grid)
	h.add_child(body)
	return h


func _attr_tile(st: StringName, value: int, delta: int) -> Control:
	var p := UiKit.panel(UiKit.PANEL_HI, 8)
	p.custom_minimum_size.x = 132
	var box := _vbox(4)
	box.add_child(UiKit.label(Stats.LABELS[st].to_upper(), 11, UiKit.MUTED))
	var r := UiKit.rich("[font_size=26][color=white]%d[/color][/font_size]%s" % [value, delta_bb(delta, 15)], 16)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(r)
	var bar := ProgressBar.new()
	bar.max_value = 99
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(100, 5)
	bar.add_theme_stylebox_override("background", _bar_style(UiKit.LINE))
	bar.add_theme_stylebox_override("fill", _bar_style(UiKit.ovr_color(value)))
	box.add_child(bar)
	p.add_child(box)
	return p


func _bar_style(c: Color) -> StyleBoxFlat:
	var sb := UiKit.flat(c, 3)
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	return sb


func _player_ratings(s: Soldier, team: Team) -> Control:
	var editable := team != null and team.user_controlled
	var role := _row_role(team, s)
	var v := _vbox(14)
	var bars := _row(30)
	var xp: Array = Progression.xp_progress(s)
	bars.add_child(_meter("XP", float(xp[0]), float(xp[1]), UiKit.INFO,
		"%d / %d  (+%d SP)  -  %sx XP from potential" % [xp[0], xp[1], Progression.SKILL_POINTS_PER_LEVEL, str(Progression.xp_multiplier(s))]))
	bars.add_child(UiKit.label("%d skill points   -   Training: %s" % [s.skill_points, Training.label(s.intensity)], 16, UiKit.INFO))
	v.add_child(bars)
	if editable:
		var actions := _row()
		var auto := UiKit.button("Auto-spend SP", func():
			Progression.auto_spend(s, role)
			_player_refresh(s), 15)
		auto.disabled = s.skill_points <= 0
		actions.add_child(auto)
		v.add_child(actions)
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
				_player_refresh(s), 13)
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
	return v


func _player_contract(s: Soldier, team: Team) -> Control:
	var season := _season()
	var v := _vbox(14)
	if s.retired_year > 0:
		v.add_child(UiKit.label("Retired after the %d season." % s.retired_year, 20, UiKit.MUTED))
		return v
	var facts := _row(12)
	if team == null:
		var yrs := Contracts.preferred_years(s)
		for item in [["STATUS", "[color=#14b8a6]FREE AGENT[/color]"], ["ASKING", "%s / yr" % Contracts.money(Contracts.asking(s, yrs))],
				["WANTS", "%d yr%s" % [yrs, "" if yrs == 1 else "s"]], ["MARKET VALUE", Contracts.money(Contracts.market_value(s))],
				["BIDDERS", str(season.fa.offers_for(s).size())]]:
			facts.add_child(_fact_box(item[0], item[1]))
		v.add_child(facts)
		var actions := _row()
		actions.add_child(UiKit.button("Make Offer", func(): open_offer(s), 16))
		v.add_child(actions)
		return v
	var c := s.contract
	if c == null:
		v.add_child(UiKit.label("No contract.", 18, UiKit.MUTED))
		return v
	var cy := season.cap_year()
	var dm := Contracts.dead_money_if_released(s)
	for item in [["SALARY", "%s / yr" % Contracts.money(c.salary)],
			["YEARS LEFT", "[color=#f59e0b]EXPIRING[/color]" if c.is_expiring() else str(c.years)],
			["REMAINING", Contracts.money(c.remaining_value())], ["SIGNED", str(c.signed_year)],
			["TYPE", "Rookie deal" if c.rookie else "Veteran"], ["MARKET VALUE", Contracts.money(Contracts.market_value(s))],
			["CAP SHARE", "%.1f%%" % (100.0 * c.salary / Contracts.SALARY_CAP)]]:
		facts.add_child(_fact_box(item[0], item[1]))
	v.add_child(facts)
	var effect := Morale.contract_effect(s)
	v.add_child(UiKit.label("Contract morale: %s" % ("feels underpaid (morale drops weekly)" if effect < 0.0 else ("happy with his pay" if effect > 0.0 else
		("rookie deal (no effect)" if c.rookie else "neutral"))), 15, UiKit.BAD if effect < 0.0 else (UiKit.GOOD if effect > 0.0 else UiKit.MUTED)))
	if not team.user_controlled:
		return v
	v.add_child(_section("ACTIONS"))
	var actions := _row(12)
	if c.is_expiring() and season.can_resign():
		actions.add_child(UiKit.button("Re-sign", hub.open_resign, 16))
	var min_roster := team.scheme.slot_ids().size()
	var confirming := _confirm_release == s
	var rel := UiKit.button(("Confirm release: %s dead money" % Contracts.money(dm)) if confirming else "Release", func():
		if _confirm_release != s:
			_confirm_release = s
			_player_refresh(s)
			return
		_confirm_release = null
		var charged := season.release_player(team, s)
		hub.app.toast("Released %s. %s dead money." % [s.full_name(), Contracts.money(charged)])
		hub.go_back(), 16)
	rel.disabled = team.roster.size() <= min_roster
	if confirming:
		UiKit.style_button(rel, UiKit.BAD.darkened(0.5), Color.WHITE, 8)
	actions.add_child(rel)
	if confirming:
		actions.add_child(UiKit.button("Cancel", func():
			_confirm_release = null
			_player_refresh(s), 16))
	v.add_child(actions)
	v.add_child(UiKit.label("Releasing leaves %d%% of his remaining salary (%s) on your %d cap as dead money. He becomes a free agent." % [
		roundi(Contracts.DEAD_MONEY_SHARE * 100), Contracts.money(dm), cy], 14, UiKit.MUTED))
	if rel.disabled:
		v.add_child(UiKit.label("You need at least %d players to field a lineup." % min_roster, 14, UiKit.BAD))
	return v


func _player_stats(s: Soldier) -> Control:
	var v := _vbox(12)
	var toggle := _row(6)
	for opt in [["SEASON", true], ["CAREER", false]]:
		var on: bool = opt[1]
		var b := UiKit.button(opt[0], func():
			_stats_season = on
			_player_refresh(s), 15)
		b.custom_minimum_size = Vector2(130, 36)
		if on == _stats_season:
			UiKit.style_button(b, UiKit.ACCENT.darkened(0.45), Color.WHITE, 6)
		toggle.add_child(b)
	v.add_child(toggle)
	v.add_child(_player_game_log(s) if _stats_season else _player_career(s))
	return v


## This season's matches, one row each, with the season total underneath.
func _player_game_log(s: Soldier) -> Control:
	var v := _vbox(12)
	var season: Season = hub.season
	var rows: Array = []
	var colors := {}
	for w in range(1, season.total_weeks() + 1):
		for m: ScheduledMatch in season.matches_for_week(w):
			if not m.is_played() or not m.result.box.has(s.id):
				continue
			var r: MatchResult = m.result
			var line: Dictionary = r.box[s.id]
			var idx: int = line["team"]
			var mine: Team = r.teams[idx]
			var opp: Team = r.teams[1 - idx]
			var d := line.duplicate()
			d["damage"] = roundi(line.get("damage", 0))
			d["mvps"] = 1 if r.mvp_id == s.id else 0
			var cells := _stat_line_cells(season.week_label(w), ("vs " if m.home == mine else "@ ") + opp.abbrev, d)
			var won := r.winner_index == idx
			cells[2] = "%s %d-%d" % ["W" if won else "L", r.score[idx], r.score[1 - idx]]
			colors[rows.size()] = {2: UiKit.GOOD if won else UiKit.BAD}
			rows.append(cells)
	v.add_child(_section("%d SEASON  -  MATCH BY MATCH" % season.year))
	if rows.is_empty():
		v.add_child(UiKit.label("No matches played this season yet.", 16, UiKit.MUTED))
		return v
	var hl := {}
	var tot: Dictionary = s.season_lines.get(season.year, {})
	if not tot.is_empty():
		var cells := _stat_line_cells("SEASON", tot.get("team", ""), tot)
		cells[2] = "%d GP" % int(tot.get("matches", 0))
		rows.append(cells)
		hl[rows.size() - 1] = UiKit.ACCENT.darkened(0.7)
	v.add_child(UiKit.table(["MATCH", "OPP", "RESULT", "K", "D", "A", "K/D", "SAVES", "WIPES", "HILL", "CAPS", "DMG", "HS%", "ACC%", "MVP"], rows,
		[130, 80, 80, 50, 50, 50, 56, 60, 60, 70, 50, 80, 56, 60, 50], hl, colors))
	return v


func _player_career(s: Soldier) -> Control:
	var v := _vbox(12)
	var years: Array = s.season_lines.keys()
	years.sort()
	years.reverse()
	var rows: Array = []
	for y in years:
		rows.append(_stat_line_cells(str(y), s.season_lines[y].get("team", ""), s.season_lines[y]))
	var hl := {}
	rows.append(_stat_line_cells("CAREER", "", s.career))
	hl[rows.size() - 1] = UiKit.ACCENT.darkened(0.7)
	v.add_child(_section("SEASON BY SEASON"))
	if years.is_empty():
		v.add_child(UiKit.label("No matches played yet.", 16, UiKit.MUTED))
	v.add_child(UiKit.table(["SEASON", "TEAM", "GP", "K", "D", "A", "K/D", "SAVES", "WIPES", "HILL", "CAPS", "DMG", "HS%", "ACC%", "MVP"], rows,
		[80, 60, 44, 50, 50, 50, 56, 60, 60, 70, 50, 80, 56, 60, 50], hl))
	return v


func _stat_line_cells(label: String, team_abbrev: String, d: Dictionary) -> Array:
	var k := int(d.get("kills", 0))
	var de := int(d.get("deaths", 0))
	var hits := int(d.get("hits", 0))
	return [label, team_abbrev, d.get("matches", 0), k, de, d.get("assists", 0), "%.2f" % (float(k) / maxi(1, de)), d.get("saves", 0),
		d.get("wipes", 0), MatchEngine._fmt_secs(d.get("hill_s", 0)), d.get("caps", 0),
		d.get("damage", 0), "%d%%" % roundi(100.0 * int(d.get("headshots", 0)) / maxi(1, hits)),
		"%d%%" % roundi(100.0 * hits / maxi(1, int(d.get("shots", 0)))), d.get("mvps", 0)]


func _player_dna(s: Soldier, team: Team) -> Control:
	var v := _vbox(14)
	var facts := _row(12)
	facts.add_child(_fact_box("CALLSIGN", "\"%s\"" % s.callsign.to_upper() if s.callsign != "" else "-"))
	facts.add_child(_fact_box("ARCHETYPE", Stats.GROUP_LABELS[Callsigns.best_group(s)]))
	facts.add_child(_fact_box("POTENTIAL", "[color=%s]%s[/color]" % [UiKit.hex(potential_color(s.potential)), s.potential_letter()]))
	facts.add_child(_fact_box("DRAFTED", str(s.draft_year) if s.draft_year > 0 else "Original roster"))
	facts.add_child(_fact_box("MORALE", "[color=%s]%s[/color]" % [UiKit.hex(morale_color(s.morale)), Soldier.morale_label(s.morale)]))
	v.add_child(facts)
	v.add_child(_dna_panel(s, team))
	return v


## Motivations (strongest first), personality and relationship with his club.
func _dna_panel(s: Soldier, team: Team) -> Control:
	var d := s.get_dna()
	var v := _vbox(8)
	v.add_child(_section("WHAT DRIVES HIM  -  %s" % d.headline().to_upper()))
	for m in d.ranked():
		v.add_child(_meter(String(Dna.LABELS[m]).to_upper(), d.value(m), 99, UiKit.ACCENT if d.value(m) >= 60 else UiKit.ACCENT.darkened(0.45), "%d  -  %s" % [d.value(m), Dna.BLURBS[m]], 130))
	v.add_child(_section("PERSONALITY"))
	v.add_child(_meter("TEMPERAMENT", d.temperament, 99, UiKit.INFO, "%d  -  %s (low = takes hard bargaining and broken promises personally)" % [d.temperament, d.temperament_label()], 130))
	v.add_child(_meter("SAVVY", d.savvy, 99, UiKit.INFO, "%d  -  %s (high = sees through weak arguments, holds a higher floor)" % [d.savvy, d.savvy_label()], 130))
	v.add_child(_section("RELATIONSHIP"))
	v.add_child(_meter("TRUST", s.trust, 100, _dna_color(s.trust), "%d  -  %s%s" % [roundi(s.trust), Soldier.trust_label(s.trust),
		(" with " + team.name) if team != null else ""], 130))
	if not s.promise.is_empty():
		var g := int(s.promise["games"])
		v.add_child(UiKit.rich("[color=%s]STARTER PROMISE[/color]  -  %d season, with %s: started %d of %d games (needs %d%%)" % [UiKit.hex(UiKit.ACCENT),
			int(s.promise["year"]), s.promise["team"], int(s.promise["started"]), g, roundi(Soldier.PROMISE_SHARE * 100)], 16))
	if s.trade_request:
		v.add_child(UiKit.rich("[color=%s]TRADE REQUESTED[/color]  -  he wants out after a broken promise." % UiKit.hex(UiKit.BAD), 16))
	var tip := UiKit.label("DNA shapes contract talks and free agency: what he weighs when picking a team, which arguments land in a negotiation, and how he reacts to hardball. Trust rises with kept promises and fair talks, and carries over between seasons.", 14, UiKit.MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip)
	return v


func _dna_color(v: float) -> Color:
	if v >= 70:
		return UiKit.GOOD
	if v >= 45:
		return Color("#84cc16")
	if v >= 30:
		return UiKit.ACCENT
	return UiKit.BAD


## Every rating / potential change, newest first, grouped by season, with the reason.
func _player_progression(s: Soldier) -> Control:
	var v := _vbox(10)
	var tip := UiKit.label("Every rating change this soldier has had and why: level-ups from performance (skill points), training camp drills, age decline and end-of-season potential re-grades.", 15, UiKit.MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip)
	if s.history.is_empty():
		v.add_child(UiKit.label("No rating changes yet.", 16, UiKit.MUTED))
		return v
	var shown_year := -1
	for i in range(s.history.size() - 1, -1, -1):
		var e: Dictionary = s.history[i]
		if int(e["year"]) != shown_year:
			shown_year = int(e["year"])
			v.add_child(_section("%d SEASON" % shown_year))
		v.add_child(_progress_entry(e))
	return v


func _progress_entry(e: Dictionary) -> Control:
	var p := UiKit.panel(UiKit.PANEL, 8)
	var h := _row(16)
	p.add_child(h)
	var when := UiKit.label(String(e["when"]), 15, UiKit.MUTED)
	when.custom_minimum_size.x = 130
	h.add_child(when)
	var reason := UiKit.label(String(e["reason"]), 16, UiKit.TEXT)
	reason.custom_minimum_size.x = 300
	h.add_child(reason)
	var bits: PackedStringArray = []
	var changes: Dictionary = e["changes"]
	for st in Stats.ALL:
		var d := int(changes.get(st, 0))
		if d != 0:
			bits.append("[color=%s]%s %+d[/color]" % [UiKit.hex(UiKit.GOOD if d > 0 else UiKit.BAD), Stats.ABBREV[st], d])
	var pf := int(e["pot_from"])
	var pt := int(e["pot_to"])
	if pf != pt:
		bits.append("POT [color=%s]%s[/color] -> [color=%s]%s[/color]" % [UiKit.hex(potential_color(pf)), Soldier.POTENTIAL_LETTERS[pf],
			UiKit.hex(potential_color(pt)), Soldier.POTENTIAL_LETTERS[pt]])
	var chips := UiKit.rich("   ".join(bits), 15)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(chips)
	var of := int(e["ovr_from"])
	var ot := int(e["ovr_to"])
	var ovr_col := UiKit.GOOD if ot > of else (UiKit.BAD if ot < of else UiKit.MUTED)
	var ovr := UiKit.rich("OVR %d -> [color=%s]%d[/color]" % [of, UiKit.hex(ovr_col), ot], 15)
	ovr.custom_minimum_size.x = 130
	h.add_child(ovr)
	return p


## A labelled bar: "LABEL  [=====-----]  detail".
func _meter(label: String, value: float, max_value: float, color: Color, detail: String, label_w := 76) -> Control:
	var h := _row(10)
	var l := UiKit.label(label, 15, UiKit.MUTED)
	l.custom_minimum_size.x = label_w
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
	var val := UiKit.rich("[color=%s]%d[/color]%s" % [UiKit.hex(UiKit.ovr_color(s.stats[st])), s.stats[st], delta_bb(int(s.morale_mods().get(st, 0)), 13)], 16)
	val.autowrap_mode = TextServer.AUTOWRAP_OFF
	val.custom_minimum_size.x = 70
	cell.add_child(val)
	return cell


## Lineup: the Swing drawn as a formation (front = top). Frontmen up front, the Center behind
## and between them, the Flexes swung far out on each side. Click a slot then a bench card (or
## another slot) to swap; or pick a bench card first, then a slot.
const LINEUP_POS := {
	&"FM1": Vector2(300, 10), &"FM2": Vector2(560, 10), &"CTR": Vector2(430, 250),
	&"LFX": Vector2(20, 120), &"RFX": Vector2(840, 120),
}
const CARD := Vector2(170, 214)
var _lineup_slot: StringName = &""
var _lineup_bench: Soldier


func lineup() -> Control:
	var team := _season().user_team()
	var refresh := func(): hub.replace("Lineup", lineup)
	var h := _row(22)
	var field := Panel.new()
	var fsb := UiKit.flat(Color("#0d1a14"), 14, 1, UiKit.LINE)
	field.add_theme_stylebox_override("panel", fsb)
	field.custom_minimum_size = Vector2(1030, 480)
	# Simple field markings: halfway line and the trio's lane.
	var mid := ColorRect.new()
	mid.color = Color(1, 1, 1, 0.06)
	mid.position = Vector2(0, 236)
	mid.size = Vector2(1030, 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(mid)
	var front := UiKit.label("ENEMY SIDE  ▲", 12, Color(1, 1, 1, 0.25))
	front.position = Vector2(910, 12)
	field.add_child(front)
	for sid in team.scheme.slot_ids():
		var card := _lineup_card(team, team.lineup.get(sid), sid, refresh)
		card.position = LINEUP_POS.get(sid, Vector2.ZERO)
		field.add_child(card)
	h.add_child(field)

	var side := _vbox(12)
	side.custom_minimum_size.x = 280
	var p := UiKit.panel(UiKit.PANEL_HI, 10)
	var pb := _vbox(4)
	pb.add_child(UiKit.label("SCHEME", 12, UiKit.MUTED))
	pb.add_child(UiKit.label(team.scheme.display_name.to_upper(), 30, Color.WHITE))
	pb.add_child(UiKit.label("2 Frontmen · Center · 2 Flex", 14, UiKit.MUTED))
	p.add_child(pb)
	side.add_child(p)
	var o := UiKit.panel(UiKit.PANEL_HI, 10)
	var ob := _vbox(4)
	ob.add_child(UiKit.label("TEAM OVR", 12, UiKit.MUTED))
	ob.add_child(UiKit.label(str(team.team_ovr()), 44, UiKit.ovr_color(team.team_ovr())))
	o.add_child(ob)
	side.add_child(o)
	var best := UiKit.button("Generate Best Lineup", func():
		team.auto_lineup()
		_lineup_slot = &""
		_lineup_bench = null
		hub.app.toast("Best lineup set.")
		refresh.call(), 16)
	best.custom_minimum_size.y = 48
	side.add_child(best)
	var hint := "Pick a slot or bench player to swap."
	if _lineup_slot != &"":
		hint = "Swapping %s: pick a bench player or another slot." % team.scheme.label_for_slot(_lineup_slot)
	elif _lineup_bench != null:
		hint = "Placing %s: pick a slot." % _lineup_bench.tag()
	var hl := UiKit.label(hint, 15, UiKit.ACCENT if hint.begins_with("Sw") or hint.begins_with("Pl") else UiKit.MUTED)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(hl)
	if _lineup_slot != &"" or _lineup_bench != null:
		side.add_child(UiKit.button("Cancel", func():
			_lineup_slot = &""
			_lineup_bench = null
			refresh.call(), 15))
	var note := UiKit.label("Injured starters are swapped for the best healthy bench soldier when the week is played. (±n) = morale effect.", 13, UiKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(note)
	h.add_child(side)

	var v := _vbox(14)
	v.add_child(h)
	v.add_child(_section("BENCH"))
	var bench := HFlowContainer.new()
	bench.add_theme_constant_override("h_separation", 12)
	bench.add_theme_constant_override("v_separation", 12)
	for s in team.bench():
		bench.add_child(_lineup_card(team, s, &"", refresh))
	if team.bench().is_empty():
		bench.add_child(UiKit.label("No bench players.", 15, UiKit.MUTED))
	v.add_child(bench)
	return v


## Player card: portrait, callsign, name, OVR (at the slot, or best position on the bench), POT.
func _lineup_card(team: Team, s: Soldier, slot: StringName, refresh: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD
	b.size = CARD
	b.clip_contents = true
	var selected := (slot != &"" and slot == _lineup_slot) or (slot == &"" and s != null and s == _lineup_bench)
	var base := UiKit.ACCENT.darkened(0.55) if selected else UiKit.PANEL
	UiKit.style_button(b, base, UiKit.ACCENT, 12)
	b.pressed.connect(func(): _lineup_click(team, s, slot, refresh))
	var box := _vbox(2)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -8
	box.offset_top = 8
	box.offset_bottom = -8
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var top := UiKit.label(team.scheme.label_for_slot(slot).to_upper() if slot != &"" else "BENCH", 12, UiKit.ACCENT if slot != &"" else UiKit.MUTED)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(top)
	if s == null:
		var e := UiKit.label("EMPTY", 18, UiKit.MUTED)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(e)
		return b
	var portrait := Portrait.new(s, 72, UiKit.BAD if s.is_injured() else team.color, team)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(portrait)
	var tag := UiKit.label(s.tag(), 17, Color.WHITE)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.clip_text = true
	box.add_child(tag)
	var nm := UiKit.label(s.short_name(), 12, UiKit.MUTED)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	box.add_child(nm)
	var role := team.scheme.role_for_slot(slot) if slot != &"" else Scheme.best_role(s.stats)
	var o := s.ovr_at_role(role)
	var nums := UiKit.rich("[center][font_size=12][color=#8b97ab]OVR[/color][/font_size] [color=%s]%d[/color]%s   [font_size=12][color=#8b97ab]POT[/color][/font_size] [color=%s]%s[/color][/center]" % [
		UiKit.hex(UiKit.ovr_color(o)), o, delta_bb(s.morale_ovr_delta(role), 12), UiKit.hex(potential_color(s.potential)), s.potential_letter()], 20)
	nums.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(nums)
	var st := UiKit.label(("INJURED %dw" % s.injury_weeks) if s.is_injured() else ("%s · FAT %d" % [Scheme.ROLE_NAMES[Scheme.best_role(s.stats)].to_upper(), roundi(s.fatigue)]),
		11, UiKit.BAD if s.is_injured() else fatigue_color(s.fatigue))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.clip_text = true
	box.add_child(st)
	return b


func _lineup_click(team: Team, s: Soldier, slot: StringName, refresh: Callable) -> void:
	if slot != &"":
		if _lineup_bench != null:
			if _lineup_bench.is_injured():
				hub.app.toast("%s is injured." % _lineup_bench.full_name())
			else:
				team.assign(slot, _lineup_bench)
			_lineup_bench = null
		elif _lineup_slot == &"":
			_lineup_slot = slot
		elif _lineup_slot == slot:
			_lineup_slot = &""
		else:
			var other: Soldier = team.lineup.get(_lineup_slot)
			if other != null:
				team.assign(slot, other)
			_lineup_slot = &""
	elif s != null:
		if _lineup_slot != &"":
			if s.is_injured():
				hub.app.toast("%s is injured." % s.full_name())
			else:
				team.assign(_lineup_slot, s)
			_lineup_slot = &""
		else:
			_lineup_bench = null if _lineup_bench == s else s
	refresh.call()


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
	var foot := _row()
	if not season.can_train_user_team():
		foot.add_child(UiKit.label("Weekly training starts in Week 1. Set intensities now; they carry over.", 15, UiKit.MUTED))
	elif season.user_trained():
		foot.add_child(UiKit.label("This week's training is done. Changes apply next week.", 15, UiKit.GOOD))
		foot.add_child(UiKit.button("View Results", func(): hub.open("Training Results", training_results)))
	else:
		var go := UiKit.button("Confirm & Train", func():
			season.train_user_team()
			hub.replace("Training Results", training_results))
		go.custom_minimum_size = Vector2(240, 52)
		foot.add_child(go)
		foot.add_child(UiKit.label("Skipping it? Training still runs at these intensities when the week is played.", 14, UiKit.MUTED))
	v.add_child(foot)
	return v


## The user's weekly training results: XP gained, the new XP bar and any skill points earned.
func training_results() -> Control:
	var season := _season()
	var team := season.user_team()
	var report: Dictionary = season.user_training_report
	var v := _vbox()
	var total_xp := 0
	var total_sp := 0
	for r in report.values():
		total_xp += int(r["xp"])
		total_sp += int(r["points"])
	v.add_child(UiKit.label("%s training complete  -  +%d XP across the roster%s" % [season.week_label(season.week), total_xp,
		("  -  %d skill points earned" % total_sp) if total_sp > 0 else ""], 20, Color.WHITE))
	var list: Array = team.roster.filter(func(x: Soldier): return report.has(x.id))
	list.sort_custom(func(a: Soldier, b: Soldier): return _slot_order(team, a) < _slot_order(team, b))
	for so: Soldier in list:
		var r: Dictionary = report[so.id]
		var row := _row(16)
		var slot := team.slot_of(so)
		var name_l := UiKit.label("%s  %s" % [slot if slot != &"" else "BN", so.display_name()], 17, Color.WHITE)
		name_l.custom_minimum_size.x = 300
		row.add_child(name_l)
		var it_l := UiKit.label(Training.label(r["intensity"]), 15, UiKit.MUTED)
		it_l.custom_minimum_size.x = 100
		row.add_child(it_l)
		var xp_l := UiKit.label("+%d XP" % int(r["xp"]), 17, UiKit.INFO)
		xp_l.custom_minimum_size.x = 100
		row.add_child(xp_l)
		var prog: Array = Progression.xp_progress(so)
		row.add_child(_meter("XP", prog[0], prog[1], UiKit.INFO, "%d / %d" % [prog[0], prog[1]]))
		if int(r["points"]) > 0:
			row.add_child(UiKit.label("  LEVEL UP  +%d SP" % int(r["points"]), 17, UiKit.GOOD))
		if Progression.can_level_up(so):
			row.add_child(UiKit.label("  can level up", 15, UiKit.GOOD))
		v.add_child(_click_wrap(row, func(): open_player(so), 46))
	var bar := _row()
	bar.add_child(UiKit.button("Player Progression", func(): hub.open("Player Progression", progression)))
	v.add_child(bar)
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
	var lines := season_totals().filter(func(t): return t["team"] == team)
	if lines.is_empty():
		v.add_child(UiKit.label("No matches played yet this season.", 18, UiKit.MUTED))
		return v
	v.add_child(UiKit.label("Click a column to sort; click a soldier for his player card.", 15, UiKit.MUTED))
	v.add_child(_stats_table(lines, false, &"team_stats", func(): hub.replace(hub.page_stack[-1]["title"], team_stats)))
	return v


## Every soldier who has played this season, any team.
func league_stats() -> Control:
	var v := _vbox()
	var lines := season_totals()
	if lines.is_empty():
		v.add_child(UiKit.label("No matches played yet this season.", 18, UiKit.MUTED))
		return v
	v.add_child(UiKit.label("Every soldier who has played this season (%d). Click a column to sort; click a soldier for his player card." % lines.size(), 15, UiKit.MUTED))
	v.add_child(_stats_table(lines, true, &"league_stats", func(): hub.replace(hub.page_stack[-1]["title"], league_stats)))
	return v


static func _stat_value(t: Dictionary, key: StringName) -> Variant:
	match key:
		&"name":
			var s: Soldier = t["soldier"]
			return s.last_name + " " + s.first_name
		&"team": return (t["team"] as Team).abbrev if t["team"] != null else ""
		&"role": return Scheme.ROLE_NAMES[Scheme.best_role((t["soldier"] as Soldier).stats)]
		&"kd": return float(t["kills"]) / maxi(1, int(t["deaths"]))
		&"hit": return float(t["hits"]) / maxi(1, int(t["shots"]))
		&"hs": return float(t["headshots"]) / maxi(1, int(t["hits"]))
	return t.get(String(key), 0)


## Sortable season stat table (one row per soldier); rows open the player card.
func _stats_table(lines: Array, show_team: bool, mode: StringName, rebuild: Callable) -> Control:
	var cols: Array = [["PLAYER", 280, &"name"]]
	if show_team:
		cols.append(["TEAM", 56, &"team"])
	cols.append_array([["POS", 90, &"role"], ["GP", 40, &"matches"], ["K", 48, &"kills"], ["D", 48, &"deaths"], ["A", 48, &"assists"],
		["K/D", 54, &"kd"], ["SAVES", 58, &"saves"], ["DMG", 66, &"damage"], ["HS", 48, &"headshots"], ["HS%", 54, &"hs"],
		["HIT%", 56, &"hit"], ["WIPES", 58, &"wipes"], ["HILL", 64, &"hill_s"], ["CAPS", 50, &"caps"], ["MVP", 48, &"mvps"]])
	var st := _sort_state(mode)
	var key: StringName = st[0]
	var desc: bool = st[1]
	var list := lines.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary):
		var va: Variant = _stat_value(a, key)
		var vb: Variant = _stat_value(b, key)
		if va == vb:
			return (a["soldier"] as Soldier).id < (b["soldier"] as Soldier).id
		return va > vb if desc else va < vb)
	var rows: Array = []
	var colors := {}
	var user := _season().user_team()
	var hl := {}
	for i in list.size():
		var t: Dictionary = list[i]
		var so: Soldier = t["soldier"]
		var row: Array = [so.display_name()]
		if show_team:
			row.append(_stat_value(t, &"team"))
			if t["team"] == user:
				hl[i] = UiKit.ACCENT.darkened(0.78)
		row.append_array([_stat_value(t, &"role"), t["matches"], t["kills"], t["deaths"], t["assists"], "%.2f" % _stat_value(t, &"kd"),
			t["saves"], int(t["damage"]), t["headshots"], "%d%%" % roundi(100.0 * _stat_value(t, &"hs")),
			"%d%%" % roundi(100.0 * _stat_value(t, &"hit")), t["wipes"], MatchEngine._fmt_secs(t["hill_s"]), t["caps"], t["mvps"]])
		rows.append(row)
		colors[i] = {0: Color.WHITE}
	var headers: Array = []
	var widths: Array = []
	for c in cols:
		headers.append(c[0])
		widths.append(c[1])
	var table := UiKit.table(headers, rows, widths, hl, colors, func(i: int): open_player(list[i]["soldier"]))
	var old_header := table.get_child(0)
	table.remove_child(old_header)
	old_header.queue_free()
	var sort_header := _sort_header(mode, cols, rebuild)
	table.add_child(sort_header)
	table.move_child(sort_header, 0)
	return table


# --- league pages ------------------------------------------------------------------

func leaders() -> Control:
	var v := _vbox(18)
	var totals := season_totals()
	if totals.is_empty():
		v.add_child(UiKit.label("No matches played yet this season.", 18, UiKit.MUTED))
		return v
	var cats := [["KILLS", "kills"], ["ASSISTS", "assists"], ["SAVES", "saves"], ["DAMAGE", "damage"], ["MVP AWARDS", "mvps"], ["HEADSHOTS", "headshots"],
		["TEAM WIPES", "wipes", "WIPE"], ["HILL TIME", "hill_s", "TIME"], ["HILL CAPTURES", "caps", "CAPS"]]
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 20)
	flow.add_theme_constant_override("v_separation", 20)
	for cat in cats:
		var key: String = cat[1]
		var sorted := totals.duplicate()
		sorted.sort_custom(func(a, b): return a[key] > b[key])
		var rows: Array = []
		var hl := {}
		var targets: Array = []
		for i in mini(5, sorted.size()):
			var s: Soldier = sorted[i]["soldier"]
			var t: Team = sorted[i]["team"]
			if t.user_controlled:
				hl[i] = t.color.darkened(0.6)
			targets.append(s)
			rows.append([i + 1, s.tag(), t.abbrev, MatchEngine._fmt_secs(sorted[i][key]) if key == "hill_s" else str(int(sorted[i][key]))])
		var col := _vbox(6)
		col.add_child(_section(cat[0]))
		col.add_child(UiKit.table(["#", "PLAYER", "TM", cat[2] if cat.size() > 2 else cat[0].left(3)], rows, [24, 170, 50, 60], hl, {},
			func(i: int): open_player(targets[i])))
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
	var d := _season().draft
	if not d.news.is_empty():
		v.add_child(_section("PROSPECT WATCH  -  %d draft class" % d.year))
		var recent: Array = d.news.slice(maxi(0, d.news.size() - 6))
		recent.reverse()
		for n in recent:
			v.add_child(_story_panel(n, true))
		v.add_child(_section("RESULTS"))
	var th: Array = _season().trades.history
	if not th.is_empty():
		v.add_child(_section("TRADES"))
		for i in range(th.size() - 1, maxi(-1, th.size() - 9), -1):
			var tp := UiKit.panel(UiKit.PANEL, 8)
			tp.add_child(UiKit.rich(trade_headline(th[i]), 17))
			v.add_child(tp)
		v.add_child(_section("RESULTS"))
	var rel := _relations_news()
	if not rel.is_empty():
		v.add_child(_section("PLAYER RELATIONS"))
		for h in rel:
			var rp := UiKit.panel(UiKit.PANEL, 8)
			rp.add_child(UiKit.rich(h, 17))
			v.add_child(rp)
		v.add_child(_section("RESULTS"))
	if items.is_empty():
		v.add_child(UiKit.label("No news yet. Play some matches.", 18, UiKit.MUTED))
	for h in items:
		var p := UiKit.panel(UiKit.PANEL, 8)
		p.add_child(UiKit.rich(h, 17))
		v.add_child(p)
	return v


## Starter promises judged and talks that broke down, newest season first (BBCode).
func _relations_news() -> Array[String]:
	var s := _season()
	var out: Array[String] = []
	for i in range(s.promise_log.size() - 1, -1, -1):
		var p: Dictionary = s.promise_log[i]
		if int(p["year"]) < s.year - 1:
			break
		var so: Soldier = p["soldier"]
		var t: Team = p["team"]
		if p["kept"]:
			out.append("[color=#22c55e]PROMISE KEPT[/color]  -  %s (%s) started %d of %d games, as promised. His trust in the club grows." % [UiKit.esc(so.display_name()), t.abbrev, p["started"], p["games"]])
		else:
			out.append("[color=#ef4444]PROMISE BROKEN[/color]  -  %s (%s) was promised a starting job but started only %d of %d games.%s" % [UiKit.esc(so.display_name()), t.abbrev,
				p["started"], p["games"], " [color=#f59e0b]He has requested a trade.[/color]" if p["request"] else ""])
	for id in s.negotiations:
		var n: Negotiation = s.negotiations[id]
		if n.state == Negotiation.WALKED:
			out.append("[color=#ef4444]TALKS COLLAPSE[/color]  -  %s walked away from %s's table and will test free agency." % [UiKit.esc(n.soldier.display_name()), UiKit.esc(n.team.name)])
	return out


## Most recent first. Generated from match results.
func headlines(limit: int) -> Array[String]:
	var s := _season()
	var out: Array[String] = []
	for w in range(s.total_weeks(), 0, -1):
		var potw := SeasonReview.player_of_week(s, w)
		if not potw.is_empty():
			out.append("[color=#f59e0b]PLAYER OF THE WEEK[/color]  -  %s\n%s" % [s.week_label(w), potw_text(potw)])
			if out.size() >= limit:
				return out
		for m in s.matches_for_week(w):
			if not m.is_played():
				continue
			var win: Team = m.winner()
			var lose: Team = m.loser()
			var mvp := _soldier(m.result.mvp_id)
			var line: Dictionary = m.result.box.get(m.result.mvp_id, {})
			var verb := "edge" if m.games_for(lose) == 1 else "sweep"
			var txt := "[color=white]%s %s %s %d-%d[/color]  -  %s" % [UiKit.esc(win.name), verb, UiKit.esc(lose.name),
				m.games_for(win), m.games_for(lose), s.week_label(w)]
			if mvp and not line.is_empty():
				txt += "\n%s named MVP with %d kills and %d damage." % [UiKit.esc(mvp.full_name()), line["kills"], line["damage"]]
			if m.stage == Season.STAGE_FINAL:
				txt = "[color=#f59e0b]CHAMPIONS![/color] " + txt
			out.append(txt)
			if out.size() >= limit:
				return out
	return out


## "Jared "Ghost" Barrett (ATL) - 14 K, 4 A, 3 saves, 1:20 on the hill vs Denver" (BBCode).
func potw_text(p: Dictionary) -> String:
	var so: Soldier = p["soldier"]
	var team: Team = p["team"]
	var line: Dictionary = p["line"]
	var r: MatchResult = p["result"]
	var opp: Team = r.teams[1] if r.teams[0] == team else r.teams[0]
	var bits: PackedStringArray = ["%d K" % line["kills"], "%d A" % line["assists"]]
	if int(line.get("saves", 0)) > 0:
		bits.append("%d saves" % line["saves"])
	if int(line.get("wipes", 0)) > 0:
		bits.append("%d wipes" % line["wipes"])
	if float(line.get("hill_s", 0.0)) >= 1.0:
		bits.append("%s on the hill" % MatchEngine._fmt_secs(line["hill_s"]))
	bits.append("%d dmg" % line["damage"])
	return "[color=white]%s[/color] (%s)  -  %s vs %s" % [UiKit.esc(so.display_name()), team.abbrev, ", ".join(bits), UiKit.esc(opp.name)]


## Gold banner for the week's best performer; clicking opens his player card.
func _potw_banner(p: Dictionary, week_text: String) -> Control:
	var so: Soldier = p["soldier"]
	var team: Team = p["team"]
	var pane := PanelContainer.new()
	var normal := UiKit.flat(UiKit.ACCENT.darkened(0.8), 8, 2, UiKit.ACCENT.darkened(0.4))
	var hover := UiKit.flat(UiKit.ACCENT.darkened(0.7), 8, 2, UiKit.ACCENT)
	for sb: StyleBoxFlat in [normal, hover]:
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
	pane.add_theme_stylebox_override("panel", normal)
	pane.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var r := _row(18)
	var face := Portrait.new(so, 72, team.color, team)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(face)
	var col := _vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(UiKit.label("PLAYER OF THE WEEK  -  %s" % week_text.to_upper(), 14, UiKit.ACCENT))
	col.add_child(UiKit.label(so.tag(), 24, Color.WHITE))
	var line := UiKit.rich(potw_text(p), 15)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(line)
	r.add_child(col)
	pane.add_child(r)
	_ignore_mouse(r)
	pane.mouse_entered.connect(func(): pane.add_theme_stylebox_override("panel", hover))
	pane.mouse_exited.connect(func(): pane.add_theme_stylebox_override("panel", normal))
	pane.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			open_player(so))
	return pane


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


## Sortable prospect header (shared by Scouting and the Draft Room).
func _prospect_header(rebuild: Callable) -> Control:
	var cols := [["", PCOL_PORTRAIT], ["PROSPECT", PCOL_NAME, &"name"], ["PROJECTED", PCOL_PROJ, &"proj"]]
	for g in Stats.GROUP_ORDER:
		cols.append([Stats.GROUP_LABELS[g].to_upper(), PCOL_GROUP, g])
	return _sort_header(&"prospects", cols, rebuild)


## Sort value for a prospect column: a group sorts by the middle of its scouted window
## (unscouted groups sink to the bottom).
func _prospect_value(p: Prospect, key: StringName) -> Variant:
	match key:
		&"name": return p.soldier.last_name + " " + p.soldier.first_name
		&"proj": return p.projected_rank
	var w: Variant = p.reveals.get(key)
	if w == null:
		return -1.0
	return ((w as Vector2i).x + (w as Vector2i).y) / 2.0


## Prospects in the current prospect sort (default: the consensus big board).
func _sorted_prospects(list: Array[Prospect]) -> Array[Prospect]:
	var st := _sort_state(&"prospects")
	var key: StringName = st[0]
	var desc: bool = st[1]
	if key == &"proj":
		desc = not desc  # rank 1 is the best, so "best first" means ascending
	var out: Array[Prospect] = list.duplicate()
	out.sort_custom(func(a: Prospect, b: Prospect):
		var va: Variant = _prospect_value(a, key)
		var vb: Variant = _prospect_value(b, key)
		if va == vb:
			return a.projected_rank < b.projected_rank
		return va > vb if desc else va < vb)
	return out


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
	hb.add_child(Portrait.new(p.soldier, PCOL_PORTRAIT))
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
	var gs := _season().draft.scout(p)
	if gs.is_empty():
		hub.app.toast("Can't scout %s." % p.soldier.short_name())
		return
	var parts: PackedStringArray = []
	for g in gs:
		parts.append("%s: %s" % [Stats.GROUP_LABELS[g], Draft.window_text(g, p.reveals[g])])
	hub.app.toast("%s  %s" % [p.soldier.short_name(), "   ".join(parts)])


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
	var help := UiKit.label("Each point scouts 2 random stat groups: the first look at a group shows a 3-grade range, a second narrows it to 2. Once every group is down to 2 grades, each point pins 1 group to its exact grade. Up to %d points per prospect. Projected rounds are the league consensus - potential stays hidden until draft day." % Draft.MAX_POINTS_PER_PROSPECT, 14, UiKit.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)
	if _season().preseason_camp:
		v.add_child(UiKit.label("Scouting opens in Week 1. Your first %d points arrive when training camp ends." % Draft.POINTS_PER_WEEK, 18, UiKit.ACCENT))
	v.add_child(_grade_legend())
	var nav := _row()
	nav.add_child(UiKit.button("Mock Draft", hub.open_mock_draft, 15))
	nav.add_child(UiKit.button("Draft Room", hub.open_draft_room, 15))
	v.add_child(nav)
	if not d.news.is_empty():
		v.add_child(_section("PROSPECT NEWS  -  latest first  -  click a story for the prospect"))
		var recent: Array = d.news.slice(maxi(0, d.news.size() - 4))
		recent.reverse()
		for n in recent:
			v.add_child(_story_panel(n, true))
	v.add_child(_filter_row("Scouting", scouting))
	var list := _sorted_prospects(_filtered(d.prospects))
	v.add_child(_section("%d PROSPECTS  -  click a column to sort  -  click a row for his full report" % list.size()))
	var rows := _vbox(4)
	rows.add_child(_prospect_header(func(): hub.replace("Scouting", scouting)))
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
	if not p.is_available() and d.is_complete():
		actions.add_child(UiKit.button("Full profile (ratings revealed)", func(): open_player(s)))
	v.add_child(actions)
	var stories: Array = d.news_for(p)
	if not stories.is_empty():
		v.add_child(_section("PROSPECT NEWS  -  rumours, not guarantees"))
		for n in stories:
			v.add_child(_story_panel(n, false))
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


## Called after every draft-room pick. Roster cut-downs now happen when free agency opens.
func _after_pick() -> void:
	pass


## Draft clock: USER_PICK_SECONDS on your pick (then the best available is auto-picked), CPU
## teams pick after CPU_PICK_SECONDS. The clock only runs while the Draft Room is open.
const USER_PICK_SECONDS := 120.0
const CPU_PICK_SECONDS := 5.0
var _clock_pick := -1
var _clock_left := 0.0


static func clock_text(seconds: float) -> String:
	var whole := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [whole / 60, whole % 60]


func _draft_clock(d: Draft, refresh: Callable) -> Control:
	var t := d.on_the_clock()
	if _clock_pick != d.next_pick:
		_clock_pick = d.next_pick
		_clock_left = USER_PICK_SECONDS if t.user_controlled else CPU_PICK_SECONDS
	var lbl := UiKit.label(clock_text(_clock_left), 34, UiKit.ACCENT if t.user_controlled else UiKit.TEXT)
	lbl.custom_minimum_size.x = 110
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	lbl.add_child(timer)
	timer.timeout.connect(func():
		if _clock_pick != d.next_pick or d.is_complete():
			timer.stop()
			return
		_clock_left -= timer.wait_time
		lbl.text = clock_text(_clock_left)
		if t.user_controlled and _clock_left <= 10.0:
			lbl.add_theme_color_override("font_color", UiKit.BAD)
		if _clock_left > 0.0:
			return
		timer.stop()
		var p := d.ai_pick()
		if p != null and t.user_controlled:
			hub.app.toast("Time's up! Auto-picked %s (%s)." % [p.soldier.full_name(), Scheme.ROLE_NAMES[p.listed_role]])
		_after_pick()
		refresh.call_deferred())
	return lbl


func draft_room() -> Control:
	var s := _season()
	var d := s.draft
	var user := s.user_team()
	var v := _vbox(12)
	if not d.is_started():
		v.add_child(UiKit.label("The %d draft is held after the Final." % d.year, 22, Color.WHITE))
		var rules := UiKit.label("%d rounds, same order every round: teams that missed the playoffs pick first, the champion picks last. Rookies sign cheap %d-%d year deals. Use your weekly scout points until then." % [
			Draft.ROUNDS, Contracts.ROOKIE_YEARS[1], Contracts.ROOKIE_YEARS[0]], 15, UiKit.MUTED)
		rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(rules)
		v.add_child(UiKit.button("Go to Scouting", hub.open_scouting))
		return v
	if s.offseason_stage == Season.OFF_RESIGN:
		v.add_child(UiKit.label("Re-signing window: the draft starts when you advance.", 22, Color.WHITE))
		var rules := UiKit.label("Lock up your expiring players first - anyone you don't re-sign hits free agency after the draft. You pick in the order below.", 15, UiKit.MUTED)
		rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(rules)
		var nav := _row()
		nav.add_child(UiKit.button("Re-sign Players", hub.open_resign))
		nav.add_child(UiKit.button("Scouting", hub.open_scouting))
		nav.add_child(UiKit.button("Mock Draft", hub.open_mock_draft))
		v.add_child(nav)
		return v
	var refresh := func(): hub.replace("Draft Room", draft_room)
	if not d.is_complete():
		var t := d.on_the_clock()
		var head := "[font_size=24][color=%s]%s[/color][/font_size]   Round %d  -  Pick %d of %d" % [
			"#f59e0b" if t.user_controlled else "white",
			"YOU ARE ON THE CLOCK" if t.user_controlled else ("On the clock: " + UiKit.esc(t.name)),
			d.round_of(d.next_pick), d.next_pick + 1, d.order.size()]
		var head_row := _row(16)
		head_row.add_child(_draft_clock(d, refresh))
		var head_rt := UiKit.rich(head, 16)
		head_rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head_rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head_row.add_child(head_rt)
		v.add_child(head_row)
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
			actions.add_child(UiKit.button("Sim to next pick", func():
				var p := d.ai_pick()
				if p != null:
					hub.app.toast("%s select %s (%s)." % [t.name, p.soldier.full_name(), Scheme.ROLE_NAMES[p.listed_role]])
				_after_pick()
				refresh.call()))
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
			var avail := _sorted_prospects(_filtered(d.available()))
			v.add_child(_section("AVAILABLE PROSPECTS  -  click a column to sort"))
			var rows := _vbox(4)
			rows.add_child(_prospect_header(refresh))
			for p in avail:
				var pick := p
				rows.add_child(_prospect_row(p, "Draft", true, func():
					d.make_pick(pick)
					hub.app.toast("You select %s (%s)." % [pick.soldier.full_name(), Scheme.ROLE_NAMES[pick.listed_role]])
					_after_pick()
					refresh.call()))
			v.add_child(rows)
	else:
		return draft_recap(d)

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


## One prospect news story. With `clickable`, the panel opens the prospect.
func _story_panel(n: Dictionary, clickable: bool) -> Control:
	var p: Prospect = n["prospect"]
	var tag: Array = {&"rising": ["STOCK UP", UiKit.GOOD], &"falling": ["STOCK DOWN", UiKit.BAD]}.get(n["kind"], ["SCOUTING NOTE", UiKit.INFO])
	var txt := "[color=%s]%s[/color]   [color=#8b97ab]%s  -  %s, %s  -  proj. %s[/color]\n[color=white]%s[/color]" % [
		UiKit.hex(tag[1]), tag[0], _season().week_label(n["week"]), Scheme.ROLE_NAMES[p.listed_role], "age %d" % p.soldier.age,
		Draft.projection_text(p.projected_rank), UiKit.esc(n["text"])]
	if not clickable:
		var pn := UiKit.panel(UiKit.PANEL, 8)
		pn.add_child(UiKit.rich(txt, 16))
		return pn
	var b := Button.new()
	UiKit.style_button(b, UiKit.PANEL, UiKit.ACCENT, 8)
	b.custom_minimum_size = Vector2(1000, 64)
	var r := UiKit.rich(txt, 16)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.offset_left = 14
	r.offset_top = 8
	r.offset_right = -14
	b.add_child(r)
	b.pressed.connect(func(): hub.open(p.soldier.full_name(), func(): return prospect(p)))
	return b


const RECAP_GROUP_ABBREV := {Stats.ACCURACY: "ACC", Stats.HANDLING: "HND", Stats.PHYSICALITY: "PHY", Stats.MENTALITY: "MEN", Stats.OBJECTIVE: "OBJ", Stats.DURABILITY: "DUR"}


## Draft recap: every pick with ratings and potential revealed, plus each prospect's hidden
## archetype (phenom, blue chip, specialist) and steals/reaches versus his real value.
func draft_recap(d: Draft) -> Control:
	var s := _season()
	var user := s.user_team()
	var v := _vbox(12)
	var picks := d.picks()
	var mine := picks.filter(func(p: Prospect): return p.drafted_by == user)
	v.add_child(UiKit.rich("[font_size=26][color=white]%d DRAFT RECAP[/color][/font_size]     %d picks  -  all ratings and potential revealed  -  click a player for his full profile" % [
		d.year, picks.size()], 16))
	var nav := _row()
	if s.phase == Season.PHASE_OFFSEASON and s.offseason_stage == Season.OFF_DRAFT:
		nav.add_child(UiKit.button("Open free agency  >>", hub.advance, 18))
	nav.add_child(UiKit.button("Roster", func(): hub.open("Roster", roster), 18))
	v.add_child(nav)
	# Real value ranks (what the board should have been), for steals and reaches.
	var by_value: Array = picks.duplicate()
	by_value.sort_custom(func(a: Prospect, b: Prospect): return Draft.true_value(a) > Draft.true_value(b))
	var value_rank := {}
	for i in by_value.size():
		value_rank[by_value[i]] = i + 1
	var tag_of := func(p: Prospect) -> Array:
		var label := Draft.standout_label(p)
		if label != "":
			return [label, UiKit.ACCENT if p.phenom else (UiKit.GOOD if p.standout in [&"blue_chip", &"generational"] else UiKit.INFO)]
		var diff: int = p.pick_number - int(value_rank[p])
		if diff >= 6:
			return ["STEAL", UiKit.GOOD]
		if diff <= -8:
			return ["REACH", UiKit.BAD]
		return ["", UiKit.MUTED]
	if not mine.is_empty():
		var parts: PackedStringArray = []
		for p in mine:
			parts.append("%s (%s, %d OVR, %s POT)" % [p.soldier.full_name(), Scheme.ROLE_NAMES[p.listed_role], p.soldier.best_ovr(), p.soldier.potential_letter()])
		var yours := UiKit.label("YOUR CLASS:  " + ",   ".join(parts), 16, UiKit.ACCENT)
		yours.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(yours)
	var headers: Array = ["PICK", "RD", "TEAM", "PLAYER", "POS", "AGE", "OVR", "POT"]
	var widths: Array = [44, 30, 56, 200, 90, 40, 46, 40]
	for g in Stats.GROUP_ORDER:
		headers.append(RECAP_GROUP_ABBREV[g])
		widths.append(44)
	headers.append_array(["PROJ", "NOTE"])
	widths.append_array([96, 190])
	var rows: Array = []
	var colors := {}
	var hl := {}
	for i in picks.size():
		var p: Prospect = picks[i]
		var so := p.soldier
		var tag: Array = tag_of.call(p)
		var row: Array = [p.pick_number, d.round_of(p.pick_number - 1), p.drafted_by.abbrev, so.full_name(),
			Scheme.ROLE_NAMES[p.listed_role], so.age, so.best_ovr(), so.potential_letter()]
		var c := {6: UiKit.ovr_color(so.best_ovr()), 7: potential_color(so.potential)}
		for gi in Stats.GROUP_ORDER.size():
			var gr := so.group_rating(Stats.GROUP_ORDER[gi])
			row.append(gr)
			c[8 + gi] = UiKit.ovr_color(gr)
		row.append(Draft.projection_text(p.projected_rank))
		row.append(tag[0])
		c[row.size() - 1] = tag[1]
		rows.append(row)
		colors[i] = c
		if p.drafted_by == user:
			hl[i] = user.color.darkened(0.6)
	v.add_child(UiKit.table(headers, rows, widths, hl, colors, func(i: int): open_player(picks[i].soldier)))
	var legend := UiKit.label("BLUE CHIP = elite all-round talent.  SPECIALIST = one elite stat group.  PHENOM = plays every position well.  STEAL / REACH = picked well after / before his real value.", 14, UiKit.MUTED)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(legend)
	return v


# --- training camp -----------------------------------------------------------------

const DRILL_COLORS := {Stats.ACCURACY: Color("#f97316"), Stats.HANDLING: Color("#eab308"), Stats.PHYSICALITY: Color("#22c55e"),
	Stats.MENTALITY: Color("#a855f7"), Stats.OBJECTIVE: Color("#06b6d4"), Stats.DURABILITY: Color("#94a3b8")}


func training_camp() -> Control:
	var s := _season()
	var user := s.user_team()
	var camp := s.camp
	var v := _vbox(12)
	if camp == null:
		v.add_child(UiKit.label("Training camp runs each offseason, after free agency.", 22, Color.WHITE))
		return v
	var open := s.camp_open()
	var head := "[font_size=26][color=white]%d TRAINING CAMP[/color][/font_size]     " % (camp.year + 1)
	if open:
		head += "[color=#38bdf8]%d of %d drills left[/color]  -  one player per drill, one drill per player" % [camp.drills_left(user), Camp.DRILLS.size()]
	elif s.phase == Season.PHASE_OFFSEASON and s.offseason_stage != Season.OFF_DONE:
		head += "[color=#8b97ab]Opens after free agency.[/color]"
	else:
		head += "[color=#8b97ab]Camp is closed.[/color]"
	v.add_child(UiKit.rich(head, 16))
	var pools: PackedStringArray = []
	for i in range(Soldier.POTENTIAL_A, -1, -1):
		var r := Camp.pool_range(i)
		pools.append("[color=%s]%s[/color] %d-%d" % [UiKit.hex(potential_color(i)), Soldier.POTENTIAL_LETTERS[i], r[0], r[1]])
	v.add_child(UiKit.rich("[color=#8b97ab]Each drill gives the player a pool of rating points, spread at random over the group's stats (max +%d per stat). Pool by potential:[/color]  %s" % [
		Camp.MAX_STAT_GAIN, "   ".join(pools)], 14))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	for g in Camp.DRILLS:
		var info: Dictionary = Camp.DRILLS[g]
		var stats_txt := ", ".join(PackedStringArray(Stats.group_stats(g).map(func(x): return Stats.LABELS[x])))
		var res := camp.result_for(user, g)
		var body := "[color=#8b97ab]%s[/color]\n%s\n\n" % [Stats.GROUP_LABELS[g].to_upper(), UiKit.esc(info["blurb"])]
		var cb: Callable
		var badge := ""
		if not res.is_empty():
			var so: Soldier = res["soldier"]
			body += "[color=#22c55e]DONE[/color]  [color=white]%s[/color]  +%d pts\nOVR %d -> %d" % [UiKit.esc(so.short_name()), res["points"], res["ovr_before"], res["ovr_after"]]
			var gg: StringName = g
			cb = func(): hub.open(Camp.drill_name(gg), func(): return drill_result(gg))
			badge = "DONE"
		elif open:
			body += "[color=#38bdf8]Select a player >[/color]\n[color=#8b97ab]%s[/color]" % stats_txt
			var gg: StringName = g
			cb = func(): hub.open(Camp.drill_name(gg), func(): return drill_pick(gg))
		else:
			body += "[color=#8b97ab]%s[/color]" % stats_txt
			cb = func(): hub.app.toast("Training camp opens after free agency.")
		flow.add_child(UiKit.tile(info["name"], body, Vector2(300, 230), DRILL_COLORS[g], cb, badge))
	v.add_child(flow)
	# Other teams' camps, once they've run.
	var rows: Array = []
	var targets: Array = []
	for t in s.league.teams:
		if t == user:
			continue
		for g in camp.team_results(t):
			var r: Dictionary = camp.team_results(t)[g]
			var so: Soldier = r["soldier"]
			rows.append([t.abbrev, Camp.drill_name(g), so.full_name(), so.potential_letter(), "+%d" % r["points"], "%d -> %d" % [r["ovr_before"], r["ovr_after"]]])
			targets.append(so)
	if not rows.is_empty():
		v.add_child(_section("AROUND THE LEAGUE"))
		v.add_child(_soldier_table(["TEAM", "DRILL", "PLAYER", "POT", "POINTS", "OVR"], rows, [60, 200, 220, 50, 70, 100], targets))
	return v


## Pick who attends a drill: your roster with the group's current ratings.
func drill_pick(group: StringName) -> Control:
	var s := _season()
	var user := s.user_team()
	var v := _vbox(12)
	if s.camp == null:
		v.add_child(UiKit.label("Training camp runs each offseason, after free agency.", 22, Color.WHITE))
		return v
	var info: Dictionary = Camp.DRILLS[group]
	v.add_child(UiKit.rich("[font_size=26][color=white]%s[/color][/font_size]     %s drill  -  %s" % [
		UiKit.esc(info["name"]), Stats.GROUP_LABELS[group], UiKit.esc(info["blurb"])], 16))
	v.add_child(UiKit.label("Pick the soldier to send. Higher potential = a bigger point pool. Each soldier can attend one drill per camp, so soldiers who already went aren't listed.", 15, UiKit.MUTED))
	var members: Array = Stats.group_stats(group)
	var cols: Array = [["PLAYER", 220, &"name"], ["POS", 100, &"role"], ["AGE", 44, &"age"], ["OVR", 50, &"ovr"], ["POT", 44, &"pot"],
		[Stats.GROUP_LABELS[group].to_upper(), 100, group]]
	for st in members:
		cols.append([Stats.ABBREV[st], 50, st])
	cols.append(["STATUS", 220, &"status"])
	var headers: Array = []
	var widths: Array = []
	for c in cols:
		headers.append(c[0])
		widths.append(c[1])
	var list: Array = _sorted(user.roster.filter(func(so: Soldier): return not s.camp.has_attended(so)), &"drill", null)
	var rows: Array = []
	var colors := {}
	if list.is_empty():
		v.add_child(UiKit.label("Every soldier has already attended a drill this camp.", 16, UiKit.MUTED))
	for i in list.size():
		var so: Soldier = list[i]
		var why := s.camp_check(group, so)
		var row: Array = [so.full_name(), Scheme.ROLE_NAMES[Scheme.best_role(so.stats)], so.age, so.best_ovr(), so.potential_letter(),
			so.group_rating(group)]
		var c := {3: UiKit.ovr_color(so.best_ovr()), 4: potential_color(so.potential), 5: UiKit.ovr_color(so.group_rating(group))}
		for j in members.size():
			row.append(so.stats[members[j]])
			c[6 + j] = UiKit.ovr_color(so.stats[members[j]])
		if why == "":
			row.append("Available")
		else:
			row.append("Injured" if so.is_injured() else "Unavailable")
			c[row.size() - 1] = UiKit.BAD
		rows.append(row)
		colors[i] = c
	var table := UiKit.table(headers, rows, widths, {}, colors, func(i: int):
		var so: Soldier = list[i]
		var why := s.camp_check(group, so)
		if why != "":
			hub.app.toast(why)
			return
		_confirm_modal(_drill_confirm_card(group, so), "Send to %s" % Camp.drill_name(group), func():
			s.run_drill(group, so)
			hub.replace(Camp.drill_name(group), func(): return drill_result(group))))
	# Swap the static header for a clickable sort header (same column widths).
	var old_header := table.get_child(0)
	table.remove_child(old_header)
	old_header.queue_free()
	var sort_header := _sort_header(&"drill", cols, func(): hub.replace(hub.page_stack[-1]["title"], func(): return drill_pick(group)))
	table.add_child(sort_header)
	table.move_child(sort_header, 0)
	if not list.is_empty():
		var pane := _player_pane()
		_fill_pane(pane, list[0], user)
		v.add_child(pane)
		v.move_child(pane, 2)
		for i in list.size():
			var who: Soldier = list[i]
			var row_btn: Control = table.get_child(i + 1)
			var preview_fn := func(): _fill_pane(pane, who, user)
			row_btn.mouse_entered.connect(preview_fn)
			row_btn.focus_entered.connect(preview_fn)
	v.add_child(table)
	return v


## "Are you sure?" card for sending `so` to the `group` drill.
func _drill_confirm_card(group: StringName, so: Soldier) -> Control:
	var team := _season().user_team()
	var pool := Camp.pool_range(so.potential)
	var v := _vbox(14)
	v.add_child(UiKit.label("SEND TO %s?" % Camp.drill_name(group).to_upper(), 16, UiKit.ACCENT))
	var h := _row(22)
	h.add_child(Portrait.new(so, 150, team.color, team))
	var info := _vbox(8)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(UiKit.label(so.full_name().to_upper(), 15, UiKit.MUTED))
	info.add_child(UiKit.label(("\"%s\"" % so.callsign.to_upper()) if so.callsign != "" else so.last_name.to_upper(), 32, Color.WHITE))
	info.add_child(UiKit.label("%s  ·  AGE %d" % [Scheme.ROLE_NAMES[Scheme.best_role(so.stats)].to_upper(), so.age], 15, UiKit.MUTED))
	var facts := _row(30)
	facts.add_child(_fact_box("OVR", "[color=%s]%d[/color]" % [UiKit.hex(UiKit.ovr_color(so.best_ovr())), so.best_ovr()], false))
	facts.add_child(_fact_box("POT", "[color=%s]%s[/color]" % [UiKit.hex(potential_color(so.potential)), so.potential_letter()], false))
	facts.add_child(_fact_box("POINT POOL", "[color=#22c55e]%d-%d[/color]" % [pool[0], pool[1]], false))
	info.add_child(facts)
	h.add_child(info)
	v.add_child(h)
	var note := UiKit.label("The pool is spread at random over %s (max +%d per stat). He can't attend another drill this camp." % [
		Stats.GROUP_LABELS[group], Camp.MAX_STAT_GAIN], 14, UiKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 520
	v.add_child(note)
	return v


## A centered dialog over the whole hub with Confirm / Cancel. Clicking the backdrop cancels.
func _confirm_modal(content: Control, confirm_text: String, on_confirm: Callable) -> Control:
	var overlay := Control.new()
	overlay.name = "ConfirmModal"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 50
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var sb := UiKit.flat(UiKit.PANEL, 14, 2, UiKit.ACCENT)
	sb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := _vbox(18)
	v.add_child(content)
	var buttons := _row(14)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var cancel := UiKit.button("Cancel", func(): overlay.queue_free())
	var ok := UiKit.button(confirm_text, func():
		overlay.queue_free()
		on_confirm.call())
	ok.custom_minimum_size.x = 240
	buttons.add_child(cancel)
	buttons.add_child(ok)
	v.add_child(buttons)
	panel.add_child(v)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			overlay.queue_free())
	hub.add_child(overlay)
	ok.grab_focus.call_deferred()
	return overlay


## What the drill did: each stat before -> after.
func drill_result(group: StringName) -> Control:
	var s := _season()
	var res := s.camp.result_for(s.user_team(), group) if s.camp != null else {}
	var v := _vbox(14)
	if res.is_empty():
		v.add_child(UiKit.label("Nobody has run this drill yet.", 20))
		return v
	var so: Soldier = res["soldier"]
	var card := UiKit.panel(UiKit.PANEL, 12)
	var h := _row(24)
	h.add_child(Portrait.new(so, 150, s.user_team().color, s.user_team()))
	var info := _vbox(8)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(UiKit.rich("[font_size=14][color=#8b97ab]%s  -  DRILL COMPLETE[/color][/font_size]\n[font_size=32][color=white]%s[/color][/font_size]\n%s  -  age %d  -  [color=%s]%s potential[/color]" % [
		Camp.drill_name(group).to_upper(), UiKit.esc(so.full_name()), Scheme.ROLE_NAMES[Scheme.best_role(so.stats)], so.age,
		UiKit.hex(potential_color(so.potential)), so.potential_letter()], 16))
	var ovr_delta: int = res["ovr_after"] - res["ovr_before"]
	info.add_child(UiKit.rich("[font_size=26][color=#22c55e]+%d rating points[/color][/font_size]     OVR [color=white]%d[/color] -> [color=%s]%d[/color]%s" % [
		res["points"], res["ovr_before"], UiKit.hex(UiKit.ovr_color(res["ovr_after"])), res["ovr_after"],
		("  [color=#22c55e](+%d)[/color]" % ovr_delta) if ovr_delta > 0 else ""], 18))
	h.add_child(info)
	card.add_child(h)
	v.add_child(card)
	v.add_child(_section("RATINGS BOOST  -  %s" % Stats.GROUP_LABELS[group].to_upper()))
	for st in res["gains"]:
		var before: int = res["before"][st]
		var gain: int = res["gains"][st]
		var line := _row(14)
		line.add_child(_big_cell(Stats.LABELS[st], Color.WHITE, 220, 18))
		line.add_child(_big_cell(str(before), UiKit.ovr_color(before), 50, 22))
		line.add_child(_big_cell("->", UiKit.MUTED, 30, 18))
		line.add_child(_big_cell(str(before + gain), UiKit.ovr_color(before + gain), 50, 22))
		line.add_child(_big_cell(("+%d" % gain) if gain > 0 else "-", UiKit.GOOD if gain > 0 else UiKit.MUTED, 50, 22))
		var bar := _row(0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var base := ColorRect.new()
		base.color = UiKit.ovr_color(before).darkened(0.3)
		base.custom_minimum_size = Vector2(4.0 * before, 12)
		bar.add_child(base)
		var up := ColorRect.new()
		up.color = UiKit.GOOD
		up.custom_minimum_size = Vector2(4.0 * gain, 12)
		bar.add_child(up)
		line.add_child(bar)
		v.add_child(line)
	var nav := _row()
	nav.add_child(UiKit.button("Back to Training Camp", func():
		hub.go_back()
		if hub.page_stack.is_empty() or hub.page_stack[-1]["title"] != "Training Camp":
			hub.open("Training Camp", training_camp)
		else:
			hub.replace("Training Camp", training_camp), 18))
	nav.add_child(UiKit.button("View player", func(): open_player(so), 18))
	v.add_child(nav)
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
		open_player(so))


# --- league players: teams, free agency, contracts, retirements -----------------------

func teams() -> Control:
	var s := _season()
	var v := _vbox(12)
	v.add_child(_section("ALL TEAMS  -  %s season cap %s (hard cap, same for every team)" % [s.cap_year(), Contracts.money(Contracts.SALARY_CAP)]))
	var rows: Array = []
	var hl := {}
	var colors := {}
	var list: Array = s.league.teams.duplicate()
	list.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	for i in list.size():
		var t: Team = list[i]
		var space := Contracts.cap_space(t, s.cap_year())
		var ages: Array = t.roster.map(func(x: Soldier): return x.age)
		var avg_age := 0.0
		for a in ages:
			avg_age += a
		rows.append([t.name, s.record_text(t), t.team_ovr(), t.roster.size(), "%.1f" % (avg_age / maxi(1, ages.size())),
			Contracts.money(Contracts.payroll(t, s.cap_year())), Contracts.money(space)])
		colors[i] = {2: UiKit.ovr_color(t.team_ovr()), 6: UiKit.GOOD if space >= 0 else UiKit.BAD}
		if t.user_controlled:
			hl[i] = t.color.darkened(0.6)
	v.add_child(UiKit.table(["TEAM", "RECORD", "OVR", "PLAYERS", "AVG AGE", "PAYROLL", "CAP SPACE"], rows, [280, 90, 60, 80, 90, 120, 120], hl, colors,
		func(i: int):
			var t: Team = list[i]
			hub.open(t.name, func(): return team_roster(t))))
	return v


func team_roster(t: Team) -> Control:
	var s := _season()
	var v := _vbox(12)
	var top := _row(14)
	top.add_child(UiKit.team_chip(t, 18))
	var info := UiKit.rich("%s   -   OVR [color=white]%d[/color]   -   %d players   -   payroll [color=white]%s[/color]   -   cap space %s%s" % [
		s.record_text(t), t.team_ovr(), t.roster.size(), Contracts.money(Contracts.payroll(t, s.cap_year())),
		Contracts.money(Contracts.cap_space(t, s.cap_year())),
		("   -   dead money %s" % Contracts.money(int(t.dead_money.get(s.cap_year(), 0)))) if t.dead_money.get(s.cap_year(), 0) > 0 else ""], 16)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(info)
	v.add_child(top)
	v.add_child(_roster_table(false, t, func(): hub.replace(t.name, func(): return team_roster(t))))
	return v


var fa_role_filter := -1


func free_agents() -> Control:
	var s := _season()
	var user := s.user_team()
	var v := _vbox(12)
	var status := "Bidding is open: offers are answered at the start of each week." if s.phase != Season.PHASE_OFFSEASON \
		else ("FREE AGENCY DAY %d of %d: offers are answered when you advance." % [s.fa_day, Season.FA_DAYS] if s.offseason_stage == Season.OFF_FREE_AGENCY
		else ("Free agency is over; unsigned soldiers still take offers until the season starts." if s.offseason_stage == Season.OFF_DONE
		else "Free agency opens after the draft. Expiring contracts and undrafted prospects join this pool."))
	v.add_child(UiKit.label(status, 18, Color.WHITE))
	var pending := s.fa.offers_by(user)
	v.add_child(_cap_banner(user))
	v.add_child(UiKit.rich("Roster %d / %d   -   %d pending offer%s   -   [color=#8b97ab]players weigh money (70%%), team quality and playing time[/color]" % [
		user.roster.size(), Team.ROSTER_SIZE, pending.size(), "" if pending.size() == 1 else "s"], 15))
	var filters := _row(8)
	filters.add_child(UiKit.label("POSITION", 13, UiKit.MUTED))
	for r in [-1] + range(Scheme.ROLE_NAMES.size()):
		var role: int = r
		var b := UiKit.button("All" if role < 0 else Scheme.ROLE_NAMES[role], func():
			fa_role_filter = role
			hub.replace("Free Agents", free_agents), 14)
		if role == fa_role_filter:
			UiKit.style_button(b, UiKit.ACCENT.darkened(0.45), Color.WHITE, 6)
		filters.add_child(b)
	v.add_child(filters)
	var list: Array = s.league.free_agents.filter(func(x: Soldier): return fa_role_filter < 0 or Scheme.best_role(x.stats) == fa_role_filter)
	list = _sorted(list, &"fa", null)
	if list.is_empty():
		v.add_child(UiKit.label("No free agents.", 16, UiKit.MUTED))
		return v
	var pane := _player_pane()
	v.add_child(pane)
	_fill_pane(pane, list[0], null)
	var table := _vbox(4)
	table.add_child(_sort_header(&"fa", _roster_cols(&"fa"), func(): hub.replace("Free Agents", free_agents)))
	for so in list:
		table.add_child(_roster_row(null, so, &"fa", pane))
	v.add_child(table)
	v.add_child(_potential_legend())
	return v


## Big "available to spend" readout: cap minus current salaries minus pending offers.
func _cap_banner(user: Team) -> Control:
	var s := _season()
	var payroll := Contracts.payroll(user, s.cap_year())
	var committed := s.fa.committed(user)
	var spendable := Contracts.SALARY_CAP - payroll - committed
	var p := UiKit.panel(UiKit.PANEL_HI, 10)
	var h := _row(40)
	p.add_child(h)
	var left := _vbox(0)
	left.add_child(UiKit.label("AVAILABLE TO SPEND", 15, UiKit.MUTED))
	left.add_child(UiKit.label(Contracts.money(spendable), 44, UiKit.GOOD if spendable > 0 else UiKit.BAD))
	h.add_child(left)
	var math := UiKit.rich("[color=#8b97ab]Salary cap[/color]  [color=white]%s[/color]
[color=#8b97ab]Current salaries[/color]  [color=white]- %s[/color]
[color=#8b97ab]Pending offers[/color]  [color=#38bdf8]- %s[/color]" % [
		Contracts.money(Contracts.SALARY_CAP), Contracts.money(payroll), Contracts.money(committed)], 17)
	math.custom_minimum_size.x = 320
	math.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(math)
	var note := UiKit.label("An offer must fit in this amount (minimum deals always fit).
Payroll includes dead money from released players.", 14, UiKit.MUTED)
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(note)
	return p


## Offer builder state (salary in $K, years) for the soldier on the offer page.
var _offer_soldier: Soldier
var _offer_salary := 0
var _offer_years := 1
var _offer_promise := false


func open_offer(s: Soldier) -> void:
	var season := _season()
	var mine := season.fa.offer_of(season.user_team(), s)
	_offer_soldier = s
	_offer_years = mine.get("years", Contracts.preferred_years(s))
	_offer_salary = mine.get("salary", Contracts.asking(s, _offer_years))
	_offer_promise = mine.get("promise", false)
	hub.open("Offer: " + s.full_name(), offer)


func offer() -> Control:
	var season := _season()
	var user := season.user_team()
	var s := _offer_soldier
	var v := _vbox(14)
	if s == null:
		v.add_child(UiKit.label("Pick a free agent to make an offer.", 18, UiKit.MUTED))
		return v
	if not season.league.free_agents.has(s):
		var t := _team_of(s)
		v.add_child(UiKit.label("%s is no longer a free agent%s." % [s.full_name(), (" - he signed with " + t.name) if t != null else ""], 20, Color.WHITE))
		return v
	var top := _row(16)
	top.add_child(Portrait.new(s, 72))
	var yrs_pref := Contracts.preferred_years(s)
	top.add_child(UiKit.rich("[font_size=26][color=white]%s[/color][/font_size]   age %d  -  %s  -  OVR [color=%s]%d[/color]  -  POT [color=%s]%s[/color]\nAsking [color=white]%s[/color] / yr for %d yr%s  -  market value %s  -  %d team%s bidding" % [
		UiKit.esc(s.full_name()), s.age, Scheme.ROLE_NAMES[Scheme.best_role(s.stats)], UiKit.hex(UiKit.ovr_color(s.best_ovr())), s.best_ovr(),
		UiKit.hex(potential_color(s.potential)), s.potential_letter(), Contracts.money(Contracts.asking(s, yrs_pref)), yrs_pref, "" if yrs_pref == 1 else "s",
		Contracts.money(Contracts.market_value(s)), season.fa.offers_for(s).size(), "" if season.fa.offers_for(s).size() == 1 else "s"], 16))
	top.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(top)
	v.add_child(_position_compare(s, user))
	var rebuild := func(): hub.replace("Offer: " + s.full_name(), offer)
	var step := maxi(50, roundi(Contracts.asking(s, _offer_years) * 0.05 / 50.0) * 50)
	var sal_row := _row(12)
	var sal_l := UiKit.label("SALARY", 15, UiKit.MUTED)
	sal_l.custom_minimum_size.x = 90
	sal_row.add_child(sal_l)
	sal_row.add_child(UiKit.button("  -  ", func():
		_offer_salary = maxi(Contracts.MIN_SALARY, _offer_salary - step)
		rebuild.call(), 18))
	var sv := UiKit.label(Contracts.money(_offer_salary) + " / yr", 24, Color.WHITE)
	sv.custom_minimum_size.x = 170
	sv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sal_row.add_child(sv)
	sal_row.add_child(UiKit.button("  +  ", func():
		_offer_salary = mini(Contracts.MAX_SALARY, _offer_salary + step)
		rebuild.call(), 18))
	sal_row.add_child(UiKit.button("Match asking", func():
		_offer_salary = Contracts.asking(s, _offer_years)
		rebuild.call(), 14))
	v.add_child(sal_row)
	var yr_row := _row(12)
	var yr_l := UiKit.label("YEARS", 15, UiKit.MUTED)
	yr_l.custom_minimum_size.x = 90
	yr_row.add_child(yr_l)
	yr_row.add_child(UiKit.button("  -  ", func():
		_offer_years = maxi(1, _offer_years - 1)
		rebuild.call(), 18))
	var yv := UiKit.label("%d yr%s" % [_offer_years, "" if _offer_years == 1 else "s"], 24, Color.WHITE)
	yv.custom_minimum_size.x = 170
	yv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	yr_row.add_child(yv)
	yr_row.add_child(UiKit.button("  +  ", func():
		_offer_years = mini(Contracts.MAX_YEARS, _offer_years + 1)
		rebuild.call(), 18))
	yr_row.add_child(UiKit.label("asking at %d yr%s: %s (longer or shorter than he wants costs more)" % [
		_offer_years, "" if _offer_years == 1 else "s", Contracts.money(Contracts.asking(s, _offer_years))], 14, UiKit.MUTED))
	v.add_child(yr_row)
	var pr_row := _row(12)
	var pr_l := UiKit.label("PROMISE", 15, UiKit.MUTED)
	pr_l.custom_minimum_size.x = 90
	pr_row.add_child(pr_l)
	pr_row.add_child(_promise_toggle(_offer_promise, func():
		_offer_promise = not _offer_promise
		rebuild.call()))
	pr_row.add_child(UiKit.label("Guarantee he starts %d%% of games next season. Break it and he loses trust (and may ask for a trade)." % roundi(Soldier.PROMISE_SHARE * 100), 14, UiKit.MUTED))
	v.add_child(pr_row)
	var w: Array = FreeAgency.weights(s)
	v.add_child(UiKit.rich("HE WEIGHS   money [color=white]%d%%[/color]   -   winning [color=white]%d%%[/color]   -   playing time [color=white]%d%%[/color]   -   [color=%s]%s[/color]%s" % [
		roundi(w[0] * 100), roundi(w[1] * 100), roundi(w[2] * 100), UiKit.hex(UiKit.INFO), s.get_dna().headline(),
		("   -   former %s player" % s.former_team) if s.former_team != "" else ""], 15))
	var it: Array = FreeAgency.interest(user, s, _offer_salary, _offer_years, _offer_promise)
	var role_text := "would START for you" if FreeAgency.would_start(user, s) else "would be a backup for you"
	v.add_child(UiKit.rich("INTEREST   [font_size=24][color=%s]%s[/color][/font_size]   -   he %s   -   your team OVR %d   -   total value %s" % [
		UiKit.hex(it[1]), it[0], role_text, user.team_ovr(), Contracts.money(_offer_salary * _offer_years)], 16))
	var err := season.fa.offer_error(season, user, s, _offer_salary, _offer_years, _offer_promise)
	if err != "":
		v.add_child(UiKit.label(err, 15, UiKit.BAD))
	var actions := _row()
	var mine := season.fa.offer_of(user, s)
	var submit := UiKit.button("Update Offer" if not mine.is_empty() else "Submit Offer", func():
		var e := season.fa.make_offer(season, user, s, _offer_salary, _offer_years, _offer_promise)
		if e != "":
			hub.app.toast(e)
		else:
			hub.app.toast("Offer sent to %s: %s x %d. He answers %s." % [s.full_name(), Contracts.money(_offer_salary), _offer_years,
				"at the start of next week" if season.phase != Season.PHASE_OFFSEASON else "when you advance"])
		rebuild.call(), 18)
	submit.disabled = err != ""
	actions.add_child(submit)
	if not mine.is_empty():
		actions.add_child(UiKit.button("Withdraw Offer", func():
			season.fa.withdraw(user, s)
			hub.app.toast("Offer withdrawn.")
			rebuild.call(), 16))
	actions.add_child(UiKit.button("Full Ratings", func(): open_player(s), 16))
	v.add_child(actions)
	if not mine.is_empty():
		v.add_child(UiKit.label("Pending: %s x %d yr%s%s." % [Contracts.money(mine["salary"]), mine["years"], "" if mine["years"] == 1 else "s",
			" + starter promise" if mine.get("promise", false) else ""], 15, UiKit.INFO))
	v.add_child(_offer_board(s))
	var tip := UiKit.label("Players sign the best offer that clears their bar. What counts depends on his DNA: money (up to 30% over asking helps), team quality, and whether he'd start (a starter promise covers that). Loyal players lean toward their old team if they trust it; security-minded ones like longer deals. Unsigned players lower their asking price over time.", 14, UiKit.MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip)
	return v


var _confirm_release: Soldier


## Every team with an offer on `s`, best first, with his interest in each as a bar. The bar
## reaches the white tick when the offer clears his bar to sign.
func _offer_board(s: Soldier) -> Control:
	var bids: Array = []
	for o in _season().fa.offers_for(s):
		bids.append([o, FreeAgency.score(o["team"], s, o["salary"], o["years"], o.get("promise", false)) / FreeAgency.ACCEPT_SCORE])
	bids.sort_custom(func(a, b): return a[1] > b[1])
	var v := _vbox(8)
	v.name = "OfferBoard"
	v.add_child(UiKit.label("CURRENT OFFERS (%d)" % bids.size(), 15, UiKit.MUTED))
	if bids.is_empty():
		v.add_child(UiKit.label("No team has made an offer yet.", 15, UiKit.MUTED))
		return v
	const BAR_MAX := 1.3
	const BAR_W := 320.0
	for b in bids:
		var o: Dictionary = b[0]
		var team: Team = o["team"]
		var it: Array = FreeAgency.interest(team, s, o["salary"], o["years"], o.get("promise", false))
		var row := _row(12)
		var chip := UiKit.team_chip(team, 15)
		chip.custom_minimum_size.x = 230
		row.add_child(chip)
		var terms := UiKit.label("%s x %d yr%s%s" % [Contracts.money(o["salary"]), o["years"], "" if o["years"] == 1 else "s", " +P" if o.get("promise", false) else ""], 15, Color.WHITE if team.user_controlled else UiKit.TEXT)
		terms.custom_minimum_size.x = 130
		row.add_child(terms)
		var bar := ProgressBar.new()
		bar.max_value = BAR_MAX
		bar.step = 0.0
		bar.value = clampf(b[1], 0.0, BAR_MAX)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(BAR_W, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", UiKit.flat(UiKit.LINE, 4))
		var fill := UiKit.flat(it[1], 4)
		fill.content_margin_top = 0
		fill.content_margin_bottom = 0
		bar.add_theme_stylebox_override("fill", fill)
		var tick := ColorRect.new()
		tick.color = Color(1, 1, 1, 0.85)
		tick.position = Vector2(BAR_W / BAR_MAX - 1.0, -3)
		tick.size = Vector2(2, 20)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(tick)
		row.add_child(bar)
		var lab := UiKit.rich("[color=%s]%s[/color]%s" % [UiKit.hex(it[1]), it[0], "   [color=#38bdf8](your offer)[/color]" if team.user_controlled else ""], 15)
		lab.custom_minimum_size.x = 220
		row.add_child(lab)
		v.add_child(row)
	return v


## Your roster players at a free agent's position, compared at that position's OVR.
func _position_compare(fa_s: Soldier, user: Team) -> Control:
	var role := Scheme.best_role(fa_s.stats)
	var v := _vbox(6)
	var mine: Array = user.roster.filter(func(x: Soldier): return Scheme.best_role(x.stats) == role)
	mine.sort_custom(func(a: Soldier, b: Soldier): return a.ovr_at_role(role) > b.ovr_at_role(role))
	var fa_ovr := fa_s.ovr_at_role(role)
	v.add_child(_section("YOUR %s  -  compared with him at %s (OVR %d)" % [Scheme.ROLE_NAMES[role].to_upper().replace("FRONTMAN", "FRONTMEN") + ("" if role == Scheme.Role.FRONTMAN else "S"), Scheme.ROLE_NAMES[role], fa_ovr]))
	if mine.is_empty():
		v.add_child(UiKit.label("You have no %ss on the roster." % Scheme.ROLE_NAMES[role], 15, UiKit.MUTED))
		return v
	var rows: Array = []
	var colors := {}
	for i in mine.size():
		var so: Soldier = mine[i]
		var o := so.ovr_at_role(role)
		var slot := user.slot_of(so)
		rows.append([so.display_name(), so.age, o, "%+d" % (fa_ovr - o), so.potential_letter(),
			user.scheme.label_for_slot(slot) if slot != &"" else "Bench",
			Contracts.money(so.contract.salary) if so.contract != null else "-",
			("EXPIRING" if so.contract.is_expiring() else "%d yr" % so.contract.years) if so.contract != null else "-"])
		colors[i] = {2: UiKit.ovr_color(o), 3: UiKit.GOOD if fa_ovr > o else (UiKit.BAD if fa_ovr < o else UiKit.MUTED), 4: potential_color(so.potential)}
	v.add_child(UiKit.table(["SOLDIER", "AGE", "OVR", "FA +/-", "POT", "SLOT", "SALARY", "YEARS"], rows,
		[260, 50, 50, 70, 50, 110, 90, 90], {}, colors, func(i: int): open_player(mine[i])))
	return v


func contracts() -> Control:
	var s := _season()
	var user := s.user_team()
	var cy := s.cap_year()
	var v := _vbox(12)
	var payroll := Contracts.payroll(user, cy)
	var dead := int(user.dead_money.get(cy, 0))
	var space := Contracts.cap_space(user, cy)
	var summary := _row(14)
	for item in [["%d CAP" % cy, Contracts.money(Contracts.SALARY_CAP), Color.WHITE], ["PAYROLL", Contracts.money(payroll), Color.WHITE],
			["DEAD MONEY", Contracts.money(dead), UiKit.BAD if dead > 0 else UiKit.MUTED], ["CAP SPACE", Contracts.money(space), UiKit.GOOD if space >= 0 else UiKit.BAD],
			["ROSTER", "%d / %d" % [user.roster.size(), Team.ROSTER_SIZE], UiKit.BAD if user.is_over_roster_limit() else Color.WHITE]]:
		var p := UiKit.panel(UiKit.PANEL_HI, 8)
		var box := _vbox(2)
		box.add_child(UiKit.label(item[0], 13, UiKit.MUTED))
		box.add_child(UiKit.label(item[1], 24, item[2]))
		box.custom_minimum_size.x = 170
		p.add_child(box)
		summary.add_child(p)
	v.add_child(summary)
	var roster_err := s.user_roster_error()
	if user.is_over_roster_limit():
		var extra := user.roster.size() - Team.ROSTER_SIZE
		var by := "Week 1" if s.phase == Season.PHASE_OFFSEASON or s.preseason_camp or (s.phase == Season.PHASE_REGULAR and s.week == 1) else "your next match"
		v.add_child(UiKit.label("Over the roster limit: release or trade %d player%s before %s." % [extra, "" if extra == 1 else "s", by], 16, UiKit.BAD))
	elif roster_err != "":
		v.add_child(UiKit.label(roster_err, 16, UiKit.ACCENT))
	v.add_child(_section("CONTRACTS  -  click a player to re-sign or release him (releasing leaves %d%% of his remaining salary as dead money)" % roundi(Contracts.DEAD_MONEY_SHARE * 100)))
	var list := _sorted(user.roster, &"contracts", user)
	var table := _vbox(4)
	table.add_child(_sort_header(&"contracts", CONTRACT_COLS, func(): hub.replace("Contracts & Payroll", contracts)))
	for so: Soldier in list:
		table.add_child(_contract_row(user, so))
	v.add_child(table)
	v.add_child(_section("FUTURE COMMITMENTS"))
	var rows: Array = []
	var colors := {}
	for k in 4:
		var yr := cy + k
		var committed := Contracts.payroll(user, cy, k)
		var under := 0
		for so in user.roster:
			if so.contract != null and so.contract.years > k:
				under += 1
		rows.append([yr, under, Contracts.money(int(user.dead_money.get(yr, 0))), Contracts.money(committed), Contracts.money(Contracts.SALARY_CAP - committed)])
		colors[k] = {4: UiKit.GOOD if committed <= Contracts.SALARY_CAP else UiKit.BAD}
	v.add_child(UiKit.table(["SEASON", "UNDER CONTRACT", "DEAD MONEY", "COMMITTED", "SPACE"], rows, [90, 150, 120, 130, 130], {}, colors))
	return v


const CONTRACT_COLS := [["SOLDIER", 240, &"name"], ["AGE", 50, &"age"], ["OVR", 60, &"ovr"], ["POSITION", 110, &"role"],
	["SALARY", 100, &"salary"], ["YEARS LEFT", 100, &"years"], ["REMAINING", 110, &"total"], ["DEAD $ IF CUT", 120, &"dead"],
	["MORALE", 80, &"morale"], ["SLOT", 110, &"slot"]]


func _contract_row(team: Team, so: Soldier) -> Control:
	var width := 28
	for c in CONTRACT_COLS:
		width += c[1] + PCOL_SEP
	var b := Button.new()
	UiKit.style_button(b, UiKit.PANEL, UiKit.ACCENT, 6)
	b.custom_minimum_size = Vector2(width, 50)
	b.pressed.connect(func(): open_player(so, 2))
	var hb := _row(PCOL_SEP)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 14
	hb.offset_right = -14
	b.add_child(hb)
	var c: Contract = so.contract
	var o := _row_ovr(team, so)
	var slot := team.slot_of(so)
	hb.add_child(_two_lines(so.display_name(), Color.WHITE, ("rookie deal" if c != null and c.rookie else "") , 240))
	hb.add_child(_big_cell(str(so.age), UiKit.TEXT, 50, 18))
	hb.add_child(_big_cell(str(o), UiKit.ovr_color(o), 60, 20))
	hb.add_child(_big_cell(Scheme.ROLE_NAMES[Scheme.best_role(so.stats)], UiKit.TEXT, 110, 16))
	hb.add_child(_big_cell(Contracts.money(c.salary) if c != null else "-", Color.WHITE, 100, 18))
	hb.add_child(_big_cell(("EXPIRING" if c.is_expiring() else str(c.years)) if c != null else "-", UiKit.ACCENT if c != null and c.is_expiring() else UiKit.TEXT, 100, 16))
	hb.add_child(_big_cell(Contracts.money(c.remaining_value()) if c != null else "-", UiKit.TEXT, 110, 16))
	var dm := Contracts.dead_money_if_released(so)
	hb.add_child(_big_cell(Contracts.money(dm), UiKit.BAD if dm > 0 else UiKit.MUTED, 120, 16))
	hb.add_child(_big_cell(str(roundi(so.morale)), morale_color(so.morale), 80, 18))
	hb.add_child(_big_cell(team.scheme.label_for_slot(slot) if slot != &"" else "Bench", Color.WHITE if slot != &"" else UiKit.MUTED, 110, 15))
	return b


var _resign_years := {}


func resign() -> Control:
	var s := _season()
	var user := s.user_team()
	var v := _vbox(12)
	var expiring := Contracts.expiring(user)
	if s.phase != Season.PHASE_OFFSEASON:
		v.add_child(UiKit.label("Re-signing opens after the Final.", 22, Color.WHITE))
		var upcoming: Array = user.roster.filter(func(x: Soldier): return x.contract != null and x.contract.years == 1)
		v.add_child(UiKit.label("Contracts ending this season: %s" % (", ".join(PackedStringArray(upcoming.map(func(x: Soldier): return x.full_name()))) if not upcoming.is_empty() else "none"), 16, UiKit.MUTED))
		return v
	v.add_child(UiKit.rich("[font_size=22][color=white]%s[/color][/font_size]   cap space for %d: [color=white]%s[/color]" % [
		"RE-SIGN WINDOW OPEN" if s.can_resign() else "RE-SIGN WINDOW CLOSED", s.cap_year(), Contracts.money(Contracts.cap_space(user, s.cap_year()))], 16))
	var help := UiKit.label("Each expiring player names his price (a hometown discount, moved by his DNA and trust in you). Sign at his ask, or Negotiate to make offers and argue your case with data. Push too hard and he walks into free agency. Anyone unsigned when free agency opens joins the pool.", 14, UiKit.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)
	if expiring.is_empty():
		v.add_child(UiKit.label("No expiring contracts.", 16, UiKit.MUTED))
	var refresh := func(): hub.replace("Re-sign Players", resign)
	for so in expiring:
		var ref: Soldier = so
		var n := s.negotiation(user, so)
		var yrs: int = _resign_years.get(so.id, Contracts.preferred_years(so))
		var row := _row(10)
		row.add_child(Portrait.new(so, 44, user.color, user))
		var info := UiKit.button("%s   -   age %d   -   OVR %d   -   POT %s   -   %s" % [so.display_name(), so.age, so.best_ovr(), so.potential_letter(),
			Scheme.ROLE_NAMES[Scheme.best_role(so.stats)]], func(): open_player(ref, 4), 15)
		info.alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.custom_minimum_size.x = 470
		row.add_child(info)
		var dna := UiKit.label(so.get_dna().headline(), 14, UiKit.INFO)
		dna.custom_minimum_size.x = 210
		row.add_child(dna)
		if n == null or not n.is_open():
			var walked := n != null and n.state == Negotiation.WALKED
			row.add_child(UiKit.label("Talks broken off - headed to free agency" if walked else "Window closed", 16, UiKit.BAD if walked else UiKit.MUTED))
			v.add_child(row)
			continue
		row.add_child(UiKit.button("-", func():
			_resign_years[ref.id] = maxi(1, yrs - 1)
			refresh.call(), 15))
		var yl := UiKit.label("%d yr%s" % [yrs, "" if yrs == 1 else "s"], 18, Color.WHITE)
		yl.custom_minimum_size.x = 60
		yl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(yl)
		row.add_child(UiKit.button("+", func():
			_resign_years[ref.id] = mini(Contracts.MAX_YEARS, yrs + 1)
			refresh.call(), 15))
		var ask := UiKit.label("%s / yr" % Contracts.money(n.demand(yrs)), 18, Color.WHITE)
		ask.custom_minimum_size.x = 120
		row.add_child(ask)
		var b := UiKit.button("Sign at Ask", func():
			var err := s.resign_player(user, ref, yrs)
			hub.app.toast(err if err != "" else "%s re-signed: %s x %d." % [ref.full_name(), Contracts.money(ref.contract.salary), yrs])
			refresh.call(), 15)
		b.disabled = not s.can_resign()
		row.add_child(b)
		var nb := UiKit.button("Negotiate", func(): open_negotiation(ref, yrs), 15)
		nb.disabled = not s.can_resign()
		row.add_child(nb)
		v.add_child(row)
	var done: Array = s.resign_log.filter(func(r): return r["year"] == s.year)
	if not done.is_empty():
		v.add_child(_section("RE-SIGNED THIS OFFSEASON  -  league-wide"))
		var rows: Array = []
		var targets: Array = []
		for r in done:
			rows.append([r["team"].abbrev, r["soldier"].full_name(), r["soldier"].age, r["soldier"].best_ovr(),
				"%s x %d%s" % [Contracts.money(r["salary"]), r["years"], "  +promise" if r.get("promise", false) else ""]])
			targets.append(r["soldier"])
		v.add_child(_soldier_table(["TEAM", "SOLDIER", "AGE", "OVR", "DEAL"], rows, [70, 220, 50, 50, 200], targets))
	return v


## Negotiation room state.
var _neg_soldier: Soldier
var _neg_salary := 0
var _neg_years := 1
var _neg_promise := false


func open_negotiation(s: Soldier, years := 0) -> void:
	var season := _season()
	var n := season.negotiation(season.user_team(), s)
	if n == null:
		hub.app.toast("You can't negotiate with %s right now." % s.full_name())
		return
	_neg_soldier = s
	_neg_years = years if years > 0 else Contracts.preferred_years(s)
	_neg_promise = false
	_neg_salary = n.floor_salary(_neg_years) + (n.demand(_neg_years) - n.floor_salary(_neg_years)) / 2
	_neg_salary = Contracts._round_salary(_neg_salary)
	hub.open("Negotiate: " + s.full_name(), negotiate)


func negotiate() -> Control:
	var season := _season()
	var user := season.user_team()
	var s := _neg_soldier
	var v := _vbox(12)
	var n: Negotiation = season.negotiations.get(s.id) if s != null else null
	if n == null:
		v.add_child(UiKit.label("No talks in progress.", 18, UiKit.MUTED))
		return v
	var rebuild := func(): hub.replace("Negotiate: " + s.full_name(), negotiate)
	var d := s.get_dna()
	var want := n.demand(_neg_years, _neg_promise)
	# --- header
	var top := _row(16)
	top.add_child(Portrait.new(s, 88, user.color, user))
	var head := _vbox(4)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(UiKit.rich("[font_size=26][color=white]%s[/color][/font_size]   age %d  -  %s  -  OVR [color=%s]%d[/color]  -  POT [color=%s]%s[/color]" % [
		UiKit.esc(s.display_name()), s.age, Scheme.ROLE_NAMES[Scheme.best_role(s.stats)], UiKit.hex(UiKit.ovr_color(s.best_ovr())), s.best_ovr(),
		UiKit.hex(potential_color(s.potential)), s.potential_letter()], 16))
	head.add_child(UiKit.rich("[color=%s]%s[/color]   -   %s   -   %s" % [UiKit.hex(UiKit.INFO), d.headline(), d.temperament_label(), d.savvy_label()], 15))
	head.add_child(UiKit.rich("Market value [color=white]%s[/color]   -   your cap space for %d: [color=white]%s[/color]   -   current deal %s" % [
		Contracts.money(Contracts.market_value(s)), season.cap_year(), Contracts.money(Contracts.cap_space(user, season.cap_year())),
		Contracts.money(s.contract.salary) if s.contract != null else "-"], 15))
	top.add_child(head)
	v.add_child(top)
	var state_col := UiKit.GOOD if n.state == Negotiation.SIGNED else (UiKit.BAD if n.state == Negotiation.WALKED else Color.WHITE)
	var state_text: String = {Negotiation.OPEN: "HE WANTS  %s / yr  for %d yr%s" % [Contracts.money(want), _neg_years, "" if _neg_years == 1 else "s"],
		Negotiation.SIGNED: "SIGNED  -  %s x %d" % [Contracts.money(s.contract.salary), s.contract.years],
		Negotiation.WALKED: "TALKS BROKEN OFF  -  he's headed to free agency"}[n.state]
	v.add_child(UiKit.label(state_text, 26, state_col))
	var meters := _row(30)
	meters.add_child(_meter("PATIENCE", maxf(0.0, n.patience), Negotiation.MAX_PATIENCE, _dna_color(n.patience), "%d" % maxi(0, roundi(n.patience))))
	meters.add_child(_meter("TRUST", s.trust, 100, _dna_color(s.trust), "%d - %s" % [roundi(s.trust), Soldier.trust_label(s.trust)]))
	meters.add_child(_meter("LEVERAGE", n.leverage(), 1.2, UiKit.INFO, {0.8: "He's a cornerstone", 1.0: "Even", 1.2: "He's a backup"}.get(n.leverage(), "")))
	v.add_child(meters)
	var body := _row(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# --- left: offer + arguments
	var left := _vbox(10)
	left.custom_minimum_size.x = 640
	body.add_child(left)
	if n.is_open():
		left.add_child(_section("YOUR OFFER  -  every offer or argument costs patience"))
		var step := maxi(50, roundi(want * 0.03 / 50.0) * 50)
		var sal_row := _row(10)
		sal_row.add_child(UiKit.button("  -  ", func():
			_neg_salary = maxi(Contracts.MIN_SALARY, _neg_salary - step)
			rebuild.call(), 18))
		var sv := UiKit.label(Contracts.money(_neg_salary) + " / yr", 24, Color.WHITE)
		sv.custom_minimum_size.x = 170
		sv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sal_row.add_child(sv)
		sal_row.add_child(UiKit.button("  +  ", func():
			_neg_salary = mini(Contracts.MAX_SALARY, _neg_salary + step)
			rebuild.call(), 18))
		var share := float(_neg_salary) / maxf(1.0, want)
		sal_row.add_child(UiKit.label("%d%% of his number%s" % [roundi(share * 100), "  -  lowball!" if share < Negotiation.LOWBALL_SHARE else ""], 14,
			UiKit.BAD if share < Negotiation.LOWBALL_SHARE else UiKit.MUTED))
		left.add_child(sal_row)
		var yr_row := _row(10)
		yr_row.add_child(UiKit.button("  -  ", func():
			_neg_years = maxi(1, _neg_years - 1)
			rebuild.call(), 18))
		var yv := UiKit.label("%d yr%s" % [_neg_years, "" if _neg_years == 1 else "s"], 24, Color.WHITE)
		yv.custom_minimum_size.x = 170
		yv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		yr_row.add_child(yv)
		yr_row.add_child(UiKit.button("  +  ", func():
			_neg_years = mini(Contracts.MAX_YEARS, _neg_years + 1)
			rebuild.call(), 18))
		yr_row.add_child(UiKit.label("he prefers %d" % Contracts.preferred_years(s), 14, UiKit.MUTED))
		left.add_child(yr_row)
		var pr := _row(10)
		pr.add_child(_promise_toggle(_neg_promise, func():
			_neg_promise = not _neg_promise
			rebuild.call()))
		pr.add_child(UiKit.label("worth about %d%% off to him" % roundi(n.promise_cut() * 100), 14, UiKit.MUTED))
		left.add_child(pr)
		var err := n.offer_error(_neg_salary, _neg_years, _neg_promise)
		if err != "":
			left.add_child(UiKit.label(err, 15, UiKit.BAD))
		var acts := _row(10)
		var mk := UiKit.button("Make Offer", func():
			var r := n.make_offer(_neg_salary, _neg_years, _neg_promise)
			hub.app.toast(r["text"])
			rebuild.call(), 18)
		mk.disabled = err != ""
		acts.add_child(mk)
		var ac := UiKit.button("Accept %s" % Contracts.money(want), func():
			var r := n.accept(_neg_years, _neg_promise)
			hub.app.toast(r["text"])
			rebuild.call(), 16)
		ac.disabled = n.offer_error(want, _neg_years, _neg_promise) != ""
		acts.add_child(ac)
		left.add_child(acts)
		left.add_child(_section("MAKE YOUR CASE  -  strength = evidence x fit with his DNA x your leverage"))
		var args := n.arguments()
		if args.is_empty():
			left.add_child(UiKit.label("The numbers don't give you anything to argue with.", 15, UiKit.MUTED))
		for a in args:
			var arg: Dictionary = a
			var fl: Array = Negotiation.fit_label(arg["fit"])
			var el: Array = Negotiation.evidence_label(arg["evidence"])
			var r := _row(10)
			var ab := UiKit.button(arg["title"], func():
				var res := n.use_argument(arg["id"])
				hub.app.toast(res["text"])
				rebuild.call(), 15)
			ab.custom_minimum_size.x = 200
			ab.disabled = arg["used"]
			r.add_child(ab)
			var txt := UiKit.rich("[color=%s]%s evidence[/color]  -  [color=%s]%s[/color]%s\n[color=#8b97ab]%s[/color]" % [UiKit.hex(el[1]), el[0], UiKit.hex(fl[1]), fl[0],
				"  -  [color=#f59e0b]hardball[/color]" if arg["tone"] == "hard" else "",
				UiKit.esc(arg["evidence_text"]) + ("   (used: %s)" % n.used[arg["id"]] if arg["used"] else "")], 14)
			txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(txt)
			left.add_child(r)
	else:
		left.add_child(UiKit.button("Back to Re-sign Players", func(): hub.replace("Re-sign Players", resign), 16))
	# --- right: conversation
	var right := _vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(_section("THE TABLE"))
	var log_box := _vbox(6)
	for i in range(n.talk.size() - 1, -1, -1):
		var e: Dictionary = n.talk[i]
		var who: String = e["who"]
		var p := UiKit.panel(UiKit.PANEL_HI if who == "you" else UiKit.PANEL, 8)
		var name_col: Color = {"you": UiKit.INFO, "him": UiKit.ACCENT, "note": UiKit.MUTED}[who]
		var speaker: String = {"you": "YOU", "him": s.callsign.to_upper() if s.callsign != "" else s.last_name.to_upper(), "note": "NOTE"}[who]
		var rt := UiKit.rich("[color=%s]%s[/color]  %s" % [UiKit.hex(name_col), speaker, UiKit.esc(e["text"])], 15)
		p.add_child(rt)
		log_box.add_child(p)
	right.add_child(log_box)
	return v


func _promise_toggle(on: bool, cb: Callable) -> Button:
	var b := UiKit.button("[x] Starter promise" if on else "[  ] Starter promise", cb, 15)
	if on:
		UiKit.style_button(b, UiKit.ACCENT.darkened(0.45), Color.WHITE, 6)
	return b


var retire_scope_team := true


func retirements() -> Control:
	var s := _season()
	var user := s.user_team()
	var v := _vbox(12)
	var toggle := _row(8)
	for opt in [[true, "Your Team"], [false, "League"]]:
		var mine: bool = opt[0]
		var b := UiKit.button(opt[1], func():
			retire_scope_team = mine
			hub.replace("Retirements", retirements), 15)
		if mine == retire_scope_team:
			UiKit.style_button(b, UiKit.ACCENT.darkened(0.45), Color.WHITE, 6)
		toggle.add_child(b)
	v.add_child(toggle)
	var help := UiKit.label("Soldiers retire from age %d (always by %d). Free agents who go a full season unsigned retire if they're below %d OVR or %d+." % [
		Retirement.AGE_CHANCE.keys().min(), Retirement.ALWAYS_AGE, Retirement.FA_MIN_OVR, Retirement.FA_MAX_AGE], 14, UiKit.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)
	var list: Array = s.retirements.filter(func(r): return not retire_scope_team or r["team"] == user)
	if list.is_empty():
		v.add_child(UiKit.label("No retirements yet. They happen after the Final.", 16, UiKit.MUTED))
		return v
	var years: Array = []
	for r in list:
		if not years.has(r["year"]):
			years.append(r["year"])
	years.sort()
	years.reverse()
	for y in years:
		var of_year: Array = list.filter(func(r): return r["year"] == y)
		of_year.sort_custom(func(a, b): return a["ovr"] > b["ovr"])
		v.add_child(_section("%d  -  %d retirement%s" % [y, of_year.size(), "" if of_year.size() == 1 else "s"]))
		var rows: Array = []
		var targets: Array = []
		for r in of_year:
			var so: Soldier = r["soldier"]
			rows.append([so.full_name(), r["team"].abbrev if r["team"] != null else "FA", r["age"], Scheme.ROLE_NAMES[r["role"]], r["ovr"],
				r["reason"], r["matches"], r["kills"], ", ".join(r["awards"]) if not r["awards"].is_empty() else "-"])
			targets.append(so)
		v.add_child(_soldier_table(["SOLDIER", "TEAM", "AGE", "POS", "OVR", "REASON", "GP", "K", "HONOURS"], rows, [210, 60, 50, 100, 50, 90, 50, 60, 300], targets))
	return v


## Free-agent signings from one round of offers (FA day or in-season week).
func signings(label: String, signed: Array) -> Control:
	var s := _season()
	var v := _vbox(12)
	v.add_child(UiKit.label("%d signing%s on %s." % [signed.size(), "" if signed.size() == 1 else "s", label], 20, Color.WHITE))
	if not signed.is_empty():
		v.add_child(_signings_table(signed))
	var user := s.user_team()
	var pending := s.fa.offers_by(user)
	if not pending.is_empty():
		v.add_child(UiKit.label("Still pending: %s" % ", ".join(PackedStringArray(pending.map(func(o): return o["soldier"].full_name()))), 15, UiKit.INFO))
	var nav := _row()
	if s.camp_open():
		nav.add_child(UiKit.button("Training Camp  >>", hub.open_camp))
	nav.add_child(UiKit.button("Free Agents", hub.open_free_agents))
	nav.add_child(UiKit.button("Contracts & Payroll", hub.open_contracts))
	v.add_child(nav)
	return v


func _signings_table(signed: Array) -> Control:
	var rows: Array = []
	var targets: Array = []
	for e in signed:
		var so: Soldier = e["soldier"]
		rows.append([e["team"].abbrev, so.full_name(), so.age, Scheme.ROLE_NAMES[Scheme.best_role(so.stats)], so.best_ovr(),
			"%s x %d" % [Contracts.money(e["salary"]), e["years"]]])
		targets.append(so)
	return _soldier_table(["TEAM", "SOLDIER", "AGE", "POS", "OVR", "DEAL"], rows, [70, 220, 50, 100, 50, 160], targets)


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
	return _season().league.team_of(s)


func _grade(s: Soldier) -> String:
	return s.potential_letter()


# --- trades -------------------------------------------------------------------------

var _trade_partner: Team
var _trade_give: Array = []
var _trade_get: Array = []
var _trade_counter: Dictionary = {}
var _trade_msg := ""
var _trade_msg_color := UiKit.MUTED


func _ai_teams() -> Array:
	var user := _season().user_team()
	return _season().league.teams.filter(func(t: Team): return t != user)


## Opens the trade builder with `partner` (keeps the current one when null) and optionally
## drops an asset onto either side.
func open_trade(partner: Team = null, get_asset: Dictionary = {}, give_asset: Dictionary = {}) -> void:
	var user := _season().user_team()
	if partner == null or partner == user:
		partner = _trade_partner if _trade_partner != null and _trade_partner != user else _ai_teams()[0]
	if partner != _trade_partner:
		_trade_get = []
	_trade_partner = partner
	if not get_asset.is_empty() and not Trades.contains(_trade_get, get_asset) and _trade_get.size() < Trades.MAX_ASSETS:
		_trade_get.append(get_asset)
	if not give_asset.is_empty() and not Trades.contains(_trade_give, give_asset) and _trade_give.size() < Trades.MAX_ASSETS:
		_trade_give.append(give_asset)
	_trade_counter = {}
	_trade_msg = ""
	hub.open("Trade Center", trade_center)


func _trade_rebuild() -> void:
	hub.replace("Trade Center", trade_center)


func _owns(team: Team, a: Dictionary) -> bool:
	var tr := _season().trades
	if Trades.is_pick(a):
		return tr.owner_of(a) == team and not tr.pick_used(_season(), a)
	return team.roster.has(a["soldier"]) and Trades.tradeable(a["soldier"])


func trade_center() -> Control:
	var s := _season()
	var tr := s.trades
	var user := s.user_team()
	if _trade_partner == null or _trade_partner == user:
		_trade_partner = _ai_teams()[0]
	var ai := _trade_partner
	_trade_give = _trade_give.filter(func(a): return _owns(user, a))
	_trade_get = _trade_get.filter(func(a): return _owns(ai, a))
	var v := _vbox(12)
	var top := _row(10)
	top.add_child(UiKit.label("PARTNER", 15, UiKit.MUTED))
	top.add_child(UiKit.button("  <  ", func(): _cycle_partner(-1), 18))
	var chip := UiKit.team_chip(ai, 20)
	chip.custom_minimum_size.x = 280
	top.add_child(chip)
	top.add_child(UiKit.button("  >  ", func(): _cycle_partner(1), 18))
	var m := tr.mode(s, ai)
	var mcol: String = {Trades.CONTENDER: "#22c55e", Trades.BALANCED: "#e5e7eb", Trades.REBUILDING: "#38bdf8"}[m]
	var info := UiKit.rich("[color=%s]%s[/color]   -   OVR [color=white]%d[/color]   -   %s   -   cap space [color=white]%s[/color]" % [
		mcol, Trades.MODE_NAMES[m].to_upper(), ai.team_ovr(), s.record_text(ai), Contracts.money(Contracts.cap_space(ai, s.cap_year()))], 16)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(info)
	var pips := ""
	for i in Trades.PATIENCE:
		pips += "[color=%s]●[/color]" % ("#f59e0b" if i < tr.patience_of(ai) else "#334155")
	var pat := UiKit.rich("PATIENCE  [font_size=22]%s[/font_size]" % pips, 15)
	pat.custom_minimum_size.x = 190
	pat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(pat)
	v.add_child(top)
	var open := tr.window_open(s)
	v.add_child(UiKit.rich("TRADE WINDOW  [color=%s]%s[/color]   -   max %d assets a side   -   both teams must stay under the cap" % [
		"#22c55e" if open else "#ef4444", tr.window_text(s), Trades.MAX_ASSETS], 15))
	var sides := _row(16)
	sides.add_child(_trade_side("YOU GIVE", user, _trade_give))
	sides.add_child(_trade_side("YOU GET", ai, _trade_get))
	v.add_child(sides)
	var both_empty := _trade_give.is_empty() and _trade_get.is_empty()
	var it := tr.interest(s, ai, _trade_give, _trade_get) if not _trade_get.is_empty() else 0.0
	var irow := _row(14)
	irow.add_child(UiKit.label("INTEREST", 15, UiKit.MUTED))
	irow.add_child(_interest_bar(it))
	var q := UiKit.rich("[i]\"%s\"[/i]   [color=#8b97ab]- %s front office[/color]" % [UiKit.esc(tr.quote(s, ai, _trade_give, _trade_get)), UiKit.esc(ai.abbrev)], 17)
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	irow.add_child(q)
	v.add_child(irow)
	var err := "" if both_empty else tr.validate(s, user, _trade_give, ai, _trade_get)
	v.add_child(UiKit.rich(_trade_after_text(user, _trade_give, _trade_get) + "        " + _trade_after_text(ai, _trade_get, _trade_give), 15))
	if err != "":
		v.add_child(UiKit.label(err, 15, UiKit.BAD))
	var actions := _row(10)
	var propose := UiKit.button("Propose Trade", func():
		var r := tr.propose(s, ai, _trade_give, _trade_get)
		_trade_counter = {}
		match r["result"]:
			"accepted":
				hub.app.toast(r["text"])
				_trade_msg = "Trade complete. Welcome to the new guys."
				_trade_msg_color = UiKit.GOOD
				_trade_give = []
				_trade_get = []
			"counter":
				_trade_counter = r
				_trade_msg = r["text"]
				_trade_msg_color = UiKit.ACCENT
			_:
				_trade_msg = r["text"]
				_trade_msg_color = UiKit.BAD
		_trade_rebuild(), 18)
	propose.disabled = err != "" or _trade_get.is_empty() or not open
	actions.add_child(propose)
	var wwit := UiKit.button("What would it take?", func():
		var g := tr.what_would_it_take(s, ai, _trade_give, _trade_get)
		_trade_counter = {}
		if g.is_empty():
			_trade_msg = "%s: \"Nothing you could add gets this done.\"" % ai.abbrev
			_trade_msg_color = UiKit.BAD
		else:
			_trade_give = g
			_trade_msg = "%s would do it for this package." % ai.abbrev
			_trade_msg_color = UiKit.INFO
		_trade_rebuild(), 16)
	wwit.disabled = _trade_get.is_empty() or not open
	actions.add_child(wwit)
	actions.add_child(UiKit.button("Clear", func():
		_trade_give = []
		_trade_get = []
		_trade_counter = {}
		_trade_msg = ""
		_trade_rebuild(), 16))
	actions.add_child(UiKit.button("Offers (%d)" % tr.offers.size(), func(): hub.open("Trade Offers", trade_offers), 16))
	actions.add_child(UiKit.button("Trade Block", func(): hub.open("Trade Block", trade_block), 16))
	actions.add_child(UiKit.button("Trade Log", func(): hub.open("Trade Log", trade_log), 16))
	v.add_child(actions)
	if _trade_msg != "":
		v.add_child(UiKit.label(_trade_msg, 17, _trade_msg_color))
	if not _trade_counter.is_empty():
		v.add_child(_counter_panel(ai))
	var lists := _row(16)
	lists.add_child(_asset_list("YOUR ROSTER & PICKS", user, true))
	lists.add_child(_asset_list("%s ROSTER & PICKS" % ai.name.to_upper(), ai, false))
	v.add_child(lists)
	var tip := UiKit.label("Click players or picks to add them to the deal. The AI judges value by its situation: contenders want starters now; rebuilders want youth, picks and cheap contracts. Each refusal costs a patience pip (it recovers weekly). ★ = on the block (shopped or asked out); those come cheaper.", 14, UiKit.MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip)
	return v


func _cycle_partner(dir: int) -> void:
	var teams := _ai_teams()
	var i := teams.find(_trade_partner)
	_trade_partner = teams[(i + dir + teams.size()) % teams.size()]
	_trade_get = []
	_trade_counter = {}
	_trade_msg = ""
	_trade_rebuild()


func _trade_after_text(t: Team, out_assets: Array, in_assets: Array) -> String:
	var s := _season()
	var players_in := in_assets.filter(func(a): return not Trades.is_pick(a))
	var players_out := out_assets.filter(func(a): return not Trades.is_pick(a))
	var sal := 0
	for a in players_in:
		sal += a["soldier"].contract.salary
	for a in players_out:
		sal -= a["soldier"].contract.salary
	var space := Contracts.cap_space(t, s.cap_year()) - sal
	var roster := t.roster.size() + players_in.size() - players_out.size()
	var note := ""
	if roster > Team.ROSTER_SIZE:
		note = "  [color=#ef4444](%s)[/color]" % ("must cut %d before the next match" % (roster - Team.ROSTER_SIZE) if t.user_controlled else "will shop or cut %d" % (roster - Team.ROSTER_SIZE))
	return "[color=#8b97ab]%s AFTER[/color]  cap space [color=%s]%s[/color]  -  roster [color=%s]%d[/color]/%d%s" % [
		t.abbrev, "#22c55e" if space >= 0 else "#ef4444", Contracts.money(space), "#ef4444" if roster > Team.ROSTER_SIZE else "white", roster, Team.ROSTER_SIZE, note]


func _interest_bar(it: float) -> Control:
	const BAR_MAX := 1.25
	const BAR_W := 360.0
	var bar := ProgressBar.new()
	bar.max_value = BAR_MAX
	bar.step = 0.0
	bar.value = clampf(it, 0.0, BAR_MAX)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(BAR_W, 18)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UiKit.flat(UiKit.LINE, 4))
	var col := UiKit.GOOD if it >= 1.0 else (UiKit.ACCENT if it >= Trades.COUNTER_FLOOR else UiKit.BAD)
	var fill := UiKit.flat(col, 4)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("fill", fill)
	var tick := ColorRect.new()
	tick.color = Color(1, 1, 1, 0.85)
	tick.position = Vector2(BAR_W / BAR_MAX - 1.0, -3)
	tick.size = Vector2(2, 24)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(tick)
	return bar


## One side of the deal: the chosen assets (click to remove).
func _trade_side(title: String, team: Team, list: Array) -> Control:
	var p := UiKit.panel(UiKit.PANEL, 10)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size.y = 150
	var v := _vbox(6)
	p.add_child(v)
	var head := _row(8)
	head.add_child(UiKit.label("%s  (%d/%d)" % [title, list.size(), Trades.MAX_ASSETS], 16, UiKit.ACCENT))
	head.add_child(UiKit.team_chip(team, 13))
	v.add_child(head)
	if list.is_empty():
		v.add_child(UiKit.label("Click players or picks below to add them.", 15, UiKit.MUTED))
	for a in list:
		var asset: Dictionary = a
		var row := _row(10)
		if not Trades.is_pick(asset):
			row.add_child(Portrait.new(asset["soldier"], 34, team.color, team))
		var txt := _asset_line(asset)
		var b := UiKit.button("✕  " + txt, func():
			_trade_give = Trades.without(_trade_give, asset)
			_trade_get = Trades.without(_trade_get, asset)
			_trade_counter = {}
			_trade_rebuild(), 15)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		v.add_child(row)
	return p


func _asset_line(a: Dictionary) -> String:
	var s := _season()
	if Trades.is_pick(a):
		return s.trades.pick_text(s, a)
	var so: Soldier = a["soldier"]
	return "%s  -  %s  -  %d OVR  -  age %d  -  %s x %d" % [so.display_name(), Scheme.ROLE_NAMES[Scheme.best_role(so.stats)], so.best_ovr(), so.age,
		Contracts.money(so.contract.salary), so.contract.years]


## A team's roster and picks; clicking toggles an asset on that side of the deal.
func _asset_list(title: String, team: Team, mine: bool) -> Control:
	var s := _season()
	var tr := s.trades
	var v := _vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_section(title))
	var hdr := _row(PCOL_SEP)
	for c in [["", 24], ["SOLDIER", 200], ["POS", 70], ["AGE", 40], ["POT", 40], ["OVR", 46], ["CONTRACT", 110], ["ROLE", 90]]:
		var l := UiKit.label(c[0], 13, UiKit.MUTED)
		l.custom_minimum_size.x = c[1]
		hdr.add_child(l)
	v.add_child(hdr)
	var chosen := _trade_give if mine else _trade_get
	var roster: Array = team.roster.duplicate()
	roster.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	for so: Soldier in roster:
		var asset := Trades.player_asset(so)
		var ok := Trades.tradeable(so)
		var picked := Trades.contains(chosen, asset)
		var hb := _row(PCOL_SEP)
		var star := UiKit.label("★" if tr.on_block(s, team, so) else "", 16, UiKit.ACCENT)
		star.custom_minimum_size.x = 24
		hb.add_child(star)
		hb.add_child(_two_lines(so.display_name(), Color.WHITE if ok else UiKit.MUTED, "TRADE REQUESTED" if so.trade_request else "", 200, 15))
		hb.add_child(_big_cell(Scheme.ROLE_NAMES[Scheme.best_role(so.stats)], UiKit.TEXT, 70, 14))
		hb.add_child(_big_cell(str(so.age), UiKit.TEXT, 40, 15))
		hb.add_child(_big_cell(so.potential_letter(), potential_color(so.potential), 40, 18))
		hb.add_child(_big_cell(str(so.best_ovr()), UiKit.ovr_color(so.best_ovr()), 46, 20))
		hb.add_child(_two_lines(Contracts.money(so.contract.salary) if so.contract != null else "-", Color.WHITE,
			("%d yr%s" % [so.contract.years, "" if so.contract.years == 1 else "s"]) if ok else "EXPIRING", 110, 15))
		var slot := team.slot_of(so)
		hb.add_child(_two_lines(team.scheme.label_for_slot(slot) if slot != &"" else "Bench", Color.WHITE if slot != &"" else UiKit.MUTED,
			_status_text(so), 90, 14))
		var row := _row(6)
		var btn := _click_wrap(hb, func(): _toggle_asset(asset, mine), 46)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = not ok
		if picked:
			btn.add_theme_stylebox_override("normal", UiKit.flat(UiKit.ACCENT.darkened(0.65), 6, 2, UiKit.ACCENT))
		row.add_child(btn)
		row.add_child(UiKit.button("Card", func(): open_player(so), 13))
		v.add_child(row)
	var picks := tr.picks_of(s, team)
	if not picks.is_empty():
		v.add_child(_section("DRAFT PICKS"))
	for a in picks:
		var asset: Dictionary = a
		var picked := Trades.contains(chosen, asset)
		var hb := _row(PCOL_SEP)
		var sp := Control.new()
		sp.custom_minimum_size.x = 24
		hb.add_child(sp)
		var via := "" if asset["orig"] == team else "   via %s" % asset["orig"].abbrev
		hb.add_child(_two_lines(tr.pick_text(s, asset, false) + via, Color.WHITE, tr.pick_text(s, asset).get_slice("  -  ", 1), 420, 15))
		var btn := _click_wrap(hb, func(): _toggle_asset(asset, mine), 42)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if picked:
			btn.add_theme_stylebox_override("normal", UiKit.flat(UiKit.ACCENT.darkened(0.65), 6, 2, UiKit.ACCENT))
		v.add_child(btn)
	return v


func _toggle_asset(a: Dictionary, mine: bool) -> void:
	var list := _trade_give if mine else _trade_get
	if Trades.contains(list, a):
		list = Trades.without(list, a)
	elif list.size() >= Trades.MAX_ASSETS:
		hub.app.toast("At most %d assets per side." % Trades.MAX_ASSETS)
		return
	else:
		list = list + [a]
	if mine:
		_trade_give = list
	else:
		_trade_get = list
	_trade_counter = {}
	_trade_msg = ""
	_trade_rebuild()


func _counter_panel(ai: Team) -> Control:
	var s := _season()
	var c := _trade_counter
	var p := UiKit.panel(UiKit.PANEL_HI, 10)
	var v := _vbox(8)
	p.add_child(v)
	v.add_child(UiKit.label("COUNTER-OFFER FROM %s" % ai.name.to_upper(), 17, UiKit.ACCENT))
	v.add_child(UiKit.rich("[color=#8b97ab]YOU GIVE[/color]  %s" % UiKit.esc(", ".join(PackedStringArray(c["give"].map(func(a): return Trades.asset_text(s, a))))), 16))
	v.add_child(UiKit.rich("[color=#8b97ab]YOU GET[/color]   %s" % UiKit.esc(", ".join(PackedStringArray(c["get"].map(func(a): return Trades.asset_text(s, a))))), 16))
	var h := _row(10)
	h.add_child(UiKit.button("Accept Counter", func():
		var err := s.trades.validate(s, s.user_team(), c["give"], ai, c["get"])
		if err != "":
			hub.app.toast(err)
			return
		s.trades.execute(s, s.user_team(), c["give"], ai, c["get"])
		hub.app.toast("Trade complete with %s." % ai.name)
		_trade_give = []
		_trade_get = []
		_trade_counter = {}
		_trade_msg = "Trade complete. Welcome to the new guys."
		_trade_msg_color = UiKit.GOOD
		_trade_rebuild(), 16))
	h.add_child(UiKit.button("Load into builder", func():
		_trade_give = c["give"]
		_trade_get = c["get"]
		_trade_counter = {}
		_trade_rebuild(), 15))
	h.add_child(UiKit.button("Decline", func():
		_trade_counter = {}
		_trade_msg = ""
		_trade_rebuild(), 15))
	v.add_child(h)
	return p


func trade_offers() -> Control:
	var s := _season()
	var tr := s.trades
	var v := _vbox(12)
	v.add_child(UiKit.label("Offers from other teams. They expire when the week ends.", 17, Color.WHITE))
	if tr.offers.is_empty():
		v.add_child(UiKit.label("No offers right now. Put players on the trade block to draw interest.", 16, UiKit.MUTED))
	for o in tr.offers.duplicate():
		var offer: Dictionary = o
		var team: Team = offer["team"]
		var p := UiKit.panel(UiKit.PANEL, 10)
		var pv := _vbox(8)
		p.add_child(pv)
		pv.add_child(UiKit.team_chip(team, 16))
		pv.add_child(UiKit.rich("[color=#8b97ab]THEY OFFER[/color]   [color=white]%s[/color]" % UiKit.esc(", ".join(PackedStringArray(offer["give"].map(func(a): return Trades.asset_text(s, a))))), 17))
		pv.add_child(UiKit.rich("[color=#8b97ab]FOR YOUR[/color]     [color=white]%s[/color]" % UiKit.esc(", ".join(PackedStringArray(offer["get"].map(func(a): return Trades.asset_text(s, a))))), 17))
		var h := _row(10)
		h.add_child(UiKit.button("Accept", func():
			var err := tr.accept_offer(s, offer)
			hub.app.toast(err if err != "" else "Trade complete with %s." % team.name)
			hub.replace("Trade Offers", trade_offers), 16))
		h.add_child(UiKit.button("Counter in builder", func():
			_trade_partner = team
			_trade_give = offer["get"].duplicate()
			_trade_get = offer["give"].duplicate()
			_trade_counter = {}
			_trade_msg = ""
			hub.open("Trade Center", trade_center), 15))
		h.add_child(UiKit.button("Decline", func():
			tr.offers.erase(offer)
			hub.replace("Trade Offers", trade_offers), 15))
		pv.add_child(h)
		v.add_child(p)
	return v


func trade_block() -> Control:
	var s := _season()
	var tr := s.trades
	var user := s.user_team()
	var v := _vbox(8)
	v.add_child(UiKit.label("Put players on the block and AI teams send you offers for them (check Trade Offers each week).", 17, Color.WHITE))
	var roster: Array = user.roster.duplicate()
	roster.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	for so: Soldier in roster:
		var p := so
		var row := _row(12)
		row.add_child(Portrait.new(so, 40, user.color, user))
		var nm := _two_lines(so.display_name(), Color.WHITE, "%s  -  age %d  -  %d OVR  -  POT %s" % [Scheme.ROLE_NAMES[Scheme.best_role(so.stats)], so.age, so.best_ovr(), so.potential_letter()], 360, 16)
		row.add_child(nm)
		var ctext := ("%s x %d" % [Contracts.money(so.contract.salary), so.contract.years]) if Trades.tradeable(so) else "EXPIRING"
		row.add_child(_big_cell(ctext, UiKit.TEXT, 130, 15))
		if so.trade_request:
			row.add_child(_big_cell("TRADE REQUESTED", UiKit.ACCENT, 170, 14))
		var on := tr.block.has(so.id)
		var b := UiKit.button("★ On the block" if on else "Add to block", func():
			if tr.block.has(p.id):
				tr.block.erase(p.id)
			else:
				tr.block[p.id] = true
			hub.replace("Trade Block", trade_block), 15)
		b.custom_minimum_size.x = 170
		b.disabled = not Trades.tradeable(so)
		if on:
			UiKit.style_button(b, UiKit.ACCENT.darkened(0.55), Color.WHITE, 6)
		row.add_child(b)
		row.add_child(UiKit.button("Shop him", func(): open_trade(null, {}, Trades.player_asset(p)), 14))
		v.add_child(row)
	return v


func trade_log() -> Control:
	var s := _season()
	var v := _vbox(10)
	var hist: Array = s.trades.history
	if hist.is_empty():
		v.add_child(UiKit.label("No trades yet.", 17, UiKit.MUTED))
	for i in range(hist.size() - 1, -1, -1):
		var p := UiKit.panel(UiKit.PANEL, 8)
		p.add_child(UiKit.rich(trade_headline(hist[i]), 16))
		v.add_child(p)
	var cuts: Array = s.trades.moves.filter(func(m): return m["kind"] == &"cut")
	if not cuts.is_empty():
		v.add_child(_section("ROSTER CUTS  -  AI teams over the limit shop their surplus for picks, then release whoever nobody wants"))
		for i in range(cuts.size() - 1, -1, -1):
			var m: Dictionary = cuts[i]
			var so: Soldier = m["soldier"]
			v.add_child(UiKit.rich("[color=#ef4444]CUT[/color]  [color=#8b97ab]%d %s[/color]   [color=white]%s[/color] released %s (%d OVR, age %d)." % [
				m["year"], m["when"], UiKit.esc(m["team"].name), UiKit.esc(so.display_name()), so.best_ovr(), so.age], 15))
	return v


## BBCode news line for one trade log entry, with player reactions.
func trade_headline(e: Dictionary) -> String:
	var a: Team = e["a"]
	var b: Team = e["b"]
	var t := "[color=#f97316]TRADE[/color]  [color=#8b97ab]%d %s[/color]   [color=white]%s[/color] send %s to [color=white]%s[/color] for %s." % [
		e["year"], e["when"], UiKit.esc(a.name), UiKit.esc(_join_or_nothing(e["a_gave"])), UiKit.esc(b.name), UiKit.esc(_join_or_nothing(e["b_gave"]))]
	for r in e["reactions"]:
		var so: Soldier = r["soldier"]
		match r["mood"]:
			"upset":
				t += "\n   [color=#ef4444]%s is upset to leave %s.[/color]" % [UiKit.esc(so.display_name()), r["from"].abbrev]
			"relieved":
				t += "\n   [color=#22c55e]%s got the fresh start he asked for.[/color]" % UiKit.esc(so.display_name())
			"thrilled":
				t += "\n   [color=#22c55e]%s is thrilled to join a stronger team.[/color]" % UiKit.esc(so.display_name())
	return t


static func _join_or_nothing(list: Array) -> String:
	return "nothing" if list.is_empty() else ", ".join(PackedStringArray(list))

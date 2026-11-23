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
	hb.add_child(Portrait.new(p, 68, UiKit.ACCENT, team))
	var info := _vbox(0)
	info.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(info)
	info.add_child(UiKit.display(("\"%s\"  %s" % [p.callsign, p.last_name]).to_upper(), 36, Color.WHITE, true))
	var role := Scheme.best_role(p.stats)
	info.add_child(_label("%s %s   ·   Age %d   ·   %s" % [
		Archetypes.find(s.player_archetype)["name"], Scheme.ROLE_NAMES[role], p.age, team.name] 		+ (("   ·   Story: %s" % Backstory.story_name(p.backstory)) if p.backstory != &"" else ""), 15, Color(1, 1, 1, 0.72)))
	if PlayerLegacy.retired(s):
		info.add_child(_label("RETIRED  ·  %s" % _verdict_text(s), 15, UiKit.GOLD))
	else:
		var st := PlayerCoach.status(s)
		info.add_child(_label("%s   ·   %s" % [s.record_text(team), STATUS_NAMES[st["where"]]], 15, STATUS_COLORS[st["where"]]))
	hb.add_child(hub._ovr_dial(p.best_ovr(), "Overall"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(gap)
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


## Career Home: all about you. A banner (where you stand), your gauges, last game and season on the left, the next game and
## what to do this week in the middle, and a news pane that only carries your own news on the right.
## `actions` is the hub's Preview / Sim To / Play row.
func home_dashboard(actions: Control) -> Control:
	var s := _season()
	var top := _hbox(18)
	top.name = "CareerDashboard"
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if PlayerLegacy.retired(s):
		var col := _vbox(10)
		col.custom_minimum_size.x = COL_W
		top.add_child(_retired_left(col))
		top.add_child(_news_pane())
		return top
	var left := _vbox(12)
	left.name = "TodoColumn"
	left.custom_minimum_size.x = COL_W
	left.add_child(_banner())
	left.add_child(_vitals_grid(s.player))
	left.add_child(UiKit.heading("Last Game", 20))
	left.add_child(_last_game_card())
	left.add_child(UiKit.heading("This Season", 20))
	left.add_child(_season_card())
	top.add_child(left)
	var mid := _vbox(12)
	mid.custom_minimum_size.x = COL_W
	mid.add_child(UiKit.heading("Next Up", 20))
	mid.add_child(_next_game_card())
	mid.add_child(actions)
	mid.add_child(UiKit.heading("This Week", 20))
	for t in _todos():
		mid.add_child(t)
	top.add_child(mid)
	top.add_child(_news_pane())
	var i := 0
	for c in left.get_children():
		UiKit.fade_in(c, 0.04 * i, 0.25)
		i += 1
	return top


## The banner at the top of the dashboard: your status, what the coach says, the big OVR and the Hall of Fame bar.
func _banner() -> Control:
	var s := _season()
	var p := s.player
	var team := s.user_team()
	var st := PlayerCoach.status(s)
	var color: Color = STATUS_COLORS[st["where"]]
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = COL_W
	panel.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, 10, 1, Color(color, 0.7)))
	var back := UiKit.backdrop(Color(color, 0.3), UiKit.PANEL, true, color)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(back)
	var v := _vbox(8)
	panel.add_child(_wrap(v, 16))
	var top := _hbox(12)
	v.add_child(top)
	var left := _vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UiKit.display(STATUS_NAMES[st["where"]], 34, color, true))
	left.add_child(_label("%s  ·  %s" % [team.name, s.record_text(team)], 14, Color(1, 1, 1, 0.7)))
	top.add_child(left)
	var ovr := _vbox(0)
	var cap := _label("OVR", 12, Color(1, 1, 1, 0.7))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ovr.add_child(cap)
	var big := UiKit.display(str(p.best_ovr()), 56, UiKit.ovr_color(p.best_ovr()), true)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ovr.add_child(big)
	top.add_child(ovr)
	var msg := _label(String(st["text"]), 15, UiKit.TEXT)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size.x = COL_W - 34
	v.add_child(msg)
	if s.player_start_ovr > 0:
		var d := p.best_ovr() - s.player_start_ovr
		v.add_child(_label("%+d OVR since you were drafted" % d, 13, UiKit.GOOD if d > 0 else UiKit.MUTED))
	var tr := PlayerLegacy.trajectory(s)
	var hof := _hbox(10)
	hof.add_child(_label("HALL OF FAME", 11, UiKit.MUTED))
	hof.add_child(Meter.new(float(tr["score"]), maxf(1.0, float(tr["threshold"])), UiKit.GOLD, 0.0, 8.0))
	hof.add_child(_label("%d / %d" % [roundi(float(tr["score"])), roundi(float(tr["threshold"]))], 12, UiKit.GOLD))
	v.add_child(hof)
	return panel


## Two-by-two gauges for the home page: XP, the next star, fatigue and wear.
func _vitals_grid(p: Soldier) -> Control:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.custom_minimum_size.x = COL_W
	var xp: Array = Progression.xp_progress(p)
	g.add_child(_gauge("XP", "%d / %d" % [xp[0], xp[1]], float(xp[0]), float(xp[1]), UiKit.INFO, "%d skill points" % p.skill_points))
	if p.dev >= Soldier.DEV_MAX:
		g.add_child(_gauge("STARS", "MAX", 1.0, 1.0, UiKit.GOLD, "Top star reached"))
	else:
		var cost := WeeklyPlan.star_cost(p.dev, p)
		g.add_child(_gauge("NEXT STAR", "%d / %d" % [roundi(p.study_progress), roundi(cost)], p.study_progress, cost, UiKit.GOLD, "%d to go" % maxi(0, roundi(cost) - roundi(p.study_progress))))
	g.add_child(_gauge("FATIGUE", str(roundi(p.fatigue)), p.fatigue, 100.0, UiKit.BAD if p.fatigue > 60.0 else (UiKit.GOLD if p.fatigue > 40.0 else UiKit.GOOD), "lower is better"))
	g.add_child(_gauge("WEAR", str(roundi(p.wear)), p.wear, 100.0, UiKit.BAD if p.wear > 60.0 else (UiKit.GOLD if p.wear > 35.0 else UiKit.GOOD), Wear.tier_name(p.wear)))
	return g


## The next game as a compact card: week, opponent, where. Camp and the offseason say what is happening instead.
func _next_game_card() -> Control:
	var s := _season()
	var team := s.user_team()
	var card := _card(UiKit.ACCENT)
	var v := _vbox(4)
	card.add_child(_wrap(v, 14))
	if s.phase == Season.PHASE_OFFSEASON:
		v.add_child(UiKit.display("OFFSEASON", 26, UiKit.GOLD, true))
		return card
	if s.preseason_camp:
		v.add_child(UiKit.display("PRESEASON CAMP", 26, UiKit.GOLD, true))
		return card
	var m := s.next_match_for(team)
	if m == null:
		v.add_child(UiKit.display("NO GAME", 26, UiKit.MUTED, true))
		v.add_child(_label("Nothing left on the schedule this season.", 14, UiKit.MUTED))
		return card
	var opp: Team = m.away if m.home == team else m.home
	v.add_child(_label(s.week_label(m.week).to_upper(), 12, UiKit.MUTED))
	var row := _hbox(14)
	row.add_child(UiKit.team_logo(opp, 54))
	var info := _vbox(0)
	info.add_child(UiKit.display(("%s %s" % ["vs" if m.home == team else "at", opp.name]).to_upper(), 24, Color.WHITE, true))
	info.add_child(_label("%s  ·  %s" % [s.record_text(opp), "Home" if m.home == team else "Away"], 13, UiKit.MUTED))
	row.add_child(info)
	v.add_child(row)
	return card


## YOUR NEWS: only things that happened to you (coach calls, stories, sponsors, money, caps) and your game results,
## newest first. Scrolls inside a fixed-height panel.
func _news_pane() -> Control:
	var s := _season()
	var box := _vbox(8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(430, 0)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(UiKit.heading("Your News", 20))
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiKit.flat(Color(UiKit.PANEL, 0.85), 8, 1, Color(1, 1, 1, 0.08)))
	frame.custom_minimum_size = Vector2(430, 0)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(frame)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(sc)
	var list := _vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_wrap(list, 10))
	var items: Array = []
	var n := 0
	for note in s.player_notes:
		items.append({"year": int(note["year"]), "week": int(note["week"]), "text": String(note["text"]), "kind": "note", "n": n})
		n += 1
	for e in s.player_log:
		var text := ""
		var good := true
		if e["played"]:
			good = bool(e["won"])
			text = "%s %s vs %s, %s. Grade %s: %d K, %d D, %d A%s." % ["Won" if e["won"] else "Lost", e["score_line"], e["opp"].name, s.week_label(int(e["week"])), e["letter"], e["kills"], e["deaths"], e["assists"], ", MVP" if e["mvp"] else ""]
		else:
			good = false
			text = "Did not play vs %s (%s): %s." % [e["opp"].name, s.week_label(int(e["week"])), e["reason"]]
		items.append({"year": int(e["year"]), "week": int(e["week"]), "text": text, "kind": "game_win" if good and e["played"] else ("game_dnp" if not e["played"] else "game_loss"), "n": n})
		n += 1
	items.sort_custom(func(a, b): return (int(a["year"]) * 1000 + int(a["week"])) * 10000 + int(a["n"]) > (int(b["year"]) * 1000 + int(b["week"])) * 10000 + int(b["n"]))
	if items.is_empty():
		list.add_child(_label("Nothing yet.", 14, UiKit.MUTED))
	var shown := 0
	for it in items:
		if shown >= 40:
			break
		shown += 1
		list.add_child(_news_row(s, it))
	return box


func _news_row(s: Season, it: Dictionary) -> Control:
	var colors := {"note": UiKit.INFO, "game_win": UiKit.GOOD, "game_loss": UiKit.BAD, "game_dnp": UiKit.MUTED}
	var c: Color = colors[it["kind"]]
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiKit.flat(Color(c, 0.08), 4, 0, Color.TRANSPARENT))
	var h := _hbox(10)
	row.add_child(h)
	var bar := ColorRect.new()
	bar.color = c
	bar.custom_minimum_size = Vector2(4, 0)
	h.add_child(bar)
	var v := _vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var w := int(it["week"])
	var when := "%d  ·  %s" % [it["year"], s.week_label(w) if w >= 1 and w <= s.total_weeks() else "Offseason"]
	v.add_child(_label(when.to_upper(), 11, UiKit.MUTED))
	var t := _label(String(it["text"]), 14, UiKit.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 360
	v.add_child(t)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 5)
	m.add_theme_constant_override("margin_bottom", 5)
	m.add_child(v)
	h.add_child(m)
	return row


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
		card.add_child(_wrap(_label("No games yet.", 15, UiKit.MUTED)))
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
			out.append(_todo("Raise a cap", "No group can take a raise at your age", UiKit.TRIM, func(): open_cap_raise()))
	if s.phase == Season.PHASE_OFFSEASON or s.preseason_camp:
		if not p.camp_plan_confirmed:
			out.append(_todo("Set your camp plan", "", UiKit.GOLD, func(): open_plan(true), true))
		else:
			out.append(_todo("Camp plan", _plan_summary(p.camp_plan, true), UiKit.TRIM, func(): open_plan(true)))
	elif not p.plan_confirmed:
		out.append(_todo("Set your weekly plan", "", UiKit.GOLD, func(): open_plan(false), true))
	else:
		out.append(_todo("Weekly plan", _plan_summary(p.plan, true), UiKit.TRIM, func(): open_plan(false)))
	if s.phase != Season.PHASE_OFFSEASON and not s.preseason_camp and WarmUp.opponent(s) != null:
		var w_err := WarmUp.error(s)
		if w_err == "":
			out.append(_todo("Warm up", "", UiKit.GOLD, func(): open_warmup(), true))
		elif not p.warmup.is_empty() and int(p.warmup.get("key", 0)) == WarmUp.week_key(s):
			out.append(_todo("Warm-up", "%s: %s" % [String(Stats.GROUP_LABELS[p.warmup["group"]]), ("+%d this match" % int(p.warmup["bonus"])) if int(p.warmup["bonus"]) > 0 else "no bonus"], UiKit.TRIM, func(): open_warmup()))
	if PlayerRequest.error(s) == "" and not PlayerRequest.reasons(s).is_empty():
		out.append(_todo("Trade request", "", UiKit.TRIM, func(): open_request()))
	if not p.stories.is_empty():
		out.append(_todo("Stories", "%d decision%s waiting" % [p.stories.size(), "" if p.stories.size() == 1 else "s"], UiKit.GOLD, func(): open_stories(), true))
	if not p.offers.is_empty():
		out.append(_todo("Sponsors", "%d offer%s waiting" % [p.offers.size(), "" if p.offers.size() == 1 else "s"], UiKit.GOLD, func(): open_sponsors(), true))
	else:
		out.append(_todo("Sponsors", "%d deal%s  ·  %s" % [p.deals.size(), "" if p.deals.size() == 1 else "s", Sponsors.money_text(p.cash)], UiKit.TRIM, func(): open_sponsors()))
	out.append(_todo("Money", "%s  ·  %d thing%s you pay for or own" % [Sponsors.money_text(p.cash), _asset_count(p), "" if _asset_count(p) == 1 else "s"], UiKit.TRIM, func(): open_assets()))
	out.append(_todo("Loadout", "Base %d, gear %+d, effective %d" % [p.base_ovr(), p.best_ovr() - p.base_ovr(), p.best_ovr()], UiKit.TRIM, func(): open_loadout()))
	var notes := s.player_notes
	if not notes.is_empty():
		out.append(_todo("Coach", String(notes[-1]["text"]), UiKit.GOLD, func(): open_game_log()))
	out.append(_todo("Game Log", "", UiKit.TRIM, func(): open_game_log()))
	out.append(_todo("Milestones", "%d reached" % s.player_milestones.size(), UiKit.TRIM, func(): open_milestones()))
	if s.phase == Season.PHASE_OFFSEASON:
		out.append(_todo("Retire?", "", UiKit.GOLD, func(): open_retire()))
	return out


func _todo(title: String, sub: String, accent: Color, cb: Callable, urgent := false) -> Button:
	var b := UiKit.row_tile(title, Color("#f97316") if urgent else accent, cb, 46, sub)
	b.tooltip_text = sub
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
	flow.add_child(UiKit.tile("My Player", "OVR %d  ·  %d SP" % [p.best_ovr(), p.skill_points], hub.TILE, UiKit.ACCENT, func(): open_my_player()))
	var sm := PlayerGrade.summary(PlayerGrade.log_for(s))
	flow.add_child(UiKit.tile("Game Log", "%d played  ·  avg %s" % [sm["games"], sm["letter"]], hub.TILE, UiKit.ACCENT, func(): open_game_log()))
	var cs := "No contract" if p.contract == null else "%s  ·  %d yr" % [Contracts.money(p.contract.salary), p.contract.years]
	flow.add_child(UiKit.tile("Contract", "%s\nGreen Team deal" % cs if p.contract != null and p.contract.green else cs, hub.TILE, UiKit.ACCENT, func(): open_contract()))
	var tr := PlayerLegacy.trajectory(s)
	var pace_text := "on pace" if tr["on_pace"] and tr["has_pace"] else "below pace"
	flow.add_child(UiKit.tile("Hall of Fame Path", "%d / %d  ·  %s" % [roundi(float(tr["score"])), roundi(float(tr["threshold"])), pace_text], hub.TILE, UiKit.GOLD, func(): open_hof_path()))
	flow.add_child(UiKit.tile("Milestones", "%d of %d reached" % [s.player_milestones.size(), PlayerLegacy.MILESTONES.size()], hub.TILE, UiKit.ACCENT, func(): open_milestones()))
	flow.add_child(UiKit.tile("Career Recap", "", hub.TILE, UiKit.ACCENT, func(): open_recap()))
	if not PlayerLegacy.retired(s):
		flow.add_child(UiKit.tile("Retire", "Offseason only", hub.TILE, UiKit.MUTED, func(): open_retire()))
	v.add_child(flow)


# --- pages ----------------------------------------------------------------------------------------

var plan_ui: PlayerPlanPages


func _plan() -> PlayerPlanPages:
	if plan_ui == null:
		plan_ui = PlayerPlanPages.new()
		plan_ui.hub = hub
	return plan_ui


func open_plan(camp: bool) -> void:
	hub.open("Camp Plan" if camp else "Weekly Plan", func(): return _plan().plan_page(camp))


var gear_ui: PlayerGearPages


func _gear() -> PlayerGearPages:
	if gear_ui == null:
		gear_ui = PlayerGearPages.new()
		gear_ui.hub = hub
	return gear_ui


var warmup_ui: PlayerWarmupPages


func _warmup() -> PlayerWarmupPages:
	if warmup_ui == null:
		warmup_ui = PlayerWarmupPages.new()
		warmup_ui.hub = hub
	return warmup_ui


func open_warmup() -> void:
	hub.open("Warm-up", func(): return _warmup().warmup_page())


var request_ui: PlayerRequestPages


func open_request() -> void:
	if request_ui == null:
		request_ui = PlayerRequestPages.new()
		request_ui.hub = hub
	hub.open("Trade request", func(): return request_ui.request_page())


func open_loadout() -> void:
	hub.open("Loadout", func(): return _gear().loadout_page())


func open_assets() -> void:
	hub.open("Money", func(): return _gear().assets_page())


func _asset_count(p: Soldier) -> int:
	var n := 0
	for k in p.assets:
		n += int(p.assets[k])
	return n


func open_sponsors() -> void:
	hub.open("Sponsors", func(): return _gear().sponsors_page())


func open_stories() -> void:
	hub.open("Stories", func(): return _gear().stories_page())


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
	var cost := roundi(WeeklyPlan.star_cost(p.dev, p))
	return "%s  ·  next star: %d of %d study points (%d to go)" % [p.dev_text(), roundi(p.study_progress), cost, maxi(0, cost - roundi(p.study_progress))]


func open_my_player() -> void:
	hub.open("My Player", func(): return my_player())


func open_game_log() -> void:
	hub.open("Game Log", func(): return game_log())


func open_contract() -> void:
	hub.open("Contract", func(): return contract())


## A thin bar: a faint ghost up to `ghost` (a cap), then the solid fill up to `value`, both out of `maximum`.
class Meter extends Control:
	var value := 0.0
	var ghost := 0.0
	var maximum := 99.0
	var color := Color.WHITE

	func _init(v := 0.0, m := 99.0, c := Color.WHITE, g := 0.0, h := 10.0) -> void:
		value = v
		maximum = maxf(1.0, m)
		color = c
		ghost = g
		custom_minimum_size = Vector2(60, h)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.07))
		if ghost > 0.0:
			draw_rect(Rect2(0, 0, size.x * clampf(ghost / maximum, 0.0, 1.0), size.y), Color(color, 0.22))
		var w := size.x * clampf(value / maximum, 0.0, 1.0)
		draw_rect(Rect2(0, 0, w, size.y), color)
		draw_rect(Rect2(0, 0, w, size.y * 0.45), Color(1, 1, 1, 0.14))


## Ratings by group with the cap, skill-point spending, and the training intensity.
func my_player() -> Control:
	var s := _season()
	var p := s.player
	var team := s.user_team()
	var root := _vbox(8)
	root.name = "MyPlayer"
	root.custom_minimum_size.x = 1100
	root.add_child(_hero(s, p, team))
	root.add_child(_vitals(p))
	var cols := _hbox(18)
	root.add_child(cols)
	var left := _vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UiKit.heading("Ratings", 22))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	for g in Stats.GROUP_ORDER:
		grid.add_child(_group_row(p, g))
	var right := _vbox(4)
	right.custom_minimum_size.x = 330
	cols.add_child(right)
	right.add_child(UiKit.heading("Your week", 22))
	right.add_child(UiKit.primary_button("Weekly plan", func(): open_plan(false), 18))
	right.add_child(_label(_plan_summary(p.plan, p.plan_confirmed), 13, UiKit.MUTED))
	right.add_child(UiKit.button("Loadout and gear", func(): open_loadout(), 16))
	right.add_child(UiKit.heading("Wear and tear", 18))
	for g in Stats.GROUP_ORDER:
		var row := _hbox(8)
		var gname := _label(String(Stats.GROUP_LABELS[g]), 13, UiKit.TEXT)
		gname.custom_minimum_size.x = 100
		row.add_child(gname)
		var rl := _label(Wear.risk_text(p.wear, g), 13, UiKit.MUTED)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(rl)
		right.add_child(row)
	return root


## The top band: portrait, name, role, the big OVR and the badges (stars, brand, story, status).
func _hero(s: Season, p: Soldier, team: Team) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, 10, 1, Color(UiKit.accent_of(team), 0.6)))
	var back := UiKit.backdrop(Color(UiKit.accent_of(team), 0.55), UiKit.PANEL, true, UiKit.accent_of(team))
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(back)
	var h := _hbox(24)
	panel.add_child(_wrap(h, 10))
	h.add_child(Portrait.new(p, 96, UiKit.ACCENT, team))
	var mid := _vbox(4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(mid)
	mid.add_child(_label(p.full_name().to_upper(), 15, Color(1, 1, 1, 0.75)))
	mid.add_child(UiKit.display(("\"%s\"" % p.callsign).to_upper(), 40, Color.WHITE, true))
	var a := Archetypes.find(s.player_archetype)
	mid.add_child(_label("%s %s  ·  %s  ·  Age %d  ·  Level %d" % [a["name"], Scheme.ROLE_NAMES[Scheme.best_role(p.stats)], team.name, p.age, p.level], 15, Color(1, 1, 1, 0.8)))
	var badges := _hbox(14)
	badges.add_child(DevInsignia.make(p.dev, 15.0))
	badges.add_child(_chip("BRAND  %s" % WeeklyPlan.tier_name(p.brand).to_upper(), UiKit.GOLD))
	if p.backstory != &"":
		badges.add_child(_chip(Backstory.story_name(p.backstory).to_upper(), UiKit.INFO))
	var st := PlayerCoach.status(s)
	badges.add_child(_chip(STATUS_NAMES[st["where"]], STATUS_COLORS[st["where"]]))
	mid.add_child(badges)
	var ovr := _vbox(0)
	ovr.alignment = BoxContainer.ALIGNMENT_CENTER
	var cap := _label("OVERALL", 13, Color(1, 1, 1, 0.7))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovr.add_child(cap)
	var big := UiKit.display(str(p.best_ovr()), 64, UiKit.ovr_color(p.best_ovr()), true)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovr.add_child(big)
	var gear := p.best_ovr() - p.base_ovr()
	var sub := _label("base %d  ·  gear %+d" % [p.base_ovr(), gear], 13, UiKit.GOOD if gear > 0 else Color(1, 1, 1, 0.6))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovr.add_child(sub)
	var sp := _label("%d skill points" % p.skill_points, 14, UiKit.INFO)
	sp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovr.add_child(sp)
	h.add_child(ovr)
	return panel


func _chip(text: String, color: Color) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.flat(Color(color, 0.16), 4, 1, Color(color, 0.7)))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 2)
	m.add_theme_constant_override("margin_bottom", 2)
	m.add_child(_label(text, 12, color))
	pc.add_child(m)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return pc


## Four gauges: XP to the next level, study toward the next star, fatigue and wear.
func _vitals(p: Soldier) -> Control:
	var row := _hbox(12)
	var xp: Array = Progression.xp_progress(p)
	row.add_child(_gauge("XP TO NEXT LEVEL", "%d / %d" % [xp[0], xp[1]], float(xp[0]), float(xp[1]), UiKit.INFO, "+%d skill points" % Progression.SKILL_POINTS_PER_LEVEL))
	if p.dev >= Soldier.DEV_MAX:
		row.add_child(_gauge("DEV STARS", "MAX", 1.0, 1.0, UiKit.GOLD, "Top star reached"))
	else:
		var cost := WeeklyPlan.star_cost(p.dev, p)
		row.add_child(_gauge("STUDY TO NEXT STAR", "%d / %d" % [roundi(p.study_progress), roundi(cost)], p.study_progress, cost, UiKit.GOLD,
			"%d to go for %s. Study, strong seasons and honors fill it" % [maxi(0, roundi(cost) - roundi(p.study_progress)), Soldier.dev_stars(p.dev + 1)]))
	row.add_child(_gauge("FATIGUE", str(roundi(p.fatigue)), p.fatigue, 100.0, UiKit.BAD if p.fatigue > 60.0 else (UiKit.GOLD if p.fatigue > 40.0 else UiKit.GOOD), "Rest, spa and a lighter plan bring it down"))
	row.add_child(_gauge("WEAR", str(roundi(p.wear)), p.wear, 100.0, UiKit.BAD if p.wear > 60.0 else (UiKit.GOLD if p.wear > 35.0 else UiKit.GOOD), Wear.tier_name(p.wear)))
	return row


func _gauge(caption: String, value: String, v: float, maximum: float, color: Color, hint: String) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, 8, 1, Color(color, 0.35)))
	var box := _vbox(2)
	card.add_child(_wrap(box, 8))
	box.add_child(_label(caption, 11, UiKit.MUTED))
	box.add_child(UiKit.display(value, 20, color, true))
	box.add_child(Meter.new(v, maximum, color, 0.0, 8.0))
	card.tooltip_text = hint
	return card


## One group as a card: its rating, a bar up to the cap, and every stat in it.
func _group_row(p: Soldier, g: StringName) -> Control:
	var upgradable := Stats.UPGRADABLE_GROUPS.has(g)
	var gr := p.group_rating(g)
	var b := Button.new()
	UiKit.style_button(b, UiKit.PANEL_HI, UiKit.ACCENT, 8, false)
	b.custom_minimum_size = Vector2(430, 86)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost := Progression.upgrade_cost(p, g)
	b.disabled = not Progression.can_place(p, g)
	var box := _vbox(3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	box.offset_top = 6
	box.offset_bottom = -6
	b.add_child(box)
	var line := _hbox(12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label(String(Stats.GROUP_LABELS[g]).to_upper(), 16, Color.WHITE if upgradable else UiKit.MUTED)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(title)
	var num := UiKit.display(str(gr), 28, UiKit.ovr_color(gr), true)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(num)
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
	var nl := _label(note, 14, note_color)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(nl)
	box.add_child(line)
	box.add_child(Meter.new(float(gr), 99.0, UiKit.ovr_color(gr), float(p.group_cap(g)) if upgradable else 0.0, 8.0))
	# Every stat in the group; one the archetype cannot grow any further shows in red.
	var stats := HFlowContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("h_separation", 12)
	for stat in Stats.GROUPS[g]:
		var maxed: bool = int(p.stats[stat]) >= p.stat_cap(stat) and upgradable
		var t := _label("%s %d" % [Stats.ABBREV[stat], p.stats[stat]], 12, UiKit.BAD if maxed else UiKit.MUTED)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	col.add_child(_todo("Career Recap", "", UiKit.TRIM, func(): open_recap()))
	if PlayerLegacy.verdict(s) == &"waiting":
		col.add_child(_todo("Wait for the Hall of Fame vote", "Play the league forward to %d" % PlayerLegacy.vote_year(s), UiKit.GOLD, func(): hub.wait_for_vote(), true))
	col.add_child(_todo("Milestones", "%d reached" % s.player_milestones.size(), UiKit.TRIM, func(): open_milestones()))
	col.add_child(_todo("Back to title", "", UiKit.MUTED, func(): hub.app.show_title()))
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
		["Production", "production", HallOfFame.PRODUCTION_POINTS],
		["Awards", "awards", HallOfFame.AWARDS_CAP],
		["Titles", "titles", HallOfFame.TITLES_CAP],
		["Peak", "peak", HallOfFame.PEAK_POINTS],
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
		# The criteria blurb for each part (part[3]) is stashed in HelpText.
		root.add_child(row)
	root.add_child(UiKit.heading("Honors", 20))
	var honors: Array = t["honors"]
	if honors.is_empty():
		root.add_child(_label("None yet.", 15, UiKit.MUTED))
	else:
		root.add_child(_label(", ".join(honors), 15, UiKit.TEXT))
	return root


func milestones() -> Control:
	var s := _season()
	var root := _vbox(8)
	root.custom_minimum_size.x = 1400
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
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 2)
	root.add_child(grid)
	for m in PlayerLegacy.MILESTONES:
		if not PlayerLegacy.achieved(s, m["id"]).is_empty():
			continue
		var row2 := _hbox(14)
		var nm2 := _label(String(m["name"]), 18, Color.WHITE)
		nm2.custom_minimum_size.x = 170
		row2.add_child(nm2)
		var pr := _label(PlayerLegacy.progress_text(s, m), 14, UiKit.INFO)
		pr.custom_minimum_size.x = 120
		row2.add_child(pr)
		row2.add_child(_label(String(m["desc"]), 14, UiKit.MUTED))
		grid.add_child(row2)
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

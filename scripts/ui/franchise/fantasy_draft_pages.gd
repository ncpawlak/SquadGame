class_name FantasyDraftPages
extends RefCounted
## Fantasy draft UI: the Fantasy Draft Room (15-round snake draft of every league player at franchise
## start) and the Set Roster screen (free roster <-> green team moves after the draft).
##
## The engine (scripts/season/fantasy_draft.gd, FantasyDraft) is used through the shared contract and
## kept untyped here (`season.fantasy_draft`), so this file does not depend on load order.

const BOARD_ROWS := 60
const ROLE_OPTIONS := [[-1, "All"], [Scheme.Role.FRONTMAN, "Frontman"], [Scheme.Role.CENTER, "Center"], [Scheme.Role.FLEX, "Flex"]]

var hub: Control  # hub.gd

var sort_key: StringName = &"ovr"
var sort_desc := true
var role_filter := -1
var search := ""
var selected: Soldier = null

var _board_box: VBoxContainer
var _pick_btn: Button
var _sel_label: Label
var _suggest: Soldier = null


# --- state helpers ---------------------------------------------------------------

static func is_drafting(season: Season) -> bool:
	return season.get(&"fantasy_draft_state") == &"drafting"


static func roster_set_open(season: Season) -> bool:
	return bool(season.get(&"roster_set_open"))


func _season() -> Season:
	return hub.season


func _row(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _section(text: String) -> Label:
	return UiKit.label(text, 16, UiKit.ACCENT)


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UiKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _role_name(s: Soldier) -> String:
	return Scheme.ROLE_NAMES[Scheme.best_role(s.stats)]


func _seg(text: String, active: bool, cb: Callable, size := 15) -> Button:
	var b := UiKit.button(text, cb, size)
	if active:
		UiKit.style_primary(b)
	else:
		UiKit.style_skewed(b)
	return b


func _refresh() -> void:
	hub.replace("Fantasy Draft", room, true)


# --- Fantasy Draft Room -------------------------------------------------------------

func open_room() -> void:
	hub.open("Fantasy Draft", room, true)


func room() -> Control:
	var s := _season()
	var d = s.get(&"fantasy_draft")
	var v := _vbox(12)
	if d == null:
		v.add_child(UiKit.label("No fantasy draft is running.", 20, UiKit.MUTED))
		return v
	if d.is_complete():
		return _recap(d)
	var team: Team = d.current_team()
	var mine: bool = d.user_on_clock()
	if not mine:
		selected = null
	# On-the-clock banner.
	var head := "%s[font_size=26][color=%s]%s[/color][/font_size]   Round %d of %d  -  Pick %d" % [UiKit.logo_bb(team, 40),
		"#f59e0b" if mine else "white", "YOU ARE ON THE CLOCK" if mine else "On the clock: " + UiKit.esc(team.name),
		d.round_number(), d.ROUNDS, d.pick_number()]
	if not mine:
		var nxt := -1
		for i in range(d.pick_index, d.order.size()):
			if d.order[i] == s.user_team():
				nxt = i + 1
				break
		if nxt > 0:
			head += "   -  [color=#f59e0b]Your next pick: #%d (%d away)[/color]" % [nxt, nxt - d.pick_number()]
	var banner := UiKit.rich(head, 16)
	banner.name = "FantasyBanner"
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(banner)
	Fx.flash(banner, 0.5, 0.45)
	# Actions.
	var actions := _row(10)
	_pick_btn = UiKit.action_button("Draft Selected Player", _draft_selected, 16)
	_pick_btn.name = "DraftSelected"
	_pick_btn.disabled = true
	actions.add_child(_pick_btn)
	var sim_next := UiKit.button("Sim Next Pick", _sim_next, 16)
	sim_next.name = "SimNext"
	sim_next.disabled = mine
	actions.add_child(sim_next)
	var sim_mine := UiKit.button("Sim to My Next Pick", _sim_to_mine, 16)
	sim_mine.name = "SimToMine"
	sim_mine.disabled = mine or d.picks_left_for(s.user_team()) <= 0
	actions.add_child(sim_mine)
	var sim_end := UiKit.button("Sim to End", _sim_end, 16)
	sim_end.name = "SimToEnd"
	actions.add_child(sim_end)
	var sug := UiKit.button("Suggested Pick", _suggest_pick, 16)
	sug.name = "SuggestPick"
	sug.disabled = not mine
	actions.add_child(sug)
	v.add_child(actions)
	_sel_label = UiKit.label("", 16, UiKit.MUTED)
	v.add_child(_sel_label)
	# Board (left) and side column (right).
	var cols := _row(18)
	var left := _vbox(8)
	left.add_child(_section("AVAILABLE PLAYERS"))
	left.add_child(_filter_row())
	_board_box = _vbox(4)
	left.add_child(_board_box)
	cols.add_child(left)
	var right := _vbox(8)
	right.custom_minimum_size.x = 430
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(_section("YOUR PICK SLOTS"))
	right.add_child(_slots(d))
	right.add_child(_section("YOUR PICKS  (%d)" % d.team_picks(s.user_team()).size()))
	right.add_child(_picks_list(d.team_picks(s.user_team()), 12))
	right.add_child(_section("RECENT PICKS"))
	var res: Array = d.results()
	right.add_child(_picks_list(res.slice(maxi(0, res.size() - 12)), 12, true))
	cols.add_child(right)
	v.add_child(cols)
	_fill_board()
	_update_selection()
	return v


func _filter_row() -> Control:
	var v := _vbox(6)
	var r := _row(8)
	for o in ROLE_OPTIONS:
		var val: int = o[0]
		var b := _seg(o[1], role_filter == val, func():
			role_filter = val
			_refresh(), 15)
		b.custom_minimum_size.x = 100
		r.add_child(b)
	var le := LineEdit.new()
	le.name = "FantasySearch"
	le.placeholder_text = "Search name..."
	le.text = search
	le.custom_minimum_size.x = 220
	le.text_changed.connect(func(t: String):
		search = t
		_fill_board())
	r.add_child(le)
	v.add_child(r)
	v.add_child(UiKit.label("Click a column header to sort.", 13, UiKit.MUTED))
	return v


func _sort_value(x: Soldier) -> Variant:
	match sort_key:
		&"name": return x.full_name().to_lower()
		&"pot": return x.potential_ovr()
		&"age": return x.age
		&"ovr": return x.best_ovr()
	return x.group_rating(sort_key)


func _board_list() -> Array:
	var d = _season().get(&"fantasy_draft")
	var out: Array = []
	var q := search.strip_edges().to_lower()
	for x in d.available():
		if role_filter != -1 and int(Scheme.best_role(x.stats)) != role_filter:
			continue
		if q != "" and not x.full_name().to_lower().contains(q):
			continue
		out.append(x)
	out.sort_custom(func(a: Soldier, b: Soldier):
		var va: Variant = _sort_value(a)
		var vb: Variant = _sort_value(b)
		if va == vb:
			return a.best_ovr() > b.best_ovr()
		return va > vb if sort_desc else va < vb)
	return out


const COL_NAME := 190
const COL_AGE := 44
const COL_POT := 86
const COL_OVR := 60
const COL_GROUP := 62
const COL_VIEW := 70
const ROW_H := 60


func _cols() -> Array:
	var cols := [["PLAYER", COL_NAME, &"name"], ["AGE", COL_AGE, &"age"], ["POT", COL_POT, &"pot"], ["OVR", COL_OVR, &"ovr"]]
	for g in Stats.GROUP_ORDER:
		cols.append([Stats.GROUP_LABELS[g].to_upper().left(4), COL_GROUP, g])
	return cols


func _set_sort(key: StringName) -> void:
	if sort_key == key:
		sort_desc = not sort_desc
	else:
		sort_key = key
		sort_desc = key != &"age" and key != &"name"
	_fill_board()


## Clickable column headers: the active column shows an arrow.
func _board_header() -> Control:
	var panel := PanelContainer.new()
	var sb := UiKit.flat(UiKit.PANEL_HI, 4)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.content_margin_left = 14
	sb.content_margin_right = COL_VIEW + 28
	panel.add_theme_stylebox_override("panel", sb)
	var hb := _row(FranchisePages.PCOL_SEP)
	for c in _cols():
		var key: StringName = c[2]
		var active := sort_key == key
		var b := Button.new()
		b.name = "Sort_" + String(key)
		b.text = c[0] + ((" v" if sort_desc else " ^") if active else "")
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(c[1], 30)
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", UiKit.ACCENT if active else UiKit.MUTED)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
		for state in ["normal", "hover", "pressed"]:
			var f := UiKit.flat(Color.TRANSPARENT if state == "normal" else UiKit.LINE, 4)
			f.content_margin_left = 0
			f.content_margin_right = 0
			f.content_margin_top = 2
			f.content_margin_bottom = 2
			b.add_theme_stylebox_override(state, f)
		b.set_meta(&"skip_autofocus", true)
		b.pressed.connect(func(): _set_sort(key))
		hb.add_child(b)
	panel.add_child(hb)
	return panel


func _board_row(x: Soldier) -> Control:
	var pg: FranchisePages = hub.pages
	var width := 28 + COL_VIEW + 14
	for c in _cols():
		width += int(c[1]) + FranchisePages.PCOL_SEP
	var btn := Button.new()
	UiKit.style_button(btn, UiKit.MINE if x == selected else UiKit.PANEL, UiKit.ACCENT, 6)
	btn.custom_minimum_size = Vector2(width, ROW_H)
	btn.pressed.connect(func():
		selected = x
		_fill_board()
		_update_selection())
	var hb := _row(FranchisePages.PCOL_SEP)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 14
	hb.offset_right = -(COL_VIEW + 22)
	hb.offset_top = 4
	hb.offset_bottom = -4
	btn.add_child(hb)
	hb.add_child(pg._two_lines(x.display_name(), Color.WHITE, _role_name(x), COL_NAME))
	hb.add_child(pg._big_cell(str(x.age), UiKit.TEXT, COL_AGE, 18))
	hb.add_child(pg._pot_cell(x, COL_POT))
	hb.add_child(pg._ovr_cell(x.best_ovr(), 0, COL_OVR))
	for g in Stats.GROUP_ORDER:
		hb.add_child(pg._rating_cell(x.group_rating(g), COL_GROUP))
	_add_view_button(btn, x)
	return btn


func _fill_board() -> void:
	if _board_box == null or not is_instance_valid(_board_box):
		return
	for c in _board_box.get_children():
		_board_box.remove_child(c)
		c.queue_free()
	var list := _board_list()
	if list.is_empty():
		_board_box.add_child(UiKit.label("Nobody matches.", 16, UiKit.MUTED))
		return
	_board_box.add_child(_board_header())
	for x in list.slice(0, BOARD_ROWS):
		_board_box.add_child(_board_row(x))
	if list.size() > BOARD_ROWS:
		_board_box.add_child(UiKit.label("Showing the top %d of %d. Search or filter to narrow it." % [BOARD_ROWS, list.size()], 14, UiKit.MUTED))


func _update_selection() -> void:
	var d = _season().get(&"fantasy_draft")
	var mine: bool = d != null and not d.is_complete() and d.user_on_clock()
	if is_instance_valid(_pick_btn):
		_pick_btn.disabled = not (mine and selected != null)
	if is_instance_valid(_sel_label):
		if not mine:
			_sel_label.text = "Not your pick: sim ahead to your next turn."
		elif selected == null:
			_sel_label.text = "Click a player on the board, then Draft Selected Player."
		else:
			_sel_label.text = "Selected: %s  (%s, age %d, OVR %d)" % [selected.full_name(), _role_name(selected), selected.age, selected.best_ovr()]


## A small "View" button pinned to the right edge of a row: opens that player's card.
func _add_view_button(row: Control, x: Soldier) -> void:
	var b := UiKit.button("View", func(): hub.pages.open_player(x), 14)
	b.name = "ViewPlayer"
	b.tooltip_text = "Open %s's player card" % x.full_name()
	b.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	b.offset_left = -(COL_VIEW + 8)
	b.offset_right = -8
	b.offset_top = -16
	b.offset_bottom = 16
	b.custom_minimum_size = Vector2(COL_VIEW, 32)
	row.add_child(b)


func _picks_list(picks: Array, limit: int, with_team := false) -> Control:
	var box := _vbox(2)
	if picks.is_empty():
		box.add_child(UiKit.label("None yet.", 15, UiKit.MUTED))
		return box
	var user := _season().user_team()
	var shown: Array = picks.duplicate()
	shown.reverse()
	# team_picks() may hand back pick dicts or bare soldiers; both are shown.
	shown = shown.map(func(p): return p if p is Dictionary else {"soldier": p, "team": user, "pick": 0, "round": 0})
	for p in shown.slice(0, limit):
		var x: Soldier = p["soldier"]
		var t: Team = p["team"]
		var line := "%s%s%s  (%s, %d)" % ["#%d  R%d   " % [p["pick"], p["round"]] if int(p["pick"]) > 0 else "", (t.abbrev + "  ") if with_team else "", x.full_name(), _role_name(x), x.best_ovr()]
		var r := _row(6)
		var l := UiKit.label(line, 15, UiKit.ACCENT if t == user else UiKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		r.add_child(l)
		r.add_child(UiKit.button("View", func(): hub.pages.open_player(x), 13))
		box.add_child(r)
	if picks.size() > limit:
		box.add_child(UiKit.label("+ %d more" % (picks.size() - limit), 14, UiKit.MUTED))
	return box


## Every slot the user holds in the snake: round, overall pick number and who they took (or when it comes up).
func _slots(d) -> Control:
	var user := _season().user_team()
	var made := {}
	for p in d.results():
		made[int(p["pick"])] = p["soldier"]
	var rows: Array = []
	var picked: Array = []
	var hl := {}
	var per_round: int = maxi(1, d.order.size() / d.ROUNDS)
	var next_found := false
	for i in d.order.size():
		if d.order[i] != user:
			continue
		var pick_no: int = int(i) + 1
		var who := ""
		if made.has(pick_no):
			who = made[pick_no].full_name()
			picked.append(made[pick_no])
		elif pick_no == d.pick_number():
			who = "ON THE CLOCK"
			hl[rows.size()] = UiKit.MINE
			next_found = true
			picked.append(null)
		else:
			var away: int = pick_no - d.pick_number()
			who = "%d pick%s away" % [away, "" if away == 1 else "s"]
			if not next_found:
				hl[rows.size()] = UiKit.MINE
				next_found = true
			picked.append(null)
		rows.append(["R%d" % (i / per_round + 1), "#%d" % pick_no, who])
	var tbl := UiKit.table(["RND", "PICK", "PLAYER"], rows, [50, 60, 230], hl, {},
		func(i: int):
			if picked[i] != null:
				hub.pages.open_player(picked[i]))
	tbl.name = "FantasySlots"
	return tbl


# --- actions -----------------------------------------------------------------------

func _draft_selected() -> void:
	var d = _season().get(&"fantasy_draft")
	if selected == null or not d.user_on_clock():
		return
	var who := selected
	var err: String = d.make_pick(who)
	if err != "":
		hub.app.toast(err)
		return
	selected = null
	hub.app.toast("You select %s (%s)." % [who.full_name(), _role_name(who)])
	hub.app.stamp("Drafted", who.full_name())
	_refresh()


func _suggest_pick() -> void:
	var d = _season().get(&"fantasy_draft")
	var x: Soldier = d.ai_choice(_season().user_team())
	if x == null:
		return
	selected = x
	_suggest = x
	search = ""
	role_filter = -1
	hub.app.toast("Suggested: %s (%s, OVR %d). Selected for you." % [x.full_name(), _role_name(x), x.best_ovr()])
	_fill_board()
	_update_selection()


func _sim_next() -> void:
	var d = _season().get(&"fantasy_draft")
	var p: Dictionary = d.sim_next()
	if not p.is_empty():
		hub.app.toast("%s select %s." % [(p["team"] as Team).name, (p["soldier"] as Soldier).full_name()])
	_refresh()


func _sim_to_mine() -> void:
	var d = _season().get(&"fantasy_draft")
	var made: Array = d.sim_to_user_pick()
	hub.app.toast("%d picks made." % made.size())
	_refresh()


func _sim_end() -> void:
	var d = _season().get(&"fantasy_draft")
	var made: Array = d.sim_to_end()
	hub.app.toast("%d picks made. The draft is complete." % made.size())
	_refresh()


# --- complete: final board + Continue ----------------------------------------------

func _recap(d) -> Control:
	var s := _season()
	var user := s.user_team()
	var v := _vbox(12)
	v.add_child(UiKit.label("Fantasy Draft complete", 28, Color.WHITE))
	v.add_child(_wrap("Every club has its roster. Continue to move on to training camp.", 16, UiKit.MUTED))
	var cont := UiKit.primary_button("Continue", _continue, 20)
	cont.name = "FantasyContinue"
	cont.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(cont)
	v.add_child(_section("YOUR DRAFT CLASS"))
	v.add_child(_picks_list(d.team_picks(user), 30))
	v.add_child(_section("FINAL BOARD"))
	var rows: Array = []
	var hl := {}
	var res: Array = d.results()
	for i in res.size():
		var p: Dictionary = res[i]
		var x: Soldier = p["soldier"]
		var t: Team = p["team"]
		rows.append([p["pick"], p["round"], t.name, x.full_name(), _role_name(x), x.age, x.best_ovr()])
		if t == user:
			hl[i] = UiKit.MINE
	v.add_child(UiKit.table(["PICK", "RD", "TEAM", "PLAYER", "ROLE", "AGE", "OVR"], rows, [60, 40, 260, 250, 110, 50, 60], hl))
	return v


func _continue() -> void:
	var s := _season()
	s.finish_fantasy_draft()
	hub.page_stack.clear()
	hub.refresh()
	hub.go_home()
	hub.app.toast("The fantasy draft is done. Training camp is open.")


# --- Set Roster ---------------------------------------------------------------------

func open_set_roster() -> void:
	hub.open("Set Roster", set_roster)


## Moves `x` between the roster and the green team for free. Only while Season.roster_set_open.
## Returns "" or the reason it failed.
static func move_error(season: Season, team: Team, x: Soldier, to_green: bool) -> String:
	if not roster_set_open(season):
		return "The roster window is closed."
	if to_green:
		if not team.roster.has(x):
			return "%s isn't on the roster." % x.full_name()
		if team.green_team.size() >= Team.GREEN_SIZE:
			return "The Green Team is full (%d)." % Team.GREEN_SIZE
	else:
		if not team.green_team.has(x):
			return "%s isn't on the Green Team." % x.full_name()
		if team.roster.size() >= Team.ROSTER_SIZE:
			return "The roster is full (%d)." % Team.ROSTER_SIZE
	return ""


static func move(season: Season, team: Team, x: Soldier, to_green: bool) -> String:
	var err := move_error(season, team, x, to_green)
	if err != "":
		return err
	var slot := team.slot_of(x)
	if to_green:
		team.roster.erase(x)
		if slot != &"":
			team.lineup.erase(slot)
		x.injury_cover_for = 0
		team.green_team.append(x)
	else:
		team.green_team.erase(x)
		team.roster.append(x)
	team.auto_lineup()
	return ""


func set_roster() -> Control:
	var s := _season()
	var team := s.user_team()
	var v := _vbox(12)
	v.add_child(UiKit.label("Set Roster", 28, Color.WHITE))
	if not roster_set_open(s):
		v.add_child(UiKit.label("The roster window is closed.", 18, UiKit.MUTED))
		return v
	v.add_child(_wrap("Arrange your %d-man roster and %d-man Green Team. Moves are free until the week ends." % [Team.ROSTER_SIZE, Team.GREEN_SIZE], 16, UiKit.MUTED))
	var cols := _row(24)
	cols.add_child(_roster_column("ROSTER  %d / %d" % [team.roster.size(), Team.ROSTER_SIZE], team, team.roster, true))
	cols.add_child(_roster_column("GREEN TEAM  %d / %d" % [team.green_team.size(), Team.GREEN_SIZE], team, team.green_team, false))
	v.add_child(cols)
	return v


func _roster_column(title: String, team: Team, list: Array, is_roster: bool) -> Control:
	var s := _season()
	var col := _vbox(6)
	col.name = "RosterCol" if is_roster else "GreenCol"
	col.add_child(_section(title))
	var sorted: Array = list.duplicate()
	sorted.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	if sorted.is_empty():
		col.add_child(UiKit.label("Empty.", 15, UiKit.MUTED))
	for x in sorted:
		var who: Soldier = x
		var r := _row(8)
		var info := UiKit.label("%s   %s  age %d  OVR %d" % [who.full_name(), _role_name(who), who.age, who.best_ovr()], 16, UiKit.TEXT)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(info)
		var b := UiKit.button("To Green  >" if is_roster else "<  To Roster", func():
			var err := move(s, team, who, is_roster)
			if err != "":
				hub.app.toast(err)
			hub.replace("Set Roster", set_roster), 15)
		b.custom_minimum_size.x = 130
		var err := move_error(s, team, who, is_roster)
		b.disabled = err != ""
		b.tooltip_text = err
		r.add_child(b)
		col.add_child(r)
	return col

class_name DataEdit
extends Control
## Title-screen Data Edit: every player in data/league.json (the base league each New Franchise starts from).
## Name, callsign, age, home state, dev stars, draft year, all 18 ratings, the 5 group caps and the picture are
## editable; contracts, personality, career and morale are not. Edits stay in memory until Save, which writes only
## the changed players' lines back to data/league.json (see LeagueEditor). Saved franchises are unaffected.

const LIST_PORTRAIT := 40
const BIG_PORTRAIT := 190
const PICK_COLS := 7

var app: Control
var ed: LeagueEditor
var _teams := {}
var _cur := -1
var _seed := {}

var _list_box: VBoxContainer
var _row_btns := {}
var _detail: VBoxContainer
var _search: LineEdit
var _team_pick: OptionButton
var _status: Label
var _save_btn: Button
var _count_lbl: Label
var _picker: Control


func _ready() -> void:
	ed = LeagueEditor.open()
	for i in LeagueData.TEAMS.size():
		var t := League.team_from_row(LeagueData.TEAMS[i], i + 1)
		_teams[t.abbrev] = t
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_rebuild_list()
	if ed.count() > 0:
		_select(0)


# --- layout -----------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var back := UiKit.button("< Back", go_back, 18)
	back.custom_minimum_size = Vector2(120, 48)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	var tt := VBoxContainer.new()
	tt.add_child(UiKit.display("DATA EDIT", 44, Color.WHITE, true))
	tt.add_child(UiKit.label("Edits the base league in data/league.json: every new franchise starts from it. Saved franchises keep their own copy.", 14, UiKit.MUTED))
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	_status = UiKit.label("", 15, UiKit.GOLD)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_status)
	_save_btn = UiKit.action_button("Save to league.json", _save, 18)
	_save_btn.custom_minimum_size = Vector2(240, 48)
	_save_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_save_btn)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	var left := UiKit.panel(UiKit.PANEL, 10)
	left.custom_minimum_size.x = 400
	body.add_child(left)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 8)
	left.add_child(lcol)
	_search = LineEdit.new()
	_search.placeholder_text = "Search name or callsign"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _rebuild_list())
	lcol.add_child(_search)
	_team_pick = OptionButton.new()
	_team_pick.add_item("All players")
	for abbrev in _teams:
		_team_pick.add_item("%s  -  %s" % [abbrev, _teams[abbrev].name])
	_team_pick.add_item("Free agents")
	_team_pick.item_selected.connect(func(_i): _rebuild_list())
	lcol.add_child(_team_pick)
	_count_lbl = UiKit.label("", 13, UiKit.MUTED)
	lcol.add_child(_count_lbl)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lcol.add_child(sc)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 3)
	sc.add_child(_list_box)

	var right := UiKit.panel(UiKit.PANEL, 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rsc := ScrollContainer.new()
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rsc)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 14)
	rsc.add_child(_detail)
	_update_status()


# --- player list ------------------------------------------------------------

func _rebuild_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_row_btns.clear()
	var q := _search.text.strip_edges().to_lower()
	var sel := _team_pick.selected
	var abbrevs := _teams.keys()
	var shown := 0
	for k in ed.count():
		var team := ed.team_of(k)
		if sel > 0:
			var want := "" if sel == abbrevs.size() + 1 else String(abbrevs[sel - 1])
			if team != want:
				continue
		var r := ed.rows[k]
		if q != "" and not ("%s %s %s" % [r["first"], r["last"], r.get("callsign", "")]).to_lower().contains(q):
			continue
		var b := Button.new()
		b.custom_minimum_size.y = LIST_PORTRAIT + 12
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_select.bind(k))
		_list_box.add_child(b)
		_row_btns[k] = b
		_fill_row(k)
		shown += 1
	_count_lbl.text = "%d of %d players" % [shown, ed.count()]
	_mark_selected()


func _fill_row(k: int) -> void:
	var b: Button = _row_btns.get(k)
	if b == null:
		return
	for c in b.get_children():
		c.queue_free()
	var s := ed.soldier(k)
	var team: Team = _teams.get(ed.team_of(k))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.add_child(Portrait.new(s, LIST_PORTRAIT, UiKit.LINE, team))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UiKit.label(s.full_name(), 16, Color.WHITE)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(nm)
	var sub := UiKit.label("\"%s\"  -  %s  -  age %d" % [s.callsign, ed.team_of(k) if ed.team_of(k) != "" else "FA", s.age], 13, UiKit.MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(sub)
	h.add_child(info)
	if ed.is_dirty(k):
		var dot := UiKit.label("EDITED", 12, UiKit.GOLD)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(dot)
	var ovr := UiKit.display(str(s.best_ovr()), 22, UiKit.ovr_color(s.best_ovr()), true)
	ovr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ovr)


func _mark_selected() -> void:
	for k in _row_btns:
		var b: Button = _row_btns[k]
		if k == _cur:
			b.add_theme_stylebox_override("normal", UiKit.flat(UiKit.PANEL_HI, 6, 2, UiKit.ACCENT))
		else:
			b.remove_theme_stylebox_override("normal")


func _select(k: int) -> void:
	_cur = k
	_mark_selected()
	_build_detail()


# --- player editor ----------------------------------------------------------

func _build_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _cur < 0:
		return
	var k := _cur
	var r := ed.rows[k]
	var s := ed.soldier(k)
	var team: Team = _teams.get(ed.team_of(k))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	_detail.add_child(top)
	var pic := VBoxContainer.new()
	pic.add_theme_constant_override("separation", 8)
	var portrait := Portrait.new(s, BIG_PORTRAIT, UiKit.ACCENT, team)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.add_child(portrait)
	pic.add_child(UiKit.action_button("Change Picture", _open_picker, 16))
	pic.add_child(UiKit.button("Reroll Morph", func(): _reroll(k), 16))
	pic.add_child(UiKit.button("Revert This Player", func(): _revert(k), 16))
	top.add_child(pic)

	var form := GridContainer.new()
	form.columns = 4
	form.add_theme_constant_override("h_separation", 14)
	form.add_theme_constant_override("v_separation", 10)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(form)
	_field(form, "First name", _line(String(r["first"]), func(t: String): _name_changed(k, true, t)))
	_field(form, "Last name", _line(String(r["last"]), func(t: String): _name_changed(k, false, t)))
	var cs := _line(String(r.get("callsign", "")), Callable())
	cs.text_submitted.connect(func(t: String): _commit_callsign(k, cs, t))
	cs.focus_exited.connect(func(): _commit_callsign(k, cs, cs.text))
	_field(form, "Callsign", cs)
	_field(form, "Age", _spin(14, 60, int(r["age"]), func(v: int): _set_and_refresh(k, "age", v)))
	var states := LeagueData.STATE_NAMES.keys()
	states.sort()
	var st := OptionButton.new()
	for code in states:
		st.add_item("%s  -  %s" % [code, LeagueData.STATE_NAMES[code]])
	st.selected = maxi(0, states.find(String(r.get("state", ""))))
	st.item_selected.connect(func(i: int): _set_and_refresh(k, "state", states[i]))
	_field(form, "Home state", st)
	_field(form, "Dev stars (1-4)", _spin(Soldier.DEV_MIN, Soldier.DEV_MAX, int(r.get("dev", 2)), func(v: int): _set_and_refresh(k, "dev", v)))
	_field(form, "Draft year (0 = none)", _spin(0, 2100, int(r.get("draft_year", 0)), func(v: int): _set_and_refresh(k, "draft_year", v)))
	var who := "%s  -  id %d" % [("Team " + ed.team_of(k)) if ed.team_of(k) != "" else "Free agent", int(r["id"])]
	_field(form, "Roster spot (read only)", UiKit.label(who, 16, UiKit.MUTED))

	var summary := UiKit.rich("", 18)
	summary.name = "Summary"
	_detail.add_child(summary)
	_update_summary(k)

	_detail.add_child(UiKit.heading("RATINGS  -  0 to 99; each group's cap limits how far skill points can raise it", 16, UiKit.MUTED))
	var groups := GridContainer.new()
	groups.columns = 3
	groups.add_theme_constant_override("h_separation", 12)
	groups.add_theme_constant_override("v_separation", 12)
	_detail.add_child(groups)
	for g in Stats.GROUP_ORDER:
		groups.add_child(_group_card(k, g))


func _group_card(k: int, g: StringName) -> Control:
	var card := UiKit.panel(UiKit.PANEL_HI, 8)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	var avg := UiKit.label("", 14, UiKit.MUTED)
	avg.name = "Avg"
	var hd := HBoxContainer.new()
	hd.add_child(UiKit.display(String(Stats.GROUP_LABELS[g]).to_upper(), 18, UiKit.ACCENT, true))
	hd.add_child(_expander())
	hd.add_child(avg)
	col.add_child(hd)
	var r := ed.rows[k]
	for stat in Stats.GROUPS[g]:
		var abbrev: String = Stats.ABBREV[stat]
		var line := HBoxContainer.new()
		var l := UiKit.label(String(Stats.LABELS[stat]), 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		line.add_child(_spin(0, 99, int(r["stats"].get(abbrev, 60)), func(v: int):
			ed.set_stat(k, abbrev, v)
			_changed(k)
			_update_avg(avg, k, g)))
		col.add_child(line)
	_update_avg(avg, k, g)
	if g in Stats.UPGRADABLE_GROUPS:
		var line := HBoxContainer.new()
		var l := UiKit.label("Cap (ceiling)", 14, UiKit.GOLD)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		line.add_child(_spin(0, 99, int(r["caps"].get(String(g), 60)), func(v: int):
			ed.set_cap(k, String(g), v)
			_changed(k)))
		col.add_child(line)
	return card


func _update_avg(lbl: Label, k: int, g: StringName) -> void:
	lbl.text = "avg %d" % ed.soldier(k).group_rating(g)


func _update_summary(k: int) -> void:
	var s := ed.soldier(k)
	var summary: RichTextLabel = _detail.get_node_or_null("Summary")
	if summary == null:
		return
	summary.text = "[color=%s]%d OVR[/color]  [color=#8b97ab]%s  -  %s[/color]" % [
		UiKit.hex(UiKit.ovr_color(s.best_ovr())), s.best_ovr(), Scheme.ROLE_NAMES[Scheme.best_role(s.stats)], s.full_name()]


# --- editing ----------------------------------------------------------------

func _set_and_refresh(k: int, key: String, value: Variant) -> void:
	ed.set_field(k, key, value)
	_changed(k)


## After any edit: refresh the list row, the OVR line and the header status.
func _changed(k: int) -> void:
	_fill_row(k)
	_update_summary(k)
	_update_status()


func _name_changed(k: int, is_first: bool, text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	var r := ed.rows[k]
	ed.set_name(k, text if is_first else String(r["first"]), String(r["last"]) if is_first else text)
	Portrait.drop_cached_mesh(int(r["id"]))
	_changed(k)


func _commit_callsign(k: int, le: LineEdit, text: String) -> void:
	text = text.strip_edges()
	var cur := String(ed.rows[k].get("callsign", ""))
	if text == cur:
		le.text = cur
		return
	var err := ""
	if text == "":
		err = "A callsign can't be empty."
	elif ed.callsign_taken(k, text):
		err = "\"%s\" is already taken by another player." % text
	if err != "":
		le.text = cur
		_toast(err)
		return
	ed.set_field(k, "callsign", text)
	le.text = text
	_changed(k)


func _reroll(k: int) -> void:
	_seed[k] = int(_seed.get(k, int(ed.rows[k]["id"]))) + 1
	ed.reroll_morph(k, _seed[k])
	_face_changed(k)


func _face_changed(k: int) -> void:
	Portrait.drop_cached_mesh(int(ed.rows[k]["id"]))
	_changed(k)
	if k == _cur:
		_build_detail()


func _revert(k: int) -> void:
	ed.revert(k)
	Portrait.drop_cached_mesh(int(ed.rows[k]["id"]))
	_changed(k)
	_build_detail()


func _update_status() -> void:
	var n := ed.dirty_count()
	_status.text = "%d unsaved edit%s" % [n, "" if n == 1 else "s"] if n > 0 else ""
	_save_btn.disabled = n == 0


func _save() -> void:
	var err := ed.save()
	if err != OK:
		_toast("Could not write data/league.json (%s). Data Edit only saves when run from the project folder." % error_string(err))
		return
	var n := ed.count()
	for k in n:
		_fill_row(k)
	_update_status()
	_toast("Saved to data/league.json. New franchises will use it.")


func _save_and_exit() -> void:
	_save()
	if ed.dirty_count() == 0:
		app.show_title()


func _toast(text: String) -> void:
	if app != null and app.has_method("toast"):
		app.toast(text)


func go_back() -> void:
	if _picker != null:
		_close_picker()
		return
	if get_node_or_null("ConfirmModal") != null:
		return
	var n := ed.dirty_count()
	if n == 0:
		app.show_title()
		return
	_modal("Unsaved edits", "%d player%s edited but not saved." % [n, " is" if n == 1 else "s are"], [
		["Save & Exit", _save_and_exit],
		["Discard & Exit", func(): app.show_title()],
		["Keep Editing", Callable()],
	])


## A small centred dialog over everything; each button is [label, callback] and closes it.
func _modal(title: String, body: String, buttons: Array) -> void:
	var overlay := ColorRect.new()
	overlay.name = "ConfirmModal"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var p := UiKit.panel(UiKit.PANEL_HI, 12)
	center.add_child(p)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 420
	col.add_theme_constant_override("separation", 12)
	p.add_child(col)
	col.add_child(UiKit.display(title.to_upper(), 26, Color.WHITE, true))
	col.add_child(UiKit.label(body, 16, UiKit.MUTED))
	for spec in buttons:
		var cb: Callable = spec[1]
		var b := UiKit.button(String(spec[0]), func():
			overlay.queue_free()
			if cb.is_valid():
				cb.call(), 18)
		col.add_child(b)
	app.focus_first.call_deferred(col)


# --- widgets ----------------------------------------------------------------

func _field(grid: GridContainer, label: String, w: Control) -> void:
	grid.add_child(UiKit.label(label, 14, UiKit.MUTED))
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(w)


func _line(text: String, on_change: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.max_length = LeagueEditor.NAME_MAX * 2
	le.custom_minimum_size.x = 120
	if on_change.is_valid():
		le.text_changed.connect(on_change)
	return le


func _spin(lo: int, hi: int, value: int, cb: Callable) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = 1
	sb.value = value
	sb.custom_minimum_size.x = 90
	sb.value_changed.connect(func(v: float): cb.call(int(v)))
	return sb


func _expander() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


# --- picture picker -----------------------------------------------------------

func _open_picker() -> void:
	if _cur < 0 or _picker != null:
		return
	var k := _cur
	var in_use := {} # head id -> [player index, ...]
	for j in ed.count():
		var hid := ed.soldier(j).get_face().head_id
		if not in_use.has(hid):
			in_use[hid] = []
		in_use[hid].append(j)
	var mine := ed.soldier(k).get_face().head_id
	var state := {"head": mine, "group": "", "hide_used": false}
	var heads: Dictionary = FaceSpec.db()["heads"]
	var ids := heads.keys()
	ids.sort()

	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.06, 0.97)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_picker = overlay
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	overlay.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	left.add_child(UiKit.display("CHOOSE A PICTURE  -  %s" % ed.soldier(k).full_name().to_upper(), 34, Color.WHITE, true))
	var legend := UiKit.rich("[color=#f59e0b]CURRENT[/color] is his head now.  [color=#ef4444]IN USE[/color] heads already belong to a player in the league (pick one anyway if you want a twin).", 14)
	left.add_child(legend)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	left.add_child(filters)
	var grid := GridContainer.new()
	grid.columns = PICK_COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var gsc := ScrollContainer.new()
	gsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gsc.add_child(grid)
	var preview_holder := VBoxContainer.new()
	var cells := {}
	var fns := {} # "preview": refreshes the right-hand preview (lambdas capture by value, so it lives here)
	var refill := func():
		for c in grid.get_children():
			c.queue_free()
		cells.clear()
		for hid in ids:
			if state["group"] != "" and heads[hid]["group"] != state["group"]:
				continue
			var used: Array = in_use.get(hid, [])
			if state["hide_used"] and not used.is_empty() and hid != mine:
				continue
			var cell := _head_cell(String(hid), used, hid == mine, k)
			cell.pressed.connect(func():
				state["head"] = hid
				for h in cells:
					_style_cell(cells[h], h == hid, h == mine, in_use.get(h, []).size() > 0)
				fns["preview"].call())
			grid.add_child(cell)
			cells[hid] = cell
			_style_cell(cell, hid == state["head"], hid == mine, used.size() > 0)
	for g in ["", "light", "dark", "brown", "asian"]:
		var fb := UiKit.button("All" if g == "" else String(g).capitalize(), func():
			state["group"] = g
			refill.call(), 15)
		filters.add_child(fb)
	var hide := CheckButton.new()
	hide.text = "Hide heads in use"
	hide.toggled.connect(func(on: bool):
		state["hide_used"] = on
		refill.call())
	filters.add_child(hide)
	left.add_child(gsc)

	var rp := UiKit.panel(UiKit.PANEL, 12)
	rp.custom_minimum_size.x = 400
	row.add_child(rp)
	preview_holder.add_theme_constant_override("separation", 12)
	preview_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	rp.add_child(preview_holder)
	var pv_pic := CenterContainer.new()
	var pv_name := UiKit.label("", 18, Color.WHITE)
	pv_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pv_warn := UiKit.label("", 14, UiKit.BAD)
	pv_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_holder.add_child(UiKit.display("PREVIEW", 22, UiKit.ACCENT, true))
	preview_holder.add_child(pv_pic)
	preview_holder.add_child(pv_name)
	preview_holder.add_child(pv_warn)
	var confirm := UiKit.action_button("Confirm Picture", func(): pass, 20)
	var seed_box := {"n": int(_seed.get(k, int(ed.rows[k]["id"])))}
	fns["preview"] = func():
		for c in pv_pic.get_children():
			c.queue_free()
		var hid: String = state["head"]
		var temp := ed.soldier(k)
		temp.id = -1
		temp.face_override = FaceSpec.make_override(hid, seed_box["n"])
		temp.face = null
		Portrait.drop_cached_mesh(-1)
		pv_pic.add_child(Portrait.new(temp, 280, UiKit.ACCENT, _teams.get(ed.team_of(k))))
		var used: Array = in_use.get(hid, [])
		var others := used.filter(func(j): return j != k)
		pv_name.text = "Head %s" % hid + ("  (current)" if hid == mine else "")
		pv_warn.text = "" if others.is_empty() else "Already used by %s" % ", ".join(others.slice(0, 3).map(func(j): return String(ed.rows[j].get("callsign", "?"))))
	confirm.pressed.connect(func():
		_seed[k] = seed_box["n"]
		ed.set_head(k, state["head"], seed_box["n"])
		_close_picker()
		_face_changed(k))
	preview_holder.add_child(UiKit.button("Reroll Morph", func():
		seed_box["n"] += 1
		fns["preview"].call(), 16))
	preview_holder.add_child(confirm)
	preview_holder.add_child(UiKit.button("Cancel", _close_picker, 16))
	refill.call()
	fns["preview"].call()
	if cells.has(mine):
		gsc.ensure_control_visible.call_deferred(cells[mine])


func _head_cell(hid: String, used: Array, is_mine: bool, k: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 188)
	b.clip_contents = true
	var tex := TextureRect.new()
	tex.texture = load(FaceSpec.HEADS_DIR + hid + ".webp")
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	tex.offset_bottom = -24
	b.add_child(tex)
	var others := used.filter(func(j): return j != k)
	var tag := UiKit.label(hid, 12, UiKit.MUTED)
	if is_mine:
		tag.text = "CURRENT  %s" % hid
		tag.add_theme_color_override("font_color", UiKit.GOLD)
	elif not others.is_empty():
		var first_user := String(ed.rows[others[0]].get("callsign", "?"))
		tag.text = "IN USE: %s%s" % [first_user, "" if others.size() == 1 else " +%d" % (others.size() - 1)]
		tag.add_theme_color_override("font_color", UiKit.BAD)
		tex.modulate = Color(1, 1, 1, 0.45)
		b.tooltip_text = "Used by " + ", ".join(others.map(func(j): return "%s %s" % [ed.rows[j]["first"], ed.rows[j]["last"]]))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 4)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.clip_text = true
	b.add_child(tag)
	return b


func _style_cell(b: Button, selected: bool, is_mine: bool, used: bool) -> void:
	var border := UiKit.ACCENT if selected else (UiKit.GOLD if is_mine else UiKit.LINE)
	var sb := UiKit.flat(UiKit.PANEL_HI if selected else UiKit.PANEL, 8, 3 if selected else (2 if is_mine else 1), border)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", UiKit.flat(UiKit.PANEL_HI, 8, 2, UiKit.ACCENT))
	b.add_theme_stylebox_override("pressed", sb)


func _close_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null
	Portrait.drop_cached_mesh(-1)

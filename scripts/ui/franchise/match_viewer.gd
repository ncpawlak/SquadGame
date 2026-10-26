class_name MatchViewer
extends Control
## Live, top-down view of a match driven tick-by-tick by the same MatchEngine used for simming.
## Scoreboard on top, a team panel per side (HP + live stats), the tactical map with tracers and
## pop-up shot results in the middle, a kill feed under the map and playback controls at the bottom.
## Emits `finished(result)` once the user continues past the final card.

signal finished(result: MatchResult)

const SPEEDS := [2.0, 3.0, 5.0]
const TRACER_S := 0.22
const POPUP_S := 0.9
const BANNER_S := 1.6
const DOT_RADIUS := 21.0
const PANEL_W := 340
## Teleports (respawns, new rounds) longer than this snap instead of sliding across the map.
const SNAP_DISTANCE := 6.0
const WALL_COLOR := Color("#3a4150")
const CRATE_COLOR := Color("#7a5a36")
const FLOOR_COLOR := Color("#1b2230")
const GRID_COLOR := Color(1, 1, 1, 0.04)
const RESULT_COLORS := {
	"MISS": Color("#9ca3af"), "HIT": Color("#f3f4f6"), "HEADSHOT": Color("#fb923c"), "KILL": Color("#ef4444"),
}

var engine: MatchEngine
var match_ref: ScheduledMatch
var teams: Array = []
var speed := 2.0
var paused := false

var _acc := 0.0
var _clock := 0.0  # real seconds, drives effect lifetimes
var _by_id := {}  # soldier id -> Combatant
var _tracers: Array = []  # {from_id, to, team, born, result}
var _popups: Array = []  # {id, text, color, born}
var _banner := ""
var _banner_until := 0.0
var _hold := false  # waiting on an intermission / final card
var _rng := RandomNumberGenerator.new()  # visual jitter only; never touches the engine

var _map: Control
var _feed: RichTextLabel
var _score_l: Label
var _score_r: Label
var _mid_label: RichTextLabel
var _series: Label
var _rows := {}  # soldier id -> {"hp": ColorRect, "hp_bg": Control, "stats": Label, "root": Control, "tag": Label}
var _pause_btn: Button
var _speed_btns: Array = []
var _card: PanelContainer
var _font: Font


func setup(m: ScheduledMatch) -> void:
	match_ref = m
	engine = m.live_engine()
	engine.record = true
	teams = [m.home, m.away]
	for squad in engine.squads:
		for c in squad:
			_by_id[c.soldier.id] = c
	_rng.seed = m.match_seed ^ 0x5eed


func _ready() -> void:
	_font = get_theme_default_font()
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.add_child(_build_scoreboard())

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	root.add_child(mid)
	mid.add_child(_build_team_panel(0))
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 6)
	mid.add_child(center)
	_map = Control.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.size_flags_stretch_ratio = 4.0
	_map.clip_contents = true
	_map.draw.connect(_draw_map)
	center.add_child(_map)
	var feed_panel := UiKit.panel(UiKit.PANEL, 8)
	feed_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(feed_panel)
	_feed = RichTextLabel.new()
	_feed.bbcode_enabled = true
	_feed.scroll_following = true
	_feed.custom_minimum_size.y = 130
	_feed.add_theme_font_size_override("normal_font_size", 14)
	feed_panel.add_child(_feed)
	mid.add_child(_build_team_panel(1))

	root.add_child(_build_controls())

	_card = UiKit.panel(Color(UiKit.PANEL_HI, 0.97), 14)
	_card.visible = false
	add_child(_card)
	_log("[color=#8b97ab]%s vs %s  -  best of 3. Space pauses.[/color]" % [UiKit.esc(teams[0].name), UiKit.esc(teams[1].name)])
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			if not _hold:
				toggle_pause()
			accept_event()
		elif event.keycode in [KEY_1, KEY_2, KEY_3]:
			set_speed(SPEEDS[event.keycode - KEY_1])
			accept_event()


func toggle_pause() -> void:
	if _hold:
		return
	paused = not paused
	_pause_btn.text = "Resume" if paused else "Pause"


func set_speed(s: float) -> void:
	speed = s
	for i in _speed_btns.size():
		var on: bool = SPEEDS[i] == s
		UiKit.style_button(_speed_btns[i], UiKit.ACCENT.darkened(0.45) if on else UiKit.PANEL_HI)


func _process(delta: float) -> void:
	_clock += delta
	if not paused and not _hold and not engine.finished and _clock >= _banner_until:
		_acc += delta * speed / MatchEngine.TICK_SECONDS
		while _acc >= 1.0 and not _hold and not engine.finished:
			_acc -= 1.0
			engine.step()
			_consume_events()
		_acc = minf(_acc, 1.0)
	_expire_effects()
	_refresh_hud()
	_map.queue_redraw()


# --- engine events --------------------------------------------------------------------

func _consume_events() -> void:
	for e in engine.visual_events:
		match e["t"]:
			"shot":
				_tracers.append({"from_id": e["id"], "to": _aim_point(e), "team": e["team"], "born": _clock, "result": e["result"]})
				var res: String = e["result"]
				var col: Color = RESULT_COLORS.get(res.split(" ")[0], RESULT_COLORS["HIT"])
				_popup(e["id"], res, col)
			"reload":
				_popup(e["id"], "RELOAD", UiKit.INFO)
			"kill":
				_log_kill(e)
			"respawn":
				_log("[color=%s]%s[/color] [color=#8b97ab]wiped - respawning in formation[/color]" % [_team_hex(e["team"]), teams[e["team"]].abbrev])
			"hill":
				_log("[color=%s]%s take the hill[/color]" % [_team_hex(e["team"]), teams[e["team"]].abbrev])
			"game_start":
				_tracers.clear()
				_popups.clear()
				_acc = 0.0
				_log("[b]GAME %d  -  %s[/b]" % [e["game"], MatchEngine.mode_name(e["mode"]).to_upper()])
			"round_start":
				_acc = 0.0
				_tracers.clear()
				_popups.clear()
			"round_end":
				var info: Dictionary = e["round"]
				var w: int = info["winner"]
				_banner = "ROUND %d  -  %s  (%d-%d)" % [info["number"], teams[w].abbrev, e["score"][0], e["score"][1]]
				_banner_until = _clock + BANNER_S
				_log("[color=%s]Round %d to %s[/color]  [%d-%d]" % [_team_hex(w), info["number"], teams[w].abbrev, e["score"][0], e["score"][1]])
			"game_end":
				var g: Dictionary = e["game"]
				_log("[b][color=%s]%s win game %d  %s[/color][/b]" % [_team_hex(g["winner"]), teams[g["winner"]].abbrev, g["number"], MatchResult.game_score_text(g)])
				if not engine.finished:
					_show_intermission(g)
			"match_end":
				_show_final()
	engine.visual_events.clear()


## Where the tracer ends: on the target for hits, past it with some spread for misses.
func _aim_point(e: Dictionary) -> Vector2:
	var from: Vector2 = e["from"]
	var to: Vector2 = e["to"]
	if e["hits"] > 0:
		return to
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x) * _rng.randf_range(1.2, 3.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
	return to + side + dir * _rng.randf_range(2.0, 6.0)


func _log_kill(e: Dictionary) -> void:
	var k: MatchEngine.Combatant = _by_id[e["killer"]]
	var v: MatchEngine.Combatant = _by_id[e["victim"]]
	var line := "[color=%s]%s[/color] %s [color=%s]%s[/color] [color=#8b97ab]%dm[/color]" % [
		_team_hex(k.team), k.soldier.tag(), "[color=#fb923c]HEADSHOT[/color]" if e["headshot"] else "killed",
		_team_hex(v.team), v.soldier.tag(), roundi(e["dist"])]
	if not e["assists"].is_empty():
		line += "  [color=#8b97ab]assist %s[/color]" % ", ".join(e["assists"])
	if not e["saved"].is_empty():
		line += "  [color=#22c55e]SAVE %s[/color]" % ", ".join(e["saved"])
	if e["wipe"]:
		line += "  [color=#f59e0b]TEAM WIPE%s[/color]" % (" +%d" % MatchEngine.TDM_WIPE_BONUS if engine.mode() == MatchEngine.MODE_TDM else "")
	_log(line)


## One pop-up per soldier: a newer result replaces the old one instead of stacking.
func _popup(id: int, text: String, color: Color) -> void:
	_popups = _popups.filter(func(p): return p["id"] != id)
	_popups.append({"id": id, "text": text, "color": color, "born": _clock})


func _log(text: String) -> void:
	_feed.append_text(text + "\n")


func _expire_effects() -> void:
	_tracers = _tracers.filter(func(t): return _clock - t["born"] < TRACER_S)
	_popups = _popups.filter(func(p): return _clock - p["born"] < POPUP_S)


# --- cards --------------------------------------------------------------------------

func _show_intermission(g: Dictionary) -> void:
	var w: int = g["winner"]
	var r := engine.result()
	var body := "GAME %d  -  %s\n%s win  %s\n\nSeries  %s %d - %d %s\nNext: %s" % [
		g["number"], MatchEngine.mode_name(g["mode"]).to_upper(), teams[w].name, MatchResult.game_score_text(g),
		teams[0].abbrev, r.score[0], r.score[1], teams[1].abbrev, MatchEngine.mode_name(MatchEngine.GAME_ORDER[g["number"]])]
	_open_card(body, teams[w].color, "Continue", func():
		_card.visible = false
		_hold = false)


func _show_final() -> void:
	var r := engine.result()
	var mvp: MatchEngine.Combatant = _by_id.get(r.mvp_id)
	var body := "FINAL\n%s win %d-%d\n\n%s" % [r.winner().name, r.score[r.winner_index], r.score[1 - r.winner_index],
		("MVP  %s  (%s)" % [mvp.soldier.tag(), mvp.soldier.full_name()]) if mvp else ""]
	_open_card(body, r.winner().color, "Continue to Results", func(): finished.emit(r))


func _open_card(body: String, accent: Color, button_text: String, cb: Callable) -> void:
	_hold = true
	_tracers.clear()
	_popups.clear()
	for c in _card.get_children():
		c.queue_free()
	_card.add_theme_stylebox_override("panel", UiKit.flat(Color(UiKit.PANEL_HI, 0.97), 14, 3, accent))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_card.add_child(v)
	var l := UiKit.label(body, 26, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var b := UiKit.button(button_text, cb, 20)
	b.custom_minimum_size = Vector2(280, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	_card.visible = true
	_card.reset_size()
	await get_tree().process_frame
	if not is_instance_valid(_card):
		return
	_card.reset_size()
	var r := _map.get_global_rect()
	_card.position = r.get_center() - _card.size / 2.0 - global_position
	b.grab_focus()


# --- layout -------------------------------------------------------------------------

func _build_scoreboard() -> Control:
	var p := UiKit.panel(UiKit.PANEL, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	for i in 2:
		var side := HBoxContainer.new()
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.alignment = BoxContainer.ALIGNMENT_END if i == 0 else BoxContainer.ALIGNMENT_BEGIN
		side.add_theme_constant_override("separation", 12)
		var sw := ColorRect.new()
		sw.color = teams[i].color
		sw.custom_minimum_size = Vector2(8, 44)
		var name_l := UiKit.label(teams[i].name.to_upper(), 24, Color.WHITE)
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var score := UiKit.label("0", 40, Color.WHITE)
		score.custom_minimum_size.x = 110
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if i == 0 else HORIZONTAL_ALIGNMENT_LEFT
		var parts: Array = [sw, name_l, score] if i == 0 else [score, name_l, sw]
		for c in parts:
			side.add_child(c)
		if i == 0:
			_score_l = score
			h.add_child(side)
			var mid := VBoxContainer.new()
			mid.custom_minimum_size.x = 300
			mid.add_theme_constant_override("separation", 0)
			_mid_label = UiKit.rich("", 16)
			_mid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mid.add_child(_mid_label)
			_series = UiKit.label("", 14, UiKit.MUTED)
			_series.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mid.add_child(_series)
			h.add_child(mid)
		else:
			_score_r = score
			h.add_child(side)
	return p


func _build_team_panel(i: int) -> Control:
	var t: Team = teams[i]
	var p := UiKit.panel(UiKit.PANEL, 8)
	p.custom_minimum_size.x = PANEL_W
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := UiKit.label(t.abbrev + "  -  " + t.name, 16, t.color.lightened(0.35))
	head.clip_text = true
	v.add_child(head)
	for c in engine.squads[i]:
		var s: Soldier = c.soldier
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL_HI, 8))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		row.add_child(Portrait.new(s, 52, t.color, t))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 3)
		row.add_child(info)
		var tag := UiKit.label("%s   %s" % [s.tag(), c.slot_id], 17, Color.WHITE)
		info.add_child(tag)
		var hp_bg := ColorRect.new()
		hp_bg.color = Color(0, 0, 0, 0.45)
		hp_bg.custom_minimum_size = Vector2(0, 8)
		info.add_child(hp_bg)
		var hp := ColorRect.new()
		hp.color = UiKit.GOOD
		hp.size = Vector2(0, 8)
		hp_bg.add_child(hp)
		var stats := UiKit.label("", 13, UiKit.MUTED)
		stats.clip_text = true
		stats.custom_minimum_size.x = 10
		tag.clip_text = true
		tag.custom_minimum_size.x = 10
		info.add_child(stats)
		v.add_child(card)
		_rows[s.id] = {"hp": hp, "hp_bg": hp_bg, "stats": stats, "root": card, "tag": tag}
	return p


func _build_controls() -> Control:
	var p := UiKit.panel(UiKit.PANEL, 0)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	_pause_btn = UiKit.button("Pause", toggle_pause, 16)
	_pause_btn.custom_minimum_size.x = 120
	h.add_child(_pause_btn)
	for s in SPEEDS:
		var b := UiKit.button("%dx" % int(s), set_speed.bind(s), 16)
		b.custom_minimum_size.x = 70
		_speed_btns.append(b)
		h.add_child(b)
	var sim := UiKit.button("Sim to End  >>", sim_to_end, 16)
	sim.custom_minimum_size.x = 160
	h.add_child(sim)
	h.add_child(UiKit.label("   Space: pause    1/2/3: speed", 13, UiKit.MUTED))
	set_speed(speed)
	return p


## Finish the match instantly (same engine, so the result is identical to watching it out).
func sim_to_end() -> void:
	if engine.finished:
		return
	_card.visible = false
	_hold = false
	engine.record = false
	engine.visual_events.clear()
	while engine.step():
		pass
	engine.record = true
	_log("[color=#8b97ab]Simmed to the end.[/color]")
	_show_final()


func _refresh_hud() -> void:
	var mode := engine.mode()
	var score := engine.game_score()
	var r := engine.result()
	if mode == MatchEngine.MODE_KOTH:
		_score_l.text = MatchEngine._fmt_secs(score[0])
		_score_r.text = MatchEngine._fmt_secs(score[1])
	else:
		_score_l.text = str(int(score[0]))
		_score_r.text = str(int(score[1]))
	var goal := ""
	match mode:
		MatchEngine.MODE_TDM:
			goal = "FIRST TO %d" % MatchEngine.TDM_POINTS_TO_WIN
		MatchEngine.MODE_KOTH:
			goal = "HOLD %s" % MatchEngine._fmt_secs(MatchEngine.KOTH_HOLD_TO_WIN_S)
			var hs := engine.hill_state()
			if hs == 2:
				goal += "  -  [color=#f59e0b]CONTESTED[/color]"
			elif hs >= 0:
				goal += "  -  [color=%s]%s HOLD[/color]" % [_team_hex(hs), teams[hs].abbrev]
		_:
			goal = "ROUND %d  -  FIRST TO %d" % [engine.round_number(), MatchEngine.ROUNDS_TO_WIN]
	_mid_label.text = "[b]GAME %d  -  %s[/b]\n%s   [color=#8b97ab]%s[/color]" % [
		maxi(engine.game_number(), 1), MatchEngine.MODE_SHORT.get(mode, "TDM"), goal, MatchEngine._fmt_secs(engine.clock_s())]
	_series.text = "SERIES  %s  %s  %s" % [_pips(r.score[0]), "-", _pips(r.score[1])]
	for id in _rows:
		var c: MatchEngine.Combatant = _by_id[id]
		var row: Dictionary = _rows[id]
		var b: Dictionary = r.box[id]
		var frac := clampf(c.hp / 100.0, 0.0, 1.0) if c.alive else 0.0
		var bg: ColorRect = row["hp_bg"]
		var hp: ColorRect = row["hp"]
		hp.size = Vector2(bg.size.x * frac, bg.size.y)
		hp.color = UiKit.GOOD if frac > 0.6 else (UiKit.ACCENT if frac > 0.3 else UiKit.BAD)
		row["root"].modulate.a = 1.0 if c.alive else 0.45
		var acc := 0 if b["shots"] == 0 else roundi(100.0 * b["hits"] / b["shots"])
		var text := "K %d   D %d   A %d   SAVES %d\nHITS %d/%d  (%d%%)" % [b["kills"], b["deaths"], b["assists"], b["saves"], b["hits"], b["shots"], acc]
		if mode == MatchEngine.MODE_KOTH:
			text += "   HILL %s" % MatchEngine._fmt_secs(b["hill_s"])
		row["stats"].text = text


func _pips(n: int) -> String:
	var out := ""
	for i in MatchEngine.GAMES_TO_WIN:
		out += "● " if i < n else "○ "
	return out.strip_edges()


func _team_hex(i: int) -> String:
	return UiKit.hex(teams[i].color.lightened(0.25))


# --- map drawing ----------------------------------------------------------------------

func _scale() -> float:
	return minf(_map.size.x / (ArenaMap.HALF.x * 2.0), _map.size.y / (ArenaMap.HALF.y * 2.0))


func _to_screen(p: Vector2) -> Vector2:
	return _map.size / 2.0 + p * _scale()


func _rect_to_screen(r: Rect2) -> Rect2:
	return Rect2(_to_screen(r.position), r.size * _scale())


func _display_pos(c: MatchEngine.Combatant) -> Vector2:
	if c.prev_pos.distance_to(c.pos) > SNAP_DISTANCE:
		return c.pos
	return c.prev_pos.lerp(c.pos, clampf(_acc, 0.0, 1.0))


func _draw_map() -> void:
	var sc := _scale()
	var arena := _rect_to_screen(Rect2(-ArenaMap.HALF, ArenaMap.HALF * 2.0))
	_map.draw_rect(arena, FLOOR_COLOR)
	var x := -ArenaMap.HALF.x
	while x <= ArenaMap.HALF.x:
		_map.draw_line(_to_screen(Vector2(x, -ArenaMap.HALF.y)), _to_screen(Vector2(x, ArenaMap.HALF.y)), GRID_COLOR)
		x += 4.0
	var y := -ArenaMap.HALF.y
	while y <= ArenaMap.HALF.y:
		_map.draw_line(_to_screen(Vector2(-ArenaMap.HALF.x, y)), _to_screen(Vector2(ArenaMap.HALF.x, y)), GRID_COLOR)
		y += 4.0
	# Spawn zones tinted with each team's colour.
	for i in 2:
		var zone := Rect2(Vector2(-ArenaMap.HALF.x, -ArenaMap.HALF.y), Vector2(9, ArenaMap.HALF.y * 2.0))
		if i == 1:
			zone.position.x = ArenaMap.HALF.x - 9.0
		_map.draw_rect(_rect_to_screen(zone), Color(teams[i].color, 0.08))
	if engine.mode() == MatchEngine.MODE_KOTH:
		var hs := engine.hill_state()
		var col := Color(1, 1, 1, 0.10)
		if hs == 2:
			col = Color(UiKit.ACCENT, 0.30)
		elif hs >= 0:
			col = Color(teams[hs].color, 0.35)
		var hr := _rect_to_screen(ArenaMap.HILL)
		_map.draw_rect(hr, col)
		_map.draw_rect(hr, Color(1, 1, 1, 0.55), false, 2.0)
		_map.draw_string(_font, hr.position + Vector2(4, 14), "HILL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	for r in ArenaMap.crates:
		var sr := _rect_to_screen(r)
		_map.draw_rect(sr, CRATE_COLOR)
		_map.draw_rect(sr, CRATE_COLOR.darkened(0.4), false, 2.0)
		_map.draw_line(sr.position, sr.end, CRATE_COLOR.darkened(0.25), 1.0)
		_map.draw_line(Vector2(sr.end.x, sr.position.y), Vector2(sr.position.x, sr.end.y), CRATE_COLOR.darkened(0.25), 1.0)
	for r in ArenaMap.walls:
		_map.draw_rect(_rect_to_screen(r), WALL_COLOR)
	_map.draw_rect(arena, Color(1, 1, 1, 0.25), false, 2.0)

	# Tracers and muzzle flashes.
	for t in _tracers:
		var c: MatchEngine.Combatant = _by_id[t["from_id"]]
		var from := _to_screen(_display_pos(c))
		var to: Vector2 = _to_screen(t["to"])
		var age: float = (_clock - t["born"]) / TRACER_S
		var dir := (to - from).normalized()
		var start := from + dir * DOT_RADIUS
		var col := Color(1.0, 0.92, 0.55, 0.9 * (1.0 - age))
		_map.draw_line(start, to, col, 2.0)
		if age < 0.5:
			var tip := start + dir * 10.0
			var side := Vector2(-dir.y, dir.x) * 5.0
			_map.draw_colored_polygon(PackedVector2Array([start + side, tip + dir * 6.0, start - side]), Color(1.0, 0.75, 0.2, 0.95))
		if t["result"] != "MISS":
			_map.draw_circle(to, 4.0 + 6.0 * age, Color(1, 0.3, 0.2, 0.6 * (1.0 - age)))

	# Soldiers: dead ones faded where they fell.
	for pass_alive in [false, true]:
		for squad in engine.squads:
			for c: MatchEngine.Combatant in squad:
				if c.alive != pass_alive:
					continue
				_draw_soldier(c, sc)

	for p in _popups:
		var c: MatchEngine.Combatant = _by_id[p["id"]]
		var age: float = (_clock - p["born"]) / POPUP_S
		var at := _to_screen(_display_pos(c)) + Vector2(0, -DOT_RADIUS - 8.0 - 18.0 * age)
		var text: String = p["text"]
		var fs := 13
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col: Color = p["color"]
		col.a = 1.0 - age * age
		_map.draw_string_outline(_font, at - Vector2(w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, col.a))
		_map.draw_string(_font, at - Vector2(w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	if _clock < _banner_until:
		var fs := 30
		var w := _font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(_map.size.x / 2.0 - w / 2.0, _map.size.y / 2.0)
		_map.draw_rect(Rect2(at + Vector2(-20, -40), Vector2(w + 40, 58)), Color(0, 0, 0, 0.7))
		_map.draw_string(_font, at, _banner, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if paused:
		_map.draw_string(_font, Vector2(12, 26), "PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiKit.ACCENT)


func _draw_soldier(c: MatchEngine.Combatant, _sc: float) -> void:
	var t: Team = teams[c.team]
	var at := _to_screen(_display_pos(c))
	var a := 1.0 if c.alive else 0.28
	_map.draw_circle(at, DOT_RADIUS, Color(t.color, a))
	_map.draw_arc(at, DOT_RADIUS, 0, TAU, 32, Color(t.color2, a), 2.5, true)
	if c.alive and c.target and c.target.alive:
		var dir := (c.target.pos - c.pos).normalized()
		_map.draw_circle(at + dir * (DOT_RADIUS + 3.0), 3.0, Color(t.color2, 0.9))
	var tag := c.soldier.tag()
	var fs := 12
	while fs > 7 and _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > DOT_RADIUS * 1.8:
		fs -= 1
	var w := _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var text_col := Color.BLACK if t.color.get_luminance() > 0.55 else Color.WHITE
	_map.draw_string(_font, at + Vector2(-w / 2.0, fs * 0.35), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(text_col, a))
	if c.alive:
		var bw := DOT_RADIUS * 2.0
		var top := at + Vector2(-bw / 2.0, DOT_RADIUS + 3.0)
		_map.draw_rect(Rect2(top, Vector2(bw, 4)), Color(0, 0, 0, 0.6))
		var frac := clampf(c.hp / 100.0, 0.0, 1.0)
		_map.draw_rect(Rect2(top, Vector2(bw * frac, 4)), UiKit.GOOD if frac > 0.6 else (UiKit.ACCENT if frac > 0.3 else UiKit.BAD))
	else:
		_map.draw_line(at + Vector2(-7, -7), at + Vector2(7, 7), Color(1, 1, 1, 0.5), 2.0)
		_map.draw_line(at + Vector2(7, -7), at + Vector2(-7, 7), Color(1, 1, 1, 0.5), 2.0)

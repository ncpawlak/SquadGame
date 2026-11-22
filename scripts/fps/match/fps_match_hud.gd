class_name FpsMatchHud
extends Control
## Match overlay for the playable 3D career match: mode / game x of 3 / games won, the score line, the clock, the respawn
## countdown, a kill feed, banners, a Tab scoreboard and the end-of-match result card. It only reads an FpsMatchGame
## (or anything with the same fields) and listens to its signals; the runner owns the lifecycle.

var game: Node = null
var teams: Array = []  # [home Team, away Team]
var human_team := 0
var spectate_text := ""  ## set by the runner while the player is dead / spectating

var _top: RichTextLabel
var _center: Label
var _respawn: Label
var _spec: Label
var _feed: RichTextLabel
var _board: PanelContainer
var _board_text: RichTextLabel
var _card: PanelContainer
var _card_text: RichTextLabel
var _feed_lines: Array = []  # {text, t}
var _banner_t := 0.0
var _board_t := 0.0
var _by_id := {}  # soldier id -> {name, team}


static func make(p_game: Node, home: Team, away: Team, p_human_team: int) -> FpsMatchHud:
	var h := FpsMatchHud.new()
	h.game = p_game
	h.teams = [home, away]
	h.human_team = p_human_team
	return h


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in teams.size():
		for so in (teams[i] as Team).starters():
			_by_id[so.id] = {"name": so.tag(), "team": i}
	_top = _rich(Control.PRESET_CENTER_TOP, Vector2(-380, 8), Vector2(760, 70), 20)
	_center = Label.new()
	_place(_center, Control.PRESET_CENTER, Vector2(-400, -150), Vector2(800, 80))
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_theme_font_size_override("font_size", 44)
	_outline(_center)
	_center.visible = false
	add_child(_center)
	_respawn = Label.new()
	_place(_respawn, Control.PRESET_CENTER, Vector2(-300, 40), Vector2(600, 40))
	_respawn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn.add_theme_font_size_override("font_size", 28)
	_outline(_respawn)
	_respawn.visible = false
	add_child(_respawn)
	_spec = Label.new()
	_place(_spec, Control.PRESET_CENTER_BOTTOM, Vector2(-300, -120), Vector2(600, 30))
	_spec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spec.add_theme_font_size_override("font_size", 18)
	_outline(_spec)
	add_child(_spec)
	_feed = _rich(Control.PRESET_TOP_RIGHT, Vector2(-420, 90), Vector2(400, 220), 15)
	_board = PanelContainer.new()
	_place(_board, Control.PRESET_CENTER, Vector2(-380, -230), Vector2(760, 460))
	_board.custom_minimum_size = Vector2(760, 0)
	_board_text = _rich_in(_board, Vector2(740, 440), 16)
	_board.visible = false
	add_child(_board)
	_card = PanelContainer.new()
	_place(_card, Control.PRESET_CENTER, Vector2(-320, -220), Vector2(640, 440))
	_card.custom_minimum_size = Vector2(640, 0)
	_card_text = _rich_in(_card, Vector2(620, 420), 20)
	_card.visible = false
	add_child(_card)
	if game != null:
		_connect(game, "game_started", _on_game_started)
		_connect(game, "game_ended", _on_game_ended)
		_connect(game, "round_started", _on_round_started)
		_connect(game, "kill_happened", _on_kill)
		_connect(game, "match_finished", _on_match_finished)


func _connect(obj: Object, sig: String, cb: Callable) -> void:
	if obj.has_signal(sig):
		obj.connect(sig, cb)


## Anchors `c` by `preset` and puts it at `pos` (offset from that anchor) with size `sz`. Offsets are set directly, so the
## result does not depend on the parent's size at the time (the HUD is built before the window lays out).
func _place(c: Control, preset: Control.LayoutPreset, pos: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y


func _outline(l: Control) -> void:
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)


func _rich(preset: Control.LayoutPreset, pos: Vector2, sz: Vector2, font: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(r, preset, pos, sz)
	r.add_theme_font_size_override("normal_font_size", font)
	r.add_theme_font_size_override("bold_font_size", font)
	r.add_theme_color_override("font_outline_color", Color.BLACK)
	r.add_theme_constant_override("outline_size", 5)
	add_child(r)
	return r


func _rich_in(parent: Control, min_size: Vector2, font: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.custom_minimum_size = min_size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", font)
	r.add_theme_font_size_override("bold_font_size", font)
	parent.add_child(r)
	return r


func _hex(team: int) -> String:
	return (teams[team] as Team).color.lightened(0.25).to_html(false)


func _abbrev(team: int) -> String:
	return (teams[team] as Team).abbrev


func show_banner(text: String, secs: float = 3.0) -> void:
	_center.text = text
	_center.visible = true
	_banner_t = secs


func set_scoreboard_visible(v: bool) -> void:
	_board.visible = v and not _card.visible
	if _board.visible:
		_refresh_board()


func is_result_shown() -> bool:
	return _card.visible


static func fmt_clock(secs: float) -> String:
	var s := maxi(0, int(ceil(secs)))
	return "%d:%02d" % [s / 60, s % 60]


## The two lines of the top bar as BBCode: mode / game x of 3 / games won, then the mode's score.
func top_text() -> String:
	if game == null:
		return ""
	var mode: StringName = game.get("mode")
	var num := int(game.get("game_number"))
	var gw: Array = game.get("games_won") if game.get("games_won") != null else [0, 0]
	var gs: Array = game.get("game_scores") if game.get("game_scores") != null else [0, 0]
	var line1 := "%s  -  GAME %d/3  -  [color=#%s]%s %d[/color] : %d [color=#%s]%s[/color]" % [
		String(MatchEngine.MODE_NAMES.get(mode, String(mode))).to_upper(), num, _hex(0), _abbrev(0), int(gw[0]), int(gw[1]), _hex(1), _abbrev(1)]
	# Sudden death counts the round down; TDM and the hill count the game clock up.
	var clock := fmt_clock(float(game.get("time_left"))) if mode == MatchEngine.MODE_SUDDEN_DEATH and game.get("time_left") != null 			else fmt_clock(float(game.get("clock_s")))
	var line2 := ""
	match mode:
		MatchEngine.MODE_KOTH:
			line2 = "[color=#%s]%s %s[/color]  /  %s  /  [color=#%s]%s %s[/color]   [color=#cccccc]%s[/color]" % [
				_hex(0), _abbrev(0), fmt_clock(float(gs[0])), fmt_clock(MatchEngine.KOTH_HOLD_TO_WIN_S), _hex(1), _abbrev(1), fmt_clock(float(gs[1])), clock]
			var holder := _hill_holder()
			if holder >= 0:
				line2 += "   HILL: [color=#%s]%s[/color]" % [_hex(holder), _abbrev(holder)]
			else:
				line2 += "   HILL: OPEN"
		MatchEngine.MODE_SUDDEN_DEATH:
			var alive := _alive_counts()
			line2 = "ROUND %d   [color=#%s]%s %d[/color] : %d [color=#%s]%s[/color]  (first to %d)   ALIVE %d v %d   [color=#cccccc]%s[/color]" % [
				int(game.get("round_number")), _hex(0), _abbrev(0), int(gs[0]), int(gs[1]), _hex(1), _abbrev(1), MatchEngine.ROUNDS_TO_WIN, alive[0], alive[1], clock]
		_:
			line2 = "[color=#%s]%s %d[/color]  -  %d [color=#%s]%s[/color]   (to %d)   [color=#cccccc]%s[/color]" % [
				_hex(0), _abbrev(0), int(gs[0]), int(gs[1]), _hex(1), _abbrev(1), MatchEngine.TDM_POINTS_TO_WIN, clock]
	return "[center]%s\n%s[/center]" % [line1, line2]


func _hill_holder() -> int:
	var h = game.get("hill_holder")
	if h != null:
		return int(h)
	if FpsHill.active and not FpsHill.state.is_empty():
		return int(FpsHill.state.get("holder", -1))
	return -1


func _alive_counts() -> Array:
	var c := [0, 0]
	if game != null and game.has_method("scoreboard"):
		for row in game.scoreboard():
			if bool(row.get("alive", false)):
				var t := int(row.get("team", 0))
				if t == 0 or t == 1:
					c[t] += 1
	return c


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game):
		return
	_top.text = top_text()
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			_center.visible = false
	for l in _feed_lines:
		l["t"] = float(l["t"]) - delta
	var before := _feed_lines.size()
	_feed_lines = _feed_lines.filter(func(l): return float(l["t"]) > 0.0)
	if before != _feed_lines.size() or _feed.text == "":
		_refresh_feed()
	var left := 0.0
	if game.has_method("human_respawn_left"):
		left = float(game.human_respawn_left())
	var human = game.get("human")
	var dead: bool = human != null and left > 0.0
	_respawn.visible = dead and not _card.visible
	if _respawn.visible:
		_respawn.text = "RESPAWN IN %d" % int(ceil(left))
	var il = game.get("intermission_left")
	if il != null and float(il) > 0.0 and _banner_t <= 0.0 and not _card.visible:
		_center.visible = true
	_spec.text = spectate_text
	_spec.visible = spectate_text != "" and not _card.visible
	if _board.visible:
		_board_t -= delta
		if _board_t <= 0.0:
			_refresh_board()


func _refresh_feed() -> void:
	var t := ""
	for l in _feed_lines:
		t += String(l["text"]) + "\n"
	_feed.text = "[right]%s[/right]" % t


func _refresh_board() -> void:
	_board_t = 0.25
	if game == null or not game.has_method("scoreboard"):
		return
	var rows: Array = game.scoreboard()
	var t := "[center][b]SCOREBOARD[/b][/center]\n"
	for team in [0, 1]:
		t += "\n[color=#%s][b]%s[/b][/color]   %s\n" % [_hex(team), (teams[team] as Team).name.to_upper(), "K   D   A"]
		for row in rows:
			if int(row.get("team", -1)) != team:
				continue
			var nm := String(row.get("tag", row.get("name", "?")))
			var c := "ffffff" if bool(row.get("alive", true)) else "888888"
			t += "[color=#%s]%-16s %3d %3d %3d[/color]\n" % [c, nm, int(row.get("kills", 0)), int(row.get("deaths", 0)), int(row.get("assists", 0))]
	_board_text.text = t


func _on_game_started(number: int, mode: StringName) -> void:
	show_banner("GAME %d: %s" % [number, String(MatchEngine.MODE_NAMES.get(mode, String(mode))).to_upper()], 3.0)
	_feed_lines.clear()


func _on_game_ended(g: Dictionary) -> void:
	var w := int(g.get("winner", -1))
	var txt := "GAME %d" % int(g.get("number", 0))
	if w >= 0 and w < teams.size():
		txt += ": %s WINS" % (teams[w] as Team).name.to_upper()
	show_banner(txt, 3.0)


func _on_round_started(number: int) -> void:
	show_banner("ROUND %d" % number, 1.5)


func _on_kill(info: Dictionary) -> void:
	var k = _by_id.get(int(info.get("killer_id", info.get("killer", -1))), {"name": "?", "team": 0})
	var v = _by_id.get(int(info.get("victim_id", info.get("victim", -1))), {"name": "?", "team": 1})
	var tail := ""
	if bool(info.get("headshot", false)):
		tail += " [HS]"
	if info.has("dist"):
		tail += "  %dm" % roundi(float(info["dist"]))
	_feed_lines.append({"text": "[color=#%s]%s[/color]  >  [color=#%s]%s[/color]%s" % [_hex(int(k["team"])), k["name"], _hex(int(v["team"])), v["name"], tail], "t": 6.0})
	if _feed_lines.size() > 7:
		_feed_lines.pop_front()
	_refresh_feed()


func _on_match_finished(result: MatchResult) -> void:
	show_result(result)


func show_result(result: MatchResult) -> void:
	_board.visible = false
	_respawn.visible = false
	_center.visible = false
	var t := "[center][b]FINAL[/b]\n"
	if result.winner_index >= 0:
		t += "[color=#%s]%s WIN[/color]   %d - %d\n" % [_hex(result.winner_index), result.teams[result.winner_index].name.to_upper(), result.score[0], result.score[1]]
	else:
		t += "%d - %d\n" % [result.score[0], result.score[1]]
	t += "[/center]\n"
	for g in result.games:
		var mode: StringName = g.get("mode", &"")
		var gw := int(g.get("winner", -1))
		t += "Game %d  %-20s %s   %s\n" % [int(g.get("number", 0)), String(MatchEngine.MODE_NAMES.get(mode, String(mode))), MatchResult.game_score_text(g), result.teams[gw].abbrev if gw >= 0 and gw < result.teams.size() else "-"]
	if result.mvp_id >= 0 and _by_id.has(result.mvp_id):
		t += "\nMVP: %s" % _by_id[result.mvp_id]["name"]
	t += "\n\n[center][color=#aaaaaa]press any key[/color][/center]"
	_card_text.text = t
	_card.visible = true

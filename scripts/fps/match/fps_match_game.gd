class_name FpsMatchGame
extends Node3D
## The playable 3D career match: best of 3 games on the home team's ArenaMap field (Game 1 TDM, Game 2 King of the Hill,
## Game 3 TDM Sudden Death if it is 1-1), ten soldiers, one of whom may be the human (an FpsPlayer; everyone else is an
## FpsBot). The rules live in FpsMatchRules, the box score mirrors MatchEngine's, and the finished match is a normal
## MatchResult the season consumes. `sim_rest()` hands the unfinished part of the match to the numeric sim.
##
## The node must be in the scene tree before setup() (launch() does that). _physics_process just calls step(delta), so
## tests can drive a match with their own deltas.
##
## World interface used by FpsBot: enemies_of, allies_of, hill_center, hill_radius, cover_points, zone_name_for,
## count_on_point, arena_map, game_mode, scheme_of (and in_spawn_zone for the spawn-safety rule).

signal game_started(number: int, mode: StringName)
signal game_ended(game: Dictionary)
signal round_started(number: int)
signal round_ended(info: Dictionary)
## {killer, victim (soldier ids, killer -1 when unknown), team (killer's), victim_team, headshot, dist, wipe, assists}
signal kill_happened(info: Dictionary)
signal human_died(killer_id: int)
signal human_respawned
## The pause between games / rounds begins (also once before game 1). `kind` is "game" or "round".
signal intermission_started(kind: String, number: int, mode: StringName)
signal match_finished(result: MatchResult)

enum Phase { INTERMISSION, PLAY, DONE }

const RESPAWN_S := FpsMatchRules.RESPAWN_S
const INTERMISSION_S := FpsMatchRules.INTERMISSION_S

var teams: Array = [null, null]
var seed_value := 1
var field: ArenaMap
var weather: Weather = null
## Rating points the home crowd adds in the part of the match that is simmed (see Market.crowd_edge).
var crowd := 0.0
var arena: FpsArena
var human: FpsPlayer = null
## FpsBot per team (the human's soldier is not in here, see `squad()` for everyone).
var bots: Array = [[], []]
## Tests can build bots another way: a Callable returning a bot-like Node3D.
var bot_factory: Callable = Callable()

var phase := Phase.INTERMISSION
var mode: StringName = MatchEngine.MODE_TDM
var game_number := 0
var round_number := 0
## TDM points / KOTH hold seconds / sudden-death rounds won, per team.
var game_scores: Array = [0.0, 0.0]
var games_won: Array[int] = [0, 0]
## Seconds into the current game (sudden death: into the current round).
var clock_s := 0.0
## Seconds left on the round clock (sudden death) or the stalemate guard (TDM/KOTH).
var time_left := 0.0
var intermission_left := 0.0
var next_game_number := 1
var next_mode: StringName = MatchEngine.MODE_TDM
## KOTH: which side banked time last (-1 none).
var hill_holder := -1
var finished := false
var result: MatchResult

var _units: Array = [[], []]  # every participant per team (bots and the human), same order as the starters
var _by_id: Dictionary = {}  # soldier id -> unit
var _down: Dictionary = {}  # soldier id -> true while logically dead
var _dead_for: Dictionary = {}  # soldier id -> seconds dead
var _dmg: Dictionary = {}  # victim id -> {attacker id: damage this life}
var _last_pos: Dictionary = {}
var _last_hit: Dictionary = {}  # shooter id -> {victim, headshot}
var _pending: Array = []  # kills waiting for the next step
var _rng := RandomNumberGenerator.new()
var _zone := FpsHillRules.Zone.EMPTY
var _hill := Rect2()
var _opening_open := true
var _clutch: Node3D = null
var _next_kind := "game"
var _game: Dictionary = {}
var _game_clock_total := 0.0
var _committed_box: Dictionary = {}
var _committed_events := 0
var _committed_rounds := 0
var _emitted_final := false
var _swapped_out := false


## Builds the arena and the soldiers under `parent`. `human` plays his own soldier when he starts for either team.
static func launch(parent: Node, team_a: Team, team_b: Team, seed_value := 1, p_human: Soldier = null,
		p_field: ArenaMap = null, wx: Weather = null) -> FpsMatchGame:
	var g := FpsMatchGame.new()
	g.name = "FpsMatchGame"
	parent.add_child(g)
	g.setup(team_a, team_b, seed_value, p_human, p_field, wx)
	return g


static func box_template(soldier: Soldier, team: int, slot: StringName) -> Dictionary:
	return FpsMatchRules.box_template(soldier.id, team, slot)


func setup(team_a: Team, team_b: Team, p_seed := 1, p_human: Soldier = null, p_field: ArenaMap = null,
		wx: Weather = null) -> void:
	teams = [team_a, team_b]
	seed_value = p_seed
	_rng.seed = p_seed
	field = p_field if p_field != null else ArenaMap.for_team(team_a.abbrev)
	field.ensure_built()
	weather = wx
	crowd = Market.crowd_edge(team_a)
	arena = FpsArena.make(field)
	add_child(arena)
	_hill = arena.hill_rect()
	FpsHill.set_rect(_hill)
	_start_result()
	for t in 2:
		var tm: Team = teams[t]
		var i := 0
		for s: Soldier in tm.starters():
			var slot: StringName = tm.slot_of(s)
			var unit: Node3D
			if p_human != null and s == p_human:
				unit = _make_human(s, t)
			else:
				unit = _make_bot(s, t, slot, i)
				bots[t].append(unit)
			_units[t].append(unit)
			_by_id[s.id] = unit
			result.box[s.id] = FpsMatchRules.box_template(s.id, t, slot)
			_place(unit, t, slot)
			unit.died.connect(_on_unit_died.bind(unit))
			unit.damaged.connect(_on_unit_damaged.bind(unit))
			var w = unit.get("weapon")
			if w != null and w is Object and (w as Object).has_signal("fired"):
				w.fired.connect(_on_unit_fired.bind(unit))
			_last_pos[s.id] = unit.global_position
			i += 1
	_freeze_all(true)
	_commit()
	_next_kind = "game"
	next_game_number = 1
	next_mode = MatchEngine.GAME_ORDER[0]
	intermission_left = INTERMISSION_S
	phase = Phase.INTERMISSION
	intermission_started.emit.call_deferred("game", next_game_number, next_mode)


func _exit_tree() -> void:
	if FpsHill.use_rect and FpsHill.rect == _hill:
		FpsHill.clear()


func _start_result() -> void:
	result = MatchResult.new()
	result.match_seed = seed_value
	var wx: Weather = weather if weather != null else Weather.clear()
	result.weather_kind = wx.kind
	result.weather_level = wx.level
	result.surface = field.surface
	result.crowd = crowd
	result.teams = [teams[0], teams[1]]
	result.events.append("=== %s vs %s (seed %d) ===" % [teams[0].name, teams[1].name, seed_value])
	result.events.append("%s OVR %d | %s OVR %d" % [teams[0].abbrev, teams[0].team_ovr(), teams[1].abbrev, teams[1].team_ovr()])
	if not wx.is_clear():
		result.events.append("Weather: %s. %s" % [wx.label(), wx.effect_text()])


func _make_bot(s: Soldier, t: int, slot: StringName, index: int) -> Node3D:
	var bot: Node3D = bot_factory.call() if bot_factory.is_valid() else FpsBot.new()
	bot.set("world", self)
	add_child(bot)
	bot.setup(s, t, Scheme.SLOT_ROLES.get(slot, Scheme.Role.FLEX))
	bot.set("slot", slot)
	if bot.get("rng") != null:
		bot.rng.seed = seed_value * 1000 + t * 100 + index
	return bot


func _make_human(s: Soldier, t: int) -> Node3D:
	var p := FpsPlayer.new()
	p.team_id = t
	add_child(p)
	p.setup(s)
	p.damage_gate = func(pl: FpsPlayer) -> bool: return not in_spawn_zone(pl.team_id, pl.global_position)
	human = p
	return p


func _place(unit: Node3D, t: int, slot: StringName) -> void:
	unit.global_position = arena.spawn_point(t, teams[t].scheme, slot)
	unit.rotation.y = arena.spawn_facing_yaw(t)


# --- queries -------------------------------------------------------------------------

## Everyone on a team (bots and the human).
func squad(team: int) -> Array:
	return _units[team]


func unit_of(soldier_id: int) -> Node3D:
	return _by_id.get(soldier_id)


func box() -> Dictionary:
	return result.box


## Seconds until the human is back, 0 when he is alive, -1 when he is out until the next round (sudden death).
func human_respawn_left() -> float:
	if human == null or not _down.has(human.soldier.id):
		return 0.0
	if mode == MatchEngine.MODE_SUDDEN_DEATH:
		return -1.0
	return maxf(0.0, RESPAWN_S - float(_dead_for.get(human.soldier.id, 0.0)))


func alive_count(team: int) -> int:
	var n := 0
	for u in _units[team]:
		if not _down.has(u.soldier.id):
			n += 1
	return n


func scoreboard() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for t in 2:
		for u in _units[t]:
			var s: Soldier = u.soldier
			var line: Dictionary = result.box[s.id]
			rows.append({
				"id": s.id, "team": t, "name": s.display_name(), "tag": s.tag(), "slot": line["slot"],
				"kills": line["kills"], "deaths": line["deaths"], "assists": line["assists"],
				"alive": not _down.has(s.id), "human": u == human,
			})
	return rows


# --- world interface for the bots ----------------------------------------------------

func enemies_of(team_id: int) -> Array:
	return _units[1 - team_id]


func allies_of(team_id: int) -> Array:
	return _units[team_id]


func hill_center() -> Vector3:
	return FpsArena.to3(_hill.get_center())


## Half the diagonal of the square, so a circle test around the centre covers the corners.
func hill_radius() -> float:
	return _hill.size.length() * 0.5


func cover_points() -> Array:
	return arena.cover_points()


func zone_name_for(team_id: int) -> String:
	if mode != MatchEngine.MODE_KOTH or phase != Phase.PLAY:
		return "empty"
	return FpsHillMatch.zone_name(_zone, team_id)


func count_on_point(team_id: int) -> int:
	var n := 0
	for u in _units[team_id]:
		if _on_hill(u):
			n += 1
	return n


func arena_map() -> ArenaMap:
	return field


func game_mode() -> StringName:
	return mode


func scheme_of(team_id: int) -> Scheme:
	return teams[team_id].scheme


## In `team`'s own spawn zone (nobody can be shot there).
func in_spawn_zone(team: int, v: Vector3) -> bool:
	return arena.in_spawn_zone(team, v)


func _on_hill(u: Node3D) -> bool:
	return not _down.has(u.soldier.id) and u.alive and _hill.has_point(Vector2(u.global_position.x, u.global_position.z))


# --- stepping ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if finished:
		return
	_flush_kills()
	match phase:
		Phase.INTERMISSION:
			intermission_left -= delta
			if intermission_left <= 0.0:
				_begin_play()
		Phase.PLAY:
			_step_play(delta)


func _step_play(delta: float) -> void:
	clock_s += delta
	var sd := mode == MatchEngine.MODE_SUDDEN_DEATH
	time_left = maxf(0.0, (FpsMatchRules.ROUND_TIME_LIMIT_S if sd else FpsMatchRules.ARENA_SAFETY_LIMIT_S) - clock_s)
	for t in 2:
		for u in _units[t]:
			var id: int = u.soldier.id
			if not _down.has(id):
				var p: Vector3 = u.global_position
				result.box[id]["distance"] += Vector2(p.x - _last_pos[id].x, p.z - _last_pos[id].z).length()
				_last_pos[id] = p
	if sd:
		_step_sudden_death()
		return
	# Individual respawns.
	for id in _dead_for.keys():
		_dead_for[id] += delta
		if _dead_for[id] >= RESPAWN_S:
			_respawn_unit(_by_id[id])
	if mode == MatchEngine.MODE_KOTH:
		_score_hill(delta)
	var w := FpsMatchRules.tdm_winner(game_scores) if mode == MatchEngine.MODE_TDM else FpsMatchRules.koth_winner(game_scores)
	if w < 0 and clock_s >= FpsMatchRules.ARENA_SAFETY_LIMIT_S:
		w = FpsMatchRules.timeout_winner(game_scores, _rng.randi_range(0, 1))
	if w >= 0:
		_end_game(w)


func _score_hill(delta: float) -> void:
	var on: Array = [[], []]
	for t in 2:
		for u in _units[t]:
			if _on_hill(u):
				on[t].append(u)
	var st := FpsMatchRules.hill_state(on[0].size(), on[1].size())
	_zone = FpsHillRules.zone_state(on[0].size(), on[1].size())
	if st == FpsMatchRules.HILL_CONTESTED:
		for side in on:
			for u in side:
				result.box[u.soldier.id]["contest_s"] += delta
	elif st >= 0:
		var before: float = game_scores[st]
		game_scores = FpsMatchRules.koth_step(game_scores, on[0].size(), on[1].size(), delta)
		for u in on[st]:
			result.box[u.soldier.id]["hill_s"] += delta
		if hill_holder != st:
			hill_holder = st
			for u in on[st]:
				result.box[u.soldier.id]["caps"] += 1
			result.events.append("%s %s take the hill.  [%s - %s]" % [_stamp(), teams[st].abbrev,
				MatchEngine._fmt_secs(game_scores[0]), MatchEngine._fmt_secs(game_scores[1])])
		elif int(before / 30.0) != int(game_scores[st] / 30.0) and game_scores[st] < FpsMatchRules.KOTH_HOLD_TO_WIN_S:
			result.events.append("%s %s have held for %s.  [%s - %s]" % [_stamp(), teams[st].abbrev,
				MatchEngine._fmt_secs(game_scores[st]), MatchEngine._fmt_secs(game_scores[0]), MatchEngine._fmt_secs(game_scores[1])])
	FpsHill.state = {"holder": hill_holder, "zone": _zone, "scores": game_scores.duplicate(),
		"time_left": time_left, "hold_to_win": FpsMatchRules.KOTH_HOLD_TO_WIN_S}


func _step_sudden_death() -> void:
	# Clutch: one soldier left alone against 2+ enemies.
	for i in 2:
		if _clutch == null and alive_count(i) == 1 and alive_count(1 - i) >= 2:
			for u in _units[i]:
				if not _down.has(u.soldier.id):
					_clutch = u
	if FpsMatchRules.sd_round_over(alive_count(0), alive_count(1), clock_s):
		_end_round()


func _end_round() -> void:
	var a := alive_count(0)
	var b := alive_count(1)
	var winner := FpsMatchRules.sd_round_winner(a, b, _hp_total(0), _hp_total(1), _rng.randi_range(0, 1))
	game_scores[winner] = int(game_scores[winner]) + 1
	var info := {"number": round_number, "mode": MatchEngine.MODE_SUDDEN_DEATH, "winner": winner,
		"duration_s": clock_s, "survivors": [a, b], "clutch_soldier_id": -1}
	for t in 2:
		for u in _units[t]:
			if not _down.has(u.soldier.id):
				result.box[u.soldier.id]["rounds_survived"] += 1
	if _clutch != null and _clutch.team_id == winner:
		result.box[_clutch.soldier.id]["clutches"] += 1
		info["clutch_soldier_id"] = _clutch.soldier.id
		result.events.append("%s CLUTCH! %s wins it alone." % [_stamp(), _name(_clutch)])
	result.rounds.append(info)
	_game["rounds"].append(info)
	_game_clock_total += clock_s
	result.events.append("Round %d -> %s (%s)  [%d-%d]" % [round_number, teams[winner].abbrev,
		MatchEngine._fmt_secs(clock_s), game_scores[0], game_scores[1]])
	round_ended.emit(info)
	if FpsMatchRules.sd_game_over(game_scores, round_number):
		_end_game(FpsMatchRules.sd_game_winner(game_scores))
	else:
		_begin_intermission("round")


func _hp_total(team: int) -> float:
	var t := 0.0
	for u in _units[team]:
		if not _down.has(u.soldier.id):
			t += maxf(0.0, float(u.health))
	return t


# --- games and rounds ----------------------------------------------------------------

func _begin_intermission(kind: String) -> void:
	phase = Phase.INTERMISSION
	_next_kind = kind
	intermission_left = INTERMISSION_S
	if kind == "game":
		next_game_number = game_number + 1
		next_mode = MatchEngine.GAME_ORDER[mini(game_number, MatchEngine.GAME_ORDER.size() - 1)]
	_freeze_all(true)
	intermission_started.emit(kind, next_game_number if kind == "game" else round_number + 1,
		next_mode if kind == "game" else mode)


func _begin_play() -> void:
	if _next_kind == "game":
		_begin_game()
	else:
		_begin_round()
	phase = Phase.PLAY


func _begin_game() -> void:
	game_number += 1
	mode = MatchEngine.GAME_ORDER[game_number - 1]
	clock_s = 0.0
	round_number = 0
	hill_holder = -1
	_zone = FpsHillRules.Zone.EMPTY
	_game_clock_total = 0.0
	_opening_open = true
	game_scores = [0, 0] if mode == MatchEngine.MODE_SUDDEN_DEATH else [0.0, 0.0]
	for t in 2:
		for u in _units[t]:
			result.box[u.soldier.id]["games"] += 1
	_game = {"number": game_number, "mode": mode, "score": [0, 0], "winner": -1, "duration_s": 0.0, "rounds": []}
	var goal := ""
	match mode:
		MatchEngine.MODE_TDM:
			goal = "first to %d" % FpsMatchRules.TDM_POINTS_TO_WIN
		MatchEngine.MODE_KOTH:
			goal = "first to %d:%02d of hold time" % [int(FpsMatchRules.KOTH_HOLD_TO_WIN_S) / 60, int(FpsMatchRules.KOTH_HOLD_TO_WIN_S) % 60]
		_:
			goal = "first to %d rounds" % FpsMatchRules.ROUNDS_TO_WIN
	result.events.append("=== GAME %d: %s (%s) ===" % [game_number, MatchEngine.mode_name(mode), goal])
	game_started.emit(game_number, mode)
	if mode == MatchEngine.MODE_SUDDEN_DEATH:
		_begin_round()
	else:
		_respawn_all()


func _begin_round() -> void:
	round_number += 1
	clock_s = 0.0
	_clutch = null
	_opening_open = true
	for t in 2:
		for u in _units[t]:
			result.box[u.soldier.id]["rounds_played"] += 1
	result.events.append("--- Round %d ---" % round_number)
	_respawn_all()
	round_started.emit(round_number)


func _end_game(winner: int) -> void:
	var sd := mode == MatchEngine.MODE_SUDDEN_DEATH
	_game["winner"] = winner
	_game["score"] = [int(game_scores[0]), int(game_scores[1])]
	_game["duration_s"] = _game_clock_total if sd else clock_s
	games_won[winner] += 1
	result.score = [games_won[0], games_won[1]]
	result.games.append(_game)
	result.events.append("=== Game %d -> %s %s  (games %d-%d) ===" % [game_number, teams[winner].abbrev,
		MatchResult.game_score_text(_game), games_won[0], games_won[1]])
	_commit()
	game_ended.emit(_game)
	FpsHill.state = {}
	if FpsMatchRules.match_winner(games_won) >= 0:
		_finish_match()
	else:
		_begin_intermission("game")


func _finish_match() -> void:
	result.winner_index = FpsMatchRules.match_winner(games_won)
	result.mvp_id = FpsMatchRules.pick_mvp(result.box, result.winner_index)
	result.events.append("=== FINAL: %s — %s wins ===" % [result.score_line(), result.winner().name])
	_conclude()


func _conclude() -> void:
	finished = true
	phase = Phase.DONE
	_freeze_all(true)
	FpsHill.clear()
	if not _emitted_final:
		_emitted_final = true
		match_finished.emit(result)


## Remembers what has been fully played, so sim_rest can drop a game in progress.
func _commit() -> void:
	_committed_box = result.box.duplicate(true)
	_committed_events = result.events.size()
	_committed_rounds = result.rounds.size()


# --- units ---------------------------------------------------------------------------

func _respawn_all() -> void:
	_dead_for.clear()
	_dmg.clear()
	for t in 2:
		for u in _units[t]:
			_respawn_unit(u)


func _respawn_unit(u: Node3D) -> void:
	var id: int = u.soldier.id
	var was_down := _down.has(id)
	var t: int = u.team_id
	var at := arena.spawn_point(t, teams[t].scheme, _slot(u))
	_down.erase(id)
	_dead_for.erase(id)
	_dmg.erase(id)
	u.respawn(at)
	u.global_position = at
	u.rotation.y = arena.spawn_facing_yaw(t)
	if u == human:
		human.controls_enabled = true
		if was_down:
			human_respawned.emit()
	_last_pos[id] = at


func _freeze_all(on: bool) -> void:
	for t in 2:
		for u in _units[t]:
			if u == human:
				human.controls_enabled = not on
				if on:
					human.weapon.set_trigger(false)
			else:
				u.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT


func _on_unit_died(source, unit: Node3D) -> void:
	if phase != Phase.PLAY:
		return
	var killer: Node3D = null
	if source != null and is_instance_valid(source) and source is Node3D and "soldier" in source and source.soldier != null:
		killer = source
	_pending.append({"killer": killer, "victim": unit,
		"dist": killer.global_position.distance_to(unit.global_position) if killer != null else 0.0})


func _on_unit_damaged(amount: float, source, victim: Node3D) -> void:
	if phase != Phase.PLAY or source == null or not is_instance_valid(source) or not ("soldier" in source) \
			or source.soldier == null or source.team_id == victim.team_id:
		return
	var aid: int = source.soldier.id
	var vid: int = victim.soldier.id
	if not _dmg.has(vid):
		_dmg[vid] = {}
	_dmg[vid][aid] = float(_dmg[vid].get(aid, 0.0)) + amount
	if result.box.has(aid):
		result.box[aid]["damage"] += amount


func _on_unit_fired(res: Dictionary, unit: Node3D) -> void:
	if phase != Phase.PLAY or not result.box.has(unit.soldier.id):
		return
	var line: Dictionary = result.box[unit.soldier.id]
	line["shots"] += 1
	if res.get("hit", false):
		line["hits"] += 1
		var head: bool = res.get("headshot", false)
		if head:
			line["headshots"] += 1
		_last_hit[unit.soldier.id] = {"victim": res.get("target", res.get("collider")), "headshot": head}


func _flush_kills() -> void:
	if _pending.is_empty():
		return
	var queue := _pending
	_pending = []
	for k in queue:
		_apply_kill(k["killer"], k["victim"], k["dist"])


func _apply_kill(killer: Node3D, victim: Node3D, dist: float) -> void:
	var vid: int = victim.soldier.id
	if _down.has(vid):
		return
	_down[vid] = true
	result.box[vid]["deaths"] += 1
	var vt: int = victim.team_id
	var kid := -1
	var wipe := false
	var assist_tags: Array[String] = []
	var assist_ids: Array[int] = []
	var headshot := false
	var line := ""
	if killer != null and killer.team_id != vt:
		kid = killer.soldier.id
		var kt: int = killer.team_id
		var kb: Dictionary = result.box[kid]
		var lh: Dictionary = _last_hit.get(kid, {})
		headshot = bool(lh.get("headshot", false)) and lh.get("victim") == victim
		kb["kills"] += 1
		kb["kills_%s" % FpsMatchRules.band(dist)] += 1
		kb["kill_dist"] += dist
		if _opening_open:
			_opening_open = false
			kb["opening_kills"] += 1
		var hurt: Dictionary = _dmg.get(vid, {})
		for u in _units[kt]:
			var aid: int = u.soldier.id
			if aid != kid and float(hurt.get(aid, 0.0)) >= FpsMatchRules.ASSIST_MIN_DAMAGE:
				result.box[aid]["assists"] += 1
				assist_ids.append(aid)
				assist_tags.append(u.soldier.tag())
		line = "%s %s %s %s at %dm (%s)" % [_stamp(), _name(killer), "HEADSHOT" if headshot else "killed",
			_name(victim), roundi(dist), FpsMatchRules.band(dist)]
		if not assist_tags.is_empty():
			line += " — assist: " + ", ".join(assist_tags)
		if mode != MatchEngine.MODE_SUDDEN_DEATH:
			wipe = alive_count(vt) == 0
			if mode == MatchEngine.MODE_TDM:
				game_scores[kt] += FpsMatchRules.tdm_kill_points(wipe)
			if wipe:
				kb["wipes"] += 1
				line += " — TEAM WIPE"
				if mode == MatchEngine.MODE_TDM:
					line += " (+%d)" % FpsMatchRules.TDM_WIPE_BONUS
			if mode == MatchEngine.MODE_TDM:
				line += "  [%d-%d]" % [int(game_scores[0]), int(game_scores[1])]
	else:
		line = "%s %s went down" % [_stamp(), _name(victim)]
	_dmg.erase(vid)
	result.events.append(line)
	if mode != MatchEngine.MODE_SUDDEN_DEATH:
		_dead_for[vid] = 0.0
	var info := {"killer": kid, "victim": vid, "team": 1 - vt if kid >= 0 else -1, "victim_team": vt,
		"headshot": headshot, "dist": dist, "wipe": wipe, "assists": assist_ids}
	kill_happened.emit(info)
	if victim == human:
		human_died.emit(kid)


func _name(u: Node3D) -> String:
	return "[%s] %s (%s)" % [teams[u.team_id].abbrev, u.soldier.tag(), _slot(u)]


func _slot(u: Node3D) -> StringName:
	return result.box[u.soldier.id]["slot"]


func _stamp() -> String:
	var secs := MatchEngine._fmt_secs(clock_s)
	if mode == MatchEngine.MODE_SUDDEN_DEATH:
		return "G%d R%d %s" % [game_number, round_number, secs]
	return "G%d %s" % [game_number, secs]


# --- sim the rest --------------------------------------------------------------------

## Stops the 3D play and finishes the match with the numeric sim. Games already completed here keep their 3D data; the game
## in progress (and anything after it) is simulated. Returns the whole MatchResult and emits match_finished once.
func sim_rest() -> MatchResult:
	if finished:
		return result
	_pending.clear()
	_swapped_out = true
	# Drop whatever the unfinished game had added.
	result.box = _committed_box.duplicate(true)
	result.events.resize(_committed_events)
	result.rounds.resize(_committed_rounds)
	var done := result.games.size()
	var eng := MatchEngine.new()
	eng.start_from(teams[0], teams[1], seed_value, field, weather, crowd, done, games_won[0], games_won[1])
	while eng.step():
		pass
	var sr := eng.result()
	for g in sr.games:
		result.games.append(g)
	for r in sr.rounds:
		result.rounds.append(r)
	result.box = FpsMatchRules.merge_box(result.box, sr.box)
	result.events.append("--- the rest of the match is simulated ---")
	var from := 0
	for i in sr.events.size():
		if sr.events[i].begins_with("=== GAME"):
			from = i
			break
	for i in range(from, sr.events.size()):
		result.events.append(sr.events[i])
	result.score = [sr.score[0], sr.score[1]]
	result.winner_index = sr.winner_index
	games_won = [sr.score[0], sr.score[1]]
	result.mvp_id = FpsMatchRules.pick_mvp(result.box, result.winner_index)
	_conclude()
	return result

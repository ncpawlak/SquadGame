class_name MatchEngine
extends RefCounted
## Tick-based 5v5 match simulator on a 2D arena (ArenaMap). Deterministic for a given seed.
## The same engine drives "Sim" (simulate() runs it to the end) and "Watch" (the viewer calls
## step() in real time with `record` on and draws the visual events it emits).
##
## A match is best of 3 games, always in this order (a 2-0 skips the third):
## 1. Team Deathmatch (TDM): 1 point per kill, +TDM_WIPE_BONUS for wiping the other team; first to
##    TDM_POINTS_TO_WIN. Eliminated soldiers stay down until their whole team is wiped, then that
##    team respawns in formation at its end of the map.
## 2. King of the Hill (KOTH): a square in the middle of the map. A team banks hold time while it
##    has someone on the point and the other team doesn't (nobody scores while it's contested);
##    first to KOTH_HOLD_TO_WIN_S of total hold time. Same elimination/respawn rule as TDM.
## 3. TDM Sudden Death: elimination rounds with no respawns, first to ROUNDS_TO_WIN rounds.
##
## Movement: soldiers spawn in the Swing formation and walk (Speed, slowed by fatigue and by being
## shot at) to their slot's spot: frontmen up front, the center watching the middle lane, flexes
## running the outside lanes until their flank lands (Speed) and they collapse in with an accuracy
## bonus. A soldier who hasn't seen an enemy for a while goes hunting; frontmen close to short
## range. Tall walls block sight; crates give cover (shots through them hit less), and aware
## soldiers who get shot at duck behind the nearest cover. In KOTH, Objective IQ decides who plays
## the point, Breach pushes onto a held point and wins the fight there, and Anchor keeps the
## soldiers on the point alive and shooting straight.
##
## Shooting: each tick every soldier with an enemy in sight may get a shot off (Awareness vs target
## Agility), then fires a burst: first bullet uses range accuracy, follow-ups use Grouping +
## Strength (recoil). Endurance limits fatigue, which builds across the whole match. Reload sets
## reload time, Composure matters when outnumbered, Teamwork drives focus fire and a small
## squad-wide bonus, Strength also absorbs damage taken, Sway steadies aim on the move, tired or at
## long range, and Awareness decides when a soldier pushes and how well a flex flanks. Weekly fatigue (Soldier.fatigue) scales down
## accuracy, speed and reaction stats via Conditioning.penalty().

const MODE_TDM := &"tdm"
const MODE_KOTH := &"koth"
const MODE_SUDDEN_DEATH := &"sudden_death"
const GAME_ORDER: Array[StringName] = [MODE_TDM, MODE_KOTH, MODE_SUDDEN_DEATH]
const GAMES_TO_WIN := 2
const MODE_NAMES := {MODE_TDM: "Team Deathmatch", MODE_KOTH: "King of the Hill", MODE_SUDDEN_DEATH: "TDM Sudden Death"}
const MODE_SHORT := {MODE_TDM: "TDM", MODE_KOTH: "KOTH", MODE_SUDDEN_DEATH: "SD"}

const TDM_POINTS_TO_WIN := 50
const TDM_WIPE_BONUS := 5
const KOTH_HOLD_TO_WIN_S := 120.0
## Sudden death: first to 4 rounds.
const ROUNDS_TO_WIN := 4
const MAX_ROUNDS := 7
const TICK_SECONDS := 0.5
## Match-day form, in rating points added to every stat for this match only: a squad-wide swing
## (the whole team is sharp or flat) plus a smaller personal one. Without it a match is hundreds of
## engagements and the better roster almost always wins; with it upsets happen like real sports.
const TEAM_FORM_SD := 12.0
const PLAYER_FORM_SD := 3.0
const FORM_LIMIT := 2.2
## Team form beyond this many points gets a line in the match log.
const FORM_NOTE := 10.0
const ROUND_TIME_LIMIT_S := 120.0
## Arena games end on the scoreboard; this only guards against a stalemate.
const ARENA_SAFETY_LIMIT_S := 1800.0
const MAX_ENGAGE_DISTANCE := 95.0
## Fatigue kept between games / by a respawning team.
const GAME_RECOVERY := 0.6
const RESPAWN_RECOVERY := 0.8
## A teammate hit below this HP is "almost eliminated": killing his attacker within
## SAVE_WINDOW_TICKS counts as a save.
const SAVE_HP := 30.0
const SAVE_WINDOW_TICKS := 6
## Movement while being shot at.
const CONTACT_ADVANCE_MULT := 0.5
## Per-tick chance of getting a shot off, before role/awareness/agility modifiers.
const BASE_ENGAGE := 0.13
const LONG_RANGE_ENGAGE_MULT := 0.75
const MAG_SIZE := 25
const BURST := 3
const SHORT_RANGE_MAX := 15.0
const MEDIUM_RANGE_MAX := 40.0
## Shots that cross a crate hit this much less often.
const COVER_HIT_MULT := 0.6
## Ticks without seeing an enemy (once settled) before a soldier goes hunting.
const HUNT_AFTER_TICKS := 10
## Frontmen on the hunt close to this range before planting.
const FRONT_PUSH_RANGE := 11.0
## How far a soldier under fire will run for cover, and how long he stays there.
const COVER_SEARCH_RADIUS := 9.0
const COVER_TICKS := 10
const REPATH_TICKS := 4
## Vision (line of sight) is refreshed every this many ticks.
const VISION_EVERY := 2
## Within this distance of a held point, the push slows down unless the soldier can Breach.
const BREACH_ZONE := 8.0
## Chance (at respawn) that a soldier plays the point, before Objective IQ.
const POINT_ROLE_BASE := {Scheme.Role.FRONTMAN: 0.65, Scheme.Role.CENTER: 0.3, Scheme.Role.FLEX: 0.4}

const RANGE_BASE_HIT := {&"short": 0.30, &"medium": 0.20, &"long": 0.11}
const RANGE_STAT := {&"short": &"short_acc", &"medium": &"medium_acc", &"long": &"long_acc"}
## Stats reduced by pre-match fatigue.
const FATIGUE_STATS: Array[StringName] = [
	&"short_acc", &"medium_acc", &"long_acc", &"grouping", &"speed", &"agility", &"awareness", &"reload",
]


class Combatant:
	var soldier: Soldier
	var team: int
	var slot_id: StringName
	var role: Scheme.Role
	var hp := 100.0
	var alive := true
	var mag := MAG_SIZE
	var reload_ticks := 0
	var fatigue := 0.0
	var flank_progress := 0.0
	var target: Combatant = null
	## victim soldier id -> damage dealt this life (for assists)
	var damage_to: Dictionary = {}
	## 1.0 = fresh; < 1.0 scales FATIGUE_STATS for a soldier who came in tired.
	var condition := 1.0
	## Match-day form in rating points (see TEAM_FORM_SD).
	var form := 0.0
	## Enemy who last dropped this soldier below SAVE_HP, and when (for teammate saves).
	var endangered_by: Combatant = null
	var endangered_tick := -100
	## Position (metres) now and at the start of the tick (the viewer interpolates between them).
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	## KOTH: playing the point, and the spot on the hill he heads for.
	var goes_point := false
	var hill_spot := Vector2.ZERO
	var pinned_tick := -100
	## Enemies in sight (refreshed every VISION_EVERY ticks) and the last tick he saw one.
	var visible: Array = []
	var last_contact_tick := 0
	var hunting := false
	var cover_spot := Vector2.ZERO
	var cover_until := -1
	var waypoint := Vector2.ZERO
	var waypoint_goal := Vector2.INF
	var repath_tick := 0
	## Match ratings (morale and pre-match fatigue applied) and role behaviour, fixed for the match.
	var _stats: Dictionary = {}
	var _behaviour: Dictionary = {}
	var _flanked_behaviour: Dictionary = {}

	func setup() -> void:
		for s in Stats.ALL:
			var v := float(soldier.eff_stat(s))
			if condition < 1.0 and FATIGUE_STATS.has(s):
				v *= condition
			_stats[s] = clampf(v + form, 1.0, 110.0)
		var b: Dictionary = Scheme.ROLE_BEHAVIOUR[role]
		for key in b:
			_behaviour[key] = b[key]
			_flanked_behaviour[key] = b.get("flanked_" + String(key), b[key])

	func stat(s: StringName) -> float:
		return _stats[s]

	func flanked() -> bool:
		return role == Scheme.Role.FLEX and flank_progress >= 1.0

	func on_point() -> bool:
		return alive and ArenaMap.on_hill(pos)

	func behaviour(key: String) -> float:
		return _flanked_behaviour[key] if flanked() else _behaviour[key]


## Emit visual events (shots, kills, respawns, game/round boundaries) for the match viewer.
var record := false
## Visual events since the viewer last drained them. Each has "t" (type) plus details.
var visual_events: Array[Dictionary] = []
## [team 0 combatants, team 1 combatants]
var squads: Array = []
var finished := false
## Match-day form per squad, in rating points (see TEAM_FORM_SD).
var team_form: Array[float] = [0.0, 0.0]

var _rng := RandomNumberGenerator.new()
var _result: MatchResult
var _mode: StringName = MODE_TDM
var _game_number := 0
var _round_number := 0
var _tick := 0
var _everyone: Array = []
## Arena scoreboard for the current game: TDM points or KOTH hold seconds.
var _arena_score: Array[float] = [0.0, 0.0]
var _game_over := false
var _game: Dictionary = {}
var _need_game := true
var _need_round := false
var _holder := -1
var _clutch_candidate: Combatant = null


static func simulate(team_a: Team, team_b: Team, seed_value: int) -> MatchResult:
	var engine := MatchEngine.new()
	engine.start(team_a, team_b, seed_value)
	while engine.step():
		pass
	return engine.result()


static func mode_name(mode: StringName) -> String:
	return MODE_NAMES.get(mode, String(mode))


func result() -> MatchResult:
	return _result


func mode() -> StringName:
	return _mode


func game_number() -> int:
	return _game_number


func round_number() -> int:
	return _round_number


## Seconds into the current game (sudden death: into the current round).
func clock_s() -> float:
	return _tick * TICK_SECONDS


## Current game's scoreboard: TDM points, KOTH hold seconds or sudden-death rounds.
func game_score() -> Array:
	if _mode == MODE_SUDDEN_DEATH:
		return _game.get("score", [0, 0]).duplicate()
	return [_arena_score[0], _arena_score[1]]


## KOTH: 0/1 = that team alone on the hill, 2 = contested, -1 = empty.
func hill_state() -> int:
	if _mode != MODE_KOTH or squads.is_empty():
		return -1
	var a := _on_point_count(squads[0]) > 0
	var b := _on_point_count(squads[1]) > 0
	if a and b:
		return 2
	if a:
		return 0
	if b:
		return 1
	return -1


func start(team_a: Team, team_b: Team, seed_value: int) -> void:
	ArenaMap.ensure_built()
	_rng.seed = seed_value
	_result = MatchResult.new()
	_result.match_seed = seed_value
	_result.teams = [team_a, team_b]
	team_form = [_roll_form(TEAM_FORM_SD), _roll_form(TEAM_FORM_SD)]
	squads = [_build_squad(team_a, 0), _build_squad(team_b, 1)]
	_everyone = squads[0] + squads[1]
	_result.events.append("=== %s vs %s (seed %d) ===" % [team_a.name, team_b.name, seed_value])
	_result.events.append("%s OVR %d | %s OVR %d" % [team_a.abbrev, team_a.team_ovr(), team_b.abbrev, team_b.team_ovr()])
	for i in 2:
		if team_form[i] >= FORM_NOTE:
			_result.events.append("%s look razor sharp in warmups." % _result.teams[i].abbrev)
		elif team_form[i] <= -FORM_NOTE:
			_result.events.append("%s look flat in warmups." % _result.teams[i].abbrev)


func _roll_form(sd: float) -> float:
	return clampf(_rng.randfn(0.0, sd), -sd * FORM_LIMIT, sd * FORM_LIMIT)


## Advances one tick (starting the next game or round first if one just ended).
## Returns false once the match is over.
func step() -> bool:
	if finished:
		return false
	if _need_game:
		_need_game = false
		_begin_game()
	elif _need_round:
		_need_round = false
		_begin_round()
	_tick += 1
	for c: Combatant in _everyone:
		c.prev_pos = c.pos
	if _mode == MODE_SUDDEN_DEATH:
		_tick_sudden_death()
	else:
		_tick_arena()
	return not finished


func _emit(e: Dictionary) -> void:
	if record:
		visual_events.append(e)


func _build_squad(team: Team, index: int) -> Array:
	var squad: Array = []
	for slot_id in team.scheme.slot_ids():
		var s: Soldier = team.lineup.get(slot_id)
		if s == null:
			push_error("%s has no soldier in slot %s" % [team.name, slot_id])
			continue
		var c := Combatant.new()
		c.soldier = s
		c.team = index
		c.slot_id = slot_id
		c.role = team.scheme.role_for_slot(slot_id)
		c.condition = 1.0 - Conditioning.penalty(s.fatigue)
		c.form = team_form[index] + _roll_form(PLAYER_FORM_SD)
		c.setup()
		c.pos = ArenaMap.spawn_point(index, slot_id)
		c.prev_pos = c.pos
		squad.append(c)
		_result.box[s.id] = {
			"team": index, "slot": slot_id, "kills": 0, "deaths": 0, "assists": 0, "shots": 0,
			"hits": 0, "headshots": 0, "damage": 0.0, "rounds_played": 0, "rounds_survived": 0,
			"clutches": 0, "saves": 0, "games": 0, "wipes": 0, "hill_s": 0.0, "caps": 0, "contest_s": 0.0,
		}
	return squad


# --- games and rounds ------------------------------------------------------------

func _begin_game() -> void:
	_mode = GAME_ORDER[_game_number]
	_game_number += 1
	for c: Combatant in _everyone:
		c.fatigue *= GAME_RECOVERY
		_result.box[c.soldier.id]["games"] += 1
	_game = {"number": _game_number, "mode": _mode, "score": [0, 0], "winner": -1, "duration_s": 0.0, "rounds": []}
	var goal := ""
	match _mode:
		MODE_TDM:
			goal = "first to %d" % TDM_POINTS_TO_WIN
		MODE_KOTH:
			goal = "first to %d:%02d of hold time" % [int(KOTH_HOLD_TO_WIN_S) / 60, int(KOTH_HOLD_TO_WIN_S) % 60]
		_:
			goal = "first to %d rounds" % ROUNDS_TO_WIN
	_result.events.append("=== GAME %d: %s (%s) ===" % [_game_number, mode_name(_mode), goal])
	_tick = 0
	_round_number = 0
	_arena_score = [0.0, 0.0]
	_game_over = false
	_holder = -1
	_emit({"t": "game_start", "game": _game_number, "mode": _mode})
	if _mode == MODE_SUDDEN_DEATH:
		_begin_round()
	else:
		for squad in squads:
			_spawn(squad, true)


func _finish_game(winner: int) -> void:
	_game["winner"] = winner
	_result.score[winner] += 1
	_result.games.append(_game)
	_result.events.append("=== Game %d -> %s %s  (games %d-%d) ===" % [_game_number, _result.teams[winner].abbrev,
		MatchResult.game_score_text(_game), _result.score[0], _result.score[1]])
	_emit({"t": "game_end", "game": _game})
	if _result.score[0] >= GAMES_TO_WIN or _result.score[1] >= GAMES_TO_WIN:
		_finish_match()
	else:
		_need_game = true


func _finish_match() -> void:
	_result.winner_index = 0 if _result.score[0] > _result.score[1] else 1
	_pick_mvp()
	_result.events.append("=== FINAL: %s — %s wins ===" % [_result.score_line(), _result.winner().name])
	finished = true
	_emit({"t": "match_end"})
	# Break Combatant <-> Combatant reference cycles so they can be freed.
	for c: Combatant in _everyone:
		c.target = null
		c.endangered_by = null
		c.visible.clear()


func _begin_round() -> void:
	_round_number += 1
	_tick = 0
	_clutch_candidate = null
	for c: Combatant in _everyone:
		_reset_life(c)
		c.fatigue *= 0.6  # partial recovery between rounds
		_result.box[c.soldier.id]["rounds_played"] += 1
	_result.events.append("--- Round %d ---" % _round_number)
	_emit({"t": "round_start", "round": _round_number})


func _reset_life(c: Combatant) -> void:
	c.hp = 100.0
	c.alive = true
	c.mag = MAG_SIZE
	c.reload_ticks = 0
	c.flank_progress = 0.0
	c.target = null
	c.endangered_by = null
	c.damage_to.clear()
	c.pos = ArenaMap.spawn_point(c.team, c.slot_id)
	c.prev_pos = c.pos
	c.pinned_tick = -100
	c.visible.clear()
	c.last_contact_tick = _tick
	c.hunting = false
	c.cover_until = -1
	c.waypoint_goal = Vector2.INF
	c.repath_tick = 0


# --- sudden death ------------------------------------------------------------------

func _tick_sudden_death() -> void:
	_update_vision()
	var order := _everyone.duplicate()
	_shuffle(order)
	for c: Combatant in order:
		if not c.alive:
			continue
		_advance_state(c)
		var enemies: Array = squads[1 - c.team]
		if _alive_count(enemies) == 0:
			break
		_move(c, enemies)
		if c.reload_ticks > 0:
			continue
		_act(c, squads[c.team], enemies)

	# Clutch: one soldier left alone against 2+ enemies.
	for i in 2:
		if _clutch_candidate == null and _alive_count(squads[i]) == 1 and _alive_count(squads[1 - i]) >= 2:
			_clutch_candidate = _first_alive(squads[i])

	if _tick >= int(ROUND_TIME_LIMIT_S / TICK_SECONDS) or _alive_count(squads[0]) == 0 or _alive_count(squads[1]) == 0:
		_end_round()


func _end_round() -> void:
	var score: Array = _game["score"]
	var winner := _round_winner()
	score[winner] += 1
	var survivors := [_alive_count(squads[0]), _alive_count(squads[1])]
	var round_info := {
		"number": _round_number, "mode": MODE_SUDDEN_DEATH, "winner": winner,
		"duration_s": _tick * TICK_SECONDS, "survivors": survivors, "clutch_soldier_id": -1,
	}
	for c: Combatant in _everyone:
		if c.alive:
			_result.box[c.soldier.id]["rounds_survived"] += 1
			c.soldier.add_usage(Stats.ENDURANCE, 0.5)
	if _clutch_candidate and _clutch_candidate.team == winner:
		_result.box[_clutch_candidate.soldier.id]["clutches"] += 1
		_clutch_candidate.soldier.add_usage(Stats.COMPOSURE, 4.0)
		round_info["clutch_soldier_id"] = _clutch_candidate.soldier.id
		_result.events.append("%s CLUTCH! %s wins it alone." % [_stamp(), _name(_clutch_candidate)])
	_result.rounds.append(round_info)
	_game["rounds"].append(round_info)
	_game["duration_s"] += round_info["duration_s"]
	_result.events.append("Round %d -> %s (%s)  [%d-%d]" % [
		_round_number, _result.teams[winner].abbrev, _fmt_time(_tick), score[0], score[1]])
	_emit({"t": "round_end", "round": round_info, "score": score.duplicate()})
	if score[0] >= ROUNDS_TO_WIN or score[1] >= ROUNDS_TO_WIN or _round_number >= MAX_ROUNDS:
		_finish_game(0 if score[0] > score[1] else 1)
	else:
		_need_round = true


# --- arena games (TDM / KOTH) -----------------------------------------------------------

func _tick_arena() -> void:
	if _mode == MODE_KOTH:
		_point_decisions()
	_update_vision()
	var order := _everyone.duplicate()
	_shuffle(order)
	for c: Combatant in order:
		if not c.alive:
			continue
		_advance_state(c)
		var enemies: Array = squads[1 - c.team]
		_move(c, enemies)
		if c.reload_ticks > 0 or _alive_count(enemies) == 0:
			continue
		_act(c, squads[c.team], enemies)
		if _game_over:
			break
	if not _game_over:
		# A wiped team respawns in formation; the survivors play on where they are.
		for i in 2:
			if _alive_count(squads[i]) == 0:
				_spawn(squads[i], false)
				_result.events.append("%s %s respawn in formation." % [_stamp(), _result.teams[i].abbrev])
				_emit({"t": "respawn", "team": i})
		if _mode == MODE_KOTH:
			_score_hill()
	if _game_over or _tick >= int(ARENA_SAFETY_LIMIT_S / TICK_SECONDS):
		var winner := 0
		if _arena_score[0] != _arena_score[1]:
			winner = 0 if _arena_score[0] > _arena_score[1] else 1
		else:
			winner = _rng.randi_range(0, 1)
		_game["score"] = [int(_arena_score[0]), int(_arena_score[1])]
		_game["duration_s"] = _tick * TICK_SECONDS
		_finish_game(winner)


func _spawn(squad: Array, first: bool) -> void:
	for c: Combatant in squad:
		_reset_life(c)
		if not first:
			c.fatigue *= RESPAWN_RECOVERY
		c.goes_point = false
		if _mode == MODE_KOTH:
			var chance := float(POINT_ROLE_BASE[c.role]) + (c.stat(Stats.OBJ_IQ) - 60.0) / 100.0
			_set_goes_point(c, _rng.randf() < clampf(chance, 0.05, 0.95))


func _set_goes_point(c: Combatant, value: bool) -> void:
	c.goes_point = value
	if value:
		var inner := ArenaMap.HILL.grow(-1.5)
		c.hill_spot = Vector2(_rng.randf_range(inner.position.x, inner.end.x), _rng.randf_range(inner.position.y, inner.end.y))


## KOTH: who plays the point. A squad with nobody heading to the point rotates someone onto it
## (faster with Objective IQ); smart players also crash a point the enemy holds alone, and
## low-IQ players sometimes wander off the point to chase kills.
func _point_decisions() -> void:
	for i in 2:
		var squad: Array = squads[i]
		var goers := 0
		for c: Combatant in squad:
			if c.alive and c.goes_point:
				goers += 1
		var enemy_alone := _on_point_count(squads[1 - i]) > 0 and _on_point_count(squad) == 0
		for c: Combatant in squad:
			if not c.alive:
				continue
			var iq := c.stat(Stats.OBJ_IQ) / 100.0
			if c.goes_point:
				if goers > 1 and _rng.randf() < (1.0 - iq) * 0.01:
					_set_goes_point(c, false)
					goers -= 1
				continue
			var chance := 0.0
			if goers == 0:
				chance = 0.04 + iq * 0.3
			elif enemy_alone:
				chance = iq * 0.05
			if chance > 0.0 and _rng.randf() < chance:
				_set_goes_point(c, true)
				c.soldier.add_usage(Stats.OBJ_IQ, 0.5)
				if goers == 0:
					_result.events.append("%s %s rotates to the point." % [_stamp(), _name(c)])
				goers += 1


## Banks hold time for a team alone on the point.
func _score_hill() -> void:
	var on: Array = [_on_point_list(squads[0]), _on_point_list(squads[1])]
	if not on[0].is_empty() and not on[1].is_empty():
		for side in on:
			for c: Combatant in side:
				_result.box[c.soldier.id]["contest_s"] += TICK_SECONDS
				c.soldier.add_usage(Stats.ANCHOR, 0.1)
		return
	for i in 2:
		if on[i].is_empty():
			continue
		var before := _arena_score[i]
		_arena_score[i] += TICK_SECONDS
		for c: Combatant in on[i]:
			_result.box[c.soldier.id]["hill_s"] += TICK_SECONDS
			c.soldier.add_usage(Stats.ANCHOR, 0.05)
		if _holder != i:
			_holder = i
			for c: Combatant in on[i]:
				_result.box[c.soldier.id]["caps"] += 1
				c.soldier.add_usage(Stats.OBJ_IQ, 1.0)
			_result.events.append("%s %s take the hill.  [%s - %s]" % [_stamp(), _result.teams[i].abbrev,
				_fmt_secs(_arena_score[0]), _fmt_secs(_arena_score[1])])
			_emit({"t": "hill", "team": i})
		if _arena_score[i] >= KOTH_HOLD_TO_WIN_S:
			_game_over = true
		elif int(before / 30.0) != int(_arena_score[i] / 30.0):
			_result.events.append("%s %s have held for %s.  [%s - %s]" % [_stamp(), _result.teams[i].abbrev,
				_fmt_secs(_arena_score[i]), _fmt_secs(_arena_score[0]), _fmt_secs(_arena_score[1])])


# --- movement ----------------------------------------------------------------------

func _update_vision() -> void:
	if _tick % VISION_EVERY != 1 and VISION_EVERY > 1:
		# Between refreshes just drop the dead.
		for c: Combatant in _everyone:
			if not c.visible.is_empty():
				c.visible = c.visible.filter(func(e: Combatant): return e.alive)
		return
	for c: Combatant in _everyone:
		c.visible.clear()
	var max_d2 := MAX_ENGAGE_DISTANCE * MAX_ENGAGE_DISTANCE
	for a: Combatant in squads[0]:
		if not a.alive:
			continue
		for b: Combatant in squads[1]:
			if b.alive and a.pos.distance_squared_to(b.pos) <= max_d2 and ArenaMap.line_of_sight(a.pos, b.pos):
				a.visible.append(b)
				b.visible.append(a)
	for c: Combatant in _everyone:
		if not c.visible.is_empty():
			c.last_contact_tick = _tick


## Where the soldier wants to be this tick (world coordinates).
func _goal(c: Combatant, enemies: Array) -> Vector2:
	if _mode == MODE_KOTH and c.goes_point:
		return c.hill_spot
	if c.cover_until >= _tick:
		return c.cover_spot
	var hold: Vector2
	if c.role == Scheme.Role.FLEX:
		hold = ArenaMap.world(c.team, ArenaMap.flank_point(c.flank_progress, c.slot_id == &"RFX"))
	else:
		var table: Dictionary = ArenaMap.OVERWATCH if _mode == MODE_KOTH else ArenaMap.HOLD
		hold = ArenaMap.world(c.team, table.get(c.slot_id, table[&"CTR"]))
	if not c.visible.is_empty():
		if not c.hunting:
			return hold
		# In a fight while hunting: plant, except frontmen who close to short range.
		if c.role == Scheme.Role.FRONTMAN and c.target and c.target.alive \
				and c.pos.distance_to(c.target.pos) > FRONT_PUSH_RANGE:
			return c.target.pos
		return c.pos
	if not c.hunting:
		var quiet := _tick - c.last_contact_tick
		var settled := c.pos.distance_squared_to(hold) < 9.0
		# Awareness: reads the lull and knows when his role should push.
		var read := HUNT_AFTER_TICKS * (1.3 - c.stat(Stats.AWARENESS) / 100.0 * 0.6)
		if quiet > read and (settled or quiet > read * 4):
			c.hunting = true
	if c.hunting:
		var nearest: Combatant = null
		var best := INF
		for e: Combatant in enemies:
			if e.alive:
				var d := c.pos.distance_squared_to(e.pos)
				if d < best:
					best = d
					nearest = e
		if nearest:
			return nearest.pos
	return hold


func _move(c: Combatant, enemies: Array) -> void:
	var goal := _goal(c, enemies)
	if c.pos.distance_squared_to(goal) < 0.04:
		return
	var rate := (0.45 + c.stat(Stats.SPEED) / 100.0 * 0.9) * (1.0 - c.fatigue * 0.3)
	if _tick - c.pinned_tick <= 4:
		rate *= CONTACT_ADVANCE_MULT
	if _mode == MODE_KOTH and c.goes_point and _on_point_count(enemies) > 0:
		var to_hill := c.pos.distance_to(c.pos.clamp(ArenaMap.HILL.position, ArenaMap.HILL.end))
		if to_hill <= BREACH_ZONE:
			# Pushing onto a held point.
			rate *= 0.25 + c.stat(Stats.BREACH) / 100.0 * 0.9
			c.soldier.add_usage(Stats.BREACH, 0.2)
	if goal.distance_squared_to(c.waypoint_goal) > 4.0 or _tick >= c.repath_tick \
			or c.pos.distance_squared_to(c.waypoint) < 0.25:
		c.waypoint = ArenaMap.next_waypoint(c.pos, goal)
		c.waypoint_goal = goal
		c.repath_tick = _tick + REPATH_TICKS
	var to := c.waypoint - c.pos
	var d := to.length()
	if d < 0.001:
		return
	var dir := to / d
	var stride := minf(rate, d)
	var np := c.pos + dir * stride
	if ArenaMap.blocked(np):
		# Slide along whatever is in the way, then re-plan next tick.
		np = c.pos + Vector2(dir.x * stride, 0.0)
		if ArenaMap.blocked(np):
			np = c.pos + Vector2(0.0, dir.y * stride)
			if ArenaMap.blocked(np):
				np = c.pos
		c.repath_tick = _tick
	c.pos = np


## Shot at: an aware soldier not playing the point ducks behind the nearest cover.
func _seek_cover(c: Combatant, shooter: Combatant) -> void:
	if not c.alive or c.cover_until >= _tick or (_mode == MODE_KOTH and c.goes_point):
		return
	if _rng.randf() > c.stat(Stats.AWARENESS) / 100.0 * 0.35:
		return
	var spot := ArenaMap.find_cover(c.pos, shooter.pos, COVER_SEARCH_RADIUS)
	if spot != Vector2.INF:
		c.cover_spot = spot
		c.cover_until = _tick + COVER_TICKS


# --- shooting ----------------------------------------------------------------------

func _advance_state(c: Combatant) -> void:
	c.fatigue = minf(1.0, c.fatigue + 0.006 * maxf(0.0, 1.0 - c.stat(Stats.ENDURANCE) / 110.0))
	if c.role == Scheme.Role.FLEX and c.flank_progress < 1.0:
		# Speed covers ground; awareness picks the right flank route.
		c.flank_progress += 0.016 + c.stat(Stats.SPEED) * 0.0004 + c.stat(Stats.AWARENESS) * 0.0001
		if c.flank_progress >= 1.0:
			c.soldier.add_usage(Stats.SPEED, 1.0)
			if _mode == MODE_SUDDEN_DEATH:
				_result.events.append("%s %s lands the flank." % [_stamp(), _name(c)])
	if c.reload_ticks > 0:
		c.reload_ticks -= 1
		if c.reload_ticks == 0:
			c.mag = MAG_SIZE


func _act(c: Combatant, allies: Array, enemies: Array) -> void:
	var target := _pick_target(c, allies)
	c.target = target
	if target == null:
		return
	var dist := c.pos.distance_to(target.pos)
	var band := _band(dist)

	# Getting a shot off: shooter awareness vs target agility (harder to pin down).
	var engage := BASE_ENGAGE * (1.0 + c.behaviour("engage_mod")) \
		* (1.0 + (c.stat(Stats.AWARENESS) - 60.0) * 0.006 - (target.stat(Stats.AGILITY) - 60.0) * 0.004)
	if band == &"long":
		engage *= LONG_RANGE_ENGAGE_MULT
	c.soldier.add_usage(Stats.AWARENESS, 0.1)
	if _rng.randf() > clampf(engage, 0.01, 0.90):
		return

	_fire(c, allies, enemies, target, band, dist)
	if c.mag <= 0:
		# 4.0s at 0 reload, ~1.0s at 99, in ticks.
		c.reload_ticks = maxi(1, ceili((4.0 - c.stat(Stats.RELOAD) * 0.03) / TICK_SECONDS))
		c.soldier.add_usage(Stats.RELOAD, 1.0)
		_emit({"t": "reload", "id": c.soldier.id})


## Picks among the enemies in sight; null if none.
func _pick_target(c: Combatant, allies: Array) -> Combatant:
	if c.visible.is_empty():
		return null
	var focus := c.stat(Stats.TEAMWORK) / 100.0
	var awareness := c.stat(Stats.AWARENESS) / 100.0
	var candidates: Array = []
	var weights: Array[float] = []
	for e: Combatant in c.visible:
		if not e.alive:
			continue
		var w := e.behaviour("exposure")
		# Aware soldiers finish off wounded enemies.
		w *= 1.0 + (1.0 - e.hp / 100.0) * awareness
		# Good teammates focus fire with allies.
		for a: Combatant in allies:
			if a != c and a.alive and a.target == e:
				w *= 1.0 + focus * 0.5
		# Whoever stands on the hill draws fire.
		if _mode == MODE_KOTH and e.on_point():
			w *= 1.5
		candidates.append(e)
		weights.append(w)
	if candidates.is_empty():
		return null
	return candidates[_weighted_index(weights)]


func _fire(c: Combatant, allies: Array, enemies: Array, target: Combatant, band: StringName, dist: float) -> void:
	var shots := mini(BURST, c.mag)
	c.mag -= shots
	target.pinned_tick = _tick
	var acc_stat: StringName = RANGE_STAT[band]
	var box: Dictionary = _result.box[c.soldier.id]
	box["shots"] += shots
	c.soldier.add_usage(acc_stat, shots * 0.5)

	var p: float = RANGE_BASE_HIT[band] * (0.35 + c.stat(acc_stat) / 100.0 * 0.75)
	if Scheme.ROLE_BEHAVIOUR[c.role]["preferred_range"] == band:
		p *= 1.12
	if c.flanked():
		p *= 1.2
	p *= 1.0 - c.fatigue * 0.4
	# Sway: aim steadiness when firing on the move, tired or at long range (neutral at 60).
	var unsteady := c.fatigue * 0.3
	if c.pos.distance_squared_to(c.prev_pos) > 0.01:
		unsteady += 0.25
	if band == &"long":
		unsteady += 0.2
	if unsteady > 0.0:
		p *= 1.0 + unsteady * (c.stat(Stats.SWAY) - 60.0) / 100.0
		c.soldier.add_usage(Stats.SWAY, unsteady)
	var outnumbered := _alive_count(allies) < _alive_count(enemies)
	var composure_scale := 200.0 if outnumbered else 600.0
	p *= 1.0 + (c.stat(Stats.COMPOSURE) - 60.0) / composure_scale
	if outnumbered:
		c.soldier.add_usage(Stats.COMPOSURE, 0.3)
	p *= 1.0 + (_avg_stat(allies, Stats.TEAMWORK) - 60.0) / 500.0
	p *= 1.0 - target.stat(Stats.AGILITY) / 100.0 * 0.15 * (1.0 - target.fatigue * 0.5)
	# Fast movers are harder to track.
	p *= 1.0 - (target.stat(Stats.SPEED) - 60.0) * 0.0015
	# Caught mid-reload: target can't return fire or dodge as well.
	if target.reload_ticks > 0:
		p *= 1.25
	var covered := ArenaMap.through_cover(c.pos, target.pos)
	if covered:
		p *= COVER_HIT_MULT
	if _mode == MODE_KOTH:
		if c.on_point():
			# Holding the hill: set angles and cover.
			p *= 1.0 + (c.stat(Stats.ANCHOR) - 60.0) / 120.0
			c.soldier.add_usage(Stats.ANCHOR, 0.2)
		elif c.goes_point and target.on_point():
			# Clearing the hill on the push.
			p *= 1.0 + (c.stat(Stats.BREACH) - 60.0) / 120.0
			c.soldier.add_usage(Stats.BREACH, 0.2)
	p = clampf(p, 0.02, 0.95)

	# Follow-up bullets: grouping consistency plus strength for recoil control.
	var follow_mult := 0.55 + c.stat(Stats.GROUPING) / 200.0 + c.stat(Stats.STRENGTH) / 400.0
	var p_follow := clampf(p * follow_mult, 0.02, 0.95)
	if shots > 1:
		c.soldier.add_usage(Stats.GROUPING, (shots - 1) * 0.3)
		c.soldier.add_usage(Stats.STRENGTH, 0.1)

	var hits := 0
	var any_headshot := false
	var killed := false
	var target_pos := target.pos
	for i in shots:
		if not target.alive:
			break
		var hit_p := p if i == 0 else p_follow
		if _rng.randf() > hit_p:
			target.soldier.add_usage(Stats.AGILITY, 0.15)
			continue
		hits += 1
		box["hits"] += 1
		var dmg := _rng.randf_range(22.0, 30.0)
		var headshot := _rng.randf() < 0.06 + c.stat(Stats.GROUPING) * 0.0008
		if headshot:
			dmg *= 2.2
			box["headshots"] += 1
			any_headshot = true
		# Strength: absorbs hits.
		dmg *= 1.0 - target.stat(Stats.STRENGTH) / 100.0 * 0.25
		if _mode == MODE_KOTH and target.on_point():
			dmg *= 1.0 - target.stat(Stats.ANCHOR) / 100.0 * 0.35
		dmg = minf(dmg, target.hp)
		target.hp -= dmg
		box["damage"] += dmg
		c.damage_to[target.soldier.id] = c.damage_to.get(target.soldier.id, 0.0) + dmg
		target.soldier.add_usage(Stats.STRENGTH, dmg / 50.0)
		if target.hp <= 0.0:
			killed = true
			_kill(c, target, allies, enemies, band, dist, headshot)
		elif target.hp < SAVE_HP:
			target.endangered_by = c
			target.endangered_tick = _tick
	if record:
		var res := "MISS"
		if killed:
			res = "KILL"
		elif any_headshot:
			res = "HEADSHOT"
		elif hits > 0:
			res = "HIT" if hits == 1 else "HIT x%d" % hits
		_emit({"t": "shot", "id": c.soldier.id, "team": c.team, "from": c.pos, "to": target_pos,
			"target": target.soldier.id, "result": res, "shots": shots, "hits": hits, "cover": covered})
	if not killed:
		_seek_cover(target, c)


func _kill(killer: Combatant, victim: Combatant, killer_allies: Array, victim_allies: Array,
		band: StringName, dist: float, headshot: bool) -> void:
	victim.alive = false
	victim.hp = 0.0
	_result.box[killer.soldier.id]["kills"] += 1
	_result.box[victim.soldier.id]["deaths"] += 1
	var saved: Array[String] = []
	for a: Combatant in killer_allies:
		if a != killer and a.alive and a.endangered_by == victim and _tick - a.endangered_tick <= SAVE_WINDOW_TICKS:
			a.endangered_by = null
			saved.append(a.soldier.tag())
	if not saved.is_empty():
		_result.box[killer.soldier.id]["saves"] += saved.size()
	var assisters: Array[String] = []
	for a: Combatant in killer_allies:
		if a != killer and a.damage_to.get(victim.soldier.id, 0.0) >= 20.0:
			_result.box[a.soldier.id]["assists"] += 1
			a.soldier.add_usage(Stats.TEAMWORK, 1.0)
			assisters.append(a.soldier.tag())
	var line := "%s %s %s %s at %dm (%s)" % [
		_stamp(), _name(killer), "HEADSHOT" if headshot else "killed", _name(victim), roundi(dist), band]
	if not assisters.is_empty():
		line += " — assist: " + ", ".join(assisters)
	if not saved.is_empty():
		line += " — SAVE: " + ", ".join(saved)
	var wipe := false
	if _mode != MODE_SUDDEN_DEATH:
		if _mode == MODE_TDM:
			_arena_score[killer.team] += 1.0
		if _alive_count(victim_allies) == 0:
			wipe = true
			_result.box[killer.soldier.id]["wipes"] += 1
			line += " — TEAM WIPE"
			if _mode == MODE_TDM:
				_arena_score[killer.team] += TDM_WIPE_BONUS
				line += " (+%d)" % TDM_WIPE_BONUS
		if _mode == MODE_TDM:
			line += "  [%d-%d]" % [int(_arena_score[0]), int(_arena_score[1])]
			if _arena_score[killer.team] >= TDM_POINTS_TO_WIN:
				_game_over = true
	_result.events.append(line)
	_emit({"t": "kill", "killer": killer.soldier.id, "victim": victim.soldier.id, "team": killer.team,
		"headshot": headshot, "dist": dist, "assists": assisters, "saved": saved, "wipe": wipe})


func _round_winner() -> int:
	var a := _alive_count(squads[0])
	var b := _alive_count(squads[1])
	if a != b:
		return 0 if a > b else 1
	# Time expired with equal numbers: total remaining health, then a coin flip.
	var hp_a := _total_hp(squads[0])
	var hp_b := _total_hp(squads[1])
	if not is_equal_approx(hp_a, hp_b):
		return 0 if hp_a > hp_b else 1
	return _rng.randi_range(0, 1)


func _pick_mvp() -> void:
	var best := -INF
	for id in _result.box:
		var line: Dictionary = _result.box[id]
		# MVP comes from the winning side.
		if line["team"] != _result.winner_index:
			continue
		var score := MatchResult.impact(line)
		if score > best:
			best = score
			_result.mvp_id = id


# --- helpers ---------------------------------------------------------------

func _band(dist: float) -> StringName:
	if dist < SHORT_RANGE_MAX:
		return &"short"
	if dist < MEDIUM_RANGE_MAX:
		return &"medium"
	return &"long"


func _alive_count(squad: Array) -> int:
	var n := 0
	for c: Combatant in squad:
		if c.alive:
			n += 1
	return n


func _on_point_count(squad: Array) -> int:
	var n := 0
	for c: Combatant in squad:
		if c.on_point():
			n += 1
	return n


func _on_point_list(squad: Array) -> Array:
	var out: Array = []
	for c: Combatant in squad:
		if c.on_point():
			out.append(c)
	return out


func _first_alive(squad: Array) -> Combatant:
	for c: Combatant in squad:
		if c.alive:
			return c
	return null


func _total_hp(squad: Array) -> float:
	var t := 0.0
	for c: Combatant in squad:
		if c.alive:
			t += c.hp
	return t


func _avg_stat(squad: Array, stat: StringName) -> float:
	var t := 0.0
	var n := 0
	for c: Combatant in squad:
		if c.alive:
			t += c.stat(stat)
			n += 1
	return t / n if n > 0 else 0.0


func _weighted_index(weights: Array[float]) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var roll := _rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return weights.size() - 1


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _name(c: Combatant) -> String:
	return "[%s] %s (%s)" % [_result.teams[c.team].abbrev, c.soldier.tag(), c.slot_id]


func _stamp() -> String:
	if _mode == MODE_SUDDEN_DEATH:
		return "G%d R%d %s" % [_game_number, _round_number, _fmt_time(_tick)]
	return "G%d %s" % [_game_number, _fmt_time(_tick)]


func _fmt_time(tick: int) -> String:
	return _fmt_secs(tick * TICK_SECONDS)


static func _fmt_secs(seconds: float) -> String:
	var secs := int(seconds)
	return "%d:%02d" % [secs / 60, secs % 60]

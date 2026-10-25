class_name MatchEngine
extends RefCounted
## Abstract tick-based 5v5 match simulator. Deterministic for a given seed.
##
## A match is best of 3 games, always in this order (a 2-0 skips the third):
## 1. Team Deathmatch (TDM): 1 point per kill, +TDM_WIPE_BONUS for wiping the other team; first to
##    TDM_POINTS_TO_WIN. Eliminated soldiers stay down until their whole team is wiped, then that
##    team respawns in formation at its end of the map.
## 2. King of the Hill (KOTH): a point in the middle of the map. A team banks hold time while it has
##    someone on the point and the other team doesn't (nobody scores while it's contested); first
##    to KOTH_HOLD_TO_WIN_S of total hold time. Same elimination/respawn rule as TDM, no wipe bonus.
## 3. TDM Sudden Death: elimination rounds with no respawns, first to ROUNDS_TO_WIN rounds.
##
## Arena model (TDM/KOTH): every soldier has a distance from the middle of the map (`pos`) and
## advances (Speed) to his role's holding spot; the distance between two soldiers is the sum of
## their positions plus scaled role offsets. In KOTH, Objective IQ decides who plays the point
## (and how fast the squad rotates someone back onto it), Breach pushes onto a held point and wins
## the fight there, and Anchor keeps the soldiers on the point alive and shooting straight.
##
## Sudden death model: the two squads start START_DISTANCE metres apart and close at a rate driven
## by Speed; each soldier's distance = team distance + both soldiers' role offsets. Frontmen push
## forward; the Center hangs back at medium range; Flexes swing wide and, once their flank lands
## (Speed), collapse in with an accuracy bonus (the flank works the same way in the arena).
##
## Shooting (all modes): each tick every alive soldier may get a shot off (Awareness vs target
## Agility), then fires a burst: first bullet uses range accuracy, follow-ups use Grouping +
## Strength (recoil). Endurance limits fatigue, which builds across the whole match. Reload sets
## reload time, Composure matters when outnumbered, Teamwork drives focus fire and a small
## squad-wide bonus, Toughness reduces damage taken. Weekly fatigue (Soldier.fatigue) scales down
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
const ROUND_TIME_LIMIT_S := 120.0
## Arena games end on the scoreboard; this only guards against a stalemate.
const ARENA_SAFETY_LIMIT_S := 1800.0
const START_DISTANCE := 65.0
const MIN_DISTANCE := 6.0
const MAX_ENGAGE_DISTANCE := 95.0
## Fatigue kept between games / by a respawning team.
const GAME_RECOVERY := 0.6
const RESPAWN_RECOVERY := 0.8
## A teammate hit below this HP is "almost eliminated": killing his attacker within
## SAVE_WINDOW_TICKS counts as a save.
const SAVE_HP := 30.0
const SAVE_WINDOW_TICKS := 6
const CONTACT_ADVANCE_MULT := 0.5
## Per-tick chance of getting a shot off, before role/awareness/agility modifiers.
const BASE_ENGAGE := 0.13
const LONG_RANGE_ENGAGE_MULT := 0.75
const MAG_SIZE := 25
const BURST := 3
const SHORT_RANGE_MAX := 15.0
const MEDIUM_RANGE_MAX := 40.0

## Arena: spawn distance from the middle, where each role settles, and how much of the
## sudden-death role offsets apply.
const SPAWN_POS := 32.5
const TDM_HOLD := {Scheme.Role.FRONTMAN: 3.0, Scheme.Role.CENTER: 16.0, Scheme.Role.FLEX: 9.0}
## KOTH: where soldiers who aren't playing the point settle (overwatch).
const KOTH_OVERWATCH := {Scheme.Role.FRONTMAN: 5.0, Scheme.Role.CENTER: 16.0, Scheme.Role.FLEX: 10.0}
const ARENA_OFFSET_SCALE := 0.4
const POINT_RADIUS := 1.0
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
	## Enemy who last dropped this soldier below SAVE_HP, and when (for teammate saves).
	var endangered_by: Combatant = null
	var endangered_tick := -100
	## Arena: distance from the middle of the map, whether he's playing the point (KOTH) and the
	## last tick he was shot at (pinned soldiers advance slower).
	var pos := SPAWN_POS
	var goes_point := false
	var pinned_tick := -100
	## Match ratings (morale and pre-match fatigue applied) and role behaviour, fixed for the match.
	var _stats: Dictionary = {}
	var _behaviour: Dictionary = {}
	var _flanked_behaviour: Dictionary = {}

	func setup() -> void:
		for s in Stats.ALL:
			var v := float(soldier.eff_stat(s))
			if condition < 1.0 and FATIGUE_STATS.has(s):
				v *= condition
			_stats[s] = v
		var b: Dictionary = Scheme.ROLE_BEHAVIOUR[role]
		for key in b:
			_behaviour[key] = b[key]
			_flanked_behaviour[key] = b.get("flanked_" + String(key), b[key])

	func stat(s: StringName) -> float:
		return _stats[s]

	func flanked() -> bool:
		return role == Scheme.Role.FLEX and flank_progress >= 1.0

	func on_point() -> bool:
		return alive and pos <= POINT_RADIUS

	func behaviour(key: String) -> float:
		return _flanked_behaviour[key] if flanked() else _behaviour[key]


var _rng := RandomNumberGenerator.new()
var _result: MatchResult
var _mode: StringName = MODE_SUDDEN_DEATH
var _game_number := 0
var _round_number := 0
var _tick := 0
var _contact := false
## Arena scoreboard for the current game: TDM points or KOTH hold seconds.
var _arena_score: Array[float] = [0.0, 0.0]
var _game_over := false


static func simulate(team_a: Team, team_b: Team, seed_value: int) -> MatchResult:
	var engine := MatchEngine.new()
	return engine._run(team_a, team_b, seed_value)


static func mode_name(mode: StringName) -> String:
	return MODE_NAMES.get(mode, String(mode))


func _run(team_a: Team, team_b: Team, seed_value: int) -> MatchResult:
	_rng.seed = seed_value
	_result = MatchResult.new()
	_result.match_seed = seed_value
	_result.teams = [team_a, team_b]

	var squads: Array = [_build_squad(team_a, 0), _build_squad(team_b, 1)]
	_result.events.append("=== %s vs %s (seed %d) ===" % [team_a.name, team_b.name, seed_value])
	_result.events.append("%s OVR %d | %s OVR %d" % [team_a.abbrev, team_a.team_ovr(), team_b.abbrev, team_b.team_ovr()])

	while _result.score[0] < GAMES_TO_WIN and _result.score[1] < GAMES_TO_WIN:
		_mode = GAME_ORDER[_game_number]
		_game_number += 1
		for squad in squads:
			for c: Combatant in squad:
				c.fatigue *= GAME_RECOVERY
				_result.box[c.soldier.id]["games"] += 1
		var game := {"number": _game_number, "mode": _mode, "score": [0, 0], "winner": -1, "duration_s": 0.0, "rounds": []}
		var goal := ""
		match _mode:
			MODE_TDM:
				goal = "first to %d" % TDM_POINTS_TO_WIN
			MODE_KOTH:
				goal = "first to %d:%02d of hold time" % [int(KOTH_HOLD_TO_WIN_S) / 60, int(KOTH_HOLD_TO_WIN_S) % 60]
			_:
				goal = "first to %d rounds" % ROUNDS_TO_WIN
		_result.events.append("=== GAME %d: %s (%s) ===" % [_game_number, mode_name(_mode), goal])
		if _mode == MODE_SUDDEN_DEATH:
			_play_sudden_death(squads, game)
		else:
			_play_arena(squads, game)
		_result.score[game["winner"]] += 1
		_result.games.append(game)
		_result.events.append("=== Game %d -> %s %s  (games %d-%d) ===" % [_game_number, _result.teams[game["winner"]].abbrev,
			MatchResult.game_score_text(game), _result.score[0], _result.score[1]])

	_result.winner_index = 0 if _result.score[0] > _result.score[1] else 1
	_pick_mvp()
	_result.events.append("=== FINAL: %s — %s wins ===" % [_result.score_line(), _result.winner().name])
	# Break Combatant <-> Combatant reference cycles so they can be freed.
	for squad in squads:
		for c: Combatant in squad:
			c.target = null
			c.endangered_by = null
	return _result


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
		c.setup()
		squad.append(c)
		_result.box[s.id] = {
			"team": index, "slot": slot_id, "kills": 0, "deaths": 0, "assists": 0, "shots": 0,
			"hits": 0, "headshots": 0, "damage": 0.0, "rounds_played": 0, "rounds_survived": 0,
			"clutches": 0, "saves": 0, "games": 0, "wipes": 0, "hill_s": 0.0, "caps": 0, "contest_s": 0.0,
		}
	return squad


# --- sudden death ------------------------------------------------------------------

func _play_sudden_death(squads: Array, game: Dictionary) -> void:
	_round_number = 0
	var score: Array = game["score"]
	while score[0] < ROUNDS_TO_WIN and score[1] < ROUNDS_TO_WIN and _round_number < MAX_ROUNDS:
		_round_number += 1
		var info := _play_round(squads, score)
		game["rounds"].append(info)
		game["duration_s"] += info["duration_s"]
	game["winner"] = 0 if score[0] > score[1] else 1


func _play_round(squads: Array, score: Array) -> Dictionary:
	_tick = 0
	_contact = false
	var distance := START_DISTANCE
	var everyone: Array = []
	for squad in squads:
		for c: Combatant in squad:
			_reset_life(c)
			c.fatigue *= 0.6  # partial recovery between rounds
			_result.box[c.soldier.id]["rounds_played"] += 1
			everyone.append(c)

	_result.events.append("--- Round %d ---" % _round_number)
	var clutch_candidate: Combatant = null
	var max_ticks := int(ROUND_TIME_LIMIT_S / TICK_SECONDS)

	while _tick < max_ticks and _alive_count(squads[0]) > 0 and _alive_count(squads[1]) > 0:
		_tick += 1
		# Once shots are flying, squads bound forward slowly instead of walking in.
		var advance := _closing_speed(squads[0]) + _closing_speed(squads[1])
		if _contact:
			advance *= CONTACT_ADVANCE_MULT
		distance = maxf(MIN_DISTANCE, distance - advance)

		var order := everyone.duplicate()
		_shuffle(order)
		for c: Combatant in order:
			if not c.alive:
				continue
			_advance_state(c)
			if c.reload_ticks > 0:
				continue
			var enemies: Array = squads[1 - c.team]
			if _alive_count(enemies) == 0:
				break
			_act(c, squads[c.team], enemies, distance)

		# Clutch: one soldier left alone against 2+ enemies.
		for i in 2:
			if clutch_candidate == null and _alive_count(squads[i]) == 1 and _alive_count(squads[1 - i]) >= 2:
				clutch_candidate = _first_alive(squads[i])

	var winner := _round_winner(squads)
	score[winner] += 1
	var survivors := [_alive_count(squads[0]), _alive_count(squads[1])]
	var round_info := {
		"number": _round_number, "mode": MODE_SUDDEN_DEATH, "winner": winner,
		"duration_s": _tick * TICK_SECONDS, "survivors": survivors, "clutch_soldier_id": -1,
	}
	for c: Combatant in everyone:
		if c.alive:
			_result.box[c.soldier.id]["rounds_survived"] += 1
			c.soldier.add_usage(Stats.ENDURANCE, 0.5)
	if clutch_candidate and clutch_candidate.team == winner:
		_result.box[clutch_candidate.soldier.id]["clutches"] += 1
		clutch_candidate.soldier.add_usage(Stats.COMPOSURE, 4.0)
		round_info["clutch_soldier_id"] = clutch_candidate.soldier.id
		_result.events.append("%s CLUTCH! %s wins it alone." % [_stamp(), _name(clutch_candidate)])
	_result.rounds.append(round_info)
	_result.events.append("Round %d -> %s (%s)  [%d-%d]" % [
		_round_number, _result.teams[winner].abbrev, _fmt_time(_tick), score[0], score[1]])
	return round_info


func _reset_life(c: Combatant) -> void:
	c.hp = 100.0
	c.alive = true
	c.mag = MAG_SIZE
	c.reload_ticks = 0
	c.flank_progress = 0.0
	c.target = null
	c.endangered_by = null
	c.damage_to.clear()
	c.pos = SPAWN_POS
	c.pinned_tick = -100


func _closing_speed(squad: Array) -> float:
	var total := 0.0
	var n := 0
	for c: Combatant in squad:
		if c.alive:
			total += c.stat(Stats.SPEED) * (1.0 - c.fatigue * 0.3)
			n += 1
	if n == 0:
		return 0.0
	return 0.3 + (total / n) / 100.0 * 0.6


# --- arena games (TDM / KOTH) -----------------------------------------------------------

func _play_arena(squads: Array, game: Dictionary) -> void:
	_tick = 0
	_round_number = 0
	_game_over = false
	_arena_score = [0.0, 0.0]
	var everyone: Array = []
	for squad in squads:
		_spawn(squad, true)
		everyone.append_array(squad)
	var holder := -1
	var max_ticks := int(ARENA_SAFETY_LIMIT_S / TICK_SECONDS)
	while _tick < max_ticks and not _game_over:
		_tick += 1
		if _mode == MODE_KOTH:
			_point_decisions(squads)
		var order := everyone.duplicate()
		_shuffle(order)
		for c: Combatant in order:
			if not c.alive:
				continue
			_advance_state(c)
			var enemies: Array = squads[1 - c.team]
			_move(c, enemies)
			if c.reload_ticks > 0 or _alive_count(enemies) == 0:
				continue
			_act(c, squads[c.team], enemies, 0.0)
			if _game_over:
				break
		if _game_over:
			break
		# A wiped team respawns in formation; the survivors play on where they are.
		for i in 2:
			if _alive_count(squads[i]) == 0:
				_spawn(squads[i], false)
				_result.events.append("%s %s respawn in formation." % [_stamp(), _result.teams[i].abbrev])
		if _mode == MODE_KOTH:
			holder = _score_hill(squads, holder)

	var winner := 0
	if _arena_score[0] != _arena_score[1]:
		winner = 0 if _arena_score[0] > _arena_score[1] else 1
	else:
		winner = _rng.randi_range(0, 1)
	game["winner"] = winner
	game["score"] = [int(_arena_score[0]), int(_arena_score[1])]
	game["duration_s"] = _tick * TICK_SECONDS


func _spawn(squad: Array, first: bool) -> void:
	for c: Combatant in squad:
		_reset_life(c)
		if not first:
			c.fatigue *= RESPAWN_RECOVERY
		c.goes_point = false
		if _mode == MODE_KOTH:
			var chance := float(POINT_ROLE_BASE[c.role]) + (c.stat(Stats.OBJ_IQ) - 60.0) / 100.0
			c.goes_point = _rng.randf() < clampf(chance, 0.05, 0.95)


## KOTH: who plays the point. A squad with nobody heading to the point rotates someone onto it
## (faster with Objective IQ); smart players also crash a point the enemy holds alone, and
## low-IQ players sometimes wander off the point to chase kills.
func _point_decisions(squads: Array) -> void:
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
					c.goes_point = false
					goers -= 1
				continue
			var chance := 0.0
			if goers == 0:
				chance = 0.04 + iq * 0.3
			elif enemy_alone:
				chance = iq * 0.05
			if chance > 0.0 and _rng.randf() < chance:
				c.goes_point = true
				c.soldier.add_usage(Stats.OBJ_IQ, 0.5)
				if goers == 0:
					_result.events.append("%s %s rotates to the point." % [_stamp(), _name(c)])
				goers += 1


func _hold_pos(c: Combatant) -> float:
	if _mode == MODE_KOTH:
		return 0.0 if c.goes_point else float(KOTH_OVERWATCH[c.role])
	return float(TDM_HOLD[c.role])


func _move(c: Combatant, enemies: Array) -> void:
	var dest := _hold_pos(c)
	if c.pos <= dest:
		return
	var rate := (0.45 + c.stat(Stats.SPEED) / 100.0 * 0.9) * (1.0 - c.fatigue * 0.3)
	if _tick - c.pinned_tick <= 4:
		rate *= CONTACT_ADVANCE_MULT
	if _mode == MODE_KOTH and c.goes_point and c.pos <= BREACH_ZONE and _on_point_count(enemies) > 0:
		# Pushing onto a held point.
		rate *= 0.25 + c.stat(Stats.BREACH) / 100.0 * 0.9
		c.soldier.add_usage(Stats.BREACH, 0.2)
	c.pos = maxf(dest, c.pos - rate)


## Banks hold time for a team alone on the point. Returns the current holder (-1 = nobody yet).
func _score_hill(squads: Array, holder: int) -> int:
	var on: Array = [_on_point_list(squads[0]), _on_point_list(squads[1])]
	if not on[0].is_empty() and not on[1].is_empty():
		for side in on:
			for c: Combatant in side:
				_result.box[c.soldier.id]["contest_s"] += TICK_SECONDS
				c.soldier.add_usage(Stats.ANCHOR, 0.1)
		return holder
	for i in 2:
		if on[i].is_empty():
			continue
		var before := _arena_score[i]
		_arena_score[i] += TICK_SECONDS
		for c: Combatant in on[i]:
			_result.box[c.soldier.id]["hill_s"] += TICK_SECONDS
			c.soldier.add_usage(Stats.ANCHOR, 0.05)
		if holder != i:
			holder = i
			for c: Combatant in on[i]:
				_result.box[c.soldier.id]["caps"] += 1
				c.soldier.add_usage(Stats.OBJ_IQ, 1.0)
			_result.events.append("%s %s take the hill.  [%s - %s]" % [_stamp(), _result.teams[i].abbrev,
				_fmt_secs(_arena_score[0]), _fmt_secs(_arena_score[1])])
		if _arena_score[i] >= KOTH_HOLD_TO_WIN_S:
			_game_over = true
		elif int(before / 30.0) != int(_arena_score[i] / 30.0):
			_result.events.append("%s %s have held for %s.  [%s - %s]" % [_stamp(), _result.teams[i].abbrev,
				_fmt_secs(_arena_score[i]), _fmt_secs(_arena_score[0]), _fmt_secs(_arena_score[1])])
	return holder


# --- shooting ----------------------------------------------------------------------

func _advance_state(c: Combatant) -> void:
	c.fatigue = minf(1.0, c.fatigue + 0.006 * maxf(0.0, 1.0 - c.stat(Stats.ENDURANCE) / 110.0))
	if c.role == Scheme.Role.FLEX and c.flank_progress < 1.0:
		c.flank_progress += 0.02 + c.stat(Stats.SPEED) * 0.0004
		if c.flank_progress >= 1.0:
			c.soldier.add_usage(Stats.SPEED, 1.0)
			if _mode == MODE_SUDDEN_DEATH:
				_result.events.append("%s %s lands the flank." % [_stamp(), _name(c)])
	if c.reload_ticks > 0:
		c.reload_ticks -= 1
		if c.reload_ticks == 0:
			c.mag = MAG_SIZE


func _distance(c: Combatant, target: Combatant, team_distance: float) -> float:
	var offsets := c.behaviour("distance_offset") + target.behaviour("distance_offset")
	if _mode == MODE_SUDDEN_DEATH:
		return maxf(3.0, team_distance + offsets)
	return maxf(3.0, c.pos + target.pos + offsets * ARENA_OFFSET_SCALE)


func _act(c: Combatant, allies: Array, enemies: Array, team_distance: float) -> void:
	var target := _pick_target(c, allies, enemies)
	c.target = target
	var dist := _distance(c, target, team_distance)
	if dist > MAX_ENGAGE_DISTANCE:
		return
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


func _pick_target(c: Combatant, allies: Array, enemies: Array) -> Combatant:
	var focus := c.stat(Stats.TEAMWORK) / 100.0
	var awareness := c.stat(Stats.AWARENESS) / 100.0
	var candidates: Array = []
	var weights: Array[float] = []
	for e: Combatant in enemies:
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
	return candidates[_weighted_index(weights)]


func _fire(c: Combatant, allies: Array, enemies: Array, target: Combatant, band: StringName, dist: float) -> void:
	var shots := mini(BURST, c.mag)
	c.mag -= shots
	_contact = true
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

	for i in shots:
		if not target.alive:
			break
		var hit_p := p if i == 0 else p_follow
		if _rng.randf() > hit_p:
			target.soldier.add_usage(Stats.AGILITY, 0.15)
			continue
		box["hits"] += 1
		var dmg := _rng.randf_range(22.0, 30.0)
		var headshot := _rng.randf() < 0.06 + c.stat(Stats.GROUPING) * 0.0008
		if headshot:
			dmg *= 2.2
			box["headshots"] += 1
		dmg *= 1.0 - target.stat(Stats.TOUGHNESS) / 100.0 * 0.25
		if _mode == MODE_KOTH and target.on_point():
			dmg *= 1.0 - target.stat(Stats.ANCHOR) / 100.0 * 0.35
		dmg = minf(dmg, target.hp)
		target.hp -= dmg
		box["damage"] += dmg
		c.damage_to[target.soldier.id] = c.damage_to.get(target.soldier.id, 0.0) + dmg
		target.soldier.add_usage(Stats.TOUGHNESS, dmg / 25.0)
		if target.hp <= 0.0:
			_kill(c, target, allies, enemies, band, dist, headshot)
		elif target.hp < SAVE_HP:
			target.endangered_by = c
			target.endangered_tick = _tick


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
	if _mode != MODE_SUDDEN_DEATH:
		if _mode == MODE_TDM:
			_arena_score[killer.team] += 1.0
		if _alive_count(victim_allies) == 0:
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


func _round_winner(squads: Array) -> int:
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

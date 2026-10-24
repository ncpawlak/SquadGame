class_name MatchEngine
extends RefCounted
## Abstract tick-based 5v5 firefight simulator. Deterministic for a given seed.
##
## Model per round:
## - The two squads start START_DISTANCE metres apart and close at a rate driven by Speed.
## - Each soldier's distance to an enemy = team distance + both soldiers' role offsets.
##   Frontmen push forward; the Center hangs back at medium range; Flexes swing wide and,
##   once their flank lands (Speed), collapse in with an accuracy bonus.
## - Each tick every alive soldier may get a shot off (Awareness vs target Agility), then fires
##   a burst: first bullet uses range accuracy, follow-ups use Grouping + Strength (recoil).
## - Endurance limits fatigue, Reload sets reload time, Composure matters when outnumbered,
##   Teamwork drives focus fire and a small squad-wide bonus, Toughness reduces damage taken.
## - Weekly fatigue (Soldier.fatigue) scales down accuracy, speed and reaction stats via
##   Conditioning.penalty(); Injury/Toughness drive weekly injuries outside the match (Conditioning).

const ROUNDS_TO_WIN := 4
const MAX_ROUNDS := 7
const TICK_SECONDS := 0.5
const ROUND_TIME_LIMIT_S := 120.0
const START_DISTANCE := 65.0
const MIN_DISTANCE := 6.0
const MAX_ENGAGE_DISTANCE := 95.0
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

## Round modes. Only elimination exists for now; each round will eventually get its own mode.
const MODE_ELIMINATION := &"elimination"

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
	## victim soldier id -> damage dealt this round (for assists)
	var damage_to: Dictionary = {}
	## 1.0 = fresh; < 1.0 scales FATIGUE_STATS for a soldier who came in tired.
	var condition := 1.0
	## Enemy who last dropped this soldier below SAVE_HP, and when (for teammate saves).
	var endangered_by: Combatant = null
	var endangered_tick := -100

	func stat(s: StringName) -> float:
		var v := float(soldier.eff_stat(s))
		if condition < 1.0 and FATIGUE_STATS.has(s):
			return v * condition
		return v

	func flanked() -> bool:
		return role == Scheme.Role.FLEX and flank_progress >= 1.0

	func behaviour(key: String) -> float:
		var b: Dictionary = Scheme.ROLE_BEHAVIOUR[role]
		if flanked() and b.has("flanked_" + key):
			return b["flanked_" + key]
		return b[key]


var _rng := RandomNumberGenerator.new()
var _result: MatchResult
var _round_number := 0
var _tick := 0
var _contact := false


static func simulate(team_a: Team, team_b: Team, seed_value: int) -> MatchResult:
	var engine := MatchEngine.new()
	return engine._run(team_a, team_b, seed_value)


func _run(team_a: Team, team_b: Team, seed_value: int) -> MatchResult:
	_rng.seed = seed_value
	_result = MatchResult.new()
	_result.match_seed = seed_value
	_result.teams = [team_a, team_b]

	var squads: Array = [_build_squad(team_a, 0), _build_squad(team_b, 1)]
	_result.events.append("=== %s vs %s (seed %d) ===" % [team_a.name, team_b.name, seed_value])
	_result.events.append("%s OVR %d | %s OVR %d" % [team_a.abbrev, team_a.team_ovr(), team_b.abbrev, team_b.team_ovr()])

	while _result.score[0] < ROUNDS_TO_WIN and _result.score[1] < ROUNDS_TO_WIN and _round_number < MAX_ROUNDS:
		_round_number += 1
		_play_round(squads, MODE_ELIMINATION)

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
		squad.append(c)
		_result.box[s.id] = {
			"team": index, "slot": slot_id, "kills": 0, "deaths": 0, "assists": 0, "shots": 0,
			"hits": 0, "headshots": 0, "damage": 0.0, "rounds_played": 0, "rounds_survived": 0,
			"clutches": 0, "saves": 0,
		}
	return squad


func _play_round(squads: Array, mode: StringName) -> void:
	_tick = 0
	_contact = false
	var distance := START_DISTANCE
	var everyone: Array = []
	for squad in squads:
		for c: Combatant in squad:
			c.hp = 100.0
			c.alive = true
			c.mag = MAG_SIZE
			c.reload_ticks = 0
			c.flank_progress = 0.0
			c.target = null
			c.endangered_by = null
			c.damage_to.clear()
			c.fatigue *= 0.6  # partial recovery between rounds
			_result.box[c.soldier.id]["rounds_played"] += 1
			everyone.append(c)

	_result.events.append("--- Round %d (%s) ---" % [_round_number, String(mode).capitalize()])
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
	_result.score[winner] += 1
	var survivors := [_alive_count(squads[0]), _alive_count(squads[1])]
	var round_info := {
		"number": _round_number, "mode": mode, "winner": winner,
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
		_round_number, _result.teams[winner].abbrev, _fmt_time(_tick),
		_result.score[0], _result.score[1]])


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


func _advance_state(c: Combatant) -> void:
	c.fatigue = minf(1.0, c.fatigue + 0.006 * maxf(0.0, 1.0 - c.stat(Stats.ENDURANCE) / 110.0))
	if c.role == Scheme.Role.FLEX and c.flank_progress < 1.0:
		c.flank_progress += 0.02 + c.stat(Stats.SPEED) * 0.0004
		if c.flank_progress >= 1.0:
			c.soldier.add_usage(Stats.SPEED, 1.0)
			_result.events.append("%s %s lands the flank." % [_stamp(), _name(c)])
	if c.reload_ticks > 0:
		c.reload_ticks -= 1
		if c.reload_ticks == 0:
			c.mag = MAG_SIZE


func _act(c: Combatant, allies: Array, enemies: Array, team_distance: float) -> void:
	var target := _pick_target(c, allies, enemies)
	c.target = target
	var dist := maxf(3.0, team_distance + c.behaviour("distance_offset") + target.behaviour("distance_offset"))
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
		candidates.append(e)
		weights.append(w)
	return candidates[_weighted_index(weights)]


func _fire(c: Combatant, allies: Array, enemies: Array, target: Combatant, band: StringName, dist: float) -> void:
	var shots := mini(BURST, c.mag)
	c.mag -= shots
	_contact = true
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
		dmg = minf(dmg, target.hp)
		target.hp -= dmg
		box["damage"] += dmg
		c.damage_to[target.soldier.id] = c.damage_to.get(target.soldier.id, 0.0) + dmg
		target.soldier.add_usage(Stats.TOUGHNESS, dmg / 25.0)
		if target.hp <= 0.0:
			_kill(c, target, allies, band, dist, headshot)
		elif target.hp < SAVE_HP:
			target.endangered_by = c
			target.endangered_tick = _tick


func _kill(killer: Combatant, victim: Combatant, killer_allies: Array, band: StringName, dist: float, headshot: bool) -> void:
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
	return "R%d %s" % [_round_number, _fmt_time(_tick)]


func _fmt_time(tick: int) -> String:
	var secs := int(tick * TICK_SECONDS)
	return "%d:%02d" % [secs / 60, secs % 60]

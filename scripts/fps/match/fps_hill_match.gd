class_name FpsHillMatch
extends Node3D
## Two squads of 5 fight for a central hill. A team alone on the point banks hold time; both on it is a
## contest. First to HOLD_TO_WIN_S, or the higher score when the round timer ends, wins.
## The score/box bookkeeping (init_box, advance, record_kill, record_damage, finish) has no scene
## dependency, so it is unit-tested directly; start() wires it to bots on a map.
##
## Map contract (hill_map.gd): spawn_positions(team_id) -> Array[Vector3], hill_center() -> Vector3,
## hill_radius() -> float, cover_points() -> Array[Vector3].

signal match_finished(result: Dictionary)
signal hill_changed(holder: int)
signal score_changed(scores: Array)

const ASSIST_MIN_DAMAGE := 25.0

var hold_to_win := FpsHillRules.HOLD_TO_WIN_S
var round_s := FpsHillRules.ROUND_S
var respawn_s := FpsHillRules.RESPAWN_S

var teams: Array = [null, null]
var map: Node = null
var bots: Array = []  # [Array of FpsBot for team 0, for team 1]
var scores: Array = [0.0, 0.0]
var time_left := 0.0
var holder := -1
var zone := FpsHillRules.Zone.EMPTY
var box: Dictionary = {}  # soldier id -> box-score fields (same names as the numeric sim)
var finished := false
var result: Dictionary = {}
var seed_value := 1

var _dmg: Dictionary = {}  # victim id -> {attacker id: damage this life}
var _dead_for: Dictionary = {}  # bot -> seconds dead
var _hill_center := Vector3.ZERO
var _hill_radius := 6.0
var _cover: Array = []
var _elapsed := 0.0


## Builds bots for both teams on `p_map`, using each team's lineup (Team.lineup / Team.starters()).
func start(team_a: Team, team_b: Team, p_map: Node, p_seed := 1) -> void:
	seed_value = p_seed
	map = p_map
	_hill_center = map.hill_center()
	_hill_radius = map.hill_radius()
	FpsHill.set_zone(_hill_center, _hill_radius)
	_cover = map.cover_points()
	init_box(team_a, team_b)
	bots = [[], []]
	for t in 2:
		var spawns: Array = map.spawn_positions(t)
		var i := 0
		for s: Soldier in teams[t].starters():
			var slot: StringName = teams[t].slot_of(s)
			var bot := FpsBot.new()
			bot.world = self
			add_child(bot)
			bot.setup(s, t, Scheme.SLOT_ROLES.get(slot, Scheme.Role.FLEX))
			bot.slot = slot
			bot.rng.seed = seed_value * 1000 + t * 100 + i
			bot.global_position = spawns[i % spawns.size()]
			bot.died.connect(_on_bot_died.bind(bot))
			bot.damaged.connect(_on_bot_damaged.bind(bot))
			bots[t].append(bot)
			i += 1
	set_physics_process(true)


func init_box(team_a: Team, team_b: Team) -> void:
	teams = [team_a, team_b]
	scores = [0.0, 0.0]
	time_left = round_s
	holder = -1
	zone = FpsHillRules.Zone.EMPTY
	finished = false
	box.clear()
	_dmg.clear()
	for t in 2:
		for s: Soldier in teams[t].starters():
			box[s.id] = FpsHillRules.new_box(s.id, t, teams[t].slot_of(s))


## One scoring step. on_ids = [soldier ids on the point for team 0, for team 1].
## Returns the winner (-1 still running, 0/1, 2 draw).
func advance(delta: float, on_ids: Array) -> int:
	if finished:
		return int(result.get("winner", -1))
	_elapsed += delta
	time_left = maxf(0.0, time_left - delta)
	zone = FpsHillRules.zone_state(on_ids[0].size(), on_ids[1].size())
	if zone == FpsHillRules.Zone.CONTESTED:
		for side in on_ids:
			for id in side:
				box[id]["contest_s"] += delta
	else:
		var t := FpsHillRules.scoring_team(zone)
		if t >= 0:
			scores = FpsHillRules.step_score(scores, zone, delta)
			for id in on_ids[t]:
				box[id]["hill_s"] += delta
			if holder != t:
				holder = t
				for id in on_ids[t]:
					box[id]["caps"] += 1
				hill_changed.emit(t)
			score_changed.emit(scores)
	FpsHill.state = {"holder": holder, "zone": zone, "scores": scores.duplicate(), "time_left": time_left, "hold_to_win": hold_to_win}
	var w := FpsHillRules.winner(scores, time_left, hold_to_win)
	if w >= 0:
		finish(w)
	return w


func record_damage(attacker_id: int, victim_id: int, amount: float) -> void:
	if attacker_id == victim_id:
		return
	if not _dmg.has(victim_id):
		_dmg[victim_id] = {}
	_dmg[victim_id][attacker_id] = float(_dmg[victim_id].get(attacker_id, 0.0)) + amount


## Credits the kill and assists (anyone else on the killer's team who did enough damage this life).
func record_kill(killer_id: int, victim_id: int) -> void:
	if not box.has(victim_id):
		return
	box[victim_id]["deaths"] += 1
	if box.has(killer_id) and box[killer_id]["team"] != box[victim_id]["team"]:
		box[killer_id]["kills"] += 1
		var hurt: Dictionary = _dmg.get(victim_id, {})
		for aid in hurt:
			if aid != killer_id and box.has(aid) and box[aid]["team"] == box[killer_id]["team"] \
					and float(hurt[aid]) >= ASSIST_MIN_DAMAGE:
				box[aid]["assists"] += 1
	_dmg.erase(victim_id)


func finish(w: int) -> Dictionary:
	finished = true
	FpsHill.clear()
	result = {
		"winner": w,
		"scores": scores.duplicate(),
		"teams": [_team_info(0), _team_info(1)],
		"duration": _elapsed,
		"box": box.duplicate(true),
	}
	match_finished.emit(result)
	return result


func _team_info(t: int) -> Dictionary:
	var tm = teams[t]
	return {"id": tm.id if tm != null else -1, "abbrev": tm.abbrev if tm != null else "", "score": scores[t]}


func _physics_process(delta: float) -> void:
	if finished or bots.is_empty():
		return
	var on: Array = [[], []]
	for t in 2:
		for b: FpsBot in bots[t]:
			if b.alive and Vector2(b.global_position.x - _hill_center.x, b.global_position.z - _hill_center.z).length() <= _hill_radius:
				on[t].append(b.soldier.id)
	for b in _dead_for.keys():
		_dead_for[b] += delta
		if FpsHillRules.respawn_ready(_dead_for[b], respawn_s):
			_dead_for.erase(b)
			var spawns: Array = map.spawn_positions(b.team_id)
			b.respawn(spawns[randi() % spawns.size()])
	advance(delta, on)


func _on_bot_died(source, bot: FpsBot) -> void:
	var kid := -1
	var killer_pos := bot.global_position
	if source != null and is_instance_valid(source) and "soldier" in source and source.soldier != null:
		kid = source.soldier.id
		killer_pos = source.global_position
	record_kill(kid, bot.soldier.id)
	_dead_for[bot] = 0.0
	for mate: FpsBot in bots[bot.team_id]:
		if mate != bot and mate.alive:
			mate.notify_teammate_down(killer_pos)


func _on_bot_damaged(amount: float, source, bot: FpsBot) -> void:
	if source != null and is_instance_valid(source) and "soldier" in source and source.soldier != null:
		record_damage(source.soldier.id, bot.soldier.id, amount)


# --- world interface used by FpsBot ---

func enemies_of(team_id: int) -> Array:
	return bots[1 - team_id] if not bots.is_empty() else []


func allies_of(team_id: int) -> Array:
	return bots[team_id] if not bots.is_empty() else []


func hill_center() -> Vector3:
	return _hill_center


func hill_radius() -> float:
	return _hill_radius


func cover_points() -> Array:
	return _cover


func zone_name_for(team_id: int) -> String:
	return zone_name(zone, team_id)


static func zone_name(z: FpsHillRules.Zone, team_id: int) -> String:
	match z:
		FpsHillRules.Zone.CONTESTED:
			return "contested"
		FpsHillRules.Zone.EMPTY:
			return "empty"
	return "mine" if FpsHillRules.scoring_team(z) == team_id else "enemy"


func count_on_point(team_id: int) -> int:
	var n := 0
	if bots.is_empty():
		return 0
	for b: FpsBot in bots[team_id]:
		if b.alive and Vector2(b.global_position.x - _hill_center.x, b.global_position.z - _hill_center.z).length() <= _hill_radius:
			n += 1
	return n

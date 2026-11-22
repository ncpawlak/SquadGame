class_name FpsRoleBrain
extends RefCounted
## The 2D sim's tactical brain (MatchEngine._role_goal/_standoff/_goal/_choose_cover/_rhythm/_point_decisions and
## the hunting + contact-memory rules) ported for ONE soldier, in the 2D arena frame (3D x,z -> 2D x,y).
## No scene dependency: FpsBot feeds it positions and reads back a 2D goal, a posture and a peek/duck flag.
##
## Time is counted in sim ticks (TICK_S = 0.5 s) so every constant below keeps its MatchEngine value.
## Ally/enemy entries are Dictionaries: {pos: Vector2, alive: bool, role: int, cover: Vector2, goes: bool, hp: float}.

const TICK_S := 0.5
const FRONT_STANDOFF := 12.0
const CENTER_STANDOFF := 30.0
const FLEX_STANDOFF := 17.0
const FLANK_LANE_TRAIL := 4.0
const AT_SPOT := 3.0
const COMMIT_DIST := 12.0
const COVER_REACHED_SQ := 2.25
const COVER_SEARCH_RADIUS := 9.0
const BOUND_RADIUS_MIN := 6.0
const BOUND_RADIUS_MAX := 14.0
const PLAN_EVERY := 3
const PEEK_BASE := 4
const DUCK_BASE := 2
const CONTACT_MEMORY := 16  ## 8 s
const HUNT_AFTER_TICKS := 20  ## 10 s
const HURT_HP := 50.0
const ARRIVING_DIST := 14.0
const BREACH_ZONE := 8.0

const POSTURE_POINT := &"point"
const POSTURE_ADVANCE := &"advancing"
const POSTURE_BOUND := &"bounding"
const POSTURE_DUCK := &"ducked"
const POSTURE_PEEK := &"peeking"
const POSTURE_FALLBACK := &"falling back"
const POSTURE_FLANK := &"flanking"

var role: int = Scheme.Role.FLEX
var team := 0
var slot: StringName = &""
var scheme: Scheme = null
var koth := false
var rng := RandomNumberGenerator.new()

# ratings, 0..1
var aw := 0.5
var comp := 0.5
var tw := 0.5
var iq := 0.5
var spd := 0.5

# life state (the sim's Combatant fields)
var tick := 0
var flank_right := false
var flank_lane := 0
var flank_progress := 0.0
var goes_point := false
var falling_back := false
var hill_spot := Vector2.INF
var hunting := false
var threat_pos := Vector2.INF
var threat_tick := -100
var last_contact_tick := 0
var cover_spot := Vector2.INF
var peeking := true
var phase_end := 0
var plan_tick := -100
var posture: StringName = POSTURE_ADVANCE

var _acc := 0.0


static func _n(soldier: Soldier, stat: StringName) -> float:
	if soldier != null and soldier.stats.has(stat):
		return clampf(float(soldier.get_stat(stat)) / 100.0, 0.0, 1.1)
	return 0.5


func setup(soldier: Soldier, p_team: int, p_role: int, p_slot: StringName, p_scheme: Scheme, p_rng: RandomNumberGenerator = null) -> void:
	team = p_team
	role = p_role
	slot = p_slot
	scheme = p_scheme
	if p_rng != null:
		rng = p_rng
	aw = _n(soldier, Stats.AWARENESS)
	comp = _n(soldier, Stats.COMPOSURE)
	tw = _n(soldier, Stats.TEAMWORK)
	iq = _n(soldier, Stats.OBJ_IQ)
	spd = _n(soldier, Stats.SPEED)
	reset_life()


## A fresh life (spawn): the sim's _reset_life + _spawn.
func reset_life() -> void:
	flank_progress = 0.0
	flank_lane = scheme.flank_lane(slot) if scheme != null else 0
	flank_right = rng.randf() < 0.5
	if role == Scheme.Role.FLEX and scheme != null:
		var side := scheme.flank_side(slot)
		flank_right = side > 0 if side != 0 else rng.randf() < 0.5
	cover_spot = Vector2.INF
	peeking = true
	phase_end = tick
	plan_tick = -100
	last_contact_tick = tick
	hunting = false
	falling_back = false
	threat_pos = Vector2.INF
	threat_tick = -100
	goes_point = false
	hill_spot = Vector2.INF
	posture = POSTURE_ADVANCE
	if koth and role == Scheme.Role.CENTER:
		_set_goes_point(true)


func set_koth(value: bool) -> void:
	if value == koth:
		return
	koth = value
	if not koth:
		goes_point = false
		falling_back = false
	elif role == Scheme.Role.CENTER:
		_set_goes_point(true)


func _set_goes_point(value: bool) -> void:
	goes_point = value
	if value:
		var inner := ArenaMap.HILL.grow(-1.5)
		hill_spot = Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))


## Advances the clock; returns how many whole sim ticks passed (the bot re-plans once per tick).
func advance(delta: float) -> int:
	_acc += delta
	var n := 0
	while _acc >= TICK_S:
		_acc -= TICK_S
		tick += 1
		n += 1
		if role == Scheme.Role.FLEX and flank_progress < 1.0:
			# speed covers ground, awareness picks the right route (same per-tick increment as the sim, 0..110 stats)
			flank_progress += 0.016 + spd * 100.0 * 0.0004 + aw * 100.0 * 0.0001
	return n


func in_cover(pos: Vector2) -> bool:
	return cover_spot != Vector2.INF and pos.distance_squared_to(cover_spot) < COVER_REACHED_SQ


func ducked(pos: Vector2) -> bool:
	return in_cover(pos) and not peeking


func flanked() -> bool:
	return role == Scheme.Role.FLEX and flank_progress >= 1.0


## A visible enemy this scan (INF = none): refreshes the threat and the contact clock.
func note_visible(enemy_pos: Vector2) -> void:
	if enemy_pos == Vector2.INF:
		return
	threat_pos = enemy_pos
	threat_tick = tick
	last_contact_tick = tick


# --- goals ---------------------------------------------------------------------------

static func nearest_enemy_pos(pos: Vector2, enemies: Array) -> Vector2:
	var best := INF
	var out := Vector2.INF
	for e in enemies:
		if not e["alive"]:
			continue
		var d := pos.distance_squared_to(e["pos"])
		if d < best:
			best = d
			out = e["pos"]
	return out


## Where the role wants him, before cover is considered (MatchEngine._role_goal).
func role_goal(pos: Vector2, allies: Array, enemies: Array) -> Vector2:
	var lane := scheme.hold_of(slot, koth).y
	if falling_back:
		return ArenaMap.world(team, Vector2(-9.0, clampf(lane * 1.5, -12.0, 12.0)))
	match role:
		Scheme.Role.FRONTMAN:
			if koth:
				return ArenaMap.world(team, Vector2(7.0, clampf(lane * 0.8, -8.0, 8.0)))
			return ArenaMap.world(team, Vector2(1.0, lane))
		Scheme.Role.CENTER:
			if koth:
				return ArenaMap.world(team, Vector2(-9.0, lane * 0.5))
			var fx := 0.0
			var n := 0
			for a in allies:
				if a["alive"] and a.get("role", -1) == Scheme.Role.FRONTMAN:
					fx += a["pos"].x if team == 0 else -a["pos"].x
					n += 1
			var line_x := fx / n if n > 0 else -4.0
			return ArenaMap.world(team, Vector2(clampf(line_x - 9.0, -30.0, -3.0), lane))
	var side := 1.0 if flank_right else -1.0
	if flank_progress < 1.0:
		var fp := ArenaMap.flank_point(flank_progress, flank_right)
		if flank_lane > 0:
			fp.x -= FLANK_LANE_TRAIL
		return ArenaMap.world(team, fp)
	if koth:
		return ArenaMap.world(team, Vector2(2.0, side * 13.0))
	var nearest := nearest_enemy_pos(pos, enemies)
	return nearest if nearest != Vector2.INF else ArenaMap.world(team, Vector2(10.0, side * 18.0))


## How close he wants to get before he stops advancing and fights from cover.
func standoff() -> float:
	match role:
		Scheme.Role.FRONTMAN:
			return FRONT_STANDOFF
		Scheme.Role.CENTER:
			return CENTER_STANDOFF
	return FLEX_STANDOFF if flank_progress >= 1.0 else 0.0


## Where he is headed this tick, and his posture (MatchEngine._goal). Call once per tick.
func goal(pos: Vector2, arena: ArenaMap, allies: Array, enemies: Array, reloading := false) -> Vector2:
	var goer := koth and goes_point
	if goer and ArenaMap.HILL.grow(COMMIT_DIST).has_point(pos):
		posture = POSTURE_POINT
		cover_spot = Vector2.INF
		return hill_spot
	var want := hill_spot if goer else role_goal(pos, allies, enemies)
	var contact := threat_pos != Vector2.INF and tick - threat_tick <= CONTACT_MEMORY
	var flank_run := role == Scheme.Role.FLEX and flank_progress < 1.0
	if not contact:
		if not hunting and not flank_run and not falling_back and (not koth or role == Scheme.Role.FRONTMAN):
			var quiet := tick - last_contact_tick
			var read := HUNT_AFTER_TICKS * (1.3 - aw * 0.6)
			if quiet > read and (pos.distance_squared_to(want) < 9.0 or quiet > read * 4):
				hunting = true
		if hunting:
			var nearest := nearest_enemy_pos(pos, enemies)
			if nearest != Vector2.INF:
				want = nearest
		cover_spot = Vector2.INF
		peeking = true
		posture = POSTURE_POINT if goer else (POSTURE_FLANK if flank_run else (POSTURE_FALLBACK if falling_back else POSTURE_ADVANCE))
		return want

	var dist := pos.distance_to(threat_pos)
	var stand := 0.0 if goer else standoff()
	if in_cover(pos):
		_rhythm(reloading)
		posture = POSTURE_PEEK if peeking else POSTURE_DUCK
		var far := pos.distance_to(want) > AT_SPOT and (dist > stand or falling_back)
		var urgency := 0.6 + aw * 0.4 if (goer or falling_back) else 0.15 + aw * 0.5
		if far and not peeking and tick - plan_tick >= PLAN_EVERY and rng.randf() < urgency:
			plan_tick = tick
			if choose_cover(pos, arena, allies, want, 1.0):
				posture = POSTURE_BOUND
				return cover_spot
		return cover_spot
	if cover_spot != Vector2.INF:
		if tick - plan_tick <= 10:
			posture = POSTURE_BOUND
			return cover_spot
		cover_spot = Vector2.INF
	if tick - plan_tick >= PLAN_EVERY:
		plan_tick = tick
		var preplan := clampf((aw - 0.35) / 0.5, 0.0, 1.0)
		if rng.randf() < preplan and choose_cover(pos, arena, allies, want, -4.0):
			posture = POSTURE_BOUND
			return cover_spot
	posture = POSTURE_POINT if goer else (POSTURE_FLANK if flank_run else (POSTURE_FALLBACK if falling_back else POSTURE_ADVANCE))
	if dist > stand or falling_back or goer:
		return want
	return pos


## Next cover toward `want`, hidden from the known threat, spread from allies (MatchEngine._choose_cover).
func choose_cover(pos: Vector2, arena: ArenaMap, allies: Array, want: Vector2, gain: float) -> bool:
	var taken: Array = []
	for a in allies:
		var c: Vector2 = a.get("cover", Vector2.INF)
		if a["alive"] and c != Vector2.INF and a["pos"] != pos:
			taken.append(c)
	var spot := arena.cover_toward(pos, want, threat_pos, lerpf(BOUND_RADIUS_MIN, BOUND_RADIUS_MAX, aw),
		gain, taken, 6.0 * tw)
	if spot == Vector2.INF:
		return false
	cover_spot = spot
	peeking = false
	phase_end = 0
	return true


## Peek and duck (MatchEngine._rhythm): fires only while peeking, reloads ducked.
func _rhythm(reloading: bool) -> void:
	if reloading:
		peeking = false
		phase_end = tick + 1
		return
	if tick < phase_end:
		return
	peeking = not peeking
	var ticks: int
	if peeking:
		ticks = PEEK_BASE + roundi(comp * 2.0) + rng.randi_range(0, 1)
	else:
		ticks = DUCK_BASE - roundi(aw * 2.0) + rng.randi_range(0, 1)
	phase_end = tick + maxi(1, ticks)


## Shot at: he knows where the shooter is and an aware soldier gets down behind the nearest cover (_seek_cover).
func shot_at(pos: Vector2, arena: ArenaMap, shooter_pos: Vector2) -> void:
	if koth and goes_point and ArenaMap.HILL.grow(2.0).has_point(pos):
		return
	threat_pos = shooter_pos
	threat_tick = tick
	if cover_spot != Vector2.INF:
		return
	if rng.randf() > 0.15 + aw * 0.6:
		return
	var spot := arena.find_cover(pos, shooter_pos, COVER_SEARCH_RADIUS)
	if spot != Vector2.INF:
		cover_spot = spot
		peeking = false
		phase_end = 0
		plan_tick = tick


## KOTH: does he go to the point (MatchEngine._point_decisions for this one soldier)? `squad` includes him as the
## entry with "self": true; entries carry role/alive/goes/pos/hp.
func point_decisions(pos: Vector2, hp: float, squad: Array, enemies: Array) -> void:
	if not koth:
		return
	var hill_c := ArenaMap.HILL.get_center()
	var enemy_on := 0
	var enemy_near := 0
	for e in enemies:
		if e["alive"]:
			if ArenaMap.on_hill(e["pos"]):
				enemy_on += 1
			if e["pos"].distance_to(hill_c) < BREACH_ZONE + 6.0:
				enemy_near += 1
	var pressure := maxi(enemy_on, enemy_near)
	var mine_on := 0
	var center_holding := false
	var center_arriving := false
	var hurt_center_on := false
	var hurt_center := false
	var on_count := 0
	for c in squad:
		if not c["alive"]:
			continue
		var cpos: Vector2 = c["pos"]
		if ArenaMap.on_hill(cpos):
			mine_on += 1
		if c["goes"]:
			on_count += 1
		if c["role"] != Scheme.Role.CENTER or not c["goes"]:
			continue
		if c["hp"] > HURT_HP:
			center_holding = true
		elif not hurt_center:
			hurt_center = true
			hurt_center_on = ArenaMap.on_hill(cpos)
		if not ArenaMap.on_hill(cpos) and cpos.distance_to(hill_c) < ARRIVING_DIST:
			center_arriving = true
	var read := 0.04 + iq * 0.32 + tw * 0.08
	if role == Scheme.Role.CENTER:
		if goes_point:
			var relief := false
			for o in squad:
				if not o.get("self", false) and o["alive"] and o["goes"] and o["role"] != Scheme.Role.CENTER \
						and o["pos"].distance_to(hill_c) < ARRIVING_DIST:
					relief = true
			if hp <= HURT_HP and relief and on_count > 1:
				_set_goes_point(false)
				falling_back = true
		elif (hp > HURT_HP or on_count == 0) and (not falling_back or on_count == 0):
			_set_goes_point(true)
			falling_back = false
		return
	if goes_point:
		if center_holding or center_arriving:
			if on_count > 1 and pressure == 0 and rng.randf() < read * 0.5:
				_set_goes_point(false)
		elif not center_holding and not hurt_center and on_count > 1 and pressure == 0 \
				and rng.randf() < (1.0 - iq) * 0.01:
			_set_goes_point(false)
		return
	var chance := 0.0
	if hurt_center and hurt_center_on and on_count <= 1:
		chance = read
	elif on_count == 0:
		if role == Scheme.Role.FRONTMAN or pressure > 0:
			chance = read
	elif enemy_on > mine_on:
		chance = read * 0.7 if role == Scheme.Role.FLEX else iq * 0.1
	if chance > 0.0 and rng.randf() < chance:
		_set_goes_point(true)

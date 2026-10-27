class_name Relationships
extends RefCounted
## Teammate chemistry (a DNA module). Every pair of soldiers who have shared a roster has a score
## (0-100) kept league-wide, so a bond survives trades, releases and re-signings.
## - Gains: each match two soldiers start together +MATCH_GAIN; formation neighbours (see
##   Scheme.ADJACENT) +ADJACENT_GAIN on top; every rostered pair +TRAINING_GAIN a week.
## - Decay: pairs not on the same roster lose DECAY a week (offseason weeks too).
## - Levels: Familiar (20), Trusted (50), Inseparable (80). When both are in the lineup, each
##   linked teammate adds +1/+2/+3 to the soldier's Mentality ratings (Awareness, Composure,
##   Teamwork), capped at +BONUS_CAP per rating.

const LEVEL_POINTS: Array[float] = [0.0, 20.0, 50.0, 80.0]
const LEVEL_NAMES: Array[String] = ["Acquainted", "Familiar", "Trusted", "Inseparable"]
const LEVEL_COLORS: Array[Color] = [Color("#64748b"), Color("#38bdf8"), Color("#22c55e"), Color("#f59e0b")]
const LEVEL_BONUS: Array[int] = [0, 1, 2, 3]
const BONUS_CAP := 4
const MAX_POINTS := 100.0
const MATCH_GAIN := 1.5
const ADJACENT_GAIN := 3.0
const TRAINING_GAIN := 0.3
const DECAY := 1.0

## The store and league the soldiers' rating mods read (Season keeps these current).
static var active: Relationships = null
static var league_now: League = null

## Vector2i(low id, high id) -> {"pts": float, "m": matches together, "d": last week's change}.
var pairs: Dictionary = {}


static func key(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


static func level_for(pts: float) -> int:
	for i in range(LEVEL_POINTS.size() - 1, 0, -1):
		if pts >= LEVEL_POINTS[i]:
			return i
	return 0


func points(a: Soldier, b: Soldier) -> float:
	var p: Dictionary = pairs.get(key(a.id, b.id), {})
	return float(p.get("pts", 0.0))


func level(a: Soldier, b: Soldier) -> int:
	return level_for(points(a, b))


## Mentality bonus (per rating) for `s` if `lineup` is who he plays with (0 if he isn't in it).
func bonus_in(s: Soldier, lineup: Array) -> int:
	if not lineup.has(s):
		return 0
	var total := 0
	for o in lineup:
		if o != s:
			total += LEVEL_BONUS[level(s, o)]
	return mini(total, BONUS_CAP)


## Bonus for `s` in his current club's lineup (0 for free agents / bench / no active store).
static func bonus_for(s: Soldier) -> int:
	if active == null or league_now == null:
		return 0
	var t := league_now.team_of(s)
	return 0 if t == null else active.bonus_in(s, t.starters())


func _add(a: Soldier, b: Soldier, amount: float, week_delta: Dictionary, match_count := 0) -> void:
	var k := key(a.id, b.id)
	var p: Dictionary = pairs.get(k, {})
	if p.is_empty():
		p = {"pts": 0.0, "m": 0, "d": 0.0}
		pairs[k] = p
	var before: float = p["pts"]
	p["pts"] = minf(MAX_POINTS, before + amount)
	p["m"] = int(p["m"]) + match_count
	week_delta[k] = float(week_delta.get(k, 0.0)) + float(p["pts"]) - before


## One week of chemistry: match gains from `played` (box scores give who started where),
## training gains for every rostered pair, decay for everyone else.
func week(league: League, played: Array) -> void:
	var delta := {}
	for m in played:
		if not m.is_played():
			continue
		var box: Dictionary = m.result.box
		for t: Team in [m.home, m.away]:
			var by_slot := {}
			for so in t.roster:
				if box.has(so.id):
					by_slot[StringName(box[so.id]["slot"])] = so
			var lineup: Array = by_slot.values()
			for i in lineup.size():
				for j in range(i + 1, lineup.size()):
					_add(lineup[i], lineup[j], MATCH_GAIN, delta, 1)
			for pr in Scheme.ADJACENT.get(t.scheme.id, []):
				if by_slot.has(pr[0]) and by_slot.has(pr[1]):
					_add(by_slot[pr[0]], by_slot[pr[1]], ADJACENT_GAIN, delta)
	for t in league.teams:
		for i in t.roster.size():
			for j in range(i + 1, t.roster.size()):
				_add(t.roster[i], t.roster[j], TRAINING_GAIN, delta)
	_decay(delta)


## Offseason week: teammates hold steady, everyone else drifts apart.
func offseason_week(league: League) -> void:
	var held := {}
	for t in league.teams:
		for i in t.roster.size():
			for j in range(i + 1, t.roster.size()):
				var k := key(t.roster[i].id, t.roster[j].id)
				if pairs.has(k):
					held[k] = 0.0
	_decay(held)


## Pairs not in `delta` lose DECAY (and vanish at 0); every pair's "d" becomes this week's change.
func _decay(delta: Dictionary) -> void:
	for k in pairs.keys():
		var p: Dictionary = pairs[k]
		if delta.has(k):
			p["d"] = delta[k]
			continue
		var before: float = p["pts"]
		p["pts"] = maxf(0.0, before - DECAY)
		p["d"] = float(p["pts"]) - before
		if float(p["pts"]) <= 0.0:
			pairs.erase(k)


## New league: current teammates already have some history, more the older both are.
func seed_league(league: League, rng: RandomNumberGenerator) -> void:
	for t in league.teams:
		for i in t.roster.size():
			for j in range(i + 1, t.roster.size()):
				var a: Soldier = t.roster[i]
				var b: Soldier = t.roster[j]
				var years := rng.randi_range(0, clampi(mini(a.age, b.age) - 21, 0, 6))
				if years == 0:
					continue
				var pts := minf(90.0, years * rng.randf_range(5.0, 13.0))
				pairs[key(a.id, b.id)] = {"pts": pts, "m": years * rng.randi_range(4, 12), "d": 0.0}


## Drops pairs involving soldiers no longer in the league (retired).
func prune(active_ids: Dictionary) -> void:
	for k in pairs.keys():
		if not active_ids.has(k.x) or not active_ids.has(k.y):
			pairs.erase(k)


## Everyone `s` has a bond with, strongest first: [{id, pts, m, d}].
func partners_of(s: Soldier) -> Array:
	var out: Array = []
	for k: Vector2i in pairs:
		if k.x == s.id or k.y == s.id:
			var p: Dictionary = pairs[k]
			out.append({"id": k.y if k.x == s.id else k.x, "pts": p["pts"], "m": p["m"], "d": p["d"]})
	out.sort_custom(func(x, y): return x["pts"] > y["pts"])
	return out

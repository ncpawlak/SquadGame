class_name Team
extends RefCounted
## A team: roster of soldiers plus a lineup slotting 5 of them into the scheme.

const ROSTER_SIZE := 12
## Offseason rosters may run this big (draft picks + free agents); cut down to ROSTER_SIZE before Week 1.
const OFFSEASON_MAX := 15
## Future weight by dev stars (1..4) in keep_value: faster developers reach their ceiling sooner.
const KEEP_DEV_W := [0.35, 0.55, 0.75, 0.9]
## Flat bonus by dev stars (1..4) for young players on top of the raw gap (scaled by age weight).
const KEEP_DEV_FLAT := [0.0, 0.0, 2.0, 4.0]
## Draft-capital bonus by round (1..3) for a pick's draft offseason and first season; halved in his second.
const KEEP_DRAFT_BONUS := [10.0, 5.0, 2.0]

## Current league year (kept in sync by Season.year) for draft-capital ages in keep_value.
static var year_now := 0
## Teams in the league (picks per draft round) for keep_value's draft round.
static var league_size := 20

var id: int
var name: String
var abbrev: String
var city := ""
var nickname := ""
## Division (LeagueData.DIVISIONS) and two-letter home state.
var division := ""
var home_state := ""
var backstory := ""
var color: Color = Color.WHITE
## Accent colour for gear trim (goggle frames, straps, brims...).
var color2: Color = Color("#e5e7eb")
var roster: Array[Soldier] = []
var scheme: Scheme = Scheme.power_front()
## slot_id (StringName) -> Soldier
var lineup: Dictionary = {}
## True for the team the user controls (skill points are not auto-spent).
var user_controlled := false
## Cap year -> dead money ($K) still owed to released soldiers.
var dead_money: Dictionary = {}
## Season year -> salary-floor penalty charged for it (also booked into next year's dead money).
var floor_penalties: Dictionary = {}


func starters() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for slot_id in scheme.slot_ids():
		if lineup.has(slot_id):
			out.append(lineup[slot_id])
	return out


func bench() -> Array[Soldier]:
	var in_lineup := starters()
	var out: Array[Soldier] = []
	for s in roster:
		if not in_lineup.has(s):
			out.append(s)
	return out


func slot_of(soldier: Soldier) -> StringName:
	for slot_id in lineup:
		if lineup[slot_id] == soldier:
			return slot_id
	return &""


func ovr_in_slot(soldier: Soldier, slot_id: StringName) -> int:
	return soldier.ovr_at_role(scheme.role_for_slot(slot_id))


## Puts `soldier` into `slot_id`. If they were already in another slot, the two swap.
func assign(slot_id: StringName, soldier: Soldier) -> void:
	var previous_slot := slot_of(soldier)
	var displaced: Soldier = lineup.get(slot_id)
	lineup[slot_id] = soldier
	if previous_slot != &"" and previous_slot != slot_id:
		if displaced:
			lineup[previous_slot] = displaced
		else:
			lineup.erase(previous_slot)


## Exhaustively picks the 5 starters/slots that maximise total positional OVR. Injured soldiers
## are skipped unless there aren't enough healthy ones. With `consider_fatigue`, OVR is scaled
## by match fatigue penalty so tired starters can be rested.
func auto_lineup(consider_fatigue := false) -> void:
	var best := _best_pick(scheme, consider_fatigue)
	var slot_ids := scheme.slot_ids()
	var pool: Array = best["pool"]
	lineup.clear()
	for i in slot_ids.size():
		lineup[slot_ids[i]] = pool[best["pick"][i]]


## Best lineup this roster could field in `sch` (slot_id -> Soldier), without changing the team.
func lineup_for(sch: Scheme) -> Dictionary:
	var best := _best_pick(sch, false)
	var pool: Array = best["pool"]
	var out := {}
	var ids := sch.slot_ids()
	for i in ids.size():
		out[ids[i]] = pool[best["pick"][i]]
	return out


## Average positional OVR of the best healthy lineup in `sch`.
func scheme_fit(sch: Scheme) -> float:
	return float(_best_pick(sch, false)["score"]) / sch.slot_ids().size()


## The scheme that gets the most out of this roster. Near-ties go to the coaching staff's taste
## (a small fixed per-team preference) and then to the current scheme.
func best_scheme() -> Scheme:
	var best: Scheme = scheme
	var best_fit := -INF
	for sch in Scheme.all():
		var f := scheme_fit(sch) + style_bias(sch.id) + (0.25 if sch.id == scheme.id else 0.0)
		if f > best_fit:
			best_fit = f
			best = sch
	return best


## 0..1 OVR points of fixed preference for a scheme, different for every team.
func style_bias(scheme_id: StringName) -> float:
	return float(hash(abbrev + String(scheme_id)) % 1000) / 1000.0


func set_scheme(sch: Scheme) -> void:
	scheme = sch
	if roster.size() >= sch.slot_ids().size():
		auto_lineup()
	else:
		lineup.clear()


## AI front offices: switch to the best-fitting scheme. Returns true if it changed.
func pick_scheme() -> bool:
	if user_controlled or roster.size() < scheme.slot_ids().size():
		return false
	var sch := best_scheme()
	if sch.id == scheme.id:
		return false
	set_scheme(sch)
	return true


func _best_pick(sch: Scheme, consider_fatigue: bool) -> Dictionary:
	var slot_ids := sch.slot_ids()
	var pool: Array[Soldier] = []
	for s in roster:
		if not s.is_injured():
			pool.append(s)
	if pool.size() < slot_ids.size():
		pool = roster.duplicate()
	var best := {"score": -1.0, "pick": []}
	# Value of each pool soldier in each slot, computed once (the search visits ~10^5 nodes).
	var vals: Array = []
	var same_as_prev: Array[bool] = []
	for d in slot_ids.size():
		var role := sch.role_for_slot(slot_ids[d])
		same_as_prev.append(d > 0 and sch.role_for_slot(slot_ids[d - 1]) == role)
		var row := PackedFloat64Array()
		for s in pool:
			var value := float(s.ovr_at_role(role))
			if consider_fatigue:
				value *= 1.0 - Conditioning.penalty(s.fatigue)
			row.append(value)
		vals.append(row)
	# Upper bound on what the remaining slots can add (each slot's best value), for pruning.
	var bound := PackedFloat64Array()
	bound.resize(slot_ids.size() + 1)
	bound[slot_ids.size()] = 0.0
	for d in range(slot_ids.size() - 1, -1, -1):
		var top := 0.0
		for v in vals[d]:
			top = maxf(top, v)
		bound[d] = bound[d + 1] + top
	best["bound"] = bound
	_search(vals, same_as_prev, pool.size(), 0, [], 0, 0.0, best)
	best["pool"] = pool
	return best


## Replaces injured starters with the best healthy bench soldier for that slot.
## Returns true if the lineup changed.
func fill_injured() -> bool:
	var changed := false
	for slot_id in scheme.slot_ids():
		var current: Soldier = lineup.get(slot_id)
		if current != null and not current.is_injured():
			continue
		var best: Soldier = null
		for s in bench():
			if s.is_injured():
				continue
			if best == null or ovr_in_slot(s, slot_id) > ovr_in_slot(best, slot_id):
				best = s
		if best != null:
			lineup[slot_id] = best
			changed = true
	return changed


func is_over_roster_limit() -> bool:
	return roster.size() > ROSTER_SIZE


## Removes a soldier from the roster (and lineup, refilling the hole from the bench).
func release(soldier: Soldier) -> void:
	soldier.former_team = abbrev
	soldier.promise = {}
	var slot := slot_of(soldier)
	roster.erase(soldier)
	if slot != &"":
		lineup.erase(slot)
		fill_injured()


## How much a front office wants to keep `s` (higher = keep), in OVR-like points:
##   now      current OVR at his best role
##   future   (projected - current) x age weight (1 at <=21, 0 by 28) x dev weight (4* 0.9 .. 1* 0.35)
##   depth    starter +5, top backup +3; deeper: -3 per player ahead who is better now and projects
##            at least as high (halved for young 3-4 star players, who are still developing)
##   draft    this year's / last year's pick: R1 +10, R2 +5, R3 +2 (half a year later, then gone)
##   contract cheap deal or big dead money if cut up to +5, overpaid down to -3
##   age      falls from 30, faster from 33
func keep_value(s: Soldier) -> float:
	var now := float(s.best_ovr())
	var v := now
	var age_w := clampf((28.0 - s.age) / 7.0, 0.0, 1.0)
	var g := clampi(s.dev, Soldier.DEV_MIN, Soldier.DEV_MAX) - Soldier.DEV_MIN
	v += (maxf(0.0, float(s.potential_ovr()) - now) * float(KEEP_DEV_W[g]) + float(KEEP_DEV_FLAT[g])) * age_w
	if s.age >= 30:
		v -= float(s.age - 29) * 0.8
	if s.age >= 33:
		v -= float(s.age - 32) * 1.2
	var role := Scheme.best_role(s.stats)
	var slots := 0
	for slot_id in scheme.slot_ids():
		if scheme.role_for_slot(slot_id) == role:
			slots += 1
	var mine := s.ovr_at_role(role)
	var ahead := 0
	var buried_by := 0
	for o in roster:
		if o == s or Scheme.best_role(o.stats) != role or o.ovr_at_role(role) <= mine:
			continue
		ahead += 1
		if o.potential_ovr() >= s.potential_ovr():
			buried_by += 1
	if ahead < slots:
		v += 5.0
	elif ahead == slots:
		v += 3.0
	else:
		var units := maxi(0, buried_by - slots + 1)
		var pen := 3.0 * float(units)
		if s.age <= 24 and s.dev >= 3:
			pen *= 0.5
		v -= pen
	v += draft_bonus(s)
	if s.contract != null and s.contract.years > 0:
		var c := minf(4.0, float(Contracts.dead_money_if_released(s)) / 4200.0)
		var surplus := float(Contracts.market_value(s) - s.contract.salary) * mini(s.contract.years, 3)
		c += clampf(surplus / 2800.0, -3.0, 3.0)
		v += clampf(c, -3.0, 5.0)
	return v


## Draft capital a front office protects: a pick from this draft (or last season's) by round,
## halved the year after, gone after that.
static func draft_bonus(s: Soldier) -> float:
	if s.draft_year <= 0 or s.draft_pick <= 0 or year_now <= 0:
		return 0.0
	var elapsed := year_now - s.draft_year
	if elapsed < 0 or elapsed > 2:
		return 0.0
	var rnd := clampi((s.draft_pick - 1) / maxi(1, league_size), 0, KEEP_DRAFT_BONUS.size() - 1)
	var b: float = KEEP_DRAFT_BONUS[rnd]
	return b * (0.5 if elapsed == 2 else 1.0)


## The soldier a front office would let go first (lowest keep_value).
func least_valuable() -> Soldier:
	var worst: Soldier = null
	var worst_v := INF
	for s in roster:
		var v := keep_value(s)
		if v < worst_v:
			worst_v = v
			worst = s
	return worst


## AI cut-down: releases the lowest keep_value soldiers until at `limit` (default ROSTER_SIZE).
## Returns the released soldiers (the caller books dead money and sends them to free agency).
func cut_to_limit(limit := ROSTER_SIZE) -> Array[Soldier]:
	var cut: Array[Soldier] = []
	while roster.size() > limit:
		var worst := least_valuable()
		release(worst)
		cut.append(worst)
	if roster.size() >= scheme.slot_ids().size():
		auto_lineup()
	return cut


func injured() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in roster:
		if s.is_injured():
			out.append(s)
	return out


func _search(vals: Array, same_as_prev: Array[bool], n: int, depth: int, picked: Array, used: int, score: float, best: Dictionary) -> void:
	if depth == vals.size():
		if score > best["score"]:
			best["score"] = score
			best["pick"] = picked.duplicate()
		return
	if score + best["bound"][depth] <= best["score"]:
		return
	var row: PackedFloat64Array = vals[depth]
	var start := 0
	# Identical adjacent slots (FM1/FM2) are interchangeable: enforce ordering to prune.
	if same_as_prev[depth]:
		start = picked[depth - 1] + 1
	for i in range(start, n):
		if used & (1 << i):
			continue
		picked.append(i)
		_search(vals, same_as_prev, n, depth + 1, picked, used | (1 << i), score + row[i], best)
		picked.pop_back()


## Team OVR: average best-role OVR of the whole roster (stars lift it, thin depth drags it).
func team_ovr() -> int:
	if roster.is_empty():
		return 0
	var total := 0
	for s in roster:
		total += s.best_ovr()
	return roundi(float(total) / roster.size())


## Average positional OVR of the starting five.
func starters_ovr() -> int:
	var total := 0
	var n := 0
	for slot_id in lineup:
		total += ovr_in_slot(lineup[slot_id], slot_id)
		n += 1
	return roundi(float(total) / max(n, 1))

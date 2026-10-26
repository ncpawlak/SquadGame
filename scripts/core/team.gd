class_name Team
extends RefCounted
## A team: roster of soldiers plus a lineup slotting 5 of them into the scheme.

const ROSTER_SIZE := 12

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
	var slot_ids := scheme.slot_ids()
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
		var role := scheme.role_for_slot(slot_ids[d])
		same_as_prev.append(d > 0 and scheme.role_for_slot(slot_ids[d - 1]) == role)
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
	lineup.clear()
	for i in slot_ids.size():
		lineup[slot_ids[i]] = pool[best["pick"][i]]


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


## How much a front office wants to keep `s` (higher = keep), in OVR-like points: current OVR,
## upside for young players, an age penalty from 30, depth at his best role (starters are kept,
## third-string and deeper are surplus), the dead money cutting him would leave and how good a
## deal his contract is for the years he has left.
func keep_value(s: Soldier) -> float:
	var v := float(s.best_ovr())
	v += float(s.potential_ovr() - s.best_ovr()) * clampf((28.0 - s.age) / 8.0, 0.0, 1.0) * 0.6
	if s.age >= 30:
		v -= float(s.age - 29) * 0.8
	var role := Scheme.best_role(s.stats)
	var slots := 0
	for slot_id in scheme.slot_ids():
		if scheme.role_for_slot(slot_id) == role:
			slots += 1
	var ahead := 0
	for o in roster:
		if o != s and Scheme.best_role(o.stats) == role and o.ovr_at_role(role) > s.ovr_at_role(role):
			ahead += 1
	if ahead < slots:
		v += 4.0
	elif ahead >= slots + 2:
		v -= 2.0 * float(ahead - slots - 1)
	if s.contract != null and s.contract.years > 0:
		v += minf(6.0, float(Contracts.dead_money_if_released(s)) / 4200.0)
		var surplus := float(Contracts.market_value(s) - s.contract.salary) * mini(s.contract.years, 3)
		v += clampf(surplus / 2800.0, -3.0, 3.0)
	return v


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

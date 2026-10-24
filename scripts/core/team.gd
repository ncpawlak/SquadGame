class_name Team
extends RefCounted
## A team: roster of soldiers plus a lineup slotting 5 of them into the scheme.

const ROSTER_SIZE := 12

var id: int
var name: String
var abbrev: String
var color: Color = Color.WHITE
var roster: Array[Soldier] = []
var scheme: Scheme = Scheme.power_front()
## slot_id (StringName) -> Soldier
var lineup: Dictionary = {}
## True for the team the user controls (skill points are not auto-spent).
var user_controlled := false
## Cap year -> dead money ($K) still owed to released soldiers.
var dead_money: Dictionary = {}


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
	_search(pool, slot_ids, 0, [], 0.0, best, consider_fatigue)
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
	var slot := slot_of(soldier)
	roster.erase(soldier)
	if slot != &"":
		lineup.erase(slot)
		fill_injured()


## AI cut-down: releases the lowest-value soldiers (current OVR plus some upside) until at
## `limit` (default ROSTER_SIZE). Returns the released soldiers.
func cut_to_limit(limit := ROSTER_SIZE) -> Array[Soldier]:
	var cut: Array[Soldier] = []
	while roster.size() > limit:
		var worst: Soldier = null
		var worst_v := INF
		for s in roster:
			var v := float(s.best_ovr()) + 0.5 * float(s.potential_ovr() - s.best_ovr())
			if v < worst_v:
				worst_v = v
				worst = s
		roster.erase(worst)
		cut.append(worst)
	auto_lineup()
	return cut


func injured() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in roster:
		if s.is_injured():
			out.append(s)
	return out


func _search(pool: Array[Soldier], slot_ids: Array[StringName], depth: int, picked: Array, score: float, best: Dictionary, fatigue: bool) -> void:
	if depth == slot_ids.size():
		if score > best["score"]:
			best["score"] = score
			best["pick"] = picked.duplicate()
		return
	var role := scheme.role_for_slot(slot_ids[depth])
	for i in pool.size():
		if picked.has(i):
			continue
		# Identical adjacent slots (FM1/FM2) are interchangeable: enforce ordering to prune.
		if depth > 0 and scheme.role_for_slot(slot_ids[depth - 1]) == role and i < picked[depth - 1]:
			continue
		var value := float(pool[i].ovr_at_role(role))
		if fatigue:
			value *= 1.0 - Conditioning.penalty(pool[i].fatigue)
		picked.append(i)
		_search(pool, slot_ids, depth + 1, picked, score + value, best, fatigue)
		picked.pop_back()


## Team OVR: average positional OVR of the starting five.
func team_ovr() -> int:
	var total := 0
	var n := 0
	for slot_id in lineup:
		total += ovr_in_slot(lineup[slot_id], slot_id)
		n += 1
	return roundi(float(total) / max(n, 1))

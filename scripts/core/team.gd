class_name Team
extends RefCounted
## A team: roster of soldiers plus a lineup slotting 5 of them into the scheme.

const ROSTER_SIZE := 8

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


## Exhaustively picks the 5 starters/slots that maximise total positional OVR.
func auto_lineup() -> void:
	var slot_ids := scheme.slot_ids()
	var best := {"score": -1, "pick": []}
	_search(slot_ids, 0, [], 0, best)
	lineup.clear()
	for i in slot_ids.size():
		lineup[slot_ids[i]] = roster[best["pick"][i]]


func _search(slot_ids: Array[StringName], depth: int, picked: Array, score: int, best: Dictionary) -> void:
	if depth == slot_ids.size():
		if score > best["score"]:
			best["score"] = score
			best["pick"] = picked.duplicate()
		return
	var role := scheme.role_for_slot(slot_ids[depth])
	for i in roster.size():
		if picked.has(i):
			continue
		# Identical adjacent slots (FM1/FM2) are interchangeable: enforce ordering to prune.
		if depth > 0 and scheme.role_for_slot(slot_ids[depth - 1]) == role and i < picked[depth - 1]:
			continue
		picked.append(i)
		_search(slot_ids, depth + 1, picked, score + roster[i].ovr_at_role(role), best)
		picked.pop_back()


## Team OVR: average positional OVR of the starting five.
func team_ovr() -> int:
	var total := 0
	var n := 0
	for slot_id in lineup:
		total += ovr_in_slot(lineup[slot_id], slot_id)
		n += 1
	return roundi(float(total) / max(n, 1))

class_name Prospect
extends RefCounted
## A draft prospect: a hidden Soldier plus what the user has scouted about it.
## Only name, age and listed position are known up front; ratings and potential stay hidden.

var soldier: Soldier
## The position the prospect says he plays. Phenoms rate well at every position.
var listed_role: Scheme.Role
var phenom := false
## Hidden class archetype, revealed in the draft recap: &"blue_chip" (elite all-round talent, a
## day-one starter), &"generational" (rarer still, mid-70s OVR and A potential),
## &"specialist" (one elite stat group, see `specialty`) or &"".
var standout: StringName = &""
var specialty: StringName = &""
## Scout points spent on this prospect (max Draft.MAX_POINTS_PER_PROSPECT).
var points := 0
## group -> Vector2i(low_tier, high_tier): the tier window revealed so far.
var reveals: Dictionary = {}
## group -> times scouted (indexes Draft.WINDOW_WIDTHS).
var scouts: Dictionary = {}
## League-wide read of his draft value (true value plus a fixed evaluation error).
var consensus := 0.0
## 1-based rank on the consensus big board; drives the projected round.
var projected_rank := 0
## Rough free "area scout" letter (A..F), class-relative and noisy.
var area_grade := "C"
## Starred by the user (favorites list, auto-scout goes first).
var favorite := false
var drafted_by: Team = null
var pick_number := 0


func is_available() -> bool:
	return drafted_by == null


func true_tier(group: StringName) -> int:
	return Draft.tier_of(soldier.group_rating(group))


## Groups that can still be narrowed by another scout.
func scoutable_groups() -> Array[StringName]:
	var out: Array[StringName] = []
	for g in Stats.GROUP_ORDER:
		if int(scouts.get(g, 0)) < Draft.WINDOW_WIDTHS.size():
			out.append(g)
	return out


func fully_scouted() -> bool:
	return points >= Draft.MAX_POINTS_PER_PROSPECT or scoutable_groups().is_empty()

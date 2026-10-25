class_name Scheme
extends RefCounted
## A formation: a set of position slots, each mapped to a role.
## Roles drive both a soldier's OVR at that slot and how they behave in the match sim.

enum Role { FRONTMAN, CENTER, FLEX }

const ROLE_NAMES := {
	Role.FRONTMAN: "Frontman",
	Role.CENTER: "Center",
	Role.FLEX: "Flex",
}

## OVR stat weights per role. Injury is intentionally absent until injuries are simulated.
const ROLE_WEIGHTS := {
	Role.FRONTMAN: {
		&"short_acc": 3.0, &"strength": 2.0, &"agility": 1.5, &"reload": 1.5,
		&"grouping": 1.5, &"composure": 1.5, &"awareness": 1.0, &"endurance": 1.0,
		&"medium_acc": 1.0, &"teamwork": 1.0, &"long_acc": 0.5, &"speed": 0.5,
		&"breach": 1.5, &"anchor": 0.5, &"obj_iq": 0.5,
	},
	Role.CENTER: {
		&"awareness": 3.0, &"medium_acc": 3.0, &"long_acc": 2.0, &"teamwork": 2.5,
		&"composure": 2.0, &"grouping": 1.5, &"short_acc": 1.0, &"strength": 1.0,
		&"agility": 1.0, &"reload": 1.0, &"endurance": 0.5,
		&"anchor": 1.5, &"obj_iq": 1.0, &"breach": 0.5,
	},
	Role.FLEX: {
		&"speed": 2.5, &"agility": 2.5, &"medium_acc": 2.0, &"endurance": 2.0,
		&"short_acc": 1.5, &"awareness": 1.5, &"reload": 1.5, &"grouping": 1.0,
		&"composure": 1.0, &"teamwork": 1.0,
		&"obj_iq": 1.5, &"breach": 1.0, &"anchor": 0.5,
	},
}

## Match-sim behaviour per role.
## distance_offset: metres added to the team-to-team distance (negative = further forward).
## exposure: relative chance of being picked as a target.
## engage_mod: relative change to the per-tick chance of getting a shot off (+0.3 = 30% more often).
## preferred_range: range band where the role gets an accuracy bonus.
const ROLE_BEHAVIOUR := {
	Role.FRONTMAN: {
		"distance_offset": -12.0, "exposure": 1.5, "engage_mod": 0.3,
		"preferred_range": &"short",
	},
	Role.CENTER: {
		"distance_offset": 10.0, "exposure": 0.8, "engage_mod": 0.0,
		"preferred_range": &"medium",
	},
	Role.FLEX: {
		# Before the flank lands, flexes are swung out wide; afterwards they collapse in.
		"distance_offset": 20.0, "flanked_distance_offset": -5.0,
		"exposure": 0.5, "flanked_exposure": 0.9,
		"engage_mod": -0.5, "flanked_engage_mod": 0.4,
		"preferred_range": &"",
	},
}

var id: StringName
var display_name: String
## Array of { "id": StringName, "label": String, "role": Role }
var slots: Array[Dictionary] = []


static func power_front() -> Scheme:
	var s := Scheme.new()
	s.id = &"power_front"
	s.display_name = "Swing"
	s.slots = [
		{"id": &"FM1", "label": "Frontman", "role": Role.FRONTMAN},
		{"id": &"FM2", "label": "Frontman", "role": Role.FRONTMAN},
		{"id": &"CTR", "label": "Center", "role": Role.CENTER},
		{"id": &"LFX", "label": "Left Flex", "role": Role.FLEX},
		{"id": &"RFX", "label": "Right Flex", "role": Role.FLEX},
	]
	return s


func slot_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for slot in slots:
		ids.append(slot["id"])
	return ids


func role_for_slot(slot_id: StringName) -> Role:
	for slot in slots:
		if slot["id"] == slot_id:
			return slot["role"]
	push_error("Unknown slot %s" % slot_id)
	return Role.FRONTMAN


func label_for_slot(slot_id: StringName) -> String:
	for slot in slots:
		if slot["id"] == slot_id:
			return slot["label"]
	return String(slot_id)


## OVR of a stat block at a role: weighted average of the role's stats.
static func ovr_for_role(stats: Dictionary, role: Role) -> int:
	var weights: Dictionary = ROLE_WEIGHTS[role]
	var total := 0.0
	var weight_sum := 0.0
	for stat in weights:
		total += float(stats[stat]) * weights[stat]
		weight_sum += weights[stat]
	return Stats.clamp_rating(total / weight_sum)


static func best_role(stats: Dictionary) -> Role:
	var best: Role = Role.FRONTMAN
	var best_ovr := -1
	for role in ROLE_WEIGHTS:
		var o := ovr_for_role(stats, role)
		if o > best_ovr:
			best_ovr = o
			best = role
	return best

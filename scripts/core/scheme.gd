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
		&"breach": 1.5, &"anchor": 0.5, &"obj_iq": 0.5, &"sway": 0.5,
	},
	Role.CENTER: {
		&"awareness": 3.0, &"medium_acc": 3.0, &"long_acc": 2.0, &"teamwork": 2.5,
		&"composure": 2.0, &"grouping": 1.5, &"short_acc": 1.0, &"strength": 1.0,
		&"agility": 1.0, &"reload": 1.0, &"endurance": 0.5,
		&"anchor": 1.5, &"obj_iq": 1.0, &"breach": 0.5, &"sway": 1.5,
	},
	Role.FLEX: {
		&"speed": 2.5, &"agility": 2.5, &"medium_acc": 2.0, &"endurance": 2.0,
		&"short_acc": 1.5, &"awareness": 1.5, &"reload": 1.5, &"grouping": 1.0,
		&"composure": 1.0, &"teamwork": 1.0,
		&"obj_iq": 1.5, &"breach": 1.0, &"anchor": 0.5, &"sway": 1.5,
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


## Every slot id used by any scheme and its role (slot ids mean the same thing in every scheme).
const SLOT_ROLES := {
	&"FM1": Role.FRONTMAN, &"FM2": Role.FRONTMAN, &"FM3": Role.FRONTMAN,
	&"CTR": Role.CENTER, &"CT2": Role.CENTER,
	&"LFX": Role.FLEX, &"LF2": Role.FLEX, &"RFX": Role.FLEX, &"RF2": Role.FLEX, &"MFX": Role.FLEX,
}
const SLOT_LABELS := {
	&"FM1": "Frontman", &"FM2": "Frontman", &"FM3": "Frontman", &"CTR": "Center", &"CT2": "Center",
	&"LFX": "Left Flex", &"LF2": "Left Flex", &"RFX": "Right Flex", &"RF2": "Right Flex", &"MFX": "Mid Flex",
}

const IDS: Array[StringName] = [&"power_front", &"wide_left", &"wide_right", &"wall", &"spread", &"pack"]
const NAMES := {
	&"power_front": "Swing", &"wide_left": "Wide-Left", &"wide_right": "Wide-Right",
	&"wall": "Wall", &"spread": "Spread", &"pack": "Pack",
}
const BLURBS := {
	&"power_front": "Balanced: 2 frontmen, a center, a flex on each side. No strengths, no weaknesses.",
	&"wide_left": "Overloads the left flank. Strong vs Wall; weak vs Spread and Pack.",
	&"wide_right": "Overloads the right flank. Strong vs Wall; weak vs Spread and Pack.",
	&"wall": "3 frontmen push the middle. Strong vs Pack and on the hill; weak vs Wide and Spread.",
	&"spread": "4 flexes stretch both flanks. Strong vs Wall and Wide; weak vs Pack and on the hill.",
	&"pack": "Tight mid-range core with 2 centers. Strong vs Spread and Wide; weak vs Wall.",
}

## Small scheme-vs-scheme accuracy edge (ratings still decide matches). Missing pairs are neutral.
const MATCHUPS := {
	&"wide_left": {&"wall": 0.025, &"spread": -0.025, &"pack": -0.02},
	&"wide_right": {&"wall": 0.025, &"spread": -0.025, &"pack": -0.02},
	&"wall": {&"wide_left": -0.025, &"wide_right": -0.025, &"spread": -0.025, &"pack": 0.025},
	&"spread": {&"wide_left": 0.025, &"wide_right": 0.025, &"wall": 0.025, &"pack": -0.02},
	&"pack": {&"wide_left": 0.02, &"wide_right": 0.02, &"spread": 0.02, &"wall": -0.025},
}
## Extra edge on King of the Hill.
const KOTH_EDGE := {&"wall": 0.02, &"spread": -0.02}

## Team-0 frame layout per scheme and slot (team 1 is the point reflection):
## spawn, hold (deathmatch spot), watch (KOTH overwatch) for frontmen/centers;
## flank side (-1 left, +1 right, 0 picks a side each life) and lane (1 trails the lane-0 flex) for flexes;
## ui = formation-card position on the lineup page.
const LAYOUTS := {
	&"power_front": {
		&"FM1": {"spawn": Vector2(-40, -4), "hold": Vector2(-6, -9), "watch": Vector2(-10, -9), "ui": Vector2(300, 10)},
		&"FM2": {"spawn": Vector2(-40, 4), "hold": Vector2(-6, 9), "watch": Vector2(-10, 9), "ui": Vector2(560, 10)},
		&"CTR": {"spawn": Vector2(-44, 0), "hold": Vector2(-25, 0), "watch": Vector2(-21, 0), "ui": Vector2(430, 250)},
		&"LFX": {"spawn": Vector2(-41, -19), "flank": -1, "ui": Vector2(20, 120)},
		&"RFX": {"spawn": Vector2(-41, 19), "flank": 1, "ui": Vector2(840, 120)},
	},
	&"wide_left": {
		&"FM1": {"spawn": Vector2(-40, -4), "hold": Vector2(-6, -9), "watch": Vector2(-10, -9), "ui": Vector2(470, 10)},
		&"FM2": {"spawn": Vector2(-40, 4), "hold": Vector2(-6, 9), "watch": Vector2(-10, 9), "ui": Vector2(730, 10)},
		&"CTR": {"spawn": Vector2(-44, 0), "hold": Vector2(-25, 0), "watch": Vector2(-21, 0), "ui": Vector2(600, 250)},
		&"LFX": {"spawn": Vector2(-41, -19), "flank": -1, "ui": Vector2(20, 60)},
		&"LF2": {"spawn": Vector2(-44, -13), "flank": -1, "lane": 1, "ui": Vector2(200, 230)},
	},
	&"wide_right": {
		&"FM1": {"spawn": Vector2(-40, -4), "hold": Vector2(-6, -9), "watch": Vector2(-10, -9), "ui": Vector2(130, 10)},
		&"FM2": {"spawn": Vector2(-40, 4), "hold": Vector2(-6, 9), "watch": Vector2(-10, 9), "ui": Vector2(390, 10)},
		&"CTR": {"spawn": Vector2(-44, 0), "hold": Vector2(-25, 0), "watch": Vector2(-21, 0), "ui": Vector2(260, 250)},
		&"RFX": {"spawn": Vector2(-41, 19), "flank": 1, "ui": Vector2(840, 60)},
		&"RF2": {"spawn": Vector2(-44, 13), "flank": 1, "lane": 1, "ui": Vector2(660, 230)},
	},
	&"wall": {
		&"FM1": {"spawn": Vector2(-40, -5), "hold": Vector2(-6, -9), "watch": Vector2(-10, -9), "ui": Vector2(170, 0)},
		&"FM2": {"spawn": Vector2(-39, 0), "hold": Vector2(-8, 0), "watch": Vector2(-11, 0), "ui": Vector2(430, 0)},
		&"FM3": {"spawn": Vector2(-40, 5), "hold": Vector2(-6, 9), "watch": Vector2(-10, 9), "ui": Vector2(690, 0)},
		&"MFX": {"spawn": Vector2(-42, 0), "flank": 0, "ui": Vector2(430, 228)},
		&"CTR": {"spawn": Vector2(-45, 0), "hold": Vector2(-25, 0), "watch": Vector2(-21, 0), "ui": Vector2(430, 456)},
	},
	&"spread": {
		&"LFX": {"spawn": Vector2(-41, -19), "flank": -1, "ui": Vector2(20, 40)},
		&"LF2": {"spawn": Vector2(-44, -13), "flank": -1, "lane": 1, "ui": Vector2(190, 230)},
		&"CTR": {"spawn": Vector2(-44, 0), "hold": Vector2(-25, 0), "watch": Vector2(-21, 0), "ui": Vector2(430, 120)},
		&"RF2": {"spawn": Vector2(-44, 13), "flank": 1, "lane": 1, "ui": Vector2(670, 230)},
		&"RFX": {"spawn": Vector2(-41, 19), "flank": 1, "ui": Vector2(840, 40)},
	},
	&"pack": {
		&"FM1": {"spawn": Vector2(-38, -4), "hold": Vector2(-6, -9), "watch": Vector2(-10, -9), "ui": Vector2(300, 0)},
		&"FM2": {"spawn": Vector2(-38, 4), "hold": Vector2(-6, 9), "watch": Vector2(-10, 9), "ui": Vector2(560, 0)},
		&"MFX": {"spawn": Vector2(-41, 0), "flank": 0, "ui": Vector2(430, 228)},
		&"CTR": {"spawn": Vector2(-44, -4), "hold": Vector2(-25, -5), "watch": Vector2(-21, -5), "ui": Vector2(300, 456)},
		&"CT2": {"spawn": Vector2(-44, 4), "hold": Vector2(-25, 5), "watch": Vector2(-21, 5), "ui": Vector2(560, 456)},
	},
}
## Slot order per scheme (also the order the lineup search fills them).
const ORDER := {
	&"power_front": [&"FM1", &"FM2", &"CTR", &"LFX", &"RFX"],
	&"wide_left": [&"FM1", &"FM2", &"CTR", &"LFX", &"LF2"],
	&"wide_right": [&"FM1", &"FM2", &"CTR", &"RFX", &"RF2"],
	&"wall": [&"FM1", &"FM2", &"FM3", &"CTR", &"MFX"],
	&"spread": [&"CTR", &"LFX", &"LF2", &"RFX", &"RF2"],
	&"pack": [&"FM1", &"FM2", &"CTR", &"CT2", &"MFX"],
}


static func power_front() -> Scheme:
	return by_id(&"power_front")


static func by_id(scheme_id: StringName) -> Scheme:
	if not ORDER.has(scheme_id):
		scheme_id = &"power_front"
	var s := Scheme.new()
	s.id = scheme_id
	s.display_name = NAMES[scheme_id]
	for sid in ORDER[scheme_id]:
		s.slots.append({"id": sid, "label": SLOT_LABELS[sid], "role": SLOT_ROLES[sid]})
	return s


static func all() -> Array[Scheme]:
	var out: Array[Scheme] = []
	for sid in IDS:
		out.append(by_id(sid))
	return out


func blurb() -> String:
	return BLURBS.get(id, "")


## Accuracy edge this scheme has over `other` (a few percent at most).
func edge_vs(other: Scheme, koth := false) -> float:
	var e: float = (MATCHUPS.get(id, {}) as Dictionary).get(other.id if other else &"", 0.0)
	if koth:
		e += KOTH_EDGE.get(id, 0.0)
	return clampf(e, -0.04, 0.04)


func _layout(slot_id: StringName) -> Dictionary:
	var by_slot: Dictionary = LAYOUTS.get(id, LAYOUTS[&"power_front"])
	return by_slot.get(slot_id, {})


func spawn_of(slot_id: StringName) -> Vector2:
	return _layout(slot_id).get("spawn", Vector2(-42, 0))


## Deathmatch hold spot (or KOTH overwatch with `koth`) for frontmen and centers.
func hold_of(slot_id: StringName, koth := false) -> Vector2:
	var l := _layout(slot_id)
	return l.get("watch" if koth else "hold", Vector2(-21, 0) if koth else Vector2(-25, 0))


## -1 left, +1 right, 0 = picks a side each life.
func flank_side(slot_id: StringName) -> int:
	return int(_layout(slot_id).get("flank", 0))


func flank_lane(slot_id: StringName) -> int:
	return int(_layout(slot_id).get("lane", 0))


func ui_pos(slot_id: StringName) -> Vector2:
	return _layout(slot_id).get("ui", Vector2.ZERO)


func count_role(role: Role) -> int:
	var n := 0
	for slot in slots:
		if slot["role"] == role:
			n += 1
	return n


## e.g. "2 Frontmen · Center · 2 Flex"
func shape_text() -> String:
	var parts: Array[String] = []
	for r in [Role.FRONTMAN, Role.CENTER, Role.FLEX]:
		var n := count_role(r)
		if n == 0:
			continue
		if n == 1:
			parts.append(ROLE_NAMES[r])
		else:
			parts.append("%d %s" % [n, {Role.FRONTMAN: "Frontmen", Role.CENTER: "Centers", Role.FLEX: "Flex"}[r]])
	return " · ".join(parts)


func slot_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for slot in slots:
		ids.append(slot["id"])
	return ids


func role_for_slot(slot_id: StringName) -> Role:
	for slot in slots:
		if slot["id"] == slot_id:
			return slot["role"]
	return SLOT_ROLES.get(slot_id, Role.FRONTMAN)


func label_for_slot(slot_id: StringName) -> String:
	for slot in slots:
		if slot["id"] == slot_id:
			return slot["label"]
	return SLOT_LABELS.get(slot_id, String(slot_id))


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

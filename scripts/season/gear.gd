class_name Gear
extends RefCounted
## Career-mode gear (#141): six slots, fifteen sponsor brands (three per brand tier), each brand selling a full line.
## An item gives bonuses on 1-4 stats from its slot's pool: the sponsor tier sets the ladder of values and how many stats,
## and the gear type sets the breadth (the rifle and attachments are specialized, one stat fewer). Gear is additive:
## effective rating = base + gear (see Soldier.set_gear_bonus), so changing it re-rates the player. Items come from
## sponsor deals (see Sponsors). A pure data / rules class: nothing here touches the league.

const HELMET := &"helmet"
const VEST := &"vest"
const RIFLE := &"rifle"
const ATTACHMENTS := &"attachments"
const BOOTS := &"boots"
const HEADSET := &"headset"
const SLOTS: Array[StringName] = [HELMET, VEST, RIFLE, ATTACHMENTS, BOOTS, HEADSET]
const SLOT_LABELS := {HELMET: "Helmet", VEST: "Vest", RIFLE: "Rifle", ATTACHMENTS: "Attachments", BOOTS: "Boots", HEADSET: "Headset"}
const SLOT_NOUN := {HELMET: "Helm", VEST: "Plate Carrier", RIFLE: "Rifle", ATTACHMENTS: "Optic Kit", BOOTS: "Boots", HEADSET: "Comms Headset"}
const SLOT_POOLS := {
	HELMET: [Stats.AWARENESS, Stats.COMPOSURE, Stats.TOUGHNESS, Stats.INJURY],
	VEST: [Stats.TOUGHNESS, Stats.INJURY, Stats.STRENGTH, Stats.ENDURANCE],
	RIFLE: [Stats.SHORT_ACC, Stats.MEDIUM_ACC, Stats.LONG_ACC, Stats.GROUPING],
	ATTACHMENTS: [Stats.SWAY, Stats.RELOAD, Stats.GROUPING, Stats.LONG_ACC],
	BOOTS: [Stats.SPEED, Stats.AGILITY, Stats.ENDURANCE, Stats.STRENGTH],
	HEADSET: [Stats.TEAMWORK, Stats.OBJ_IQ, Stats.ANCHOR, Stats.BREACH],
}
## Slots whose items carry one stat fewer (minimum 1) but keep the top values.
const SPECIALIZED: Array[StringName] = [RIFLE, ATTACHMENTS]

## Bonus ladders by sponsor tier (index = brand tier 0 Unknown .. 4 Icon), highest first.
## Values step down by 1 from the top stat.
const LADDERS := [[3], [5, 4], [8, 7, 5], [10, 9, 8, 7], [13, 12, 10, 9]]
## Brand needed for each sponsor tier (brand points, see WeeklyPlan.BRAND_TIER_SIZE).
const TIER_BRAND := [0.0, 20.0, 40.0, 60.0, 80.0]
## Tuning: multiplies every ladder value (rounded). 1.0 = the spec ladders.
static var scale := 1.0
const STAT_CAP := 15  # total gear bonus on any one stat
const SET_PIECES := 3  # items from one brand that wake its set bonus (+1 on its lead stat)

const LEANS := {
	&"mixed": [],
	&"mobility": [Stats.SPEED, Stats.AGILITY, Stats.ENDURANCE, Stats.STRENGTH],
	&"balanced": [Stats.AWARENESS, Stats.ENDURANCE, Stats.SHORT_ACC, Stats.COMPOSURE],
	&"defense": [Stats.TOUGHNESS, Stats.INJURY, Stats.STRENGTH, Stats.COMPOSURE],
	&"precision": [Stats.LONG_ACC, Stats.MEDIUM_ACC, Stats.SHORT_ACC, Stats.GROUPING],
	&"awareness": [Stats.AWARENESS, Stats.COMPOSURE, Stats.TEAMWORK, Stats.OBJ_IQ],
	&"handling": [Stats.RELOAD, Stats.GROUPING, Stats.SWAY, Stats.SHORT_ACC],
}
## id, display name (parodies of real brands), sponsor tier, lean.
const BRANDS := [
	{"id": &"haynes", "name": "Haynes Tactical", "tier": 0, "lean": &"mixed"},
	{"id": &"champ", "name": "Champ Gear", "tier": 0, "lean": &"mobility"},
	{"id": &"boom", "name": "Fruit of the Boom", "tier": 0, "lean": &"defense"},
	{"id": &"fyla", "name": "Fyla", "tier": 1, "lean": &"mobility"},
	{"id": &"rebook", "name": "Rebook", "tier": 1, "lean": &"balanced"},
	{"id": &"timberlane", "name": "Timberlane", "tier": 1, "lean": &"defense"},
	{"id": &"overarmour", "name": "Over Armour", "tier": 2, "lean": &"defense"},
	{"id": &"pooma", "name": "Pooma", "tier": 2, "lean": &"mobility"},
	{"id": &"smyth", "name": "Smyth & Weston", "tier": 2, "lean": &"precision"},
	{"id": &"nyke", "name": "Nyke", "tier": 3, "lean": &"mobility"},
	{"id": &"addidas", "name": "Addidas", "tier": 3, "lean": &"balanced"},
	{"id": &"oakly", "name": "Oakly Tactical", "tier": 3, "lean": &"awareness"},
	{"id": &"glok", "name": "Glok Custom", "tier": 4, "lean": &"handling"},
	{"id": &"sigsawyer", "name": "Sig Sawyer", "tier": 4, "lean": &"precision"},
	{"id": &"cryo", "name": "Cryo Precision", "tier": 4, "lean": &"defense"},
]


static func brand(id: StringName) -> Dictionary:
	for b in BRANDS:
		if b["id"] == id:
			return b
	return {}


static func brands_in_tier(tier: int) -> Array:
	return BRANDS.filter(func(b): return int(b["tier"]) == tier)


static func tier_name(tier: int) -> String:
	return WeeklyPlan.BRAND_TIERS[clampi(tier, 0, WeeklyPlan.BRAND_TIERS.size() - 1)]


## The sponsor tier a brand value unlocks (0 Unknown .. 4 Icon).
static func tier_for_brand(value: float) -> int:
	var t := 0
	for i in TIER_BRAND.size():
		if value >= float(TIER_BRAND[i]):
			t = i
	return t


## The stats an item of `brand_id` in `slot` boosts, lean-favoured first, then the slot's pool order.
static func item_stats(brand_id: StringName, slot: StringName) -> Array:
	var b := brand(brand_id)
	var ladder: Array = LADDERS[int(b["tier"])]
	var n := ladder.size()
	if SPECIALIZED.has(slot):
		n = maxi(1, n - 1)
	# Brands of one tier never share an item: bump the seed until the order differs from the earlier brands'.
	var taken: Array = []
	for other in brands_in_tier(int(b["tier"])):
		if other["id"] == brand_id:
			break
		taken.append(_ordered(other["id"], slot, taken, n))
	return _ordered(brand_id, slot, taken, n)


## Every item has its own stat order: the brand's lean picks the top stat, the rest are a seeded shuffle.
static func _ordered(brand_id: StringName, slot: StringName, taken: Array, n: int) -> Array:
	var lean: Array = LEANS.get(brand(brand_id).get("lean", &"mixed"), [])
	var pool: Array = SLOT_POOLS[slot]
	var attempt := 0
	while true:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s/%s/%d" % [brand_id, slot, attempt])
		var rest: Array = pool.duplicate()
		var ordered: Array = []
		for st in lean:
			if pool.has(st):
				ordered.append(st)
				rest.erase(st)
				break
		for i in range(rest.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = rest[i]
			rest[i] = rest[j]
			rest[j] = tmp
		ordered.append_array(rest)
		var out: Array = ordered.slice(0, n)
		if not taken.has(out) or attempt > 40:
			return out
		attempt += 1
	return []


## One item: {brand, brand_name, slot, tier, name, bonus: {stat: value}}.
static func item(brand_id: StringName, slot: StringName) -> Dictionary:
	var b := brand(brand_id)
	if b.is_empty() or not SLOTS.has(slot):
		return {}
	var ladder: Array = LADDERS[int(b["tier"])]
	var bonus := {}
	var stats := item_stats(brand_id, slot)
	for i in stats.size():
		bonus[stats[i]] = maxi(1, roundi(float(ladder[i]) * scale))
	return {"brand": brand_id, "brand_name": b["name"], "slot": slot, "tier": int(b["tier"]),
		"name": "%s %s" % [b["name"], SLOT_NOUN[slot]], "bonus": bonus}


## Sum of equipped items' bonuses (plus brand set bonuses), per-stat capped at STAT_CAP.
static func total_bonus(slots: Dictionary, influence: Dictionary = {}) -> Dictionary:
	var out := {}
	var per_brand := {}
	for slot in slots:
		var it: Dictionary = slots[slot]
		for st in it.get("bonus", {}):
			out[st] = int(out.get(st, 0)) + int(it["bonus"][st])
		per_brand[it["brand"]] = int(per_brand.get(it["brand"], 0)) + 1
	for id in per_brand:
		var lean: Array = LEANS.get(brand(id).get("lean", &"mixed"), [])
		if lean.is_empty():
			continue
		for part in set_parts(id, int(per_brand[id]), float(influence.get(id, 0.0))):
			out[lean[part[0]]] = int(out.get(lean[part[0]], 0)) + int(part[1])
	for st in out:
		out[st] = mini(int(out[st]), STAT_CAP)
	return out


## The set bonus of `pieces` items from one brand at this influence: [[lean index, points]]. 3 pieces +1 on the lead stat;
## partner influence (50+) makes it +2; ambassador influence (75+) with 5 pieces is +4 and +2 on the second lean stat.
static func set_parts(_brand_id: StringName, pieces: int, infl: float) -> Array:
	if pieces < SET_PIECES:
		return []
	if pieces >= 5 and infl >= 75.0:
		return [[0, 4], [1, 2]]
	if infl >= 50.0:
		return [[0, 2]]
	return [[0, 1]]


## The set bonus line for the loadout page ("" if none): "Over Armour set: +1 toughness".
static func set_text(slots: Dictionary, influence: Dictionary = {}) -> String:
	var per_brand := {}
	for slot in slots:
		per_brand[slots[slot]["brand"]] = int(per_brand.get(slots[slot]["brand"], 0)) + 1
	var parts: PackedStringArray = []
	for id in per_brand:
		var lean: Array = LEANS.get(brand(id).get("lean", &"mixed"), [])
		if lean.is_empty():
			continue
		var bits: PackedStringArray = []
		for part in set_parts(id, int(per_brand[id]), float(influence.get(id, 0.0))):
			bits.append("+%d %s" % [int(part[1]), Stats.LABELS[lean[part[0]]]])
		if not bits.is_empty():
			parts.append("%s set: %s" % [brand(id)["name"], ", ".join(bits)])
	return ", ".join(parts)


## Re-rates the soldier from what is equipped.
static func recalc(s: Soldier) -> void:
	s.set_gear_bonus(total_bonus(s.gear_slots, s.influence))


## Items the soldier can equip in `slot`: one per active deal that grants it, plus the ones he bought.
static func available(s: Soldier, slot: StringName) -> Array:
	var out: Array = []
	var seen := {}
	for d in s.deals:
		if Array(d["slots"]).has(slot) and not seen.has(d["brand"]):
			seen[d["brand"]] = true
			out.append(item(d["brand"], slot))
	for key in s.owned_gear:
		var parts := String(key).split(":")
		if StringName(parts[1]) == slot and not seen.has(StringName(parts[0])):
			seen[StringName(parts[0])] = true
			out.append(item(StringName(parts[0]), slot))
	return out


static func equip(s: Soldier, it: Dictionary) -> String:
	var slot: StringName = it.get("slot", &"")
	var ok := false
	for cand in available(s, slot):
		if cand["brand"] == it.get("brand"):
			ok = true
	if not ok:
		return "No deal gives you that item and you do not own it."
	s.gear_slots[slot] = it
	recalc(s)
	return ""


static func unequip(s: Soldier, slot: StringName) -> void:
	s.gear_slots.erase(slot)
	recalc(s)


## Drops anything equipped whose deal is gone (called when deals change), then re-rates.
static func prune(s: Soldier) -> void:
	for slot in s.gear_slots.keys():
		var keep := false
		for cand in available(s, slot):
			if cand["brand"] == s.gear_slots[slot]["brand"]:
				keep = true
		if not keep:
			s.gear_slots.erase(slot)
	recalc(s)


## Effective OVR with these items, for the loadout preview: {ovr, bonus}.
static func preview(s: Soldier, slots: Dictionary) -> int:
	var eff := s.base_stats().duplicate()
	var b := total_bonus(slots, s.influence)
	for st in b:
		eff[st] = Stats.clamp_rating(int(eff[st]) + int(b[st]))
	return Scheme.ovr_for_role(eff, Scheme.best_role(eff))

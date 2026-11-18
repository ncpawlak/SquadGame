class_name Gear
extends RefCounted
## Career-mode gear (#141): five slots, fifteen sponsor brands (three per brand tier), each brand selling a full line.
## An item gives bonuses on 1-4 stats from its slot's pool: the sponsor tier sets the ladder of values and how many stats,
## and the gear type sets the breadth (the rifle and attachments are specialized, one stat fewer). Gear is additive:
## effective rating = base + gear (see Soldier.set_gear_bonus), so changing it re-rates the player. Items come from
## sponsor deals (see Sponsors). A pure data / rules class: nothing here touches the league.

const HELMET := &"helmet"
const VEST := &"vest"
const RIFLE := &"rifle"
const ATTACHMENTS := &"attachments"
const BOOTS := &"boots"
const SLOTS: Array[StringName] = [HELMET, VEST, RIFLE, ATTACHMENTS, BOOTS]
const SLOT_LABELS := {HELMET: "Helmet", VEST: "Vest", RIFLE: "Rifle", ATTACHMENTS: "Attachments", BOOTS: "Boots"}
const SLOT_NOUN := {HELMET: "Helm", VEST: "Plate Carrier", RIFLE: "Rifle", ATTACHMENTS: "Optic Kit", BOOTS: "Boots"}
const SLOT_POOLS := {
	HELMET: [Stats.AWARENESS, Stats.COMPOSURE, Stats.TOUGHNESS, Stats.INJURY],
	VEST: [Stats.TOUGHNESS, Stats.INJURY, Stats.STRENGTH, Stats.ENDURANCE],
	RIFLE: [Stats.SHORT_ACC, Stats.MEDIUM_ACC, Stats.LONG_ACC, Stats.GROUPING],
	ATTACHMENTS: [Stats.SWAY, Stats.RELOAD, Stats.GROUPING, Stats.LONG_ACC],
	BOOTS: [Stats.SPEED, Stats.AGILITY, Stats.ENDURANCE, Stats.STRENGTH],
}
## Slots whose items carry one stat fewer (minimum 1) but keep the top values.
const SPECIALIZED: Array[StringName] = [RIFLE, ATTACHMENTS]

## Bonus ladders by sponsor tier (index = brand tier 0 Unknown .. 4 Icon), highest first.
const LADDERS := [[1], [2, 1], [3, 2, 1], [4, 3, 2, 1], [5, 4, 3, 2]]
## Brand needed for each sponsor tier (brand points, see WeeklyPlan.BRAND_TIER_SIZE).
const TIER_BRAND := [0.0, 20.0, 40.0, 60.0, 80.0]
const STAT_CAP := 10  # total gear bonus on any one stat
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
	var lean: Array = LEANS.get(b.get("lean", &"mixed"), [])
	var pool: Array = SLOT_POOLS[slot]
	var ordered: Array = []
	for st in lean:
		if pool.has(st):
			ordered.append(st)
	for st in pool:
		if not ordered.has(st):
			ordered.append(st)
	var ladder: Array = LADDERS[int(b["tier"])]
	var n := ladder.size()
	if SPECIALIZED.has(slot):
		n = maxi(1, n - 1)
	return ordered.slice(0, n)


## One item: {brand, brand_name, slot, tier, name, bonus: {stat: value}}.
static func item(brand_id: StringName, slot: StringName) -> Dictionary:
	var b := brand(brand_id)
	if b.is_empty() or not SLOTS.has(slot):
		return {}
	var ladder: Array = LADDERS[int(b["tier"])]
	var bonus := {}
	var stats := item_stats(brand_id, slot)
	for i in stats.size():
		bonus[stats[i]] = int(ladder[i])
	return {"brand": brand_id, "brand_name": b["name"], "slot": slot, "tier": int(b["tier"]),
		"name": "%s %s" % [b["name"], SLOT_NOUN[slot]], "bonus": bonus}


## Sum of equipped items' bonuses (plus brand set bonuses), per-stat capped at STAT_CAP.
static func total_bonus(slots: Dictionary) -> Dictionary:
	var out := {}
	var per_brand := {}
	for slot in slots:
		var it: Dictionary = slots[slot]
		for st in it.get("bonus", {}):
			out[st] = int(out.get(st, 0)) + int(it["bonus"][st])
		per_brand[it["brand"]] = int(per_brand.get(it["brand"], 0)) + 1
	for id in per_brand:
		if int(per_brand[id]) >= SET_PIECES:
			var lean: Array = LEANS.get(brand(id).get("lean", &"mixed"), [])
			if not lean.is_empty():
				out[lean[0]] = int(out.get(lean[0], 0)) + 1
	for st in out:
		out[st] = mini(int(out[st]), STAT_CAP)
	return out


## The set bonus line for the loadout page ("" if none): "Over Armour set: +1 toughness".
static func set_text(slots: Dictionary) -> String:
	var per_brand := {}
	for slot in slots:
		per_brand[slots[slot]["brand"]] = int(per_brand.get(slots[slot]["brand"], 0)) + 1
	var parts: PackedStringArray = []
	for id in per_brand:
		if int(per_brand[id]) >= SET_PIECES:
			var lean: Array = LEANS.get(brand(id).get("lean", &"mixed"), [])
			if not lean.is_empty():
				parts.append("%s set: +1 %s" % [brand(id)["name"], Stats.LABELS[lean[0]]])
	return ", ".join(parts)


## Re-rates the soldier from what is equipped.
static func recalc(s: Soldier) -> void:
	s.set_gear_bonus(total_bonus(s.gear_slots))


## Items the soldier can equip in `slot`: one per active deal that covers it.
static func available(s: Soldier, slot: StringName) -> Array:
	var out: Array = []
	for d in s.deals:
		if Array(d["slots"]).has(slot):
			out.append(item(d["brand"], slot))
	return out


static func equip(s: Soldier, it: Dictionary) -> String:
	var slot: StringName = it.get("slot", &"")
	var ok := false
	for cand in available(s, slot):
		if cand["brand"] == it.get("brand"):
			ok = true
	if not ok:
		return "No sponsor deal covers that item."
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
	var b := total_bonus(slots)
	for st in b:
		eff[st] = Stats.clamp_rating(int(eff[st]) + int(b[st]))
	return Scheme.ovr_for_role(eff, Scheme.best_role(eff))

class_name Assets
extends RefCounted
## What the career player spends cash on (#141, first pass). Four things, each with a purpose:
## - Private coach (levels 1-3): more XP every week. Costs a retainer.
## - Agent (levels 1-3): more brand from every game, better sponsor pay. Costs a retainer.
## - Rental property (up to 3): steady rent, paid weekly in season. Safe.
## - Business (up to 2): a season's profit is a gamble (a loss is possible) but the average beats rent.
## Retainers are paid weekly in season; when cash runs out the service drops a level. Property and businesses can be
## sold for part of the price. Cash is in dollars (see Sponsors.money_text).

const COACH := &"coach"
const AGENT := &"agent"
const PROPERTY := &"property"
const BUSINESS := &"business"
const SPEC_IDS: Array[StringName] = [&"spec_accuracy", &"spec_handling", &"spec_physicality", &"spec_mentality", &"spec_objective"]
const SERVICES: Array[StringName] = [COACH, AGENT, &"spec_accuracy", &"spec_handling", &"spec_physicality", &"spec_mentality", &"spec_objective"]
const HOLDINGS: Array[StringName] = [PROPERTY, BUSINESS]

## Service levels: price to move up to it (the old level's price is credited), the yearly retainer, and the effect.
const SPEC_LEVELS := [
	{"name": "Assistant trainer", "price": 1500000, "upkeep": 500000, "meter": 1.15},
	{"name": "Specialist trainer", "price": 6000000, "upkeep": 1750000, "meter": 1.30},
	{"name": "Elite specialist", "price": 20000000, "upkeep": 5000000, "meter": 1.50},
]
const LEVELS := {
	&"spec_accuracy": SPEC_LEVELS,
	&"spec_handling": SPEC_LEVELS,
	&"spec_physicality": SPEC_LEVELS,
	&"spec_mentality": SPEC_LEVELS,
	&"spec_objective": SPEC_LEVELS,
	COACH: [
		{"name": "Position coach", "price": 1500000, "upkeep": 500000, "xp": 1.10},
		{"name": "Skills coach", "price": 6000000, "upkeep": 1750000, "xp": 1.20},
		{"name": "Elite performance staff", "price": 20000000, "upkeep": 5000000, "xp": 1.35},
	],
	AGENT: [
		{"name": "Local agent", "price": 2500000, "upkeep": 800000, "brand": 1.15, "pay": 1.05},
		{"name": "Full-service agency", "price": 9000000, "upkeep": 3000000, "brand": 1.30, "pay": 1.10},
		{"name": "PR firm and agency", "price": 30000000, "upkeep": 8000000, "brand": 1.50, "pay": 1.15},
	],
}
const HOLDING := {
	PROPERTY: {"name": "Rental property", "price": 25000000, "max": 3, "yield": 0.07, "low": 0.07, "high": 0.07},
	BUSINESS: {"name": "Business", "price": 50000000, "max": 2, "yield": 0.10, "low": -0.05, "high": 0.25},
}
const SELL_SHARE := 0.8


static func level(p: Soldier, id: StringName) -> int:
	return int(p.assets.get(id, 0))


static func count(p: Soldier, id: StringName) -> int:
	return int(p.assets.get(id, 0))


static func _lv(p: Soldier, id: StringName) -> Dictionary:
	var n := level(p, id)
	if n <= 0:
		return {}
	return LEVELS[id][n - 1]


static func xp_mult(p: Soldier) -> float:
	return float(_lv(p, COACH).get("xp", 1.0))


static func brand_mult(p: Soldier) -> float:
	return float(_lv(p, AGENT).get("brand", 1.0))


## The group a specialist trainer id works on (&"" for the others).
static func spec_group(id: StringName) -> StringName:
	return StringName(String(id).trim_prefix("spec_")) if SPEC_IDS.has(id) else &""


## How fast a group's ceiling meter fills with this trainer: x1.15, x1.30 or x1.50.
static func meter_mult(p: Soldier, group: StringName) -> float:
	return float(_lv(p, StringName("spec_" + String(group))).get("meter", 1.0))


static func title(id: StringName) -> String:
	if id == COACH:
		return "Private coach"
	if id == AGENT:
		return "Agent"
	return "%s trainer" % String(Stats.GROUP_LABELS[spec_group(id)])


static func pay_mult(p: Soldier) -> float:
	return float(_lv(p, AGENT).get("pay", 1.0))


## Retainers a year (dollars).
static func upkeep_yearly(p: Soldier) -> int:
	return int(_lv(p, COACH).get("upkeep", 0)) + int(_lv(p, AGENT).get("upkeep", 0))


## Rent a year (dollars): a business is not counted, its profit is a gamble.
static func rent_yearly(p: Soldier) -> int:
	return roundi(float(count(p, PROPERTY)) * float(HOLDING[PROPERTY]["price"]) * float(HOLDING[PROPERTY]["yield"]))


## What the next level of a service, or one more holding, costs now (0 when there is nothing to buy).
static func cost_of(p: Soldier, id: StringName) -> int:
	if SERVICES.has(id):
		var n := level(p, id)
		if n >= LEVELS[id].size():
			return 0
		var credit := int(LEVELS[id][n - 1]["price"]) if n > 0 else 0
		return int(LEVELS[id][n]["price"]) - credit
	return int(HOLDING[id]["price"])


## "" if he can buy the next level of a service, or one more holding.
static func buy_error(p: Soldier, id: StringName) -> String:
	if SERVICES.has(id):
		if level(p, id) >= LEVELS[id].size():
			return "Already the best."
	elif HOLDINGS.has(id):
		if count(p, id) >= int(HOLDING[id]["max"]):
			return "You own as many as you can manage."
	else:
		return "No such thing."
	var cost := cost_of(p, id)
	if p.cash < cost:
		return "You need %s." % Sponsors.money_text(cost)
	return ""


static func buy(season: Season, id: StringName) -> String:
	var p := season.player
	var err := buy_error(p, id)
	if err != "":
		return err
	var cost := cost_of(p, id)
	p.cash -= cost
	p.assets[id] = level(p, id) + 1
	var what := String(HOLDING[id]["name"]) if HOLDINGS.has(id) else String(LEVELS[id][level(p, id) - 1]["name"])
	season.player_notes.append({"year": season.year, "week": season.week, "text": "You bought: %s (%s)." % [what, Sponsors.money_text(cost)]})
	return ""


## Lets a service go one level (no refund) or sells one holding for SELL_SHARE of its price. Returns the cash got.
static func sell(season: Season, id: StringName) -> int:
	var p := season.player
	if level(p, id) <= 0:
		return 0
	p.assets[id] = level(p, id) - 1
	var got := 0
	if HOLDINGS.has(id):
		got = roundi(float(HOLDING[id]["price"]) * SELL_SHARE)
		p.cash += got
	return got


## One regular-season week: rent comes in, retainers go out. A retainer he cannot pay drops that service a level.
## Returns the net dollars.
static func weekly(season: Season) -> int:
	var p := season.player
	var rw := float(maxi(1, season.regular_weeks))
	var net := roundi(float(rent_yearly(p)) / rw)
	for id in SERVICES:
		var lv := _lv(p, id)
		if lv.is_empty():
			continue
		var fee := roundi(float(lv["upkeep"]) / rw)
		if p.cash + net >= fee:
			net -= fee
		else:
			p.assets[id] = level(p, id) - 1
			season.player_notes.append({"year": season.year, "week": season.week, "text": "You could not pay your %s: they let you go." % String(lv["name"]).to_lower()})
	p.cash += net
	return net


## A season's business profit (or loss), settled once at the end.
static func season_end(season: Season) -> int:
	var p := season.player
	if p == null or not season.player_mode or count(p, BUSINESS) <= 0:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([season.league.league_seed, season.year, "business"])
	var total := 0
	for i in count(p, BUSINESS):
		var roll := rng.randf_range(float(HOLDING[BUSINESS]["low"]), float(HOLDING[BUSINESS]["high"]))
		total += roundi(float(HOLDING[BUSINESS]["price"]) * roll)
	p.cash += total
	season.player_notes.append({"year": season.year, "week": season.week, "text": "Your business%s %s %s this year." % ["es" if count(p, BUSINESS) > 1 else "", "made" if total >= 0 else "lost", Sponsors.money_text(absi(total))]})
	return total

class_name Sponsors
extends RefCounted
## Career-mode sponsor deals (#141). Sponsors come to the player; interest ("heat") is built from brand, recent
## performance, prospect value (draft slot, fading), dev stars and youth. A brand approaches when the heat passes its
## tier's threshold, and brand caps how high a tier can be interested. An offer covers some gear slots, pays yearly money
## and asks the player to keep his brand above a floor. The player can hold several deals as long as their slots do not
## overlap. Deals pay and tick at the end of each season; an ended or broken deal takes its gear back.

## Heat needed for each sponsor tier to be interested.
const TIER_HEAT := [5.0, 25.0, 50.0, 75.0, 95.0]
## Yearly money (thousands) per covered slot, by tier.
const TIER_PAY := [4, 12, 30, 70, 150]
const MAX_OFFERS := 4
const STYLE_MONEY := &"money"
const STYLE_GEAR := &"gear"
const PROSPECT_FADE := 0.25  # per season in the league
const PROSPECT_RANKS := 40.0


## Seasons since the first logged game year (0 in the rookie year).
static func seasons_in(season: Season) -> int:
	var first := season.year
	for e in season.player_log:
		first = mini(first, int(e.get("year", season.year)))
	return maxi(0, season.year - first)


static func prospect_value(season: Season) -> float:
	var pick := season.player_pick
	if pick <= 0:
		return 0.0
	var raw := maxf(0.0, PROSPECT_RANKS - float(pick))
	return raw * maxf(0.0, 1.0 - PROSPECT_FADE * float(seasons_in(season)))


## Last completed season's graded average mapped to 0-40 (nothing played = 0).
static func performance_value(season: Season) -> float:
	var p := season.player
	var year := season.year
	var sm := PlayerGrade.summary(PlayerGrade.log_for(season, year))
	if int(sm["games"]) < 3:
		return 0.0
	return clampf((float(sm["avg"]) - 60.0), 0.0, 40.0)


## What sponsors see: {heat, parts: [[label, value]]}.
static func heat(season: Season) -> Dictionary:
	var p := season.player
	var parts: Array = []
	parts.append(["Brand", p.brand * 0.6])
	parts.append(["Performance", performance_value(season)])
	parts.append(["Prospect value", prospect_value(season)])
	parts.append(["Dev stars", float(p.dev - 1) * 4.0 + (4.0 if p.age <= 21 else 0.0)])
	var total := 0.0
	for x in parts:
		total += float(x[1])
	return {"heat": total, "parts": parts}


## The highest sponsor tier that can be interested: brand tier, plus one for a real prospect.
static func tier_ceiling(season: Season) -> int:
	var t := Gear.tier_for_brand(season.player.brand)
	if prospect_value(season) >= 25.0:
		t += 1
	return mini(t, Gear.TIER_BRAND.size() - 1)


static func covered(p: Soldier) -> Array:
	var out: Array = []
	for d in p.deals:
		for s in d["slots"]:
			if not out.has(s):
				out.append(s)
	return out


static func holds(p: Soldier, brand_id: StringName) -> bool:
	for d in p.deals:
		if d["brand"] == brand_id:
			return true
	return false


static func _terms(brand_id: StringName, margin: float, style: StringName, rng: RandomNumberGenerator) -> Dictionary:
	var b := Gear.brand(brand_id)
	var tier := int(b["tier"])
	var n := clampi(1 + int(margin / 15.0), 1, 5)
	if style == STYLE_GEAR:
		n = mini(5, n + 1)
	else:
		n = maxi(1, n - 1)
	var slots: Array = Gear.SLOTS.duplicate()
	# Stable shuffle from the rng so the same offer is reproducible.
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp
	var picked: Array = slots.slice(0, n)
	var pay := float(TIER_PAY[tier]) * float(n) * (1.4 if style == STYLE_MONEY else 0.6)
	return {"slots": picked, "money": roundi(pay), "years": rng.randi_range(1, 3),
		"floor": maxf(0.0, float(Gear.TIER_BRAND[tier]) - 10.0)}


## Brands that approach now, added to season.player.offers (up to MAX_OFFERS). Call at the season's end and on a tier-up.
static func refresh(season: Season) -> int:
	var p := season.player
	if p == null or not season.player_mode or PlayerLegacy.retired(season):
		return 0
	var h: float = float(heat(season)["heat"])
	var ceiling := tier_ceiling(season)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([season.league.league_seed, season.year, season.week, p.offers.size(), p.deals.size(), roundi(h)])
	var added := 0
	for b in Gear.BRANDS:
		if p.offers.size() >= MAX_OFFERS:
			break
		var tier := int(b["tier"])
		if tier > ceiling or h < float(TIER_HEAT[tier]):
			continue
		if holds(p, b["id"]) or _has_offer(p, b["id"]):
			continue
		if rng.randf() > 0.5:
			continue
		var style := STYLE_MONEY if rng.randf() < 0.5 else STYLE_GEAR
		var t := _terms(b["id"], h - float(TIER_HEAT[tier]), style, rng)
		t["brand"] = b["id"]
		t["style"] = style
		t["countered"] = false
		t["expires"] = season.year + 1
		t["reason"] = _reason(season, tier)
		p.offers.append(t)
		added += 1
	if added > 0:
		season.player_notes.append({"year": season.year, "week": season.week, "text": "%d sponsor%s want%s to talk." % [added, "" if added == 1 else "s", "s" if added == 1 else ""]})
	return added


static func _has_offer(p: Soldier, brand_id: StringName) -> bool:
	for o in p.offers:
		if o["brand"] == brand_id:
			return true
	return false


static func _reason(season: Season, tier: int) -> String:
	var parts: Array = heat(season)["parts"]
	parts.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	match String(parts[0][0]):
		"Prospect value": return "They like your draft slot."
		"Performance": return "They like how you have been playing."
		"Dev stars": return "They see a rising talent."
	return "Your brand reached %s." % Gear.tier_name(Gear.tier_for_brand(season.player.brand))


## "" if the offer can be signed now, else why not.
static func accept_error(p: Soldier, offer: Dictionary) -> String:
	for s in offer["slots"]:
		if covered(p).has(s):
			return "Your %s is already covered by another deal." % String(Gear.SLOT_LABELS[s]).to_lower()
	return ""


static func accept(season: Season, offer: Dictionary) -> String:
	var p := season.player
	var err := accept_error(p, offer)
	if err != "":
		return err
	p.deals.append({"brand": offer["brand"], "slots": offer["slots"].duplicate(), "money": int(offer["money"]), "years_left": int(offer["years"]),
		"floor": float(offer["floor"]), "signed": season.year})
	p.offers.erase(offer)
	season.player_notes.append({"year": season.year, "week": season.week, "text": "You signed with %s." % Gear.brand(offer["brand"])["name"]})
	# Equip what the deal gives right away into empty slots.
	for s in offer["slots"]:
		if not p.gear_slots.has(s):
			p.gear_slots[s] = Gear.item(offer["brand"], s)
	Gear.recalc(p)
	return ""


static func decline(season: Season, offer: Dictionary) -> void:
	season.player.offers.erase(offer)


## Ask for the other style (money instead of gear or the reverse). Once per offer; it can fall through.
## Returns "countered", "withdrawn" or "".
static func counter(season: Season, offer: Dictionary) -> String:
	if bool(offer["countered"]):
		return ""
	var p := season.player
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([season.league.league_seed, season.year, str(offer["brand"]), p.offers.size()])
	var margin := float(heat(season)["heat"]) - float(TIER_HEAT[int(Gear.brand(offer["brand"])["tier"])])
	if rng.randf() > 0.65 + margin / 100.0:
		p.offers.erase(offer)
		return "withdrawn"
	var style := STYLE_GEAR if offer["style"] == STYLE_MONEY else STYLE_MONEY
	var t := _terms(offer["brand"], margin, style, rng)
	for k in ["slots", "money"]:
		offer[k] = t[k]
	offer["style"] = style
	offer["countered"] = true
	return "countered"


## End of a season: pay the deals, drop the ended or broken ones, expire old offers, then see who calls.
static func season_end(season: Season) -> Dictionary:
	var rep := {"paid": 0, "dropped": []}
	var p := season.player
	if p == null or not season.player_mode:
		return rep
	var keep: Array = []
	for d in p.deals:
		p.cash += int(d["money"])
		rep["paid"] += int(d["money"])
		d["years_left"] = int(d["years_left"]) - 1
		if p.brand < float(d["floor"]):
			rep["dropped"].append([d["brand"], "your brand fell below %d" % roundi(float(d["floor"]))])
		elif int(d["years_left"]) <= 0:
			rep["dropped"].append([d["brand"], "the deal ran out"])
		else:
			keep.append(d)
	p.deals = keep
	for note in rep["dropped"]:
		season.player_notes.append({"year": season.year, "week": season.week, "text": "%s ended: %s." % [Gear.brand(note[0])["name"], note[1]]})
	p.offers = p.offers.filter(func(o): return int(o["expires"]) > season.year)
	Gear.prune(p)
	refresh(season)
	return rep

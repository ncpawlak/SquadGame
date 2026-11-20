class_name Sponsors
extends RefCounted
## Career-mode sponsor deals v2 (#141, docs/career_gear_wear_spec.md "Sponsor deals v2"). Sponsors come to the player;
## interest ("heat") is built from brand, recent performance, prospect value (draft slot, fading), dev stars and youth.
## A deal is a contract: it grants some gear items, pays a fixed amount per match played while the clauses are met (a
## reduced amount, written in the contract, when they are not) and runs 1-3 seasons. Each brand has an influence meter
## (0-100) that grows when the clauses are met and the brand's items are worn, and shrinks when they are missed or the
## deal is dropped. Influence never changes the pay inside a contract: it sets what the next contract offers (more items,
## more money) and gates the bigger set bonus. With no deal nothing changes it. Items a deal ever granted are unlocked and
## can be bought with career money once the deal is gone.

## Heat needed for each sponsor tier to be interested.
const TIER_HEAT := [5.0, 25.0, 50.0, 75.0, 95.0]
## Yearly money (thousands) per granted item, by tier. A match pays this / MATCHES_PER_YEAR.
const TIER_PAY := [4, 12, 30, 70, 150]
const MATCHES_PER_YEAR := 16.0
## Influence: tiers (cold, friendly, partner, ambassador), what a deal may grant at each, and the meter's moves.
const INFLUENCE_TIERS := [0.0, 25.0, 50.0, 75.0]
const INFLUENCE_NAMES := ["Cold", "Friendly", "Partner", "Ambassador"]
const GRANT_CAP := [2, 3, 4, 5]
const SIGN_START := 10.0
const GAIN_BASE := 0.6
const GAIN_PER_ITEM := 0.4
const MISS_LOSS := 1.5
const SEASON_MISS_LOSS := 8.0
const DROP_LOSS := 35.0
const RIVAL_LOSS := 10.0
const RENEW_MIN := 15.0
const PAY_INFLUENCE := 0.6  # a contract pays x (0.8 + 0.6 * influence / 100)
const REDUCED_LOW := 0.35
const REDUCED_HIGH := 0.6
const BUY_MATCHES := 12.0  # an unlocked item costs this many matches of its tier's pay
const RIVALS := {&"haynes": &"champ", &"champ": &"haynes", &"fyla": &"rebook", &"rebook": &"fyla", &"overarmour": &"pooma",
	&"pooma": &"overarmour", &"nyke": &"addidas", &"addidas": &"nyke", &"glok": &"sigsawyer", &"sigsawyer": &"glok"}
const GRADE_FLOOR := [55, 60, 64, 68, 72]
const AVG_FLOOR := [55, 59, 63, 67, 71]
const GAMES_NEEDED := [6, 7, 8, 9, 10]
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
	var story := Backstory.heat_bonus(p, seasons_in(season))
	if story != 0.0:
		parts.append(["Your story", story])
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


static func holds(p: Soldier, brand_id: StringName) -> bool:
	return not deal_of(p, brand_id).is_empty()


static func deal_of(p: Soldier, brand_id: StringName) -> Dictionary:
	for d in p.deals:
		if d["brand"] == brand_id:
			return d
	return {}


# --- influence ---------------------------------------------------------------------------------

static func influence_of(p: Soldier, brand_id: StringName) -> float:
	return float(p.influence.get(brand_id, 0.0))


static func influence_tier(value: float) -> int:
	var t := 0
	for i in INFLUENCE_TIERS.size():
		if value >= float(INFLUENCE_TIERS[i]):
			t = i
	return t


static func _add_influence(p: Soldier, brand_id: StringName, delta: float) -> void:
	p.influence[brand_id] = clampf(influence_of(p, brand_id) + delta, 0.0, 100.0)


## Active deals he may hold, by brand level.
static func deal_cap(p: Soldier) -> int:
	var t := Gear.tier_for_brand(p.brand)
	return 2 if t <= 1 else (3 if t <= 3 else 4)


static func slot_pay(tier: int) -> int:
	return roundi(float(TIER_PAY[tier]) * 1000.0 / MATCHES_PER_YEAR)


static func money_text(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if n < 0 else "$") + s + out


## Items of `brand_id` he is wearing.
static func worn_of(p: Soldier, brand_id: StringName) -> int:
	var n := 0
	for slot in p.gear_slots:
		if p.gear_slots[slot].get("brand") == brand_id:
			n += 1
	return n


## True when he wears 3+ items of the rival of `brand_id`.
static func _rival_blocks(p: Soldier, brand_id: StringName) -> bool:
	var r: StringName = RIVALS.get(brand_id, &"")
	return r != &"" and worn_of(p, r) >= Gear.SET_PIECES


# --- clauses -----------------------------------------------------------------------------------

static func clause_text(c: Dictionary) -> String:
	match c["kind"]:
		&"wear": return "Wear %d of their items" % int(c["n"])
		&"brand": return "Keep your brand at %d+" % int(c["n"])
		&"kills": return "%d+ kills in a match" % int(c["n"])
		&"grade": return "A %d+ grade in a match" % int(c["n"])
		&"ovr": return "Keep your base OVR at %d+" % int(c["n"])
		&"games": return "Play %d+ games a season" % int(c["n"])
		&"avg": return "A %d+ grade average over the season" % int(c["n"])
	return "?"


static func _per_match(c: Dictionary) -> bool:
	return not (c["kind"] == &"games" or c["kind"] == &"avg")


static func _avg_kills(season: Season) -> float:
	var played: Array = PlayerGrade.log_for(season, season.year).filter(func(e): return bool(e.get("played", false)))
	if played.is_empty():
		played = PlayerGrade.log_for(season, season.year - 1).filter(func(e): return bool(e.get("played", false)))
	if played.is_empty():
		return 1.0
	var total := 0.0
	for e in played:
		total += float(e.get("kills", 0))
	return total / float(played.size())


static func _clauses(season: Season, tier: int, n_items: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = [{"kind": &"wear", "n": clampi(ceili(float(n_items) * 0.7), 1, n_items)}]
	var pool: Array = [
		{"kind": &"brand", "n": roundi(maxf(0.0, float(Gear.TIER_BRAND[tier]) - 10.0))},
		{"kind": &"kills", "n": maxi(1, roundi(_avg_kills(season) * 0.8))},
		{"kind": &"grade", "n": GRADE_FLOOR[tier]},
		{"kind": &"games", "n": GAMES_NEEDED[tier]},
		{"kind": &"avg", "n": AVG_FLOOR[tier]},
		{"kind": &"ovr", "n": maxi(1, season.player.base_ovr() - 3)},
	]
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var extra := clampi(tier / 2 + (1 if rng.randf() < 0.5 else 0), 0, 2)
	for k in extra:
		var c: Dictionary = pool[k]
		if c["kind"] == &"brand" and int(c["n"]) <= 0:
			continue
		out.append(c)
	return out


## {met, missed: [clause text]} for the per-match clauses after a played match (entry = the grade log entry).
static func evaluate(p: Soldier, d: Dictionary, entry: Dictionary) -> Dictionary:
	var missed: Array = []
	for c in d["clauses"]:
		if not _per_match(c):
			continue
		var ok := true
		match c["kind"]:
			&"wear": ok = worn_of(p, d["brand"]) >= int(c["n"])
			&"brand": ok = p.brand >= float(c["n"])
			&"kills": ok = int(entry.get("kills", 0)) >= int(c["n"])
			&"grade": ok = float(entry.get("score", 0.0)) >= float(c["n"])
			&"ovr": ok = p.base_ovr() >= int(c["n"])
		if not ok:
			missed.append(clause_text(c))
	return {"met": missed.is_empty(), "missed": missed}


# --- offers ------------------------------------------------------------------------------------

## The per-match pay for `n` items from a brand at this influence. Influence lifts it from x0.8 (cold) to x1.4 (ambassador).
static func contract_pay(tier: int, n: int, style: StringName, infl: float) -> int:
	var style_mult := 1.4 if style == STYLE_MONEY else 0.6
	var infl_mult := 0.8 + PAY_INFLUENCE * infl / 100.0
	return roundi(float(slot_pay(tier)) * float(n) * style_mult * infl_mult)


## What a contract with `brand_id` looks like at this influence: items granted, pay, reduced pay, length, clauses.
static func _terms(season: Season, brand_id: StringName, margin: float, style: StringName, rng: RandomNumberGenerator, n_floor := 1) -> Dictionary:
	var p := season.player
	var b := Gear.brand(brand_id)
	var tier := int(b["tier"])
	var infl := influence_of(p, brand_id)
	var n := clampi(1 + int(margin / 15.0), 1, 5)
	if style == STYLE_GEAR:
		n = mini(5, n + 1)
	else:
		n = maxi(1, n - 1)
	n = clampi(n, n_floor, maxi(n_floor, GRANT_CAP[influence_tier(infl)]))
	var slots: Array = Gear.SLOTS.duplicate()
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp
	var picked: Array = slots.slice(0, n)
	var pay := contract_pay(tier, n, style, infl)
	var reduced := roundi(float(pay) * rng.randf_range(REDUCED_LOW, REDUCED_HIGH))
	return {"slots": picked, "pay": pay, "reduced": reduced, "years": rng.randi_range(1, 3), "clauses": _clauses(season, tier, n, rng)}


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
		if holds(p, b["id"]) or _has_offer(p, b["id"]) or _rival_blocks(p, b["id"]):
			continue
		if rng.randf() > 0.5:
			continue
		var style := STYLE_MONEY if rng.randf() < 0.5 else STYLE_GEAR
		var t := _terms(season, b["id"], h - float(TIER_HEAT[tier]), style, rng)
		t["brand"] = b["id"]
		t["style"] = style
		t["countered"] = false
		t["renewal"] = false
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


## The offer to renew an ending deal: more items and money with influence, the same without it.
static func _renewal(season: Season, d: Dictionary) -> Dictionary:
	var p := season.player
	var brand_id: StringName = d["brand"]
	var infl := influence_of(p, brand_id)
	var it := influence_tier(infl)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([season.league.league_seed, season.year, str(brand_id), roundi(infl)])
	var tier := int(Gear.brand(brand_id)["tier"])
	var style := STYLE_MONEY if d["slots"].size() <= 2 else STYLE_GEAR
	var slots: Array = d["slots"].duplicate()
	var want := slots.size()
	if it >= 1:
		want = mini(5, slots.size() + it)  # friendly +1 item, partner +2, ambassador +3
	want = mini(want, GRANT_CAP[it] if it >= 1 else slots.size())
	var extras: Array = Gear.SLOTS.filter(func(x): return not slots.has(x))
	for i in range(extras.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = extras[i]
		extras[i] = extras[j]
		extras[j] = tmp
	while slots.size() < want and not extras.is_empty():
		slots.append(extras.pop_back())
	var pay := contract_pay(tier, slots.size(), style, infl)
	return {"brand": brand_id, "slots": slots, "pay": pay, "reduced": roundi(float(pay) * rng.randf_range(REDUCED_LOW, REDUCED_HIGH)),
		"years": rng.randi_range(1, 3), "clauses": _clauses(season, tier, slots.size(), rng), "style": style, "countered": true, "renewal": true,
		"expires": season.year + 1,
		"reason": "%s want to keep you. Influence: %s (%d)." % [Gear.brand(brand_id)["name"], INFLUENCE_NAMES[it], roundi(infl)]}


## "" if the offer can be signed now, else why not. (A renewal replaces the deal it came from.)
static func accept_error(p: Soldier, offer: Dictionary) -> String:
	if holds(p, offer["brand"]) and not bool(offer.get("renewal", false)):
		return "You already have a deal with them."
	var count := p.deals.size() - (1 if holds(p, offer["brand"]) else 0)
	if count >= deal_cap(p):
		return "You can hold %d deals at this brand level." % deal_cap(p)
	return ""


static func unlock(p: Soldier, brand_id: StringName, slot: StringName) -> void:
	var key := "%s:%s" % [brand_id, slot]
	if not p.unlocked_gear.has(key):
		p.unlocked_gear.append(key)


static func accept(season: Season, offer: Dictionary) -> String:
	var p := season.player
	var err := accept_error(p, offer)
	if err != "":
		return err
	var old := deal_of(p, offer["brand"])
	if not old.is_empty():
		p.deals.erase(old)
	p.deals.append({"brand": offer["brand"], "slots": offer["slots"].duplicate(), "pay": int(offer["pay"]), "reduced": int(offer["reduced"]),
		"years_left": int(offer["years"]), "clauses": offer["clauses"].duplicate(true), "signed": season.year, "season_full": 0, "season_games": 0})
	p.offers.erase(offer)
	if influence_of(p, offer["brand"]) < SIGN_START:
		p.influence[offer["brand"]] = SIGN_START
	var rival: StringName = RIVALS.get(offer["brand"], &"")
	if rival != &"" and influence_of(p, rival) > 0.0:
		_add_influence(p, rival, -RIVAL_LOSS)
	for s in offer["slots"]:
		unlock(p, offer["brand"], s)
	season.player_notes.append({"year": season.year, "week": season.week, "text": "You signed with %s." % Gear.brand(offer["brand"])["name"]})
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
	var t := _terms(season, offer["brand"], margin, style, rng)
	for k in ["slots", "pay", "reduced", "clauses"]:
		offer[k] = t[k]
	offer["style"] = style
	offer["countered"] = true
	return "countered"


## He walks away from a deal: its items go and the brand never forgets it.
static func drop(season: Season, d: Dictionary) -> void:
	var p := season.player
	if not p.deals.has(d):
		return
	p.deals.erase(d)
	_add_influence(p, d["brand"], -DROP_LOSS)
	season.player_notes.append({"year": season.year, "week": season.week, "text": "You walked out on %s. They will remember it." % Gear.brand(d["brand"])["name"]})
	Gear.prune(p)


# --- during the season -------------------------------------------------------------------------

## Called after a played match: each deal pays (the full amount when the clauses are met, the reduced amount otherwise)
## and its brand's influence moves. A deal whose influence runs out is cancelled. Returns the money earned.
static func after_match(season: Season, entry: Dictionary) -> int:
	var p := season.player
	if p == null or p.deals.is_empty():
		return 0
	var earned := 0
	for d in p.deals.duplicate():
		var r := evaluate(p, d, entry)
		earned += int(d["pay"]) if r["met"] else int(d["reduced"])
		d["season_games"] = int(d["season_games"]) + 1
		if r["met"]:
			d["season_full"] = int(d["season_full"]) + 1
			_add_influence(p, d["brand"], GAIN_BASE + GAIN_PER_ITEM * float(worn_of(p, d["brand"])))
		else:
			_add_influence(p, d["brand"], -MISS_LOSS * float(r["missed"].size()))
			if influence_of(p, d["brand"]) <= 0.0:
				p.deals.erase(d)
				season.player_notes.append({"year": season.year, "week": season.week, "text": "%s cancelled your deal: you kept missing what they asked for." % Gear.brand(d["brand"])["name"]})
	p.cash += earned
	Gear.prune(p)
	entry["sponsor_pay"] = earned
	return earned


# --- the items he can keep ----------------------------------------------------------------------

static func owns(p: Soldier, brand_id: StringName, slot: StringName) -> bool:
	return p.owned_gear.has("%s:%s" % [brand_id, slot])


static func price(brand_id: StringName, slot: StringName) -> int:
	return roundi(float(slot_pay(int(Gear.brand(brand_id)["tier"]))) * BUY_MATCHES)


## Unlocked items he does not own and no active deal gives him: [{brand, slot, price}].
static func buyable(p: Soldier) -> Array:
	var out: Array = []
	for key in p.unlocked_gear:
		var parts := String(key).split(":")
		var b := StringName(parts[0])
		var slot := StringName(parts[1])
		if owns(p, b, slot):
			continue
		var d := deal_of(p, b)
		if not d.is_empty() and Array(d["slots"]).has(slot):
			continue
		out.append({"brand": b, "slot": slot, "price": price(b, slot)})
	return out


static func buy(season: Season, brand_id: StringName, slot: StringName) -> String:
	var p := season.player
	if not p.unlocked_gear.has("%s:%s" % [brand_id, slot]):
		return "No sponsor ever gave you that."
	if owns(p, brand_id, slot):
		return "You already own it."
	var pr := price(brand_id, slot)
	if p.cash < pr:
		return "You need %s." % money_text(pr)
	p.cash -= pr
	p.owned_gear.append("%s:%s" % [brand_id, slot])
	season.player_notes.append({"year": season.year, "week": season.week, "text": "You bought the %s for %s." % [Gear.item(brand_id, slot)["name"], money_text(pr)]})
	return ""


# --- end of season -----------------------------------------------------------------------------

## End of a season: season clauses are judged (a miss claws back the full-pay difference and costs influence), deals tick,
## ended ones get a renewal offer if the brand still likes him, old offers expire, then see who calls.
static func season_end(season: Season) -> Dictionary:
	var rep := {"dropped": [], "renewals": 0, "clawback": 0}
	var p := season.player
	if p == null or not season.player_mode:
		return rep
	var sm := PlayerGrade.summary(PlayerGrade.log_for(season, season.year))
	var keep: Array = []
	for d in p.deals:
		var failed := 0
		for c in d["clauses"]:
			if _per_match(c):
				continue
			if c["kind"] == &"games" and int(sm["games"]) < int(c["n"]):
				failed += 1
			elif c["kind"] == &"avg" and (int(sm["games"]) == 0 or float(sm["avg"]) < float(c["n"])):
				failed += 1
		if failed > 0:
			var claw := mini(p.cash, (int(d["pay"]) - int(d["reduced"])) * int(d["season_full"]))
			p.cash -= claw
			rep["clawback"] += claw
			_add_influence(p, d["brand"], -SEASON_MISS_LOSS * float(failed))
			season.player_notes.append({"year": season.year, "week": season.week, "text": "%s: you missed a season clause. They took back %s." % [Gear.brand(d["brand"])["name"], money_text(claw)]})
		d["years_left"] = int(d["years_left"]) - 1
		d["season_full"] = 0
		d["season_games"] = 0
		if influence_of(p, d["brand"]) <= 0.0:
			rep["dropped"].append([d["brand"], "their trust ran out"])
		elif int(d["years_left"]) <= 0:
			if influence_of(p, d["brand"]) >= RENEW_MIN:
				p.offers.append(_renewal(season, d))
				rep["renewals"] += 1
				rep["dropped"].append([d["brand"], "the deal ran out (a renewal is on the table)"])
			else:
				rep["dropped"].append([d["brand"], "the deal ran out and they do not want to renew"])
		else:
			keep.append(d)
	p.deals = keep
	for note in rep["dropped"]:
		season.player_notes.append({"year": season.year, "week": season.week, "text": "%s ended: %s." % [Gear.brand(note[0])["name"], note[1]]})
	p.offers = p.offers.filter(func(o): return int(o["expires"]) > season.year)
	Gear.prune(p)
	refresh(season)
	return rep

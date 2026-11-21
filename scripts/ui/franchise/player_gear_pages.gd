class_name PlayerGearPages
extends RefCounted
## Player mode (#141): the gear loadout page and the sponsors page. Rules live in Gear and Sponsors; these pages only
## show them and call equip / unequip / accept.

var hub: Control


func _season() -> Season:
	return hub.season


func _label(t: String, size := 16, color := UiKit.TEXT) -> Label:
	var l := UiKit.label(t, size, color)
	return l


func _vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _wrap(text: String, size := 15, color := UiKit.MUTED, width := 1000) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


func _bonus_text(bonus: Dictionary) -> String:
	var parts: PackedStringArray = []
	for st in bonus:
		parts.append("+%d %s" % [bonus[st], Stats.LABELS[st]])
	return ", ".join(parts)


# --- loadout ---------------------------------------------------------------------------------------

func loadout_page() -> Control:
	var st := {"open": &""}
	var root := _vbox(10)
	root.custom_minimum_size.x = 1100
	var holder := _vbox(10)
	root.add_child(holder)
	var fns := {}
	fns["render"] = func():
		_clear(holder)
		_fill_loadout(holder, st, fns)
	fns["render"].call()
	return root


func _fill_loadout(box: VBoxContainer, st: Dictionary, fns: Dictionary) -> void:
	var p := _season().player
	box.add_child(_wrap("Gear comes from your sponsor deals, or from items you bought after a deal ended. Mix brands freely, one item per slot. It adds to your ratings, and taking it off takes the bonus away again. It never counts toward Hall of Fame milestones. Wearing several pieces of one brand wakes its set bonus, which grows with your influence with that brand.", 15))
	var base := p.base_ovr()
	var eff := p.best_ovr()
	box.add_child(_label("Base OVR %d   ·   gear %+d   ·   effective OVR %d" % [base, eff - base, eff], 20, Color.WHITE))
	var set_line := Gear.set_text(p.gear_slots, p.influence)
	if set_line != "":
		box.add_child(_label(set_line, 15, UiKit.GOOD))
	for slot in Gear.SLOTS:
		var row := _hbox(14)
		var name := _label(String(Gear.SLOT_LABELS[slot]), 18, Color.WHITE)
		name.custom_minimum_size.x = 150
		row.add_child(name)
		var cur: Dictionary = p.gear_slots.get(slot, {})
		var desc := _label("%s  (%s)  %s" % [cur["name"], Gear.tier_name(int(cur["tier"])), _bonus_text(cur["bonus"])] if not cur.is_empty() else _empty_reason(p, slot), 15, UiKit.TEXT if not cur.is_empty() else UiKit.MUTED)
		desc.custom_minimum_size.x = 640
		row.add_child(desc)
		if not Gear.available(p, slot).is_empty():
			row.add_child(UiKit.button("Change" if not cur.is_empty() else "Equip", func():
				st["open"] = &"" if st["open"] == slot else slot
				fns["render"].call(), 15))
		if not cur.is_empty():
			row.add_child(UiKit.button("Remove", func():
				Gear.unequip(p, slot)
				fns["render"].call(), 15))
		box.add_child(row)
		if st["open"] == slot:
			for cand in Gear.available(p, slot):
				var trial: Dictionary = p.gear_slots.duplicate()
				trial[slot] = cand
				var after := Gear.preview(p, trial)
				var line := _hbox(12)
				line.add_child(_label("    %s  (%s)  %s   →  OVR %d%s" % [cand["name"], Gear.tier_name(int(cand["tier"])), _bonus_text(cand["bonus"]), after, "  ·  owned" if Sponsors.owns(p, cand["brand"], slot) and not Sponsors.holds(p, cand["brand"]) else ""], 14, UiKit.INFO))
				line.add_child(UiKit.primary_button("Equip", func():
					Gear.equip(p, cand)
					st["open"] = &""
					fns["render"].call(), 14))
				box.add_child(line)
	box.add_child(UiKit.heading("By stat", 18))
	var any := false
	for stat in Stats.ALL:
		var d := int(p.gear_delta.get(stat, 0))
		if d == 0:
			continue
		any = true
		var capped: bool = int(Gear.total_bonus(p.gear_slots).get(stat, 0)) >= Gear.STAT_CAP
		box.add_child(_label("%s:  base %d  +%d gear  =  %d%s" % [Stats.LABELS[stat], p.base_stat(stat), d, int(p.stats[stat]), "   (gear cap %d)" % Gear.STAT_CAP if capped else ""], 15, UiKit.TEXT))
	if not any:
		box.add_child(_label("No gear bonuses yet.", 15, UiKit.MUTED))
	var foot := _hbox(12)
	foot.add_child(UiKit.button("Back", func(): hub.go_back(), 16))
	box.add_child(foot)


func _empty_reason(p: Soldier, slot: StringName) -> String:
	if p.deals.is_empty() and p.owned_gear.is_empty():
		return "Empty: no sponsor deal yet"
	return "Empty: no deal or purchase gives you an item for this slot"


# --- sponsors --------------------------------------------------------------------------------------

func sponsors_page() -> Control:
	var root := _vbox(10)
	root.custom_minimum_size.x = 1100
	var holder := _vbox(10)
	root.add_child(holder)
	var fns := {}
	fns["render"] = func():
		_clear(holder)
		_fill_sponsors(holder, fns)
	fns["render"].call()
	return root


func assets_page() -> Control:
	var root := _vbox(10)
	root.custom_minimum_size.x = 1100
	var holder := _vbox(10)
	root.add_child(holder)
	var fns := {}
	fns["render"] = func():
		_clear(holder)
		_fill_assets(holder, fns)
	fns["render"].call()
	return root


func _service_effect(id: StringName, lv: Dictionary) -> String:
	if id == Assets.COACH:
		return "+%d%% XP" % roundi((float(lv["xp"]) - 1.0) * 100.0)
	if lv.has("meter"):
		return "fills the ceiling meter %d%% faster" % roundi((float(lv["meter"]) - 1.0) * 100.0)
	return "+%d%% brand, +%d%% sponsor pay" % [roundi((float(lv["brand"]) - 1.0) * 100.0), roundi((float(lv["pay"]) - 1.0) * 100.0)]


func _fill_assets(box: VBoxContainer, fns: Dictionary) -> void:
	var s := _season()
	var p := s.player
	box.add_child(_wrap("Spend what you earn. A coach and an agent cost a retainer every week in season, and let you go if you cannot pay it. Property pays steady rent. A business can lose money in a bad year, but pays more on average.", 15))
	box.add_child(_label("Cash: %s   ·   salary %s a year   ·   retainers %s a year   ·   rent %s a year" % [Sponsors.money_text(p.cash), Sponsors.money_text(PlayerPay.yearly(p)), Sponsors.money_text(Assets.upkeep_yearly(p)), Sponsors.money_text(Assets.rent_yearly(p))], 16, Color.WHITE))
	for id in Assets.SERVICES:
		var n := Assets.level(p, id)
		box.add_child(UiKit.heading(Assets.title(id), 18))
		var levels: Array = Assets.LEVELS[id]
		if n > 0:
			var cur: Dictionary = levels[n - 1]
			box.add_child(_label("%s  ·  %s  ·  retainer %s a year" % [cur["name"], _service_effect(id, cur), Sponsors.money_text(int(cur["upkeep"]))], 15, UiKit.TEXT))
		else:
			box.add_child(_label("None.", 14, UiKit.MUTED))
		var row := _hbox(10)
		if n < levels.size():
			var nxt: Dictionary = levels[n]
			var buy := UiKit.button("Hire %s (%s, retainer %s)  %s" % [nxt["name"], Sponsors.money_text(Assets.cost_of(p, id)), Sponsors.money_text(int(nxt["upkeep"])), _service_effect(id, nxt)], func():
				var e := Assets.buy(s, id)
				hub.app.toast(e if e != "" else "Done.")
				fns["render"].call(), 14)
			buy.disabled = Assets.buy_error(p, id) != ""
			row.add_child(buy)
		if n > 0:
			row.add_child(UiKit.button("Let them go", func():
				Assets.sell(s, id)
				fns["render"].call(), 14))
		box.add_child(row)
	for id in Assets.HOLDINGS:
		var h: Dictionary = Assets.HOLDING[id]
		box.add_child(UiKit.heading("Rental property" if id == Assets.PROPERTY else "Businesses", 18))
		var what := ""
		if id == Assets.PROPERTY:
			what = "%s rent a year each" % Sponsors.money_text(roundi(float(h["price"]) * float(h["yield"])))
		else:
			what = "profit between %d%% and %d%% of its price a year, %d%% on average" % [roundi(float(h["low"]) * 100.0), roundi(float(h["high"]) * 100.0), roundi(float(h["yield"]) * 100.0)]
		box.add_child(_label("Own %d of %d  ·  %s" % [Assets.count(p, id), int(h["max"]), what], 15, UiKit.TEXT))
		var hrow := _hbox(10)
		var hb := UiKit.button("Buy one (%s)" % Sponsors.money_text(int(h["price"])), func():
			var e := Assets.buy(s, id)
			hub.app.toast(e if e != "" else "Bought.")
			fns["render"].call(), 14)
		hb.disabled = Assets.buy_error(p, id) != ""
		hrow.add_child(hb)
		if Assets.count(p, id) > 0:
			hrow.add_child(UiKit.button("Sell one (%s)" % Sponsors.money_text(roundi(float(h["price"]) * Assets.SELL_SHARE)), func():
				Assets.sell(s, id)
				fns["render"].call(), 14))
		box.add_child(hrow)
	box.add_child(UiKit.button("Back", func(): hub.go_back(), 16))


func _slots_text(slots: Array) -> String:
	return ", ".join(slots.map(func(s): return String(Gear.SLOT_LABELS[s]).to_lower()))


func _clauses_text(clauses: Array) -> String:
	return "; ".join(clauses.map(func(c): return Sponsors.clause_text(c)))


func _meter(v: float) -> String:
	var n := clampi(roundi(v / 10.0), 0, 10)
	return "[" + "#".repeat(n) + "-".repeat(10 - n) + "]"


func _fill_sponsors(box: VBoxContainer, fns: Dictionary) -> void:
	var s := _season()
	var p := s.player
	var h := Sponsors.heat(s)
	box.add_child(_wrap("Sponsors come to you. A deal grants gear and pays a fixed amount every match you play, as long as you meet its clauses; miss them and the pay drops to a lower amount, and the brand's influence with you falls. Influence builds when you meet the clauses and wear their items. It never changes the pay inside a contract, but it decides how many items and how much money you are offered at renewal, and it makes their set bonus bigger. Dropping a deal costs you a lot of influence.", 15))
	box.add_child(_label("Team salary: %s a year, paid weekly in season" % Sponsors.money_text(PlayerPay.yearly(p)), 15, Color.WHITE))
	box.add_child(_label("Cash: %s   ·   sponsor heat %d   ·   brand %d (%s)   ·   deals %d of %d" % [Sponsors.money_text(p.cash), roundi(h["heat"]), roundi(p.brand), WeeklyPlan.tier_name(p.brand), p.deals.size(), Sponsors.deal_cap(p)], 18, Color.WHITE))
	box.add_child(_wrap("Heat: " + ", ".join(h["parts"].map(func(x): return "%s %d" % [x[0], roundi(x[1])])), 14))
	box.add_child(UiKit.heading("Your deals", 18))
	if p.deals.is_empty():
		box.add_child(_label("No deals yet.", 15, UiKit.MUTED))
	for d in p.deals.duplicate():
		var b := Gear.brand(d["brand"])
		var infl := Sponsors.influence_of(p, d["brand"])
		var row := _vbox(3)
		row.add_child(_label("%s (%s)  ·  %s  ·  %s a match (%s if you miss a clause)  ·  %d year%s left" % [b["name"], Gear.tier_name(int(b["tier"])), _slots_text(d["slots"]), Sponsors.money_text(int(d["pay"])), Sponsors.money_text(int(d["reduced"])), d["years_left"], "" if int(d["years_left"]) == 1 else "s"], 15, UiKit.TEXT))
		row.add_child(_label("    Clauses: " + _clauses_text(d["clauses"]), 14, UiKit.MUTED))
		var worn := Sponsors.worn_of(p, d["brand"])
		row.add_child(_label("    Influence %s %d (%s)  ·  wearing %d of %d items" % [_meter(infl), roundi(infl), Sponsors.INFLUENCE_NAMES[Sponsors.influence_tier(infl)], worn, d["slots"].size()], 14, UiKit.GOOD if infl >= 50.0 else (UiKit.BAD if infl < 15.0 else UiKit.INFO)))
		row.add_child(UiKit.button("Walk away (costs %d influence)" % roundi(Sponsors.DROP_LOSS), func():
			Sponsors.drop(s, d)
			fns["render"].call(), 13))
		box.add_child(row)
	box.add_child(UiKit.heading("Offers", 18))
	if p.offers.is_empty():
		box.add_child(_label("No offers right now.", 15, UiKit.MUTED))
	for o in p.offers.duplicate():
		var b := Gear.brand(o["brand"])
		var row := _vbox(4)
		row.add_child(_label("%s%s (%s)  ·  %s  ·  %s a match (%s if you miss a clause) for %d year%s  ·  %s" % ["RENEWAL: " if bool(o.get("renewal", false)) else "", b["name"], Gear.tier_name(int(b["tier"])), _slots_text(o["slots"]), Sponsors.money_text(int(o["pay"])), Sponsors.money_text(int(o["reduced"])), o["years"], "" if int(o["years"]) == 1 else "s", "money-heavy" if o["style"] == Sponsors.STYLE_MONEY else "gear-heavy"], 15, Color.WHITE))
		row.add_child(_label("    Clauses: " + _clauses_text(o["clauses"]), 14, UiKit.TEXT))
		row.add_child(_label("    " + String(o["reason"]), 14, UiKit.MUTED))
		var btns := _hbox(10)
		var err := Sponsors.accept_error(p, o)
		var accept := UiKit.primary_button("Accept", func():
			var e := Sponsors.accept(s, o)
			if e == "":
				hub.app.toast("Signed with %s." % b["name"])
			fns["render"].call(), 15)
		accept.disabled = err != ""
		btns.add_child(accept)
		if not bool(o["countered"]):
			btns.add_child(UiKit.button("Ask for %s" % ("gear" if o["style"] == Sponsors.STYLE_MONEY else "money"), func():
				var r := Sponsors.counter(s, o)
				hub.app.toast("They came back with new terms." if r == "countered" else "They walked away.")
				fns["render"].call(), 15))
		btns.add_child(UiKit.button("Decline", func():
			Sponsors.decline(s, o)
			fns["render"].call(), 15))
		if err != "":
			btns.add_child(_label(err, 13, UiKit.BAD))
		row.add_child(btns)
		box.add_child(row)
	box.add_child(UiKit.heading("Influence", 18))
	var any_infl := false
	for br in Gear.BRANDS:
		var v := Sponsors.influence_of(p, br["id"])
		if v <= 0.0 and not Sponsors.holds(p, br["id"]):
			continue
		any_infl = true
		box.add_child(_label("%s  %s %d  (%s)%s" % [br["name"], _meter(v), roundi(v), Sponsors.INFLUENCE_NAMES[Sponsors.influence_tier(v)], "" if Sponsors.holds(p, br["id"]) else "  ·  no deal"], 14, UiKit.TEXT))
	if not any_infl:
		box.add_child(_label("No brand has any influence with you yet.", 14, UiKit.MUTED))
	box.add_child(UiKit.heading("Gear you can buy", 18))
	var shop := Sponsors.buyable(p)
	if shop.is_empty():
		box.add_child(_label("Nothing. Items a deal gave you can be bought here once the deal is over.", 14, UiKit.MUTED))
	for it in shop:
		var row2 := _hbox(12)
		var item := Gear.item(it["brand"], it["slot"])
		row2.add_child(_label("%s  (%s)  %s  ·  %s" % [item["name"], Gear.tier_name(int(item["tier"])), _bonus_text(item["bonus"]), Sponsors.money_text(int(it["price"]))], 14, UiKit.TEXT))
		var buy := UiKit.button("Buy", func():
			var e := Sponsors.buy(s, it["brand"], it["slot"])
			hub.app.toast(e if e != "" else "Bought %s." % item["name"])
			fns["render"].call(), 14)
		buy.disabled = p.cash < int(it["price"])
		row2.add_child(buy)
		box.add_child(row2)
	box.add_child(UiKit.heading("A foot in the door", 18))
	box.add_child(_wrap("Buy one item from a brand that has not signed you, at %dx the normal price. It stays yours; wearing it builds a little influence (up to Friendly), and so does training your brand. When they sign you, the item is already paid for." % int(Sponsors.PREBUY_MULT), 14))
	var pre := Sponsors.prebuy_brands(s)
	if pre.is_empty():
		box.add_child(_label("No brand to approach right now.", 14, UiKit.MUTED))
	for id in pre:
		var pb := Gear.brand(id)
		var prow := _vbox(2)
		prow.add_child(_label("%s (%s)  ·  influence %d" % [pb["name"], Gear.tier_name(int(pb["tier"])), roundi(Sponsors.influence_of(p, id))], 14, UiKit.TEXT))
		var pbtns := _hbox(6)
		for slot in Gear.SLOTS:
			var pit := Gear.item(id, slot)
			var pbtn := UiKit.button("%s %s  %s" % [Gear.SLOT_LABELS[slot], _bonus_text(pit["bonus"]), Sponsors.money_text(Sponsors.prebuy_price(id, slot))], func():
				var e := Sponsors.prebuy(s, id, slot)
				hub.app.toast(e if e != "" else "Bought %s." % pit["name"])
				fns["render"].call(), 12)
			pbtn.disabled = Sponsors.prebuy_error(s, id, slot) != ""
			pbtns.add_child(pbtn)
		prow.add_child(pbtns)
		box.add_child(prow)
	box.add_child(UiKit.heading("What the others want", 18))
	for t in Gear.TIER_BRAND.size():
		var names := ", ".join(Gear.brands_in_tier(t).map(func(b): return b["name"]))
		var gated := t > Sponsors.tier_ceiling(s)
		var line := "%s (%s): heat %d%s" % [Gear.tier_name(t), names, roundi(float(Sponsors.TIER_HEAT[t])), "  ·  needs a bigger brand (or a top prospect)" if gated else ""]
		box.add_child(_label(line, 14, UiKit.MUTED if gated else UiKit.TEXT))
	var foot := _hbox(12)
	foot.add_child(UiKit.button("Loadout", func(): hub.open("Loadout", func(): return loadout_page()), 16))
	foot.add_child(UiKit.button("Back", func(): hub.go_back(), 16))
	box.add_child(foot)


# --- stories ---------------------------------------------------------------------------------------

func stories_page() -> Control:
	var root := _vbox(10)
	root.custom_minimum_size.x = 1000
	var holder := _vbox(10)
	root.add_child(holder)
	var fns := {}
	fns["render"] = func():
		_clear(holder)
		_fill_stories(holder, fns)
	fns["render"].call()
	return root


func _fill_stories(box: VBoxContainer, fns: Dictionary) -> void:
	var s := _season()
	var p := s.player
	box.add_child(_wrap("Things that happen on the way: a decision here can change your morale, brand and skill points. Automatic stories (group training, a breakthrough game, a comeback) show up as coach notes.", 15))
	if p.stories.is_empty():
		box.add_child(_label("Nothing waiting.", 16, UiKit.MUTED))
	for st in p.stories.duplicate():
		box.add_child(_label(String(st["title"]), 19, Color.WHITE))
		box.add_child(_wrap(String(st["text"]), 15, UiKit.TEXT))
		for c in st["choices"]:
			box.add_child(UiKit.button(String(c["label"]), func():
				var msg := Stories.choose(s, st, String(c["key"]))
				if msg != "":
					hub.app.toast(msg)
				fns["render"].call(), 15))
	var foot := _hbox(12)
	foot.add_child(UiKit.button("Back", func(): hub.go_back(), 16))
	box.add_child(foot)

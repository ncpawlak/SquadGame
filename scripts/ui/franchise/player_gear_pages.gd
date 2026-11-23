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


const TIER_COLORS := [Color("#94a3b8"), Color("#22c55e"), Color("#38bdf8"), Color("#a855f7"), Color("#f59e0b")]
var _sp_tab: StringName = &"deals"


func _chip(text: String, color: Color, size := 12) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.flat(Color(color, 0.16), 4, 1, Color(color, 0.7)))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 2)
	m.add_theme_constant_override("margin_bottom", 2)
	m.add_child(_label(text, size, color))
	pc.add_child(m)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return pc


func _card(accent: Color, width := 0) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, 8, 1, Color(accent, 0.5)))
	if width > 0:
		pc.custom_minimum_size.x = width
	return pc


func _pad(c: Control, m := 14) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	mc.add_child(c)
	return mc


func _fill_sponsors(box: VBoxContainer, fns: Dictionary) -> void:
	var s := _season()
	var p := s.player
	var h := Sponsors.heat(s)
	box.add_child(_sponsor_header(s, p, h))
	box.add_child(_sponsor_tabs(p, fns))
	match _sp_tab:
		&"offers":
			_tab_offers(box, s, p, fns)
		&"brands":
			_tab_brands(box, s, p)
		&"shop":
			_tab_shop(box, s, p, fns)
		_:
			_tab_deals(box, s, p, fns)
	var foot := _hbox(12)
	foot.add_child(UiKit.button("Loadout", func(): hub.open("Loadout", func(): return loadout_page()), 16))
	foot.add_child(UiKit.button("Back", func(): hub.go_back(), 16))
	box.add_child(foot)


func _gauge_card(caption: String, value: String, v: float, maximum: float, color: Color, sub: String, tip := "") -> Control:
	var card := _card(color)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := _vbox(4)
	card.add_child(_pad(box, 12))
	box.add_child(_label(caption, 11, UiKit.MUTED))
	box.add_child(UiKit.display(value, 26, color, true))
	if maximum > 0.0:
		box.add_child(PlayerPages.Meter.new(v, maximum, color, 0.0, 8.0))
	box.add_child(_label(sub, 11, UiKit.MUTED))
	if tip != "":
		card.tooltip_text = tip
	return card


func _sponsor_header(s: Season, p: Soldier, h: Dictionary) -> Control:
	var row := _hbox(12)
	row.add_child(_gauge_card("CASH", Sponsors.money_text(p.cash), 0.0, 0.0, UiKit.GOOD, "Salary %s a year" % Sponsors.money_text(PlayerPay.yearly(p))))
	var parts: Array = h["parts"]
	var tip := "\n".join(parts.map(func(x): return "%s  %d" % [x[0], roundi(x[1])]))
	row.add_child(_gauge_card("SPONSOR HEAT", str(roundi(h["heat"])), float(h["heat"]), float(Sponsors.TIER_HEAT[Sponsors.TIER_HEAT.size() - 1]) + 10.0, UiKit.GOLD, "Hover for the breakdown", tip))
	row.add_child(_gauge_card("BRAND", WeeklyPlan.tier_name(p.brand), p.brand, WeeklyPlan.BRAND_MAX, UiKit.INFO, "%d of %d" % [roundi(p.brand), roundi(WeeklyPlan.BRAND_MAX)]))
	var cap := Sponsors.deal_cap(p)
	row.add_child(_gauge_card("DEALS", "%d / %d" % [p.deals.size(), cap], float(p.deals.size()), float(maxi(1, cap)), UiKit.ACCENT, "slots in use"))
	return row


func _sponsor_tabs(p: Soldier, fns: Dictionary) -> Control:
	var row := _hbox(8)
	var tabs := [[&"deals", "DEALS  %d" % p.deals.size()], [&"offers", "OFFERS  %d" % p.offers.size()], [&"brands", "BRANDS"], [&"shop", "SHOP"]]
	for t in tabs:
		var key: StringName = t[0]
		var b := UiKit.button(t[1], func():
			_sp_tab = key
			fns["render"].call(), 17)
		UiKit.style_skewed(b, Color(UiKit.PANEL, 0.8))
		b.custom_minimum_size = Vector2(150, 44)
		if _sp_tab == key:
			UiKit.style_primary(b)
		elif key == &"offers" and not p.offers.is_empty():
			UiKit.style_primary(b, Color("#f97316"))
		row.add_child(b)
	return row


## Slot pips for a deal: one chip per slot it covers, lit when you are wearing that brand's item there.
func _slot_pips(p: Soldier, brand_id: StringName, slots: Array) -> Control:
	var row := _hbox(6)
	for slot in slots:
		var worn: bool = p.gear_slots.get(slot, {}).get("brand") == brand_id
		row.add_child(_chip(String(Gear.SLOT_LABELS[slot]).to_upper(), UiKit.GOOD if worn else UiKit.MUTED, 11))
	return row


func _clause_chips(clauses: Array) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for c in clauses:
		row.add_child(_chip(Sponsors.clause_text(c), UiKit.INFO, 12))
	return row


func _tab_deals(box: VBoxContainer, s: Season, p: Soldier, fns: Dictionary) -> void:
	var cap := Sponsors.deal_cap(p)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for d in p.deals.duplicate():
		var b := Gear.brand(d["brand"])
		var tc: Color = TIER_COLORS[int(b["tier"])]
		var card := _card(tc)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.x = 530
		var v := _vbox(8)
		card.add_child(_pad(v))
		var top := _hbox(10)
		top.add_child(UiKit.display(String(b["name"]).to_upper(), 24, Color.WHITE, true))
		top.add_child(_chip(Gear.tier_name(int(b["tier"])).to_upper(), tc))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(sp)
		top.add_child(_label("%d yr left" % int(d["years_left"]), 13, UiKit.MUTED))
		v.add_child(top)
		var pay := _hbox(10)
		pay.add_child(UiKit.display("%s / match" % Sponsors.money_text(int(d["pay"])), 22, UiKit.GOOD, true))
		pay.add_child(_label("%s if you miss a clause" % Sponsors.money_text(int(d["reduced"])), 12, UiKit.MUTED))
		v.add_child(pay)
		var infl := Sponsors.influence_of(p, d["brand"])
		var irow := _hbox(10)
		irow.add_child(_label("INFLUENCE", 11, UiKit.MUTED))
		irow.add_child(PlayerPages.Meter.new(infl, 100.0, UiKit.GOOD if infl >= 50.0 else (UiKit.BAD if infl < 15.0 else UiKit.INFO), 0.0, 10.0))
		irow.add_child(_label("%d  %s" % [roundi(infl), Sponsors.INFLUENCE_NAMES[Sponsors.influence_tier(infl)]], 12, UiKit.TEXT))
		v.add_child(irow)
		v.add_child(_slot_pips(p, d["brand"], d["slots"]))
		v.add_child(_clause_chips(d["clauses"]))
		var walk := UiKit.button("Walk away  (-%d influence)" % roundi(Sponsors.DROP_LOSS), func():
			Sponsors.drop(s, d)
			fns["render"].call(), 12)
		walk.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(walk)
		grid.add_child(card)
	for i in maxi(0, cap - p.deals.size()):
		var empty := _card(UiKit.MUTED)
		empty.custom_minimum_size = Vector2(530, 110)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c := CenterContainer.new()
		c.add_child(_label("OPEN SLOT" if p.offers.is_empty() else "OPEN SLOT  ·  you have offers", 14, UiKit.MUTED if p.offers.is_empty() else Color("#f97316")))
		empty.add_child(c)
		grid.add_child(empty)


func _tab_offers(box: VBoxContainer, s: Season, p: Soldier, fns: Dictionary) -> void:
	if p.offers.is_empty():
		box.add_child(_label("No offers right now. Heat and brand bring them.", 15, UiKit.MUTED))
		return
	for o in p.offers.duplicate():
		var b := Gear.brand(o["brand"])
		var tc: Color = TIER_COLORS[int(b["tier"])]
		var renewal := bool(o.get("renewal", false))
		var card := _card(Color("#f97316") if renewal else tc)
		var v := _vbox(8)
		card.add_child(_pad(v))
		var top := _hbox(10)
		top.add_child(UiKit.display(String(b["name"]).to_upper(), 26, Color.WHITE, true))
		top.add_child(_chip(Gear.tier_name(int(b["tier"])).to_upper(), tc))
		if renewal:
			top.add_child(_chip("RENEWAL", Color("#f97316")))
		top.add_child(_chip("MONEY" if o["style"] == Sponsors.STYLE_MONEY else "GEAR", UiKit.GOLD))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(sp)
		top.add_child(UiKit.display("%s / match" % Sponsors.money_text(int(o["pay"])), 24, UiKit.GOOD, true))
		v.add_child(top)
		var meta := _hbox(14)
		meta.add_child(_label("%d year%s" % [int(o["years"]), "" if int(o["years"]) == 1 else "s"], 13, UiKit.TEXT))
		meta.add_child(_label("%s if you miss a clause" % Sponsors.money_text(int(o["reduced"])), 12, UiKit.MUTED))
		meta.add_child(_slot_pips(p, o["brand"], o["slots"]))
		v.add_child(meta)
		v.add_child(_clause_chips(o["clauses"]))
		var why := _label(String(o["reason"]), 12, UiKit.MUTED)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size.x = 900
		v.add_child(why)
		var btns := _hbox(10)
		var err := Sponsors.accept_error(p, o)
		var accept := UiKit.primary_button("Accept", func():
			var e := Sponsors.accept(s, o)
			if e == "":
				hub.app.toast("Signed with %s." % b["name"])
			fns["render"].call(), 16)
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
			btns.add_child(_label(err, 12, UiKit.BAD))
		v.add_child(btns)
		box.add_child(card)


## Every brand by tier: its influence with you, and whether it is signed, offering, within reach or locked.
func _tab_brands(box: VBoxContainer, s: Season, p: Soldier) -> void:
	for t in Gear.TIER_BRAND.size():
		var tc: Color = TIER_COLORS[t]
		var gated := t > Sponsors.tier_ceiling(s)
		var head := _hbox(10)
		head.add_child(UiKit.display(Gear.tier_name(t).to_upper(), 18, tc, true))
		head.add_child(_label("needs heat %d" % roundi(float(Sponsors.TIER_HEAT[t])) + ("   ·   locked: bigger brand or a top prospect" if gated else ""), 12, UiKit.MUTED))
		box.add_child(head)
		var row := _hbox(10)
		for br in Gear.brands_in_tier(t):
			var id: StringName = br["id"]
			var v := Sponsors.influence_of(p, id)
			var signed := Sponsors.holds(p, id)
			var offered := Sponsors._has_offer(p, id)
			var card := _card(tc if not gated else UiKit.MUTED, 200)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var c := _vbox(5)
			card.add_child(_pad(c, 10))
			c.add_child(_label(String(br["name"]).to_upper(), 14, Color.WHITE if not gated else UiKit.MUTED))
			c.add_child(PlayerPages.Meter.new(v, 100.0, tc, 0.0, 8.0))
			var state := "SIGNED" if signed else ("OFFER" if offered else ("LOCKED" if gated else "OPEN"))
			var scol := UiKit.GOOD if signed else (Color("#f97316") if offered else (UiKit.MUTED if gated else UiKit.INFO))
			var line := _hbox(6)
			line.add_child(_chip(state, scol, 11))
			line.add_child(_label(str(roundi(v)), 12, UiKit.MUTED))
			c.add_child(line)
			row.add_child(card)
		box.add_child(row)


func _tab_shop(box: VBoxContainer, s: Season, p: Soldier, fns: Dictionary) -> void:
	box.add_child(UiKit.heading("Buy back", 18))
	var shop := Sponsors.buyable(p)
	if shop.is_empty():
		box.add_child(_label("Nothing yet. Items from a finished deal can be bought here.", 14, UiKit.MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	box.add_child(flow)
	for it in shop:
		var item := Gear.item(it["brand"], it["slot"])
		var tc: Color = TIER_COLORS[int(item["tier"])]
		var card := _card(tc, 250)
		var v := _vbox(4)
		card.add_child(_pad(v, 10))
		v.add_child(_label(String(item["name"]), 14, Color.WHITE))
		v.add_child(_label(_bonus_text(item["bonus"]), 12, UiKit.MUTED))
		var buy := UiKit.button("Buy  %s" % Sponsors.money_text(int(it["price"])), func():
			var e := Sponsors.buy(s, it["brand"], it["slot"])
			hub.app.toast(e if e != "" else "Bought %s." % item["name"])
			fns["render"].call(), 14)
		buy.disabled = p.cash < int(it["price"])
		v.add_child(buy)
		flow.add_child(card)
	box.add_child(UiKit.heading("A foot in the door", 18))
	var pre := Sponsors.prebuy_brands(s)
	if pre.is_empty():
		box.add_child(_label("No brand to approach right now.", 14, UiKit.MUTED))
	for id in pre:
		var pb := Gear.brand(id)
		var tc2: Color = TIER_COLORS[int(pb["tier"])]
		var card2 := _card(tc2)
		var pv := _vbox(6)
		card2.add_child(_pad(pv, 12))
		var head := _hbox(10)
		head.add_child(UiKit.display(String(pb["name"]).to_upper(), 18, Color.WHITE, true))
		head.add_child(_chip(Gear.tier_name(int(pb["tier"])).to_upper(), tc2, 11))
		head.add_child(PlayerPages.Meter.new(Sponsors.influence_of(p, id), 100.0, tc2, 0.0, 8.0))
		pv.add_child(head)
		var pbtns := _hbox(6)
		for slot in Gear.SLOTS:
			var pit := Gear.item(id, slot)
			var pbtn := UiKit.button("%s  %s" % [Gear.SLOT_LABELS[slot], Sponsors.money_text(Sponsors.prebuy_price(id, slot))], func():
				var e := Sponsors.prebuy(s, id, slot)
				hub.app.toast(e if e != "" else "Bought %s." % pit["name"])
				fns["render"].call(), 12)
			pbtn.tooltip_text = _bonus_text(pit["bonus"])
			pbtn.disabled = Sponsors.prebuy_error(s, id, slot) != ""
			pbtns.add_child(pbtn)
		pv.add_child(pbtns)
		box.add_child(card2)


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

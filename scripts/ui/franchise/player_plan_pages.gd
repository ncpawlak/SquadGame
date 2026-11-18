class_name PlayerPlanPages
extends RefCounted
## Player mode (#138): the weekly / camp plan screen and the skill-point placement screen. Rules live in WeeklyPlan and
## Progression; these pages only edit a draft and commit it with a Confirm button.

const METER_W := 720.0
const BAND_COLORS := [Color("#22c55e"), Color("#84cc16"), Color("#f59e0b"), Color("#ef4444")]
const BAND_EDGES := [0.0, 25.0, 50.0, 75.0, 100.0]

var hub: Control


func _season() -> Season:
	return hub.season


func _label(t: String, size := 16, color := UiKit.TEXT) -> Label:
	return UiKit.label(t, size, color)


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


# --- weekly / camp plan ---------------------------------------------------------------------------

## The plan screen. `camp`: the offseason camp plan (8 points, spa is rehab, no fatigue meter).
func plan_page(camp := false) -> Control:
	var p := _season().player
	var st := {"plan": (p.camp_plan if camp else p.plan).duplicate()}
	var root := _vbox(10)
	root.custom_minimum_size.x = 1150
	var holder := _vbox(10)
	root.add_child(holder)
	var fns := {}
	fns["render"] = func():
		_clear(holder)
		_fill_plan(holder, camp, st, fns)
	fns["render"].call()
	return root


func _fill_plan(box: VBoxContainer, camp: bool, st: Dictionary, fns: Dictionary) -> void:
	var s := _season()
	var p := s.player
	var plan: Dictionary = st["plan"]
	var intro := _label("%d points, at most %d in any one activity. Every point except spa adds fatigue. Your plan repeats until you change it." % [WeeklyPlan.points(camp), WeeklyPlan.max_level(camp)] if not camp \
		else "Camp: %d points, at most %d in any one activity. Camp has no fatigue; spa here is rehab and takes Wear off. Your camp plan repeats every offseason." % [WeeklyPlan.points(camp), WeeklyPlan.max_level(camp)], 15, UiKit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 1100
	box.add_child(intro)
	var pr := {}
	if not camp:
		pr = WeeklyPlan.projection(s, plan)
		box.add_child(_meter(pr))
	var mx := WeeklyPlan.max_level(camp)
	for a in WeeklyPlan.activities(camp):
		var lvl := WeeklyPlan.level(plan, a)
		var row := _hbox(14)
		var name := _label(String(WeeklyPlan.LABELS[a]).to_upper(), 18, Color.WHITE)
		name.custom_minimum_size.x = 190
		row.add_child(name)
		var down := UiKit.button("<", func():
			plan[a] = maxi(0, WeeklyPlan.level(plan, a) - 1)
			fns["render"].call(), 16)
		down.disabled = lvl <= 0
		row.add_child(down)
		var pips := _hbox(4)
		for i in mx:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(20, 20)
			pip.color = UiKit.ACCENT if i < lvl else Color(1, 1, 1, 0.14)
			pips.add_child(pip)
		row.add_child(pips)
		var up := UiKit.button(">", func():
			plan[a] = mini(mx, WeeklyPlan.level(plan, a) + 1)
			fns["render"].call(), 16)
		up.disabled = lvl >= mx or WeeklyPlan.unspent(plan, camp) <= 0
		row.add_child(up)
		for l in range(1, mx + 1):
			var t := _label(_bonus_text(a, l, camp), 14, Color.WHITE if l == lvl else UiKit.MUTED)
			t.custom_minimum_size.x = 170
			row.add_child(t)
		box.add_child(row)
	var left := WeeklyPlan.unspent(plan, camp)
	box.add_child(_label("Points left: %d" % left, 20, UiKit.GOLD if left > 0 else UiKit.GOOD))
	if left > 0:
		box.add_child(_label("%d unspent point%s will be wasted." % [left, "" if left == 1 else "s"], 15, UiKit.GOLD))
	box.add_child(_label(_stars_line(p, plan, camp), 15, UiKit.INFO))
	if not camp and not bool(pr.get("played", false)) and WeeklyPlan.level(plan, WeeklyPlan.BRAND) > 0:
		box.add_child(_label("You are not expected to play this week, so brand exposure earns nothing.", 14, UiKit.GOLD))
	if not camp and not bool(pr.get("played", false)):
		box.add_child(_label("You are not expected to play this week: fatigue will not hurt you.", 14, UiKit.MUTED))
	var err := WeeklyPlan.error(plan, camp)
	if err != "":
		box.add_child(_label(err, 15, UiKit.BAD))
	var foot := _hbox(12)
	var confirm := UiKit.primary_button("Confirm plan", func():
		if camp:
			p.camp_plan = plan.duplicate()
			p.camp_plan_confirmed = true
		else:
			p.plan = plan.duplicate()
			p.plan_confirmed = true
		hub.app.toast("Camp plan confirmed." if camp else "Weekly plan confirmed. It repeats until you change it.")
		hub.go_back(), 22)
	confirm.disabled = err != ""
	foot.add_child(confirm)
	foot.add_child(UiKit.button("Cancel", func(): hub.go_back(), 16))
	box.add_child(foot)


## The fatigue meter: the four bands, a marker for fatigue now, and the bar for where it ends this week.
func _meter(pr: Dictionary) -> Control:
	var box := _vbox(4)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(METER_W, 26)
	for i in 4:
		var seg := ColorRect.new()
		seg.color = Color(BAND_COLORS[i], 0.22)
		seg.position = Vector2(METER_W * BAND_EDGES[i] / 100.0, 0)
		seg.size = Vector2(METER_W * (BAND_EDGES[i + 1] - BAND_EDGES[i]) / 100.0, 26)
		bar.add_child(seg)
	var after := clampf(float(pr["after"]), 0.0, 100.0)
	var fill := ColorRect.new()
	fill.color = BAND_COLORS[mini(int(after / 25.0), 3)]
	fill.position = Vector2(0, 7)
	fill.size = Vector2(METER_W * after / 100.0, 12)
	bar.add_child(fill)
	var now := ColorRect.new()
	now.color = Color.WHITE
	now.position = Vector2(METER_W * clampf(float(pr["now"]), 0.0, 100.0) / 100.0, 0)
	now.size = Vector2(3, 26)
	bar.add_child(now)
	box.add_child(bar)
	var note := ""
	if pr["bye"]:
		note = "  (bye week)"
	elif pr["played"]:
		note = "  (includes this week's match)"
	box.add_child(_label("Fatigue now %d  ->  after this week %d  (%s)%s" % [roundi(float(pr["now"])), roundi(after), pr["band"], note], 15, UiKit.TEXT))
	return box


## What `lvl` points in `a` would give, after multipliers.
func _bonus_text(a: StringName, lvl: int, camp: bool) -> String:
	var s := _season()
	var p := s.player
	var team := s.user_team()
	match a:
		WeeklyPlan.PRACTICE:
			var mult := Progression.xp_multiplier(p) * Facilities.training_mult(team) * (GreenTeam.XP_MULT if team.green_team.has(p) else 1.0)
			var xp: float = (WeeklyPlan.CAMP_PRACTICE_XP if camp else WeeklyPlan.PRACTICE_XP)[lvl]
			return "+%d XP" % roundi(xp * mult)
		WeeklyPlan.STUDY:
			var pts: float = (WeeklyPlan.CAMP_STUDY_POINTS if camp else WeeklyPlan.STUDY_POINTS)[lvl]
			return "+%.1f study" % pts
		WeeklyPlan.OUTING:
			var m: float = (WeeklyPlan.CAMP_OUTING_MORALE if camp else WeeklyPlan.OUTING_MORALE)[lvl]
			return "+%d squad, +%d club" % [roundi(m), roundi(m * WeeklyPlan.OUTING_CLUB_SHARE)]
		WeeklyPlan.BRAND:
			var base: float = (WeeklyPlan.CAMP_BRAND_BASE if camp else WeeklyPlan.BRAND_BASE)[lvl]
			var room := maxf(0.0, 1.0 - p.brand / (WeeklyPlan.BRAND_MAX * WeeklyPlan.BRAND_SOFT))
			return "+%.1f to %.1f brand" % [base * WeeklyPlan.FACTOR_LOW * room, base * WeeklyPlan.FACTOR_HIGH * room]
		WeeklyPlan.SPA:
			if camp:
				return "rehab: -%d Wear" % roundi(lvl * Wear.rehab_per_point)
			return "+%d%% recovery, +%d morale" % [roundi(WeeklyPlan.SPA_RECOVERY[lvl] * 100.0), roundi(WeeklyPlan.SPA_MORALE[lvl])]
	return ""


func _stars_line(p: Soldier, plan: Dictionary, camp: bool) -> String:
	if p.dev >= Soldier.DEV_MAX:
		return "%s  (top star reached)" % p.dev_text()
	var lvl := WeeklyPlan.level(plan, WeeklyPlan.STUDY)
	var pts: float = (WeeklyPlan.CAMP_STUDY_POINTS if camp else WeeklyPlan.STUDY_POINTS)[lvl]
	return "%s   next star: %.1f / %d study points   (this plan adds %.1f)" % [p.dev_text(), p.study_progress, roundi(WeeklyPlan.star_cost(p.dev)), pts]


# --- skill-point placement --------------------------------------------------------------------------

## The offseason cap raise: pick one capped group and raise its ceiling.
func cap_raise_page() -> Control:
	var root := _vbox(10)
	root.custom_minimum_size.x = 1000
	var holder := _vbox(10)
	root.add_child(holder)
	var fns := {}
	fns["render"] = func():
		_clear(holder)
		_fill_cap_raise(holder, fns)
	fns["render"].call()
	return root


func _fill_cap_raise(box: VBoxContainer, fns: Dictionary) -> void:
	var s := _season()
	var p := s.player
	var intro := _label("Once an offseason you can raise one group's ceiling. Fill a group to its cap first; the raise is +2, plus a point each for a strong season, a Performance Institute, a camp special and a story (max +%d). A raise lifts the cap only: you still earn the rating with skill points." % CapRaise.MAX_RAISE, 15, UiKit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 960
	box.add_child(intro)
	var window := CapRaise.window_error(s)
	if window != "":
		box.add_child(_label(window, 16, UiKit.GOLD))
	for g in Stats.UPGRADABLE_GROUPS:
		var row := _hbox(14)
		var name := _label(String(Stats.GROUP_LABELS[g]), 18, Color.WHITE)
		name.custom_minimum_size.x = 150
		row.add_child(name)
		var info := _label("rating %d  /  cap %d" % [p.group_rating(g), p.group_cap(g)], 16, UiKit.TEXT)
		info.custom_minimum_size.x = 220
		row.add_child(info)
		var err := CapRaise.group_error(s, g)
		if err == "":
			var n := CapRaise.size(s, g)
			var why := ", ".join(CapRaise.parts(s, g).map(func(x): return "%s +%d" % [x[0], x[1]]))
			row.add_child(_label("+%d  (%s)" % [n, why], 14, UiKit.GOOD))
			var go := UiKit.primary_button("Raise", func():
				var rep := CapRaise.apply(s, g)
				if not rep.is_empty():
					hub.app.toast("%s cap +%d, now %d." % [Stats.GROUP_LABELS[g], rep["size"], rep["cap"]])
				fns["render"].call(), 16)
			row.add_child(go)
		else:
			row.add_child(_label(err, 14, UiKit.MUTED))
		box.add_child(row)


## Place a group upgrade by hand: one stat point per stat in the group, up to each stat's cap, then confirm.
func placement_page(group: StringName) -> Control:
	var st := {"alloc": {}}
	var root := _vbox(10)
	root.custom_minimum_size.x = 900
	var holder := _vbox(10)
	root.add_child(holder)
	var fns := {}
	fns["render"] = func():
		_clear(holder)
		_fill_placement(holder, group, st, fns)
	fns["render"].call()
	return root


func _fill_placement(box: VBoxContainer, group: StringName, st: Dictionary, fns: Dictionary) -> void:
	var p := _season().player
	var alloc: Dictionary = st["alloc"]
	var members: Array = Stats.group_stats(group)
	var n := members.size()
	var placed := 0
	for k in alloc:
		placed += int(alloc[k])
	var cost := Progression.upgrade_cost(p, group)
	var head := _label("%s: place %d points (+1 to the group). Cost: %d skill points (you have %d)." % [String(Stats.GROUP_LABELS[group]).to_upper(), n, cost, p.skill_points], 18, Color.WHITE)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size.x = 860
	box.add_child(head)
	for stat in members:
		var add := int(alloc.get(stat, 0))
		var cap := mini(Stats.MAX_RATING, p.stat_cap(stat))
		var cur := int(p.stats[stat])
		var row := _hbox(14)
		var name := _label(String(Stats.LABELS[stat]), 18, UiKit.TEXT)
		name.custom_minimum_size.x = 210
		row.add_child(name)
		var minus := UiKit.button("-", func():
			alloc[stat] = maxi(0, int(alloc.get(stat, 0)) - 1)
			fns["render"].call(), 16)
		minus.disabled = add <= 0
		row.add_child(minus)
		var val := _label("%d" % (cur + add) + ("  (+%d)" % add if add > 0 else ""), 20, UiKit.GOOD if add > 0 else Color.WHITE)
		val.custom_minimum_size.x = 130
		row.add_child(val)
		var plus := UiKit.button("+", func():
			alloc[stat] = int(alloc.get(stat, 0)) + 1
			fns["render"].call(), 16)
		plus.disabled = placed >= n or cur + add >= cap
		row.add_child(plus)
		row.add_child(_label("cap %d" % cap, 14, UiKit.BAD if cur + add >= cap else UiKit.MUTED))
		box.add_child(row)
	box.add_child(_label("Points left to place: %d" % (n - placed), 18, UiKit.GOLD if placed < n else UiKit.GOOD))
	var group_now := p.group_rating(group)
	box.add_child(_label("%s rating: %d -> %d once all points are placed" % [Stats.GROUP_LABELS[group], group_now, group_now + 1], 15, UiKit.MUTED))
	var err := Progression.placement_error(p, group, alloc)
	if placed < n:
		err = "Place %d more point%s." % [n - placed, "" if n - placed == 1 else "s"]
	elif err == "":
		err = ""
	if err != "":
		box.add_child(_label(err, 15, UiKit.GOLD if placed < n else UiKit.BAD))
	var foot := _hbox(12)
	var confirm := UiKit.primary_button("Confirm", func():
		var gains := Progression.place_group(p, group, alloc)
		if not gains.is_empty():
			var parts: PackedStringArray = []
			for k in gains:
				if int(gains[k]) > 0:
					parts.append("%s +%d" % [Stats.ABBREV[k], gains[k]])
			hub.app.toast("%s %d  (%s)" % [Stats.GROUP_LABELS[group], p.group_rating(group), ", ".join(parts)])
		hub.go_back(), 22)
	confirm.disabled = placed < n or Progression.placement_error(p, group, alloc) != ""
	foot.add_child(confirm)
	foot.add_child(UiKit.button("Cancel", func(): hub.go_back(), 16))
	box.add_child(foot)

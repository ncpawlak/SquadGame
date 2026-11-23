class_name PlayerDraftPages
extends RefCounted
## Player mode phase 3 (#101): the draft screens. `report` is the scouting report and projected pick, `night` is the
## live pick-by-pick reveal, `offers` is where an undrafted player picks a Green Team deal, `landing` is where the
## career begins. The rules live in PlayerDraft.

const REVEAL_SECS := 0.09
const SUSPENSE_SECS := 0.55
const SUSPENSE_PICKS := 3


static func _frame(title: String, subtitle: String) -> Array:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var wrap := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		wrap.add_theme_constant_override("margin_" + side, 30)
	wrap.add_child(root)
	root.add_child(UiKit.display(title, 44, Color.WHITE, true))
	var bar := ColorRect.new()
	bar.color = UiKit.ACCENT
	bar.custom_minimum_size = Vector2(90, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	root.add_child(bar)
	if subtitle != "":
		root.add_child(UiKit.label(subtitle, 15, UiKit.MUTED))
	return [wrap, root]


static func _who(season: Season) -> String:
	var s := season.player
	return "%s \"%s\" %s  -  %s %s" % [s.first_name, s.callsign, s.last_name,
		Archetypes.find(season.player_archetype)["name"], Scheme.ROLE_NAMES[Archetypes.role_of(season.player_archetype)]]


# --- scouting report ----------------------------------------------------------------------

static func report(season: Season, on_enter: Callable) -> Control:
	var r := PlayerDraft.report(season)
	var f := _frame("DRAFT REPORT", "")
	var root: VBoxContainer = f[1]
	root.name = "DraftReport"
	root.add_child(UiKit.label(_who(season), 18, UiKit.ACCENT))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	root.add_child(cols)

	var left := UiKit.panel(UiKit.PANEL, 12)
	left.custom_minimum_size.x = 470
	cols.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	lv.add_child(UiKit.display("PROJECTED", 22, UiKit.ACCENT, true))
	lv.add_child(UiKit.display(String(r["round_text"]).to_upper(), 54, Color.WHITE, true))
	if r["likely_undrafted"]:
		lv.add_child(UiKit.label("Scouts expect you to go undrafted.", 18, UiKit.BAD))
	else:
		lv.add_child(UiKit.label("Most likely pick %d  (range %d - %d of %d)" % [r["rank"], r["lo"], mini(int(r["hi"]), int(r["picks"])), r["picks"]], 18, UiKit.TEXT))
	lv.add_child(UiKit.label("Class rank: %d of %d     Area scout grade: %s" % [r["rank"], r["class_size"], r["area_grade"]], 16, UiKit.MUTED))
	if r["mock_team"] != null:
		lv.add_child(UiKit.label("Mock draft: pick %d to the %s" % [r["mock_pick"], r["mock_team"].name], 16, UiKit.GOLD))
	else:
		lv.add_child(UiKit.label("Mock draft: no team takes you.", 16, UiKit.GOLD))
	var pad := Control.new()
	pad.custom_minimum_size.y = 10
	lv.add_child(pad)
	var ovr: Vector2i = season.player_combine.ovr_range()
	lv.add_child(UiKit.label("Your combine range: OVR %d - %d" % [ovr.x, ovr.y], 16, UiKit.TEXT))

	var right := UiKit.panel(UiKit.PANEL, 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	rv.add_child(UiKit.display("HOW SCOUTS RATE YOU", 22, UiKit.ACCENT, true))
	for g in Stats.UPGRADABLE_GROUPS:
		if not r["windows"].has(g):
			continue
		var row := HBoxContainer.new()
		var gl := UiKit.label(String(Stats.GROUP_LABELS[g]), 16, UiKit.GOLD)
		gl.custom_minimum_size.x = 120
		row.add_child(gl)
		row.add_child(UiKit.label(Draft.window_text(g, r["windows"][g]), 16, UiKit.TEXT))
		rv.add_child(row)

	var pad2 := Control.new()
	pad2.custom_minimum_size.y = 6
	root.add_child(pad2)
	root.add_child(UiKit.primary_button("Enter the draft", on_enter, 24))
	return f[0]


# --- draft night -----------------------------------------------------------------------------

## The live reveal of `res` (PlayerDraft.run's result): picks appear one at a time, slower just before yours.
static func night(season: Season, res: Dictionary, on_done: Callable) -> Control:
	var f := _frame("DRAFT NIGHT", "")
	var root: VBoxContainer = f[1]
	root.name = "DraftNight"
	var picks: Array = res["picks"]
	var mine: int = int(res["pick"])
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	root.add_child(foot)

	var st := {"i": 0, "done": false}
	var timer := Timer.new()
	timer.one_shot = false
	timer.wait_time = REVEAL_SECS
	root.add_child(timer)

	var show_row := func(row: Dictionary):
		var q: Prospect = row["prospect"]
		var is_me: bool = q.soldier == season.player
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var no := UiKit.label("%d." % row["pick"], 17, UiKit.GOLD if is_me else UiKit.MUTED)
		no.custom_minimum_size.x = 44
		h.add_child(no)
		var tm := UiKit.label(String(row["team"].abbrev), 17, row["team"].color.lightened(0.35))
		tm.custom_minimum_size.x = 60
		h.add_child(tm)
		var nm := UiKit.label(q.soldier.full_name() if not is_me else "%s  (YOU)" % q.soldier.full_name(), 17, Color.WHITE if is_me else UiKit.TEXT)
		nm.custom_minimum_size.x = 300
		h.add_child(nm)
		h.add_child(UiKit.label(String(Scheme.ROLE_NAMES[q.listed_role]), 15, UiKit.MUTED))
		if is_me:
			var pc := PanelContainer.new()
			pc.add_theme_stylebox_override("panel", UiKit.flat(Color(UiKit.GOLD, 0.2), 6, 2, UiKit.GOLD))
			pc.add_child(h)
			list.add_child(pc)
		else:
			list.add_child(h)
		scroll.scroll_vertical = 1000000

	var finish := func():
		if st["done"]:
			return
		st["done"] = true
		timer.stop()
		for c in foot.get_children():
			c.queue_free()
		foot.add_child(UiKit.display("SELECTED" if mine > 0 else "UNDRAFTED", 40, UiKit.GOLD if mine > 0 else UiKit.BAD, true))
		var msg := UiKit.label(PlayerDraft.story(season), 18, UiKit.TEXT)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		foot.add_child(msg)
		foot.add_child(UiKit.primary_button("Continue", on_done, 22))

	var step := func():
		if st["done"]:
			return
		if st["i"] >= picks.size():
			finish.call()
			return
		var row: Dictionary = picks[st["i"]]
		show_row.call(row)
		st["i"] += 1
		if mine > 0 and row["pick"] == mine:
			finish.call()
			return
		var until: int = mine - st["i"]
		timer.wait_time = SUSPENSE_SECS if (mine > 0 and until >= 0 and until < SUSPENSE_PICKS) else REVEAL_SECS

	timer.timeout.connect(step)
	foot.add_child(UiKit.button("Skip to my pick", func():
		while not st["done"]:
			step.call(), 16))
	timer.autostart = true
	return f[0]


# --- undrafted offers ------------------------------------------------------------------------

static func offers(season: Season, on_signed: Callable) -> Control:
	var f := _frame("UNDRAFTED", "")
	var root: VBoxContainer = f[1]
	root.name = "DraftOffers"
	root.add_child(UiKit.label(_who(season), 18, UiKit.ACCENT))
	var salary := Contracts.green_salary_for(season.player)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	root.add_child(row)
	for t in PlayerDraft.undrafted_offers(season):
		var card := UiKit.panel(UiKit.PANEL, 12)
		card.custom_minimum_size = Vector2(300, 220)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		v.add_child(UiKit.team_logo(t, 64))
		v.add_child(UiKit.display(t.name.to_upper(), 24, Color.WHITE, true))
		v.add_child(UiKit.label("Team OVR %d" % t.team_ovr(), 15, UiKit.MUTED))
		v.add_child(UiKit.label("Green Team deal: %s" % Contracts.money(salary), 15, UiKit.TEXT))
		v.add_child(UiKit.action_button("Sign with them", func():
			var err := PlayerDraft.sign_undrafted(season, t)
			if err == "":
				on_signed.call(), 18))
		row.add_child(card)
	return f[0]


# --- landing --------------------------------------------------------

static func landing(season: Season, on_continue: Callable) -> Control:
	var f := _frame("YOUR CAREER BEGINS", "")
	var root: VBoxContainer = f[1]
	root.name = "DraftLanding"
	var team := season.player_team
	root.add_child(UiKit.label(_who(season), 20, UiKit.ACCENT))
	root.add_child(UiKit.team_logo(team, 96))
	root.add_child(UiKit.display(team.name.to_upper(), 36, Color.WHITE, true))
	var s := season.player
	var how := "Drafted with pick %d" % season.player_pick if season.player_pick > 0 else "Signed as an undrafted free agent"
	root.add_child(UiKit.label("%s. Green Team deal: %s." % [how, Contracts.money(s.contract.salary)], 18, UiKit.TEXT))
	root.add_child(UiKit.primary_button("Begin your rookie season", on_continue, 24))
	return f[0]

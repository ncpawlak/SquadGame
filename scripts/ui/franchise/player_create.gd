class_name PlayerCreate
extends RefCounted
## Player mode, step 1 (#100/#101): the create-a-player screen. Pick a face, a name and callsign, a role and an
## archetype, and see the highest rating each stat can reach at the combine (Archetypes.ceilings).
## `make` returns the screen; the caller supplies callbacks and reads the choice from the `done` callback.

const PREVIEW_ID := -77
const STAT_GROUPS := [Stats.ACCURACY, Stats.HANDLING, Stats.PHYSICALITY, Stats.MENTALITY, Stats.OBJECTIVE]
const ROLE_ORDER := [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]


## taken: lower-cased callsigns already in use. on_back: Callable().
## on_done: Callable(choice: Dictionary) with keys first, last, callsign, head, morph, archetype.
static func make(taken: Dictionary, on_back: Callable, on_done: Callable) -> Control:
	var st := {"role": Scheme.Role.FRONTMAN, "arch": &"", "group": "", "head": "", "morph": 1, "age": PlayerCareer.START_AGE, "story": Backstory.DEFAULT}
	st["arch"] = StringName(Archetypes.for_role(st["role"])[0]["id"])
	var heads: Array = FaceSpec.db().get("heads", {}).keys()
	heads.sort()
	if not heads.is_empty():
		st["head"] = heads[0]

	var root := VBoxContainer.new()
	root.name = "PlayerCreate"
	root.add_theme_constant_override("separation", 10)
	var wrap := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		wrap.add_theme_constant_override("margin_" + side, 22)
	wrap.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var back := UiKit.button("< Back", on_back, 18)
	UiKit.style_skewed(back)
	back.custom_minimum_size = Vector2(120, 48)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.set_meta(&"skip_autofocus", true)
	head.add_child(back)
	var sp := Control.new()
	sp.custom_minimum_size.x = 16
	head.add_child(sp)
	var tt := VBoxContainer.new()
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tt.add_child(UiKit.display("CREATE YOUR SOLDIER", 44, Color.WHITE, true))
	var bar := ColorRect.new()
	bar.color = UiKit.ACCENT
	bar.custom_minimum_size = Vector2(90, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tt.add_child(bar)
	tt.add_child(UiKit.label("Pick a face, a name, an archetype and a starting story. Your archetype sets how high each rating can go at the combine; your story sets how fast you grow.", 15, UiKit.MUTED))
	head.add_child(tt)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# --- left: face preview and identity ---------------------------------------------------
	var left := UiKit.panel(UiKit.PANEL, 12)
	left.custom_minimum_size.x = 420
	cols.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	var pic := CenterContainer.new()
	pic.custom_minimum_size.y = 250
	lv.add_child(pic)
	var first := _field(lv, "First name", PlayerCareer.MAX_NAME)
	var last := _field(lv, "Last name", PlayerCareer.MAX_NAME)
	var call := _field(lv, "Callsign", PlayerCareer.MAX_CALLSIGN)
	lv.add_child(UiKit.label("Age", 14, UiKit.MUTED))
	var age_row := HBoxContainer.new()
	age_row.add_theme_constant_override("separation", 10)
	lv.add_child(age_row)
	var age_label := UiKit.display(str(PlayerCareer.START_AGE), 28, Color.WHITE, true)
	age_label.custom_minimum_size.x = 50
	var age_hint := UiKit.label("", 13, UiKit.MUTED)
	age_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var err := UiKit.label("", 14, UiKit.BAD)
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# --- middle: face picker ---------------------------------------------------------------
	var mid := UiKit.panel(UiKit.PANEL, 12)
	mid.custom_minimum_size.x = 360
	cols.add_child(mid)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mid.add_child(mv)
	mv.add_child(UiKit.display("FACE", 22, UiKit.ACCENT, true))
	var filters := HBoxContainer.new()
	mv.add_child(filters)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mv.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	# --- right: archetype ------------------------------------------------------------------
	var right := UiKit.panel(UiKit.PANEL, 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	rv.add_child(UiKit.display("ARCHETYPE", 22, UiKit.ACCENT, true))
	var roles := HBoxContainer.new()
	roles.add_theme_constant_override("separation", 8)
	rv.add_child(roles)
	var archs := HFlowContainer.new()
	archs.name = "Archetypes"
	archs.add_theme_constant_override("h_separation", 8)
	archs.add_theme_constant_override("v_separation", 8)
	rv.add_child(archs)
	var blurb := UiKit.label("", 16, UiKit.TEXT)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(blurb)
	rv.add_child(UiKit.display("STARTING STORY", 22, UiKit.ACCENT, true))
	var stories := HFlowContainer.new()
	stories.name = "Stories"
	stories.add_theme_constant_override("h_separation", 8)
	stories.add_theme_constant_override("v_separation", 8)
	rv.add_child(stories)
	var story_blurb := UiKit.label("", 15, UiKit.TEXT)
	story_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(story_blurb)
	var story_fx := VBoxContainer.new()
	story_fx.add_theme_constant_override("separation", 2)
	rv.add_child(story_fx)
	var ceil_box := VBoxContainer.new()
	ceil_box.add_theme_constant_override("separation", 4)
	ceil_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(ceil_box)

	# --- footer ----------------------------------------------------------------------------
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	root.add_child(foot)
	err.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(err)
	var go := UiKit.primary_button("Continue", func(): pass, 22)
	foot.add_child(go)

	var fns := {}
	fns["age"] = func():
		age_label.text = str(st["age"])
		var off := Archetypes.age_offset(st["age"])
		age_hint.text = "Every rating ceiling %s. Younger means rawer now, with more room and more seasons to grow." % ("is full" if off == 0 else "is %d lower" % -off)
		fns["ceilings"].call()
	age_row.add_child(UiKit.button("-", func():
		st["age"] = maxi(Archetypes.AGE_MIN, st["age"] - 1)
		fns["age"].call(), 16))
	age_row.add_child(age_label)
	age_row.add_child(UiKit.button("+", func():
		st["age"] = mini(Archetypes.AGE_MAX, st["age"] + 1)
		fns["age"].call(), 16))
	lv.add_child(age_hint)
	fns["preview"] = func():
		for c in pic.get_children():
			c.queue_free()
		if st["head"] == "":
			return
		var temp := PlayerCareer.create_soldier(PREVIEW_ID, "Preview", "Soldier", "Preview", st["head"], st["morph"], st["arch"], st["age"])
		Portrait.drop_cached_mesh(PREVIEW_ID)
		pic.add_child(Portrait.new(temp, 240, UiKit.ACCENT))
	fns["heads"] = func():
		for c in grid.get_children():
			c.queue_free()
		for hid in heads:
			if st["group"] != "" and FaceSpec.db()["heads"][hid]["group"] != st["group"]:
				continue
			var b := Button.new()
			b.custom_minimum_size = Vector2(104, 128)
			b.clip_contents = true
			var tex := TextureRect.new()
			tex.texture = load(FaceSpec.HEADS_DIR + hid + ".webp")
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
			b.add_child(tex)
			UiKit.style_button(b, UiKit.PANEL_HI, UiKit.ACCENT if hid == st["head"] else Color.TRANSPARENT, 6)
			b.pressed.connect(func():
				st["head"] = hid
				fns["heads"].call()
				fns["preview"].call())
			grid.add_child(b)
	fns["ceilings"] = func():
		for c in ceil_box.get_children():
			c.queue_free()
		var a := Archetypes.find(st["arch"])
		blurb.text = String(a.get("blurb", ""))
		var cc := Archetypes.ceilings(st["arch"], st["age"])
		var ups: Dictionary = a.get("up", {})
		var downs: Dictionary = a.get("down", {})
		for g in STAT_GROUPS:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var gl := UiKit.label(String(Stats.GROUP_LABELS[g]), 14, UiKit.MUTED)
			gl.custom_minimum_size.x = 96
			row.add_child(gl)
			for stat in Stats.GROUPS[g]:
				var key := String(stat)
				var col := UiKit.TEXT
				if ups.has(key):
					col = UiKit.GOOD
				elif downs.has(key):
					col = UiKit.BAD
				var cell := UiKit.label("%s %d" % [Stats.ABBREV[stat], cc[stat]], 15, col)
				cell.custom_minimum_size.x = 76
				row.add_child(cell)
			ceil_box.add_child(row)
		ceil_box.add_child(UiKit.label("Green: raised by your archetype.  Red: lowered.  These are the highest ratings the combine can award.", 13, UiKit.MUTED))
		ceil_box.add_child(UiKit.label("Starting OVR is capped at %d whatever you score." % Archetypes.START_OVR_CAP, 13, UiKit.MUTED))
	fns["stories"] = func():
		for c in stories.get_children():
			c.queue_free()
		for id in Backstory.ORDER:
			var b := UiKit.button(Backstory.story_name(id), func():
				st["story"] = id
				fns["stories"].call(), 15)
			if id == st["story"]:
				UiKit.style_primary(b)
			stories.add_child(b)
		story_blurb.text = String(Backstory.find(st["story"])["blurb"])
		for c in story_fx.get_children():
			c.queue_free()
		for fx in Backstory.effects(st["story"]):
			var col := UiKit.TEXT
			if int(fx[1]) > 0:
				col = UiKit.GOOD
			elif int(fx[1]) < 0:
				col = UiKit.BAD
			story_fx.add_child(UiKit.label("• " + String(fx[0]), 14, col))
	fns["archs"] = func():
		for c in archs.get_children():
			c.queue_free()
		for a in Archetypes.for_role(st["role"]):
			var id := StringName(a["id"])
			var b := UiKit.button(String(a["name"]), func():
				st["arch"] = id
				fns["archs"].call()
				fns["ceilings"].call()
				fns["preview"].call(), 15)
			if id == st["arch"]:
				UiKit.style_primary(b)
			archs.add_child(b)
	fns["roles"] = func():
		for c in roles.get_children():
			c.queue_free()
		for r in ROLE_ORDER:
			var role: Scheme.Role = r
			var b := UiKit.button(String(Scheme.ROLE_NAMES[role]), func():
				st["role"] = role
				st["arch"] = StringName(Archetypes.for_role(role)[0]["id"])
				fns["roles"].call()
				fns["archs"].call()
				fns["ceilings"].call(), 17)
			if role == st["role"]:
				UiKit.style_primary(b)
			roles.add_child(b)
	for g in ["", "light", "dark", "brown", "asian"]:
		filters.add_child(UiKit.button("All" if g == "" else String(g).capitalize(), func():
			st["group"] = g
			fns["heads"].call(), 14))
	filters.add_child(UiKit.button("Reroll", func():
		st["morph"] += 1
		fns["preview"].call(), 14))

	go.pressed.connect(func():
		var msg := PlayerCareer.problem(first.text, last.text, call.text, st["head"], st["arch"])
		if msg == "" and taken.has(PlayerCareer.clean(call.text, PlayerCareer.MAX_CALLSIGN).to_lower()):
			msg = "That callsign is already taken in the league."
		err.text = msg
		if msg == "":
			on_done.call({"first": PlayerCareer.clean(first.text, PlayerCareer.MAX_NAME),
				"last": PlayerCareer.clean(last.text, PlayerCareer.MAX_NAME),
				"callsign": PlayerCareer.clean(call.text, PlayerCareer.MAX_CALLSIGN),
				"head": st["head"], "morph": st["morph"], "archetype": st["arch"], "age": st["age"], "backstory": st["story"]}))

	fns["roles"].call()
	fns["archs"].call()
	fns["stories"].call()
	fns["ceilings"].call()
	fns["heads"].call()
	fns["age"].call()
	fns["preview"].call()
	return wrap


static func _field(parent: Control, caption: String, limit: int) -> LineEdit:
	parent.add_child(UiKit.label(caption, 14, UiKit.MUTED))
	var e := LineEdit.new()
	e.max_length = limit
	e.custom_minimum_size.y = 40
	parent.add_child(e)
	return e

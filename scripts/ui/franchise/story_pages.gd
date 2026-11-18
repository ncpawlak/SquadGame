class_name StoryPages
extends RefCounted
## The Storylines screens (opened from the Home to-do): a list of this season's stories, and a page
## for each one with the scenario, what needs to be done, and the choices with what each earns
## and costs. Text comes from StoryDefs; choices go through Storylines.choose.

const PAGE_W := 1100
const CARD_W := 520
const PURPLE := Color("#a855f7")


## Every story shown on the list: running ones first, then this season's finished ones.
static func stories(season: Season) -> Array:
	var shown: Array = season.storylines.active.duplicate()
	shown.append_array(season.storylines.finished_in(season.year))
	return shown


# --- season summary --------------------------------------------------------------------------

## How a story ended, as a word and a colour.
static func _verdict_label(st: Dictionary) -> Array:
	match st["status"]:
		Storylines.STATUS_WON:
			return ["WON", UiKit.GOOD]
		Storylines.STATUS_LOST:
			return ["LOST", UiKit.BAD]
		Storylines.STATUS_SPLIT:
			return ["SPLIT", UiKit.GOLD]
		Storylines.STATUS_FIZZLED:
			return ["FIZZLED", UiKit.MUTED]
	return ["STILL RUNNING", UiKit.INFO]


## The call the player made on a story, in words.
static func _choice_text(st: Dictionary) -> String:
	if st["choice"] == &"":
		return "No call made yet"
	if st["choice"] == StoryDefs.STAY:
		return "No call made: it played out on its own"
	for o: Dictionary in StoryDefs.DEFS.get(st["kind"], {}).get("options", []):
		if o["id"] == st["choice"]:
			return String(o["label"]).replace("{name}", String(st.get("name", "the player")))
	return String(st["choice"])


## One season's stories in one place: the tally, what they earned, and each story with the call you
## made and what came of it.
static func summary_page(season: Season, hub, year: int) -> Control:
	var v := VBoxContainer.new()
	v.name = "StorySummary"
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size.x = PAGE_W
	var sl := season.storylines
	var shown := sl.all_in(year)
	if shown.is_empty():
		v.add_child(UiKit.label("No storylines were played in %d." % year, 17, UiKit.MUTED))
		return v
	var t := sl.season_totals(year)
	var parts: Array[String] = ["%d stor%s" % [t["count"], "y" if t["count"] == 1 else "ies"]]
	for k in ["won", "lost", "split", "fizzled", "open"]:
		if int(t[k]) > 0:
			parts.append("%d %s" % [t[k], "still running" if k == "open" else k])
	v.add_child(_para(", ".join(PackedStringArray(parts)), 17))
	var gains: Array[String] = []
	if absf(float(t["buzz"])) >= 0.5:
		gains.append("buzz %+d" % roundi(float(t["buzz"])))
	if int(t["sp"]) > 0:
		gains.append("%d skill point%s" % [t["sp"], "" if int(t["sp"]) == 1 else "s"])
	if not gains.is_empty():
		v.add_child(_para("What the stories earned directly: %s. Squad morale and XP lumps are listed on each story below." % ", ".join(PackedStringArray(gains)), 15, UiKit.MUTED))
	# Wins first, then splits, losses, fizzles and anything still open.
	var order := {Storylines.STATUS_WON: 0, Storylines.STATUS_SPLIT: 1, Storylines.STATUS_LOST: 2, Storylines.STATUS_FIZZLED: 3}
	var rows := shown.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		var oa: int = order.get(a["status"], 4)
		var ob: int = order.get(b["status"], 4)
		return oa < ob if oa != ob else int(a["id"]) < int(b["id"]))
	for st: Dictionary in rows:
		var verdict := _verdict_label(st)
		var card := UiKit.panel(UiKit.PANEL, 10)
		card.custom_minimum_size.x = PAGE_W - 40
		card.set_meta("story_id", st["id"])
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		card.add_child(col)
		col.add_child(UiKit.rich("[color=%s]%s[/color]  [color=#8b97ab]%s[/color]" % [UiKit.hex(verdict[1]), verdict[0], StoryDefs.KIND_LABEL.get(st["kind"], "STORY")], 13))
		col.add_child(UiKit.display(String(st["title"]), 24, Color.WHITE))
		col.add_child(_para("Your call: %s" % _choice_text(st), 15, UiKit.MUTED, PAGE_W - 80))
		for l in StoryDefs.outcome_lines(st):
			col.add_child(_para("-  %s" % String(l), 15, UiKit.TEXT, PAGE_W - 80))
		var id: int = st["id"]
		col.add_child(UiKit.action_button("Read the story", func(): hub.open(String(st["title"]), func(): return detail_page(season, id, hub))))
		v.add_child(card)
	return v


# --- list ------------------------------------------------------------------------------------

static func list_page(season: Season, hub) -> Control:
	var v := VBoxContainer.new()
	v.name = "StorylinesPage"
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size.x = PAGE_W
	var shown := stories(season)
	# A summary tile for each season that has stories on file (newest first, a few at most).
	var summaries := 0
	for year: int in season.storylines.years_on_file():
		if summaries >= 3:
			break
		if season.storylines.finished_in(year).is_empty():
			continue
		summaries += 1
		var t := season.storylines.season_totals(year)
		var y := year
		var sum_tile := UiKit.tile("%d season in stories" % year, "%d stor%s  -  %d won, %d lost" % [t["count"], "y" if t["count"] == 1 else "ies", t["won"], t["lost"]],
			Vector2(PAGE_W - 40, 84), UiKit.GOLD, func(): hub.open("%d in stories" % y, func(): return summary_page(season, hub, y)), "")
		sum_tile.set_meta("summary_year", year)
		v.add_child(sum_tile)
	if shown.is_empty():
		if summaries == 0:
			v.add_child(UiKit.label("No storylines are running right now.", 17, UiKit.MUTED))
		return v
	v.add_child(UiKit.label("Pick a story to read it, see what it needs and make your call.", 16, UiKit.MUTED))
	for st: Dictionary in shown:
		var live: bool = st["status"] == Storylines.STATUS_ACTIVE
		var sub := "%s  -  %s  -  %s" % [StoryDefs.KIND_LABEL.get(st["kind"], "STORY"), season.storylines.stage_name(st).to_upper(), season.storylines.status_line(st, season)]
		var badge := "DECISION NEEDED" if Storylines.decision_open(st) else ("" if live else "DONE")
		var id: int = st["id"]
		var tile := UiKit.tile(String(st["title"]), sub, Vector2(PAGE_W - 40, 104), PURPLE if live else UiKit.MUTED,
			func(): hub.open(String(st["title"]), func(): return detail_page(season, id, hub)), badge)
		tile.set_meta("story_id", id)
		v.add_child(tile)
	return v


# --- detail ----------------------------------------------------------------------------------

static func detail_page(season: Season, id: int, hub) -> Control:
	var v := VBoxContainer.new()
	v.name = "StoryDetail"
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size.x = PAGE_W
	var st := _find(season, id)
	if st.is_empty():
		v.add_child(UiKit.label("This story is no longer on file.", 17, UiKit.MUTED))
		return v
	var sl := season.storylines
	var live: bool = st["status"] == Storylines.STATUS_ACTIVE
	var kicker := "%s  -  %s" % [StoryDefs.KIND_LABEL.get(st["kind"], "STORY"), sl.stage_name(st).to_upper()]
	v.add_child(UiKit.label(kicker, 14, UiKit.GOLD if live else UiKit.MUTED))

	v.add_child(UiKit.heading("The scenario", 20))
	v.add_child(_para(StoryDefs.scenario(st, season), 17))

	v.add_child(UiKit.heading("What needs to be done", 20))
	for o in StoryDefs.objectives(st, season):
		v.add_child(_para("-  %s" % String(o), 17))
	if not st["results"].is_empty():
		for r: Dictionary in st["results"]:
			var colr := UiKit.hex(UiKit.GOOD if r["won"] else UiKit.BAD)
			v.add_child(UiKit.rich("[color=%s]%s[/color]  Week %d  -  %s" % [colr, "W" if r["won"] else "L", int(r["week"]), UiKit.esc(String(r["score"]))], 15))

	var dec := StoryDefs.decision(st)
	if not (dec["options"] as Array).is_empty():
		v.add_child(UiKit.heading("Your call", 20))
		if dec["open"]:
			v.add_child(_para("%s Pick one %s. This can't be changed once you lock it in." % [dec["prompt"], dec["window"]], 16, UiKit.MUTED))
		elif st["choice"] == StoryDefs.STAY:
			v.add_child(_para("The first meeting came before you made a call, so this one played out on its own.", 16, UiKit.MUTED))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		for o: Dictionary in dec["options"]:
			row.add_child(_option_card(season, st, o, dec["open"], hub))
		v.add_child(row)

	var lines := StoryDefs.outcome_lines(st)
	if not lines.is_empty():
		v.add_child(UiKit.heading("What happened", 20))
		for l in lines:
			v.add_child(_para("-  %s" % String(l), 16))
	return v


static func _option_card(season: Season, st: Dictionary, o: Dictionary, open: bool, hub) -> Control:
	var chosen: bool = st["choice"] == o["id"]
	var card := UiKit.panel(UiKit.PANEL_HI if chosen else UiKit.PANEL, 10)
	card.custom_minimum_size.x = CARD_W
	card.set_meta("option_id", o["id"])
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	if chosen:
		col.add_child(UiKit.label("YOUR CHOICE", 13, UiKit.GOLD))
	col.add_child(UiKit.display(String(o["label"]), 26, Color.WHITE))
	col.add_child(_para(String(o["blurb"]), 15, UiKit.MUTED, CARD_W - 50))
	_effect_block(col, "RIGHT AWAY", o["now"], UiKit.INFO)
	_effect_block(col, "REWARDS", o["good"], UiKit.GOOD)
	_effect_block(col, "COSTS", o["bad"], UiKit.BAD)
	if String(o["note"]) != "":
		col.add_child(_para(String(o["note"]), 14, UiKit.MUTED, CARD_W - 50))
	if open:
		var id: int = st["id"]
		var option: StringName = o["id"]
		var title := String(st["title"])
		col.add_child(UiKit.action_button("Choose this", func():
			var err := season.storylines.choose(season, id, option)
			if err == "":
				hub.replace(title, func(): return detail_page(season, id, hub))))
	elif not chosen and st["choice"] != &"":
		card.modulate = Color(1, 1, 1, 0.5)
	return card


static func _effect_block(col: VBoxContainer, title: String, lines: Array, color: Color) -> void:
	if lines.is_empty():
		return
	col.add_child(UiKit.label(title, 13, color))
	for l in lines:
		col.add_child(_para("-  %s" % String(l), 15, UiKit.TEXT, CARD_W - 50))


static func _para(text: String, size := 16, color := UiKit.TEXT, width := PAGE_W - 40) -> Label:
	var l := UiKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


static func _find(season: Season, id: int) -> Dictionary:
	for st in season.storylines.active:
		if int(st["id"]) == id:
			return st
	for st in season.storylines.finished:
		if int(st["id"]) == id:
			return st
	return {}

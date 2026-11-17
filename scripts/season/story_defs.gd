class_name StoryDefs
extends RefCounted
## What each story says and what its choices do (issue #104). The text the player reads (scenario,
## objectives, option rewards and costs) is generated from the same tables Storylines applies, so
## the page can never promise something the engine does not do.
##
## Effects are Dictionaries with any of: heat (rivalry heat, both clubs), buzz (club buzz heat),
## morale and xp (every player on the roster and the Green Team; xp is base XP before the
## age/dev multiplier, and a match is worth about 250).

const FUEL := &"fuel"
const COOL := &"cool"
## Not a choice the player picks: what the story falls back to when the window closes undecided.
const STAY := &"stay"

## Rivalry Run: effects the moment a choice is made.
const RR_NOW := {
	&"fuel": {"heat": 15.0, "buzz": 2.0},
	&"cool": {"heat": -10.0},
}
## Rivalry Run: effects when the series ends, by choice then verdict.
const RR_END := {
	&"fuel": {&"won": {"buzz": 6.0, "morale": 3.0, "xp": 200.0}, &"lost": {"buzz": -4.0, "morale": -3.0}, &"split": {"buzz": 2.0}},
	&"cool": {&"won": {"buzz": 2.0, "morale": 1.0, "xp": 100.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"morale": 1.0}, &"lost": {}, &"split": {}},
}

const RR_OPTIONS := [
	{"id": &"fuel", "label": "Fuel the feud",
		"blurb": "Talk it up. Make every meeting a grudge match and let the city feel it."},
	{"id": &"cool", "label": "Keep it professional",
		"blurb": "Lower the temperature. Treat these as ordinary games on the calendar."},
]


# --- text ------------------------------------------------------------------------------------

## "Buzz +3, morale +3, +200 XP each" for one effect dictionary ("" if it is empty).
static func effect_text(e: Dictionary) -> String:
	var parts: Array[String] = []
	if e.has("heat"):
		parts.append("rivalry heat %+d" % roundi(float(e["heat"])))
	if e.has("buzz"):
		parts.append("buzz %+d" % roundi(float(e["buzz"])))
	if e.has("morale"):
		parts.append("morale %+d" % roundi(float(e["morale"])))
	if e.has("xp"):
		parts.append("%+d XP" % roundi(float(e["xp"])))
	if parts.is_empty():
		return ""
	var s := ", ".join(PackedStringArray(parts))
	return s.substr(0, 1).to_upper() + s.substr(1)


## Who morale and XP effects reach.
const WHO := "Morale and XP go to every player on your roster and Green Team."


## True if any effect in the list gives morale or XP (so the card should say who gets it).
static func reaches_players(effects: Array) -> bool:
	for e: Dictionary in effects:
		if e.has("morale") or e.has("xp"):
			return true
	return false


## True if an effect helps the club (used to sort lines into rewards and costs).
static func is_good(e: Dictionary) -> bool:
	return float(e.get("buzz", 0.0)) + float(e.get("morale", 0.0)) + float(e.get("xp", 0.0)) > 0.0


## The decision a story is waiting on: {open, prompt, options:[{id,label,blurb,now:[],good:[],bad:[]}]}.
static func decision(st: Dictionary) -> Dictionary:
	if st["kind"] != Storylines.RIVALRY_RUN:
		return {"open": false, "prompt": "", "options": []}
	var opts: Array = []
	for o: Dictionary in RR_OPTIONS:
		var id: StringName = o["id"]
		var now: Array = []
		var good: Array = []
		var bad: Array = []
		var n := effect_text(RR_NOW.get(id, {}))
		if n != "":
			now.append(n)
		for verdict: StringName in [&"won", &"split", &"lost"]:
			var e: Dictionary = RR_END[id][verdict]
			var t := effect_text(e)
			if t == "":
				continue
			var line := "%s the series: %s" % [{&"won": "Win", &"lost": "Lose", &"split": "Split"}[verdict], t]
			(good if is_good(e) else bad).append(line)
		if bad.is_empty() and id == COOL:
			bad.append("Less buzz and no big payoff if you win")
		var all: Array = RR_END[id].values()
		all.append(RR_NOW.get(id, {}))
		opts.append({"id": id, "label": o["label"], "blurb": o["blurb"], "now": now, "good": good, "bad": bad,
			"note": WHO if reaches_players(all) else ""})
	return {"open": Storylines.decision_open(st), "prompt": "How do you play this rivalry?", "options": opts}


static func scenario(st: Dictionary, season: Season) -> String:
	var user := season.league.team_by_abbrev(st["team"])
	var rival := season.league.team_by_abbrev(st["rival"])
	if user == null or rival == null:
		return ""
	var rv := season.rivalries
	var kind := ""
	var f := rv.flags(user, rival)
	if f & Rivalries.TEAM and Rivalries.anchor_name(user.abbrev, rival.abbrev) != "":
		kind = "one of the league's permanent rivalries"
	elif f & Rivalries.TEAM:
		kind = "a rivalry that boiled over on its own"
	else:
		kind = "a rivalry between division mates"
	var text := "The %s and the %s are %s. They meet %d time%s in the regular season." % [
		user.nickname, rival.nickname, kind, st["total"], "" if int(st["total"]) == 1 else "s"]
	var h2h := season.ledger.series_text(user, rival)
	if h2h != "No meetings yet":
		text += " Head to head: %s." % h2h
	text += " Everything you do around these games gets noticed, by the room and by the city."
	return text


## What has to happen, with progress.
static func objectives(st: Dictionary, season: Season) -> Array:
	var rival := season.league.team_by_abbrev(st["rival"])
	var rn := rival.nickname if rival != null else String(st["rival"])
	var total: int = st["total"]
	var wins := 0
	for r in st["results"]:
		if r["won"]:
			wins += 1
	var played: int = st["results"].size()
	var need := total / 2 + 1
	var out: Array = []
	if st["status"] != Storylines.STATUS_ACTIVE:
		out.append("Series with the %s: %s (%d of %d meetings won)" % [rn, String(st["status"]).capitalize(), wins, total])
		return out
	var left := total - played
	out.append("Win the series: take %d of %d meetings from the %s  -  %d won so far, %d to play" % [need, total, rn, wins, left])
	var user := season.league.team_by_abbrev(st["team"])
	for m: ScheduledMatch in season.matches_for(user):
		if not m.is_played() and m.stage == Season.STAGE_REGULAR and m.opponent_of(user) == rival:
			out.append("Next meeting: %s, %s" % [season.week_label(m.week), "at home" if m.home == user else "away"])
			break
	return out


## The outcome of a finished story, as lines for the page ("" choice = nothing happened).
static func outcome_lines(st: Dictionary) -> Array:
	var out: Array = []
	for l in st.get("applied", []):
		out.append(String(l))
	return out

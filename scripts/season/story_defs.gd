class_name StoryDefs
extends RefCounted
## What each story says and what its choices do (issue #104). The text the player reads (scenario,
## objectives, option rewards and costs) is generated from the same tables Storylines applies, so
## the page can never promise something the engine does not do.
##
## Effects are Dictionaries with any of:
##   heat    rivalry heat between the two clubs
##   buzz    club buzz heat
##   morale  every player on the roster and Green Team
##   xp      base XP for every player on the roster and Green Team (before the age/dev multiplier;
##           a match is worth about 250)
##   t_morale, t_xp, t_sp, t_trust   the same for the story's one featured player (st["soldier"]);
##           t_sp is skill points
##   t_request   1.0 = the featured player asks for a trade

const FUEL := &"fuel"
const COOL := &"cool"
const START := &"start"
const SLOW := &"slow"
const HYPE := &"hype"
const DOWN := &"down"
const PROMISE := &"promise"
const HOLD := &"hold"
const EMBRACE := &"embrace"
const DEFLECT := &"deflect"
const FIRE_UP := &"fire_up"
const CALM := &"calm"
const MINUTES := &"minutes"
const IGNORE := &"ignore"
## Not a choice the player picks: what a story falls back to when its window closes undecided.
const STAY := &"stay"

const KIND_LABEL := {
	&"rivalry_run": "ARC", &"rookie_rise": "ARC", &"revenge_game": "SPOTLIGHT", &"contract_standoff": "CONDITIONAL",
	&"cinderella": "ARC", &"derby_week": "SPOTLIGHT", &"bench_grumble": "CONDITIONAL",
}

# --- Rivalry Run -------------------------------------------------------------------------------
const RR_NOW := {
	&"fuel": {"heat": 15.0, "buzz": 2.0},
	&"cool": {"heat": -10.0},
}
const RR_END := {
	&"fuel": {&"won": {"buzz": 6.0, "morale": 3.0, "xp": 200.0}, &"lost": {"buzz": -4.0, "morale": -3.0}, &"split": {"buzz": 2.0}},
	&"cool": {&"won": {"buzz": 2.0, "morale": 1.0, "xp": 100.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"morale": 1.0}, &"lost": {}, &"split": {}},
}
const RR_OPTIONS := [
	{"id": &"fuel", "label": "Fuel the feud",
		"blurb": "Talk it up. Make every meeting a grudge match and let the city feel it."},
	{"id": &"cool", "label": "Keep it professional",
		"blurb": "Lower the temperature. Treat these as ordinary games on the calendar.",
		"cost": "Less buzz and no big payoff if you win"},
]

# --- Rookie's Rise -----------------------------------------------------------------------------
const RISE_NOW := {
	&"start": {"t_morale": 4.0},
	&"slow": {},
}
const RISE_END := {
	&"start": {&"won": {"buzz": 4.0, "t_xp": 400.0, "t_sp": 1.0, "t_trust": 8.0}, &"lost": {"t_morale": -8.0, "t_trust": -10.0}, &"split": {}},
	&"slow": {&"won": {"t_xp": 150.0, "t_trust": 3.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {}, &"lost": {}, &"split": {}},
}
const RISE_OPTIONS := [
	{"id": &"start", "label": "Give the starts",
		"blurb": "Put {name} in the lineup and let the learning happen on the job. {name} has to actually play."},
	{"id": &"slow", "label": "Bring along slowly",
		"blurb": "Let {name} develop in training and take the minutes as they come.",
		"cost": "No buzz, and a much smaller payoff"},
]

# --- Revenge Game ------------------------------------------------------------------------------
const REV_NOW := {
	&"hype": {},
	&"down": {},
}
const REV_END := {
	&"hype": {&"won": {"buzz": 4.0, "t_morale": 6.0, "t_xp": 150.0}, &"lost": {"t_morale": -6.0}, &"split": {}},
	&"down": {&"won": {"t_morale": 2.0, "t_xp": 75.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"t_morale": 2.0}, &"lost": {}, &"split": {}},
}
const REV_OPTIONS := [
	{"id": &"hype", "label": "Hype it up",
		"blurb": "Let {name} and the press have their moment against the old club."},
	{"id": &"down", "label": "Play it down",
		"blurb": "It's just another game. Keep the focus on the team.",
		"cost": "Small payoff even in a win"},
]

# --- Contract Standoff -------------------------------------------------------------------------
const CON_NOW := {
	&"promise": {"t_trust": 10.0, "t_morale": 3.0},
	&"hold": {"t_trust": -5.0, "t_morale": -3.0},
}
const CON_END := {
	&"promise": {&"won": {"buzz": 4.0, "morale": 2.0}, &"lost": {"t_trust": -10.0, "t_morale": -5.0}, &"split": {}},
	&"hold": {&"won": {"buzz": 4.0}, &"lost": {"morale": -2.0, "t_request": 1.0}, &"split": {}},
	&"stay": {&"won": {}, &"lost": {}, &"split": {}},
}
const CON_OPTIONS := [
	{"id": &"promise", "label": "Promise to prioritise an extension",
		"blurb": "Tell {name} that a new deal is the front office's next priority. Then deliver."},
	{"id": &"hold", "label": "Hold the line",
		"blurb": "{name} plays out the deal on current terms. No promises, no pressure from you."},
]

# --- Cinderella --------------------------------------------------------------------------------
const CIN_NOW := {
	&"embrace": {"buzz": 2.0},
	&"deflect": {},
}
const CIN_END := {
	&"embrace": {&"won": {"buzz": 6.0, "morale": 3.0, "xp": 150.0}, &"lost": {"buzz": -2.0}, &"split": {}},
	&"deflect": {&"won": {"morale": 1.0, "xp": 75.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"morale": 1.0}, &"lost": {}, &"split": {}},
}
const CIN_OPTIONS := [
	{"id": &"embrace", "label": "Embrace the underdog role",
		"blurb": "Lean into it. Nobody expects anything, so let the city fall in love with a long shot."},
	{"id": &"deflect", "label": "Deflect the talk",
		"blurb": "Ignore the labels and keep the focus on the next match.",
		"cost": "Less buzz and a smaller payoff"},
]

# --- Derby Week --------------------------------------------------------------------------------
const DER_NOW := {
	&"fire_up": {"heat": 8.0, "morale": 2.0},
	&"calm": {"morale": 1.0},
}
const DER_END := {
	&"fire_up": {&"won": {"buzz": 4.0, "morale": 2.0}, &"lost": {"morale": -3.0}, &"split": {}},
	&"calm": {&"won": {"xp": 100.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"morale": 1.0}, &"lost": {}, &"split": {}},
}
const DER_OPTIONS := [
	{"id": &"fire_up", "label": "Fire them up",
		"blurb": "Make it personal. The room goes in angry and the city gets loud."},
	{"id": &"calm", "label": "Stay calm",
		"blurb": "A derby is a game like any other. Keep heads level and trust the preparation.",
		"cost": "No buzz, small morale effect"},
]

# --- Bench Grumble -----------------------------------------------------------------------------
const GRU_NOW := {
	&"minutes": {"t_trust": 6.0, "t_morale": 4.0},
	&"ignore": {},
}
const GRU_END := {
	&"minutes": {&"won": {"t_trust": 3.0, "t_xp": 100.0}, &"lost": {"t_trust": -10.0, "t_morale": -5.0}, &"split": {}},
	&"ignore": {&"won": {}, &"lost": {"t_request": 1.0}, &"split": {}},
	&"stay": {&"won": {}, &"lost": {"t_request": 1.0}, &"split": {}},
}
const GRU_OPTIONS := [
	{"id": &"minutes", "label": "Promise minutes",
		"blurb": "Tell {name} a real shot is coming, and then put {name} in the lineup."},
	{"id": &"ignore", "label": "Let it ride",
		"blurb": "Depth players don't always play. {name} can wait for a chance.",
		"cost": "May ask for a trade if the mood does not recover"},
]

## Per kind: effects when a choice is made, effects when the story ends (by choice then verdict),
## the options, the prompt, and how a verdict reads on an option card.
const DEFS := {
	&"rivalry_run": {"now": RR_NOW, "end": RR_END, "options": RR_OPTIONS, "prompt": "How do you play this rivalry?", "window": "before the first meeting",
		"verdict": {&"won": "Win the series", &"split": "Split the series", &"lost": "Lose the series"}},
	&"rookie_rise": {"now": RISE_NOW, "end": RISE_END, "options": RISE_OPTIONS, "prompt": "How do you handle the rise?", "window": "before the first match",
		"verdict": {&"won": "It works out", &"split": "", &"lost": "The starts don't happen"}},
	&"revenge_game": {"now": REV_NOW, "end": REV_END, "options": REV_OPTIONS, "prompt": "How do you play the build-up?", "window": "before the match is played",
		"verdict": {&"won": "You win", &"split": "", &"lost": "You lose"}},
	&"contract_standoff": {"now": CON_NOW, "end": CON_END, "options": CON_OPTIONS, "prompt": "What do you tell the player?", "window": "within two weeks",
		"verdict": {&"won": "Trust recovers", &"split": "", &"lost": "It turns sour"}},
	&"cinderella": {"now": CIN_NOW, "end": CIN_END, "options": CIN_OPTIONS, "prompt": "How do you handle the underdog tag?", "window": "before the first match",
		"verdict": {&"won": "The run holds up", &"split": "", &"lost": "The run falls short"}},
	&"derby_week": {"now": DER_NOW, "end": DER_END, "options": DER_OPTIONS, "prompt": "What is your message for derby week?", "window": "before the match is played",
		"verdict": {&"won": "You win", &"split": "", &"lost": "You lose"}},
	&"bench_grumble": {"now": GRU_NOW, "end": GRU_END, "options": GRU_OPTIONS, "prompt": "What do you tell the player?", "window": "within two matches",
		"verdict": {&"won": "It settles down", &"split": "", &"lost": "It stays sour"}},
}

## Who morale and XP effects reach.
const WHO := "Morale and XP go to every player on your roster and Green Team."


# --- effects ---------------------------------------------------------------------------------

static func now_effects(st: Dictionary, option: StringName) -> Dictionary:
	return DEFS[st["kind"]]["now"].get(option, {})


static func end_effects(st: Dictionary, choice: StringName, verdict: StringName) -> Dictionary:
	var by_choice: Dictionary = DEFS[st["kind"]]["end"]
	return by_choice.get(choice, by_choice[STAY]).get(verdict, {})


## "Buzz +3, morale +3, +200 XP" for one effect dictionary ("" if it is empty). The featured
## player's parts are named: "Reyes: +400 XP, +1 skill point".
static func effect_text(e: Dictionary, st := {}) -> String:
	var parts: Array[String] = []
	if e.has("heat"):
		parts.append("rivalry heat %+d" % roundi(float(e["heat"])))
	if e.has("buzz"):
		parts.append("buzz %+d" % roundi(float(e["buzz"])))
	if e.has("morale"):
		parts.append("morale %+d" % roundi(float(e["morale"])))
	if e.has("xp"):
		parts.append("%+d XP" % roundi(float(e["xp"])))
	var who := String(st.get("name", "Player"))
	var tp: Array[String] = []
	if e.has("t_xp"):
		tp.append("%+d XP" % roundi(float(e["t_xp"])))
	if e.has("t_sp"):
		tp.append("%+d skill point%s" % [roundi(float(e["t_sp"])), "" if roundi(float(e["t_sp"])) == 1 else "s"])
	if e.has("t_morale"):
		tp.append("morale %+d" % roundi(float(e["t_morale"])))
	if e.has("t_trust"):
		tp.append("trust %+d" % roundi(float(e["t_trust"])))
	if e.has("t_request"):
		tp.append("asks for a trade")
	if not tp.is_empty():
		parts.append("%s: %s" % [who, ", ".join(PackedStringArray(tp))])
	if parts.is_empty():
		return ""
	var s := ", ".join(PackedStringArray(parts))
	return s.substr(0, 1).to_upper() + s.substr(1)


## True if an effect helps the club (used to sort lines into rewards and costs).
static func is_good(e: Dictionary) -> bool:
	var net := 0.0
	for k in ["buzz", "morale", "xp", "t_xp", "t_sp", "t_morale", "t_trust"]:
		net += float(e.get(k, 0.0))
	if e.has("t_request"):
		net -= 100.0
	return net > 0.0


## True if any effect in the list gives team-wide morale or XP (so the card should say who gets it).
static func reaches_players(effects: Array) -> bool:
	for e: Dictionary in effects:
		if e.has("morale") or e.has("xp"):
			return true
	return false


# --- the decision a story is waiting on ------------------------------------------------------

## {open, prompt, options:[{id,label,blurb,now:[],good:[],bad:[],note}]}.
static func decision(st: Dictionary) -> Dictionary:
	if not DEFS.has(st["kind"]):
		return {"open": false, "prompt": "", "window": "", "options": []}
	var def: Dictionary = DEFS[st["kind"]]
	var name := String(st.get("name", "him"))
	var opts: Array = []
	for o: Dictionary in def["options"]:
		var id: StringName = o["id"]
		var now: Array = []
		var good: Array = []
		var bad: Array = []
		var n := effect_text(def["now"].get(id, {}), st)
		if n != "":
			now.append(n)
		for verdict: StringName in [&"won", &"split", &"lost"]:
			var e: Dictionary = def["end"][id][verdict]
			var t := effect_text(e, st)
			var label: String = def["verdict"][verdict]
			if t == "" or label == "":
				continue
			var line := "%s: %s" % [label, t]
			(good if is_good(e) else bad).append(line)
		if o.has("cost"):
			bad.append(String(o["cost"]))
		var all: Array = def["end"][id].values()
		all.append(def["now"].get(id, {}))
		opts.append({"id": id, "label": o["label"], "blurb": String(o["blurb"]).replace("{name}", name),
			"now": now, "good": good, "bad": bad, "note": WHO if reaches_players(all) else ""})
	return {"open": Storylines.decision_open(st), "prompt": def["prompt"], "window": def["window"], "options": opts}


# --- the words -------------------------------------------------------------------------------

static func scenario(st: Dictionary, season: Season) -> String:
	var user := season.league.team_by_abbrev(st["team"])
	var name := String(st.get("name", ""))
	match st["kind"]:
		Storylines.RIVALRY_RUN:
			var rival := season.league.team_by_abbrev(st["rival"])
			if user == null or rival == null:
				return ""
			var kind := ""
			var f := season.rivalries.flags(user, rival)
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
			return text + " Everything you do around these games gets noticed, by the room and by the city."
		Storylines.ROOKIE_RISE:
			return "%s (age %d, %d-star development) is the best young talent in your system. The league is watching to see whether you trust %s with real minutes this season, and %s is watching too." % [
				name, int(st.get("age", 0)), int(st.get("dev", 0)), name, name]
		Storylines.REVENGE_GAME:
			var opp := season.league.team_by_abbrev(st["rival"])
			return "%s used to play for the %s, and this week you face them. %s has been looking forward to this since the schedule came out." % [
				name, opp.nickname if opp != null else String(st["rival"]), name]
		Storylines.CONTRACT_STANDOFF:
			return "%s is in the final year of a contract and is not happy about where things stand. Trust in the front office is low, and the clock is running: if nothing changes, %s will walk in free agency, or ask out before then." % [name, name]
		Storylines.CINDERELLA:
			return "The %s are projected near the bottom of the league this season. Nobody is expecting much, which means a winning record would be a real story." % (user.nickname if user != null else "club")
		Storylines.DERBY_WEEK:
			var dopp := season.league.team_by_abbrev(st["rival"])
			return "This week's match is against the %s, a division mate or a heated rival. These games carry extra weight with fans and the room." % (dopp.nickname if dopp != null else String(st["rival"]))
		Storylines.BENCH_GRUMBLE:
			return "%s is not playing as much as %s would like, and morale has dipped below the line. A word from the front office could settle it, or it could fester." % [name, name]
	return ""


## What has to happen, with progress.
static func objectives(st: Dictionary, season: Season) -> Array:
	var out: Array = []
	var user := season.league.team_by_abbrev(st["team"])
	var name := String(st.get("name", "The player"))
	match st["kind"]:
		Storylines.RIVALRY_RUN:
			var rival := season.league.team_by_abbrev(st["rival"])
			var rn := rival.nickname if rival != null else String(st["rival"])
			var total: int = st["total"]
			var wins := 0
			for r in st["results"]:
				if r["won"]:
					wins += 1
			var played: int = st["results"].size()
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Series with the %s: %s (%d of %d meetings won)" % [rn, String(st["status"]).capitalize(), wins, total])
				return out
			out.append("Win the series: take %d of %d meetings from the %s  -  %d won so far, %d to play" % [total / 2 + 1, total, rn, wins, total - played])
			for m: ScheduledMatch in season.matches_for(user):
				if not m.is_played() and m.stage == Season.STAGE_REGULAR and m.opponent_of(user) == rival:
					out.append("Next meeting: %s, %s" % [season.week_label(m.week), "at home" if m.home == user else "away"])
					break
		Storylines.ROOKIE_RISE:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("%s started %d of %d matches (needed %d)" % [name, st["started"], st["played"], st["need"]])
				return out
			if st["choice"] == SLOW:
				out.append("Keep %s with the club and let the development happen through the season" % name)
			else:
				out.append("Start %s in at least %d of your %d matches  -  %d of %d so far" % [name, st["need"], st["total"], st["started"], st["played"]])
		Storylines.REVENGE_GAME:
			var opp := season.league.team_by_abbrev(st["rival"])
			var on := opp.nickname if opp != null else String(st["rival"])
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Result against the %s: %s" % [on, String(st["status"]).capitalize()])
				return out
			out.append("Beat the %s with %s in the game: %s" % [on, name, season.week_label(st["start_week"])])
			out.append("%s has to be in the lineup. Check your lineup before you play the week." % name)
		Storylines.CONTRACT_STANDOFF:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Where it ended: %s" % String(st["status"]).capitalize())
				return out
			out.append("Win back trust: get %s to Trusting (62) or better before the regular season ends" % name)
			var s: Soldier = Storylines.find_soldier(season, st)
			if s != null:
				out.append("%s trust now: %d (%s)  -  extension talks and kept promises move it" % [name, roundi(s.trust), Soldier.trust_label(s.trust)])
		Storylines.CINDERELLA:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Finished %d-%d (needed %d wins)" % [st["wins"], st["played"] - st["wins"], st["need"]])
				return out
			out.append("Finish with a winning record: %d wins from %d matches  -  %d-%d so far" % [st["need"], st["total"], st["wins"], st["played"] - st["wins"]])
		Storylines.DERBY_WEEK:
			var dopp := season.league.team_by_abbrev(st["rival"])
			var don := dopp.nickname if dopp != null else String(st["rival"])
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Result against the %s: %s" % [don, String(st["status"]).capitalize()])
				return out
			out.append("Beat the %s: %s" % [don, season.week_label(st["start_week"])])
		Storylines.BENCH_GRUMBLE:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Where it ended: %s" % String(st["status"]).capitalize())
				return out
			if st["choice"] == MINUTES:
				out.append("Start %s in one of the next two matches  -  breaking the promise costs trust" % name)
			else:
				out.append("Get %s's morale back to %d or better, or start %s, within two matches" % [name, roundi(Storylines.GRUMBLE_MORALE), name])
			var s: Soldier = Storylines.find_soldier(season, st)
			if s != null:
				out.append("%s morale now: %d (%s)" % [name, roundi(s.morale), Soldier.morale_label(s.morale)])
	return out


## The outcome of a finished story, as lines for the page.
static func outcome_lines(st: Dictionary) -> Array:
	var out: Array = []
	for l in st.get("applied", []):
		out.append(String(l))
	return out

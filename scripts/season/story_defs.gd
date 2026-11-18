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
const TOUR := &"tour"
const COMPETE := &"compete"
const FULL := &"full"
const REST := &"rest"
const ANSWER := &"answer"
const SILENCE := &"silence"
const ALL_IN := &"all_in"
const PROTECT := &"protect"
const RALLY := &"rally"
const STEADY := &"steady"
const EASE := &"ease"
const RUSH := &"rush"
const TOGETHER := &"together"
const MIX := &"mix"
const MEDIATE := &"mediate"
const BACK_STARTER := &"back_starter"
const BACK_BENCH := &"back_bench"
const FEATURE := &"feature"
const TEAM_GAME := &"team_game"
const CEREMONY := &"ceremony"
const TRIBUTE := &"tribute"
const REAFFIRM := &"reaffirm"
const BRUSH_OFF := &"brush_off"
const VOW := &"vow"
const QUIET := &"quiet"
## Not a choice the player picks: what a story falls back to when its window closes undecided.
const STAY := &"stay"

const KIND_LABEL := {
	&"rivalry_run": "ARC", &"rookie_rise": "ARC", &"revenge_game": "SPOTLIGHT", &"contract_standoff": "CONDITIONAL",
	&"cinderella": "ARC", &"derby_week": "SPOTLIGHT", &"bench_grumble": "CONDITIONAL",
	&"last_ride": "ARC", &"statement_game": "SPOTLIGHT", &"press_storm": "CONDITIONAL",
	&"title_chase": "ARC", &"must_win": "SPOTLIGHT", &"comeback_trail": "CONDITIONAL",
	&"bromance": "CONDITIONAL", &"locker_rift": "CONDITIONAL", &"milestone_chase": "SPOTLIGHT",
	&"banner_night": "SPOTLIGHT", &"poaching_rumor": "CONDITIONAL", &"hot_seat": "ARC",
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

# --- Veteran's Last Ride -----------------------------------------------------------------------
const RIDE_NOW := {
	&"tour": {"t_morale": 4.0},
	&"compete": {},
}
const RIDE_END := {
	&"tour": {&"won": {"buzz": 5.0, "morale": 3.0, "xp": 100.0, "t_trust": 5.0}, &"lost": {"t_morale": -6.0, "t_trust": -8.0}, &"split": {}},
	&"compete": {&"won": {"morale": 1.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"morale": 1.0}, &"lost": {}, &"split": {}},
}
const RIDE_OPTIONS := [
	{"id": &"tour", "label": "Give a farewell tour",
		"blurb": "{name} gets guaranteed minutes all season, and the young players learn from the veteran in the lineup."},
	{"id": &"compete", "label": "Let {name} compete",
		"blurb": "Minutes go to whoever earns them, veteran or not.",
		"cost": "No send-off, much smaller payoff"},
]

# --- Statement Game ----------------------------------------------------------------------------
const STM_NOW := {
	&"full": {"morale": 2.0},
	&"rest": {},
}
const STM_END := {
	&"full": {&"won": {"buzz": 5.0, "morale": 2.0, "xp": 150.0}, &"lost": {"morale": -3.0}, &"split": {}},
	&"rest": {&"won": {"buzz": 2.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"buzz": 1.0}, &"lost": {}, &"split": {}},
}
const STM_OPTIONS := [
	{"id": &"full", "label": "Go all out",
		"blurb": "Treat it as the biggest game of the year and tell the room so."},
	{"id": &"rest", "label": "Keep the pressure off",
		"blurb": "Nobody expects a win, so stay relaxed and play it loose.",
		"cost": "Smaller payoff even in a win"},
]

# --- Press Storm -------------------------------------------------------------------------------
const STO_NOW := {
	&"answer": {"buzz": 2.0, "morale": -1.0},
	&"silence": {"buzz": -3.0},
}
const STO_END := {
	&"answer": {&"won": {"buzz": 3.0, "morale": 2.0}, &"lost": {"buzz": -3.0}, &"split": {}},
	&"silence": {&"won": {"morale": 2.0}, &"lost": {"morale": -2.0}, &"split": {}},
	&"stay": {&"won": {}, &"lost": {"buzz": -2.0}, &"split": {}},
}
const STO_OPTIONS := [
	{"id": &"answer", "label": "Face the press",
		"blurb": "Take the questions yourself and own the losing streak in public."},
	{"id": &"silence", "label": "Say nothing",
		"blurb": "No comment. Keep the noise away from the locker room.",
		"cost": "Buzz drops right away"},
]

# --- Title Chase -------------------------------------------------------------------------------
const TIT_NOW := {
	&"all_in": {"buzz": 2.0, "morale": 2.0},
	&"protect": {},
}
const TIT_END := {
	&"all_in": {&"won": {"buzz": 6.0, "morale": 3.0, "xp": 200.0}, &"lost": {"buzz": -4.0, "morale": -3.0}, &"split": {}},
	&"protect": {&"won": {"morale": 1.0, "xp": 100.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"morale": 1.0}, &"lost": {}, &"split": {}},
}
const TIT_OPTIONS := [
	{"id": &"all_in", "label": "Go all in",
		"blurb": "Tell the city this is the year. Every match is a title match."},
	{"id": &"protect", "label": "Protect the long game",
		"blurb": "Stay level, rotate where needed and look after the roster.",
		"cost": "Smaller payoff even if the run works"},
]

# --- Must-Win ----------------------------------------------------------------------------------
const MUS_NOW := {
	&"rally": {"morale": 2.0},
	&"steady": {},
}
const MUS_END := {
	&"rally": {&"won": {"buzz": 3.0, "morale": 2.0}, &"lost": {"morale": -4.0}, &"split": {}},
	&"steady": {&"won": {"buzz": 1.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"buzz": 1.0}, &"lost": {}, &"split": {}},
}
const MUS_OPTIONS := [
	{"id": &"rally", "label": "Rally the room",
		"blurb": "Give the speech of the season and make sure everyone knows what is at stake."},
	{"id": &"steady", "label": "Business as usual",
		"blurb": "Same preparation, same routine. Do not let the pressure in.",
		"cost": "Smaller payoff even in a win"},
]

# --- Comeback Trail ----------------------------------------------------------------------------
const COM_NOW := {
	&"ease": {"t_trust": 3.0},
	&"rush": {"t_morale": 3.0},
}
const COM_END := {
	&"ease": {&"won": {"t_xp": 100.0, "t_trust": 2.0}, &"lost": {}, &"split": {}},
	&"rush": {&"won": {"t_morale": 2.0}, &"lost": {"t_morale": -4.0, "t_trust": -5.0}, &"split": {}},
	&"stay": {&"won": {}, &"lost": {}, &"split": {}},
}
const COM_OPTIONS := [
	{"id": &"ease", "label": "Ease {name} back",
		"blurb": "Manage the minutes and let {name} find the rhythm again.",
		"cost": "No immediate boost"},
	{"id": &"rush", "label": "Throw {name} straight back in",
		"blurb": "The team needs {name} and {name} wants to play. Full minutes from day one."},
]

# --- Bromance ----------------------------------------------------------------------------------
const BRO_NOW := {
	&"together": {},
	&"mix": {"t_morale": -3.0, "p_morale": -3.0},
}
const BRO_END := {
	&"together": {&"won": {"buzz": 2.0, "t_xp": 100.0, "p_xp": 100.0}, &"lost": {"t_morale": -3.0, "p_morale": -3.0}, &"split": {}},
	&"mix": {&"won": {}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {}, &"lost": {}, &"split": {}},
}
const BRO_OPTIONS := [
	{"id": &"together", "label": "Keep them together",
		"blurb": "Start {name} and the partner side by side and let the chemistry do its work. They have to start together in two of the next three matches."},
	{"id": &"mix", "label": "Mix up the lineup",
		"blurb": "Spread them around so nobody gets too comfortable.",
		"cost": "Both take a morale hit and no reward"},
]

# --- Locker Room Rift --------------------------------------------------------------------------
const RIF_NOW := {
	&"mediate": {"t_trust": 4.0, "t_morale": 4.0, "p_morale": 2.0},
	&"back_starter": {"t_trust": -4.0, "t_morale": -3.0, "p_morale": 4.0},
	&"back_bench": {"t_trust": 5.0, "t_morale": 4.0, "p_morale": -4.0},
}
const RIF_END := {
	&"mediate": {&"won": {"t_xp": 100.0, "t_trust": 3.0}, &"lost": {}, &"split": {}},
	&"back_starter": {&"won": {}, &"lost": {}, &"split": {}},
	&"back_bench": {&"won": {}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {}, &"lost": {}, &"split": {}},
}
const RIF_OPTIONS := [
	{"id": &"mediate", "label": "Sit them down together",
		"blurb": "Get both in a room, clear the air and make them work it out."},
	{"id": &"back_starter", "label": "Back the starter",
		"blurb": "The starter has earned the room's respect. The rest can adapt.",
		"cost": "The bench player's morale and trust drop"},
	{"id": &"back_bench", "label": "Back the bench player",
		"blurb": "Make clear the bench player is valued, whatever the starter thinks.",
		"cost": "The starter's morale drops"},
]

# --- Milestone Chase ---------------------------------------------------------------------------
const MIL_NOW := {
	&"feature": {"t_morale": 3.0},
	&"team_game": {},
}
const MIL_END := {
	&"feature": {&"won": {"buzz": 4.0, "t_trust": 4.0, "t_xp": 150.0}, &"lost": {"t_morale": -4.0, "morale": -1.0}, &"split": {}},
	&"team_game": {&"won": {"t_xp": 50.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"t_xp": 50.0}, &"lost": {}, &"split": {}},
}
const MIL_OPTIONS := [
	{"id": &"feature", "label": "Make it {name}'s night",
		"blurb": "Celebrate the milestone in the build-up and let the crowd feel it."},
	{"id": &"team_game", "label": "Play the team game",
		"blurb": "The milestone will take care of itself. Keep the focus on the match.",
		"cost": "Small payoff even in a win"},
]

# --- Banner Night ------------------------------------------------------------------------------
const BAN_NOW := {
	&"ceremony": {"buzz": 3.0, "morale": 2.0},
	&"tribute": {"morale": 1.0},
}
const BAN_END := {
	&"ceremony": {&"won": {"buzz": 3.0, "morale": 2.0}, &"lost": {}, &"split": {}},
	&"tribute": {&"won": {"buzz": 1.0}, &"lost": {}, &"split": {}},
	&"stay": {&"won": {"buzz": 1.0}, &"lost": {}, &"split": {}},
}
const BAN_OPTIONS := [
	{"id": &"ceremony", "label": "Hold a full ceremony",
		"blurb": "Banner, video tribute, the whole building on its feet. Give the night the weight it deserves."},
	{"id": &"tribute", "label": "Keep it low-key",
		"blurb": "A short tribute before the match and then straight to business.",
		"cost": "Smaller buzz and morale boost"},
]

# --- Poaching Rumor ----------------------------------------------------------------------------
const POA_NOW := {
	&"reaffirm": {"t_trust": 6.0, "t_morale": 2.0},
	&"brush_off": {},
}
const POA_END := {
	&"reaffirm": {&"won": {"t_trust": 3.0}, &"lost": {}, &"split": {}},
	&"brush_off": {&"won": {}, &"lost": {"t_request": 1.0}, &"split": {}},
	&"stay": {&"won": {}, &"lost": {"t_request": 1.0}, &"split": {}},
}
const POA_OPTIONS := [
	{"id": &"reaffirm", "label": "Reaffirm the commitment",
		"blurb": "Tell {name} publicly and privately that the club wants {name} here for the long run."},
	{"id": &"brush_off", "label": "Ignore the noise",
		"blurb": "Rumours are rumours. Do not give them the oxygen.",
		"cost": "May end in a trade request if trust slips"},
]

# --- Hot Seat ----------------------------------------------------------------------------------
const SEAT_NOW := {
	&"vow": {"buzz": 3.0},
	&"quiet": {},
}
const SEAT_END := {
	&"vow": {&"won": {"buzz": 6.0, "morale": 3.0}, &"lost": {"buzz": -6.0, "morale": -4.0}, &"split": {}},
	&"quiet": {&"won": {"buzz": 2.0, "morale": 2.0}, &"lost": {"buzz": -1.0}, &"split": {}},
	&"stay": {&"won": {"buzz": 1.0, "morale": 1.0}, &"lost": {"buzz": -1.0}, &"split": {}},
}
const SEAT_OPTIONS := [
	{"id": &"vow", "label": "Vow to make the playoffs",
		"blurb": "Say it in public: this club is going to the postseason, and everyone can hold you to it."},
	{"id": &"quiet", "label": "Stay quietly confident",
		"blurb": "No promises. Do the work and let the results speak.",
		"cost": "Smaller payoff even if the season works out"},
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
	&"last_ride": {"now": RIDE_NOW, "end": RIDE_END, "options": RIDE_OPTIONS, "prompt": "How do you send the veteran off?", "window": "before the first match",
		"verdict": {&"won": "A proper send-off", &"split": "", &"lost": "The minutes don't come"}},
	&"statement_game": {"now": STM_NOW, "end": STM_END, "options": STM_OPTIONS, "prompt": "How do you approach the big game?", "window": "before the match is played",
		"verdict": {&"won": "You win", &"split": "", &"lost": "You lose"}},
	&"press_storm": {"now": STO_NOW, "end": STO_END, "options": STO_OPTIONS, "prompt": "How do you respond to the press?", "window": "within two matches",
		"verdict": {&"won": "The club wins again", &"split": "", &"lost": "The slide goes on"}},
	&"title_chase": {"now": TIT_NOW, "end": TIT_END, "options": TIT_OPTIONS, "prompt": "How do you approach the title chase?", "window": "before the first match",
		"verdict": {&"won": "A top-4 finish", &"split": "", &"lost": "Outside the top 4"}},
	&"must_win": {"now": MUS_NOW, "end": MUS_END, "options": MUS_OPTIONS, "prompt": "How do you handle the pressure?", "window": "before the match is played",
		"verdict": {&"won": "You win", &"split": "", &"lost": "You lose"}},
	&"comeback_trail": {"now": COM_NOW, "end": COM_END, "options": COM_OPTIONS, "prompt": "How do you bring the player back?", "window": "within two matches",
		"verdict": {&"won": "A clean comeback", &"split": "", &"lost": "Hurt again"}},
	&"bromance": {"now": BRO_NOW, "end": BRO_END, "options": BRO_OPTIONS, "prompt": "What do you do with the pair?", "window": "within three matches",
		"verdict": {&"won": "They play together", &"split": "", &"lost": "They drift apart"}},
	&"locker_rift": {"now": RIF_NOW, "end": RIF_END, "options": RIF_OPTIONS, "prompt": "How do you handle the rift?", "window": "within two matches",
		"verdict": {&"won": "The air clears", &"split": "", &"lost": "The rift widens"}},
	&"milestone_chase": {"now": MIL_NOW, "end": MIL_END, "options": MIL_OPTIONS, "prompt": "How do you mark the milestone?", "window": "before the match is played",
		"verdict": {&"won": "You win", &"split": "", &"lost": "You lose"}},
	&"banner_night": {"now": BAN_NOW, "end": BAN_END, "options": BAN_OPTIONS, "prompt": "How do you honour the night?", "window": "before the match is played",
		"verdict": {&"won": "You win", &"split": "", &"lost": "You lose"}},
	&"poaching_rumor": {"now": POA_NOW, "end": POA_END, "options": POA_OPTIONS, "prompt": "How do you answer the rumours?", "window": "within two weeks",
		"verdict": {&"won": "The talk dies down", &"split": "", &"lost": "Trust slips"}},
	&"hot_seat": {"now": SEAT_NOW, "end": SEAT_END, "options": SEAT_OPTIONS, "prompt": "How do you face the pressure?", "window": "before the first match",
		"verdict": {&"won": "You make the playoffs", &"split": "", &"lost": "You miss the playoffs"}},
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
	var pp: Array[String] = []
	if e.has("p_xp"):
		pp.append("%+d XP" % roundi(float(e["p_xp"])))
	if e.has("p_morale"):
		pp.append("morale %+d" % roundi(float(e["p_morale"])))
	if not pp.is_empty():
		parts.append("%s: %s" % [String(st.get("partner_name", "Partner")), ", ".join(PackedStringArray(pp))])
	if parts.is_empty():
		return ""
	var s := ", ".join(PackedStringArray(parts))
	return s.substr(0, 1).to_upper() + s.substr(1)


## True if an effect helps the club (used to sort lines into rewards and costs).
static func is_good(e: Dictionary) -> bool:
	var net := 0.0
	for k in ["buzz", "morale", "xp", "t_xp", "t_sp", "t_morale", "t_trust", "p_xp", "p_morale"]:
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
		Storylines.LAST_RIDE:
			return "%s (age %d) is in the final year of a contract and the end of a long career is in sight. The club has to decide whether to give %s a proper send-off or make %s fight for every minute." % [name, int(st.get("age", 0)), name, name]
		Storylines.STATEMENT_GAME:
			var sopp := season.league.team_by_abbrev(st["rival"])
			return "This week's opponent, the %s, is clearly stronger than your club on paper. Nobody outside the building expects a win, which is what makes one worth something." % (sopp.nickname if sopp != null else String(st["rival"]))
		Storylines.PRESS_STORM:
			return "The club has lost %d straight and the press is circling. What you say, or do not say, sets the mood for the next couple of weeks." % int(st.get("streak", 0))
		Storylines.TITLE_CHASE:
			return "The %s are among the strongest clubs in the league, and the city is starting to talk about a title. Favourites carry more pressure, and the table will show whether the run is real." % (user.nickname if user != null else "club")
		Storylines.MUST_WIN:
			var mopp := season.league.team_by_abbrev(st["rival"])
			return "The regular season is nearly over and the club is right on the playoff line. This match, against the %s, could decide whether there is a postseason at all." % (mopp.nickname if mopp != null else String(st["rival"]))
		Storylines.COMEBACK_TRAIL:
			return "%s is back from a long injury and cleared to play. Everyone wants %s on the court, but a rushed return can undo the recovery." % [name, name]
		Storylines.BROMANCE:
			return "%s and %s have become close, and they are better when they play together. The club can build around the pairing or keep the lineup moving." % [name, String(st.get("partner_name", "a teammate"))]
		Storylines.LOCKER_RIFT:
			return "%s is unhappy and not getting on with %s, who is flying. The mood is spreading, and the front office has to pick how to handle it." % [name, String(st.get("partner_name", "a starter"))]
		Storylines.MILESTONE_CHASE:
			var mopp := season.league.team_by_abbrev(st["rival"])
			return "This week's match against the %s will be %s's %dth career match. The club can make a moment of it or keep the focus on the game." % [mopp.nickname if mopp != null else String(st["rival"]), name, int(st.get("milestone", 0))]
		Storylines.BANNER_NIGHT:
			var bopp := season.league.team_by_abbrev(st["rival"])
			return "The club honours %s (%s) at home this week against the %s. It is a big night for the fans, and for everyone who played with the honouree." % [name, String(st.get("honour", "legend")).to_lower(), bopp.nickname if bopp != null else String(st["rival"])]
		Storylines.POACHING_RUMOR:
			var popp := season.league.team_by_abbrev(st["rival"])
			return "The %s are reported to be interested in %s, and %s has been unsettled for a while. The wrong response could turn rumour into a request." % [popp.nickname if popp != null else String(st["rival"]), name, name]
		Storylines.HOT_SEAT:
			return "The club went %d-%d last season and missed the playoffs. The mood around the front office is tense, and another season without a berth will bring hard questions." % [int(st.get("last_wins", 0)), int(st.get("last_losses", 0))]
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
		Storylines.LAST_RIDE:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("%s started %d of %d matches (needed %d)" % [name, st["started"], st["played"], st["need"]])
				return out
			if st["choice"] == COMPETE:
				out.append("Keep %s with the club through the season" % name)
			else:
				out.append("Start %s in at least %d of your %d matches  -  %d of %d so far" % [name, st["need"], st["total"], st["started"], st["played"]])
		Storylines.STATEMENT_GAME:
			var sopp := season.league.team_by_abbrev(st["rival"])
			var son := sopp.nickname if sopp != null else String(st["rival"])
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Result against the %s: %s" % [son, String(st["status"]).capitalize()])
				return out
			out.append("Beat the %s: %s" % [son, season.week_label(st["start_week"])])
		Storylines.PRESS_STORM:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Where it ended: %s" % String(st["status"]).capitalize())
				return out
			out.append("Win either of your next two matches to stop the slide  -  %d played so far" % int(st["played"]))
		Storylines.TITLE_CHASE:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Finished %d-%d, table position %d (needed top %d)" % [st["wins"], st["played"] - st["wins"], int(st.get("rank", 0)), Storylines.TITLE_FINISH])
				return out
			out.append("Finish in the top %d of the table  -  %d-%d so far" % [Storylines.TITLE_FINISH, st["wins"], st["played"] - st["wins"]])
		Storylines.MUST_WIN:
			var mopp := season.league.team_by_abbrev(st["rival"])
			var mon := mopp.nickname if mopp != null else String(st["rival"])
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Result against the %s: %s" % [mon, String(st["status"]).capitalize()])
				return out
			out.append("Beat the %s: %s" % [mon, season.week_label(st["start_week"])])
		Storylines.COMEBACK_TRAIL:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Where it ended: %s" % String(st["status"]).capitalize())
				return out
			out.append("Get %s through the next two matches without another injury" % name)
		Storylines.BROMANCE:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("%s and %s started together in %d of %d matches (needed %d)" % [name, st["partner_name"], st["together"], st["played"], Storylines.BROMANCE_NEED])
				return out
			out.append("Start %s and %s together in %d of the next %d matches  -  %d so far" % [name, st["partner_name"], Storylines.BROMANCE_NEED, Storylines.BROMANCE_WINDOW, st["together"]])
		Storylines.LOCKER_RIFT:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Where it ended: %s" % String(st["status"]).capitalize())
				return out
			out.append("Get %s's morale above %d within two matches" % [name, roundi(Storylines.RIFT_BENCH_MORALE)])
			var rs: Soldier = Storylines.find_soldier(season, st)
			if rs != null:
				out.append("%s morale now: %d (%s)" % [name, roundi(rs.morale), Soldier.morale_label(rs.morale)])
		Storylines.MILESTONE_CHASE:
			var mopp := season.league.team_by_abbrev(st["rival"])
			var mon := mopp.nickname if mopp != null else String(st["rival"])
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Result against the %s: %s" % [mon, String(st["status"]).capitalize()])
				return out
			out.append("Beat the %s with %s in the lineup: %s" % [mon, name, season.week_label(st["start_week"])])
			out.append("%s has to play. Check your lineup before you play the week." % name)
		Storylines.BANNER_NIGHT:
			var bopp := season.league.team_by_abbrev(st["rival"])
			var bon := bopp.nickname if bopp != null else String(st["rival"])
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Result against the %s: %s" % [bon, String(st["status"]).capitalize()])
				return out
			out.append("Give the night a win against the %s: %s" % [bon, season.week_label(st["start_week"])])
		Storylines.POACHING_RUMOR:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Where it ended: %s" % String(st["status"]).capitalize())
				return out
			out.append("Keep %s's trust at %d or better for two weeks" % [name, roundi(Storylines.POACH_KEEP)])
			var ps: Soldier = Storylines.find_soldier(season, st)
			if ps != null:
				out.append("%s trust now: %d (%s)" % [name, roundi(ps.trust), Soldier.trust_label(ps.trust)])
		Storylines.HOT_SEAT:
			if st["status"] != Storylines.STATUS_ACTIVE:
				out.append("Finished %d-%d, table position %d (the playoff field is the top %d)" % [st["wins"], st["played"] - st["wins"], int(st.get("rank", 0)), season.playoff_teams])
				return out
			out.append("Finish in the top %d of the table to make the playoffs  -  %d-%d so far" % [season.playoff_teams, st["wins"], st["played"] - st["wins"]])
	return out


## The outcome of a finished story, as lines for the page.
static func outcome_lines(st: Dictionary) -> Array:
	var out: Array = []
	for l in st.get("applied", []):
		out.append(String(l))
	return out

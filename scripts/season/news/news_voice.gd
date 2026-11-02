extends "res://scripts/season/news/news_base.gd"
## The beat writer as a character: each writer has a persona (optimist, skeptic, numbers or old-school) that
## colors a closing "take", and makes calls the paper remembers and checks later: a pick for the next
## match, checked in the following issue, and a preseason call on the season, checked in the wrap.

const PERSONAS := ["optimist", "skeptic", "numbers", "oldschool"]
## Rating points added to the writer's read of our side when he makes a pick.
const PICK_BIAS := {"optimist": 3.0, "skeptic": -3.0, "numbers": 0.0, "oldschool": 0.0}

const TAKES := {
	"optimist_won": ["This is the version of the {us_nick} this column has been waiting for.", "Say what you want about the schedule: this team is getting better.", "The ceiling on this club is higher than most people are willing to say."],
	"optimist_lost": ["One loss doesn't change what this team can be. The ceiling is still high.", "Bad nights happen to good teams, and the {us_nick} are a good team.", "Don't read too much into this one. The pieces are still there."],
	"skeptic_won": ["Enjoy it, but one win doesn't settle the real questions about this roster.", "It's a win. The questions about the {us_nick} haven't gone anywhere.", "Good result, same concerns. This column will believe it when it lasts."],
	"skeptic_lost": ["This is what this column worried about all along.", "The warning signs were there, and tonight the {them_nick} found every one of them.", "Losses like this are where the {us_nick}'s real problems show."],
	"numbers_won_fav": ["The ratings had the {us_nick} as the better side, and they played like it.", "Favorites by the numbers, winners on the floor. Nothing surprising here."],
	"numbers_won_dog": ["The ratings gave the {them_nick} the edge. The {us_nick} didn't read them.", "Underdogs by the numbers and winners on the night: that is how a rating stops mattering."],
	"numbers_won_even": ["The ratings had these two level, and the {us_nick} found the difference.", "A coin-flip on paper and the {us_nick} called it right."],
	"numbers_lost_fav": ["The ratings had the {us_nick} as the better side, which makes this one harder to explain.", "Favorites by the numbers, and the numbers lost. It happens, but not often."],
	"numbers_lost_dog": ["The ratings said the {them_nick} were better, and they were.", "Underdogs by the numbers, and the numbers held."],
	"numbers_lost_even": ["The ratings had these two level, and on this night one of them was better.", "A coin-flip on paper, and the {us_nick} lost the toss."],
	"oldschool_won": ["Nothing fancy about it. They took the point, won the fights and went home with the win.", "The {us_nick} won the boring way, which is the best way."],
	"oldschool_lost": ["Games like this are lost in the details, and the {us_nick} didn't sweat the details.", "The {us_nick} got beat by a team that wanted the point more."],
}


func _persona() -> String:
	var writer := String(LeagueData.press_for(_us)[1])
	return PERSONAS[absi(writer.hash()) % PERSONAS.size()]


## One closing opinion in the writer's voice ("" some weeks, so the column isn't always opinionated).
func _take(g: Dictionary, force := false) -> String:
	if not force and not _chance(0.6):
		return ""
	var p := _persona()
	var key := "%s_%s" % [p, "won" if g["won"] else "lost"]
	if p == "numbers":
		var gap := int(g["gap"])
		key += "_" + ("fav" if gap <= -3 else ("dog" if gap >= 3 else "even"))
	return _g("take_" + key, TAKES[key])


## The pick for the next match in the writer's voice, remembered for the next issue ("" with no match).
func _pick_line(nm: ScheduledMatch) -> String:
	if nm == null or not _chance(0.7):
		return ""
	var them: Team = nm.opponent_of(_us)
	var score: float = float(_us.team_ovr() - them.team_ovr()) + float(PICK_BIAS[_persona()]) + (2.0 if nm.home == _us else -1.0)
	var us_wins: bool = score >= 0.0
	memory["pick"] = {"year": _s.year, "opp": them.abbrev, "us": us_wins}
	var ex := {"pick": _nick(_us) if us_wins else _nick(them), "how": "narrowly" if absf(score) < 3.0 else "comfortably"}
	return _g("pick_" + ("us" if us_wins else "them"), ["The pick here: the {pick}, {how}.", "This column has the {pick}, {how}.", "Call it {how} for the {pick}.", "Put the {pick} down, {how}.", "The {pick} get the nod, {how}.", "Lean {pick}, {how}."], ex)


## How last issue's pick turned out ("" when there was none for this opponent).
func _pick_callback(g: Dictionary) -> String:
	var pick: Dictionary = memory.get("pick", {})
	if pick.is_empty():
		return ""
	memory.erase("pick")
	var them: Team = g["them"]
	if int(pick["year"]) != _s.year or pick["opp"] != them.abbrev:
		return ""
	var right: bool = bool(pick["us"]) == bool(g["won"])
	var side := _nick(_us) if pick["us"] else _nick(them)
	return _g("pickcb_" + ("right" if right else "wrong"),
		["Last week's pick of the {side} held up.", "This column had the {side}, and it got that one right.", "The {side} were the pick, and the pick was right."] if right else
		["This column had the {side} last week. That one it got wrong.", "Last week's pick of the {side} did not hold up, and the column owns that.", "The pick was the {side}. The match had other ideas."], {"side": side})


## The preseason call on the season; remembered so the wrap can check it.
func _season_call(pos: int, n: int) -> String:
	var lean: int = {"optimist": 2, "skeptic": -2, "numbers": 0, "oldschool": 0}[_persona()]
	var playoffs := pos <= n / 2 + lean
	memory["season_call"] = {"year": _s.year, "playoffs": playoffs}
	return _g("call_" + ("in" if playoffs else "out"),
		["The call here: the {us_nick} are a playoff team.", "This column has the {us_nick} in the playoffs.", "The {us_nick} make the field, in this writer's view.", "Bet on the {us_nick} to get into the bracket."] if playoffs else
		["The call here: the {us_nick} miss the playoffs.", "This column does not have the {us_nick} in the playoff field.", "The {us_nick} fall short of the bracket, in this writer's view.", "Don't book the {us_nick} for the playoffs."])


## How the preseason call turned out, for the wrap ("" with no call this year).
func _season_callback() -> String:
	var call: Dictionary = memory.get("season_call", {})
	if call.is_empty() or int(call["year"]) != _s.year:
		return ""
	memory.erase("season_call")
	var made := _s.playoff_seeds.has(_us)
	var said := "a playoff team" if call["playoffs"] else "no playoffs"
	if bool(call["playoffs"]) == made:
		return _g("callcb_right", ["The preseason call here was %s, and it held up." % said,
			"Back in the preseason this column said %s. It got that right." % said])
	return _g("callcb_wrong", ["The preseason call here was %s. It was wrong." % said,
		"This column said %s in the preseason, and was wrong about it." % said])


const OFFSEASON_TAKES := {
	"optimist": ["This column likes the direction the {us_nick} are heading.", "There is real reason for optimism around the {us_nick} after this stretch."],
	"skeptic": ["None of this matters if the {us_nick} can't turn it into wins, and this column has questions.", "The offseason is when every team looks good. The real test comes when the matches count."],
	"numbers": ["The ratings will tell the story soon enough; offseason moves are only as good as the numbers behind them.", "Roster building is a game of margins, and this column is watching the margins."],
	"oldschool": ["Matches are won by people who show up, and the {us_nick} are building a group that does.", "Depth and discipline win more than headlines do."],
}
const SEASON_TAKES := {
	"optimist_good": ["This is a club on the way up, and the column said so early.", "Seasons like this are the start of something."],
	"optimist_bad": ["The season fell short, but the pieces for a rebound are on the roster.", "One bad year does not define this club."],
	"skeptic_good": ["A good season, and the questions are still there for next year.", "Enjoy it. The hard part is doing it again."],
	"skeptic_bad": ["This column saw the cracks early, and the season only confirmed them.", "The warning signs were there from the start."],
	"numbers_good": ["The results matched what the ratings suggested for most of the year.", "By the numbers, this was a season the {us_nick} earned."],
	"numbers_bad": ["The ratings said this club was better than its record, or at least that it should have been.", "The numbers never really backed this season, and the record shows it."],
	"oldschool_good": ["They did the simple things well, and it showed in the standings.", "It was the boring kind of good, which is the best kind."],
	"oldschool_bad": ["The details cost them all year.", "Too many nights lost to the small stuff."],
}


## A persona line for an offseason issue ("" some of the time).
func _offseason_take() -> String:
	if not _chance(0.55):
		return ""
	return _g("otake_" + _persona(), OFFSEASON_TAKES[_persona()])


## A persona line looking back at the season, by whether it went well.
func _season_take(good: bool) -> String:
	if not _chance(0.7):
		return ""
	var key := "%s_%s" % [_persona(), "good" if good else "bad"]
	return _g("stake_" + key, SEASON_TAKES[key])

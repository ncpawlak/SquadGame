class_name PlayerRequest
extends RefCounted
## Career mode (#141): the player can ask the club for a trade. He needs a real reason and the club decides whether to
## shop him. If it does, the other teams make real offers through the league's own trade logic (each pays with its own
## players and picks, and the club has to like the package), and he picks one. A refusal costs a little morale and a few
## weeks before he can ask again. Only while the trade window is open, and one move a season.
##
## Reasons (any one will do):
##   playing_time  he is on the bench or the Green Team (from Week 3 on)
##   contender     his club is in the bottom half of the league and he is good enough to matter elsewhere
##   unhappy       morale is well below neutral
## The club will not let a core player go (top 3 on its roster) unless he is unhappy.

const CORE_RANK := 3
const REFUSE_MORALE := -4.0
const COOLDOWN_WEEKS := 4
const MIN_WEEK := 3
const UNHAPPY_GAP := 10.0
const REASON_TEXT := {
	&"playing_time": "You are not playing and want a team where you will.",
	&"contender": "Your club is going nowhere and you want to play for a winner.",
	&"unhappy": "You are unhappy here and want a fresh start.",
}


static func _key(season: Season) -> int:
	return season.year * 1000 + season.week


## Why he may ask right now (a list of reason keys; empty = he has no case).
static func reasons(season: Season) -> Array:
	var out: Array = []
	var p := season.player
	var team := season.user_team()
	if p == null or team == null:
		return out
	var st := PlayerCoach.status(season)
	var early := season.phase == Season.PHASE_REGULAR and not season.preseason_camp and season.week < MIN_WEEK
	if (st["where"] == PlayerCoach.WHERE_BENCH or st["where"] == PlayerCoach.WHERE_GREEN) and not early:
		out.append(&"playing_time")
	if rank_of(season, team) > season.league.teams.size() / 2 and p.best_ovr() >= weakest_starter_ovr(team):
		out.append(&"contender")
	if p.morale <= Soldier.MORALE_NEUTRAL - UNHAPPY_GAP:
		out.append(&"unhappy")
	return out


## 1 = the strongest team in the league.
static func rank_of(season: Season, team: Team) -> int:
	var mine := team.team_ovr()
	var r := 1
	for t in season.league.teams:
		if t != team and t.team_ovr() > mine:
			r += 1
	return r


static func weakest_starter_ovr(team: Team) -> int:
	var worst := 999
	for s in team.starters():
		worst = mini(worst, s.best_ovr())
	return worst if worst != 999 else 0


## "" if he may open the request page's list now, else why not.
static func error(season: Season) -> String:
	var p := season.player
	if p == null or not season.player_mode:
		return "Career mode only."
	if PlayerLegacy.retired(season):
		return "You have retired."
	if not season.trades.window_open(season):
		return "The trade window is closed. It reopens after the Final."
	if p.moved_year == season.year:
		return "You already changed clubs this season."
	if p.request_block > _key(season) and season.phase != Season.PHASE_OFFSEASON:
		return "The club told you no recently. Give it a few weeks."
	if p.is_injured():
		return "You are injured; no club wants to talk to you right now."
	return ""


## The ask: the club decides whether to shop him. If it does, every team that wants him bids with a package from its own
## assets (see Trades.shop_player). Returns {result: refused|none|offers|error, text, reasons, offers}.
static func shop(season: Season) -> Dictionary:
	var err := error(season)
	if err != "":
		return {"result": "error", "text": err}
	var p := season.player
	var mine := season.user_team()
	var why := reasons(season)
	if why.is_empty():
		return _refuse(season, p, "%s: \"Give us a reason. You are playing, your club is fine and you are in good spirits.\"" % mine.name, why)
	if mine.roster.has(p) and mine.roster_count() <= season.trades.min_roster(season):
		return _refuse(season, p, "%s cannot spare a body right now." % mine.name, why)
	if _core(mine, p) and not why.has(&"unhappy"):
		return _refuse(season, p, "%s: \"You are one of our top players. We are not letting you go.\"" % mine.name, why)
	p.shopped = true  # the league may deal for him only while he is being shopped
	p.trade_request = true  # on the block, and he would leave relieved (Trades._move)
	var offers := season.trades.shop_player(season, p)
	p.shopped = false
	p.trade_request = false
	p.trade_offers = offers
	p.trade_offers_key = _key(season)
	season.player_notes.append({"year": season.year, "week": season.week, "text": "Your club agreed to shop you: %d team%s made an offer." % [offers.size(), "" if offers.size() == 1 else "s"]})
	if offers.is_empty():
		p.request_block = _key(season) + 1
		return {"result": "none", "text": "%s shopped you around and nobody would pay for you right now." % mine.name, "reasons": why, "offers": []}
	return {"result": "offers", "text": "%s agreed to shop you. %d team%s made an offer." % [mine.name, offers.size(), "" if offers.size() == 1 else "s"], "reasons": why, "offers": offers}


## Offers still good this week.
static func live_offers(season: Season) -> Array:
	var p := season.player
	if p == null or p.trade_offers_key != _key(season):
		return []
	return p.trade_offers


## He takes `offer`: the club sends him out and gets the package back. Returns {result: granted|error, text}.
static func accept(season: Season, offer: Dictionary) -> Dictionary:
	var err := error(season)
	if err == "" and not live_offers(season).has(offer):
		err = "That offer is no longer on the table."
	var p := season.player
	var mine := season.user_team()
	var dest: Team = offer["team"]
	if err == "":
		p.shopped = true
		p.trade_request = true
		err = season.trades.validate(season, mine, offer["get"], dest, offer["give"])
		p.shopped = false
		p.trade_request = false
	if err != "":
		p.trade_offers.erase(offer)
		return {"result": "error", "text": err}
	p.shopped = true
	p.trade_request = true
	season.trades.execute(season, mine, offer["get"], dest, offer["give"])
	p.shopped = false
	p.trade_request = false
	season.player_team = dest
	p.moved_year = season.year
	p.request_block = 0
	p.trade_offers = []
	p.trade_offers_key = 0
	season.player_notes.append({"year": season.year, "week": season.week, "text": "%s traded you to %s." % [mine.name, dest.name]})
	PlayerLegacy.update(season)
	return {"result": "granted", "text": "Traded to %s." % dest.name}


## Withdraws the request: he stays and the offers go.
static func withdraw(season: Season) -> void:
	var p := season.player
	p.trade_offers = []
	p.trade_offers_key = 0


static func _core(team: Team, p: Soldier) -> bool:
	var better := 0
	for s in team.roster:
		if s != p and s.best_ovr() > p.best_ovr():
			better += 1
	return team.roster.has(p) and better < CORE_RANK


static func _refuse(season: Season, p: Soldier, text: String, why: Array) -> Dictionary:
	p.add_morale(REFUSE_MORALE)
	p.request_block = _key(season) + COOLDOWN_WEEKS
	season.player_notes.append({"year": season.year, "week": season.week, "text": "Your trade request was refused."})
	return {"result": "refused", "text": text, "reasons": why}

class_name Revenue
extends RefCounted
## Club revenue (issue #8, phase 2) and the club fund (issue #50). Money is in $K, like contracts.
## Revenue is a ledger only: each team earns money from four streams, and the board reads it. It never
## credits cash. Cash (the club fund) changes only at the yearly board review (the grant) and when
## money is spent (signing bonuses, the luxury tax; later facilities, issue #38). It carries
## over with no limit and may go below $0.
##
##   tickets   each home game: the team's gate at an average crowd, scaled by how full the stadium is
##             (buzz, the opponent's buzz, a rivalry); playoff gates are a share of that by round.
##   sponsors  a deal set at the start of the season from the buzz the club carried in, paid evenly across
##             the regular season, so winning pays next year and not mid-season.
##   merch     paid evenly across the regular season, scaled by live buzz and the stars on the roster.
##   media     an equal league-wide share for every team.
##   bonus     playoff qualification, each playoff win, the title and the runner-up.
## The market rating sets the size of the first three (a small market earns about 100M, a big one about
## 300M at average buzz); buzz moves them between 0.75x (cold) and 1.25x (Electric). Payroll is NOT paid
## out of this money: the salary cap is its own rule.
##
## Board review (season end, after the luxury tax): every club gets next season's grant from one formula
## (AI clubs too):
##   grant = (market + results + playoffs + awards + development + cap savings) x confidence
##   market       GRANT_BASE .. GRANT_BASE + GRANT_MARKET, linear in market rating (LRK $15M, NYE $90M)
##   results      RESULTS_PER_PLACE per place finished above the preseason team-rating rank, +/- RESULTS_CAP
##   playoffs     PLAYOFF_WIN_GRANT per playoff win, plus TITLE_GRANT for the title
##   awards       AWARD_GRANT per season award or All-League pick, up to AWARD_CAP
##   development  DEV_GRANT per dev-star gain and per rookie-deal player worth ROOKIE_BEAT over his slot, up to DEV_CAP
##   cap savings  SAVINGS_SHARE of the payroll room under the soft cap
##   confidence   CONF_BROKE if the fund is below $0, CONF_SLUMP after SLUMP_SEASONS straight seasons
##                below expectations (the lower applies), else 1
##
## Every figure scales off REFERENCE_PAYROLL, so a new salary scale (issue #41) changes one number.
## No RNG. Saved with the Season.

## The payroll all dollar figures are sized against (today's salary cap). The design figures below are
## for DESIGN_PAYROLL (the pre-#41 cap).
const REFERENCE_PAYROLL := 250000
const DESIGN_PAYROLL := 150000
## Yearly revenue of the smallest and biggest market (ratings RATING_LOW and RATING_HIGH) at average buzz.
const SMALL_TOTAL := 100000
const BIG_TOTAL := 300000
const RATING_LOW := 8
const RATING_HIGH := 98
## Every team's equal share of the league's media money.
const MEDIA_FLAT := 40000
## Shares of the market-driven part (total minus media).
const TICKET_SHARE := 0.55
const SPONSOR_SHARE := 0.30
const MERCH_SHARE := 0.15
## Buzz scales market money from 1 - BUZZ_SWING (buzz 0) to 1 + BUZZ_SWING (buzz 100).
const BUZZ_SWING := 0.25
## Home games a club plays in a regular season, on average (the gate is sized for this many).
const HOME_GAMES := 5.5
## Fixed yearly operating cost.
const OPERATIONS := 25000
## Stadium fill: base, plus per full point of buzz, a rivalry, and the opponent's buzz above or below 50.
const FILL_BASE := 0.62
const FILL_BUZZ := 0.5
const FILL_RIVAL := 0.05
const FILL_OPPONENT := 0.1
const FILL_AVERAGE := 0.87
## A playoff gate as a share of a regular home gate, by round (the league pools part of playoff money, so a deep
## run adds a modest share to a club's ticket revenue).
const STAGE_GATE := {&"quarterfinal": 0.5, &"semifinal": 0.6, &"final": 0.7}
## Capacity by market rating (for attendance figures; pricing is automatic, see #39).
const CAPACITY_BASE := 12000
const CAPACITY_PER_RATING := 280
## Playoff money.
const BONUS_QUALIFY := 3000
const BONUS_WIN := 4000
const BONUS_TITLE := 15000
const BONUS_RUNNER_UP := 6000
## Star power lifts merchandise: per superstar / star on the roster, up to the cap.
const MERCH_SUPERSTAR := 0.04
const MERCH_STAR := 0.02
const MERCH_STAR_CAP := 0.2
## Board grant terms (see the header). A new club opens with its market term.
const GRANT_BASE := 15000
const GRANT_MARKET := 75000
const RESULTS_PER_PLACE := 1000
const RESULTS_CAP := 10000
const PLAYOFF_WIN_GRANT := 5000
const TITLE_GRANT := 15000
const AWARD_GRANT := 2000
const AWARD_CAP := 10000
const DEV_GRANT := 1000
const DEV_CAP := 10000
const ROOKIE_BEAT := 3000
const SAVINGS_SHARE := 0.05
const CONF_BROKE := 0.9
const CONF_SLUMP := 0.75
const SLUMP_SEASONS := 3
## Seasons of ledger kept.
const LEDGER_YEARS := 10
## A sponsor story needs the deal to grow by this much.
const SPONSOR_STORY_GAIN := 0.15

var seeded := false
## Abbrev -> cash balance ($K).
var cash := {}
## Season year -> {abbrev -> ledger}. A ledger is {tickets, sponsors, merch, media, bonus, operations,
## revenue, net, home_games, attendance, sellouts, deal}.
var ledgers := {}
## Abbrev -> this season's sponsor deal (yearly).
var deals := {}
## Abbrev -> last season's sponsor deal.
var last_deals := {}
## Season year -> {abbrev -> luxury tax paid ($K)} (only teams that paid).
var taxes := {}
## Season year -> {abbrev -> board review}: {market, results, playoffs, awards, development, savings,
## confidence, grant, expected, finish, cash_before}.
var grants := {}
## Season year -> {abbrev -> signing bonuses paid ($K)}.
var bonuses := {}


# --- scale ----------------------------------------------------------------------------

static func scale() -> float:
	return float(REFERENCE_PAYROLL) / float(DESIGN_PAYROLL)


## Yearly revenue of a market at average buzz (media included).
static func neutral_total(rating: int) -> float:
	var t := clampf(float(rating - RATING_LOW) / float(RATING_HIGH - RATING_LOW), 0.0, 1.0)
	return lerpf(float(SMALL_TOTAL), float(BIG_TOTAL), t) * scale()


static func media() -> float:
	return MEDIA_FLAT * scale()


## The market-driven part of a market's neutral yearly revenue (tickets, sponsors and merchandise).
static func market_part(rating: int) -> float:
	return neutral_total(rating) - media()


static func operations() -> float:
	return OPERATIONS * scale()


## 0.75 .. 1.25: how buzz scales market money.
static func buzz_factor(buzz: float) -> float:
	return 1.0 + BUZZ_SWING * (buzz - 50.0) / 50.0


static func capacity(rating: int) -> int:
	return CAPACITY_BASE + CAPACITY_PER_RATING * rating


## How full the home team's stadium is, 0.3 .. 1.0.
static func fill(home_buzz: float, away_buzz: float, rivalry: bool) -> float:
	var f := FILL_BASE + FILL_BUZZ * home_buzz / 100.0 + FILL_OPPONENT * (away_buzz - 50.0) / 100.0
	if rivalry:
		f += FILL_RIVAL
	return clampf(f, 0.3, 1.0)


## The gate for one home game ($K): an average crowd earns the market's even share of its ticket money.
static func gate(rating: int, fill_share: float, stage: StringName) -> float:
	var per_game := market_part(rating) * TICKET_SHARE / HOME_GAMES
	return per_game * fill_share / FILL_AVERAGE * float(STAGE_GATE.get(stage, 1.0))


## The market term of the board grant (and a new club's opening fund).
static func market_grant(rating: int) -> float:
	return GRANT_BASE + GRANT_MARKET * clampf(float(rating - RATING_LOW) / float(RATING_HIGH - RATING_LOW), 0.0, 1.0)


## This year's ledger line for `team` ({} before the season has opened).
func ledger_of(year: int, team: Team) -> Dictionary:
	return (ledgers.get(year, {}) as Dictionary).get(team.abbrev, {})


func cash_of(team: Team) -> float:
	return float(cash.get(team.abbrev, 0.0))


## Teams by revenue this year, best first: [{team, ledger}].
func table(season: Season) -> Array:
	var out: Array = []
	for t: Team in season.league.teams:
		var l := ledger_of(season.year, t)
		if not l.is_empty():
			out.append({"team": t, "ledger": l})
	out.sort_custom(func(a, b): return float(a["ledger"]["revenue"]) > float(b["ledger"]["revenue"]))
	return out


# --- setup ----------------------------------------------------------------------------

## Opening fund (the market term of the grant). Also runs on loading an older save that predates revenue.
func ensure(season: Season) -> void:
	if seeded:
		return
	seeded = true
	for t: Team in season.league.teams:
		cash[t.abbrev] = market_grant(t.market_rating)
	_set_deals(season)
	_open_ledger(season)


func begin_season(season: Season) -> void:
	ensure(season)
	last_deals = deals.duplicate()
	_set_deals(season)
	_open_ledger(season)
	_sponsor_stories(season)


## Sponsor deals for the season, from the buzz each club carries in.
func _set_deals(season: Season) -> void:
	deals = {}
	for t: Team in season.league.teams:
		deals[t.abbrev] = market_part(t.market_rating) * SPONSOR_SHARE * buzz_factor(t.buzz)


func _open_ledger(season: Season) -> void:
	var year_ledger := {}
	for t: Team in season.league.teams:
		year_ledger[t.abbrev] = {"tickets": 0.0, "sponsors": 0.0, "merch": 0.0, "media": 0.0, "bonus": 0.0, "operations": 0.0,
			"revenue": 0.0, "net": 0.0, "home_games": 0, "attendance": 0, "sellouts": 0, "deal": float(deals.get(t.abbrev, 0.0))}
	ledgers[season.year] = year_ledger
	var oldest := season.year - LEDGER_YEARS
	for y in ledgers.keys():
		if int(y) <= oldest:
			ledgers.erase(y)


# --- the season -----------------------------------------------------------------------

## After a week is played and the calendar has advanced.
func week(season: Season, played: Array, w: int) -> void:
	ensure(season)
	if not ledgers.has(season.year):
		_open_ledger(season)
	if w <= season.regular_weeks:
		_accrue_week(season)
	var sellouts: Array = []
	for m: ScheduledMatch in played:
		if m.is_played():
			var l := _game(season, m)
			if not l.is_empty() and l["sold_out"]:
				sellouts.append(l)
	if season.phase == Season.PHASE_PLAYOFFS and w == season.regular_weeks:
		for t in season.playoff_seeds:
			_book(season, t, "bonus", BONUS_QUALIFY * scale())
	elif season.phase == Season.PHASE_OFFSEASON:
		_season_over(season)
	_sellout_stories(season, sellouts, season.week_label(w))


## One regular-season week of sponsors, merchandise, media and operating cost for every club.
func _accrue_week(season: Season) -> void:
	var weeks := float(season.regular_weeks)
	for t: Team in season.league.teams:
		_book(season, t, "sponsors", float(deals.get(t.abbrev, 0.0)) / weeks)
		_book(season, t, "merch", market_part(t.market_rating) * MERCH_SHARE / weeks * buzz_factor(t.buzz) * (1.0 + _star_lift(t)))
		_book(season, t, "media", media() / weeks)
		_book(season, t, "operations", operations() / weeks)


func _star_lift(t: Team) -> float:
	var lift := 0.0
	for s in t.roster:
		if s.best_ovr() >= Market.SUPERSTAR_OVR:
			lift += MERCH_SUPERSTAR
		elif s.best_ovr() >= Market.STAR_OVR:
			lift += MERCH_STAR
	return minf(lift, MERCH_STAR_CAP)


## A played match: the home gate, and playoff win money. Returns {team, fill, attendance, sold_out}.
func _game(season: Season, m: ScheduledMatch) -> Dictionary:
	var home := m.home
	var f := fill(home.buzz, m.away.buzz, season.rivalries.is_rivalry(home, m.away))
	_book(season, home, "tickets", gate(home.market_rating, f, m.stage))
	var l := ledger_of(season.year, home)
	if not l.is_empty():
		l["home_games"] = int(l["home_games"]) + 1
		l["attendance"] = int(l["attendance"]) + roundi(capacity(home.market_rating) * f)
		if f >= 1.0:
			l["sellouts"] = int(l["sellouts"]) + 1
	if m.stage != Season.STAGE_REGULAR and m.winner() != null:
		_book(season, m.winner(), "bonus", BONUS_WIN * scale())
	return {"team": home, "fill": f, "sold_out": f >= 1.0}


## The final is played: title money closes the ledgers.
func _season_over(season: Season) -> void:
	var champ := season.champion
	if champ != null:
		_book(season, champ, "bonus", BONUS_TITLE * scale())
		for m in season.playoff_matches:
			if m.stage == Season.STAGE_FINAL and m.is_played() and m.loser() != null:
				_book(season, m.loser(), "bonus", BONUS_RUNNER_UP * scale())


## Adds `amount` to a ledger line (ledger only: revenue never credits the club fund).
func _book(season: Season, team: Team, key: String, amount: float) -> void:
	var l := ledger_of(season.year, team)
	if l.is_empty() or is_zero_approx(amount):
		return
	l[key] = float(l[key]) + amount
	l["revenue"] = float(l["tickets"]) + float(l["sponsors"]) + float(l["merch"]) + float(l["media"]) + float(l["bonus"])
	l["net"] = float(l["revenue"]) - float(l["operations"])


## Season end: every team over the tax line pays the luxury tax on this season's payroll out of
## club cash (it may go below $0). Returns [{team, over, amount}], biggest bill first.
func charge_tax(season: Season) -> Array:
	var out: Array = []
	var paid := {}
	for t: Team in season.league.teams:
		var due := Contracts.tax_due(t, season.year)
		if due <= 0:
			continue
		cash[t.abbrev] = float(cash.get(t.abbrev, 0.0)) - due
		paid[t.abbrev] = due
		out.append({"team": t, "over": Contracts.tax_overage(t, season.year), "amount": due})
	taxes[season.year] = paid
	for y in taxes.keys():
		if int(y) <= season.year - LEDGER_YEARS:
			taxes.erase(y)
	out.sort_custom(func(a, b): return int(a["amount"]) > int(b["amount"]))
	return out


## Why `team` can't promise a `bonus` now ("" = it can). `committed` is bonus money already promised in
## pending offers.
func bonus_error(team: Team, bonus: int, committed := 0) -> String:
	if bonus <= 0:
		return ""
	if frozen(team):
		return "The board has frozen bonuses while the club fund is below $0."
	if bonus + committed > cash_of(team):
		return "Not enough in the club fund: %s available%s." % [Contracts.money(roundi(cash_of(team) - committed)),
			" after pending offers" if committed > 0 else ""]
	return ""


## Pays a signing bonus out of the club fund (it never counts on the cap).
func pay_bonus(season: Season, team: Team, amount: int) -> void:
	if amount <= 0:
		return
	cash[team.abbrev] = cash_of(team) - amount
	if not bonuses.has(season.year):
		bonuses[season.year] = {}
	bonuses[season.year][team.abbrev] = int(bonuses[season.year].get(team.abbrev, 0)) + amount
	for y in bonuses.keys():
		if int(y) <= season.year - LEDGER_YEARS:
			bonuses.erase(y)


func bonuses_paid(year: int, team: Team) -> int:
	return int((bonuses.get(year, {}) as Dictionary).get(team.abbrev, 0))


func tax_paid(year: int, team: Team) -> int:
	return int((taxes.get(year, {}) as Dictionary).get(team.abbrev, 0))


# --- board review (issue #50) -----------------------------------------------------------

## Season end, after the luxury tax: every club's grant for next season is added to its fund.
## Returns [{team, review}], biggest grant first.
func board_review(season: Season) -> Array:
	var finish := {}
	var rows := season.standings()
	for i in rows.size():
		finish[(rows[i].team as Team).abbrev] = i + 1
	var expected := _expected_ranks(season)
	var wins := {}
	for m in season.playoff_matches:
		if m.is_played() and m.winner() != null:
			wins[m.winner().abbrev] = int(wins.get(m.winner().abbrev, 0)) + 1
	var honors := {}
	var gains := {}
	if season.review != null:
		for list in [season.review.awards, season.review.all_league]:
			for a in list:
				if a.get("team") != null:
					honors[(a["team"] as Team).abbrev] = int(honors.get((a["team"] as Team).abbrev, 0)) + 1
		for d in season.review.dev_changes:
			if d.get("team") != null and int(d["to"]) > int(d["from"]):
				gains[(d["team"] as Team).abbrev] = int(gains.get((d["team"] as Team).abbrev, 0)) + 1
	var year_grants := {}
	var out: Array = []
	for t: Team in season.league.teams:
		var k := t.abbrev
		var r := {}
		r["expected"] = int(expected.get(k, finish.get(k, 0)))
		r["finish"] = int(finish.get(k, r["expected"]))
		r["market"] = market_grant(t.market_rating)
		r["results"] = clampf(RESULTS_PER_PLACE * (r["expected"] - r["finish"]), -RESULTS_CAP, RESULTS_CAP)
		r["playoffs"] = PLAYOFF_WIN_GRANT * int(wins.get(k, 0)) + (TITLE_GRANT if season.champion == t else 0)
		r["awards"] = minf(AWARD_CAP, AWARD_GRANT * int(honors.get(k, 0)))
		var dev := int(gains.get(k, 0))
		for so in t.roster:
			if so.contract != null and so.contract.rookie and Contracts.market_value(so) >= so.contract.salary + ROOKIE_BEAT:
				dev += 1
		r["development"] = minf(DEV_CAP, DEV_GRANT * dev)
		r["savings"] = SAVINGS_SHARE * maxi(0, Contracts.SALARY_CAP - Contracts.payroll(t, season.year))
		r["cash_before"] = cash_of(t)
		r["confidence"] = _confidence(season, t, float(r["results"]) < 0.0)
		var total: float = r["market"] + r["results"] + r["playoffs"] + r["awards"] + r["development"] + r["savings"]
		r["grant"] = float(roundi(maxf(0.0, total) * r["confidence"] / 10.0) * 10)
		cash[k] = cash_of(t) + r["grant"]
		year_grants[k] = r
		out.append({"team": t, "review": r})
	grants[season.year] = year_grants
	for y in grants.keys():
		if int(y) <= season.year - LEDGER_YEARS:
			grants.erase(y)
	out.sort_custom(func(a, b): return float(a["review"]["grant"]) > float(b["review"]["grant"]))
	return out


func grant_of(year: int, team: Team) -> Dictionary:
	return (grants.get(year, {}) as Dictionary).get(team.abbrev, {})


## The board's preseason expectations: team-rating rank when the season began (today's rating for an
## older save that never recorded it).
func _expected_ranks(season: Season) -> Dictionary:
	if not season.market.preseason_rank.is_empty():
		return season.market.preseason_rank
	var list: Array = season.league.teams.duplicate()
	list.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	var out := {}
	for i in list.size():
		out[(list[i] as Team).abbrev] = i + 1
	return out


## CONF_BROKE when the fund is below $0, CONF_SLUMP when this and the previous SLUMP_SEASONS - 1
## reviews all finished below expectations; the lower applies.
func _confidence(season: Season, t: Team, below_now: bool) -> float:
	var c := 1.0
	if cash_of(t) < 0.0:
		c = CONF_BROKE
	if below_now:
		var streak := 1
		for back in range(1, SLUMP_SEASONS):
			var g := grant_of(season.year - back, t)
			if g.is_empty() or float(g["results"]) >= 0.0:
				break
			streak += 1
		if streak >= SLUMP_SEASONS:
			c = minf(c, CONF_SLUMP)
	return c


## The board freezes spending while the fund is below $0: no deal may take payroll over the tax line.
func frozen(team: Team) -> bool:
	return cash_of(team) < 0.0


# --- news -----------------------------------------------------------------------------

## A club whose sponsor deal grew a lot this season makes the wire (the two biggest jumps).
func _sponsor_stories(season: Season) -> void:
	if last_deals.is_empty():
		return
	var jumps: Array = []
	for t: Team in season.league.teams:
		var was := float(last_deals.get(t.abbrev, 0.0))
		var now := float(deals.get(t.abbrev, 0.0))
		if was > 0.0 and now / was - 1.0 >= SPONSOR_STORY_GAIN:
			jumps.append({"team": t, "was": was, "now": now})
	jumps.sort_custom(func(a, b): return float(a["now"]) / float(a["was"]) > float(b["now"]) / float(b["was"]))
	for j in jumps.slice(0, 2):
		season.news.sponsor_deal(season, j["team"], float(j["now"]), float(j["was"]))


func _sellout_stories(season: Season, sellouts: Array, when: String) -> void:
	for l in sellouts.slice(0, 2):
		var t: Team = l["team"]
		var led := ledger_of(season.year, t)
		if int(led.get("sellouts", 0)) == 1:
			season.news.sellout(season, when, t)

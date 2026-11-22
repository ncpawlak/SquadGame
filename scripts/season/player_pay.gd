class_name PlayerPay
extends RefCounted
## What the career player earns from his team contract (#141). Contract money is in $K; his cash is in dollars.
## The yearly salary is paid out in equal weekly pieces over the regular season; the signing bonus is a one-time
## payment, up front, the first time it is settled after the deal is signed.


## Pays any unpaid signing bonus. Returns the dollars paid.
static func settle_bonus(season: Season) -> int:
	var p := season.player
	if p == null or not season.player_mode or PlayerLegacy.retired(season) or p.contract == null:
		return 0
	var c := p.contract
	if c.bonus <= 0 or c.bonus_paid:
		return 0
	c.bonus_paid = true
	var dollars := c.bonus * 1000
	p.cash += dollars
	season.player_notes.append({"year": season.year, "week": season.week, "text": "Your signing bonus of %s arrived." % Sponsors.money_text(dollars)})
	return dollars


## One week of salary (regular season only), plus any unpaid bonus. Returns the dollars paid.
static func weekly(season: Season) -> int:
	var paid := settle_bonus(season)
	var p := season.player
	if p == null or not season.player_mode or PlayerLegacy.retired(season) or p.contract == null:
		return paid
	if season.phase != Season.PHASE_REGULAR or season.week > season.regular_weeks:
		return paid
	var pay := roundi(float(p.contract.salary) * 1000.0 / float(maxi(1, season.regular_weeks)))
	p.cash += pay
	return paid + pay + Assets.weekly(season)


## The yearly salary in dollars (0 with no contract).
static func yearly(p: Soldier) -> int:
	return p.contract.salary * 1000 if p != null and p.contract != null else 0

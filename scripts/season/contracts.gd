class_name Contracts
extends RefCounted
## Salary cap rules (Madden-style hard cap, the same for every team). Money is in $K.
##
## - Payroll = salaries of rostered soldiers under contract for the cap year + dead money +
##   signing bonuses paid that year (a bonus stays on the payer's cap if the player leaves).
##   The cap year is the current season, or next season during the offseason.
## - New deals (re-signs, free-agent offers) must fit under the cap, except minimum-salary deals,
##   which are always allowed so a team can fill its roster. Draft picks get fixed rookie deals.
## - Salary floor: a team whose payroll ends a season under SALARY_FLOOR pays the shortfall as a
##   penalty on next season's cap (booked like dead money).
## - Releasing a soldier leaves DEAD_MONEY_SHARE of each remaining year on the cap.
## - Asking salary comes from OVR, age and potential, plus a premium for deal lengths the soldier
##   doesn't want (see preferred_years); free agents drop their price the longer they go unsigned.

const SALARY_CAP := 150000
const SALARY_FLOOR := 20000
const MIN_SALARY := 750
const MAX_SALARY := 20000
## Market salary by OVR (interpolated): [ovr, $K].
const MARKET_CURVE := [[52, 750], [62, 1000], [67, 2000], [72, 4000], [77, 6500], [82, 9000], [87, 14000], [92, 20000]]
const MAX_YEARS := 5
const DEAD_MONEY_SHARE := 0.5
const YEARS_PREMIUM := 0.06
const RESIGN_DISCOUNT := 0.95
## Rookie scale: pick 1 earns ROOKIE_TOP, the last pick ROOKIE_BOTTOM. Years by round.
const ROOKIE_TOP := 5000
const ROOKIE_BOTTOM := 750
const ROOKIE_YEARS := [3, 2, 2]


static func money(k: int) -> String:
	var neg := "-" if k < 0 else ""
	k = absi(k)
	if k >= 1000:
		return "%s$%.2fM" % [neg, k / 1000.0]
	return "%s$%dK" % [neg, k]


static func contract_text(c: Contract) -> String:
	if c == null:
		return "-"
	if c.is_expiring():
		return "%s  EXPIRING" % money(c.salary)
	return "%s x %d yr%s" % [money(c.salary), c.years, "" if c.years == 1 else "s"]


## Fair yearly salary for a soldier: MARKET_CURVE by OVR, a premium for young players with room
## to grow (ceiling over his OVR) and more dev stars, and a discount for players past 30.
static func market_value(s: Soldier) -> int:
	var v := curve_salary(s.best_ovr())
	var youth := clampf((30.0 - s.age) / 8.0, 0.0, 1.0)
	var upside := float(s.potential_ovr() - s.best_ovr())
	v *= 1.0 + (0.012 * clampf(upside - 6.0, -6.0, 14.0) + 0.06 * (s.dev - 2)) * youth
	if s.age > 30:
		v *= maxf(0.5, 1.0 - 0.08 * (s.age - 30))
	return _round_salary(v)


static func curve_salary(ovr: float) -> float:
	if ovr <= MARKET_CURVE[0][0]:
		return float(MARKET_CURVE[0][1])
	for i in range(1, MARKET_CURVE.size()):
		var hi: Array = MARKET_CURVE[i]
		if ovr <= hi[0]:
			var lo: Array = MARKET_CURVE[i - 1]
			return lerpf(lo[1], hi[1], (ovr - lo[0]) / float(hi[0] - lo[0]))
	return float(MARKET_CURVE[-1][1])


## Deal length the soldier wants: young players bet on themselves, prime players want security,
## veterans take what they can get.
static func preferred_years(s: Soldier) -> int:
	if s.age <= 25:
		return 3
	if s.age <= 29:
		return 4
	if s.age <= 32:
		return 2
	return 1


## Yearly salary he asks for a `years`-long deal.
static func asking(s: Soldier, years: int) -> int:
	var v := float(market_value(s)) * s.ask_mult * (1.0 + YEARS_PREMIUM * absi(years - preferred_years(s)))
	return _round_salary(v)


## What one of your own expiring soldiers asks to re-sign (a small hometown discount).
static func resign_asking(s: Soldier, years: int) -> int:
	var v := float(market_value(s)) * RESIGN_DISCOUNT * (1.0 + YEARS_PREMIUM * absi(years - preferred_years(s)))
	return _round_salary(v)


static func rookie_contract(pick_number: int, total_picks: int, year: int) -> Contract:
	var t := 0.0 if total_picks <= 1 else float(pick_number - 1) / float(total_picks - 1)
	var salary := _round_salary(lerpf(ROOKIE_TOP, ROOKIE_BOTTOM, t))
	var rnd := clampi((pick_number - 1) * Draft.ROUNDS / maxi(1, total_picks), 0, ROOKIE_YEARS.size() - 1)
	return Contract.make(salary, ROOKIE_YEARS[rnd], year, true)


## Payroll for `cap_year + ahead` (ahead 0 = the cap year itself). In the offseason an expiring
## deal stays on the cap year as a cap hold (his old salary) until he re-signs or leaves.
static func payroll(team: Team, cap_year: int, ahead := 0) -> int:
	var total := int(team.dead_money.get(cap_year + ahead, 0)) + int(team.bonus_money.get(cap_year + ahead, 0))
	for s in team.roster:
		if s.contract != null and (s.contract.years > ahead or (ahead == 0 and s.contract.is_expiring())):
			total += s.contract.salary
	return total


## The cap hold an expiring soldier carries (his old salary); re-signing him replaces it.
static func cap_hold(s: Soldier) -> int:
	return s.contract.salary if s.contract != null and s.contract.is_expiring() else 0


static func cap_space(team: Team, cap_year: int) -> int:
	return SALARY_CAP - payroll(team, cap_year)


## Whether a new deal paying `salary` fits (minimum deals always fit). `committed` is money
## already promised elsewhere (e.g. pending free-agent offers); negative frees room (a cap hold).
static func fits(team: Team, cap_year: int, salary: int, committed := 0) -> bool:
	return salary <= MIN_SALARY or salary + committed <= cap_space(team, cap_year)


## Whether re-signing `s` at `salary` fits: his new deal replaces his cap hold.
static func resign_fits(team: Team, cap_year: int, s: Soldier, salary: int) -> bool:
	return fits(team, cap_year, salary, -cap_hold(s))


## Dead money left on the cap if `s` is released now: DEAD_MONEY_SHARE of each remaining year.
static func dead_money_if_released(s: Soldier) -> int:
	if s.contract == null or s.contract.years <= 0:
		return 0
	return roundi(s.contract.salary * DEAD_MONEY_SHARE) * s.contract.years


## Books dead money for releasing `s` and clears his contract. The caller moves him off the roster.
static func charge_release(team: Team, s: Soldier, cap_year: int) -> int:
	var total := 0
	if s.contract != null:
		for k in maxi(s.contract.years, 0):
			var amount := roundi(s.contract.salary * DEAD_MONEY_SHARE)
			team.dead_money[cap_year + k] = int(team.dead_money.get(cap_year + k, 0)) + amount
			total += amount
	s.contract = null
	return total


## A season ended: every contract loses a year (expiring deals hit 0).
static func rollover(league: League) -> void:
	for t in league.teams:
		for s in t.roster:
			if s.contract != null:
				s.contract.years -= 1


static func expiring(team: Team) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in team.roster:
		if s.contract != null and s.contract.is_expiring():
			out.append(s)
	return out


## Salary-floor penalty for `cap_year`'s payroll (0 if at or over the floor). Dead money and
## earlier penalties count toward the floor.
static func floor_shortfall(team: Team, cap_year: int) -> int:
	return maxi(0, SALARY_FLOOR - payroll(team, cap_year))


## Season end: teams under the floor have the shortfall booked onto next season's cap.
## Returns [{team, amount}].
static func charge_floor(league: League, cap_year: int) -> Array:
	var out: Array = []
	for t in league.teams:
		var short := floor_shortfall(t, cap_year)
		if short > 0:
			t.dead_money[cap_year + 1] = int(t.dead_money.get(cap_year + 1, 0)) + short
			t.floor_penalties[cap_year] = short
			out.append({"team": t, "amount": short})
	return out


## Starting contracts for a new league: market value with some noise, 1-4 years (veterans
## shorter); teams that come out over the cap have their deals scaled down to fit.
static func assign_initial(league: League, year: int, rng: RandomNumberGenerator) -> void:
	for t in league.teams:
		var total := 0
		for s in t.roster:
			var yrs := rng.randi_range(1, 2) if s.age >= 31 else rng.randi_range(1, 4)
			var salary := _round_salary(market_value(s) * rng.randf_range(0.85, 1.1))
			s.contract = Contract.make(salary, yrs, year - rng.randi_range(0, 2))
			total += salary
		var limit := int(SALARY_CAP * 0.95)
		if total > limit:
			var scale := float(limit) / float(total)
			for s in t.roster:
				s.contract.salary = maxi(MIN_SALARY, _round_salary(s.contract.salary * scale))


static func _round_salary(v: float) -> int:
	return clampi(roundi(v / 10.0) * 10, MIN_SALARY, MAX_SALARY)

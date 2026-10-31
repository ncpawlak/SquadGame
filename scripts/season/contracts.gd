class_name Contracts
extends RefCounted
## Salary cap rules (NBA-style soft cap with a luxury tax, the same for every team). Money is in $K.
##
## - Payroll = salaries of rostered soldiers under contract for the cap year + dead money +
##   signing bonuses paid that year (a bonus stays on the payer's cap if the player leaves).
##   The cap year is the current season, or next season during the offseason.
## - Soft cap (SALARY_CAP): signing another team's free agent needs room under it (pending offers
##   count). Minimum deals, re-signing your own expiring players (Bird rights; his cap hold is
##   freed), extensions and rookie deals may go over it, up to the APRON.
## - Apron: a hard ceiling nothing may cross (signings, re-signs, extensions, trades).
## - Luxury tax: payroll over TAX_LINE at season end costs TAX_RATE in club cash per $1 over.
## - There is no salary floor (issue #41): hoarding cap room is allowed.
## - Releasing a soldier leaves DEAD_MONEY_SHARE of each remaining year on the cap.
## - In-season extensions (players in their last year) are checked against next season's apron
##   and count on future payrolls; the new deal starts at the rollover (see rollover).
## - Asking salary comes from OVR, age and potential, plus a premium for deal lengths the soldier
##   doesn't want (see preferred_years); free agents drop their price the longer they go unsigned.

const SALARY_CAP := 250000
## Every line above the cap is a share of it, so cap growth is one number.
const TAX_LINE := SALARY_CAP * 32 / 25
const APRON := SALARY_CAP * 38 / 25
const TAX_RATE := 1.5
const MIN_SALARY := 1000
const MAX_SALARY := 60000
## Market salary by OVR (interpolated): under 60 the minimum, 60s $2-8M, 70s $8-25M, 80s $25-40M,
## 90s $40-60M. [ovr, $K].
const MARKET_CURVE := [[59, 1000], [60, 2000], [70, 8000], [80, 25000], [90, 40000], [99, 60000]]
const MAX_YEARS := 5
const DEAD_MONEY_SHARE := 0.5
const YEARS_PREMIUM := 0.06
const RESIGN_DISCOUNT := 0.95
## Rookie scale: pick 1 earns ROOKIE_TOP, falling steeply through round 1 (cubic) to ROOKIE_BOTTOM
## at the last pick. Every rookie deal runs ROOKIE_YEARS.
const ROOKIE_TOP := 15000
const ROOKIE_BOTTOM := 1000
const ROOKIE_YEARS := 4
## Salary scale version. Saves and data from before issue #41 (version 0) are rescaled on load
## (see rescale_legacy) from the old scale below.
const ECONOMY_VERSION := 1
const LEGACY_CURVE := [[52, 750], [62, 1000], [67, 2000], [72, 4000], [77, 6500], [82, 9000], [87, 14000], [92, 20000]]
const LEGACY_MIN_SALARY := 750
const LEGACY_MAX_SALARY := 20000
const LEGACY_SALARY_CAP := 150000


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
	return _round_salary(_market_raw(s, MARKET_CURVE))


static func _market_raw(s: Soldier, curve: Array) -> float:
	var v := curve_salary(s.best_ovr(), curve)
	var youth := clampf((30.0 - s.age) / 8.0, 0.0, 1.0)
	var upside := float(s.potential_ovr() - s.best_ovr())
	v *= 1.0 + (0.012 * clampf(upside - 6.0, -6.0, 14.0) + 0.06 * (s.dev - 2)) * youth
	if s.age > 30:
		v *= maxf(0.5, 1.0 - 0.08 * (s.age - 30))
	return v


static func curve_salary(ovr: float, curve: Array = MARKET_CURVE) -> float:
	if ovr <= curve[0][0]:
		return float(curve[0][1])
	for i in range(1, curve.size()):
		var hi: Array = curve[i]
		if ovr <= hi[0]:
			var lo: Array = curve[i - 1]
			return lerpf(lo[1], hi[1], (ovr - lo[0]) / float(hi[0] - lo[0]))
	return float(curve[-1][1])


## `old_salary` (a deal signed on the pre-#41 scale) on today's scale: his new market value times
## how far over or under his old market value the deal was.
static func rescale_legacy(s: Soldier, old_salary: int) -> int:
	var old_market := clampf(roundf(_market_raw(s, LEGACY_CURVE) / 10.0) * 10.0, LEGACY_MIN_SALARY, LEGACY_MAX_SALARY)
	return _round_salary(market_value(s) * float(old_salary) / old_market)


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
	return Contract.make(rookie_salary(pick_number, total_picks), ROOKIE_YEARS, year, true)


## Slot salary for pick `pick_number` of `total_picks`: min + (top - min)(1 - t)^3.
static func rookie_salary(pick_number: int, total_picks: int) -> int:
	var t := 0.0 if total_picks <= 1 else clampf(float(pick_number - 1) / float(total_picks - 1), 0.0, 1.0)
	return _round_salary(ROOKIE_BOTTOM + (ROOKIE_TOP - ROOKIE_BOTTOM) * pow(1.0 - t, 3.0))


## Payroll for `cap_year + ahead` (ahead 0 = the cap year itself). In the offseason an expiring
## deal stays on the cap year as a cap hold (his old salary) until he re-signs or leaves. An agreed
## extension counts from the season after his current deal ends.
static func payroll(team: Team, cap_year: int, ahead := 0) -> int:
	var total := int(team.dead_money.get(cap_year + ahead, 0)) + int(team.bonus_money.get(cap_year + ahead, 0))
	for s in team.roster:
		if s.contract != null and (s.contract.years > ahead or (ahead == 0 and s.contract.is_expiring())):
			total += s.contract.salary
		elif extension_covers(s, ahead):
			total += s.ext_salary
	return total


## Whether `s`'s agreed extension pays him `ahead` seasons from the cap year.
static func extension_covers(s: Soldier, ahead: int) -> bool:
	if s.contract == null or not s.has_extension():
		return false
	var start := maxi(1, s.contract.years)
	return ahead >= start and ahead < start + s.ext_years


## The cap hold an expiring soldier carries (his old salary); re-signing him replaces it.
static func cap_hold(s: Soldier) -> int:
	return s.contract.salary if s.contract != null and s.contract.is_expiring() else 0


## Room under the soft cap: what a free-agent signing needs.
static func cap_space(team: Team, cap_year: int) -> int:
	return SALARY_CAP - payroll(team, cap_year)


## Room under the apron (`ahead` seasons past the cap year): the hard ceiling for every deal.
static func apron_room(team: Team, cap_year: int, ahead := 0) -> int:
	return APRON - payroll(team, cap_year, ahead)


## How far `cap_year`'s payroll is over the tax line (0 if under).
static func tax_overage(team: Team, cap_year: int) -> int:
	return maxi(0, payroll(team, cap_year) - TAX_LINE)


## Luxury tax owed on `cap_year`'s payroll ($K of club cash).
static func tax_due(team: Team, cap_year: int) -> int:
	return roundi(tax_overage(team, cap_year) * TAX_RATE)


## Whether a free-agent deal paying `salary` fits under the soft cap. `committed` is money
## already promised elsewhere (e.g. pending free-agent offers). Minimum deals always fit, so a
## team can fill its roster.
static func fits(team: Team, cap_year: int, salary: int, committed := 0) -> bool:
	return salary <= MIN_SALARY or salary + committed <= cap_space(team, cap_year)


## Whether re-signing `s` at `salary` fits (Bird rights): his new deal replaces his cap hold and
## may go over the soft cap, but not the apron.
static func resign_fits(team: Team, cap_year: int, s: Soldier, salary: int) -> bool:
	return salary <= MIN_SALARY or salary - cap_hold(s) <= apron_room(team, cap_year)


## Room under next season's (`year` + 1) apron, counting agreed extensions: what an in-season
## extension is checked against.
static func next_apron_room(team: Team, year: int) -> int:
	return apron_room(team, year, 1)


## Whether an in-season extension paying `salary` next season (plus a bonus booked on that year)
## fits under next season's apron. Minimum deals always fit.
static func extension_fits(team: Team, year: int, salary: int, bonus := 0) -> bool:
	return (salary <= MIN_SALARY and bonus <= 0) or salary + bonus <= next_apron_room(team, year)


## Dead money left on the cap if `s` is released now: DEAD_MONEY_SHARE of each remaining year.
static func dead_money_if_released(s: Soldier) -> int:
	if s.contract == null or s.contract.years <= 0:
		return 0
	return roundi(s.contract.salary * DEAD_MONEY_SHARE) * s.contract.years


## Books dead money for releasing `s` and clears his contract (an agreed extension is voided; its
## bonus stays booked). The caller moves him off the roster.
static func charge_release(team: Team, s: Soldier, cap_year: int) -> int:
	var total := 0
	if s.contract != null:
		for k in maxi(s.contract.years, 0):
			var amount := roundi(s.contract.salary * DEAD_MONEY_SHARE)
			team.dead_money[cap_year + k] = int(team.dead_money.get(cap_year + k, 0)) + amount
			total += amount
	s.contract = null
	s.clear_extension()
	return total


## A season ended: every contract loses a year (expiring deals hit 0). An expiring soldier with an
## agreed extension starts it now (signed in `year`), so he never reaches the re-sign window.
static func rollover(league: League, year := 0) -> void:
	for t in league.teams:
		for s in t.roster:
			if s.contract != null:
				s.contract.years -= 1
				if s.contract.is_expiring() and s.has_extension():
					s.contract = Contract.make(s.ext_salary, s.ext_years, year)
					s.contract.bonus = s.ext_bonus
					s.contract.no_trade = s.ext_no_trade
					s.clear_extension()


static func expiring(team: Team) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in team.roster:
		if s.contract != null and s.contract.is_expiring():
			out.append(s)
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


## Moves a league signed on the pre-#41 scale onto today's: every contract and agreed extension by
## the player's own ratio (rescale_legacy); dead money and bonuses by the team's payroll ratio;
## pending free-agent `offers` by the player's ratio; a team left over the apron has its deals
## trimmed to fit. Salary-floor penalties still waiting on next
## season's cap (stashed by Team._migrate_prop) are dropped: there is no floor any more.
static func migrate_legacy(league: League, offers: Array, cap_year: int) -> void:
	for t in league.teams:
		var pen: Dictionary = t.get_meta(&"legacy_floor_penalties", {})
		for y in pen:
			var y1 := int(y) + 1
			if t.dead_money.has(y1):
				t.dead_money[y1] = maxi(0, int(t.dead_money[y1]) - int(pen[y]))
		if t.has_meta(&"legacy_floor_penalties"):
			t.remove_meta(&"legacy_floor_penalties")
		var before := 0
		var after := 0
		for s in t.roster:
			if s.contract != null:
				var old := s.contract.salary
				s.contract.salary = rescale_legacy(s, old)
				var ratio := float(s.contract.salary) / maxf(1.0, old)
				s.contract.bonus = roundi(s.contract.bonus * ratio / 10.0) * 10
				before += old
				after += s.contract.salary
			if s.has_extension():
				var old_ext := s.ext_salary
				s.ext_salary = rescale_legacy(s, old_ext)
				s.ext_bonus = roundi(s.ext_bonus * float(s.ext_salary) / maxf(1.0, old_ext) / 10.0) * 10
		var f := float(after) / float(before) if before > 0 else float(SALARY_CAP) / float(LEGACY_SALARY_CAP)
		for book: Dictionary in [t.dead_money, t.bonus_money]:
			for y in book:
				book[y] = roundi(int(book[y]) * f / 10.0) * 10
		var over := payroll(t, cap_year) - APRON
		if over > 0 and after > 0:
			var k := maxf(0.0, 1.0 - float(over) / float(after))
			for s in t.roster:
				if s.contract != null:
					s.contract.salary = _round_salary(floorf(s.contract.salary * k))
	for o: Dictionary in offers:
		o["salary"] = rescale_legacy(o["soldier"], int(o["salary"]))

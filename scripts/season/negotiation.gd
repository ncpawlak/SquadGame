class_name Negotiation
extends RefCounted
## Re-signing talks with one of your expiring soldiers. Deterministic: every outcome comes from his
## DNA, his trust in you, his bonds with teammates, real season data and your leverage.
##
## - His demand is Contracts.resign_asking(years) x demand_mult. The opening mult comes from DNA
##   (money up, loyalty down), trust, hometown, his bonds on the roster and his opening statements
##   (star treatment, teammate comparison, a broken promise).
## - An offer is salary plus deal terms ({bonus, no_trade, promise, keep}). Each term is worth
##   something to him (value_to_him): a signing bonus counts more for money-driven players, a
##   no-trade clause for loyal / hometown players, a starter promise for players who want playing
##   time, and promising to keep his closest teammate for loyal players with a strong bond.
## - He signs when the offer's value reaches his demand AND the cash per year (salary + bonus /
##   years) reaches his floor (what he believes the open market would pay). Terms can't buy him
##   below his floor.
## - Every action costs patience; at 0 he walks into free agency. Below his demand he counters
##   (closing part of the gap); lowballs cost extra patience and trust with thin-skinned players.
## - Arguments (SELL and HARDBALL tabs) only exist when the data backs them up. Strength =
##   evidence x DNA fit x leverage. A poor fit backfires (trust and patience drop, demand rises);
##   weak evidence gets rebutted by savvy players. Each can be used once; later ones have
##   diminishing returns.
## - Tactics: Ask what it'll take (reveals a floor range and his favourite term), Smooth it over
##   (repairs trust after a misstep), Sleep on it (patience back, but his demand drifts toward
##   where it opened) and Final offer (take it or leave it: he signs or walks).
## - Walkouts, insults and backfires are logged to Season.talks_log for storylines.
##
## Extension mode (Season.negotiation in the regular season, for a player in his last contract
## year): the same talks, but the deal is checked against next season's cap and stored on the
## soldier as a pending extension (Soldier.ext_*) that replaces his contract at the rollover.
## Two extra arguments ("Lock in now", "Test the market"), Sleep on it pauses talks until next
## week, and a walkout blocks talks until the re-sign window, where he opens with
## EXT_WALK_PATIENCE less patience and EXT_WALK_DEMAND more demand.

const MAX_PATIENCE := 100.0
const ROUND_COST := 20.0
const LOWBALL_SHARE := 0.85
const LOWBALL_COST := 12.0
const ARG_CUT := 0.13
const DIMINISH := 0.85
const BACKFIRE_FIT := 0.2
const REBUT_EVIDENCE := 0.45
const PROMISE_CUT := 0.09
const SIGN_TRUST := 4.0
const WALK_TRUST := -10.0
const ASK_COST := 10.0
const SMOOTH_COST := 15.0
const SMOOTH_TRUST_BELOW := 45.0
const SLEEP_PATIENCE := 25.0
const SLEEP_DRIFT := 0.30
const BACKFIRE_MULT := 1.03
const EXT_WALK_PATIENCE := 20.0
const EXT_WALK_DEMAND := 0.03
## Extra patience lost when "Test the market" backfires (he might just do it).
const TEST_MARKET_COST := 10.0

const OPEN := &"open"
const SIGNED := &"signed"
const WALKED := &"walked"

const SELL := &"sell"
const HARDBALL := &"hardball"
## Deal terms an offer can carry besides salary and years.
const TERMS: Array[StringName] = [&"bonus", &"no_trade", &"promise", &"keep"]
const TERM_NAMES := {&"bonus": "Signing bonus", &"no_trade": "No-trade clause", &"promise": "Starter promise", &"keep": "Keep the core"}

var season: Season
var team: Team
var soldier: Soldier
var demand_mult := 1.0
var opening_mult := 1.0
var floor_mult := 0.8
var patience := MAX_PATIENCE
var state: StringName = OPEN
## Argument id -> result ("landed", "rebutted", "backfired").
var used := {}
## Conversation: Array of {who: "you" | "him" | "note", text}.
var talk: Array = []
## What "Ask what it'll take" told you: {low, high, years, term} ({} until asked).
var revealed := {}
var smoothed := false
var slept := false
## Backfires and insults not yet smoothed over.
var missteps := 0
## In-season extension talks (see the class notes).
var extension := false
## Extension mode: talks resume this week after Sleep on it (0 = not sleeping).
var wake_week := 0
var _args_cache: Array = []


static func start(p_season: Season, p_team: Team, s: Soldier, ext := false) -> Negotiation:
	var n := Negotiation.new()
	n.season = p_season
	n.team = p_team
	n.soldier = s
	n.extension = ext
	var d := s.get_dna()
	var trust_t := (s.trust - Soldier.TRUST_NEUTRAL) / 50.0
	var home := Dna.hometown_pull(s, p_team)
	var pull := n.bond_pull()
	n.demand_mult = 1.0 + 0.10 * (2.0 * d.n(&"money") - 1.0) - 0.06 * d.n(&"loyalty") - 0.10 * trust_t - 0.06 * home \
		- 0.05 * pull * (0.5 + 0.5 * d.n(&"loyalty"))
	n.floor_mult = 0.80 + 0.10 * d.n(&"savvy") - 0.08 * d.n(&"loyalty") - 0.05 * trust_t - 0.05 * home - 0.04 * pull
	n._opening()
	n.floor_mult = minf(n.floor_mult, n.demand_mult - 0.03)
	n.opening_mult = n.demand_mult
	return n


# --- terms ---------------------------------------------------------------------

func demand(years: int) -> int:
	return Contracts._round_salary(Contracts.resign_asking(soldier, years) * demand_mult)


func floor_salary(years: int) -> int:
	return Contracts._round_salary(Contracts.resign_asking(soldier, years) * floor_mult)


## Share of his base demand a starter promise is worth.
func promise_cut() -> float:
	return PROMISE_CUT * (0.3 + soldier.get_dna().n(&"playing_time"))


## 0..1: pull of his Familiar+ teammates on this roster.
func bond_pull() -> float:
	return season.relationships.bond_pull(soldier, team) if season.relationships != null else 0.0


## The teammate a "keep the core" promise would cover: his strongest Familiar+ bond on the roster
## who is under contract next season (null if none).
func keep_target() -> Soldier:
	if season.relationships == null:
		return null
	var best: Soldier = null
	var best_pts := Relationships.LEVEL_POINTS[1] - 0.001
	for o in team.roster:
		if o == soldier or o.contract == null:
			continue
		if o.contract.is_expiring() or (extension and o.contract.years <= 1 and not o.has_extension()):
			continue
		var pts := season.relationships.points(soldier, o)
		if pts > best_pts:
			best = o
			best_pts = pts
	return best


## Yearly value (in $K) of one term to him for a deal of `years` years.
func term_value(term: StringName, years: int, terms: Dictionary) -> float:
	var d := soldier.get_dna()
	var base := float(Contracts.resign_asking(soldier, years))
	match term:
		&"bonus":
			return int(terms.get("bonus", 0)) / float(maxi(1, years)) * (1.0 + 0.5 * d.n(&"money"))
		&"no_trade":
			return (0.02 + 0.08 * maxf(d.n(&"loyalty"), Dna.hometown_pull(soldier, team))) * base
		&"promise":
			return promise_cut() * base
		&"keep":
			var k := keep_target()
			if k == null:
				return 0.0
			return (0.03 + 0.06 * d.n(&"loyalty")) * (season.relationships.level(soldier, k) / 3.0) * base
	return 0.0


## Whether `terms` includes `term`.
static func has_term(terms: Dictionary, term: StringName) -> bool:
	if term == &"bonus":
		return int(terms.get("bonus", 0)) > 0
	return bool(terms.get(String(term), false))


## What the offer is worth to him per year: salary plus every term's value.
func value_to_him(salary: int, years: int, terms := {}) -> float:
	var v := float(salary)
	for t in TERMS:
		if has_term(terms, t):
			v += term_value(t, years, terms)
	return v


## Cash per year: salary plus the bonus spread over the deal.
func cash_per_year(salary: int, years: int, terms := {}) -> float:
	return salary + int(terms.get("bonus", 0)) / float(maxi(1, years))


## Share of his demand the offer reaches (1.0 = he signs if the cash clears his floor).
func offer_share(salary: int, years: int, terms := {}) -> float:
	return value_to_him(salary, years, terms) / float(maxi(1, demand(years)))


func accepts(salary: int, years: int, terms := {}) -> bool:
	return value_to_him(salary, years, terms) >= demand(years) - 0.5 and cash_per_year(salary, years, terms) >= floor_salary(years) - 0.5


## The lowest salary that signs him with these terms.
func required_salary(years: int, terms := {}) -> int:
	var extras := value_to_him(0, years, terms)
	var need := maxf(demand(years) - extras, floor_salary(years) - int(terms.get("bonus", 0)) / float(maxi(1, years)))
	return clampi(ceili(need / 10.0 - 0.001) * 10, Contracts.MIN_SALARY, Contracts.MAX_SALARY)


func is_open() -> bool:
	return state == OPEN


## Extension mode: he's sleeping on it until next week.
func is_resting() -> bool:
	return wake_week > 0 and season.week < wake_week


## Talks are open and he's at the table.
func can_act() -> bool:
	return is_open() and not is_resting()


func _closed_text() -> String:
	return "He's sleeping on it. Talks resume next week." if is_open() else "Talks are over."


## The season the new deal starts: next season for an extension, else the cap year.
func deal_year() -> int:
	return season.year + 1 if extension else season.cap_year()


## Room for his new deal under the apron (Bird rights: a re-sign may go over the soft cap): next
## season's room for an extension, else this cap year's room with his cap hold freed.
func cap_room() -> int:
	if extension:
		return Contracts.next_apron_room(team, season.year)
	return Contracts.apron_room(team, season.cap_year()) + Contracts.cap_hold(soldier)


## Room under the tax line for his new deal (same years as cap_room).
func tax_room() -> int:
	if extension:
		return Contracts.TAX_LINE - Contracts.payroll(team, season.year, 1)
	return Contracts.TAX_LINE - Contracts.payroll(team, season.cap_year()) + Contracts.cap_hold(soldier)


## Extension mode: a sleeping player comes back to the table once the week turns (patience back,
## his ask drifts toward where it opened). Called by Season.negotiation.
func wake() -> void:
	if wake_week <= 0 or season.week < wake_week:
		return
	wake_week = 0
	if not is_open():
		return
	patience = minf(MAX_PATIENCE, patience + SLEEP_PATIENCE)
	demand_mult = maxf(floor_mult, demand_mult + (opening_mult - demand_mult) * SLEEP_DRIFT)
	_say("him", "I've thought it over. My ask is %s." % Contracts.money(demand(Contracts.preferred_years(soldier))))


# --- actions -------------------------------------------------------------------

## Why this offer can't be made ("" = it can).
func offer_error(salary: int, years: int, terms := {}) -> String:
	if not can_act():
		return _closed_text()
	if years < 1 or years > Contracts.MAX_YEARS:
		return "Deals run 1-%d years." % Contracts.MAX_YEARS
	if salary < Contracts.MIN_SALARY or salary > Contracts.MAX_SALARY:
		return "Salary must be %s - %s." % [Contracts.money(Contracts.MIN_SALARY), Contracts.money(Contracts.MAX_SALARY)]
	var bonus := int(terms.get("bonus", 0))
	if bonus < 0 or bonus > Contracts.MAX_SALARY:
		return "Signing bonus must be %s - %s." % [Contracts.money(0), Contracts.money(Contracts.MAX_SALARY)]
	if extension:
		if not Contracts.extension_fits(team, season.year, salary, bonus):
			return "Not enough room under the %d apron (%s left next season%s)." % [deal_year(), Contracts.money(cap_room()),
				"; the bonus counts on that year" if bonus > 0 else ""]
	elif not Contracts.resign_fits(team, season.cap_year(), soldier, salary + bonus):
		return "Not enough room under the apron (%s left, counting his %s cap hold%s)." % [
			Contracts.money(cap_room()), Contracts.money(Contracts.cap_hold(soldier)),
			"; the bonus counts this year" if bonus > 0 else ""]
	if season.revenue.frozen(team) and salary + bonus > Contracts.MIN_SALARY and salary + bonus > tax_room():
		return "The board has frozen spending while the club fund is below $0: this deal would take payroll %s over the tax line." % Contracts.money(salary + bonus - tax_room())
	if has_term(terms, &"promise"):
		if extension and not soldier.promise.is_empty():
			return "He already has a starter promise. It has to play out first."
		if promises_out() >= team.scheme.slot_ids().size():
			return "You've already promised all %d starting spots." % team.scheme.slot_ids().size()
	if has_term(terms, &"keep"):
		if keep_target() == null:
			return "He has no close teammate under contract to promise to keep."
		if extension and not soldier.keep_promise.is_empty():
			return "He already has a keep-the-core promise. It has to play out first."
	return ""


## Starter promises `team` has out for the season this deal starts.
func promises_out() -> int:
	if not extension:
		return season.fa.promises_made(season, team)
	var n := 0
	for so in team.roster:
		if not so.promise.is_empty() and int(so.promise["year"]) == deal_year():
			n += 1
	return n


## Puts an offer on the table. Returns {ok: bool, result: "signed" | "countered" | "insulted" |
## "walked" | "error", text}.
func make_offer(salary: int, years: int, terms := {}) -> Dictionary:
	var err := offer_error(salary, years, terms)
	if err != "":
		return {"ok": false, "result": "error", "text": err}
	var d := soldier.get_dna()
	_say("you", offer_text(salary, years, terms) + ".")
	if accepts(salary, years, terms):
		_sign(salary, years, terms)
		_say("him", "Deal. Let's get to work.")
		return {"ok": true, "result": "signed", "text": "%s accepts." % soldier.full_name()}
	patience -= ROUND_COST
	var share := offer_share(salary, years, terms)
	var result := "countered"
	if share < LOWBALL_SHARE:
		patience -= LOWBALL_COST * (1.5 - d.n(&"temperament"))
		soldier.add_trust(-4.0 * (1.0 - d.n(&"temperament")))
		missteps += 1
		result = "insulted"
		_say("him", "That's not a serious offer." if d.temperament >= 50 else "That's insulting. Do you know who you're talking to?")
		season.log_talk(soldier, team, &"insulted", "%s called %s's offer %s." % [
			soldier.full_name(), team.abbrev, "not serious" if d.temperament >= 50 else "insulting"])
	else:
		demand_mult = maxf(floor_mult, demand_mult * (1.0 - (1.0 - minf(share, 1.0)) * 0.35 * (1.0 - 0.5 * d.n(&"savvy"))))
	if patience <= 0.0:
		_walk()
		return {"ok": true, "result": "walked", "text": "%s has broken off talks." % soldier.full_name()}
	if result == "countered":
		_say("him", "I can come down to %s a year for %d year%s%s." % [Contracts.money(required_salary(years, terms)), years,
			"" if years == 1 else "s", " with those terms" if value_to_him(0, years, terms) > 0.0 else ""])
	return {"ok": true, "result": result, "text": _say_last()}


## Signs at the lowest salary that works with these terms.
func accept(years: int, terms := {}) -> Dictionary:
	return make_offer(required_salary(years, terms), years, terms)


## Take it or leave it. Signs if the offer meets his demand, or comes close enough (savvy and
## thick-skinned players hold out for more) with the cash at his floor. Otherwise he walks.
func final_offer(salary: int, years: int, terms := {}) -> Dictionary:
	var err := offer_error(salary, years, terms)
	if err != "":
		return {"ok": false, "result": "error", "text": err}
	var d := soldier.get_dna()
	_say("you", "Final offer: %s. Take it or leave it." % offer_text(salary, years, terms))
	var need := 0.90 + 0.06 * d.n(&"savvy") + 0.04 * d.n(&"temperament")
	var cash_ok := cash_per_year(salary, years, terms) >= floor_salary(years) - 0.5
	if accepts(salary, years, terms) or (cash_ok and offer_share(salary, years, terms) >= need):
		_sign(salary, years, terms)
		_say("him", "Alright. You've got a deal.")
		return {"ok": true, "result": "signed", "text": "%s accepts your final offer." % soldier.full_name()}
	_walk()
	return {"ok": true, "result": "walked", "text": "%s turned down your final offer." % soldier.full_name()}


## "$4.20M x 3 yrs, $1.00M bonus, no-trade clause".
func offer_text(salary: int, years: int, terms := {}) -> String:
	var parts: Array[String] = ["%s x %d yr%s" % [Contracts.money(salary), years, "" if years == 1 else "s"]]
	if has_term(terms, &"bonus"):
		parts.append("%s signing bonus" % Contracts.money(int(terms["bonus"])))
	if has_term(terms, &"no_trade"):
		parts.append("a no-trade clause")
	if has_term(terms, &"promise"):
		parts.append("I promise you'll start")
	if has_term(terms, &"keep"):
		var k := keep_target()
		if k != null:
			parts.append("%s stays with us" % k.short_name())
	return ", ".join(parts)


# --- tactics -------------------------------------------------------------------

func can_ask() -> bool:
	return can_act() and revealed.is_empty()


## Ask what it'll take: a range around his floor (wider for savvy players) and the term he values
## most. Costs ASK_COST patience; once per talks.
func ask(years: int) -> Dictionary:
	if not can_ask():
		return {"ok": false, "result": "error", "text": "You already asked." if can_act() else _closed_text()}
	var d := soldier.get_dna()
	_say("you", "Level with me. What's it going to take?")
	patience -= ASK_COST
	var fl := float(floor_salary(years))
	var width := 0.03 + 0.12 * d.n(&"savvy")
	var tilt := float(absi(hash([soldier.id, 0xA5])) % 100) / 100.0
	var low := Contracts._round_salary(fl * (1.0 - width * tilt))
	var high := Contracts._round_salary(fl * (1.0 + width * (1.0 - tilt)))
	var term := favourite_term(years)
	revealed = {"low": low, "high": high, "years": years, "term": term}
	_say("note", "Agent: He won't take less than %s - %s a year in cash on a %d-year deal. %s" % [
		Contracts.money(low), Contracts.money(high), years, _term_hint(term)])
	if patience <= 0.0:
		_walk()
		return {"ok": true, "result": "walked", "text": "%s has broken off talks." % soldier.full_name()}
	return {"ok": true, "result": "asked", "text": _say_last()}


## The deal term worth the most to him (bonus = he wants cash up front).
func favourite_term(years: int) -> StringName:
	var probe := {"bonus": Contracts.resign_asking(soldier, years) * years / 10, "no_trade": true, "promise": true, "keep": true}
	var best: StringName = &"bonus"
	var best_v: float = term_value(&"bonus", years, probe) - int(probe["bonus"]) / float(years)
	for t: StringName in [&"no_trade", &"promise", &"keep"]:
		var v := term_value(t, years, probe)
		if v > best_v:
			best = t
			best_v = v
	return best


func can_smooth() -> bool:
	return can_act() and not smoothed and (soldier.trust < SMOOTH_TRUST_BELOW or missteps > 0)


## Smooth it over: trust back (more with thick-skinned players) and one misstep's demand bump
## undone. Costs SMOOTH_COST patience; once per talks, after a misstep or with low trust.
func smooth_over() -> Dictionary:
	if not can_smooth():
		return {"ok": false, "result": "error", "text": _closed_text() if not can_act() else ("There's nothing to smooth over." if not smoothed else "You can only do that once.")}
	var d := soldier.get_dna()
	smoothed = true
	_say("you", "Look, that came out wrong. I respect you, and I want you here.")
	patience -= SMOOTH_COST
	soldier.add_trust(4.0 + 6.0 * d.n(&"temperament"))
	if missteps > 0:
		missteps -= 1
		demand_mult = maxf(floor_mult, demand_mult / BACKFIRE_MULT)
	if patience <= 0.0:
		_walk()
		return {"ok": true, "result": "walked", "text": "%s has broken off talks." % soldier.full_name()}
	_say("him", "Alright. Let's keep talking.")
	return {"ok": true, "result": "smoothed", "text": _say_last()}


func can_sleep() -> bool:
	return can_act() and not slept


## Sleep on it: patience back, but his demand drifts SLEEP_DRIFT of the way back to where it opened.
## In extension mode the break lasts until next week (see wake); nothing happens until then.
func sleep_on_it() -> Dictionary:
	if not can_sleep():
		return {"ok": false, "result": "error", "text": "You already took a break." if can_act() else _closed_text()}
	slept = true
	if extension:
		wake_week = season.week + 1
		_say("you", "Let's both take a week and think it over.")
		_say("him", "Fine. Call me next week.")
		return {"ok": true, "result": "slept", "text": _say_last()}
	patience = minf(MAX_PATIENCE, patience + SLEEP_PATIENCE)
	demand_mult = maxf(floor_mult, demand_mult + (opening_mult - demand_mult) * SLEEP_DRIFT)
	_say("you", "Let's both sleep on it.")
	_say("him", "Fine. Call me tomorrow. My ask is %s." % Contracts.money(demand(Contracts.preferred_years(soldier))))
	return {"ok": true, "result": "slept", "text": _say_last()}


# --- arguments -----------------------------------------------------------------

## Every argument the data supports right now (used ones included, flagged).
## Each: {id, title, pitch, evidence (0-1), evidence_text, fit, tone ("hard"/"soft"/"neutral"),
## group (SELL / HARDBALL), used}.
func arguments() -> Array:
	if _args_cache.is_empty():
		_args_cache = _build_arguments()
	for a in _args_cache:
		a["used"] = used.has(a["id"])
	return _args_cache


func arguments_in(group: StringName) -> Array:
	return arguments().filter(func(a): return a["group"] == group)


func argument(id: StringName) -> Dictionary:
	for a in arguments():
		if a["id"] == id:
			return a
	return {}


## Uses an argument. Returns {ok, result: "landed" | "rebutted" | "backfired" | "walked" | "error",
## cut (share of demand removed), text}.
func use_argument(id: StringName) -> Dictionary:
	var a := argument(id)
	if not can_act():
		return {"ok": false, "result": "error", "cut": 0.0, "text": _closed_text()}
	if a.is_empty():
		return {"ok": false, "result": "error", "cut": 0.0, "text": "You don't have the evidence for that."}
	if a["used"]:
		return {"ok": false, "result": "error", "cut": 0.0, "text": "You already made that point."}
	var d := soldier.get_dna()
	var prior := used.size()
	_say("you", a["pitch"])
	patience -= ROUND_COST
	var before := demand_mult
	var result := "landed"
	if a["fit"] < BACKFIRE_FIT:
		result = "backfired"
		soldier.add_trust(-6.0 - 6.0 * (1.0 - d.n(&"temperament")))
		patience -= 15.0
		demand_mult *= BACKFIRE_MULT
		if id == &"test_market":
			patience -= TEST_MARKET_COST
		missteps += 1
		_say("him", _backfire_line(id))
		season.log_talk(soldier, team, &"backfired", "%s took offense in talks with %s: \"%s\"" % [soldier.full_name(), team.abbrev, a["title"]])
	else:
		var strength: float = a["evidence"] * a["fit"] * leverage()
		var cut := ARG_CUT * strength * pow(DIMINISH, prior)
		if a["evidence"] < REBUT_EVIDENCE and d.savvy >= 60:
			result = "rebutted"
			cut *= 0.3
			_say("him", _rebuttal_line(id))
		demand_mult = maxf(floor_mult, demand_mult * (1.0 - cut))
		if a["tone"] == "hard":
			soldier.add_trust(-3.0 * (1.0 - d.n(&"temperament")))
		else:
			soldier.add_trust(2.0 + (2.0 if id == &"build_around" else 0.0))
		if result == "landed":
			_say("him", _concede_line(id) if demand_mult < before - 0.001 else "I hear you, but I'm already at my number.")
	used[id] = result
	if patience <= 0.0:
		_walk()
		return {"ok": true, "result": "walked", "cut": 0.0, "text": "%s has broken off talks." % soldier.full_name()}
	return {"ok": true, "result": result, "cut": maxf(0.0, 1.0 - demand_mult / before), "text": _say_last()}


## Your bargaining position: lower for your best players, higher for backups.
func leverage() -> float:
	var better := 0
	for so in team.roster:
		if so != soldier and so.best_ovr() > soldier.best_ovr():
			better += 1
	if better <= 1:
		return 0.8
	if team.slot_of(soldier) == &"":
		return 1.2
	return 1.0


static func fit_label(fit: float) -> Array:
	if fit < BACKFIRE_FIT:
		return ["Will offend him", Color("#ef4444")]
	if fit < 0.5:
		return ["Poor fit", Color("#f59e0b")]
	if fit < 0.9:
		return ["Decent fit", Color("#84cc16")]
	return ["Great fit", Color("#22c55e")]


static func evidence_label(e: float) -> Array:
	if e < REBUT_EVIDENCE:
		return ["Weak", Color("#f59e0b")]
	if e < 0.75:
		return ["Solid", Color("#84cc16")]
	return ["Strong", Color("#22c55e")]


# --- internals -----------------------------------------------------------------

func _opening() -> void:
	var s := soldier
	var d := s.get_dna()
	var broke := season.promise_log.any(func(p): return p["soldier"] == s and not p["kept"] and int(p["year"]) == season.year)
	if broke:
		patience -= 25.0
		demand_mult += 0.05
		_say("him", "You promised I'd start and you benched me. Why should I believe anything you say now?")
	if not extension and s.ext_walked_year == season.year:
		patience -= EXT_WALK_PATIENCE
		demand_mult += EXT_WALK_DEMAND
		_say("him", "We already did this dance during the season. My number hasn't gotten any smaller.")
	if extension:
		_say("note", "Extension talks: the new deal starts in %d, after his current contract runs out." % deal_year())
	var top := true
	for so in team.roster:
		if so != s and so.best_ovr() > s.best_ovr():
			top = false
	if top and d.money >= 50:
		demand_mult += 0.06
		_say("him", "I'm the best player on this roster. I expect to be paid like it.")
	else:
		var richer: Soldier = null
		for so in team.roster:
			if so == s or so.contract == null or so.contract.rookie or so.contract.is_expiring():
				continue
			if so.best_ovr() < s.best_ovr() and so.contract.salary > Contracts.resign_asking(s, Contracts.preferred_years(s)):
				if richer == null or so.contract.salary > richer.contract.salary:
					richer = so
		if richer != null and d.money >= 40:
			demand_mult += 0.04
			_say("him", "%s makes %s and he isn't as good as me." % [richer.short_name(), Contracts.money(richer.contract.salary)])
	var lead := d.ranked()[0]
	var wants := {&"money": "My client is focused on getting paid what he's worth.",
		&"winning": "He wants to know this team can win a title.",
		&"playing_time": "He needs to know he's a starter here.",
		&"loyalty": "He'd like to stay. Make it easy for him.",
		&"security": "He's looking for a long-term commitment.",
		&"hometown": "He likes playing close to home. Give him a reason to stay." if Dna.hometown_pull(s, team) > 0.0 else "He's always wanted to play closer to home."}
	_say("note", "Agent: " + String(wants[lead]))
	if bond_pull() > 0.3 and season.relationships != null:
		var pal := season.relationships.best_bond(s, team)
		if pal != null:
			_say("note", "Agent: He's close with %s. That counts for something." % pal.short_name())


func _sign(salary: int, years: int, terms: Dictionary) -> void:
	var bonus := int(terms.get("bonus", 0))
	var no_trade := has_term(terms, &"no_trade")
	var dy := deal_year()
	if extension:
		soldier.ext_salary = salary
		soldier.ext_years = years
		soldier.ext_bonus = bonus
		soldier.ext_no_trade = no_trade
	else:
		soldier.contract = Contract.make(salary, years, season.year)
		soldier.contract.bonus = bonus
		soldier.contract.no_trade = no_trade
	if bonus > 0:
		team.bonus_money[dy] = int(team.bonus_money.get(dy, 0)) + bonus
	soldier.morale = maxf(soldier.morale, 82.0)
	soldier.add_trust(SIGN_TRUST)
	var promise := has_term(terms, &"promise")
	if promise:
		soldier.promise = {"year": dy, "team": team.abbrev, "games": 0, "started": 0}
	var keep := false
	if has_term(terms, &"keep"):
		var k := keep_target()
		if k != null:
			soldier.keep_promise = {"year": dy, "team": team.abbrev, "id": k.id, "name": k.full_name()}
			keep = true
	season.resign_log.append({"soldier": soldier, "team": team, "salary": salary, "years": years, "year": season.year,
		"promise": promise, "bonus": bonus, "no_trade": no_trade, "keep": keep, "extension": extension})
	season.news.resign(season, team, soldier, salary, years, extension)
	state = SIGNED


func _walk() -> void:
	state = WALKED
	soldier.add_trust(WALK_TRUST)
	if extension:
		soldier.ext_walked_year = season.year
		_say("him", "Forget it. We'll talk after the season, and it won't be cheaper.")
		season.log_talk(soldier, team, &"walked", "%s broke off extension talks with %s." % [soldier.full_name(), team.abbrev])
		return
	_say("him", "We're done here. I'll take my chances in free agency.")
	season.log_talk(soldier, team, &"walked", "%s broke off contract talks with %s." % [soldier.full_name(), team.abbrev])


func _say(who: String, text: String) -> void:
	talk.append({"who": who, "text": text})


func _say_last() -> String:
	return talk[-1]["text"] if not talk.is_empty() else ""


func _term_hint(term: StringName) -> String:
	match term:
		&"bonus":
			return "He'd like money up front."
		&"no_trade":
			return "He wants to know he won't be moved."
		&"promise":
			return "He needs to know he'll start."
		&"keep":
			var k := keep_target()
			return "He wants %s kept around." % (k.short_name() if k != null else "his friends")
	return ""


func _concede_line(id: StringName) -> String:
	var lines := {&"production": "Fine. The numbers weren't what they should have been.",
		&"injury": "I can't argue with the time I missed.",
		&"age": "I know I'm not getting younger.",
		&"market": "Alright, I've seen those deals.",
		&"contender": "Winning matters to me. I'll meet you partway.",
		&"cap": "I get it, you've got a lot of guys to pay.",
		&"competition": "Fine. I'll earn the spot.",
		&"loyalty": "This place means a lot to me. I can bend a little.",
		&"hometown": "Being near home matters. My family would like that.",
		&"teammates": "Those guys are my brothers. I don't want to break that up.",
		&"starter": "As long as I'm on the field, I can be flexible.",
		&"big_stage": "Playing in front of this crowd... yeah, that's worth something.",
		&"young_core": "This group's going to be good for a long time. I see it.",
		&"we_made_you": "You're right. I wasn't this player when I got here.",
		&"build_around": "That means a lot. I'll help you build it.",
		&"peaked": "Alright. I know what I am at this point.",
		&"lock_in": "Getting it done now would take a weight off. I'll give a little.",
		&"test_market": "Fine. Maybe the grass isn't greener out there."}
	return "%s New ask: %s / yr." % [lines.get(id, "Fair point."), Contracts.money(demand(Contracts.preferred_years(soldier)))]


func _rebuttal_line(id: StringName) -> String:
	var lines := {&"production": "That's a handful of matches. You can't judge me on that.",
		&"injury": "A few weeks out doesn't make me fragile.",
		&"age": "I'm in the best shape of my life.",
		&"market": "Those guys aren't me. Look at the sample.",
		&"contender": "One good season doesn't make you a contender.",
		&"cap": "Your cap trouble isn't my problem.",
		&"competition": "He's not taking my spot and you know it.",
		&"loyalty": "Loyalty goes both ways.",
		&"hometown": "Close to home isn't the same as home.",
		&"teammates": "I've got friends everywhere in this league.",
		&"starter": "Every team I talk to will start me.",
		&"big_stage": "Bright lights don't pay the bills.",
		&"young_core": "Kids are kids until they win something.",
		&"we_made_you": "I put in the work. Not you.",
		&"build_around": "Words are cheap. Show me in the offer.",
		&"peaked": "I've still got another level in me.",
		&"lock_in": "I'm not worried about getting hurt. I'll bet on myself.",
		&"test_market": "Plenty of teams will be calling. Count on it."}
	return lines.get(id, "I don't buy it.")


func _backfire_line(id: StringName) -> String:
	var lines := {&"production": "You're questioning my game? After everything I did out there?",
		&"injury": "I played hurt for this team and you're throwing it back at me?",
		&"age": "So I'm washed now? Unbelievable.",
		&"market": "I'm not some average guy. Don't compare me to them.",
		&"contender": "I don't care about rings. Pay me.",
		&"cap": "Don't make your mistakes my problem.",
		&"competition": "You're threatening me with a backup? Then play him.",
		&"loyalty": "Loyalty? Don't guilt-trip me.",
		&"hometown": "I don't care where I play. This is business.",
		&"teammates": "Friendship doesn't pay rent.",
		&"starter": "Starting is the least you can do.",
		&"big_stage": "I don't need a spotlight. I need a paycheck.",
		&"young_core": "I'm not here to babysit.",
		&"we_made_you": "You made me? I made myself.",
		&"build_around": "Then pay me like the guy you build around.",
		&"peaked": "Peaked? You've got some nerve.",
		&"lock_in": "Rushing me isn't going to work.",
		&"test_market": "You want me to test the market? Maybe I will."}
	return "%s My price just went up." % lines.get(id, "That was out of line.")


func _build_arguments() -> Array:
	var s := soldier
	var d := s.get_dna()
	var out: Array = []
	var temper_n := d.n(&"temperament")
	var savvy_n := d.n(&"savvy")
	var role := Scheme.best_role(s.stats)
	var ask_now := demand(Contracts.preferred_years(s))

	# Production vs rating, judged within his role.
	var rows := SeasonReview.totals(season)
	var mine: Dictionary = {}
	for t in rows:
		if t["soldier"] == s:
			mine = t
	if not mine.is_empty() and int(mine["matches"]) > 0:
		var my_role: int = mine["role"]
		var peers := rows.filter(func(t): return t["role"] == my_role and t["matches"] >= 2)
		if peers.size() >= 4:
			var my_ipm: float = mine["impact"] / mine["matches"]
			var below_imp := 0
			var below_ovr := 0
			for t in peers:
				if t["impact"] / t["matches"] < my_ipm:
					below_imp += 1
				if t["soldier"].best_ovr() < s.best_ovr():
					below_ovr += 1
			var imp_pct := float(below_imp) / peers.size()
			var ovr_pct := float(below_ovr) / peers.size()
			var gap := ovr_pct - imp_pct
			if gap > 0.15:
				var sample := clampf(mine["matches"] / 8.0, 0.25, 1.0)
				out.append({"id": &"production", "title": "Production didn't match his rating", "tone": "hard",
					"pitch": "Your rating says top-%d%% %s. Your impact says otherwise." % [roundi(100 - ovr_pct * 100), Scheme.ROLE_NAMES[my_role]],
					"evidence": clampf((gap - 0.1) / 0.4, 0.15, 1.0) * sample,
					"evidence_text": "Impact/match ranks %s percentile among %ss; his OVR ranks %s (%d matches)." % [
						_ord(roundi(imp_pct * 100)), Scheme.ROLE_NAMES[my_role], _ord(roundi(ovr_pct * 100)), mine["matches"]],
					"fit": 0.6 + 0.6 * savvy_n - 0.9 * (1.0 - temper_n) * (1.0 if s.best_ovr() >= 68 else 0.5)})

	# Injury time this season.
	var weeks := 0
	for inj in season.injury_log:
		if inj["soldier"] == s and int(inj["year"]) == season.year:
			weeks += int(inj["weeks"])
	if weeks >= 3:
		out.append({"id": &"injury", "title": "Injury history", "tone": "hard",
			"pitch": "You missed %d weeks this season. I have to price that in." % weeks,
			"evidence": clampf(weeks / 8.0, 0.3, 1.0), "evidence_text": "%d weeks injured in %d." % [weeks, season.year],
			"fit": 0.5 + 0.5 * d.n(&"security") - 0.5 * (1.0 - temper_n)})

	# Age and decline.
	if s.age >= 30:
		out.append({"id": &"age", "title": "Age and decline", "tone": "hard",
			"pitch": "You're %d. Players decline from here, and I can't pay for what you used to be." % s.age,
			"evidence": clampf((s.age - 29) / 5.0, 0.2, 1.0), "evidence_text": "Age %d: ratings start to slip past 30." % s.age,
			"fit": 0.4 + 0.7 * d.n(&"security") - 0.3 * d.n(&"money") + 0.2 * savvy_n})

	# No ceiling left.
	var upside := s.potential_ovr() - s.best_ovr()
	if upside <= 2 and s.age >= 27:
		out.append({"id": &"peaked", "title": "He's peaked", "tone": "hard",
			"pitch": "You are who you are at this point. I'm paying for the player you are, not one you won't become.",
			"evidence": clampf(0.6 + (2 - upside) * 0.15 + (s.age - 27) * 0.03, 0.4, 1.0),
			"evidence_text": "Age %d, OVR %d, ceiling %d." % [s.age, s.best_ovr(), s.potential_ovr()],
			"fit": 0.4 + 0.6 * savvy_n - 0.6 * (1.0 - temper_n)})

	# Comparable contracts around the league.
	var comps: Array = []
	for t in season.league.teams:
		for so in t.roster:
			if so == s or so.contract == null or so.contract.rookie:
				continue
			if Scheme.best_role(so.stats) == role and absi(so.best_ovr() - s.best_ovr()) <= 2:
				comps.append(so.contract.salary)
	if comps.size() >= 3:
		var avg := 0.0
		for c in comps:
			avg += c
		avg /= comps.size()
		if avg < ask_now * 0.95:
			out.append({"id": &"market", "title": "Comparable contracts", "tone": "neutral",
				"pitch": "%d %ss at your level average %s. That's the market." % [comps.size(), Scheme.ROLE_NAMES[role], Contracts.money(roundi(avg))],
				"evidence": clampf((ask_now - avg) / ask_now * 4.0, 0.0, 1.0) * clampf(comps.size() / 6.0, 0.4, 1.0),
				"evidence_text": "%d %ss within 2 OVR average %s / yr (he asks %s)." % [comps.size(), Scheme.ROLE_NAMES[role], Contracts.money(roundi(avg)), Contracts.money(ask_now)],
				"fit": 0.4 + 0.8 * savvy_n})

	# Someone pushing for his spot.
	var rival: Soldier = null
	for so in team.roster:
		if so == s or Scheme.best_role(so.stats) != role:
			continue
		if so.ovr_at_role(role) >= s.ovr_at_role(role) - 3 and (rival == null or so.ovr_at_role(role) > rival.ovr_at_role(role)):
			rival = so
	if rival != null:
		out.append({"id": &"competition", "title": "Competition for his spot", "tone": "hard",
			"pitch": "%s is pushing for your spot. I have options." % rival.short_name(),
			"evidence": clampf(1.0 - (s.ovr_at_role(role) - rival.ovr_at_role(role)) / 6.0, 0.3, 1.0),
			"evidence_text": "%s: %s OVR %d (age %d) vs his %d." % [rival.full_name(), Scheme.ROLE_NAMES[role], rival.ovr_at_role(role), rival.age, s.ovr_at_role(role)],
			"fit": 0.3 + 0.9 * d.n(&"playing_time") - 0.9 * (1.0 - temper_n)})

	# A winning team.
	var record := _record()
	var pct: float = record[0]
	var finalist: bool = record[1]
	var cont := clampf((pct - 0.5) / 0.3, 0.0, 1.0) + (0.3 if finalist else 0.0)
	if cont > 0.1:
		out.append({"id": &"contender", "title": "We're a contender", "tone": "soft",
			"pitch": "We went %s. Stay and win with us." % record[2],
			"evidence": clampf(cont, 0.0, 1.0), "evidence_text": "%s this season%s." % [record[2], ", reached the Final" if finalist else ""],
			"fit": 0.1 + 1.2 * d.n(&"winning")})

	# Tax squeeze.
	var space := tax_room() - ask_now
	var tight := Contracts.SALARY_CAP * 0.08
	if space < tight:
		out.append({"id": &"cap", "title": "Cap is tight", "tone": "soft",
			"pitch": ("Paying your ask leaves us %s under the luxury tax. I need help to keep this roster together." % Contracts.money(space)) if space >= 0
				else ("Paying your ask puts us %s into the luxury tax. I need help to keep this roster together." % Contracts.money(-space)),
			"evidence": clampf(1.0 - space / tight, 0.2, 1.0), "evidence_text": "Room under the tax line after his ask: %s." % Contracts.money(space),
			"fit": 0.2 + 0.9 * d.n(&"loyalty") - 0.3 * d.n(&"money") + 0.2 * savvy_n})

	# Years with the club.
	var yrs := 0
	var first_year := 0
	for y in s.season_lines:
		if s.season_lines[y].get("team", "") == team.abbrev:
			yrs += 1
			if first_year == 0 or int(y) < first_year:
				first_year = int(y)
	if yrs >= 2:
		out.append({"id": &"loyalty", "title": "Loyalty to the club", "tone": "soft",
			"pitch": "You've been with us %d seasons. This is home." % yrs,
			"evidence": clampf(yrs / 5.0, 0.3, 1.0), "evidence_text": "%d seasons with %s." % [yrs, team.abbrev],
			"fit": 0.1 + 1.2 * d.n(&"loyalty")})

	# How much he grew here.
	if first_year > 0:
		var start_ovr := -1
		for h in s.history:
			if int(h.get("year", 0)) >= first_year and h.has("ovr_from"):
				start_ovr = int(h["ovr_from"])
				break
		var gain := s.best_ovr() - start_ovr
		if start_ovr > 0 and gain >= 4:
			out.append({"id": &"we_made_you", "title": "We made you", "tone": "soft",
				"pitch": "You were a %d when you got here. Our staff made you a %d." % [start_ovr, s.best_ovr()],
				"evidence": clampf(gain / 10.0, 0.4, 1.0), "evidence_text": "OVR %d -> %d with %s since %d." % [start_ovr, s.best_ovr(), team.abbrev, first_year],
				"fit": 0.2 + 0.9 * d.n(&"loyalty") - 0.4 * d.n(&"money") + 0.2 * savvy_n})

	# Close to home.
	var home := Dna.hometown_pull(s, team)
	if home > 0.0:
		var same := team.home_state == s.home_state
		out.append({"id": &"hometown", "title": "Close to home", "tone": "soft",
			"pitch": "You grew up %s. Your family can see every match." % ("right here" if same else "a short drive away"),
			"evidence": 1.0 if same else 0.5,
			"evidence_text": "From %s; %s plays in %s." % [LeagueData.state_name(s.home_state), team.abbrev, LeagueData.state_name(team.home_state)],
			"fit": 0.1 + 1.2 * d.n(&"hometown")})

	# His friends on the roster.
	var pull := bond_pull()
	if pull >= 0.15 and season.relationships != null:
		var pal := season.relationships.best_bond(s, team)
		var pal_name := pal.short_name() if pal != null else "the guys"
		out.append({"id": &"teammates", "title": "His teammates", "tone": "soft",
			"pitch": "You and %s have something special. Don't walk away from that." % pal_name,
			"evidence": clampf(pull, 0.0, 1.0),
			"evidence_text": "Bonds on the roster: %d%% pull%s." % [roundi(pull * 100),
				"" if pal == null else ", closest: %s (%s)" % [pal.full_name(), Relationships.LEVEL_NAMES[season.relationships.level(s, pal)]]],
			"fit": 0.15 + 0.7 * d.n(&"loyalty") + 0.4 * d.n(&"winning") - 0.2 * d.n(&"money")})

	# A guaranteed spot.
	if team.slot_of(s) != &"" and rival == null:
		out.append({"id": &"starter", "title": "The job is his", "tone": "soft",
			"pitch": "Nobody here is close to you. That spot is yours as long as you want it.",
			"evidence": 0.9, "evidence_text": "Starting; no %s on the roster within 3 OVR." % Scheme.ROLE_NAMES[role],
			"fit": 0.1 + 1.2 * d.n(&"playing_time")})

	# A big market or a hot team.
	var tier := Market.tier_of(team.market_rating)
	if tier >= 3 or team.buzz >= 60.0:
		out.append({"id": &"big_stage", "title": "The big stage", "tone": "soft",
			"pitch": "This is a %s and the city is %s. Endorsements follow players here." % [Market.tier_name(tier), Market.band_name(team.buzz).to_lower()],
			"evidence": clampf(maxf((tier - 1) / 4.0, team.buzz / 100.0), 0.3, 1.0),
			"evidence_text": "%s (%d), buzz %s (%d)." % [Market.tier_name(tier), team.market_rating, Market.band_name(team.buzz), roundi(team.buzz)],
			"fit": 0.15 + 0.9 * d.n(&"money") + 0.2 * savvy_n})

	# Young talent coming through.
	var young := 0
	for so in team.starters():
		if so != s and so.age <= 24 and so.potential_ovr() - so.best_ovr() >= 4:
			young += 1
	if young >= 2:
		out.append({"id": &"young_core", "title": "Young core", "tone": "soft",
			"pitch": "We've got %d young starters still getting better. Be part of what's coming." % young,
			"evidence": clampf(young / 3.0, 0.4, 1.0), "evidence_text": "%d starters aged 24 or under with 4+ OVR of upside." % young,
			"fit": 0.1 + 0.7 * d.n(&"winning") + 0.5 * d.n(&"security")})

	# One of the two best players here.
	var better := 0
	for so in team.roster:
		if so != s and so.best_ovr() > s.best_ovr():
			better += 1
	if better <= 1:
		out.append({"id": &"build_around", "title": "Build around him", "tone": "soft",
			"pitch": "You're %s. This franchise is built around you." % ("our best player" if better == 0 else "one of our two best players"),
			"evidence": 1.0 if better == 0 else 0.7, "evidence_text": "#%d OVR on the roster (%d)." % [better + 1, s.best_ovr()],
			"fit": 0.2 + 0.5 * d.n(&"playing_time") + 0.4 * d.n(&"money") + 0.2 * (1.0 - savvy_n)})

	if extension:
		# Certainty now vs the open market.
		var weeks_left := maxi(0, season.regular_weeks - season.week)
		out.append({"id": &"lock_in", "title": "Lock in now", "tone": "soft",
			"pitch": "Sign now and it's done. No injury risk, no slump, no wondering what's out there.",
			"evidence": clampf(0.35 + weeks_left / float(maxi(1, season.regular_weeks)) * 0.65, 0.35, 1.0),
			"evidence_text": "%d regular-season week%s left for something to go wrong." % [weeks_left, "" if weeks_left == 1 else "s"],
			"fit": 0.1 + 0.8 * d.n(&"security") + 0.4 * d.n(&"loyalty")})
		out.append({"id": &"test_market", "title": "Test the market", "tone": "hard",
			"pitch": "Go ahead and test free agency. See if anyone pays you more than this.",
			"evidence": clampf(1.0 - (s.best_ovr() - 55) / 25.0, 0.2, 1.0),
			"evidence_text": "OVR %d: %s." % [s.best_ovr(), "teams won't line up for him" if s.best_ovr() < 65 else "he'd have suitors"],
			"fit": 0.2 + 0.8 * d.n(&"security") + 0.4 * d.n(&"loyalty") - 0.5 * d.n(&"money") - 0.5 * savvy_n})
	for a in out:
		a["group"] = SELL if a["tone"] == "soft" else HARDBALL
	return out


## [win share, reached the Final, "W-L" text] for this season.
func _record() -> Array:
	var w := 0
	var l := 0
	for r in season.standings():
		if r.team == team:
			w = r.wins
			l = r.losses
	var finalist := false
	for m in season.playoff_matches:
		if m.stage == Season.STAGE_FINAL and m.is_played() and (m.home == team or m.away == team):
			finalist = true
	return [float(w) / maxi(1, w + l), finalist, "%d-%d" % [w, l]]


static func _ord(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]

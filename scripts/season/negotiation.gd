class_name Negotiation
extends RefCounted
## Re-signing talks with one of your expiring soldiers. Deterministic: every outcome comes from his
## DNA, his trust in you, real season data and your leverage.
##
## - His demand is Contracts.resign_asking(years) x demand_mult. The opening mult comes from DNA
##   (money up, loyalty down), trust and his opening statements (star treatment, teammate
##   comparison, a broken promise).
## - He never goes below his floor (what he believes the open market would pay), however good
##   your arguments are.
## - Every action (offer or argument) costs patience; at 0 he walks into free agency.
## - Offers at or above his demand sign. Below it he counters (closing part of the gap); lowballs
##   cost extra patience and trust with thin-skinned players.
## - Arguments only exist when the data backs them up. Strength = evidence x DNA fit x leverage.
##   A poor fit backfires (trust and patience drop, demand rises); weak evidence gets rebutted by
##   savvy players. Each argument can be used once and later ones have diminishing returns.
## - A starter promise lowers his demand (more for players who value playing time) and is tracked
##   through next season.

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

const OPEN := &"open"
const SIGNED := &"signed"
const WALKED := &"walked"

var season: Season
var team: Team
var soldier: Soldier
var demand_mult := 1.0
var floor_mult := 0.8
var patience := MAX_PATIENCE
var state: StringName = OPEN
## Argument id -> result ("landed", "rebutted", "backfired").
var used := {}
## Conversation: Array of {who: "you" | "him" | "note", text}.
var talk: Array = []
var _args_cache: Array = []


static func start(p_season: Season, p_team: Team, s: Soldier) -> Negotiation:
	var n := Negotiation.new()
	n.season = p_season
	n.team = p_team
	n.soldier = s
	var d := s.get_dna()
	var trust_t := (s.trust - Soldier.TRUST_NEUTRAL) / 50.0
	n.demand_mult = 1.0 + 0.10 * (2.0 * d.n(&"money") - 1.0) - 0.06 * d.n(&"loyalty") - 0.10 * trust_t
	n.floor_mult = 0.80 + 0.10 * d.n(&"savvy") - 0.08 * d.n(&"loyalty") - 0.05 * trust_t
	n._opening()
	n.floor_mult = minf(n.floor_mult, n.demand_mult - 0.03)
	return n


# --- terms ---------------------------------------------------------------------

func demand(years: int, promise := false) -> int:
	var m := demand_mult
	if promise:
		m = maxf(floor_mult, m - promise_cut())
	return Contracts._round_salary(Contracts.resign_asking(soldier, years) * m)


func floor_salary(years: int) -> int:
	return Contracts._round_salary(Contracts.resign_asking(soldier, years) * floor_mult)


## Share knocked off his demand by a starter promise.
func promise_cut() -> float:
	return PROMISE_CUT * (0.3 + soldier.get_dna().n(&"playing_time"))


func is_open() -> bool:
	return state == OPEN


# --- actions -------------------------------------------------------------------

## Why this offer can't be made ("" = it can).
func offer_error(salary: int, years: int, promise := false) -> String:
	if not is_open():
		return "Talks are over."
	if years < 1 or years > Contracts.MAX_YEARS:
		return "Deals run 1-%d years." % Contracts.MAX_YEARS
	if salary < Contracts.MIN_SALARY or salary > Contracts.MAX_SALARY:
		return "Salary must be %s - %s." % [Contracts.money(Contracts.MIN_SALARY), Contracts.money(Contracts.MAX_SALARY)]
	if not Contracts.fits(team, season.cap_year(), salary):
		return "Not enough cap space (%s left)." % Contracts.money(Contracts.cap_space(team, season.cap_year()))
	if promise and season.fa.promises_made(season, team) >= team.scheme.slot_ids().size():
		return "You've already promised all %d starting spots." % team.scheme.slot_ids().size()
	return ""


## Puts an offer on the table. Returns {ok: bool, result: "signed" | "countered" | "insulted" |
## "walked" | "error", text}.
func make_offer(salary: int, years: int, promise := false) -> Dictionary:
	var err := offer_error(salary, years, promise)
	if err != "":
		return {"ok": false, "result": "error", "text": err}
	var d := soldier.get_dna()
	_say("you", "%s x %d yr%s%s." % [Contracts.money(salary), years, "" if years == 1 else "s", ", and I promise you'll start" if promise else ""])
	var want := demand(years, promise)
	if salary >= want:
		_sign(salary, years, promise)
		_say("him", "Deal. Let's get to work.")
		return {"ok": true, "result": "signed", "text": "%s accepts." % soldier.full_name()}
	patience -= ROUND_COST
	var share := float(salary) / float(want)
	var result := "countered"
	if share < LOWBALL_SHARE:
		patience -= LOWBALL_COST * (1.5 - d.n(&"temperament"))
		soldier.add_trust(-4.0 * (1.0 - d.n(&"temperament")))
		result = "insulted"
		_say("him", "That's not a serious offer." if d.temperament >= 50 else "That's insulting. Do you know who you're talking to?")
	else:
		demand_mult = maxf(floor_mult, demand_mult * (1.0 - (1.0 - share) * 0.35 * (1.0 - 0.5 * d.n(&"savvy"))))
	if patience <= 0.0:
		_walk()
		return {"ok": true, "result": "walked", "text": "%s has broken off talks." % soldier.full_name()}
	if result == "countered":
		_say("him", "I can come down to %s a year for %d year%s." % [Contracts.money(demand(years, promise)), years, "" if years == 1 else "s"])
	return {"ok": true, "result": result, "text": _say_last()}


## Signs at his current demand.
func accept(years: int, promise := false) -> Dictionary:
	return make_offer(demand(years, promise), years, promise)


## Every argument the data supports right now (used ones included, flagged).
## Each: {id, title, pitch, evidence (0-1), evidence_text, fit, tone ("hard"/"soft"), used}.
func arguments() -> Array:
	if _args_cache.is_empty():
		_args_cache = _build_arguments()
	for a in _args_cache:
		a["used"] = used.has(a["id"])
	return _args_cache


func argument(id: StringName) -> Dictionary:
	for a in arguments():
		if a["id"] == id:
			return a
	return {}


## Uses an argument. Returns {ok, result: "landed" | "rebutted" | "backfired" | "walked" | "error",
## cut (share of demand removed), text}.
func use_argument(id: StringName) -> Dictionary:
	var a := argument(id)
	if not is_open():
		return {"ok": false, "result": "error", "cut": 0.0, "text": "Talks are over."}
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
		demand_mult *= 1.03
		_say("him", _backfire_line(id))
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
			soldier.add_trust(2.0)
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
		&"security": "He's looking for a long-term commitment."}
	_say("note", "Agent: " + String(wants[lead]))


func _sign(salary: int, years: int, promise: bool) -> void:
	soldier.contract = Contract.make(salary, years, season.year)
	soldier.morale = maxf(soldier.morale, 82.0)
	soldier.add_trust(SIGN_TRUST)
	if promise:
		soldier.promise = {"year": season.cap_year(), "team": team.abbrev, "games": 0, "started": 0}
	season.resign_log.append({"soldier": soldier, "team": team, "salary": salary, "years": years, "year": season.year, "promise": promise})
	state = SIGNED


func _walk() -> void:
	state = WALKED
	soldier.add_trust(WALK_TRUST)
	_say("him", "We're done here. I'll take my chances in free agency.")


func _say(who: String, text: String) -> void:
	talk.append({"who": who, "text": text})


func _say_last() -> String:
	return talk[-1]["text"] if not talk.is_empty() else ""


func _concede_line(id: StringName) -> String:
	var lines := {&"production": "Fine. The numbers weren't what they should have been.",
		&"injury": "I can't argue with the time I missed.",
		&"age": "I know I'm not getting younger.",
		&"market": "Alright, I've seen those deals.",
		&"contender": "Winning matters to me. I'll meet you partway.",
		&"cap": "I get it, you've got a lot of guys to pay.",
		&"competition": "Fine. I'll earn the spot.",
		&"loyalty": "This place means a lot to me. I can bend a little."}
	return "%s New ask: %s / yr." % [lines.get(id, "Fair point."), Contracts.money(demand(Contracts.preferred_years(soldier)))]


func _rebuttal_line(id: StringName) -> String:
	var lines := {&"production": "That's a handful of matches. You can't judge me on that.",
		&"injury": "A few weeks out doesn't make me fragile.",
		&"age": "I'm in the best shape of my life.",
		&"market": "Those guys aren't me. Look at the sample.",
		&"contender": "One good season doesn't make you a contender.",
		&"cap": "Your cap trouble isn't my problem.",
		&"competition": "He's not taking my spot and you know it.",
		&"loyalty": "Loyalty goes both ways."}
	return lines.get(id, "I don't buy it.")


func _backfire_line(id: StringName) -> String:
	var lines := {&"production": "You're questioning my game? After everything I did out there?",
		&"injury": "I played hurt for this team and you're throwing it back at me?",
		&"age": "So I'm washed now? Unbelievable.",
		&"market": "I'm not some average guy. Don't compare me to them.",
		&"contender": "I don't care about rings. Pay me.",
		&"cap": "Don't make your mistakes my problem.",
		&"competition": "You're threatening me with a backup? Then play him.",
		&"loyalty": "Loyalty? Don't guilt-trip me."}
	return "%s My price just went up." % lines.get(id, "That was out of line.")


func _build_arguments() -> Array:
	var s := soldier
	var d := s.get_dna()
	var out: Array = []
	var temper_n := d.n(&"temperament")
	var role := Scheme.best_role(s.stats)

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
					"fit": 0.6 + 0.6 * d.n(&"savvy") - 0.9 * (1.0 - temper_n) * (1.0 if s.best_ovr() >= 75 else 0.5)})

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
			"fit": 0.4 + 0.7 * d.n(&"security") - 0.3 * d.n(&"money") + 0.2 * d.n(&"savvy")})

	# Comparable contracts around the league.
	var comps: Array = []
	for t in season.league.teams:
		for so in t.roster:
			if so == s or so.contract == null or so.contract.rookie:
				continue
			if Scheme.best_role(so.stats) == role and absi(so.best_ovr() - s.best_ovr()) <= 2:
				comps.append(so.contract.salary)
	var ask := demand(Contracts.preferred_years(s))
	if comps.size() >= 3:
		var avg := 0.0
		for c in comps:
			avg += c
		avg /= comps.size()
		if avg < ask * 0.95:
			out.append({"id": &"market", "title": "Comparable contracts", "tone": "neutral",
				"pitch": "%d %ss at your level average %s. That's the market." % [comps.size(), Scheme.ROLE_NAMES[role], Contracts.money(roundi(avg))],
				"evidence": clampf((ask - avg) / ask * 4.0, 0.0, 1.0) * clampf(comps.size() / 6.0, 0.4, 1.0),
				"evidence_text": "%d %ss within 2 OVR average %s / yr (he asks %s)." % [comps.size(), Scheme.ROLE_NAMES[role], Contracts.money(roundi(avg)), Contracts.money(ask)],
				"fit": 0.4 + 0.8 * d.n(&"savvy")})

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

	# Cap squeeze.
	var space := Contracts.cap_space(team, season.cap_year()) - ask
	var tight := Contracts.SALARY_CAP * 0.08
	if space < tight:
		out.append({"id": &"cap", "title": "Cap is tight", "tone": "soft",
			"pitch": "Paying your ask leaves us %s under the cap. I need help to keep this roster together." % Contracts.money(space),
			"evidence": clampf(1.0 - space / tight, 0.2, 1.0), "evidence_text": "Cap space after his ask: %s." % Contracts.money(space),
			"fit": 0.2 + 0.9 * d.n(&"loyalty") - 0.3 * d.n(&"money") + 0.2 * d.n(&"savvy")})

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

	# Years with the club.
	var yrs := 0
	for y in s.season_lines:
		if s.season_lines[y].get("team", "") == team.abbrev:
			yrs += 1
	if yrs >= 2:
		out.append({"id": &"loyalty", "title": "Loyalty to the club", "tone": "soft",
			"pitch": "You've been with us %d seasons. This is home." % yrs,
			"evidence": clampf(yrs / 5.0, 0.3, 1.0), "evidence_text": "%d seasons with %s." % [yrs, team.abbrev],
			"fit": 0.1 + 1.2 * d.n(&"loyalty")})
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

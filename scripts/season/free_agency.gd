class_name FreeAgency
extends RefCounted
## Free-agent bidding. Teams place offers (salary + years) on free agents; offers resolve each
## free-agency day in the offseason and at the start of every week in-season. Each soldier
## scores his offers and signs with the best one if it clears his bar; otherwise he waits and
## lowers his asking price.
##
## Offer score (weights come from his DNA; an average soldier is about 70 / 15 / 15):
##     W_money x money (salary / his asking price for that length, capped at 1.3)
##   + W_win x team quality (team OVR) + W_time x playing time (would he start there? a starter
##     promise counts for a lot) + loyalty (his former club, scaled by trust) + security (deal
##     length vs what he wants) + hometown (a club near home, scaled by his Hometown DNA).

const W_MONEY := 0.70
const W_TEAM := 0.15
const W_ROLE := 0.15
## How far DNA moves the weights (before they're normalised to sum to 1).
const DNA_MONEY := [0.55, 0.30]
const DNA_WIN := [0.05, 0.20]
const DNA_TIME := [0.05, 0.20]
const LOYALTY_BONUS := 0.12
const SECURITY_BONUS := 0.05
const HOMETOWN_BONUS := 0.10
## A starter promise: a backup treats it as nearly a starting job; a starter likes the guarantee.
const PROMISE_ROLE := 0.45
const PROMISE_STARTER_BONUS := 0.15
## Score a soldier needs to sign: an at-asking offer from an average team where he'd come off
## the bench just clears it.
const ACCEPT_SCORE := 0.80
## Asking price multiplier after each resolution without signing (with / without offers).
const ASK_DROP_WITH_OFFERS := 0.92
const ASK_DROP_NO_OFFERS := 0.95
const ASK_FLOOR := 0.55

## Pending offers: {team: Team, soldier: Soldier, salary: int, years: int, promise: bool}.
var offers: Array = []
## Every signing: {soldier, team, salary, years, year, when: String, user: bool}.
var history: Array = []


func offer_of(team: Team, s: Soldier) -> Dictionary:
	for o in offers:
		if o["team"] == team and o["soldier"] == s:
			return o
	return {}


func offers_for(s: Soldier) -> Array:
	return offers.filter(func(o): return o["soldier"] == s)


func offers_by(team: Team) -> Array:
	return offers.filter(func(o): return o["team"] == team)


## Salary promised in a team's pending offers (optionally ignoring the offer on `except`).
func committed(team: Team, except: Soldier = null) -> int:
	var total := 0
	for o in offers_by(team):
		if o["soldier"] != except and o["salary"] > Contracts.MIN_SALARY:
			total += o["salary"]
	return total


## Why `team` can't make this offer ("" = it can).
func offer_error(season: Season, team: Team, s: Soldier, salary: int, years: int, promise := false) -> String:
	if not season.free_agency_open():
		return "Free agency opens when the re-signing window closes."
	if not season.league.free_agents.has(s):
		return "%s is not a free agent." % s.full_name()
	if years < 1 or years > Contracts.MAX_YEARS:
		return "Deals run 1-%d years." % Contracts.MAX_YEARS
	if salary < Contracts.MIN_SALARY or salary > Contracts.MAX_SALARY:
		return "Salary must be %s - %s." % [Contracts.money(Contracts.MIN_SALARY), Contracts.money(Contracts.MAX_SALARY)]
	var pending := 0
	for o in offers_by(team):
		if o["soldier"] != s:
			pending += 1
	if team.user_controlled and roster_capped(season, team) and team.roster.size() + pending >= Team.ROSTER_SIZE:
		return "No roster space: %d on the roster + %d pending offers (max %d)." % [team.roster.size(), pending, Team.ROSTER_SIZE]
	if not Contracts.fits(team, season.cap_year(), salary, committed(team, s)):
		return "Not enough cap space (%s left after pending offers)." % Contracts.money(Contracts.cap_space(team, season.cap_year()) - committed(team, s))
	if promise and promises_made(season, team, s) >= team.scheme.slot_ids().size():
		return "You've already promised all %d starting spots." % team.scheme.slot_ids().size()
	return ""


## Starter promises `team` has out for the cap year: rostered soldiers plus pending offers
## (optionally ignoring the offer on `except`).
func promises_made(season: Season, team: Team, except: Soldier = null) -> int:
	var n := 0
	for so in team.roster:
		if not so.promise.is_empty() and int(so.promise["year"]) == season.cap_year():
			n += 1
	for o in offers_by(team):
		if o["soldier"] != except and o.get("promise", false):
			n += 1
	return n


## Every team may carry more than ROSTER_SIZE soldiers during the offseason (cut down before
## Week 1); in-season everyone is held to the limit.
static func roster_capped(season: Season, _team: Team = null) -> bool:
	return season.phase != Season.PHASE_OFFSEASON


## A full roster stops the user signing in-season; an AI team releases its least valuable
## player instead (sign_player).
static func blocks_signing(season: Season, team: Team) -> bool:
	return team.user_controlled and roster_capped(season, team) and team.roster.size() >= Team.ROSTER_SIZE


## Places or replaces `team`'s offer. Returns the error text ("" on success).
func make_offer(season: Season, team: Team, s: Soldier, salary: int, years: int, promise := false) -> String:
	var err := offer_error(season, team, s, salary, years, promise)
	if err != "":
		return err
	withdraw(team, s)
	offers.append({"team": team, "soldier": s, "salary": salary, "years": years, "promise": promise})
	return ""


func withdraw(team: Team, s: Soldier) -> void:
	offers = offers.filter(func(o): return not (o["team"] == team and o["soldier"] == s))


## Whether `s` would start for `team` at his best role (beats the weakest starter there).
static func would_start(team: Team, s: Soldier) -> bool:
	var role := Scheme.best_role(s.stats)
	var weakest := 999
	for slot_id in team.scheme.slot_ids():
		if team.scheme.role_for_slot(slot_id) != role:
			continue
		var cur: Soldier = team.lineup.get(slot_id)
		if cur == null:
			return true
		weakest = mini(weakest, cur.ovr_at_role(role))
	return s.ovr_at_role(role) > weakest


static func score(team: Team, s: Soldier, salary: int, years: int, promise := false) -> float:
	var d := s.get_dna()
	var w := weights(s)
	var money := minf(1.3, float(salary) / float(maxi(1, Contracts.asking(s, years))))
	var team_q := clampf((team.team_ovr() - 64.0) / 25.0, 0.0, 1.0)
	var starts := would_start(team, s)
	var role := 1.0 if starts else 0.3
	if promise:
		role += PROMISE_STARTER_BONUS if starts else PROMISE_ROLE
	var sc: float = w[0] * money + w[1] * team_q + w[2] * role
	if s.former_team != "" and s.former_team == team.abbrev:
		sc += LOYALTY_BONUS * d.n(&"loyalty") * clampf((s.trust - 30.0) / 40.0, -1.0, 1.0)
	sc += HOMETOWN_BONUS * Dna.hometown_pull(s, team)
	sc += SECURITY_BONUS * (d.n(&"security") - 0.5) * 2.0 * clampf((years - Contracts.preferred_years(s)) / 2.0, -1.0, 1.0)
	return sc


## [money, winning, playing time] weights from his DNA, summing to 1.
static func weights(s: Soldier) -> Array:
	var d := s.get_dna()
	var m: float = DNA_MONEY[0] + DNA_MONEY[1] * d.n(&"money")
	var wi: float = DNA_WIN[0] + DNA_WIN[1] * d.n(&"winning")
	var t: float = DNA_TIME[0] + DNA_TIME[1] * d.n(&"playing_time")
	var total := m + wi + t
	return [m / total, wi / total, t / total]


## Player interest in an offer, for the UI: [label, color].
static func interest(team: Team, s: Soldier, salary: int, years: int, promise := false) -> Array:
	var r := score(team, s, salary, years, promise) / ACCEPT_SCORE
	if r >= 1.08:
		return ["VERY HIGH", Color("#22c55e")]
	if r >= 1.0:
		return ["HIGH", Color("#84cc16")]
	if r >= 0.93:
		return ["MEDIUM", Color("#f59e0b")]
	return ["LOW", Color("#ef4444")]


## AI front offices. Open roster spots are filled with the best fit they can afford, and a team
## also chases a free agent who clearly beats its least valuable player (Team.keep_value: OVR,
## upside, age, depth, contract), so good free agents draw several bids. In the offseason AI
## rosters may run over the limit (they cut down before Week 1); in-season a signing releases
## the team's least valuable player. Contenders pay a premium for stars, and every rival bid
## already on a player pushes the next one up.
const AI_UPGRADE_MARGIN := 3.0
const AI_UPGRADE_BIDS := 2
const AI_UPGRADE_BIDS_IN_SEASON := 1
const AI_OFFSEASON_MAX := Team.OFFSEASON_MAX


func ai_offers(season: Season, rng: RandomNumberGenerator, in_season := false) -> void:
	var pool := season.league.free_agents
	if pool.is_empty():
		return
	for team in season.league.teams:
		if team.user_controlled:
			continue
		if in_season and rng.randf() > 0.5:
			continue
		var mine := offers_by(team)
		# Before the draft, roster spots and rookie-scale money are held back for the picks.
		var picks := season.pending_picks(team)
		var reserve := season.rookie_reserve(team)
		var open := maxi(0, Team.ROSTER_SIZE - team.roster.size() - picks - mine.size())
		var budget := maxi(0, Team.ROSTER_SIZE - team.roster.size() - picks) + (AI_UPGRADE_BIDS_IN_SEASON if in_season else AI_UPGRADE_BIDS) - mine.size()
		if not roster_capped(season, team):
			budget = mini(budget, AI_OFFSEASON_MAX - team.roster.size() - picks - mine.size())
		if budget <= 0:
			continue
		var worst := team.least_valuable()
		var bar := (team.keep_value(worst) if worst != null else -INF) + AI_UPGRADE_MARGIN
		var kv := {}
		for s: Soldier in pool:
			kv[s] = team.keep_value(s)
		var ranked: Array = pool.duplicate()
		ranked.sort_custom(func(a: Soldier, b: Soldier): return kv[a] > kv[b])
		var contender := team.team_ovr() >= 78
		for s: Soldier in ranked:
			if budget <= 0:
				break
			if open <= 0 and kv[s] < bar:
				break
			if not offer_of(team, s).is_empty():
				continue
			var years := Contracts.preferred_years(s)
			var ask := Contracts.asking(s, years)
			var mult := rng.randf_range(0.95, 1.08) + 0.04 * offers_for(s).size()
			if contender and s.best_ovr() >= 80:
				mult += 0.05
			var salary := clampi(roundi(ask * mult / 10.0) * 10, Contracts.MIN_SALARY, Contracts.MAX_SALARY)
			if not Contracts.fits(team, season.cap_year(), salary, committed(team) + reserve):
				salary = ask
				if not Contracts.fits(team, season.cap_year(), salary, committed(team) + reserve):
					continue
			if make_offer(season, team, s, salary, years) == "":
				budget -= 1
				open -= 1


static func _ai_value(s: Soldier, weak_role: int) -> float:
	var v := float(s.best_ovr()) + (3.0 if Scheme.best_role(s.stats) == weak_role else 0.0)
	if s.age <= 25:
		v += 0.8 * s.potential
	if s.age >= 32:
		v -= 2.0 * (s.age - 31)
	return v


## Resolves every pending offer. Best soldiers choose first. Returns this round's signings.
## With `only`, just the soldiers that team bid on decide (between all their offers).
func resolve(season: Season, rng: RandomNumberGenerator, when: String, only: Team = null) -> Array:
	var signed: Array = []
	var pool: Array = season.league.free_agents.duplicate()
	pool.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	for s: Soldier in pool:
		var mine := offers_for(s)
		if only != null and not mine.any(func(o): return o["team"] == only):
			continue
		var best: Dictionary = {}
		var best_score := -1.0
		for o in mine:
			var team: Team = o["team"]
			if blocks_signing(season, team):
				continue
			if not Contracts.fits(team, season.cap_year(), o["salary"]):
				continue
			var sc := score(team, s, o["salary"], o["years"], o.get("promise", false)) + rng.randf_range(0.0, 0.01)
			if sc > best_score:
				best_score = sc
				best = o
		if not best.is_empty() and best_score >= ACCEPT_SCORE:
			signed.append(sign_player(season, best["team"], s, best["salary"], best["years"], when, best.get("promise", false)))
		else:
			s.ask_mult = maxf(ASK_FLOOR, s.ask_mult * (ASK_DROP_WITH_OFFERS if not mine.is_empty() else ASK_DROP_NO_OFFERS))
	# Offers that couldn't be honoured (roster filled up) are dropped; the rest stay pending.
	offers = offers.filter(func(o): return season.league.free_agents.has(o["soldier"]) and not blocks_signing(season, o["team"]))
	return signed


## In-season decision on the spot (no waiting a week): `s` weighs every current offer right
## now. Returns {signed: entry or {}, text: String} from `team`'s point of view. His asking
## price doesn't drop, so re-offering can't be used to wear him down.
func decide_now(season: Season, team: Team, s: Soldier) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for o in offers_for(s):
		var t: Team = o["team"]
		if blocks_signing(season, t):
			continue
		if not Contracts.fits(t, season.cap_year(), o["salary"]):
			continue
		var sc := score(t, s, o["salary"], o["years"], o.get("promise", false))
		if sc > best_score or (sc == best_score and t == team):
			best_score = sc
			best = o
	if best.is_empty() or best_score < ACCEPT_SCORE:
		return {"signed": {}, "text": "%s turned it down - not enough to sign. Raise the money, years or add a starter promise." % s.full_name()}
	var winner: Team = best["team"]
	var entry := sign_player(season, winner, s, best["salary"], best["years"], season.week_label(season.week), best.get("promise", false))
	if winner == team:
		return {"signed": entry, "text": "%s signed with you: %s x %d." % [s.full_name(), Contracts.money(best["salary"]), best["years"]]}
	return {"signed": entry, "text": "%s chose %s's offer instead." % [s.full_name(), winner.name]}


## Signs a free agent outright (accepted offer, or a team filling its roster).
func sign_player(season: Season, team: Team, s: Soldier, salary: int, years: int, when: String, promise := false) -> Dictionary:
	season.league.free_agents.erase(s)
	if s.former_team != team.abbrev:
		s.trust = Soldier.TRUST_NEUTRAL
	s.trade_request = false
	s.promise = {"year": season.cap_year(), "team": team.abbrev, "games": 0, "started": 0} if promise else {}
	offers = offers.filter(func(o): return o["soldier"] != s)
	if not team.user_controlled and roster_capped(season, team) and team.roster.size() >= Team.ROSTER_SIZE:
		var cut := team.least_valuable()
		if cut != null:
			season.release_player(team, cut)
			season.trades.moves.append({"year": season.year, "when": season.trades._when(season), "team": team, "soldier": cut, "kind": &"cut", "to": null})
	s.contract = Contract.make(salary, years, season.year)
	s.ask_mult = 1.0
	s.intensity = Soldier.INTENSITY_NORMAL
	s.morale = maxf(s.morale, 80.0)
	team.roster.append(s)
	season.league.give_callsign(s)
	if team.lineup.size() < team.scheme.slot_ids().size():
		team.auto_lineup()
	var entry := {"soldier": s, "team": team, "salary": salary, "years": years, "year": season.year, "when": when, "user": team.user_controlled, "promise": promise}
	history.append(entry)
	return entry


## Fills `team` up to `target` players with the best affordable free agents at their asking
## price (or the minimum when over the cap). Used for AI teams before the season starts.
func fill_roster(season: Season, team: Team, target: int, when: String) -> Array:
	var out: Array = []
	while team.roster.size() < target and not season.league.free_agents.is_empty():
		var weak := Draft.weakest_role(team)
		var ranked: Array = season.league.free_agents.duplicate()
		ranked.sort_custom(func(a: Soldier, b: Soldier): return _ai_value(a, weak) > _ai_value(b, weak))
		var pick: Soldier = null
		var salary := Contracts.MIN_SALARY
		for s: Soldier in ranked:
			var ask := Contracts.asking(s, Contracts.preferred_years(s))
			if Contracts.fits(team, season.cap_year(), ask):
				pick = s
				salary = ask
				break
		if pick == null:
			pick = ranked[-1]
			for s: Soldier in ranked:
				if Contracts.asking(s, Contracts.preferred_years(s)) <= Contracts.MIN_SALARY:
					pick = s
					break
			salary = Contracts.MIN_SALARY
		out.append(sign_player(season, team, pick, salary, Contracts.preferred_years(pick), when))
	return out

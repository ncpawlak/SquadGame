class_name FreeAgency
extends RefCounted
## Free-agent bidding. Teams place offers (salary + years) on free agents; offers resolve each
## free-agency day in the offseason and at the start of every week in-season. Each soldier
## scores his offers and signs with the best one if it clears his bar; otherwise he waits and
## lowers his asking price.
##
## Offer score = 0.70 x money (salary / his asking price for that length, capped at 1.3)
##             + 0.15 x team quality (team OVR) + 0.15 x playing time (would he start there?)

const W_MONEY := 0.70
const W_TEAM := 0.15
const W_ROLE := 0.15
## Score a soldier needs to sign: an at-asking offer from an average team where he'd come off
## the bench just clears it.
const ACCEPT_SCORE := 0.80
## Asking price multiplier after each resolution without signing (with / without offers).
const ASK_DROP_WITH_OFFERS := 0.92
const ASK_DROP_NO_OFFERS := 0.95
const ASK_FLOOR := 0.55

## Pending offers: {team: Team, soldier: Soldier, salary: int, years: int}.
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
func offer_error(season: Season, team: Team, s: Soldier, salary: int, years: int) -> String:
	if not season.free_agency_open():
		return "Free agency opens after the draft."
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
	if roster_capped(season, team) and team.roster.size() + pending >= Team.ROSTER_SIZE:
		return "No roster space: %d on the roster + %d pending offers (max %d)." % [team.roster.size(), pending, Team.ROSTER_SIZE]
	if not Contracts.fits(team, season.cap_year(), salary, committed(team, s)):
		return "Not enough cap space (%s left after pending offers)." % Contracts.money(Contracts.cap_space(team, season.cap_year()) - committed(team, s))
	return ""


## The user may carry more than ROSTER_SIZE soldiers during the offseason (he must cut down
## before Week 1); AI teams and everyone in-season are held to the limit.
static func roster_capped(season: Season, team: Team) -> bool:
	return not (team.user_controlled and season.phase == Season.PHASE_OFFSEASON)


## Places or replaces `team`'s offer. Returns the error text ("" on success).
func make_offer(season: Season, team: Team, s: Soldier, salary: int, years: int) -> String:
	var err := offer_error(season, team, s, salary, years)
	if err != "":
		return err
	withdraw(team, s)
	offers.append({"team": team, "soldier": s, "salary": salary, "years": years})
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


static func score(team: Team, s: Soldier, salary: int, years: int) -> float:
	var money := minf(1.3, float(salary) / float(maxi(1, Contracts.asking(s, years))))
	var team_q := clampf((team.team_ovr() - 58.0) / 20.0, 0.0, 1.0)
	var role := 1.0 if would_start(team, s) else 0.3
	return W_MONEY * money + W_TEAM * team_q + W_ROLE * role


## Player interest in an offer, for the UI: [label, color].
static func interest(team: Team, s: Soldier, salary: int, years: int) -> Array:
	var r := score(team, s, salary, years) / ACCEPT_SCORE
	if r >= 1.08:
		return ["VERY HIGH", Color("#22c55e")]
	if r >= 1.0:
		return ["HIGH", Color("#84cc16")]
	if r >= 0.93:
		return ["MEDIUM", Color("#f59e0b")]
	return ["LOW", Color("#ef4444")]


## AI teams bid for open roster spots: the best free agent at their weakest role they can
## afford, at roughly his asking price for his preferred length.
func ai_offers(season: Season, rng: RandomNumberGenerator, in_season := false) -> void:
	var pool := season.league.free_agents
	if pool.is_empty():
		return
	for team in season.league.teams:
		if team.user_controlled:
			continue
		if in_season and rng.randf() > 0.5:
			continue
		var open := Team.ROSTER_SIZE - team.roster.size() - offers_by(team).size()
		if open <= 0:
			continue
		var weak := Draft.weakest_role(team)
		var ranked: Array = pool.duplicate()
		ranked.sort_custom(func(a: Soldier, b: Soldier): return _ai_value(a, weak) > _ai_value(b, weak))
		for s: Soldier in ranked:
			if open <= 0:
				break
			if not offer_of(team, s).is_empty():
				continue
			var years := Contracts.preferred_years(s)
			var ask := Contracts.asking(s, years)
			var salary := clampi(roundi(ask * rng.randf_range(0.95, 1.1) / 10.0) * 10, Contracts.MIN_SALARY, Contracts.MAX_SALARY)
			if not Contracts.fits(team, season.cap_year(), salary, committed(team)):
				salary = ask
				if not Contracts.fits(team, season.cap_year(), salary, committed(team)):
					continue
			if make_offer(season, team, s, salary, years) == "":
				open -= 1


static func _ai_value(s: Soldier, weak_role: int) -> float:
	var v := float(s.best_ovr()) + (3.0 if Scheme.best_role(s.stats) == weak_role else 0.0)
	if s.age <= 25:
		v += 0.8 * s.potential
	if s.age >= 32:
		v -= 2.0 * (s.age - 31)
	return v


## Resolves every pending offer. Best soldiers choose first. Returns this round's signings.
func resolve(season: Season, rng: RandomNumberGenerator, when: String) -> Array:
	var signed: Array = []
	var pool: Array = season.league.free_agents.duplicate()
	pool.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	for s: Soldier in pool:
		var mine := offers_for(s)
		var best: Dictionary = {}
		var best_score := -1.0
		for o in mine:
			var team: Team = o["team"]
			if roster_capped(season, team) and team.roster.size() >= Team.ROSTER_SIZE:
				continue
			if not Contracts.fits(team, season.cap_year(), o["salary"]):
				continue
			var sc := score(team, s, o["salary"], o["years"]) + rng.randf_range(0.0, 0.01)
			if sc > best_score:
				best_score = sc
				best = o
		if not best.is_empty() and best_score >= ACCEPT_SCORE:
			signed.append(sign_player(season, best["team"], s, best["salary"], best["years"], when))
		else:
			s.ask_mult = maxf(ASK_FLOOR, s.ask_mult * (ASK_DROP_WITH_OFFERS if not mine.is_empty() else ASK_DROP_NO_OFFERS))
	# Offers that couldn't be honoured (roster filled up) are dropped; the rest stay pending.
	offers = offers.filter(func(o): return season.league.free_agents.has(o["soldier"]) and (not roster_capped(season, o["team"]) or o["team"].roster.size() < Team.ROSTER_SIZE))
	return signed


## Signs a free agent outright (accepted offer, or a team filling its roster).
func sign_player(season: Season, team: Team, s: Soldier, salary: int, years: int, when: String) -> Dictionary:
	season.league.free_agents.erase(s)
	offers = offers.filter(func(o): return o["soldier"] != s)
	s.contract = Contract.make(salary, years, season.year)
	s.ask_mult = 1.0
	s.intensity = Soldier.INTENSITY_NORMAL
	s.morale = maxf(s.morale, 80.0)
	team.roster.append(s)
	season.league.give_callsign(s)
	if team.lineup.size() < team.scheme.slot_ids().size():
		team.auto_lineup()
	var entry := {"soldier": s, "team": team, "salary": salary, "years": years, "year": season.year, "when": when, "user": team.user_controlled}
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

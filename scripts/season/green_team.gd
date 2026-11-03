class_name GreenTeam
extends RefCounted
## The Green Team: every club's development roster (like a practice squad / minor-league team),
## kept apart from the 10-man main roster (Team.green_team, up to Team.GREEN_SIZE).
##
## - Every draft pick starts on the Green Team on a Green Team deal (Contracts.green_contract: one
##   year, $100K-$500K, renewed each offseason while he stays down). A low-trust player may refuse
##   the renewal and leave as a free agent.
## - Call up (any time): instant, no talks. He plays the rest of the season on his Green Team deal,
##   then must sign a real contract in the re-sign window (the Call-Ups section) or he becomes a free
##   agent - even if he was sent back down. In the offseason a call-up signs at once (his asking price).
## - Send down: a young main-roster player (age <= MAX_AGE, <= MAX_PRO_SEASONS seasons) can be sent
##   down once in his career, then never again. He keeps his salary.
## - Injury replacement: while a main-roster player is out MIN_COVER_WEEKS+ weeks, one Green Team
##   player may cover for him without counting against the roster limit and without new talks.
##   When the injured player is healthy (or leaves) the replacement goes back down, using his one
##   send-down - unless he was converted to a full call-up. At season end replacements go down free.
##   Teams down to fewer than 5 healthy players get one automatically.
## - A player may spend MAX_SEASONS seasons on the Green Team; then he must be called up or let go.
## - Development: Green Team players train at XP_MULT x XP and gain reps (see Soldier.reps) faster
##   than main-roster bench players. Reps reveal potential.
## - Patience: no playing-time frustration in his first Green Team season (round-1 picks who are
##   ready to play excepted); after that his morale slides by DNA, and an unhappy one asks out.

const MAX_SEASONS := 3
const MAX_AGE := 24
const MAX_PRO_SEASONS := 3
const XP_MULT := 1.5
const MIN_COVER_WEEKS := 2
## New leagues and old saves: the lowest-OVR players moved down from each 12-man roster.
const SETUP_MOVED := 2
## Reps per week: Green Team by training intensity; main roster starters / bench.
const REP_INTENSITY := {
	Soldier.INTENSITY_REST: 0.5, Soldier.INTENSITY_LIGHT: 0.75,
	Soldier.INTENSITY_NORMAL: 1.0, Soldier.INTENSITY_HEAVY: 1.5,
}
const STARTER_REPS := 1.0
const BENCH_REPS := 0.5
## Pre-draft scouting head start: reps per scouting point (10 points = 4 reps); AI clubs' own picks.
const DRAFT_REPS_PER_POINT := 0.4
const AI_DRAFT_REPS := 2.0
## Weekly morale for a patient (first-season) Green Team player, and the base slide once frustrated.
const CONTENT := 0.3
const FRUSTRATION := -2.0
## Morale under this asks for a call-up or a trade (weekly morale settles near 75 + 4 x the weekly change,
## so only impatient DNA - high playing-time, low temperament, round-1 picks - gets here).
const ASK_OUT_MORALE := 65.0
## Trust under this may refuse the Green Team renewal (chance grows as trust falls).
const REFUSE_TRUST := 30.0
const CALLUP_MORALE := 8.0
const CALLUP_TRUST := 5.0
const SEND_DOWN_MORALE := -6.0
## AI: a Green Team player must beat a main-roster player's OVR by this much to swap them in season.
const AI_SWAP_MARGIN := 3


# --- eligibility -------------------------------------------------------------

## Seasons he has played on a main roster.
static func pro_seasons(s: Soldier) -> int:
	return s.season_lines.size()


static func is_green(team: Team, s: Soldier) -> bool:
	return team.green_team.has(s)


## A Green Team player good enough to help now: better than the worst healthy bench player.
static func is_ready(team: Team, s: Soldier) -> bool:
	var worst := 999
	for b in team.bench():
		if b.injury_cover_for == 0:
			worst = mini(worst, b.best_ovr())
	if worst == 999:
		return false
	return s.best_ovr() > worst


## Frustrated: past his first season down, or a round-1 pick who is ready to play.
static func is_frustrated(team: Team, s: Soldier) -> bool:
	if s.green_seasons >= 1:
		return true
	return _round(s) == 1 and is_ready(team, s)


static func _round(s: Soldier) -> int:
	if s.draft_pick <= 0:
		return 0
	return (s.draft_pick - 1) / maxi(1, Team.league_size) + 1


## Projected end-of-season asking price if he is called up now (his re-sign ask today).
static func projected_ask(s: Soldier) -> int:
	return Contracts.resign_asking(s, Contracts.preferred_years(s))


# --- call up -----------------------------------------------------------------

## Why `s` can't be called up to `team`'s main roster ("" = he can).
static func call_up_error(season: Season, team: Team, s: Soldier) -> String:
	if not team.green_team.has(s):
		return "%s isn't on the Green Team." % s.full_name()
	var limit := Team.OFFSEASON_MAX if season.phase == Season.PHASE_OFFSEASON else Team.ROSTER_SIZE
	if team.roster_count() >= limit:
		return "The roster is full (%d/%d). Send a player down or release one first." % [team.roster_count(), limit]
	if _signs_now(season, s):
		var ask := projected_ask(s)
		if not Contracts.resign_fits(team, season.cap_year(), s, ask):
			return "No room under the apron for his %s asking price." % Contracts.money(ask)
	return ""


## Offseason call-ups of a player still on his Green Team deal sign a real contract at once.
static func _signs_now(season: Season, s: Soldier) -> bool:
	return season.phase == Season.PHASE_OFFSEASON and s.contract != null and s.contract.green \
		and not s.contract.is_expiring() and not s.callup_pending


## Calls `s` up. Returns "" or the reason it failed.
static func call_up(season: Season, team: Team, s: Soldier) -> String:
	var err := call_up_error(season, team, s)
	if err != "":
		return err
	if _signs_now(season, s):
		var yrs := Contracts.preferred_years(s)
		var salary := projected_ask(s)
		s.contract = Contract.make(salary, yrs, season.year)
		season.resign_log.append({"soldier": s, "team": team, "salary": salary, "years": yrs, "year": season.year, "extension": false})
	elif s.contract != null and s.contract.green:
		s.callup_pending = true
	_move_up(team, s)
	s.add_morale(CALLUP_MORALE)
	s.add_trust(CALLUP_TRUST)
	s.trade_request = false
	_log(season, team, s, &"call_up")
	return ""


static func _move_up(team: Team, s: Soldier) -> void:
	team.green_team.erase(s)
	if not team.roster.has(s):
		team.roster.append(s)
	if team.user_controlled:
		team.fill_injured()
	elif team.roster.size() >= team.scheme.slot_ids().size():
		team.auto_lineup()


static func _move_down(team: Team, s: Soldier) -> void:
	var slot := team.slot_of(s)
	team.roster.erase(s)
	if slot != &"":
		team.lineup.erase(slot)
		team.fill_injured()
	s.injury_cover_for = 0
	s.promise = {}
	if not team.green_team.has(s):
		team.green_team.append(s)


# --- send down ---------------------------------------------------------------

## Why `s` can't be sent down ("" = he can).
static func send_down_error(season: Season, team: Team, s: Soldier) -> String:
	if not team.roster.has(s):
		return "%s isn't on the main roster." % s.full_name()
	if s.injury_cover_for != 0:
		return "%s is an injury replacement: he goes back down when the injured player returns." % s.full_name()
	if s.send_down_used:
		return "%s has already been sent down once. He can't be sent down again." % s.full_name()
	if s.age > MAX_AGE:
		return "Only players %d or younger can be sent down." % MAX_AGE
	if pro_seasons(s) > MAX_PRO_SEASONS:
		return "%s has played %d pro seasons (max %d to be sent down)." % [s.full_name(), pro_seasons(s), MAX_PRO_SEASONS]
	if season.phase != Season.PHASE_OFFSEASON and team.green_team.size() > Team.GREEN_SIZE:
		return "The Green Team is full (%d/%d). Call someone up first." % [team.green_team.size(), Team.GREEN_SIZE]
	return ""


## Short send-down status for the roster table: "AVAIL", "USED" or "-" (not eligible).
static func send_down_tag(season: Season, team: Team, s: Soldier) -> String:
	if s.send_down_used:
		return "USED"
	if s.age > MAX_AGE or pro_seasons(s) > MAX_PRO_SEASONS:
		return "-"
	return "AVAIL"


## Sends `s` down to the Green Team (his one send-down). Returns "" or the reason it failed.
static func send_down(season: Season, team: Team, s: Soldier) -> String:
	var err := send_down_error(season, team, s)
	if err != "":
		return err
	_move_down(team, s)
	s.send_down_used = true
	s.add_morale(SEND_DOWN_MORALE)
	_log(season, team, s, &"send_down")
	return ""


# --- injury replacement ------------------------------------------------------

## The Green Team player covering for `injured` (null = none).
static func cover_for(team: Team, injured: Soldier) -> Soldier:
	for s in team.roster:
		if s.injury_cover_for == injured.id:
			return s
	return null


## The injured player `s` covers for (null if he isn't a replacement or that player is gone).
static func covered(team: Team, s: Soldier) -> Soldier:
	if s.injury_cover_for == 0:
		return null
	for o in team.roster:
		if o.id == s.injury_cover_for:
			return o
	return null


## Main-roster players out long enough for an injury replacement who don't have one yet.
static func coverable(team: Team) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in team.roster:
		if s.injury_cover_for == 0 and s.injury_weeks >= MIN_COVER_WEEKS and cover_for(team, s) == null:
			out.append(s)
	return out


## Why `s` can't come up to cover for `injured` ("" = he can).
static func cover_error(season: Season, team: Team, injured: Soldier, s: Soldier, automatic := false) -> String:
	if season.phase == Season.PHASE_OFFSEASON:
		return "Injury replacements are for the season."
	if not team.green_team.has(s):
		return "%s isn't on the Green Team." % s.full_name()
	if not team.roster.has(injured) or not injured.is_injured():
		return "%s isn't on the injured list." % injured.full_name()
	if injured.injury_cover_for != 0:
		return "%s is himself an injury replacement." % injured.full_name()
	if not automatic and injured.injury_weeks < MIN_COVER_WEEKS:
		return "Injury replacements need an injury of %d+ weeks." % MIN_COVER_WEEKS
	if cover_for(team, injured) != null:
		return "%s already has a replacement." % injured.full_name()
	if s.send_down_used:
		return "%s has used his send-down: he can only come up for good (Call Up)." % s.full_name()
	if s.is_injured():
		return "%s is injured." % s.full_name()
	return ""


## Brings `s` up to cover for `injured`. Returns "" or the reason it failed.
static func cover(season: Season, team: Team, injured: Soldier, s: Soldier, automatic := false) -> String:
	var err := cover_error(season, team, injured, s, automatic)
	if err != "":
		return err
	_move_up(team, s)
	s.injury_cover_for = injured.id
	s.add_morale(CALLUP_MORALE * 0.5)
	_log(season, team, s, &"cover", injured)
	return ""


static func convert_error(season: Season, team: Team, s: Soldier) -> String:
	if not team.roster.has(s) or s.injury_cover_for == 0:
		return "%s isn't an injury replacement." % s.full_name()
	if team.roster_count() >= Team.ROSTER_SIZE:
		return "The roster is full (%d/%d). Send a player down or release one first." % [team.roster_count(), Team.ROSTER_SIZE]
	return ""


## Keeps an injury replacement up for good: no send-down used; he joins the Call-Ups negotiation.
static func convert_cover(season: Season, team: Team, s: Soldier) -> String:
	var err := convert_error(season, team, s)
	if err != "":
		return err
	s.injury_cover_for = 0
	if s.contract != null and s.contract.green:
		s.callup_pending = true
	s.add_morale(CALLUP_MORALE * 0.5)
	s.add_trust(CALLUP_TRUST)
	_log(season, team, s, &"call_up")
	return ""


## End of a week: replacements whose injured teammate is healthy again (or gone) go back down,
## using their send-down. AI clubs convert one instead when he is worth a roster spot.
static func update_covers(season: Season) -> void:
	for t in season.league.teams:
		for s in t.covers():
			var inj := covered(t, s)
			if inj != null and inj.is_injured():
				continue
			if not t.user_controlled and _ai_keeps_cover(t, s) and convert_cover(season, t, s) == "":
				continue
			_move_down(t, s)
			s.send_down_used = true
			_log(season, t, s, &"cover_done", inj)


static func _ai_keeps_cover(team: Team, s: Soldier) -> bool:
	if team.roster_count() >= Team.ROSTER_SIZE:
		return false
	return true


## Teams down to fewer than 5 healthy players get an automatic injury replacement (best healthy
## Green Team player for the longest injury without one).
static func auto_covers(season: Season) -> void:
	if season.phase == Season.PHASE_OFFSEASON:
		return
	for t in season.league.teams:
		var need := t.scheme.slot_ids().size()
		while _healthy(t) < need:
			var hurt: Array = t.roster.filter(func(o: Soldier): return o.is_injured() and o.injury_cover_for == 0 and cover_for(t, o) == null)
			if hurt.is_empty():
				break
			hurt.sort_custom(func(a: Soldier, b: Soldier): return a.injury_weeks > b.injury_weeks)
			var pick := _best_available(t, func(o: Soldier): return not o.send_down_used and not o.is_injured())
			if pick == null or cover(season, t, hurt[0], pick, true) != "":
				break


static func _healthy(team: Team) -> int:
	var n := 0
	for s in team.roster:
		if not s.is_injured():
			n += 1
	return n


static func _best_available(team: Team, ok: Callable) -> Soldier:
	var best: Soldier = null
	for s in team.green_team:
		if ok.call(s) and (best == null or s.best_ovr() > best.best_ovr()):
			best = s
	return best


# --- seasons -----------------------------------------------------------------

## The season just ended (after Contracts.rollover): injury replacements go back down (no
## send-down used), Green Team players log a season down and their expiring Green Team deals renew
## (a low-trust player may refuse and leave). Called-up players' deals wait for the Call-Ups talks.
static func season_end(season: Season, rng: RandomNumberGenerator) -> void:
	for t in season.league.teams:
		for s in t.covers():
			_move_down(t, s)
		for s in t.green_team.duplicate():
			s.green_seasons += 1
			if s.callup_pending or s.contract == null or not s.contract.is_expiring():
				continue
			if s.trust < REFUSE_TRUST and rng.randf() < (REFUSE_TRUST - s.trust) / REFUSE_TRUST:
				season.departures.append({"soldier": s, "team": t, "year": season.year, "green_refused": true})
				_log(season, t, s, &"refused")
				t.release(s)
				season.league.add_free_agent(s, season.year)
				continue
			var salary: int = s.contract.salary if s.contract.green else Contracts.green_salary_for(s)
			s.contract = Contracts.green_contract(salary, season.year)


## Called-up players who signed (or left) are settled once the re-sign window closes.
static func settle_callups(season: Season) -> void:
	for t in season.league.teams:
		for s in t.org():
			if s.callup_pending and s.contract != null and not s.contract.is_expiring():
				s.callup_pending = false


## Why the user's Green Team blocks Week 1 ("" = it doesn't).
static func user_error(team: Team) -> String:
	if team.green_team.size() > Team.GREEN_SIZE:
		var extra := team.green_team.size() - Team.GREEN_SIZE
		return "Your Green Team has %d players (max %d). Call up or release %d before Week 1." % [team.green_team.size(), Team.GREEN_SIZE, extra]
	for s in team.green_team:
		if s.green_seasons >= MAX_SEASONS:
			return "%s has spent %d seasons on the Green Team. Call him up or release him before Week 1." % [s.full_name(), MAX_SEASONS]
	return ""


# --- AI ----------------------------------------------------------------------

## AI weekly moves: fill open roster spots from the Green Team, then swap in one Green Team player
## who clearly beats a main-roster player who can still be sent down.
static func ai_week(season: Season, team: Team) -> void:
	if team.user_controlled:
		return
	while team.roster_count() < Team.ROSTER_SIZE:
		var up := _best_available(team, func(o: Soldier): return not o.is_injured())
		if up == null or call_up(season, team, up) != "":
			break
	var best := _best_available(team, func(o: Soldier): return not o.is_injured())
	if best == null:
		return
	var worst: Soldier = null
	for s in team.roster:
		if send_down_error(season, team, s) != "" or team.slot_of(s) != &"":
			continue
		if worst == null or s.best_ovr() < worst.best_ovr():
			worst = s
	if worst != null and best.best_ovr() >= worst.best_ovr() + AI_SWAP_MARGIN:
		if send_down(season, team, worst) == "":
			call_up(season, team, best)


## AI preseason clean-up (also the user's safety net in headless sims): players out of Green Team
## seasons are called up if they beat the roster's least valuable player (else released); then the
## Green Team is trimmed to GREEN_SIZE by keep value; open roster spots are filled from it.
static func enforce(season: Season, team: Team) -> void:
	for s in team.green_team.duplicate():
		if s.green_seasons < MAX_SEASONS:
			continue
		var worst := team.least_valuable()
		if worst != null and team.keep_value(s) > team.keep_value(worst) and call_up_error(season, team, s) != "":
			season.release_player(team, worst)
		if call_up(season, team, s) != "":
			season.release_player(team, s)
	while team.green_team.size() > Team.GREEN_SIZE:
		var cut: Soldier = null
		var cut_v := INF
		for s in team.green_team:
			var v := team.keep_value(s)
			if v < cut_v:
				cut_v = v
				cut = s
		season.release_player(team, cut)
	if not team.user_controlled:
		while team.roster_count() < Team.ROSTER_SIZE and not team.green_team.is_empty():
			var up := _best_available(team, func(_o: Soldier): return true)
			if call_up(season, team, up) != "":
				break


# --- training, reps, morale --------------------------------------------------

## Reps a draft pick starts with: the user's scouting head start, a flat AI_DRAFT_REPS for AI clubs.
static func draft_reps(p: Prospect, team: Team) -> float:
	if team != null and team.user_controlled:
		return minf(float(p.points) * DRAFT_REPS_PER_POINT, 4.0)
	return AI_DRAFT_REPS


## One week of reps for `team` (after lineups are set).
static func weekly_reps(team: Team) -> void:
	var starters := team.starters()
	for s in team.roster:
		if not s.is_injured():
			s.add_reps(STARTER_REPS if starters.has(s) else BENCH_REPS)
	for s in team.green_team:
		if not s.is_injured():
			s.add_reps(float(REP_INTENSITY.get(s.intensity, 1.0)))


## Weekly morale change for a Green Team player: content in his first season, then a DNA-scaled slide.
static func morale_delta(team: Team, s: Soldier) -> float:
	if not is_frustrated(team, s):
		return CONTENT
	var d := s.get_dna()
	var f := 0.5 + d.playing_time / 100.0
	if d.temperament <= 35:
		f *= 1.25
	if _round(s) == 1:
		f *= 1.25
	return FRUSTRATION * f


# --- setup -------------------------------------------------------------------

## Builds every club's Green Team (new leagues and saves from before it existed): the SETUP_MOVED
## lowest-OVR players (youngest first on ties) move down from the main roster on Green Team deals
## (they're exempt from the eligibility rules), then new rookie-tier players fill it to GREEN_SIZE.
static func setup_league(league: League, year: int, rng: RandomNumberGenerator) -> void:
	var roles := [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]
	for t in league.teams:
		var order: Array = t.roster.duplicate()
		order.sort_custom(func(a: Soldier, b: Soldier):
			return a.best_ovr() < b.best_ovr() if a.best_ovr() != b.best_ovr() else a.age < b.age)
		var moving := mini(SETUP_MOVED, maxi(0, t.roster.size() - Season.ROSTER_MIN))
		for i in moving:
			var s: Soldier = order[i]
			_move_down(t, s)
			s.contract = Contracts.green_contract(Contracts.green_salary_for(s), year)
			s.clear_extension()
		var k := 0
		while t.green_team.size() < Team.GREEN_SIZE:
			var role: Scheme.Role = roles[(t.id + k) % roles.size()]
			k += 1
			var quality := Draft.PROSPECT_QUALITY + rng.randfn(0.0, Draft.PROSPECT_QUALITY_SD)
			var s := PlayerGenerator.generate(rng, league.next_soldier_id, role, quality, rng.randi_range(19, 22))
			league.next_soldier_id += 1
			s.home_state = LeagueData.random_state(rng)
			s.reps = float(rng.randi_range(0, 6))
			s.morale = 78.0
			s.contract = Contracts.green_contract(Contracts.green_salary_for(s), year)
			t.green_team.append(s)
			league.give_callsign(s)
		if t.roster.size() >= t.scheme.slot_ids().size():
			t.auto_lineup()


# --- log ---------------------------------------------------------------------

static func _log(season: Season, team: Team, s: Soldier, kind: StringName, other: Soldier = null) -> void:
	season.green_log.append({"year": season.year, "when": Trades._when(season), "team": team, "soldier": s,
		"kind": kind, "other": other})

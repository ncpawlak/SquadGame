class_name Morale
extends RefCounted
## Weekly morale drivers (0-100, 75 = neutral). See Soldier.morale_mods() for the stat effects.
## - Playing time: starters who played +2, healthy benched players -1.5.
## - Results: win +2, loss -2 (whole roster). Match MVP +3.
## - Contract: underpaid (< 75% of market value, rookie deals excepted) -1, fairly paid +0.5.
## - Every week morale drifts 20% back toward neutral.

const STARTER := 2.0
const BENCHED := -1.5
const WIN := 2.0
const LOSS := -2.0
const MVP := 3.0
const UNDERPAID := -1.0
const FAIR_PAY := 0.5
const UNDERPAID_SHARE := 0.75
const FAIR_SHARE := 0.9
const DRIFT := 0.2


## Applies one week of morale changes. `played` = matches played this week.
static func update_week(league: League, played: Array) -> void:
	var result_of := {}
	var mvps := {}
	var started := {}
	for m in played:
		if not m.is_played():
			continue
		result_of[m.winner()] = WIN
		result_of[m.loser()] = LOSS
		mvps[m.result.mvp_id] = true
		for sid in m.result.box:
			started[sid] = true
	for t in league.teams:
		var played_this_week := result_of.has(t)
		for s in t.roster:
			var delta := 0.0
			if played_this_week:
				delta += result_of[t]
				if started.has(s.id):
					delta += STARTER
				elif not s.is_injured():
					delta += BENCHED
			if mvps.has(s.id):
				delta += MVP
			delta += contract_effect(s)
			s.add_morale(delta)
			s.morale = lerpf(s.morale, Soldier.MORALE_NEUTRAL, DRIFT)


static func contract_effect(s: Soldier) -> float:
	if s.contract == null or s.contract.rookie:
		return 0.0
	var market := float(Contracts.market_value(s))
	if market <= 0.0:
		return 0.0
	var share := float(s.contract.salary) / market
	if share < UNDERPAID_SHARE:
		return UNDERPAID
	if share >= FAIR_SHARE:
		return FAIR_PAY
	return 0.0


## Short reasons for the player page.
static func factors(s: Soldier, team: Team) -> Array[String]:
	var out: Array[String] = []
	if team != null:
		if team.slot_of(s) != &"":
			out.append("Starting (+)")
		elif not s.is_injured():
			out.append("Riding the bench (-)")
	var c := contract_effect(s)
	if c < 0.0:
		out.append("Feels underpaid (-)")
	elif c > 0.0:
		out.append("Happy with his contract (+)")
	return out

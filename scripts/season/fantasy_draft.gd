class_name FantasyDraft
extends RefCounted
## Fantasy draft at the start of a new franchise: every soldier in the league (all rosters and
## Green Teams) goes into one pool and the clubs draft them back, ROUNDS rounds, snake order
## (the round-1 order is random, then it reverses every round). Drafted soldiers keep their
## contracts and careers; each pick lands on the club's roster first (up to Team.ROSTER_SIZE),
## then on its Green Team (up to Team.GREEN_SIZE). Whoever is left over is released to free
## agency by Season.finish_fantasy_draft.
##
## All state is plain script vars, so SaveSystem's generic serializer persists a draft in progress.

const ROUNDS := 15
## AI scoring: bonus for a role the club still lacks starters at, penalty for stacking one role.
const NEED_BONUS := Draft.NEED_BONUS
const STACK_PENALTY := 3.0
## Std-dev of the noise AI clubs add to every evaluation (suggestions for the user use none).
const AI_NOISE := 1.2

var teams: Array[Team] = []
var user_team: Team = null
## Snake order of every pick: teams.size() * ROUNDS entries.
var order: Array[Team] = []
var pick_index := 0
## Everyone still undrafted.
var pool: Array[Soldier] = []
## Every pick so far: {team: Team, soldier: Soldier, pick: int (1-based), round: int (1-based)}.
var picks: Array = []
var rng := RandomNumberGenerator.new()
## Left over once Season.finish_fantasy_draft released them to free agency.
var undrafted: Array[Soldier] = []


## Pools every player in the league (removing them from their teams) and builds the snake order.
static func begin(season: Season, rng_in: RandomNumberGenerator) -> FantasyDraft:
	var d := FantasyDraft.new()
	d.rng = rng_in
	d.user_team = season.user_team()
	var seat: Array[Team] = []
	for t in season.league.teams:
		d.teams.append(t)
		seat.append(t)
		for s in t.roster:
			d.pool.append(s)
		for s in t.green_team:
			d.pool.append(s)
		t.roster.clear()
		t.green_team.clear()
		t.lineup.clear()
	for s in d.pool:
		s.promise = {}
		s.keep_promise = {}
		s.injury_cover_for = 0
		s.callup_pending = false
	# Fisher-Yates with the passed rng (Array.shuffle would use the global one).
	for i in range(seat.size() - 1, 0, -1):
		var j := rng_in.randi_range(0, i)
		var tmp := seat[i]
		seat[i] = seat[j]
		seat[j] = tmp
	for r in ROUNDS:
		for i in seat.size():
			d.order.append(seat[i] if r % 2 == 0 else seat[seat.size() - 1 - i])
	return d


func is_complete() -> bool:
	return pick_index >= order.size() or pool.is_empty()


func current_team() -> Team:
	return null if is_complete() else order[pick_index]


func user_on_clock() -> bool:
	return not is_complete() and user_team != null and order[pick_index] == user_team


## 1-based round of the pick on the clock (the last round once complete).
func round_number() -> int:
	return mini(ROUNDS, pick_index / maxi(1, teams.size()) + 1)


## 1-based overall number of the pick on the clock.
func pick_number() -> int:
	return pick_index + 1


## Undrafted soldiers, best overall first.
func available() -> Array[Soldier]:
	var out: Array[Soldier] = pool.duplicate()
	out.sort_custom(func(a: Soldier, b: Soldier):
		var oa := a.best_ovr()
		var ob := b.best_ovr()
		return oa > ob if oa != ob else a.id < b.id)
	return out


func picks_left_for(team: Team) -> int:
	var n := 0
	for i in range(pick_index, order.size()):
		if order[i] == team:
			n += 1
	return n


func results() -> Array:
	return picks.duplicate()


func team_picks(team: Team) -> Array:
	return picks.filter(func(p): return p["team"] == team)


## The user's pick. Returns "" or an error text.
func make_pick(s: Soldier) -> String:
	if is_complete():
		return "The draft is over."
	if not user_on_clock():
		return "It's not your pick."
	if not pool.has(s):
		return "%s is no longer available." % s.full_name()
	_take(order[pick_index], s)
	return ""


## Makes the pick for whoever is on the clock (an AI club's choice, noise included).
func sim_next() -> Dictionary:
	if is_complete():
		return {}
	var team := order[pick_index]
	return _take(team, _choose(team, true))


## AI clubs pick until the user is on the clock or the draft ends. Returns the pick dicts.
func sim_to_user_pick() -> Array:
	var made: Array = []
	while not is_complete() and not user_on_clock():
		made.append(sim_next())
	return made


## Picks everything that's left, for the user too.
func sim_to_end() -> Array:
	var made: Array = []
	while not is_complete():
		made.append(sim_next())
	return made


## The best-available choice for `team` without noise (also a suggestion for the user).
func ai_choice(team: Team) -> Soldier:
	return _choose(team, false)


# --- internals -------------------------------------------------------------------------

func _take(team: Team, s: Soldier) -> Dictionary:
	pool.erase(s)
	if team.roster.size() < Team.ROSTER_SIZE:
		team.roster.append(s)
	elif team.green_team.size() < Team.GREEN_SIZE:
		team.green_team.append(s)
	else:
		team.roster.append(s)  # overflow (only with oversized drafts): the offseason cap trims it
	var p := {"team": team, "soldier": s, "pick": pick_index + 1, "round": round_number()}
	picks.append(p)
	pick_index += 1
	return p


func _choose(team: Team, noisy: bool) -> Soldier:
	var deficit := _role_deficit(team)
	var best: Soldier = null
	var best_v := -INF
	for s in pool:
		var v := _value(s, deficit)
		if noisy:
			v += rng.randfn(0.0, AI_NOISE)
		if v > best_v or (v == best_v and best != null and s.id < best.id):
			best_v = v
			best = s
	return best


## Starting slots minus the club's picks at each role (positive = still needs a starter there).
func _role_deficit(team: Team) -> Dictionary:
	var d := {}
	for slot_id in team.scheme.slot_ids():
		var role: int = team.scheme.role_for_slot(slot_id)
		d[role] = int(d.get(role, 0)) + 1
	for s in team.org():
		var role: int = Scheme.best_role(s.stats)
		d[role] = int(d.get(role, 0)) - 1
	return d


## Rating now, upside for the young (weighted by dev stars), a decline for the old, and a
## nudge toward the club's open positions.
static func _value(s: Soldier, deficit: Dictionary) -> float:
	var now := float(s.best_ovr())
	var v := now
	var age_w := clampf((28.0 - s.age) / 7.0, 0.0, 1.0)
	var g := clampi(s.dev, Soldier.DEV_MIN, Soldier.DEV_MAX) - Soldier.DEV_MIN
	v += (maxf(0.0, float(s.potential_ovr()) - now) * float(Team.KEEP_DEV_W[g]) + float(Team.KEEP_DEV_FLAT[g])) * age_w
	if s.age >= 30:
		v -= float(s.age - 29) * 0.8
	if s.age >= 33:
		v -= float(s.age - 32) * 1.2
	var need := int(deficit.get(Scheme.best_role(s.stats), 0))
	if need > 0:
		v += NEED_BONUS
	elif need < -1:
		v -= STACK_PENALTY
	return v

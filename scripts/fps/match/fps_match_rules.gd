class_name FpsMatchRules
extends RefCounted
## Pure rules for the playable 3D match (no nodes, so tests drive them directly). They mirror the numeric sim
## (MatchEngine): TDM first to 50 with a +5 wipe bonus, King of the Hill 120 s of hold time (only a team alone on the
## point banks it), Sudden Death best to 4 rounds (7 at most) with one life per round.

const TDM_POINTS_TO_WIN := MatchEngine.TDM_POINTS_TO_WIN
const TDM_WIPE_BONUS := MatchEngine.TDM_WIPE_BONUS
const KOTH_HOLD_TO_WIN_S := MatchEngine.KOTH_HOLD_TO_WIN_S
const ROUNDS_TO_WIN := MatchEngine.ROUNDS_TO_WIN
const MAX_ROUNDS := MatchEngine.MAX_ROUNDS
const ROUND_TIME_LIMIT_S := MatchEngine.ROUND_TIME_LIMIT_S
const ARENA_SAFETY_LIMIT_S := MatchEngine.ARENA_SAFETY_LIMIT_S
const GAMES_TO_WIN := MatchEngine.GAMES_TO_WIN
const RESPAWN_S := 6.0
const INTERMISSION_S := 3.0
## Damage this life needed on a victim to share the kill as an assist (same as the sim).
const ASSIST_MIN_DAMAGE := 20.0

const HILL_EMPTY := -1
const HILL_CONTESTED := 2


## The box-score line every soldier starts with: exactly the keys MatchEngine creates.
static func box_template(soldier_id: int, team: int, slot: StringName) -> Dictionary:
	return {
		"team": team, "slot": slot, "kills": 0, "deaths": 0, "assists": 0, "shots": 0,
		"hits": 0, "headshots": 0, "damage": 0.0, "rounds_played": 0, "rounds_survived": 0,
		"clutches": 0, "saves": 0, "games": 0, "wipes": 0, "hill_s": 0.0, "caps": 0, "contest_s": 0.0,
		"opening_kills": 0, "kills_short": 0, "kills_medium": 0, "kills_long": 0, "kill_dist": 0.0,
		"bursts": 0, "fire_dist": 0.0, "distance": 0.0, "cover_s": 0.0, "first_shot_s": 0.0, "first_shot_n": 0,
	}


# --- TDM -----------------------------------------------------------------------------

## Points a kill is worth: 1, plus the wipe bonus when it eliminated the whole squad.
static func tdm_kill_points(wipe: bool) -> int:
	return 1 + (TDM_WIPE_BONUS if wipe else 0)


## 0/1 for a side that has reached the target, else -1.
static func tdm_winner(scores: Array) -> int:
	var a := float(scores[0])
	var b := float(scores[1])
	if a < TDM_POINTS_TO_WIN and b < TDM_POINTS_TO_WIN:
		return -1
	return 0 if a >= b else 1


## Stalemate guard (TDM/KOTH): the higher score wins, a tie goes to `coin` (0 or 1).
static func timeout_winner(scores: Array, coin: int) -> int:
	if float(scores[0]) != float(scores[1]):
		return 0 if float(scores[0]) > float(scores[1]) else 1
	return coin


# --- KOTH ----------------------------------------------------------------------------

## 0/1 = that side alone on the hill, HILL_CONTESTED = both, HILL_EMPTY = nobody.
static func hill_state(on0: int, on1: int) -> int:
	if on0 > 0 and on1 > 0:
		return HILL_CONTESTED
	if on0 > 0:
		return 0
	if on1 > 0:
		return 1
	return HILL_EMPTY


## Hold seconds after `dt`: only the side alone on the point banks time.
static func koth_step(scores: Array, on0: int, on1: int, dt: float) -> Array:
	var out := [float(scores[0]), float(scores[1])]
	var st := hill_state(on0, on1)
	if st == 0 or st == 1:
		out[st] += dt
	return out


static func koth_winner(scores: Array) -> int:
	var a := float(scores[0])
	var b := float(scores[1])
	if a < KOTH_HOLD_TO_WIN_S and b < KOTH_HOLD_TO_WIN_S:
		return -1
	return 0 if a >= b else 1


# --- Sudden death --------------------------------------------------------------------

## Winner of a round that ended: more alive, then more total health, then `coin` (0 or 1).
static func sd_round_winner(alive0: int, alive1: int, hp0: float, hp1: float, coin: int) -> int:
	if alive0 != alive1:
		return 0 if alive0 > alive1 else 1
	if not is_equal_approx(hp0, hp1):
		return 0 if hp0 > hp1 else 1
	return coin


## True when the round is over: a side wiped, or the clock ran out.
static func sd_round_over(alive0: int, alive1: int, clock_s: float) -> bool:
	return alive0 == 0 or alive1 == 0 or clock_s >= ROUND_TIME_LIMIT_S


## True once a side has the rounds or the round cap is reached.
static func sd_game_over(score: Array, round_number: int) -> bool:
	return int(score[0]) >= ROUNDS_TO_WIN or int(score[1]) >= ROUNDS_TO_WIN or round_number >= MAX_ROUNDS


static func sd_game_winner(score: Array) -> int:
	return 0 if int(score[0]) > int(score[1]) else 1


# --- match / box ---------------------------------------------------------------------

## Number of games a side needs, and the winner (-1 while undecided).
static func match_winner(games_won: Array) -> int:
	if int(games_won[0]) >= GAMES_TO_WIN:
		return 0
	if int(games_won[1]) >= GAMES_TO_WIN:
		return 1
	return -1


## Range band of a kill, as the sim names them.
static func band(dist: float) -> StringName:
	if dist < MatchEngine.SHORT_RANGE_MAX:
		return &"short"
	if dist < MatchEngine.MEDIUM_RANGE_MAX:
		return &"medium"
	return &"long"


## Adds `b`'s numeric box fields into a copy of `a` (team/slot come from `a`, or `b` for a soldier only it has).
static func merge_box(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for id in b:
		if not out.has(id):
			out[id] = b[id].duplicate(true)
			continue
		var line: Dictionary = out[id]
		for k in b[id]:
			if k == "team" or k == "slot":
				continue
			line[k] = line.get(k, 0) + b[id][k]
	return out


## MVP soldier id: best MatchResult.impact on the winning side (-1 if there is no winner).
static func pick_mvp(box: Dictionary, winner_index: int) -> int:
	var best := -INF
	var out := -1
	for id in box:
		var line: Dictionary = box[id]
		if line["team"] != winner_index:
			continue
		var score := MatchResult.impact(line)
		if score > best:
			best = score
			out = id
	return out

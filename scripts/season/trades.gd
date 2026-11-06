class_name Trades
extends RefCounted
## Trades between teams: how AI front offices value players and draft picks, the rules a deal
## must pass (window, cap, roster, asset limit), counter-offers, "what would it take?", AI offers
## to the user and AI-to-AI deals. Season owns one instance and passes itself in.
##
## Cap rules (issue #41): a team that ends a trade over the soft cap may take back at most
## SALARY_MATCH (125%) of the salary it sends out, and nobody may end one over the apron. Signing
## bonuses are sunk: they were paid from the old club's fund and never move with the player.
##
## Fair offers (issue #103): CPU offers to the user and AI-to-AI deals are built by _payment() as
## packages that are a fair swap on the open market (neutral_value: no mode, no roster need) within
## FAIR_LOW..FAIR_HIGH on both sides, that each team wants by its own valuation, and that pass
## _guard() (roster limit, lineup not clearly worse, best player not sold for filler). Each team's
## mode shapes what it asks for (_wants) and spends (_give_penalty), and an offer carries a "reason".
## The interest bar stays the AI's willingness; Trades.difficulty() sets how big an edge it needs
## and whether it refuses to overpay (Easy lets the user fleece it).
##
## An asset is a Dictionary: {"soldier": Soldier} or {"pick": true, "year", "round", "orig": Team}.

const DEADLINE_WEEK := 8
const MAX_ASSETS := 3
## The AI accepts when what it gets is worth this much more than what it gives.
const ACCEPT_MARGIN := 1.05
## Below acceptance but at least this share of it, the AI counters instead of refusing.
const COUNTER_FLOOR := 0.85
const PATIENCE := 3
## Fewest players a team can be left with by a trade: in-season, and before Week 1 (offseason
## and preseason camp). There is no maximum: a team over Team.ROSTER_SIZE must cut down before its
## next match (AI teams restructure right away, see restructure()).
const MIN_ROSTER := 8
const MIN_ROSTER_OFFSEASON := 5
const NEXT_YEAR_PICK := 0.85
## Getting several pieces is worth less than one piece of the same total (roster spots, quality).
const DEPTH_WEIGHTS := [1.0, 0.8, 0.65]
const OFFER_CHANCE := 0.35
const BLOCK_OFFER_CHANCE := 0.6
const AI_TRADE_CHANCE := 0.3
const AI_TRADE_CHANCE_OFFSEASON := 0.12
## Salary matching (issue #41): a team that would end a trade over the soft cap may take back at
## most this share of the salary it sends out. Under the cap a team may absorb salary up to it, and
## a player on a minimum deal always fits. Nobody may end a trade over the apron.
const SALARY_MATCH := 1.25
## $K of contract surplus (market value minus salary, summed over up to 3 seasons) worth one point
## of trade value; a team over the soft cap weighs it SURPLUS_OVER_CAP times as much.
const SURPLUS_SCALE := 1200.0
const SURPLUS_OVER_CAP := 1.3
## A fair swap: market value received / given within this band (both sides, so 0.8..1.25).
const FAIR_LOW := 0.8
const FAIR_HIGH := 1.25
## Weights on his projected rating this season and the next four, by front-office mode: a contender
## lives in the present, a rebuilder in the later years.
const PROJ_WEIGHTS := {
	&"contender": [0.35, 0.25, 0.2, 0.12, 0.08],
	&"balanced": [0.25, 0.22, 0.2, 0.18, 0.15],
	&"rebuilding": [0.12, 0.18, 0.22, 0.23, 0.25],
}
## Expected rating lost going from this age to the next (indexed by age, capped at 34).
const DECLINE_PER_YEAR := {29: 0.5, 30: 1.0, 31: 1.8, 32: 2.5, 33: 3.0, 34: 3.5}
## A player who starts for his new team only gets full credit when he improves the lineup by this
## many rating points (summed over slots); a smaller gain counts proportionally, never below BENCH_USE.
const FULL_UPGRADE := 4.0
## An older player replacing a starter must project at least this far above him over three seasons.
const SIDEGRADE_MARGIN := 1.0
## Veterans (30+) on an expiring deal keep this share of their value.
const RENTAL_FACTOR := 0.9
## What a player who wouldn't start for his new team is worth to him: bench depth only. A young
## prospect who is clearly still developing is the exception (he is bought for what he'll become).
const BENCH_USE := 0.35
## Largest lineup drop (average rating per slot) a generated offer may cost the user when it brings
## players back; picks-only offers are exempt.
const OFFER_LINEUP_TOLERANCE := 0.4

## Trade difficulty (Franchise Settings). Easy: the AI accepts less than it gives and has no fairness
## floor, so a lopsided deal can be fleeced. Normal: it wants a 5% edge by its own valuation and
## won't overpay by more than FAIR_LOW in market value. Hard: a 15% edge and a 0.9 floor. Offers the
## AI makes on its own are always fair (FAIR_LOW..FAIR_HIGH on both sides), whatever the setting.
enum Difficulty { EASY, NORMAL, HARD }
const DIFFICULTY_NAMES := {Difficulty.EASY: "Easy", Difficulty.NORMAL: "Normal", Difficulty.HARD: "Hard"}
const DIFFICULTY_MARGIN := {Difficulty.EASY: 0.6, Difficulty.NORMAL: ACCEPT_MARGIN, Difficulty.HARD: 1.15}
const DIFFICULTY_FLOOR := {Difficulty.EASY: 0.0, Difficulty.NORMAL: FAIR_LOW, Difficulty.HARD: 0.9}
const CFG_PATH := "user://settings.cfg"
## Tests and audits pin a difficulty here (-1 = use the saved setting).
static var difficulty_override := -1
static var _difficulty := -1

const CONTENDER := &"contender"
const BALANCED := &"balanced"
const REBUILDING := &"rebuilding"
const MODE_NAMES := {CONTENDER: "Contender", BALANCED: "Middle of the pack", REBUILDING: "Rebuilding"}

## "year:round:abbrev" -> Team that owns the pick (missing = the original team).
var pick_owner := {}
## Team abbrev -> patience pips left this week.
var patience := {}
## Soldier id -> true: players the user put on the trade block.
var block := {}
## Incoming AI offers to the user: {team, give (AI gives), get (AI wants), year, week}.
var offers: Array = []
## Every completed trade: {year, when, a, b, a_gave, b_gave, reactions, ai, fair (a's market-value ratio)}.
var history: Array = []
## Trades completed in the latest weekly tick.
var last_trades: Array = []
## Soldier id -> year he was last traded; the AI won't flip him again that year.
var acquired := {}
## AI roster moves after going over the limit: {year, when, team, soldier, kind (&"cut"/&"traded"), to}.
var moves: Array = []
var _restructuring := false

var _cache_key := ""
var _modes := {}
var _round1 := {}
## key_of -> market value, cleared whenever the valuation cache is.
var _neutral := {}
## While > 0 (inside one offer / AI-trade pass), team abbrev -> payer pool, so each team's assets
## and spending preferences are worked out once instead of per partner.
var _memo_depth := 0
var _pool_memo := {}
## Package searches left in the current AI-to-AI pass.
var _search_budget := 0


# --- difficulty --------------------------------------------------------------------

static func difficulty() -> int:
	if difficulty_override >= 0:
		return difficulty_override
	if _difficulty < 0:
		_difficulty = Difficulty.NORMAL
		var cfg := ConfigFile.new()
		if cfg.load(CFG_PATH) == OK:
			_difficulty = clampi(int(cfg.get_value("gameplay", "trade_difficulty", Difficulty.NORMAL)), 0, Difficulty.HARD)
	return _difficulty


static func set_difficulty(d: int) -> void:
	_difficulty = clampi(d, 0, Difficulty.HARD)
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("gameplay", "trade_difficulty", _difficulty)
	cfg.save(CFG_PATH)


## The edge (received / given by its own valuation) the AI needs before it says yes.
static func accept_margin() -> float:
	return DIFFICULTY_MARGIN[difficulty()]


## Below this market-value ratio (AI received / AI gave) the AI won't accept: it is overpaying.
static func fair_floor() -> float:
	return DIFFICULTY_FLOOR[difficulty()]


## "Fair", "Slightly in your favor"... for the market-value ratio the user receives / gives.
static func fairness_label(r: float) -> String:
	if r >= FAIR_HIGH * 1.2:
		return "Lopsided in your favor"
	if r > FAIR_HIGH:
		return "Slightly in your favor"
	if r > 1.12:
		return "Fair, leaning your way"
	if r >= 1.0 / 1.12:
		return "Fair"
	if r >= FAIR_LOW:
		return "Fair, leaning their way"
	if r >= FAIR_LOW * 0.75:
		return "Slightly in their favor"
	return "Lopsided in their favor"


# --- assets -------------------------------------------------------------------

static func player_asset(s: Soldier) -> Dictionary:
	return {"soldier": s}


static func pick_asset(year: int, rnd: int, orig: Team) -> Dictionary:
	return {"pick": true, "year": year, "round": rnd, "orig": orig}


static func is_pick(a: Dictionary) -> bool:
	return a.has("pick")


static func key_of(a: Dictionary) -> String:
	if is_pick(a):
		return "%d:%d:%s" % [a["year"], a["round"], a["orig"].abbrev]
	return "p%d" % a["soldier"].id


static func contains(list: Array, a: Dictionary) -> bool:
	var k := key_of(a)
	for x in list:
		if key_of(x) == k:
			return true
	return false


static func without(list: Array, a: Dictionary) -> Array:
	var k := key_of(a)
	return list.filter(func(x): return key_of(x) != k)


func owner(year: int, rnd: int, orig: Team) -> Team:
	return pick_owner.get("%d:%d:%s" % [year, rnd, orig.abbrev], orig)


func owner_of(a: Dictionary) -> Team:
	return owner(a["year"], a["round"], a["orig"])


## Pick years that can be traded: this draft and next year's.
static func pick_years(season: Season) -> Array:
	return [season.draft.year, season.draft.year + 1]


func pick_used(season: Season, a: Dictionary) -> bool:
	var d := season.draft
	if a["year"] < d.year:
		return true
	if a["year"] > d.year or not d.is_started():
		return false
	return _draft_index(d, a) < d.next_pick


func _draft_index(d: Draft, a: Dictionary) -> int:
	for i in d.original.size():
		if d.original[i] == a["orig"] and d.round_of(i) == a["round"]:
			return i
	return -1


## Rewrites the set draft order so traded picks go to their new owners.
func apply_owners(season: Season) -> void:
	var d := season.draft
	if not d.is_started():
		return
	for i in d.original.size():
		d.order[i] = owner(d.year, d.round_of(i), d.original[i])


## Full pick order (all rounds) from a round-1 order, with traded picks moved to their owners.
func owned_order(year: int, round1: Array) -> Array:
	var out: Array = []
	var picks := Draft.full_order(round1)
	var n := maxi(1, round1.size())
	for i in picks.size():
		out.append(owner(year, i / n + 1, picks[i]))
	return out


func picks_of(season: Season, team: Team) -> Array:
	var out: Array = []
	for y in pick_years(season):
		for r in range(1, Draft.ROUNDS + 1):
			for orig in season.league.teams:
				var a := pick_asset(y, r, orig)
				if owner_of(a) == team and not pick_used(season, a):
					out.append(a)
	return out


## Players `team` can trade: everyone under contract past this season, except a no-trade clause
## (waived if he has asked out).
static func tradeable(s: Soldier) -> bool:
	return s.contract != null and s.contract.years > 0 and s.retired_year == 0 and (not s.contract.no_trade or s.trade_request)


func assets_of(season: Season, team: Team) -> Array:
	var out: Array = []
	for s in team.roster:
		if tradeable(s):
			out.append(player_asset(s))
	out.append_array(picks_of(season, team))
	return out


## Projected overall pick (0-based) for a pick asset.
func pick_index(season: Season, a: Dictionary) -> int:
	var d := season.draft
	if a["year"] == d.year and d.is_started():
		return maxi(0, _draft_index(d, a))
	_refresh_cache(season)
	var round1: Array = _round1["now"] if a["year"] == d.year else _round1["next"]
	var n := round1.size()
	var pos := maxi(0, round1.find(a["orig"]))
	var rnd: int = a["round"] - 1
	return rnd * n + pos


func pick_text(season: Season, a: Dictionary, with_projection := true) -> String:
	var t := "%d Round %d (%s)" % [a["year"], a["round"], a["orig"].abbrev]
	if not with_projection:
		return t
	var proj := "#%d" % (pick_index(season, a) + 1)
	if a["year"] != season.draft.year or not season.draft.is_started():
		proj = "proj. " + proj
	return "%s  -  %s" % [t, proj]


static func asset_text(season: Season, a: Dictionary) -> String:
	if is_pick(a):
		return "%d R%d pick (%s)" % [a["year"], a["round"], a["orig"].abbrev]
	var s: Soldier = a["soldier"]
	return "%s (%d OVR)" % [s.display_name(), s.best_ovr()]


# --- valuation --------------------------------------------------------------------

func _refresh_cache(season: Season) -> void:
	var key := "%d:%d:%s:%d:%d" % [season.year, season.week, season.offseason_stage, history.size(), season.draft.next_pick]
	if key == _cache_key:
		return
	_cache_key = key
	_neutral = {}
	var teams: Array = season.league.teams.duplicate()
	var score := {}
	var rows := season.standings()
	for r in rows:
		var gp: int = r.wins + r.losses
		var pct := float(r.wins) / gp if gp > 0 and season.phase != Season.PHASE_OFFSEASON else 0.5
		score[r.team] = float(r.team.team_ovr()) + (pct - 0.5) * 16.0
	teams.sort_custom(func(a: Team, b: Team): return score[a] > score[b])
	_modes = {}
	var n := teams.size()
	for i in n:
		_modes[teams[i]] = CONTENDER if i < n * 0.4 else (REBUILDING if i >= n * 0.6 else BALANCED)
	_round1 = {}
	_round1["now"] = season.draft_order()
	var weak_first: Array = season.league.teams.duplicate()
	weak_first.sort_custom(func(a: Team, b: Team): return a.team_ovr() < b.team_ovr())
	_round1["next"] = weak_first


func mode(season: Season, team: Team) -> StringName:
	_refresh_cache(season)
	return _modes.get(team, BALANCED)


## Convex worth of an effective rating: one star is worth more than two average players.
static func curve(ovr: float) -> float:
	return pow(maxf(ovr - 37.0, 0.0) / 10.0, 2.2) * 10.0


## What `s` is worth to `team` (receiving him, or giving him up when `giving`): his rating on the
## convex curve, plus his contract surplus (Contracts.market_value minus salary, up to 3 seasons),
## so an overpaid player is worth less and a cheap productive or rookie deal more.
func player_value(season: Season, s: Soldier, team: Team, giving := false) -> float:
	var m := mode(season, team)
	var over_cap := Contracts.payroll(team, season.cap_year()) > Contracts.SALARY_CAP
	var need_ovr := 0.0
	if not giving and Scheme.best_role(s.stats) == Draft.weakest_role(team):
		need_ovr = 2.0
	var v := _player_base(season, s, m, over_cap, need_ovr)
	if not giving:
		v *= need_factor(season, team, s)
	if giving and on_block(season, team, s):
		v *= 0.8
	return maxf(v, 1.0)


## Rough rating of `s` `years` seasons from now at his best role. Under 28 he closes part of the gap
## to his potential each year (faster when young and with more dev stars); from 29 he declines, a
## little at first and then quickly.
static func projected_ovr(s: Soldier, years: int) -> float:
	var o := float(s.best_ovr())
	var pot := maxf(float(s.potential_ovr()), o)
	var age := s.age
	for i in years:
		if age <= 27 and pot > o:
			var base := 0.45 if age <= 22 else (0.35 if age <= 24 else (0.22 if age <= 26 else 0.1))
			var dev_mult: float = {1: 0.45, 2: 0.75, 3: 1.1, 4: 1.5}.get(clampi(s.dev, 1, 4), 0.75)
			o += (pot - o) * minf(0.7, base * dev_mult)
		elif age >= 29:
			o -= DECLINE_PER_YEAR[mini(age, 34)]
		age += 1
	return o


## Average projected rating over the next `years` seasons (now included).
static func projected_avg(s: Soldier, years: int) -> float:
	var t := 0.0
	for h in years:
		t += projected_ovr(s, h)
	return t / float(maxi(years, 1))


## The part of a player's value that only depends on the front office's mode: projected rating
## (plus a need bump), contract surplus, injury. Neutral market value uses BALANCED and no bump.
func _player_base(season: Season, s: Soldier, m: StringName, over_cap: bool, need_ovr: float) -> float:
	# Worth = his projected rating over the next few seasons (young players grow toward their
	# potential, 29+ decline), weighted by what the front office's mode cares about.
	var w: Array = PROJ_WEIGHTS[m]
	var v := 0.0
	for h in w.size():
		v += float(w[h]) * curve(projected_ovr(s, h) + need_ovr)
	if s.contract != null:
		# Contract surplus year by year: what he'd cost on the market at his projected rating
		# minus what he is paid, so an overpaid decliner is a liability and a cheap riser an asset.
		var scale := float(Contracts.market_value(s)) / maxf(Contracts.curve_salary(float(s.best_ovr())), 1.0)
		var surplus := 0.0
		for h in mini(maxi(s.contract.years, 0), 4):
			surplus += scale * Contracts.curve_salary(projected_ovr(s, h)) - float(s.contract.salary)
		var cap_w := SURPLUS_OVER_CAP if over_cap else 1.0
		v += surplus / SURPLUS_SCALE * cap_w * float({CONTENDER: 0.7, BALANCED: 1.0, REBUILDING: 1.3}[m])
		# A veteran on an expiring deal is a one-season rental: nothing left to re-sign or flip.
		if s.age >= 30 and s.contract.years <= 1:
			v *= RENTAL_FACTOR
	if s.is_injured() and season.phase != Season.PHASE_OFFSEASON:
		v *= maxf(0.5, 1.0 - 0.07 * s.injury_weeks * (1.3 if m == CONTENDER else 1.0))
	return v


## How much `team` actually needs incoming `s` (0.2..1): a starter at his role counts fully, the
## top backup a bit less; behind that, every player ahead who is better now and projects at least
## as high cuts it hard (softer for young A/B prospects, more so for a rebuilder). A player who
## would be the first cut on a full roster is worth almost nothing to them.
func need_factor(season: Season, team: Team, s: Soldier) -> float:
	var role := Scheme.best_role(s.stats)
	var slots := team.scheme.count_role(role)
	var mine := s.ovr_at_role(role)
	var ahead := 0
	var buried_by := 0
	for o in team.roster:
		if o == s or Scheme.best_role(o.stats) != role or o.ovr_at_role(role) <= mine:
			continue
		ahead += 1
		if o.potential_ovr() >= s.potential_ovr():
			buried_by += 1
	var f := 1.0
	if ahead == slots:
		f = 0.85
	elif ahead > slots:
		var units := maxi(1, buried_by - slots + 1)
		var step := 0.3
		if s.age <= 24 and s.dev >= 3:
			step = 0.12 if mode(season, team) == REBUILDING else 0.18
		f = maxf(0.25, 0.85 - step * float(units))
	var full := team.roster.size() >= (Team.ROSTER_SIZE if season.phase != Season.PHASE_OFFSEASON else Team.OFFSEASON_MAX)
	if full:
		var worst := team.least_valuable()
		if worst != null and team.keep_value(s) <= team.keep_value(worst):
			f = minf(f, 0.2)
	return f


func pick_value(season: Season, a: Dictionary, team: Team) -> float:
	return _pick_base(season, a) * float({CONTENDER: 0.8, BALANCED: 1.0, REBUILDING: 1.25}[mode(season, team)])


func _pick_base(season: Season, a: Dictionary) -> float:
	var v := curve(82.0 - 0.32 * pick_index(season, a)) + 8.0
	if a["year"] > season.draft.year:
		v *= NEXT_YEAR_PICK
	return v


func value(season: Season, a: Dictionary, team: Team, giving := false) -> float:
	if _memo_depth == 0:
		return pick_value(season, a, team) if is_pick(a) else player_value(season, a["soldier"], team, giving)
	var k := "%s|%s|%s" % [team.abbrev, key_of(a), giving]
	if not _value_memo.has(k):
		_value_memo[k] = pick_value(season, a, team) if is_pick(a) else player_value(season, a["soldier"], team, giving)
	return _value_memo[k]


## What an asset is worth on the open market: no front office's mode, no roster need, no
## block discount. Fairness is judged on this so it doesn't depend on either team's quirks.
func neutral_value(season: Season, a: Dictionary) -> float:
	_refresh_cache(season)
	var k := key_of(a)
	if _neutral.has(k):
		return _neutral[k]
	var v := _pick_base(season, a) if is_pick(a) else maxf(_player_base(season, a["soldier"], BALANCED, false, 0.0), 1.0)
	_neutral[k] = v
	return v


## Depth-weighted market value of a package (several pieces are worth less than one of the same total).
func neutral_total(season: Season, list: Array) -> float:
	var vals: Array = list.map(func(a): return neutral_value(season, a))
	vals.sort()
	vals.reverse()
	var t := 0.0
	for i in vals.size():
		t += vals[i] * DEPTH_WEIGHTS[mini(i, DEPTH_WEIGHTS.size() - 1)]
	return t


## Market value received / market value given. 1.0 is an even swap; FAIR_LOW..FAIR_HIGH is fair.
## Both sides of a deal are fair or both are not: one side's ratio is the other's inverse (up to
## the depth weights, which each side applies to what it receives).
func fair_ratio(season: Season, receive: Array, give: Array) -> float:
	var given := neutral_total(season, give)
	if given <= 0.0:
		return 9.0 if not receive.is_empty() else 1.0
	return neutral_total(season, receive) / given


## Players a team is shopping: trade requests, the user's block, and a rebuilder's veterans.
func on_block(season: Season, team: Team, s: Soldier) -> bool:
	if s.trade_request:
		return true
	if team.user_controlled:
		return block.has(s.id)
	return mode(season, team) == REBUILDING and s.age >= 30 and s.best_ovr() >= 58


## How `team` sees a deal: value received (depth-weighted) / value given. >= ACCEPT_MARGIN accepts.
func ratio(season: Season, team: Team, receive: Array, give: Array) -> float:
	var got: Array = receive.map(func(a): return value(season, a, team))
	got.sort()
	got.reverse()
	var g := 0.0
	for i in got.size():
		g += got[i] * DEPTH_WEIGHTS[mini(i, DEPTH_WEIGHTS.size() - 1)]
	var l := 0.0
	for a in give:
		l += value(season, a, team, true)
	if l <= 0.0:
		return 9.0 if g > 0.0 else 0.0
	return g / l


## 0..1+ for the interest bar: 1.0 means the AI says yes. The AI also refuses to overpay: when it
## would give up more than FAIR_LOW worth of market value (Hard: 0.9) it stays just short of yes.
func interest(season: Season, ai: Team, user_give: Array, ai_give: Array) -> float:
	var i := ratio(season, ai, user_give, ai_give) / accept_margin()
	if _overpaying(season, ai, user_give, ai_give):
		i = minf(i, 0.97)
	return i


## True when `ai` would be giving up clearly more market value than it gets back.
func _overpaying(season: Season, ai: Team, user_give: Array, ai_give: Array) -> bool:
	return not ai_give.is_empty() and fair_floor() > 0.0 and fair_ratio(season, user_give, ai_give) < fair_floor()


# --- rules --------------------------------------------------------------------------

func window_open(season: Season) -> bool:
	if season.preseason_camp:
		return true
	match season.phase:
		Season.PHASE_REGULAR:
			return season.week <= DEADLINE_WEEK
		Season.PHASE_OFFSEASON:
			return true
	return false


func window_text(season: Season) -> String:
	if window_open(season):
		if season.phase == Season.PHASE_REGULAR and not season.preseason_camp:
			return "OPEN  -  deadline after Week %d" % DEADLINE_WEEK
		return "OPEN"
	return "CLOSED  -  the deadline passed after Week %d; reopens after the Final" % DEADLINE_WEEK


static func _salary(list: Array) -> int:
	var total := 0
	for a in list:
		if not is_pick(a) and a["soldier"].contract != null:
			total += a["soldier"].contract.salary
	return total


static func _players(list: Array) -> int:
	return list.filter(func(a): return not is_pick(a)).size()


## Players in `list` who sit on a main roster (Green Team players don't count against it).
func _main_players(season: Season, list: Array) -> int:
	var n := 0
	for a in list:
		if is_pick(a):
			continue
		var t := season.league.team_of(a["soldier"])
		if t == null or not t.green_team.has(a["soldier"]):
			n += 1
	return n


## Salary that counts for matching: players on more than a minimum deal (a minimum deal always fits).
static func _matched_salary(list: Array) -> int:
	var total := 0
	for a in list:
		if not is_pick(a) and a["soldier"].contract != null and a["soldier"].contract.salary > Contracts.MIN_SALARY:
			total += a["soldier"].contract.salary
	return total


## Salary matching for `team` sending `out_list` and taking back `in_list` (this cap year's
## salaries, like the apron check): {out, in (all incoming salary), matched (incoming minus minimum
## deals), max_in (-1 = no limit: it stays under the soft cap or sheds salary), ok}.
static func salary_match(season: Season, team: Team, out_list: Array, in_list: Array) -> Dictionary:
	var outgoing := _salary(out_list)
	var incoming := _salary(in_list)
	var matched := _matched_salary(in_list)
	var after := Contracts.payroll(team, season.cap_year()) + incoming - outgoing
	var max_in := -1
	if incoming > outgoing and after > Contracts.SALARY_CAP:
		max_in = floori(outgoing * SALARY_MATCH)
	return {"out": outgoing, "in": incoming, "matched": matched, "max_in": max_in, "ok": max_in < 0 or matched <= max_in}


## "" when `team` passes salary matching, otherwise why not.
static func matching_error(season: Season, team: Team, out_list: Array, in_list: Array) -> String:
	var m := salary_match(season, team, out_list, in_list)
	if m["ok"]:
		return ""
	var over := Contracts.payroll(team, season.cap_year()) > Contracts.SALARY_CAP
	var who := "%s %s" % [team.name, "is over the cap" if over else "would end up over the cap"]
	if m["out"] == 0:
		return "%s and must send salary back to take any on (up to %d%% of what it sends out)." % [who, roundi(SALARY_MATCH * 100.0)]
	return "%s and can take back at most %s (%d%% of %s sent out)." % [who, Contracts.money(m["max_in"]),
		roundi(SALARY_MATCH * 100.0), Contracts.money(m["out"])]


static func min_roster(season: Season) -> int:
	return MIN_ROSTER_OFFSEASON if season.phase == Season.PHASE_OFFSEASON or season.preseason_camp else MIN_ROSTER


## "" when the deal is legal, otherwise why not. Rosters may go over the limit (cut before the
## next match); they may not drop below min_roster(). Salary matching (SALARY_MATCH) is skipped for
## `unmatched` while the AI is still building that team's side of a package.
func validate(season: Season, a: Team, a_give: Array, b: Team, b_give: Array, unmatched: Team = null) -> String:
	if not window_open(season):
		return "The trade window is closed."
	if a_give.is_empty() and b_give.is_empty():
		return "Add players or picks to both sides."
	if a_give.size() > MAX_ASSETS or b_give.size() > MAX_ASSETS:
		return "At most %d assets per side." % MAX_ASSETS
	for side in [[a, a_give], [b, b_give]]:
		var t: Team = side[0]
		for x in side[1]:
			if is_pick(x):
				if owner_of(x) != t or pick_used(season, x):
					return "%s doesn't own the %s." % [t.abbrev, asset_text(season, x)]
			else:
				var s: Soldier = x["soldier"]
				if not t.has_player(s):
					return "%s is no longer on %s." % [s.display_name(), t.name]
				if not tradeable(s):
					if s.contract != null and s.contract.no_trade and s.contract.years > 0:
						return "%s has a no-trade clause." % s.display_name()
					return "%s's contract is expiring; he can't be traded." % s.display_name()
	var cy := season.cap_year()
	var floor_n := min_roster(season)
	for side in [[a, a_give, b_give], [b, b_give, a_give]]:
		var t: Team = side[0]
		# Green Team players keep their Green Team status in a trade, so they don't move the roster count.
		var n_out := _main_players(season, side[1])
		var n_in := _main_players(season, side[2])
		var after: int = t.roster.size() - n_out + n_in
		if after < floor_n and n_out > n_in:
			return "%s would be left with only %d players (min %d)." % [t.name, after, floor_n]
		var incoming := _salary(side[2])
		var outgoing := _salary(side[1])
		var payroll := Contracts.payroll(t, cy) + incoming - outgoing
		if incoming > outgoing and payroll > Contracts.APRON:
			return "%s would be %s over the apron." % [t.name, Contracts.money(payroll - Contracts.APRON)]
		if incoming > outgoing and payroll > Contracts.TAX_LINE and season.revenue.frozen(t):
			return "%s's board has frozen spending (club fund below $0): the trade would put them %s over the tax line." % [
				t.name, Contracts.money(payroll - Contracts.TAX_LINE)]
		if t != unmatched:
			var merr := matching_error(season, t, side[1], side[2])
			if merr != "":
				return merr
	return ""


# --- user <-> AI ------------------------------------------------------------------

func patience_of(team: Team) -> int:
	return int(patience.get(team.abbrev, PATIENCE))


## The AI's one-liner about the current package.
func quote(season: Season, ai: Team, user_give: Array, ai_give: Array) -> String:
	if user_give.is_empty() and ai_give.is_empty():
		return "Let's hear it. What are you thinking?"
	if ai_give.is_empty():
		return "Tell us what you want back."
	if _overpaying(season, ai, user_give, ai_give) and ratio(season, ai, user_give, ai_give) >= accept_margin():
		return "That's more than we can give up for what you're offering. Even it out."
	var i := interest(season, ai, user_give, ai_give)
	if i >= 1.15:
		return "You're being generous. We'd sign that today."
	if i >= 1.0:
		return "That works for us."
	if i >= COUNTER_FLOOR:
		return "We're close. Sweeten it a little and we have a deal."
	var m := mode(season, ai)
	var young := user_give.any(func(a): return is_pick(a) or a["soldier"].age <= 25)
	if m == REBUILDING and not young:
		return "We're rebuilding. Picks and young talent move the needle for us."
	if m == CONTENDER and not user_give.any(func(a): return not is_pick(a) and FreeAgency.would_start(ai, a["soldier"])):
		return "We're trying to win now. We need someone who can start."
	if i < 0.5:
		return "That's not even close."
	return "You're asking for a lot more than you're giving."


## Proposes a deal to `ai`. Returns {result: accepted|counter|rejected|error, text, give, get}.
## A counter's give/get is the AI's version; accept it with execute().
func propose(season: Season, ai: Team, user_give: Array, ai_give: Array) -> Dictionary:
	var user := season.user_team()
	if patience_of(ai) <= 0:
		return {"result": "rejected", "text": "%s won't take your calls again until next week." % ai.name}
	var err := validate(season, user, user_give, ai, ai_give)
	if err != "":
		return {"result": "error", "text": err}
	var i := interest(season, ai, user_give, ai_give)
	if i >= 1.0:
		execute(season, user, user_give, ai, ai_give)
		return {"result": "accepted", "text": "%s accepted the trade." % ai.name}
	if i >= COUNTER_FLOOR:
		var c := counter(season, ai, user_give, ai_give)
		if not c.is_empty():
			c["result"] = "counter"
			c["text"] = "%s counters." % ai.name
			return c
	patience[ai.abbrev] = patience_of(ai) - 1
	return {"result": "rejected", "text": "%s turned it down. \"%s\"" % [ai.name, quote(season, ai, user_give, ai_give)]}


## The AI's counter: ask for one more of the user's assets, or hold back one of its own.
func counter(season: Season, ai: Team, user_give: Array, ai_give: Array) -> Dictionary:
	var user := season.user_team()
	if user_give.size() < MAX_ASSETS:
		var pool := _sorted_pool(season, user, user_give, ai)
		for x in pool:
			var g: Array = user_give + [x]
			if interest(season, ai, g, ai_give) >= 1.0 and validate(season, user, g, ai, ai_give) == "":
				return {"give": g, "get": ai_give}
	if ai_give.size() > 1:
		var mine := ai_give.duplicate()
		mine.sort_custom(func(p, q): return value(season, p, ai, true) < value(season, q, ai, true))
		for x in mine:
			var keep := without(ai_give, x)
			if interest(season, ai, user_give, keep) >= 1.0 and validate(season, user, user_give, ai, keep) == "":
				return {"give": user_give, "get": keep}
	return {}


## User assets not already offered, cheapest (to `ai`) first.
func _sorted_pool(season: Season, user: Team, offered: Array, ai: Team) -> Array:
	var pool: Array = assets_of(season, user).filter(func(x): return not contains(offered, x))
	var vals := {}
	for x in pool:
		vals[key_of(x)] = value(season, x, ai)
	pool.sort_custom(func(p, q): return vals[key_of(p)] < vals[key_of(q)])
	return pool


## The cheapest additions to the user's side that make `ai` say yes, or [] if nothing works.
func what_would_it_take(season: Season, ai: Team, user_give: Array, ai_give: Array) -> Array:
	var user := season.user_team()
	var cur := user_give.duplicate()
	if ai_give.is_empty():
		return []
	while true:
		if interest(season, ai, cur, ai_give) >= 1.0 and validate(season, user, cur, ai, ai_give) == "":
			return cur
		if cur.size() >= MAX_ASSETS:
			return []
		var pool := _sorted_pool(season, user, cur, ai)
		var best: Dictionary = {}
		for x in pool:
			var g: Array = cur + [x]
			# The user's own salary matching may still be short: another piece can fix it.
			if validate(season, user, g, ai, ai_give, user) != "":
				continue
			if interest(season, ai, g, ai_give) >= 1.0 and validate(season, user, g, ai, ai_give) == "":
				return g
			best = x
		if best.is_empty():
			return []
		cur.append(best)
	return []


# --- execution -------------------------------------------------------------------

## Moves every asset and records the trade. Returns the log entry.
func execute(season: Season, a: Team, a_give: Array, b: Team, b_give: Array) -> Dictionary:
	var reactions: Array = []
	var fair := fair_ratio(season, b_give, a_give)
	for x in a_give:
		var r := _move(season, x, a, b)
		if not r.is_empty():
			reactions.append(r)
	for x in b_give:
		var r := _move(season, x, b, a)
		if not r.is_empty():
			reactions.append(r)
	for t: Team in [a, b]:
		if t.user_controlled:
			t.fill_injured()
		elif t.roster.size() >= t.scheme.slot_ids().size():
			t.auto_lineup()
	apply_owners(season)
	var when := _when(season)
	var e := {"year": season.year, "when": when, "a": a, "b": b, "a_gave": a_give.map(func(x): return asset_text(season, x)),
		"b_gave": b_give.map(func(x): return asset_text(season, x)), "reactions": reactions, "ai": not (a.user_controlled or b.user_controlled), "fair": fair}
	history.append(e)
	last_trades.append(e)
	season.rivalries.note_trade(a, b)
	var moved := {}
	for x in a_give + b_give:
		moved[key_of(x)] = true
	offers = offers.filter(func(o): return not (o["give"] + o["get"]).any(func(x): return moved.has(key_of(x))))
	_cache_key = ""
	for t: Team in [a, b]:
		if not t.user_controlled and t.is_over_roster_limit():
			restructure(season, t)
	return e


static func _when(season: Season) -> String:
	return season.step_label() if season.phase == Season.PHASE_OFFSEASON else ("Preseason" if season.preseason_camp else season.week_label(season.week))


# --- AI roster restructuring ---------------------------------------------------------

## An AI team over `limit` (default Team.ROSTER_SIZE) gets back under it: it first shops its
## least valuable players (Team.keep_value: OVR, upside, age, depth, dead money, contract) to AI
## teams with roster room for a draft pick, and cuts whoever nobody wants. Returns
## {traded: [Soldier], cut: [Soldier]}. A dump must pass the buyer's salary matching, so it goes to
## a team with cap room (or is a minimum deal).
func restructure(season: Season, team: Team, limit := Team.ROSTER_SIZE) -> Dictionary:
	var out := {"traded": [], "cut": []}
	if team.user_controlled or _restructuring:
		return out
	_restructuring = true
	while team.roster.size() > limit:
		var order: Array = team.roster.duplicate()
		var kv := {}
		for s in order:
			kv[s] = team.keep_value(s)
		order.sort_custom(func(p: Soldier, q: Soldier): return kv[p] < kv[q])
		var dealt := false
		if window_open(season):
			for s: Soldier in order.slice(0, 3):
				if not tradeable(s) or _fresh(season, s):
					continue
				var deal := _dump_deal(season, team, s)
				if deal.is_empty():
					continue
				execute(season, team, [player_asset(s)], deal["buyer"], [deal["pick"]])
				out["traded"].append(s)
				moves.append({"year": season.year, "when": _when(season), "team": team, "soldier": s, "kind": &"traded", "to": deal["buyer"]})
				dealt = true
				break
		if not dealt:
			var s: Soldier = order[0]
			season.release_player(team, s)
			out["cut"].append(s)
			moves.append({"year": season.year, "when": _when(season), "team": team, "soldier": s, "kind": &"cut", "to": null})
	if team.roster.size() >= team.scheme.slot_ids().size():
		team.auto_lineup()
	_restructuring = false
	_cache_key = ""
	return out


## The best pick (to `seller`) an AI team with roster room will give for `s`: {buyer, pick} or {}.
func _dump_deal(season: Season, seller: Team, s: Soldier) -> Dictionary:
	var want := [player_asset(s)]
	var best := {}
	var best_v := 0.0
	for buyer: Team in season.league.teams:
		if buyer == seller or buyer.user_controlled or buyer.roster.size() >= Team.ROSTER_SIZE:
			continue
		var picks := picks_of(season, buyer)
		var cost := {}
		for p in picks:
			cost[key_of(p)] = value(season, p, buyer, true)
		picks.sort_custom(func(p, q): return cost[key_of(p)] < cost[key_of(q)])
		for p in picks:
			if ratio(season, buyer, want, [p]) < ACCEPT_MARGIN:
				break
			if validate(season, buyer, [p], seller, want) != "":
				continue
			var v := value(season, p, seller)
			if v > best_v:
				best_v = v
				best = {"buyer": buyer, "pick": p}
	return best


func moves_in(year: int) -> Array:
	return moves.filter(func(m): return m["year"] == year)


func _move(season: Season, x: Dictionary, from: Team, to: Team) -> Dictionary:
	if is_pick(x):
		pick_owner[key_of(x)] = to
		return {}
	var s: Soldier = x["soldier"]
	var d := s.get_dna()
	var delta := -14.0 * d.n(&"loyalty")
	var asked := s.trade_request
	if asked:
		delta += 12.0
	delta += clampf((to.team_ovr() - from.team_ovr()) / 4.0, -1.0, 1.0) * 5.0 * d.n(&"winning")
	season.break_keep_promises(from, s)
	var was_green := from.green_team.has(s)
	from.release(s)
	if was_green:
		to.green_team.append(s)
	else:
		to.roster.append(s)
	s.add_morale(delta)
	s.trust = Soldier.TRUST_NEUTRAL
	s.trade_request = false
	block.erase(s.id)
	acquired[s.id] = season.year
	season.negotiations.erase(s.id)
	var mood := "relieved" if asked else ("upset" if d.loyalty >= 65 else ("thrilled" if delta >= 3.0 else ""))
	return {"soldier": s, "from": from, "to": to, "morale": delta, "mood": mood}


# --- weekly AI activity -----------------------------------------------------------

## Once per week (and each offseason step): patience recovers, old offers expire, the AI
## occasionally trades among itself and sends the user an offer.
func weekly(season: Season, rng: RandomNumberGenerator) -> void:
	last_trades = []
	for t in season.league.teams:
		patience[t.abbrev] = mini(PATIENCE, patience_of(t) + 1)
	offers.clear()
	if not window_open(season):
		return
	if rng.randf() < (AI_TRADE_CHANCE_OFFSEASON if season.phase == Season.PHASE_OFFSEASON else AI_TRADE_CHANCE):
		ai_to_ai(season, rng)
	var chance := BLOCK_OFFER_CHANCE if _user_block(season).size() > 0 else OFFER_CHANCE
	if rng.randf() < chance:
		offer_to_user(season, rng)


func _user_block(season: Season) -> Array:
	var user := season.user_team()
	return user.roster.filter(func(s: Soldier): return tradeable(s) and on_block(season, user, s))


## How much `team` would rather keep `a` (0 = happy to give it, higher = reluctant): a contender
## spends picks and prospects before starters, a rebuilder moves veterans before young players or
## picks, a middling team gives depth first.
func _give_penalty(season: Season, team: Team, a: Dictionary) -> float:
	var m := mode(season, team)
	if is_pick(a):
		return {CONTENDER: 0.0, BALANCED: 0.1, REBUILDING: 0.4}[m]
	var s: Soldier = a["soldier"]
	var starter := _starters_of(team).has(s)
	match m:
		CONTENDER:
			return 0.6 if starter else (0.05 if s.age <= 24 else 0.12)
		REBUILDING:
			if s.age >= 28:
				return 0.0 if not starter else 0.05
			return 0.7 if starter else 0.2
	return 0.4 if starter else 0.0


var _starters_memo := {}
var _ovr_memo := {}
var _strength_memo := {}
var _value_memo := {}


## Rating of `s` at `role`, remembered for the length of a pass.
func _ovr_at(s: Soldier, role: int) -> int:
	if _memo_depth == 0:
		return s.ovr_at_role(role)
	var k := s.id * 4 + role
	if not _ovr_memo.has(k):
		_ovr_memo[k] = s.ovr_at_role(role)
	return _ovr_memo[k]


func _strength_now(team: Team) -> float:
	if _memo_depth == 0:
		return _lineup_strength(team, team.roster)
	if not _strength_memo.has(team.abbrev):
		_strength_memo[team.abbrev] = _lineup_strength(team, team.roster)
	return _strength_memo[team.abbrev]


func _starters_of(team: Team) -> Array:
	if _memo_depth > 0:
		if not _starters_memo.has(team.abbrev):
			_starters_memo[team.abbrev] = team.starters()
		return _starters_memo[team.abbrev]
	return team.starters()


func _begin_pass() -> void:
	_memo_depth += 1
	if _memo_depth == 1:
		_pool_memo = {}
		_starters_memo = {}
		_ovr_memo = {}
		_strength_memo = {}
		_value_memo = {}


func _end_pass() -> void:
	_memo_depth = maxi(0, _memo_depth - 1)
	if _memo_depth == 0:
		_pool_memo = {}
		_starters_memo = {}
		_ovr_memo = {}
		_strength_memo = {}
		_value_memo = {}


## Whether `team` would go looking for `s` given its mode: a real need first (a starter or the top
## backup at his role), then a contender wants someone who starts now, a rebuilder youth.
func _wants(season: Season, team: Team, s: Soldier) -> bool:
	if need_factor(season, team, s) < 0.85:
		return false
	match mode(season, team):
		CONTENDER:
			return s.age <= 33 and FreeAgency.would_start(team, s)
		REBUILDING:
			return s.age <= 26 and s.potential_ovr() >= 55
	return true


## Average rating across `team`'s lineup slots if `players` were its roster (greedy best fit per slot).
func _lineup_strength(team: Team, players: Array) -> float:
	return _lineup_pick(team, players)["strength"]


## Greedy best fit of `players` into `team`'s lineup slots: {strength: average rating, used: {Soldier: true}}.
func _lineup_pick(team: Team, players: Array) -> Dictionary:
	var used := {}
	var total := 0.0
	var slots := team.scheme.slot_ids()
	for slot_id in slots:
		var role: int = team.scheme.role_for_slot(slot_id)
		var best: Soldier = null
		var best_o := -1
		for p: Soldier in players:
			if used.has(p):
				continue
			var o := _ovr_at(p, role)
			if o > best_o:
				best_o = o
				best = p
		if best != null:
			used[best] = true
			total += best_o
	return {"strength": total / maxf(1.0, float(slots.size())), "used": used}


static func _soldiers(list: Array) -> Array:
	return list.filter(func(a): return not is_pick(a)).map(func(a): return a["soldier"])


func _roster_after(team: Team, out_list: Array, in_list: Array) -> Array:
	var outp := _soldiers(out_list)
	return team.roster.filter(func(x: Soldier): return not outp.has(x)) + _soldiers(in_list)


## How `team`'s lineup changes (average rating per slot) if it gives `out_list` and takes `in_list`.
## Negative: the deal weakens its starting lineup.
func lineup_change(team: Team, out_list: Array, in_list: Array) -> float:
	return _lineup_strength(team, _roster_after(team, out_list, in_list)) - _strength_now(team)


## True when an incoming player would take the lineup spot of one of `team`'s current starters (whether
## he stays on the roster or is the one traded away) without clearly beating him over the next three
## seasons: a bigger rating now doesn't make up for an older or lower-potential player (a short-term
## bump that costs the future).
func sidegrade(team: Team, out_list: Array, in_list: Array) -> bool:
	var inp := _soldiers(in_list)
	if inp.is_empty():
		return false
	var before: Dictionary = _lineup_pick(team, team.roster)["used"]
	var outp := _soldiers(out_list)
	var after: Dictionary = _lineup_pick(team, _roster_after(team, out_list, in_list))["used"]
	for d: Soldier in before:
		if after.has(d):
			continue
		var best_gain := -999.0
		var replaced := false
		for p: Soldier in inp:
			if after.has(p):
				replaced = true
				best_gain = maxf(best_gain, projected_avg(p, 3) - projected_avg(d, 3))
		# A starter who is traded away only counts when an incoming player takes his place (a straight
		# swap); one pushed out while staying on the roster is always compared.
		if not replaced and outp.has(d):
			continue
		if best_gain < SIDEGRADE_MARGIN:
			return true
	return false


## What the incoming `in_list` is worth to `team` after the deal, rather than on the open market:
## each player counts in full if he'd be in the lineup (or is a developing prospect), otherwise only
## as bench depth. Depth-weighted like neutral_total. Picks count in full.
func useful_total(season: Season, team: Team, out_list: Array, in_list: Array) -> float:
	var after := _roster_after(team, out_list, in_list)
	var pick := _lineup_pick(team, after)
	var used: Dictionary = pick["used"]
	var slots := float(maxi(1, team.scheme.slot_ids().size()))
	var vals: Array = []
	for a in in_list:
		var v := neutral_value(season, a)
		if not is_pick(a):
			var s: Soldier = a["soldier"]
			var prospect := s.age <= 24 and s.potential_ovr() >= s.best_ovr() + 4
			if used.has(s):
				# Credit in proportion to how much he lifts the lineup (rating points over the slots).
				var gain: float = (float(pick["strength"]) - _lineup_strength(team, after.filter(func(x): return x != s))) * slots
				v *= clampf(BENCH_USE + (1.0 - BENCH_USE) * gain / FULL_UPGRADE, BENCH_USE, 1.0)
			elif not prospect:
				v *= BENCH_USE
		vals.append(v)
	vals.sort()
	vals.reverse()
	var t := 0.0
	for i in vals.size():
		t += vals[i] * DEPTH_WEIGHTS[mini(i, DEPTH_WEIGHTS.size() - 1)]
	return t


## Usable value `team` gets (in_list) over the market value it gives up (out_list). Unlike
## fair_ratio this punishes a package of players who would just sit on the bench.
func useful_ratio(season: Season, team: Team, in_list: Array, out_list: Array) -> float:
	var given := neutral_total(season, out_list)
	if given <= 0.0:
		return 9.0 if not in_list.is_empty() else 1.0
	return useful_total(season, team, out_list, in_list) / given


## "" when `team` can sensibly make this trade, else why not: the roster stays within its limit
## (nobody is forced to cut), and for an AI team the lineup doesn't get clearly worse and its best
## player isn't traded for filler. For the user (offers made to them) the players coming back must
## be usable and not weaken the lineup much; deals the user builds themselves are only warned about.
func _guard(season: Season, team: Team, out_list: Array, in_list: Array) -> String:
	var outp := _soldiers(out_list)
	var inp := _soldiers(in_list)
	var limit := Team.OFFSEASON_MAX if season.phase == Season.PHASE_OFFSEASON else Team.ROSTER_SIZE
	var after := team.roster.size() - outp.size() + inp.size()
	if after > limit and inp.size() > outp.size():
		return "%s would be over the roster limit." % team.name
	if team.user_controlled:
		# Offers to the user must be worth having: players coming back have to help the lineup (or
		# be real prospects), not just fill the bench. Picks-only offers skip the lineup check.
		if not inp.is_empty():
			if useful_ratio(season, team, in_list, out_list) < FAIR_LOW:
				return "%s would mostly get bench players back." % team.name
			if lineup_change(team, out_list, in_list) < -OFFER_LINEUP_TOLERANCE:
				return "%s would weaken its lineup." % team.name
			if sidegrade(team, out_list, in_list):
				return "%s would swap a starter for an older player with a worse outlook." % team.name
		return ""
	if outp.is_empty():
		return ""
	var m := mode(season, team)
	var top: Soldier = team.roster[0]
	for x in team.roster:
		if x.best_ovr() > top.best_ovr():
			top = x
	if outp.has(top) and not (m == REBUILDING and top.age >= 28):
		if not inp.any(func(x: Soldier): return x.best_ovr() >= top.best_ovr() - 3):
			return "%s won't trade its best player for filler." % team.name
	var roster_after: Array = team.roster.filter(func(x: Soldier): return not outp.has(x)) + inp
	var tol: float = {CONTENDER: 0.5, BALANCED: 1.5, REBUILDING: 3.0}[m]
	if _lineup_strength(team, roster_after) < _strength_now(team) - tol:
		return "%s would weaken its lineup." % team.name
	return ""


## `payer`'s assets as [asset, market value, give penalty], skipping players acquired this year.
func _payer_pool(season: Season, payer: Team) -> Array:
	if _memo_depth > 0 and _pool_memo.has(payer.abbrev):
		return _pool_memo[payer.abbrev]
	var out: Array = []
	for x in assets_of(season, payer):
		if not is_pick(x) and _fresh(season, x["soldier"]):
			continue
		out.append([x, neutral_value(season, x), _give_penalty(season, payer, x)])
	if _memo_depth > 0:
		_pool_memo[payer.abbrev] = out
	return out


## Builds `payer`'s side for `target` (which `other` gives): up to MAX_ASSETS of payer's assets such
## that the deal is a fair swap on the market (FAIR_LOW..FAIR_HIGH, both ways), payer still comes out
## ahead by its own valuation (and `other` too when it is an AI team), both rosters are fine, and the
## deal is legal. Of the packages that qualify, the closest to even that leans on what payer's mode
## likes to spend wins. Returns [] if there is none.
func _payment(season: Season, payer: Team, other: Team, target: Array, other_gives: Array) -> Array:
	var n_target := neutral_total(season, target)
	if n_target <= 0.0:
		return []
	if _memo_depth > 0:
		if _search_budget <= 0:
			return []
		_search_budget -= 1
	var nv := {}
	for x in target:
		nv[key_of(x)] = neutral_value(season, x)
	var pen := {}
	var players: Array = []
	var picks: Array = []
	for e in _payer_pool(season, payer):
		var v: float = e[1]
		if v > n_target * FAIR_HIGH:
			continue
		var k := key_of(e[0])
		nv[k] = v
		pen[k] = e[2]
		(picks if is_pick(e[0]) else players).append(e[0])
	players.sort_custom(func(p, q):
		var a: float = pen[key_of(p)]
		var b: float = pen[key_of(q)]
		return a < b or (a == b and nv[key_of(p)] > nv[key_of(q)]))
	picks.sort_custom(func(p, q): return nv[key_of(p)] > nv[key_of(q)])
	var pool: Array = players.slice(0, 7) + picks.slice(0, 5)
	var margin := maxf(ACCEPT_MARGIN, accept_margin())
	var n := pool.size()
	var pv: Array = pool.map(func(x): return nv[key_of(x)])
	var pp: Array = pool.map(func(x): return pen[key_of(x)])
	# Cheap pass: every combination in the fair band, scored by closeness to even plus how much the
	# payer's mode likes spending those assets. The expensive checks run best-first until one passes.
	var cands: Array = []
	for i in n:
		_add_combo([i], pv, pp, n_target, cands)
		for j in range(i + 1, n):
			_add_combo([i, j], pv, pp, n_target, cands)
			for k in range(j + 1, n):
				_add_combo([i, j, k], pv, pp, n_target, cands)
	cands.sort_custom(func(p, q): return p[0] < q[0])
	for c in cands:
		var combo: Array = c[1].map(func(x): return pool[x])
		if _guard(season, payer, combo, target) != "" or _guard(season, other, target, combo) != "":
			continue
		if ratio(season, payer, target, combo) < margin:
			continue
		if not other.user_controlled and ratio(season, other, combo, target) < 1.0:
			continue
		if validate(season, payer, combo, other, target) != "":
			continue
		return combo
	return []


## Adds `idx` (indexes into a payment pool) to `cands` as [score, idx] when its market value is
## within the fair band of `n_target` both ways. Lower scores are closer to even and cheaper to spend.
func _add_combo(idx: Array, pv: Array, pp: Array, n_target: float, cands: Array) -> void:
	var vals: Array = []
	var pen_sum := 0.0
	for x in idx:
		vals.append(pv[x])
		pen_sum += pp[x]
	vals.sort()
	var total := 0.0
	for q in vals.size():
		total += vals[vals.size() - 1 - q] * DEPTH_WEIGHTS[mini(q, DEPTH_WEIGHTS.size() - 1)]
	var r := total / n_target
	if r < FAIR_LOW or r > FAIR_HIGH or 1.0 / r < FAIR_LOW or 1.0 / r > FAIR_HIGH:
		return
	cands.append([absf(log(r)) + pen_sum / idx.size() + 0.03 * idx.size(), idx])


## Why `ai` wants `s` and how it is paying, for the offer card.
func _reason(season: Season, ai: Team, s: Soldier, pay: Array) -> String:
	var role := Scheme.best_role(s.stats)
	var rname := String(Scheme.ROLE_NAMES[role])
	var floor_ovr := 999
	for slot_id in ai.scheme.slot_ids():
		if ai.scheme.role_for_slot(slot_id) == role:
			var cur: Soldier = ai.lineup.get(slot_id)
			floor_ovr = mini(floor_ovr, 0 if cur == null else cur.ovr_at_role(role))
	var why := ""
	match mode(season, ai):
		CONTENDER:
			why = "Contender: %s (%d OVR) would start at %s" % [s.display_name(), s.ovr_at_role(role), rname]
			if floor_ovr < 999 and floor_ovr > 0:
				why += " (+%d over their current starter)" % maxi(0, s.ovr_at_role(role) - floor_ovr)
			why += "."
		REBUILDING:
			why = "Rebuilding: they want %s (age %d, %d OVR, %d potential) for the long run." % [s.display_name(), s.age, s.best_ovr(), s.potential_ovr()]
		_:
			why = "Needs %s depth: %s (%d OVR) would be a top option for them." % [rname, s.display_name(), s.ovr_at_role(role)]
	var picks := pay.filter(func(a): return is_pick(a)).size()
	var how := "players they can spare"
	if picks == pay.size():
		how = "draft picks"
	elif picks > 0:
		how = "players and picks"
	return "%s They're paying with %s." % [why, how]


## An AI team makes the user an offer for one of his players (block players first): a player it
## actually needs, paid for with a fair package built from what its mode spends.
func offer_to_user(season: Season, rng: RandomNumberGenerator) -> bool:
	_begin_pass()
	_search_budget = 40
	var made := _offer_to_user(season, rng)
	_end_pass()
	return made


func _offer_to_user(season: Season, rng: RandomNumberGenerator) -> bool:
	var user := season.user_team()
	var targets := _user_block(season)
	if targets.is_empty():
		targets = user.roster.filter(func(s: Soldier): return tradeable(s) and s.best_ovr() >= 53)
	if targets.is_empty():
		return false
	var ais: Array = season.league.teams.filter(func(t: Team): return not t.user_controlled and patience_of(t) > 0)
	_shuffle(ais, rng)
	for ai: Team in ais:
		var ranked: Array = targets.filter(func(p: Soldier): return _wants(season, ai, p))
		if ranked.is_empty():
			continue
		ranked.sort_custom(func(p: Soldier, q: Soldier): return player_value(season, p, ai) > player_value(season, q, ai))
		var n := mini(3, ranked.size())
		var first := rng.randi() % n
		for k in n:
			var target: Soldier = ranked[(first + k) % n]
			var want := [player_asset(target)]
			var pay := _payment(season, ai, user, want, want)
			if pay.is_empty():
				continue
			offers.append({"team": ai, "give": pay, "get": want, "year": season.year, "week": season.week,
				"reason": _reason(season, ai, target, pay), "fair": fair_ratio(season, pay, want),
					"useful": useful_ratio(season, user, pay, want), "lineup": lineup_change(user, want, pay)})
			return true
	return false


## User accepts offer `o`. Returns "" or the reason it can't go through any more.
func accept_offer(season: Season, o: Dictionary) -> String:
	var err := validate(season, season.user_team(), o["get"], o["team"], o["give"])
	if err != "":
		offers.erase(o)
		return err
	execute(season, season.user_team(), o["get"], o["team"], o["give"])
	offers.erase(o)
	return ""


## Two AI teams swap: one shops a player (block players first), a buyer that needs him pays with a
## fair package. Both sides come out ahead by their own valuation and within the market-fair band.
func ai_to_ai(season: Season, rng: RandomNumberGenerator) -> bool:
	_begin_pass()
	_search_budget = 24
	var made := _ai_to_ai(season, rng)
	_end_pass()
	return made


func _ai_to_ai(season: Season, rng: RandomNumberGenerator) -> bool:
	var ais: Array = season.league.teams.filter(func(t: Team): return not t.user_controlled)
	_shuffle(ais, rng)
	for seller: Team in ais:
		var shop: Array = seller.roster.filter(func(s: Soldier): return tradeable(s) and on_block(season, seller, s) and not _fresh(season, s))
		if shop.is_empty():
			var bench: Array = seller.bench().filter(func(s: Soldier): return tradeable(s) and s.best_ovr() >= 51 and not _fresh(season, s))
			if bench.is_empty():
				continue
			shop = [bench[rng.randi() % bench.size()]]
		var target: Soldier = shop[rng.randi() % shop.size()]
		var want := [player_asset(target)]
		for buyer: Team in ais:
			if buyer == seller or not _wants(season, buyer, target):
				continue
			var pay := _payment(season, buyer, seller, want, want)
			if pay.is_empty():
				continue
			execute(season, seller, want, buyer, pay)
			return true
	return false


func _fresh(season: Season, s: Soldier) -> bool:
	return int(acquired.get(s.id, -1)) == season.year


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


## A new season: forget past years' pick records and stale offers.
func new_season(season: Season) -> void:
	offers.clear()
	last_trades = []
	for k in pick_owner.keys():
		if int(String(k).get_slice(":", 0)) < season.year:
			pick_owner.erase(k)
	_cache_key = ""

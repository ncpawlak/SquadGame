class_name Trades
extends RefCounted
## Trades between teams: how AI front offices value players and draft picks, the rules a deal
## must pass (window, cap, roster, asset limit), counter-offers, "what would it take?", AI offers
## to the user and AI-to-AI deals. Season owns one instance and passes itself in.
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
## Every completed trade: {year, when, a, b, a_gave, b_gave, reactions, ai}.
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


## Players `team` can trade: everyone under contract past this season.
static func tradeable(s: Soldier) -> bool:
	return s.contract != null and s.contract.years > 0 and s.retired_year == 0


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


## What `s` is worth to `team` (receiving him, or giving him up when `giving`).
func player_value(season: Season, s: Soldier, team: Team, giving := false) -> float:
	var m := mode(season, team)
	var ovr := float(s.best_ovr())
	if not giving and Scheme.best_role(s.stats) == Draft.weakest_role(team):
		ovr += 2.0
	var fut_w: float = clampf((28.0 - s.age) / 8.0, 0.0, 1.0) * {CONTENDER: 0.3, BALANCED: 0.45, REBUILDING: 0.65}[m]
	var eff := ovr + float(s.potential_ovr() - s.best_ovr()) * fut_w
	if s.age >= 30:
		eff -= float(s.age - 29) * float({CONTENDER: 0.4, BALANCED: 0.8, REBUILDING: 1.4}[m])
	var v := curve(eff)
	if s.contract != null:
		var surplus := float(Contracts.market_value(s) - s.contract.salary) * mini(maxi(s.contract.years, 0), 3)
		v += surplus / 420.0 * float({CONTENDER: 0.7, BALANCED: 1.0, REBUILDING: 1.3}[m])
	if s.is_injured() and season.phase != Season.PHASE_OFFSEASON:
		v *= maxf(0.5, 1.0 - 0.07 * s.injury_weeks * (1.3 if m == CONTENDER else 1.0))
	if not giving:
		v *= need_factor(season, team, s)
	if giving and on_block(season, team, s):
		v *= 0.8
	return maxf(v, 1.0)


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
		if s.age <= 24 and s.potential >= Soldier.POTENTIAL_A - 1:
			step = 0.12 if mode(season, team) == REBUILDING else 0.18
		f = maxf(0.25, 0.85 - step * float(units))
	var full := team.roster.size() >= (Team.ROSTER_SIZE if season.phase != Season.PHASE_OFFSEASON else Team.OFFSEASON_MAX)
	if full:
		var worst := team.least_valuable()
		if worst != null and team.keep_value(s) <= team.keep_value(worst):
			f = minf(f, 0.2)
	return f


func pick_value(season: Season, a: Dictionary, team: Team) -> float:
	var idx := pick_index(season, a)
	var v := curve(82.0 - 0.32 * idx) + 8.0
	v *= float({CONTENDER: 0.8, BALANCED: 1.0, REBUILDING: 1.25}[mode(season, team)])
	if a["year"] > season.draft.year:
		v *= NEXT_YEAR_PICK
	return v


func value(season: Season, a: Dictionary, team: Team, giving := false) -> float:
	return pick_value(season, a, team) if is_pick(a) else player_value(season, a["soldier"], team, giving)


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


## 0..1+ for the interest bar: 1.0 means the AI says yes.
func interest(season: Season, ai: Team, user_give: Array, ai_give: Array) -> float:
	return ratio(season, ai, user_give, ai_give) / ACCEPT_MARGIN


# --- rules --------------------------------------------------------------------------

func window_open(season: Season) -> bool:
	if season.preseason_camp:
		return true
	match season.phase:
		Season.PHASE_REGULAR:
			return season.week <= DEADLINE_WEEK
		Season.PHASE_OFFSEASON:
			return season.offseason_stage in [Season.OFF_DRAFT, Season.OFF_FREE_AGENCY, Season.OFF_CAMP, Season.OFF_DONE]
	return false


func window_text(season: Season) -> String:
	if window_open(season):
		if season.phase == Season.PHASE_REGULAR and not season.preseason_camp:
			return "OPEN  -  deadline after Week %d" % DEADLINE_WEEK
		return "OPEN"
	if season.phase == Season.PHASE_OFFSEASON:
		return "CLOSED  -  reopens when the draft starts"
	return "CLOSED  -  the deadline passed after Week %d; reopens at the draft" % DEADLINE_WEEK


static func _salary(list: Array) -> int:
	var total := 0
	for a in list:
		if not is_pick(a) and a["soldier"].contract != null:
			total += a["soldier"].contract.salary
	return total


static func _players(list: Array) -> int:
	return list.filter(func(a): return not is_pick(a)).size()


static func min_roster(season: Season) -> int:
	return MIN_ROSTER_OFFSEASON if season.phase == Season.PHASE_OFFSEASON or season.preseason_camp else MIN_ROSTER


## "" when the deal is legal, otherwise why not. Rosters may go over the limit (cut before the
## next match); they may not drop below min_roster().
func validate(season: Season, a: Team, a_give: Array, b: Team, b_give: Array) -> String:
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
				if not t.roster.has(s):
					return "%s is no longer on %s." % [s.display_name(), t.name]
				if not tradeable(s):
					return "%s's contract is expiring; he can't be traded." % s.display_name()
	var cy := season.cap_year()
	var floor_n := min_roster(season)
	for side in [[a, a_give, b_give], [b, b_give, a_give]]:
		var t: Team = side[0]
		var after: int = t.roster.size() - _players(side[1]) + _players(side[2])
		if after < floor_n and _players(side[1]) > _players(side[2]):
			return "%s would be left with only %d players (min %d)." % [t.name, after, floor_n]
		var incoming := _salary(side[2])
		var outgoing := _salary(side[1])
		var payroll := Contracts.payroll(t, cy) + incoming - outgoing
		if incoming > outgoing and payroll > Contracts.SALARY_CAP:
			return "%s would be %s over the cap." % [t.name, Contracts.money(payroll - Contracts.SALARY_CAP)]
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
			if validate(season, user, g, ai, ai_give) != "":
				continue
			if interest(season, ai, g, ai_give) >= 1.0:
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
		"b_gave": b_give.map(func(x): return asset_text(season, x)), "reactions": reactions, "ai": not (a.user_controlled or b.user_controlled)}
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
## {traded: [Soldier], cut: [Soldier]}.
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
	from.release(s)
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


## Fills `payer`'s side for `target` assets (going to `payer`): as much value as possible while
## `payer` still comes out ACCEPT_MARGIN ahead. Ranks payer assets by how much `other` likes them.
func _payment(season: Season, payer: Team, other: Team, target: Array, other_gives: Array) -> Array:
	var budget := 0.0
	var got: Array = target.map(func(a): return value(season, a, payer))
	got.sort()
	got.reverse()
	for i in got.size():
		budget += got[i] * DEPTH_WEIGHTS[mini(i, DEPTH_WEIGHTS.size() - 1)]
	budget /= ACCEPT_MARGIN
	var pool: Array = assets_of(season, payer).filter(func(x): return is_pick(x) or not _fresh(season, x["soldier"]))
	var cost := {}
	var appeal := {}
	for x in pool:
		cost[key_of(x)] = value(season, x, payer, true)
		appeal[key_of(x)] = value(season, x, other)
	pool = pool.filter(func(x): return cost[key_of(x)] <= budget)
	pool.sort_custom(func(p, q): return appeal[key_of(p)] / cost[key_of(p)] > appeal[key_of(q)] / cost[key_of(q)])
	var out: Array = []
	var spent := 0.0
	for x in pool:
		if out.size() >= MAX_ASSETS:
			break
		var c: float = cost[key_of(x)]
		if spent + c > budget:
			continue
		var trial: Array = out + [x]
		if validate(season, payer, trial, other, other_gives) != "":
			continue
		out = trial
		spent += c
	return out


## An AI team makes the user an offer for one of his players (block players first).
func offer_to_user(season: Season, rng: RandomNumberGenerator) -> bool:
	var user := season.user_team()
	var targets := _user_block(season)
	if targets.is_empty():
		targets = user.roster.filter(func(s: Soldier): return tradeable(s) and s.best_ovr() >= 53)
	if targets.is_empty():
		return false
	var ais: Array = season.league.teams.filter(func(t: Team): return not t.user_controlled and patience_of(t) > 0)
	_shuffle(ais, rng)
	for ai: Team in ais:
		# Only players who fill a real need: a starter or the top backup at his role.
		var ranked: Array = targets.filter(func(p: Soldier): return need_factor(season, ai, p) >= 0.85)
		if ranked.is_empty():
			continue
		ranked.sort_custom(func(p: Soldier, q: Soldier): return player_value(season, p, ai) > player_value(season, q, ai))
		var target: Soldier = ranked[rng.randi() % mini(3, ranked.size())]
		var want := [player_asset(target)]
		var pay := _payment(season, ai, user, want, want)
		if pay.is_empty() or validate(season, user, want, ai, pay) != "":
			continue
		if ratio(season, ai, want, pay) < ACCEPT_MARGIN:
			continue
		offers.append({"team": ai, "give": pay, "get": want, "year": season.year, "week": season.week})
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


## Two AI teams swap: one shops a player (block players first), the other pays as long as both
## come out ahead by their own valuation.
func ai_to_ai(season: Season, rng: RandomNumberGenerator) -> bool:
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
			if buyer == seller:
				continue
			var pay := _payment(season, buyer, seller, want, want)
			if pay.is_empty() or validate(season, buyer, pay, seller, want) != "":
				continue
			if ratio(season, buyer, want, pay) < ACCEPT_MARGIN or ratio(season, seller, pay, want) < 1.0:
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

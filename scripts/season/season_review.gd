class_name SeasonReview
extends RefCounted
## End-of-season review: league awards (MVP, best Frontman/Center/Flex, Rookie of the Year,
## All-League team) and the yearly dev-star re-grade. Awards, Player of the Week honors, a
## breakout, outplaying his rating and a veteran mentor give a soldier a chance at a star; major
## injuries, riding the bench, underperforming and age (30+) a chance to lose one. Stars move at
## most one a season (camp drills share that limit) and never touch the caps: Potential (A-F)
## comes from the caps alone, so this only changes how fast he grows toward them.

const MIN_MATCHES := 4
## Performance percentile minus rating percentile that counts as out/underplaying his rating.
const PERFORMANCE_GAP := 0.3
## Injury length (weeks) that can cost a star.
const MAJOR_INJURY_WEEKS := 5
## Chance of a star per reason (combined as 1 - product of misses, then scaled by GAIN_AGE).
const GAIN_CHANCE := {"Season MVP": 0.6, "Rookie of the Year": 0.35, "Best role": 0.3, "All-League": 0.25,
	"Breakout": 0.3, "Outplayed his rating": 0.15, "Veteran mentor": 0.08}
## Player of the Week: chance per honor, capped.
const POTW_CHANCE := 0.02
const POTW_MAX := 0.10
## Age factor on star gains: [max age, factor].
const GAIN_AGE := [[22, 1.25], [26, 1.0], [30, 0.65], [33, 0.4], [99, 0.25]]
## Chance of losing a star per reason (only rolled when he didn't gain one; award winners are safe).
const LOSS_CHANCE := {"Major injury": 0.35, "Didn't play": 0.35, "Underperformed": 0.25, "Age": 0.08}
const LOSS_AGE_LATE := 0.15
## A breakout: this young and this many OVR gained over the season.
const BREAKOUT_AGE := 24
const BREAKOUT_GAIN := 4
## A mentor: a teammate this old and this good at the same best role, who also played.
const MENTOR_AGE := 30
const MENTOR_OVR := 85
const ALL_LEAGUE_ROLES := [Scheme.Role.FRONTMAN, Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX, Scheme.Role.FLEX]

var year: int
## Array of {award: String, soldier, team, line: String}.
var awards: Array = []
## All-League team: Array of {soldier, team, role, line}.
var all_league: Array = []
## Dev-star changes: Array of {soldier, team, from: int, to: int, reasons: Array[String]}.
var dev_changes: Array = []


## Per-soldier totals for a season's played matches: Array of dicts
## {soldier, team, matches, kills, deaths, assists, damage, shots, hits, headshots, mvps, impact,
## role}. `role` is the role he played most.
static func totals(season: Season) -> Array:
	var by_id := {}
	var roles := {}
	for w in range(1, season.total_weeks() + 1):
		for m in season.matches_for_week(w):
			if not m.is_played():
				continue
			var r: MatchResult = m.result
			for sid in r.box:
				var line: Dictionary = r.box[sid]
				var team: Team = r.teams[line["team"]]
				if not by_id.has(sid):
					var so := _find(season.league, sid)
					if so == null:
						continue
					by_id[sid] = {"soldier": so, "team": team, "matches": 0, "kills": 0, "deaths": 0,
						"assists": 0, "damage": 0, "shots": 0, "hits": 0, "headshots": 0, "saves": 0, "wipes": 0, "hill_s": 0.0, "caps": 0, "mvps": 0, "impact": 0.0}
					roles[sid] = {}
				var t: Dictionary = by_id[sid]
				t["matches"] += 1
				for k in ["kills", "deaths", "assists", "damage", "shots", "hits", "headshots", "saves", "wipes", "hill_s", "caps"]:
					t[k] += line.get(k, 0)
				t["impact"] += MatchResult.impact(line)
				if sid == r.mvp_id:
					t["mvps"] += 1
				var role: int = team.scheme.role_for_slot(line["slot"])
				roles[sid][role] = int(roles[sid].get(role, 0)) + 1
	for sid in by_id:
		var best := -1
		for role in roles[sid]:
			if best < 0 or roles[sid][role] > roles[sid][best]:
				best = role
		by_id[sid]["role"] = best
		var so: Soldier = by_id[sid]["soldier"]
		var current := _team_of(season.league, so)
		if current != null:
			by_id[sid]["team"] = current
	return by_id.values()


## The single best performance of week `w` (highest match impact across every played match):
## {soldier, team, line, impact, result}, or {} if nothing was played.
static func player_of_week(season: Season, w: int) -> Dictionary:
	var best := {}
	for m in season.matches_for_week(w):
		if not m.is_played():
			continue
		var r: MatchResult = m.result
		for sid in r.box:
			var line: Dictionary = r.box[sid]
			var imp := MatchResult.impact(line)
			if not best.is_empty() and imp <= float(best["impact"]):
				continue
			var so := _find(season.league, sid)
			if so == null:
				continue
			best = {"soldier": so, "team": r.teams[line["team"]], "line": line, "impact": imp, "result": r}
	return best


static func run(season: Season, rng: RandomNumberGenerator) -> SeasonReview:
	var rev := SeasonReview.new()
	rev.year = season.year
	var rows := totals(season).filter(func(t): return t["matches"] >= MIN_MATCHES)
	for t in rows:
		t["ipm"] = t["impact"] / t["matches"]
	rows.sort_custom(func(a, b): return a["ipm"] > b["ipm"])
	if rows.is_empty():
		return rev
	var gains := {}  # soldier -> {reason: chance}
	var losses := {}

	var mvp: Dictionary = rows[0]
	rev._add_award("Season MVP", mvp)
	_reason(gains, mvp["soldier"], "Season MVP", GAIN_CHANCE["Season MVP"])

	var honored := {}
	for role in [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]:
		for t in rows:
			if t["role"] == role and t != mvp:
				rev._add_award("Best %s" % Scheme.ROLE_NAMES[role], t)
				honored[t["soldier"]] = true
				_reason(gains, t["soldier"], "Best %s" % Scheme.ROLE_NAMES[role], GAIN_CHANCE["Best role"])
				break

	var rookies := rows.filter(func(t): return t["soldier"].draft_year == season.year - 1)
	if not rookies.is_empty():
		rev._add_award("Rookie of the Year", rookies[0])
		honored[rookies[0]["soldier"]] = true
		_reason(gains, rookies[0]["soldier"], "Rookie of the Year", GAIN_CHANCE["Rookie of the Year"])

	var used := {}
	for role in ALL_LEAGUE_ROLES:
		for t in rows:
			if t["role"] == role and not used.has(t["soldier"]):
				used[t["soldier"]] = true
				rev.all_league.append({"soldier": t["soldier"], "team": t["team"], "role": role, "line": _line(t)})
				honored[t["soldier"]] = true
				_reason(gains, t["soldier"], "All-League", GAIN_CHANCE["All-League"])
				break
	honored[mvp["soldier"]] = true

	# Player of the Week: a small chance that grows with every repeat honor.
	var potw := {}
	for w in range(1, season.regular_weeks + 1):
		var p := player_of_week(season, w)
		if not p.is_empty():
			potw[p["soldier"]] = int(potw.get(p["soldier"], 0)) + 1
	for so in potw:
		var n_potw: int = potw[so]
		_reason(gains, so, "Player of the Week" + (" x%d" % n_potw if n_potw > 1 else ""), minf(POTW_CHANCE * n_potw, POTW_MAX))

	# Performance vs expectation: percentile of impact/match vs percentile of rating.
	var n := rows.size()
	if n >= 4:
		var by_ovr := rows.duplicate()
		by_ovr.sort_custom(func(a, b): return a["soldier"].best_ovr() > b["soldier"].best_ovr())
		for i in n:
			var so: Soldier = rows[i]["soldier"]
			var perf_pct := 1.0 - float(i) / (n - 1)
			var ovr_pct := 1.0 - float(by_ovr.find(rows[i])) / (n - 1)
			if perf_pct - ovr_pct > PERFORMANCE_GAP:
				_reason(gains, so, "Outplayed his rating", GAIN_CHANCE["Outplayed his rating"])
			elif ovr_pct - perf_pct > PERFORMANCE_GAP:
				_reason(losses, so, "Underperformed", LOSS_CHANCE["Underperformed"])

	var played := {}
	for r in rows:
		played[r["soldier"]] = int(r["matches"])
	var best_role := {}
	for r in rows:
		best_role[r["soldier"]] = r["role"]
	var big_injury := {}
	for inj in season.injury_log:
		if int(inj["weeks"]) >= MAJOR_INJURY_WEEKS:
			big_injury[inj["soldier"]] = true
	var start_ovr: Dictionary = season.news.start_ovr
	for t in season.league.teams:
		for so in t.roster:
			# Breakout: a young player who made a big jump this season.
			if so.age <= BREAKOUT_AGE and start_ovr.has(so.id) and so.best_ovr() - int(start_ovr[so.id]) >= BREAKOUT_GAIN:
				_reason(gains, so, "Breakout", GAIN_CHANCE["Breakout"])
			# Veteran mentor: a proven teammate at his role who played alongside him.
			if so.age <= BREAKOUT_AGE and played.has(so):
				for m in t.roster:
					if m != so and m.age >= MENTOR_AGE and m.best_ovr() >= MENTOR_OVR and played.has(m) \
							and best_role.get(m, -1) == best_role[so]:
						_reason(gains, so, "Veteran mentor", GAIN_CHANCE["Veteran mentor"])
						break
			if honored.has(so):
				continue
			if big_injury.has(so):
				_reason(losses, so, "Major injury", LOSS_CHANCE["Major injury"])
			if so.age >= 22 and int(played.get(so, 0)) < season.regular_weeks / 3:
				_reason(losses, so, "Didn't play", LOSS_CHANCE["Didn't play"])
			if so.age >= 30:
				_reason(losses, so, "Age", LOSS_AGE_LATE if so.age >= 33 else LOSS_CHANCE["Age"])

	# Roll in roster order so a seed always gives the same review.
	for t in season.league.teams:
		for so: Soldier in t.roster:
			if so.dev_changed_in(season.year):
				continue
			var delta := 0
			var reasons: Array = []
			if gains.has(so) and so.dev < Soldier.DEV_MAX and rng.randf() < gain_chance(so, gains[so]):
				delta = 1
				reasons = gains[so].keys()
			elif losses.has(so) and not honored.has(so) and so.dev > Soldier.DEV_MIN and rng.randf() < _combine(losses[so]):
				delta = -1
				reasons = losses[so].keys()
			if delta == 0:
				continue
			var from := so.dev
			so.change_dev(delta, season.year)
			so.log_progress("Dev re-grade: " + ", ".join(reasons), {}, so.best_ovr(), from, so.dev)
			rev.dev_changes.append({"soldier": so, "team": t, "from": from, "to": so.dev, "reasons": reasons})
	rev.dev_changes.sort_custom(func(a, b): return a["to"] - a["from"] > b["to"] - b["from"])
	return rev


## His chance of gaining a star from `reasons` ({reason: chance}), scaled by age.
static func gain_chance(so: Soldier, reasons: Dictionary) -> float:
	var factor: float = GAIN_AGE[-1][1]
	for band in GAIN_AGE:
		if so.age <= band[0]:
			factor = band[1]
			break
	return clampf(_combine(reasons) * factor, 0.0, 0.95)


## 1 - the product of every miss.
static func _combine(reasons: Dictionary) -> float:
	var miss := 1.0
	for k in reasons:
		miss *= 1.0 - float(reasons[k])
	return 1.0 - miss

func award_for(so: Soldier) -> Array:
	var out: Array = []
	for a in awards:
		if a["soldier"] == so:
			out.append(a["award"])
	for a in all_league:
		if a["soldier"] == so:
			out.append("All-League")
	return out


func _add_award(award: String, t: Dictionary) -> void:
	awards.append({"award": award, "soldier": t["soldier"], "team": t["team"], "line": _line(t)})


static func _line(t: Dictionary) -> String:
	return "%d GP  %d K  %d D  %d A  %.0f IMP/G" % [t["matches"], t["kills"], t["deaths"], t["assists"], t["impact"] / t["matches"]]


static func _reason(into: Dictionary, so: Soldier, reason: String, chance: float) -> void:
	if not into.has(so):
		into[so] = {}
	into[so][reason] = chance


static func _find(league: League, id: int) -> Soldier:
	for t in league.teams:
		for s in t.roster:
			if s.id == id:
				return s
	return null


static func _team_of(league: League, so: Soldier) -> Team:
	for t in league.teams:
		if t.roster.has(so):
			return t
	return null

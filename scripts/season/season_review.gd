class_name SeasonReview
extends RefCounted
## End-of-season review: league awards (MVP, best Frontman/Center/Flex, Rookie of the Year,
## All-League team) and the yearly potential re-grade. Awards and outplaying your rating raise a
## soldier's potential grade; underperforming and age lower it. Grade changes also move the
## hidden group caps (up: more room to grow, down: less).

const MIN_MATCHES := 4
## Performance percentile minus rating percentile needed to move a grade.
const PERFORMANCE_GAP := 0.3
const MAX_GRADE_CHANGE := 2
const ALL_LEAGUE_ROLES := [Scheme.Role.FRONTMAN, Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX, Scheme.Role.FLEX]

var year: int
## Array of {award: String, soldier, team, line: String}.
var awards: Array = []
## All-League team: Array of {soldier, team, role, line}.
var all_league: Array = []
## Array of {soldier, team, from: int, to: int, reasons: Array[String]}.
var potential_changes: Array = []


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


static func run(season: Season, rng: RandomNumberGenerator) -> SeasonReview:
	var rev := SeasonReview.new()
	rev.year = season.year
	var rows := totals(season).filter(func(t): return t["matches"] >= MIN_MATCHES)
	for t in rows:
		t["ipm"] = t["impact"] / t["matches"]
	rows.sort_custom(func(a, b): return a["ipm"] > b["ipm"])
	var bumps := {}  # soldier -> {delta, reasons}
	if rows.is_empty():
		return rev

	var mvp: Dictionary = rows[0]
	rev._add_award("Season MVP", mvp)
	_bump(bumps, mvp["soldier"], 1 + (1 if rng.randf() < 0.5 else 0), "Season MVP")

	var honored := {}
	for role in [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]:
		for t in rows:
			if t["role"] == role and t != mvp:
				rev._add_award("Best %s" % Scheme.ROLE_NAMES[role], t)
				honored[t["soldier"]] = "Best %s" % Scheme.ROLE_NAMES[role]
				break

	var rookies := rows.filter(func(t): return t["soldier"].draft_year == season.year - 1)
	if not rookies.is_empty():
		rev._add_award("Rookie of the Year", rookies[0])
		_bump(bumps, rookies[0]["soldier"], 1, "Rookie of the Year")

	var used := {}
	for role in ALL_LEAGUE_ROLES:
		for t in rows:
			if t["role"] == role and not used.has(t["soldier"]):
				used[t["soldier"]] = true
				rev.all_league.append({"soldier": t["soldier"], "team": t["team"], "role": role, "line": _line(t)})
				if not honored.has(t["soldier"]):
					honored[t["soldier"]] = "All-League"
				break
	for so in honored:
		if so != mvp["soldier"]:
			_bump(bumps, so, 1, honored[so])

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
				_bump(bumps, so, 1, "Outplayed his rating")
			elif ovr_pct - perf_pct > PERFORMANCE_GAP:
				_bump(bumps, so, -1, "Underperformed")

	# Age: veterans' upside fades (unless they just won an award).
	for t in season.league.teams:
		for so in t.roster:
			if so == mvp["soldier"] or honored.has(so) or rev.award_for(so).has("Rookie of the Year"):
				continue
			if so.age >= 33:
				_bump(bumps, so, -1, "Age")
			elif so.age >= 30 and rng.randf() < 0.5:
				_bump(bumps, so, -1, "Age")

	for so: Soldier in bumps:
		var delta := clampi(int(bumps[so]["delta"]), -MAX_GRADE_CHANGE, MAX_GRADE_CHANGE)
		var to := clampi(so.potential + delta, 0, Soldier.POTENTIAL_A)
		if to == so.potential:
			continue
		var from := so.potential
		set_potential(so, to, rng)
		rev.potential_changes.append({"soldier": so, "team": _team_of(season.league, so), "from": from, "to": to,
			"reasons": bumps[so]["reasons"]})
	rev.potential_changes.sort_custom(func(a, b): return a["to"] - a["from"] > b["to"] - b["from"])
	return rev


## Changes a soldier's grade and moves his caps: +2..6 on a random group per step up, -2..6 per
## step down (never below his current rating).
static func set_potential(so: Soldier, grade: int, rng: RandomNumberGenerator) -> void:
	grade = clampi(grade, 0, Soldier.POTENTIAL_A)
	var steps := grade - so.potential
	so.potential = grade
	for i in absi(steps):
		var g: StringName = Stats.UPGRADABLE_GROUPS[rng.randi_range(0, Stats.UPGRADABLE_GROUPS.size() - 1)]
		var amount := rng.randi_range(2, 6) * signi(steps)
		so.group_caps[g] = clampi(so.group_cap(g) + amount, so.group_rating(g), Stats.MAX_RATING)


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


static func _bump(bumps: Dictionary, so: Soldier, delta: int, reason: String) -> void:
	if not bumps.has(so):
		bumps[so] = {"delta": 0, "reasons": []}
	bumps[so]["delta"] += delta
	bumps[so]["reasons"].append(reason)


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

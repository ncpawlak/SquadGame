class_name Progression
extends RefCounted
## XP -> skill points (SP), spent on stat GROUPS (MLB The Show / CFB27 style).
## - XP comes from matches (performance-based) and weekly training (scaled by intensity).
## - The soldier's potential grade scales XP gain (A 1.5x .. F 0.6x).
## - Every xp_to_next() XP grants SKILL_POINTS_PER_LEVEL SP (levels are internal, not shown).
## - Upgrading a group raises its rating (the average of its stats) by 1: the group's N stats
##   receive N points, handed out one at a time at random (max +2 per stat per upgrade, 99 max).
## - Cost scales with the group's current rating. A group can't be upgraded past its cap.

const SKILL_POINTS_PER_LEVEL := 3
## Max points one stat can get from a single group upgrade.
const MAX_STAT_GAIN_PER_UPGRADE := 2

const MATCH_BASE_XP := 150.0
const MATCH_WIN_XP := 100.0
const MATCH_IMPACT_XP_SCALE := 0.25
const MVP_XP := 75.0


## XP multiplier per potential grade (F..A).
const POTENTIAL_XP := [0.6, 0.8, 1.0, 1.25, 1.5]


static func xp_to_next(level: int) -> int:
	return 500 + 150 * (level - 1)


static func xp_multiplier(soldier: Soldier) -> float:
	return POTENTIAL_XP[clampi(soldier.potential, 0, POTENTIAL_XP.size() - 1)]


## Progress toward the next batch of skill points: [xp, needed].
static func xp_progress(soldier: Soldier) -> Array:
	return [soldier.xp, xp_to_next(soldier.level)]


## SP needed to upgrade a group by 1 from its current rating.
static func group_cost(group_rating: int) -> int:
	if group_rating < 60:
		return 1
	if group_rating < 80:
		return 2
	if group_rating < 90:
		return 3
	return 4


static func upgrade_cost(soldier: Soldier, group: StringName) -> int:
	return group_cost(soldier.group_rating(group))


## Adds XP (after the potential multiplier). Returns a report: { xp, levels, points }.
static func gain_xp(soldier: Soldier, base_xp: float) -> Dictionary:
	var amount := roundi(base_xp * xp_multiplier(soldier))
	var report := {"xp": amount, "levels": 0, "points": 0}
	soldier.xp += amount
	while soldier.xp >= xp_to_next(soldier.level):
		soldier.xp -= xp_to_next(soldier.level)
		soldier.level += 1
		soldier.skill_points += SKILL_POINTS_PER_LEVEL
		report["levels"] += 1
		report["points"] += SKILL_POINTS_PER_LEVEL
		# Usage decays so recent play matters most.
		for s in Stats.ALL:
			soldier.usage[s] *= 0.5
	return report


static func is_capped(soldier: Soldier, group: StringName) -> bool:
	if not Stats.UPGRADABLE_GROUPS.has(group):
		return true
	if soldier.group_headroom(group) <= 0:
		return true
	for s in Stats.group_stats(group):
		if soldier.stats[s] < Stats.MAX_RATING:
			return false
	return true


static func can_upgrade(soldier: Soldier, group: StringName) -> bool:
	return not is_capped(soldier, group) and soldier.skill_points >= upgrade_cost(soldier, group)


## Spends SP to raise `group` by 1. Returns stat -> points gained (empty if refused).
static func upgrade_group(soldier: Soldier, group: StringName, rng: RandomNumberGenerator = null) -> Dictionary:
	if not can_upgrade(soldier, group):
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	soldier.skill_points -= upgrade_cost(soldier, group)
	var members: Array = Stats.group_stats(group)
	var gains := {}
	for s in members:
		gains[s] = 0
	for i in members.size():
		var open: Array = []
		for s in members:
			if gains[s] < MAX_STAT_GAIN_PER_UPGRADE and soldier.stats[s] + gains[s] < Stats.MAX_RATING:
				open.append(s)
		if open.is_empty():
			break
		var pick: StringName = open[rng.randi_range(0, open.size() - 1)]
		gains[pick] += 1
	for s in members:
		soldier.stats[s] += gains[s]
	return gains


## How much a group matters to a role's OVR: the sum of the role's weights on its stats
## (an upgrade adds ~1 to each stat in the group).
static func group_value(role: Scheme.Role, group: StringName) -> float:
	var weights: Dictionary = Scheme.ROLE_WEIGHTS[role]
	var total := 0.0
	for s in Stats.group_stats(group):
		total += float(weights.get(s, 0.0))
	return total


## AI spending: best OVR gain per SP for the soldier's role, nudged by recent usage.
## Spends until nothing affordable remains. Returns the groups upgraded (in order).
static func auto_spend(soldier: Soldier, role: Scheme.Role, rng: RandomNumberGenerator = null) -> Array[StringName]:
	var raised: Array[StringName] = []
	var usage_total := 0.0
	for s in Stats.ALL:
		usage_total += soldier.usage[s]
	while true:
		var best: StringName = &""
		var best_score := -INF
		for g in Stats.UPGRADABLE_GROUPS:
			if not can_upgrade(soldier, g):
				continue
			var usage_share := 0.0
			if usage_total > 0.0:
				for s in Stats.group_stats(g):
					usage_share += soldier.usage[s] / usage_total
			var score: float = (group_value(role, g) + 0.2 + usage_share * 2.0) / upgrade_cost(soldier, g)
			if score > best_score:
				best_score = score
				best = g
		if best == &"":
			break
		upgrade_group(soldier, best, rng)
		raised.append(best)
	return raised


## Awards post-match XP to every soldier who played. Returns soldier_id -> gain_xp report.
static func award_match_xp(result: MatchResult, year := 0) -> Dictionary:
	var reports := {}
	for team_index in 2:
		var team: Team = result.teams[team_index]
		for soldier in team.starters():
			var line := result.box_for(soldier)
			if line.is_empty():
				continue
			var xp := MATCH_BASE_XP + maxf(0.0, MatchResult.impact(line)) * MATCH_IMPACT_XP_SCALE
			if team_index == result.winner_index:
				xp += MATCH_WIN_XP
			if soldier.id == result.mvp_id:
				xp += MVP_XP
			reports[soldier.id] = gain_xp(soldier, xp)
			_record_career(soldier, line, soldier.id == result.mvp_id, year, team.abbrev)
	return reports


static func _record_career(soldier: Soldier, line: Dictionary, mvp := false, year := 0, team_abbrev := "") -> void:
	var add := {"matches": 1, "rounds": line["rounds_played"], "kills": line["kills"], "deaths": line["deaths"],
		"assists": line["assists"], "damage": roundi(line["damage"]), "saves": line.get("saves", 0),
		"headshots": line["headshots"], "shots": line["shots"], "hits": line["hits"], "mvps": 1 if mvp else 0,
		"clutches": line["clutches"]}
	var targets: Array = [soldier.career]
	if year > 0:
		if not soldier.season_lines.has(year):
			var fresh := {"team": team_abbrev}
			for k in Soldier.STAT_LINE_KEYS:
				fresh[k] = 0
			soldier.season_lines[year] = fresh
		soldier.season_lines[year]["team"] = team_abbrev
		targets.append(soldier.season_lines[year])
	for d: Dictionary in targets:
		for k in add:
			d[k] = int(d.get(k, 0)) + int(add[k])


## Runs auto_spend for every soldier on AI-controlled teams.
static func auto_spend_team(team: Team, rng: RandomNumberGenerator = null) -> void:
	if team.user_controlled:
		return
	for soldier in team.roster:
		var slot := team.slot_of(soldier)
		var role := team.scheme.role_for_slot(slot) if slot != &"" else Scheme.best_role(soldier.stats)
		auto_spend(soldier, role, rng)

class_name Progression
extends RefCounted
## XP -> levels -> skill points, in the style of College Football 27.
## - XP comes from matches (performance-based) and weekly training.
## - Age scales XP gain: young players develop faster.
## - Each level grants SKILL_POINTS_PER_LEVEL points to spend on stats (by the user, or by the AI).
## - Raising a stat costs more the higher it already is, and can never pass its hidden cap.
## - Light randomness: a level-up can trigger a free +1 "breakthrough" in a stat the soldier
##   has been using a lot (weighted by usage).

const SKILL_POINTS_PER_LEVEL := 3
const BREAKTHROUGH_CHANCE := 0.35

const MATCH_BASE_XP := 150.0
const MATCH_WIN_XP := 100.0
const MATCH_IMPACT_XP_SCALE := 0.25
const MVP_XP := 75.0


static func xp_to_next(level: int) -> int:
	return 500 + 150 * (level - 1)


static func age_multiplier(age: int) -> float:
	if age <= 22:
		return 1.25
	if age <= 26:
		return 1.1
	if age <= 29:
		return 1.0
	if age <= 32:
		return 0.8
	return 0.6


## Skill points needed to raise a stat by 1 from its current value.
static func point_cost(current_rating: int) -> int:
	if current_rating < 70:
		return 1
	if current_rating < 80:
		return 2
	if current_rating < 90:
		return 3
	return 4


## Adds XP (after the age multiplier). Returns a report:
## { xp, levels, points, breakthroughs: Array[StringName] }
static func gain_xp(soldier: Soldier, base_xp: float, rng: RandomNumberGenerator) -> Dictionary:
	var amount := roundi(base_xp * age_multiplier(soldier.age))
	var report := {"xp": amount, "levels": 0, "points": 0, "breakthroughs": [] as Array[StringName]}
	soldier.xp += amount
	while soldier.xp >= xp_to_next(soldier.level):
		soldier.xp -= xp_to_next(soldier.level)
		soldier.level += 1
		soldier.skill_points += SKILL_POINTS_PER_LEVEL
		report["levels"] += 1
		report["points"] += SKILL_POINTS_PER_LEVEL
		if rng.randf() < BREAKTHROUGH_CHANCE:
			var stat := _pick_breakthrough_stat(soldier, rng)
			if stat != &"":
				soldier.stats[stat] += 1
				report["breakthroughs"].append(stat)
		# Usage decays so recent play matters most.
		for s in Stats.ALL:
			soldier.usage[s] *= 0.5
	return report


static func _pick_breakthrough_stat(soldier: Soldier, rng: RandomNumberGenerator) -> StringName:
	var options: Array[StringName] = []
	var weights: Array[float] = []
	for s in Stats.ALL:
		if soldier.headroom(s) > 0:
			options.append(s)
			weights.append(1.0 + soldier.usage[s])
	if options.is_empty():
		return &""
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			return options[i]
	return options[-1]


static func can_raise(soldier: Soldier, stat: StringName) -> bool:
	return soldier.headroom(stat) > 0 and soldier.skill_points >= point_cost(soldier.stats[stat])


## Spends points to raise `stat` by 1. Returns false if capped or unaffordable.
static func spend_point(soldier: Soldier, stat: StringName) -> bool:
	if not can_raise(soldier, stat):
		return false
	soldier.skill_points -= point_cost(soldier.stats[stat])
	soldier.stats[stat] += 1
	return true


## AI spending: favour stats that matter for the soldier's role, nudged by recent usage.
## Spends until nothing affordable with headroom remains. Returns the stats raised (in order).
static func auto_spend(soldier: Soldier, role: Scheme.Role) -> Array[StringName]:
	var raised: Array[StringName] = []
	var role_weights: Dictionary = Scheme.ROLE_WEIGHTS[role]
	var usage_total := 0.0
	for s in Stats.ALL:
		usage_total += soldier.usage[s]
	while true:
		var best: StringName = &""
		var best_score := -INF
		for s in Stats.ALL:
			if not can_raise(soldier, s):
				continue
			var usage_share: float = soldier.usage[s] / usage_total if usage_total > 0.0 else 0.0
			# Value per point spent: cheaper upgrades on important stats first.
			var score: float = (float(role_weights.get(s, 0.1)) + usage_share * 2.0) / point_cost(soldier.stats[s])
			if score > best_score:
				best_score = score
				best = s
		if best == &"":
			break
		spend_point(soldier, best)
		raised.append(best)
	return raised


## Awards post-match XP to every soldier who played. Returns soldier_id -> gain_xp report.
static func award_match_xp(result: MatchResult, rng: RandomNumberGenerator) -> Dictionary:
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
			reports[soldier.id] = gain_xp(soldier, xp, rng)
			_record_career(soldier, line)
	return reports


static func _record_career(soldier: Soldier, line: Dictionary) -> void:
	soldier.career["matches"] += 1
	soldier.career["rounds"] += line["rounds_played"]
	soldier.career["kills"] += line["kills"]
	soldier.career["deaths"] += line["deaths"]
	soldier.career["assists"] += line["assists"]
	soldier.career["damage"] += roundi(line["damage"])


## Runs auto_spend for every soldier on AI-controlled teams.
static func auto_spend_team(team: Team) -> void:
	if team.user_controlled:
		return
	for soldier in team.roster:
		var slot := team.slot_of(soldier)
		var role := team.scheme.role_for_slot(slot) if slot != &"" else Scheme.best_role(soldier.stats)
		auto_spend(soldier, role)

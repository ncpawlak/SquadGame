class_name Backstory
extends RefCounted
## Career-mode starting stories (#141): chosen at creation, each trades one thing for another. A story sets the starting dev
## stars (the combine's hidden talent moves it one star either way), a cap offset on every group, the cost of earning
## stars, the starting brand and sponsor interest, and a few starting extras. Nobody picks "4 stars"; the story is the pick.

const PHENOM := &"phenom"
const BALANCED := &"balanced"
const LATE := &"late"
const WALKON := &"walkon"
const ORDER: Array[StringName] = [PHENOM, BALANCED, LATE, WALKON]
const DEFAULT := BALANCED
## The highest star count a story can start at (stars above this are earned).
const MAX_START := 3
## Starting-interest bonuses fade by this much each season in the league (like a prospect's draft slot).
const HEAT_FADE := 0.25

const DEFS := {
	PHENOM: {"name": "Phenom", "stars": 3, "caps": -3, "cost": 1.0, "brand": 15.0, "heat": 14.0, "points": 0, "morale": 0.0,
		"blurb": "A can't-miss name before you ever play a game. You grow fast and the sponsors call early, but your ceiling is lower, so you peak sooner and lower."},
	BALANCED: {"name": "Balanced", "stars": 2, "caps": 0, "cost": 1.0, "brand": 0.0, "heat": 0.0, "points": 0, "morale": 0.0,
		"blurb": "An ordinary route in: solid prospect, normal ceilings, normal costs. The baseline everything else is measured against."},
	LATE: {"name": "Late bloomer", "stars": 1, "caps": 3, "cost": 0.75, "brand": 0.0, "heat": 0.0, "points": 0, "morale": 0.0,
		"blurb": "Slow out of the gate, with the highest ceilings and cheaper stars. A long road: you get there late, and only if you keep at it."},
	WALKON: {"name": "Walk-on", "stars": 1, "caps": 0, "cost": 1.0, "brand": 0.0, "heat": -10.0, "points": 6, "morale": 8.0,
		"blurb": "Nobody's idea of a prospect. Few sponsors early, but you arrive with extra skill points and a chip on your shoulder."},
}


static func find(id: StringName) -> Dictionary:
	return DEFS.get(id, DEFS[DEFAULT])


static func story_name(id: StringName) -> String:
	return String(find(id)["name"])


## The effect lines shown on the creation screen: Array of [text, tone] with tone +1 good, -1 bad, 0 neutral.
static func effects(id: StringName) -> Array:
	var d := find(id)
	var out: Array = []
	out.append(["Starts with %d dev star%s (the combine can move it one star)" % [int(d["stars"]), "" if int(d["stars"]) == 1 else "s"], 1 if int(d["stars"]) >= 2 else -1])
	var caps := int(d["caps"])
	out.append(["Ratings ceilings %s" % ("normal" if caps == 0 else "%+d on every group" % caps), 0 if caps == 0 else (1 if caps > 0 else -1)])
	var cost := float(d["cost"])
	out.append(["Stars cost %s" % ("the normal study points" if is_equal_approx(cost, 1.0) else "%d%% fewer study points" % roundi((1.0 - cost) * 100.0)), 0 if is_equal_approx(cost, 1.0) else 1])
	if float(d["brand"]) > 0.0:
		out.append(["Starts with %d brand and early sponsor interest" % roundi(float(d["brand"])), 1])
	if float(d["heat"]) < 0.0:
		out.append(["Sponsors are slow to notice you at first", -1])
	if int(d["points"]) > 0:
		out.append(["+%d starting skill points" % int(d["points"]), 1])
	if float(d["morale"]) > 0.0:
		out.append(["Starts hungry: morale +%d" % roundi(float(d["morale"])), 1])
	return out


## Starting dev stars: the story's, moved one star by the combine's hidden talent (4 up, 1 down), within 1..MAX_START.
static func start_stars(id: StringName, talent: int) -> int:
	var stars := int(find(id)["stars"])
	if talent >= 4:
		stars += 1
	elif talent <= 1:
		stars -= 1
	return clampi(stars, Soldier.DEV_MIN, MAX_START)


## Cap points added to every group's rolled room.
static func cap_offset(id: StringName) -> int:
	return int(find(id)["caps"])


## Multiplier on the study points a star costs.
static func cost_mult(s: Soldier) -> float:
	if s == null or s.backstory == &"":
		return 1.0
	return float(find(s.backstory)["cost"])


## Sponsor interest from the story, fading each season in the league.
static func heat_bonus(s: Soldier, seasons_in: int) -> float:
	if s == null or s.backstory == &"":
		return 0.0
	return float(find(s.backstory)["heat"]) * maxf(0.0, 1.0 - HEAT_FADE * float(seasons_in))


## One-time extras, applied once when the combine locks in (after the caps are rolled).
static func apply_start(s: Soldier) -> void:
	if s.backstory == &"":
		return
	var d := find(s.backstory)
	s.brand = minf(WeeklyPlan.BRAND_MAX, s.brand + float(d["brand"]))
	s.skill_points += int(d["points"])
	if float(d["morale"]) > 0.0:
		s.add_morale(float(d["morale"]))

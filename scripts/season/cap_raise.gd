class_name CapRaise
extends RefCounted
## Career-mode offseason cap raise (#141): once an offseason the player picks one stat group that is capped (every
## stat at its ceiling) and raises its ceiling. Base +2, plus a point each for a strong season, a Performance Institute
## tier, a camp special on that group and a story that year: +6 at most. Caps never pass 99.

const BASE := 2
const MAX_RAISE := 6
const STRONG_AVG := 80.0
const STRONG_GAMES := 3
const INSTITUTE_MIN_STEPS := 1
## Age window per group, from the group's peak age (Aging.PEAK_AGE): the base and the largest raise by years before the peak.
const FULL_YEARS := 4  # this many years or more before the peak: full base, full max
const TAPER_BASE := 1
const TAPER_MAX := 4
const PEAK_MAX := 2  # at the peak age: bonuses only, up to this


## {base, max} for `group` at the player's age, or {} when the window has closed (past the group's peak).
static func window(p: Soldier, group: StringName) -> Dictionary:
	var left := int(Aging.PEAK_AGE[group]) - p.age
	if left < 0:
		return {}
	if left >= FULL_YEARS:
		return {"base": BASE, "max": MAX_RAISE}
	if left >= 1:
		return {"base": TAPER_BASE, "max": TAPER_MAX}
	return {"base": 0, "max": PEAK_MAX}


## Whether the player may raise a cap this offseason at all ("" = yes, else why not).
static func window_error(season: Season) -> String:
	var p := season.player
	if p == null or not season.player_mode:
		return "Career mode only."
	if PlayerLegacy.retired(season):
		return "You have retired."
	if season.phase != Season.PHASE_OFFSEASON:
		return "Caps are raised in the offseason."
	if p.cap_raise_year == season.year:
		return "You already raised a cap this offseason."
	return ""


## The groups that could take a raise now (capped, and below 99 somewhere).
static func eligible_groups(season: Season) -> Array[StringName]:
	var out: Array[StringName] = []
	if window_error(season) != "":
		return out
	for g in Stats.UPGRADABLE_GROUPS:
		if group_error(season, g) == "":
			out.append(g)
	return out


static func group_error(season: Season, group: StringName) -> String:
	var p := season.player
	var w := window_error(season)
	if w != "":
		return w
	if not Stats.UPGRADABLE_GROUPS.has(group):
		return "That group has no cap to raise."
	if window(p, group).is_empty():
		return "Closed: past the %s peak age (%d)." % [String(Stats.GROUP_LABELS[group]).to_lower(), int(Aging.PEAK_AGE[group])]
	if not Progression.is_capped(p, group):
		return "Fill the %s cap first (%d points of room left)." % [String(Stats.GROUP_LABELS[group]).to_lower(), Progression.placement_room(p, group)]
	if size(season, group) <= 0:
		return "At your age only a strong season, a camp special or a story can raise this cap."
	var open := false
	for st in Stats.group_stats(group):
		if p.stat_cap(st) < Stats.MAX_RATING:
			open = true
	if p.group_cap(group) >= Stats.MAX_RATING and not open:
		return "Already at 99."
	return ""


## The parts of the raise for `group`: Array of [label, points], and the total (<= MAX_RAISE).
static func parts(season: Season, group: StringName) -> Array:
	var p := season.player
	var out: Array = []
	var w := window(p, group)
	if not w.is_empty() and int(w["base"]) > 0:
		out.append(["Base", int(w["base"])])
	var sm := PlayerGrade.summary(PlayerGrade.log_for(season, season.year))
	if int(sm["games"]) >= STRONG_GAMES and float(sm["avg"]) >= STRONG_AVG:
		out.append(["Strong season (avg %d)" % roundi(float(sm["avg"])), 1])
	var team := season.user_team()
	if team != null and Facilities.steps(team, Facilities.INSTITUTE) >= INSTITUTE_MIN_STEPS:
		out.append(["Performance Institute", 1])
	if p.camp_focus == group:
		out.append(["Camp special", 1])
	if p.cap_story_bonus > 0:
		out.append(["A story this year", 1])
	return out


static func size(season: Season, group: StringName) -> int:
	var n := 0
	for part in parts(season, group):
		n += int(part[1])
	var w := window(season.player, group)
	return mini(n, int(w["max"])) if not w.is_empty() else 0


## Raises the cap. Returns {group, size, ...} on success, {} when refused.
static func apply(season: Season, group: StringName) -> Dictionary:
	if group_error(season, group) != "":
		return {}
	var p := season.player
	var n := size(season, group)
	if n <= 0:
		return {}
	var before := p.group_cap(group)
	p.group_caps[group] = mini(Stats.MAX_RATING, before + n)
	for st in Stats.group_stats(group):
		p.stat_caps[st] = mini(Stats.MAX_RATING, p.stat_cap(st) + n)
	p.cap_raise_year = season.year
	p.camp_focus = &""
	p.cap_story_bonus = 0
	season.player_notes.append({"year": season.year, "week": season.week,
		"text": "Your %s ceiling rose by %d (to %d)." % [String(Stats.GROUP_LABELS[group]).to_lower(), n, p.group_cap(group)]})
	return {"group": group, "size": n, "cap": p.group_cap(group)}

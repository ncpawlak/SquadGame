class_name WarmUp
extends RefCounted
## Career-mode match warm-up (#141): before a match the player runs one stat group's combine drill. The score sets a
## match-only bonus to every stat in that group. It is applied when the player's match starts and removed when it ends,
## so nothing carries over, and it never reaches ratings, milestones, Hall of Fame scoring or reports.
## No penalty for a bad run, just no bonus. One warm-up a week; repeating the same group pays a little less.

const MAX_BONUS := 15
## Bonus = MAX_BONUS * score ^ CURVE: half score is about +4, 0.8 is about +10.
const CURVE := 1.9
## The auto-run counts as this score (a small, steady bonus without playing the drill).
const AUTO_SCORE := 0.4
const REPEAT_STEP := 0.9  # each consecutive week on the same group
const REPEAT_MIN := 0.7
const PLAYOFF_MULT := 0.9


static func week_key(season: Season) -> int:
	return season.year * 1000 + season.week


## The bonus for a drill score (0..1).
static func bonus_for(score: float, repeats: int, playoffs: bool) -> int:
	var raw := float(MAX_BONUS) * pow(clampf(score, 0.0, 1.0), CURVE)
	raw *= maxf(REPEAT_MIN, pow(REPEAT_STEP, float(repeats)))
	if playoffs:
		raw *= PLAYOFF_MULT
	return roundi(raw)


## Consecutive earlier weeks he warmed up the same group.
static func repeats(p: Soldier, group: StringName) -> int:
	return p.warmup_streak if p.warmup_last == group else 0


## The opponent in his match this week (null when there is none).
static func opponent(season: Season) -> Team:
	var team := season.user_team()
	if team == null or season.phase == Season.PHASE_OFFSEASON:
		return null
	for m in season.matches_for_week(season.week):
		if m.involves(team):
			return m.away if m.home == team else m.home
	return null


## "" if he can warm up now, else why not.
static func error(season: Season) -> String:
	var p := season.player
	if p == null or not season.player_mode:
		return "Career mode only."
	if PlayerLegacy.retired(season):
		return "You have retired."
	if season.phase == Season.PHASE_OFFSEASON:
		return "Warm-ups are for match weeks."
	var team := season.user_team()
	if team == null or not team.roster.has(p):
		return "Only the main roster plays matches, so there is nothing to warm up for."
	if opponent(season) == null:
		return "No match this week."
	if p.is_injured():
		return "You are injured and will not play."
	if not p.warmup.is_empty() and int(p.warmup.get("key", 0)) == week_key(season):
		return "You already warmed up this week."
	return ""


static func group_stats(group: StringName) -> Array:
	return Stats.group_stats(group)


## Records the warm-up. Returns {bonus, group, score, repeats} or {} when refused.
static func submit(season: Season, group: StringName, score: float, auto := false) -> Dictionary:
	if error(season) != "" or not Stats.UPGRADABLE_GROUPS.has(group):
		return {}
	var p := season.player
	var rep := repeats(p, group)
	var s := AUTO_SCORE if auto else clampf(score, 0.0, 1.0)
	var bonus := bonus_for(s, rep, season.phase == Season.PHASE_PLAYOFFS)
	p.warmup = {"key": week_key(season), "group": group, "score": s, "bonus": bonus, "auto": auto}
	p.warmup_streak = rep + 1 if p.warmup_last == group else 1
	p.warmup_last = group
	var opp := opponent(season)
	season.player_notes.append({"year": season.year, "week": season.week,
		"text": "Warm-up (%s): %s for the match against %s." % [String(Stats.GROUP_LABELS[group]).to_lower(), ("+%d to every rating in the group" % bonus) if bonus > 0 else "no bonus this time", opp.name if opp != null else "this week"]})
	return {"bonus": bonus, "group": group, "score": s, "repeats": rep}


## The stat -> points map of the pending bonus ({} when none).
static func pending_bonus(p: Soldier) -> Dictionary:
	if p.warmup.is_empty() or int(p.warmup.get("bonus", 0)) <= 0:
		return {}
	var out := {}
	for st in group_stats(StringName(p.warmup["group"])):
		out[st] = int(p.warmup["bonus"])
	return out


## Called when a match starts: puts the warm-up bonus on the player (if he is on either team).
static func begin(home: Team, away: Team) -> void:
	for t in [home, away]:
		for so: Soldier in t.org():
			if so.player_controlled:
				so.set_match_bonus(pending_bonus(so))


## Called when a match ends: takes the bonus off again.
static func end(home: Team, away: Team) -> void:
	for t in [home, away]:
		for so: Soldier in t.org():
			if so.player_controlled and not so.match_delta.is_empty():
				so.set_match_bonus({})


## End of the week: whatever was pending is gone, played or not.
static func clear(season: Season) -> void:
	var p := season.player
	if p == null:
		return
	if not p.match_delta.is_empty():
		p.set_match_bonus({})
	if p.warmup.is_empty():
		p.warmup_streak = 0  # a week without a warm-up breaks the run on one group
		p.warmup_last = &""
	p.warmup = {}

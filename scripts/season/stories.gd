class_name Stories
extends RefCounted
## Career-mode stories and camp specials (#141). Small events that fire from how the career is going and feed growth:
## skill points, morale, brand and the offseason cap raise (CapRaise adds a point for a story and for a camp special).
## Some are automatic (a note on Home); some ask a question and wait in the player's story list until answered.
##
## Automatic: group training (high morale on a win streak: skill points), breakthrough game, injury comeback.
## Asks: media storm after a bad game, captaincy, veteran mentor.

const GROUP_TRAINING_MORALE := 85.0
const GROUP_TRAINING_STREAK := 3
const BREAKTHROUGH_SCORE := 95.0
const STORM_SCORE := 55.0
const STORM_BRAND := 40.0
const COMEBACK_GAMES := 8
const CAPTAIN_GAMES := 10
const CAPTAIN_AVG := 75.0
const CAPTAIN_MORALE := 75.0
const MENTOR_AGE := 29
## A stellar first season on the normal roster is rare: it earns a dev star outright (once per career).
const BREAKOUT_GAMES := 8
const BREAKOUT_AVG := 88.0
## Common star sources (on top of studying): a strong season, an honor, a title. Shares of the next star's study cost.
## Tuning switch (the sims turn it off to measure what these sources add): strong seasons, titles, honors and the breakout star.
static var star_sources := true
const STRONG_GAMES := 8
const STRONG_AVG := 80.0
const STRONG_SHARE := 0.45
const GREAT_AVG := 85.0
const GREAT_SHARE := 0.7
const TITLE_SHARE := 0.3


static func _once(p: Soldier, kind: String, year: int) -> bool:
	if int(p.story_years.get(kind, 0)) == year:
		return false
	p.story_years[kind] = year
	return true


static func _note(season: Season, text: String) -> void:
	season.player_notes.append({"year": season.year, "week": season.week, "text": text})


static func _ask(season: Season, kind: String, title: String, text: String, choices: Array) -> void:
	var p := season.player
	for s in p.stories:
		if s["kind"] == kind:
			return
	p.stories.append({"kind": kind, "title": title, "text": text, "choices": choices, "year": season.year})
	_note(season, "%s: a decision is waiting in your stories." % title)


## After a player-log entry is recorded: `won` is whether his club won the match.
static func after_match(season: Season, entry: Dictionary, won: bool) -> void:
	var p := season.player
	p.streak = p.streak + 1 if won else 0
	if bool(entry.get("played", false)):
		var score := float(entry["score"])
		if score >= BREAKTHROUGH_SCORE and _once(p, "breakthrough", season.year):
			p.add_morale(10.0)
			p.cap_story_bonus = 1
			_note(season, "Breakthrough game: a %d grade. Morale up, and it will count toward your next cap raise." % roundi(score))
		elif score <= STORM_SCORE and p.brand >= STORM_BRAND and _once(p, "storm", season.year):
			_ask(season, "storm", "Media storm", "A rough night in front of a big audience. The press wants to hear from you.",
				[{"key": "face", "label": "Face the press (brand +3, morale -6)"}, {"key": "lowkey", "label": "Lie low (morale +4, brand -1)"}])
	if p.streak >= GROUP_TRAINING_STREAK and p.morale >= GROUP_TRAINING_MORALE and _once(p, "group", season.year):
		var sp := 2 + (1 if p.streak >= 5 else 0) + (1 if p.morale >= 95.0 else 0)
		p.skill_points += sp
		_note(season, "The squad is flying: a group training session on your own time earned %d skill points." % sp)


## End of a season, before the offseason: breakout, comeback, captaincy and mentor stories.
static func season_end(season: Season) -> void:
	var p := season.player
	if p == null or not season.player_mode:
		return
	p.stories = p.stories.filter(func(s): return int(s["year"]) >= season.year)
	var sm := PlayerGrade.summary(PlayerGrade.log_for(season, season.year))
	var games := int(sm["games"])
	if star_sources and games >= STRONG_GAMES and p.dev < Soldier.DEV_MAX and float(sm["avg"]) >= STRONG_AVG:
		var share := GREAT_SHARE if float(sm["avg"]) >= GREAT_AVG else STRONG_SHARE
		_note(season, "A %s season: scouts noticed (%d average). That counts toward your next star." % ["great" if share == GREAT_SHARE else "strong", roundi(float(sm["avg"]))])
		WeeklyPlan.add_study(p, WeeklyPlan.star_cost(p.dev, p) * share, season.year)
	var team_now := season.user_team()
	if star_sources and team_now != null and season.champion == team_now and games >= STRONG_GAMES and p.dev < Soldier.DEV_MAX:
		_note(season, "A title as a regular: it counts toward your next star.")
		WeeklyPlan.add_study(p, WeeklyPlan.star_cost(p.dev, p) * TITLE_SHARE, season.year)
	if star_sources and games >= BREAKOUT_GAMES and float(sm["avg"]) >= BREAKOUT_AVG and p.dev < Soldier.DEV_MAX and _first_roster_season(season) and _once(p, "star_breakout", season.year):
		p.change_dev(1, season.year)
		p.study_progress = 0.0
		_note(season, "Breakout season: a %d average in your first year on the roster. Scouts have re-graded you: you are now a %s." % [roundi(float(sm["avg"])), p.dev_text()])
	if p.wear_injuries >= 1 and games >= COMEBACK_GAMES and _once(p, "comeback", season.year):
		p.cap_story_bonus = 1
		p.brand = minf(WeeklyPlan.BRAND_MAX, p.brand + 3.0)
		_note(season, "Comeback season: back from a long injury and playing every week. Fans noticed, and it counts toward your next cap raise.")
	if games >= CAPTAIN_GAMES and float(sm["avg"]) >= CAPTAIN_AVG and p.morale >= CAPTAIN_MORALE and not p.captain and _once(p, "captain", season.year):
		_ask(season, "captain", "Captaincy", "The squad wants you to wear the armband next season.",
			[{"key": "accept", "label": "Take it (brand +5, morale +8)"}, {"key": "decline", "label": "Pass (morale +2)"}])
	var team := season.user_team()
	if team != null and _once(p, "mentor", season.year):
		for v in team.roster:
			if v != p and v.age >= MENTOR_AGE and v.best_ovr() >= p.base_ovr():
				var choices: Array = []
				for g in Stats.UPGRADABLE_GROUPS:
					choices.append({"key": String(g), "label": "%s (+2 skill points, a camp special on it)" % Stats.GROUP_LABELS[g]})
				_ask(season, "mentor", "Veteran mentor", "A veteran on the squad offers to teach you. Pick what to learn.", choices)
				break


## Share of the next star's study cost each yearly honor adds to the star meter.
const HONOR_SHARE := {"Season MVP": 1.0, "Rookie of the Year": 0.7, "Best role": 0.6, "All-League": 0.45, "Player of the Week": 0.1}


## After the season review: every honor fills part of the star meter, by the honor (a star is earned only when the bar
## fills, one a season). Returns the share of a star it added.
static func honors_study(season: Season) -> float:
	var p := season.player
	var rev := season.review
	if not star_sources or p == null or rev == null or not season.player_mode or p.dev >= Soldier.DEV_MAX:
		return 0.0
	var share := 0.0
	var names: PackedStringArray = []
	for a in rev.award_for(p):
		var key: String = "Best role" if String(a).begins_with("Best ") else String(a)
		if HONOR_SHARE.has(key):
			share += float(HONOR_SHARE[key])
			names.append(String(a))
	var potw := SeasonReview.potw_count(season, p, season.regular_weeks)
	if potw > 0:
		share += float(HONOR_SHARE["Player of the Week"]) * potw
		names.append("Player of the Week x%d" % potw)
	if share <= 0.0:
		return 0.0
	var from := p.dev
	WeeklyPlan.add_study(p, WeeklyPlan.star_cost(p.dev, p) * share, season.year)
	_note(season, "Honors (%s) fill %d%% of your next star%s." % [", ".join(names), roundi(share * 100.0), " and earned it: you are now a %s" % p.dev_text() if p.dev > from else ""])
	return share


## True when this is the first season he played any games (the first on the normal roster, not the Green Team).
static func _first_roster_season(season: Season) -> bool:
	for e in season.player_log:
		if bool(e.get("played", false)) and int(e["year"]) < season.year:
			return false
	return true


## Answers a pending story. Returns the toast text ("" if it was not found).
static func choose(season: Season, story: Dictionary, key: String) -> String:
	var p := season.player
	if not p.stories.has(story):
		return ""
	p.stories.erase(story)
	match String(story["kind"]):
		"storm":
			if key == "face":
				p.brand = minf(WeeklyPlan.BRAND_MAX, p.brand + 3.0)
				p.add_morale(-6.0)
				return "You faced the press. Brand up."
			p.add_morale(4.0)
			p.brand = maxf(0.0, p.brand - 1.0)
			return "You kept your head down."
		"captain":
			if key == "accept":
				p.captain = true
				p.brand = minf(WeeklyPlan.BRAND_MAX, p.brand + 5.0)
				p.add_morale(8.0)
				return "You are the captain."
			p.add_morale(2.0)
			return "You passed on the armband."
		"mentor":
			var g := StringName(key)
			if Stats.UPGRADABLE_GROUPS.has(g):
				p.skill_points += 2
				p.camp_focus = g
				return "You learned from the veteran: +2 skill points and a camp special on %s." % String(Stats.GROUP_LABELS[g]).to_lower()
	return "Done."


## Camp special: pick the group (or &"" for none) your camp focuses on. It adds a point to that group's next cap raise.
static func set_camp_special(season: Season, group: StringName) -> String:
	var p := season.player
	if group != &"" and not Stats.UPGRADABLE_GROUPS.has(group):
		return "That group cannot be a camp special."
	if season.phase != Season.PHASE_OFFSEASON:
		return "Camp specials are picked in the offseason."
	p.camp_focus = group
	return ""

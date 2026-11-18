class_name PlayerCoach
extends RefCounted
## Player mode phase 4 (#100/#101): the coach. The user plays one soldier and the club picks the lineup (the usual
## AI), so he has to earn his spot. Two things decide it, and both are explained to the player:
##
## - Call-up: a Green Team player is called up once he is clearly better than the weakest main-roster player
##   (CALLUP_MARGIN OVR points). That player goes down to the Green Team to make room.
## - Starting: the lineup is the AI's usual pick. A main-roster player who is not in it is on the bench, and the
##   coach says whose slot he is chasing and by how much.
##
## `status` is what the Home screen shows; `weekly` runs before each week's lineups.

const CALLUP_MARGIN := 1

const WHERE_GREEN := &"green"
const WHERE_BENCH := &"bench"
const WHERE_STARTER := &"starter"
const WHERE_INJURED := &"injured"


## Where the player is and why. {where, team, role (Scheme.Role), ovr, holder (Soldier or null), gap (OVR points
## behind the soldier he is chasing; <= 0 means ahead), target (OVR needed), text (one line)}.
static func status(season: Season) -> Dictionary:
	var s := season.player
	var team := season.user_team()
	var role := Scheme.best_role(s.stats)
	var ovr := s.ovr_at_role(role)
	var out := {"where": WHERE_BENCH, "team": team, "role": role, "ovr": ovr, "holder": null, "gap": 0, "target": ovr, "text": ""}
	if s.is_injured():
		out["where"] = WHERE_INJURED
		out["text"] = "Injured (%s): out %d more week%s." % [s.injury_name if s.injury_name != "" else "hurt", s.injury_weeks, "" if s.injury_weeks == 1 else "s"]
		return out
	if team.green_team.has(s):
		out["where"] = WHERE_GREEN
		var worst := _call_up_target(season, team)
		if worst == null:
			out["text"] = "On the Green Team. No healthy player on the roster to pass right now."
		else:
			var need := worst.best_ovr() + CALLUP_MARGIN
			out["holder"] = worst
			out["target"] = need
			out["gap"] = need - s.best_ovr()
			out["text"] = "On the Green Team. Reach %d OVR (you are %d) to pass %s and be called up." % [need, s.best_ovr(), worst.short_name()]
		return out
	if team.slot_of(s) != &"":
		out["where"] = WHERE_STARTER
		out["text"] = "Starting."
		return out
	var holder := _holder(team, role)
	out["holder"] = holder
	if holder != null:
		var h := holder.ovr_at_role(role)
		out["gap"] = h - ovr
		out["target"] = h
		if h - ovr > 0:
			out["text"] = "On the bench. %s starts ahead of you at %s: %d OVR to catch up." % [holder.short_name(), Scheme.ROLE_NAMES[role], h - ovr]
		else:
			out["text"] = "On the bench. You match %s at %s, but the coach is sticking with the starter." % [holder.short_name(), Scheme.ROLE_NAMES[role]]
	else:
		out["text"] = "On the bench."
	return out


## One line for the game log when he did not play.
static func reason_for_absence(season: Season) -> String:
	var st := status(season)
	match st["where"]:
		WHERE_INJURED: return "Injured"
		WHERE_GREEN: return "Green Team"
		_: return "Bench"


## The starter at `role` with the lowest rating there: the one the player would replace.
static func _holder(team: Team, role: Scheme.Role) -> Soldier:
	var best: Soldier = null
	for s in team.starters():
		if team.scheme.role_for_slot(team.slot_of(s)) != role:
			continue
		if best == null or s.ovr_at_role(role) < best.ovr_at_role(role):
			best = s
	return best


## The weakest healthy main-roster player: the one the player has to pass. The coach may move him to the Green
## Team whatever his age (as the league's setup does), so a better player can always take the spot.
static func _call_up_target(_season: Season, team: Team) -> Soldier:
	var worst: Soldier = null
	for s in team.roster:
		if s.is_injured() or s.injury_cover_for != 0:
			continue
		if worst == null or s.best_ovr() < worst.best_ovr():
			worst = s
	return worst


## Weekly, before lineups: calls the player up when he has earned it. Returns the news line, or "".
static func weekly(season: Season) -> String:
	if not season.player_mode or season.player == null or season.phase == Season.PHASE_OFFSEASON or PlayerLegacy.retired(season):
		return ""
	var s := season.player
	var team := season.user_team()
	if not team.green_team.has(s) or s.is_injured():
		return ""
	var worst := _call_up_target(season, team)
	if worst == null or s.best_ovr() < worst.best_ovr() + CALLUP_MARGIN:
		return ""
	if team.roster_count() >= Team.ROSTER_SIZE:
		GreenTeam._move_down(team, worst)
	if GreenTeam.call_up(season, team, s) != "":
		GreenTeam._move_up(team, worst)  # could not promote him: put the other player back
		return ""
	var line := "The coach called you up: you are now better than %s (%d vs %d OVR)." % [worst.short_name(), s.best_ovr(), worst.best_ovr()]
	season.player_notes.append({"year": season.year, "week": season.week, "text": line})
	PlayerLegacy.update(season)
	return line

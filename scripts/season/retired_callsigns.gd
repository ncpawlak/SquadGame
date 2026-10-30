class_name RetiredCallsigns
extends RefCounted
## Retired callsigns: a retiring soldier who gave a club long service and won major honors has his
## callsign retired league-wide, so nobody is ever handed it again and it hangs from that club's
## banner row. AI clubs apply the rule automatically; the user's club is asked first. Undecided
## proposals are honoured when the next season starts.
##
## Entries (League.retired_callsigns / callsign_proposals):
## {callsign, soldier, team (the club), year (retired), seasons (with the club), honors: Array[String]}

## Seasons with one club that count as long service.
const MIN_SEASONS_WITH_CLUB := 6
## Major honors: a Season MVP, or this many awards and All-League picks combined.
const MIN_HONORS := 3
const MVP_AWARD := "Season MVP"


## The soldier's club (the one he played most seasons for; ties go to the most recent) and the
## number of seasons with it, from his season lines. {} if he has no lines.
static func club_of(season: Season, s: Soldier) -> Dictionary:
	var count := {}
	var latest := {}
	for year in s.season_lines:
		var abbrev: String = s.season_lines[year].get("team", "")
		if abbrev == "":
			continue
		count[abbrev] = int(count.get(abbrev, 0)) + 1
		latest[abbrev] = maxi(int(latest.get(abbrev, 0)), int(year))
	var best := ""
	for abbrev in count:
		if best == "" or count[abbrev] > count[best] or (count[abbrev] == count[best] and latest[abbrev] > latest[best]):
			best = abbrev
	var team := season.league.team_by_abbrev(best) if best != "" else null
	return {} if team == null else {"team": team, "seasons": count[best]}


## "2031 Season MVP", "2029 All-League", ... for every honor `s` has won.
static func honors_of(season: Season, s: Soldier) -> Array:
	var out: Array = []
	for rev: SeasonReview in season.review_history:
		for a in rev.award_for(s):
			out.append("%d %s" % [rev.year, a])
	return out


## The entry to retire `s`'s callsign with, or {} if he does not qualify.
static func make_entry(season: Season, s: Soldier) -> Dictionary:
	if s.callsign == "" or is_retired(season.league, s.callsign):
		return {}
	var club := club_of(season, s)
	if club.is_empty() or club["seasons"] < MIN_SEASONS_WITH_CLUB:
		return {}
	var honors := honors_of(season, s)
	var has_mvp := honors.any(func(h: String): return h.ends_with(MVP_AWARD))
	if not has_mvp and honors.size() < MIN_HONORS:
		return {}
	return {"callsign": s.callsign, "soldier": s, "team": club["team"], "year": season.year,
		"seasons": club["seasons"], "honors": honors}


static func is_retired(league: League, callsign: String) -> bool:
	for e in league.retired_callsigns:
		if String(e["callsign"]).to_lower() == callsign.to_lower():
			return true
	return false


## Runs the rule over this offseason's retirements (Retirement.run records). AI clubs retire
## qualifying callsigns at once; the user's club gets a proposal to answer.
static func process(season: Season, records: Array) -> void:
	for rec in records:
		var entry := make_entry(season, rec["soldier"])
		if entry.is_empty():
			continue
		if entry["team"].user_controlled:
			season.league.callsign_proposals.append(entry)
		else:
			season.league.retired_callsigns.append(entry)


## The user's answer to a proposal: retire the callsign, or let it go back into circulation.
static func decide(season: Season, entry: Dictionary, retire: bool) -> void:
	if not season.league.callsign_proposals.has(entry):
		return
	season.league.callsign_proposals.erase(entry)
	if retire:
		season.league.retired_callsigns.append(entry)


## Honours every proposal still open (called when the next season starts).
static func resolve_all(season: Season) -> void:
	for entry in season.league.callsign_proposals.duplicate():
		decide(season, entry, true)


## Callsigns retired by `team`'s fans, oldest first.
static func of_team(league: League, team: Team) -> Array:
	return league.retired_callsigns.filter(func(e: Dictionary): return e["team"] == team)

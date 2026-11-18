class_name PlayerDraft
extends RefCounted
## Player mode phase 3 (#100/#101): the created soldier enters the draft.
##
## Before Week 1 the league holds one extra rookie class (year - 1, so those rookies play this season): the normal
## generated class plus the user's soldier. League consensus on him is his true worth plus the same fixed evaluation
## error every prospect has, so the picture teams have of him is not the truth. Order is worst team first (there is
## no standings yet); AI teams pick as they always do. Every pick starts on his club's Green Team, as always.
##
## `begin` builds the class, `report` is what the scouting report shows, `run` plays the draft out and lands the
## player (or, undrafted, leaves him choosing between `undrafted_offers`). `Season.draft` (this year's normal class)
## is not touched.

const OFFERS := 3
## Spread on a pick projection: two teams' noise and the need bonus (see Draft.AI_NOISE / NEED_BONUS).
const RANGE_SPREAD := 4.2
## Draft stock per year the player is under (or over) AGE_STOCK_PIVOT: scouts like a younger body with upside.
const AGE_STOCK_BONUS := 0.5
const AGE_STOCK_PIVOT := 22

const STATE_NONE := &""
const STATE_READY := &"ready"
const STATE_OFFERS := &"offers"
const STATE_DONE := &"done"


## Builds the class with the player in it, sets the order and stores it all on the season. Safe to call once.
static func begin(season: Season) -> void:
	if season.player_draft != null:
		return
	var league := season.league
	var d := Draft.generate(Season._mix([league.league_seed, season.year, 0xD2AF1]), season.year - 1, league.next_soldier_id)
	d.league = league
	league.next_soldier_id += Draft.CLASS_SIZE
	var s := season.player
	if s.home_state == "":
		var hrng := RandomNumberGenerator.new()
		hrng.seed = Season._mix([league.league_seed, s.id, 0x40E57])
		s.home_state = LeagueData.random_state(hrng)
	var p := Prospect.new()
	p.soldier = s
	p.listed_role = Archetypes.role_of(season.player_archetype)
	var rng := RandomNumberGenerator.new()
	rng.seed = Season._mix([league.league_seed, s.id, 0xC0A5E])
	p.consensus = Draft.true_value(p) + rng.randfn(0.0, Draft.CONSENSUS_NOISE) + float(AGE_STOCK_PIVOT - s.age) * AGE_STOCK_BONUS
	d.prospects.append(p)
	d.rerank()
	d._grade_area(rng)
	d._assign_tiers()
	var teams: Array = league.teams.duplicate()
	teams.sort_custom(func(a: Team, b: Team) -> bool:
		return a.team_ovr() < b.team_ovr() if a.team_ovr() != b.team_ovr() else a.id < b.id)
	d.set_order(teams)
	season.player_draft = d
	season.player_prospect = p
	season.player_draft_state = STATE_READY


## Tier (0..4) a group rating would have in this class, ranked against everyone but the player.
static func tier_of_rating(d: Draft, player: Soldier, group: StringName, rating: int) -> int:
	var better := 0
	var n := 0
	for p in d.prospects:
		if p.soldier == player:
			continue
		n += 1
		if p.soldier.group_rating(group) > rating:
			better += 1
	return Draft.tier_for_pct(float(better) / maxf(1.0, float(n)))


## The scouting report: what the league can see of the player.
## {rank, round_text, lo, hi, area_grade, windows (group -> Vector2i of tiers), mock_pick, mock_team, class_size,
## picks (total picks in the draft), likely_undrafted}.
static func report(season: Season) -> Dictionary:
	var d := season.player_draft
	var p := season.player_prospect
	var picks := d.order.size()
	var better := 0
	var better_lo := 0
	var better_hi := 0
	for q in d.prospects:
		if q == p:
			continue
		if q.consensus > p.consensus:
			better += 1
		if q.consensus > p.consensus + RANGE_SPREAD:
			better_lo += 1
		if q.consensus > p.consensus - RANGE_SPREAD:
			better_hi += 1
	var out := {
		"rank": p.projected_rank, "round_text": d.projection(p), "lo": better_lo + 1, "hi": better_hi + 1,
		"area_grade": p.area_grade, "windows": {}, "class_size": d.prospects.size(), "picks": picks,
		"mock_pick": 0, "mock_team": null,
	}
	out["likely_undrafted"] = int(out["lo"]) > picks
	var bands: Dictionary = season.player_combine.bands()
	for g in Stats.UPGRADABLE_GROUPS:
		var lo := 0.0
		var hi := 0.0
		var n := 0
		for stat in Stats.GROUPS[g]:
			if bands.has(stat):
				lo += bands[stat].x
				hi += bands[stat].y
				n += 1
		if n == 0:
			continue
		var tl := tier_of_rating(d, season.player, g, roundi(lo / n))
		var th := tier_of_rating(d, season.player, g, roundi(hi / n))
		out["windows"][g] = Vector2i(mini(tl, th), maxi(tl, th))
	for m in d.mock(d.order):
		if m["prospect"] == p:
			out["mock_pick"] = m["pick"]
			out["mock_team"] = m["team"]
			break
	return out


## Plays the draft out. Returns the player's result: {pick (0 = undrafted), team (Team or null), projected (rank),
## slide (picks below his projection, negative = went early), picks: Array of {pick, team, prospect}}.
## A drafted player is landed at once; an undrafted one waits for `sign_undrafted`.
static func run(season: Season) -> Dictionary:
	var d := season.player_draft
	var p := season.player_prospect
	if season.player_draft_state != STATE_READY:
		return result(season)
	d.sim_to_end()
	_fix_callsigns(season)
	season.player_pick = p.pick_number
	for q in d.picks():
		# The class year is last year's; rookie deals run from this season.
		q.soldier.contract = Contracts.green_contract_for_pick(q.pick_number, d.order.size(), season.year)
	if p.drafted_by != null:
		_land(season, p.drafted_by)
	else:
		season.player_draft_state = STATE_OFFERS
	return result(season)


static func result(season: Season) -> Dictionary:
	var d := season.player_draft
	var p := season.player_prospect
	var rows: Array = []
	for q in d.picks():
		rows.append({"pick": q.pick_number, "team": q.drafted_by, "prospect": q})
	return {"pick": p.pick_number, "team": p.drafted_by, "projected": p.projected_rank,
		"slide": p.pick_number - p.projected_rank if p.pick_number > 0 else 0, "picks": rows}


## No AI rookie may keep the player's callsign.
static func _fix_callsigns(season: Season) -> void:
	var mine := season.player.callsign.to_lower()
	for q in season.player_draft.picks():
		if q != season.player_prospect and q.soldier.callsign.to_lower() == mine:
			q.soldier.callsign = ""
			season.league.give_callsign(q.soldier)


## Teams that would sign the undrafted player to a Green Team deal: those whose weakest position is his, then the
## weakest clubs. Deterministic.
static func undrafted_offers(season: Season) -> Array:
	var role := int(season.player_prospect.listed_role)
	var teams: Array = season.league.teams.duplicate()
	teams.sort_custom(func(a: Team, b: Team) -> bool:
		var na := 0 if Draft.weakest_role(a) == role else 1
		var nb := 0 if Draft.weakest_role(b) == role else 1
		if na != nb:
			return na < nb
		return a.team_ovr() < b.team_ovr() if a.team_ovr() != b.team_ovr() else a.id < b.id)
	return teams.slice(0, OFFERS)


## The undrafted player signs a Green Team deal with `team`. Returns "" or why it failed.
static func sign_undrafted(season: Season, team: Team) -> String:
	if season.player_draft_state != STATE_OFFERS:
		return "He is not choosing an offer."
	if not undrafted_offers(season).has(team):
		return "That team did not make an offer."
	var s := season.player
	s.contract = Contracts.green_contract(Contracts.green_salary_for(s), season.year)
	s.draft_year = 0
	s.draft_pick = 0
	s.morale = 80.0
	s.reps = 0.0
	s.green_seasons = 0
	team.green_team.append(s)
	_land(season, team)
	return ""


## Everything after the player has a club: other prospects' leftovers hit free agency, Green Teams are trimmed
## (the player is never the one cut), the user's club becomes his, and the class is filed away.
static func _land(season: Season, team: Team) -> void:
	var d := season.player_draft
	var undrafted: Array = d.available()
	undrafted = undrafted.filter(func(q: Prospect) -> bool: return q.soldier != season.player)
	undrafted.sort_custom(func(a: Prospect, b: Prospect): return Draft.true_value(a) > Draft.true_value(b))
	for q in undrafted.slice(0, Season.UNDRAFTED_TO_FA):
		season.league.add_free_agent(q.soldier, season.year)
	# The user is one soldier: every club, his included, is run by the AI (Season.user_team still names his).
	season.player.player_controlled = true
	season.player_start_ovr = season.player.best_ovr()
	season.player.stat_caps = Archetypes.growth_caps(season.player_archetype)
	for t in season.league.teams:
		t.user_controlled = false
		GreenTeam.enforce(season, t)
	# New rookies and free agents get their abilities now, as every week and every load does.
	Abilities.refresh_league(season.league, season.year)
	season.past_drafts.append(d)
	season.player_team = team
	season.player_draft_state = STATE_DONE


## Short line about how the night went for the player.
static func story(season: Season) -> String:
	var p := season.player_prospect
	var s := season.player
	if p.pick_number == 0:
		return "%s went undrafted, but %s teams called with Green Team offers." % [s.full_name(), OFFERS]
	var pick := p.pick_number
	var slide := pick - p.projected_rank
	var team := p.drafted_by.name
	if slide >= 5:
		return "%s slid to pick %d (projected %d) and is picked by the %s." % [s.full_name(), pick, p.projected_rank, team]
	if slide <= -5:
		return "%s jumped to pick %d (projected %d): the %s moved up for him." % [s.full_name(), pick, p.projected_rank, team]
	return "%s is selected with pick %d by the %s, about where he was projected." % [s.full_name(), pick, team]

class_name LeagueNews
extends RefCounted
## League-wide news wire. Stories are templates fired by conditions, never by names, so the same
## story finds whoever fits it in any season (today's Detroit captain, a different contender's
## veteran three years on). Every story is true to the numbers it quotes, and most carry a light
## effect:
##   last_ride        veteran (33+, 85+ OVR, final contract year or 35+) on a contender.
##                    Preseason story, morale +4; reaching the playoffs adds morale +6.
##   hometown         a starter playing for his home-state club wins a home game. Morale +4.
##   contract_year    final-year player (31 or younger) up 3+ OVR since the season began. Morale +3.
##   rookie_starter   last offseason's draftee starts one of his team's first three games. Morale +4.
##   bust             a top-3 pick, 24+ and 3+ years in, still below 80 OVR. Morale -3.
##   trade_request    a player's trade request goes public. Morale -3.
##   rivalry          a rivalry game (see Rivalries): the winners gain morale and the losers lose it, by
##                    the rivalry's intensity (2 to 4). Also a new emergent rivalry forming or ending.
##   champion / floor season-end headlines (title, salary-floor penalties).
## Offseason stories (filed under the season just finished), each capped per year:
##   mega_deal        a signing or re-signing at MEGA_SALARY or more a year.
##   fa_signing       a free agent of BIG_SIGNING_OVR+ lands with a new team.
##   defection        a free agent of DEFECTION_OVR+ leaves for his old team's rival.
##   homecoming       a free agent of HOMECOMING_OVR+ signs with his home-state club.
##   resign           a cornerstone (BIG_SIGNING_OVR+) re-signs.
##   extension        in-season: a cornerstone (BIG_SIGNING_OVR+, or a MEGA_SALARY deal) agrees to
##                    an extension (filed under the week it was signed).
##   hits_market      a STAR_MARKET_OVR+ player reaches free agency.
##   surprise_cut     an AI team releases a STAR_CUT_OVR+ player ranked in its top STAR_CUT_RANK.
##   draft_*          #1 pick, a generational talent who slid, steals, reaches and the best haul.
##   retired          a legend (LEGEND_OVR+ or an award winner) retires.
## Buzz stories (see Market): buzz_up / buzz_down when a team's buzz crosses into a new band, buzz_leader
## for the week's biggest earner. Every story also adds heat for the teams it names (Market.STORY_POINTS).

const MAX_ITEMS := 600
const MAX_PER_KIND := 3
const LAST_RIDE_AGE := 33
const LAST_RIDE_OVR := 85
const CONTENDERS := 6
const BREAKOUT_GAIN := 3
const BUST_OVR := 80
## Rivalry heat at which even a divisional game makes the wire.
const HOT_HEAT := 25.0
## Offseason story thresholds (see the header).
const MEGA_SALARY := 12000
const BIG_SIGNING_OVR := 84
const DEFECTION_OVR := 78
const HOMECOMING_OVR := 76
const STAR_MARKET_OVR := 82
const STAR_CUT_OVR := 78
## A release only shocks when he ranked this high on his team's roster.
const STAR_CUT_RANK := 8
const LEGEND_OVR := 80
const OFFSEASON_PER_KIND := 3
## Draft: a steal went STEAL_GAP picks later than his value rank (a top-STEAL_RANK talent); a reach
## went in the top REACH_PICK despite ranking REACH_GAP places lower.
const STEAL_GAP := 25
const STEAL_RANK := 12
const REACH_GAP := 25
const REACH_PICK := 10

## Newest last: {year, when, kind, headline, body, teams: [abbrev], soldier_id}.
var items: Array = []
## Soldier id -> best OVR when this season began (for contract-year breakouts).
var start_ovr := {}
var _counts := {}


func latest(n: int, team_abbrev := "") -> Array:
	var out: Array = []
	for i in range(items.size() - 1, -1, -1):
		if team_abbrev == "" or items[i]["teams"].has(team_abbrev):
			out.append(items[i])
			if out.size() >= n:
				break
	return out


func for_year(y: int) -> Array:
	return items.filter(func(it): return it["year"] == y)


## Preseason: snapshot OVRs and write the last-ride stories.
func begin_season(season: Season) -> void:
	start_ovr = {}
	for s in season.league.all_soldiers():
		start_ovr[s.id] = s.best_ovr()
	var contenders := season.league.teams.duplicate()
	contenders.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	contenders = contenders.slice(0, CONTENDERS)
	var count := 0
	for t: Team in contenders:
		for s in t.roster:
			if count >= MAX_PER_KIND:
				break
			var final_year := s.contract != null and s.contract.years <= 1
			if s.age < LAST_RIDE_AGE or s.best_ovr() < LAST_RIDE_OVR or not (final_year or s.age >= 35):
				continue
			if not _tag(s, "last_ride", season.year):
				continue
			count += 1
			s.add_morale(4.0)
			var why := "with his contract up after this season" if final_year else "at %d" % s.age
			_add(season, "Preseason", "last_ride", [t.abbrev], s.id,
				"%s wants one more ring before he hangs it up" % s.display_name(),
				"%s (%d OVR) enters what could be his final season %s. \"I want to bring a championship home to %s before I'm done.\" The %s are a contender, and the room is rallying around him." % [
					s.full_name(), s.best_ovr(), why, t.city, t.nickname])


## After a week is played: rivalry results, then player stories.
func week_stories(season: Season, played: Array, wk: int) -> void:
	var when := season.week_label(wk)
	_counts = {}
	var counts := _counts
	var winners := {}
	for m: ScheduledMatch in played:
		if not m.is_played():
			continue
		winners[m.winner()] = m
		if season.rivalries.is_rivalry(m.home, m.away):
			_rivalry(season, m, when)
	for e in season.rivalries.last_events:
		_rivalry_change(season, when, e)
	var home_winners := {}
	for t in winners:
		if winners[t].home == t:
			home_winners[t] = true
	for t: Team in season.league.teams:
		var starters := t.starters()
		for s in t.roster:
			# Hometown hero: a starter for his home-state club, in a home win.
			if home_winners.has(t) and s.home_state != "" and s.home_state == t.home_state \
					and starters.has(s) and _room(counts, "hometown") and _tag(s, "hometown:" + t.abbrev, season.year):
				s.add_morale(4.0)
				_add(season, when, "hometown", [t.abbrev], s.id,
					"Hometown kid %s delivers for %s" % [s.display_name(), t.city],
					"%s grew up in %s and starts for the %s. Today's home win in front of family and friends was one he'll remember." % [
						s.full_name(), LeagueData.state_name(s.home_state), t.nickname])
			# Contract-year breakout.
			if wk >= 5 and s.contract != null and s.contract.years == 1 and s.age <= 31 and start_ovr.has(s.id) \
					and s.best_ovr() - int(start_ovr[s.id]) >= BREAKOUT_GAIN and _room(counts, "contract_year") \
					and _tag(s, "contract_year", season.year):
				s.add_morale(3.0)
				_add(season, when, "contract_year", [t.abbrev], s.id,
					"%s is playing for his next contract" % s.display_name(),
					"In the last year of his deal, %s has climbed from %d to %d OVR this season. His agent will be busy this offseason." % [
						s.full_name(), int(start_ovr[s.id]), s.best_ovr()])
			# Rookie wins a starting job.
			if wk <= 3 and s.draft_year == season.year - 1 and starters.has(s) and _played(t, played):
				if _room(counts, "rookie_starter") and _tag(s, "rookie_starter", 0):
					s.add_morale(4.0)
					var pick := ("the #%d pick" % s.draft_pick) if s.draft_pick > 0 else "a rookie"
					_add(season, when, "rookie_starter", [t.abbrev], s.id,
						"Rookie %s wins a starting job" % s.display_name(),
						"%s, %s in %d, has cracked the %s starting five at %d OVR." % [
							s.full_name(), pick, s.draft_year, t.nickname, s.best_ovr()])
			# Former top pick bust.
			if s.draft_pick >= 1 and s.draft_pick <= 3 and s.age >= 24 and season.year - s.draft_year >= 3 \
					and s.best_ovr() < BUST_OVR and _room(counts, "bust") and _tag(s, "bust", 0):
				s.add_morale(-3.0)
				_add(season, when, "bust", [t.abbrev], s.id,
					"Is %s the biggest miss of the %d draft?" % [s.display_name(), s.draft_year],
					"Taken #%d overall in %d, %s is %d and still sits at %d OVR. Patience is running out." % [
						s.draft_pick, s.draft_year, s.full_name(), s.age, s.best_ovr()])
			# Public trade request.
			if s.trade_request and _room(counts, "trade_request") and _tag(s, "trade_request", season.year):
				s.add_morale(-3.0)
				_add(season, when, "trade_request", [t.abbrev], s.id,
					"%s asks %s for a trade" % [s.display_name(), t.city],
					"%s (%d OVR) has gone public: he wants out of %s. The %s say they will listen to offers." % [
						s.full_name(), s.best_ovr(), t.city, t.nickname])
	# The playoffs begin: last-ride veterans whose teams made it get a lift.
	if season.phase == Season.PHASE_PLAYOFFS and wk == season.regular_weeks:
		for t in season.playoff_seeds:
			for s in t.roster:
				if int(s.news_tags.get("last_ride", 0)) == season.year and _tag(s, "last_ride_playoffs", season.year):
					s.add_morale(6.0)
					_add(season, season.week_label(season.regular_weeks + 1), "last_ride", [t.abbrev], s.id,
						"%s's last ride reaches the playoffs" % s.display_name(),
						"The %s are the #%d seed, and %s gets one more shot at a title." % [
							t.nickname, int(season.playoff_seeds[t]), s.full_name()])


## Season-end headlines: the champion (and any last ride that ended with a ring), floor penalties.
func end_season(season: Season, penalties: Array) -> void:
	var champ := season.champion
	if champ != null:
		var runner: Team = null
		for m in season.playoff_matches:
			if m.stage == Season.STAGE_FINAL:
				runner = m.loser()
		_add(season, "Final", "champion", [champ.abbrev], 0,
			"%s win the %d championship" % [champ.name, season.year],
			"The %s beat %s in the final to lift the title." % [champ.nickname, runner.name if runner else "their rival"])
		for s in champ.roster:
			if int(s.news_tags.get("last_ride", 0)) == season.year:
				_add(season, "Final", "last_ride", [champ.abbrev], s.id,
					"%s gets his ring" % s.display_name(),
					"%s chased one more title and got it. Whatever he decides next, he goes out a champion." % s.full_name())
	var legends: Array = season.retirements_in(season.year).filter(func(r): return r["reason"] == Retirement.REASON_AGE \
		and (int(r["ovr"]) >= LEGEND_OVR or not (r["awards"] as Array).is_empty()))
	legends.sort_custom(func(a, b): return int(a["ovr"]) > int(b["ovr"]))
	for r in legends.slice(0, 3):
		var s: Soldier = r["soldier"]
		if not _tag(s, "retired", 0):
			continue
		var rt: Team = r["team"]
		var awards: Array = r["awards"]
		var line := "%d matches and %d kills" % [int(r["matches"]), int(r["kills"])]
		if not awards.is_empty():
			line += ", with %d award%s (%s)" % [awards.size(), "" if awards.size() == 1 else "s", ", ".join(awards.slice(0, 3))]
		_add(season, "Re-signing", "retired", [rt.abbrev] if rt != null else [], s.id,
			"%s retires at %d" % [s.display_name(), int(r["age"])],
			"%s hangs it up after a career of %s." % [s.full_name(), line])
	for p in penalties:
		var t: Team = p["team"]
		_add(season, "Offseason", "floor", [t.abbrev], 0,
			"%s fined for spending under the salary floor" % t.name,
			"The %s finished under the %s floor and owe the %s shortfall next season." % [
				t.nickname, Contracts.money(Contracts.SALARY_FLOOR), Contracts.money(p["amount"])])


## A soldier signs with a team (free agency, camp fill-ins, in-season pickups). `entry` is a
## FreeAgency history entry. One story at most, the biggest angle first.
func signing(season: Season, entry: Dictionary) -> void:
	var s: Soldier = entry["soldier"]
	var t: Team = entry["team"]
	var salary := int(entry["salary"])
	var years := int(entry["years"])
	var ovr := s.best_ovr()
	var from := season.league.team_by_abbrev(s.former_team)
	var moved := from != null and from != t
	var teams := [t.abbrev]
	if moved:
		teams.append(from.abbrev)
	var rival := moved and season.rivalries.is_rivalry(from, t)
	var deal := "%s a year for %d year%s (%s in all)" % [Contracts.money(salary), years, "" if years == 1 else "s", Contracts.money(salary * years)]
	var kind := ""
	var head := ""
	var body := ""
	if salary >= MEGA_SALARY:
		kind = "mega_deal"
		head = "%s cashes in: %s a year from %s" % [s.display_name(), Contracts.money(salary), t.city]
		body = "%s (%d OVR) gets %s, one of the biggest contracts the league has seen." % [s.full_name(), ovr, deal]
		if rival:
			body += " He left rival %s to get it." % from.nickname
	elif rival and ovr >= DEFECTION_OVR:
		kind = "defection"
		head = "%s leaves %s for rival %s" % [s.display_name(), from.city, t.city]
		body = "%s (%d OVR) walks away from the %s and joins their rivals, the %s, on %s. Expect that to come up at the next meeting." % [
			s.full_name(), ovr, from.nickname, t.nickname, deal]
	elif moved and ovr >= BIG_SIGNING_OVR:
		kind = "fa_signing"
		head = "%s signs with %s" % [s.display_name(), t.name]
		body = "The %s land one of the top names on the market: %s (%d OVR) on %s." % [t.nickname, s.full_name(), ovr, deal]
	elif moved and ovr >= HOMECOMING_OVR and s.home_state != "" and s.home_state == t.home_state:
		kind = "homecoming"
		head = "%s is going home to %s" % [s.display_name(), t.city]
		body = "%s (%d OVR) grew up in %s and signs with the %s on %s." % [
			s.full_name(), ovr, LeagueData.state_name(s.home_state), t.nickname, deal]
	if kind == "" or not _year_room(season, kind) or not _tag(s, kind, season.year):
		return
	_add(season, String(entry["when"]), kind, teams, s.id, head, body)


## An expiring contract is renewed (AI teams, or the user through a negotiation), or an in-season
## extension is agreed (`extension`).
func resign(season: Season, team: Team, s: Soldier, salary: int, years: int, extension := false) -> void:
	var ovr := s.best_ovr()
	var mega := salary >= MEGA_SALARY
	if not mega and ovr < BIG_SIGNING_OVR:
		return
	var kind := "extension" if extension else ("mega_deal" if mega else "resign")
	if not _year_room(season, kind) or not _tag(s, kind, season.year):
		return
	var deal := "%s a year for %d year%s" % [Contracts.money(salary), years, "" if years == 1 else "s"]
	if extension:
		_add(season, Trades._when(season), kind, [team.abbrev], s.id,
			"%s extend %s%s" % [team.name, s.display_name(), " on %s a year" % Contracts.money(salary) if mega else ""],
			"%s (%d OVR) won't reach free agency: he agrees to %s starting in %d." % [s.full_name(), ovr, deal, season.year + 1])
	elif mega:
		_add(season, "Re-signing", kind, [team.abbrev], s.id,
			"%s lock up %s on %s a year" % [team.name, s.display_name(), Contracts.money(salary)],
			"%s (%d OVR) stays put and gets %s. The %s are building around him." % [s.full_name(), ovr, deal, team.nickname])
	else:
		_add(season, "Re-signing", kind, [team.abbrev], s.id,
			"%s stays with %s" % [s.display_name(), team.city],
			"%s (%d OVR) re-signs with the %s on %s." % [s.full_name(), ovr, team.nickname, deal])


## Free agency opens: the best players who just hit the market.
func free_agency_opens(season: Season) -> void:
	var gone: Array = season.departures.filter(func(d): return d["year"] == season.year and d["soldier"].best_ovr() >= STAR_MARKET_OVR)
	gone.sort_custom(func(a, b): return a["soldier"].best_ovr() > b["soldier"].best_ovr())
	for d in gone:
		var s: Soldier = d["soldier"]
		var t: Team = d["team"]
		if not _year_room(season, "hits_market") or not _tag(s, "hits_market", season.year):
			continue
		_add(season, "FA Day 1", "hits_market", [t.abbrev], s.id,
			"%s hits the open market" % s.display_name(),
			"%s (%d OVR, age %d) is a free agent after leaving the %s. Every team with cap space will call." % [
				s.full_name(), s.best_ovr(), s.age, t.nickname])


## Dev-star changes from the season review (SeasonReview.dev_changes): every change on the
## user's team, plus the biggest names league-wide (OFFSEASON_PER_KIND of each direction, best first).
func dev_changes(season: Season, changes: Array) -> void:
	var sorted := changes.duplicate()
	sorted.sort_custom(func(a, b): return _dev_rank(a["soldier"]) > _dev_rank(b["soldier"]))
	for c in sorted:
		var s: Soldier = c["soldier"]
		var t: Team = c["team"]
		var up: bool = int(c["to"]) > int(c["from"])
		var kind := "dev_up" if up else "dev_down"
		var mine := t != null and t.user_controlled
		if not mine and not _year_room(season, kind):
			continue
		if not _tag(s, kind, season.year):
			continue
		var why := ", ".join((c["reasons"] as Array).map(func(r): return String(r).to_lower()))
		if up:
			_add(season, "Offseason", kind, [t.abbrev] if t != null else [], s.id,
				"%s earns a %d-star rating" % [s.display_name(), int(c["to"])],
				"The staff now rate %s (%d OVR, age %d) a %s developer after %s. He should close in on his ceiling faster." % [
					s.full_name(), s.best_ovr(), s.age, Soldier.dev_stars(int(c["to"])), why])
		else:
			_add(season, "Offseason", kind, [t.abbrev] if t != null else [], s.id,
				"%s drops to %d star%s" % [s.display_name(), int(c["to"]), "" if int(c["to"]) == 1 else "s"],
				"%s (%d OVR, age %d) slips to a %s developer (%s). His ceiling hasn't moved, but he'll grow toward it slower." % [
					s.full_name(), s.best_ovr(), s.age, Soldier.dev_stars(int(c["to"])), why])


## A training camp drill earned `s` a dev star.
func camp_star(season: Season, team: Team, s: Soldier, drill: String) -> void:
	if not team.user_controlled and not _year_room(season, "dev_up"):
		return
	if not _tag(s, "dev_up", season.year):
		return
	_add(season, _offseason_when(season), "dev_up", [team.abbrev], s.id,
		"%s turns heads at camp" % s.display_name(),
		"%s (%d OVR, age %d) stood out at the %s and the staff bumped him to a %s developer." % [
			s.full_name(), s.best_ovr(), s.age, drill, Soldier.dev_stars(s.dev)])


static func _dev_rank(s: Soldier) -> int:
	return maxi(s.best_ovr(), s.potential_ovr())


## An AI team releases `s` (call before his contract is cleared). Only stars make the wire.
func release(season: Season, team: Team, s: Soldier) -> void:
	if team.user_controlled or s.contract == null or s.best_ovr() < STAR_CUT_OVR:
		return
	var rank := 1
	for o in team.roster:
		if o != s and o.best_ovr() > s.best_ovr():
			rank += 1
	if rank > STAR_CUT_RANK or not _year_room(season, "surprise_cut") or not _tag(s, "surprise_cut", season.year):
		return
	var owed := s.contract.salary * maxi(s.contract.years, 1)
	_add(season, _offseason_when(season), "surprise_cut", [team.abbrev], s.id,
		"Shock: %s cut %s" % [team.name, s.display_name()],
		"The %s released %s (%d OVR, age %d), the #%d soldier on their roster, with %s still owed on his deal. Nobody saw it coming." % [
			team.nickname, s.full_name(), s.best_ovr(), s.age, rank, Contracts.money(owed)])


## The draft is complete: the top pick, a generational talent who slid, steals, reaches, best haul.
func draft_stories(season: Season) -> void:
	var picks := season.draft.picks()
	if picks.is_empty() or _wrote(season, "draft_top"):
		return
	var by_value: Array = picks.duplicate()
	by_value.sort_custom(func(a: Prospect, b: Prospect): return Draft.true_value(a) > Draft.true_value(b))
	var vrank := {}
	for i in by_value.size():
		vrank[by_value[i]] = i + 1
	var first: Prospect = picks[0]
	var fs := first.soldier
	var flavor := ""
	if first.standout == &"generational":
		flavor = " Scouts call him a generational talent."
	elif first.standout == &"blue_chip":
		flavor = " Scouts see a day-one starter."
	_add(season, "Draft", "draft_top", [first.drafted_by.abbrev], fs.id,
		"%s take %s first overall" % [first.drafted_by.name, fs.display_name()],
		"%s (%d OVR) goes #1 in the %d draft on a %s rookie deal.%s" % [
			fs.full_name(), fs.best_ovr(), season.draft.year, Contracts.contract_text(fs.contract), flavor])
	for p: Prospect in picks:
		if p.standout == &"generational" and p.pick_number > 1:
			_add(season, "Draft", "draft_slide", [p.drafted_by.abbrev], p.soldier.id,
				"%s slides to #%d" % [p.soldier.display_name(), p.pick_number],
				"%s (%d OVR), a generational talent, is still on the board at #%d and the %s pounce." % [
					p.soldier.full_name(), p.soldier.best_ovr(), p.pick_number, p.drafted_by.nickname])
			break
	var steals := 0
	var reaches := 0
	for p: Prospect in picks:
		var v: int = vrank[p]
		var s := p.soldier
		if steals < 2 and v <= STEAL_RANK and p.pick_number - v >= STEAL_GAP and p.standout != &"generational":
			steals += 1
			_add(season, "Draft", "draft_steal", [p.drafted_by.abbrev], s.id,
				"%s is the steal of the draft" % s.display_name(),
				"%s lasted until #%d and the %s grabbed him. He rates as the #%d talent in the class (%d OVR)." % [
					s.full_name(), p.pick_number, p.drafted_by.nickname, v, s.best_ovr()])
		elif reaches < 1 and p.pick_number <= REACH_PICK and v - p.pick_number >= REACH_GAP:
			reaches += 1
			_add(season, "Draft", "draft_reach", [p.drafted_by.abbrev], s.id,
				"Why did %s take %s at #%d?" % [p.drafted_by.city, s.display_name(), p.pick_number],
				"%s (%d OVR) rates only #%d in this class. The %s reached, and the board noticed." % [
					s.full_name(), s.best_ovr(), v, p.drafted_by.nickname])
	var haul := {}
	var count := {}
	for p: Prospect in picks:
		haul[p.drafted_by] = float(haul.get(p.drafted_by, 0.0)) + Draft.true_value(p)
		count[p.drafted_by] = int(count.get(p.drafted_by, 0)) + 1
	var best: Team = null
	for t: Team in haul:
		if best == null or haul[t] > haul[best]:
			best = t
	if best != null:
		_add(season, "Draft", "draft_haul", [best.abbrev], 0,
			"%s win the draft" % best.name,
			"With %d picks, the %s took the most talent of any team in the %d class." % [count[best], best.nickname, season.draft.year])


## A team's buzz crossed into a new band (see Market).
func buzz_band(season: Season, when: String, t: Team, up: bool) -> void:
	var band := Market.band_name(t.buzz)
	if up:
		_add(season, when, "buzz_up", [t.abbrev], 0,
			"%s are heating up: now %s" % [t.name, band],
			"The %s have the %s talking. Buzz around the club has climbed to %s (%d), and the %s crowds are noticing." % [
				t.nickname, t.city, band, roundi(t.buzz), Market.market_name(t).to_lower()])
	else:
		_add(season, when, "buzz_down", [t.abbrev], 0,
			"%s are cooling off: now %s" % [t.name, band],
			"Interest in the %s is slipping. Buzz has dropped to %s (%d), and %s will need results to win the city back." % [
				t.nickname, band, roundi(t.buzz), t.city])


## The week's hottest team: the club that earned the most buzz.
func buzz_leader(season: Season, when: String, t: Team, gain: float) -> void:
	var why := ""
	for e in Market.log_for(t, season.year):
		if e["when"] == when and float(e["amount"]) > 0.0:
			why = String(e["label"]).substr(0, 1).to_lower() + String(e["label"]).substr(1)
			break
	_add(season, when, "buzz_leader", [t.abbrev], 0,
		"%s are the talk of the league" % t.name,
		"The %s earned %d buzz points this week%s and sit at %s." % [
			t.nickname, roundi(gain), (", led by %s," % why) if why != "" else "", Market.buzz_text(t)])


## A club's sponsor deal for the season grew a lot (see Revenue).
func sponsor_deal(season: Season, t: Team, now: float, was: float) -> void:
	_add(season, "Preseason", "sponsor_deal", [t.abbrev], 0,
		"%s land a bigger sponsorship deal" % t.name,
		"Buzz has paid off for the %s: their sponsorship deal for %d is worth %s, up %d%% on last year's %s." % [
			t.nickname, season.year, Contracts.money(roundi(now)), roundi((now / was - 1.0) * 100.0), Contracts.money(roundi(was))])


## A club's first sold-out home game of the season.
func sellout(season: Season, when: String, t: Team) -> void:
	_add(season, when, "sellout", [t.abbrev], 0,
		"%s sell out for the first time this year" % t.name,
		"Every seat was taken in %s. With buzz at %s, the %s are the hot ticket." % [
			t.city, Market.band_name(t.buzz), t.nickname])


func _offseason_when(season: Season) -> String:
	return season.step_label() if season.phase == Season.PHASE_OFFSEASON else season.week_label(season.week)


# --- offseason recaps ----------------------------------------------------------------

## The year whose offseason is being recapped: this season during the offseason, last season
## once the next one has started.
func recap_year(season: Season) -> int:
	return season.year if season.phase == Season.PHASE_OFFSEASON else season.year - 1


## Offseason steps that have finished and can be recapped, in order.
func digest_steps(season: Season) -> Array[String]:
	var out: Array[String] = []
	if season.review_history.is_empty():
		return out
	var stage := season.offseason_stage if season.phase == Season.PHASE_OFFSEASON else Season.OFF_DONE
	# Order: re-signing, free agency days, the draft, the roster review week, camp.
	var past_fa := stage in [Season.OFF_DRAFT, Season.OFF_REVIEW, Season.OFF_CAMP, Season.OFF_DONE]
	if stage != Season.OFF_RESIGN:
		out.append("Re-signing")
	for d in range(1, Season.FA_DAYS + 1):
		if past_fa or (stage == Season.OFF_FREE_AGENCY and season.fa_day > d):
			out.append("FA Day %d" % d)
	if stage in [Season.OFF_REVIEW, Season.OFF_CAMP, Season.OFF_DONE]:
		out.append("Draft")
	if stage in [Season.OFF_CAMP, Season.OFF_DONE]:
		out.append("Roster Review")
	if stage == Season.OFF_DONE and _step_has_entries(season, "Preseason"):
		out.append("Preseason")
	return out


func _step_has_entries(season: Season, step: String) -> bool:
	var y := recap_year(season)
	return season.fa.history.any(func(e): return e["year"] == y and e["when"] == step) \
		or season.trades.moves.any(func(m): return m["year"] == y and m["when"] == step)


## Everything that happened in one offseason step: {step, year, stories, signings, cuts, trades,
## resigned, retired, market, picks}. Signings are sorted by salary, the market and re-signs by OVR.
func digest(season: Season, step: String) -> Dictionary:
	var y := recap_year(season)
	var out := {"step": step, "year": y, "stories": [], "signings": [], "cuts": [], "trades": [],
		"resigned": [], "retired": [], "market": [], "picks": []}
	var wire_when := [step] + (["Offseason"] if step == "Re-signing" else [])
	out["stories"] = items.filter(func(it): return it["year"] == y and wire_when.has(it["when"]))
	out["signings"] = season.fa.history.filter(func(e): return e["year"] == y and e["when"] == step)
	out["signings"].sort_custom(func(a, b): return int(a["salary"]) > int(b["salary"]))
	out["cuts"] = season.trades.moves.filter(func(m): return m["year"] == y and m["when"] == step and m["kind"] == &"cut")
	out["trades"] = season.trades.history.filter(func(e): return e["year"] == y and e["when"] == step)
	if step == "Re-signing":
		out["resigned"] = season.resign_log.filter(func(r): return r["year"] == y and not r.get("extension", false))
		out["resigned"].sort_custom(func(a, b): return a["soldier"].best_ovr() > b["soldier"].best_ovr())
		out["retired"] = season.retirements.filter(func(r): return r["year"] == y)
		out["retired"].sort_custom(func(a, b): return int(a["ovr"]) > int(b["ovr"]))
	elif step == "Draft":
		out["picks"] = season.draft.picks()
	elif step == "FA Day 1":
		out["market"] = season.departures.filter(func(d): return d["year"] == y)
		out["market"].sort_custom(func(a, b): return a["soldier"].best_ovr() > b["soldier"].best_ovr())
	return out


## One-line summary of a step for the Home card ("14 signings, 2 cuts, 1 trade, 3 stories").
func digest_summary(season: Season, step: String) -> String:
	var d := digest(season, step)
	var parts: Array[String] = []
	var add := func(n: int, one: String, many: String):
		if n > 0:
			parts.append("%d %s" % [n, one if n == 1 else many])
	add.call((d["picks"] as Array).size(), "pick", "picks")
	add.call((d["resigned"] as Array).size(), "re-signing", "re-signings")
	add.call((d["retired"] as Array).size(), "retirement", "retirements")
	add.call((d["market"] as Array).size(), "free agent", "free agents")
	add.call((d["signings"] as Array).size(), "signing", "signings")
	add.call((d["cuts"] as Array).size(), "cut", "cuts")
	add.call((d["trades"] as Array).size(), "trade", "trades")
	add.call((d["stories"] as Array).size(), "story", "stories")
	return ", ".join(parts) if not parts.is_empty() else "a quiet step"


## Stories about one soldier, newest first.
func for_soldier(id: int) -> Array:
	var out: Array = []
	for i in range(items.size() - 1, -1, -1):
		if int(items[i]["soldier_id"]) == id and id > 0:
			out.append(items[i])
	return out


func _year_room(season: Season, kind: String) -> bool:
	var n := 0
	for it in items:
		if it["year"] == season.year and it["kind"] == kind:
			n += 1
	return n < OFFSEASON_PER_KIND


func _wrote(season: Season, kind: String) -> bool:
	return items.any(func(it): return it["year"] == season.year and it["kind"] == kind)


## Every rivalry game moves morale; team-specific, playoff and hot games (and snapped streaks)
## make the wire, quiet divisional ones only while the week has room.
func _rivalry(season: Season, m: ScheduledMatch, when: String) -> void:
	var rv := season.rivalries
	var w := m.winner()
	var l := m.loser()
	var swing := rv.swing(w, l)
	for s in w.roster:
		s.add_morale(swing)
	for s in l.roster:
		s.add_morale(-swing)
	var rec := rv.record_of(w, l)
	var snapped_streak := int(rec.get("last", {}).get("snapped", 0))
	var notable := (rv.flags(w, l) & Rivalries.TEAM) != 0 or m.stage != Season.STAGE_REGULAR \
		or rv.heat_of(w, l) >= HOT_HEAT or snapped_streak >= Rivalries.STREAK_STORY
	if not notable and not _room(_counts, "rivalry"):
		return
	var games := "%d-%d" % [m.games_for(w), m.games_for(l)]
	var head := "%s: %s beat %s %s" % [rv.title(w, l), w.name, l.name, games]
	if snapped_streak >= Rivalries.STREAK_STORY:
		head = "%s snap a %d-game skid against %s, %s" % [w.name, snapped_streak, l.nickname, games]
	_add(season, when, "rivalry", [w.abbrev, l.abbrev], 0, head,
		"Bragging rights to the %s. %s. The %s will hear about this one until the rematch." % [
			w.nickname, rv.record_text(w, l), l.nickname])


func _rivalry_change(season: Season, when: String, e: Dictionary) -> void:
	var a := season.league.team_by_abbrev(e["a"])
	var b := season.league.team_by_abbrev(e["b"])
	if a == null or b == null:
		return
	if e["kind"] == &"formed":
		_add(season, when, "rivalry", [a.abbrev, b.abbrev], 0,
			"%s and %s: a new rivalry is born" % [a.name, b.name],
			"After a string of close games, playoff clashes and front-office dealings, the %s and %s now genuinely dislike each other." % [
				a.nickname, b.nickname])
	else:
		_add(season, when, "rivalry", [a.abbrev, b.abbrev], 0,
			"The %s-%s rivalry cools off" % [a.city, b.city],
			"The %s and %s have gone quiet on each other. Whatever this was, it is over for now." % [a.nickname, b.nickname])


func _played(t: Team, played: Array) -> bool:
	for m in played:
		if m.is_played() and m.involves(t):
			return true
	return false


func _room(counts: Dictionary, kind: String) -> bool:
	return int(counts.get(kind, 0)) < MAX_PER_KIND


## Marks story `kind` as written about `s` (`yr` = 0 for once-a-career). False if already written.
func _tag(s: Soldier, kind: String, yr: int) -> bool:
	if s.news_tags.has(kind) and (yr == 0 or int(s.news_tags[kind]) == yr):
		return false
	s.news_tags[kind] = yr if yr > 0 else 1
	return true


func _add(season: Season, when: String, kind: String, teams: Array, soldier_id: int, headline: String, body: String) -> void:
	items.append({"year": season.year, "when": when, "kind": kind, "headline": headline, "body": body,
		"teams": teams, "soldier_id": soldier_id})
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	season.market.story(season, kind, teams, headline)
	if items.size() > MAX_ITEMS:
		items = items.slice(items.size() - MAX_ITEMS)

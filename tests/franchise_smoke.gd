extends SceneTree
## Headless smoke test for the franchise menus: walks every tab and page through a full season.
##   godot --headless --path . --script res://tests/franchise_smoke.gd

var ok := true


func _init() -> void:
	var app = load("res://scenes/franchise.tscn").instantiate()
	root.add_child(app)
	await process_frame

	app.show_team_select()
	await process_frame
	app.start_franchise(4242, 2)
	_check(app.screen is LoadingScreen, "new franchise shows the loading screen")
	while not (app.screen is Control and app.screen.has_method("advance")):
		await process_frame
	await process_frame
	var hub = app.screen
	_check(hub.season.user_team() == hub.season.league.teams[2], "picked team is user team")
	_check(hub.season.league.teams.size() == 20, "20 teams")

	# Every tab builds, with tiles.
	for i in hub.TABS.size():
		hub.select_tab(i)
		await process_frame
		_check(hub._content.get_child_count() > 0, "tab %s builds" % hub.TABS[i])
	hub.cycle_tab(1)
	_check(hub.tab_index == 0, "tab cycling wraps")

	await _visit_pages(hub, "preseason")
	# A new franchise opens in preseason training camp.
	_check(hub.season.preseason_camp and hub.season.camp_open() and hub.season.week == 1, "new franchise starts in training camp")
	_check(hub._advance_text().begins_with("START 2026"), "advance button starts the season")
	_check(hub.season.draft.scout_points == 0, "no scouting during camp")
	hub.open("Drill", func(): return hub.pages.drill_pick(Stats.MENTALITY))
	await process_frame
	_check(_press(hub, "AGE"), "drill table sorts by column")
	await process_frame
	hub.page_stack.clear()
	hub.refresh()
	var pre_pool: Array = hub.season.user_team().roster.filter(func(x: Soldier): return not Progression.is_capped(x, Stats.MENTALITY) and not x.is_injured())
	var pre_guy: Soldier = pre_pool[0]
	# Drill pick confirm popup: Cancel does nothing, Send runs the drill.
	hub.pages._confirm_modal(hub.pages._drill_confirm_card(Stats.MENTALITY, pre_guy), "Send to drill", func():
		hub.season.run_drill(Stats.MENTALITY, pre_guy))
	await process_frame
	var cancel_btn := _find_button(hub, "Cancel")
	_check(cancel_btn != null, "drill confirm popup opens")
	cancel_btn.pressed.emit()
	await process_frame
	_check(not hub.season.camp.has_attended(pre_guy) and hub.get_node_or_null("ConfirmModal") == null, "cancel closes the popup")
	hub.pages._confirm_modal(hub.pages._drill_confirm_card(Stats.MENTALITY, pre_guy), "Send to drill", func():
		hub.season.run_drill(Stats.MENTALITY, pre_guy))
	await process_frame
	_find_button(hub, "Send to drill").pressed.emit()
	await process_frame
	_check(hub.season.camp.has_attended(pre_guy), "preseason drill runs")
	hub.open("Drill", func(): return hub.pages.drill_result(Stats.MENTALITY))
	await process_frame
	hub.advance()  # warns about the unused drills
	_check(hub.season.preseason_camp, "unused preseason drills warning holds camp")
	hub.advance()  # closes camp
	await process_frame
	_check(not hub.season.preseason_camp and hub.season.week == 1 and hub.season.phase == Season.PHASE_REGULAR, "camp closed, Week 1 next")
	for t in hub.season.league.teams:
		if not t.user_controlled:
			_check(hub.season.camp.drills_left(t) == 0, "%s ran preseason drills" % t.abbrev)
	# Scouting: press Scout buttons, then open a scouting report.
	hub.open("Scouting", hub.pages.scouting)
	await process_frame
	for i in 3:
		_check(_press(hub, "Scout"), "scout button")
		await process_frame
	var scouted: Prospect = null
	for pr in hub.season.draft.prospects:
		if pr.points > 0:
			scouted = pr
	_check(scouted != null and scouted.points == 3 and hub.season.draft.scout_points == Draft.POINTS_PER_WEEK - 3, "scouting spent points")
	hub.open("p", func(): return hub.pages.prospect(scouted))
	await process_frame
	_check(_press(hub, "Scout ("), "report scout button")
	await process_frame
	_check(scouted.points == 4, "scouted from report")
	hub.page_stack.clear()
	hub.refresh()
	# Auto-progress all.
	for so in hub.season.user_team().roster:
		so.skill_points += 3
	hub.open("Player Progression", hub.pages.progression)
	await process_frame
	_check(_press(hub, "Auto-progress all"), "auto-progress button")
	await process_frame
	var left := 0
	for so in hub.season.user_team().roster:
		left += so.skill_points
	_check(left < 3 * Team.ROSTER_SIZE, "auto-progress spent SP")
	hub.page_stack.clear()
	hub.refresh()
	hub.open("Training", hub.pages.training)
	hub.season.user_team().roster[0].intensity = Soldier.INTENSITY_HEAVY
	hub.replace("Training", hub.pages.training)
	await process_frame
	# Weekly training: Confirm & Train runs it now, shows results, and the week doesn't train twice.
	_check(not hub.season.user_trained(), "not trained yet this week")
	_check(_press(hub, "Confirm & Train"), "confirm & train button")
	await process_frame
	_check(hub.season.user_trained() and hub.season.user_training_report.size() == hub.season.user_team().roster.size(), "weekly training ran")
	_check(hub.page_stack[-1]["title"] == "Training Results", "training results page")
	var xp_after := 0
	for so in hub.season.user_team().roster:
		xp_after += so.xp + so.level * 100000
	hub.season.prepare_week()
	var xp_again := 0
	for so in hub.season.user_team().roster:
		xp_again += so.xp + so.level * 100000
	_check(xp_after == xp_again, "week doesn't train the user team twice")
	hub.page_stack.clear()
	hub.refresh()

	# Play the season week by week through the hub.
	var guard := 0
	var saw_matchup := false
	var watched := false
	while hub.season.phase != Season.PHASE_OFFSEASON and guard < 50:
		hub.advance()
		await process_frame
		await _wait_loading(hub)
		guard += 1
		if hub._on_matchup_page():
			saw_matchup = true
			if not watched:
				watched = true
				var wk: int = hub.season.week
				var m: ScheduledMatch = hub.user_match_this_week()
				hub.watch_match(m)
				await process_frame
				_check(hub.viewer != null and not hub._root.visible, "live viewer open")
				for i in 30:
					await process_frame
				hub.viewer.sim_to_end()
				hub.viewer.finished.emit(hub.viewer.engine.result())
				await process_frame
				_check(hub.simming and _find_loading(hub) != null and not hub._root.visible, "loading screen after the watched match")
				await _wait_loading(hub)
				_check(hub.viewer == null and hub._root.visible, "viewer closed back to the hub")
				_check(m.is_played() and hub.season.week == wk + 1, "watched match recorded, week advanced")
		if guard == 3:
			await _visit_pages(hub, "midseason")
	_check(saw_matchup and watched, "Play Week opens the matchup screen")
	_check(hub.season.champion != null, "season finished with a champion")
	await _visit_pages(hub, "offseason")

	var player: Soldier = hub.season.user_team().roster[0]
	hub.open(player.full_name(), func(): return hub.pages.player(player))
	await process_frame
	_check(hub.go_back(), "back pops page")
	_check(not hub.go_back(), "back at tab root does nothing")

	# Re-sign negotiation room: make a case, put an offer in, then walk away from the page.
	var talker: Soldier = hub.season.user_team().roster[1]
	talker.contract.years = 0
	hub.open_resign()
	await process_frame
	_check(_find_button(hub, "Negotiate") != null, "re-sign page has Negotiate")
	hub.pages.open_negotiation(talker)
	await process_frame
	var talks: Negotiation = hub.season.negotiations.get(talker.id)
	_check(talks != null and talks.is_open(), "negotiation started")
	var said := talks.talk.size()
	if not talks.arguments().is_empty():
		_check(_press(hub, talks.arguments()[0]["title"]), "argument button")
		await process_frame
	_check(_press(hub, "Make Offer"), "make offer button")
	await process_frame
	_check(talks.talk.size() > said, "the table logs the exchange")
	if talks.is_open():
		_check(_press(hub, "Accept "), "accept button")
		await process_frame
		_check(talks.state == Negotiation.SIGNED or talks.offer_error(talks.demand(2), 2) != "", "accepting his number signs him")
	hub.page_stack.clear()
	hub.refresh()
	await process_frame

	hub.advance()  # offseason: re-sign window -> free agency
	await process_frame
	_check(hub.season.offseason_stage == Season.OFF_FREE_AGENCY, "re-sign window closed into free agency")
	var d: Draft = hub.season.draft
	var user: Team = hub.season.user_team()
	_check(not d.is_complete(), "the draft waits for free agency")
	for t in hub.season.league.teams:
		if t != user:
			_check(t.roster.size() <= Team.OFFSEASON_MAX, "AI at or under the offseason max")
	_check(not hub.season.league.free_agents.is_empty(), "free agent pool")
	var fa_target: Soldier = hub.season.league.free_agents[0]
	hub.pages.open_offer(fa_target)
	await process_frame
	await _visit_pages(hub, "free agency")
	hub.open("Draft Room", hub.pages.draft_room)
	await process_frame
	var pick_at := d.next_pick
	await create_timer(0.3).timeout
	_check(d.next_pick == pick_at, "no draft clock during free agency")
	var guard_fa := 0
	while hub.season.offseason_stage == Season.OFF_FREE_AGENCY and guard_fa < 10:
		hub.advance()
		await process_frame
		guard_fa += 1
	_check(hub.season.phase == Season.PHASE_OFFSEASON, "can't skip the draft")
	_check(hub.season.offseason_stage == Season.OFF_DRAFT, "free agency days finished into the draft")
	var before_draft := user.roster.size()
	var my_picks: int = hub.season.trades.picks_of(hub.season, user).filter(func(a): return a["year"] == d.year).size()
	_check(d.is_started() and not d.is_complete(), "draft is open")
	hub.advance()  # blocked while picks remain
	await process_frame
	_check(hub.season.offseason_stage == Season.OFF_DRAFT, "advance blocked until the draft is done")
	# Draft clock: a CPU pick fires when its clock runs out; so does the user's (auto-pick).
	hub.open("Draft Room", hub.pages.draft_room)
	await process_frame
	var guard_clock := 0
	while not d.on_the_clock().user_controlled and guard_clock < 40:
		var at := d.next_pick
		hub.pages._clock_left = 0.05
		await create_timer(0.4).timeout
		_check(d.next_pick == at + 1, "CPU picks when the clock runs out")
		guard_clock += 1
	var user_before := user.roster.size()
	hub.pages._clock_left = 0.05
	await create_timer(0.4).timeout
	_check(user.roster.size() == user_before + 1, "user's clock expiring auto-picks")
	_check(_press(hub, "Sim to next pick") or d.on_the_clock().user_controlled, "sim to next pick button")
	await process_frame
	while not d.is_complete():
		if d.on_the_clock() == user:
			_check(_press(hub, "Draft"), "draft button")
		else:
			_check(_press(hub, "Sim "), "sim to pick button")
		await process_frame
	_check(user.roster.size() == before_draft + my_picks, "user drafted %d (%d)" % [my_picks, user.roster.size() - before_draft])
	await _visit_pages(hub, "post-draft")
	hub.advance()  # draft -> roster review
	await process_frame
	_check(hub.season.offseason_stage == Season.OFF_REVIEW, "roster review after the draft")
	await _visit_pages(hub, "roster review")
	while user.is_over_roster_limit():
		var cut: Soldier = user.bench().back()
		hub.pages.open_player(cut, 2)
		await process_frame
		_check(_press(hub, "Release"), "release button")
		await process_frame
		_check(_press(hub, "Confirm"), "confirm release")
		await process_frame
	_check(user.lineup.size() == 5, "user lineup intact after cuts")
	while hub.season.user_cap_error() != "" and user.roster.size() > Trades.MIN_ROSTER_OFFSEASON:
		hub.season.release_player(user, user.least_valuable())
	hub.advance()  # roster review -> training camp
	await process_frame
	_check(hub.season.offseason_stage == Season.OFF_CAMP, "roster review finished into training camp")
	var recap_steps: Array = hub.season.news.digest_steps(hub.season)
	_check(recap_steps == ["Re-signing", "FA Day 1", "FA Day 2", "FA Day 3", "Draft", "Roster Review"], "every offseason step has a recap, in order (%s)" % str(recap_steps))
	_check(hub._feed_items().any(func(it): return String(it["tag"]).begins_with("OFFSEASON RECAP")), "Home shows the latest recap card")
	for step in recap_steps:
		var st: String = step
		hub.open("Offseason Recap", func(): return hub.pages.offseason_recap(st))
		await process_frame
		_check(hub._content.get_child_count() > 0, "recap page builds: %s" % st)
		hub.go_back()
	hub.open_offseason_recap()
	await process_frame
	_check(hub.pages._recap_step == recap_steps[-1], "the recap card opens the latest step")
	hub.go_back()
	var drill_guy: Soldier = user.starters()[0]
	for x in user.starters():
		if not Progression.is_capped(x, Stats.ACCURACY):
			drill_guy = x
			break
	var ovr_before := drill_guy.best_ovr()
	var res: Dictionary = hub.season.run_drill(Stats.ACCURACY, drill_guy)
	_check(not res.is_empty() and res["points"] > 0, "user ran the accuracy drill")
	_check(hub.season.run_drill(Stats.HANDLING, drill_guy).is_empty(), "one drill per player")
	_check(drill_guy.best_ovr() >= ovr_before, "drill doesn't lower OVR")
	hub.open("Drill", func(): return hub.pages.drill_result(Stats.ACCURACY))
	await process_frame
	_check(hub._content.get_child_count() > 0, "drill result page builds")
	hub.go_back()
	await _visit_pages(hub, "training camp")
	hub.advance()  # warns about unused drills
	await process_frame
	_check(hub.season.offseason_stage == Season.OFF_CAMP and hub.season.year == 2026, "unused drills warning holds the season")
	hub.advance()  # start next season
	await process_frame
	_check(hub.simming and _find_loading(hub) != null, "loading screen for the new season")
	await _wait_loading(hub)
	for t in hub.season.league.teams:
		if t != user:
			_check(hub.season.camp.drills_left(t) < Camp.DRILLS.size(), "AI %s ran camp drills" % t.abbrev)
	_check(hub.season.year == 2027 and hub.season.phase == Season.PHASE_REGULAR, "next season started")
	_check(hub.season.draft.year == 2027 and hub.season.draft.scout_points == Draft.POINTS_PER_WEEK, "new draft class")
	await _visit_pages(hub, "new season")

	app.open_debug()
	await process_frame
	_check(app.debug_layer != null, "debug tools open")
	app.close_debug()
	await process_frame
	app.show_title()
	await process_frame

	print("Franchise smoke: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _wait_loading(hub) -> void:
	while hub.simming:
		await process_frame
	await process_frame
	_check(_find_loading(hub) == null or _find_loading(hub).is_queued_for_deletion(), "loading screen removed")


func _find_loading(hub) -> LoadingScreen:
	for c in hub.get_children():
		if c is LoadingScreen and not c.is_queued_for_deletion():
			return c
	return null


func _visit_pages(hub, phase: String) -> void:
	var p = hub.pages
	var builders := {
		"standings": p.standings, "schedule": p.schedule, "roster": p.roster, "progression": p.progression,
		"lineup": p.lineup, "training": p.training, "team_stats": p.team_stats, "leaders": p.leaders,
		"playoffs": p.playoffs, "rankings": p.team_rankings, "news": p.news, "sim_options": p.sim_options,
		"injuries": p.injuries, "scouting": p.scouting, "draft_room": p.draft_room, "mock_draft": p.mock_draft,
		"awards": p.awards, "teams": p.teams, "free_agents": p.free_agents, "contracts": p.contracts,
		"resign": p.resign, "retirements": p.retirements, "offer": p.offer,
		"legacy_champions": func():
			hub.legacy_pages.tab = "champions"
			return hub.legacy_pages.legacy(),
		"legacy_awards": func():
			hub.legacy_pages.tab = "awards"
			return hub.legacy_pages.legacy(),
		"legacy_records": func():
			hub.legacy_pages.tab = "records"
			hub.legacy_pages.records_team = ""
			return hub.legacy_pages.legacy(),
		"legacy_records_franchise": func():
			hub.legacy_pages.tab = "records"
			hub.legacy_pages.records_team = hub.season.user_team().abbrev
			var c: Control = hub.legacy_pages.legacy()
			hub.legacy_pages.records_team = ""
			return c,
		"legacy_record_page": func():
			var top := Records.player_seasons(hub.season, Records.PLAYER_STATS[0])
			return hub.legacy_pages.record_page(Records.PLAYER_STATS[0], top, "season"),
		"legacy_callsigns": func():
			hub.legacy_pages.tab = "callsigns"
			return hub.legacy_pages.legacy(),
		"legacy_callsign_proposals": func():
			var lg: League = hub.season.league
			var so: Soldier = hub.season.user_team().roster[0]
			var entry := {"callsign": so.callsign, "soldier": so, "team": hub.season.user_team(), "year": hub.season.year, "seasons": 7, "honors": ["2030 Season MVP"]}
			lg.callsign_proposals.append(entry)
			lg.retired_callsigns.append(entry)
			var c: Control = hub.legacy_pages.callsign_proposals()
			var banner: Control = hub.legacy_pages.banner_row(hub.season.user_team())
			lg.callsign_proposals.erase(entry)
			lg.retired_callsigns.erase(entry)
			if banner != null:
				banner.free()
			return c,
		"legacy_season": func():
			if hub.season.history.is_empty():
				return Control.new()
			return hub.legacy_pages.season_page(hub.season.history[-1]),
		"other_roster": func(): return p.team_roster(hub.season.league.teams[1]),
		"signings": func(): return p.signings("Test", hub.season.fa.history.slice(-5)),
		"training_camp": p.training_camp, "league_stats": p.league_stats, "negotiate": p.negotiate,
		"trade_center": p.trade_center, "trade_offers": p.trade_offers, "trade_block": p.trade_block, "trade_log": p.trade_log,
		"trade_center_deal": func():
			var ai: Team = p._ai_teams()[0]
			p._trade_partner = ai
			p._trade_get = [Trades.player_asset(ai.roster[0])]
			p._trade_give = hub.season.trades.picks_of(hub.season, hub.season.user_team()).slice(0, 1)
			var c: Control = p.trade_center()
			p._trade_give = []
			p._trade_get = []
			return c,
		"other_player_card": func():
			p._player_tab = 0
			return p.player(hub.season.league.teams[1].roster[0] if hub.season.league.teams[1] != hub.season.user_team() else hub.season.league.teams[2].roster[0]),
	}
	for tab in p.PLAYER_TABS.size():
		var ti: int = tab
		var ps: Soldier = hub.season.user_team().roster[0]
		builders["player_tab_%d" % ti] = func():
			p._player_tab = ti
			return p.player(ps)
	builders["player_stats_career"] = func():
		p._player_tab = 3
		p._stats_season = false
		var c: Control = p.player(hub.season.user_team().roster[0])
		p._stats_season = true
		return c
	for g in Camp.DRILLS:
		var gg: StringName = g
		builders["drill_pick_" + str(g)] = func(): return p.drill_pick(gg)
	var recap_draft: Draft = hub.season.draft if hub.season.draft.is_complete() else (hub.season.past_drafts[-1] if not hub.season.past_drafts.is_empty() else null)
	if recap_draft != null:
		builders["draft_recap"] = func(): return p.draft_recap(recap_draft)
	if not hub.season.draft.news.is_empty():
		var np: Prospect = hub.season.draft.news[-1]["prospect"]
		builders["news_prospect"] = func(): return p.prospect(np)
	if not hub.season.league.free_agents.is_empty():
		var fa_s: Soldier = hub.season.league.free_agents[0]
		builders["fa_player"] = func(): return p.player(fa_s)
	if not hub.season.retirements.is_empty():
		var r_s: Soldier = hub.season.retirements[0]["soldier"]
		builders["retired_player"] = func(): return p.player(r_s)
	builders["news_archive"] = p.news_archive
	for ni in [0, hub.season.newsroom.count() - 1]:
		var nii: int = ni
		builders["news_article_%d" % nii] = func(): return p.news_article(nii)
	p.retire_scope_team = false
	for key in builders:
		hub.open(key, builders[key])
		await process_frame
		_check(hub._content.get_child_count() > 0, "%s page builds (%s)" % [key, phase])
		hub.go_back()
	for w in [1, hub.season.week, hub.season.total_weeks()]:
		hub.open("Scores", func(): return p.scores(w))
		await process_frame
		hub.go_back()
	for m in hub.season.matches_for(hub.season.user_team()):
		var mm = m
		hub.open("m", func(): return p.recap(mm) if mm.is_played() else p.preview(mm))
		await process_frame
		hub.go_back()
	for i in hub.TABS.size():
		hub.select_tab(i)
		await process_frame
	hub.select_tab(0)


## Presses the first enabled button in the current page whose text starts with `prefix`.
func _press(hub, prefix: String) -> bool:
	var b := _find_button(hub._content, prefix)
	if b == null:
		return false
	b.pressed.emit()
	return true


func _find_button(n: Node, prefix: String) -> Button:
	if n is Button and not n.disabled and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var found := _find_button(c, prefix)
		if found != null:
			return found
	return null


func _check(cond: bool, msg: String) -> void:
	if not cond:
		ok = false
		printerr("  FAIL: ", msg)

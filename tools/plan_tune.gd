extends SceneTree
## Plays one full player-mode career in the real league with an automatic weekly plan and appends one JSON line of
## results, so many careers can be run in parallel and compared (see the weekly plan tuning in #138).
##   godot --headless --path . --script res://tools/plan_tune.gd -- age=21 style=smart seed=7 seasons=8 skill=0.8 \
##       archetype=marksman vote=0 out=C:/path/results.jsonl
## Styles: grind (practice 2 + study 2), study (study 3 + practice 1), balanced (1 each of practice, study, brand,
## spa), nospa (practice 3 + study 1), smart (grinds on the Green Team, spas and builds brand once he plays).
## vote=1 retires him at the end and plays on to the Hall of Fame vote.

var args := {"age": "21", "style": "smart", "seed": "1", "seasons": "8", "skill": "0.8", "archetype": "marksman", "vote": "0", "out": ""}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if args.has("boost"):
		WeeklyPlan.xp_boost = float(args["boost"])
	if args.has("wgain"):
		Wear.age_gain = float(args["wgain"])
	if args.has("wspa"):
		Wear.spa_per_level = float(args["wspa"])
	if args.has("agecap"):
		Combine.age_cap_bonus = float(args["agecap"])
	if args.has("costs"):
		var c := String(args["costs"]).split(",")
		for i in c.size():
			WeeklyPlan.star_costs[i + 1] = float(c[i])
	var age := int(args["age"])
	var seed_value := int(args["seed"])
	var skill := float(args["skill"])
	var arch := StringName(args["archetype"])
	var season := Season.new_franchise(seed_value)
	var heads: Array = FaceSpec.db()["heads"].keys()
	heads.sort()
	season.player_mode = true
	season.player_archetype = arch
	season.player = PlayerCareer.create_soldier(season.league.next_soldier_id, "Sim", "Player", "Simmer%d" % seed_value, heads[seed_value % heads.size()], seed_value, arch, age)
	season.league.next_soldier_id += 1
	season.player_combine = Combine.make(arch, age)
	for g in Combine.DRILL_ORDER:
		var sc := {}
		for t in Combine.drill_tasks(g):
			sc[t["stat"]] = skill
		season.player_combine.record_try(g, sc)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	season.player_combine.finalize(season.player, rng)
	season.player_combine_done = true
	PlayerDraft.begin(season)
	var entry_ovr := season.player.best_ovr()
	var proj: int = season.player_prospect.projected_rank
	PlayerDraft.run(season)
	if season.player_draft_state == PlayerDraft.STATE_OFFERS:
		PlayerDraft.sign_undrafted(season, PlayerDraft.undrafted_offers(season)[0])
	var p := season.player
	var rows: Array = []
	var seasons := int(args["seasons"])
	var fatigue_sum := 0.0
	var fatigue_n := 0
	var raises := 0
	var stories := 0
	for n in seasons:
		var fat_sum := 0.0
		var fat_n := 0
		var started := 0
		while season.phase != Season.PHASE_OFFSEASON:
			_take_deals(season)
			_set_plan(season, false)
			if p.skill_points > 0:
				Progression.auto_spend(p, Scheme.best_role(p.stats))
			season.sim_week()
			if p.fatigue > 0.0 or true:
				fat_sum += p.fatigue
				fat_n += 1
		var sm := PlayerGrade.summary(PlayerGrade.log_for(season, season.year))
		rows.append({"year": season.year, "age": p.age, "ovr": p.best_ovr(), "dev": p.dev, "study": snappedf(p.study_progress, 0.1),
			"brand": snappedf(p.brand, 0.1), "wear": snappedf(p.wear, 0.1), "base": p.base_ovr(), "caps": _cap_avg(p), "cash": p.cash, "deals": p.deals.size(), "raises": raises, "stories": stories, "games": sm["games"], "avg": snappedf(sm["avg"], 0.1), "fatigue": snappedf(fat_sum / maxf(1.0, float(fat_n)), 0.1),
			"on": "green" if season.user_team().green_team.has(p) else "roster", "hof": snappedf(PlayerLegacy.trajectory(season)["score"], 0.1)})
		print("season %d done t=%d" % [n, Time.get_ticks_msec() / 1000])
		_take_deals(season)
		stories += _answer_stories(season)
		if _raise_cap(season):
			raises += 1
		fatigue_sum += fat_sum
		fatigue_n += fat_n
		if n == seasons - 1:
			break
		_set_plan(season, true)
		var guard := 0
		while season.offseason_stage != Season.OFF_DONE and guard < 30:
			season.advance_offseason()
			guard += 1
		season.start_next_season()
	var stars: Array = []
	for note in season.player_notes:
		if String(note["text"]).begins_with("Your study paid off"):
			stars.append("%d.w%d" % [note["year"], note["week"]])
	var result := {"age": age, "style": args["style"], "seed": seed_value, "skill": skill, "boost": WeeklyPlan.xp_boost, "agecap": Combine.age_cap_bonus, "costs": WeeklyPlan.star_costs.values(), "arch": String(arch), "entry_ovr": entry_ovr,
		"proj": proj, "pick": season.player_pick, "talent": p.talent, "stars": stars, "seasons": rows, "milestones": season.player_milestones.size()}
	if int(args["vote"]) == 1:
		_wait_vote(season, result)
	var line := JSON.stringify(result)
	var out := String(args["out"])
	if out == "":
		print(line)
	else:
		var f := FileAccess.open(out, FileAccess.READ_WRITE) if FileAccess.file_exists(out) else FileAccess.open(out, FileAccess.WRITE)
		f.seek_end()
		f.store_line(line)
		f.close()
	quit(0)


func _wait_vote(season: Season, result: Dictionary) -> void:
	if season.phase != Season.PHASE_OFFSEASON:
		season.sim_to_end_of_season()
	PlayerLegacy.retire(season)
	var v := PlayerLegacy.simulate_to_vote(season)
	result["verdict"] = String(v)
	result["final_hof"] = snappedf(float(PlayerLegacy.final_score(season)["score"]), 0.1)


## Signs every offer that fits (best tier first), like a player who takes what he is given.
func _take_deals(season: Season) -> void:
	var p := season.player
	if p.offers.is_empty():
		return
	var offers: Array = p.offers.duplicate()
	offers.sort_custom(func(a, b): return int(Gear.brand(a["brand"])["tier"]) > int(Gear.brand(b["brand"])["tier"]))
	for o in offers:
		Sponsors.accept(season, o)


## Takes the first choice of every waiting story (a mentor teaches the group with the most room). Returns how many.
func _answer_stories(season: Season) -> int:
	var p := season.player
	var n := 0
	for st in p.stories.duplicate():
		var key := String(st["choices"][0]["key"])
		if st["kind"] == "mentor":
			var best := Stats.ACCURACY
			for g in Stats.UPGRADABLE_GROUPS:
				if p.group_cap(g) - p.group_rating(g) > p.group_cap(best) - p.group_rating(best):
					best = g
			key = String(best)
		Stories.choose(season, st, key)
		n += 1
	return n


## Sets a camp special on the first capped group, then raises the biggest available cap. Returns true if one was raised.
func _raise_cap(season: Season) -> bool:
	var p := season.player
	var ready := CapRaise.eligible_groups(season)
	if ready.is_empty():
		return false
	if p.camp_focus == &"":
		Stories.set_camp_special(season, ready[0])
	var best: StringName = ready[0]
	for g in ready:
		if CapRaise.size(season, g) > CapRaise.size(season, best):
			best = g
	return not CapRaise.apply(season, best).is_empty()


func _cap_avg(p: Soldier) -> float:
	var total := 0.0
	for g in Stats.UPGRADABLE_GROUPS:
		total += p.group_cap(g)
	return snappedf(total / float(Stats.UPGRADABLE_GROUPS.size()), 0.1)


## The automatic plan for the chosen style (camp: the offseason plan).
func _set_plan(season: Season, camp: bool) -> void:
	var p := season.player
	var style := String(args["style"])
	var where: StringName = PlayerCoach.status(season)["where"] if not camp else &""
	var plan := {}
	match style:
		"grind":
			plan = {WeeklyPlan.PRACTICE: 2, WeeklyPlan.STUDY: 2}
		"study":
			plan = {WeeklyPlan.STUDY: 3, WeeklyPlan.PRACTICE: 1}
		"balanced":
			plan = {WeeklyPlan.PRACTICE: 1, WeeklyPlan.STUDY: 1, WeeklyPlan.BRAND: 1, WeeklyPlan.SPA: 1}
		"nospa":
			plan = {WeeklyPlan.PRACTICE: 3, WeeklyPlan.STUDY: 1}
		_:
			if where == PlayerCoach.WHERE_STARTER:
				plan = {WeeklyPlan.PRACTICE: 1, WeeklyPlan.STUDY: 1, WeeklyPlan.BRAND: 1, WeeklyPlan.SPA: 1}
			elif where == PlayerCoach.WHERE_BENCH:
				plan = {WeeklyPlan.PRACTICE: 2, WeeklyPlan.STUDY: 1, WeeklyPlan.SPA: 1}
			else:
				plan = {WeeklyPlan.PRACTICE: 2, WeeklyPlan.STUDY: 2}
	if camp:
		var camp_plan := {WeeklyPlan.PRACTICE: 4, WeeklyPlan.STUDY: 4}
		if style == "balanced" or style == "smart":
			camp_plan = {WeeklyPlan.PRACTICE: 3, WeeklyPlan.STUDY: 3, WeeklyPlan.BRAND: 2}
		p.camp_plan = camp_plan
		p.camp_plan_confirmed = true
	else:
		p.plan = plan
		p.plan_confirmed = true

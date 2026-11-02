extends "res://scripts/season/news/news_stories.gd"
## The game-week article: facts, angles scored by weight, then headline, dek, lede and body.

## Everything the writer may say about `m`, from the user's side. Also fills the issue facts.
func _game_facts(m: ScheduledMatch) -> Dictionary:
	var r: MatchResult = m.result
	var ui := 0 if m.home == _us else 1
	var oi := 1 - ui
	var them: Team = m.opponent_of(_us)
	var g := {"m": m, "r": r, "them": them, "home": ui == 0, "won": r.winner() == _us,
		"gw": r.score[ui], "gl": r.score[oi], "stage": m.stage}
	var games: Array = []
	for game in r.games:
		games.append({"mode": game["mode"], "us": float(game["score"][ui]), "them": float(game["score"][oi]),
			"won": int(game["winner"]) == ui})
	g["games"] = games
	for key in ["tdm", "koth", "sd"]:
		g[key] = {}
	for gm in games:
		match gm["mode"]:
			MatchEngine.MODE_TDM:
				g["tdm"] = gm
			MatchEngine.MODE_KOTH:
				g["koth"] = gm
			MatchEngine.MODE_SUDDEN_DEATH:
				g["sd"] = gm
	var ours: Array = []
	var theirs: Array = []
	for sid in r.box:
		var line: Dictionary = r.box[sid]
		var so: Soldier = _ids.get(sid)
		if so == null:
			continue
		var e := {"s": so, "line": line, "imp": MatchResult.impact(line)}
		if int(line["team"]) == ui:
			ours.append(e)
		else:
			theirs.append(e)
	var by_imp := func(a, b): return a["imp"] > b["imp"]
	ours.sort_custom(by_imp)
	theirs.sort_custom(by_imp)
	g["ours"] = ours
	g["theirs"] = theirs
	g["star"] = ours[0] if not ours.is_empty() else {}
	g["their_star"] = theirs[0] if not theirs.is_empty() else {}
	# A struggling regular: one of our three best-rated starters with the weakest line.
	g["goat"] = {}
	var stars := _top_ovr(_us, 3)
	for i in range(ours.size() - 1, 0, -1):
		var e: Dictionary = ours[i]
		if stars.has(e["s"]) and int(e["line"]["kills"]) * 2 <= int(e["line"]["deaths"]) + 2:
			g["goat"] = e
			break
	var hill: Dictionary = {}
	for e in ours:
		if float(e["line"].get("hill_s", 0.0)) > float(hill.get("line", {}).get("hill_s", 0.0)):
			hill = e
	g["hill_hero"] = hill
	g["clutch"] = null
	g["clutch_ours"] = false
	if not g["sd"].is_empty() and not r.rounds.is_empty():
		var last: Dictionary = r.rounds[-1]
		var cid := int(last.get("clutch_soldier_id", -1))
		if cid >= 0 and _ids.has(cid):
			g["clutch"] = _ids[cid]
			g["clutch_ours"] = int(last["winner"]) == ui
	g["mvp"] = _ids.get(r.mvp_id)
	var w := m.shown_weather()
	g["weather"] = w
	g["gap"] = them.team_ovr() - _us.team_ovr()
	g["edge"] = _us.scheme.edge_vs(them.scheme)
	g["koth_edge"] = _us.scheme.edge_vs(them.scheme, true)
	g["rival"] = _s.rivalries.title(_us, them) if _s.rivalries.is_rivalry(_us, them) else ""
	g["named_rival"] = g["rival"] != "" and not String(g["rival"]).ends_with("Division Rivalry")
	var inj: Array = _s.last_injuries.filter(func(i): return i["team"] == _us and i["soldier"] is Soldier)
	inj.sort_custom(func(a, b): return int(a["weeks"]) > int(b["weeks"]))
	g["injuries"] = inj
	var res := _results(_us)
	g["run"] = _run(res)
	g["prev_run"] = _run(res.slice(0, res.size() - 1))
	g["wins"] = res.count("W")
	g["losses"] = res.count("L")

	_f["them_city"] = _city(them)
	_f["them_nick"] = _nick(them)
	_f["them_poss"] = _poss(_nick(them))
	_f["them_full"] = _full(them)
	_f["them_abbr"] = them.abbrev
	_f["them_record"] = _record(them)
	_f["them_scheme"] = them.scheme.display_name
	_f["venue"] = m.field().venue
	_f["at_venue"] = "at %s" % _f["venue"] if g["home"] else "in %s" % _f["them_city"]
	_f["home_or_road"] = "at home" if g["home"] else "on the road"
	_f["gs"] = "%d-%d" % [g["gw"], g["gl"]]
	_f["gs_w"] = "%d-%d" % [maxi(g["gw"], g["gl"]), mini(g["gw"], g["gl"])]
	_f["w_city"] = _f["us_city"] if g["won"] else _f["them_city"]
	_f["l_city"] = _f["them_city"] if g["won"] else _f["us_city"]
	_f["w_nick"] = _f["us_nick"] if g["won"] else _f["them_nick"]
	_f["l_nick"] = _f["them_nick"] if g["won"] else _f["us_nick"]
	_f["stage_name"] = _s.week_label(m.week).to_lower() if m.stage != Season.STAGE_REGULAR else "regular season"
	_f["gap"] = str(absi(g["gap"]))
	_f["rival"] = g["rival"]
	_f["weather"] = w.label().to_lower()
	var t: Dictionary = g["tdm"]
	if not t.is_empty():
		_f["tdm_us"] = str(int(t["us"]))
		_f["tdm_them"] = str(int(t["them"]))
		_f["tdm_w"] = "%d-%d" % [maxf(t["us"], t["them"]), minf(t["us"], t["them"])]
	var k: Dictionary = g["koth"]
	if not k.is_empty():
		_f["koth_us"] = _secs(k["us"])
		_f["koth_them"] = _secs(k["them"])
		_f["koth_w"] = "%s to %s" % [_secs(maxf(k["us"], k["them"])), _secs(minf(k["us"], k["them"]))]
		_f["koth_lose_hold"] = _secs_words(minf(k["us"], k["them"]))
		_f["koth_win_hold"] = _secs_words(maxf(k["us"], k["them"]))
	var d: Dictionary = g["sd"]
	if not d.is_empty():
		_f["sd_w"] = "%d-%d" % [maxf(d["us"], d["them"]), minf(d["us"], d["them"])]
		_f["sd_rounds"] = _num(int(d["us"] + d["them"]))
	var st: Dictionary = g["star"]
	if not st.is_empty():
		_f["k"] = str(int(st["line"]["kills"]))
		_f["d"] = str(int(st["line"]["deaths"]))
		_f["a"] = str(int(st["line"]["assists"]))
		_f["hs"] = str(int(st["line"].get("headshots", 0)))
		_f["star_last"] = st["s"].last_name
	return g

## How much each angle the facts support is worth (higher leads). Keys are angle ids.
func _game_angles(g: Dictionary) -> Dictionary:
	var a := {}
	var won: bool = g["won"]
	var tdm: Dictionary = g["tdm"]
	var koth: Dictionary = g["koth"]
	var sd: Dictionary = g["sd"]
	if g["stage"] != Season.STAGE_REGULAR:
		a["playoffs"] = 95.0 if g["stage"] == Season.STAGE_FINAL else 85.0
	if won and int(g["gl"]) == 1 and not tdm.is_empty() and not tdm["won"]:
		a["comeback"] = 68.0
	if not won and int(g["gw"]) == 1 and not tdm.is_empty() and tdm["won"]:
		a["collapse"] = 66.0
	if won and int(g["gl"]) == 0:
		a["sweep"] = 40.0 + clampf((tdm["us"] - tdm["them"]) if not tdm.is_empty() else 0.0, 0.0, 20.0)
	if not won and int(g["gw"]) == 0:
		a["swept"] = 46.0 + clampf((tdm["them"] - tdm["us"]) if not tdm.is_empty() else 0.0, 0.0, 20.0)
	if g["clutch"] != null:
		a["clutch"] = 72.0 if absf(sd["us"] - sd["them"]) <= 1.0 else 56.0
	if won and int(g["gap"]) >= 4:
		a["upset_win"] = 54.0 + float(g["gap"]) * 2.0
	if not won and int(g["gap"]) <= -4:
		a["upset_loss"] = 54.0 - float(g["gap"]) * 2.0
	var run: Array = g["run"]
	var prev: Array = g["prev_run"]
	if won and int(run[1]) >= 3:
		a["streak_win"] = 38.0 + int(run[1]) * 6.0
	if not won and int(run[1]) >= 2:
		a["streak_loss"] = 40.0 + int(run[1]) * 8.0
	if int(prev[1]) >= 3 and prev[0] != run[0]:
		a["snapped"] = 50.0 + int(prev[1]) * 3.0
	if g["rival"] != "":
		a["rivalry"] = 58.0 if g["named_rival"] else 36.0
	if not g["star"].is_empty():
		var k := int(g["star"]["line"]["kills"])
		if k >= 18:
			a["star"] = 30.0 + k
	if not g["injuries"].is_empty() and int(g["injuries"][0]["weeks"]) >= 3:
		a["injury"] = 42.0 + int(g["injuries"][0]["weeks"]) * 3.0
	if not g["weather"].is_clear():
		a["weather"] = 30.0 + g["weather"].level * 12.0
	if won and int(g["wins"]) == 1 and int(g["losses"]) >= 1:
		a["first_win"] = 52.0 + int(g["losses"]) * 4.0
	if not koth.is_empty() and minf(koth["us"], koth["them"]) < 25.0:
		a["hill"] = 34.0
	if not won and float(g["edge"]) < 0.0:
		a["scheme"] = 34.0
	if not g["goat"].is_empty():
		a["goat"] = 22.0 if won else 32.0
	a.merge(_story_scores(g))
	# Don't lead with the same thing two weeks running, and let an angle that has been leading a lot rest.
	var last: String = memory.get("lede", "")
	if a.has(last):
		a[last] -= 25.0
	var recent: Array = memory.get("ledes", [])
	for k in a:
		a[k] = float(a[k]) - 10.0 * recent.count(k) + _r.randf_range(-6.0, 6.0)
	return a


func _ranked(a: Dictionary) -> Array:
	var keys := a.keys()
	keys.sort_custom(func(x, y): return a[x] > a[y])
	return keys

# --- the game-week article --------------------------------------------------------------


func _game_article(m: ScheduledMatch, wk: int) -> Dictionary:
	var g := _game_facts(m)
	var scores := _game_angles(g)
	var order := _ranked(scores)
	var lede: String = order[0] if not order.is_empty() else ("win" if g["won"] else "loss")
	var fmt := _pick_format(g, lede, scores)
	var art := {"kind": KIND_GAME, "section": _section(g), "angles": [lede] + order.slice(1, 4),
		"dateline": _city(m.home), "format": fmt}
	art["headline"] = _headline(lede, g)
	art["dek"] = _dek(lede, g)
	if STORIES.has(lede):
		art["story"] = _story_record(lede, g)
	var plan := _plan(fmt, g, lede)
	var body: Array = []
	var quote := {}
	for step: Array in plan:
		var text := ""
		match step[0]:
			"lede":
				text = _lede(lede, g)
			"story":
				text = _story_text("body", lede, g) if STORIES.has(lede) else ""
			"match":
				text = _narrative(g, lede)
			"star":
				if not (g["star"] as Dictionary).is_empty():
					var sp := _star_para(g)
					text = sp[0]
					quote = sp[1]
			"why":
				text = _secondary(g, order, lede)
			"sides":
				var sides: Array = []
				for id: String in order.slice(1, 4):
					if STORIES.has(id) and float(scores[id]) >= 40.0:
						sides.append(_story_text("side", id, g))
				text = _para(sides)
			"records":
				text = _records_para(m)
			"callback":
				text = _pick_callback(g)
			"take":
				text = _take(g, step[0] == "take" and fmt == "column")
			"table":
				text = _standings_para(wk)
			"mood":
				text = _buzz_para()
			"numbers":
				text = _numbers_para(g)
			"next":
				text = _para([_preview_para(wk), _pick_line(_s.next_match_for(_us))])
		if text.strip_edges() != "":
			body.append(("%s: %s" % [String(step[1]), text]) if String(step[1]) != "" else text)
	art["body"] = body
	art["pull_quote"] = quote
	art["sidebar"] = _box_sidebar(g)
	art["roundup"] = _roundup(wk)
	return art


## How a game article is laid out. Feature is the full story; notebook is a lede and a few labeled notes;
## column leads with the writer's opinion and skips the game-by-game; numbers leans on the box score.
const FORMAT_WEIGHTS := {"feature": 45.0, "notebook": 22.0, "column": 20.0, "numbers": 13.0}
const NOTE_LABELS := {"match": "THE MATCH", "star": "THE STAR", "why": "BEHIND THE RESULT", "sides": "ALSO", "records": "RECORD WATCH",
	"table": "THE TABLE", "mood": "THE MOOD", "next": "NEXT UP", "numbers": "BY THE NUMBERS"}


func _pick_format(g: Dictionary, lede: String, scores: Dictionary) -> String:
	var w := FORMAT_WEIGHTS.duplicate()
	if g["stage"] != Season.STAGE_REGULAR or lede in ["playoffs", "clutch", "comeback", "collapse", "rivalry"]:
		w["feature"] += 40.0
		w["notebook"] *= 0.4
	if STORIES.has(lede):
		w["feature"] += 12.0
	if float(scores.get(lede, 0.0)) < 45.0:
		w["notebook"] += 15.0
		w["feature"] -= 15.0
	match _persona():
		"numbers":
			w["numbers"] += 20.0
		"oldschool":
			w["feature"] += 10.0
		_:
			w["column"] += 15.0
	var recent: Array = memory.get("formats", [])
	for k in w:
		w[k] = maxf(1.0, float(w[k]) * pow(0.4, recent.count(k)))
	var total := 0.0
	for k in w:
		total += float(w[k])
	var roll := _r.randf() * total
	var pick := "feature"
	for k in w:
		roll -= float(w[k])
		if roll <= 0.0:
			pick = k
			break
	recent.append(pick)
	memory["formats"] = recent.slice(maxi(0, recent.size() - 2))
	return pick


## The article's paragraphs in order: [[step, label]]. Labels (notebook and numbers formats) lead a paragraph.
func _plan(fmt: String, g: Dictionary, lede: String) -> Array:
	var plan: Array = []
	match fmt:
		"notebook":
			var pool := ["match", "star", "why", "sides", "records", "table", "mood"]
			var keep := _r.randi_range(2, 4)
			plan.append(["lede", ""])
			plan.append(["story", ""])
			var chosen: Array = []
			while chosen.size() < keep and not pool.is_empty():
				chosen.append(pool.pop_at(_r.randi_range(0, pool.size() - 1)))
			for k in ["match", "star", "why", "sides", "records", "table", "mood"]:
				if chosen.has(k):
					plan.append([k, NOTE_LABELS[k]])
			plan.append(["callback", ""])
			plan.append(["next", NOTE_LABELS["next"]])
		"column":
			plan = [["take", ""], ["lede", ""], ["story", ""], ["why", ""], ["star", ""], ["callback", ""], ["next", ""]]
		"numbers":
			plan = [["lede", ""], ["story", ""], ["numbers", NOTE_LABELS["numbers"]], ["star", NOTE_LABELS["star"]], ["records", NOTE_LABELS["records"]],
				["table", NOTE_LABELS["table"]], ["callback", ""], ["next", NOTE_LABELS["next"]]]
		_:
			plan = [["lede", ""], ["story", ""], ["match", ""], ["star", ""], ["why", ""], ["sides", ""], ["records", ""], ["callback", ""],
				["take", ""], ["table", ""], ["mood", ""], ["next", ""]]
	return plan


## Team totals from the box score: kills, damage and the best lines on our side.
func _numbers_para(g: Dictionary) -> String:
	var tk := 0
	var ok := 0
	var td := 0
	var od := 0
	for e: Dictionary in g["ours"]:
		tk += int(e["line"]["kills"])
		td += int(e["line"].get("damage", 0))
	for e: Dictionary in g["theirs"]:
		ok += int(e["line"]["kills"])
		od += int(e["line"].get("damage", 0))
	var top: Array = (g["ours"] as Array).slice(0, 3).map(func(e): return "%s %d-%d-%d" % [_short_name(e["s"]), int(e["line"]["kills"]), int(e["line"]["deaths"]), int(e["line"]["assists"])])
	var ex := {"tk": str(tk), "ok": str(ok), "td": str(td), "od": str(od), "top": ", ".join(top)}
	var out: Array = [_g("nb_kills", ["The {us_nick} finished with {tk} kills to the {them_nick}'s {ok}.", "Kills: {tk} for the {us_nick}, {ok} for the {them_nick}.",
		"{tk} kills against {ok}: that was the match for the {us_nick}."], ex)]
	if td > 0 or od > 0:
		out.append(_g("nb_dmg", ["Damage was {td} to {od}.", "On damage it was {td} to {od}.", "The damage sheet read {td} to {od}."], ex))
	if not top.is_empty():
		out.append(_g("nb_top", ["Best lines (K-D-A): {top}.", "The lines that mattered, kills-deaths-assists: {top}."], ex))
	return _para(out)


## The league records this match broke, one sentence each ("" when it broke none). Plain text, so a record
## never shifts the phrases picked for other articles.
func _records_para(m: ScheduledMatch) -> String:
	var out: Array = []
	for rec: Dictionary in m.records:
		var value := StatRegistry.format(rec, rec["value"])
		var scope := "playoff " if rec["phase"] == StatRegistry.PHASE_PLAYOFFS else ""
		if int(rec["id"]) < 0:
			out.append("The %s now own the league's longest %s: %s %s." % [rec["name"],
				"winning streak" if rec["stat"] == "win_streak" else "losing streak", value, rec["noun"]])
		else:
			out.append("%s's %s %s is a new %ssingle-match league record." % [rec["name"], value, rec["noun"], scope])
	return " ".join(out)


func _section(g: Dictionary) -> String:
	if g["stage"] != Season.STAGE_REGULAR:
		return "%s %s" % [_f["us_nick"].to_upper(), _s.week_label(g["m"].week).to_upper()]
	return "%s - %s" % [_f["us_nick"].to_upper(), _f["when"].to_upper()]


func _headline(angle: String, g: Dictionary) -> String:
	if STORIES.has(angle):
		return _story_text("headline", angle, g)
	var star_last: String = g["star"]["s"].last_name if not g["star"].is_empty() else _f["us_nick"]
	var ex := {"star": star_last, "n": _num(int(g["run"][1])).capitalize(),
		"clutch": g["clutch"].last_name if g["clutch"] != null else star_last}
	match angle:
		"playoffs":
			if g["won"]:
				return _g("h_po_w", ["{us_nick} Survive, Advance", "{star} Carries {us_nick} Past {them_nick}",
					"On to the Next One: {us_nick} Dispatch {them_city}", "{us_nick} Keep the Season Alive"], ex)
			return _g("h_po_l", ["Season Over: {them_nick} End {us_poss} Run", "The Ride Ends in {them_city}",
				"{them_nick} Close the Book on {us_nick}", "Out: {us_nick} Fall {gs} to {them_nick}"], ex)
		"comeback":
			return _g("h_comeback", ["Down a Game, {us_nick} Climb Back", "{us_nick} Rally Past {them_nick}",
				"{star} Leads Comeback Over {them_city}", "Lost the Opener, Won the Night"], ex)
		"collapse":
			return _g("h_collapse", ["{us_nick} Let One Slip", "Fast Start, Hard Fall for {us_nick}",
				"Early Lead Evaporates in {gs} Loss", "{them_nick} Rally Past Stunned {us_nick}"], ex)
		"sweep":
			return _g("h_sweep", ["{us_nick} Sweep {them_nick}", "Clean Sheet: {us_nick} Roll {them_city}",
				"{star} Leads Rout of {them_nick}", "Two and Done for {us_nick}"], ex)
		"swept":
			return _g("h_swept", ["{them_nick} Sweep {us_nick}", "Blanked in {them_city}" if not g["home"] else "Blanked at Home",
				"{us_nick} Never Show Up Against {them_nick}", "Nothing Goes Right for {us_nick}"], ex)
		"clutch":
			if g["clutch_ours"]:
				return _g("h_clutch_w", ["{clutch} Wins It Alone", "Last One Standing: {clutch}",
					"{clutch} Clutch Lifts {us_nick} Past {them_nick}", "{clutch}, With Everything on the Line"], ex)
			return _g("h_clutch_l", ["{clutch} Breaks {us_poss} Hearts", "One {them_nick} Soldier Too Many",
				"{clutch} Clutch Sinks {us_nick}", "Last Man Standing Wasn't Ours"], ex)
		"upset_win":
			return _g("h_upset_w", ["{us_nick} Stun {them_nick}", "Nobody Gave Them a Chance",
				"Upset in {w_city}: {us_nick} Topple {them_nick}", "{us_nick} Punch Above Their Weight"], ex)
		"upset_loss":
			return _g("h_upset_l", ["{them_nick} Stun {us_nick}", "An Upset Nobody Saw Coming",
				"{us_nick} Tripped Up by {them_city}", "Favorites No More"], ex)
		"streak_win":
			return _g("h_streak_w", ["{n} Straight for {us_nick}", "The Streak Hits {n}",
				"{us_nick} Keep Rolling", "{us_nick} Make It {n} in a Row"], ex)
		"streak_loss":
			return _g("h_streak_l", ["Skid Reaches {n} for {us_nick}", "{us_nick} Drop {n} Straight",
				"Free Fall Continues for {us_nick}", "Losing Has Become a Habit"], ex)
		"snapped":
			if g["won"]:
				return _g("h_snap_w", ["Skid Over: {us_nick} Win Again", "{us_nick} Finally Stop the Bleeding",
					"Losing Streak Snapped in {w_city}"], ex)
			return _g("h_snap_l", ["Streak Snapped in {them_city}" if not g["home"] else "Streak Snapped at Home",
				"{them_nick} End {us_poss} Run", "All Good Things: {us_nick} Fall to {them_nick}"], ex)
		"rivalry":
			return _g("h_rival", ["{us_nick} Win {rival} Round" if g["won"] else "{them_nick} Take {rival} Round",
				"Bad Blood, {w_nick} Win" , "Rivalry Night Goes to {w_city}"], ex)
		"star":
			return _g("h_star", ["{star}'s Night", "{star} Unstoppable" if g["won"] else "{star} Not Enough",
				"{k} Kills for {star}", "{star} Puts on a Show"], ex)
		"injury":
			var inj: Soldier = g["injuries"][0]["soldier"]
			return _g("h_injury", ["%s Hurt in %s" % [inj.last_name, "Win" if g["won"] else "Loss"],
				"Costly Night: %s Goes Down" % inj.last_name, "%s Out, Questions In" % inj.last_name], ex)
		"weather":
			return _g("h_weather", ["{w_nick} Weather the {weather}", "Mud, Misery and a {gs_w} {w_nick} Win",
				"{w_nick} Handle the Elements Best"], ex)
		"first_win":
			return _g("h_first", ["Finally: {us_nick} Get Their First", "In the Win Column at Last",
				"{us_nick} Break Through"], ex)
		"hill":
			return _g("h_hill", ["King of the Hill" if g["koth"]["won"] else "Pushed Off the Hill",
				"{w_nick} Own the Hill", "The Hill Decides It"], ex)
		"scheme":
			return _g("h_scheme", ["Outschemed by {them_nick}", "{them_scheme} Solves {us_nick}",
				"Wrong Plan, Wrong Result"], ex)
		"goat":
			return _g("h_goat", ["{us_nick} Fall {gs} to {them_nick}", "{them_nick} Top {us_nick}"] if not g["won"]
				else ["{us_nick} Win Despite Themselves", "Ugly but Effective"], ex)
	if g["won"]:
		return _g("h_win", ["{us_nick} Top {them_nick} {gs_w}", "{us_nick} Handle {them_city}", "{star} Lifts {us_nick}"], ex)
	return _g("h_loss", ["{them_nick} Top {us_nick} {gs_w}", "{us_nick} Come Up Short", "Not Enough in {them_city}"], ex)


func _dek(angle: String, g: Dictionary) -> String:
	if STORIES.has(angle):
		return _story_text("dek", angle, g)
	var won: bool = g["won"]
	var lead := ""
	match angle:
		"playoffs":
			lead = _g("d_po_w", ["A {gs_w} win {at_venue} buys one more week.", "Survive and advance: {gs_w} over the {them_nick}.",
				"The season goes on after a {gs_w} win {at_venue}."]) if won else _g("d_po_l", [
				"A {gs_w} loss {at_venue} ends the {year} season.", "The {stage_name} were as far as it went.",
				"The {them_nick} end it, {gs_w}."])
		"comeback":
			lead = _g("d_comeback", ["Down a game after Team Deathmatch, the {us_nick} took the next two.",
				"They lost the opener {tdm_w} and won the night anyway."])
		"collapse":
			lead = _g("d_collapse", ["They won the opener {tdm_w}. Then it got away.", "One game up, then two games down."])
		"sweep":
			lead = _g("d_sweep", ["Two games, and {them_city} never led in either.", "Team Deathmatch {tdm_w}, then the hill, then done.",
				"A {gs_w} sweep {at_venue}."])
		"swept":
			lead = _g("d_swept", ["Outplayed in both games {at_venue}.", "Team Deathmatch went {tdm_w} the wrong way, and it didn't get better.",
				"Swept, {gs_w}, {at_venue}."])
		"upset_win":
			lead = _g("d_upset_w", ["Rated {gap} points worse, the {us_nick} won anyway.", "The ratings had the {them_nick} by {gap}. The scoreboard didn't."])
		"upset_loss":
			lead = _g("d_upset_l", ["Rated {gap} points better, the {us_nick} lost anyway.", "The {them_nick} came in {gap} points worse on paper and left with the win."])
		"streak_win", "streak_loss":
			lead = _g("d_streak", ["That's {n} straight.", "Make it {n} in a row."], {"n": _num(int(g["run"][1]))})
		"snapped":
			lead = _g("d_snap", ["The run ends at {n}.", "{n_cap} straight, and then this."] if not won
				else ["The skid ends at {n}.", "{n_cap} straight losses, and then a win."],
				{"n": _num(int(g["prev_run"][1])), "n_cap": _num(int(g["prev_run"][1])).capitalize()})
		"clutch":
			lead = _g("d_clutch", ["{c} was the last man standing in Sudden Death.", "It came down to {c}, alone, in the final round."],
				{"c": g["clutch"].last_name})
		"first_win":
			lead = _g("d_first", ["Win number one, at last.", "The first win of the year comes over the {them_nick}."])
		"rivalry":
			lead = _g("d_rival", ["Another chapter of the {rival}, and this one went to {w_city}.", "{w_city} takes this round of the {rival}."]) \
				if g["named_rival"] else _g("d_div", ["A division game, and it went to {w_city}.", "{w_city} wins the division matchup."])
		"star":
			lead = _g("d_star", ["{s}: {k} kills, {d} deaths, {a} assists.", "{k} kills from {s}."], {"s": g["star"]["s"].last_name})
		"injury":
			var inj: Dictionary = g["injuries"][0]
			lead = "%s is out %s with %s." % [(inj["soldier"] as Soldier).last_name, _plural(int(inj["weeks"]), "week"), _a(String(inj["name"]).to_lower())]
		"weather":
			lead = _g("d_weather", ["Played in {weather}, won by {w_city}.", "{weather_cap}, and {w_city} handled it better."],
				{"weather_cap": _cap_first(_f["weather"])})
		"hill":
			lead = _g("d_hill", ["The hill went {koth_w}, and that told the story."])
		"scheme":
			lead = _g("d_scheme", ["The {them_scheme} had an answer for the {us_scheme}."])
	if lead == "":
		lead = _g("d_plain", ["{w_city} wins it {gs_w}.", "A {gs_w} {result} {at_venue}."], {"result": "win" if won else "loss"})
	# One supporting fact the lead didn't already use.
	var extra := ""
	var st: Dictionary = g["star"]
	var ts: Dictionary = g["their_star"]
	if angle != "star" and not st.is_empty() and (won or ts.is_empty() or int(st["line"]["kills"]) >= int(ts["line"]["kills"])):
		extra = _g("d_x_star", ["{s} had {k} kills.", "{s} led the way with {k} kills.", "{k} kills for {s}."], {"s": st["s"].last_name})
	elif not won and not ts.is_empty():
		extra = _g("d_x_their", ["{s} had {tk} kills for {them_city}.", "{them_city} got {tk} kills from {s}."],
			{"s": _short_name(ts["s"]), "tk": str(int(ts["line"]["kills"]))})
	var status := ""
	if g["stage"] == Season.STAGE_REGULAR:
		var rank: int = _rank_of(_us)
		status = _g("d_status", ["They're {record}.", "That makes it {record}, {rk} in the league.", "Record: {record}."],
			{"rk": _ord(rank)})
	return _para([lead, extra, status])

## The opening paragraph, built around the lead angle.
func _lede(angle: String, g: Dictionary) -> String:
	if STORIES.has(angle):
		return _story_text("lede", angle, g)
	var star: Dictionary = g["star"]
	var sw: String = _who(star["s"]) if not star.is_empty() else ""
	var ex := {"star": sw, "n": _num(int(g["run"][1])), "pn": _num(int(g["prev_run"][1]))}
	var opener := ""
	match angle:
		"playoffs":
			if g["won"]:
				opener = _g("l_po_w", [
					"The {us_nick} are still playing. A {gs_w} win over the {them_full} {at_venue} sends them through the {stage_name}, and nobody in that locker room pretended it was comfortable.",
					"Win or go home, and the {us_nick} won. They beat the {them_full} {gs_w} {at_venue} in the {stage_name}, and the season gets at least one more week.",
					"Playoff matches are supposed to be tight, and this one was tight enough to feel in your teeth. The {us_nick} came out the other side, {gs_w} over {them_city} in the {stage_name}."], ex)
			else:
				opener = _g("l_po_l", [
					"It ends here. The {them_full} beat the {us_nick} {gs_w} {at_venue} in the {stage_name}, and the {year} season is over for {us_city}.",
					"There is no next week. The {us_nick} lost {gs_w} to the {them_full} in the {stage_name}, and the questions that followed this club all season will follow it into the offseason.",
					"A season that promised more ended with less. The {them_nick} were better {at_venue}, winning {gs_w} and sending the {us_nick} home from the {stage_name}."], ex)
		"comeback":
			opener = _g("l_comeback", [
				"Down a game and looking every bit of it, the {us_nick} found something. They lost Team Deathmatch {tdm_w}, then took the next two to beat the {them_full} {gs_w} {at_venue}.",
				"For one game, this looked like a long night. The {them_nick} won the opener {tdm_w} and the {us_nick} looked a step slow. Then everything turned, and {us_city} won the next two for a {gs_w} comeback.",
				"The {us_nick} spent the first game getting run over and the rest of the night getting even. A {tdm_w} loss in Team Deathmatch became a {gs_w} win over {them_city}."], ex)
		"collapse":
			opener = _g("l_collapse", [
				"For one game the {us_nick} looked like the better team. They won Team Deathmatch {tdm_w}, then lost the next two and the match, {gs_w}, to the {them_full} {at_venue}.",
				"A lead is only worth what you do with it. The {us_nick} took the opener from the {them_nick} {tdm_w} and did nothing with it, dropping the last two games in a {gs_w} loss.",
				"It started the way the {us_nick} drew it up and ended the way they feared. Up a game after a {tdm_w} Team Deathmatch win, they lost the next two to {them_city}."], ex)
		"sweep":
			opener = _g("l_sweep", [
				"Two games, no drama. The {us_nick} swept the {them_full} {at_venue}, and it was every bit as one-sided as 2-0 sounds.",
				"The {us_nick} didn't need a third game. They handled the {them_full} 2-0 {at_venue}, in control almost from the opening spawn.",
				"Clean. The {us_nick} took both games from the {them_nick} {home_or_road} and never gave {them_city} a reason to believe."], ex)
		"swept":
			opener = _g("l_swept", [
				"There isn't much to salvage from this one. The {them_full} swept the {us_nick} {at_venue}, and {us_city} never led in either game.",
				"Two games, two losses, and not a lot of fight in between. The {them_nick} beat the {us_nick} 2-0 {at_venue}.",
				"The {us_nick} were second to everything {at_venue}. The {them_full} won both games and were rarely threatened."], ex)
		"clutch":
			var c: Soldier = g["clutch"]
			ex["clutch"] = _who_role(c)
			if g["clutch_ours"]:
				opener = _g("l_clutch_w", [
					"It came down to one round, and then it came down to one soldier. {clutch} was the last {us_nick} player standing in the final round of Sudden Death, and he won it, and the match, {gs_w}.",
					"When the last round of Sudden Death got down to its final seconds, the {us_nick} had one soldier left. It was {clutch}, and it was enough: {us_city} beat {them_city} {gs_w}.",
					"Every team says it wants the ball in its best player's hands. The {us_nick} got their wish in the final round against the {them_nick}, and {clutch} closed it out for a {gs_w} win."], ex)
			else:
				opener = _g("l_clutch_l", [
					"The {us_nick} had the numbers in the final round and still lost it. {clutch} was the last {them_nick} soldier alive, and he finished the job for a {gs_w} {them_city} win.",
					"One player beat the {us_nick} tonight. With the match on the final round of Sudden Death, {clutch} cleaned up alone, and the {them_full} won {gs_w}.",
					"This one will sting for a while. The {us_nick} were a round from a win before {clutch} took the final round of Sudden Death by himself, and the {them_nick} took it {gs_w}."], ex)
		"upset_win":
			opener = _g("l_upset_w", [
				"On paper, the {them_full} were {gap} points better. On the field, the {us_nick} won {gs_w}, and paper doesn't get a vote.",
				"Nobody outside the building expected this. The {us_nick} beat a {them_nick} roster rated {gap} points higher, {gs_w} {at_venue}.",
				"The ratings said {them_city} by a mile. The {us_nick} didn't read them, beating the {them_full} {gs_w} {home_or_road}."], ex)
		"upset_loss":
			opener = _g("l_upset_l", [
				"This was supposed to be the easy one. The {us_nick} came in rated {gap} points better than the {them_full} and left with a {gs_w} loss.",
				"Some losses are understandable. This was not one of them: the {them_nick}, rated {gap} points worse on paper, beat the {us_nick} {gs_w} {at_venue}.",
				"The {us_nick} had every advantage that can be measured before a match and lost anyway, {gs_w} to the {them_full}."], ex)
		"streak_win":
			opener = _g("l_streak_w", [
				"Make it {n} straight. The {us_nick} beat the {them_full} {gs_w} {at_venue}, and the winning streak is now the story of this season.",
				"The {us_nick} keep stacking them. A {gs_w} win over {them_city} {home_or_road} runs the streak to {n}.",
				"Another week, another win. The {us_nick} handled the {them_nick} {gs_w}, that's {n} in a row, and the rest of the league has noticed."], ex)
		"streak_loss":
			opener = _g("l_streak_l", [
				"That's {n} straight. The {us_nick} lost {gs_w} to the {them_full} {at_venue}, and the skid has stopped being a blip.",
				"The losing doesn't stop. The {them_nick} beat the {us_nick} {gs_w} {home_or_road}, the {n}th straight defeat for {us_city}.",
				"{n} matches, {n} losses. The {us_nick} fell to the {them_full} {gs_w}, and the answers aren't coming any faster than the wins."], ex)
		"snapped":
			if g["won"]:
				opener = _g("l_snap_w", [
					"{pn} straight losses, and then, finally, a win. The {us_nick} beat the {them_full} {gs_w} {at_venue}.",
					"The skid is over. After {pn} straight defeats, the {us_nick} beat {them_city} {gs_w} and can breathe again."], ex)
			else:
				opener = _g("l_snap_l", [
					"The streak is over at {pn}. The {them_full} beat the {us_nick} {gs_w} {at_venue}.",
					"{pn} straight wins, and then a reminder that nothing lasts. The {them_nick} beat the {us_nick} {gs_w} {home_or_road}."], ex)
		"rivalry":
			opener = _g("l_rival", [
				"{rival} matches are never just one result in the standings, and this one won't be forgotten quickly in {l_city}. The {w_nick} won it {gs_w}.",
				"There was an edge to this one before anyone spawned in. The {w_full} took the latest round of {rival}, {gs_w}, {at_venue}.",
				"Rivalry week delivered. The {w_nick} beat the {l_nick} {gs_w} {at_venue}, and the other side heard about it."], ex.merged({"w_full": _f["us_full"] if g["won"] else _f["them_full"]}))
		"star":
			opener = _g("l_star", [
				"{star} was the best player on the field and it wasn't especially close: {k} kills, {d} deaths and {a} assists as the {us_nick} %s the {them_full} {gs_w}." % ("beat" if g["won"] else "fell to"),
				"Some nights are about one player. This was {star}'s, a {k}-kill performance %s." % ("that carried the {us_nick} past the {them_nick} {gs_w}" if g["won"] else "that still wasn't enough in a {gs_w} loss to the {them_nick}"),
				"{k} kills. That's the number from {star}, and %s" % ("the {us_nick} needed every one of them in a {gs_w} win over {them_city}." if g["won"] else "it still couldn't save the {us_nick} in a {gs_w} loss to {them_city}.")], ex)
		"injury":
			var e: Dictionary = g["injuries"][0]
			var hurt: Soldier = e["soldier"]
			ex["hurt"] = _who_role(hurt)
			ex["inj"] = String(e["name"]).to_lower()
			ex["a_inj"] = _a(String(e["name"]).to_lower())
			ex["wk"] = _plural(int(e["weeks"]), "week")
			opener = _g("l_injury", [
				"The result was a %s. The news was worse: {hurt} left with {a_inj} and is expected to miss {wk}." % ("{gs_w} win over the {them_nick}" if g["won"] else "{gs_w} loss to the {them_nick}"),
				"Whatever the {us_nick} took from {them_city}, they lost more. {hurt} went down with {a_inj}, and the timetable is {wk}.",
				"{hurt} is out {wk} with {a_inj}, and that will be the headline long after anyone remembers the %s to {them_city}." % ("{gs_w} win" if g["won"] else "{gs_w} loss")], ex)
		"weather":
			opener = _g("l_weather", [
				"It was a {weather} night {at_venue}, the kind that turns long sightlines into guesses, and the {w_nick} handled it better. They won {gs_w}.",
				"Nobody plays their best in {weather}, but somebody has to win. The {w_full} did, {gs_w}.",
				"In {weather} {at_venue}, the {w_nick} adapted and the {l_nick} didn't. {w_city} won {gs_w}."], ex.merged({"w_full": _f["us_full"] if g["won"] else _f["them_full"]}))
		"first_win":
			ex["l"] = _num(int(g["losses"]))
			opener = _g("l_first", [
				"It took a while, but the {us_nick} are in the win column. They beat the {them_full} {gs_w} {at_venue} after opening the year with {l} losses.",
				"{l} losses, then a win. The {us_nick} finally have one, {gs_w} over {them_city}, and it was a long time coming."], ex)
		"hill":
			var held: bool = g["koth"]["won"]
			opener = _g("l_hill", [
				"The hill decided this one. The %s held it {koth_win_hold} to {them_or_us}'s {koth_lose_hold}, and the {w_nick} won {gs_w}." % ("{us_nick}" if held else "{them_nick}"),
				"King of the Hill wasn't a contest. One side held for {koth_win_hold}; the other managed {koth_lose_hold}. The {w_nick} won {gs_w}."], ex.merged({"them_or_us": _f["them_city"] if held else _f["us_city"]}))
		"scheme":
			opener = _g("l_scheme", [
				"The {them_nick} came in with the right plan and the {us_nick} did not. {them_city}'s {them_scheme} was a step ahead of the {us_scheme} all night in a {gs_w} {them_nick} win.",
				"You could see this one coming at the whiteboard. The {us_nick} ran the {us_scheme} into a {them_scheme} that was built to beat it, and lost {gs_w}."], ex)
	if opener == "":
		if g["won"]:
			opener = _g("l_win", [
				"The {us_nick} did what they needed to {at_venue}, beating the {them_full} {gs_w}.",
				"A win is a win, and the {us_nick} got one, {gs_w} over the {them_full} {home_or_road}.",
				"No style points, but the {us_nick} beat the {them_full} {gs_w} {at_venue}."], ex)
		else:
			opener = _g("l_loss", [
				"The {us_nick} lost {gs_w} to the {them_full} {at_venue}, and it was the kind of loss that leaves questions.",
				"Not this week. The {them_full} beat the {us_nick} {gs_w} {home_or_road}.",
				"The {them_nick} were the better side {at_venue}, beating the {us_nick} {gs_w}."], ex)
	return _cap_first(opener)


func _side(ours: bool) -> String:
	return _f["us_nick"] if ours else _f["them_nick"]

## Game by game: how the match actually went.
func _narrative(g: Dictionary, lede: String) -> String:
	var parts: Array = []
	var prev := -1
	for i in g["games"].size():
		var gm: Dictionary = g["games"][i]
		var won: bool = gm["won"]
		var ex := {"w": _side(won), "l": _side(not won), "ord": _ord_word(i + 1)}
		var lead := ""
		if i > 0:
			lead = _g("n_same", ["Then", "After that,", "And again,", "It kept going that way."]) if (1 if won else 0) == prev \
				else _g("n_swing", ["Then it swung.", "The momentum turned.", "That didn't last.", "Then the match changed."])
		prev = 1 if won else 0
		var sentence := ""
		match gm["mode"]:
			MatchEngine.MODE_TDM:
				ex["sc"] = "%d-%d" % [maxf(gm["us"], gm["them"]), minf(gm["us"], gm["them"])]
				var margin := absf(gm["us"] - gm["them"])
				if margin <= 6:
					sentence = _g("n_tdm_close", [
						"Team Deathmatch went to the wire, the {w} edging it {sc}.",
						"The {w} won a Team Deathmatch that was even almost to the finish, {sc}.",
						"Team Deathmatch was a trade of kill for kill until the {w} got to 50 first, {sc}."], ex)
				elif margin >= 20:
					sentence = _g("n_tdm_rout", [
						"Team Deathmatch was a rout, {sc} for the {w}.",
						"The {w} ran away with Team Deathmatch, {sc}, and the {l} never found their footing.",
						"The {l} were outgunned in Team Deathmatch, {sc}."], ex)
				else:
					sentence = _g("n_tdm", [
						"The {w} took Team Deathmatch {sc}.",
						"Team Deathmatch went to the {w}, {sc}.",
						"The {w} won the opening Team Deathmatch {sc}, pulling away in the back half."], ex)
			MatchEngine.MODE_KOTH:
				ex["hw"] = _secs_words(maxf(gm["us"], gm["them"]))
				ex["hl"] = _secs(minf(gm["us"], gm["them"]))
				var hh: Dictionary = g["hill_hero"]
				ex["hero"] = ""
				if won and not hh.is_empty() and float(hh["line"].get("hill_s", 0.0)) >= 30.0:
					ex["hero"] = " %s spent %s on the point himself." % [_who(hh["s"]), _secs(float(hh["line"]["hill_s"]))]
				if minf(gm["us"], gm["them"]) >= 90.0:
					sentence = _g("n_koth_close", [
						"King of the Hill came down to the last seconds of contested time, the {w} getting to two minutes with the {l} at {hl}.{hero}",
						"King of the Hill was a war for the point, the {w} winning it while the {l} sat at {hl}.{hero}"], ex)
				else:
					sentence = _g("n_koth", [
						"The {w} took King of the Hill, holding for {hw} while the {l} managed {hl}.{hero}",
						"King of the Hill belonged to the {w}, {hw} on the point to {hl} for the {l}.{hero}",
						"The {w} controlled the hill, getting to two minutes with the {l} stuck at {hl}.{hero}"], ex)
			MatchEngine.MODE_SUDDEN_DEATH:
				ex["sc"] = "%d-%d" % [maxf(gm["us"], gm["them"]), minf(gm["us"], gm["them"])]
				ex["rounds"] = _num(int(gm["us"] + gm["them"]))
				if lede == "clutch":
					sentence = _g("n_sd_clutch", [
						"That left Sudden Death to decide it, and it took all {rounds} rounds, {sc}.",
						"Sudden Death went the distance, {rounds} rounds, before it was settled {sc}."], ex)
				elif absf(gm["us"] - gm["them"]) <= 1.0:
					sentence = _g("n_sd_close", [
						"Sudden Death went {rounds} rounds, the {w} taking it {sc}.",
						"It went to Sudden Death, and the decider was as tight as it gets: {sc} for the {w} over {rounds} rounds."], ex)
				else:
					sentence = _g("n_sd", [
						"In Sudden Death, the {w} were sharper, winning {sc}.",
						"The {w} took Sudden Death {sc} without much argument.",
						"Sudden Death went to the {w}, {sc}."], ex)
		parts.append(_para([lead, sentence.substr(0, 1).to_lower() + sentence.substr(1)
			if not lead.ends_with(".") and lead != "" and (sentence.begins_with("The ") or sentence.begins_with("In ")) else sentence]))
	if g["games"].size() >= 1 and g["games"].size() < 3 and g["gw"] + g["gl"] == 2:
		parts.append(_g("n_no3", ["No decider needed.", "There was no third game.", ""]))
	return _para(parts)

## The best player's line, his season in context and his quote. Returns [paragraph, pull_quote].
func _star_para(g: Dictionary) -> Array:
	var e: Dictionary = g["star"]
	var s: Soldier = e["s"]
	var line: Dictionary = e["line"]
	var ex := {"star": _who_role(s), "last": s.last_name}
	var extras: Array = []
	if int(line.get("headshots", 0)) >= 5:
		extras.append("%s of his kills were headshots" % _num(int(line["headshots"])))
	if float(line.get("hill_s", 0.0)) >= 40.0:
		extras.append("he spent %s on the hill" % _secs(float(line["hill_s"])))
	if int(line.get("clutches", 0)) > 0:
		extras.append("he won %s clutch round%s" % [_num(int(line["clutches"])), "" if int(line["clutches"]) == 1 else "s"])
	ex["extra"] = ""
	ex["a"] = _plural(int(line["assists"]), "assist")
	ex["dd"] = _plural(int(line["deaths"]), "death")
	var tail := (", and ".join(extras) + ".") if not extras.is_empty() else ""
	var first := ""
	if g["won"]:
		first = _g("s_line_w", [
			"{star} led the way with {k} kills, {dd} and {a}.",
			"{star} was the engine: {k} kills against {d} deaths, plus {a}.",
			"The box score belongs to {star}, who went {k}-{d} with {a}.",
			"{star} did most of the damage: {k} kills, {d} deaths and {a}.",
			"If you read one line of the stat sheet, make it {star}'s: {k}-{d}, plus {a}."], ex)
	else:
		first = _g("s_line_l", [
			"{star} did his part, {k} kills against {d} deaths with {a}.",
			"{star} was the lone bright spot: {k}-{d}, {a}.",
			"It wasn't on {star}, who finished {k}-{d} with {a}."], ex)
	first = _para([first, tail])
	var sk := int(_line(s).get("kills", 0))
	var rank := _league_rank(s, "kills")
	ex["sk"] = str(sk)
	ex["rk"] = _ord(rank)
	var second := ""
	if rank == 1:
		second = _g("s_season_1", ["His {sk} kills this season lead the league.", "Nobody in the league has more kills this year than his {sk}."], ex)
	elif rank <= 8:
		second = _g("s_season_top", ["That's {sk} kills on the season, {rk} in the league.", "He's up to {sk} kills, {rk} in the league."], ex)
	elif int(_line(s).get("matches", 0)) >= 3:
		second = _g("s_season", ["He has {sk} kills on the year.", "That brings him to {sk} kills for the season."], ex)
	var their: Dictionary = g["their_star"]
	var third := ""
	if not g["won"] and not their.is_empty():
		ex["them_star"] = _who_role(their["s"])
		ex["tk"] = str(int(their["line"]["kills"]))
		third = _g("s_their", [
			"The difference was on the other side, where {them_star} had {tk} kills for {them_city}.",
			"{them_star} was the best player on the field for the {them_nick}, with {tk} kills.",
			"The {them_nick} got {tk} kills from {them_star}, and the {us_nick} had no answer for him."], ex)
	var sit := "star_win" if g["won"] else "star_loss"
	if g["clutch"] == s and g["clutch_ours"]:
		sit = "clutch"
	var q := _quote(s, sit, g)
	ex["q"] = q
	var said := _g("s_said", ["\"{q}\" {last} said.", "\"{q}\" {last} said afterward.", "\"{q}\" {last} said after the match."], ex)
	return [_para([first, second, third, said]), {"text": q, "who": s.display_name(), "team": _us.abbrev}]

## The critical angles the lede didn't use: the scheme, the lineup, injuries, the opponent.
func _secondary(g: Dictionary, order: Array, lede: String) -> String:
	var out: Array = []
	var won: bool = g["won"]
	# The scheme question, carried week to week.
	var doubt: Dictionary = memory.get("scheme_doubt", {})
	if float(g["edge"]) < 0.0 or (not g["koth"].is_empty() and float(g["koth_edge"]) < 0.0 and not g["koth"]["won"]):
		var again: bool = doubt.get("scheme", "") == _us.scheme.display_name and _s.week - int(doubt.get("week", -99)) <= 5
		var ex := {"times": _num(int(doubt.get("count", 0)) + 1), "nth": _ord_word(int(doubt.get("count", 0)) + 1)}
		if not won and lede != "scheme":
			if again:
				out.append(_g("x_scheme_again", [
					"And here we go again with the {us_scheme}. That's {times} times in a few weeks it has been the wrong answer against the opponent's shape, and at some point the staff has to stop calling it bad luck.",
					"For the {nth} time recently, the {us_scheme} looked like the wrong tool. The {them_scheme} had the better angles all night, which is the kind of thing a staff is supposed to see coming."], ex))
			else:
				out.append(_g("x_scheme", [
					"It's fair to ask about the plan. The {us_scheme} gave up the matchup to the {them_scheme} before a shot was fired, and the {us_nick} played like a team that knew it.",
					"The scheme deserves a look, too. The {them_scheme} is a bad matchup for the {us_scheme}, and the {us_nick} ran it anyway.",
					"Somebody on the staff should explain the {us_scheme} here. Against a {them_scheme}, it ceded the best lanes, and the {them_nick} lived in them."], ex))
		elif won:
			out.append(_g("x_scheme_won", [
				"The {us_nick} won in spite of the matchup: the {us_scheme} is a poor fit against the {them_scheme}, and they made it work anyway.",
				"Worth noting: on paper the {them_scheme} beats the {us_scheme}. The {us_nick} won through it, not because of it."]))
		doubt = {"week": _s.week, "scheme": _us.scheme.display_name, "count": (int(doubt.get("count", 0)) + 1) if again else 1}
		memory["scheme_doubt"] = doubt
	# The struggling regular, and who is sitting behind him. The paper remembers who it has
	# called out, and a second bad night in a few weeks reads like a pattern, not a one-off.
	var hurt_before: Dictionary = memory.get("injured", {})
	var goat: Dictionary = g["goat"]
	if not goat.is_empty():
		var gs: Soldier = goat["s"]
		var calls: Dictionary = memory.get("goat", {})
		var past: Array = (calls.get(str(gs.id), []) as Array).filter(func(w): return _s.week - int(w) <= 4)
		var ex := {"goat": _who_role(gs), "gk": str(int(goat["line"]["kills"])), "gd": str(int(goat["line"]["deaths"])),
			"ovr": str(gs.best_ovr()), "role": _role(gs), "nth": _ord_word(past.size() + 1), "span": _num(maxi(2, _s.week - int(past[0]) + 1)) if not past.is_empty() else ""}
		if past.is_empty():
			out.append(_g("x_goat", [
				"{goat} has to be better. He went {gk}-{gd}, and a {ovr}-rated starter cannot hand the other side that many free kills.",
				"Then there's {goat}, who finished {gk}-{gd}. That's not good enough from one of the best-rated players on the roster.",
				"The quiet problem was {goat}: {gk} kills, {gd} deaths. When a {ovr} plays like that, the math gets hard."], ex))
		else:
			out.append(_g("x_goat_again", [
				"And it's {goat} again: {gk}-{gd}, his {nth} rough night in {span} weeks. One bad game is noise. This is starting to look like a trend.",
				"{goat} went {gk}-{gd}. That's the {nth} time in {span} weeks this column has had to write that sentence about a {ovr}-rated {role}.",
				"The {us_nick} keep waiting on {goat}, and he keeps not arriving: {gk}-{gd} this week, the {nth} poor line in {span} weeks."], ex))
		past.append(_s.week)
		calls[str(gs.id)] = past
		memory["goat"] = calls
		var alt: Soldier = null
		for b in _us.bench():
			if b.injury_weeks <= 0 and not hurt_before.has(str(b.id)) and b.best_ovr() >= gs.best_ovr() - 1 \
					and (alt == null or b.best_ovr() > alt.best_ovr()):
				alt = b
		if alt != null:
			var benched: Dictionary = memory.get("bench", {})
			var times := int(benched.get(str(alt.id), 0)) + 1
			benched[str(alt.id)] = times
			memory["bench"] = benched
			var bx := {"alt": _who_role(alt), "aovr": str(alt.best_ovr()), "times": _num(times)}
			if times == 1:
				out.append(_g("x_bench", [
					"Meanwhile {alt}, rated {aovr}, watched from the bench. Somebody will have to explain that.",
					"And {alt} ({aovr} OVR) never got off the bench, which is a choice."], bx))
			else:
				out.append(_g("x_bench_again", [
					"{alt}, rated {aovr}, sat again. That's {times} weeks now he has watched a lower-rated player struggle in his spot.",
					"The {aovr}-rated {alt} was on the bench for it, again. Whatever the staff sees in practice, it isn't showing up on Sundays."], bx))
	# Injuries the lede didn't cover.
	var inj: Array = g["injuries"]
	for i in inj.size():
		if i == 0 and lede == "injury":
			continue
		var e: Dictionary = inj[i]
		out.append(_g("x_injury", [
			"{hurt} left with {a_inj} and will miss {wk}.",
			"{hurt} is out {wk} with {a_inj}.",
			"Add {hurt} to the injury report: {a_inj}, {wk}."],
			{"hurt": _who_role(e["soldier"]), "inj": String(e["name"]).to_lower(), "a_inj": _a(String(e["name"]).to_lower()),
				"wk": _plural(int(e["weeks"]), "week")}))
		if i >= 1:
			break
	# Someone back from injury.
	for e in g["ours"]:
		var s: Soldier = e["s"]
		if hurt_before.has(str(s.id)):
			out.append(_g("x_back", [
				"{who} was back from his {inj} and finished {k}-{d}.",
				"Good news on {who}, who returned from the {inj} with {k} kills."],
				{"who": _who_role(s), "inj": String(hurt_before[str(s.id)]).to_lower(), "k": str(int(e["line"]["kills"])),
					"d": str(int(e["line"]["deaths"]))}))
			break
	var now_hurt := {}
	for s in _us.roster:
		if s.injury_weeks > 0:
			now_hurt[str(s.id)] = s.injury_name
	memory["injured"] = now_hurt
	# The rivalry's running score.
	if g["rival"] != "" and lede != "rivalry":
		var series := _series(g["them"])
		if g["named_rival"]:
			out.append(_g("x_rival", ["It was a {rival} game, too, and {ser}.", "In {rival} terms, {ser}."],
				{"ser": series if series != "" else "it was the first meeting"}))
		elif series != "":
			out.append(_g("x_div", ["It was a division game, and {ser}.", "It was a division game; {ser}.", "The division was on the line, and {ser}.", "Inside the division, {ser}.", "Division rivals again: {ser}."],
				{"ser": series}))
	if not g["weather"].is_clear() and lede != "weather" and g["weather"].level >= 1:
		out.append(_g("x_weather", ["The {weather} didn't help anyone's aim.", "It was played in {weather}, and it showed in the accuracy numbers."]))
	return _para(out.slice(0, 4))

## Where the club stands now, and what moved.
func _standings_para(wk: int) -> String:
	var row := _row(_us)
	if row == null or wk > _s.regular_weeks or _s.phase == Season.PHASE_OFFSEASON:
		return ""
	var ex := {"rank": _ord(row.rank), "streak": row.streak}
	var was := int(memory.get("rank", 0))
	var drows := _div_rows(_us)
	var leader: StandingRow = drows[0] if not drows.is_empty() else row
	var gb := ((leader.wins - row.wins) + (row.losses - leader.losses)) / 2.0
	ex["gb"] = ("%d" % int(gb)) if is_equal_approx(gb, roundf(gb)) else ("%.1f" % gb)
	ex["leader"] = _nick(leader.team)
	ex["dpos"] = _ord(drows.find(row) + 1)
	ex["left"] = _num(_s.regular_weeks - wk)
	ex["left_w"] = "%s week%s" % [_num(_s.regular_weeks - wk), "" if _s.regular_weeks - wk == 1 else "s"]
	var out: Array = []
	if was > 0 and was != row.rank:
		ex["was"] = _ord(was)
		out.append(_g("t_move", [
			"The {us_nick} are {record} and {rank} in the league, %s from {was} a week ago." % ("up" if row.rank < was else "down"),
			"At {record}, the {us_nick} %s from {was} to {rank} in the league table." % ("climb" if row.rank < was else "slide"),
		], ex))
	else:
		out.append(_g("t_hold", ["The {us_nick} are {record}, {rank} in the league.", "At {record}, the {us_nick} sit {rank} overall."], ex))
	if leader.team == _us:
		out.append(_g("t_lead", ["They lead {div_name}.", "That's good for first in {div_name}.", "Nobody in {div_name} is ahead of them."],
			ex.merged({"div_name": _div_name(_us)})))
	else:
		out.append(_g("t_chase", [
			"They are {dpos} in {div_name}, {gb} back of the {leader}.",
			"In {div_name} they're {dpos}, {gb} behind the {leader}."], ex.merged({"div_name": _div_name(_us)})))
	var field := _s.playoff_field()
	if wk >= _s.regular_weeks / 2 and _s.regular_weeks - wk > 0:
		if field.has(_us):
			out.append(_g("t_in", ["With {left_w} left, they'd be in the playoffs if it ended today.", "{left_w} to go, and they're in the field for now."], ex))
		elif not field.is_empty():
			var last_in: StandingRow = _row(field[-1])
			ex["need"] = _plural(maxi(1, last_in.wins - row.wins), "win")
			out.append(_g("t_out", ["With {left_w} left, they're on the outside of the playoff line, {need} back.", "{left_w} left, and the playoff line is {need} away."], ex))
	elif wk == _s.regular_weeks:
		if field.has(_us):
			ex["seed"] = _ord(field.find(_us) + 1)
			out.append(_g("t_done_in", ["That's the regular season, and they're in: the {seed} seed.", "The regular season is done. They're the {seed} seed."], ex))
		else:
			out.append(_g("t_done_out", ["That's the regular season, and it ends without a playoff spot.", "The regular season is over, and the playoffs will go on without them."], ex))
	if row.streak.length() >= 2 and int(row.streak.substr(1)) >= 3:
		out.append(_g("t_streak", ["The streak sits at {streak}.", "The form line reads {streak}."], ex))
	return _cap_first(_para(out))

## The next opponent: form, their best player, the matchup, the forecast, and a word from them.
func _preview_para(wk: int) -> String:
	var nm := _s.next_match_for(_us)
	if nm == null:
		if wk < _s.regular_weeks:
			return _g("p_bye", ["Next week is a bye, and then the stretch run.", "The {us_nick} are off next week."] if wk + 1 < _s.regular_weeks
				else ["Next week is a bye to close the regular season, so the {us_nick} will wait and watch the table settle around them."])
		return ""
	var them: Team = nm.opponent_of(_us)
	var star := _team_star(them)
	var ex := {"next": _full(them), "next_nick": _nick(them), "next_rec": _record(them), "nwk": _s.week_label(nm.week),
		"where": "at home" if nm.home == _us else "in %s" % _city(them), "next_scheme": them.scheme.display_name}
	var row := _row(them)
	ex["form"] = row.streak if row != null else "-"
	var out: Array = []
	if nm.stage != Season.STAGE_REGULAR:
		ex["round"] = _s.week_label(nm.week).to_lower()
		ex["seed"] = _ord(int(_s.playoff_seeds.get(_us, 0)))
		ex["nseed"] = _ord(int(_s.playoff_seeds.get(them, 0)))
		ex["ncity"] = _city(them)
		if nm.home == _us:
			out.append(_g("p_po_home", ["In the {round}, the {us_nick} host the {nseed}-seeded {next} ({next_rec}).",
				"The {round} come to {us_city}: the {next}, the {nseed} seed, at {next_rec}."], ex))
		else:
			out.append(_g("p_po_road", ["The {us_nick} are in as the {seed} seed and head to {ncity} for the {round}, against the {next} ({next_rec}).",
				"Next is the {round}, on the road against the {nseed}-seeded {next}, {next_rec}."], ex))
	else:
		out.append(_g("p_open", [
			"Next up: the {next} ({next_rec}) {where} in {nwk}.",
			"{nwk} brings the {next}, {next_rec}, {where}.",
			"The {next} are next, {where}, in {nwk}. They're {next_rec}."], ex))
	if star != null:
		ex["ns"] = _who_role(star)
		var nk := int(star.season_lines.get(_s.year, {}).get("kills", 0))
		ex["nk"] = str(nk)
		ex["novr"] = str(star.best_ovr())
		if nk > 0:
			out.append(_g("p_star", ["The name to know is {ns}, with {nk} kills this season.", "Keep an eye on {ns} ({nk} kills on the year).",
				"Their danger man is {ns}, who has {nk} kills.", "Everything they do runs through {ns}: {nk} kills so far.",
				"{ns} is the one to stop, with {nk} kills this year.", "Plan around {ns}. {nk} kills on the season says why.", "{ns} leads them with {nk} kills, and the {next_nick} know it."], ex))
		else:
			out.append(_g("p_star0", ["Their best player is {ns}, rated {novr}.", "The name to know is {ns}, a {novr}-rated problem.", "The danger is {ns}, a {novr}.", "Start the scouting report with {ns}, rated {novr}."], ex))
	var edge := _us.scheme.edge_vs(them.scheme)
	if absf(edge) >= 0.01:
		out.append(_g("p_edge_good" if edge > 0 else "p_edge_bad", [
			"The {us_scheme} matches up well against their {next_scheme}.",
			"On the whiteboard, the {us_scheme} has the edge on the {next_scheme}."] if edge > 0 else [
			"The {us_scheme} is a bad matchup against their {next_scheme}, if nothing changes.",
			"Their {next_scheme} is built to punish the {us_scheme}. Watch whether the staff adjusts."], ex))
	var w := nm.shown_weather()
	if not w.is_clear():
		ex["fc"] = w.label().to_lower()
		out.append(_g("p_wx", ["The forecast calls for {fc}.", "Expect {fc}."], ex))
	var prev_m := _match_of(wk)
	if prev_m != null and prev_m.is_played() and prev_m.opponent_of(_us) == them:
		out.append(_g("p_rematch", ["Same opponent, different building: it's an immediate rematch.", "So it's the {next_nick} again, a week later, with everything fresh in the memory."], ex))
	elif _s.rivalries.is_rivalry(_us, them):
		var ser := _series(them)
		ex["rt"] = _s.rivalries.title(_us, them)
		ex["ser"] = ser
		if not ex["rt"].ends_with("Division Rivalry"):
			out.append(_g("p_rival", ["Circle it: it's the {rt}, and {ser}.", "It's another chapter of the {rt}; {ser}."] if ser != ""
				else ["Circle it: the first {rt} meeting."], ex))
		else:
			out.append(_g("p_div", ["It's a division game, and {ser}.", "Division game: {ser}.", "The division cares about this one, and {ser}.", "Inside the division: {ser}."] if ser != ""
				else ["It's a division game, the first meeting of the year between the two.", "The first division meeting of the year between the two.", "Division rivals, with no meeting yet this year."], ex))
	if star != null and _chance(0.6):
		ex["q"] = _quote(star, "preview", {"them": _us})
		ex["sl"] = star.last_name
		out.append(_g("p_q", ["\"{q}\" {sl} said this week.", "\"{q}\" {sl} told reporters."], ex))
	return _para(out)


func _box_sidebar(g: Dictionary) -> Array:
	var games: Array = []
	for gm in g["games"]:
		var name := "TDM"
		var sc := "%d-%d" % [gm["us"], gm["them"]]
		if gm["mode"] == MatchEngine.MODE_KOTH:
			name = "King of the Hill"
			sc = "%s-%s" % [_secs(gm["us"]), _secs(gm["them"])]
		elif gm["mode"] == MatchEngine.MODE_SUDDEN_DEATH:
			name = "Sudden Death"
		games.append([name, "%s %s" % ["W" if gm["won"] else "L", sc]])
	var box: Array = []
	for e in g["ours"]:
		var ln: Dictionary = e["line"]
		box.append([e["s"].short_name(), "%d-%d-%d" % [ln["kills"], ln["deaths"], ln["assists"]]])
	var table: Array = []
	for r in _div_rows(_us).slice(0, 6):
		table.append(["%s %s" % [r.team.abbrev, "*" if r.team == _us else ""], "%d-%d" % [r.wins, r.losses]])
	return [{"title": "%s %s %s" % [_us.abbrev, _f["gs"], g["them"].abbrev], "rows": games},
		{"title": "Box (K-D-A)", "rows": box}, {"title": _division(_us), "rows": table}, _buzz_box()]

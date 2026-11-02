extends "res://scripts/season/news/news_game.gd"
## In-season articles that are not a game recap: bye week, sidelined and the season wrap.


func _bye_article(wk: int) -> Dictionary:
	var row := _row(_us)
	var drows := _div_rows(_us)
	var art := {"kind": KIND_BYE, "section": "%s - %s" % [_f["us_nick"].to_upper(), _f["when"].to_upper()], "angles": ["bye"]}
	var res := _results(_us)
	var run := _run(res)
	var ex := {"run": _num(int(run[1])), "rank": _ord(row.rank) if row != null else "-"}
	art["headline"] = _g("hb", ["A Week Off, and a Lot to Think About", "{us_nick} Idle as the Table Shifts", "Bye Week: Taking Stock at {record}",
		"Rest, Repairs and the Road Ahead"], ex)
	art["dek"] = _cap_first(_g("hb_dek", ["The {us_nick} sat out {when} at {record}.", "No match for the {us_nick}, who sit {rank} at {record}."], ex))
	var body: Array = []
	var open := ""
	if run[0] == "W" and int(run[1]) >= 2:
		open = _g("b_hot", ["The worst thing about a bye week is when it arrives in the middle of a run. The {us_nick} have won {run} straight, and now they wait.",
			"The {us_nick} would have happily kept playing. They've won {run} in a row and spent {when} watching instead."], ex)
	elif run[0] == "L" and int(run[1]) >= 2:
		open = _g("b_cold", ["If any team needed a week to stop and think, it was this one. The {us_nick} have lost {run} straight, and the bye couldn't have come at a better time.",
			"The {us_nick} got a week away from the losing, which is the best thing that could have happened to them. They've dropped {run} in a row."], ex)
	else:
		open = _g("b_norm", ["The {us_nick} had {when} off, and at {record} there was plenty to think about.",
			"No match this week for the {us_nick}, who sit {rank} in the league at {record}."], ex)
	body.append(open)
	# How the week around them went: division rivals.
	var mov: Array = []
	for m in _s.matches_for_week(wk):
		if not m.is_played():
			continue
		var w: Team = m.winner()
		var l: Team = m.opponent_of(w)
		if w.division != _us.division and l.division != _us.division:
			continue
		var sc := "%d-%d" % [m.result.score.max(), m.result.score.min()]
		var mex := {"w": _nick(w), "l": _nick(l), "sc": sc}
		if w.division == _us.division and l.division == _us.division:
			mov.append(_g("b_div2", ["The {w} beat the {l} {sc} in a division game.", "The {w} took care of the {l}, {sc}, inside the division."], mex))
		elif w.division == _us.division:
			mov.append(_g("b_divw", ["The {w} beat the {l} {sc}.", "The {w} won {sc} over the {l}."], mex))
		else:
			mov.append(_g("b_divl", ["The {l} lost {sc} to the {w}.", "The {l} fell to the {w}, {sc}."], mex))
	var div_open := ""
	var div_text := ""
	if not mov.is_empty():
		div_open = _g("b_div_open", ["Around {div_name}:", "Elsewhere in {div_name}:"], {"div_name": _div_name(_us)})
		div_text = _para(mov.slice(0, 3))
	var hurt: Array = _us.roster.filter(func(s: Soldier): return s.injury_weeks > 0)
	var hurt_text := ""
	if not hurt.is_empty():
		var names: Array = []
		for s in hurt.slice(0, 3):
			names.append("%s (%s, %s)" % [_who_role(s), s.injury_name.to_lower(), _plural(s.injury_weeks, "week")])
		hurt_text = _g("b_hurt", ["The week off matters most to the injury list: {list}.", "The training room will be busy: {list}."], {"list": ", ".join(names)})
	# A notebook (labeled notes) or a feature, never the same one twice running.
	var fmt := "notebook" if memory.get("bye_fmt", "") != "notebook" and _chance(0.55) else "feature"
	memory["bye_fmt"] = fmt
	art["format"] = fmt
	var parts: Array = []
	if div_text != "":
		parts.append(["DIVISION WATCH", div_text if fmt == "notebook" else "%s %s" % [div_open, div_text]])
	if hurt_text != "":
		parts.append(["TRAINING ROOM", hurt_text])
	parts.append(["THE TABLE", "<table>"])
	parts.append(["THE MOOD", "<mood>"])
	var notes := _quiet_notes()
	if fmt == "notebook":
		parts.append_array(notes)
		while parts.size() > _r.randi_range(3, 5):
			parts.pop_at(_r.randi_range(0, parts.size() - 1))
	else:
		parts.append_array(notes.slice(0, 2))
	for part: Array in parts:
		var text: String = part[1]
		if text == "<table>":
			text = _standings_para(wk) if row != null else ""
		elif text == "<mood>":
			text = _buzz_para()
		if text.strip_edges() != "":
			body.append(("%s: %s" % [part[0], text]) if fmt == "notebook" else text)
	var star := _team_star(_us)
	if star != null:
		var q := _quote(star, "bye", {})
		if fmt == "feature":
			body.append(_g("b_q", ["\"{q}\" {who} said.", "\"{q}\" said {who}."], {"q": q, "who": _who_role(star)}))
		art["pull_quote"] = {"text": q, "who": star.display_name(), "team": _us.abbrev}
	var next := _preview_para(wk)
	body.append(("NEXT UP: %s" % next) if fmt == "notebook" and next != "" else next)
	art["body"] = body
	art["sidebar"] = [{"title": _division(_us), "rows": drows.slice(0, 6).map(func(r): return [r.team.abbrev, "%d-%d" % [r.wins, r.losses]])}, _buzz_box()]
	art["roundup"] = _roundup(wk)
	return art


func _sidelined_article(wk: int) -> Dictionary:
	var lost := _exit_match()
	var art := {"kind": KIND_SIDELINED, "section": "%s - %s" % [_f["us_nick"].to_upper(), _f["when"].to_upper()], "angles": ["sidelined"]}
	var ex := {"stage": _s.week_label(wk).to_lower(), "stage_t": _s.week_label(wk)}
	var body: Array = []
	if lost == null:
		art["headline"] = _g("hs_out", ["Watching From Home", "The Playoffs Go On Without Them", "{us_nick} on the Outside Looking In"])
		art["dek"] = _cap_first(_g("hs_out_d", ["The {us_nick} finished {record} and missed the field.", "At {record}, the {us_nick} are spectators."]))
		body.append(_g("s_out", [
			"The playoffs started this week without the {us_nick}, who finished {record} and never got into the field. That is the season, and it should sting.",
			"There's a {stage} going on, and the {us_nick} aren't in it. A {record} season left them short of the playoffs."], ex))
		var field := _s.playoff_field()
		var row := _row(_us)
		if not field.is_empty() and row != null:
			var last_in: StandingRow = _row(field[-1])
			if last_in != null:
				body.append(_g("s_short", ["The last spot went to the {t} at {r}. The {us_nick} finished {n} behind them.",
					"The {t} took the final seed at {r}, {n} clear of the {us_nick}."],
					{"t": _nick(last_in.team), "r": "%d-%d" % [last_in.wins, last_in.losses], "n": _plural(maxi(1, last_in.wins - row.wins), "win")}))
	else:
		var them: Team = lost.opponent_of(_us)
		ex["them"] = _full(them)
		ex["them_nick"] = _nick(them)
		ex["round"] = _s.week_label(lost.week).to_lower()
		ex["sc"] = "%d-%d" % [lost.result.score.max(), lost.result.score.min()]
		art["headline"] = _g("hs_elim", ["Still Stewing Over the {them_nick}", "The {stage_t}, Without the {us_nick}", "What Might Have Been"], ex)
		art["dek"] = _cap_first(_g("hs_elim_d", ["The {us_nick} went out in the {round}.", "The {round} loss still hangs over the {us_nick}."], ex))
		body.append(_g("s_elim", [
			"The {us_nick} spent the {stage} watching. Their season ended {sc} in the {round} against the {them}, and the questions haven't stopped since.",
			"It's a strange feeling, being done while other teams are still playing. The {them} sent the {us_nick} home {sc} in the {round}."], ex))
		var g := _game_facts(lost)
		var voice: Soldier = null
		for e in g["ours"]:
			if e["s"] != _team_star(_us):
				voice = e["s"]
				break
		if voice != null:
			var q := _quote(voice, "star_loss", g)
			body.append(_g("s_q", ["A week later, it still stung. \"{q}\" {who} said.", "\"{q}\" {who} said, still not over it."], {"q": q, "who": _who_role(voice)}))
			art["pull_quote"] = {"text": q, "who": voice.display_name(), "team": _us.abbrev}
	for note: Array in _quiet_notes().slice(0, 2):
		body.append(note[1])
	body.append(_offseason_look())
	var alive: Array = []
	for m in _s.matches_for_week(wk):
		if m.is_played():
			alive.append("the %s beat the %s %d-%d" % [_full(m.winner()), _nick(m.opponent_of(m.winner())), m.result.score.max(), m.result.score.min()])
	if not alive.is_empty():
		body.append(_cap_first(_g("s_bracket", ["In the {stage}, {list}.", "Elsewhere, the bracket moved on: {list}."], {"list": "; ".join(alive)}.merged(ex))))
	art["body"] = body
	art["roundup"] = _roundup(wk)
	return art

## Notes about our own people that suit a week without a match: [[label, text]], each only when true.
func _quiet_notes() -> Array:
	var notes: Array = []
	# Closest to a career milestone.
	var chase: Dictionary = {}
	var chase_gap := 1 << 30
	for so: Soldier in _us.roster:
		for row: Array in MILESTONES:
			var total := int(so.career.get(row[0], 0))
			for mark: int in row[2]:
				if total < mark:
					var gap := mark - total
					if gap <= maxi(5, mark / 10) and gap < chase_gap:
						chase_gap = gap
						chase = {"so": so, "gap": gap, "mark": _commas(mark), "noun": String(row[1]).replace("career ", ""), "what": row[1]}
					break
	if not chase.is_empty():
		var so: Soldier = chase["so"]
		notes.append(["MILESTONE WATCH", _g("q_chase", ["{who} is {gap} {noun} short of {mark} {what}.", "{last} is {gap} {noun} from {mark} {what}, and the next match could do it."],
			{"who": _who(so), "last": so.last_name, "gap": str(chase["gap"]), "noun": chase["noun"], "mark": chase["mark"], "what": chase["what"]})])
	# Honors this season.
	var honored: Soldier = null
	var honors := 0
	for so: Soldier in _us.roster:
		var n := NewsHistory.potw_count(history, so.id, _s.year)
		if n > honors:
			honors = n
			honored = so
	if honored != null:
		notes.append(["AWARDS", _g("q_potw", ["{who} has been the league's Player of the Week {times} this season.", "{last} comes into the break with {times_n} as Player of the Week."],
			{"who": _who(honored), "last": honored.last_name, "times": _plural(honors, "time"), "times_n": _plural(honors, "award")})])
	# The most worn-down starter.
	var tired: Soldier = null
	for so: Soldier in _us.starters():
		if so.injury_weeks <= 0 and so.fatigue >= 45.0 and (tired == null or so.fatigue > tired.fatigue):
			tired = so
	if tired != null:
		notes.append(["WEAR AND TEAR", _g("q_tired", ["{who} is the most worn-down starter on the roster, and a quiet week is the best medicine for him.",
			"If anyone needs the time, it is {who}: the heaviest legs in the starting group."], {"who": _who(tired)})])
	# Form over the last three matches.
	var form: Soldier = null
	var form_gap := 5
	var form_line := {}
	for so: Soldier in _us.roster:
		var rows := _last_lines(so, 3)
		if rows.is_empty():
			continue
		var tk := 0
		var td := 0
		for r: Dictionary in rows:
			tk += int(r["k"])
			td += int(r["d"])
		if tk - td > form_gap:
			form_gap = tk - td
			form = so
			form_line = {"tk": tk, "td": td}
	if form != null:
		notes.append(["FORM", _g("q_form", ["{who} is {tk}-{td} over his last three matches.", "{last} has been the steadiest hand lately: {tk}-{td} across three matches."],
			{"who": _who(form), "last": form.last_name, "tk": str(form_line["tk"]), "td": str(form_line["td"])})])
	for i in range(notes.size() - 1, 0, -1):
		var j := _r.randi_range(0, i)
		var tmp: Array = notes[i]
		notes[i] = notes[j]
		notes[j] = tmp
	return notes


## Our last playoff loss this season (null if we didn't make it or haven't lost).
func _exit_match() -> ScheduledMatch:
	var exit: ScheduledMatch = null
	for m in _s.matches_for(_us):
		if m.stage != Season.STAGE_REGULAR and m.is_played() and m.winner() != _us:
			exit = m
	return exit

## The expiring contracts and what each player wants: the offseason in miniature.
func _offseason_look() -> String:
	var off := _s.phase == Season.PHASE_OFFSEASON
	var exp: Array = _us.roster.filter(func(s: Soldier): return s.contract != null and (s.contract.is_expiring() if off else s.contract.years <= 1))
	if exp.is_empty():
		return _g("o_none", ["The good news for the front office: nobody of consequence is up for a new deal.", "Nobody on the roster is entering free agency, so the core stays together."])
	exp.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	var bits: Array = []
	for s in exp.slice(0, 3):
		bits.append("%s (%d OVR, age %d), who %s" % [_who_role(s), s.best_ovr(), s.age, _wants(s)])
	return _g("o_list", ["The bigger questions are on the contract sheet. Up for new deals: {list}.",
		"Now the front office has decisions to make. Expiring: {list}.",
		"The offseason starts with the expiring contracts: {list}."], {"list": "; ".join(bits)})


func _wrap_article(wk: int) -> Dictionary:
	var art := {"kind": KIND_WRAP, "section": "%s SEASON REVIEW" % _f["year"], "angles": ["wrap"]}
	var champ: Team = _s.champion
	var final_m: ScheduledMatch = _match_of(wk)
	var exit := _exit_match()
	var seed := int(_s.playoff_seeds.get(_us, 0))
	var row := _row(_us)
	var ex := {"champ": _full(champ) if champ != null else "", "champ_nick": _nick(champ) if champ != null else "",
		"rank": _ord(row.rank) if row != null else "-", "seed": _ord(seed)}
	var body: Array = []
	var good := false
	if champ == _us:
		good = true
		art["headline"] = _g("hw_champ", ["Champions", "{us_nick} Win It All", "On Top of the League"], ex)
		art["dek"] = _cap_first("The %s are %s champions." % [_f["us_full"], _f["year"]])
		var g := _game_facts(final_m) if final_m != null and final_m.is_played() else {}
		body.append(_g("w_champ", [
			"Say it slowly: the {us_full} are champions. They beat the {them_full} {gs_w} in the final, and every argument about this team is settled for at least one summer.",
			"There's nothing left to win. The {us_nick} beat the {them_nick} {gs_w} in the final and are the {year} champions."], ex))
		if not g.is_empty():
			body.append(_narrative(g, ""))
			if not g["star"].is_empty():
				body.append(_star_para(g)[0])
	elif final_m != null and final_m.is_played():
		var g := _game_facts(final_m)
		art["headline"] = _g("hw_runner", ["So Close", "One Match Short", "{them_nick} Deny {us_nick} the Title"], ex)
		art["dek"] = _cap_first("The %s fell %s to the %s in the final." % [_f["us_nick"], _f["gs_w"], _f["them_nick"]])
		body.append(_g("w_runner", ["One match from a title, the {us_nick} lost the final {gs_w} to the {them_full}. It will take a long time for that to stop hurting.",
			"The last match of the year belonged to the {them_nick}, who beat the {us_nick} {gs_w} for the title."], ex))
		body.append(_narrative(g, ""))
		good = true
	elif exit != null:
		var them: Team = exit.opponent_of(_us)
		ex["them"] = _full(them)
		ex["round"] = _s.week_label(exit.week).to_lower()
		art["headline"] = _g("hw_exit", ["{champ_nick} Win It; {us_nick} Left to Wonder", "A {record} Year, Graded", "The Season That Was"], ex)
		art["dek"] = _cap_first(_g("hw_exit_d", ["The {champ} are champions. The {us_nick} went out in the {round}.", "A {seed} seed, a {round} exit, and a long summer."], ex))
		body.append(_g("w_exit", ["The {champ} are champions. The {us_nick} were done before the final, beaten by the {them} in the {round} after a {record} regular season.",
			"Another team lifted the trophy. The {us_nick}, the {seed} seed, went out in the {round} to the {them}."], ex))
		good = row != null and row.rank <= 4
	else:
		art["headline"] = _g("hw_miss", ["A Year to Forget", "No Playoffs, Plenty of Questions", "Grading a {record} Season"], ex)
		art["dek"] = _cap_first(_g("hw_miss_d", ["The {champ} won the title. The {us_nick} finished {rank} and missed the playoffs.", "{record}, {rank}, and home for the playoffs."], ex))
		body.append(_g("w_miss", ["The {champ} won the title this week, and the {us_nick} watched it like everyone else. They finished {record}, {rank} in the league, and never seriously threatened the playoff line.",
			"The season is over, and for the {us_nick} it ended weeks ago. {record}, {rank} in the league, no playoffs."], ex))
	body.append(_arc_para())
	# The best player's season.
	var star := _team_star(_us)
	if star != null:
		var ln := _line(star)
		body.append(_g("w_star", ["The best player on the roster all year was {who}: {k} kills, {d} deaths in {m} matches.",
			"{who} carried more than his share, with {k} kills and {d} deaths in {m} matches."],
			{"who": _who_role(star), "k": str(int(ln.get("kills", 0))), "d": str(int(ln.get("deaths", 0))), "m": str(int(ln.get("matches", 0)))}))
	# Awards.
	var aw: Array = []
	if _s.review != null:
		for a in _s.review.awards:
			if a["team"] == _us:
				aw.append("%s won %s" % [_who(a["soldier"]), a["award"]])
		if not _s.review.awards.is_empty() and _s.review.awards[0]["team"] != _us:
			var mvp: Dictionary = _s.review.awards[0]
			aw.append("the league MVP went to %s of the %s" % [mvp["soldier"].display_name(), _nick(mvp["team"])])
	if not aw.is_empty():
		body.append(_cap_first(_g("w_aw", ["On awards night, {list}.", "The hardware: {list}."], {"list": "; ".join(aw)})) )
	# Retirements.
	var ret: Array = _s.retirements.filter(func(r): return r["team"] == _us and r["year"] == _s.year)
	for r in ret.slice(0, 2):
		var s: Soldier = r["soldier"]
		body.append(_g("w_ret", ["{who} is retiring at {age} after {m} career matches and {k} kills. {reason}",
			"And {who} is hanging it up at {age}, {k} kills over {m} matches. {reason}"],
			{"who": _who_role(s), "age": str(int(r["age"])), "m": str(int(r["matches"])), "k": str(int(r["kills"])), "reason": _cap_first(String(r.get("reason", "")))}))
	body.append(_season_callback())
	body.append(_season_take(good))
	for note: Array in _quiet_notes().slice(0, 1):
		if note[0] == "AWARDS" or note[0] == "MILESTONE WATCH":
			body.append(note[1])
	body.append(_buzz_year_para())
	body.append(_money_year_para())
	body.append(_offseason_look())
	if star != null:
		var q := _quote(star, "season_good" if good else "season_bad", {})
		body.append(_g("w_q", ["\"{q}\" {who} said.", "\"{q}\" {who} said as he cleaned out his locker."], {"q": q, "who": star.last_name}))
		art["pull_quote"] = {"text": q, "who": star.display_name(), "team": _us.abbrev}
	art["body"] = body
	var side: Array = []
	if _s.review != null:
		side.append({"title": "Awards", "rows": _s.review.awards.map(func(a): return [a["award"], "%s (%s)" % [a["soldier"].short_name(), a["team"].abbrev]])})
	side.append(_buzz_box(true))
	art["sidebar"] = side
	var finish := "missed the playoffs"
	if champ == _us:
		finish = "won the title"
	elif final_m != null and final_m.is_played():
		finish = "lost in the final"
	elif exit != null:
		finish = "went out in the %s" % _s.week_label(exit.week).to_lower()
	memory["last_season"] = {"record": _f["record"], "finish": finish, "starter_ovr": _avg_starter_ovr(_us)}
	memory["season_roster"] = _us.roster.map(func(s: Soldier): return s.id)
	var names := {}
	for s in _us.roster:
		names[str(s.id)] = [s.display_name(), int(_line(s).get("kills", 0)), _role(s)]
	memory["season_names"] = names
	return art

## The shape of the regular season: the start, the best and worst runs, the signature win.
func _arc_para() -> String:
	var games: Array = []
	for m in _s.matches_for(_us):
		if m.stage == Season.STAGE_REGULAR and m.is_played():
			games.append(m)
	if games.size() < 4:
		return ""
	var bits: Array = []
	var w3 := 0
	for m in games.slice(0, 3):
		if m.winner() == _us:
			w3 += 1
	var ex := {"start": "%d-%d" % [w3, 3 - w3]}
	bits.append(_g("arc_start", ["They opened {start}.", "It started {start}."] if w3 != 1 and w3 != 2
		else ["They opened {start}, which told nobody much.", "The first three weeks went {start}."], ex))
	var best_w := 0
	var best_l := 0
	var cur := 0
	var last := ""
	for m in games:
		var r := "W" if m.winner() == _us else "L"
		cur = cur + 1 if r == last else 1
		last = r
		if r == "W":
			best_w = maxi(best_w, cur)
		else:
			best_l = maxi(best_l, cur)
	ex["bw"] = _num(best_w)
	ex["bl"] = _num(best_l)
	if best_w >= 3 and best_l >= 3:
		bits.append(_g("arc_both", ["There was a {bw}-match winning streak and a {bl}-match skid, and the season lived somewhere between them.",
			"They won {bw} straight at one point and lost {bl} straight at another."], ex))
	elif best_w >= 3:
		bits.append(_g("arc_w", ["The high point was a {bw}-match winning streak.", "At their best they won {bw} in a row."], ex))
	elif best_l >= 3:
		bits.append(_g("arc_l", ["The low point was a {bl}-match losing streak they never fully recovered from.", "A {bl}-match skid did the most damage."], ex))
	var sig: ScheduledMatch = null
	var sig_rank := 999
	var dw := 0
	var dl := 0
	for m in games:
		var o: Team = m.opponent_of(_us)
		var orow := _row(o)
		if m.winner() == _us and orow != null and orow.rank < sig_rank:
			sig_rank = orow.rank
			sig = m
		if o.division == _us.division:
			if m.winner() == _us:
				dw += 1
			else:
				dl += 1
	if sig != null and sig_rank <= 4:
		var o: Team = sig.opponent_of(_us)
		bits.append(_g("arc_sig", ["The best win was {w} over the {o}, who finished {r}.", "Their signature result: {w} over the {o}, the league's {r} team."],
			{"w": "%d-%d" % [sig.result.score.max(), sig.result.score.min()], "o": _nick(o), "r": _ord(sig_rank)}))
	if dw + dl >= 2:
		bits.append(_g("arc_div", ["They went {d} inside {div}.", "Against {div}, they were {d}."], {"d": "%d-%d" % [dw, dl], "div": _div_name(_us)}))
	return _para(bits)

# --- the offseason ----------------------------------------------------------------------

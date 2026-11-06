extends "res://scripts/season/news/news_season.gd"
## Offseason issues: re-signing, free agency, draft, review, camp and preseason.


func _off_art(kind: String, label: String) -> Dictionary:
	return {"kind": kind, "section": "%s OFFSEASON - %s" % [_f["us_nick"].to_upper(), label.to_upper()], "angles": [kind]}

## "$1.25M a year for three years".
func _deal(salary: int, years: int) -> String:
	return "%s a year for %s" % [_money(salary), "one year" if years == 1 else "%s years" % _num(years)]


func _cap_line() -> String:
	var cy := _s.cap_year()
	var space := Contracts.cap_space(_us, cy)
	var apron := Contracts.apron_room(_us, cy)
	if apron < 0:
		return _g("cap_over", ["They are {m} over the apron, and that has to be fixed before camp.", "The cap sheet is {m} past the apron."], {"m": _money(-apron)})
	var tax := Contracts.tax_overage(_us, cy)
	if tax > 0:
		return _g("cap_tax", ["They are {m} into the luxury tax.", "The cap sheet sits {m} over the tax line, and the owner pays for every dollar of it."], {"m": _money(tax)})
	if space < 0:
		return _g("cap_soft", ["They are {m} over the cap: re-signs and minimum deals only.", "The cap sheet is {m} past the soft cap."], {"m": _money(-space)})
	return _g("cap_room", ["They have {m} in cap space to work with.", "That leaves {m} of room under the cap.", "The cap sheet shows {m} free."], {"m": _money(space)})

## Lays an offseason issue out: the lead runs as prose, then the notes ([label, text, pinned]). A notebook labels
## the notes, shuffles the loose ones and keeps a few; a feature runs them as prose in order and may drop one.
## Never the same layout twice running.
func _off_body(art: Dictionary, lead: Array, notes: Array, tail: Array) -> Array:
	var fmt := "notebook" if memory.get("off_fmt", "") != "notebook" and _chance(0.5) else "feature"
	memory["off_fmt"] = fmt
	art["format"] = fmt
	var loose: Array = notes.filter(func(n: Array): return not n[2] and String(n[1]).strip_edges() != "")
	if fmt == "notebook":
		for i in range(loose.size() - 1, 0, -1):
			var j := _r.randi_range(0, i)
			var swap: Array = loose[i]
			loose[i] = loose[j]
			loose[j] = swap
		loose = loose.slice(0, _r.randi_range(3, 5))
	elif loose.size() > 4 and _chance(0.5):
		loose.pop_at(_r.randi_range(0, loose.size() - 1))
	var body: Array = lead.duplicate()
	var li := 0
	for n: Array in notes:
		var note: Array = n
		if not n[2]:
			if fmt == "notebook":
				if li >= loose.size():
					continue
				note = loose[li]
				li += 1
			elif not loose.has(n):
				continue
		var text := String(note[1]).strip_edges()
		if text != "":
			body.append(("%s: %s" % [note[0], text]) if fmt == "notebook" else text)
	body.append_array(tail)
	return body


## "41 kills and 22 deaths" from the soldier's latest season line, or "" when he has none.
func _last_line(s: Soldier) -> String:
	var years: Array = s.season_lines.keys()
	if years.is_empty():
		return ""
	years.sort()
	var line: Dictionary = s.season_lines[years[years.size() - 1]]
	var k := int(line.get("kills", 0))
	if k <= 0:
		return ""
	return "%d kills and %s" % [k, _plural(int(line.get("deaths", 0)), "death")]


## A "by the numbers" note about one soldier's last season, or "".
func _numbers_note(s: Soldier) -> String:
	var line := _last_line(s)
	if line == "":
		return ""
	return _g("on_nums", ["{who} put up {line} last season.", "Last season, {who} finished with {line}.", "The ledger on {last}: {line} last season."],
		{"who": _who(s), "last": s.last_name, "line": line})


## Roles on the roster versus what the scheme asks for: the thinnest role, or "".
func _need() -> String:
	var want := {}
	for slot in _us.scheme.slot_ids():
		var r: int = _us.scheme.role_for_slot(slot)
		want[r] = int(want.get(r, 0)) + 1
	var have := {}
	for s in _us.roster:
		var r := Scheme.best_role(s.stats)
		have[r] = int(have.get(r, 0)) + 1
	var worst := -1
	var worst_gap := 0
	for r in want:
		var gap: int = want[r] * 2 - int(have.get(r, 0))
		if gap > worst_gap:
			worst_gap = gap
			worst = r
	return String(Scheme.ROLE_NAMES[worst]).to_lower() if worst >= 0 else ""


func _resign_article() -> Dictionary:
	var art := _off_art(KIND_RESIGN, "Re-signing")
	var y := _s.year
	var kept: Array = _s.resign_log.filter(func(e): return e["team"] == _us and e["year"] == y)
	var gone: Array = _s.departures.filter(func(e): return e["team"] == _us and e["year"] == y)
	kept.sort_custom(func(a, b): return a["salary"] > b["salary"])
	gone.sort_custom(func(a, b): return a["soldier"].best_ovr() > b["soldier"].best_ovr())
	var body: Array = []
	var big_loss: Soldier = gone[0]["soldier"] if not gone.is_empty() else null
	var big_keep: Soldier = kept[0]["soldier"] if not kept.is_empty() else null
	var led_with_loss := big_loss != null and big_loss.best_ovr() >= 72
	if led_with_loss:
		art["headline"] = _g("hr_loss", ["%s Walks" % big_loss.last_name, "%s Heads to Free Agency" % big_loss.last_name, "No Deal for %s" % big_loss.last_name])
		body.append(_g("rs_loss", [
			"The {us_nick} let {who} walk. The {age}-year-old, rated {ovr}, didn't get a new deal and hits the open market, and the {us_nick} will have to explain what comes next.",
			"{who} is gone, or at least he's no longer theirs. The {us_nick} couldn't or wouldn't get a deal done with the {ovr}-rated {role}, and he's a free agent."],
			{"who": _who(big_loss), "age": str(big_loss.age), "ovr": str(big_loss.best_ovr()), "role": _role(big_loss)}))
	elif big_keep != null:
		var e: Dictionary = kept[0]
		art["headline"] = _g("hr_keep", ["%s Stays" % big_keep.last_name, "{us_nick} Lock Up %s" % big_keep.last_name, "%s Signs On Again" % big_keep.last_name])
		body.append(_g("rs_keep", [
			"The {us_nick} took care of their own first. {who} re-signed at {deal}, keeping a {ovr}-rated {role} in {us_city}.",
			"First order of business: {who}. The {us_nick} brought him back at {deal}."],
			{"who": _who_role(big_keep), "deal": _deal(e["salary"], e["years"]), "ovr": str(big_keep.best_ovr()), "role": _role(big_keep)}))
	else:
		art["headline"] = _g("hr_quiet", ["A Quiet Start to the Offseason", "Little Movement in {us_city}", "The Market Opens"])
		body.append(_g("rs_quiet", ["The re-signing window came and went quietly in {us_city}.", "It was a quiet re-signing week for the {us_nick}."]))
	art["dek"] = _cap_first("%s re-signed, %s headed to free agency." % [_num(kept.size()) if kept.size() > 0 else "nobody", _num(gone.size()) if gone.size() > 0 else "none"])
	var gone_k := 0
	var sn: Dictionary = memory.get("season_names", {})
	for e in gone:
		gone_k += int(sn.get(str(e["soldier"].id), ["", 0])[1])
	var notes: Array = []
	var more: Array = []
	for e in kept.slice(0 if led_with_loss else 1, 4):
		more.append("%s (%s)" % [_who(e["soldier"]), _deal(e["salary"], e["years"])])
	if not more.is_empty():
		notes.append(["ALSO BACK", _g("rs_more", ["Also back: {list}.", "They also re-signed {list}."], {"list": _join_and(more)}), false])
	var left: Array = []
	for e in gone.slice(1 if led_with_loss else 0, 4):
		var s: Soldier = e["soldier"]
		left.append("%s, who %s" % [_who_role(s), _wants(s)])
	if not left.is_empty():
		notes.append(["HEADING OUT", _g("rs_left", ["Heading out: {list}.", "Not coming back: {list}."], {"list": "; ".join(left)}), false])
	if gone_k >= 20:
		notes.append(["PRODUCTION LOST", _g("rs_gonek", ["All told, {k} kills from last season walked out the door.", "That's {k} kills of last year's production now on the open market."], {"k": str(gone_k)}), false])
	if big_keep != null:
		notes.append(["BY THE NUMBERS", _numbers_note(big_keep), false])
	# Around the league.
	var market: Array = _s.departures.filter(func(e): return e["year"] == y and e["team"] != _us)
	market.sort_custom(func(a, b): return a["soldier"].best_ovr() > b["soldier"].best_ovr())
	var names: Array = []
	for e in market.slice(0, 3):
		names.append("%s (%d OVR, from the %s)" % [e["soldier"].display_name(), e["soldier"].best_ovr(), _nick(e["team"])])
	if not names.is_empty():
		notes.append(["THE MARKET", _g("rs_market", ["The best names on the open market: {list}.", "Free agency opens with these names available: {list}."], {"list": "; ".join(names)}), false])
	var need := _need()
	if need != "":
		notes.append(["NEEDS", _g("rs_need", ["The obvious need is at {need}.", "If you're making a shopping list, start with a {need}."], {"need": need}), false])
	notes.append(["CAP SHEET", _cap_line(), true])
	var tail: Array = []
	if big_keep != null:
		var q := _quote(big_keep, "resigned", {})
		tail.append("\"%s\" %s said." % [q, big_keep.last_name])
		art["pull_quote"] = {"text": q, "who": big_keep.display_name(), "team": _us.abbrev}
	art["body"] = _off_body(art, body, notes, tail)
	var rs_rows: Array = kept.map(func(e): return [e["soldier"].short_name(), _money(e["salary"]) + " x" + str(e["years"])])
	var dp_rows: Array = gone.map(func(e): return [e["soldier"].short_name(), "%d OVR" % e["soldier"].best_ovr()])
	art["sidebar"] = [{"title": "Re-signed", "rows": rs_rows if not rs_rows.is_empty() else [["None", ""]]},
		{"title": "Departed", "rows": dp_rows if not dp_rows.is_empty() else [["None", ""]]}]
	return art

## A letter grade for one signing: fit against the starters, price against the market, and age.
func _signing_score(s: Soldier, salary: int) -> float:
	var fit := s.best_ovr() - _avg_starter_ovr(_us)
	var value := float(Contracts.market_value(s)) / maxf(1.0, float(salary))
	return fit * 1.2 + (value - 1.0) * 18.0 - maxf(0.0, s.age - 30.0) * 1.5


static func _letter(score: float) -> String:
	for step in [[8.0, "A"], [5.0, "A-"], [2.0, "B+"], [-1.0, "B"], [-4.0, "B-"], [-7.0, "C+"], [-10.0, "C"], [-14.0, "C-"]]:
		if score >= step[0]:
			return step[1]
	return "D"


func _fa_article(step: String) -> Dictionary:
	var art := _off_art(KIND_FA, step)
	var y := _s.year
	var day: Array = _s.fa.history.filter(func(e): return e["year"] == y and e["when"] == step)
	var ours: Array = day.filter(func(e): return e["team"] == _us)
	var theirs: Array = day.filter(func(e): return e["team"] != _us)
	theirs.sort_custom(func(a, b): return a["salary"] > b["salary"])
	ours.sort_custom(func(a, b): return a["salary"] > b["salary"])
	var body: Array = []
	var notes: Array = []
	var tail: Array = []
	var total := 0.0
	var rows: Array = []
	for e in ours:
		var sc := _signing_score(e["soldier"], e["salary"])
		e["grade"] = _letter(sc)
		total += sc
		rows.append([e["soldier"].short_name(), "%s  %s" % [_money(e["salary"]), e["grade"]]])
	var grade := _letter(total / ours.size()) if not ours.is_empty() else "INC"
	art["grade"] = grade
	var ex := {"step": step, "grade": grade, "n": _num(ours.size())}
	if ours.is_empty():
		art["headline"] = _g("hf_none", ["{us_nick} Sit Out {step}", "Watching the Market Move", "Nothing Doing in {us_city}"], ex)
		body.append(_g("f_none", [
			"The {us_nick} didn't sign anyone on {step}. Maybe that's patience; maybe it's a front office that got outbid. Either way, the roster that walked into the offseason is the one still standing.",
			"{step} came and went without a {us_nick} signing. Grade: incomplete, and the clock is running."], ex))
	else:
		var top: Dictionary = ours[0]
		var s: Soldier = top["soldier"]
		ex["who"] = _who_role(s)
		ex["deal"] = _deal(top["salary"], top["years"])
		ex["ovr"] = str(s.best_ovr())
		ex["age"] = str(s.age)
		ex["from"] = s.former_team
		ex["mv"] = _money(Contracts.market_value(s))
		var returning: bool = (memory.get("season_names", {}) as Dictionary).has(str(s.id))
		if returning:
			art["headline"] = _g("hf_back", ["%s Comes Back" % s.last_name, "{us_nick} Bring %s Home" % s.last_name, "%s Returns, at a Price" % s.last_name], ex)
			ex["lk"] = str(int(memory["season_names"][str(s.id)][1]))
			body.append(_g("f_back", [
				"Days after letting him reach the market, the {us_nick} brought {who} back on {step} at {deal}. He had {lk} kills for them last season, and the going rate said he was worth about {mv}.",
				"{who} is back. The {us_nick} let his contract run out, watched him test the market, and then paid him {deal} to return. His {lk} kills from last season are why."], ex))
		else:
			art["headline"] = _g("hf_sign", ["{us_nick} Land %s" % s.last_name, "%s Signs With {us_nick}" % s.last_name, "{step}: {us_nick} Get Their Man"], ex)
			body.append(_g("f_top", [
				"The {us_poss} big move of {step} was {who}, signed at {deal}. He's {age}, rated {ovr}, and the market said he was worth about {mv}.",
				"{who} is coming to {us_city}. The {us_nick} gave him {deal} on {step}; the going rate for a {ovr}-rated {age}-year-old is around {mv}."], ex))
		var fit := s.best_ovr() - _avg_starter_ovr(_us)
		var value := float(Contracts.market_value(s)) / maxf(1.0, float(top["salary"]))
		var verdict: Array = []
		verdict.append("He's an upgrade on the current starters." if fit >= 2 else ("He slots in about level with the starting group." if fit >= -2 else "He's depth, not a starter, on this roster."))
		verdict.append("And it's a bargain." if value >= 1.15 else ("The price is fair." if value >= 0.9 else "They paid more than they had to."))
		if s.age >= 31:
			verdict.append("At %d, the clock is a real concern." % s.age)
		body.append(" ".join(verdict))
		var rest: Array = []
		for e in ours.slice(1, 4):
			rest.append("%s (%s, %s)" % [_who_role(e["soldier"]), _deal(e["salary"], e["years"]), e["grade"]])
		if not rest.is_empty():
			notes.append(["ALSO SIGNED", _g("f_rest", ["They also added {list}.", "Also signed: {list}."], {"list": "; ".join(rest)}), false])
		notes.append(["BY THE NUMBERS", _numbers_note(s), false])
		var q := _quote(s, "signed", {})
		tail.append("\"%s\" %s said." % [q, s.last_name])
		art["pull_quote"] = {"text": q, "who": s.display_name(), "team": _us.abbrev}
	art["dek"] = _cap_first(_g("hf_dek", ["{step} grade: {grade}.", "Our {step} grade for the {us_nick}: {grade}."], ex))
	var big: Array = []
	var old_names: Dictionary = memory.get("season_names", {})
	for e in theirs:
		var key := str(e["soldier"].id)
		if old_names.has(key):
			notes.append(["FAMILIAR FACE", _g("f_ex", ["One familiar name moved: {who}, who had {k} kills for the {us_nick} last season, signed with the {t} at {deal}.",
				"{who} is officially gone. The former {us_nick} {role} signed with the {t} for {deal}."],
				{"who": e["soldier"].display_name(), "k": str(old_names[key][1]), "role": old_names[key][2], "t": _nick(e["team"]), "deal": _deal(e["salary"], e["years"])}), false])
			theirs.erase(e)
			break
	for e in theirs.slice(0, 3):
		big.append("the %s signed %s (%d OVR) at %s" % [_nick(e["team"]), e["soldier"].display_name(), e["soldier"].best_ovr(), _deal(e["salary"], e["years"])])
	if not big.is_empty():
		notes.append(["AROUND THE LEAGUE", _cap_first(_g("f_big", ["Elsewhere, {list}.", "Around the league, {list}."], {"list": "; ".join(big)})), false])
	var pool: Array = _s.league.free_agents.duplicate()
	pool.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	var left: Array = []
	for s in pool.slice(0, 3):
		left.append("%s (%d OVR, age %d), who %s" % [s.display_name(), s.best_ovr(), s.age, _wants(s)])
	if not left.is_empty():
		notes.append(["STILL AVAILABLE", _g("f_left", ["Still on the board: {list}.", "Best still available: {list}."], {"list": "; ".join(left)}), false])
	var need := _need()
	if need != "":
		notes.append(["NEEDS", _g("f_need", ["The {us_nick} still look thin at {need}.", "The need at {need} hasn't gone away."], {"need": need}), false])
	notes.append(["CAP SHEET", _cap_line(), true])
	art["body"] = _off_body(art, body, notes, tail)
	art["sidebar"] = [{"title": "Signings (grade %s)" % grade, "rows": rows if not rows.is_empty() else [["None", ""]]},
		{"title": "Best Available", "rows": pool.slice(0, 5).map(func(s): return [s.short_name(), "%d OVR" % s.best_ovr()])}]
	return art


func _draft_article() -> Dictionary:
	var art := _off_art(KIND_DRAFT, "Draft")
	var picks: Array = _s.draft.picks()
	var ours: Array = picks.filter(func(p: Prospect): return p.drafted_by == _us)
	var body: Array = []
	var notes: Array = []
	var tail: Array = []
	var verdicts := 0.0
	var first: Prospect = ours[0] if not ours.is_empty() else null
	if first != null:
		var s := first.soldier
		var diff := first.pick_number - first.projected_rank
		verdicts += diff
		var ex := {"who": s.display_name(), "pick": _ord(first.pick_number), "proj": _ord(first.projected_rank), "age": str(s.age),
			"role": String(Scheme.ROLE_NAMES[first.listed_role]).to_lower(), "home": LeagueData.state_name(s.home_state) if s.home_state != "" else ""}
		_seen[s.id] = true
		if diff >= 5:
			art["headline"] = _g("hd_steal", ["A Steal at %s" % _ord(first.pick_number), "{us_nick} Wait, and Win", "%s Falls to {us_nick}" % s.last_name], ex)
			body.append(_g("d_steal", ["The {us_nick} let the board come to them and it paid off. {who}, a {role} most boards had going {proj}, was still there at {pick}.",
				"Somebody else's mistake is the {us_poss} gain. {who}, projected {proj}, slid to them at {pick}."], ex))
		elif diff <= -5:
			art["headline"] = _g("hd_reach", ["{us_nick} Reach for %s" % s.last_name, "A Gamble at %s" % _ord(first.pick_number), "%s? Already?" % s.last_name], ex)
			body.append(_g("d_reach", ["The {us_nick} went off the board early, taking {who} at {pick}. Most projections had him around {proj}. They'd better be right.",
				"This one will be debated. {who}, a {role} projected {proj}, went {pick} to the {us_nick}."], ex))
		else:
			art["headline"] = _g("hd_fair", ["{us_nick} Take %s" % s.last_name, "%s Comes to {us_city}" % s.last_name, "Draft Day: {us_nick} Add %s" % s.last_name], ex)
			body.append(_g("d_fair", ["With the {pick} pick the {us_nick} took {who}, a {age}-year-old {role}, right about where the boards had him.",
				"The {us_nick} took {who} at {pick}. No surprise there: he was projected {proj}."], ex))
		if first.phenom:
			notes.append(["THE TAG", _g("d_phenom", ["Scouts called him a phenom, and the tape doesn't argue.", "He came in with the phenom tag, and that label carries expectations."]), false])
		var pex := {"ovr": str(s.best_ovr()), "pot": s.potential_letter(), "ceil": str(s.potential_ovr()), "last": s.last_name}
		if not s.potential_known():
			# A fresh pick's ceiling is a scouting range, not a number the club has.
			notes.append(["THE CEILING", _g("d_pot_unk", ["He's a {ovr} today. How high he can go is anyone's guess until he gets reps with the club.",
				"Right now {last} is a {ovr}. The ceiling is unknown: the staff won't have a read on it until he's had some practice time."], pex), false])
		elif s.potential_grade() >= 3:
			notes.append(["THE CEILING", _g("d_pot_hi", ["He's a {ovr} today with {pot}-grade potential, and the staff's projections have him topping out around {ceil}.",
				"Right now {last} is a {ovr}. The ceiling is the selling point: a {pot} potential grade and a projected peak near {ceil}."], pex), false])
		else:
			notes.append(["THE CEILING", _g("d_pot_lo", ["He's a {ovr} with a {pot} potential grade, which makes him more of a depth piece than a future star.",
				"The ceiling is modest, a {pot} potential grade and a projected peak around {ceil}, so the {us_nick} are betting on what he is now."], pex), false])
		var need := _need()
		if need != "" and need == ex["role"]:
			notes.append(["THE FIT", _g("d_fit", ["It's a pick for a need, too: {role} was the thinnest spot on the depth chart.", "And it fills a hole. The {us_nick} were short at {role}."], ex), false])
		elif need != "":
			notes.append(["THE FIT", _g("d_nofit", ["It doesn't fix the shortage at {need}, though. That'll have to come from somewhere else.", "The {need} spot is still thin after this one."], {"need": need}), false])
		if ex["home"] != "" and s.home_state == _us.home_state:
			notes.append(["HOMETOWN", _g("d_local", ["He's a {home} kid, too, which the fans will like.", "And he's from {home}, so he'll have a crowd."], ex), false])
		var q := _quote(s, "drafted", {})
		tail.append("\"%s\" %s said." % [q, s.last_name])
		art["pull_quote"] = {"text": q, "who": s.display_name(), "team": _us.abbrev}
	else:
		art["headline"] = _g("hd_none", ["No Picks, No Problem?", "{us_nick} Sit Out the Draft"])
		body.append(_g("d_none", ["The {us_nick} didn't make a pick, having traded away their selections.", "The draft went on without the {us_nick}, who had no picks."]))
	var rest: Array = []
	for p in ours.slice(1, 4):
		verdicts += p.pick_number - p.projected_rank
		var tag := " (a steal)" if p.pick_number - p.projected_rank >= 5 else (" (a reach)" if p.projected_rank - p.pick_number >= 5 else "")
		rest.append("%s at %s%s" % [p.soldier.display_name(), _ord(p.pick_number), tag])
	if not rest.is_empty():
		notes.append(["LATER ON", _g("d_rest", ["Later on: {list}.", "They also took {list}."], {"list": "; ".join(rest)}), false])
	if not picks.is_empty():
		var top: Prospect = picks[0]
		if top.drafted_by != _us:
			notes.append(["TOP OF THE BOARD", _g("d_top", ["The first pick went to the {t}, who took {who}.", "{who} went first overall, to the {t}."],
				{"t": _nick(top.drafted_by), "who": top.soldier.display_name()}), false])
	var slide: Prospect = null
	var slide_gap := 0
	for p: Prospect in picks:
		if p.pick_number - p.projected_rank > slide_gap and p.drafted_by != null:
			slide_gap = p.pick_number - p.projected_rank
			slide = p
	if slide != null and slide_gap >= 8:
		notes.append(["BIGGEST SLIDE", _g("d_slide", ["{who} was projected {proj} and fell to {pick}, where the {t} took him.", "The night's biggest slide: {who}, a {proj} on the board, went {pick} to the {t}."],
			{"who": slide.soldier.display_name(), "proj": _ord(slide.projected_rank), "pick": _ord(slide.pick_number), "t": _nick(slide.drafted_by)}), false])
	var grade := _letter(verdicts / maxf(1.0, ours.size()) * 0.8) if not ours.is_empty() else "INC"
	art["grade"] = grade
	art["dek"] = "Draft grade: %s." % grade
	art["body"] = _off_body(art, body, notes, tail)
	art["sidebar"] = [{"title": "%s Picks" % _us.abbrev, "rows": ours.map(func(p): return [p.soldier.short_name(), "#%d (proj %d)" % [p.pick_number, p.projected_rank]])}]
	return art


func _review_article() -> Dictionary:
	var art := _off_art(KIND_REVIEW, "Roster Review")
	var y := _s.year
	var cuts: Array = _s.trades.moves.filter(func(e): return e["year"] == y and e["team"] == _us and e["kind"] == &"cut")
	var adds: Array = _s.fa.history.filter(func(e): return e["year"] == y and e["when"] == "Roster Review" and e["team"] == _us)
	var body: Array = []
	var notes: Array = []
	art["headline"] = _g("hv", ["Taking Shape", "The Roster, Before Camp", "{us_nick} Set Their Group"])
	var ad_w := _num(adds.size()) if adds.size() > 0 else "no"
	var ct_w := _num(cuts.size()) if cuts.size() > 0 else "no"
	art["dek"] = _cap_first("%s late signing%s, %s cut%s, and a first look at the lineup." % [ad_w, "" if adds.size() == 1 else "s", ct_w, "" if cuts.size() == 1 else "s"])
	body.append(_g("v_open", ["With the draft done and the market thinning out, the {us_nick} have roughly the roster they'll take into camp.",
		"Roster review week is where offseason plans meet the cap sheet, and the {us_nick} came out of it with a group that looks like this."]))
	if not adds.is_empty():
		notes.append(["LATE ADDITIONS", _g("v_add", ["Late additions: {list}.", "They added {list} in the final free-agent window."],
			{"list": ", ".join(adds.map(func(e): return "%s (%s)" % [_who_role(e["soldier"]), _money(e["salary"])]))}), false])
	if not cuts.is_empty():
		notes.append(["THE CUTS", _g("v_cut", ["Released: {list}.", "The cuts: {list}."], {"list": ", ".join(cuts.map(func(e): return _who_role(e["soldier"])))}), false])
	var by_role := {}
	var order: Array = []
	for slot in _us.scheme.slot_ids():
		var s: Soldier = _us.lineup.get(slot)
		if s == null:
			continue
		var lbl := _us.scheme.label_for_slot(slot).to_lower()
		if not by_role.has(lbl):
			by_role[lbl] = []
			order.append(lbl)
		by_role[lbl].append("%s (%d)" % [_who(s), s.best_ovr()])
	if not order.is_empty():
		var groups: Array = []
		for lbl in order:
			var ns: Array = by_role[lbl]
			groups.append("%s at %s" % [_join_and(ns), lbl])
		notes.append(["PROJECTED STARTERS", _g("v_five", ["Projected starters in the {us_scheme}: {list}.", "If camp started today, the {us_scheme} would line up {list}."], {"list": "; ".join(groups)}), false])
	var last: Dictionary = memory.get("last_season", {})
	if last.has("starter_ovr"):
		var now := _avg_starter_ovr(_us)
		var d := now - float(last["starter_ovr"])
		var vex := {"now": "%.1f" % now, "then": "%.1f" % float(last["starter_ovr"]), "d": "%.1f" % absf(d)}
		if d >= 1.0:
			notes.append(["ON PAPER", _g("v_up", ["On paper that's better than last year: the starters average {now}, up from {then}.", "The starting group averages {now}, {d} points better than the one that finished last season."], vex), false])
		elif d <= -1.0:
			notes.append(["ON PAPER", _g("v_dn", ["On paper it's a step back: the starters average {now}, down from {then}.", "The starters average {now}, {d} points worse than last year's group. Camp has work to do."], vex), false])
		else:
			notes.append(["ON PAPER", _g("v_eq", ["The starters average {now}, about where last year's group finished ({then}).", "On paper it's the same team as last year: {now} against {then}."], vex), false])
	notes.append(["CAP SHEET", _cap_line(), true])
	var snap := {}
	for s in _us.roster:
		snap[str(s.id)] = s.best_ovr()
	memory["camp_ovr"] = snap
	art["body"] = _off_body(art, body, notes, [])
	art["sidebar"] = [{"title": "Roster", "rows": _top_ovr(_us, 12).map(func(s): return [s.short_name(), "%d OVR, %d" % [s.best_ovr(), s.age]])}]
	return art


static func _camp_better(a: Dictionary, b: Dictionary) -> bool:
	var da := int(a["ovr_after"]) - int(a["ovr_before"])
	var db := int(b["ovr_after"]) - int(b["ovr_before"])
	return da > db or (da == db and int(a["points"]) > int(b["points"]))


func _camp_article() -> Dictionary:
	var art := _off_art(KIND_CAMP, "Camp")
	var res: Dictionary = _s.camp.team_results(_us) if _s.camp != null else {}
	var drills: Array = res.values()
	drills.sort_custom(_camp_better)
	var body: Array = []
	var notes: Array = []
	if drills.is_empty():
		art["headline"] = _g("hc_none", ["Camp, Such As It Was", "An Empty Practice Field"])
		art["dek"] = "No drills were run in %s." % _f["us_city"]
		body.append(_g("c_none", ["The {us_nick} didn't run a single camp drill, which means the roster that shows up in Week 1 is the one that left last season.",
			"Camp came and went in {us_city} without anybody running a drill. Every other team got better this week; the {us_nick} stood still."]))
		art["body"] = body
		art["sidebar"] = [{"title": "Camp Drills", "rows": [["None run", ""]]}]
		return art
	var top: Dictionary = drills[0]
	var s: Soldier = top["soldier"]
	var gains: Dictionary = top["gains"]
	var best_st: StringName = &""
	for st in gains:
		if best_st == &"" or int(gains[st]) > int(gains[best_st]):
			best_st = st
	var ex := {"who": _who_role(s), "drill": Camp.drill_name(top["group"]), "pts": _plural(int(top["points"]), "point"),
		"o1": str(int(top["ovr_before"])), "o2": str(int(top["ovr_after"])), "age": str(s.age),
		"stat": String(Stats.LABELS.get(best_st, str(best_st))).to_lower().replace(" acc", " accuracy").replace("short range", "short-range").replace("medium range", "medium-range").replace("long range", "long-range") if best_st != &"" else "his game",
		"blurb": String(Camp.DRILLS[top["group"]]["blurb"]).to_lower().trim_suffix(".")}
	var jumped := int(top["ovr_after"]) > int(top["ovr_before"])
	if jumped:
		art["headline"] = _g("hc_up", ["%s Turns Heads in Camp" % s.last_name, "The Talk of Camp: %s" % s.last_name, "%s Comes Back Better" % s.last_name], ex)
		body.append(_g("c_up", [
			"Every camp has a story, and this year's in {us_city} is {who}. He went through the {drill} ({blurb}) and came out {pts} better, most of it in {stat}. He's now a {o2}, up from {o1}.",
			"{who} walked into the {drill} a {o1} and walked out a {o2}. The {age}-year-old banked {pts}, and the biggest jump came in {stat}."], ex))
	else:
		art["headline"] = _g("hc_flat", ["Camp Breaks With Small Gains", "Inches, Not Leaps", "A Workmanlike Camp"], ex)
		body.append(_g("c_flat", [
			"Nobody took a leap in {us_city}. The best of camp was {who} in the {drill}: {pts}, mostly {stat}, though not quite enough to move his {o1} rating.",
			"It was a camp of small steps. {who} got the most out of the {drill}, adding {pts}, but his overall stayed at {o1}."], ex))
	var others: Array = []
	for d in drills.slice(1, 6):
		var ds: Soldier = d["soldier"]
		var delta := int(d["ovr_after"]) - int(d["ovr_before"])
		others.append("%s in the %s (%s%s)" % [_who(ds), Camp.drill_name(d["group"]), _plural(int(d["points"]), "point"),
			", now a %d" % int(d["ovr_after"]) if delta > 0 else ""])
	if not others.is_empty():
		notes.append(["THE DRILLS", _g("c_more", ["The rest of the camp assignments: {list}.", "Elsewhere on the practice field: {list}."], {"list": "; ".join(others)}), false])
	var skipped := Camp.DRILLS.size() - drills.size()
	if skipped > 0:
		notes.append(["UNUSED DRILLS", _g("c_skip", ["{n} of the six drills went unused, which is points left on the table.", "They left {n} drills unrun."],
			{"n": _cap_first(_num(skipped)) if skipped > 1 else "One"}), false])
	var net := 0
	var risers := 0
	for d in drills:
		var dl := int(d["ovr_after"]) - int(d["ovr_before"])
		net += dl
		if dl > 0:
			risers += 1
	if risers > 0:
		notes.append(["THE NET", _g("c_net", ["{n} of the {m} players who drilled came out higher, {pts} in all.", "Across the roster camp added {pts}, spread over {n} players."],
			{"n": _num(risers), "m": _num(drills.size()), "pts": _plural(net, "rating point")}), false])
	var q := _quote(s, "camp", {})
	var tail: Array = ["\"%s\" %s said." % [q, s.last_name]]
	art["pull_quote"] = {"text": q, "who": s.display_name(), "team": _us.abbrev}
	art["dek"] = _cap_first(_g("hc_dek", ["{who} leads the way after the {drill}.", "{drill} report: {pts} for {who}."], {"who": s.last_name, "drill": ex["drill"], "pts": ex["pts"]}))
	art["body"] = _off_body(art, body, notes, tail)
	art["sidebar"] = [{"title": "Camp Drills", "rows": drills.map(func(d): return [d["soldier"].short_name(),
		"%s  +%d" % [Camp.drill_name(d["group"]), int(d["points"])]])}]
	return art


func _preseason_article() -> Dictionary:
	var art := {"kind": KIND_PRESEASON, "section": "%s %s PREVIEW" % [_f["us_nick"].to_upper(), _f["year"]], "angles": ["preseason"]}
	var teams: Array = _s.league.teams.duplicate()
	teams.sort_custom(func(a: Team, b: Team): return a.team_ovr() > b.team_ovr())
	var pos := teams.find(_us) + 1
	var last: Dictionary = memory.get("last_season", {})
	var ex := {"pos": _ord(pos), "n": str(teams.size()), "ovr": str(_us.team_ovr()), "last_rec": last.get("record", ""),
		"last_fin": last.get("finish", "")}
	var tier := "contender" if pos <= 4 else ("bubble" if pos <= teams.size() / 2 else "rebuild")
	art["headline"] = _g("hp_" + tier, {"contender": ["Built to Win Now", "Expectations: Title", "The Window Is Open"],
		"bubble": ["Somewhere in the Middle", "A Season on the Bubble", "Prove It"],
		"rebuild": ["A Long Way to Go", "Patience Required", "Building, Again"]}[tier], ex)
	art["dek"] = _cap_first("By the ratings, the %s are %s of %s." % [_f["us_nick"], ex["pos"], ex["n"]])
	var body: Array = []
	var notes: Array = []
	if not last.is_empty():
		body.append(_g("pr_last", ["Last year the {us_nick} went {last_rec} and {last_fin}. On paper, this year's roster rates {pos} of {n} in the league.",
			"After a {last_rec} season in which they {last_fin}, the {us_nick} open {year} rated {pos} of {n}."], ex))
		var old_names: Dictionary = memory.get("season_names", {})
		var now_ids := {}
		for s in _us.roster:
			now_ids[str(s.id)] = true
		var gone: Array = []
		for key in old_names:
			if not now_ids.has(key):
				gone.append(old_names[key])
		gone.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
		if not gone.is_empty():
			var gk := 0
			for g in gone:
				gk += int(g[1])
			var names: Array = gone.slice(0, 3).map(func(g): return "%s (%d kills)" % [g[0], int(g[1])] if int(g[1]) > 0 else String(g[0]))
			notes.append(["GONE", _g("pr_gone", ["Gone from last year's roster: {list}. That's {k} kills to replace.",
				"The departures matter: {list}, {k} kills between them."] if gk > 0 else ["Gone from last year's roster: {list}."],
				{"list": _join_and(names), "k": str(gk)}), false])
	else:
		body.append(_g("pr_first", ["The {us_full} open {year} rated {pos} of {n} in the league, with a team OVR of {ovr}.",
			"Here's where the {us_nick} start: {pos} of {n} by the ratings, a {ovr} team OVR."], ex))
	var old_ids: Array = memory.get("season_roster", [])
	var new_faces: Array = _us.roster.filter(func(s: Soldier): return not old_ids.is_empty() and not old_ids.has(s.id))
	new_faces.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	if not new_faces.is_empty():
		notes.append(["NEW FACES", _g("pr_new", ["The new faces: {list}.", "Arrivals to know: {list}."],
			{"list": ", ".join(new_faces.slice(0, 4).map(func(s): return "%s (%d)" % [_who_role(s), s.best_ovr()]))}), false])
	var star := _top_ovr(_us, 1)
	if not star.is_empty():
		var s: Soldier = star[0]
		notes.append(["THE FACE", _g("pr_star", ["It all still runs through {who}, the roster's best at {ovr}.", "The best player on the roster is {who}, a {ovr}."],
			{"who": _who_role(s), "ovr": str(s.best_ovr())}), false])
	var vets: Array = _us.roster.filter(func(s: Soldier): return s.age >= 33 and s.contract != null and s.contract.is_expiring())
	if not vets.is_empty():
		notes.append(["LAST RIDE", _g("pr_vet", ["Watch {who}, {age} and in the last year of his deal. This could be the last ride.", "{who} is {age} and playing out his contract."],
			{"who": _who_role(vets[0]), "age": str(vets[0].age)}), false])
	notes.append(["THE SCHEME", _g("pr_scheme", ["They'll run the {us_scheme}.", "The plan is the {us_scheme}."]) + " " + String(Scheme.BLURBS.get(_us.scheme.id, "")), false])
	notes.append(["THE MOOD", _buzz_pre_para(), false])
	notes.append(["PREDICTION", _season_call(pos, teams.size()), false])
	notes.append(["WEEK 1", _preview_para(1), true])
	var tail: Array = []
	var q_s: Soldier = star[0] if not star.is_empty() else null
	if q_s != null:
		var q := _quote(q_s, "camp", {})
		tail.append("\"%s\" %s said." % [q, q_s.last_name])
		art["pull_quote"] = {"text": q, "who": q_s.display_name(), "team": _us.abbrev}
	art["body"] = _off_body(art, body, notes, tail)
	art["sidebar"] = [{"title": "Power Ratings", "rows": teams.slice(0, 8).map(func(t): return [t.abbrev, str(t.team_ovr())])}, _buzz_box()]
	return art

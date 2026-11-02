extends "res://scripts/season/news/news_voice.gd"
## Stories that need more than this week's match: honors, MVP runs, career milestones, hot and cold
## stretches, reunions with old clubs and the franchise record book. Each story is a row in STORIES (its
## words) and a check method `_chk_<id>(g)` that returns {} when it does not apply or {score, ex} when it
## does. `ex` carries the facts the words quote (and `v`, the variant of the words to use). The game
## article scores the stories against its other angles and lets the biggest lead.
##
## A pool is an Array of phrases, or a Dictionary of variant -> Array when the story reads differently
## depending on the facts. Parts: headline, dek, lede (opens the piece) and body (the paragraph that
## follows it, or the side note when another angle leads).

const STORIES := {
	"potw_ours": {
		"tag": "Honor",
		"headline": {
			"first": ["{last} Is the League's Player of the Week", "Player of the Week: {last} Delivers for {us_nick}", "{last} Takes the League's Top Honor for the Week"],
			"repeat": ["{last} Wins Player of the Week Again", "Another Weekly Honor for {last}", "{last} Collects His {nth} Player of the Week"],
			"b2b": ["Back-to-Back: {last} Is Player of the Week Again", "Two Weeks, Two Awards for {last}", "{last} Repeats as Player of the Week"]},
		"dek": {
			"first": ["{k}-{d} with {a}: no line in the league was better this week.", "The league named {last} its Player of the Week after a {k}-{d} night."],
			"repeat": ["It is the {nth} time this season the league has singled {last} out.", "{k}-{d} with {a} earned {last} the weekly award once more."],
			"b2b": ["For the second week running, nobody's line in the league beat {last}'s.", "{k}-{d} with {a} makes it two straight weekly awards."]},
		"lede": {
			"first": ["{who} was the best player in the league this week, and the league made it official: Player of the Week, off a {k}-{d} line with {a}.",
				"Nobody was better. {who} went {k}-{d} with {a} and was named the league's Player of the Week."],
			"repeat": ["{who} has now been Player of the Week {times} this season. This one came on a {k}-{d} night with {a}.",
				"The weekly award keeps finding {who}: {times} this season now, the latest on a {k}-{d} line with {a}."],
			"b2b": ["It is two in a row for {who}, Player of the Week for a second straight week after a {k}-{d} night with {a}.",
				"{who} was named Player of the Week for the second week running ({k}-{d}, {a}), and the {us_nick} are happy to keep collecting."]},
		"body": ["He earned it {outcome}, and weeks like that tend to follow a player into the next one.",
			"The line came {outcome}. {last} has {won_n} this season.",
			"It is the kind of honor that gets a player talked about around the league, and {last} is being talked about."],
		"side": ["{who} was also named the league's Player of the Week, off a {k}-{d} line with {a}.", "The league made {who} its Player of the Week, too: {k}-{d}, {a}."]},
	"mvp_streak": {
		"tag": "Streak",
		"headline": {
			"two": ["{last} Is MVP Again", "Back-to-Back MVP Matches for {last}", "{last} Keeps Winning the Night"],
			"three": ["{last}'s MVP Streak Reaches {n}", "Three Straight: {last} Is the Match MVP Again", "{last} Won't Be Slowed: MVP for the {nth} Match Running"],
			"long": ["{last} Makes It {n} Straight as Match MVP", "The {last} Streak: {n} MVP Matches in a Row", "{n} in a Row: {last} Owns the MVP Award"]},
		"dek": {
			"two": ["That's two matches running in which no one on either side was better than {last}.", "{last} was the match MVP for a second straight match."],
			"three": ["{n} matches in a row now, {last} has been the best player on the floor.", "{last} has been the match MVP for {n} straight matches."],
			"long": ["{last} has been the match MVP in {n} straight matches, and the streak is the story of the {us_nick}'s season.",
				"{n} straight MVP matches. Nobody has taken the award from {last} in a while."]},
		"lede": {
			"two": ["{who} was the MVP again. That's two matches running in which no one on either side was better, and this one was {k}-{d} with {a} {outcome}.",
				"For the second match in a row, {who} was the best player on the floor: {k}-{d}, {a} {outcome}."],
			"three": ["{who} has now been the MVP of {n} matches in a row. This time it was {k}-{d} with {a} {outcome}.",
				"{who} is the match MVP again, the {nth} time running, off a {k}-{d} line with {a} {outcome}."],
			"long": ["{who} has been the MVP of {n} straight matches. The latest was {k}-{d} with {a} {outcome}, and the streak keeps going.",
				"It is {n} in a row. {who} went {k}-{d} with {a} {outcome} and the MVP award has not left his hands."]},
		"body": {
			"two": ["Two in a row is a start, and {last} has made it look like more than that.", "It is not a streak yet, but {last} has been the best player on the floor twice running."],
			"three": ["A run like that gets noticed around the league. {last} has been the MVP in {nw} straight matches, and the question each week now is whether anyone can slow him down.",
				"The {us_nick} have a player in a groove. {last}, MVP in {nw} matches running, keeps finding the biggest moments of the night."],
			"long": ["A run like that gets noticed around the league. {last} has been the MVP in {nw} straight matches, and the question each week now is whether anyone can slow him down.",
				"Streaks end, but nothing about {last}'s last {nw} matches suggests this one is close to done."]},
		"side": ["{who} was the match MVP for the {nth} match in a row.", "{who} took the match MVP award again, {nw} straight now."]},
	"milestone": {
		"tag": "Milestone",
		"headline": ["{last} Reaches {n} {what}", "Milestone Night: {last} Passes {n} {what}", "{n} and Counting for {last}"],
		"dek": ["{last} crossed the mark {outcome}, with {k} kills and {a}.", "The milestone came {outcome}: {k} kills and {a} for {last}."],
		"lede": ["{who} passed {n} {what} this week, getting there with {k} kills and {a} {outcome}.",
			"The number is {n}. {who} crossed {n} {what} {outcome}, and it will be on the wall soon enough."],
		"body": ["Numbers like that don't come from one big night. {last} sits at {total} {what} now, and he is still adding to it.",
			"{last} is up to {total} {what}, a mark that took seasons of showing up."],
		"side": ["{who} passed {n} {what} along the way.", "{who} also crossed {n} {what}."]},
	"hot_run": {
		"tag": "Form",
		"headline": ["{last} Is Locked In", "{last} Keeps Stacking Big Nights", "Hot Hand: {last} Strings Together Another One"],
		"dek": ["{last} has finished well ahead on kills over deaths in {nw} straight matches.", "{tk} kills against {td} deaths over {nw} matches: {last} is on a run."],
		"lede": ["{who} is on a heater. Over his last {nw} matches he has {tk} kills against {td} deaths, and this week was part of it: {k}-{d} {outcome}.",
			"The {us_nick} have a hot hand in {who}: {tk}-{td} across his last {nw} matches, including {k}-{d} {outcome}."],
		"body": ["Hot streaks have a way of ending, but {last} gives no sign of cooling off. {tk}-{td} over {nw} matches is the kind of stretch coaches build plans around.",
			"{last} has made the last {nw} matches look easy, and the opposition has run out of ways to hide from him."],
		"side": ["{who} is hot: {tk}-{td} over his last {nw} matches.", "{who} has been the steadiest piece of it, {tk}-{td} over his last {nw}."]},
	"slump": {
		"tag": "Slump",
		"headline": ["Questions Grow Around {last}", "{last} Is Struggling", "The Search for Answers: {last} in a Slump"],
		"dek": ["{last} has finished with more deaths than kills in {nw} straight matches.", "{tk} kills against {td} deaths over {nw} matches: the {us_nick} need more from {last}."],
		"lede": ["{who}, rated {ovr}, has more deaths than kills in {nw} straight matches, and this week was {k}-{d} {outcome}.",
			"It has been {nw} matches since {who} had the better of the kill count. This time it was {k}-{d} {outcome}."],
		"body": ["A slump from a starter this highly rated is rarely about talent. The staff has to decide whether to wait it out or look at the bench.",
			"{last} is {ovr} on paper, and the paper and the scoreboard have stopped agreeing. Over {nw} matches it is {tk}-{td}."],
		"side": ["{who} is {tk}-{td} over his last {nw} matches and has not found his form.", "{who}, rated {ovr}, is {tk}-{td} over {nw} matches. That is not the player on the roster sheet."]},
	"reunion": {
		"tag": "Reunion",
		"headline": ["{last} Meets His Old Team", "Reunion Night: {last} Against the Club That Had Him", "Homecoming of a Kind for {last}"],
		"dek": {
			"theirs_good": ["{last} played for the {us_nick} {when_there}. This week he was the one beating them up: {k}-{d}.", "A former {us_nick} player, {last} went {k}-{d} for the {them_nick}."],
			"theirs_bad": ["{last} played for the {us_nick} {when_there}, and the reunion did not go well for him: {k}-{d}.", "A former {us_nick} player, {last} was held to {k}-{d} for the {them_nick}."],
			"ours_good": ["{last} played for the {them_nick} {when_there}, and he made them pay: {k}-{d}.", "Facing his old club, {last} went {k}-{d} for the {us_nick}."],
			"ours_bad": ["{last} played for the {them_nick} {when_there}, and the reunion was a quiet one: {k}-{d}.", "Facing his old club, {last} was held to {k}-{d}."]},
		"lede": {
			"theirs_good": ["{who} spent {when_there} with the {us_nick}. This week he was on the other side, and he went {k}-{d} for the {them_nick}.",
				"{who} knows this club. He wore the {us_nick} colors {when_there}, and this week he used what he learned: {k}-{d} for the {them_nick}."],
			"theirs_bad": ["{who} spent {when_there} with the {us_nick}. This week he was on the other side, and the {us_nick} held him to {k}-{d}.",
				"{who} came back to face his old team, and it went badly: {k}-{d} for the {them_nick}."],
			"ours_good": ["{who} spent {when_there} with the {them_nick}, and he got to face them this week. He went {k}-{d} for the {us_nick}.",
				"{who} played for the {them_nick} {when_there}. This week he faced them and came out {k}-{d}."],
			"ours_bad": ["{who} spent {when_there} with the {them_nick} and got to face them this week. It was a quiet one: {k}-{d}.",
				"{who} played for the {them_nick} {when_there}. The reunion went by without much fanfare, {k}-{d}."]},
		"body": ["Matches against an old club carry an extra weight, and nobody pretends otherwise. {last} knew who was on the other side.",
			"There is always a little more in it when a player faces the team that used to employ him, and the match, {outcome_gs}, was no exception."],
		"side": ["{who} faced his old club, the {old}, and went {k}-{d}.", "{who} played against the {old}, his club {when_there}, and finished {k}-{d}."]},
	"franchise_book": {
		"tag": "Record",
		"headline": ["{last} Cracks the {us_nick} Record Book", "{last} Climbs the Franchise Books", "A Place in {us_nick} History for {last}"],
		"dek": ["{vl} {noun} {outcome} is {rankp} single-match mark in club history.", "{last}'s {vl} {noun} now sits in the franchise record book."],
		"lede": ["{who} put his name in the {us_nick} record book this week: {vl} {noun} {outcome} is {rankp} single-match mark in franchise history.",
			"{who} owns {rankp} single-match performance in {us_nick} history for {what}: {vl} {noun} {outcome}."],
		"body": ["Franchise records are the kind of thing a club holds onto, and this one is {last}'s now.",
			"Nights like that are rare enough to be written down. {last}'s was written down."],
		"side": ["{who}'s {vl} {noun} is {rankp} single-match mark in {us_nick} history.", "{who} also moved into the {us_nick} record book with {vl} {noun}."]},
}

## Career marks that make news, in order. Each: [stat key, what it counts, thresholds].
const MILESTONES := [
	["kills", "career kills", [100, 250, 500, 750, 1000, 1500, 2000, 2500, 3000, 4000, 5000]],
	["assists", "career assists", [100, 250, 500, 750, 1000, 1500, 2000]],
	["mvps", "career MVP awards", [10, 25, 50, 75, 100]],
]
const RANK_PHRASE := ["the best", "the second-best", "the third-best", "the fourth-best", "the fifth-best"]


## The `part` ("headline", "dek", "lede", "body") of story `id` for this match's facts.
func _story_text(part: String, id: String, g: Dictionary) -> String:
	var ex: Dictionary = (g["stories"][id] as Dictionary).duplicate()
	var so: Soldier = ex.get("so")
	if so != null:
		ex["who"] = _who(so) if part != "headline" and part != "dek" else so.last_name
		ex["last"] = so.last_name
	var pools: Variant = (STORIES[id] as Dictionary)[part]
	var v := String(ex.get("v", "any"))
	var pool: Array = pools[v] if pools is Dictionary else pools
	return _g("st_%s_%s_%s" % [id, part, v], pool, ex)


## The scalar facts a story quoted, kept on the issue (soldier by id) so what it claimed can be checked later.
func _story_record(id: String, g: Dictionary) -> Dictionary:
	var out := {"id": id, "year": _s.year, "week": (g["m"] as ScheduledMatch).week}
	var ex: Dictionary = g["stories"][id]
	for k in ex:
		var v: Variant = ex[k]
		if v is Soldier:
			out["sid"] = (v as Soldier).id
		elif v is int or v is float or v is String or v is bool:
			out[k] = v
	return out


## The facts every story shares: how the match went, from our side ("in a win over the Foxes").
func _story_outcome(g: Dictionary) -> Dictionary:
	var them := _nick(g["them"])
	return {"outcome": ("in a win over the %s" % them) if g["won"] else ("in a loss to the %s" % them),
		"outcome_gs": ("a %s win" % _f["gs_w"]) if g["won"] else ("a %s loss" % _f["gs_w"])}


## Runs every story check against the match facts. Returns {id: score} and fills g["stories"][id] = ex.
func _story_scores(g: Dictionary) -> Dictionary:
	var scores := {}
	g["stories"] = {}
	for id: String in STORIES:
		var r: Dictionary = call("_chk_" + id, g)
		if r.is_empty():
			continue
		var ex: Dictionary = r["ex"]
		ex.merge(_story_outcome(g))
		g["stories"][id] = ex
		scores[id] = float(r["score"])
	return scores


static func _commas(n: int) -> String:
	var s := str(n)
	for i in range(s.length() - 3, 0, -3):
		s = s.insert(i, ",")
	return s


func _line_ex(e: Dictionary) -> Dictionary:
	var line: Dictionary = e["line"]
	return {"so": e["s"], "k": int(line["kills"]), "d": int(line["deaths"]), "a": _plural(int(line["assists"]), "assist")}


func _chk_potw_ours(g: Dictionary) -> Dictionary:
	var e := NewsHistory.potw_of(history, _s.year, (g["m"] as ScheduledMatch).week)
	if e.is_empty() or e["team"] != _us.abbrev:
		return {}
	var so: Soldier = _ids.get(int(e["id"]))
	if so == null:
		return {}
	var n := NewsHistory.potw_count(history, so.id, _s.year)
	var b2b := NewsHistory.potw_back_to_back(history, so.id)
	var ex := {"so": so, "v": "b2b" if b2b else ("repeat" if n > 1 else "first"), "k": int(e["k"]), "d": int(e["d"]), "a": _plural(int(e["a"]), "assist"),
		"n": n, "nth": _ord_word(n), "times": _plural(n, "time"), "won_n": "%s Player of the Week %s" % [_num(n), "award" if n == 1 else "awards"]}
	return {"score": 60.0 + 9.0 * (n - 1) + (8.0 if b2b else 0.0), "ex": ex}


func _chk_mvp_streak(g: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var run := 1
	for e: Dictionary in g["ours"]:
		var n := NewsHistory.mvp_run(history, (e["s"] as Soldier).id)
		if n > run:
			run = n
			best = e
	if best.is_empty():
		return {}
	var ex := _line_ex(best)
	ex.merge({"n": run, "nw": _num(run), "nth": _ord_word(run), "v": "two" if run == 2 else ("three" if run == 3 else "long")})
	return {"score": 52.0 + 7.0 * run, "ex": ex}


func _chk_milestone(g: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0.0
	for e: Dictionary in g["ours"]:
		var so: Soldier = e["s"]
		var line: Dictionary = e["line"]
		for row: Array in MILESTONES:
			var key: String = row[0]
			var got := int(line.get(key, 0)) if key != "mvps" else (1 if so.id == (g["r"] as MatchResult).mvp_id else 0)
			var total := int(so.career.get(key, 0))
			for t: int in row[2]:
				if total - got < t and total >= t:
					var sc := 50.0 + minf(24.0, float(t) / 40.0)
					if sc > best_score:
						best_score = sc
						best = _line_ex(e)
						best.merge({"n": _commas(t), "what": row[1], "total": _commas(total), "key": row[0], "mark": t})
	if best.is_empty():
		return {}
	return {"score": best_score, "ex": best}


## Our soldiers' last `n` lines this season (oldest first), or [] when he has fewer.
func _last_lines(so: Soldier, n: int) -> Array:
	var rows := NewsHistory.recent(history, so.id, _s.year)
	return rows.slice(rows.size() - n) if rows.size() >= n else []


func _chk_hot_run(g: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_gap := 0
	for e: Dictionary in g["ours"]:
		var rows := _last_lines(e["s"], 3)
		if rows.is_empty() or not rows.all(func(r): return int(r["k"]) - int(r["d"]) >= 3):
			continue
		var tk := 0
		var td := 0
		for r: Dictionary in rows:
			tk += int(r["k"])
			td += int(r["d"])
		if tk - td > best_gap:
			best_gap = tk - td
			best = _line_ex(e)
			best.merge({"nw": _num(rows.size()), "tk": tk, "td": td})
	if best.is_empty():
		return {}
	return {"score": 44.0 + minf(14.0, best_gap * 0.6), "ex": best}


func _chk_slump(g: Dictionary) -> Dictionary:
	var stars := _top_ovr(_us, 5)
	var best: Dictionary = {}
	var best_gap := 0
	for e: Dictionary in g["ours"]:
		if not stars.has(e["s"]):
			continue
		var rows := _last_lines(e["s"], 3)
		if rows.is_empty() or not rows.all(func(r): return int(r["d"]) > int(r["k"])):
			continue
		var tk := 0
		var td := 0
		for r: Dictionary in rows:
			tk += int(r["k"])
			td += int(r["d"])
		if td - tk > best_gap:
			best_gap = td - tk
			best = _line_ex(e)
			best.merge({"nw": _num(rows.size()), "tk": tk, "td": td, "ovr": (e["s"] as Soldier).best_ovr()})
	if best.is_empty():
		return {}
	return {"score": 40.0 + minf(12.0, best_gap * 0.8), "ex": best}


## The abbrev of the club he played for in the last season before this one, and that year ("", 0 when none).
func _prev_club(so: Soldier) -> Array:
	var years := so.season_lines.keys()
	years.sort()
	years.reverse()
	for y in years:
		if int(y) < _s.year:
			return [String((so.season_lines[y] as Dictionary).get("team", "")), int(y)]
	return ["", 0]


func _chk_reunion(g: Dictionary) -> Dictionary:
	var them: Team = g["them"]
	var best: Dictionary = {}
	var best_score := 0.0
	for side: String in ["theirs", "ours"]:
		for e: Dictionary in g[side]:
			var club := _prev_club(e["s"])
			var back: String = _us.abbrev if side == "theirs" else them.abbrev
			if club[0] != back:
				continue
			var line: Dictionary = e["line"]
			var good := int(line["kills"]) >= int(line["deaths"])
			var sc := 50.0 + float((e["s"] as Soldier).best_ovr()) * 0.2 + (6.0 if good else 0.0)
			if sc > best_score:
				best_score = sc
				best = _line_ex(e)
				best.merge({"v": "%s_%s" % [side, "good" if good else "bad"],
					"when_there": "last season" if int(club[1]) == _s.year - 1 else "in %d" % int(club[1]),
					"old": _nick(_us) if side == "theirs" else _nick(them), "old_abbr": _us.abbrev if side == "theirs" else them.abbrev})
	if best.is_empty():
		return {}
	return {"score": best_score, "ex": best}


func _chk_franchise_book(g: Dictionary) -> Dictionary:
	var ledger: StatLedger = _s.ledger
	if not ledger.seeded and ledger.matches_regular + ledger.matches_playoffs < StatLedger.MATURE_AFTER:
		return {}
	var m: ScheduledMatch = g["m"]
	var ids := {}
	for e: Dictionary in g["ours"]:
		ids[(e["s"] as Soldier).id] = e
	var best: Dictionary = {}
	var best_rank := 99
	for stat: Dictionary in StatRegistry.SINGLE_MATCH:
		if stat["id"] not in ["kills", "assists", "damage", "saves", "impact"]:
			continue
		var list := ledger.top(stat["id"], StatRegistry.PHASE_COMBINED, _us.abbrev)
		for i in mini(list.size(), 3):
			var snap: Dictionary = list[i]
			if int(snap["year"]) == _s.year and int(snap["week"]) == m.week and ids.has(int(snap["id"])) and i < best_rank:
				best_rank = i
				best = _line_ex(ids[int(snap["id"])])
				best.merge({"noun": stat["noun"], "what": String(stat["label"]).to_lower().replace(" in a match", ""),
					"vl": StatRegistry.format(stat, float(snap["value"])), "rankp": RANK_PHRASE[i]})
	if best.is_empty():
		return {}
	return {"score": 46.0 + (5 - best_rank) * 3.0, "ex": best}

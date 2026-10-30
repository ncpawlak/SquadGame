class_name Newsroom
extends RefCounted
## The Weekly News: one feature article a week (and one per offseason step) about the user's
## club, written by its beat writer (LeagueData.PRESS) in a shared house voice.
##
## Nothing here is a fill-in-the-names template. Each issue gathers that week's facts (the
## game-by-game swing, holds and rounds, box scores, clutch finishes, standings, schemes,
## weather, injuries, contracts, morale and DNA), scores every angle the facts support and leads
## with the biggest one; the rest of the piece is assembled from whichever angles are left. Every
## sentence quotes facts that are true. Phrasing comes from small grammars whose choices each
## paper remembers (`used`), so a turn of phrase doesn't come back for weeks, and `memory`
## carries threads from issue to issue (streaks, the scheme question, injuries, the table).
## Quotes come from the soldiers themselves: temperament sets the voice, morale the mood and the
## top DNA motivation what they bring up.
##
## Generated on its own RNG seeded from the league, year and step: the league RNG is never touched
## and nothing in the league changes. Issues are plain dictionaries (saved with the Season):
##   {n, year, when, kind, team, paper, writer, section, headline, dek, dateline, body: [String],
##    pull_quote: {text, who}, sidebar: [{title, rows: [[label, value]]}], roundup: [{head, text}],
##    grade, angles: [String]}

const MAX_ISSUES := 400
## Buzz must move this far (or change band) since the paper last mentioned it to earn a paragraph.
const BUZZ_NOTE := 4.0
## A phrase choice stays off-limits for this many later uses of its slot (capped by the options).
const PHRASE_MEMORY := 6

const KIND_GAME := "game"
const KIND_BYE := "bye"
const KIND_SIDELINED := "sidelined"
const KIND_WRAP := "wrap"
const KIND_RESIGN := "resign"
const KIND_FA := "free_agency"
const KIND_DRAFT := "draft"
const KIND_REVIEW := "review"
const KIND_CAMP := "camp"
const KIND_PRESEASON := "preseason"

const WORDS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
	"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
const ORDINAL_WORDS := ["zeroth", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth",
	"ninth", "tenth", "eleventh", "twelfth"]

## Every issue for the user's club, oldest first.
var issues: Array = []
## The highest issue number (`n`) the user has opened; the Home tile is "done" once he's read the latest.
var read_upto := 0
## Phrase slot -> recently used option indexes (anti-repetition, per paper).
var used: Dictionary = {}
## Threads carried between issues (rank, last lede, the scheme question, injuries...).
var memory: Dictionary = {}

# Working state for the issue being written (cleared afterwards so saves never see it).
var _r := RandomNumberGenerator.new()
var _s: Season = null
var _us: Team = null
var _f: Dictionary = {}
var _seen: Dictionary = {}
var _ids: Dictionary = {}
var _table: Array = []


# --- public -----------------------------------------------------------------------

func latest() -> Dictionary:
	return issues[-1] if not issues.is_empty() else {}


func count() -> int:
	return issues.size()


func issue(i: int) -> Dictionary:
	return issues[i] if i >= 0 and i < issues.size() else {}


## Marks issue index `i` read (and everything before it).
func mark_read(i: int) -> void:
	var a := issue(i)
	if not a.is_empty():
		read_upto = maxi(read_upto, int(a["n"]))


func is_read(i: int) -> bool:
	var a := issue(i)
	return a.is_empty() or int(a["n"]) <= read_upto


## Issues newer than the last one the user opened.
func unread() -> int:
	var n := 0
	for a in issues:
		if int(a["n"]) > read_upto:
			n += 1
	return n


## After a regular-season or playoff week is played (the season is still on).
func publish_week(season: Season, wk: int) -> void:
	if not _open(season, season.week_label(wk), wk):
		return
	var m := _match_of(wk)
	var art: Dictionary
	if m != null and m.is_played():
		art = _game_article(m, wk)
	elif wk > season.regular_weeks:
		art = _sidelined_article(wk)
	else:
		art = _bye_article(wk)
	_close(art)


## After the final: the season in review (and the final itself if we played in it).
func publish_wrap(season: Season, wk: int) -> void:
	if not _open(season, "Season Review", wk):
		return
	_close(_wrap_article(wk))


## After an offseason step resolves: "Re-signing", "FA Day N", "Draft", "Roster Review", "Camp".
func publish_offseason(season: Season, step: String) -> void:
	if not _open(season, step, 0):
		return
	var art: Dictionary
	if step == "Re-signing":
		art = _resign_article()
	elif step.begins_with("FA Day"):
		art = _fa_article(step)
	elif step == "Draft":
		art = _draft_article()
	elif step == "Roster Review":
		art = _review_article()
	elif step == "Camp":
		art = _camp_article()
	else:
		_clear()
		return
	_close(art)


## A new season is about to start: the preview issue.
func publish_preseason(season: Season) -> void:
	if not _open(season, "Preseason", 0):
		return
	_close(_preseason_article())


# --- issue plumbing -----------------------------------------------------------------

func _open(season: Season, when: String, wk: int) -> bool:
	_s = season
	_us = season.user_team()
	if _us == null:
		_s = null
		return false
	_r.seed = Season._mix([season.league.league_seed, season.year, when.hash(), wk, _us.id, issues.size(), 0x4E35])
	_seen = {}
	_ids = {}
	for t in season.league.teams:
		for so in t.roster:
			_ids[so.id] = so
	for so in season.league.free_agents:
		_ids[so.id] = so
	_table = season.standings()
	_f = {"us_city": _city(_us), "us_nick": _nick(_us), "us_full": _full(_us), "us_abbr": _us.abbrev,
		"us_poss": _poss(_nick(_us)),
		"when": when, "year": str(season.year), "us_scheme": _us.scheme.display_name, "record": _record(_us),
		"div": _division(_us)}
	return true


func _close(art: Dictionary) -> void:
	var press := LeagueData.press_for(_us)
	art["n"] = (int(issues[-1]["n"]) + 1) if not issues.is_empty() else 1
	art["year"] = _s.year
	art["when"] = _f["when"]
	art["team"] = _us.abbrev
	art["paper"] = press[0]
	art["writer"] = press[1]
	art["dateline"] = String(art.get("dateline", _city(_us))).to_upper()
	for k in ["section", "headline", "dek", "grade"]:
		if not art.has(k):
			art[k] = ""
	for k in ["body", "sidebar", "roundup", "angles"]:
		if not art.has(k):
			art[k] = []
	if not art.has("pull_quote"):
		art["pull_quote"] = {}
	var body: Array = []
	for p in art["body"]:
		if String(p).strip_edges() != "":
			body.append(_polish(String(p)))
	art["body"] = body
	art["dek"] = _polish(art["dek"])
	if not art["pull_quote"].is_empty():
		art["pull_quote"]["text"] = _polish(art["pull_quote"]["text"])
	for r in art["roundup"]:
		r["text"] = _polish(r["text"])
	memory["rank"] = _rank_of(_us)
	memory["buzz"] = _us.buzz
	if not memory.has("buzz_said"):
		memory["buzz_said"] = _us.buzz
	if not (art["angles"] as Array).is_empty():
		memory["lede"] = art["angles"][0]
	issues.append(art)
	if issues.size() > MAX_ISSUES:
		issues.pop_front()
	_clear()


func _clear() -> void:
	_s = null
	_us = null
	_f = {}
	_seen = {}
	_ids = {}
	_table = []


# --- grammar --------------------------------------------------------------------

## One of `options` for phrase slot `key`, never one this paper used in its last few uses of
## the slot, filled in from the issue's facts (plus `extra`).
func _g(key: String, options: Array, extra := {}) -> String:
	if options.is_empty():
		return ""
	var recent: Array = used.get(key, [])
	var pool: Array = []
	for i in options.size():
		if not recent.has(i):
			pool.append(i)
	if pool.is_empty():
		pool = range(options.size())
	var pick: int = pool[_r.randi_range(0, pool.size() - 1)]
	recent.append(pick)
	while recent.size() > mini(PHRASE_MEMORY, options.size() - 1):
		recent.pop_front()
	used[key] = recent
	return _fmt(String(options[pick]), extra)


func _fmt(text: String, extra := {}) -> String:
	var facts := _f.duplicate()
	facts.merge(extra, true)
	var out := text.format(facts)
	if out.contains("{"):
		push_warning("Newsroom: unfilled slot in \"%s\"" % out)
	return out


func _chance(p: float) -> bool:
	return _r.randf() < p


func _any(list: Array) -> Variant:
	return list[_r.randi_range(0, list.size() - 1)] if not list.is_empty() else null


## Joins sentences, skipping empties.
static func _para(parts: Array) -> String:
	var out: Array[String] = []
	for p in parts:
		var s := String(p).strip_edges()
		if s != "":
			out.append(s)
	return " ".join(out)


static var _re_an: RegEx
static var _re_cap: RegEx
static var _re_said: RegEx
static var _re_space: RegEx


## Copy-desk pass over a finished paragraph: a/an, capitals at sentence starts (also inside
## quotes and after a lower-case role like "frontman"), commas before attributions
## ("...plan," Webb said) and stray double spaces.
static func _polish(text: String) -> String:
	if _re_an == null:
		_re_an = RegEx.create_from_string("\\b(a|A) (?=(?:8\\d*|11|18)\\b|(?!one\\b|once\\b|uni|Uni|use|usu|eu|Eu|ur|Ur)[aeiouAEIOU])")
		_re_cap = RegEx.create_from_string("(^|[.!?]\"? +\"?|^\")([a-z])")
		_re_said = RegEx.create_from_string("\\.\" ((?:[a-z]+ )?[A-Z][^.!?\\n]{0,48}? (?:said|told reporters|added)\\b|said\\b)")
		_re_space = RegEx.create_from_string(" {2,}")
	var out := _re_space.sub(text.strip_edges(), " ", true)
	out = _re_an.sub(out, "$1n ", true)
	out = _re_said.sub(out, ",\" $1", true)
	var parts: Array[String] = []
	var at := 0
	for m in _re_cap.search_all(out):
		var i := m.get_start(2)
		parts.append(out.substr(at, i - at))
		parts.append(m.get_string(2).to_upper())
		at = i + 1
	parts.append(out.substr(at))
	return "".join(parts)


## "a jammed finger", "an ankle sprain".
static func _a(noun: String) -> String:
	return ("an " if _polish("a " + noun).begins_with("An ") else "a ") + noun


# --- names and numbers ------------------------------------------------------------

static func _city(t: Team) -> String:
	return t.city if t.city != "" else t.name


static func _nick(t: Team) -> String:
	return t.nickname if t.nickname != "" else t.name


static func _full(t: Team) -> String:
	return "%s %s" % [t.city, t.nickname] if t.city != "" and t.nickname != "" else t.name


## Possessive of a plural nickname ("the Ironmen'").
static func _poss(nick: String) -> String:
	return nick + ("'" if nick.ends_with("s") else "'s")


## First mention: Theo "Anvil" Brandt; afterwards: Brandt.
func _who(s: Soldier) -> String:
	if s == null:
		return ""
	if _seen.has(s.id):
		return s.last_name
	_seen[s.id] = true
	return s.display_name()


## First mention with his role: center Theo "Anvil" Brandt.
func _who_role(s: Soldier) -> String:
	if s == null:
		return ""
	if _seen.has(s.id):
		return s.last_name
	return "%s %s" % [_role(s), _who(s)]


## Last name, or "First Last" when one of our own players shares it (avoids "Stone had 14 for Chicago").
func _short_name(s: Soldier) -> String:
	if _us != null:
		for m in _us.roster:
			if m != s and (m as Soldier).last_name == s.last_name:
				return "%s %s" % [s.first_name, s.last_name]
	return s.last_name


static func _join_and(items: Array) -> String:
	if items.size() <= 1:
		return "" if items.is_empty() else str(items[0])
	return ", ".join(items.slice(0, -1)) + " and " + str(items[-1])


static func _role(s: Soldier) -> String:
	return String(Scheme.ROLE_NAMES[Scheme.best_role(s.stats)]).to_lower()


static func _num(n: int) -> String:
	return WORDS[n] if n >= 0 and n < WORDS.size() else str(n)


static func _cap_first(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1) if t != "" else t


static func _ord(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [n, suffix]


static func _ord_word(n: int) -> String:
	return ORDINAL_WORDS[n] if n >= 0 and n < ORDINAL_WORDS.size() else _ord(n)


static func _secs(v: float) -> String:
	return MatchEngine._fmt_secs(v)


## "two full minutes", "a minute and 12 seconds", "41 seconds".
static func _secs_words(v: float) -> String:
	var s := int(v)
	if s >= 120:
		return "two full minutes"
	if s >= 60:
		var rest := s - 60
		return "a full minute" if rest == 0 else "a minute and %d seconds" % rest
	return "%d seconds" % s


static func _games(n: int) -> String:
	return "%s game%s" % [_num(n), "" if n == 1 else "s"]


static func _plural(n: int, word: String) -> String:
	var nn := _num(n) if word in ["week", "win", "loss", "game", "match", "drill", "season", "point", "pick"] else str(n)
	return "%s %s%s" % [nn, word, ("" if n == 1 else ("es" if word.ends_with("ch") or word.ends_with("ss") else "s"))]


# --- league lookups ---------------------------------------------------------------

func _row(t: Team) -> StandingRow:
	for r in _table:
		if r.team == t:
			return r
	return null


func _record(t: Team) -> String:
	var r := _row(t)
	return "%d-%d" % [r.wins, r.losses] if r != null else "0-0"


func _rank_of(t: Team) -> int:
	var r := _row(t)
	return r.rank if r != null else 0


func _division(t: Team) -> String:
	return t.division if t.division != "" else Season.DIVISION_NAME


## "the East" / "the Premier Division".
func _div_name(t: Team) -> String:
	return "the %s" % t.division if t.division != "" else "the %s" % Season.DIVISION_NAME


func _div_rows(t: Team) -> Array:
	var d := _division(t)
	return _table.filter(func(r: StandingRow): return _division(r.team) == d)


func _match_of(wk: int) -> ScheduledMatch:
	for m in _s.matches_for_week(wk):
		if m.involves(_us):
			return m
	return null


## "W"/"L" for every played match of `t` this season, oldest first.
func _results(t: Team) -> Array:
	var out: Array = []
	for m in _s.matches_for(t):
		if m.is_played():
			out.append("W" if m.winner() == t else "L")
	return out


## Length of the run at the end of `res` (and its letter).
static func _run(res: Array) -> Array:
	if res.is_empty():
		return ["", 0]
	var last: String = res[-1]
	var n := 0
	for i in range(res.size() - 1, -1, -1):
		if res[i] != last:
			break
		n += 1
	return [last, n]


## {matches, kills, deaths, ...} for `s` this season.
func _line(s: Soldier) -> Dictionary:
	return s.season_lines.get(_s.year, {})


## Where `s` ranks in the league in season `key` (kills, hill_s...), 1 = best.
func _league_rank(s: Soldier, key: String) -> int:
	var mine := int(_line(s).get(key, 0))
	var better := 0
	for t in _s.league.teams:
		for o in t.roster:
			if int(o.season_lines.get(_s.year, {}).get(key, 0)) > mine:
				better += 1
	return better + 1


## The roster's best healthy player: by this season's kills per match once anyone has played,
## else by OVR.
func _team_star(t: Team) -> Soldier:
	var best: Soldier = null
	var best_v := -1.0
	var played := false
	for so in t.roster:
		if int(so.season_lines.get(_s.year, {}).get("matches", 0)) > 0:
			played = true
			break
	for so in t.roster:
		if so.is_injured():
			continue
		var ln: Dictionary = so.season_lines.get(_s.year, {})
		var m := int(ln.get("matches", 0))
		var v := 0.0
		if played:
			if m == 0:
				continue
			v = float(ln.get("kills", 0)) / m
		else:
			v = so.best_ovr()
		if v > best_v:
			best_v = v
			best = so
	return best


## "Boston leads the series 3-1 and has won the last two" ("" before the first meeting).
func _series(them: Team) -> String:
	var rec := _s.rivalries.record_of(_us, them)
	if rec.is_empty():
		return ""
	var wu := int(rec["w"].get(_us.abbrev, 0))
	var wt := int(rec["w"].get(them.abbrev, 0))
	if wu + wt == 0:
		return ""
	var text := "the series is tied %d-%d" % [wu, wt]
	var leader: Team = _us if wu > wt else them
	if wu != wt:
		text = "%s leads the series %d-%d" % [_city(leader), maxi(wu, wt), mini(wu, wt)]
	var streak := int(rec.get("streak", 0))
	if streak >= 2 and streak < wu + wt:
		var st: Team = _us if String(rec.get("streak_team", "")) == _us.abbrev else them
		if wu != wt and st == leader:
			text += " and has won the last %s" % _num(streak)
		else:
			text += ", with %s winning the last %s" % [_city(st), _num(streak)]
	return text


func _top_ovr(t: Team, n: int) -> Array:
	var list := t.roster.duplicate()
	list.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	return list.slice(0, n)


func _avg_starter_ovr(t: Team) -> float:
	var st := t.starters()
	if st.is_empty():
		return 0.0
	var total := 0
	for so in st:
		total += so.best_ovr()
	return float(total) / st.size()

# --- match facts --------------------------------------------------------------------

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
	# Don't lead with the same thing two weeks running.
	var last: String = memory.get("lede", "")
	if a.has(last):
		a[last] -= 25.0
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
	var art := {"kind": KIND_GAME, "section": _section(g), "angles": [lede] + order.slice(1, 4),
		"dateline": _city(m.home)}
	var star: Dictionary = g["star"]
	art["headline"] = _headline(lede, g)
	art["dek"] = _dek(lede, g)
	var body: Array = []
	body.append(_lede(lede, g))
	body.append(_narrative(g, lede))
	var quote := {}
	if not star.is_empty():
		var sp := _star_para(g)
		body.append(sp[0])
		quote = sp[1]
	body.append(_secondary(g, order, lede))
	body.append(_standings_para(wk))
	body.append(_buzz_para())
	body.append(_preview_para(wk))
	art["body"] = body
	art["pull_quote"] = quote
	art["sidebar"] = _box_sidebar(g)
	art["roundup"] = _roundup(wk)
	return art


func _section(g: Dictionary) -> String:
	if g["stage"] != Season.STAGE_REGULAR:
		return "%s %s" % [_f["us_nick"].to_upper(), _s.week_label(g["m"].week).to_upper()]
	return "%s - %s" % [_f["us_nick"].to_upper(), _f["when"].to_upper()]


func _headline(angle: String, g: Dictionary) -> String:
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
			if not lead.ends_with(".") and lead != "" and sentence.begins_with("The ") else sentence]))
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
			"The box score belongs to {star}, who went {k}-{d} with {a}."], ex)
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
			"ovr": str(gs.best_ovr()), "role": _role(gs), "nth": _ord_word(past.size() + 1), "span": _num(_s.week - int(past[0]) + 1) if not past.is_empty() else ""}
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
			out.append(_g("x_div", ["It was a division game, and {ser}.", "It was a division game; {ser}."],
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
				"Their danger man is {ns}, who has {nk} kills.", "Everything they do runs through {ns}: {nk} kills so far."], ex))
		else:
			out.append(_g("p_star0", ["Their best player is {ns}, rated {novr}.", "The name to know is {ns}, a {novr}-rated problem."], ex))
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
			out.append(_g("p_div", ["It's a division game, and {ser}.", "Division game: {ser}."] if ser != ""
				else ["It's a division game, the first meeting of the year between the two."], ex))
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


## The biggest logged event that moved `t`'s buzz in `when` ("" if none), first letter lower-cased.
## `sign` is 1 for a gain, -1 for a drop.
func _buzz_cause(t: Team, when: String, sign: int) -> String:
	var best: Dictionary = {}
	for e in Market.log_for(t, _s.year):
		var a := float(e["amount"])
		if e["when"] != when or signf(a) != float(sign) or String(e["label"]).begins_with("League average"):
			continue
		if best.is_empty() or absf(a) > absf(float(best["amount"])):
			best = e
	if best.is_empty():
		return ""
	return _lc_first(String(best["label"]))


static func _lc_first(t: String) -> String:
	return t.substr(0, 1).to_lower() + t.substr(1)


## The city's mood, when buzz around the club has moved enough since the paper last wrote about it to be
## worth a line (a new band, or four points either way), so a slow drift is covered too.
func _buzz_para() -> String:
	if not memory.has("buzz_said"):
		return ""
	var now := _us.buzz
	var said := float(memory["buzz_said"])
	var d := now - said
	if Market.band_of(now) == Market.band_of(said) and absf(d) < BUZZ_NOTE:
		return ""
	memory["buzz_said"] = now
	var up := d > 0.0
	var ex := {"band": Market.band_name(now), "b": str(roundi(now)), "d": str(absi(roundi(d))),
		"mkt": Market.market_name(_us).to_lower()}
	var out: Array = []
	if up:
		out.append(_g("bz_up", [
			"The city is paying attention. Buzz around the {us_nick} has climbed to {band} ({b}), up {d} points in recent weeks.",
			"The {us_nick} are getting louder in {us_city}: buzz is up {d} to {b}, which now reads {band}."], ex))
	else:
		out.append(_g("bz_dn", [
			"The mood in {us_city} is cooling. Buzz around the {us_nick} has slipped to {band} ({b}), down {d} points in recent weeks.",
			"{us_city} is losing interest: buzz is down {d} to {b}, and the club now reads {band}."], ex))
	var why := _buzz_cause(_us, _f["when"], 1 if up else -1)
	if why != "":
		out.append(_g("bz_why", ["The biggest swing: {why}.", "A lot of it came from one thing: {why}."], {"why": why}))
	var tier := Market.tier_of(_us.market_rating)
	if up and Market.band_of(now) >= 4 and tier <= 2:
		out.append(_g("bz_small", ["It is rare for a {mkt} to get this loud.", "Not many {mkt} clubs ever feel this much attention."], ex))
	elif not up and Market.band_of(now) <= 1 and tier >= 4:
		out.append(_g("bz_big", ["In a {mkt}, a cold stretch does not go unnoticed.", "A {mkt} has little patience for a club this quiet."], ex))
	return _cap_first(_para(out))


## The year in the city: where buzz started, where it ended, what moved it.
func _buzz_year_para() -> String:
	memory["buzz_said"] = _us.buzz
	var start := float(_s.market.start_buzz.get(_us.abbrev, _us.buzz))
	var now := _us.buzz
	var ex := {"band": Market.band_name(now), "b": str(roundi(now)), "band0": Market.band_name(start), "b0": str(roundi(start)),
		"d": str(absi(roundi(now - start)))}
	var out: Array = []
	if absf(now - start) < 3.0:
		out.append(_g("by_flat", ["Around {us_city}, interest held steady all year: buzz began at {band0} ({b0}) and ends at {band} ({b}).",
			"The city's mood barely moved. Buzz around the {us_nick} started {band0} and finishes {band}."], ex))
	elif now > start:
		out.append(_g("by_up", ["It was a year the city noticed. Buzz around the {us_nick} grew from {band0} ({b0}) to {band} ({b}).",
			"Interest in {us_city} is up {d} points, from {band0} to {band}."], ex))
	else:
		out.append(_g("by_dn", ["{us_city} cooled on the {us_nick} this year: buzz fell from {band0} ({b0}) to {band} ({b}).",
			"Interest is down {d} points, from {band0} to {band}, and the club will have to win the city back."], ex))
	var ups: Array = Market.drivers(_us, _s.year, 1, 2).map(func(e): return _lc_first(String(e["label"])))
	var downs: Array = Market.drivers(_us, _s.year, -1, 1).map(func(e): return _lc_first(String(e["label"])))
	if not ups.is_empty():
		out.append(_g("by_ups", ["What helped most: {list}.", "The biggest boosts: {list}."], {"list": _join_and(ups)}))
	if not downs.is_empty():
		out.append(_g("by_downs", ["What hurt most: {list}.", "The biggest drag: {list}."], {"list": _join_and(downs)}))
	return _cap_first(_para(out))


## Preview line: how loud the city is going in, for a market this size.
func _buzz_pre_para() -> String:
	memory["buzz_said"] = _us.buzz
	var band := Market.band_of(_us.buzz)
	var ex := {"band": Market.band_name(_us.buzz), "b": str(roundi(_us.buzz)), "mkt": Market.market_name(_us).to_lower()}
	if band >= 4:
		return _g("bp_hot", ["{us_city} is buzzing: interest sits at {band} ({b}) in a {mkt}, and the expectations come with it.",
			"The city is loud going in. Buzz is {band} ({b}), and a {mkt} wants results."], ex)
	if band <= 1:
		return _g("bp_cold", ["Interest in {us_city} is thin: buzz sits at {band} ({b}), and winning is the only way to bring a {mkt} back.",
			"The {us_nick} open {band} ({b}) in a {mkt}. The fans have to be won back."], ex)
	return _g("bp_mid", ["Buzz around the {us_nick} sits at {band} ({b}) in a {mkt}: not loud, not quiet.",
		"{us_city} is watching, without much noise yet. Buzz is {band} ({b})."], ex)


## Sidebar box: the club's market and buzz (with the season's start in the review).
func _buzz_box(year := false) -> Dictionary:
	var rows: Array = [["Market", Market.market_name(_us)], ["Buzz", "%s %d" % [Market.band_name(_us.buzz), roundi(_us.buzz)]]]
	if year:
		var start := float(_s.market.start_buzz.get(_us.abbrev, _us.buzz))
		rows.append(["Season start", "%s %d" % [Market.band_name(start), roundi(start)]])
	elif memory.has("buzz"):
		rows.append(["Since last issue", "%+d" % roundi(_us.buzz - float(memory["buzz"]))])
	rows.append(["Resting level", str(roundi(Market.baseline(_us)))])
	return {"title": "Market & Buzz", "rows": rows}


## Around the league: the week's buzz leader (or a team clearly heating up or cooling off).
func _buzz_watch(wk: int) -> Dictionary:
	var when := _s.week_label(wk)
	var pick: Dictionary = {}
	for i in range(_s.news.items.size() - 1, -1, -1):
		var it: Dictionary = _s.news.items[i]
		if it["year"] != _s.year or it["when"] != when or not String(it["kind"]).begins_with("buzz_") or (it["teams"] as Array).has(_us.abbrev):
			continue
		if pick.is_empty() or (it["kind"] == "buzz_leader" and pick["kind"] != "buzz_leader"):
			pick = it
	if pick.is_empty():
		return {}
	var t := _s.league.team_by_abbrev(pick["teams"][0])
	if t == null:
		return {}
	var ex := {"t": _nick(t), "band": Market.band_name(t.buzz), "b": str(roundi(t.buzz))}
	if pick["kind"] == "buzz_down":
		return {"head": "Cooling Off", "text": _g("r_buzz_dn", ["Interest in the {t} is slipping: buzz is down to {band} ({b}).",
			"The {t} are losing the room. Buzz has fallen to {band} ({b})."], ex)}
	var why := _buzz_cause(t, when, 1)
	var text := _g("r_buzz", ["The {t} are the talk of the league: buzz is {band} ({b}).", "Nobody is louder than the {t} right now, at {band} ({b})."], ex)
	if why != "":
		text += " " + _g("r_buzz_why", ["The biggest swing: {why}.", "It started with {why}."], {"why": why})
	return {"head": "Buzz Watch", "text": text}


## Around the league this week, in the paper's voice.
func _roundup(wk: int) -> Array:
	var out: Array = []
	var pow := SeasonReview.player_of_week(_s, wk)
	if not pow.is_empty():
		var s: Soldier = pow["soldier"]
		var ln: Dictionary = pow["line"]
		out.append({"head": "Player of the Week", "text": _g("r_pow", [
			"{who} of the {tm} went {k}-{d} with {a}, the best line in the league this week.",
			"Nobody was better than {who}: {k} kills, {dd}, {a} for the {tm}."],
			{"who": s.display_name(), "tm": _nick(pow["team"]), "k": str(int(ln["kills"])), "d": str(int(ln["deaths"])), "dd": _plural(int(ln["deaths"]), "death"), "a": _plural(int(ln["assists"]), "assist")})})
	var watch := _buzz_watch(wk)
	if not watch.is_empty():
		out.append(watch)
	var upsets: Array = []
	for m in _s.matches_for_week(wk):
		if not m.is_played() or m.involves(_us):
			continue
		var w: Team = m.winner()
		var l: Team = m.opponent_of(w)
		var gap := l.team_ovr() - w.team_ovr()
		if gap >= 4:
			upsets.append({"w": w, "l": l, "gap": gap, "m": m})
	upsets.sort_custom(func(a, b): return a["gap"] > b["gap"])
	if not upsets.is_empty():
		var u: Dictionary = upsets[0]
		var m: ScheduledMatch = u["m"]
		out.append({"head": "Upset Watch", "text": _g("r_upset", [
			"The {w} took down the {l} {sc}, beating a roster rated {gap} points higher.",
			"Nobody saw the {w} beating the {l}, {sc}. The ratings gap was {gap}."],
			{"w": _full(u["w"]), "l": _nick(u["l"]), "sc": "%d-%d" % [m.result.score.max(), m.result.score.min()], "gap": str(u["gap"])})})
	for r: StandingRow in _table:
		if r.team == _us:
			continue
		if r.streak.length() >= 2 and int(r.streak.substr(1)) >= 4:
			var hot: bool = r.streak.begins_with("W")
			out.append({"head": "Hot Streak" if hot else "Cold Streak", "text": _g("r_streak_" + ("w" if hot else "l"), [
				"The {t} have won {n} straight and are {rec}.", "Make it {n} in a row for the {t} ({rec})."] if hot else [
				"The {t} have lost {n} straight and fallen to {rec}.", "Still searching: the {t} are {rec} after {n} straight losses."],
				{"t": _full(r.team), "n": _num(int(r.streak.substr(1))), "rec": "%d-%d" % [r.wins, r.losses]})})
			break
	if not _table.is_empty() and _table[0].team != _us and _s.phase == Season.PHASE_REGULAR:
		var top: StandingRow = _table[0]
		out.append({"head": "Top of the Table", "text": _g("r_top", [
			"The {t} lead the league at {rec}.", "Everyone is chasing the {t}, {rec}."],
			{"t": _full(top.team), "rec": "%d-%d" % [top.wins, top.losses]})})
	for e in _s.last_injuries:
		if e["team"] != _us and int(e["weeks"]) >= 4 and e["soldier"] is Soldier and e["soldier"].best_ovr() >= 70:
			out.append({"head": "Injury Report", "text": _g("r_inj", [
				"The {t} lost {who} to {a_inj}; he's out {wk}.", "{who} ({t}) will miss {wk} with {a_inj}."],
				{"t": _nick(e["team"]), "who": e["soldier"].display_name(), "inj": String(e["name"]).to_lower(), "a_inj": _a(String(e["name"]).to_lower()), "wk": _plural(int(e["weeks"]), "week")})})
			break
	for tr in _s.trades.last_trades:
		if tr.get("a") == _us or tr.get("b") == _us:
			continue
		out.append({"head": "Trade Wire", "text": _cap_first("%s and %s made a deal: %s for %s." % [_trade_team(tr["a"]), _trade_team(tr["b"]),
			", ".join(tr["a_gave"]), ", ".join(tr["b_gave"])])})
		break
	return out.slice(0, 5)


func _trade_team(t: Variant) -> String:
	if t is Team:
		return "the " + _full(t)
	var found: Team = _s.league.team_by_abbrev(String(t))
	return "the " + _full(found) if found != null else str(t)

# --- quotes ---------------------------------------------------------------------------

## The soldier's voice: "thick" (blunt, sure of himself), "thin" (raw, takes it personally) or "even".
static func _voice(s: Soldier) -> String:
	var t := s.get_dna().temperament
	return "thick" if t >= 70 else ("thin" if t <= 30 else "even")


## What he really cares about, as a DNA motivation.
static func _drive(s: Soldier) -> StringName:
	return s.get_dna().ranked()[0]


## "high", "low" or "ok" morale.
static func _mood(s: Soldier) -> String:
	return "high" if s.morale >= Soldier.MORALE_BOOST_START else ("low" if s.morale < 60.0 else "ok")


## A quote from `s` about `sit`, in his own voice. `ctx` is the match facts (or {"them": Team} etc).
func _quote(s: Soldier, sit: String, ctx: Dictionary) -> String:
	var v := _voice(s)
	var mood := _mood(s)
	var drive := _drive(s)
	var ex := {"opp": _nick(ctx["them"]) if ctx.get("them") is Team else "them"}
	var parts: Array = []
	match sit:
		"star_win", "clutch":
			parts.append(_g("q_win_" + v, {
				"thick": ["We were better. Simple as that.", "I told the guys before we went out that we'd win this one.", "That's what we do.", "Nobody's beating us when we play like that."],
				"thin": ["Honestly, I'm just relieved.", "I needed that one. We all did.", "Man, my hands are still shaking.", "I don't think I breathed for the whole last game."],
				"even": ["Good win. We stuck to the plan.", "We did the simple things well tonight.", "It was a good team win.", "That's the standard we want to play to."]}[v]))
			parts.append(_fact_clause(s, sit, ctx, v))
		"star_loss":
			parts.append(_g("q_loss_" + v, {
				"thick": ["I don't care about my numbers. We lost.", "That's not who we are, and everybody in here knows it.", "We got beat. Put it on me if you want.", "We'll see them again."],
				"thin": ["That one hurts. It really does.", "I don't know what to say right now.", "I keep thinking about the plays I didn't make.", "It's hard. You put everything in and come up short."],
				"even": ["We've got to clean some things up.", "They played well. We didn't play well enough.", "Credit to the {opp}. We'll look at the film.", "One match. We move on."]}[v], ex))
			parts.append(_fact_clause(s, sit, ctx, v))
		"preview":
			parts.append(_g("q_prev_" + v, {
				"thick": ["They know who we are. They should be worried about us.", "I'm not losing sleep over the {opp}.", "Doesn't matter who's across from us."],
				"thin": ["We respect the {opp}. They can beat anybody.", "They're dangerous. We've got to be sharp.", "I've been thinking about this one all week, honestly."],
				"even": ["The {opp} are a good team. It'll come down to execution.", "We know what they do well. We have a plan.", "Another good test for us."]}[v], ex))
		"bye":
			parts.append(_g("q_bye_" + v, {
				"thick": ["I'd rather be playing, but fine.", "Rest is for the other guys. I'm getting reps in.", "We'll be ready."],
				"thin": ["Honestly, the body needed it.", "It's good to breathe for a second.", "It's been a lot. The week off helps."],
				"even": ["A good week to get healthy and get some work in.", "We'll use it.", "Time to reset and get back to work."]}[v]))
		"season_good":
			parts.append(_g("q_sg_" + v, {
				"thick": ["We're not done. This is the start.", "Next year we finish it.", "I said in camp we'd be a problem. We were."],
				"thin": ["I'm proud of this group. I really am.", "I'll remember this year for a long time.", "It hurts how it ended, but what a ride."],
				"even": ["We took a step this year. Now we build on it.", "A lot to be proud of, a lot to work on.", "Good season. Not the one we wanted, but a good one."]}[v]))
		"season_bad":
			parts.append(_g("q_sb_" + v, {
				"thick": ["That was unacceptable. Everybody in here should be embarrassed.", "Something has to change.", "I'm not sitting through another year like that."],
				"thin": ["It was a really hard year.", "I don't know. I just don't know what happened.", "I feel like I let people down."],
				"even": ["We weren't good enough. There's no other way to say it.", "We've got a long offseason to figure it out.", "Everybody has to look in the mirror."]}[v]))
		"signed":
			parts.append(_g("q_sign_" + v, {
				"thick": ["They got a good one.", "I'm here to win, and I'm here to start.", "You'll see why they paid me."],
				"thin": ["I'm just grateful for the chance.", "It means a lot that they wanted me.", "I can't wait to get started."],
				"even": ["It felt like the right fit.", "Good organization, good people. Easy decision.", "I'm looking forward to it."]}[v]))
		"drafted":
			parts.append(_g("q_draft_" + v, {
				"thick": ["They won't regret it.", "Everybody who passed on me is going to hear about it.", "I'm ready right now."],
				"thin": ["I'm still kind of in shock.", "My family's going crazy right now.", "I just want to earn it."],
				"even": ["I'm ready to work.", "It's a dream. Now the job starts.", "I'll do whatever they need."]}[v]))
		"camp":
			parts.append(_g("q_camp_" + v, {
				"thick": ["I feel the best I've ever felt.", "Watch this year.", "I'm better. Everybody can see it."],
				"thin": ["I worked so hard this summer. I hope it shows.", "I just want to prove I belong.", "I'm a little nervous, honestly. Good nervous."],
				"even": ["Good camp. I got a lot done.", "The work's in. Now we play.", "I feel ready."]}[v]))
		"resigned":
			parts.append(_g("q_resign_" + v, {
				"thick": ["They knew what I'm worth.", "I wasn't going anywhere.", "Unfinished business here."],
				"thin": ["This is home. I'm so glad it worked out.", "I was nervous it wouldn't happen.", "I love it here."],
				"even": ["Glad we got it done.", "It's the right place for me.", "Happy to be back."]}[v]))
	parts.append(_drive_tail(s, sit, mood, v))
	return _fmt(_para(parts), ex)


## A first-person fact from the match.
func _fact_clause(s: Soldier, sit: String, g: Dictionary, v: String) -> String:
	if not g.has("ours"):
		return ""
	var mine: Dictionary = {}
	for e in g["ours"]:
		if e["s"] == s:
			mine = e["line"]
	if mine.is_empty():
		return ""
	var ex := {"k": _num(int(mine["kills"])), "hold": _secs_words(float(mine.get("hill_s", 0.0))), "opp": _nick(g["them"])}
	if sit == "clutch":
		return _g("qf_clutch", ["When it's just you, you slow everything down. I wasn't rushing anything.",
			"I knew where they had to come from. I just waited.", "Last guy alive, you don't think. You just play."])
	if g["won"] and float(mine.get("hill_s", 0.0)) >= 50.0:
		return _g("qf_hill", ["I was on that point for {hold}. That hill was ours.", "We held that hill. I spent {hold} on it and I'd do it again."], ex)
	if g["won"]:
		return _g("qf_kills_w", ["{k} kills, sure, but the guys made that easy.", "I had {k}, but look at the spacing everybody gave me.", ""], ex)
	if v == "thick":
		return _g("qf_kills_lt", ["{k} kills and a loss. Doesn't mean anything.", "I don't care that I had {k}."], ex)
	return _g("qf_kills_l", ["Doesn't matter that I had {k}.", "", "The {opp} made us pay for every mistake."], ex)


## What he brings up because of what drives him.
func _drive_tail(s: Soldier, sit: String, mood: String, v: String) -> String:
	if not _chance(0.55):
		return ""
	var losing := sit in ["star_loss", "season_bad"]
	var ex := {"home": LeagueData.state_name(s.home_state) if s.home_state != "" else "home"}
	match _drive(s):
		&"winning":
			return _g("qd_win_l" if losing else "qd_win", ["I'm here to win titles. Anything else is a waste of time.",
				"I didn't come here for anything but winning."] if losing else ["Winning is the only thing I care about.", "This is why I'm here."], ex)
		&"money":
			if mood == "low" or s.contract != null and s.contract.is_expiring():
				return _g("qd_money", ["Everybody knows what my situation is. My agent can talk about the rest.",
					"Business is business. We'll see what happens with my deal."], ex)
		&"playing_time":
			if mood == "low":
				return _g("qd_pt", ["I just want to be on the field. That's all I've ever asked.", "Put me out there and I'll produce."], ex)
			return _g("qd_pt2", ["I want the ball in big moments.", "Keep giving me minutes and this is what you get."], ex)
		&"loyalty":
			return _g("qd_loyal", ["I'd run through a wall for these guys.", "This organization took a chance on me. I don't forget that.",
				"It's about the guy next to you."], ex)
		&"hometown":
			if not sit in ["star_win", "clutch", "star_loss"]:
				return ""
			return _g("qd_home_l" if losing else "qd_home", (["My people back in {home} deserved better than that.", "I'm a {home} kid. I hate losing in front of them."] if losing else ["My people back in {home} were watching. That matters to me.", "I'm a {home} kid. This one's for them.", "Somebody back in {home} is smiling tonight."]), ex)
		&"security":
			if mood == "low":
				return _g("qd_sec", ["I just want to know where I stand.", "You want some stability, you know? Some certainty."], ex)
	return ""

# --- bye, sidelined and the season wrap ---------------------------------------------------

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
	if not mov.is_empty():
		body.append(_para([_g("b_div_open", ["Around {div_name}:", "Elsewhere in {div_name}:"], {"div_name": _div_name(_us)})] + mov.slice(0, 3)))
	var hurt: Array = _us.roster.filter(func(s: Soldier): return s.injury_weeks > 0)
	if not hurt.is_empty():
		var names: Array = []
		for s in hurt.slice(0, 3):
			names.append("%s (%s, %s)" % [_who_role(s), s.injury_name.to_lower(), _plural(s.injury_weeks, "week")])
		body.append(_g("b_hurt", ["The week off matters most to the injury list: {list}.", "The training room will be busy: {list}."], {"list": ", ".join(names)}))
	if row != null:
		var leader: StandingRow = drows[0] if not drows.is_empty() else row
		body.append(_standings_para(wk) if leader != null else "")
	body.append(_buzz_para())
	var star := _team_star(_us)
	if star != null:
		var q := _quote(star, "bye", {})
		body.append(_g("b_q", ["\"{q}\" {who} said.", "\"{q}\" said {who}."], {"q": q, "who": _who_role(star)}))
		art["pull_quote"] = {"text": q, "who": star.display_name(), "team": _us.abbrev}
	body.append(_preview_para(wk))
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


## What `s` wants from his next deal, from his top DNA motivation ("wants a long, safe deal").
func _wants(s: Soldier) -> String:
	var d := String(_drive(s))
	var home := LeagueData.state_name(s.home_state) if s.home_state != "" else "home"
	var opts: Dictionary = {
		"winning": ["wants to play for a contender", "cares more about rings than money", "wants to be somewhere that wins now"],
		"money": ["is chasing the biggest paycheck", "will go to the highest bidder", "wants to be paid like a star"],
		"playing_time": ["wants a guaranteed starting spot", "won't sign anywhere he'll sit", "wants to be on the field every week"],
		"loyalty": ["has said he'd like to stay", "values loyalty above the last dollar", "would like to finish where he is"],
		"hometown": ["would love to play near home in {home}", "has {home} on his mind", "wants to be close to {home}"],
		"security": ["wants a long, safe deal", "wants years more than dollars", "is looking for security"]}
	if not opts.has(d):
		return "wants a fair deal"
	return _g("want_" + d, opts[d], {"home": home})


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
	body.append(_buzz_year_para())
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

func _off_art(kind: String, label: String) -> Dictionary:
	return {"kind": kind, "section": "%s OFFSEASON - %s" % [_f["us_nick"].to_upper(), label.to_upper()], "angles": [kind]}


func _money(k: int) -> String:
	return Contracts.money(k)


## "$1.25M a year for three years".
func _deal(salary: int, years: int) -> String:
	return "%s a year for %s" % [_money(salary), "one year" if years == 1 else "%s years" % _num(years)]


func _cap_line() -> String:
	var space := Contracts.cap_space(_us, _s.cap_year())
	if space < 0:
		return _g("cap_over", ["They are {m} over the cap, and that has to be fixed before camp.", "The cap sheet is {m} in the red."], {"m": _money(-space)})
	return _g("cap_room", ["They have {m} in cap space to work with.", "That leaves {m} of room under the cap.", "The cap sheet shows {m} free."], {"m": _money(space)})


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
	var more: Array = []
	for e in kept.slice(0 if led_with_loss else 1, 4):
		more.append("%s (%s)" % [_who(e["soldier"]), _deal(e["salary"], e["years"])])
	if not more.is_empty():
		body.append(_g("rs_more", ["Also back: {list}.", "They also re-signed {list}."], {"list": _join_and(more)}))
	var left: Array = []
	for e in gone.slice(1 if led_with_loss else 0, 4):
		var s: Soldier = e["soldier"]
		left.append("%s, who %s" % [_who_role(s), _wants(s)])
	if not left.is_empty():
		body.append(_g("rs_left", ["Heading out: {list}.", "Not coming back: {list}."], {"list": "; ".join(left)}))
	if gone_k >= 20:
		body.append(_g("rs_gonek", ["All told, {k} kills from last season walked out the door.", "That's {k} kills of last year's production now on the open market."], {"k": str(gone_k)}))
	# Around the league.
	var market: Array = _s.departures.filter(func(e): return e["year"] == y and e["team"] != _us)
	market.sort_custom(func(a, b): return a["soldier"].best_ovr() > b["soldier"].best_ovr())
	var names: Array = []
	for e in market.slice(0, 3):
		names.append("%s (%d OVR, from the %s)" % [e["soldier"].display_name(), e["soldier"].best_ovr(), _nick(e["team"])])
	if not names.is_empty():
		body.append(_g("rs_market", ["The best names on the open market: {list}.", "Free agency opens with these names available: {list}."], {"list": "; ".join(names)}))
	var need := _need()
	if need != "":
		body.append(_g("rs_need", ["The obvious need is at {need}.", "If you're making a shopping list, start with a {need}."], {"need": need}))
	body.append(_cap_line())
	if big_keep != null:
		var q := _quote(big_keep, "resigned", {})
		body.append("\"%s\" %s said." % [q, big_keep.last_name])
		art["pull_quote"] = {"text": q, "who": big_keep.display_name(), "team": _us.abbrev}
	art["body"] = body
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
			body.append(_g("f_rest", ["They also added {list}.", "Also signed: {list}."], {"list": "; ".join(rest)}))
		var q := _quote(s, "signed", {})
		body.append("\"%s\" %s said." % [q, s.last_name])
		art["pull_quote"] = {"text": q, "who": s.display_name(), "team": _us.abbrev}
	art["dek"] = _cap_first(_g("hf_dek", ["{step} grade: {grade}.", "Our {step} grade for the {us_nick}: {grade}."], ex))
	var big: Array = []
	var old_names: Dictionary = memory.get("season_names", {})
	for e in theirs:
		var key := str(e["soldier"].id)
		if old_names.has(key):
			body.append(_g("f_ex", ["One familiar name moved: {who}, who had {k} kills for the {us_nick} last season, signed with the {t} at {deal}.",
				"{who} is officially gone. The former {us_nick} {role} signed with the {t} for {deal}."],
				{"who": e["soldier"].display_name(), "k": str(old_names[key][1]), "role": old_names[key][2], "t": _nick(e["team"]), "deal": _deal(e["salary"], e["years"])}))
			theirs.erase(e)
			break
	for e in theirs.slice(0, 3):
		big.append("the %s signed %s (%d OVR) at %s" % [_nick(e["team"]), e["soldier"].display_name(), e["soldier"].best_ovr(), _deal(e["salary"], e["years"])])
	if not big.is_empty():
		body.append(_cap_first(_g("f_big", ["Elsewhere, {list}.", "Around the league, {list}."], {"list": "; ".join(big)})))
	var pool: Array = _s.league.free_agents.duplicate()
	pool.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	var left: Array = []
	for s in pool.slice(0, 3):
		left.append("%s (%d OVR, age %d), who %s" % [s.display_name(), s.best_ovr(), s.age, _wants(s)])
	if not left.is_empty():
		body.append(_g("f_left", ["Still on the board: {list}.", "Best still available: {list}."], {"list": "; ".join(left)}))
	var need := _need()
	if need != "":
		body.append(_g("f_need", ["The {us_nick} still look thin at {need}.", "The need at {need} hasn't gone away."], {"need": need}))
	body.append(_cap_line())
	art["body"] = body
	art["sidebar"] = [{"title": "Signings (grade %s)" % grade, "rows": rows if not rows.is_empty() else [["None", ""]]},
		{"title": "Best Available", "rows": pool.slice(0, 5).map(func(s): return [s.short_name(), "%d OVR" % s.best_ovr()])}]
	return art


func _draft_article() -> Dictionary:
	var art := _off_art(KIND_DRAFT, "Draft")
	var picks: Array = _s.draft.picks()
	var ours: Array = picks.filter(func(p: Prospect): return p.drafted_by == _us)
	var body: Array = []
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
			body.append(_g("d_phenom", ["Scouts called him a phenom, and the tape doesn't argue.", "He came in with the phenom tag, and that label carries expectations."]))
		var pex := {"ovr": str(s.best_ovr()), "pot": s.potential_letter(), "ceil": str(s.potential_ovr()), "last": s.last_name}
		if s.potential_grade() >= 3:
			body.append(_g("d_pot_hi", ["He's a {ovr} today with {pot}-grade potential, and the staff's projections have him topping out around {ceil}.",
				"Right now {last} is a {ovr}. The ceiling is the selling point: a {pot} potential grade and a projected peak near {ceil}."], pex))
		else:
			body.append(_g("d_pot_lo", ["He's a {ovr} with a {pot} potential grade, which makes him more of a depth piece than a future star.",
				"The ceiling is modest, a {pot} potential grade and a projected peak around {ceil}, so the {us_nick} are betting on what he is now."], pex))
		var need := _need()
		if need != "" and need == ex["role"]:
			body.append(_g("d_fit", ["It's a pick for a need, too: {role} was the thinnest spot on the depth chart.", "And it fills a hole. The {us_nick} were short at {role}."], ex))
		elif need != "":
			body.append(_g("d_nofit", ["It doesn't fix the shortage at {need}, though. That'll have to come from somewhere else.", "The {need} spot is still thin after this one."], {"need": need}))
		if ex["home"] != "" and s.home_state == _us.home_state:
			body.append(_g("d_local", ["He's a {home} kid, too, which the fans will like.", "And he's from {home}, so he'll have a crowd."], ex))
		var q := _quote(s, "drafted", {})
		body.append("\"%s\" %s said." % [q, s.last_name])
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
		body.append(_g("d_rest", ["Later on: {list}.", "They also took {list}."], {"list": "; ".join(rest)}))
	if not picks.is_empty():
		var top: Prospect = picks[0]
		if top.drafted_by != _us:
			body.append(_g("d_top", ["The first pick went to the {t}, who took {who}.", "{who} went first overall, to the {t}."],
				{"t": _nick(top.drafted_by), "who": top.soldier.display_name()}))
	var grade := _letter(verdicts / maxf(1.0, ours.size()) * 0.8) if not ours.is_empty() else "INC"
	art["grade"] = grade
	art["dek"] = "Draft grade: %s." % grade
	art["body"] = body
	art["sidebar"] = [{"title": "%s Picks" % _us.abbrev, "rows": ours.map(func(p): return [p.soldier.short_name(), "#%d (proj %d)" % [p.pick_number, p.projected_rank]])}]
	return art


func _review_article() -> Dictionary:
	var art := _off_art(KIND_REVIEW, "Roster Review")
	var y := _s.year
	var cuts: Array = _s.trades.moves.filter(func(e): return e["year"] == y and e["team"] == _us and e["kind"] == &"cut")
	var adds: Array = _s.fa.history.filter(func(e): return e["year"] == y and e["when"] == "Roster Review" and e["team"] == _us)
	var body: Array = []
	art["headline"] = _g("hv", ["Taking Shape", "The Roster, Before Camp", "{us_nick} Set Their Group"])
	var ad_w := _num(adds.size()) if adds.size() > 0 else "no"
	var ct_w := _num(cuts.size()) if cuts.size() > 0 else "no"
	art["dek"] = _cap_first("%s late signing%s, %s cut%s, and a first look at the lineup." % [ad_w, "" if adds.size() == 1 else "s", ct_w, "" if cuts.size() == 1 else "s"])
	body.append(_g("v_open", ["With the draft done and the market thinning out, the {us_nick} have roughly the roster they'll take into camp.",
		"Roster review week is where offseason plans meet the cap sheet, and the {us_nick} came out of it with a group that looks like this."]))
	if not adds.is_empty():
		body.append(_g("v_add", ["Late additions: {list}.", "They added {list} in the final free-agent window."],
			{"list": ", ".join(adds.map(func(e): return "%s (%s)" % [_who_role(e["soldier"]), _money(e["salary"])]))}))
	if not cuts.is_empty():
		body.append(_g("v_cut", ["Released: {list}.", "The cuts: {list}."], {"list": ", ".join(cuts.map(func(e): return _who_role(e["soldier"])))}))
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
		body.append(_g("v_five", ["Projected starters in the {us_scheme}: {list}.", "If camp started today, the {us_scheme} would line up {list}."], {"list": "; ".join(groups)}))
	var last: Dictionary = memory.get("last_season", {})
	if last.has("starter_ovr"):
		var now := _avg_starter_ovr(_us)
		var d := now - float(last["starter_ovr"])
		var vex := {"now": "%.1f" % now, "then": "%.1f" % float(last["starter_ovr"]), "d": "%.1f" % absf(d)}
		if d >= 1.0:
			body.append(_g("v_up", ["On paper that's better than last year: the starters average {now}, up from {then}.", "The starting group averages {now}, {d} points better than the one that finished last season."], vex))
		elif d <= -1.0:
			body.append(_g("v_dn", ["On paper it's a step back: the starters average {now}, down from {then}.", "The starters average {now}, {d} points worse than last year's group. Camp has work to do."], vex))
		else:
			body.append(_g("v_eq", ["The starters average {now}, about where last year's group finished ({then}).", "On paper it's the same team as last year: {now} against {then}."], vex))
	body.append(_cap_line())
	var snap := {}
	for s in _us.roster:
		snap[str(s.id)] = s.best_ovr()
	memory["camp_ovr"] = snap
	art["body"] = body
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
		body.append(_g("c_more", ["The rest of the camp assignments: {list}.", "Elsewhere on the practice field: {list}."], {"list": "; ".join(others)}))
	var skipped := Camp.DRILLS.size() - drills.size()
	if skipped > 0:
		body.append(_g("c_skip", ["{n} of the six drills went unused, which is points left on the table.", "They left {n} drills unrun."],
			{"n": _cap_first(_num(skipped)) if skipped > 1 else "One"}))
	var q := _quote(s, "camp", {})
	body.append("\"%s\" %s said." % [q, s.last_name])
	art["pull_quote"] = {"text": q, "who": s.display_name(), "team": _us.abbrev}
	art["dek"] = _cap_first(_g("hc_dek", ["{who} leads the way after the {drill}.", "{drill} report: {pts} for {who}."], {"who": s.last_name, "drill": ex["drill"], "pts": ex["pts"]}))
	art["body"] = body
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
			body.append(_g("pr_gone", ["Gone from last year's roster: {list}. That's {k} kills to replace.",
				"The departures matter: {list}, {k} kills between them."] if gk > 0 else ["Gone from last year's roster: {list}."],
				{"list": _join_and(names), "k": str(gk)}))
	else:
		body.append(_g("pr_first", ["The {us_full} open {year} rated {pos} of {n} in the league, with a team OVR of {ovr}.",
			"Here's where the {us_nick} start: {pos} of {n} by the ratings, a {ovr} team OVR."], ex))
	var old_ids: Array = memory.get("season_roster", [])
	var new_faces: Array = _us.roster.filter(func(s: Soldier): return not old_ids.is_empty() and not old_ids.has(s.id))
	new_faces.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	if not new_faces.is_empty():
		body.append(_g("pr_new", ["The new faces: {list}.", "Arrivals to know: {list}."],
			{"list": ", ".join(new_faces.slice(0, 4).map(func(s): return "%s (%d)" % [_who_role(s), s.best_ovr()]))}))
	var star := _top_ovr(_us, 1)
	if not star.is_empty():
		var s: Soldier = star[0]
		body.append(_g("pr_star", ["It all still runs through {who}, the roster's best at {ovr}.", "The best player on the roster is {who}, a {ovr}."],
			{"who": _who_role(s), "ovr": str(s.best_ovr())}))
	var vets: Array = _us.roster.filter(func(s: Soldier): return s.age >= 33 and s.contract != null and s.contract.is_expiring())
	if not vets.is_empty():
		body.append(_g("pr_vet", ["Watch {who}, {age} and in the last year of his deal. This could be the last ride.", "{who} is {age} and playing out his contract."],
			{"who": _who_role(vets[0]), "age": str(vets[0].age)}))
	body.append(_g("pr_scheme", ["They'll run the {us_scheme}.", "The plan is the {us_scheme}."]) + " " + String(Scheme.BLURBS.get(_us.scheme.id, "")))
	body.append(_buzz_pre_para())
	body.append(_preview_para(1))
	var q_s: Soldier = star[0] if not star.is_empty() else null
	if q_s != null:
		var q := _quote(q_s, "camp", {})
		body.append("\"%s\" %s said." % [q, q_s.last_name])
		art["pull_quote"] = {"text": q, "who": q_s.display_name(), "team": _us.abbrev}
	art["body"] = body
	art["sidebar"] = [{"title": "Power Ratings", "rows": teams.slice(0, 8).map(func(t): return [t.abbrev, str(t.team_ovr())])}, _buzz_box()]
	return art

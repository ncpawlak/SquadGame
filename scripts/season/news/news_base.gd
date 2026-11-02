extends RefCounted
## Shared state and helpers for the Weekly News (see Newsroom): phrase grammar, team and soldier lookups,
## quotes, buzz and the league roundup. The article builders sit in the layers above it:
## NewsGame (the game-week article), NewsSeason (bye, sidelined, wrap) and NewsOffseason (offseason issues).

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
## People remembered across weeks (Player of the Week, MVP runs, our soldiers' lines); see NewsHistory.
var history: Dictionary = {}

# Working state for the issue being written (cleared afterwards so saves never see it).
var _r := RandomNumberGenerator.new()

var _s: Season = null

var _us: Team = null

var _f: Dictionary = {}

var _seen: Dictionary = {}

var _ids: Dictionary = {}

var _table: Array = []


# --- public -----------------------------------------------------------------------

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
	var nn := _num(n) if word in ["week", "win", "loss", "game", "match", "drill", "season", "point", "pick", "time", "award"] else str(n)
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
	var rec := _s.ledger.head_to_head_of(_us, them)
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

## The year in money: revenue, where it ranks, the gate and the sellouts.
func _money_year_para() -> String:
	var led := _s.revenue.ledger_of(_s.year, _us)
	if led.is_empty():
		return ""
	var table := _s.revenue.table(_s)
	var rank := 1
	for i in table.size():
		if table[i]["team"] == _us:
			rank = i + 1
	var ex := {"rev": _money(roundi(float(led["revenue"]))), "tix": _money(roundi(float(led["tickets"]))), "rank": _ord(rank), "n": str(table.size())}
	var out: Array = [_g("my_rev", ["On the business side, the {us_nick} took in {rev} this year, {rank} of {n} in the league, with {tix} of it from the gate.",
		"The books: {rev} in revenue, {rank} of {n}, and {tix} at the gate."], ex)]
	if int(led["sellouts"]) > 0:
		out.append(_g("my_so", ["They sold out {so} at home.", "The building was full for {so}."], {"so": _plural(int(led["sellouts"]), "game")}))
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
		var led := _s.revenue.ledger_of(_s.year, _us)
		if not led.is_empty():
			rows.append(["Revenue", _money(roundi(float(led["revenue"])))])
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
	var text := _g("r_buzz", ["The {t} are the talk of the league: buzz is {band} ({b}).", "Nobody is louder than the {t} right now, at {band} ({b}).", "Buzz around the {t} sits at {band} ({b}), the highest in the league.", "{band} ({b}): that is where the {t} are in the court of public opinion."], ex)
	if why != "":
		text += " " + _g("r_buzz_why", ["The biggest swing: {why}.", "It started with {why}.", "The move that did it: {why}.", "Most of the heat traces back to {why}."], {"why": why})
	return {"head": "Buzz Watch", "text": text}

## A player on another club with the longest run of match-MVP games (three or more), as a roundup item.
func _mvp_heater() -> Dictionary:
	var best_id := -1
	var best_n := 2
	for key in (history.get("mvp", {}) as Dictionary):
		var n := int(history["mvp"][key]["n"])
		var so: Soldier = _ids.get(int(key))
		if n > best_n and so != null and not _us.roster.has(so):
			best_n = n
			best_id = int(key)
	if best_id < 0:
		return {}
	var so: Soldier = _ids[best_id]
	var team: Team = null
	for t in _s.league.teams:
		if t.roster.has(so):
			team = t
			break
	if team == null:
		return {}
	return {"head": "Heater", "text": _g("r_heater", [
		"{who} of the {tm} has been the match MVP {n} times in a row.",
		"Nobody on the {tm} can take the MVP award from {who} right now: {n} matches running."],
		{"who": so.display_name(), "tm": _nick(team), "n": str(best_n)})}


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
		var again := NewsHistory.potw_count(history, s.id, _s.year)
		if again >= 2:
			out[-1]["text"] += " It is his %s Player of the Week award this season." % _ord_word(again)
	var heater := _mvp_heater()
	if not heater.is_empty():
		out.append(heater)
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
			"Nobody saw the {w} beating the {l}, {sc}. The ratings gap was {gap}.",
			"{sc} to the {w}, over a {l} roster that rated {gap} points better. The rating sheet had other plans for the night.",
			"On paper the {l} were {gap} points clear. On the field it was the {w}, {sc}.",
			"Call it the upset of the week: the {w} over the {l}, {sc}, against a {gap}-point rating gap."],
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
		return _g("qf_hill", ["I was on that point for {hold}. That hill was ours.", "We held that hill. I spent {hold} on it and I'd do it again.",
			"{hold} on the point, and nobody got me off it.", "Hill was the whole game for me. {hold} up there and I wasn't moving.", "You sit on that point for {hold} and you stop hearing anything but the countdown."], ex)
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


func _money(k: int) -> String:
	return Contracts.money(k)

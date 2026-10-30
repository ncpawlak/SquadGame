class_name LeagueData
extends RefCounted
## The fixed 20-team league: franchises, divisions, home states and the opening
## pick trades (rivalries live in Rivalries). Player rosters live in data/league.json (authored once by tools/build_league.gd
## and never regenerated); only draft classes are generated each season.

const DIVISIONS: Array[String] = ["East", "South", "Central", "West"]

## abbrev, city, nickname, primary, secondary, division, home state, preseason OVR, backstory.
const TEAMS := [
	["NYE", "New York", "Empire", "#1B1B1F", "#D4AF37", "East", "NY", 85,
		"Wealthiest and most recognizable franchise. Built around expensive superstars and aggressive free-agent signings, but has limited salary-cap flexibility."],
	["DET", "Detroit", "Ironmen", "#39434B", "#D97732", "East", "MI", 83,
		"Defending champions renowned for defensive discipline, elite coaching, and player development. Their veteran captain is approaching retirement."],
	["LAS", "Los Angeles", "Stars", "#F2B632", "#432E74", "West", "CA", 82,
		"Star-studded franchise built through blockbuster trades and expensive contracts. Explosive offense, but chemistry issues and limited roster depth threaten their title ambitions."],
	["BOS", "Boston", "Minutemen", "#E5D8BC", "#8B1E2D", "East", "MA", 82,
		"Historic, decorated franchise known for tactical preparation and intelligent drafting. Aging veterans are chasing one final championship after years of playoff disappointment."],
	["SEA", "Seattle", "Storm", "#244C40", "#9DC4AD", "West", "WA", 80,
		"Young, analytically driven contender built around precision, intelligence gathering, and map control. Widely viewed as a potential future dynasty."],
	["ARL", "Arlington", "Outlaws", "#A65A2A", "#20252B", "Central", "TX", 79,
		"Aggressive Texas powerhouse built around elite offensive talent. Dominant in elimination-heavy matches but occasionally sacrifices objectives for individual statistics."],
	["CHI", "Chicago", "Cyclones", "#D9E3EA", "#1669A4", "Central", "IL", 78,
		"Former powerhouse emerging from a successful rebuild. Young, fast, and relentless, with a high-pressure tactical style and growing championship expectations."],
	["STL", "St. Louis", "Sentinels", "#173B35", "#C6C9CC", "Central", "MO", 77,
		"Disciplined defensive organization built through drafting and development. Excellent coordination and coaching, but lacks a true offensive superstar."],
	["CHA", "Charlotte", "Royals", "#552583", "#F5C542", "South", "NC", 76,
		"Ambitious franchise revitalized by ownership investment in coaching and facilities. Talented and rapidly improving, but still unproven in high-pressure playoff situations."],
	["SDV", "San Diego", "Vipers", "#75B843", "#22272B", "West", "CA", 75,
		"Dangerous, aggressive squad specializing in early engagements and eliminations. Exceptional offensive potential, but inconsistent support play undermines team coordination."],
	["REN", "Reno", "Aces", "#981B32", "#111217", "West", "NV", 75,
		"Cleverly managed smaller-market team known for overlooked talent and unconventional strategies. Strong clutch performance and efficient contracts offset limited superstar power."],
	["ATL", "Atlanta", "Bulldogs", "#2C2C30", "#BA0C2F", "South", "GA", 74,
		"Tough, defensively oriented franchise known for physical play and consistency. Competitive most seasons, but lacks the offensive firepower to overcome elite opponents."],
	["IND", "Indianapolis", "Racers", "#1455B3", "#F4F4F4", "East", "IN", 73,
		"Fast-paced young squad emphasizing movement, speed, and offensive pressure. Talented prospects show promise but struggle against experienced tactical opponents."],
	["MIA", "Miami", "Pirates", "#53606A", "#E37B61", "South", "FL", 72,
		"Flashy franchise with talented individuals but frequent roster turnover. Poor discipline, inconsistent coaching, and chemistry problems prevent sustained success."],
	["DEN", "Denver", "Grizzlies", "#4B382A", "#D5A24A", "West", "CO", 71,
		"Once-feared defensive franchise struggling to adapt to the modern competitive environment. Aging veterans and expensive contracts have slowed an overdue transition."],
	["BKN", "Brooklyn", "Breakers", "#102A43", "#00B8B0", "East", "NY", 70,
		"Scrappy underdog historically overshadowed by the New York Empire. Recently drafted a potential franchise superstar but still lacks veteran leadership and supporting talent."],
	["NSH", "Nashville", "Rattlers", "#B89A42", "#262626", "South", "TN", 69,
		"Young, aggressive franchise loaded with developmental talent. Raw mechanical skill is promising, but poor discipline and inconsistent tactical decisions limit results."],
	["LOU", "Louisville", "Mustangs", "#0B4F3C", "#D7A34A", "Central", "KY", 68,
		"Formerly successful franchise entering a major rebuild. Recently traded aging veterans for draft capital and salary-cap flexibility to prepare for the future."],
	["ORL", "Orlando", "Comets", "#233C91", "#FF6633", "South", "FL", 67,
		"Struggling franchise burdened by failed free-agent contracts and weak roster depth. A promising young offensive prospect offers hope amid poor leadership and financial constraints."],
	["LRK", "Little Rock", "Riverhawks", "#356B82", "#C1A272", "Central", "AR", 65,
		"Small-market franchise undergoing a complete rebuild. Limited current talent but excellent youth development, promising prospects, and valuable future draft picks."],
]

## abbrev -> [newspaper, beat writer]: who covers each club in the Weekly News (Newsroom).
const PRESS := {
	"NYE": ["Empire City Herald", "Vivian Castellano"],
	"DET": ["Detroit Motor Ledger", "Ray Kowalczyk"],
	"LAS": ["Los Angeles Sun-Courier", "Marisol Vega"],
	"BOS": ["Boston Commonwealth Post", "Desmond Fairweather"],
	"SEA": ["Puget Sound Dispatch", "Hannah Lindqvist"],
	"ARL": ["Tarrant County Clarion", "Wade Hollister"],
	"CHI": ["Chicago Lakefront Tribune", "Frank Mazurek"],
	"STL": ["Gateway Post-Examiner", "Lorraine Beaumont"],
	"CHA": ["Queen City Observer", "Calvin Pettiford"],
	"SDV": ["San Diego Harbor Times", "Elena Ruiz-Taylor"],
	"REN": ["High Desert Gazette", "Jack Delacroix"],
	"ATL": ["Peachtree Courier", "Darnell Whitfield"],
	"IND": ["Crossroads Star", "Mitch Brandenburg"],
	"MIA": ["Biscayne Herald", "Sofia Arrieta"],
	"DEN": ["Mile High Sentinel", "Gus Thorvaldsen"],
	"BKN": ["Brooklyn Eagle-Bulletin", "Nadia Rosenthal"],
	"NSH": ["Music City Banner", "Beau Ellery"],
	"LOU": ["Bluegrass Courier", "Shelby Hargrove"],
	"ORL": ["Orange County Beacon", "Trevor Okonkwo"],
	"LRK": ["Riverfront Gazette", "Earl Whitlock"],
}
const _PRESS_WRITERS := ["Pat Donnelly", "Renee Albright", "Sam Okafor", "Lou Brennan", "Dana Whitcomb", "Max Ferreira"]


## [paper, writer] covering `team` (generated clubs get a stable stand-in).
static func press_for(team: Team) -> Array:
	if PRESS.has(team.abbrev):
		return PRESS[team.abbrev]
	var place := team.city if team.city != "" else team.name
	return ["%s Daily Wire" % place, _PRESS_WRITERS[absi(hash(team.abbrev)) % _PRESS_WRITERS.size()]]


## Every state (and DC) belongs to one division's region (hometown pull, region scouting).
const STATE_REGION := {
	"ME": "East", "NH": "East", "VT": "East", "MA": "East", "RI": "East", "CT": "East", "NY": "East",
	"NJ": "East", "PA": "East", "DE": "East", "MD": "East", "DC": "East", "MI": "East", "OH": "East",
	"IN": "East", "WV": "East",
	"VA": "South", "NC": "South", "SC": "South", "GA": "South", "FL": "South", "AL": "South",
	"MS": "South", "TN": "South",
	"TX": "Central", "OK": "Central", "AR": "Central", "LA": "Central", "KY": "Central", "IL": "Central",
	"MO": "Central", "IA": "Central", "MN": "Central", "WI": "Central", "KS": "Central", "NE": "Central",
	"SD": "Central", "ND": "Central",
	"CA": "West", "WA": "West", "OR": "West", "NV": "West", "CO": "West", "AZ": "West", "NM": "West",
	"UT": "West", "ID": "West", "MT": "West", "WY": "West", "AK": "West", "HI": "West",
}

const STATE_NAMES := {
	"AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
	"CT": "Connecticut", "DE": "Delaware", "DC": "Washington D.C.", "FL": "Florida", "GA": "Georgia",
	"HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
	"KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts",
	"MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
	"NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
	"NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
	"OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
	"TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
	"WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
}

## Rough talent-pool weights: where prospects and free agents come from.
const STATE_WEIGHTS := {
	"CA": 12, "TX": 10, "FL": 8, "NY": 7, "GA": 5, "IL": 5, "OH": 5, "PA": 5, "NC": 4, "MI": 4,
	"VA": 3, "WA": 3, "AZ": 3, "TN": 3, "IN": 3, "MO": 3, "CO": 3, "NJ": 3, "MA": 3, "LA": 2,
	"AL": 2, "SC": 2, "KY": 2, "MD": 2, "MN": 2, "WI": 2, "OK": 2, "OR": 2, "NV": 2, "AR": 2,
	"UT": 1, "IA": 1, "KS": 1, "MS": 1, "NE": 1, "NM": 1, "CT": 1, "WV": 1, "ID": 1, "HI": 1,
	"ME": 1, "NH": 1, "RI": 1, "MT": 1, "DE": 1, "SD": 1, "ND": 1, "AK": 1, "VT": 1, "WY": 1, "DC": 1,
}

## Draft picks traded away before the league's first season: [draft year offset, round, original
## team, owner]. Louisville and Little Rock stockpiled them in their rebuilds.
const OPENING_PICK_TRADES := [
	[0, 1, "DEN", "LOU"], [0, 2, "NYE", "LOU"], [1, 1, "BOS", "LOU"],
	[0, 1, "LAS", "LRK"], [0, 2, "ORL", "LRK"], [1, 1, "NYE", "LRK"], [1, 2, "DET", "LRK"],
]


static func team_row(abbrev: String) -> Array:
	for r in TEAMS:
		if r[0] == abbrev:
			return r
	return []


static func region_of(state: String) -> String:
	return STATE_REGION.get(state, "")


static func state_name(state: String) -> String:
	return STATE_NAMES.get(state, state)


## A weighted random state (all states if `region` is "", else only that region's).
static func random_state(rng: RandomNumberGenerator, region := "") -> String:
	var total := 0
	for st in STATE_WEIGHTS:
		if region == "" or STATE_REGION[st] == region:
			total += int(STATE_WEIGHTS[st])
	var roll := rng.randi_range(1, total)
	for st in STATE_WEIGHTS:
		if region == "" or STATE_REGION[st] == region:
			roll -= int(STATE_WEIGHTS[st])
			if roll <= 0:
				return st
	return "CA"

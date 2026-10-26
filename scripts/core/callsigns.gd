class_name Callsigns
extends RefCounted
## Callsign pools keyed by a soldier's best stat group. A soldier gets one from the pool matching
## his strongest group; callsigns are unique among active soldiers in the league.

const POOLS := {
	&"accuracy": ["Hawkeye", "Deadeye", "Longshot", "Crosshair", "Bullseye", "Sniper", "Lancer", "Pinpoint",
		"Scope", "Falcon", "Arrow", "Marksman", "Needle", "Optic", "Sightline", "Kestrel", "Zero", "Range",
		"Tracer", "Spotter", "Eagle", "Vector", "Dart", "Lens", "Ghost"],
	&"handling": ["Trigger", "Quickdraw", "Hammer", "Slide", "Clip", "Chamber", "Gunsmith", "Bolt", "Rattle",
		"Stock", "Burst", "Spitfire", "Recoil", "Brass", "Magpie", "Ratchet", "Smoke", "Pistol", "Snapshot",
		"Cyclone", "Rapid", "Drum", "Hotshot", "Spark", "Flint"],
	&"physicality": ["Tank", "Bulldozer", "Rhino", "Bison", "Brick", "Juggernaut", "Ox", "Grizzly", "Moose",
		"Titan", "Mammoth", "Boulder", "Diesel", "Hulk", "Anvil", "Jackrabbit", "Cheetah", "Blitz", "Viper",
		"Lightning", "Mongoose", "Jet", "Gazelle", "Wolf", "Panther"],
	&"mentality": ["Maverick", "Professor", "Chess", "Iceman", "Sage", "Oracle", "Compass", "Anchor", "Shepherd",
		"Captain", "Atlas", "Cipher", "Radar", "Echo", "Monk", "Stoic", "Prophet", "Wizard", "Owl", "Coach",
		"Patch", "Signal", "Archer", "Pilot", "Watchman"],
	&"objective": ["Sentinel", "Warden", "Keeper", "Gatekeeper", "Ram", "Breaker", "Siege", "Vanguard",
		"Spearhead", "Bulldog", "Summit", "Ridge", "Hilltop", "Beacon", "Outpost", "Garrison", "Sentry", "Holdfast",
		"Lockdown", "Overlord", "Baron", "Claim", "Bastille", "Citadel", "Highground"],
	&"durability": ["Ironside", "Rock", "Granite", "Bunker", "Fortress", "Steel", "Cast Iron", "Bedrock",
		"Concrete", "Rebar", "Bastion", "Wall", "Armor", "Kevlar", "Bulwark", "Crowbar", "Nails", "Gravel",
		"Rampart", "Tough Guy", "Unbreakable", "Brickhouse", "Mule", "Stone", "Oak"],
}

## Used once a soldier's group pools are all taken (a 240-man league plus free agents and prospects).
const GENERAL := [
	"Ace", "Apex", "Avalanche", "Badger", "Bandit", "Banshee", "Barracuda", "Bearcat", "Blackjack", "Blade",
	"Blaze", "Blizzard", "Bluejay", "Bobcat", "Bones", "Boomer", "Bravo", "Bronco", "Buckshot", "Buzzsaw",
	"Cactus", "Canyon", "Cardinal", "Cargo", "Cobalt", "Cobra", "Comet", "Condor", "Copper", "Cougar", "Coyote",
	"Crash", "Crow", "Cutlass", "Dagger", "Dakota", "Dash", "Dingo", "Domino", "Doc", "Dozer", "Dragon",
	"Drifter", "Duke", "Dusty", "Dynamo", "Ember", "Fang", "Ferret", "Fireball", "Fisher", "Flash", "Flyer",
	"Fox", "Frost", "Fury", "Gator", "Gecko", "Gizmo", "Glacier", "Gonzo", "Gopher", "Gremlin", "Griffin",
	"Gunner", "Gust", "Hatchet", "Havoc", "Hazard", "Heron", "Hex", "Hickory", "Hornet", "Hound", "Hurricane",
	"Husky", "Hyena", "Icebox", "Jackal", "Jaguar", "Jester", "Jinx", "Jolt", "Jockey", "Judge", "Junior",
	"Kodiak", "Kong", "Kraken", "Lasso", "Legend", "Lefty", "Lobo", "Lockjaw", "Lucky", "Lynx", "Mako",
	"Mantis", "Marlin", "Mercury", "Midnight", "Mojo", "Monsoon", "Mustang", "Nomad", "Nova", "Nugget", "Onyx",
	"Orbit", "Osprey", "Outlaw", "Ozark", "Paladin", "Pepper", "Phantom", "Phoenix", "Pike", "Piston",
	"Pitbull", "Prowler", "Puma", "Python", "Quake", "Quill", "Raider", "Rascal", "Raven", "Razor", "Rebel",
	"Reaper", "Ricochet", "Riptide", "Rocket", "Rogue", "Rooster", "Rowdy", "Ruckus", "Rusty", "Sabre", "Saint",
	"Scorpion", "Scout", "Scrapper", "Shadow", "Shark", "Shogun", "Skipper", "Slate", "Sledge", "Slick",
	"Smokey", "Snake", "Sparrow", "Specter", "Sphinx", "Spike", "Stallion", "Stinger", "Storm", "Striker",
	"Sundance", "Taco", "Talon", "Tango", "Taz", "Tempest", "Thunder", "Tiger", "Tinman", "Tomahawk", "Tonka",
	"Torch", "Tornado", "Trapper", "Trojan", "Tundra", "Turbo", "Tusk", "Twister", "Typhoon", "Valkyrie",
	"Venom", "Voodoo", "Vulture", "Wasp", "Whiskey", "Whip", "Wildcat", "Wolverine", "Wrangler", "Wraith",
	"Yankee", "Yeti", "Zephyr", "Zulu", "Bishop", "Bowie", "Brawler", "Chief", "Colt", "Crusader", "Cyclops",
	"Dutch", "Gambit", "Goose", "Hondo", "Iceberg", "Kingpin", "Maestro", "Major", "Nitro", "Pharaoh",
	"Rambler", "Ranger", "Rook", "Sarge", "Sheriff", "Sling", "Spartan", "Tex", "Trucker", "Wheels", "Wrench",
	"Ziggy"
]

## Last resort: "<prefix> <callsign>" (e.g. "Iron Hawkeye") instead of a number.
const PREFIXES := ["Iron", "Little", "Big", "Black", "Red", "Silent", "Lone", "Wild", "Old", "Young", "Mad", "Cold"]


## The group a callsign is drawn from: his best group (durability included).
static func best_group(s: Soldier) -> StringName:
	var best: StringName = Stats.ACCURACY
	var best_v := -1.0
	for g in Stats.GROUP_ORDER:
		var v := Stats.group_average(s.stats, g)
		if v > best_v:
			best_v = v
			best = g
	return best


## A free callsign for `s`, starting at a deterministic spot in his group's pool, then the other
## pools, then the general pool, then prefixed variants (numbers only if all of those are taken).
static func pick(s: Soldier, taken: Dictionary) -> String:
	var order: Array = [best_group(s)]
	for g in Stats.GROUP_ORDER:
		if not order.has(g):
			order.append(g)
	for g in order:
		var pool: Array = POOLS[g]
		var start := absi(hash(s.id * 31 + 7)) % pool.size()
		for i in pool.size():
			var name: String = pool[(start + i) % pool.size()]
			if not taken.has(name.to_lower()):
				return name
	var gstart := absi(hash(s.id * 17 + 3)) % GENERAL.size()
	for i in GENERAL.size():
		var name: String = GENERAL[(gstart + i) % GENERAL.size()]
		if not taken.has(name.to_lower()):
			return name
	var own: Array = POOLS[order[0]]
	for pre in PREFIXES:
		for i in own.size():
			var name := "%s %s" % [pre, own[(absi(hash(s.id)) + i) % own.size()]]
			if not taken.has(name.to_lower()):
				return name
	var base: String = POOLS[order[0]][absi(hash(s.id)) % POOLS[order[0]].size()]
	var n := 2
	while taken.has(("%s %d" % [base, n]).to_lower()):
		n += 1
	return "%s %d" % [base, n]

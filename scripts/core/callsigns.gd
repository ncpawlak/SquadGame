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
	&"durability": ["Ironside", "Rock", "Granite", "Bunker", "Fortress", "Steel", "Cast Iron", "Bedrock",
		"Concrete", "Rebar", "Bastion", "Wall", "Armor", "Kevlar", "Bulwark", "Crowbar", "Nails", "Gravel",
		"Rampart", "Tough Guy", "Unbreakable", "Brickhouse", "Mule", "Stone", "Oak"],
}


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
## pools, then numbered variants.
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
	var base: String = POOLS[order[0]][absi(hash(s.id)) % POOLS[order[0]].size()]
	var n := 2
	while taken.has(("%s %d" % [base, n]).to_lower()):
		n += 1
	return "%s %d" % [base, n]

class_name FpsWeaponDefs
extends RefCounted
## Data-driven weapon definitions. Angles are degrees, times seconds, distances metres.
## spread_* are the cone half-angle at a 50-rated soldier for the distance band; the matching
## SHORT/MEDIUM/LONG_ACC stat scales them (see FpsWeapon.accuracy_factor).

const MODE_SEMI := &"semi"
const MODE_AUTO := &"auto"
const MODE_BURST := &"burst"

## Distance bands (upper bounds, metres): short < SHORT_MAX <= medium < MEDIUM_MAX <= long.
const SHORT_MAX := 12.0
const MEDIUM_MAX := 35.0

const DEFS := {
	&"rifle": {
		"name": "Assault Rifle",
		"damage": 28.0, "headshot_mult": 2.0,
		"rpm": 600.0, "mode": &"auto", "modes": [&"auto", &"burst", &"semi"], "burst_count": 3, "burst_rpm": 900.0,
		"mag_size": 30, "reserve": 120, "reload_time": 2.2,
		"spread_short": 1.2, "spread_medium": 0.9, "spread_long": 0.7,
		"bloom_per_shot": 0.25, "bloom_max": 2.5, "bloom_recover": 4.0,
		"recoil_pitch": 0.9, "recoil_yaw": 0.35, "recoil_max": 12.0, "recoil_recover": 6.0,
		"falloff_start": 30.0, "falloff_end": 80.0, "min_damage_mult": 0.6,
		"sway": 0.25, "range": 250.0,
	},
	&"smg": {
		"name": "SMG",
		"damage": 18.0, "headshot_mult": 1.6,
		"rpm": 850.0, "mode": &"auto", "modes": [&"auto", &"semi"], "burst_count": 3, "burst_rpm": 1000.0,
		"mag_size": 32, "reserve": 160, "reload_time": 1.7,
		"spread_short": 1.0, "spread_medium": 1.8, "spread_long": 3.0,
		"bloom_per_shot": 0.3, "bloom_max": 3.5, "bloom_recover": 5.0,
		"recoil_pitch": 0.6, "recoil_yaw": 0.5, "recoil_max": 9.0, "recoil_recover": 8.0,
		"falloff_start": 12.0, "falloff_end": 45.0, "min_damage_mult": 0.45,
		"sway": 0.2, "range": 200.0,
	},
	&"marksman": {
		"name": "Marksman Rifle",
		"damage": 60.0, "headshot_mult": 2.5,
		"rpm": 160.0, "mode": &"semi", "modes": [&"semi"], "burst_count": 1, "burst_rpm": 160.0,
		"mag_size": 10, "reserve": 40, "reload_time": 2.8,
		"spread_short": 1.5, "spread_medium": 0.6, "spread_long": 0.25,
		"bloom_per_shot": 0.8, "bloom_max": 3.0, "bloom_recover": 2.5,
		"recoil_pitch": 2.6, "recoil_yaw": 0.4, "recoil_max": 8.0, "recoil_recover": 5.0,
		"falloff_start": 80.0, "falloff_end": 200.0, "min_damage_mult": 0.8,
		"sway": 0.45, "range": 400.0,
	},
	&"pistol": {
		"name": "Pistol",
		"damage": 22.0, "headshot_mult": 2.0,
		"rpm": 400.0, "mode": &"semi", "modes": [&"semi"], "burst_count": 1, "burst_rpm": 400.0,
		"mag_size": 12, "reserve": 48, "reload_time": 1.5,
		"spread_short": 1.0, "spread_medium": 1.4, "spread_long": 2.2,
		"bloom_per_shot": 0.5, "bloom_max": 2.5, "bloom_recover": 4.0,
		"recoil_pitch": 1.2, "recoil_yaw": 0.3, "recoil_max": 6.0, "recoil_recover": 7.0,
		"falloff_start": 15.0, "falloff_end": 50.0, "min_damage_mult": 0.5,
		"sway": 0.2, "range": 150.0,
	},
}


static func ids() -> Array:
	return DEFS.keys()


static func get_def(id: StringName) -> Dictionary:
	return DEFS.get(id, DEFS[&"rifle"])

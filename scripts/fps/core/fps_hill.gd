class_name FpsHill
extends RefCounted
## Shared hill state for the 3D game. A hill match publishes the zone and the live state here; the weapon (breach), the
## player and bots (anchor) and the HUD (objective IQ readout) read it. Inactive when there is no hill match.

static var active := false
static var center := Vector3.ZERO
static var radius := 6.0
## {holder: int (-1 none), zone: FpsHillRules.Zone, scores: Array, time_left: float, hold_to_win: float}
static var state: Dictionary = {}


static func set_zone(p_center: Vector3, p_radius: float) -> void:
	active = true
	center = p_center
	radius = p_radius


static func clear() -> void:
	active = false
	state = {}


## True when a world position is on the hill (a flat circle, like the match's own check).
static func on_hill(pos: Vector3) -> bool:
	if not active:
		return false
	return Vector2(pos.x - center.x, pos.z - center.z).length() <= radius

class_name FpsHill
extends RefCounted
## Shared hill state for the 3D game. A hill match publishes the zone and the live state here; the weapon (breach), the
## player and bots (anchor) and the HUD (objective IQ readout) read it. Inactive when there is no hill match.
## The zone is a circle (set_zone, the legacy hill) or an axis-aligned square (set_rect, the arena hill).

static var active := false
static var center := Vector3.ZERO
static var radius := 6.0
## When true the hill is `rect` (2D x/z) instead of the circle.
static var use_rect := false
static var rect := Rect2()
## {holder: int (-1 none), zone: FpsHillRules.Zone, scores: Array, time_left: float, hold_to_win: float}
static var state: Dictionary = {}


static func set_zone(p_center: Vector3, p_radius: float) -> void:
	active = true
	use_rect = false
	center = p_center
	radius = p_radius


## A square/rect hill in world x/z (2D y == 3D z). `center` and a half-diagonal `radius` stay valid for consumers.
static func set_rect(r: Rect2) -> void:
	active = true
	use_rect = true
	rect = r
	var c := r.get_center()
	center = Vector3(c.x, 0.0, c.y)
	radius = r.size.length() * 0.5


static func clear() -> void:
	active = false
	use_rect = false
	rect = Rect2()
	state = {}


## True when a world position is on the hill (a flat circle or rect, like the match's own check).
static func on_hill(pos: Vector3) -> bool:
	if not active:
		return false
	if use_rect:
		return rect.has_point(Vector2(pos.x, pos.z))
	return Vector2(pos.x - center.x, pos.z - center.z).length() <= radius

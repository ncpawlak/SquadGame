class_name FpsHealth
extends Node
## Reusable health component. Add as a child of anything that should take damage; the owner's
## own take_damage(amount, hit) can simply forward to this node's take_damage.

signal changed(health: float, max_health: float)
signal damaged(amount: float, source)
signal died(source)

@export var max_health: float = 100.0
var health: float = 100.0
var dead: bool = false
## Multiplied into incoming damage (armour, toughness...).
var damage_scale: float = 1.0


func _init(p_max: float = 100.0) -> void:
	max_health = p_max
	health = p_max


func take_damage(amount: float, hit: Dictionary = {}) -> float:
	## Returns the damage actually applied.
	if dead or amount <= 0.0:
		return 0.0
	var applied := minf(amount * damage_scale, health)
	health -= applied
	var source = hit.get("source", null)
	damaged.emit(applied, source)
	changed.emit(health, max_health)
	if health <= 0.0:
		dead = true
		died.emit(source)
	return applied


func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = minf(max_health, health + amount)
	changed.emit(health, max_health)


func reset() -> void:
	health = max_health
	dead = false
	changed.emit(health, max_health)


func fraction() -> float:
	return health / maxf(max_health, 0.001)

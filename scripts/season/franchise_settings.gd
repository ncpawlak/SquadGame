class_name FranchiseSettings
extends RefCounted
## Per-franchise options chosen at team select and editable later in the in-game settings.
## Stored on Season.settings (the generic save serializer picks the fields up automatically; old
## saves simply keep these defaults). apply() pushes the values into the systems that read them
## (Trades.difficulty(), Fx.is_reduced()).

var trade_difficulty: int = Trades.Difficulty.NORMAL
var reduce_animations: bool = false
var fantasy_draft: bool = false


func to_dict() -> Dictionary:
	return {
		"trade_difficulty": trade_difficulty,
		"reduce_animations": reduce_animations,
		"fantasy_draft": fantasy_draft,
	}


static func from_dict(d: Dictionary) -> FranchiseSettings:
	var s := FranchiseSettings.new()
	s.trade_difficulty = clampi(int(d.get("trade_difficulty", s.trade_difficulty)), 0, Trades.Difficulty.HARD)
	s.reduce_animations = bool(d.get("reduce_animations", s.reduce_animations))
	s.fantasy_draft = bool(d.get("fantasy_draft", s.fantasy_draft))
	return s


## Pushes the values into Trades and Fx so existing code keeps reading those.
func apply() -> void:
	Trades.set_difficulty(trade_difficulty)
	Fx.set_reduced(reduce_animations)


## Pulls the current global values back in (the in-game settings cards still toggle the globals).
func sync_from_globals() -> void:
	trade_difficulty = Trades.difficulty()
	reduce_animations = Fx.is_reduced()


## Starting point for the new-franchise popup: the global defaults.
static func from_globals() -> FranchiseSettings:
	var s := FranchiseSettings.new()
	s.sync_from_globals()
	return s

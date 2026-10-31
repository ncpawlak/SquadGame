class_name StatLedger
extends RefCounted
## What the league remembers beyond the per-season lines on each soldier: match counts by phase now,
## single-game records and streaks as the records engine lands (issue #11). Fed once per league match
## from `Season.play_week_match`.

## Matches recorded so far, split by phase.
var matches_regular := 0
var matches_playoffs := 0


## Records one finished league match. `playoffs` is true for any knockout round.
func record_match(playoffs: bool) -> void:
	if playoffs:
		matches_playoffs += 1
	else:
		matches_regular += 1


## Saves from before the ledger existed load with it empty; nothing to rebuild yet.
func ensure(_season: Season) -> void:
	pass

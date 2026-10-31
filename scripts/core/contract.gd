class_name Contract
extends RefCounted
## A soldier's deal. Money is in $K. `years` counts the seasons left on it, including the current
## season (or, in the offseason, the upcoming one). Contracts tick down when a season ends, and a
## contract at 0 years is expiring: re-sign him before free agency or he walks.

var salary: int = 0
var years: int = 1
var signed_year: int = 0
var rookie := false
## Signing bonus paid when he signed ($K; paid from the club fund, off the cap).
var bonus: int = 0
## No-trade clause: he can't be traded for the life of the deal (unless he asks out).
var no_trade := false


static func make(salary_k: int, years_left: int, year: int, is_rookie := false) -> Contract:
	var c := Contract.new()
	c.salary = salary_k
	c.years = years_left
	c.signed_year = year
	c.rookie = is_rookie
	return c


func is_expiring() -> bool:
	return years <= 0


func remaining_value() -> int:
	return salary * maxi(years, 0)

class_name FacePrior
extends RefCounted
## Name -> face-group likelihoods, so a soldier's face fits his name the way it would in real life.
## Groups match tools/portraits/groups.py: "dark", "brown" (medium brown / olive: Latino, Middle Eastern, South
## Asian, Pacific), "asian" (East Asian) and "light" (light and tan, mostly European). Each entry multiplies the
## base weight of the listed groups; an unlisted group (or a name that is not listed at all) multiplies by 1,
## so ambiguous names like "Tyler" or "Max" simply fall back to the base mix. First and last name multiply
## together, so mixed pairings stay possible but rare (a Japanese surname with a Latino first name reads as mixed).

const GROUPS := ["light", "dark", "brown", "asian"]
## Roster-wide mix before any name evidence.
const BASE := {"light": 52.0, "dark": 26.0, "brown": 14.0, "asian": 8.0}

## [light, dark, brown, asian] multipliers.
const FIRST := {
	"Marcus": [1.5, 2.0, 0.8, 0.2], "Diego": [0.5, 0.3, 6.0, 0.05], "Tariq": [0.1, 3.0, 4.0, 0.05],
	"Jonah": [3.0, 1.0, 0.5, 0.1], "Wes": [4.0, 0.5, 0.3, 0.1], "Kai": [1.5, 0.5, 1.5, 2.0],
	"Nico": [2.0, 0.3, 2.0, 0.1], "Owen": [5.0, 0.3, 0.2, 0.05], "Rafael": [1.5, 0.5, 4.0, 0.05],
	"Ivan": [5.0, 0.1, 0.3, 0.1], "Luca": [6.0, 0.05, 1.0, 0.05], "Mateo": [1.5, 0.3, 5.0, 0.05],
	"Theo": [3.0, 1.5, 1.0, 0.3], "Andre": [1.0, 4.0, 1.0, 0.1], "Malik": [0.1, 5.0, 3.0, 0.05],
	"Hugo": [3.0, 0.1, 3.0, 0.1], "Felix": [4.0, 0.5, 1.0, 0.2], "Jasper": [5.0, 0.5, 0.2, 0.1],
	"Dante": [2.0, 2.0, 2.0, 0.05], "Ezra": [3.0, 1.0, 2.0, 0.1], "Silas": [4.0, 1.5, 0.3, 0.1],
	"Cole": [4.0, 1.0, 0.3, 0.1], "Rhys": [6.0, 0.2, 0.1, 0.05], "Bruno": [3.0, 1.0, 3.0, 0.05],
	"Kenji": [0.05, 0.02, 0.1, 8.0], "Omar": [0.3, 2.0, 6.0, 0.1], "Viktor": [6.0, 0.1, 0.3, 0.1],
	"Elias": [3.0, 0.5, 3.0, 0.1], "Sami": [1.0, 1.0, 4.0, 1.0], "Tomas": [4.0, 0.1, 3.0, 0.1],
	"Reed": [5.0, 0.5, 0.2, 0.1], "Jalen": [0.5, 6.0, 1.0, 0.05], "Arlo": [4.0, 0.5, 0.5, 0.2],
	"Cyrus": [2.0, 1.0, 4.0, 0.2], "Damon": [2.0, 3.0, 1.0, 0.1], "Emil": [5.0, 0.2, 0.5, 0.1],
	"Gage": [5.0, 1.0, 0.3, 0.1], "Hank": [6.0, 0.3, 0.2, 0.1], "Idris": [0.5, 3.0, 5.0, 0.05],
	"Jordan": [2.0, 2.5, 1.0, 0.3], "Caleb": [3.0, 2.0, 0.5, 0.1], "Isaiah": [1.5, 4.0, 1.0, 0.1],
	"Darius": [0.5, 4.0, 3.0, 0.1], "Trent": [5.0, 1.5, 0.2, 0.1], "Brody": [6.0, 0.3, 0.1, 0.05],
	"Colton": [5.0, 1.0, 0.2, 0.05], "Devin": [2.0, 2.0, 1.0, 0.2], "Garrett": [4.0, 1.5, 0.3, 0.1],
	"Jamal": [0.1, 7.0, 1.0, 0.02], "Keegan": [6.0, 0.3, 0.1, 0.05], "Landon": [4.0, 2.0, 0.3, 0.1],
	"Miles": [3.0, 2.0, 0.5, 0.2], "Nolan": [5.0, 1.0, 0.2, 0.1], "Pierce": [6.0, 0.5, 0.1, 0.05],
	"Quentin": [3.0, 3.0, 0.3, 0.1], "Rashad": [0.1, 6.0, 2.0, 0.02], "Shane": [6.0, 0.5, 0.2, 0.05],
	"Troy": [3.0, 3.0, 0.5, 0.1], "Victor": [2.5, 1.0, 2.0, 0.2], "Wyatt": [6.0, 0.3, 0.2, 0.05],
	"Xavier": [2.0, 2.5, 3.0, 0.1], "Zeke": [3.0, 2.0, 1.0, 0.1], "Aaron": [3.0, 2.0, 1.0, 0.3],
	"Beau": [5.0, 0.5, 0.2, 0.05], "Cody": [5.0, 1.0, 0.3, 0.1], "Derek": [3.0, 2.0, 0.5, 0.5],
	"Evan": [3.0, 1.5, 0.5, 1.0], "Finn": [7.0, 0.1, 0.1, 0.05], "Grady": [6.0, 0.5, 0.1, 0.05],
	"Hector": [0.5, 0.5, 7.0, 0.02], "Javier": [0.5, 0.2, 7.0, 0.02], "Kendrick": [1.0, 5.0, 0.3, 0.05],
	"Logan": [4.0, 1.5, 0.3, 0.2], "Mason": [3.0, 2.0, 0.5, 0.1], "Oscar": [3.0, 1.0, 3.0, 0.1],
	"Preston": [4.0, 2.0, 0.2, 0.1], "Ray": [1.0, 1.0, 1.0, 0.5], "Santiago": [1.0, 0.2, 7.0, 0.02],
	"Travis": [4.0, 2.0, 0.3, 0.1], "Ulysses": [2.0, 2.0, 1.0, 0.1], "Vince": [5.0, 1.0, 1.0, 0.1],
	"Warren": [4.0, 2.0, 0.3, 0.1], "Yusuf": [0.2, 3.0, 5.0, 0.1], "Zach": [1.5, 1.0, 1.0, 1.0],
	"Brock": [6.0, 0.3, 0.1, 0.05], "Chase": [4.0, 1.5, 0.3, 0.1], "Dmitri": [7.0, 0.1, 0.3, 0.05],
}

const LAST := {
	"Reyes": [1.0, 0.1, 6.0, 0.1], "Novak": [6.0, 0.05, 0.2, 0.05], "Okafor": [0.1, 8.0, 0.2, 0.02],
	"Lindqvist": [8.0, 0.02, 0.05, 0.02], "Hart": [1.5, 1.0, 1.0, 1.0], "Moreau": [6.0, 0.8, 1.0, 0.1],
	"Kowalski": [8.0, 0.02, 0.05, 0.02], "Tanaka": [0.05, 0.02, 0.1, 8.0], "Silva": [3.0, 2.0, 3.0, 0.1],
	"Brennan": [6.0, 0.3, 0.1, 0.05], "Vance": [3.0, 1.0, 0.5, 0.2], "Ortiz": [0.5, 0.2, 7.0, 0.05],
	"Petrov": [7.0, 0.05, 0.3, 0.05], "Haddad": [1.0, 0.2, 7.0, 0.05], "Fischer": [7.0, 0.1, 0.1, 0.05],
	"Mbeki": [0.05, 8.0, 0.1, 0.02], "Calloway": [2.0, 3.0, 0.3, 0.1], "Ruiz": [0.5, 0.1, 7.0, 0.05],
	"Sato": [0.05, 0.02, 0.1, 8.0], "Grant": [2.0, 3.0, 0.3, 0.2], "Ivers": [5.0, 0.3, 0.1, 0.05],
	"Duarte": [2.0, 0.5, 5.0, 0.05], "Kerr": [5.0, 0.3, 0.1, 0.1], "Lowe": [3.0, 1.5, 0.3, 0.3],
	"Mercer": [3.0, 1.5, 0.3, 0.2], "Nash": [3.0, 2.0, 0.3, 0.1], "Pike": [4.0, 0.5, 0.2, 0.1],
	"Quinn": [5.0, 0.5, 0.1, 0.1], "Rourke": [6.0, 0.2, 0.1, 0.05], "Thorne": [4.0, 0.5, 0.1, 0.1],
	"Ueda": [0.05, 0.02, 0.1, 8.0], "Voss": [6.0, 0.2, 0.1, 0.05], "Wilder": [4.0, 0.5, 0.2, 0.1],
	"Yates": [4.0, 1.0, 0.2, 0.1], "Zane": [3.0, 1.0, 1.0, 0.2], "Bishop": [3.0, 2.0, 0.3, 0.2],
	"Cruz": [1.0, 0.2, 6.0, 0.2], "Adams": [3.0, 3.0, 0.3, 0.2], "Barrett": [4.0, 1.5, 0.2, 0.1],
	"Carver": [3.0, 2.0, 0.2, 0.1], "Dalton": [5.0, 0.8, 0.1, 0.1], "Ellison": [3.0, 2.0, 0.2, 0.1],
	"Foster": [3.0, 2.5, 0.2, 0.1], "Garza": [0.5, 0.1, 7.0, 0.05], "Holloway": [3.0, 2.5, 0.2, 0.1],
	"Ingram": [3.0, 3.0, 0.2, 0.1], "Jennings": [3.0, 2.5, 0.2, 0.1], "Keller": [6.0, 0.3, 0.1, 0.1],
	"Lawson": [3.0, 2.5, 0.2, 0.1], "Maddox": [4.0, 1.0, 0.3, 0.1], "Navarro": [1.0, 0.1, 6.0, 0.1],
	"O'Neal": [3.0, 3.0, 0.2, 0.1], "Palmer": [3.0, 2.0, 0.2, 0.2], "Ramsey": [4.0, 1.5, 0.2, 0.1],
	"Sutton": [5.0, 0.8, 0.1, 0.1], "Tate": [3.0, 2.0, 0.2, 0.1], "Underwood": [4.0, 1.5, 0.2, 0.1],
	"Vaughn": [4.0, 1.5, 0.2, 0.1], "Whitaker": [5.0, 1.0, 0.1, 0.1], "York": [5.0, 1.0, 0.2, 0.2],
	"Abbott": [5.0, 1.0, 0.2, 0.1], "Brooks": [3.0, 3.0, 0.2, 0.1], "Cannon": [3.0, 2.0, 0.2, 0.1],
	"Delgado": [0.5, 0.1, 7.0, 0.05], "Easton": [5.0, 0.8, 0.1, 0.1], "Fletcher": [5.0, 0.8, 0.1, 0.1],
	"Gibbs": [3.0, 2.5, 0.2, 0.1], "Hayes": [3.0, 2.5, 0.2, 0.1], "Irwin": [6.0, 0.3, 0.1, 0.1],
	"Jacobs": [3.5, 2.0, 0.5, 0.1], "Kimura": [0.05, 0.02, 0.1, 8.0], "Lockhart": [6.0, 0.3, 0.1, 0.05],
	"Mendez": [0.5, 0.1, 7.0, 0.05], "Nolan": [6.0, 0.4, 0.1, 0.1], "Oduya": [0.05, 8.0, 0.2, 0.02],
	"Park": [1.0, 0.1, 0.1, 7.0], "Rhodes": [3.0, 2.5, 0.2, 0.1], "Salazar": [0.5, 0.1, 7.0, 0.05],
	"Townsend": [4.0, 1.5, 0.2, 0.1], "Valdez": [0.5, 0.1, 7.0, 0.05], "Webb": [4.0, 1.5, 0.2, 0.1],
	"Boone": [4.0, 1.5, 0.2, 0.1], "Crawford": [3.0, 2.0, 0.2, 0.1], "Drake": [3.0, 2.0, 0.3, 0.1],
	"Fuentes": [0.5, 0.1, 7.0, 0.05], "Hale": [5.0, 0.8, 0.1, 0.1], "Knox": [4.0, 1.0, 0.2, 0.1],
}


## Weight of each group for a first/last name pair (normalised to sum 1), in GROUPS order.
static func weights(first: String, last: String) -> Array:
	var f: Array = FIRST.get(first, [1.0, 1.0, 1.0, 1.0])
	var l: Array = LAST.get(last, [1.0, 1.0, 1.0, 1.0])
	var out := []
	var total := 0.0
	for i in GROUPS.size():
		var w: float = BASE[GROUPS[i]] * f[i] * l[i]
		out.append(w)
		total += w
	for i in out.size():
		out[i] /= total
	return out


## Draw a group for this name using the caller's RNG.
static func pick_group(rng: RandomNumberGenerator, first: String, last: String) -> String:
	var w := weights(first, last)
	var roll := rng.randf()
	for i in w.size():
		roll -= w[i]
		if roll <= 0.0:
			return GROUPS[i]
	return GROUPS[0]

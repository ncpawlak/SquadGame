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


## Multiplier profiles for the wider name pool, same [light, dark, brown, asian] order. The sets below say which
## profile each extra name gets, so a name only needs a line in a set, not four numbers.
const PROFILES := {
	"light": [6.0, 0.3, 0.2, 0.1],
	"lean_light": [3.0, 1.5, 0.5, 0.3],
	"black": [0.4, 6.0, 0.8, 0.05],
	"lean_black": [2.0, 3.5, 0.3, 0.1],
	"latino": [0.5, 0.2, 7.0, 0.05],
	"caribbean": [0.4, 1.5, 5.0, 0.05],
	"asian": [0.1, 0.03, 0.1, 7.0],
	"pacific": [0.3, 0.4, 7.0, 0.5],
	"african": [0.05, 8.0, 0.2, 0.02],
	"mideast": [0.3, 1.5, 5.0, 0.3],
}

## Extra first names, in the style of NFL, MLB and NBA rosters (the original 90 live in PlayerGenerator).
const FIRST_SETS := {
	"light": [
		"Brady", "Tanner", "Hunter", "Connor", "Kyle", "Luke", "Drew", "Bryce", "Carson", "Chad", "Clay", "Dawson",
		"Holden", "Jared", "Kurt", "Lance", "Levi", "Mitch", "Parker", "Rex", "Rocco", "Ryder", "Sawyer", "Sean",
		"Spencer", "Tristan", "Tucker", "Walker", "Anders", "Lars", "Mikael", "Nikola", "Luka", "Goran", "Dario",
		"Bogdan", "Tomasz", "Marko", "Stefan", "Kristaps", "Jonas", "Lukas", "Joakim", "Axel", "Soren", "Dominik",
		"Matthias", "Henrik", "Gustav", "Mikhail", "Pavel", "Anton", "Konrad", "Declan", "Seamus", "Colin", "Liam",
		"Brendan", "Dylan", "Griffin", "Heath", "Jett", "Tripp", "Wade", "Cash", "Dax", "Cade", "Colby", "Jace",
	],
	"lean_light": [
		"Michael", "David", "Chris", "Matthew", "Joshua", "Daniel", "Ryan", "Brandon", "Justin", "Nick", "Josh", "Jake",
		"Jesse", "Austin", "Patrick", "Peyton", "Jackson", "Dennis", "Gordon", "Ben", "Sam", "Eric", "Kevin", "Brian",
		"Scott", "Mark", "Paul", "Adam", "Alan", "Ian", "Jason", "Jeremy", "Kent", "Dean", "Craig", "Shawn", "Todd",
		"Tim", "Greg", "Steve", "Dustin", "Corey", "Casey", "Blake", "Cameron", "Taylor",
	],
	"black": [
		"DeAndre", "Terrell", "Tyrone", "Jamarcus", "Dwayne", "Darnell", "Marquis", "Demetrius", "Reggie", "Calvin",
		"Cedric", "Deshawn", "Javon", "Jerome", "Kareem", "Lamont", "Maurice", "Antoine", "Tyreek", "Devonte", "Amari",
		"Jaylen", "Jabari", "Tyrese", "Terrance", "Montrell", "Trevon", "Donovan", "Rodney", "Marquise", "Deion",
		"Khalil", "Elijah", "Josiah", "Micah", "Jerry", "Larry", "Deshaun", "Dezmon", "Tavon", "Raheem", "Nasir",
		"Keenan", "Cornell", "Tremaine", "Vernon", "Leroy", "Roosevelt", "Booker", "Zion", "Marlon", "Kelvin", "Cortez",
		"Bernard", "Dominique", "Julian",
	],
	"latino": [
		"Fernando", "Jose", "Luis", "Carlos", "Juan", "Ricardo", "Sergio", "Adrian", "Alejandro", "Angel", "Eduardo",
		"Enrique", "Francisco", "Gabriel", "Gerardo", "Guillermo", "Jesus", "Joaquin", "Lorenzo", "Marcelo", "Miguel",
		"Roberto", "Salvador", "Cristian", "Emmanuel", "Armando", "Alonso", "Esteban", "Leonel", "Humberto", "Mauricio",
		"Ignacio", "Rodrigo", "Gustavo", "Federico", "Raul", "Pablo",
	],
	"caribbean": [
		"Julio", "Wilson", "Ronald", "Manny", "Pedro", "Ramon", "Nelson", "Orlando", "Yoan", "Elvis", "Rigoberto",
	],
	"asian": [
		"Hiroshi", "Takeshi", "Yuki", "Kenta", "Haruto", "Ryo", "Koji", "Satoshi", "Akira", "Daisuke", "Hyun", "Jae",
		"Minho", "Seung", "Wei", "Jian", "Hao", "Jun", "Taro", "Yuta", "Masato", "Shin", "Tae", "Sung", "Dae", "Jisoo",
		"Kazuki", "Shoma", "Naoki", "Hideo",
	],
	"pacific": [
		"Sione", "Manu", "Tevita", "Malakai", "Siaki", "Kalani", "Keanu", "Koa", "Ioane", "Taulia", "Lotu", "Penei",
		"Mata", "Tavita", "Folau", "Viliami", "Isaia", "Kaimana", "Makoa",
	],
	"african": [
		"Emeka", "Chidi", "Kwame", "Kofi", "Obi", "Tunde", "Femi", "Chima", "Sekou", "Mamadou", "Amadou", "Ousmane",
		"Thabo", "Sizwe", "Babatunde", "Ikenna", "Nnamdi", "Olu", "Yaw", "Kojo", "Jelani", "Bakari", "Tendai", "Lwazi",
	],
	"mideast": [
		"Karim", "Hakeem", "Khalid", "Hassan", "Ahmad", "Amir", "Rami", "Samir", "Ravi", "Arjun", "Dev", "Rohan",
		"Sanjay", "Vikram", "Anil", "Raj", "Nikhil", "Faisal", "Zaid", "Bilal", "Ismail", "Tarek", "Nadir", "Jamil",
		"Rashid",
	],
}

## Extra surnames, same idea.
const LAST_SETS := {
	"light": [
		"Baker", "Bennett", "Campbell", "Carlson", "Chapman", "Cooper", "Cox", "Dawson", "Doyle", "Dunn", "Fisher",
		"Fitzgerald", "Gallagher", "Gardner", "Graham", "Hansen", "Hoffman", "Hughes", "Hunt", "Jensen", "Johansson",
		"Kelly", "Kennedy", "Kessler", "Klein", "Larsen", "Lambert", "Lundgren", "MacLeod", "McBride", "McCarthy",
		"McDonald", "Miller", "Morgan", "Murphy", "Nielsen", "Olsen", "Paulson", "Peterson", "Pratt", "Reilly",
		"Reynolds", "Richter", "Schmidt", "Schneider", "Schultz", "Sullivan", "Sweeney", "Vogel", "Wagner", "Walsh",
		"Weber", "Weaver", "Wolfe", "Zimmerman", "Dvorak", "Horvat", "Ivanov", "Jovanovic", "Kovac", "Markovic",
		"Nowak", "Popescu", "Sokolov", "Volkov", "Stojanovic", "Yoder", "Bauer", "Hendricks", "Larkin", "Gunderson",
		"Halvorsen", "Eriksen", "Becker", "Koch", "Lang", "Brandt",
	],
	"lean_light": [
		"Anderson", "Clark", "Dixon", "Ellis", "Gordon", "Griffin", "Harper", "Hudson", "King", "Lewis", "Marshall",
		"Matthews", "Mitchell", "Owens", "Perry", "Rogers", "Shaw", "Turner", "Tucker", "Wright", "Evans", "Gray",
		"Hunter", "Cole", "Warren", "Burke", "Reid", "Grayson", "Mills", "Lloyd", "Holmes", "Dunbar", "Mathis",
		"Fields", "Stanton", "Parsons",
	],
	"lean_black": [
		"Washington", "Johnson", "Williams", "Jones", "Davis", "Robinson", "Harris", "Freeman", "Mosley", "Bryant",
		"Banks", "Sanders", "Simmons", "Stewart", "Thomas", "Thompson", "Walker", "Watkins", "Wallace", "Wiggins",
		"Dorsey", "Gaines", "Hawkins", "Henderson", "Hopkins", "Mack", "McCoy", "Mobley", "Pope", "Rivers", "Robertson",
		"Sims", "Sterling", "Toney", "Tillman", "Wade", "Waters", "Wilkins", "Winfield", "Alexander", "Bell", "Bridges",
		"Burks", "Burton", "Butler", "Carter", "Chambers", "Coleman", "Cooks", "Dennis", "Edwards", "Franklin", "Glover",
		"Green", "Hardy", "Hill", "Howard", "McKinney", "Moore", "Moss", "Parker", "Payton", "Rice", "Richardson",
		"Ross", "Scott", "Smith", "Taylor", "Terry", "Thornton", "Walton", "Ward", "White", "Wilson", "Woods", "Young",
	],
	"latino": [
		"Garcia", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Perez", "Sanchez", "Ramirez", "Torres",
		"Flores", "Rivera", "Gomez", "Diaz", "Morales", "Gutierrez", "Ortega", "Castillo", "Vargas", "Romero",
		"Herrera", "Medina", "Aguilar", "Vega", "Castro", "Soto", "Jimenez", "Moreno", "Alvarez", "Mejia", "Pena",
		"Rojas", "Contreras", "Acosta", "Cardenas", "Padilla", "Espinoza", "Quintero", "Bravo", "Lara", "Rosales",
		"Ibarra", "Zamora", "Cisneros", "Montoya", "Escobar",
	],
	"caribbean": [
		"Marte", "Tejada", "Polanco", "Baez", "Cabrera", "Santana", "Guerrero", "Ramos", "Nunez", "Batista",
		"Encarnacion", "Mercedes", "Peralta", "Taveras", "Paredes", "Brito",
	],
	"asian": [
		"Nakamura", "Watanabe", "Yamamoto", "Suzuki", "Ito", "Kobayashi", "Takahashi", "Matsui", "Kim", "Choi", "Kang",
		"Yoon", "Chen", "Wang", "Liu", "Zhang", "Huang", "Lin", "Wu", "Nguyen", "Tran", "Pham", "Nakagawa", "Hayashi",
		"Shimizu", "Fujita", "Sakamoto", "Ishikawa", "Maeda", "Han", "Jung", "Song", "Yang", "Zhou", "Xu", "Tang",
		"Cho", "Ahn", "Moon",
	],
	"pacific": [
		"Fifita", "Tupou", "Leota", "Soliai", "Mataele", "Faleolo", "Aiono", "Vaea", "Tuimavave", "Kaufusi",
	],
	"african": [
		"Okonkwo", "Adeyemi", "Mensah", "Diallo", "Nwosu", "Abara", "Osei", "Boateng", "Okoye", "Adebayo", "Eze",
		"Balogun", "Ndiaye", "Traore", "Keita", "Mabaso", "Owusu", "Appiah", "Kamara", "Sesay", "Bangura", "Ogunleye",
		"Chukwu",
	],
	"mideast": [
		"Khan", "Patel", "Singh", "Sharma", "Ali", "Hassan", "Nasser", "Khoury", "Aziz", "Rahman", "Hussein", "Mansour",
		"Said", "Najjar", "Farah", "Bakr", "Shah", "Gupta", "Reddy", "Kapoor", "Desai", "Haidari", "Qureshi", "Sabbagh",
	],
}

static var _first_extra: Array = []
static var _last_extra: Array = []
static var _first_profile := {}
static var _last_profile := {}


static func _index(sets: Dictionary, names: Array, profile: Dictionary) -> void:
	for key in sets:
		for n in sets[key]:
			names.append(n)
			profile[n] = PROFILES[key]


static func _ensure() -> void:
	if _first_extra.is_empty():
		_index(FIRST_SETS, _first_extra, _first_profile)
		_index(LAST_SETS, _last_extra, _last_profile)


## The extra names, for PlayerGenerator's pool.
static func extra_first() -> Array:
	_ensure()
	return _first_extra


static func extra_last() -> Array:
	_ensure()
	return _last_extra


## Weight of each group for a first/last name pair (normalised to sum 1), in GROUPS order.
static func weights(first: String, last: String) -> Array:
	_ensure()
	var f: Array = FIRST.get(first, _first_profile.get(first, [1.0, 1.0, 1.0, 1.0]))
	var l: Array = LAST.get(last, _last_profile.get(last, [1.0, 1.0, 1.0, 1.0]))
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

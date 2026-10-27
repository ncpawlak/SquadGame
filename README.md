# SquadGame

A squad-based 5v5 shooter that runs like a pro sports franchise: teams, rosters, soldier stats and
progression. Built in **Godot 4.7** (GDScript). It's currently a headless-friendly sim with a debug UI. Visual combat comes later.

## Running

1. Install Godot 4.7+ (`winget install GodotEngine.GodotEngine`).
2. Open `project.godot` in the Godot editor and press **F5**.

You can also run it from the command line: `godot --path .`

### In the browser

One-time setup: install the Godot 4.7.2 export templates (Editor → Manage Export Templates → Download). Then:

```powershell
godot --headless --path . --export-release "Web" build/web/index.html
python tools/serve_web.py          # http://127.0.0.1:8060/
```

The Web preset is the no-threads build, so it runs on any static host without special server headers.

## Franchise mode (main screen)

Title → New Franchise → pick one of 20 teams → franchise hub (Madden/CFB-style). Title → Load Franchise opens the save slots.

- **The league** (`scripts/core/league_data.gd`, `data/league.json`): 20 fixed franchises in 4 divisions of 5 -
  East (NYE, DET, BOS, IND, BKN), South (CHA, ATL, MIA, NSH, ORL), Central (ARL, CHI, STL, LOU, LRK) and West
  (LAS, SEA, SDV, REN, DEN) - each with its city, colours, home state, backstory and a **hand-authored 12-man
  roster** (names, ratings, ages, potential, DNA, home states and contracts are fixed; the same in every new
  franchise). Team OVRs start from 85 (New York Empire) down to 65 (Little Rock Riverhawks), league average ~75: most players sit between 60 and 85 and only a handful are 90+. Each team carries 2-4 A/B potential players (better teams more); most are C or lower. Every team has the same
  cap, so payrolls (and cap space) differ. `tools/build_league.gd` regenerates `league.json` from the table in
  `league_data.gd` with one fixed seed (only needed if the table changes).
- **Team logos** (`assets/logos/<ABBR>.png`, 256x256 transparent PNGs): shown on team-select tiles (inside an
  OVR ring), the hub header, home matchup, standings, playoff bracket, scores, news, draft and roster screens via
  `UiKit.team_logo` / `UiKit.logo_bb`; a team without a logo falls back to its coloured abbreviation chip.
  **Rating shape**: every player has a role-driven profile - one signature group above the rest, his role's core
  groups at his level and one or two clear holes - so nobody is 90+ in every group and 99s are rare. Players
  21 and under start around 60-66 (a couple of story prodigies excepted); ratings climb
  toward a 26-30 prime, which is where most of the league's best players sit.
- **Look**: sports-broadcast style themed in your team's colours (`UiKit.set_team`) - Barlow / Barlow Condensed
  fonts (`assets/fonts/`, OFL), slanted accent buttons and tabs, a team-colour header banner with a score-bug
  (year + phase), a gradient backdrop with your logo watermarked, and short fade/slide transitions between pages.
  The title screen uses the default gold. Matchup, recap and player-card headers use the teams' colour banners.
- **Header**: team banner only (the Play button moved to Home). **Sim To** (next to Play in the week card) sims ahead to the next week, the trade deadline, the end of
  the regular season or the end of the season, stopping early if your roster needs fixing. A progress overlay
  shows each week as it sims.
- **Home layout**: **This Week** to-dos on the left (Roster Cuts / Spots Open, Trade Offers, Re-sign whenever the
  re-sign window is open, Draft Room, Free Agency, Training Camp, Weekly Training, Upgrade Players (only when someone
  can level up), Scout (in season), Adjust Lineup); the current week on the right. **<** / **>** arrows on the
  "WEEK n of 12" bar browse back and forward through the season and playoffs: past weeks show the final score, each
  game and the MVP with a Box Score button; future weeks show the matchup preview (two-tone team banner, logos, team OVRs
  and stat-comparison bars). **SIM TO ▾** and **PLAY WEEK X** sit in the week card's top bar next to Match Preview.
  Urgent to-dos come first in orange with a "!"; finished ones are greyed out with a check.
- **Home news box**: a fixed-height scrolling feed under everything, filtered by All / Around the League (results,
  Player of the Week, wire stories, trades, signings, injuries, player stories, retirements) / Prospect News /
  Upcoming Matches (your next 3 plus this week's slate). After the trade deadline, < > arrows flip it to the
  **Playoff Picture**: a logo bracket (projected seeds in-season, live series in the playoffs) with a champion slot.
- **Team tab**: one big pane (tall enough for the full roster or lineup + bench without inner scrolling) whose < > arrows flip between the full **Roster** and **Lineup** screens
  (sorting, swaps and scheme changes refresh in place). Under it, live cards for Player Progression (can level up),
  Training (avg fatigue), Injuries (out), Team Stats (K/D + league rank) and Schedule (record, last / next) with pulsing
  alert chips (LEVEL UP / TRAIN / STARTER OUT), then a dimmed Coming Soon strip.
- **Team select**: tiles rest in a muted team tint with a team-colour bottom stripe and light up in full colour on
  hover; each logo sits on a dark disc inside a thin OVR ring, with an expectation tag (Title Favorite / Contender /
  Playoff Team / Bubble / Rebuild). Divisions are vertical badges. A big pane on top shows the hovered/focused team - logo in its colours, division, OVR and
  preseason rank, cap space, average age, expectation, backstory (a fixed 5-line box), starters' average group
  ratings and its top 3 players in the team's uniform - over 4 division rows of 5 team tiles (name and a big OVR).
  Click to start.
- **Season loop** (`scripts/season/`): 12 weeks. Each team plays its 4 division rivals home and away (8), one team
  from each other division (3) and has one **bye**. The **playoffs** take 8 teams: the 4 division winners are seeds
  1-4 (by record), then the 4 best other records are wild cards 5-8. Bracket 1v8, 4v5, 2v7, 3v6 (no reseeding),
  higher seed hosts: Quarterfinals → Semifinals → Final.
  Then the end-of-season review (awards and potential changes), the offseason (re-sign → draft → free agency → training camp),
  and aging → next season (rosters, ratings and contracts carry over).
- **Standings** (League → Standings): Divisions / Whole league toggle with W-L, division record and a SEED column
  (DIV / WC) for the current playoff picture. League → Playoffs shows the projected logo bracket in-season and the live
  bracket in the playoffs. Ties: match W/L, then head-to-head, then game differential (games won − lost across the best-of-3
  matches), then TDM point differential.
- **Match day**: Play Week opens a matchup screen (both starting fives, OVRs; click a soldier for his player card) with **Watch** and **Sim**.
  Sim plays it instantly. Watch opens the live viewer (`scripts/ui/franchise/match_viewer.gd`): a top-down
  tactical map with walls (block movement and sight), crates (low cover) and the hill; soldiers are circles in team
  colours with their callsign, moving and fighting in real time. Shots draw a tracer + muzzle flash and a pop-up
  (MISS / HIT / HEADSHOT / KILL / RELOAD). Scoreboard on top (TDM points, KOTH hold clocks with the hill tinted by
  the holder, sudden-death rounds), team panels with HP bars and live K/D/A, saves, hits/shots and hill time,
  and a kill feed under the map. Controls: Pause (Space), 2x / 3x / 5x real-time speed (keys 1-3) and Sim to End.
  An intermission card shows each game's winner and the series score. A watched match plays out exactly like a
  simmed one with the same seed.
- **Each week**: all teams train at each soldier's intensity, every match is played, XP is awarded, then fatigue
  and injuries update. AI teams train every week on Auto (rest the exhausted, ease veterans, push fresh young players) and auto-spend skill points. Home → **Weekly Training** opens the
  intensity screen; **Confirm & Train** runs this week's training right away and shows the results (XP gained, the
  new XP bar, level-ups and SP). Once per week; if you skip it, your team trains at its set intensities when the
  week is played. Spend SP on the player page (or **Auto-progress all** on the Progression page). The Home "Upgrade Players"
  to-do appears only when soldiers can afford an upgrade right now ("x players can level up"). Injured starters are
  auto-replaced by the best healthy bench soldier.
- **Scouting** (`scripts/season/draft.gd`, `prospect.gd`): each season has a class of 110 recruits (age 19–22)
  from every state. You only see name, age, listed position and home state. You get 20 scout points a week (unspent points carry over); scouting opens in Week 1, not during training camp.
  Each point spent on a prospect scouts **2 stat groups**, each shown as a range of named grades, e.g. Accuracy
  "Steady Aim - Marksman". The first look at a group shows 3 grades, a second narrows it to 2 (every group gets a
  first look before any gets a second). After 6 points every group is down to 2 grades; from then on each point
  pins **1 group** to its exact grade. Max 10 points per prospect; numbers and potential are never shown.
  Grades (worst → best) per group:
  - Accuracy: Spray & Pray, Inconsistent, Steady Aim, Marksman, Sharpshooter
  - Handling: Butterfingers, Clunky, Capable, Smooth Operator, Gunslinger
  - Physicality: Out of Shape, Average Build, Athletic, Explosive, Freak Athlete
  - Mentality: Lost, Rattled, Level-Headed, Leader, Field General
  - Objective: Point Shy, Wanderer, Contester, Point Man, King of the Hill
  - Injury: Glass, Fragile, Durable, Sturdy, Iron Man

  Grade thresholds: below 58, 58-67, 68-76, 77-85, 86+.
  **Area scouts** give every prospect a free, coarse **SCOUT** grade (A, B+, B, C+, C, D, F; noisy, from his
  true quality, shown with a "?" like "B+?" - hover it for the explanation). Scouting him to all 10 points drops the "?"
  and reveals his **true grade** (his real class percentile, no noise) - a cheap first sort of the big class. Once a season you can send a **region scout** trip (East, South,
  Central, West): every available prospect from that region gets 4 free points. **Auto-scout** spends your points
  for you: "Up to 3" gives everyone a first look, "Up to 6" deepens those already at 3 - favorites first, then
  the big board. Star a prospect (row star or the ☆ Favorite button on his card) to make him a **favorite**; Scouting
  filters by region and favorites, and the Draft Room and Mock Draft have a ★ Favorites filter too.
  Most classes hide one unlabelled **phenom** (sometimes none or two). A phenom lists one position but grades
  well in every group, so he can play anywhere. AI teams don't know who they are, and the league consensus
  underrates them.
  Every class also has **standouts**: 3-6 unlabelled **blue chips** (day-one contributors at 68-72 OVR, B/A potential),
  sometimes (about 1 class in 5) a **generational** talent (74-77 OVR, A potential), and 8-12 **specialists** (one
  stat in the 84-95 range). Scouting is how you find them.
- **Prospect news**: 0-2 stories a week during the season (Scouting page, League News → Prospect Watch, Home news box):
  stock rising, stock falling, and stat notes ("claimed #1 in the country for long range target practice").
  Stories nudge the consensus board, and none says outright who is a blue chip. **Facts** are always true:
  class rankings ("finished the ruck march first") go only to the real class leader (or last place) in that
  stat, and measured reports only to standout (82+) or poor (52-) ratings. **Rumors** ("Word is...", "reportedly",
  stock rising/falling) are true about half the time, so scout before you believe them.
  Every prospect shows a **projected pick** (Early/Mid/Late 1st or 2nd, or Undrafted) from a noisy league-consensus
  board. The **Mock Draft** page (Personnel → Draft, or the Scouting page) predicts every pick from the current
  standings. The Scouting list and Draft Room are a table: portrait, name/age/position, projection, then one column per
  stat group (a 5-segment bar lit where his grade could be, best grade on top). Click any header to sort (groups sort by
  the middle of the scouted range; unscouted sinks). Each grade is colored: red Poor, orange Below average, gray Average, blue Good, green Elite.
- **Draft**: after the Final, 3 rounds (60 picks), same order every round (like football). Teams that missed the playoffs pick first (worst record first),
  then quarterfinal losers, semifinal losers, the runner-up, and the champion last. AI teams pick from the consensus board with a little noise, leaning toward their weakest position.
  The Draft Room runs a **clock**: you have 2:00 on your pick (then the best available is auto-picked) and CPU teams
  pick after 5 seconds. The clock only runs while the Draft Room is open. **Sim to next pick** skips one CPU pick;
  you can also sim to your pick, draft a prospect or auto-pick. Draftees get rookie contracts (cheaper
  later in the draft; 3 years in round 1, 2 years in rounds 2-3). The best 12 undrafted prospects join free agency; the rest leave.
  When the draft ends the Draft Room becomes the **Draft Recap**: every pick with all ratings and potential revealed,
  a note for blue chips, specialists, steals and reaches, and click-through to each player's profile. Past recaps
  stay under Personnel → Draft.
- **Contracts & payroll** (`scripts/core/contract.gd`, `scripts/season/contracts.gd`): every soldier has a salary
  and years left. Hard cap of $150M per team per season, the same for everyone (Madden-style); minimum salary
  $750K always fits. **Salary floor** $20M: a team whose payroll ends a season below it pays the shortfall as a
  penalty (charged to its cap, reported in News); League → Teams flags teams below the floor. Contracts tick down after the Final. Releasing a player leaves 50% of his remaining money on
  the cap as dead money, split over his remaining years. Personnel → Contracts & Payroll shows cap space, every
  contract and future commitments. Trades have to fit under the cap too.
- **Player DNA** (`scripts/core/dna.gd`, player page → DNA tab, fully visible): five motivations - Money,
  Winning, Playing Time, Loyalty, Security - plus Temperament (thick- vs thin-skinned) and Savvy (negotiating
  skill), 1-99. Rolled once per soldier (young players lean money/playing time, veterans winning/security) with one
  clear headline motivation. **Hometown** (the DNA tab shows his home state): free agents add up to 10% interest for
  their home state's club (half for a club in the same region), scaled by this motivation. **Trust** (0-100, starts 50) is his relationship with his club: kept promises and fair
  talks build it, hardball, broken promises and walk-outs cost it; it carries across seasons and resets when he
  changes teams.
- **Re-sign negotiation** (`scripts/season/negotiation.gd`, Home → Re-sign Players): each expiring player names
  his price (the hometown-discount ask moved by his money/loyalty DNA, trust, star status and richer teammates) and
  has a hidden floor (higher for savvy players). **Sign at Ask**, or **Negotiate**: every offer or argument costs
  patience; run out and he walks to free agency. Offers under 85% of his number insult him. Arguments are built
  from data - production at his role, injuries, age 30+, comparable contracts, being a contender, a tight cap,
  competition at his spot, years with the club - and land by evidence × fit with his DNA × your leverage (lower
  for your best players), with diminishing returns. Weak evidence gets rebutted by savvy players; a bad fit
  (e.g. threatening a playing-time guy with his backup) backfires and raises his price. You can also offer a
  **starter promise** (worth up to ~9% off to a player who wants to start).
- **Starter promises** (re-signs and free-agent offers): he must start 75% of next season's games (weeks out
  injured don't count). Kept → trust +12; broken → trust −25, morale −10, and players who need to start or are
  thin-skinned **request a trade**. His next negotiation opens sour. Results show under News → Player Relations.
- **Trades** (`scripts/season/trades.gd`, Personnel → Trades, or "Trade for Him" / "Shop" on any player card):
  up to 3 assets a side - players under contract past this season and this year's and next year's draft picks
  (expiring contracts can't be traded). The window is open in preseason camp, through Week 8 (the deadline), and
  in the offseason from the draft on (including during the live draft); closed for the rest of the season and the
  playoffs. Trades can push a roster past 12 (you must cut before your next match; AI teams restructure right away:
  shop their least valuable surplus to teams with room for a pick, else cut, weighing OVR, potential, age, years
  left, dead money and depth at his role). AI teams value incoming players by **need**: a would-be starter is worth
  full value, a top backup 85%, and a player buried behind better, higher-potential players at his role far less
  (young A/B prospects are discounted less); AI offers only target players who'd start or be the top backup. A trade can't drop a team below 8 in-season or 5 in the offseason, and
  teams can't go over the cap by taking on salary; contracts and picks
  just move (no salary retention). Each AI team is a **Contender**, **Balanced** or **Rebuilding** (team OVR plus
  record): contenders pay for starters who fit their weakest role, rebuilders pay for youth, picks and cheap
  contracts and sell their 30+ veterans. The **Trade Center** shows a hidden-math interest bar and the GM's
  one-liner; **Propose** (accepted, countered, or refused), **What would it take?** (the cheapest package of yours
  they'd accept), patience pips (each refusal costs one, one recovers a week). Put players on the **Trade Block**
  and AI teams send **Trade Offers** (they expire at week's end). AI teams also trade with each other. Traded players
  lose morale by their Loyalty (players who asked out are relieved), trust resets, and requests clear. Trades show
  in News and the Trade Log; traded picks move in the mock and real draft order.
- **Offseason** (advance button walks the stages): **Re-sign** (Sign at Ask or Negotiate; AI teams re-sign
  their keepers) → **Draft** → **Free agency** (3 days) → **Training camp** → next season. Rosters max out at 12 (5 starters + 7 backups).
  In the offseason your roster can be any size (trades, draft picks, extra signings), but **Week 1 needs exactly 12**:
  release down or sign up to it (an urgent "Roster Cuts" / "Roster Spots Open" to-do on Home). After Week 1
  you can play with 8-12; going over 12 by trade blocks your next match until you cut. AI teams carry up to 15 through
  the draft and free agency and cut to 12 when camp ends, by a **keep score**: current OVR, upside (potential gap x
  grade, weighted toward youth), age decline, depth at his role (starters and the top backup are safe; players buried
  behind better prospects drop), a bonus for recent draft picks (round 1 > 2 > 3, fading after two years) and contract
  (dead money, surplus value). So a young A-potential is kept over a late-20s C, and fresh picks aren't cut into free agency.
- **Training camp** (`scripts/season/camp.gd`, Home → Training Camp): one drill per rating group (Marksmanship Range,
  Weapons Lab, Combine Gauntlet, War Room, Hill Assault, Iron Conditioning). Pick a drill, pick a soldier, see his ratings boost.
  One soldier per drill and one drill per soldier. The point pool depends on potential (A 9-13, B 7-10, C 5-8, D 3-6,
  F 2-4), spread at random over the group's stats (max +4 each). Drills respect group caps: a capped group
  shows "Capped" and can't be drilled, and points stop landing once the group reaches its cap. AI teams run theirs when camp closes; advancing with
  unused drills asks you to confirm first.
  A new franchise opens in a **preseason training camp** before Week 1 (same drills; "Start 2026 Season" closes it). The home hero shows the camp, not Week 1. Drill pick tables sort by any column and hide soldiers who already attended a drill.
  Hovering a row shows the soldier in the pane above; clicking opens an "are you sure" popup with his portrait, age,
  OVR, potential and point pool.
- **Offseason XP**: every offseason step is an XP week (100 base XP, scaled by age and potential), and camp week gives 250.
- **Free agency** (`scripts/season/free_agency.gd`, League → Free Agents): unsigned soldiers with all ratings
  visible. A big **Available to spend** readout on top shows cap − current salaries (incl. dead money) − pending offers. Bidding: make offers (salary and years) during FA days or in-season. In-season (training camp included) a free agent answers your offer on the spot, weighing every current
  offer: he signs with you, picks another team, or turns you down so you can raise it. In the offseason each round every free agent scores
  his offers and signs the best one that clears his bar. The weights come from his DNA (money ~55-85% vs.
  asking, team quality and playing time the rest), plus a starter promise (a backup treats it as nearly a starting
  job), a loyalty pull toward his former club (scaled by trust) and a security bonus for his preferred length. The
  offer page shows what he weighs and has a starter-promise toggle. It lists every team's current offer with a bar for his interest in each (the tick marks his bar). Unsigned players lower their asking price over time. AI teams bid too: every team with
  cap room chases free agents who would upgrade its weakest starter or depth (so top free agents draw several offers).
  A full AI roster releases its least valuable player to make room. "Keep value" weighs OVR, age, potential and
  salary, so a late-20s C-potential depth player is cut long before a young A/B prospect.
- **Retirement** (`scripts/season/retirement.gd`): soldiers retire from age 35 (always by 39), more likely as
  they decline. Free agents unsigned for a season retire if they're weak or 33+, which keeps the pool churning.
  Home/League → Retirements lists them by year, toggling between your team and the league.
- **Other teams**: League → Teams lists every club's division, record, OVR, payroll and cap space; click one for its roster.
  League → **Team Stats** compares all 20 teams (record, games and point differential, kills, deaths, K/D, hit%,
  HS%, wipes, hill time, captures, payroll), sortable by any column.
- **League Wire** (`scripts/season/league_news.gd`, News page, Home news box): condition-based stories around the
  league, written from the real state of the league so they keep coming in future seasons with new players -
  a veteran star on a contender in his final contract year (or 35+) wants **one more ring** (and how it ended),
  hometown heroes, contract-year breakouts, rookie starters, busts, trade requests, **rivalry** results
  (division and backstory rivals), the champion, and salary-floor penalties. Each story fires once per player per
  season, capped per kind per week.
- **Save / Load** (`scripts/save/save_system.gd`, Settings → Save Franchise / Load Franchise, title → Load Franchise): 3 manual slots
  plus an **autosave** after every week, the season rollover and camp. A save is the whole league graph (shared
  objects, RNG states) as compressed text, so a loaded game continues exactly as the original would have.
- **Match-day form**: each match rolls a small team form swing (and a smaller per-soldier one), so close teams split
  results and upsets happen without changing ratings.
- **Awards** (scripts/season/season_review.gd, Home → Awards): after the Final the league hands out Season MVP,
  Best Frontman/Center/Flex, Rookie of the Year and a 5-man All-League team (2 FM, 1 C, 2 FX), ranked on impact
  per game (min 4 games). During the season the page shows the MVP race. It also lists potential changes and
  this year's aging declines.
- **Home**: a big pane for this week's match (both teams' OVR and record, starter averages per group plus morale and
  energy as head-to-head bars, and two impact players per side), with the This Week to-dos and news box described
  above.
- **Week results / box score**: the final score and each game on top, then away and home panes side by side with
  all five players' K/D/A, damage, hit%, headshots and hill time (click a player for their card) and a Play-by-Play
  button that opens the full event log. Around the League below lists every match on one line, then FA signings.
  Training Results ends with a Continue button back to Home.
- **Your team stands out**: your team and players get a gold-bordered row in standings, league leaders, league and
  team stats, mock draft, draft order, awards and rankings. The Trade Center shows the partner's full name in a
  fixed-size box.
- **Portraits** are procedurally generated per soldier (`Look` + `Portrait`): skin tone; headgear (boonie hat,
  infantry helmet, helmet with goggles, beanie, beanie with headset, forward/backward ball cap or hair); eyewear
  (clear/tinted goggles, sunglasses, night vision on helmets, or brown/black/blue eyes); face (normal, balaclava,
  face paint, eye black); and lower face (bandana, half mask, shemagh, or shaved/goatee/short/big beard). The roll
  is mostly random, lightly biased by role (Frontmen wear more armour and masks, Centers boonies and shemaghs, Flexes
  caps and headsets) and age (older players grow more beards and go gray). Headgear, masks and the uniform use the
  team's primary colour and straps, frames, brims and trim its secondary (auto-picked to contrast), so a traded
  player changes colours at once. Free agents and prospects wear neutral khaki and gray.
- **Roster** (2K style): a big preview pane on top (portrait, name and callsign, salary, contract, OVR/POT, fatigue
  and morale rings, group ratings) that follows the hovered/focused row. Below it is a table you can sort by any
  column (click a header; click again to flip). Free Agents, Progression and Contracts use the same sortable tables.
- **Player page** (Madden style) with tabs: **Overview** (action rail, morale/health/energy/XP rings, morale
  factors, OVR at each position and every attribute), **Ratings** (spend skill points), **Contract** (details,
  re-sign, release with a confirm step), **Stats** (a Season / Career toggle: Season lists every match this year - opponent, W/L score and the full line - with the season total; Career is the season-by-season lines and career total), **DNA** (motivations, personality, trust, promise status, trade request, chemistry bonds) and
  **Progression**: every rating change with when and why, newest first by season - level-ups (skill points), training
  camp drills, age decline and end-of-season potential re-grades - with +/- per stat and OVR before → after.
  League Leaders, League/Team Stats, box scores, the matchup screen and Free Agents all open it.
- **Team Stats / League Stats** (Team → Team Stats, League → League Stats): every soldier's season line (callsign and
  name, team, position, GP, K, D, A, K/D, saves, damage, headshots, HS%, hit%, wipes, hill time, captures, MVPs),
  sortable by any column; click a row for the player card.
- **Player of the Week**: the single best match performance (impact score) across the week, shown on the week
  results page, the Home news box and League News.
- **Lineup**: the current scheme drawn as a formation. Cards show face, OVR and POT. Click a slot, then a bench card
  (or another slot), to swap. "Generate Best Lineup" picks the best five. **Change Scheme** lists all six schemes with
  each one's fit for your roster; hover one to preview its formation (auto-filled with your best players), click to
  use it. The match preview shows each side's scheme and the matchup edge.
- **Contracts & Payroll**: a sortable table (salary, years left, remaining, dead money if cut, OVR, morale...).
  Click a row to open that player's Contract tab, where you can release him.
- **Free agent offers** list your players at the free agent's best position with an OVR +/- column.
- **Morale** (`scripts/sim/morale.gd`): 0-100, no effect from 75 to 84. Every 5 points below 75 lowers a random stat
  by 1-3; every 5 points from 85 up raises one. OVR shows the effect, e.g. "69 (-4)". Each week: wins/losses (+/-2),
  starting (+2) or sitting healthy (-1.5), match MVP (+3), pay (under 75% of market value -1), then a 20% drift
  back toward 75.
- **Chemistry** (`scripts/core/relationships.gd`, a DNA module): every pair of soldiers who have shared a roster has a
  bond score (0-100) kept league-wide, so it survives trades, releases and re-signings. Starting a match together +1.5,
  formation neighbours (`Scheme.ADJACENT`, e.g. Wide-Left's two left flexes) +3 more, same roster +0.3 a week; pairs
  apart lose 1 a week (offseason too). New leagues seed current teammates with history (more for veterans). Levels:
  Familiar 20, Trusted 50, Inseparable 80. When both are in the lineup each linked teammate adds +1/+2/+3 to the
  soldier's Mentality ratings (Awareness, Composure, Teamwork), max +4, shown in the (±n) with morale. The DNA tab
  lists every bond (club logo, level, progress, games together, rising/fading); the lineup page draws lines between
  bonded starters (blue Familiar, green Trusted, gold Inseparable).
- **Saves**: a soldier saves a teammate when he eliminates an attacker who has the teammate nearly dead. Tracked in
  box scores, season lines and League Leaders.
- **Callsigns** (`scripts/core/callsigns.gd`): every soldier gets a unique callsign that fits his best group
  (e.g. Ivan "Ironside" Hart). Used in tables, leaders and the lineup instead of jersey numbers.
- **Hub tabs**: Home, Team, League, Personnel, Settings. Tiles marked **SOON** are laid out but not built yet
  (staff, facilities, records).

Controls:

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | Arrows / WASD | D-pad / left stick |
| Select | Enter | A |
| Back | Esc / Backspace | B |
| Switch tab | Q / E | LB / RB |
| Advance week | Space | Y |
| Scroll | Mouse wheel, PageUp/PageDown | Right stick |

The old debug UI is still available from the title screen or Settings → Debug Sim Tools:
- Generate a league from a seed.
- Simulate a match and view the play-by-play and box score.
- Train for a week (set each soldier's intensity).
- Upgrade stat groups with skill points, swap lineup slots.
- Batch-sim 200 matches.

## Tests

```powershell
godot --headless --path . --import                              # first run: builds class cache
godot --headless --path . --script res://tests/run_tests.gd     # sim/progression tests (~20 min; TEST_ONLY=<name part> for a subset)
godot --headless --path . --script res://tests/season_tests.gd  # season loop tests (slow; ONLY=test_a,test_b runs a subset)
godot --headless --path . --script res://tests/ui_smoke.gd      # debug UI smoke test
godot --headless --path . --script res://tests/franchise_smoke.gd  # franchise menus through a full season
godot --headless --path . --script res://tests/save_tests.gd    # save/load round trips and determinism after load
```

Exit code 0 = pass. The slow part is the stat-sensitivity test, which plays 200 matches per stat.

## Model (Milestone 1)

- **Stats (0–99), in groups (MLB The Show style).** Each group's rating is the average of its stats (`scripts/core/stats.gd`):
  - Accuracy: short, medium and long-range acc
  - Handling: reload, grouping, sway
  - Physicality: speed, agility, strength, endurance
  - Mentality: awareness, composure, teamwork
  - Objective: anchor (holding a point), breach (taking a held point), objective IQ (playing the point and rotating)
  - Injury: injury, toughness (view only, can't be upgraded)
- **What each stat does in a match:**
  - Short/medium/long acc: hit chance in that range band. Grouping: headshot chance and tighter bursts.
  - Reload: time spent reloading. **Sway**: aim steadiness when moving, tired or at long range (60 is neutral).
  - Speed: movement and flank pace. Agility: evasion when shot at. **Strength**: sustained fire and absorbing
    damage (up to 25% less). Endurance: fatigue gain and recovery.
  - **Awareness**: spotting and ducking to cover, plus role knowledge - when to push, hunt and flank (smart
    soldiers read a quiet fight sooner and flank faster). Composure: accuracy under fire. Teamwork: crossfire bonus.
  - Anchor / Breach / Objective IQ: King of the Hill (below). Injury: injury chance. **Toughness**: only how long
    an injury lasts.
- **Schemes** (`scripts/core/scheme.gd`): six formations of the same three roles.
  - **Swing**: 2 Frontmen, Center, Left Flex, Right Flex. **Wide-Left / Wide-Right**: 2 Frontmen, Center, both
    Flexes on one side. **Wall**: 3 Frontmen, a Mid Flex behind, Center at the back. **Spread**: 4 Flexes (2 per
    side) around a Center. **Pack**: 2 Frontmen, a Mid Flex, 2 Centers.
  - Each role has its own OVR weights; role drives in-sim behaviour (frontmen push the middle, centers anchor back,
    flexes flank the edges; a Mid Flex picks a side each life).
  - Matchups are small rock-paper-scissors edges (about ±2-3% accuracy, capped at ±4%), plus a King of the Hill
    nudge (Wall +2%, Spread −2%). Ratings still decide most matches.
  - AI teams pick the scheme that best fits their roster (with a small per-team style lean) each week.
- **Rosters:** 12 soldiers each (5 starters + 7 bench). The franchise league has 20 teams (the debug sim generates its own small league).
- **Match:**
  - **Best of 3 games**, always in this order (a 2-0 sweep skips game 3), 0.5s ticks. Same lineup all match;
    fatigue carries across games (partial recovery between them).
    1. **Team Deathmatch**: 1 point per kill, first to 50. Eliminated soldiers stay down until their whole team is
       wiped; then that team respawns in formation and the team that wiped them gets +5.
    2. **King of the Hill**: a point in the middle. A team banks hold time while it's alone on the point (nothing
       while contested); first to 2:00 total wins. Same wipe/respawn rule, no wipe bonus.
    3. **TDM Sudden Death**: elimination rounds, no respawns, first to 4 rounds.
  - Objective stats only matter in King of the Hill: Objective IQ decides who plays the point and how fast a squad
    rotates back onto it; Breach speeds the push onto a held point and adds accuracy against soldiers on it;
    Anchor adds accuracy and damage resistance while on the point. Frontmen lean Breach, Centers Anchor, Flexes OIQ.
  - New box/season stats: team wipes, hill time, hill captures (and contest time in the box score).
    Hill time, captures and wipes have League Leaders boards. XP impact is averaged per game played.
  - **2D arena** (`scripts/sim/arena_map.gd`): a symmetric 96x60 m map with walls, crates and the hill in the
    middle. Soldiers spawn in the scheme formation, path around obstacles (waypoint graph), hold lanes, flank,
    hunt when it goes quiet, and duck to nearby cover when shot at (Awareness). Only enemies in line of sight can be
    targeted; real distance sets the range band and shots through a crate hit less often.
  - Each shot is resolved on the range band, accuracy, sway, fatigue, composure, teamwork, and the target's evasion; damage is reduced by the target's strength.
  - The engine is steppable (`start` / `step`), so Sim and the live viewer share it; `record` turns on visual events.
  - Deterministic for a given match seed (`scripts/sim/match_engine.gd`).
- **Progression:**
  - XP from matches and weekly training gives skill points (SP): every 500 XP (+150 per batch) = 3 SP.
    Levels are internal; the UI shows an XP bar toward the next SP.
  - SP buy +1 to a whole group. That spreads N points (N = stats in the group) randomly across the group, at most +2 per stat.
  - Cost rises with the group rating: 1 SP below 60, 2 below 80, 3 below 90, 4 below 95, 6 at 95+. Stats already
    94+ are 4× less likely to receive upgrade points, so 99s stay rare.
  - Only a soldier's two highest group caps may exceed 89 (`PlayerGenerator.limit_elite_caps`), so even
    superstars keep a hole or two.
  - **XP gain scales with age AND potential** (`AGE_POTENTIAL_XP`), tuned for these season OVR gains (before age
    decline): 19-22 A +5-7 / B +3-4 / C +1-2 / D-F 0-1; 23-26 A +3-4 / B +2-3 / C +1; 27-30 A +1-2 / B +1;
    31-33 small; 34+ next to none. Good seasons push a soldier toward the top of his range.
  - **Potential** is an A–F grade, rolled by age (young players skew higher); draft phenoms are A (sometimes B).
  - Each group has a hidden cap (CFB27 style). Headroom comes from age, is multiplied by the potential grade
    (A 1.7× … F 0.4×) and by a random per-group factor, so a high grade means more room overall but which
    groups get it is random.
  - **End-of-season re-grade**: MVP +1 (50% chance of +2); a position award, All-League or Rookie of the Year +1;
    performance well above/below the rating rank (impact-per-game percentile vs OVR percentile, ±0.3) ±1;
    only players 25 and under (or graded D/F) can earn +1 from performance; age 30–32 50% chance of −1, 33+ −1,
    A/B players 27+ 35% chance of −1; a 5+ week injury 50% chance of −1; 22+ and under 4 games played 45%
    chance of −1 (award winners exempt). Max ±2 a year. Each step up adds 2–6 to a
    random group's cap; each step down removes 2–6 (never below the current rating).
  - **Aging** (scripts/sim/aging.gd): everyone ages a year each offseason. Past a group's peak age
    (Physicality 28, Injury 29, Accuracy 30, Handling 31, Objective 31, Mentality 33) its stats drop each year, ~1 per stat
    the first year and faster after (+0.75 a year, up to 6). Caps drop with them. Cap headroom also runs out
    earlier (physical ~28, skills ~30, mentality ~33), so most players peak between 26 and 30.
  - AI teams spend their points automatically, favouring groups their role uses (`scripts/sim/progression.gd`).
- **Training intensity** (`scripts/sim/training.gd`), per soldier, per week:
  - Rest: 0.25× XP (film study), extra recovery. Injured soldiers also get film-study XP.
  - Light: 0.6× XP.
  - Normal: 1×.
  - Heavy: 1.6× XP, much more fatigue.
- **Fatigue (0–100)** (`scripts/sim/conditioning.gd`):
  - Builds from training and matches, and recovers weekly (byes recover more).
  - Endurance and age scale load and recovery.
  - In-match penalty: nothing below 50, mild from 50 to 75, steep above 75.
- **Injuries:**
  - Rolled each week. The Injury stat sets the chance: 99 means rarely injured, 70 means more often.
  - High fatigue multiplies the chance.
  - Toughness sets how many weeks the soldier is out.
  - Injured soldiers can't play or train. League injuries are on the Injuries page.

## Roadmap

- Seasons and schedules (done: 20 teams, 4 divisions, 8-team playoffs)
- Save / Load (done)
- Scouting and the end-of-season draft (done)
- Contracts, hard cap, free agency, retirement, DNA, re-sign negotiation and starter promises (done)
- Trades: in-season (Week 8 deadline), offseason and draft-day, trade block and AI offers (done)
- Best-of-3 match modes (done; next: more modes and per-mode schemes)
- Visual combat
- Android and PC exports

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

Title → New Franchise → pick one of 5 teams → franchise hub (Madden/CFB-style).

- **Season loop** (`scripts/season/`): 1 division ("Premier Division"), 5 teams. Double round robin: 10 weeks,
  8 matches per team, one bye per week. Top 4 make the playoffs: semis (1v4, 2v3, higher seed hosts), then the final.
  Then the end-of-season review (awards and potential changes), the offseason (re-sign → draft → free agency),
  and aging → next season (rosters, ratings and contracts carry over).
- **Standings**: W/L, tiebreakers head-to-head, then round differential, then rounds won.
- **Each week**: all teams train at each soldier's intensity, every match is played, XP is awarded, then fatigue
  and injuries update. AI teams auto-spend skill points and pick intensities; you set yours on the Training page
  and spend SP on the player page (or **Auto-progress all** on the Progression page). Injured starters are
  auto-replaced by the best healthy bench soldier.
- **Scouting** (`scripts/season/draft.gd`, `prospect.gd`): each season has a class of 30 recruits (age 19–22).
  You only see name, age and listed position. You get 12 scout points a week (unspent points carry over).
  Each point spent on a prospect reveals a random stat group as a range of named grades, e.g. Accuracy
  "Steady Aim - Marksman". Points land on random groups: the first on a group shows 3 grades, a second narrows it to 2.
  Max 8 points per prospect; numbers and potential are never shown. Grades (worst → best) per group:
  - Accuracy: Spray & Pray, Inconsistent, Steady Aim, Marksman, Sharpshooter
  - Handling: Butterfingers, Clunky, Capable, Smooth Operator, Gunslinger
  - Physicality: Out of Shape, Average Build, Athletic, Explosive, Freak Athlete
  - Mentality: Lost, Rattled, Level-Headed, Leader, Field General
  - Injury: Glass, Fragile, Durable, Sturdy, Iron Man

  Grade thresholds: below 50, 50s, 60s, 70s, 80+.
  Most classes hide one unlabelled **phenom** (sometimes none or two). A phenom lists one position but grades
  well in every group, so he can play anywhere. AI teams don't know who they are, and the league consensus
  underrates them.
  Every prospect shows a **projected pick** (Early/Mid/Late 1st or 2nd, or Undrafted) from a noisy league-consensus
  board. The **Mock Draft** page (Personnel → Draft, or the Scouting page) predicts every pick from the current
  standings. The Scouting list and Draft Room are a table: portrait, name/age/position, projection, then one column per
  stat group (a 5-segment bar lit where his grade could be, best grade on top). Each grade is colored: red Poor, orange Below average, gray Average, blue Good, green Elite.
- **Draft**: after the Final, 2 rounds in snake order. Teams that missed the playoffs pick first (worst record first),
  then semifinal losers, the runner-up, and the champion last. AI teams pick from the consensus board with a little noise, leaning toward their weakest position.
  In the Draft Room you can sim to your pick, draft a prospect or auto-pick. Draftees get rookie contracts (cheaper
  later in the draft). The best 12 undrafted prospects join free agency; the rest leave.
- **Contracts & payroll** (`scripts/core/contract.gd`, `scripts/season/contracts.gd`): every soldier has a salary
  and years left. Hard cap of $36M per team per season, the same for everyone (Madden-style); minimum salary
  $750K always fits. Contracts tick down after the Final. Releasing a player leaves 50% of his remaining money on
  the cap as dead money, split over his remaining years. Personnel → Contracts & Payroll shows cap space, every
  contract and future commitments. Trades (later) will have to fit under the cap.
- **Offseason** (advance button walks the stages): **Re-sign** (choose years for expiring players; AI teams re-sign
  their keepers) → **Draft** → **Free agency** (3 days) → next season. Rosters max out at 8; you must release down to
  8 before the season starts.
- **Free agency** (`scripts/season/free_agency.gd`, League → Free Agents): unsigned soldiers with all ratings
  visible. Bidding: make offers (salary and years) during FA days or in-season. Each round every free agent scores
  his offers (70% money vs. asking, 15% team quality, 15% playing time) and signs the best one that clears his
  bar. Unsigned players lower their asking price over time. AI teams bid too. Contract negotiation (counter-offers,
  bonuses) is planned.
- **Retirement** (`scripts/season/retirement.gd`): soldiers retire from age 35 (always by 39), more likely as
  they decline. Free agents unsigned for a season retire if they're weak or 33+, which keeps the pool churning.
  Home/League → Retirements lists them by year, toggling between your team and the league.
- **Other teams**: League → Teams lists every club's record, OVR, payroll and cap space; click one for its roster.
- **Awards** (scripts/season/season_review.gd, Home → Awards): after the Final the league hands out Season MVP,
  Best Frontman/Center/Flex, Rookie of the Year and a 5-man All-League team (2 FM, 1 C, 2 FX), ranked on impact
  per game (min 4 games). During the season the page shows the MVP race. It also lists potential changes and
  this year's aging declines.
- **Home**: a big pane for this week's match (both teams' OVR and record, starter averages per group plus morale and
  energy as head-to-head bars, and two impact players per side), the Advance and Last Result tiles, a row of this
  week's actions (Set Training, Progress Players, Adjust Lineup, Roster, Scout, Free Agents, Contracts), then
  League News tiles (results with MVPs, awards, signings, injuries, retirements).
- **Roster** (2K style): a big preview pane on top (portrait, name and callsign, salary, contract, OVR/POT, fatigue
  and morale rings, group ratings) that follows the hovered/focused row. Below it is a table you can sort by any
  column (click a header; click again to flip). Free Agents, Progression and Contracts use the same sortable tables.
- **Player page** (Madden style) with tabs: **Overview** (action rail, morale/health/energy/XP rings, morale
  factors, OVR at each position and every attribute), **Ratings** (spend skill points), **Contract** (details,
  re-sign, release with a confirm step), **Stats** (season-by-season lines and career) and **DNA** (placeholder).
  League Leaders, box scores and Free Agents all open it.
- **Lineup**: the Swing drawn as a formation (2 Frontmen up front, the Center behind them, the Flexes far out on each
  side). Cards show face, OVR and POT. Click a slot, then a bench card (or another slot), to swap. "Generate Best
  Lineup" picks the best five.
- **Contracts & Payroll**: a sortable table (salary, years left, remaining, dead money if cut, OVR, morale...).
  Click a row to open that player's Contract tab, where you can release him.
- **Free agent offers** list your players at the free agent's best position with an OVR +/- column.
- **Morale** (`scripts/sim/morale.gd`): 0-100, no effect from 75 to 84. Every 5 points below 75 lowers a random stat
  by 1-3; every 5 points from 85 up raises one. OVR shows the effect, e.g. "69 (-4)". Each week: wins/losses (+/-2),
  starting (+2) or sitting healthy (-1.5), match MVP (+3), pay (under 75% of market value -1), then a 20% drift
  back toward 75.
- **Saves**: a soldier saves a teammate when he eliminates an attacker who has the teammate nearly dead. Tracked in
  box scores, season lines and League Leaders.
- **Callsigns** (`scripts/core/callsigns.gd`): every soldier gets a unique callsign that fits his best group
  (e.g. Ivan "Ironside" Hart). Used in tables, leaders and the lineup instead of jersey numbers.
- **Hub tabs**: Home, Team, League, Personnel, Settings. Tiles marked **SOON** are laid out but not built yet
  (trades, contract negotiation, staff, facilities).

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
godot --headless --path . --script res://tests/run_tests.gd     # sim/progression tests (~5 min)
godot --headless --path . --script res://tests/season_tests.gd  # season loop tests (~2 min)
godot --headless --path . --script res://tests/ui_smoke.gd      # debug UI smoke test
godot --headless --path . --script res://tests/franchise_smoke.gd  # franchise menus through a full season
```

Exit code 0 = pass. The slow part is the stat-sensitivity test, which plays 200 matches per stat.

## Model (Milestone 1)

- **Stats (0–99), in groups (MLB The Show style).** Each group's rating is the average of its stats (`scripts/core/stats.gd`):
  - Accuracy: short, medium and long-range acc
  - Handling: reload, grouping
  - Physicality: speed, agility, strength, endurance
  - Mentality: awareness, composure, teamwork
  - Injury: injury, toughness (view only, can't be upgraded)
- **Scheme "Swing":**
  - Frontman ×2, Center, Left Flex, Right Flex.
  - Each role has its own OVR weights (`scripts/core/scheme.gd`).
  - Role also drives in-sim behaviour (distance, exposure, flanking).
- **Rosters:** 8 soldiers each (5 starters + 3 bench). The league currently has 2 teams.
- **Match:**
  - Best of 7 elimination rounds, 0.5s ticks.
  - Each shot is resolved on the range band, accuracy, fatigue, composure, teamwork, and the target's evasion and toughness.
  - Deterministic for a given match seed (`scripts/sim/match_engine.gd`).
- **Progression:**
  - XP from matches and weekly training gives skill points (SP): every 500 XP (+150 per batch) = 3 SP.
    Levels are internal; the UI shows an XP bar toward the next SP.
  - SP buy +1 to a whole group. That spreads N points (N = stats in the group) randomly across the group, at most +2 per stat.
  - Cost rises with the group rating: 2 SP below 60, up to 6 SP at 90+.
  - **Potential** is an A–F grade that scales XP gain: A 1.5×, B 1.25×, C 1×, D 0.8×, F 0.6×. It's rolled by age
    (young players skew higher); draft phenoms are A (sometimes B).
  - Each group has a hidden cap (CFB27 style). Headroom comes from age, is multiplied by the potential grade
    (A 1.7× … F 0.4×) and by a random per-group factor, so a high grade means more room overall but which
    groups get it is random.
  - **End-of-season re-grade**: MVP +1 (50% chance of +2); a position award, All-League or Rookie of the Year +1;
    performance well above/below the rating rank (impact-per-game percentile vs OVR percentile, ±0.3) ±1;
    age 30–32 50% chance of −1, 33+ −1 (award winners exempt). Max ±2 a year. Each step up adds 2–6 to a
    random group's cap; each step down removes 2–6 (never below the current rating).
  - **Aging** (scripts/sim/aging.gd): everyone ages a year each offseason. Past a group's peak age
    (Physicality 28, Injury 29, Accuracy 31, Handling 32, Mentality 34) its stats drop each year, ~1 per stat
    the first year and faster after (up to 6). Caps drop with them.
  - AI teams spend their points automatically, favouring groups their role uses (`scripts/sim/progression.gd`).
- **Training intensity** (`scripts/sim/training.gd`), per soldier, per week:
  - Rest: 0 XP, extra recovery.
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

- Seasons and schedules
- Scouting and the end-of-season draft (done; next: draft-day trades)
- Contracts, hard cap, free agency, retirement (done; next: contract negotiation with counter-offers and bonuses)
- In-season trades (must fit under the cap)
- Different game modes per round
- Visual combat
- Android and PC exports

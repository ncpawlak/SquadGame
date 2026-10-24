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
  Then the offseason draft → start next season (rosters and ratings carry over; aging and contracts come later).
- **Standings**: W/L, tiebreakers head-to-head, then round differential, then rounds won.
- **Each week**: all teams train at each soldier's intensity, every match is played, XP is awarded, then fatigue
  and injuries update. AI teams auto-spend skill points and pick intensities; you set yours on the Training page
  and spend SP on the player page (or **Auto-progress all** on the Progression page). Injured starters are
  auto-replaced by the best healthy bench soldier.
- **Scouting** (`scripts/season/draft.gd`, `prospect.gd`): each season has a class of 30 recruits (age 19–22).
  You only see name, age and listed position. You get 12 scout points a week (unspent points carry over).
  Each point spent on a prospect reveals a random stat group as a range of named grades, e.g. Accuracy
  "Steady Aim - Marksman". Each point goes to an unscouted group first and shows a 2-grade range, so 5 points (the max per
  prospect) covers every group; numbers and potential are never shown. Grades (worst → best) per group:
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
  standings. Grade colors: red Poor, orange Below average, gray Average, blue Good, green Elite.
- **Draft**: after the Final, 2 rounds in snake order. Teams that missed the playoffs pick first (worst record first),
  then semifinal losers, the runner-up, and the champion last. AI teams pick from the consensus board with a little noise, leaning toward their weakest position.
  In the Draft Room you can sim to your pick, draft a prospect or auto-pick. Afterwards every team cuts down to
  8 soldiers (you choose who to release). The next season can't start until the draft and cuts are done.
- **Hub tabs**: Home, Team, League, Personnel, Settings. Tiles marked **SOON** are laid out but not built yet
  (trades, contracts, free agency, saves, awards, history, staff, facilities).

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
godot --headless --path . --script res://tests/season_tests.gd  # season loop tests (~10 s)
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
- **Scheme "Power Front":**
  - Frontman ×2, Center, Left Flex, Right Flex.
  - Each role has its own OVR weights (`scripts/core/scheme.gd`).
  - Role also drives in-sim behaviour (distance, exposure, flanking).
- **Rosters:** 8 soldiers each (5 starters + 3 bench). The league currently has 2 teams.
- **Match:**
  - Best of 7 elimination rounds, 0.5s ticks.
  - Each shot is resolved on the range band, accuracy, fatigue, composure, teamwork, and the target's evasion and toughness.
  - Deterministic for a given match seed (`scripts/sim/match_engine.gd`).
- **Progression:**
  - XP from matches and weekly training gives levels, and levels give skill points (SP).
  - SP buy +1 to a whole group. That spreads N points (N = stats in the group) randomly across the group, at most +2 per stat.
  - Cost rises with the group rating: 2 SP below 60, up to 6 SP at 90+.
  - Each group has a hidden cap (CFB27 style). Young players have more headroom, and the headroom also depends on the group's peak age (Physicality 29, Accuracy/Handling 33, Mentality 36).
  - Young players gain XP faster.
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
- Scouting and the end-of-season draft (done: basic version; next: rookie contracts, draft-day trades)
- Contracts, salaries, yearly money pools
- In-season trades
- Age-based decline (including shrinking group caps)
- Different game modes per round
- Visual combat
- Android and PC exports

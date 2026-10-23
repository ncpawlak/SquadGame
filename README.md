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

Debug UI:
- Generate a league from a seed.
- Simulate a match and view the play-by-play and box score.
- Train for a week (pick up to 3 focus players).
- Spend skill points, swap lineup slots.
- Batch-sim 200 matches.

## Tests

```powershell
godot --headless --path . --import                              # first run: builds class cache
godot --headless --path . --script res://tests/run_tests.gd     # sim/progression tests (~5 min)
godot --headless --path . --script res://tests/ui_smoke.gd      # UI smoke test
```

Exit code 0 = pass. The slow part is the stat-sensitivity test, which plays 200 matches per stat.

## Model (Milestone 1)

- **Stats (0–99):**
  - Accuracy: awareness, short/medium/long-range acc, grouping
  - Physical: speed, strength, agility, endurance
  - Other: reload, composure, toughness, injury, teamwork
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
  - XP from matches and weekly training gives levels, and levels give skill points.
  - Skill points cost more as a stat rises, and each stat has a hidden cap.
  - Stats used heavily in matches can get random breakthroughs.
  - Young players gain XP faster.
  - AI teams spend their points automatically (`scripts/sim/progression.gd`, `training.gd`).
- **Injury stat:** higher means less likely to get injured. Toughness reduces damage and will set injury length. Actual injuries aren't simulated yet.

## Roadmap

- Seasons and schedules
- Contracts, salaries, yearly money pools
- In-season trades
- End-of-season draft
- Age-based decline
- Injuries
- Different game modes per round
- Visual combat
- Android and PC exports

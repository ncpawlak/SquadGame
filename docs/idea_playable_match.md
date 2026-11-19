# Idea (bookmark): a playable match

Status: **idea only, nothing built.** Captured so it is not lost. The idea: an area-based, team-based first-person
shooter that could be played in career mode (as your soldier) and in franchise mode (with your team). Your stats shape
how the gun and the body behave.

## What exists today
- `MatchEngine` is a tick-based **5v5 simulator on a 2D arena** (`ArenaMap`), deterministic per seed. A match is best of 3:
  Team Deathmatch, King of the Hill, then a Sudden Death elimination game.
- Soldiers have role slots (frontman, center, flex), 20-odd ratings in five groups, fatigue, cover, flanks and objectives.
- The combine mini-games (`CombineTasks`: targets, timing, recoil, hold-steady, sprint, recall, sequence) are small
  playable skill checks already wired to stats. They are the seed of the aiming and movement feel.
- A watch viewer already draws the sim's events in real time (`match_viewer`).

## The idea
Play the match instead of (or as well as) simulating it. The match is short, small-map and team-based (the same modes
as the sim), in the first person. Your soldier's ratings decide how hard it is to aim and move.

### Ratings to mechanics (first pass)
| Rating | Playable effect |
|---|---|
| Short, medium, long accuracy | base spread (how wild shots land) and how fast the reticle settles at that range |
| Grouping | recoil recovery and burst pattern |
| Sway | reticle drift when moving, tired or at long range |
| Reload | reload time |
| Speed, agility | move speed, strafe and turn speed, dodge window |
| Strength, endurance | stamina for sprinting, recoil resistance, how fast fatigue builds |
| Toughness, injury | damage taken and chance of going down for good |
| Awareness | minimap and enemy-ping range, how soon enemies are marked |
| Composure | flinch and spread penalty when shot at or outnumbered |
| Teamwork | callout range and shared marks with teammates |
| Anchor, breach, objective IQ | point capture and hold speed, push bonuses, objective hints |

Gear and the warm-up bonus feed in as ordinary stat changes. A weak player is playable but wobbly, not locked out.

## Plan (phases, each shippable on its own)
0. **Feel prototype:** one small room, one enemy bot, stats driving spread, sway, speed. Reuse the combine tasks' scoring
   to check the numbers against sim hit rates.
1. **One soldier in a real match:** keep the sim for the nine other soldiers; the player *possesses* one slot. The 2D sim
   state is mapped to a 3D arena (same `ArenaMap` walls, cover and point), so a possessed game still produces the same box
   score and `MatchResult`.
2. **Hybrid mode:** play only key moments (the point, a clutch round, the final game) and sim the rest, so a match is
   five minutes, not thirty.
3. **Career integration:** the result feeds the player grade, brand, honors and the star meter exactly like a sim.
4. **Franchise integration:** possess any soldier on your team, or call plays as a coach and play one round.
5. **Polish:** replays through the existing viewer, accessibility (aim assist scaled by stats), difficulty.

## Design questions to answer first
- First person or third person? The 2D sim and web build argue for a simple top-down or over-the-shoulder prototype first.
- Does a played match replace the sim result or blend with it (for example, the player's performance adjusts the sim)?
- Aim assist and fairness: how much of the outcome should be ratings and how much skill? A "stats set the ceiling, skill
  gets you to it" rule keeps training meaningful.
- Time budget per match and per season, so career mode does not become a chore (hybrid mode, skip and auto-sim).
- Determinism and saves: the sim is deterministic per seed; a played match must be recorded so a replay and standings agree.
- Web build and performance (there is a web server tool in `tools/`): 3D in the browser is a real cost.
- Assets: weapons, animations, an arena kit. This is the biggest scope risk.

## Risks
- Scope: a first-person game is bigger than the whole management layer. Phases 0 and 1 should prove it is fun before more.
- Balance: two sources of truth (sim and played) can drift; the played result must reuse the sim's rules where possible.
- Input and platforms: controls on controller, keyboard and a browser.

## Related
- Warm-up mini-games in `docs/career_gear_wear_spec.md` (section 8) are the cheap first step toward this.

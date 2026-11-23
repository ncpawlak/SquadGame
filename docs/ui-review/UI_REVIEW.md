# Squad League: UI Review (Start, Career, Franchise)

Method: I captured 42 screens from the running game at 1600x900, the design resolution. I also captured 5 at 1280x720. Each capture waited about 1.6 s for animations to settle. Screenshots are in this folder and are linked by filename. Code references point at the file that builds the screen.

The game has a strong visual identity: a condensed display face (Barlow Condensed), skewed "broadcast" buttons, team-tinted hub headers, and a consistent dark navy and amber palette. The problems below are mostly layout discipline, hierarchy and a few unfinished screens. They are not a style problem.

---

## Verdict at a glance

| Area | Grade | One-line summary |
|---|---|---|
| Visual identity / palette / type | **A-** | Cohesive and recognisable. Keep it. |
| Franchise hub (Home, League, Standings) | **B+** | Best screens in the game. Standings and Scores are close to shippable. |
| Franchise Roster / Lineup / Player page | **C+** | Data is good, but hero cards eat the screen and text is clipped. |
| Career hub (Home) | **B+** | The three-column layout is the right model for the rest of the game. |
| Career flow (Combine, Report, Draft, Landing) | **D** | Unstyled, mostly empty, stretched CTAs. Looks like a debug build. |
| Settings / Club / secondary pages | **C-** | Tile system is misused. Dead tiles, meaningless big numbers. |
| Resolution robustness | **F** | Breaks below about 1600 px wide. |

---

## P0: Fix first (blocks "professional")

### 1. The UI does not scale, and it breaks below 1600 px wide
`project.godot` sets `window/stretch/aspect="expand"` but no stretch **mode**, so the mode defaults to `disabled`. At 1280x720, the tab bar clips ("Settings" is cut off) and the roster table runs off the right edge ([s04_roster](s04_roster.png), [s03_home](s03_home.png)). At 1440p or 4K the whole UI stays at pixel size and text becomes tiny.
**Fix:** add `window/stretch/mode="canvas_items"` with aspect `expand`. This scales the 1600x900 design to any window. It is one line and the single highest-impact change. Re-check the pages that assume a fixed width afterwards.

### 2. Career flow screens are unstyled
[c03_combine_results](c03_combine_results.png) is raw text on a black void:
- Columns are aligned with spaces, so the ranges are ragged.
- Two columns of text fill 25% of the width, and the rest is blank.
- The Continue button is stretched edge to edge.

[c04_draft_report](c04_draft_report.png) and [c05_landing](c05_landing.png) have the same problem. The logo is centred, the text is left-aligned, and the CTA is a full-width amber slab.
These are the moments a player is meant to feel something: the combine result, the draft, and "your career begins".
**Fix:**
- Use the same panel and card language as Create Soldier.
- Make each range a card with a bar showing the range on a 0-99 scale.
- Constrain the CTA to about 360 px, right-aligned or centred.
- Give the draft and landing screens a hero treatment (big team logo and a pick number, and the team colour as a backdrop).

Files: `combine_screen.gd:202`, `player_draft_pages.gd:93` and `:216-227`.

### 3. Roster, Green Team and Player pages: the hero card hides the data
[f11_team_0](f11_team_0.png): a 250 px featured-player card sits above the table, so only **4 of 10 rows** are visible, and the roster is the point of the page. [f20_player_page](f20_player_page.png) is worse. The header, name and tabs take about 330 px, and the title "Vernon Moreau" appears twice (page title and hero), so the content gets about 200 px.
**Fix:**
- Put the table first and make the hero a **compact right-hand detail pane** that updates on focus. This is the standard sports-management pattern.
- Remove the duplicated page title on player pages (the hero already names the player).
- Collapse the hero to about 130 px on the Roster page.

### 4. Clipped and colliding text
- Header stats run into the scrollbar: "$270.67M" and "SEED 2 PLAYOFF SPOTS 8" touch the scrollbar gutter ([f11_team_0](f11_team_0.png), [f13_league_0](f13_league_0.png)). Add a right margin equal to the scrollbar width.
- Lineup cards clip their stars ("POT A ★★★" on the Oracle card) ([f11_team_1](f11_team_1.png)).
- The "Card" button overlaps the Role column in the Trade Center ([f22_trade](f22_trade.png)).
- The tab badges ("!" and "1") overlap the "3 / RT" hint ([f12_personnel_1](f12_personnel_1.png)).

---

## P1: Hierarchy, density and readability

### 5. Chrome is too tall
The team header, tab bar and footer take about 255 px of 900, which leaves **640 px (71%)** for content. Players scroll constantly. Pages that need an overview (Home, Roster, Lineup) don't fit.
- Merge the market and buzz meters into the right side of the header, or into a drawer.
- Drop the header to about 90 px and the tab bar to about 44 px. That gives back about 70 px.
- The footer hint bar is always on and is 14 px wide-tracked text. Make it contextual (only the 3 to 4 relevant hints), or make it a collapsible "?" overlay.

### 6. Type scale has too many tiny sizes
About 90 call sites use text of 9 to 13 px, mostly in muted grey. Examples:
- The 11-12 px help text in the Lineup side panel.
- The 13 px "Q / LB" key hints.
- The 12 px captions under stats.

At 1080p and above these are hard to read, and on a TV or Steam Deck they are unreadable.
**Proposed scale (1600x900 base):**

| Role | Size |
|---|---|
| Page title | 44 |
| Section header | 26 |
| Card title | 22 |
| Body | 17 |
| Table cell | 16 |
| Caption and meta | **14, never below**. |

Code already enforces a floor in one place (`ui_kit.gd:257` bumps `[font_size=12/13]` to 14). Apply the same floor in `UiKit.label`.

### 7. The key hints are cryptic
"Q / LB" renders in this font as **"0 / LB"** at 13 px. The `Q` and `0` glyphs are nearly identical. Use "Q" in a keycap-style box and the controller glyph (LB). Show only the set that matches the last input device (keyboard or gamepad).

### 8. Home to-do tiles are empty
In the franchise hub ([f10_hub_home](f10_hub_home.png)), "Weekly Training", "Upgrade Players" and "Scout" are title-only tiles with about 40 px of dead space each. The `_body` parameter of `_todo()` is ignored (`hub.gd:1124`). Compare the career Home ([c10_hub_home](c10_hub_home.png)), where each tile has a status line ("9 SP ready", "Practice 2, Study 1"). **Fix:** show one status line per tile (e.g. "3 starters tired", "2 scouted, 8 to go"), and a done check or an urgent dot. News is pushed below the fold, so give it a column like the career Home does.

### 9. Matchup panel is hard to read
In the Home matchup, both teams' bars share one axis and are drawn in orange and red, which are two similar hues. The rank "(#11)" is attached to each value. The label text is 11-12 px and sits on top of the bars. Use team colours for the two sides, put the labels between the bars, and highlight the better side.

### 10. Title screen
[f01_title](f01_title.png)
- The menu is **off-centre**. The invisible 300 px side column used for "Career/Franchise" sub-options reserves space on the right, so the main buttons sit left of centre while the title is centred. Overlay the sub-menu or reveal it with a slide, but keep the main stack centred.
- Menu text is mid-grey on navy at rest, so the first screen looks disabled. Use white text at rest and a clear amber focus state.
- "Debug Sim Tools" and "Data Edit" sit at the same level as Career and Franchise. Move them behind a Developer toggle or into Settings.
- "Exhibition Match" shows a "coming soon" toast. Hide it or grey it out with a badge.
- No version number, and no background art or team imagery. Even a slow-scrolling team-logo wall would lift it.

### 11. Mode select and Team Select
- [f02_mode_select](f02_mode_select.png): the two cards are good, but they sit in the middle of a mostly empty screen and the header floats top-left. The Player card appears greyed at rest even though it is available. Show both at full strength, with a highlight on the focused one.
- [f03_team_select](f03_team_select.png): the vertical "E A S T" division labels are hard to read. Use a horizontal division header (a rotated label is the weakest option).
- The scouting panel takes about 315 px, so only two rows of teams are visible. Shrink it, or make it a side panel.
- Team cards carry too many signals (OVR, ring, badge, logo, bar colour). Pick two.
- [f04_franchise_settings](f04_franchise_settings.png): clean. This is the model for modals. One nit: **the dimmed backdrop is not dim enough**, so text bleeds through ("Atlanta Bulldogs" shows around the dialog).

### 12. Create Soldier
[c01_create](c01_create.png)
- **Name inputs are nearly invisible.** They are near-black fields with no border or placeholder, so a new player does not know where to type. Add a 1 px border, a lighter fill, a placeholder and a focus ring.
- The ratings table uses three-letter codes ("SRA 95", "MRA 71", "LRA 57") that are only explained by a footnote. Show full names, or add a tooltip.
- The Continue button floats outside the panels at bottom right. Anchor it in a footer bar.
- The left column has a gap between the face and the fields, and the archetype tabs wrap onto two rows.

### 13. Combine screen
[c02_combine](c02_combine.png) The drill list is a single narrow column of tall cards, with the "YOUR RANGES SO FAR" panel empty at 75% of the width. Use a 2x4 grid of drill cards on the left, with the "ranges" panel updating as you complete drills.

---

## P2: Consistency and polish

- **Tile system misuse** ([f15_settings](f15_settings.png), [f14_club](f14_club.png)). The tile is a good component for navigation but is used for settings. "W5", "M1", "2/3", "3" and "SOON" are large meaningless numbers. Use a normal settings list: label on the left, control on the right. Remove the dead "Franchise Settings: SOON" tile.
- **Mode wording leaks.** In Career mode, Settings still says "Save Franchise", "Load Franchise" and "Trade Difficulty" ([c13_settings](c13_settings.png)). Hide trade options in Career and rename to "Save Career".
- **Ragged tile rows** (4, 1 and 3 tiles with different widths). Use a fixed 4-column grid with consistent tile sizes, and let tiles span columns when needed.
- **Club** is three tiles and about 60% empty ([f14_club](f14_club.png)). Either fill it (finance chart, facility upgrades) or merge it into a smaller page. The finance tile text wraps into the number.
- **Weekly Plan** ([c20_plan](c20_plan.png)): the three outcome columns (levels 1, 2, 3) have no header, the first column is brighter than the others, the whole thing fills only the left 60%, and the fatigue bar has no legend. Add column headers ("1 pt, 2 pts, 3 pts"), align numbers, and fill the width.
- **Loadout, Skill Points, Hall of Fame Path** ([c23](c23_loadout.png), [c22](c22_placement.png), [c27](c27_hof.png)) are form-style text with no panels and large blank areas on the right. Use cards, put the preview on the right, and tint empty or locked rows.
- **Two back buttons**: the page header has "< Back", and some pages add another "Back" at the bottom (Loadout). Keep one.
- **Double scrollbars** appear on League Leaders (page scroll plus table scroll) ([f13_league_2](f13_league_2.png)). League Leaders also uses 3 of 4 columns and leaves a quarter of the width empty.
- **Load menu** ([f05_load_menu](f05_load_menu.png)): the text is sound but the whole list is a narrow column in an empty screen. Add the team logo and a thumbnail, and add a delete action.
- **Empty states** ("Nothing yet", "None yet", "Run a drill to start") are plain grey text. Give them an icon and a next-step line.
- **Focus states**: confirm every control has a visible focus ring for gamepad use. I could not see one on the title menu at load.
- **Colour use**: red is used for both "team accent" and "negative/danger" (cap space, losing score, tab accent in red-themed teams). Boston's red theme makes a negative "-$20.67M" read like decoration. Reserve one colour for danger, and keep team colour away from semantic states.

---

## What to keep
- Barlow Condensed headings with Barlow body text. Strong, legible, very "sports broadcast".
- Skewed buttons and tabs with a clear selected state (amber or team colour).
- Team-tinted hub backgrounds and the watermark logo.
- Standings, Scores and the Career Home layout are the target quality for other pages.
- Rating colour-coding (green to amber to red) with a thin bar under each number.

## Suggested order of work
1. Stretch mode (one line), then re-test at 1280x720, 1920x1080 and 2560x1440.
2. Reskin the four career-flow screens with the existing panel components.
3. Roster and Player pages: table first, compact hero.
4. Type-scale floor of 14 px, key-hint fix and header height.
5. Settings and Club as list pages. Title screen centring and debug entries.
6. Polish items (P2).

I have not changed any game code. Say the word and I can start with P0 items 1 and 4, which are small and safe.

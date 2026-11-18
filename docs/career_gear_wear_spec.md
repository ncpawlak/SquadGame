# First-pass spec: Wear, offseason cap raises, sponsors and gear

Design notes for issue #141. Numbers are starting points to be tuned in sims. Nothing here is built.
Career mode unless a line says franchise.

## 1. Wear (career regression)

### The meter
- One value per player, 0-100, carried across seasons. It never resets; reducers bleed it off.
- Shown as a tier name plus a per-group "regression risk" line, not as a raw number only.

### Gain and reduction per season (applied at the offseason, before aging)
| Term | Value |
|---|---|
| Age base | 0 up to age 23, then +4 a year |
| Load | mean weekly fatigue x 0.08 plus games played x 0.05 (a typical season is about +4) |
| Injuries | +5 for each major injury |
| Passive recovery | -1 |
| Spa, weekly | average spa level over the season: level 1 = -3, 2 = -6, 3 = -9 |
| Camp rehab | -1 per camp point spent on spa (max 4 points) |
| Sports Science Lab | -1 per facility tier |

Typical trainer with no spa: about +7 a year from 24, so about 35 at age 28 and about 63 at 32.

### Tiers and the regression roll
Each offseason, every stat group rolls on its own. The group's effective Wear is `wear x weight`.

Group weights (the old peak ages turned into weights): physicality 1.0, durability 0.9, accuracy 0.7,
handling 0.6, objective 0.6, mentality 0.4.

| Effective Wear | Tier | Chance the group loses | Loss per stat if hit |
|---|---|---|---|
| under 35 | Fresh | 0% | - |
| 35-59 | Worn | 25% | 1-2 |
| 60-79 | Beaten up | 50% | 1-3 |
| 80+ | Broken | 80% | 2-5 |

- A loss lowers the **rating only. The cap is kept**, so the points can be trained back with skill points.
- Regained points cost 50% XP while a stat is below its cap because of earlier regression (the "rebound").
- Old players keep earning XP; Wear never blocks it.

### Guardrails (must pass in sims before shipping)
- A grind-only player (no spa) aged 30-33 loses about 1 OVR a year or less, never collapses.
- A player on a moderate spa plan holds his rating until about 33.
- The average AI-era curve, when the same math is run league-wide, stays close to today's.
- Hall of Fame odds re-measured, since prime years get longer.

### Franchise
- No Wear meter. A **Recovery** facility (new, or an extension of the Sports Science Lab; open question) cuts every
  regression loss by 15% / 30% / 45% at tiers 1-3.
- Applies to AI teams too. Aging, AI trade valuation (`DECLINE_PER_YEAR`) and the negotiation "age and decline" pitch
  need to read the new expected curve.

## 2. Offseason cap raise
- Once an offseason the player picks one stat group and raises its cap.
- The group must be filled (rating at cap), so skill points gate it.
- Size: base +2, plus up to +4 more, max +6.
  - +1 for a strong season in the group (graded average above 80, or a relevant award)
  - +1 for a facility tier of at least 2
  - +1 for a camp special or coach focus on that group
  - +1 for a milestone or story event that year
- Caps never pass 99. Open: whether the base should be +1 if it proves too fast.

## 3. Sponsors and gear

### Structure
- Slots: helmet, vest, rifle, attachments, boots.
- Five brand tiers (the existing brand tiers): Unknown, Rising, Known, Star, Icon. Each has **3 sponsors**, and each sponsor
  has a full 5-slot line, so there are 3 items per slot per tier (75 items).
- Gear comes only through **sponsor deals** (see "Sponsor deals" below). A deal covers some slots, so a player can hold
  several deals from different brands. Any deal-provided item can be equipped in its slot.
- Gear is additive: effective rating = base + gear. Remove or swap an item and the ratings change immediately.
  Gear can exceed the cap. Hard ceiling 99. Hall of Fame scoring reads base ratings only.
- Per-stat total gear bonus is capped at +10.

### Bonus sizes (per item)
An item boosts **1 to 4 stats**, set by the sponsor tier and the gear type. Each tier has a bonus ladder (highest first)
and the item uses the first N values from the stats in the slot's pool.

| Tier | Brand needed | Bonus ladder | Stats on a full-breadth item |
|---|---|---|---|
| Unknown | 0 | +1 | 1 |
| Rising | 20 | +2, +1 | 2 |
| Known | 40 | +3, +2, +1 | 3 |
| Star | 60 | +4, +3, +2, +1 | 4 |
| Icon | 80 | +5, +4, +3, +2 | 4 |

**Gear type changes the breadth.** Helmet, vest and boots are full breadth. The rifle and attachments are specialized,
so they carry one fewer stat (minimum 1) but keep the top values, e.g. an Icon rifle is +5, +4, +3 on three stats.

Points per item: Unknown 1, Rising 3, Known 6, Star 10, Icon 14 (12 on the rifle and attachments). A full Icon set is
about 66 stat points across the slots, about +4 to +5 OVR in sims to be confirmed. Target: base 94-95 plus top gear
reaches 99.

### Slot stat pools
| Slot | Stats it can boost |
|---|---|
| Helmet | awareness, composure, toughness, injury |
| Vest | toughness, injury, strength, endurance |
| Rifle | short, medium, long accuracy, grouping |
| Attachments | sway, reload, grouping, long accuracy |
| Boots | speed, agility, endurance, strength |

Each brand has a lean (e.g. mobility, precision, defense) that decides which stats its items favor, so the three
brands in a tier are a real choice. Wearing 3 or more items of one brand gives a set bonus of +1 on its lean stat.

### Sponsors (placeholder names, parodies of real brands)
| Tier | Sponsors | Lean |
|---|---|---|
| Unknown | Haynes Tactical, Champ Gear, Fruit of the Boom | basic mixed |
| Rising | Fyla, Rebook, Timberlane | mobility, balance, defense |
| Known | Over Armour, Pooma, Smyth & Weston | defense, mobility, precision |
| Star | Nyke, Addidas, Oakly Tactical | speed, balance, awareness |
| Icon | Glok Custom, Sig Sawyer, Cryo Precision | handling, accuracy, defense |

### Sponsor deals
Sponsors come to you; you do not pick from a list. Interest depends on who you are, so a Green Team player usually has
none.

**Interest** (checked each offseason, and on events like a tier-up or award): a sponsor's interest in the player is
built from
- brand (the tier is the ceiling on which sponsors can be interested)
- recent graded performance and awards
- prospect value: draft slot and potential (grade), fading over a few seasons
- stars and age (younger and rising is attractive)
- fit with the brand's lean (a mobility brand likes high physicality)
- team success and morale (small)

A sponsor approaches when interest passes its threshold, so the number of offers varies. A top draft pick or a strong
prospect might draw a single Unknown or Rising offer on the Green Team. A Green Team player with a low draft slot and no
brand gets none. A star starter gets several, including the higher tiers.

**An offer** has terms: the slots covered (1 to 5), the item tier, yearly money, length (1-3 seasons), and obligations
(keep brand above a floor, play at least some games). Offers lean either money-heavy or gear-heavy, and the player can
counter once, e.g. ask for more money instead of gear. Accept, decline or let it expire.

**Several deals:** the player can talk to multiple sponsors and sign several, as long as the slots they cover do not
overlap. Slots taken by one deal cannot be covered by another until it ends.

**When a deal ends or is broken** (expired, or brand below the floor for a full season) its items are removed and the
ratings change back, since gear is additive. Renewal is a fresh negotiation, and performance since signing matters.

**Money:** pays per season (what money buys is still the open bookmark; placeholder until it exists).

Possible reuse: the contract negotiation system (`negotiation.gd`) already has offers, pitches and counters, so the
sponsor flow may be built on it. To check when planning the build.

Appearances as a plan-point cost are left out of the first version.

### UI plan
Built in the player hub (`player_pages.gd`) like the plan and placement pages, text based first, art later.

- **Loadout page** (new, opened from the player hub and from a Home to-do when there is a new offer or an empty slot):
  - Five slot rows: helmet, vest, rifle, attachments, boots. Each shows the equipped item (name, brand, tier), its stat
    bonuses (e.g. "+4 speed, +3 agility"), and which deal supplies it. An empty slot says why (no deal covers it).
  - Tapping a row lists the items available for that slot from active deals, with the stat change preview
    ("long acc 81 -> 85, OVR 88 -> 89") before you equip. Equipping or removing re-rates immediately.
  - A summary strip: base OVR, gear bonus, effective OVR, and any brand set bonus that is active.
  - Per-stat view: base, gear bonus and total for each stat, with the +10 gear cap marked where it binds.
- **Sponsors page** (new, from the loadout page):
  - Active deals: brand, tier, slots covered, yearly money, years left, the obligation (brand floor) and how close you are.
  - Offers: each with its terms, the interest reason in a line ("scouts like your draft slot", "your brand hit Known"),
    and Accept, Counter and Decline. Offers show an expiry.
  - Sponsors that are not interested yet show what they would want (brand tier, performance), so there is a goal.
- **Home**: a to-do for a new offer, an expiring deal, or a deal about to be dropped for low brand.
- **Status card and Plan page**: a gear line (effective OVR and bonus) next to the stars and brand line.
- **Wear**: the status card shows the Wear tier and per-group regression risk; the Camp Plan page shows rehab.
- **Testing**: a smoke test for opening the loadout and sponsors pages, equipping and removing an item, accepting an offer,
  and a deal ending; screenshots like the plan page (`tools/ui_shot_plan.gd`).

## 4. Stories and camp specials (scope for later)
- Group training: when morale is above 85 and the team is on a win streak, a session grants 2-4 skill points to a chosen group.
- Other events: veteran mentor, breakthrough game, injury comeback, rivalry match, captaincy, award season, media storm,
  coach conflict, contract-year spotlight, sponsor offers on a tier-up.
- Camp specials: a masterclass or specialist coach picks a group and feeds the cap raise.

## 5. Build order (suggested)
1. Wear for career, plus sim checks and tuning.
2. Offseason cap raise.
3. Effective-stat layer, then gear data and the loadout page, then sponsor deals and the sponsors page.
4. Franchise Recovery facility and league-wide aging calibration.
5. Story events and camp specials.

## Open questions
- Recovery facility: new facility or extend the Sports Science Lab?
- How many sponsor deals at once, and how the interest score is weighted.
- Money: what it buys beyond sponsor income.
- Does the effective-stat layer feed the match engine directly (yes, assumed) and the contract and draft reports (base only, assumed)?

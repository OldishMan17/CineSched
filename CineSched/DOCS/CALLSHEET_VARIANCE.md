# CineSched — Call Sheet Variance Report

Companion to `CALLSHEET_SPEC.md` (fields) and `CALLSHEET_LAYOUT.md` (geometry). This one
answers: **where do real call sheets disagree, and what must the export accommodate?**

Based on 9 call sheets + 2 production reports. Reference IDs match `CALLSHEET_SPEC.md` §0.

> Reference documents are real production paperwork and are not included in this
> repository. Content below is genericized.

---

## 1. Headline

**There is no single call sheet layout.** There are three families, differing at the level
of *which blocks exist at all*, not just their order:

| Family | Refs | Defining trait |
|---|---|---|
| **Narrative** | A, B, C, D, E, F | Scene schedule table drives page 1 |
| **Commercial** | G, H | **No scene table at all.** Crew + client on page 1, vendor table |
| **Reality/doc** | I | No scene table. Story beats + locations + crew with per-person wrap |

Within Narrative there are then **two template lineages** that order the scene table
differently (§3).

Build for Narrative. Commercial and Reality are separate templates, not the narrative
layout with blocks toggled off.

---

## 2. Templates propagate with people, not productions

The reference corpus spans 2002–2025 and multiple budget tiers, but several sheets share
identical boilerplate strings, block order, and column sets — because the same first AD
carried the same spreadsheet from job to job across a career.

This is not trivia. It means **"professional format" is not one target** — it's whatever
lineage a given AD was trained in. It argues for template *configurability* over a single
hardcoded layout, and it means whatever CineSched ships will become somebody's career
template.

---

## 3. The two narrative lineages

### Lineage A — "Description-first"

Scene table columns, in order:

```
SET / SCENE DESCRIPTION | D/N | SCENES | CAST | PAGES | LOCATION
```

- Description **first**, scene number **fourth**
- **LOCATION is a per-scene column**, right-hand side
- Page 1 right rail carries LOCATION / CREW PARKING / BASECAMP / TRUCKS REPORT TO stacked
- Table opens with a `This Day's Work:` label row
- Pages stored as **decimals** (`0.25`, `0.375`, `0.625`, `4.625`) — the float bug from
  spec §3.2 is this lineage's native behavior, not one person's mistake

REF-B (a 2025 student sheet) is *the same template file* as REF-E (a 2007 studio feature),
18 years later — identical boilerplate strings, identical block order, identical column set.

**So: does a student sheet drop blocks a union sheet requires? No.** It's the same template
with blocks left empty. Scale changes what gets filled in, not what exists.

### Lineage B — "Scene-first"

```
SCENE | SET / SCENE DESCRIPTION | CAST | D/N | PAGES | EST TIME
```

- Scene number **first**
- **No location column** — location lives in the header block only (single-location day)
- **EST TIME** column, which Lineage A lacks entirely
- Pages as proper eighths strings (`7 6/8`, `1 3/8`)

### Implication

The scene table column set must be **configurable per production**, not fixed. Minimum:

```
columns: ordered list from
  { scene_number, description, cast, day_night, pages, est_time, location, i_e }
```

Ship Lineage B as default — it's the modern union sheet, and EST TIME is the most valuable
column for a small production. Offer Lineage A as a preset.

---

## 4. Union vs. indie: the crew table diverges

The biggest field-level difference in the corpus.

| | Union (REF-A) | Indie/student (REF-B, C, D) |
|---|---|---|
| Crew columns | headcount, title, name, call | #, position, name, call, **telephone**, **email** |
| Contact info | **Absent** | Present for every crew member |
| Union reps row | Present (local numbers, guilds) | Absent |
| Health & Safety committee | Present | Absent |
| Walkie channel per dept | Present | Absent (single list in boilerplate) |
| Land acknowledgment | Present (Canadian) | Absent |
| COVID screener | Present | Absent |
| Meal counts | `Crew Breakfast x60, BG Lunch x0` | Absent or minimal |

Union sheets **omit crew phone and email** — the crew list is a separate distributed
document. Indie and student sheets put contacts directly on the sheet because there is no
separate crew list.

**Implication:** store contacts always; make their *appearance on the call sheet* a
per-production toggle. A student production wants them printed; a union production must not
print them.

---

## 5. Commercial family — genuinely different page 1

Verified on REF-G and REF-H. Page 1 is:

```
1. Four-company header    Client | Agency | Production | Editorial
                          each: name, address, tel, fax, + own call time
2. Film stock flags       35mm XX | 16mm | 8mm | Sync XX | MOS
3. Job block              Job name, Job #, multiple Spot titles
4. Location + parking + hospital
5. Sun / length           Rise • Set • Length
6. CREW TABLE             ← page 1, left half
   columns: CREW | NAME | TELEPHONE | MOBILE/ALT | CALL | WRAP
7. CLIENT/AGENCY TABLE    ← page 1, right half, beside crew
   columns: company | NAME | TITLE | PHONE | CALL | WRAP
8. VENDOR / EQUIPMENT     ~40 rows: category | vendor | phone | contact
9. TALENT TABLE           roles + agent
10. Production report stub 1st Shot AM | Lunch | Wrap | Stock | Total Footage |
                          Footage Shot | Balance
```

**No scene table exists.** A commercial shoots boards, not scenes. Nothing to map
CineSched's core data structure onto.

REF-H carries a tech-scout tab plus `Day 1`–`Day 4` tabs in one workbook — multi-day in a
single file, which is the multi-production/multi-day requirement showing up as existing
professional practice.

**Recommendation: don't build this.** Different product. The vendor table alone is a large
feature.

---

## 6. Reality/doc family — REF-I

Also no scene table. Location-and-crew-centric:

```
Show logo | shoot date | shoot day # | episode or shoot title
PRODUCTION OFFICE | DISTANT LOCATION | Story Beats | Shoot Locations | PRODUCTION NOTES
HOSPITALS | WEATHER | CALL LOCATION | ADVANCED SCHEDULE | Call Time / Crew Meal / Wrap
CREW: TITLE | NAME | CELL # | OFFICE # | LOCATION | CALL | CREW MEAL | WRAP | SCHEDULE
```

Four location slots. `Story Beats` replaces the scene table — free text, no page counts.
Crew rows carry **per-person location, meal, and wrap** because a doc crew splits across
locations on the same day.

Noted for completeness; not worth building.

---

## 7. Other cross-corpus variance

**Sheet architecture.** REF-C and REF-D are workbooks structured as
`FRONT | BACK | CAST | CREW` — presentation sheets fed by separate data sheets. That's the
plan/render split CineSched should have internally. Independent confirmation the
architecture is right.

**Two hospitals.** REF-F carries two; REF-I has four location slots. Model as lists.

**Headcount is not an integer.** REF-D uses `SD` in the `#` column alongside `1` and blank.
Union type, same as call times.

**Day-of-days is not always integer.** `DAY 9 OF 27`, `SHOOT DAY: 3 OUT OF: 4`,
`DAY 1 OF 30`. One file stores the total as a float — validate input.

**Meal handling varies.** `ND BREAKFAST: 8:00A–8:30A`, `COME HAVING HAD`, `LUNCH 7P`,
`Breakfast: 1300-1500`. Sometimes a time, sometimes a range, sometimes an instruction.
Union type again.

**Page size.** A4 (REF-A), Letter (most), Legal 8×14 (REF-E). REF-E uses the extra length
for **more rows**, not wider columns — its scene table still spans the same proportional
width. So page size affects row capacity, not column ratios. One set of proportions works
across all three sizes.

---

## 8. Recommended architecture

The export should be **block-list driven**, not a hardcoded page:

```
Template = ordered list of Blocks
Block    = { type, enabled, config }
```

A template is then data, not code, and the families become template definitions rather than
separate renderers. Blocks needed for Narrative:

```
title_bar · header_grid · boilerplate · weather_strip · scene_table · banner ·
cast_table · standins_bg · crew_table · dept_notes · hospital · advance_schedule ·
paper_chase · signature_footer
```

Per-production config the corpus proves is needed:

- page size (A4 / Letter / Legal)
- scene table column set + order (Lineage A vs B)
- print crew contacts (indie) vs suppress (union)
- union blocks on/off (reps, H&S committee, per-dept walkie)
- 12h vs 24h clock
- pages display: eighths (correct) vs decimal (legacy compatibility)

**Ship one template — Narrative, Lineage B, union blocks off.** That covers a student film
and a sheet you'd hand a professional crew. Everything above just needs to not be *designed
out* of the schema now.

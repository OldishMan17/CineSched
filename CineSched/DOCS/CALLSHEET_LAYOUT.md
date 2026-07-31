# CineSched — Call Sheet Layout Reference

Companion to `CALLSHEET_SPEC.md`. That document covers **what fields exist**. This one
covers **where they go on the page** — measured from REF-A, the primary model.

> Reference documents are real production paperwork and are not included in this
> repository. All example content below is genericized. Measurements are unmodified.

---

## 1. Page geometry

| Property | REF-A | Implementation note |
|---|---|---|
| Page size | **A4** (8.27 × 11.69 in) | Canadian production. Do **not** hardcode Letter. |
| Margins | 0.50 in all four sides | Tight — call sheets use the full page |
| Usable width | **7.27 in** (A4) / 7.50 in (Letter) / 7.50 in (Legal 8×14) | All column specs are % of usable width |
| Orientation | Portrait | Commercials in the corpus run landscape |

Page size must be a **production-level setting**. The corpus contains A4, US Letter, and
Legal 8×14. Column proportions stay fixed; absolute widths reflow.

---

## 2. Page 1 block order (vertical)

Measured top to bottom on REF-A:

```
1. Title bar                    — production | date | day-of-days      (3 cells, full width)
2. Header grid                  — 3 columns, unequal
     col A ~33%   production co. address + key personnel stack
     col B ~34%   date / day-of-days / land acknowledgment
     col C ~33%   crew call / shooting call / meals / location / basecamp / crew park
3. Boilerplate rules block      — full width, single merged cell, centered caps
4. Weather strip                — 8 equal cells, single row:
                                  sunrise | sunset | weather | wind | gusts | hi | low | POP
5. SCENE SCHEDULE TABLE         — see §3
6. Forced-call warning banner   — full width, centered, asterisk-wrapped
7. CAST TABLE                   — see §4
8. Stand-ins / background block
9. CREW TABLE                   — see §4.3 (spills to page 2)
10. Department notes
11. Nearest hospital + emergency
12. Advance schedule            — repeats §3 columns per day
13. Paper chase
14. Signature footer            — N cells, name over phone
```

Blocks 3, 6, and the banner rows inside 5 and 7 are all **full-width merged rows**. That
merge behavior is the most important structural fact for the renderer — see §3.2.

---

## 3. Scene schedule table

### 3.1 Column widths

Measured, normalized to % of usable width:

| Column | % width | On A4 (7.27") | Alignment |
|---|---|---|---|
| SCENE | 12.6% | 0.92" | left |
| SET / SCENE DESCRIPTION | **52.9%** | 3.85" | left |
| CAST | 13.5% | 0.98" | left |
| D/N | 6.1% | 0.44" | center |
| PAGES | 8.4% | 0.61" | center |
| EST TIME | 6.4% | 0.47" | center |

The description column takes **more than half the page**. This proportion is what makes a
sheet read as professional; an even split across six columns reads as a spreadsheet.

If EST TIME is disabled (8 of 9 sheets in the corpus lack it), redistribute its width to
DESCRIPTION rather than spreading it evenly.

### 3.2 Row types

The table has **three** row types, not one:

| Type | Rendering |
|---|---|
| `scene` | Normal 6-column row. Set name bold, synopsis italic on the line beneath, same cell. |
| `banner` | **Single cell spanning all 6 columns.** Bold, centered, caps. |
| `total` | Right-aligned label + page total + time total. |

Banner rows are interleaved *between* scene rows — they are ordered calendar items, not
metadata attached to a scene. Model calendar items as `Scene | Banner` in one ordered list
per day, or the export can't reproduce this.

### 3.3 Cell content structure

The description cell is two paragraphs in one cell:

```
INT. [SET NAME] (VFX)                ← bold, caps, may carry (VFX) suffix
[One-line action synopsis.]          ← italic, sentence case, one line
```

Scene numbers appear comma-joined when a row covers several: `9pt, 10, 11pt`. A row is
keyed to a **list** of scene numbers, not one.

---

## 4. Cast, stand-in, and crew tables

### 4.1 Cast table — 9 columns

| Column | % width |
|---|---|
| ID# | 4.9% |
| CAST (actor) | 17.4% |
| CHARACTER | 19.5% |
| S/W/F | 6.3% |
| P/U | 6.3% |
| H/M/W | 6.5% |
| BLOCK | 7.4% |
| SET | 6.1% |
| NOTES | 13.5% |

Actor + character together take **37%**. The four call columns are narrow and equal — they
hold values like `1400`, `S/D`, `-`, `O/C`. Note `-` means "not applicable to this person,"
distinct from blank.

Banner rows appear here too, same full-width merge.

### 4.2 Stand-ins / background

A 6-column strip with paired headers — stand-ins on the left, background on the right, each
with its own CALL and ON SET columns and its own NOTE row. Renders as two logical tables
sharing one row grid.

### 4.3 Crew table — the three-block grid

58 rows × 18 columns on REF-A. The 18 columns are **three repeated 6-column department
blocks** laid side by side:

```
[ headcount | title | name | call ] × 3 blocks
```

Departments flow **down each block, then to the next block** — not left to right across the
page. Each block carries its own department header rows (`CAMERA`, `GRIPS`, `LX`, `SOUND`,
`SPFX`, `VFX` down block 1; `MAKE-UP FX`, `MAKEUP`, `HAIR`, `COSTUMES` down block 2; and so
on).

The headcount column is a `0`/`1` flag — `1` = counted for meals, `0` = not. That's what
feeds `Crew Breakfast x60`. It is not a quantity.

Department headers carry an optional walkie channel in the adjacent cell
(`MAKE-UP FX | CH.1`, `TRANSPORTATION | CH. 3`).

**Renderer approach:** compute the full ordered department list with its rows, then balance
into three columns by total row height. Do not hand-assign departments to blocks.

REF-K uses the same block logic at two blocks instead of three
(`# · POSITION · NAME · IN · OUT · TOTAL`), so the balancing algorithm should take block
count as a parameter.

---

## 5. Rendering notes

- **Fixed-height rows are wrong.** Description cells wrap to two lines, banner rows are one
  line, department-note cells run long. Rows must size to content, then paginate.
- **Repeat table headers across page breaks.** The crew table spans pages in REF-A.
- **Full-width merged rows must survive pagination** — a banner splitting across a page
  break is the most likely visual bug.
- **Everything is bold or caps.** Body text is the exception. Field labels, department
  headers, banners, totals, and header block keys are all bold caps.
- **Type is small** — roughly 7–8pt in the tables. Density is the point; a call sheet that
  needs three pages has failed.
- Borders: thin rules on all table cells, heavier rule between major blocks.

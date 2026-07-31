# CineSched — Call Sheet Export Spec

Field requirements for professional call sheet export, derived from a reference corpus of
9 production call sheets (1998–2022) plus 2 Daily Production Reports.

> **Note on sources.** The reference documents are real production paperwork containing
> crew contact information and are not included in this repository. All examples below use
> placeholder names, numbers, and addresses. Measurements, structure, and field inventories
> are unchanged.

**Reference corpus** (anonymized):

| ID | Type | Era | Role in spec |
|---|---|---|---|
| **REF-A** | Union feature | 2020s | **Primary model** — most complete |
| REF-B | Student short | 2020s | Same template lineage as REF-E |
| REF-C | Indie feature | 2010s | Front/back workbook structure |
| REF-D | Film-school short | 2000s | Timed day plan in scene table |
| REF-E | Studio feature | 2000s | Legal 8×14 |
| REF-F | TV pilot | 2000s | Two hospitals |
| REF-G | Commercial | 2000s | No scene table |
| REF-H | Commercial | 2000s | Multi-day workbook + tech scout tab |
| REF-I | Blank template | 2000s | Reality/doc structure |
| REF-J | Daily Production Report | 2020s | Union scale |
| REF-K | Daily Production Report | 2010s | Indie scale |

---

## 1. Page architecture

Near-universal two-page structure:

**PAGE 1 (FRONT)** — what everyone reads on set
- Header / title / date / day-of-days / calls
- Weather + sunrise/sunset
- Boilerplate rules block
- Locations + hospital
- **Scene schedule table**
- Cast table
- Stand-ins / background
- Department requirements
- Advance schedule
- Signature footer

**PAGE 2 (BACK)** — the phone book
- Full crew list by department, with individual calls
- Vendor list (commercials only)
- Union reps / head counts / meal counts

Paper: US Letter portrait is the modern default. REF-A is **A4** (Canadian production).
REF-E is **legal 8×14** to fit more rows. Page size must be a production-level setting, not
a constant.

---

## 2. Field inventory

### 2.1 Header block

| Field | Notes | In corpus |
|---|---|---|
| Production title | | 9/9 |
| Production company (legal entity) | e.g. "Example Films, LLC" | 8/9 |
| Production office address / phone / fax / email | | 8/9 |
| Date | Full format: "WEDNESDAY, JUNE 1, 2022" — day-of-week matters | 9/9 |
| Shoot day / total days | "DAY 1 OF 19" | 9/9 |
| Crew call | | 9/9 |
| Shooting call | | 8/9 |
| Sunrise / sunset | | 9/9 |
| Day length | "Length • 14:24" | 2/9 |
| Weather: condition, hi, low | | 8/9 |
| Weather: wind, gusts, POP (precip %) | modern addition | 1/9 |
| Set cell phone (+ whose) | "[NAME]: [PHONE]" | 7/9 |
| Key personnel in header | Director, Producer(s), EP, Co-P, Line Producer, PM, 1st AD | 9/9 |
| Meal times | Breakfast, lunch, dinner; "COME HAVING HAD"; "ND Breakfast" | 8/9 |
| Revision state | "CALL SHEET – BLUE REVISED [DATE] – 11:45P" | 3/9 |
| Script / schedule revision colors | "Script: Pink 8/9  Schedule: Pink 8/6" | 3/9 |
| Land acknowledgment | Canadian productions | 1/9 |
| "See attached map" | | 6/9 |

### 2.2 Locations block

Repeatable list — **not** single fields. REF-F carries **two hospitals**; REF-I has slots
for four locations.

- Shooting location(s): name + full address
- Crew parking (address + instructions: "Park as directed", "Enter via main gate")
- Basecamp / lunchcover
- Trucks report to
- Nearest hospital: **name, address, phone** — 9/9, and legally load-bearing. Support N entries.
- Emergency number (911)
- Shuttle notes

### 2.3 Boilerplate rules block

Reusable per-production text, set once — never retyped daily. Observed clauses:

- No forced calls / pre-calls / upgrades / meal penalty without prior approval from [PM/Line Producer/Producer]
- No visitors on set without producer approval
- No personal photos / nothing posted to social media without approval
- Smoke only in designated areas — always use a butt can
- A safety meeting will be held at call
- All departments must report safety concerns to Production/AD staff
- Harassment-free workplace statement + who to contact
- COVID screener protocol
- "Individual call times may vary — please check your times"
- Walkie channel assignments (`1 – Production/Art, 2 – Private, 3 – Transpo, 6 – Camera, 7 – Elec, 8 – Grip, 11 – FX`)

### 2.4 Scene schedule table

Core columns: **Scene # · Set/Scene Description · Cast · D/N · Pages · Location**, plus
optional **Est. Time** (modern) and **I/E**.

- **Scene number** — see §3.1. Strings, not integers.
- **Set description** — `INT./EXT. SET NAME` on one line, italic one-line synopsis beneath
- **Cast** — list of cast ID numbers: `1, 2, 3, 4, 6, 7`
- **D/N + story day** — see §3.3
- **Pages** — eighths; see §3.2
- **Est. time** — per-scene estimate (`:45`, `5:15`) with a day total (`9:45`). Only REF-A
  has this, and it's the single most useful column for a student production.
- Totals row: total pages, total est. time

**Non-scene banner rows** are interleaved throughout the table. Observed patterns
(genericized):

`COMPANY MOVE TO [LOCATION]` · `SET SHIFT TO [SET] AFTER LUNCH` · `BLOCK SHOOT [SET]` ·
`MOVE OUTSIDE` · `PRE-LIGHT [SET]` · `TECH SURVEY @ WRAP – Director/DP/Key Grip/Gaffer/Sound/1st AD/Locations/PD` ·
`MRT – 4` · `SAFETY MEETING @ 8:30A` · `BE PREPARED TO SHOOT SCENES [N, N, N]` ·
`***MUST HAVE ID FOR [LOCATION]***`

REF-D goes further and interleaves a timed day plan: `SHOOT 2 | 9:30A–12P`,
`WRAP | 12P–12:30P`, `COMPANY MOVE | 12:30–1P`, `LUNCH | 1:30–2:15P`.

### 2.5 Cast table

| Column | Notes |
|---|---|
| Cast ID # | Stable production-wide; the DOOD key |
| Actor name | |
| Character | |
| Status | `SW W WF SWF SWD H WD R T D` — see §3.4 |
| Pickup (P/U) | `S/D` = self-drive, or a time |
| H/M/W call | Hair/makeup/wardrobe |
| Rehearsal | |
| On set / set call | |
| Shooting call | |
| Out / dismiss | |
| Remarks | "Report to [ADDRESS], 2nd Floor", "WRD FITTING 1ST", "Report to H/MU/WARD" |

Banners: `**ALL CALLS SUBJECT TO CHANGE AT WRAP**`,
`*NO PUSH/PULL ZONE – HOLD/REHEARSAL/TRAVEL/FITTINGS/ADR*`

REF-D and REF-B list the **full cast roster** including not-called actors with blank calls —
the sheet doubles as a company directory.

### 2.6 Stand-ins, photo doubles, background

- Type tag (`SI`, photo double), description ("Male Utility", "[CHARACTER] SI", "20 BAR PATRONS")
- Count, call, ready@/on set, report to
- Total BG count
- Notes ("Park @ Crew Park, SI report to AD on set")

### 2.7 Department requirements / notes

**Scene-keyed** notes grouped by department — build the note on the scene and aggregate
here, don't maintain twice.

Departments observed: Props · Set Dressing / Set Dec · Costumes / Wardrobe · Make-up ·
Hair · SFX MU / Prosthetics · FX / SPFX · VFX · Camera · Graphics · Additional Labor ·
Special Equipment · Vehicles / Picture Cars · Music · Locations · Animals

Format: `PROPS — 86: [items]. 9pt,10,11pt: [items]...`

### 2.8 Crew table (page 2)

Per person: **headcount flag · title · name · call**, plus **phone · email** on indie and
student sheets. Grouped by department. DPR adds **in/out**.

> **Union vs indie difference.** Union sheets (REF-A) deliberately **omit** crew phone and
> email — contacts are distributed as a separate crew list. Indie and student sheets
> (REF-B, REF-C, REF-D) print them inline. Make this a per-production toggle; printing sixty
> personal phone numbers on a union sheet is wrong.

Department order (composite of corpus):
`Production · Assistant Directors · Script Supervisor · Camera · Grips · Electric/LX ·
Sound · Art Department · Set Decoration · Props · Construction · Paint · Costumes ·
Makeup · Makeup FX · Hair · SPFX · VFX · Stunts · Transportation · Locations · Catering ·
Craft Service / First Aid · Accounting · Casting / Extras Casting · Post Production /
Editorial · Security · COVID Safety · Composer · Additional Labour`

Also: per-department **walkie channel** (`MAKE-UP FX | CH.1`), union reps (local numbers
and guild names), Health & Safety committee, head count, meal counts
(`Crew Breakfast x60, BG Lunch x0`).

### 2.9 Advance schedule

Next day(s), each with date, day-of-days, location, estimated call, and the same
scene-table columns + totals. REF-A and REF-E both show **two** advance days — support N.

### 2.10 Signature footer

Name + phone for: Line Producer, Production Manager, 1st AD, 2nd AD, Location Manager, ALM,
Transport Coordinator, Producer, 2nd 2nd AD. Plus **Quote of the Day** (3/9 — keep it,
crews like it).

### 2.11 Commercial-only blocks

Skip for narrative; needed only if CineSched serves commercial work:

- **Client / Agency / Editorial** companies: name, address, phone, fax
- **Job name, Job #, Spot titles** (a commercial shoots multiple spots/day)
- **Client & agency contacts**: name, title, phone, call — they attend the shoot
- **Vendor/equipment table**: category · vendor · phone · fax · contact. ~40 rows
- **Film stock flags**: 35mm / 16mm / 8mm, Sync / MOS
- **Talent + agent**: agent name and agency phone alongside talent
- Thomas Guide page reference (obsolete — drop)

---

## 3. Data model requirements

These are the ones that cost a rewrite if gotten wrong.

### 3.1 Scene numbers are strings

Observed: `86`, `9pt`, `10`, `11pt`, `75pt`, `A20`, `B20`, `A79`, `B79pt`, `A88pt`, `A89`,
`60pt4`, `63pt1`, `72pt`, `110pt`, `103pt`, `75A`, `B Roll`

Never `int`. Sort with a natural-sort comparator that decomposes into
`(numeric core, alpha prefix, alpha suffix, pt-index)`. `pt` = partial scene, meaning **the
same scene appears on multiple shoot days** — so scene→day is many-to-many.

### 3.2 Store pages as integer eighths

Real bug in the corpus — REF-D totals to:

```
1.9600000000000002
```

Float accumulation, shipped in a real production document. That sheet's per-scene values
(`0.1`, `0.16`, `0.7`) aren't valid eighths at all — someone typed decimals into a page
column.

```
store:   pages_eighths: int        # 15
render:  "1 7/8"                   # mixed fraction, professional standard
totals:  sum ints, then format     # never sum floats
```

Professional sheets display eighths (`7 6/8`, `4 6/8`, `1 3/8`) and notably do **not**
reduce fractions — `6/8` stays `6/8`, not `3/4`. Match that.

### 3.3 Story day ≠ day/night

`D8` is "day, story day 8". Parse into two fields:

- **Time of day**: `D`, `N`, `EVE`, `DUSK`, `DAWN`, `ND`, `FB` (flashback), `M`, `I/E`
- **Story day**: integer or null

Rendering rejoins them. Keeping story day separate is what later enables continuity checks.

### 3.4 Cast status codes

`S` start · `W` work · `F` finish · `H` hold · `R` rehearsal · `T` travel · `D` drop ·
combined as `SW`, `WF`, `SWF`, `SWD`, `WD`

Model as a **set of flags**, not an enum of strings. Derive automatically from the DOOD: a
character's first shoot day is `S`, last is `F`, gaps between are `H`.

### 3.5 Call time is a union type, not a time

Observed non-time values: `O/C` (on call) · `N/C` (not called) · `TBD` · `SD` ·
`RTS @ 8:30A` (report to set) · `Per [DEPT HEAD]` · `L` · `A` · `---` · `N/A` · `SUN`

```
CallTime = Time | OnCall | NotCalled | TBD | PerPerson(name) | ReportToSet(time) | Text(str)
```

A plain time field forces users to type garbage into it. Also: times appear in both 12h
(`8:30A`, `12:30P`) and **24h** (`1400`, `0918`, `2242`) — union productions use 24h. Make
it a production-level display setting.

### 3.6 Phone numbers carry type suffixes

Format examples: `555.555.0123` · `555.555.0182c` (cell) · `555.555.0295h` (home) ·
`555.555.0836p` (pager) · `555.555.0226f` (fax)

Store `{number, type}` rather than parsing suffixes forever. Multiple numbers per person
(corpus has `TELEPHONE` + `MOBILE` + `ALT #` columns). Model contacts as a list of typed
contact methods, not two text fields.

### 3.7 Revision / paper chase state

Call sheets are versioned like scripts, by color:
`White → Blue → Pink → Yellow → Green → Goldenrod`. Track on both:

- **Call sheet**: revision color + timestamp, and `PRELIM` vs final
- **Script/schedule**: which revision the sheet was built from
  (`White Script + pink rev + YELLOW REV (date) + GREEN REV (date)`)

REF-A's "PAPER CHASE" block exists purely to record this. It's how a crew knows whether
their pages are current.

---

## 4. The Daily Production Report

REF-J and REF-K are **Daily Production Reports** — filled out after the day wraps. Roughly
80% field overlap with the call sheet: same header, same cast rows, same crew list. The
difference is recording **actuals against the plan**.

If CineSched models plan + actual on the same objects, the DPR is nearly free — and no
student scheduling tool has one.

DPR-only fields:

- **Timing actuals**: 1st shot, 1st shot after lunch, dinner, 1st shot after dinner, company dismissed
- **Scene/page ledger**: script total · scheduled · previous · today · total · to-be-shot
  (as scene count **and** page eighths)
- **Scene disposition**: scheduled · full scenes shot · partial scenes shot · added ·
  not completed · omitted · retakes
- **Time ledger**: est vs actual minutes, ± variance, master running time, remaining RT
- **Set-ups**: previous / today / total
- **Media**: camera rolls per cam, sound rolls, video data GB per cam, video running time
- **Cast on-set times**: call · H/M/W · on set · meal in/out · dismiss · leave base ·
  arrive location · leave location · arrive base
- **Crew in/out** per person
- **Days**: scheduled vs actual, holidays

REF-K (indie scale) shows the irreducible core both scales share: day-type matrix
(`1ST UNIT · 2ND UNIT · REHEARSAL · TEST · TRAVEL · HOLIDAYS · TURNAROUND · ADDED SCENES ·
RETAKES · TOTAL` crossed against `SCHEDULED` / `ACTUAL`), scene/page ledger, timing column,
crew in/out. Everything else is scale-specific.

The est-time column in §2.4 is what makes the variance columns computable.

---

## 5. Build order

1. **Schema first** — productions as first-class entities; calendar items as
   `Scene | Banner` in one ordered list; crew/cast as records with typed contact lists.
2. **Eighths + scene-number types** (§3.1, §3.2). Cheap now, brutal later.
3. **Production settings**: boilerplate text, walkie channels, hospital list, locations,
   department order, 12h/24h, page size.
4. **Fountain import** → scenes get production ID + parsed heading + story day.
5. **Call sheet export**: page 1 / page 2 PDF, reading from 1–3.
6. **DPR** — reuses everything above.

Do 5 before 1 and it gets written twice.

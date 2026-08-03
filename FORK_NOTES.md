# Fork Notes

This is a personal fork of CineSched, built with AI-assisted coding (Claude Code) 
Everything here is scoped to this fork only.

---

## Why

Started because I wanted a professional call sheet PDF export (mentioned as a known gap).
Getting there required rebuilding the data model first — the original single-scene structure
couldn't represent things a union call sheet needs: non-scene calendar items, multi-day scenes, structured contacts. That groundwork ended up being most of the work
so far; the call sheet export itself is still in progress.

Spec work behind these changes `DOCS/` if useful

---

## What's changed

### Data model
- **Production** as a first-class object (prep for multi-production support — not built yet, scenes just carry a production ID now).
- **Scene numbers** are strings with a natural-sort comparator — supports numbering like `9pt`, `A20`, `B79pt` (partial/split scenes, inserted scenes).
- **Calendar days** hold an ordered list of scenes *and* non-scene items (banners) together — supports things like company moves, prelights, and safety meetings sitting inline with scenes in schedule order
- **Structured contacts** — cast, crew, Director, and Producer can each hold multiple typed contact entries (cell, home, email, emergency, etc.).
- **Crew department field** — adds department groupings, with an explicit "None" default for small crews. Not required.

All of the above includes migration handling for existing saved files

### Calendar / UI
- Toolbar buttons now have SF Symbol icons (fixes labels truncating on narrow windows).
- Fixed layout stacking/disappearing issues at narrow window widths.
- Banner items (company moves, prelights, etc.) can be created, edited, and reordered inline with scenes on the calendar.
- Contacts entry UI for cast/crew/Director/Producer, matching the existing availability-editor popover pattern.
- Cast/crew rows show a primary phone/email at a glance (first Cell / first Email entry) without opening the full contacts editor.

### Exports
- Calendar PDF export: added cast-list, added per-scene time/page count, added banner items, added a color toggle (defaults to black-and-white).
- New standalone **Contact Sheet export** — cast/crew/Director/Producer with primary phone and email, grouped by department for crew, for when you just need a phone list.

---

## Status / what's not done
**Call sheet PDF export** — the original goal. Data model is ready for it; export itself hasn’t been built yet.
- **Union vs. indie contact visibility toggle** — real call sheets differ on whether crew phone/email print at all (union sheets omit it; indie/student sheets include it). Contact storage supports this already; the print-time toggle doesn't exist yet.- **Multi-production UI** — the schema supports it (every scene has a production ID) but there's no UI yet to actually create/switch between productions. Currently everything still lands in one default production.
- **Fountain import** — not started.

---

## Compatibility

Every schema change above includes a migration path for files saved before that change existed. If you pull this fork and open an old project, it should just work — if it doesn't, that's a bug, not expected behavior.

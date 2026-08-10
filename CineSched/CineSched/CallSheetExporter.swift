// CallSheetExporter.swift
// Generates a full two-page call sheet PDF for a single shoot day, matching
// CineSched/DOCS/CALLSHEET_LAYOUT.md's block order/measurements and
// CineSched/DOCS/CALLSHEET_SPEC.md's field inventory — verified against
// CineSched/DOCS/REFERENCE_CALLSHEET.docx, whose measured column widths (in dxa) are what
// the percentages below are actually derived from (they match the spec's rounded figures,
// just with more precision, and — unlike the spec's cast-table figures alone — sum to 100%).
//
// Page 1: title bar, header grid, boilerplate, weather, scene table, cast table, stand-ins.
// Page 2: crew table (three-block grid), department notes, hospital/emergency, advance
// schedule, signature footer — see CALLSHEET_LAYOUT.md §2 blocks 9-14. Paper chase (block 13)
// and Quote of the Day aren't built — not asked for.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - CallSheetExporter

class CallSheetExporter {

    // MARK: Page geometry — A4 portrait, per CALLSHEET_LAYOUT.md §1. REF-A (the primary
    // model) is A4; page size is called out there as a production-level setting rather than
    // a constant, but no such setting exists in the data model yet, so this hardcodes A4
    // rather than defaulting to Letter — Letter would silently contradict the reference this
    // was built against.
    private static let pageWidth:  CGFloat = 595.28   // 210mm
    private static let pageHeight: CGFloat = 841.89   // 297mm
    private static let margin:     CGFloat = 36       // 0.5in
    private static var usableWidth: CGFloat { pageWidth - 2 * margin }

    // MARK: Fonts — small and dense per CALLSHEET_LAYOUT.md §5 ("Type is small — roughly
    // 7-8pt in the tables. Density is the point.")
    private static let fontTitle      = NSFont.boldSystemFont(ofSize: 12)
    private static let fontHeadLabel  = NSFont.boldSystemFont(ofSize: 7)
    private static let fontHeadValue  = NSFont.systemFont(ofSize: 7.5)
    private static let fontHeadBold   = NSFont.boldSystemFont(ofSize: 7.5)
    private static let fontTableHead  = NSFont.boldSystemFont(ofSize: 6.5)
    private static let fontBody       = NSFont.systemFont(ofSize: 7.5)
    private static let fontBodyItalic: NSFont = {
        let base = NSFont.systemFont(ofSize: 7.5)
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }()
    private static let fontBanner     = NSFont.boldSystemFont(ofSize: 8)
    private static let fontBannerNote = NSFont.systemFont(ofSize: 7)

    private static let colorBlack     = NSColor.black
    private static let colorDark      = NSColor(white: 0.12, alpha: 1)
    private static let colorMid       = NSColor(white: 0.4,  alpha: 1)
    private static let colorRule      = NSColor(white: 0.25, alpha: 1)
    private static let colorRuleLight = NSColor(white: 0.7,  alpha: 1)
    private static let colorFill      = NSColor(white: 0.90, alpha: 1)
    private static let colorFillAlt   = NSColor(white: 0.97, alpha: 1)

    /// Used identically for measuring (boundingRect) and drawing (draw(with:)) throughout
    /// this file — see PDFExporter.swift's textLayoutOptions for why that consistency
    /// matters: those two APIs can silently disagree on line-wrapping when given different
    /// option sets, which previously caused real content to be cut off with an ellipsis.
    private static let textLayoutOptions: NSString.DrawingOptions = [
        .usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine
    ]

    // MARK: - Entry point

    static func generatePDF(
        shootDay: ShootDay,
        productionInfo: ProductionInfo,
        projectTitle: String,
        shootDays: [ShootDay]
    ) -> Data? {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        let cursor = PageCursor(ctx: ctx)
        cursor.beginPage()

        let castIDs = castIDLookup(productionInfo: productionInfo)
        let (dayNumber, totalDays) = dayOfDays(for: shootDay, in: shootDays)

        drawTitleBar(cursor: cursor, shootDay: shootDay, productionInfo: productionInfo,
                     projectTitle: projectTitle, dayNumber: dayNumber, totalDays: totalDays)
        drawHeaderGrid(cursor: cursor, shootDay: shootDay, productionInfo: productionInfo,
                       dayNumber: dayNumber, totalDays: totalDays)
        drawBoilerplate(cursor: cursor, productionInfo: productionInfo)
        drawWeatherStrip(cursor: cursor)
        drawSceneTable(cursor: cursor, shootDay: shootDay, castIDs: castIDs)
        drawForcedCallBanner(cursor: cursor)
        drawCastTable(cursor: cursor, shootDay: shootDay, productionInfo: productionInfo, castIDs: castIDs)
        drawStandInsBlock(cursor: cursor)

        // Page 2 always starts on its own page — a call sheet is genuinely front/back, not
        // "whatever fits after page 1," even on a light day where page 1 ends up short.
        cursor.startNewPage()
        // No crew at all yet — omit the crew list title and table entirely rather than
        // printing an empty table with a sentence explaining nobody's been added.
        if !productionInfo.crew.isEmpty {
            drawCrewListTitle(cursor: cursor, shootDay: shootDay, projectTitle: projectTitle,
                               dayNumber: dayNumber, totalDays: totalDays)
            // Two genuinely different layouts, not one grid with a column toggled on/off:
            // contact info needs room for phone AND email per person, which doesn't fit
            // three sub-columns wide, so it gets its own full-width single-column table;
            // without it, the existing side-by-side block grid stays, just 2 blocks instead
            // of 3 so long department names/titles ("ART DEPARTMENT") have room to fit.
            if productionInfo.printCrewContactInfo {
                drawCrewTableSingleColumn(cursor: cursor, productionInfo: productionInfo)
            } else {
                drawCrewTableGrid(cursor: cursor, productionInfo: productionInfo)
            }
        }
        drawDepartmentNotes(cursor: cursor)
        drawHospitalBlock(cursor: cursor, shootDay: shootDay)
        drawAdvanceSchedule(cursor: cursor, shootDay: shootDay, shootDays: shootDays, castIDs: castIDs)
        drawSignatureFooter(cursor: cursor, productionInfo: productionInfo)

        cursor.endPage()
        ctx.closePDF()
        return pdfData as Data
    }

    // MARK: - Day-of-days / cast ID helpers

    /// "DAY 4 OF 18" — position of this day among every day in the schedule that has
    /// anything on it (scenes or banners), not just scenes; a company-move-only day is
    /// still a working day and still deserves its own call sheet.
    private static func dayOfDays(for shootDay: ShootDay, in shootDays: [ShootDay]) -> (Int, Int) {
        let working = shootDays.filter { !$0.items.isEmpty }
        let total = working.count
        if let idx = working.firstIndex(where: { $0.id == shootDay.id }) {
            return (idx + 1, total)
        }
        return (1, max(total, 1))
    }

    /// Cast ID# isn't a persisted field anywhere in the data model — the spec calls for a
    /// small stable per-production number ("the DOOD key"), which CineSched doesn't have
    /// yet. This derives one from each cast member's position in the production's cast
    /// list, which is stable for as long as that list isn't reordered. Good enough to match
    /// the reference's numbering scheme without inventing a new persisted field for a
    /// page-1-only export.
    private static func castIDLookup(productionInfo: ProductionInfo) -> [String: Int] {
        var lookup: [String: Int] = [:]
        for (i, member) in productionInfo.castList.enumerated() {
            let key = member.characterName.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            lookup[key] = i + 1
        }
        return lookup
    }

    private static func castID(for character: String, in lookup: [String: Int]) -> String {
        lookup[character.trimmingCharacters(in: .whitespaces).lowercased()].map(String.init) ?? "?"
    }

    /// Sorts character names by their cast ID# ascending (matching CALLSHEET_SPEC.md §2.4's
    /// own example, "1, 2, 3, 4, 6, 7" — always ascending), rather than the order they
    /// happen to be listed on the scene or CallSheetData.resolvedCast's alphabetical order.
    /// A character with no roster match sorts last, after every numbered one.
    private static func sortedByCastID(_ characters: [String], using lookup: [String: Int]) -> [String] {
        characters.sorted { a, b in
            let ai = lookup[a.trimmingCharacters(in: .whitespaces).lowercased()] ?? Int.max
            let bi = lookup[b.trimmingCharacters(in: .whitespaces).lowercased()] ?? Int.max
            return ai != bi ? ai < bi : a < b
        }
    }

    // MARK: - Block 1: Title bar

    private static func drawTitleBar(
        cursor: PageCursor, shootDay: ShootDay, productionInfo: ProductionInfo,
        projectTitle: String, dayNumber: Int, totalDays: Int
    ) {
        let rowHeight: CGFloat = 26
        cursor.ensureSpace(rowHeight)
        let colWidth = usableWidth / 3
        let rect = CGRect(x: margin, y: cursor.y - rowHeight, width: usableWidth, height: rowHeight)

        let company = productionInfo.companyName.trimmingCharacters(in: .whitespaces).uppercased()
        let title   = (projectTitle.isEmpty ? "Untitled Movie" : projectTitle).uppercased()
        let dayLabel = "CALL SHEET — DAY \(dayNumber) OF \(totalDays)"

        drawGridCells(
            texts: [company, title, dayLabel],
            widths: [colWidth, colWidth, usableWidth - 2 * colWidth],
            font: fontTitle, color: colorBlack, alignment: .center,
            rect: rect, verticalCenter: true
        )
        strokeRect(rect, color: colorRule, width: 0.8)
        cursor.y -= rowHeight
    }

    // MARK: - Block 2: Header grid (3 unequal columns)

    private static func drawHeaderGrid(
        cursor: PageCursor, shootDay: ShootDay, productionInfo: ProductionInfo,
        dayNumber: Int, totalDays: Int
    ) {
        let colAWidth = usableWidth * 0.33
        let colBWidth = usableWidth * 0.34
        let colCWidth = usableWidth - colAWidth - colBWidth

        // Column A — key personnel. No production-office-address field exists in the data
        // model, so this is personnel only (Director/Producer), not the full "office info +
        // personnel" stack the layout doc shows — nothing to placeholder here since the
        // fields genuinely aren't in the model. If neither is set yet, the column is simply
        // left blank rather than explaining that — a blank column reads as "nothing here,"
        // not as the app announcing an unfinished feature.
        var colALines: [NSAttributedString] = []
        if !productionInfo.director.name.isEmpty {
            colALines.append(labelValue("DIRECTOR", productionInfo.director.name))
        }
        if !productionInfo.producer.name.isEmpty {
            colALines.append(labelValue("PRODUCER", productionInfo.producer.name))
        }

        // Column B — date, day-of-days. Land acknowledgment has no field; omitted rather
        // than fabricated.
        let colBLines: [NSAttributedString] = [
            plain(fullFormattedDate(shootDay.date).uppercased(), font: fontHeadBold, color: colorBlack),
            plain("DAY \(dayNumber) OF \(totalDays)", font: fontHeadBold, color: colorBlack)
        ]

        // Column C — call times, location, basecamp, crew park. Each line renders the day's
        // real value once entered in the call sheet editor; "—" is only the fallback for a
        // field that's genuinely still empty, same placeholder convention the weather strip
        // below uses for fields with no data source at all.
        var colCLines: [NSAttributedString] = []
        colCLines.append(labelValue("CREW CALL", shootDay.callSheet.generalCallTime.isEmpty ? "—" : shootDay.callSheet.generalCallTime))
        colCLines.append(labelValue("SHOOTING CALL", shootDay.callSheet.shootingCallTime.isEmpty ? "—" : shootDay.callSheet.shootingCallTime))
        colCLines.append(labelValue("BREAKFAST", shootDay.callSheet.breakfastTime.isEmpty ? "—" : shootDay.callSheet.breakfastTime))
        colCLines.append(labelValue("LUNCH", shootDay.callSheet.lunchTime.isEmpty ? "—" : shootDay.callSheet.lunchTime))
        // Dinner is genuinely optional (most day shoots don't have one) — only shown when set,
        // rather than a permanent "DINNER —" line on every call sheet.
        if !shootDay.callSheet.dinnerTime.isEmpty {
            colCLines.append(labelValue("DINNER", shootDay.callSheet.dinnerTime))
        }
        if shootDay.callSheet.locations.isEmpty {
            colCLines.append(labelValue("LOCATION", "TBD"))
        } else {
            colCLines.append(plain("LOCATION", font: fontHeadLabel, color: colorMid))
            for loc in shootDay.callSheet.locations {
                let name = loc.name.isEmpty ? "Unnamed Location" : loc.name
                colCLines.append(plain(loc.address.isEmpty ? name : "\(name), \(loc.address)",
                                        font: fontHeadValue, color: colorDark))
            }
        }
        colCLines.append(labelValue("BASECAMP", shootDay.callSheet.basecamp.isEmpty ? "—" : shootDay.callSheet.basecamp))
        colCLines.append(labelValue("CREW PARK", shootDay.callSheet.crewPark.isEmpty ? "—" : shootDay.callSheet.crewPark))

        let colAHeight = measureLines(colALines, width: colAWidth - 8)
        let colBHeight = measureLines(colBLines, width: colBWidth - 8)
        let colCHeight = measureLines(colCLines, width: colCWidth - 8)
        let rowHeight = max(colAHeight, colBHeight, colCHeight) + 8

        cursor.ensureSpace(rowHeight)
        let top = cursor.y
        let rect = CGRect(x: margin, y: top - rowHeight, width: usableWidth, height: rowHeight)

        var cx = margin
        for (lines, w) in [(colALines, colAWidth), (colBLines, colBWidth), (colCLines, colCWidth)] {
            let cellRect = CGRect(x: cx, y: top - rowHeight, width: w, height: rowHeight)
            drawLines(lines, in: CGRect(x: cx + 4, y: top - 4 - measureLines(lines, width: w - 8),
                                         width: w - 8, height: measureLines(lines, width: w - 8)))
            strokeRect(cellRect, color: colorRuleLight, width: 0.4)
            cx += w
        }
        strokeRect(rect, color: colorRule, width: 0.8)
        cursor.y -= rowHeight
    }

    // MARK: - Block 3: Boilerplate rules block

    /// Uses the production's own boilerplate text (Production Setup → Boilerplate / Rules)
    /// once it's been filled in; falls back to a generic placeholder — drawn from
    /// CALLSHEET_SPEC.md §2.3's own list of common boilerplate clauses, not anything specific
    /// to a real production — for a production that hasn't set one yet.
    private static func drawBoilerplate(cursor: PageCursor, productionInfo: ProductionInfo) {
        let custom = productionInfo.boilerplateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = custom.isEmpty
            ? "INDIVIDUAL CALL TIMES MAY VARY — PLEASE CHECK YOUR TIMES  •  NO VISITORS ON SET WITHOUT PRODUCER APPROVAL  •  NO PERSONAL PHOTOS OR SOCIAL MEDIA POSTS  •  SMOKE ONLY IN DESIGNATED AREAS — ALWAYS USE A BUTT CAN  •  THIS IS A HARASSMENT-FREE WORKPLACE — REPORT CONCERNS TO PRODUCTION OR AD STAFF"
            : custom.uppercased()
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 1.5
        let attr = NSAttributedString(string: text, attributes: [
            .font: fontHeadValue, .foregroundColor: colorDark, .paragraphStyle: para
        ])
        let h = ceil(attr.boundingRect(with: CGSize(width: usableWidth - 12, height: .greatestFiniteMagnitude),
                                        options: textLayoutOptions).height)
        let rowHeight = h + 10
        cursor.ensureSpace(rowHeight)
        let rect = CGRect(x: margin, y: cursor.y - rowHeight, width: usableWidth, height: rowHeight)
        attr.draw(with: CGRect(x: margin + 6, y: rect.minY + (rowHeight - h) / 2, width: usableWidth - 12, height: h),
                   options: textLayoutOptions)
        strokeRect(rect, color: colorRule, width: 0.8)
        cursor.y -= rowHeight
    }

    // MARK: - Block 4: Weather strip

    /// CineSched doesn't track weather data at all yet, so this block is omitted rather than
    /// printed as a full row of "—" placeholders — a strip of 8 empty columns reads as the
    /// app pointing out something it can't do, where a real lean call sheet just wouldn't
    /// have the block. Once real weather data exists, this can render the actual 8-column
    /// strip (structure already scoped out in CALLSHEET_LAYOUT.md §2 block 4).
    private static func drawWeatherStrip(cursor: PageCursor) {
        // Nothing to draw — see doc comment above.
    }

    // MARK: - Block 5: Scene schedule table

    private struct SceneColumns {
        static let widths: [CGFloat] = {
            // Percentages measured from REFERENCE_CALLSHEET.docx's actual column widths
            // (1319, 5549, 1413, 639, 879, 670 dxa of 10469 total) — they match
            // CALLSHEET_SPEC.md §3.1's rounded figures almost exactly, but sum to exactly
            // 100% where the spec's rounded numbers are only approximate.
            let pct: [CGFloat] = [0.1260, 0.5301, 0.1350, 0.0610, 0.0840, 0.0640]
            return pct.map { $0 * usableWidth }
        }()
        static let titles = ["SCENE", "SET / SCENE DESCRIPTION", "CAST", "D/N", "PAGES", "EST TIME"]
    }

    private static func drawSceneTable(cursor: PageCursor, shootDay: ShootDay, castIDs: [String: Int]) {
        drawTableHeaderRow(cursor: cursor, widths: SceneColumns.widths, titles: SceneColumns.titles)

        for item in shootDay.items {
            switch item {
            case .scene(let scene):
                drawSceneRow(cursor: cursor, scene: scene, castIDs: castIDs)
            case .banner(let banner):
                drawBannerRow(cursor: cursor, banner: banner, totalWidth: SceneColumns.widths.reduce(0, +))
            }
        }

        drawSceneTotalRow(cursor: cursor, shootDay: shootDay)
    }

    private static func drawSceneRow(cursor: PageCursor, scene: Scene, castIDs: [String: Int]) {
        let widths = SceneColumns.widths
        let descWidth = widths[1] - 8

        var descLines: [NSAttributedString] = [
            plain(descriptionHeading(for: scene), font: NSFont.boldSystemFont(ofSize: 7.5), color: colorBlack)
        ]
        let synopsis = scene.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !synopsis.isEmpty {
            descLines.append(plain(synopsis, font: fontBodyItalic, color: colorDark))
        }
        let descHeight = measureLines(descLines, width: descWidth)
        let rowHeight = max(descHeight + 6, 16)

        let didBreak = cursor.ensureSpace(rowHeight)
        if didBreak { drawTableHeaderRow(cursor: cursor, widths: widths, titles: SceneColumns.titles) }

        let top = cursor.y
        let rect = CGRect(x: margin, y: top - rowHeight, width: widths.reduce(0, +), height: rowHeight)

        let castText = sortedByCastID(scene.cast, using: castIDs).map { castID(for: $0, in: castIDs) }.joined(separator: ", ")
        let dn = dayNightLetter(scene.dayNightType)

        var cx = margin
        // SCENE
        drawCentered(scene.sceneNumber.isEmpty ? "—" : scene.sceneNumber, font: fontBody, color: colorBlack,
                     in: CGRect(x: cx, y: top - rowHeight, width: widths[0], height: rowHeight), leftAlign: true)
        cx += widths[0]
        // DESCRIPTION (2 paragraphs)
        drawLines(descLines, in: CGRect(x: cx + 4, y: top - 3 - descHeight, width: descWidth, height: descHeight))
        cx += widths[1]
        // CAST
        drawCentered(castText.isEmpty ? "—" : castText, font: fontBody, color: colorDark,
                     in: CGRect(x: cx, y: top - rowHeight, width: widths[2], height: rowHeight), leftAlign: true)
        cx += widths[2]
        // D/N
        drawCentered(dn, font: fontBody, color: colorDark,
                     in: CGRect(x: cx, y: top - rowHeight, width: widths[3], height: rowHeight))
        cx += widths[3]
        // PAGES
        drawCentered(formattedEighths(scene.duration), font: fontBody, color: colorDark,
                     in: CGRect(x: cx, y: top - rowHeight, width: widths[4], height: rowHeight))
        cx += widths[4]
        // EST TIME
        drawCentered(callSheetTime(scene.estimatedTime), font: fontBody, color: colorDark,
                     in: CGRect(x: cx, y: top - rowHeight, width: widths[5], height: rowHeight))

        drawRowRules(widths: widths, rect: rect)
        cursor.y -= rowHeight
    }

    private static func drawBannerRow(cursor: PageCursor, banner: BannerItem, totalWidth: CGFloat) {
        let label = banner.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let note  = banner.note.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [NSAttributedString] = []
        let labelPara = NSMutableParagraphStyle(); labelPara.alignment = .center
        let labelText = NSMutableAttributedString(
            string: (label.isEmpty ? "ITEM" : label).uppercased(),
            attributes: [.font: fontBanner, .foregroundColor: colorBlack, .paragraphStyle: labelPara]
        )
        // Not every company move or safety meeting takes the same amount of time — this
        // is real per-item data (BannerItem.estimatedTime), not a placeholder, so it needs
        // to show up here rather than only being folded into the table's TOTAL row.
        if banner.estimatedTime > 0 {
            labelText.append(NSAttributedString(
                string: "  (\(callSheetTime(banner.estimatedTime)))",
                attributes: [.font: fontBannerNote, .foregroundColor: colorMid, .paragraphStyle: labelPara]
            ))
        }
        lines.append(labelText)
        if !note.isEmpty {
            let notePara = NSMutableParagraphStyle(); notePara.alignment = .center
            lines.append(NSAttributedString(
                string: note, attributes: [.font: fontBannerNote, .foregroundColor: colorMid, .paragraphStyle: notePara]
            ))
        }
        let contentHeight = measureLines(lines, width: totalWidth - 12)
        let rowHeight = contentHeight + 8

        let didBreak = cursor.ensureSpace(rowHeight)
        if didBreak { drawTableHeaderRow(cursor: cursor, widths: SceneColumns.widths, titles: SceneColumns.titles) }

        let top = cursor.y
        let rect = CGRect(x: margin, y: top - rowHeight, width: totalWidth, height: rowHeight)
        colorFillAlt.setFill()
        NSBezierPath(rect: rect).fill()
        drawLines(lines, in: CGRect(x: margin + 6, y: top - 4 - contentHeight, width: totalWidth - 12, height: contentHeight))
        strokeRect(rect, color: colorRuleLight, width: 0.5)
        cursor.y -= rowHeight
    }

    private static func drawSceneTotalRow(cursor: PageCursor, shootDay: ShootDay) {
        let widths = SceneColumns.widths
        let rowHeight: CGFloat = 16
        cursor.ensureSpace(rowHeight)
        let top = cursor.y
        let mergedWidth = widths[0] + widths[1] + widths[2] + widths[3]
        let rect = CGRect(x: margin, y: top - rowHeight, width: widths.reduce(0, +), height: rowHeight)

        var cx = margin
        drawRightAligned("TOTAL", font: NSFont.boldSystemFont(ofSize: 7.5), color: colorBlack,
                          in: CGRect(x: cx, y: top - rowHeight, width: mergedWidth - 6, height: rowHeight))
        cx += mergedWidth
        drawCentered(formattedEighths(shootDay.totalDuration), font: NSFont.boldSystemFont(ofSize: 7.5), color: colorBlack,
                     in: CGRect(x: cx, y: top - rowHeight, width: widths[4], height: rowHeight))
        cx += widths[4]
        drawCentered(callSheetTime(shootDay.totalEstimatedTime), font: NSFont.boldSystemFont(ofSize: 7.5), color: colorBlack,
                     in: CGRect(x: cx, y: top - rowHeight, width: widths[5], height: rowHeight))

        strokeRect(rect, color: colorRule, width: 0.8)
        strokeLine(from: CGPoint(x: margin + mergedWidth, y: top), to: CGPoint(x: margin + mergedWidth, y: top - rowHeight), color: colorRuleLight, width: 0.4)
        strokeLine(from: CGPoint(x: margin + mergedWidth + widths[4], y: top), to: CGPoint(x: margin + mergedWidth + widths[4], y: top - rowHeight), color: colorRuleLight, width: 0.4)
        cursor.y -= rowHeight
    }

    // MARK: - Block 6: Forced-call warning banner

    /// Same placeholder rationale as the boilerplate block — no per-production field for
    /// this exists yet, so this draws the exact conventional line from CALLSHEET_SPEC.md
    /// §2.3's own clause list, asterisk-wrapped and centered per CALLSHEET_LAYOUT.md §2.
    private static func drawForcedCallBanner(cursor: PageCursor) {
        let text = "*** NO FORCED CALLS, PRE-CALLS, UPGRADES OR MEAL PENALTY WITHOUT PRIOR APPROVAL FROM THE UPM ***"
        let rowHeight: CGFloat = 16
        cursor.ensureSpace(rowHeight)
        let rect = CGRect(x: margin, y: cursor.y - rowHeight, width: usableWidth, height: rowHeight)
        drawCentered(text, font: NSFont.boldSystemFont(ofSize: 7.5), color: colorBlack, in: rect)
        strokeRect(rect, color: colorRule, width: 0.8)
        cursor.y -= rowHeight
    }

    // MARK: - Block 7: Cast table

    private struct CastColumns {
        static let widths: [CGFloat] = {
            // Percentages measured from REFERENCE_CALLSHEET.docx (584, 2073, 2322, 751, 751,
            // 774, 882, 727, 1605 dxa of 10469) — used over CALLSHEET_SPEC.md §4.1's listed
            // figures because those only sum to ~88%; the docx's sum to exactly 100%.
            let pct: [CGFloat] = [0.0558, 0.1980, 0.2218, 0.0717, 0.0717, 0.0739, 0.0843, 0.0695, 0.1533]
            return pct.map { $0 * usableWidth }
        }()
        static let titles = ["ID#", "CAST", "CHARACTER", "S/W/F", "P/U", "H/M/W", "BLOCK", "SET", "NOTES"]
    }

    private static func drawCastTable(
        cursor: PageCursor, shootDay: ShootDay, productionInfo: ProductionInfo, castIDs: [String: Int]
    ) {
        let widths = CastColumns.widths
        drawTableHeaderRow(cursor: cursor, widths: widths, titles: CastColumns.titles)

        let characters = sortedByCastID(shootDay.callSheet.resolvedCast(from: shootDay.scenes), using: castIDs)
        if characters.isEmpty {
            drawCastEmptyRow(cursor: cursor, totalWidth: widths.reduce(0, +))
        } else {
            for character in characters {
                drawCastRow(cursor: cursor, character: character, productionInfo: productionInfo, castIDs: castIDs)
            }
        }

        // "** ALL CALLS SUBJECT TO CHANGE AT WRAP **" — same fixed-convention treatment as
        // the boilerplate/forced-call banners; CALLSHEET_SPEC.md §2.5 lists this exact line.
        drawCastBanner(cursor: cursor, text: "** ALL CALLS SUBJECT TO CHANGE AT WRAP **", totalWidth: widths.reduce(0, +))
    }

    private static func drawCastRow(
        cursor: PageCursor, character: String, productionInfo: ProductionInfo, castIDs: [String: Int]
    ) {
        let widths = CastColumns.widths
        let rowHeight: CGFloat = 14
        cursor.ensureSpace(rowHeight)
        let top = cursor.y
        let rect = CGRect(x: margin, y: top - rowHeight, width: widths.reduce(0, +), height: rowHeight)

        let match = productionInfo.castList.first {
            $0.characterName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(character.trimmingCharacters(in: .whitespaces)) == .orderedSame
        }
        let id     = castID(for: character, in: castIDs)
        let actor  = match?.actorName.isEmpty == false ? match!.actorName : "—"
        // Status (S/W/F), pickup, H/M/W call, block, set call, and notes have no scheduling
        // data source in the model yet (CastMember has no per-day call times) — "-" is the
        // spec's own convention for "not applicable to this person," which is accurate here:
        // every cell in these columns is currently untrackable, not merely blank.
        let values = [id, actor.uppercased(), character.uppercased(), "-", "-", "-", "-", "-", "-"]

        var cx = margin
        for (i, value) in values.enumerated() {
            let leftAlign = (i == 1 || i == 2 || i == 8) // CAST, CHARACTER, NOTES read left-aligned
            drawCentered(value, font: fontBody, color: colorDark,
                         in: CGRect(x: cx, y: top - rowHeight, width: widths[i], height: rowHeight), leftAlign: leftAlign)
            cx += widths[i]
        }
        drawRowRules(widths: widths, rect: rect)
        cursor.y -= rowHeight
    }

    private static func drawCastEmptyRow(cursor: PageCursor, totalWidth: CGFloat) {
        let rowHeight: CGFloat = 14
        cursor.ensureSpace(rowHeight)
        let rect = CGRect(x: margin, y: cursor.y - rowHeight, width: totalWidth, height: rowHeight)
        drawCentered("No cast assigned to scenes on this day.", font: fontBody, color: colorMid, in: rect)
        strokeRect(rect, color: colorRuleLight, width: 0.4)
        cursor.y -= rowHeight
    }

    private static func drawCastBanner(cursor: PageCursor, text: String, totalWidth: CGFloat) {
        let rowHeight: CGFloat = 14
        cursor.ensureSpace(rowHeight)
        let rect = CGRect(x: margin, y: cursor.y - rowHeight, width: totalWidth, height: rowHeight)
        colorFillAlt.setFill()
        NSBezierPath(rect: rect).fill()
        drawCentered(text, font: NSFont.boldSystemFont(ofSize: 7.5), color: colorBlack, in: rect)
        strokeRect(rect, color: colorRule, width: 0.6)
        cursor.y -= rowHeight
    }

    // MARK: - Block 8: Stand-ins / background

    /// No data source exists for stand-ins/photo doubles/background yet — omitted entirely
    /// rather than printing the 6-column CALLSHEET_LAYOUT.md §4.2 structure with a sentence
    /// explaining it's empty. A real call sheet with nothing to say here just doesn't have
    /// the block; once real data exists, this can render the actual table.
    private static func drawStandInsBlock(cursor: PageCursor) {
        // Nothing to draw — see doc comment above.
    }

    // MARK: - Page 2, Block 9: Crew list title

    private static func drawCrewListTitle(
        cursor: PageCursor, shootDay: ShootDay, projectTitle: String, dayNumber: Int, totalDays: Int
    ) {
        let title = (projectTitle.isEmpty ? "Untitled Movie" : projectTitle).uppercased()
        let text = "\(title)  —  CREW LIST  —  \(fullFormattedDate(shootDay.date).uppercased())  —  DAY \(dayNumber) OF \(totalDays)"
        let rowHeight: CGFloat = 16
        cursor.ensureSpace(rowHeight)
        let rect = CGRect(x: margin, y: cursor.y - rowHeight, width: usableWidth, height: rowHeight)
        colorFill.setFill()
        NSBezierPath(rect: rect).fill()
        drawCentered(text, font: NSFont.boldSystemFont(ofSize: 8), color: colorBlack, in: rect)
        strokeRect(rect, color: colorRule, width: 0.8)
        cursor.y -= rowHeight
    }

    // MARK: - Page 2, Block 9: Crew table — the three-block grid

    private struct CrewGridColumns {
        static let titles = ["#", "TITLE", "NAME", "CALL"]

        /// # / TITLE / NAME / CALL widths for ONE block, sized so `blockCount` blocks span
        /// the full page — relative proportions between the four sub-columns are preserved
        /// from the original measurement (REFERENCE_CALLSHEET.docx: 419/1152/1221/698 dxa of
        /// 10469, a block that was 1 of 3), only each block's total share of the page
        /// changes. Parameterized per CALLSHEET_LAYOUT.md §4.3's own note that the balancing
        /// approach — and so the block count — shouldn't be hardcoded (REF-K uses 2 blocks).
        static func widths(blockCount: Int) -> [CGFloat] {
            let basePct: [CGFloat] = [0.0400, 0.1100, 0.1167, 0.0667]   // sums to ~1/3 (one of 3 blocks)
            let scale = (1.0 / CGFloat(blockCount)) / basePct.reduce(0, +)
            return basePct.map { $0 * scale * usableWidth }
        }
    }

    private enum CrewGridRow {
        case header(DepartmentKind)
        case member(CrewMember)
    }

    /// Side-by-side block grid — used when "Print crew contact info" is OFF. Departments
    /// flow down each block, then to the next block — not left to right — per
    /// CALLSHEET_LAYOUT.md §4.3. No call-time-per-crew-member field exists in the data model
    /// yet, so the CALL column is "—" throughout, same placeholder convention page 1 already
    /// uses. The headcount flag (0/1, "not a quantity") also has no source field; every row
    /// here shows "1" as the reasonable default (everyone listed is presumed meal-counted
    /// unless told otherwise) — but that default is never summed into a real meal-count
    /// total below, since presenting a synthetic sum as a real headcount would be worse than
    /// not showing one at all.
    private static func drawCrewTableGrid(cursor: PageCursor, productionInfo: ProductionInfo) {
        // 2 blocks (not 3): with no contact info competing for room, this is still a fairly
        // dense grid, and 2 blocks at ~50% each gives long department names ("ART
        // DEPARTMENT") and long crew names room to fit without wrapping under normal
        // circumstances, where 3 blocks at ~33% forced them to.
        let blockCount = 2
        let blockWidths = CrewGridColumns.widths(blockCount: blockCount)
        let blockTitles = CrewGridColumns.titles
        let allWidths = Array(repeating: blockWidths, count: blockCount).flatMap { $0 }
        let allTitles = Array(repeating: blockTitles, count: blockCount).flatMap { $0 }

        drawTableHeaderRow(cursor: cursor, widths: allWidths, titles: allTitles)

        // Grouped/sorted exactly the way ContactSheetExporter.swift already groups the same
        // roster for its own crew section — Department.sortIndex (traditional call-sheet
        // department order; "Other" then "None" sort last, never interleaved with named
        // departments) — reused rather than redefined here.
        let grouped = Dictionary(grouping: productionInfo.crew) { $0.department.kind }
        let departments: [(kind: DepartmentKind, members: [CrewMember])] = grouped
            .map { kind, members in
                (kind: kind, members: members.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
            .filter { !$0.members.isEmpty }
            .sorted { $0.kind.sortIndex < $1.kind.sortIndex }

        // Defensive: generatePDF only calls this when productionInfo.crew is non-empty, so
        // departments can't actually be empty here — but if this is ever called directly,
        // do nothing rather than print an empty table.
        guard !departments.isEmpty else { return }

        // Each department becomes one block of rows (a header row + one row per member) that
        // must never be split across two columns — CALLSHEET_LAYOUT.md §4.3: "compute the
        // full ordered department list with its rows, then balance into three columns by
        // total row height. Do not hand-assign departments to blocks."
        let departmentBlocks: [[CrewGridRow]] = departments.map { kind, members in
            [CrewGridRow.header(kind)] + members.map { CrewGridRow.member($0) }
        }
        let columns = balanceIntoColumns(departmentBlocks, columnCount: blockCount)

        let totalRows = columns.map { $0.count }.max() ?? 0
        for rowIndex in 0..<totalRows {
            drawCrewGridRowBand(cursor: cursor, columns: columns, rowIndex: rowIndex,
                                 blockWidths: blockWidths, blockTitles: blockTitles)
        }

        drawCrewMealCountRow(cursor: cursor, totalWidth: allWidths.reduce(0, +))
    }

    /// Greedy longest-processing-time-first bin packing: largest department blocks placed
    /// first, each into whichever column currently has the fewest rows so far — keeps the
    /// columns close to even without ever splitting one department's rows across two of
    /// them. `columnCount` is a parameter (not hardcoded) per CALLSHEET_LAYOUT.md §4.3's own
    /// note that REF-K uses 2 blocks instead of 3.
    private static func balanceIntoColumns(_ blocks: [[CrewGridRow]], columnCount: Int) -> [[CrewGridRow]] {
        var columns: [[CrewGridRow]] = Array(repeating: [], count: columnCount)
        for block in blocks.sorted(by: { $0.count > $1.count }) {
            let shortest = columns.indices.min { columns[$0].count < columns[$1].count }!
            columns[shortest].append(contentsOf: block)
        }
        return columns
    }

    /// One block's drawable cells for a row-band slot: either a member's 4 columns, a
    /// department header (name merged across TITLE+NAME), or blank cells when this column
    /// has already run out of content at this row index. Widths carry through so the whole
    /// band's height can be measured before anything is drawn. This grid never shows contact
    /// info — that's the single-column layout's job (drawCrewTableSingleColumn) — so it's
    /// always just #/TITLE/NAME/CALL.
    private static func crewBlockCells(row: CrewGridRow?, widths: [CGFloat]) -> [(text: NSAttributedString, width: CGFloat)] {
        func aligned(_ text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment) -> NSAttributedString {
            let para = NSMutableParagraphStyle(); para.alignment = alignment
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        }
        guard let row else {
            return widths.map { (NSAttributedString(string: ""), $0) }
        }
        switch row {
        case .header(let kind):
            // "#" stays blank (a department header isn't itself a headcount-flagged person);
            // CALL-column position would hold an optional walkie channel in the reference —
            // no such field exists in the model, so it's left blank rather than fabricated.
            return [
                (NSAttributedString(string: ""), widths[0]),
                (aligned(kind.displayName.uppercased(), font: NSFont.boldSystemFont(ofSize: 6.5), color: colorDark, alignment: .left),
                 widths[1] + widths[2]),
                (NSAttributedString(string: ""), widths[3])
            ]
        case .member(let member):
            let idCell    = aligned("1", font: fontBody, color: colorDark, alignment: .center)
            let titleCell = aligned(member.role.isEmpty ? "—" : member.role.uppercased(), font: fontBody, color: colorDark, alignment: .left)
            let nameCell  = aligned(member.name.uppercased(), font: fontBody, color: colorDark, alignment: .left)
            let callCell  = aligned("—", font: fontBody, color: colorDark, alignment: .center)
            return [(idCell, widths[0]), (titleCell, widths[1]), (nameCell, widths[2]), (callCell, widths[3])]
        }
    }

    /// Draws one row-band across all blocks simultaneously (so a page break happens at the
    /// same row for every block, keeping their shared horizontal rules aligned) — a block
    /// that's already run out of rows for this band just renders blank cells with the same
    /// grid lines, rather than leaving a gap.
    ///
    /// The row-band's height is measured from its actual content (same textLayoutOptions +
    /// 1.15x buffer as drawTableHeaderRow) rather than a fixed 12pt — a long crew name (e.g.
    /// a two-word name that doesn't fit the narrow NAME column) wraps to a second line
    /// instead of losing the rest of it to drawCentered's single-line truncation, which is
    /// exactly what happened here before this fix ("Mother Fucker" → "Mother Fu…").
    private static func drawCrewGridRowBand(
        cursor: PageCursor, columns: [[CrewGridRow]], rowIndex: Int, blockWidths: [CGFloat], blockTitles: [String]
    ) {
        let blockCellSets: [[(text: NSAttributedString, width: CGFloat)]] = columns.map { column in
            crewBlockCells(row: rowIndex < column.count ? column[rowIndex] : nil, widths: blockWidths)
        }
        let allCells = blockCellSets.flatMap { $0 }
        let rowHeight = max(measureCellRow(allCells), 9) + 4

        let didBreak = cursor.ensureSpace(rowHeight)
        if didBreak {
            let allWidths = Array(repeating: blockWidths, count: columns.count).flatMap { $0 }
            let allTitles = Array(repeating: blockTitles, count: columns.count).flatMap { $0 }
            drawTableHeaderRow(cursor: cursor, widths: allWidths, titles: allTitles)
        }

        let top = cursor.y
        let blockTotalWidth = blockWidths.reduce(0, +)
        var cx = margin
        for (blockIndex, column) in columns.enumerated() {
            let blockRect = CGRect(x: cx, y: top - rowHeight, width: blockTotalWidth, height: rowHeight)
            if rowIndex < column.count, case .header = column[rowIndex] {
                colorFill.setFill()
                NSBezierPath(rect: blockRect).fill()
            }
            drawCellRow(blockCellSets[blockIndex], x: cx, y: top, height: rowHeight)
            drawRowRules(widths: blockWidths, rect: blockRect)
            cx += blockTotalWidth
        }
        cursor.y -= rowHeight
    }

    // MARK: - Page 2, Block 9: Crew table — single-column layout (contact info shown)

    private struct CrewContactColumns {
        // TITLE | NAME | PHONE | EMAIL | CALL, one full-width column — sized generously so
        // phone/email don't need to wrap under normal circumstances (not measured from the
        // reference doc, which has no contact-info variant of this table; Email gets the
        // most room since addresses are typically the longest field).
        static let widths: [CGFloat] = {
            let pct: [CGFloat] = [0.14, 0.18, 0.15, 0.38, 0.15]
            return pct.map { $0 * usableWidth }
        }()
        static let titles = ["TITLE", "NAME", "PHONE", "EMAIL", "CALL"]
    }

    /// Single full-width column — used when "Print crew contact info" is ON. No side-by-side
    /// blocks at all: departments stack vertically, each with its own header row followed by
    /// its members, since a 3-sub-column-wide block has nowhere near enough room for a phone
    /// number AND an email address per person. No "#" headcount column here (not part of the
    /// 5 fields this layout is scoped to: Title/Name/Phone/Email/Call).
    private static func drawCrewTableSingleColumn(cursor: PageCursor, productionInfo: ProductionInfo) {
        let widths = CrewContactColumns.widths
        let titles = CrewContactColumns.titles

        drawTableHeaderRow(cursor: cursor, widths: widths, titles: titles)

        let grouped = Dictionary(grouping: productionInfo.crew) { $0.department.kind }
        let departments: [(kind: DepartmentKind, members: [CrewMember])] = grouped
            .map { kind, members in
                (kind: kind, members: members.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
            .filter { !$0.members.isEmpty }
            .sorted { $0.kind.sortIndex < $1.kind.sortIndex }

        // Defensive: generatePDF only calls this when productionInfo.crew is non-empty.
        guard !departments.isEmpty else { return }

        for (kind, members) in departments {
            drawCrewContactDepartmentHeader(cursor: cursor, kind: kind, widths: widths, titles: titles)
            for member in members {
                drawCrewContactRow(cursor: cursor, member: member, widths: widths, titles: titles)
            }
        }

        drawCrewMealCountRow(cursor: cursor, totalWidth: widths.reduce(0, +))
    }

    private static func drawCrewContactDepartmentHeader(
        cursor: PageCursor, kind: DepartmentKind, widths: [CGFloat], titles: [String]
    ) {
        let rowHeight: CGFloat = 14
        let didBreak = cursor.ensureSpace(rowHeight)
        if didBreak { drawTableHeaderRow(cursor: cursor, widths: widths, titles: titles) }

        let top = cursor.y
        let totalWidth = widths.reduce(0, +)
        let rect = CGRect(x: margin, y: top - rowHeight, width: totalWidth, height: rowHeight)
        colorFill.setFill()
        NSBezierPath(rect: rect).fill()
        drawCentered(kind.displayName.uppercased(), font: NSFont.boldSystemFont(ofSize: 7), color: colorDark,
                     in: rect, leftAlign: true)
        strokeRect(rect, color: colorRuleLight, width: 0.4)
        cursor.y -= rowHeight
    }

    private static func drawCrewContactRow(
        cursor: PageCursor, member: CrewMember, widths: [CGFloat], titles: [String]
    ) {
        func aligned(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
            let para = NSMutableParagraphStyle(); para.alignment = .left
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        }
        let cells: [(text: NSAttributedString, width: CGFloat)] = [
            (aligned(member.role.isEmpty ? "—" : member.role.uppercased(), font: fontBody, color: colorDark), widths[0]),
            (aligned(member.name.uppercased(), font: fontBody, color: colorDark), widths[1]),
            (aligned(member.primaryPhone ?? "—", font: fontBody, color: colorDark), widths[2]),
            (aligned(member.primaryEmail ?? "—", font: fontBody, color: colorDark), widths[3]),
            (aligned("—", font: fontBody, color: colorDark), widths[4])
        ]
        let rowHeight = max(measureCellRow(cells), 9) + 4

        let didBreak = cursor.ensureSpace(rowHeight)
        if didBreak { drawTableHeaderRow(cursor: cursor, widths: widths, titles: titles) }

        let top = cursor.y
        let rect = CGRect(x: margin, y: top - rowHeight, width: widths.reduce(0, +), height: rowHeight)
        drawCellRow(cells, x: margin, y: top, height: rowHeight)
        drawRowRules(widths: widths, rect: rect)
        cursor.y -= rowHeight
    }

    /// Shared measuring helper: the tallest wrapped cell in a row, across arbitrary
    /// (text, width) pairs — same math drawTableHeaderRow uses for its own header cells.
    private static func measureCellRow(_ cells: [(text: NSAttributedString, width: CGFloat)]) -> CGFloat {
        cells.map { cell in
            ceil(cell.text.boundingRect(with: CGSize(width: max(cell.width - 4, 1), height: .greatestFiniteMagnitude),
                                         options: textLayoutOptions).height * 1.15)
        }.max() ?? 0
    }

    /// Draws a row of independently-positioned cells, each measured+drawn with the same
    /// 1.15x buffer used everywhere else in this file — shared by the crew grid and the
    /// single-column contact rows so the "measure and draw must agree" fix (see
    /// drawCrewGridRowBand's history: a crew member's name/contact line was losing its last
    /// line to truncatesLastVisibleLine when this used the raw, unbuffered height) only has
    /// to live in one place.
    private static func drawCellRow(_ cells: [(text: NSAttributedString, width: CGFloat)], x: CGFloat, y: CGFloat, height: CGFloat) {
        var cx = x
        for cell in cells {
            let h = ceil(cell.text.boundingRect(with: CGSize(width: max(cell.width - 4, 1), height: .greatestFiniteMagnitude),
                                                 options: textLayoutOptions).height * 1.15)
            cell.text.draw(with: CGRect(x: cx + 2, y: y - height + (height - h) / 2, width: cell.width - 4, height: h),
                            options: textLayoutOptions)
            cx += cell.width
        }
    }

    /// Meal counts (CALLSHEET_SPEC.md §2.8: "Crew Breakfast x60, BG Lunch x0") are computed
    /// from the headcount flag's real 0/1 values in a real call sheet — since that flag has
    /// no data source here, this placeholders the counts rather than summing the "1" default
    /// shown per-row above and presenting a made-up total as if it were real.
    private static func drawCrewMealCountRow(cursor: PageCursor, totalWidth: CGFloat) {
        let rowHeight: CGFloat = 14
        cursor.ensureSpace(rowHeight)
        let rect = CGRect(x: margin, y: cursor.y - rowHeight, width: totalWidth, height: rowHeight)
        drawCentered("CREW BREAKFAST —   •   CREW LUNCH —   •   BG LUNCH —",
                     font: NSFont.boldSystemFont(ofSize: 7), color: colorDark, in: rect)
        strokeRect(rect, color: colorRule, width: 0.6)
        cursor.y -= rowHeight
    }

    // MARK: - Page 2, Block 10: Department notes

    /// Scene-keyed notes grouped by department (CALLSHEET_SPEC.md §2.7) have no data source
    /// yet — no per-scene department-notes field exists — so this is omitted entirely rather
    /// than printed as an empty placeholder block. Once a per-scene department-notes field
    /// exists, this can aggregate and render the real table.
    private static func drawDepartmentNotes(cursor: PageCursor) {
        // Nothing to draw — see doc comment above.
    }

    // MARK: - Page 2, Block 11: Nearest hospital + emergency

    /// EMERGENCY: 911 always renders — genuinely universal, not something that depends on
    /// CineSched tracking anything. The "nearest hospital" section only appears once the
    /// day's hospital list has real entries; when it's empty, the block collapses to a
    /// single "EMERGENCY: 911" line rather than a hospital section explaining that it isn't
    /// tracked. Set medic / production safety contacts have no data source at all yet, so
    /// that line is simply left out rather than explained either way.
    private static func drawHospitalBlock(cursor: PageCursor, shootDay: ShootDay) {
        let hospitals = shootDay.callSheet.hospitals

        guard !hospitals.isEmpty else {
            let rowHeight: CGFloat = 16
            cursor.ensureSpace(rowHeight)
            let rect = CGRect(x: margin, y: cursor.y - rowHeight, width: usableWidth, height: rowHeight)
            drawCentered("EMERGENCY: 911", font: NSFont.boldSystemFont(ofSize: 8), color: colorBlack, in: rect)
            strokeRect(rect, color: colorRule, width: 0.8)
            cursor.y -= rowHeight
            return
        }

        let colWidth = usableWidth / 2
        let widths = [colWidth, usableWidth - colWidth]

        var hospitalLines: [NSAttributedString] = [plain("NEAREST HOSPITAL", font: NSFont.boldSystemFont(ofSize: 7.5), color: colorBlack)]
        for hospital in hospitals {
            let name = hospital.name.isEmpty ? "Unnamed Hospital" : hospital.name
            hospitalLines.append(plain(name, font: fontHeadValue, color: colorDark))
            let detail = [hospital.address, hospital.phone].filter { !$0.isEmpty }.joined(separator: "   —   ")
            if !detail.isEmpty {
                hospitalLines.append(plain(detail, font: fontHeadValue, color: colorMid))
            }
        }
        let emergencyLines: [NSAttributedString] = [
            plain("EMERGENCY: 911", font: NSFont.boldSystemFont(ofSize: 7.5), color: colorBlack)
        ]

        let cellLines = [hospitalLines, emergencyLines]
        let rowHeight = zip(cellLines, widths).map { measureLines($0, width: $1 - 12) }.max()! + 10

        cursor.ensureSpace(rowHeight)
        let top = cursor.y
        var cx = margin
        for (lines, w) in zip(cellLines, widths) {
            let cellRect = CGRect(x: cx, y: top - rowHeight, width: w, height: rowHeight)
            let h = measureLines(lines, width: w - 12)
            drawLines(lines, in: CGRect(x: cx + 6, y: top - 5 - h, width: w - 12, height: h))
            strokeRect(cellRect, color: colorRuleLight, width: 0.4)
            cx += w
        }
        strokeRect(CGRect(x: margin, y: top - rowHeight, width: usableWidth, height: rowHeight), color: colorRule, width: 0.8)
        cursor.y -= rowHeight
    }

    // MARK: - Page 2, Block 12: Advance schedule

    /// Reuses drawSceneTable (header, scene/banner rows, totals) directly for each upcoming
    /// day, rather than a second copy of that rendering logic — CALLSHEET_SPEC.md §2.9: same
    /// scene-table columns + totals as page 1. Up to the next 2 working days after this one.
    private static func drawAdvanceSchedule(
        cursor: PageCursor, shootDay: ShootDay, shootDays: [ShootDay], castIDs: [String: Int]
    ) {
        let upcoming = shootDays
            .filter { !$0.items.isEmpty && $0.date > shootDay.date }
            .sorted { $0.date < $1.date }
            .prefix(2)

        guard !upcoming.isEmpty else {
            let rowHeight: CGFloat = 16
            cursor.ensureSpace(rowHeight)
            let rect = CGRect(x: margin, y: cursor.y - rowHeight, width: usableWidth, height: rowHeight)
            drawCentered("ADVANCE SCHEDULE — no further shoot days scheduled.",
                         font: NSFont.boldSystemFont(ofSize: 7.5), color: colorMid, in: rect)
            strokeRect(rect, color: colorRuleLight, width: 0.4)
            cursor.y -= rowHeight
            return
        }

        for day in upcoming {
            let (dayNumber, totalDays) = dayOfDays(for: day, in: shootDays)
            let label = "ADVANCE SCHEDULE — DAY \(dayNumber) OF \(totalDays) — \(fullFormattedDate(day.date).uppercased())"
            let rowHeight: CGFloat = 16
            cursor.ensureSpace(rowHeight)
            let rect = CGRect(x: margin, y: cursor.y - rowHeight, width: usableWidth, height: rowHeight)
            colorFillAlt.setFill()
            NSBezierPath(rect: rect).fill()
            drawCentered(label, font: NSFont.boldSystemFont(ofSize: 7.5), color: colorBlack, in: rect)
            strokeRect(rect, color: colorRule, width: 0.6)
            cursor.y -= rowHeight

            drawSceneTable(cursor: cursor, shootDay: day, castIDs: castIDs)
        }
    }

    // MARK: - Page 2, Block 13: Signature footer

    /// Name + phone for key roles (CALLSHEET_SPEC.md §2.10). Director/Producer come straight
    /// from ProductionInfo's structured KeyContact fields; 1st/2nd AD have no dedicated
    /// fields, so they're matched by searching crew role text for common aliases — a role
    /// with no match still gets its own slot with "—", rather than being dropped, so the
    /// footer's shape doesn't shift day to day. Line Producer/UPM/Location Manager/etc. from
    /// the spec's full list have no data source at all (not even a role-text guess would be
    /// reliable) and are left out rather than guessed.
    private static func drawSignatureFooter(cursor: PageCursor, productionInfo: ProductionInfo) {
        struct Entry { let name: String; let role: String; let phone: String }

        var entries: [Entry] = [
            Entry(name: productionInfo.director.name.isEmpty ? "—" : productionInfo.director.name,
                  role: "DIRECTOR", phone: productionInfo.director.primaryPhone ?? "—"),
            Entry(name: productionInfo.producer.name.isEmpty ? "—" : productionInfo.producer.name,
                  role: "PRODUCER", phone: productionInfo.producer.primaryPhone ?? "—")
        ]

        let adRoles: [(label: String, aliases: [String])] = [
            ("1ST AD", ["1st ad", "first ad", "1st assistant director"]),
            ("2ND AD", ["2nd ad", "second ad", "2nd assistant director"])
        ]
        for (label, aliases) in adRoles {
            let match = productionInfo.crew.first { member in
                aliases.contains { member.role.lowercased().contains($0) }
            }
            entries.append(Entry(name: (match?.name.isEmpty == false) ? match!.name : "—",
                                  role: label, phone: match?.primaryPhone ?? "—"))
        }

        let colWidth = usableWidth / CGFloat(entries.count)
        let cellLines: [[NSAttributedString]] = entries.map { entry in
            [plain(entry.name.uppercased(), font: NSFont.boldSystemFont(ofSize: 7.5), color: colorBlack),
             plain(entry.role, font: fontHeadLabel, color: colorMid),
             plain(entry.phone, font: fontHeadValue, color: colorDark)]
        }
        let rowHeight = (cellLines.map { measureLines($0, width: colWidth - 8) }.max() ?? 0) + 10

        cursor.ensureSpace(rowHeight)
        let top = cursor.y
        var cx = margin
        for lines in cellLines {
            let cellRect = CGRect(x: cx, y: top - rowHeight, width: colWidth, height: rowHeight)
            let h = measureLines(lines, width: colWidth - 8)
            drawLines(lines, in: CGRect(x: cx + 4, y: top - (rowHeight - h) / 2 - h, width: colWidth - 8, height: h))
            strokeRect(cellRect, color: colorRuleLight, width: 0.4)
            cx += colWidth
        }
        strokeRect(CGRect(x: margin, y: top - rowHeight, width: usableWidth, height: rowHeight), color: colorRule, width: 0.8)
        cursor.y -= rowHeight
    }

    // MARK: - Scene text helpers

    /// Strips a leading "12. " scene-number prefix from the title (already shown in its own
    /// column) so the description cell doesn't repeat it — common when a scene's title was
    /// typed or imported as "12. INT. HOUSE - DAY".
    private static func descriptionHeading(for scene: Scene) -> String {
        var t = scene.title.trimmingCharacters(in: .whitespaces)
        if !scene.sceneNumber.isEmpty {
            let prefix = "\(scene.sceneNumber). "
            if t.hasPrefix(prefix) { t.removeFirst(prefix.count) }
        }
        return t.uppercased()
    }

    private static func dayNightLetter(_ type: DayNightType) -> String {
        switch type {
        case .day:    return "D"
        case .night:  return "N"
        case .custom: return "C"
        }
    }

    /// Call-sheet convention time format (":45", "1:45", "5:40") — distinct from the app's
    /// own formattedTime ("1 hr 45 min"), which is right for on-screen UI but not what a
    /// printed call sheet's EST TIME column uses.
    private static func callSheetTime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return String(format: ":%02d", m) }
        return String(format: "%d:%02d", h, m)
    }

    private static func fullFormattedDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d, yyyy"; return f.string(from: date)
    }

    // MARK: - Low-level text/line helpers

    private static func plain(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    /// "LABEL   value" on one line — the header grid's most common line shape.
    private static func labelValue(_ label: String, _ value: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "\(label)  ", attributes: [
            .font: fontHeadLabel, .foregroundColor: colorMid
        ])
        result.append(NSAttributedString(string: value.isEmpty ? "—" : value, attributes: [
            .font: fontHeadValue, .foregroundColor: colorDark
        ]))
        return result
    }

    private static func lineGap(_ font: NSFont) -> CGFloat { 1 }

    private static func measureLines(_ lines: [NSAttributedString], width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return lines.reduce(0) { total, line in
            let h = ceil(line.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                            options: textLayoutOptions).height)
            return total + h + 1
        }
    }

    private static func drawLines(_ lines: [NSAttributedString], in rect: CGRect) {
        var y = rect.maxY
        for line in lines {
            let h = ceil(line.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                                            options: textLayoutOptions).height)
            line.draw(with: CGRect(x: rect.minX, y: y - h, width: rect.width, height: h), options: textLayoutOptions)
            y -= h + 1
        }
    }

    private static func drawGridCells(
        texts: [String], widths: [CGFloat], font: NSFont, color: NSColor,
        alignment: NSTextAlignment, rect: CGRect, verticalCenter: Bool
    ) {
        var cx = rect.minX
        let para = NSMutableParagraphStyle(); para.alignment = alignment
        for (text, w) in zip(texts, widths) {
            let attr = NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: para
            ])
            let h = attr.size().height
            let ty = verticalCenter ? rect.minY + (rect.height - h) / 2 : rect.maxY - h
            attr.draw(in: CGRect(x: cx + 4, y: ty, width: w - 8, height: h))
            if cx > rect.minX {
                strokeLine(from: CGPoint(x: cx, y: rect.minY), to: CGPoint(x: cx, y: rect.maxY), color: colorRuleLight, width: 0.4)
            }
            cx += w
        }
    }

    private static func drawCentered(_ text: String, font: NSFont, color: NSColor, in rect: CGRect, leftAlign: Bool = false) {
        let para = NSMutableParagraphStyle(); para.alignment = leftAlign ? .left : .center
        para.lineBreakMode = .byTruncatingTail
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: para
        ])
        let h = attr.size().height
        attr.draw(in: CGRect(x: rect.minX + 3, y: rect.minY + (rect.height - h) / 2, width: rect.width - 6, height: h))
    }

    private static func drawRightAligned(_ text: String, font: NSFont, color: NSColor, in rect: CGRect) {
        let para = NSMutableParagraphStyle(); para.alignment = .right
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: para
        ])
        let h = attr.size().height
        attr.draw(in: CGRect(x: rect.minX, y: rect.minY + (rect.height - h) / 2, width: rect.width - 4, height: h))
    }

    /// A narrow column ("EST TIME" at 6.4% width) can genuinely not fit its header on one
    /// line at any reasonable font size — this measures each header's real wrapped height
    /// (same textLayoutOptions used everywhere else in this file, so measuring and drawing
    /// can't disagree) and sizes the row to whichever header needs the most lines, rather
    /// than truncating with an ellipsis the way drawCentered's single-line assumption would.
    private static func drawTableHeaderRow(cursor: PageCursor, widths: [CGFloat], titles: [String]) {
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let headers: [NSAttributedString] = titles.map {
            NSAttributedString(string: $0, attributes: [.font: fontTableHead, .foregroundColor: colorDark, .paragraphStyle: para])
        }
        // The 1.15x factor matches PDFExporter.swift's wrappedHeight: boundingRect's
        // font-metric-based estimate consistently runs a little short of what draw(with:)
        // actually needs once text really wraps, and without this margin a 2-line header
        // like "EST TIME" measures as fitting but then loses its second line to
        // truncatesLastVisibleLine at draw time — measured, not guessed.
        let heights: [CGFloat] = zip(headers, widths).map { header, w in
            ceil(header.boundingRect(with: CGSize(width: max(w - 4, 1), height: .greatestFiniteMagnitude),
                                      options: textLayoutOptions).height * 1.15)
        }
        let rowHeight = max(heights.max() ?? 9, 9) + 4

        cursor.ensureSpace(rowHeight)
        let top = cursor.y
        let totalWidth = widths.reduce(0, +)
        let rect = CGRect(x: margin, y: top - rowHeight, width: totalWidth, height: rowHeight)

        colorFill.setFill()
        NSBezierPath(rect: rect).fill()

        var cx = margin
        for (i, w) in widths.enumerated() {
            let h = heights[i]
            headers[i].draw(with: CGRect(x: cx + 2, y: top - rowHeight + (rowHeight - h) / 2, width: w - 4, height: h),
                             options: textLayoutOptions)
            cx += w
        }
        drawRowRules(widths: widths, rect: rect)
        strokeRect(rect, color: colorRule, width: 0.8)
        cursor.y -= rowHeight
    }

    private static func drawRowRules(widths: [CGFloat], rect: CGRect) {
        var cx = rect.minX
        for w in widths {
            strokeLine(from: CGPoint(x: cx, y: rect.minY), to: CGPoint(x: cx, y: rect.maxY), color: colorRuleLight, width: 0.4)
            cx += w
        }
        strokeRect(rect, color: colorRuleLight, width: 0.4)
    }

    private static func strokeRect(_ rect: CGRect, color: NSColor, width: CGFloat) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private static func strokeLine(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = width
        color.setStroke()
        path.move(to: from)
        path.line(to: to)
        path.stroke()
    }

    // MARK: - Page cursor

    /// Tracks the current draw position and starts a new PDF page whenever a block/row
    /// doesn't fit in what's left — CALLSHEET_LAYOUT.md §5: "fixed-height rows are wrong...
    /// rows must size to content, then paginate." Table-drawing call sites check
    /// ensureSpace's return value so a continued table repeats its header row on the new
    /// page, per the same section's "repeat table headers across page breaks."
    private final class PageCursor {
        let ctx: CGContext
        var y: CGFloat = 0

        init(ctx: CGContext) { self.ctx = ctx }

        func beginPage() {
            ctx.beginPDFPage(nil)
            let gctx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gctx
            y = CallSheetExporter.pageHeight - CallSheetExporter.margin
        }

        func endPage() {
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }

        @discardableResult
        func ensureSpace(_ height: CGFloat) -> Bool {
            if y - height < CallSheetExporter.margin {
                endPage()
                beginPage()
                return true
            }
            return false
        }

        /// Unconditional page break, for a real page-1/page-2 boundary rather than an
        /// overflow break — used once, between page 1's last block and page 2's title.
        func startNewPage() {
            endPage()
            beginPage()
        }
    }
}

// MARK: - CallSheetFile

struct CallSheetFile: FileDocument {
    static var readableContentTypes:  [UTType] = [.pdf]
    static var writableContentTypes: [UTType]  = [.pdf]

    private let shootDay:       ShootDay
    private let productionInfo: ProductionInfo
    private let projectTitle:   String
    private let shootDays:      [ShootDay]

    init(shootDay: ShootDay, productionInfo: ProductionInfo, projectTitle: String, shootDays: [ShootDay]) {
        self.shootDay       = shootDay
        self.productionInfo = productionInfo
        self.projectTitle   = projectTitle
        self.shootDays      = shootDays
    }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = CallSheetExporter.generatePDF(
            shootDay: shootDay, productionInfo: productionInfo, projectTitle: projectTitle, shootDays: shootDays
        ) else { throw CocoaError(.fileWriteUnknown) }
        return FileWrapper(regularFileWithContents: data)
    }
}

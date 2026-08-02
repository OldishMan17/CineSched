// PDFExporter.swift
// Generates a landscape US Letter PDF calendar from shoot data

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - PDFExporter

class PDFExporter {

    // MARK: Fonts (shared between measurement and drawing so the two can never disagree)

    private static let sceneNumberFont = NSFont.boldSystemFont(ofSize: 8)
    private static let sceneTitleFont  = NSFont.systemFont(ofSize: 8)
    private static let sceneMetaFont   = NSFont.systemFont(ofSize: 7.5)
    private static let bannerFont      = NSFont.boldSystemFont(ofSize: 7.5)
    private static let bannerMetaFont  = NSFont.systemFont(ofSize: 7)
    private static let bannerNoteFont  = NSFont.systemFont(ofSize: 6.5)
    private static let castFont        = NSFont.systemFont(ofSize: 7)

    // A day's cast list and a banner's label/note must never silently truncate with an
    // ellipsis — a real cast list can run to a dozen names, and a banner label or note is
    // free text with no natural length limit. Row height already has no upper cap (see
    // calculateIdealRowHeights), so these can genuinely just wrap as many lines as needed;
    // this is a generous finite ceiling purely as a sanity backstop against a truly
    // pathological input, not a limit meant to ever actually engage in real use.
    private static let unboundedLineCap = 25

    static func generatePDF(
        shootDays: [ShootDay],
        projectTitle: String,
        allScenes: [Scene],
        startDate: Date,
        endDate: Date,
        useColor: Bool = false
    ) -> Data? {

        let pageWidth:  CGFloat = 792   // US Letter landscape
        let pageHeight: CGFloat = 612
        // Tightened from 40 — gives every day column a little more usable width, on top of
        // scene/banner text now wrapping instead of truncating.
        let margin:     CGFloat = 30

        let contentRect = CGRect(
            x: margin, y: margin,
            width:  pageWidth  - 2 * margin,
            height: pageHeight - 2 * margin
        )

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        let weeks      = groupDaysIntoWeeks(shootDays)
        let cellWidth  = contentRect.width / 7
        let rowHeights = calculateIdealRowHeights(weeks: weeks, cellWidth: cellWidth)

        var pageNumber = 0
        var weekIndex  = 0
        var currentY   = contentRect.maxY

        while weekIndex < weeks.count {
            pageNumber += 1
            context.beginPDFPage(nil)

            let gctx = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gctx

            // Header on first page only
            if pageNumber == 1 {
                let headerHeight: CGFloat = 50
                let headerRect = CGRect(
                    x: contentRect.minX,
                    y: contentRect.maxY - headerHeight,
                    width: contentRect.width,
                    height: headerHeight
                )
                drawHeader(
                    in: headerRect,
                    projectTitle: projectTitle,
                    startDate: startDate,
                    endDate: endDate,
                    allScenes: allScenes,
                    shootDays: shootDays
                )
                currentY = contentRect.maxY - headerHeight - 10
            } else {
                currentY = contentRect.maxY
            }

            var horizontalLines: [CGFloat] = [currentY]

            while weekIndex < weeks.count {
                let rowHeight = rowHeights[weekIndex]
                guard currentY - rowHeight >= contentRect.minY + 10 else { break }

                let rowRect = CGRect(
                    x: contentRect.minX,
                    y: currentY - rowHeight,
                    width: contentRect.width,
                    height: rowHeight
                )
                drawWeekRow(week: weeks[weekIndex], in: rowRect, cellWidth: cellWidth, useColor: useColor)
                currentY -= rowHeight
                horizontalLines.append(currentY)
                weekIndex += 1
            }

            drawGridLines(
                horizontalLines: horizontalLines,
                minX: contentRect.minX, maxX: contentRect.maxX,
                minY: contentRect.minY, maxY: contentRect.maxY
            )

            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }

        context.closePDF()
        return pdfData as Data
    }

    // MARK: - Private Drawing Helpers

    private static func drawHeader(
        in rect: CGRect,
        projectTitle: String,
        startDate: Date,
        endDate: Date,
        allScenes: [Scene],
        shootDays: [ShootDay]
    ) {
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.black
        ]
        let displayTitle = projectTitle.isEmpty ? "Untitled Movie" : projectTitle
        NSAttributedString(string: displayTitle, attributes: titleAttr)
            .draw(in: CGRect(x: rect.minX, y: rect.maxY - 25, width: rect.width, height: 25))

        let smallAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray
        ]
        let scheduled = shootDays.filter { !$0.scenes.isEmpty }.count
        NSAttributedString(string: "Shoot Days: \(scheduled)", attributes: smallAttr)
            .draw(in: CGRect(x: rect.minX, y: rect.maxY - 50, width: rect.width, height: 20))
    }

    // MARK: - Item line model
    //
    // Building one shared "what does this item look like" representation and reusing it for
    // both the row-height measurement pass and the actual drawing pass is what guarantees
    // the two can never disagree — there's no separate "estimate the height" formula that
    // could drift out of sync with what actually gets drawn.

    private struct ItemLine {
        let text: NSAttributedString
        let referenceFont: NSFont   // for single-line-height purposes when text has mixed runs
        let maxLines: Int
    }

    private static func lineHeight(for font: NSFont) -> CGFloat {
        font.ascender - font.descender + font.leading
    }

    /// Used identically for both measuring (boundingRect) and drawing (draw(with:)) — those
    /// two APIs can compute subtly different line-wrapping/line-spacing when given different
    /// option sets, and that mismatch was exactly why text measured as "fits in N lines"
    /// could still render as only N-1 lines at draw time, silently losing the rest to
    /// truncatesLastVisibleLine. Using one shared constant for both calls guarantees they
    /// can never drift out of sync with each other again.
    private static let textLayoutOptions: NSString.DrawingOptions = [
        .usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine
    ]

    /// Height needed to draw `line` wrapped within `maxWidth`, capped at its maxLines.
    ///
    /// This deliberately thinks in whole lines rather than continuous point heights. Font
    /// metrics (ascender/descender/leading, used for `single` below) are only an
    /// *approximation* of the line spacing CoreText's real text layout actually uses when
    /// it wraps and draws text — the true spacing is consistently a little taller (measured
    /// at roughly 4-5% per line for the fonts used here). That gap compounds with every
    /// additional line, so a cast list that measures as "fits in 5 lines" can come up just
    /// short of a real 5th line at draw time and lose the rest to truncatesLastVisibleLine.
    ///
    /// The fix is a proportional per-line margin (15%, comfortably above the measured ~4-5%
    /// gap) rather than a flat "+1 whole extra line" — a flat extra line was enough headroom
    /// for a 5-line cast list, but wrapped in totalHeight() below, which sums this per
    /// paragraph, it meant a banner's label + note (two short paragraphs) got charged two
    /// full extra lines while a scene's single combined paragraph only got charged one —
    /// visibly taller banner boxes for the same amount of actual text.
    private static func wrappedHeight(_ line: ItemLine, maxWidth: CGFloat) -> CGFloat {
        let single = lineHeight(for: line.referenceFont)
        guard maxWidth > 0, single > 0 else { return single }
        let unbounded = line.text.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: textLayoutOptions
        ).height
        let estimatedLines = max(1, (unbounded / single).rounded(.up))
        let cappedLines     = min(estimatedLines, CGFloat(line.maxLines))
        return cappedLines * single * 1.15 + 1
    }

    private static func totalHeight(of lines: [ItemLine], maxWidth: CGFloat) -> CGFloat {
        lines.reduce(0) { $0 + wrappedHeight($1, maxWidth: maxWidth) }
    }

    /// The printable lines for one day item — a scene gets one wrapping line combining its
    /// number, title, and (pages, est. time) inline; a banner gets a bold label line (with
    /// its own est. time, if set) and an optional note line beneath.
    private static func itemLines(for item: DayItem) -> [ItemLine] {
        switch item {
        case .scene(let scene):
            let combined = NSMutableAttributedString()
            if !scene.sceneNumber.isEmpty {
                combined.append(NSAttributedString(
                    string: "\(scene.sceneNumber)  ",
                    attributes: [.font: sceneNumberFont, .foregroundColor: NSColor.black]
                ))
            }
            combined.append(NSAttributedString(
                string: scene.title,
                attributes: [.font: sceneTitleFont, .foregroundColor: NSColor.black]
            ))
            combined.append(NSAttributedString(
                string: "  (\(formattedEighths(scene.duration)), \(formattedTime(scene.estimatedTime)))",
                attributes: [.font: sceneMetaFont, .foregroundColor: NSColor.darkGray]
            ))
            // 3 lines, not 2 — an unusually long title can otherwise wrap far enough that
            // the trailing "(pages, time)" never makes it onto a visible line at all.
            return [ItemLine(text: combined, referenceFont: sceneTitleFont, maxLines: 3)]

        case .banner(let banner):
            var lines: [ItemLine] = []
            let label = banner.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let labelLine = NSMutableAttributedString(
                string: label.isEmpty ? "ITEM" : label.uppercased(),
                attributes: [.font: bannerFont, .foregroundColor: NSColor(white: 0.2, alpha: 1)]
            )
            if banner.estimatedTime > 0 {
                labelLine.append(NSAttributedString(
                    string: "  (\(formattedTime(banner.estimatedTime)))",
                    attributes: [.font: bannerMetaFont, .foregroundColor: NSColor.darkGray]
                ))
            }
            lines.append(ItemLine(text: labelLine, referenceFont: bannerFont, maxLines: unboundedLineCap))

            let note = banner.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                lines.append(ItemLine(
                    text: NSAttributedString(string: note, attributes: [
                        .font: bannerNoteFont, .foregroundColor: NSColor.darkGray
                    ]),
                    referenceFont: bannerNoteFont,
                    maxLines: unboundedLineCap
                ))
            }
            return lines
        }
    }

    /// A banner's fill/border — light gray with a dashed outline, no day/night color, so it
    /// reads as a note rather than something shootable — matches the dashed-border treatment
    /// BannerCardView uses inline on the calendar itself (see CalendarView.swift).
    private static func drawItemBackground(item: DayItem, in boxRect: CGRect, useColor: Bool) {
        switch item {
        case .scene(let scene):
            let path = NSBezierPath(roundedRect: boxRect, xRadius: 2, yRadius: 2)
            if useColor {
                nsColor(for: scene.dayNightType).withAlphaComponent(0.16).setFill()
            } else {
                (scene.dayNightType == .night ? NSColor(white: 0.9, alpha: 1.0) : NSColor.white).setFill()
            }
            path.fill()
            path.lineWidth = 0.5
            (useColor ? nsColor(for: scene.dayNightType) : NSColor.lightGray).setStroke()
            path.stroke()

        case .banner:
            let path = NSBezierPath(roundedRect: boxRect, xRadius: 2, yRadius: 2)
            NSColor(white: 0.93, alpha: 1.0).setFill()
            path.fill()
            let dashed = NSBezierPath(roundedRect: boxRect, xRadius: 2, yRadius: 2)
            dashed.lineWidth = 0.6
            dashed.setLineDash([2, 1.5], count: 2, phase: 0)
            NSColor(white: 0.4, alpha: 1.0).setStroke()
            dashed.stroke()
        }
    }

    /// Bridges a scene's SwiftUI day/night color into AppKit for the color export option —
    /// same colors the app itself already uses (orange/blue/green), so a color export reads
    /// consistently with what's on screen.
    private static func nsColor(for type: DayNightType) -> NSColor {
        NSColor(type.color)
    }

    // MARK: - Row height

    private static func calculateIdealRowHeights(weeks: [[ShootDay?]], cellWidth: CGFloat) -> [CGFloat] {
        let minHeight: CGFloat = 50
        // Deliberately no upper cap: a row is always sized to what its busiest day actually
        // needs. Clamping this to a fixed maximum used to silently clip content shorter than
        // what drawDay would then try to draw into it, causing the day's totals to overlap
        // its last item on a busy day. If a day is unusually packed, the row just ends up
        // tall — the page-break logic below already handles giving an oversized row its own
        // page when it doesn't fit under the current one.
        let padding: CGFloat = 6
        let innerWidth = cellWidth - 2 * padding - 6   // minus cell padding and text inset

        return weeks.map { week in
            let contentHeight = week.compactMap { $0 }.map { day -> CGFloat in
                dayContentHeight(day: day, innerWidth: innerWidth)
            }.max() ?? 40
            return max(contentHeight + 20, minHeight)
        }
    }

    /// Everything that stacks vertically in one day cell: date header, cast summary (if
    /// any), every item's wrapped height, and the totals block (if there's any content).
    /// Used both to decide how tall a week's row needs to be and, implicitly, to draw within
    /// exactly that space — see dayContentHeight's use in both calculateIdealRowHeights and
    /// its mirror layout in drawDay.
    private static func dayContentHeight(day: ShootDay, innerWidth: CGFloat) -> CGFloat {
        var total: CGFloat = 16   // date header

        let cast = day.allCast
        if !cast.isEmpty {
            let castLine = ItemLine(
                text: NSAttributedString(string: "Cast: " + cast.joined(separator: ", "), attributes: [.font: castFont]),
                referenceFont: castFont,
                maxLines: unboundedLineCap
            )
            total += wrappedHeight(castLine, maxWidth: innerWidth) + 2
        }

        for item in day.items {
            // +4 for the box's own top/bottom padding, +1 to match the inter-item gap
            // drawDay actually leaves between boxes (yOffset += boxHeight + 1) — this was
            // previously missing here, which under-reserved the row's height by 1pt per
            // item and let the last item's box run into the totals text below it.
            total += totalHeight(of: itemLines(for: item), maxWidth: innerWidth) + 4 + 1
        }

        if !day.items.isEmpty { total += 20 }   // totals block
        return total
    }

    private static func drawWeekRow(week: [ShootDay?], in rowRect: CGRect, cellWidth: CGFloat, useColor: Bool) {
        for (col, day) in week.enumerated() {
            let cellRect = CGRect(
                x: rowRect.minX + CGFloat(col) * cellWidth,
                y: rowRect.minY,
                width: cellWidth,
                height: rowRect.height
            )
            if let day = day { drawDay(day: day, in: cellRect, useColor: useColor) }
        }
    }

    private static func drawGridLines(
        horizontalLines: [CGFloat],
        minX: CGFloat, maxX: CGFloat,
        minY: CGFloat, maxY: CGFloat
    ) {
        guard !horizontalLines.isEmpty else { return }

        let path = NSBezierPath()
        path.lineWidth = 0.5
        NSColor.lightGray.setStroke()

        let top    = horizontalLines.first ?? maxY
        let bottom = horizontalLines.last  ?? minY

        // Vertical lines spanning actual calendar content only
        for i in 0...7 {
            let x = minX + CGFloat(i) * ((maxX - minX) / 7)
            path.move(to: CGPoint(x: x, y: bottom))
            path.line(to: CGPoint(x: x, y: top))
        }

        // Horizontal row separators
        for y in horizontalLines {
            path.move(to: CGPoint(x: minX, y: y))
            path.line(to: CGPoint(x: maxX, y: y))
        }
        path.stroke()
    }

    private static func drawDay(day: ShootDay, in rect: CGRect, useColor: Bool) {
        // Tightened from 8 — reclaims a little more width for scene/banner text.
        let padding = CGFloat(6)
        let content = CGRect(
            x: rect.minX + padding, y: rect.minY + padding,
            width:  rect.width  - 2 * padding,
            height: rect.height - 2 * padding
        )
        let innerWidth = content.width - 6   // text inset within each item's box

        // Date header (top of cell)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E MMM d"
        let dateAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.black
        ]
        NSAttributedString(string: dateFormatter.string(from: day.date), attributes: dateAttr)
            .draw(in: CGRect(x: content.minX, y: content.maxY - 12, width: content.width, height: 12))

        var yOffset: CGFloat = 16

        // Cast summary — every character appearing anywhere in the day's scenes, deduplicated
        // and listed once, the way a real call sheet answers "who's needed today" rather than
        // repeating cast per scene.
        let cast = day.allCast
        if !cast.isEmpty {
            let castLine = ItemLine(
                text: NSAttributedString(
                    string: "Cast: " + cast.joined(separator: ", "),
                    attributes: [.font: castFont, .foregroundColor: NSColor.darkGray]
                ),
                referenceFont: castFont,
                maxLines: unboundedLineCap
            )
            // width: innerWidth (not content.width) — this must match the width wrappedHeight
            // measured against above, or the draw pass can wrap differently than the height
            // was computed for.
            let h = wrappedHeight(castLine, maxWidth: innerWidth)
            let boxRect = CGRect(x: content.minX, y: content.maxY - yOffset - h, width: innerWidth, height: h)
            castLine.text.draw(with: boxRect, options: textLayoutOptions)
            yOffset += h + 2
        }

        // Items — scenes and banners together, in the day's actual schedule order, each
        // wrapping instead of truncating so titles and scene numbers aren't cut off.
        for item in day.items {
            let lines = itemLines(for: item)
            let boxHeight = totalHeight(of: lines, maxWidth: innerWidth) + 4
            let boxRect = CGRect(
                x: content.minX,
                y: content.maxY - yOffset - boxHeight,
                width: content.width,
                height: boxHeight
            )

            drawItemBackground(item: item, in: boxRect, useColor: useColor)

            var lineY = boxRect.maxY - 2
            for line in lines {
                let h = wrappedHeight(line, maxWidth: innerWidth)
                let textRect = CGRect(x: boxRect.minX + 3, y: lineY - h, width: boxRect.width - 6, height: h)
                line.text.draw(with: textRect, options: textLayoutOptions)
                lineY -= h
            }

            yOffset += boxHeight + 1
        }

        // Totals at bottom — gated on items rather than scenes alone, since a banner's
        // estimated time now counts toward the day's total time even on a day with no scenes.
        if !day.items.isEmpty {
            let totalAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7),
                .foregroundColor: NSColor.gray
            ]
            let totalText = "Total: \(formattedEighths(day.totalDuration))\nEst: \(formattedTime(day.totalEstimatedTime))"
            NSAttributedString(string: totalText, attributes: totalAttr)
                .draw(in: CGRect(x: content.minX, y: content.minY, width: content.width, height: 20))
        }
    }

    private static func groupDaysIntoWeeks(_ shootDays: [ShootDay]) -> [[ShootDay?]] {
        guard !shootDays.isEmpty else { return [] }

        let cal  = Calendar.current
        var weeks: [[ShootDay?]] = []
        var week = Array(repeating: ShootDay?.none, count: 7)

        var date = cal.startOfDay(for: shootDays.first!.date)
        let end  = cal.startOfDay(for: shootDays.last!.date)
        var idx  = 0

        while date <= end {
            let weekday = cal.component(.weekday, from: date) - 1 // 0 = Sun

            let match = (idx < shootDays.count && cal.isDate(shootDays[idx].date, inSameDayAs: date))
                ? shootDays[idx] : nil
            if match != nil { idx += 1 }

            week[weekday] = match ?? ShootDay(date: date)

            if weekday == 6 || date == end {
                weeks.append(week)
                week = Array(repeating: nil, count: 7)
            }
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        return weeks
    }
}

// MARK: - PDFFile (FileDocument wrapper)

struct PDFFile: FileDocument {
    static var readableContentTypes:  [UTType] = [.pdf]
    static var writableContentTypes: [UTType] = [.pdf]

    private let shootDays:    [ShootDay]
    private let projectTitle: String
    private let allScenes:    [Scene]
    private let startDate:    Date
    private let endDate:      Date

    init(shootDays: [ShootDay], projectTitle: String, allScenes: [Scene], startDate: Date, endDate: Date) {
        self.shootDays    = shootDays
        self.projectTitle = projectTitle
        self.allScenes    = allScenes
        self.startDate    = startDate
        self.endDate      = endDate
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = PDFExporter.generatePDF(
            shootDays: shootDays,
            projectTitle: projectTitle,
            allScenes: allScenes,
            startDate: startDate,
            endDate: endDate
        ) else { throw CocoaError(.fileWriteUnknown) }
        return FileWrapper(regularFileWithContents: data)
    }
}

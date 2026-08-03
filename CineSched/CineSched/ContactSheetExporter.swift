// ContactSheetExporter.swift
// Generates a standalone cast/crew phone list PDF — separate from the calendar schedule
// and the per-day call sheet, for when someone just needs a phone list, not the full
// schedule. Deliberately mirrors CallSheetExporter's page setup and styling (same portrait
// page size, margins, fonts, colors, and section/table drawing style) rather than building
// a new PDF pipeline — see CallSheetExporter.swift for the pattern this follows.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ContactSheetExporter

class ContactSheetExporter {

    private static let pageWidth:  CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin:     CGFloat = 50
    private static let colWidth:   CGFloat = 512

    private static let fontTitle   = NSFont.boldSystemFont(ofSize: 16)
    private static let fontHeading = NSFont.boldSystemFont(ofSize: 11)
    private static let fontSubhead = NSFont.boldSystemFont(ofSize: 9)
    private static let fontBody    = NSFont.systemFont(ofSize: 9)

    private static let colorBlack   = NSColor.black
    private static let colorDark    = NSColor(white: 0.15, alpha: 1)
    private static let colorMid     = NSColor(white: 0.45, alpha: 1)
    private static let colorLight   = NSColor(white: 0.92, alpha: 1)
    private static let colorDivider = NSColor(white: 0.75, alpha: 1)

    /// One row in the printed table — already resolved to plain strings (name, role or
    /// character, primary phone, primary email) so the drawing code doesn't need to know
    /// whether it's looking at a CastMember or a CrewMember.
    private struct ContactRow {
        let name: String
        let roleOrCharacter: String
        let phone: String
        let email: String
    }

    static func generatePDF(productionInfo: ProductionInfo, projectTitle: String) -> Data? {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        ctx.beginPDFPage(nil)
        let gctx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx

        var y = pageHeight - margin
        y = drawPageHeader(y: y, productionInfo: productionInfo, projectTitle: projectTitle)

        // Director and Producer first — production leadership, not part of either roster,
        // but they can carry their own contact info the same way cast/crew do.
        let productionRows: [ContactRow] = [
            ContactRow(name: productionInfo.director.name.isEmpty ? "—" : productionInfo.director.name,
                       roleOrCharacter: "Director",
                       phone: productionInfo.director.primaryPhone ?? "",
                       email: productionInfo.director.primaryEmail ?? ""),
            ContactRow(name: productionInfo.producer.name.isEmpty ? "—" : productionInfo.producer.name,
                       roleOrCharacter: "Producer",
                       phone: productionInfo.producer.primaryPhone ?? "",
                       email: productionInfo.producer.primaryEmail ?? "")
        ]
        y = drawSection(y: y, title: "PRODUCTION", columnLabels: ("NAME", "ROLE")) { yy in
            drawPeopleTable(y: yy, rows: productionRows, emptyMessage: "No production contacts added.")
        }

        // Alphabetical by the name actually printed in the NAME column — a phone list
        // that isn't sorted isn't usable as a phone list.
        let castRows = productionInfo.castList
            .sorted {
                let a = $0.actorName.isEmpty ? $0.characterName : $0.actorName
                let b = $1.actorName.isEmpty ? $1.characterName : $1.actorName
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            .map {
                ContactRow(
                    name: $0.actorName.isEmpty ? ($0.characterName.isEmpty ? "—" : $0.characterName) : $0.actorName,
                    roleOrCharacter: $0.characterName,
                    phone: $0.primaryPhone ?? "",
                    email: $0.primaryEmail ?? ""
                )
            }
        y = drawSection(y: y, title: "CAST", columnLabels: ("NAME", "CHARACTER")) { yy in
            drawPeopleTable(y: yy, rows: castRows, emptyMessage: "No cast added.")
        }

        let crewRows = productionInfo.crew
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map {
                ContactRow(
                    name: $0.name.isEmpty ? "—" : $0.name,
                    roleOrCharacter: $0.role,
                    phone: $0.primaryPhone ?? "",
                    email: $0.primaryEmail ?? ""
                )
            }
        // No department grouping — there's no department field anywhere in the app today
        // (CrewMember only has a free-text `role`), so this doesn't invent one; crew is
        // just one alphabetical list, same as cast.
        _ = drawSection(y: y, title: "CREW", columnLabels: ("NAME", "ROLE")) { yy in
            drawPeopleTable(y: yy, rows: crewRows, emptyMessage: "No crew added.")
        }

        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return pdfData as Data
    }

    // MARK: - Page Header

    private static func drawPageHeader(
        y: CGFloat,
        productionInfo: ProductionInfo,
        projectTitle: String
    ) -> CGFloat {
        var y = y
        if !productionInfo.companyName.isEmpty {
            y = drawText(productionInfo.companyName.uppercased(),
                         font: fontHeading, color: colorMid, x: margin, y: y, width: colWidth)
            y -= 4
        }
        y = drawText(projectTitle.isEmpty ? "Untitled Movie" : projectTitle,
                     font: fontTitle, color: colorBlack, x: margin, y: y, width: colWidth * 0.65)
        drawTextRight("Contact Sheet", font: fontBody, color: colorMid, x: margin, y: y + 16, width: colWidth)
        y -= 6
        // Same "Contact: ..." treatment CallSheetExporter's header uses for this field.
        if !productionInfo.contactNumber.isEmpty {
            y = drawText("Production Contact: \(productionInfo.contactNumber)",
                         font: fontBody, color: colorDark, x: margin, y: y, width: colWidth)
            y -= 4
        }
        y -= 6
        drawHRule(y: y, thick: true)
        y -= 12
        return y
    }

    // MARK: - Section wrapper (same shape as CallSheetExporter.drawSection)

    private static func drawSection(
        y: CGFloat, title: String, columnLabels: (String, String), content: (CGFloat) -> CGFloat
    ) -> CGFloat {
        var y = y
        guard y > margin + 40 else { return y }
        let barRect = CGRect(x: margin, y: y - 16, width: colWidth, height: 16)
        colorLight.setFill()
        NSBezierPath(rect: barRect).fill()
        let titleAttr: [NSAttributedString.Key: Any] = [.font: fontSubhead, .foregroundColor: colorDark]
        NSAttributedString(string: title, attributes: titleAttr)
            .draw(in: CGRect(x: margin + 6, y: y - 14, width: colWidth - 12, height: 14))
        y -= 20

        // Column headers
        let (col1, col2, col3, col4) = columnPositions()
        let headerAttr: [NSAttributedString.Key: Any] = [.font: fontSubhead, .foregroundColor: colorMid]
        NSAttributedString(string: columnLabels.0, attributes: headerAttr).draw(in: CGRect(x: col1.x, y: y - 12, width: col1.w, height: 12))
        NSAttributedString(string: columnLabels.1, attributes: headerAttr).draw(in: CGRect(x: col2.x, y: y - 12, width: col2.w, height: 12))
        NSAttributedString(string: "PHONE",        attributes: headerAttr).draw(in: CGRect(x: col3.x, y: y - 12, width: col3.w, height: 12))
        NSAttributedString(string: "EMAIL",        attributes: headerAttr).draw(in: CGRect(x: col4.x, y: y - 12, width: col4.w, height: 12))
        y -= 16

        y = content(y)
        y -= 10
        drawHRule(y: y, thick: false)
        y -= 10
        return y
    }

    // MARK: - Table

    // EMAIL gets the most extra room, taken from PHONE specifically (never needs much —
    // phone numbers are a fixed short shape) rather than from ROLE/CHARACTER, which turned
    // out to need its original width just as much as email needed more ("Director of
    // Photography" truncated once ROLE dropped from 130). NAME trimmed slightly too, but
    // stays comfortably ahead of any real name.
    private static func columnPositions() -> (
        (x: CGFloat, w: CGFloat), (x: CGFloat, w: CGFloat), (x: CGFloat, w: CGFloat), (x: CGFloat, w: CGFloat)
    ) {
        let col1: CGFloat = margin + 6;  let colW1: CGFloat = 130
        let col2: CGFloat = col1 + 130;  let colW2: CGFloat = 130
        let col3: CGFloat = col2 + 130;  let colW3: CGFloat = 80
        let col4: CGFloat = col3 + 80;   let colW4: CGFloat = 160
        return ((col1, colW1), (col2, colW2), (col3, colW3), (col4, colW4))
    }

    private static func drawPeopleTable(y: CGFloat, rows: [ContactRow], emptyMessage: String) -> CGFloat {
        var y = y
        if rows.isEmpty {
            return drawText(emptyMessage, font: fontBody, color: colorMid,
                            x: margin + 6, y: y, width: colWidth - 12)
        }
        let (col1, col2, col3, col4) = columnPositions()
        for (i, row) in rows.enumerated() {
            if i % 2 == 0 {
                NSColor(white: 0.97, alpha: 1).setFill()
                NSBezierPath(rect: CGRect(x: margin, y: y - 12, width: colWidth, height: 13)).fill()
            }
            drawTextInline(row.name,                          font: fontBody, color: colorDark, x: col1.x, y: y - 11, width: col1.w - 4)
            drawTextInline(row.roleOrCharacter,                font: fontBody, color: colorMid,  x: col2.x, y: y - 11, width: col2.w - 4)
            drawTextInline(row.phone.isEmpty ? "—" : row.phone, font: fontBody, color: colorDark, x: col3.x, y: y - 11, width: col3.w - 4)
            drawTextInline(row.email.isEmpty ? "—" : row.email, font: fontBody, color: colorDark, x: col4.x, y: y - 11, width: col4.w - 4)
            y -= 14
        }
        return y
    }

    // MARK: - Low-level drawing helpers (same as CallSheetExporter's)

    @discardableResult
    private static func drawText(_ text: String, font: NSFont, color: NSColor,
                                  x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str  = NSAttributedString(string: text, attributes: attr)
        let h    = str.size().height
        str.draw(in: CGRect(x: x, y: y - h, width: width, height: h))
        return y - h
    }

    private static func drawTextInline(_ text: String, font: NSFont, color: NSColor,
                                        x: CGFloat, y: CGFloat, width: CGFloat) {
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        NSAttributedString(string: text, attributes: attr).draw(in: CGRect(x: x, y: y, width: width, height: 11))
    }

    private static func drawTextRight(_ text: String, font: NSFont, color: NSColor,
                                       x: CGFloat, y: CGFloat, width: CGFloat) {
        let para = NSMutableParagraphStyle(); para.alignment = .right
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        let h = NSAttributedString(string: text, attributes: attr).size().height
        NSAttributedString(string: text, attributes: attr).draw(in: CGRect(x: x, y: y - h, width: width, height: h))
    }

    private static func drawHRule(y: CGFloat, thick: Bool) {
        let path = NSBezierPath(); path.lineWidth = thick ? 1.0 : 0.4
        (thick ? colorDark : colorDivider).setStroke()
        path.move(to: CGPoint(x: margin, y: y)); path.line(to: CGPoint(x: margin + colWidth, y: y))
        path.stroke()
    }
}

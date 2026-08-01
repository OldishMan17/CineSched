// Parsers.swift
// Utility parsers for page duration (eighths) and time (minutes) input

import Foundation

// MARK: - FractionParser

struct FractionParser {

    /// Converts natural script-page notation to eighths of a page.
    /// Supports: "4" (4 whole pages), "4 3/8" (mixed), "7/8" (fraction alone), "4.375" (decimal pages)
    static func parseToEighths(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Plain whole number — whole pages, e.g. "4" = 4 pages = 32 eighths. (Not "4 eighths":
        // that reading is technically correct script jargon but reads as a typo to anyone
        // typing a page count, which is what this field is for.)
        if let wholePages = Int(trimmed) { return wholePages * 8 }

        // Decimal number — pages, e.g. "4.375" = 4 3/8 pages
        if let decimal = Double(trimmed) { return Int(round(decimal * 8)) }

        // Mixed fraction: "4 3/8" = 4 and 3/8 pages
        let mixedPattern = #"^(\d+)\s+(\d+)/(\d+)$"#
        if trimmed.range(of: mixedPattern, options: .regularExpression) != nil {
            let components = trimmed.components(separatedBy: .whitespaces)
            if components.count == 2, let whole = Int(components[0]),
               let fraction = parseFraction(components[1]) {
                return (whole * 8) + fraction
            }
        }

        // Simple fraction: "7/8"
        if trimmed.contains("/") { return parseFraction(trimmed) }

        return nil
    }

    /// Parses a simple "n/d" fraction string into eighths.
    private static func parseFraction(_ fraction: String) -> Int? {
        let parts = fraction.components(separatedBy: "/")
        guard parts.count == 2,
              let numerator   = Int(parts[0]),
              let denominator = Int(parts[1]),
              denominator > 0 else { return nil }
        return (numerator * 8) / denominator
    }

    /// Formats an eighths value back to a human-readable page string.
    static func formatEighths(_ eighths: Int) -> String {
        let whole     = eighths / 8
        let remainder = eighths % 8
        switch (whole, remainder) {
        case (0, 0): return "0"
        case (0, _): return "\(remainder)/8"
        case (_, 0): return "\(whole)"
        default:     return "\(whole) \(remainder)/8"
        }
    }

    static var placeholderText: String { "e.g. 4, 4 3/8, 4.375" }
}

// MARK: - TimeParser

struct TimeParser {

    /// Converts various time input formats to minutes.
    ///
    /// Rules:
    /// - Integers ≤ 10 → hours  (e.g. "4"  = 4 hr  = 240 min)
    /// - Integers > 10 → minutes (e.g. "15" = 15 min)
    /// - Decimal ≤ 14  → hours  (e.g. "2.5" = 150 min)
    /// - Decimal > 14  → minutes
    /// - "H:MM" format → explicit hours:minutes (e.g. "2:30" = 150 min)
    static func parseToMinutes(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // H:MM explicit format
        if trimmed.contains(":") {
            let parts = trimmed.components(separatedBy: ":")
            guard parts.count == 2,
                  let hours   = Int(parts[0]),
                  let minutes = Int(parts[1]),
                  hours   >= 0,
                  minutes >= 0,
                  minutes <  60 else { return nil }
            return (hours * 60) + minutes
        }

        // Decimal hours / minutes
        if let decimal = Double(trimmed) {
            return decimal <= 14 ? Int(decimal * 60) : Int(decimal)
        }

        // Integer hours / minutes
        if let integer = Int(trimmed) {
            return integer <= 10 ? integer * 60 : integer
        }

        return nil
    }

    /// Formats a minute count back to a readable time string.
    static func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins  = minutes % 60
        switch (hours, mins) {
        case (0, 0): return "0 min"
        case (0, _): return "\(mins) min"
        case (_, 0): return "\(hours) hr"
        default:     return "\(hours) hr \(mins) min"
        }
    }

    /// Returns a formatted hint string for the current input, e.g. "= 2 hr 30 min"
    static func getInputHint(_ input: String) -> String? {
        guard let minutes = parseToMinutes(input) else { return nil }
        return "= \(formatMinutes(minutes))"
    }

    static var placeholderText: String { "e.g. 4 (4hr), 15 (15min), 2:30 (2hr 30min)" }
}

// MARK: - SceneNumberParser

/// Real scene numbers aren't plain integers — see CALLSHEET_SPEC.md §3.1. A shooting script
/// numbers scenes in order (1, 2, 3…), but revisions insert scenes between existing ones
/// (lettered: "9A", or prefixed: "A9") without renumbering everything after, and a scene
/// shot across more than one day gets split into "pt" (partial) continuations ("9pt",
/// "60pt4"). None of that survives being stored as an Int, and sorting the raw text
/// alphabetically gets the order wrong too — "10" would sort before "9".
struct SceneNumberParser {

    /// The components real scene numbers decompose into, in sort priority order: the
    /// numeric core, which "insert family" it belongs to, the insert letter itself, and a
    /// "pt" index.
    ///
    /// The insert family matters because a letter *before* the number and a letter *after*
    /// the number mean opposite things on a real set. A prefix like "A20" is a scene
    /// inserted *before* 20 once the script was already locked — script supervisors number
    /// it off the scene it comes before, so it belongs before plain "20" (order: A20, B20,
    /// 20). A suffix like "75A" is the opposite: inserted *after* 75, numbered off the
    /// scene it follows, so it belongs after plain "75" (order: 75, 75A, 75B).
    struct SortKey: Comparable {
        let core: Int
        let insertRank: Int   // 0 = prefixed (inserted before the plain scene)
                               // 1 = the plain scene itself (no insert letter)
                               // 2 = suffixed (inserted after the plain scene)
        let letter: String    // the insert letter ("" for the plain scene), A before B
        let ptIndex: Int

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            if lhs.core       != rhs.core       { return lhs.core       < rhs.core }
            if lhs.insertRank != rhs.insertRank { return lhs.insertRank < rhs.insertRank }
            if lhs.letter     != rhs.letter     { return lhs.letter     < rhs.letter }
            return lhs.ptIndex < rhs.ptIndex
        }
    }

    /// Decomposes a scene number string into its sortable components.
    /// Examples: "86" -> (86, plain, "", 0) · "9pt" -> (9, plain, "", 1)
    /// · "A20" -> (20, prefixed, "A", 0) · "75A" -> (75, suffixed, "A", 0)
    /// · "60pt4" -> (60, plain, "", 4)
    static func sortKey(for sceneNumber: String) -> SortKey {
        let trimmed = sceneNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var rest = Substring(trimmed)

        var prefix = ""
        while let first = rest.first, first.isLetter {
            prefix.append(first)
            rest = rest.dropFirst()
        }

        var digits = ""
        while let first = rest.first, first.isNumber {
            digits.append(first)
            rest = rest.dropFirst()
        }

        guard let core = Int(digits) else {
            // Doesn't look like a real scene number at all (e.g. a banner-style entry like
            // "B ROLL") — push it to the very end rather than interleaving it arbitrarily
            // among properly-numbered scenes or crashing.
            return SortKey(core: .max, insertRank: 1, letter: trimmed, ptIndex: 0)
        }

        if rest.hasPrefix("PT") {
            let afterPT = rest.dropFirst(2)
            let ptIndex = Int(afterPT) ?? 1   // bare "PT" with no number = the 1st continuation
            if !prefix.isEmpty {
                // e.g. "B79pt" — a "B"-prefixed insert that's also been split into parts.
                return SortKey(core: core, insertRank: 0, letter: prefix, ptIndex: ptIndex)
            }
            return SortKey(core: core, insertRank: 1, letter: "", ptIndex: ptIndex)
        }
        if !prefix.isEmpty {
            return SortKey(core: core, insertRank: 0, letter: prefix, ptIndex: 0)
        }
        if !rest.isEmpty {
            return SortKey(core: core, insertRank: 2, letter: String(rest), ptIndex: 0)
        }
        return SortKey(core: core, insertRank: 1, letter: "", ptIndex: 0)
    }

    /// True if `lhs` should sort before `rhs` in real shooting-script order — e.g. for
    /// ["9", "9pt", "10", "11pt", "A20", "B20"], sorting with this comparator produces
    /// exactly that order, where plain alphabetical sorting would not.
    static func sortsBefore(_ lhs: String, _ rhs: String) -> Bool {
        sortKey(for: lhs) < sortKey(for: rhs)
    }

    /// Best-effort scene number extracted from a scene's title text, for a scene that
    /// predates the dedicated sceneNumber field (or a manually-typed title formatted like
    /// "9pt. INT. KITCHEN - DAY"). Returns "" if the title doesn't start with anything
    /// recognizable as a scene number.
    static func extractFromTitle(_ title: String) -> String {
        let pattern = #"^([A-Za-z]?\d+(?:[Pp][Tt]\d*)?[A-Za-z]?)\."#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else {
            return ""
        }
        return String(title[range])
    }
}

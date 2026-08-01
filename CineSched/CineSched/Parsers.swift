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

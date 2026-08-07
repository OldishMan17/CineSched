// FountainParser.swift
// Parses Fountain (.fountain) plain-text screenplay files and extracts scene
// information. Fountain has no XML structure like Final Draft's .fdx, so this
// reads scene headings and formatting cues from plain text, but it converges
// on the exact same FinalDraftParser.ParsedScene shape — and reuses
// FinalDraftParser's own scene-heading splitting and page/time estimation —
// so both import paths produce identical results downstream.

import Foundation

struct FountainParser {

    /// Parse a Fountain file and extract all scenes.
    static func parseScenes(from url: URL) throws -> [FinalDraftParser.ParsedScene] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return parseScenes(fromText: raw)
    }

    /// Parse Fountain source text directly (exposed for testing).
    static func parseScenes(fromText raw: String) -> [FinalDraftParser.ParsedScene] {
        let cleaned = stripNotesAndComments(raw)
        let lines = stripTitlePage(cleaned.components(separatedBy: .newlines))

        var scenes: [FinalDraftParser.ParsedScene] = []
        var pendingHeading: String?
        var pendingBody: [(type: String, text: String)] = []
        // Fountain has no explicit "end of dialogue" marker other than a blank
        // line or a new character cue, so this tracks whether we're still
        // inside a character's speech as we walk line by line.
        var inDialogueBlock = false

        func finishPendingScene() {
            defer {
                pendingHeading = nil
                pendingBody = []
                inDialogueBlock = false
            }
            guard let heading = pendingHeading else { return }

            let (explicitNumber, strippedHeading) = extractSceneNumber(heading)
            let (parsedNumber, location, timeOfDay) = FinalDraftParser.parseSceneHeading(strippedHeading)
            let finalNumber = explicitNumber ?? parsedNumber ?? "\(scenes.count + 1)"
            let eighths = FinalDraftParser.estimatePageEighths(from: pendingBody)

            scenes.append(FinalDraftParser.ParsedScene(
                sceneNumber: finalNumber,
                location: location,
                timeOfDay: timeOfDay,
                fullHeading: strippedHeading,
                pageEighths: eighths,
                estimatedMinutes: FinalDraftParser.estimateMinutes(fromEighths: eighths)
            ))
        }

        var index = 0
        while index < lines.count {
            defer { index += 1 }

            let line = lines[index].trimmingCharacters(in: .whitespaces)
            let previousBlank = index == 0 || lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty
            let nextLine = index + 1 < lines.count ? lines[index + 1].trimmingCharacters(in: .whitespaces) : ""
            let nextBlank = nextLine.isEmpty

            if line.isEmpty {
                inDialogueBlock = false
                continue
            }

            // Section headers (#) and synopses (=) are outline notes, not screenplay content.
            if line.hasPrefix("#") || (line.hasPrefix("=") && !line.hasPrefix("===")) {
                continue
            }
            // Page breaks ("===").
            if line.hasPrefix("===") {
                continue
            }

            if isSceneHeading(line) {
                finishPendingScene()
                pendingHeading = strippedForcedSceneHeading(line)
                inDialogueBlock = false
                continue
            }

            // Nothing to attribute this line to until we've seen a scene heading
            // (e.g. leading boilerplate before the first scene) — skip it.
            guard pendingHeading != nil else { continue }

            if line.hasPrefix("(") && line.hasSuffix(")") {
                pendingBody.append((type: "Parenthetical", text: line))
                inDialogueBlock = true
                continue
            }

            if isTransition(line) {
                pendingBody.append((type: "Transition", text: strippedForcedTransition(line)))
                inDialogueBlock = false
                continue
            }

            if isCharacterCue(line, previousBlank: previousBlank, nextBlank: nextBlank) {
                pendingBody.append((type: "Character", text: strippedForcedCharacter(line)))
                inDialogueBlock = true
                continue
            }

            if inDialogueBlock {
                pendingBody.append((type: "Dialogue", text: line))
                continue
            }

            pendingBody.append((type: "Action", text: strippedForcedAction(line)))
        }

        finishPendingScene()
        return scenes
    }

    // MARK: - Line classification

    private static let sceneHeadingPrefixes = [
        "INT.", "EXT.", "EST.", "INT/EXT.", "INT./EXT.", "I/E.",
        "INT ", "EXT ", "EST ", "INT/EXT ", "I/E "
    ]

    private static func isSceneHeading(_ line: String) -> Bool {
        if line.hasPrefix(".") && !line.hasPrefix("..") {
            return true // forced scene heading
        }
        let upper = line.uppercased()
        return sceneHeadingPrefixes.contains { upper.hasPrefix($0) }
    }

    private static func strippedForcedSceneHeading(_ line: String) -> String {
        if line.hasPrefix(".") && !line.hasPrefix("..") {
            return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private static func isTransition(_ line: String) -> Bool {
        if line.hasPrefix(">") && !line.hasSuffix("<") {
            return true // forced transition
        }
        let upper = line.uppercased()
        return upper == line && upper.hasSuffix("TO:")
    }

    private static func strippedForcedTransition(_ line: String) -> String {
        if line.hasPrefix(">") {
            return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private static func isCharacterCue(_ line: String, previousBlank: Bool, nextBlank: Bool) -> Bool {
        if line.hasPrefix("@") { return true } // forced character cue
        guard previousBlank, !nextBlank else { return false }

        // Strip a trailing extension like "(V.O.)" / "(CONT'D)" before checking case.
        var core = line
        if let parenRange = core.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            core.removeSubrange(parenRange)
        }
        guard !core.isEmpty, core.rangeOfCharacter(from: .letters) != nil else { return false }
        return core == core.uppercased()
    }

    private static func strippedForcedCharacter(_ line: String) -> String {
        if line.hasPrefix("@") {
            return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private static func strippedForcedAction(_ line: String) -> String {
        if line.hasPrefix("!") {
            return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if line.hasPrefix(">") && line.hasSuffix("<") {
            return String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    // MARK: - Scene numbers

    /// Fountain puts explicit scene numbers at the end of the heading line,
    /// e.g. "INT. HOUSE - DAY #12A#" — unlike FDX, which stores them separately.
    private static func extractSceneNumber(_ heading: String) -> (number: String?, strippedHeading: String) {
        guard let regex = try? NSRegularExpression(pattern: #"#([^#\n]+)#\s*$"#),
              let match = regex.firstMatch(in: heading, range: NSRange(heading.startIndex..., in: heading)),
              let numberRange = Range(match.range(at: 1), in: heading) else {
            return (nil, heading)
        }
        let number = String(heading[numberRange])
        var stripped = heading
        if let fullRange = Range(match.range, in: heading) {
            stripped.removeSubrange(fullRange)
        }
        return (number, stripped.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Preprocessing

    /// Strip Fountain boneyard notes [[ ... ]] and block comments /* ... */ so
    /// they never get counted as scene content or leak into scene text.
    private static func stripNotesAndComments(_ text: String) -> String {
        var result = text
        for pattern in [#"\[\[.*?\]\]"#, #"/\*.*?\*/"#] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        return result
    }

    /// Drop a leading Fountain title page block (key: value lines up to the first blank line).
    private static func stripTitlePage(_ lines: [String]) -> [String] {
        guard let firstNonEmptyIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return lines
        }
        let firstLine = lines[firstNonEmptyIndex].trimmingCharacters(in: .whitespaces)
        guard !isSceneHeading(firstLine),
              firstLine.range(of: #"^[A-Za-z][A-Za-z0-9 _\-]*:\s*\S"#, options: .regularExpression) != nil else {
            return lines
        }
        var end = firstNonEmptyIndex
        while end < lines.count && !lines[end].trimmingCharacters(in: .whitespaces).isEmpty {
            end += 1
        }
        return Array(lines[end...])
    }
}

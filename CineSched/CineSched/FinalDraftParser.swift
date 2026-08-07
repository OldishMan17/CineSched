// FinalDraftParser.swift
// Parses Final Draft .fdx files and extracts scene information

import Foundation

struct FinalDraftParser {
    
    enum TimeOfDay {
        case day
        case night
        case unknown
        
        init(from text: String) {
            let lowercased = text.lowercased()
            if lowercased.contains("day") || lowercased.contains("morning") || lowercased.contains("afternoon") {
                self = .day
            } else if lowercased.contains("night") || lowercased.contains("evening") || lowercased.contains("dusk") || lowercased.contains("dawn") {
                self = .night
            } else {
                self = .unknown
            }
        }
    }
    
    struct ParsedScene {
        let sceneNumber: String
        let location: String
        let timeOfDay: TimeOfDay
        let fullHeading: String
        /// Page length in eighths (matches how manually-created Scenes store duration —
        /// see CALLSHEET_SPEC.md §3.2), estimated from the scene's body text.
        let pageEighths: Int
        /// Estimated shoot time in minutes, scaled from pageEighths.
        let estimatedMinutes: Int
    }

    /// Parse an FDX file and extract all scenes
    static func parseScenes(from url: URL) throws -> [ParsedScene] {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        let delegate = FDXParserDelegate()
        parser.delegate = delegate

        guard parser.parse() else {
            if let error = parser.parserError {
                throw error
            }
            throw NSError(domain: "FinalDraftParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse FDX file"])
        }

        return delegate.scenes
    }

    // MARK: - Page length estimation

    /// A standard screenplay page (Courier 12, 1" margins) holds roughly 55 lines once
    /// scene headings, action, and dialogue are mixed together. Dialogue is indented on
    /// both sides so it wraps at a much narrower column than action.
    private static let linesPerPage: Double = 55
    private static let actionCharsPerLine: Double = 60
    private static let dialogueCharsPerLine: Double = 35

    /// Estimate a scene's length in eighths of a page from its FDX body paragraphs
    /// (everything between one Scene Heading and the next). This is what was missing
    /// before: the parser only ever looked at scene headings, so every imported scene
    /// got the same flat placeholder length regardless of how long it actually was.
    static func estimatePageEighths(from bodyLines: [(type: String, text: String)]) -> Int {
        // +1 line for the scene heading itself, which isn't included in bodyLines.
        var totalLines: Double = 1
        for line in bodyLines {
            let charCount = Double(line.text.count)
            switch line.type {
            case "Dialogue":
                totalLines += max(1, (charCount / dialogueCharsPerLine).rounded(.up))
            case "Character", "Parenthetical", "Transition", "Shot":
                totalLines += 1
            default: // Action, General, and anything else reads at full column width
                totalLines += max(1, (charCount / actionCharsPerLine).rounded(.up))
            }
        }
        let pages = totalLines / linesPerPage
        let eighths = Int((pages * 8).rounded())
        // A scene is never less than 1/8 page, matching how manually-created scenes are entered.
        return max(eighths, 1)
    }

    /// Scale the shoot-time estimate with page length rather than using one flat number
    /// for every scene. 15 min/eighth matches this app's own previous placeholder for a
    /// minimal (1/8 page) scene; longer scenes now get proportionally more time instead
    /// of the same 15 minutes as everything else.
    static func estimateMinutes(fromEighths eighths: Int) -> Int {
        let minutesPerEighth = 15
        return max(eighths * minutesPerEighth, minutesPerEighth)
    }
    
    /// Extract scene components from a scene heading
    /// Examples:
    /// "3. EXT. WOODS - DAY" -> (number: "3", location: "EXT. WOODS", time: .day)
    /// "INT. BEDROOM - NIGHT" -> (number: nil, location: "INT. BEDROOM", time: .night)
    static func parseSceneHeading(_ heading: String) -> (number: String?, location: String, timeOfDay: TimeOfDay) {
        var workingHeading = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Extract scene number if present (e.g., "3.", "12A.", "5B.")
        var sceneNumber: String? = nil
        let numberPattern = #"^(\d+[A-Z]?)\.\s*"#
        if let regex = try? NSRegularExpression(pattern: numberPattern),
           let match = regex.firstMatch(in: workingHeading, range: NSRange(workingHeading.startIndex..., in: workingHeading)) {
            if let range = Range(match.range(at: 1), in: workingHeading) {
                sceneNumber = String(workingHeading[range])
                // Remove the number from the heading
                if let fullRange = Range(match.range, in: workingHeading) {
                    workingHeading.removeSubrange(fullRange)
                }
            }
        }
        
        // Split by hyphen or dash to separate location from time
        let components = workingHeading.components(separatedBy: CharacterSet(charactersIn: "-–—"))
        
        var location = workingHeading
        var timeOfDay = TimeOfDay.unknown
        
        if components.count >= 2 {
            // Last component is typically the time of day
            location = components.dropLast().joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
            let timeString = components.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            timeOfDay = TimeOfDay(from: timeString)
        } else {
            // No dash found, try to detect time in the full string
            timeOfDay = TimeOfDay(from: workingHeading)
            // If we found a time indicator, try to remove it from location
            if timeOfDay != .unknown {
                location = workingHeading.replacingOccurrences(of: #"\b(day|night|morning|afternoon|evening|dusk|dawn)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Clean up location (remove extra spaces)
        location = location.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (sceneNumber, location, timeOfDay)
    }
}

// MARK: - XML Parser Delegate

private class FDXParserDelegate: NSObject, XMLParserDelegate {
    var scenes: [FinalDraftParser.ParsedScene] = []

    private var currentType = ""
    private var currentText = ""
    private var inText = false
    private var textElements: [String] = []
    // Depth of ALL <Paragraph> nesting, not just inside Scene Heading — FDX can nest
    // Paragraphs (e.g. SceneArcBeats) inside Action/Dialogue paragraphs too, and those
    // nested ones must not be double-counted as separate body lines.
    private var paragraphDepth = 0

    // The heading for the scene currently being accumulated, plus its body paragraphs
    // collected so far (type + text for each, used to estimate page length), and the
    // Length Final Draft baked into that same heading's <SceneProperties> (if any).
    private var pendingHeading: String?
    private var pendingBody: [(type: String, text: String)] = []
    private var pendingLength: String?

    // Scratch value for the Length attribute captured WHILE parsing the Scene Heading
    // paragraph currently being read. This has to stay separate from pendingLength: a
    // Scene Heading's <SceneProperties> child is read before that paragraph closes, which
    // is also the moment the *previous* scene gets finished via finishPendingScene() — if
    // this fed pendingLength directly, the new heading's own Length would already have
    // overwritten the previous scene's Length before it got consumed, handing every scene
    // its next neighbor's page count instead of its own. Confirmed against a real .fdx:
    // scene 1 (Length="2 6/8") was coming out with scene 2's "6", and scene 2 was falling
    // through to the text estimate entirely.
    private var headingLengthScratch: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "Paragraph" {
            paragraphDepth += 1
            if paragraphDepth == 1 {
                currentType = attributeDict["Type"] ?? ""
                textElements = []
                if currentType == "Scene Heading" {
                    headingLengthScratch = nil
                }
            }
        } else if elementName == "Text" && paragraphDepth == 1 {
            // Only collect Text for top-level paragraphs, not nested ones (e.g. SceneArcBeats)
            inText = true
            currentText = ""
        } else if elementName == "SceneProperties" && paragraphDepth == 1 && currentType == "Scene Heading" {
            if let length = attributeDict["Length"], !length.isEmpty {
                headingLengthScratch = length
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Text" && inText {
            if !currentText.isEmpty {
                textElements.append(currentText)
            }
            currentText = ""
            inText = false
        } else if elementName == "Paragraph" {
            if paragraphDepth == 1 {
                let rawText = textElements.joined().trimmingCharacters(in: .whitespacesAndNewlines)

                if currentType == "Scene Heading" {
                    // A new scene heading closes out whatever scene we were accumulating,
                    // scored against the body text (and Length, if any) collected since
                    // its own heading. Finish the OLD scene before adopting the NEW
                    // heading's own headingLengthScratch, so the old scene's Length isn't
                    // clobbered by the new one's.
                    finishPendingScene()
                    if !rawText.isEmpty {
                        pendingHeading = rawText.uppercased()  // AUTO-CAPITALIZE
                        pendingLength = headingLengthScratch
                    }
                } else if !rawText.isEmpty {
                    pendingBody.append((type: currentType, text: rawText))
                }

                currentType = ""
                textElements = []
            }
            paragraphDepth -= 1
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        finishPendingScene()
    }

    private func finishPendingScene() {
        defer { pendingHeading = nil; pendingBody = []; pendingLength = nil }
        guard let heading = pendingHeading else { return }

        let (number, location, timeOfDay) = FinalDraftParser.parseSceneHeading(heading)
        let finalNumber = number ?? "\(scenes.count + 1)"
        // Prefer Final Draft's own baked-in pagination (<SceneProperties Length="...">)
        // over the text-based estimate — it's the exact value Final Draft's pagination
        // engine computed, not an approximation. Only estimate from body text when a
        // scene is missing that attribute.
        let eighths = pendingLength.flatMap(FractionParser.parseToEighths)
            ?? FinalDraftParser.estimatePageEighths(from: pendingBody)

        let scene = FinalDraftParser.ParsedScene(
            sceneNumber: finalNumber,
            location: location,
            timeOfDay: timeOfDay,
            fullHeading: heading,
            pageEighths: eighths,
            estimatedMinutes: FinalDraftParser.estimateMinutes(fromEighths: eighths)
        )

        scenes.append(scene)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print("XML Parse Error: \(parseError.localizedDescription)")
    }
}

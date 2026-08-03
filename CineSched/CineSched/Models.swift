// Models.swift
// Core data models for CineSched

import SwiftUI

// MARK: - DayNightType

enum DayNightType: String, Codable, CaseIterable {
    case day    = "DAY"
    case night  = "NIGHT"
    case custom = "CUSTOM"

    var color: Color {
        switch self {
        case .day:    return Color.orange
        case .night:  return Color.blue
        case .custom: return Color.green
        }
    }

    var displayName: String { rawValue }
}

// MARK: - Production

/// A single production (e.g. one film/show) that scenes belong to. Only one is ever created
/// or shown today — there's no UI yet to add another or switch between them — but every
/// scene already carries a productionID so that future step doesn't require touching every
/// scene again. See CineSched/DOCS/CALLSHEET_SPEC.md §5 for why this comes first.
struct Production: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String = "") {
        self.id   = id
        self.name = name
    }

    /// Fixed (not random) id for "the one production" every scene belongs to today: every
    /// freshly created scene gets this id, and every scene loaded from a project file saved
    /// before productions existed is migrated to this same id — so old data and new data
    /// always agree on which production they're in, with no per-file guessing required.
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

// MARK: - Scene

struct Scene: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var duration: Int
    var estimatedTime: Int
    var dayNightType: DayNightType
    var cast: [String]
    var summary: String
    var productionID: UUID
    // Real scene numbers are text, not integers — "9pt", "A20", "60pt4" are all valid and
    // none of them fit in an Int. See CALLSHEET_SPEC.md §3.1 and SceneNumberParser in
    // Parsers.swift for the natural-sort comparator that keeps these in real shooting-script
    // order (9, 9pt, 10, 11pt, A20, B20) rather than plain alphabetical order.
    var sceneNumber: String

    init(
        title: String,
        duration: Int,
        estimatedTime: Int,
        dayNightType: DayNightType = .day,
        cast: [String] = [],
        summary: String = "",
        productionID: UUID = Production.defaultID,
        sceneNumber: String? = nil
    ) {
        self.id            = UUID()
        self.title         = title
        self.duration      = duration
        self.estimatedTime = estimatedTime
        self.dayNightType  = dayNightType
        self.cast          = cast
        self.summary       = summary
        self.productionID  = productionID
        // Defaults to whatever number-looking prefix is already in the typed title (e.g.
        // "9pt. INT. KITCHEN - DAY") so scenes get a usable scene number without requiring
        // a dedicated input field yet.
        self.sceneNumber   = sceneNumber ?? SceneNumberParser.extractFromTitle(title)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, duration, estimatedTime, dayNightType, cast, summary, productionID, sceneNumber
    }

    init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,         forKey: .id)
        title         = try c.decode(String.self,       forKey: .title)
        // duration is pages stored as an integer count of eighths (15 == "1 7/8"). Every
        // scene this app has ever saved already stores it that way, so this is the path
        // almost every file takes. The two fallbacks below only matter for a file from
        // somewhere else (or hand-edited) that stored pages as a plain decimal (1.875) or
        // a fraction string ("1 7/8", "0.625") instead — see CALLSHEET_SPEC.md §3.2 for why
        // that's a real bug to guard against: decimal page counts don't accumulate cleanly
        // when totaled, which is exactly what storing eighths as an integer avoids.
        if let eighths = try? c.decode(Int.self, forKey: .duration) {
            duration = eighths
        } else if let decimalPages = try? c.decode(Double.self, forKey: .duration) {
            duration = Int((decimalPages * 8).rounded())
        } else if let text = try? c.decode(String.self, forKey: .duration),
                  let parsed = FractionParser.parseToEighths(text) {
            duration = parsed
        } else {
            duration = 0
        }
        estimatedTime = try c.decode(Int.self,          forKey: .estimatedTime)
        dayNightType  = try c.decode(DayNightType.self, forKey: .dayNightType)
        summary       = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        // Absent on any scene saved before productions existed — migrate it to the one
        // default production rather than leaving it unassigned.
        productionID  = try c.decodeIfPresent(UUID.self, forKey: .productionID) ?? Production.defaultID
        // Absent on any scene saved before this field existed — fall back to whatever
        // number-looking prefix is already sitting in the title text, same as a brand new
        // scene created from a typed title would get.
        if let existing = try c.decodeIfPresent(String.self, forKey: .sceneNumber), !existing.isEmpty {
            sceneNumber = existing
        } else {
            sceneNumber = SceneNumberParser.extractFromTitle(title)
        }
        if let array = try? c.decode([String].self, forKey: .cast) {
            cast = array
        } else if let legacy = try? c.decode(String.self, forKey: .cast) {
            cast = legacy.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            cast = []
        }
    }
}

// MARK: - Location

struct Location: Identifiable, Codable, Hashable {
    let id: UUID
    var name:    String
    var address: String

    init(name: String = "", address: String = "") {
        self.id      = UUID()
        self.name    = name
        self.address = address
    }
}

// MARK: - CallSheetData

struct CallSheetData: Codable {
    var generalCallTime: String
    var locations:       [Location]
    var castOverride:    [String]?       // raw character names (NOT resolved "Actor — Character" text) so
                                          // renaming an actor or character always re-resolves correctly,
                                          // even for a day whose cast list was manually edited
    var crewOverride:    [String]?       // legacy, pre-3.4 saves only — mixed roster display-strings and
                                          // one-off names together; kept so old project files still decode
    var crewIDOverride:  [UUID]?         // roster CrewMember IDs explicitly selected for this day — an ID
                                          // reference instead of frozen text, so a roster rename ripples
                                          // through automatically
    var crewOneOffs:     [String]?       // free-typed crew not in the roster; these have no stable identity
                                          // to rename, so they're just kept as plain text
    var notes:           String

    init(
        generalCallTime: String     = "",
        locations:       [Location] = [],
        castOverride:    [String]?  = nil,
        crewOverride:    [String]?  = nil,
        crewIDOverride:  [UUID]?    = nil,
        crewOneOffs:     [String]?  = nil,
        notes:           String    = ""
    ) {
        self.generalCallTime = generalCallTime
        self.locations       = locations
        self.castOverride    = castOverride
        self.crewOverride    = crewOverride
        self.crewIDOverride  = crewIDOverride
        self.crewOneOffs     = crewOneOffs
        self.notes           = notes
    }

    /// Resolves the raw character names (auto-pulled from scenes, or the manually-edited
    /// override) to "Actor — Character" using the *current* cast list — always live, so a
    /// rename in Production Setup is reflected immediately, whether or not this day's cast
    /// has ever been manually edited.
    func resolvedCast(from scenes: [Scene], productionInfo: ProductionInfo? = nil) -> [String] {
        let characters = castOverride ?? Array(Set(scenes.flatMap { $0.cast })).sorted()
        guard let production = productionInfo, !production.castList.isEmpty else {
            return characters
        }
        return characters.map { character in
            if let match = production.castList.first(where: {
                $0.characterName.trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare(character.trimmingCharacters(in: .whitespaces)) == .orderedSame
            }) {
                return match.displayString
            }
            return character
        }
    }

    /// Resolves selected crew to "Name — Role" using the *current* roster for anyone selected
    /// by ID, so a name/role edit in Production Setup ripples through immediately. One-off
    /// crew (not in the roster) are plain text with no identity to resolve.
    func resolvedCrew(productionInfo: ProductionInfo) -> [String] {
        if crewIDOverride != nil || crewOneOffs != nil {
            let roster = productionInfo.crew
            let selected = (crewIDOverride ?? []).compactMap { id in
                roster.first(where: { $0.id == id })?.displayString
            }
            return selected + (crewOneOffs ?? [])
        }
        // Pre-3.4 project file that hasn't been re-saved since: fall back to the old frozen
        // text so nothing appears to vanish, but it won't ripple until the day is saved again.
        if let legacy = crewOverride { return legacy }
        return productionInfo.crew
            .filter { $0.isDailyDefault }
            .map    { $0.displayString }
    }
}

// MARK: - ContactMethod

/// One typed contact method — a person can have several (a cell, a separate home or office
/// number, an email, an emergency contact), not just one or two plain text fields. See
/// CALLSHEET_SPEC.md §3.6: real phone numbers carry their type in how they're written
/// (a trailing "555.555.0182c" for cell, "h" for home, etc.) — this structured `type` field
/// replaces the need for that notation going forward, so `value` is always just the plain
/// number or address, never a suffix to parse.
///
/// Storing this is a separate concern from ever *printing* it — CALLSHEET_SPEC.md §2.8:
/// union call sheets omit crew phone/email entirely while indie/student sheets print them
/// inline. That's a future per-production display toggle; nothing here assumes contacts
/// will always be shown.
enum ContactType: String, Codable, CaseIterable {
    case cell, home, office, email, emergency, fax, other

    var displayName: String {
        switch self {
        case .cell:      return "Cell"
        case .home:      return "Home"
        case .office:    return "Office"
        case .email:     return "Email"
        case .emergency: return "Emergency"
        case .fax:       return "Fax"
        case .other:     return "Other"
        }
    }
}

struct ContactMethod: Identifiable, Codable, Hashable {
    let id: UUID
    var type:  ContactType
    var value: String

    init(type: ContactType = .cell, value: String = "") {
        self.id    = UUID()
        self.type  = type
        self.value = value
    }
}

// MARK: - CrewMember

struct CrewMember: Identifiable, Codable, Hashable {
    let id: UUID
    var name:           String
    var role:           String
    var isDailyDefault: Bool
    var contacts:       [ContactMethod]

    init(name: String = "", role: String = "", isDailyDefault: Bool = false, contacts: [ContactMethod] = []) {
        self.id             = UUID()
        self.name           = name
        self.role           = role
        self.isDailyDefault = isDailyDefault
        self.contacts       = contacts
    }

    enum CodingKeys: String, CodingKey {
        case id, name, role, isDailyDefault, contacts
    }

    init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        name           = try c.decode(String.self, forKey: .name)
        role           = try c.decode(String.self, forKey: .role)
        isDailyDefault = try c.decodeIfPresent(Bool.self, forKey: .isDailyDefault) ?? false
        // Absent on any crew member saved before contacts existed — no prior field held
        // phone/email at all, so there's nothing to migrate from, just an empty list.
        contacts       = try c.decodeIfPresent([ContactMethod].self, forKey: .contacts) ?? []
    }

    var displayString: String {
        role.isEmpty ? name : "\(name) — \(role)"
    }

    /// The first Cell-type entry, if any — shown as a quick-glance "primary phone" wherever
    /// opening the full Contacts popover would be overkill (a sidebar row, a printed
    /// contact sheet). The full list, and the ability to have several numbers, is unchanged
    /// — this is just which one gets a shortcut.
    var primaryPhone: String? {
        contacts.first(where: { $0.type == .cell })?.value
    }

    /// The first Email-type entry, if any — same idea as primaryPhone.
    var primaryEmail: String? {
        contacts.first(where: { $0.type == .email })?.value
    }
}

// MARK: - CastMember

// MARK: - DateRange (actor unavailability)

/// A simple inclusive date range, used to mark when an actor isn't available. Day-level
/// granularity only (no times), matching the rest of the app's day-based scheduling.
struct DateRange: Identifiable, Codable, Hashable {
    let id: UUID
    var start: Date
    var end: Date

    init(start: Date, end: Date) {
        self.id    = UUID()
        self.start = start
        self.end   = max(start, end)   // keep end from ever preceding start
    }

    func contains(_ date: Date) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: date)
        return d >= cal.startOfDay(for: start) && d <= cal.startOfDay(for: end)
    }
}

// MARK: - CastMember

struct CastMember: Identifiable, Codable, Hashable {
    let id: UUID
    var actorName:     String
    var characterName: String
    var unavailableRanges: [DateRange]
    var contacts:      [ContactMethod]

    init(
        actorName: String = "",
        characterName: String = "",
        unavailableRanges: [DateRange] = [],
        contacts: [ContactMethod] = []
    ) {
        self.id                = UUID()
        self.actorName         = actorName
        self.characterName     = characterName
        self.unavailableRanges = unavailableRanges
        self.contacts          = contacts
    }

    enum CodingKeys: String, CodingKey {
        case id, actorName, characterName, unavailableRanges, contacts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self,   forKey: .id)
        actorName         = try c.decode(String.self, forKey: .actorName)
        characterName     = try c.decode(String.self, forKey: .characterName)
        unavailableRanges = try c.decodeIfPresent([DateRange].self, forKey: .unavailableRanges) ?? []
        // Absent on any cast member saved before contacts existed — no prior field held
        // phone/email at all, so there's nothing to migrate from, just an empty list.
        contacts          = try c.decodeIfPresent([ContactMethod].self, forKey: .contacts) ?? []
    }

    var displayString: String {
        actorName.isEmpty ? characterName : "\(actorName) — \(characterName)"
    }

    /// The first Cell-type entry, if any — see CrewMember.primaryPhone for why.
    var primaryPhone: String? {
        contacts.first(where: { $0.type == .cell })?.value
    }

    /// The first Email-type entry, if any — see CrewMember.primaryEmail for why.
    var primaryEmail: String? {
        contacts.first(where: { $0.type == .email })?.value
    }
}

// MARK: - Scene tooltip

extension Scene {
    /// Hover-tooltip text combining the scene's quick facts, cast, and summary — shown via
    /// the app's own faster tooltip (`.fastTooltip`, see HoverTooltip.swift) in both the
    /// Boneyard and the calendar.
    var tooltipText: String {
        let titleLine = sceneNumber.isEmpty ? title : "\(sceneNumber) \(title)"
        var lines: [String] = [titleLine]
        lines.append("Pages: \(FractionParser.formatEighths(duration))")
        lines.append("Est: \(formattedTime(estimatedTime))")
        if !cast.isEmpty {
            lines.append("Cast: " + cast.joined(separator: ", "))
        }
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty {
            lines.append(trimmedSummary)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - KeyContact

/// A single named production contact who isn't part of a roster — the Director, the
/// Producer. Same idea as CrewMember/CastMember's contact handling (a name plus a list of
/// typed ContactMethod entries), just for a role where there's exactly one person rather
/// than a list of them.
struct KeyContact: Codable, Equatable {
    var name: String
    var contacts: [ContactMethod]

    init(name: String = "", contacts: [ContactMethod] = []) {
        self.name     = name
        self.contacts = contacts
    }

    var primaryPhone: String? { contacts.first(where: { $0.type == .cell })?.value }
    var primaryEmail: String? { contacts.first(where: { $0.type == .email })?.value }
}

// MARK: - ProductionInfo

struct ProductionInfo: Codable, Equatable {
    var companyName:   String
    var director:      KeyContact
    var producer:      KeyContact
    var contactNumber: String
    var crew:          [CrewMember]
    var castList:      [CastMember]

    init(
        companyName:   String = "",
        director:      KeyContact = KeyContact(),
        producer:      KeyContact = KeyContact(),
        contactNumber: String = "",
        crew:          [CrewMember] = [],
        castList:      [CastMember] = []
    ) {
        self.companyName   = companyName
        self.director      = director
        self.producer      = producer
        self.contactNumber = contactNumber
        self.crew          = crew
        self.castList      = castList
    }

    // Raw string values are unchanged from before ("directorName", "producerName") even
    // though the Swift property names are now `director`/`producer` — keeps the on-disk
    // JSON key stable while the value shape underneath changes from a plain string to a
    // structured {name, contacts} object.
    enum CodingKeys: String, CodingKey {
        case companyName
        case directorName
        case producerName
        case contactNumber, crew, castList
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        companyName   = try c.decode(String.self, forKey: .companyName)
        director      = Self.decodeKeyContact(c, key: .directorName)
        producer      = Self.decodeKeyContact(c, key: .producerName)
        contactNumber = try c.decode(String.self, forKey: .contactNumber)
        crew          = try c.decode([CrewMember].self, forKey: .crew)
        castList      = try c.decode([CastMember].self, forKey: .castList)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(companyName,   forKey: .companyName)
        try c.encode(director,      forKey: .directorName)
        try c.encode(producer,      forKey: .producerName)
        try c.encode(contactNumber, forKey: .contactNumber)
        try c.encode(crew,          forKey: .crew)
        try c.encode(castList,      forKey: .castList)
    }

    /// A key contact might be in any of three states depending on when the file was saved:
    /// a structured {name, contacts} object (current format), a plain string (Director
    /// existed before Producer or contacts did — just a name, no contacts), or absent
    /// entirely (Producer didn't exist at all before a few steps ago). Tries each in turn
    /// rather than assuming the newest format.
    private static func decodeKeyContact(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> KeyContact {
        if let structured = try? c.decode(KeyContact.self, forKey: key) {
            return structured
        }
        if let legacyName = try? c.decode(String.self, forKey: key) {
            return KeyContact(name: legacyName)
        }
        return KeyContact()
    }
}

// MARK: - BannerItem

/// A non-scene entry that can sit in a day's schedule alongside scenes — a company move, a
/// safety meeting, pre-lighting, a production meeting. Deliberately lightweight compared to
/// Scene: a call sheet renders one of these as a single bold banner line spanning the whole
/// table width, not a full scene row — see CALLSHEET_LAYOUT.md §3.2 and
/// CALLSHEET_SPEC.md §2.4.
struct BannerItem: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var note: String
    // Minutes. Not every company move, safety meeting, or pre-light takes the same amount
    // of time, so this is a per-item estimate the same way a scene has one — it counts
    // toward the day's total estimated time alongside scenes' own estimates.
    var estimatedTime: Int

    init(label: String = "", note: String = "", estimatedTime: Int = 0) {
        self.id            = UUID()
        self.label         = label
        self.note          = note
        self.estimatedTime = estimatedTime
    }

    enum CodingKeys: String, CodingKey {
        case id, label, note, estimatedTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,   forKey: .id)
        label         = try c.decode(String.self, forKey: .label)
        note          = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        // Absent on a banner saved in the brief window before this field existed.
        estimatedTime = try c.decodeIfPresent(Int.self, forKey: .estimatedTime) ?? 0
    }
}

// MARK: - DayItem

/// One entry in a day's ordered schedule — either a Scene or a BannerItem, in whatever
/// order the user arranges them. This is what makes "Scene 12, then a PRE-LIGHT banner,
/// then Scene 13" representable at all: both kinds of entry live in the *same* list, at
/// the *same* level, rather than scenes being the list and banners being some separate,
/// unordered thing attached to the day.
enum DayItem: Identifiable, Hashable {
    case scene(Scene)
    case banner(BannerItem)

    var id: UUID {
        switch self {
        case .scene(let scene):   return scene.id
        case .banner(let banner): return banner.id
        }
    }
}

extension DayItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, scene, banner
    }
    private enum ItemType: String, Codable {
        case scene, banner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // No "type" key at all only happens if something outside this app's own encoder
        // hand-wrote a day item without one — fall back to treating it as a scene, since
        // that's the only kind of entry that has ever existed until now.
        let type = try c.decodeIfPresent(ItemType.self, forKey: .type) ?? .scene
        switch type {
        case .banner:
            self = .banner(try c.decode(BannerItem.self, forKey: .banner))
        case .scene:
            self = .scene(try c.decode(Scene.self, forKey: .scene))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .scene(let scene):
            try c.encode(ItemType.scene, forKey: .type)
            try c.encode(scene, forKey: .scene)
        case .banner(let banner):
            try c.encode(ItemType.banner, forKey: .type)
            try c.encode(banner, forKey: .banner)
        }
    }
}

// MARK: - ShootDay

struct ShootDay: Identifiable, Codable {
    let id: UUID
    var date:      Date
    // The single ordered list of what's happening this day — scenes and banners together,
    // in the order they'll shoot. See DayItem above for why this is one list, not two.
    var items:     [DayItem]
    var callSheet: CallSheetData

    init(date: Date, scenes: [Scene] = [], callSheet: CallSheetData = CallSheetData()) {
        self.id        = UUID()
        self.date      = date
        self.items     = scenes.map { .scene($0) }
        self.callSheet = callSheet
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, items, scenes, callSheet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self, forKey: .id)
        date      = try c.decode(Date.self, forKey: .date)
        callSheet = try c.decodeIfPresent(CallSheetData.self, forKey: .callSheet) ?? CallSheetData()
        if let decodedItems = try c.decodeIfPresent([DayItem].self, forKey: .items) {
            items = decodedItems
        } else {
            // A file saved before DayItem existed only ever had a flat "scenes" array —
            // its existing order is already the correct shooting order, so it's kept as-is,
            // just wrapped as scene items.
            let legacyScenes = try c.decodeIfPresent([Scene].self, forKey: .scenes) ?? []
            items = legacyScenes.map { .scene($0) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(items, forKey: .items)
        try c.encode(callSheet, forKey: .callSheet)
    }

    /// A view of just the scene entries, in order — nearly everything in the app only
    /// cares about scenes, not banners, so this lets almost every existing read site keep
    /// working completely unchanged.
    ///
    /// Setting this replaces the scene entries with the given array, in the given order —
    /// which is exactly how every existing scene edit already works (add one, remove one,
    /// reorder by drag, swap two days' whole scene lists): each of those becomes "read the
    /// current scenes, apply one array change, write the result back," and this setter is
    /// what "write back" now means. Any banners already on the day are kept, moved to the
    /// end. That's a deliberate simplification — there's no UI yet to place a banner at a
    /// specific position relative to scenes, so there's nothing meaningful yet to preserve
    /// about exactly where a banner sat through a full scene-list rewrite. Revisit once
    /// banner-editing UI exists.
    var scenes: [Scene] {
        get {
            items.compactMap {
                if case .scene(let scene) = $0 { return scene }
                return nil
            }
        }
        set {
            let banners = items.filter {
                if case .banner = $0 { return true }
                return false
            }
            items = newValue.map { .scene($0) } + banners
        }
    }

    /// A view of just the banner entries, in order — read-only; banners are added/removed/
    /// reordered through `items` directly (see CalendarView.swift), since unlike scenes
    /// there's no legacy call site expecting a plain settable array of them.
    var banners: [BannerItem] {
        items.compactMap {
            if case .banner(let banner) = $0 { return banner }
            return nil
        }
    }

    // Pages only ever come from scenes — a banner isn't shootable, so it has no page count.
    var totalDuration: Int { scenes.reduce(0) { $0 + $1.duration } }
    // Time, unlike pages, includes banners too: a company move or safety meeting takes real
    // time out of the day just like a scene does, so it belongs in the day's total.
    var totalEstimatedTime: Int {
        scenes.reduce(0) { $0 + $1.estimatedTime } + banners.reduce(0) { $0 + $1.estimatedTime }
    }

    var dayScenes:    [Scene] { scenes.filter { $0.dayNightType == .day } }
    var nightScenes:  [Scene] { scenes.filter { $0.dayNightType == .night } }
    var customScenes: [Scene] { scenes.filter { $0.dayNightType == .custom } }

    var totalDayDuration:   Int { dayScenes.reduce(0)   { $0 + $1.duration } }
    var totalNightDuration: Int { nightScenes.reduce(0) { $0 + $1.duration } }

    var allCast: [String] {
        Array(Set(scenes.flatMap { $0.cast })).sorted()
    }

    var hasCallSheetData: Bool {
        !callSheet.generalCallTime.isEmpty ||
        !callSheet.locations.isEmpty       ||
        !callSheet.notes.isEmpty
    }
}

// MARK: - ProjectData

struct ProjectData: Codable {
    var allScenes:          [Scene]
    var shootDays:          [ShootDay]
    var projectTitle:       String
    var createdDate:        Date
    var isShiftModeEnabled: Bool?
    var productionInfo:     ProductionInfo?
    var productions:        [Production]?   // absent on any file saved before productions existed

    init(
        allScenes:          [Scene],
        shootDays:          [ShootDay],
        projectTitle:       String = "Untitled Movie",
        isShiftModeEnabled: Bool?  = false,
        createdDate:        Date   = Date(),
        productionInfo:     ProductionInfo? = nil,
        productions:        [Production]?   = nil
    ) {
        self.allScenes          = allScenes
        self.shootDays          = shootDays
        self.projectTitle       = projectTitle
        self.createdDate        = createdDate
        self.isShiftModeEnabled = isShiftModeEnabled
        self.productionInfo     = productionInfo
        self.productions        = productions
    }
}

// MARK: - Legacy Support

struct LegacyProjectData: Codable {
    var allScenes: [Scene]
    var shootDays: [ShootDay]
}

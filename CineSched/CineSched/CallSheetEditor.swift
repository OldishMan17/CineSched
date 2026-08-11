// CallSheetEditor.swift
// Per-day call sheet editor — opened by clicking a date header in the calendar.

import SwiftUI

struct CallSheetEditor: View {
    @Binding var shootDay: ShootDay
    let productionInfo: ProductionInfo
    /// The nearest prior shoot day (by date) whose basecamp/crew park/hospital list isn't
    /// all empty — the source for "Copy from Previous Day." Computed by the caller (it needs
    /// the full shootDays array, which this view doesn't otherwise have); nil when there's no
    /// usable prior day, in which case that action is hidden rather than shown disabled.
    var previousDayCallSheet: CallSheetData? = nil
    /// The full production schedule — needed to auto-derive each cast member's S/W/F status
    /// (their earliest/latest scheduled day across every day, not just this one). A snapshot
    /// as of when this sheet opened, same as previousDayCallSheet; doesn't live-update if
    /// another day changes while this sheet is open.
    var allShootDays: [ShootDay] = []
    @Binding var isPresented: Bool
    let onSave: () -> Void
    let onExportPDF: (ShootDay) -> Void

    @State private var callTime:     String     = ""
    @State private var shootingCallTime: String = ""
    @State private var breakfastTime: String = ""
    @State private var lunchTime:     String = ""
    @State private var dinnerTime:    String = ""
    @State private var showCrewMealCount: Bool = true
    @State private var basecamp:      String = ""
    @State private var crewPark:      String = ""
    @State private var hospitals:     [Hospital] = []
    @State private var sunrise:          String = ""
    @State private var sunset:           String = ""
    @State private var weatherCondition: String = ""
    @State private var wind:             String = ""
    @State private var gusts:            String = ""
    @State private var weatherHi:        String = ""
    @State private var weatherLo:        String = ""
    @State private var pop:              String = ""
    @State private var locations:    [Location] = []
    @State private var castCharacters: [String] = []   // raw character names, NOT "Actor — Character" text
    @State private var castIsEdited: Bool       = false
    @State private var notes:        String     = ""

    // Cast table's per-character columns — all keyed by normalized (trimmed, lowercased)
    // character name, dictionary-backed rather than parallel arrays so add/remove on
    // castCharacters never has to keep six other arrays index-aligned with it.
    @State private var castStatusOverride: [String: String] = [:]   // blank/missing = use auto-derived
    @State private var castPickup: [String: String] = [:]
    @State private var castHMW:    [String: String] = [:]
    @State private var castBlock:  [String: String] = [:]
    @State private var castSet:    [String: String] = [:]
    @State private var castNotesByCharacter: [String: String] = [:]

    private static let castStatusOptions = ["S", "SW", "W", "WF", "F", "SWF", "H", "R", "T", "D", "SWD", "WD"]

    // Crew state — parallel arrays track checked/counted/call-time state, all indexed to
    // allRosterEntries
    @State private var crewChecked:  [Bool]   = []
    @State private var crewCounted:  [Bool]   = []   // headcount — only editable/shown per-person when showHeadcount is on
    @State private var showHeadcount: Bool    = false
    @State private var crewCallTimes: [String] = []  // per-person call time — shown for any selected crew member
    @State private var crewOneOffs:  [String] = []   // free-typed additions not in roster
    @State private var newCrewEntry: String   = ""

    // New location entry
    @State private var newLocationName:    String = ""
    @State private var newLocationAddress: String = ""
    @State private var showingAddLocation: Bool   = false

    // New hospital entry
    @State private var newHospitalName:    String = ""
    @State private var newHospitalAddress: String = ""
    @State private var newHospitalPhone:   String = ""
    @State private var showingAddHospital: Bool   = false

    // New cast entry
    @State private var newCastMember: String = ""

    // Roster split: daily defaults first, then specialty
    private var dailyRoster:    [CrewMember] { productionInfo.crew.filter {  $0.isDailyDefault } }
    private var specialtyRoster: [CrewMember] { productionInfo.crew.filter { !$0.isDailyDefault } }
    private var allRosterEntries: [CrewMember] { dailyRoster + specialtyRoster }

    /// Resolves a raw character name to "Actor — Character" using the *current* cast list,
    /// live — so an actor/character rename in Production Setup shows up immediately here,
    /// even before this call sheet is saved again.
    private func displayText(forCharacter character: String) -> String {
        if let match = productionInfo.castList.first(where: {
            $0.characterName.trimmingCharacters(in: .whitespaces)
                .caseInsensitiveCompare(character.trimmingCharacters(in: .whitespaces)) == .orderedSame
        }) {
            return match.displayString
        }
        return character
    }

    private func normalizedCastKey(_ character: String) -> String {
        character.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// allShootDays with this day's entry swapped for the in-progress castCharacters edit,
    /// so adding/removing a cast member updates everyone's auto-derived S/W/F live, without
    /// requiring a save first.
    private var shootDaysForAutoStatus: [ShootDay] {
        allShootDays.map { day in
            guard day.id == shootDay.id else { return day }
            var updated = day
            updated.callSheet.castOverride = castCharacters
            return updated
        }
    }

    private func autoCastStatus(for character: String) -> String {
        CallSheetData.autoCastStatus(forCharacter: character, on: shootDay.date, allShootDays: shootDaysForAutoStatus)
    }

    private func dictBinding(_ dict: Binding<[String: String]>, key: String) -> Binding<String> {
        Binding(get: { dict.wrappedValue[key] ?? "" }, set: { dict.wrappedValue[key] = $0 })
    }

    private func castStatusBinding(key: String) -> Binding<String> {
        Binding(
            get: { castStatusOverride[key] ?? "" },
            set: { newValue in
                if newValue.isEmpty { castStatusOverride.removeValue(forKey: key) }
                else { castStatusOverride[key] = newValue }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Call Sheet").font(.title2).fontWeight(.bold)
                    Text(formattedDate(shootDay.date)).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // General Call Time
                    sectionHeader("General Call Time", icon: "clock")
                    TextField("e.g. 7:00 AM", text: $callTime)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Divider()

                    // Shooting Call — distinct from crew call: crew call is when everyone
                    // arrives, shooting call is when the camera actually rolls.
                    sectionHeader("Shooting Call", icon: "video")
                    TextField("e.g. 8:00 AM", text: $shootingCallTime)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Divider()

                    // Meal Times — plain text, not time pickers: real call sheets use ranges
                    // ("0600–0700") or free text ("COME HAVING HAD") here just as often as a
                    // single clock time (CALLSHEET_SPEC.md §2.1).
                    sectionHeader("Meal Times", icon: "fork.knife")
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledTextField("Breakfast", placeholder: "e.g. 0600–0700, or COME HAVING HAD", text: $breakfastTime)
                        LabeledTextField("Lunch",     placeholder: "e.g. 1300 (½ hr)",                   text: $lunchTime)
                        LabeledTextField("Dinner",    placeholder: "optional",                           text: $dinnerTime)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Show crew meal count on call sheet", isOn: $showCrewMealCount)
                        Text("Prints \"CREW BREAKFAST x_ • CREW LUNCH x_\" using the crew table's headcount flag — the same per-person \"counted\" toggle, not a separate breakfast/lunch count.")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    Divider()

                    // Weather — matches the export's 8-column weather strip. Text fields for
                    // everything, same as the time fields above: sunrise/sunset are often
                    // given as plain times, and condition/wind/gusts/hi/lo/POP are naturally
                    // short text ("SW 10-15", "30%"), not numeric types. Leaving all eight
                    // blank omits the whole strip on export.
                    sectionHeader("Weather", icon: "cloud.sun")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            LabeledTextField("Sunrise", placeholder: "e.g. 6:12 AM", text: $sunrise)
                            LabeledTextField("Sunset",  placeholder: "e.g. 8:47 PM", text: $sunset)
                            LabeledTextField("Weather", placeholder: "e.g. Partly Cloudy", text: $weatherCondition)
                            LabeledTextField("Wind",    placeholder: "e.g. SW 10-15", text: $wind)
                        }
                        HStack(spacing: 8) {
                            LabeledTextField("Gusts", placeholder: "e.g. 25 mph", text: $gusts)
                            LabeledTextField("Hi",    placeholder: "e.g. 72°",     text: $weatherHi)
                            LabeledTextField("Low",   placeholder: "e.g. 58°",     text: $weatherLo)
                            LabeledTextField("POP",   placeholder: "e.g. 30%",     text: $pop)
                        }
                    }

                    Divider()

                    // Locations
                    sectionHeader("Locations", icon: "mappin.and.ellipse")
                    if locations.isEmpty {
                        Text("No locations added yet.").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(Array(locations.enumerated()), id: \.element.id) { index, loc in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption).foregroundColor(.secondary)
                                    .frame(width: 16, alignment: .trailing).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loc.name.isEmpty ? "Unnamed Location" : loc.name).fontWeight(.medium)
                                    if !loc.address.isEmpty {
                                        Text(loc.address).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button { locations.remove(at: index) } label: {
                                    Image(systemName: "minus.circle").foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }

                    if showingAddLocation {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Location name (e.g. Owen's Farmhouse)", text: $newLocationName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            TextField("Address (optional)", text: $newLocationAddress)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            HStack {
                                Button("Cancel") {
                                    newLocationName = ""; newLocationAddress = ""; showingAddLocation = false
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button("Add Location") {
                                    guard !newLocationName.isEmpty else { return }
                                    locations.append(Location(name: newLocationName, address: newLocationAddress))
                                    newLocationName = ""; newLocationAddress = ""; showingAddLocation = false
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newLocationName.isEmpty)
                            }
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                    } else {
                        Button { showingAddLocation = true } label: {
                            Label("Add Location", systemImage: "plus.circle").font(.callout)
                        }
                        .buttonStyle(.plain).foregroundColor(.blue)
                    }

                    Divider()

                    // Basecamp / Crew Park / Hospitals — usually identical across consecutive
                    // days at one location, so "Copy from Previous Day" carries all three
                    // forward at once rather than making every day retype them. Shooting call
                    // and meal times above are deliberately NOT part of this action — those
                    // genuinely change day to day.
                    HStack {
                        sectionHeader("Basecamp, Crew Park & Hospitals", icon: "cross.case")
                        Spacer()
                        if let previous = previousDayCallSheet {
                            Button {
                                basecamp  = previous.basecamp
                                crewPark  = previous.crewPark
                                hospitals = previous.hospitals
                            } label: {
                                Label("Copy from Previous Day", systemImage: "arrow.turn.down.right")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain).foregroundColor(.blue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledTextField("Basecamp",  placeholder: "e.g. North lot — park as directed", text: $basecamp)
                        LabeledTextField("Crew Park", placeholder: "e.g. Example Road, east side",       text: $crewPark)
                    }

                    if hospitals.isEmpty {
                        Text("No hospitals added yet.").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(Array(hospitals.enumerated()), id: \.element.id) { index, hospital in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption).foregroundColor(.secondary)
                                    .frame(width: 16, alignment: .trailing).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hospital.name.isEmpty ? "Unnamed Hospital" : hospital.name).fontWeight(.medium)
                                    if !hospital.address.isEmpty {
                                        Text(hospital.address).font(.caption).foregroundColor(.secondary)
                                    }
                                    if !hospital.phone.isEmpty {
                                        Text(hospital.phone).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button { hospitals.remove(at: index) } label: {
                                    Image(systemName: "minus.circle").foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }

                    if showingAddHospital {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Hospital name", text: $newHospitalName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            TextField("Address", text: $newHospitalAddress)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            TextField("Phone", text: $newHospitalPhone)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            HStack {
                                Button("Cancel") {
                                    newHospitalName = ""; newHospitalAddress = ""; newHospitalPhone = ""; showingAddHospital = false
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button("Add Hospital") {
                                    guard !newHospitalName.isEmpty else { return }
                                    hospitals.append(Hospital(name: newHospitalName, address: newHospitalAddress, phone: newHospitalPhone))
                                    newHospitalName = ""; newHospitalAddress = ""; newHospitalPhone = ""; showingAddHospital = false
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newHospitalName.isEmpty)
                            }
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                    } else {
                        Button { showingAddHospital = true } label: {
                            Label("Add Hospital", systemImage: "plus.circle").font(.callout)
                        }
                        .buttonStyle(.plain).foregroundColor(.blue)
                    }

                    Divider()

                    // Cast
                    HStack {
                        sectionHeader("Cast", icon: "person.2")
                        Spacer()
                        if castIsEdited {
                            Button("Reset to Auto") {
                                castCharacters = shootDay.allCast
                                castIsEdited   = false
                            }
                            .font(.caption).foregroundColor(.secondary).buttonStyle(.plain)
                        } else {
                            Text("Auto-pulled from scenes").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    if castCharacters.isEmpty {
                        Text("No cast assigned to scenes on this day.").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(Array(castCharacters.enumerated()), id: \.offset) { index, character in
                            let key = normalizedCastKey(character)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(displayText(forCharacter: character))
                                    Spacer()
                                    Button { castCharacters.remove(at: index); castIsEdited = true } label: {
                                        Image(systemName: "minus.circle").foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                // S/W/F auto-derives from this character's earliest/latest
                                // scheduled day across the whole production
                                // (CALLSHEET_SPEC.md §3.4); picking "Auto" clears any
                                // override and reverts to that computed value, picking
                                // anything else pins it. The other five are plain per-day
                                // text, same convention as the per-crew Call field —
                                // O/C, S/D, TBD, "Per Karen", whatever the day calls for.
                                HStack(spacing: 6) {
                                    Picker("", selection: castStatusBinding(key: key)) {
                                        let auto = autoCastStatus(for: character)
                                        Text(auto.isEmpty ? "Auto" : "Auto (\(auto))").tag("")
                                        Divider()
                                        ForEach(Self.castStatusOptions, id: \.self) { code in
                                            Text(code).tag(code)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 110)
                                    castMiniField("P/U",    dictBinding($castPickup, key: key))
                                    castMiniField("H/M/W",  dictBinding($castHMW, key: key))
                                    castMiniField("Block",  dictBinding($castBlock, key: key))
                                    castMiniField("Set",    dictBinding($castSet, key: key))
                                    castMiniField("Notes",  dictBinding($castNotesByCharacter, key: key), width: 120)
                                }
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }

                    HStack {
                        TextField("Add cast member (character name)", text: $newCastMember)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button {
                            let trimmed = newCastMember.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            castCharacters.append(trimmed); newCastMember = ""; castIsEdited = true
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(newCastMember.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Divider()

                    // Crew
                    HStack {
                        sectionHeader("Crew", icon: "person.3")
                        Spacer()
                        Toggle("Show headcount column", isOn: $showHeadcount)
                            .toggleStyle(.switch)
                            .font(.caption)
                    }

                    if allRosterEntries.isEmpty && crewOneOffs.isEmpty {
                        Text("No crew in Production Setup yet. Add crew members there, or type a name below.")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        // Daily defaults section
                        if !dailyRoster.isEmpty {
                            Text("Daily Crew").font(.caption).foregroundColor(.secondary).padding(.top, 2)
                            ForEach(Array(dailyRoster.enumerated()), id: \.element.id) { i, member in
                                let globalIndex = i  // daily crew comes first in allRosterEntries
                                crewRow(member: member, index: globalIndex)
                            }
                        }

                        // Specialty crew section
                        if !specialtyRoster.isEmpty {
                            Text("Additional Crew").font(.caption).foregroundColor(.secondary).padding(.top, 4)
                            ForEach(Array(specialtyRoster.enumerated()), id: \.element.id) { i, member in
                                let globalIndex = dailyRoster.count + i
                                crewRow(member: member, index: globalIndex)
                            }
                        }

                        // One-off additions
                        if !crewOneOffs.isEmpty {
                            Text("Added for Today").font(.caption).foregroundColor(.secondary).padding(.top, 4)
                            ForEach(Array(crewOneOffs.enumerated()), id: \.offset) { index, name in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                                    Text(name).font(.callout)
                                    Spacer()
                                    Button { crewOneOffs.remove(at: index) } label: {
                                        Image(systemName: "minus.circle").foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 3)
                                Divider()
                            }
                        }
                    }

                    // Add one-off crew member
                    HStack {
                        TextField("Add crew member not in roster", text: $newCrewEntry)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button {
                            let trimmed = newCrewEntry.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            crewOneOffs.append(trimmed); newCrewEntry = ""
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(newCrewEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Divider()

                    // Notes
                    sectionHeader("Notes", icon: "note.text")
                    TextEditor(text: $notes)
                        .frame(minHeight: 100).font(.body)
                        .border(Color.gray.opacity(0.3), width: 1).cornerRadius(4)
                    Text("Use this for props, special gear, late arrivals, permit info, etc.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack(spacing: 12) {
                Button("Export PDF") { saveToDay(); onExportPDF(shootDay) }
                    .buttonStyle(.bordered).help("Export call sheet as PDF")
                Spacer()
                Button("Cancel") { isPresented = false }.buttonStyle(.bordered)
                Button("Save") { saveToDay(); onSave(); isPresented = false }.buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
        .frame(width: 560, height: 740)
        .onAppear { populateFields() }
    }

    // MARK: - Crew row helper

    @ViewBuilder
    private func crewRow(member: CrewMember, index: Int) -> some View {
        HStack {
            // Safe bounds check
            if index < crewChecked.count {
                Image(systemName: crewChecked[index] ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(crewChecked[index] ? .green : .secondary)
                    .font(.callout)
                    .onTapGesture { crewChecked[index].toggle() }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(member.name).font(.callout)
                    .foregroundColor(index < crewChecked.count && crewChecked[index] ? .primary : .secondary)
                if !member.role.isEmpty {
                    Text(member.role).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            // Call time — shown for any crew member selected for this day, independent of
            // the headcount toggle. Text, not a time picker: CALLSHEET_SPEC.md §3.5 — real
            // call times are often "O/C" or "TBD", not just a clock time. Blank here falls
            // back to the day's general crew call time at export (CallSheetData.callTime(for:)),
            // not to a value pre-filled in this field.
            if index < crewChecked.count, crewChecked[index], index < crewCallTimes.count {
                TextField("Call", text: Binding(
                    get: { crewCallTimes[index] },
                    set: { crewCallTimes[index] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .frame(width: 70)
            }
            // Headcount only matters (and is only shown) for crew actually selected for this
            // day, and only when the day's master toggle is on — never shown disabled.
            if showHeadcount, index < crewChecked.count, crewChecked[index], index < crewCounted.count {
                Button {
                    crewCounted[index].toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: crewCounted[index] ? "checkmark.square.fill" : "square")
                        Text("Headcount")
                    }
                    .font(.caption2)
                    .foregroundColor(crewCounted[index] ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { if index < crewChecked.count { crewChecked[index].toggle() } }
        Divider()
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).foregroundColor(.primary)
    }

    /// A small labeled text field for a single line item within a section (meal times,
    /// basecamp, crew park) — lighter-weight than a whole sectionHeader for fields that
    /// share one section together.
    @ViewBuilder
    private func LabeledTextField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }

    /// A cast row's compact per-character fields (P/U, H/M/W, Block, Set, Notes) — same
    /// placeholder-as-label, no time-picker convention as the per-crew Call field.
    @ViewBuilder
    private func castMiniField(_ placeholder: String, _ text: Binding<String>, width: CGFloat = 60) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.caption2)
            .frame(width: width)
    }

    // MARK: - Populate / save

    private func populateFields() {
        callTime         = shootDay.callSheet.generalCallTime
        shootingCallTime = shootDay.callSheet.shootingCallTime
        breakfastTime    = shootDay.callSheet.breakfastTime
        lunchTime        = shootDay.callSheet.lunchTime
        dinnerTime       = shootDay.callSheet.dinnerTime
        showCrewMealCount = shootDay.callSheet.showCrewMealCount
        basecamp         = shootDay.callSheet.basecamp
        crewPark         = shootDay.callSheet.crewPark
        hospitals        = shootDay.callSheet.hospitals
        sunrise          = shootDay.callSheet.sunrise
        sunset           = shootDay.callSheet.sunset
        weatherCondition = shootDay.callSheet.weatherCondition
        wind             = shootDay.callSheet.wind
        gusts            = shootDay.callSheet.gusts
        weatherHi        = shootDay.callSheet.hi
        weatherLo        = shootDay.callSheet.lo
        pop              = shootDay.callSheet.pop
        locations = shootDay.callSheet.locations
        notes     = shootDay.callSheet.notes

        // Cast — always raw character names now
        if let override = shootDay.callSheet.castOverride {
            castCharacters = override; castIsEdited = true
        } else {
            castCharacters = shootDay.allCast
            castIsEdited   = false
        }
        castStatusOverride   = shootDay.callSheet.castStatusOverride ?? [:]
        castPickup           = shootDay.callSheet.castPickup ?? [:]
        castHMW               = shootDay.callSheet.castHMW ?? [:]
        castBlock             = shootDay.callSheet.castBlock ?? [:]
        castSet               = shootDay.callSheet.castSet ?? [:]
        castNotesByCharacter = shootDay.callSheet.castNotes ?? [:]

        // Crew — build checked array from the new ID-based override, or migrate a legacy
        // text-based one the first time this day is opened after upgrading
        let roster = allRosterEntries
        if shootDay.callSheet.crewIDOverride != nil || shootDay.callSheet.crewOneOffs != nil {
            let selectedIDs = Set(shootDay.callSheet.crewIDOverride ?? [])
            crewChecked = roster.map { selectedIDs.contains($0.id) }
            crewOneOffs = shootDay.callSheet.crewOneOffs ?? []
        } else if let legacy = shootDay.callSheet.crewOverride {
            // One-time best-effort migration: match old frozen display strings against the
            // current roster. Saving this day will replace it with the ID-based override.
            crewChecked = roster.map { legacy.contains($0.displayString) }
            let rosterStrings = Set(roster.map { $0.displayString })
            crewOneOffs = legacy.filter { !rosterStrings.contains($0) }
        } else {
            // No override yet — default: daily members checked, specialty unchecked
            crewChecked = roster.map { $0.isDailyDefault }
            crewOneOffs = []
        }

        // Headcount. previouslySelectedIDs is who this day's crewIDOverride already had
        // *before* this editing session opened — for them, an explicit saved
        // crewCountedIDs decision (if any) is authoritative even if it happens to say
        // "not counted" for a daily-default person (a deliberate override, e.g. sick that
        // day). For anyone NOT already selected — a brand new day, or a crew member being
        // checked for the first time just now in this session — there's no prior decision
        // to honor, so the daily-default applies live, exactly like a freshly created day.
        showHeadcount = shootDay.callSheet.showHeadcount
        let previouslySelectedIDs = Set(shootDay.callSheet.crewIDOverride ?? [])
        let explicitCounted = shootDay.callSheet.crewCountedIDs
        crewCounted = roster.map { member in
            if previouslySelectedIDs.contains(member.id), let explicit = explicitCounted {
                return explicit.contains(member.id)
            }
            return member.isDailyDefault
        }

        // Call times — left blank unless this member already has an explicit one saved;
        // blank always means "use the day's general crew call time," never a value that
        // needs pre-filling here.
        let explicitCallTimes = shootDay.callSheet.crewCallTimes ?? [:]
        crewCallTimes = roster.map { explicitCallTimes[$0.id] ?? "" }
    }

    private func saveToDay() {
        shootDay.callSheet.generalCallTime  = callTime
        shootDay.callSheet.shootingCallTime = shootingCallTime
        shootDay.callSheet.breakfastTime    = breakfastTime
        shootDay.callSheet.lunchTime        = lunchTime
        shootDay.callSheet.dinnerTime       = dinnerTime
        shootDay.callSheet.showCrewMealCount = showCrewMealCount
        shootDay.callSheet.basecamp         = basecamp
        shootDay.callSheet.crewPark         = crewPark
        shootDay.callSheet.hospitals        = hospitals
        shootDay.callSheet.sunrise          = sunrise
        shootDay.callSheet.sunset           = sunset
        shootDay.callSheet.weatherCondition = weatherCondition
        shootDay.callSheet.wind             = wind
        shootDay.callSheet.gusts            = gusts
        shootDay.callSheet.hi               = weatherHi
        shootDay.callSheet.lo               = weatherLo
        shootDay.callSheet.pop              = pop
        shootDay.callSheet.locations       = locations
        shootDay.callSheet.notes           = notes
        shootDay.callSheet.castOverride    = castIsEdited ? castCharacters : nil

        func trimmedDict(_ dict: [String: String]) -> [String: String] {
            var result: [String: String] = [:]
            for (k, v) in dict {
                let t = v.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { result[k] = t }
            }
            return result
        }
        shootDay.callSheet.castStatusOverride = trimmedDict(castStatusOverride)
        shootDay.callSheet.castPickup         = trimmedDict(castPickup)
        shootDay.callSheet.castHMW            = trimmedDict(castHMW)
        shootDay.callSheet.castBlock          = trimmedDict(castBlock)
        shootDay.callSheet.castSet            = trimmedDict(castSet)
        shootDay.callSheet.castNotes          = trimmedDict(castNotesByCharacter)

        // Build the new ID-based crew override: checked roster members by ID + one-offs by name
        let roster = allRosterEntries
        var selectedIDs: [UUID] = []
        for (i, member) in roster.enumerated() where i < crewChecked.count && crewChecked[i] {
            selectedIDs.append(member.id)
        }
        shootDay.callSheet.crewIDOverride = selectedIDs
        shootDay.callSheet.crewOneOffs    = crewOneOffs
        shootDay.callSheet.crewOverride   = nil   // fully migrated off the legacy text-based field

        shootDay.callSheet.showHeadcount = showHeadcount
        let countedIDs = zip(roster, crewCounted).compactMap { member, isCounted in isCounted ? member.id : nil }
        shootDay.callSheet.crewCountedIDs = countedIDs

        var callTimes: [UUID: String] = [:]
        for (i, member) in roster.enumerated() where i < crewCallTimes.count {
            let trimmed = crewCallTimes[i].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { callTimes[member.id] = trimmed }
        }
        shootDay.callSheet.crewCallTimes = callTimes
    }
}

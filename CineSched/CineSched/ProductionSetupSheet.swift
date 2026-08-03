// ProductionSetupSheet.swift
// Project-wide production info — company, director, contact number, cast, and crew.
// Filled in once per project; opened from the toolbar.

import SwiftUI

struct ProductionSetupSheet: View {
    @Binding var productionInfo: ProductionInfo
    @Binding var isPresented: Bool
    let onSave: () -> Void
    /// Called once per renamed character (oldName, newName) when Save is pressed, so the
    /// caller can propagate the rename into every scene's cast list and existing call sheets.
    var onCharacterRenamed: (String, String) -> Void = { _, _ in }

    @State private var companyName:   String = ""
    @State private var director:      KeyContact = KeyContact()
    @State private var producer:      KeyContact = KeyContact()
    @State private var contactNumber: String = ""
    @State private var castList:      [CastMember] = []
    @State private var crew:          [CrewMember] = []

    @State private var newActorName:          String = ""
    @State private var availabilityEditorIndex: Int? = nil
    @State private var castContactsEditorIndex: Int? = nil
    @State private var crewContactsEditorIndex: Int? = nil
    @State private var showingDirectorContacts: Bool = false
    @State private var showingProducerContacts: Bool = false
    @State private var newCharacterName:      String = ""
    @State private var newCrewName:           String = ""
    @State private var newCrewRole:           String = ""
    @State private var newCrewIsDailyDefault: Bool   = false

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Production Setup")
                        .font(.title2).fontWeight(.bold)
                    Text("These details appear on every call sheet")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Production details
                    Group {
                        Label("Production Details", systemImage: "building.2").font(.headline)
                        LabeledField("Production Company", placeholder: "e.g. Tempel Films", text: $companyName)
                        LabeledKeyContactField("Director", placeholder: "e.g. Chris Tempel",
                                                contact: $director, showingContacts: $showingDirectorContacts)
                        LabeledKeyContactField("Producer", placeholder: "e.g. Jamie Rivera",
                                                contact: $producer, showingContacts: $showingProducerContacts)
                        LabeledField("Contact Number",     placeholder: "e.g. 555-867-5309",  text: $contactNumber)
                    }

                    Divider()

                    // Cast list
                    Label("Cast", systemImage: "star").font(.headline)
                    Text("Enter each actor and the character they play. Scene strips use character names — the app will look up the actor automatically. Editing a name here updates it everywhere, including scenes and call sheets already scheduled.")
                        .font(.caption).foregroundColor(.secondary)

                    if castList.isEmpty {
                        Text("No cast added yet.").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(Array(castList.enumerated()), id: \.element.id) { index, member in
                            VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                TextField("Actor name", text: Binding(
                                    get: { castList[index].actorName },
                                    set: { castList[index].actorName = $0 }
                                ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())

                                TextField("Character name", text: Binding(
                                    get: { castList[index].characterName },
                                    set: { castList[index].characterName = $0 }
                                ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())

                                Button {
                                    availabilityEditorIndex = index
                                } label: {
                                    let count = castList[index].unavailableRanges.count
                                    HStack(spacing: 3) {
                                        Image(systemName: count > 0 ? "calendar.badge.exclamationmark" : "calendar")
                                        if count > 0 { Text("\(count)").font(.caption2) }
                                    }
                                    .foregroundColor(count > 0 ? .orange : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Set dates this actor is unavailable")
                                .popover(isPresented: Binding(
                                    get: { availabilityEditorIndex == index },
                                    set: { if !$0 { availabilityEditorIndex = nil } }
                                )) {
                                    AvailabilityEditor(ranges: Binding(
                                        get: { castList[index].unavailableRanges },
                                        set: { castList[index].unavailableRanges = $0 }
                                    ), personLabel: castList[index].displayString)
                                }

                                Button {
                                    castContactsEditorIndex = index
                                } label: {
                                    let count = castList[index].contacts.count
                                    HStack(spacing: 3) {
                                        Image(systemName: count > 0 ? "phone.badge.checkmark" : "phone")
                                        if count > 0 { Text("\(count)").font(.caption2) }
                                    }
                                    .foregroundColor(count > 0 ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Manage contact info")
                                .popover(isPresented: Binding(
                                    get: { castContactsEditorIndex == index },
                                    set: { if !$0 { castContactsEditorIndex = nil } }
                                )) {
                                    ContactsEditor(contacts: Binding(
                                        get: { castList[index].contacts },
                                        set: { castList[index].contacts = $0 }
                                    ), personLabel: castList[index].displayString)
                                }

                                Button { castList.remove(at: index) } label: {
                                    Image(systemName: "minus.circle").foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            // At-a-glance preview of this person's primary contacts — only
                            // takes up room once there's something to show, so rows for
                            // people with no contacts yet stay exactly as compact as before.
                            // Purely a display convenience: editing still only happens in
                            // the Contacts popover above, never here.
                            ContactPreviewLine(
                                phone: castList[index].primaryPhone,
                                email: castList[index].primaryEmail
                            )
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Actor name", text: $newActorName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Character name", text: $newCharacterName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button {
                            let actor     = newActorName.trimmingCharacters(in: .whitespaces)
                            let character = newCharacterName.trimmingCharacters(in: .whitespaces)
                            guard !actor.isEmpty || !character.isEmpty else { return }
                            castList.append(CastMember(actorName: actor, characterName: character))
                            newActorName     = ""
                            newCharacterName = ""
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            newActorName.trimmingCharacters(in: .whitespaces).isEmpty &&
                            newCharacterName.trimmingCharacters(in: .whitespaces).isEmpty
                        )
                    }

                    Divider()

                    // Crew list
                    Label("Crew", systemImage: "person.3").font(.headline)
                    Text("Check \"Daily\" for crew expected on set every day — they'll be pre-populated on each call sheet. Specialty crew can be added per-day when building call sheets.")
                        .font(.caption).foregroundColor(.secondary)

                    // Column header
                    HStack {
                        Text("Name / Role")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Daily")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(width: 44, alignment: .center)
                        Spacer().frame(width: 28)
                        Spacer().frame(width: 28)
                    }
                    .padding(.horizontal, 8)

                    if crew.isEmpty {
                        Text("No crew added yet.").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(Array(crew.enumerated()), id: \.element.id) { index, member in
                            VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                TextField("Name", text: Binding(
                                    get: { crew[index].name },
                                    set: { crew[index].name = $0 }
                                ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())

                                TextField("Role", text: Binding(
                                    get: { crew[index].role },
                                    set: { crew[index].role = $0 }
                                ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: 120)

                                Toggle("", isOn: Binding(
                                    get: { crew[index].isDailyDefault },
                                    set: { crew[index].isDailyDefault = $0 }
                                ))
                                .toggleStyle(.checkbox)
                                .frame(width: 44, alignment: .center)

                                Button {
                                    crewContactsEditorIndex = index
                                } label: {
                                    let count = crew[index].contacts.count
                                    HStack(spacing: 3) {
                                        Image(systemName: count > 0 ? "phone.badge.checkmark" : "phone")
                                        if count > 0 { Text("\(count)").font(.caption2) }
                                    }
                                    .foregroundColor(count > 0 ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Manage contact info")
                                .popover(isPresented: Binding(
                                    get: { crewContactsEditorIndex == index },
                                    set: { if !$0 { crewContactsEditorIndex = nil } }
                                )) {
                                    ContactsEditor(contacts: Binding(
                                        get: { crew[index].contacts },
                                        set: { crew[index].contacts = $0 }
                                    ), personLabel: crew[index].displayString)
                                }

                                Button { crew.remove(at: index) } label: {
                                    Image(systemName: "minus.circle").foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 28)
                            }
                            // Same at-a-glance contact preview as the cast rows above —
                            // display only, editing stays in the Contacts popover.
                            ContactPreviewLine(
                                phone: crew[index].primaryPhone,
                                email: crew[index].primaryEmail
                            )
                            }
                            .padding(8)
                            .background(member.isDailyDefault
                                ? Color.blue.opacity(0.07)
                                : Color.gray.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }

                    // Add crew member
                    HStack(spacing: 8) {
                        TextField("Name", text: $newCrewName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Role (e.g. DP)", text: $newCrewRole)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 140)
                        Toggle("Daily", isOn: $newCrewIsDailyDefault)
                            .toggleStyle(.checkbox)
                            .help("Pre-populate on every call sheet")
                        Button {
                            let name = newCrewName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            crew.append(CrewMember(
                                name:           name,
                                role:           newCrewRole.trimmingCharacters(in: .whitespaces),
                                isDailyDefault: newCrewIsDailyDefault
                            ))
                            newCrewName           = ""
                            newCrewRole           = ""
                            newCrewIsDailyDefault = false
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(newCrewName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Cancel") { isPresented = false }.buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    // Detect character renames (same cast member, different character text) by
                    // matching against the *old* list — still intact in the binding at this
                    // point, since we haven't overwritten it yet — before applying the edits.
                    let oldByID = Dictionary(uniqueKeysWithValues: productionInfo.castList.map { ($0.id, $0) })
                    for member in castList {
                        if let old = oldByID[member.id],
                           old.characterName.trimmingCharacters(in: .whitespaces) != member.characterName.trimmingCharacters(in: .whitespaces),
                           !old.characterName.trimmingCharacters(in: .whitespaces).isEmpty,
                           !member.characterName.trimmingCharacters(in: .whitespaces).isEmpty {
                            onCharacterRenamed(old.characterName, member.characterName)
                        }
                    }

                    productionInfo.companyName   = companyName
                    productionInfo.director      = director
                    productionInfo.producer      = producer
                    productionInfo.contactNumber = contactNumber
                    productionInfo.castList      = castList
                    productionInfo.crew          = crew
                    onSave()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
        .frame(width: 580, height: 700)
        .onAppear {
            companyName   = productionInfo.companyName
            director      = productionInfo.director
            producer      = productionInfo.producer
            contactNumber = productionInfo.contactNumber
            castList      = productionInfo.castList
            crew          = productionInfo.crew
        }
    }
}

private struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    init(_ label: String, placeholder: String, text: Binding<String>) {
        self.label       = label
        self.placeholder = placeholder
        self._text       = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

/// Same idea as LabeledField, but for a single named production contact (Director,
/// Producer) that — like crew and cast — can have its own list of contact methods. Reuses
/// the exact same ContactsEditor popover the Cast/Crew rows use below.
private struct LabeledKeyContactField: View {
    let label: String
    let placeholder: String
    @Binding var contact: KeyContact
    @Binding var showingContacts: Bool

    init(_ label: String, placeholder: String, contact: Binding<KeyContact>, showingContacts: Binding<Bool>) {
        self.label           = label
        self.placeholder     = placeholder
        self._contact        = contact
        self._showingContacts = showingContacts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField(placeholder, text: $contact.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button {
                    showingContacts = true
                } label: {
                    let count = contact.contacts.count
                    HStack(spacing: 3) {
                        Image(systemName: count > 0 ? "phone.badge.checkmark" : "phone")
                        if count > 0 { Text("\(count)").font(.caption2) }
                    }
                    .foregroundColor(count > 0 ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("Manage \(label)'s contact info")
                .popover(isPresented: $showingContacts) {
                    ContactsEditor(
                        contacts: $contact.contacts,
                        personLabel: contact.name.isEmpty ? label : contact.name
                    )
                }
            }
        }
    }
}

/// A small "at a glance" preview of a person's primary phone/email beneath their row in the
/// Cast or Crew list — renders nothing at all if neither is set, so a person with no
/// contacts yet doesn't grow an empty line. Read-only: this is purely a display shortcut,
/// not an editing surface — actually adding/changing/removing contacts always happens
/// through that row's Contacts popover.
private struct ContactPreviewLine: View {
    let phone: String?
    let email: String?

    var body: some View {
        if phone != nil || email != nil {
            HStack(spacing: 14) {
                if let phone {
                    Label(phone, systemImage: "phone.fill")
                }
                if let email {
                    Label(email, systemImage: "envelope.fill")
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .padding(.leading, 2)
        }
    }
}

/// Popover content for adding/removing the date ranges a cast member is unavailable —
/// feeds both the schedule-wide conflict scan and the live red-strip coloring on the
/// calendar.
private struct AvailabilityEditor: View {
    @Binding var ranges: [DateRange]
    let personLabel: String

    @State private var newStart: Date = Date()
    @State private var newEnd:   Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unavailable Dates").font(.headline)
            Text(personLabel.isEmpty ? "Unnamed" : personLabel)
                .font(.caption).foregroundColor(.secondary)

            if ranges.isEmpty {
                Text("No dates marked yet.").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(ranges) { range in
                    HStack {
                        Text(rangeLabel(range)).font(.caption)
                        Spacer()
                        Button {
                            ranges.removeAll { $0.id == range.id }
                        } label: {
                            Image(systemName: "minus.circle").foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Text("Add a range").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 8) {
                DatePicker("From", selection: $newStart, displayedComponents: .date)
                    .labelsHidden()
                Text("–")
                DatePicker("To", selection: $newEnd, displayedComponents: .date)
                    .labelsHidden()
                Button {
                    ranges.append(DateRange(start: newStart, end: newEnd))
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func rangeLabel(_ range: DateRange) -> String {
        let cal = Calendar.current
        if cal.isDate(range.start, inSameDayAs: range.end) {
            return formattedDate(range.start)
        }
        return "\(formattedDate(range.start)) – \(formattedDate(range.end))"
    }
}

/// Popover content for managing one person's contact list — same pattern as
/// AvailabilityEditor above, just editing ContactMethod entries (type + value) instead of
/// date ranges. No limit on how many entries of the same type someone can have — e.g. two
/// cell numbers are both just separate rows.
private struct ContactsEditor: View {
    @Binding var contacts: [ContactMethod]
    let personLabel: String

    @State private var newType:  ContactType = .cell
    @State private var newValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contacts").font(.headline)
            Text(personLabel.isEmpty ? "Unnamed" : personLabel)
                .font(.caption).foregroundColor(.secondary)

            if contacts.isEmpty {
                Text("No contacts added yet.").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(Array(contacts.enumerated()), id: \.element.id) { index, _ in
                    HStack(spacing: 6) {
                        Picker("", selection: Binding(
                            get: { contacts[index].type },
                            set: { contacts[index].type = $0 }
                        )) {
                            ForEach(ContactType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)

                        TextField("Value", text: Binding(
                            get: { contacts[index].value },
                            set: { contacts[index].value = $0 }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button {
                            contacts.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle").foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Text("Add a contact").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 6) {
                Picker("", selection: $newType) {
                    ForEach(ContactType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 110)

                TextField("e.g. 555.555.0182", text: $newValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit(addContact)

                Button(action: addContact) {
                    Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func addContact() {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        contacts.append(ContactMethod(type: newType, value: trimmed))
        newValue = ""
    }
}

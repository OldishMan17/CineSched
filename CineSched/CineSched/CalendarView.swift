// CalendarView.swift
// Calendar grid with drag-and-drop scene scheduling

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - CompactMonthCalendarView

struct CompactMonthCalendarView: View {
    @Binding var shootDays: [ShootDay]
    let assignScene:  (Scene, ShootDay) -> Void
    @Binding var allScenes: [Scene]
    let updateScene:  (Scene, UUID) -> Void
    let removeScene:  (Scene, UUID) -> Void
    let projectTitle: String
    let productionInfo: ProductionInfo
    let isSidebarCollapsed: Bool
    @Binding var selectedSceneIDs:    Set<UUID>
    @Binding var lastSelectedSceneID: UUID?
    let conflictDates: Set<Date>
    let conflictSceneIDs: Set<UUID>
    @Binding var scrollToDate: Date?
    let onSceneChanged: () -> Void
    let onCallSheetExport: (ShootDay) -> Void   // called when Export PDF tapped in editor

    // Editing state
    @State private var editingScene:      Scene?
    @State private var editingDayId:      UUID?
    @State private var editingDayIndex:   Int?
    @State private var editingSceneIndex: Int?
    @State private var showingEditSheet = false

    // Call sheet state — using sheet(item:) guarantees data is present when sheet renders
    @State private var callSheetDay: ShootDay? = nil

    // "Send to Day" state — lets a selection be moved to a day that isn't currently
    // scrolled into view, instead of dragging across a long schedule.
    @State private var showingSendToDaySheet = false
    @State private var sendToDaySceneIDs: [UUID] = []

    // Day rearrange drag/drop state
    @State private var draggingDayId:       UUID? = nil
    @State private var dayDropTargetId:     UUID? = nil

    // Drag/drop state — position is an index into a day's full items list (scenes and
    // banners together), not scenes alone, so the two can be reordered relative to each other.
    @State private var dropTargetDayId:    UUID?
    @State private var dropTargetPosition: Int?
    @State private var draggedItemId:      UUID?
    @State private var interactingItemId:  UUID?

    // New/edit (non-scene) item form — a lightweight popover shared by both the "+" control
    // (create) and double-clicking an existing item (edit), rather than a whole new sidebar
    // form or sheet, since this is a much smaller/rarer thing to create or edit than a scene.
    // The three text fields are shared between both modes; which mode is active is just
    // whichever of these two is non-nil.
    @State private var addingBannerToDayId: UUID? = nil          // "+" button popover (create)
    @State private var editingBanner: (dayId: UUID, id: UUID)?   // item-card popover (edit)
    @State private var newBannerLabel: String = ""
    @State private var newBannerNote:  String = ""
    @State private var newBannerTime:  String = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                // Tighter gaps between days (8pt instead of 16pt) give each column more
                // of the window's width to work with. minimum: 95 is enough for the
                // compact "Thu 07/09" fallback plus the grip/call-sheet/conflict icons.
                let columns = Array(repeating: GridItem(.flexible(minimum: 95), spacing: 8), count: 7)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(shootDays.enumerated()), id: \.element.id) { dayIndex, day in
                        dayCell(day: day, dayIndex: dayIndex)
                            .id(day.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 60)   // extra breathing room so the last row's totals are never flush with the scroll edge
            }
            .onChange(of: scrollToDate) { _, newValue in
                guard let date = newValue else { return }
                if let target = shootDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                    withAnimation { proxy.scrollTo(target.id, anchor: .top) }
                }
                scrollToDate = nil
            }
        }
        // Without an explicit bounded height here, the ScrollView sizes itself to fit
        // *all* of its content rather than the space actually visible in the window,
        // so there's nothing left to scroll past the last row. Filling the parent's
        // available space makes the ScrollView clip properly and scroll the rest.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tooltipContainer()
        .sheet(isPresented: $showingEditSheet) {
            editSheetContent()
        }
        .sheet(item: $callSheetDay) { day in
            callSheetEditorContent(for: day)
        }
        .sheet(isPresented: $showingSendToDaySheet) {
            SendToDaySheet(
                shootDays:  shootDays,
                sceneCount: sendToDaySceneIDs.count,
                onSelect: { targetDayId in
                    sendScenes(sendToDaySceneIDs, toDay: targetDayId)
                    showingSendToDaySheet = false
                },
                onCancel: { showingSendToDaySheet = false }
            )
        }
        .onChange(of: showingEditSheet) { _, isShowing in
            if !isShowing { clearEditingState() }
        }
    }

    // MARK: - Day Cell

    @ViewBuilder
    private func dayCell(day: ShootDay, dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {

            // Date header row: grip handle (drag) + date + call sheet indicator
            HStack(spacing: 6) {

                // Grip icon — drag handle for rearranging the day
                // Uses a draggable view isolated from the button hierarchy
                // so it responds to click-and-drag without a prior activation click
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(draggingDayId == day.id ? .blue : .secondary)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onDrag {
                        draggingDayId = day.id
                        return NSItemProvider(object: "day:\(day.id.uuidString)" as NSString)
                    }
                    .simultaneousGesture(TapGesture())   // absorbs tap so parent button doesn't fire
                    .help("Drag to move this day's scenes and call sheet to another date")

                // Tappable date text — opens call sheet editor
                Button {
                    callSheetDay = day
                } label: {
                    HStack(spacing: 4) {
                        // Always the compact numeric form. An earlier version used
                        // ViewThatFits to switch to the fuller month-name format when
                        // there was room, but ViewThatFits has to actually measure both
                        // candidates against the available width — for every day cell,
                        // on every single re-render. Typing one character anywhere in
                        // the sidebar re-renders this whole calendar, so that measuring
                        // work was happening for 30+ day cells per keystroke, which is
                        // what froze the app. A plain Text costs almost nothing to size.
                        Text(formattedCalendarDayDateCompact(day.date))
                            .font(.caption).bold().foregroundColor(.primary)
                            .lineLimit(1)
                        if day.hasCallSheetData {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 5, height: 5)
                        }
                        if conflictDates.contains(Calendar.current.startOfDay(for: day.date)) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.red)
                                .help("An actor scheduled this day is marked unavailable — see Production > Scan for Conflicts…")
                        }
                        Spacer()
                        Image(systemName: "doc.text")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Click to open call sheet for this day")
            }

            // The day's full schedule — scenes and non-scene items (company moves, safety
            // meetings, etc.) together in one ordered list, in whatever order the user has
            // arranged them. See DayItem in Models.swift.
            VStack(spacing: 2) {
                ForEach(Array(day.items.enumerated()), id: \.element.id) { itemIndex, item in
                    VStack(spacing: 0) {
                        if shouldShowDropIndicator(dayId: day.id, position: itemIndex) {
                            DropIndicatorView()
                        }
                        switch item {
                        case .scene(let scene):
                            // The edit sheet navigates scene-to-scene (skipping any banners
                            // in between), so it needs the scene's position *among scenes
                            // only* — separate from itemIndex, which is its position in the
                            // full mixed list used for layout and drag/drop.
                            let sceneOnlyIndex = day.scenes.firstIndex(where: { $0.id == scene.id }) ?? 0
                            SceneCardView(
                                scene: scene,
                                dayId: day.id,
                                dayIndex: dayIndex,
                                sceneIndex: sceneOnlyIndex,
                                interactingItemId: $interactingItemId,
                                isSelected: selectedSceneIDs.contains(scene.id),
                                selectionCount: selectedSceneIDs.count,
                                showCast: isSidebarCollapsed,
                                hasConflict: conflictSceneIDs.contains(scene.id),
                                onEdit:      { editScene(dayIndex: dayIndex, sceneIndex: sceneOnlyIndex, scene: scene, dayId: day.id) },
                                onRemove:    { removeFromDay(scene, dayId: day.id) },
                                onDuplicate: { duplicateScene(scene) },
                                onDragStart: { draggedItemId = scene.id },
                                onDragEnd:   { draggedItemId = nil },
                                onSelect:    { selectScene(scene, dayId: day.id) },
                                onSendToDay: { beginSendToDay(scene) }
                            )
                        case .banner(let banner):
                            BannerCardView(
                                banner: banner,
                                interactingItemId: $interactingItemId,
                                onEdit:      { beginEditBanner(banner, dayId: day.id) },
                                onDelete:    { removeBanner(id: banner.id, from: day.id) },
                                onDragStart: { draggedItemId = banner.id },
                                onDragEnd:   { draggedItemId = nil }
                            )
                            .popover(isPresented: Binding(
                                get: { editingBanner?.id == banner.id },
                                set: { if !$0 { editingBanner = nil } }
                            )) {
                                bannerFormPopoverContent(dayId: day.id, editingBannerId: banner.id)
                            }
                        }
                    }
                    .onDrop(of: [UTType.text.identifier], delegate: ItemDropDelegate(
                        dayId: day.id,
                        position: itemIndex,
                        dropTargetDayId: $dropTargetDayId,
                        dropTargetPosition: $dropTargetPosition,
                        onDrop: { idList in handleItemDrop(idList: idList, targetDayId: day.id, targetPosition: itemIndex) }
                    ))
                }

                if shouldShowDropIndicator(dayId: day.id, position: day.items.count) {
                    DropIndicatorView()
                }
            }

            // Small, unobtrusive "+" to add a non-scene item — deliberately not in the date
            // header row, which is already tight for space (see the header's own comments
            // on how little room 95pt gives it).
            Button {
                newBannerLabel = ""
                newBannerNote  = ""
                newBannerTime  = ""
                addingBannerToDayId = day.id
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "plus.circle")
                    Text("Item").lineLimit(1)
                }
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add a non-scene item to this day — company move, safety meeting, pre-light, etc.")
            .popover(isPresented: Binding(
                get: { addingBannerToDayId == day.id },
                set: { if !$0 { addingBannerToDayId = nil } }
            )) {
                bannerFormPopoverContent(dayId: day.id, editingBannerId: nil)
            }

            Spacer()

            if !day.scenes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total: \(formattedEighths(day.totalDuration))")
                        .font(.caption2).foregroundColor(.gray)
                    Text("Est: \(formattedTime(day.totalEstimatedTime))")
                        .font(.caption2).foregroundColor(.gray)
                }
            }
        }
        .padding(6)
        // minWidth keeps each day column from being squeezed narrower than its date
        // header and totals can actually display without overlapping each other.
        .frame(minWidth: 95, maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(Color.gray.opacity(0.2))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    dayDropTargetId == day.id ? Color.green :
                    dropTargetDayId == day.id ? Color.red : Color.black,
                    lineWidth: (dayDropTargetId == day.id || dropTargetDayId == day.id) ? 2 : 1
                )
        )
        .cornerRadius(8)
        .onDrop(of: [UTType.text.identifier], delegate: CombinedDayDropDelegate(
            dayId: day.id,
            items: day.items,
            dropTargetDayId: $dropTargetDayId,
            dropTargetPosition: $dropTargetPosition,
            dayDropTargetId: $dayDropTargetId,
            draggingDayId: $draggingDayId,
            onItemDrop: { idList in
                handleItemDrop(idList: idList, targetDayId: day.id, targetPosition: day.items.count)
            },
            onDayDrop: { sourceDayId in
                handleDayRearrange(sourceDayId: sourceDayId, targetDayId: day.id)
            }
        ))
    }

    // MARK: - Add/Edit Item Popover

    /// Shared by both the "+" control (editingBannerId nil — creating) and double-clicking
    /// an existing item (editingBannerId set — editing), since the form itself is identical
    /// either way; only the title, the primary button, and what happens on save differ.
    @ViewBuilder
    private func bannerFormPopoverContent(dayId: UUID, editingBannerId: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(editingBannerId == nil ? "New Item" : "Edit Item").font(.headline)
            TextField("Label (e.g. COMPANY MOVE)", text: $newBannerLabel)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 220)
            TextField("Note (optional)", text: $newBannerNote)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 220)
            VStack(alignment: .leading, spacing: 2) {
                TextField(TimeParser.placeholderText, text: $newBannerTime)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 220)
                if let hint = TimeParser.getInputHint(newBannerTime), !newBannerTime.isEmpty {
                    Text(hint).font(.caption).foregroundColor(.secondary)
                } else {
                    Text("Estimated time (optional) — a company move or safety meeting doesn't always take the same amount of time")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 220, alignment: .leading)
                }
            }
            HStack {
                if let editingBannerId {
                    Button("Delete", role: .destructive) {
                        removeBanner(id: editingBannerId, from: dayId)
                        editingBanner = nil
                    }
                }
                Spacer()
                Button("Cancel") { addingBannerToDayId = nil; editingBanner = nil }
                Button(editingBannerId == nil ? "Add" : "Save") {
                    if let editingBannerId {
                        updateBanner(id: editingBannerId, label: newBannerLabel, note: newBannerNote, time: newBannerTime, in: dayId)
                        editingBanner = nil
                    } else {
                        addBanner(label: newBannerLabel, note: newBannerNote, time: newBannerTime, to: dayId)
                        addingBannerToDayId = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newBannerLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
    }

    private func beginEditBanner(_ banner: BannerItem, dayId: UUID) {
        newBannerLabel = banner.label
        newBannerNote  = banner.note
        newBannerTime  = banner.estimatedTime > 0 ? editableTimeString(banner.estimatedTime) : ""
        editingBanner  = (dayId: dayId, id: banner.id)
    }

    /// Converts a stored minute count back to a string TimeParser can parse again — mirrors
    /// SceneEditSheet's formatMinutesForEditing, since a banner's time field is edited the
    /// same way a scene's is.
    private func editableTimeString(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins  = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours):\(String(format: "%02d", mins))" }
        if hours > 0              { return "\(hours)" }
        return "\(mins)"
    }

    // MARK: - Call Sheet Editor

    /// Nearest prior day (by date) whose basecamp/crew park/hospital list isn't all
    /// empty — the source CallSheetEditor's "Copy from Previous Day" pulls from. Skips days
    /// that have nothing to offer (e.g. an empty gap day) rather than always using the
    /// literal day before, so the action reaches back to the last day that actually set
    /// these up even across an off day or two.
    private func previousDayCallSheet(before day: ShootDay) -> CallSheetData? {
        shootDays
            .filter { $0.date < day.date }
            .sorted { $0.date > $1.date }
            .first {
                !$0.callSheet.basecamp.isEmpty || !$0.callSheet.crewPark.isEmpty || !$0.callSheet.hospitals.isEmpty
            }
            .map { $0.callSheet }
    }

    @ViewBuilder
    private func callSheetEditorContent(for day: ShootDay) -> some View {
        if let idx = shootDays.firstIndex(where: { $0.id == day.id }) {
            CallSheetEditor(
                shootDay: $shootDays[idx],
                productionInfo: productionInfo,
                previousDayCallSheet: previousDayCallSheet(before: day),
                allShootDays: shootDays,
                isPresented: Binding(
                    get: { callSheetDay != nil },
                    set: { if !$0 { callSheetDay = nil } }
                ),
                onSave: {
                    callSheetDay = nil
                    onSceneChanged()
                },
                onExportPDF: { exportDay in
                    onCallSheetExport(exportDay)
                }
            )
        }
    }

    // MARK: - Edit Sheet

    @ViewBuilder
    private func editSheetContent() -> some View {
        if let dayIndex   = editingDayIndex,
           let sceneIndex = editingSceneIndex,
           dayIndex   < shootDays.count,
           sceneIndex < shootDays[dayIndex].scenes.count {

            SceneEditSheet(
                scene: $shootDays[dayIndex].scenes[sceneIndex],
                isPresented: $showingEditSheet,
                onSave: {
                    onSceneChanged()
                },
                onDelete: {
                    if let id = editingDayId {
                        removeScene(shootDays[dayIndex].scenes[sceneIndex], id)
                        onSceneChanged()
                    }
                    clearEditingState()
                },
                canGoPrevious: sceneIndex > 0,
                canGoNext: sceneIndex < shootDays[dayIndex].scenes.count - 1,
                onPrevious: { editingSceneIndex = sceneIndex - 1 },
                onNext: { editingSceneIndex = sceneIndex + 1 },
                positionLabel: "Scene \(sceneIndex + 1) of \(shootDays[dayIndex].scenes.count)"
            )
        } else {
            VStack(spacing: 20) {
                Text("Error: Scene not found")
                    .font(.title2).foregroundColor(.red)
                Text("The scene may have been moved or deleted.")
                    .font(.body).multilineTextAlignment(.center)
                Button("Close") {
                    showingEditSheet = false
                    clearEditingState()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24).frame(width: 400)
        }
    }

    // MARK: - Drag & Drop Helpers

    private func shouldShowDropIndicator(dayId: UUID, position: Int) -> Bool {
        dropTargetDayId == dayId && dropTargetPosition == position
    }

    /// Accepts either a single item ID or a comma-separated list of IDs (dragged together
    /// from a Boneyard multi-selection) and inserts them, in order, starting at
    /// targetPosition — a position in the day's *full* items list, where scenes and
    /// banners share one ordering, so a banner can be dragged above or below a scene the
    /// same way two scenes can be reordered. Banners never appear in the Boneyard, so an ID
    /// that isn't there is assumed to already be scheduled somewhere (the second loop below)
    /// — true for both a scene being moved and a banner being moved, with no special-casing
    /// needed for which kind of item it is.
    private func handleItemDrop(idList: String, targetDayId: UUID, targetPosition: Int) {
        let ids = idList.components(separatedBy: ",").compactMap { UUID(uuidString: $0) }
        guard !ids.isEmpty else { return }

        var insertPosition = targetPosition
        for uuid in ids {
            // From Boneyard (scenes only — banners have no Boneyard equivalent)
            if let idx = allScenes.firstIndex(where: { $0.id == uuid }) {
                let scene = allScenes.remove(at: idx)
                insertItemIntoDay(item: .scene(scene), dayId: targetDayId, position: insertPosition)
                insertPosition += 1
                continue
            }

            // Already scheduled somewhere — a scene or a banner, on this day or another
            for dayIdx in shootDays.indices {
                if let itemIdx = shootDays[dayIdx].items.firstIndex(where: { $0.id == uuid }) {
                    let item = shootDays[dayIdx].items.remove(at: itemIdx)
                    var adjustedPos = insertPosition
                    if shootDays[dayIdx].id == targetDayId && itemIdx < insertPosition { adjustedPos -= 1 }
                    insertItemIntoDay(item: item, dayId: targetDayId, position: adjustedPos)
                    insertPosition += 1
                    break
                }
            }
        }
        onSceneChanged()
    }

    private func insertItemIntoDay(item: DayItem, dayId: UUID, position: Int) {
        guard let dayIdx = shootDays.firstIndex(where: { $0.id == dayId }) else { return }
        let clamped = min(max(0, position), shootDays[dayIdx].items.count)
        shootDays[dayIdx].items.insert(item, at: clamped)
    }

    // MARK: - Banner (non-scene item) CRUD

    private func addBanner(label: String, note: String, time: String, to dayId: UUID) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, let dayIdx = shootDays.firstIndex(where: { $0.id == dayId }) else { return }
        let banner = BannerItem(
            label: trimmedLabel,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedTime: TimeParser.parseToMinutes(time) ?? 0
        )
        shootDays[dayIdx].items.append(.banner(banner))
        onSceneChanged()
    }

    private func removeBanner(id: UUID, from dayId: UUID) {
        guard let dayIdx = shootDays.firstIndex(where: { $0.id == dayId }) else { return }
        shootDays[dayIdx].items.removeAll { $0.id == id }
        onSceneChanged()
    }

    /// Updates an existing banner's fields in place, preserving its id — a BannerItem's
    /// own initializer always mints a fresh random id, so this edits the item found in the
    /// array directly rather than constructing a replacement.
    private func updateBanner(id: UUID, label: String, note: String, time: String, in dayId: UUID) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty,
              let dayIdx = shootDays.firstIndex(where: { $0.id == dayId }),
              let itemIdx = shootDays[dayIdx].items.firstIndex(where: { $0.id == id }),
              case .banner(var banner) = shootDays[dayIdx].items[itemIdx]
        else { return }
        banner.label         = trimmedLabel
        banner.note          = note.trimmingCharacters(in: .whitespacesAndNewlines)
        banner.estimatedTime = TimeParser.parseToMinutes(time) ?? 0
        shootDays[dayIdx].items[itemIdx] = .banner(banner)
        onSceneChanged()
    }

    // MARK: - Selection

    /// Applies click / ⌘-click / ⇧-click semantics for scenes on the calendar, reading live
    /// modifier flags the same way the Boneyard does. A shift-click range only applies when
    /// the anchor scene is in the same day — reordering "up or down the schedule" doesn't have
    /// a single obvious axis to range over, so a cross-day shift-click just selects the one scene.
    private func selectScene(_ scene: Scene, dayId: UUID) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedSceneIDs.contains(scene.id) { selectedSceneIDs.remove(scene.id) } else { selectedSceneIDs.insert(scene.id) }
            lastSelectedSceneID = scene.id
        } else if flags.contains(.shift),
                  let anchor = lastSelectedSceneID,
                  let dayIdx = shootDays.firstIndex(where: { $0.id == dayId }),
                  let anchorIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == anchor }),
                  let targetIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == scene.id }) {
            let range = anchorIdx < targetIdx ? anchorIdx...targetIdx : targetIdx...anchorIdx
            selectedSceneIDs.formUnion(range.map { shootDays[dayIdx].scenes[$0].id })
        } else {
            selectedSceneIDs = [scene.id]
            lastSelectedSceneID = scene.id
        }
    }

    // MARK: - Remove from Day

    /// Removes the clicked scene from its day back into the Boneyard — or, if it's part of
    /// a multi-scene selection, every selected scene that's currently scheduled anywhere on
    /// the calendar, mirroring the grouping behavior of "Send to Day".
    private func removeFromDay(_ scene: Scene, dayId: UUID) {
        if selectedSceneIDs.contains(scene.id), selectedSceneIDs.count > 1 {
            for dayIdx in shootDays.indices {
                let matching = shootDays[dayIdx].scenes.filter { selectedSceneIDs.contains($0.id) }
                for s in matching {
                    removeScene(s, shootDays[dayIdx].id)
                }
            }
        } else {
            removeScene(scene, dayId)
        }
        onSceneChanged()
    }

    // MARK: - Send to Day

    /// Right-clicking a scene that's part of the current multi-selection sends the whole
    /// selection; right-clicking a scene outside the selection sends just that one, mirroring
    /// the same "act on the selection, or act on what you clicked" rule the Boneyard drag uses.
    private func beginSendToDay(_ scene: Scene) {
        if selectedSceneIDs.contains(scene.id), selectedSceneIDs.count > 1 {
            // Selection is shared with the Boneyard, so a right-click here could be acting on
            // a mix of scheduled and unscheduled scenes. Order scheduled ones by their existing
            // calendar position, then append any still-unscheduled selected ones from the
            // Boneyard, rather than relying on Set's arbitrary iteration order.
            let scheduledOrdered = shootDays.flatMap { $0.scenes.map(\.id) }.filter { selectedSceneIDs.contains($0) }
            let boneyardOrdered  = allScenes.map(\.id).filter { selectedSceneIDs.contains($0) }
            sendToDaySceneIDs = scheduledOrdered + boneyardOrdered
        } else {
            sendToDaySceneIDs = [scene.id]
        }
        showingSendToDaySheet = true
    }

    /// Moves the given scenes (from the Boneyard or any day) to the end of the target day,
    /// preserving the order they're passed in, and clears them from the selection afterward.
    private func sendScenes(_ ids: [UUID], toDay targetDayId: UUID) {
        guard let targetIdx = shootDays.firstIndex(where: { $0.id == targetDayId }) else { return }
        var insertPosition = shootDays[targetIdx].items.count

        for uuid in ids {
            if let idx = allScenes.firstIndex(where: { $0.id == uuid }) {
                let scene = allScenes.remove(at: idx)
                insertItemIntoDay(item: .scene(scene), dayId: targetDayId, position: insertPosition)
                insertPosition += 1
                continue
            }
            for dayIdx in shootDays.indices {
                if let sceneIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == uuid }) {
                    let scene = shootDays[dayIdx].scenes.remove(at: sceneIdx)
                    insertItemIntoDay(item: .scene(scene), dayId: targetDayId, position: insertPosition)
                    insertPosition += 1
                    break
                }
            }
        }

        selectedSceneIDs.subtract(ids)
        onSceneChanged()
    }

    private func duplicateScene(_ scene: Scene) {
        allScenes.append(Scene(
            title: scene.title + " (Copy)",
            duration: scene.duration,
            estimatedTime: scene.estimatedTime,
            dayNightType: scene.dayNightType,
            cast: scene.cast,
            summary: scene.summary,
            productionID: scene.productionID,
            sceneNumber: scene.sceneNumber
        ))
        onSceneChanged()
    }

    // MARK: - Edit State

    private func editScene(dayIndex: Int, sceneIndex: Int, scene: Scene, dayId: UUID) {
        editingDayIndex   = dayIndex
        editingSceneIndex = sceneIndex
        editingScene      = scene
        editingDayId      = dayId
        showingEditSheet  = true
    }

    private func clearEditingState() {
        editingScene      = nil
        editingDayId      = nil
        editingDayIndex   = nil
        editingSceneIndex = nil
    }

    // MARK: - Day Rearrange

    /// Moves scenes and call sheet from sourceDayId to targetDayId.
    /// If target has content, swaps both days' items (scenes and banners together) and call
    /// sheet data. The calendar dates themselves never change — only the content moves.
    /// Swapping the full items list rather than just scenes matters now: swapping only
    /// scenes would silently strand any banner on the day it started on, orphaned on the
    /// wrong date after the scenes around it had already moved.
    private func handleDayRearrange(sourceDayId: UUID, targetDayId: UUID) {
        guard sourceDayId != targetDayId,
              let sourceIdx = shootDays.firstIndex(where: { $0.id == sourceDayId }),
              let targetIdx = shootDays.firstIndex(where: { $0.id == targetDayId })
        else { return }

        // Swap items and call sheet, preserving both dates
        let sourceItems     = shootDays[sourceIdx].items
        let sourceCallSheet = shootDays[sourceIdx].callSheet
        let targetItems     = shootDays[targetIdx].items
        let targetCallSheet = shootDays[targetIdx].callSheet

        shootDays[sourceIdx].items     = targetItems
        shootDays[sourceIdx].callSheet = targetCallSheet
        shootDays[targetIdx].items     = sourceItems
        shootDays[targetIdx].callSheet = sourceCallSheet

        draggingDayId   = nil
        dayDropTargetId = nil
        onSceneChanged()
    }
}

// MARK: - SceneCardView

struct SceneCardView: View {
    let scene:      Scene
    let dayId:      UUID
    let dayIndex:   Int
    let sceneIndex: Int
    @Binding var interactingItemId: UUID?
    let isSelected:     Bool
    let selectionCount: Int
    let showCast:       Bool
    let hasConflict:    Bool
    let onEdit:      () -> Void
    let onRemove:    () -> Void
    let onDuplicate: () -> Void
    let onDragStart: () -> Void
    let onDragEnd:   () -> Void
    let onSelect:    () -> Void
    let onSendToDay: () -> Void

    private var isDragging: Bool { interactingItemId == scene.id }
    private var isMultiSelected: Bool { isSelected && selectionCount > 1 }
    /// A conflict (this scene's cast includes someone marked unavailable that day) takes
    /// visual priority over the normal Day/Night/Custom color — it's the more urgent thing
    /// to notice at a glance.
    private var displayColor: Color { hasConflict ? .red : scene.dayNightType.color }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Circle()
                .fill(displayColor)
                .frame(width: 8, height: 8)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    if !scene.sceneNumber.isEmpty {
                        Text(scene.sceneNumber)
                            .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(scene.title)
                        .font(.caption2).fontWeight(.medium).lineLimit(2)
                    if hasConflict {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.red)
                    }
                }

                Text("(\(formattedEighths(scene.duration)), \(formattedTime(scene.estimatedTime)))")
                    .font(.caption2).foregroundColor(.secondary)
                    .lineLimit(1)

                // Cast only shows when the sidebar is collapsed — with the sidebar open there's
                // not enough width for it to read cleanly, and it's left off the PDF entirely
                // since PDFExporter never draws it.
                if showCast, !scene.cast.isEmpty {
                    Text(scene.cast.joined(separator: ", "))
                        .font(.caption2).foregroundColor(.secondary).italic()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(displayColor.opacity(isDragging ? 0.3 : (hasConflict ? 0.22 : 0.15)))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isSelected ? Color.accentColor : displayColor.opacity(isDragging ? 0.8 : (hasConflict ? 0.9 : 0.4)),
                            lineWidth: isSelected ? 2 : (isDragging || hasConflict ? 2 : 1)
                        )
                )
        )
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .opacity(isDragging ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .fastTooltip(scene.tooltipText)
        .onDrag {
            interactingItemId = scene.id
            onDragStart()
            return NSItemProvider(object: scene.id.uuidString as NSString)
        } preview: {
            HStack(spacing: 4) {
                Circle().fill(scene.dayNightType.color).frame(width: 8, height: 8)
                Text(scene.title).font(.caption).fontWeight(.medium)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(radius: 4)
            )
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { interactingItemId = nil; onEdit() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { interactingItemId = nil; onSelect() })
        .contextMenu {
            Button("Edit Scene") { interactingItemId = nil; onEdit() }

            Button(isMultiSelected ? "Remove \(selectionCount) Scenes from Day" : "Remove from Day") {
                interactingItemId = nil; onRemove()
            }
            Divider()
            Button("Duplicate Scene") { interactingItemId = nil; onDuplicate() }
            Divider()
            Button(isMultiSelected ? "Send \(selectionCount) Scenes to Day…" : "Send to Day…") {
                interactingItemId = nil; onSendToDay()
            }
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging { onDragEnd() }
        }
    }
}

// MARK: - BannerCardView

/// A lightweight, visually distinct card for a non-scene day item — a company move, a
/// safety meeting, pre-lighting, and so on. No page count, no cast, no day/night color —
/// just a label and an optional note, with a dashed border and a flag icon instead of a
/// solid one, so it reads as a note rather than a shootable scene. Matches how a real call
/// sheet renders one of these: a single bold banner line, not a scene row — see
/// CALLSHEET_LAYOUT.md §3.2.
struct BannerCardView: View {
    let banner: BannerItem
    @Binding var interactingItemId: UUID?
    let onEdit:      () -> Void
    let onDelete:    () -> Void
    let onDragStart: () -> Void
    let onDragEnd:   () -> Void

    private var isDragging: Bool { interactingItemId == banner.id }

    // Label and time share one line instead of each getting their own — a scene card is
    // already at minimum two lines (title, then duration/time), so keeping this to one
    // line, most of the time, is what makes a banner noticeably *smaller* than a scene
    // rather than larger. The note isn't shown inline at all; it's in the hover tooltip
    // instead, the same place a scene's cast/summary detail lives.
    private var displayText: String {
        let label = banner.label.isEmpty ? "UNTITLED ITEM" : banner.label.uppercased()
        guard banner.estimatedTime > 0 else { return label }
        return "\(label)  ·  \(formattedTime(banner.estimatedTime))"
    }

    private var tooltipText: String {
        var lines: [String] = [banner.label.isEmpty ? "Untitled item" : banner.label]
        if banner.estimatedTime > 0 {
            lines.append("Est: \(formattedTime(banner.estimatedTime))")
        }
        if !banner.note.isEmpty {
            lines.append(banner.note)
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flag.fill")
                .font(.system(size: 7))
                .foregroundColor(.secondary)
            Text(displayText)
                .font(.caption2).fontWeight(.bold)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(isDragging ? 0.30 : 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(style: StrokeStyle(lineWidth: isDragging ? 2 : 1, dash: [3, 2]))
                        .foregroundColor(.secondary.opacity(isDragging ? 0.9 : 0.5))
                )
        )
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .opacity(isDragging ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .fastTooltip(tooltipText)
        .onDrag {
            interactingItemId = banner.id
            onDragStart()
            return NSItemProvider(object: banner.id.uuidString as NSString)
        } preview: {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill").font(.caption2).foregroundColor(.secondary)
                Text(banner.label).font(.caption).fontWeight(.semibold)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(radius: 4)
            )
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { interactingItemId = nil; onEdit() })
        .contextMenu {
            Button("Edit Item") { interactingItemId = nil; onEdit() }
            Button("Delete Item", role: .destructive) {
                interactingItemId = nil
                onDelete()
            }
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging { onDragEnd() }
        }
    }
}

// MARK: - DropIndicatorView

struct DropIndicatorView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.blue.opacity(0.3))
            .frame(height: 6)
            .padding(.horizontal, 8)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.blue, lineWidth: 1))
            .accessibilityLabel("Drop zone")
            .animation(.easeInOut(duration: 0.3), value: true)
    }
}

// MARK: - ItemDropDelegate

/// Handles dropping a scene or a banner onto a specific slot in a day's items list — the
/// same delegate for both, since from here it's just "a dragged ID landed at this position."
struct ItemDropDelegate: DropDelegate {
    let dayId:    UUID
    let position: Int
    @Binding var dropTargetDayId:   UUID?
    @Binding var dropTargetPosition: Int?
    let onDrop: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text.identifier])
    }
    func dropEntered(info: DropInfo) {
        dropTargetDayId      = dayId
        dropTargetPosition   = position
    }
    func dropExited(info: DropInfo) {
        if dropTargetDayId == dayId && dropTargetPosition == position {
            dropTargetDayId    = nil
            dropTargetPosition = nil
        }
    }
    func performDrop(info: DropInfo) -> Bool {
        defer { dropTargetDayId = nil; dropTargetPosition = nil }
        guard let provider = info.itemProviders(for: [UTType.text.identifier]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { item, _ in
            if let id = item as? String {
                DispatchQueue.main.async { onDrop(id) }
            }
        }
        return true
    }
}

// MARK: - CombinedDayDropDelegate
// Handles both scene drops (from Boneyard/other days) and day rearrange drops
// by inspecting the "day:" prefix on the drag identifier.

struct CombinedDayDropDelegate: DropDelegate {
    let dayId:    UUID
    let items:    [DayItem]
    @Binding var dropTargetDayId:    UUID?
    @Binding var dropTargetPosition: Int?
    @Binding var dayDropTargetId:    UUID?
    @Binding var draggingDayId:      UUID?
    let onItemDrop: (String) -> Void
    let onDayDrop:  (UUID)   -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text.identifier])
    }

    func dropEntered(info: DropInfo) {
        // Peek at the identifier to decide which highlight to show
        // We can't read the value synchronously, so we show day highlight
        // if draggingDayId is set, item highlight otherwise
        if draggingDayId != nil {
            dayDropTargetId = dayId
        } else if items.isEmpty {
            dropTargetDayId  = dayId
            dropTargetPosition = 0
        }
    }

    func dropExited(info: DropInfo) {
        if dayDropTargetId == dayId   { dayDropTargetId  = nil }
        if dropTargetDayId == dayId   { dropTargetDayId  = nil; dropTargetPosition = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dropTargetDayId    = nil
            dropTargetPosition = nil
            dayDropTargetId    = nil
        }

        guard let provider = info.itemProviders(for: [UTType.text.identifier]).first else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let idString = item as? String else { return }
            DispatchQueue.main.async {
                if idString.hasPrefix("day:"),
                   let uuid = UUID(uuidString: String(idString.dropFirst(4))) {
                    onDayDrop(uuid)
                } else {
                    onItemDrop(idString)
                }
            }
        }
        return true
    }
}

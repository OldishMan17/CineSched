// ContentView.swift
// Root view: holds app state, sidebar, toolbar, and calendar.
// Business logic lives in ProjectStore.swift (persistence),
// CalendarView.swift (calendar/drag-drop), and the other focused files.

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Custom UTType for FDX files

extension UTType {
    static var fdx: UTType { UTType(importedAs: "com.finaldraft.fdx") }
}

// MARK: - Script drag-and-drop

/// Highlights the window and accepts a dropped .fdx/.fountain file. Kept as its own
/// ViewModifier rather than inline .overlay/.dropDestination calls on ContentView's body
/// because attaching them directly there overwhelmed the type-checker on that already-long
/// modifier chain — isolating them into their own `body(content:)` keeps that inference local.
private struct ScriptDropModifier: ViewModifier {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 4)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                onDrop(urls)
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }
}

/// Confirmation alert shown after a .fdx/.fountain file is parsed, before the resulting
/// scenes are added to the project — "Import" commits them, "Cancel" discards them.
private struct ImportConfirmAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content.alert("Import Script", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) { onCancel() }
            Button("Import") { onConfirm() }
        } message: {
            Text(message)
        }
    }
}

// MARK: - ContentView

struct ContentView: View {

    // MARK: Project state
    @State var allScenes:   [Scene]    = []
    @State var shootDays:   [ShootDay] = generateDays(
        from: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
        to:   Calendar.current.date(byAdding: .day, value: 30,  to: Date())!
    )
    @State var startDate:   Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State var endDate:     Date = Calendar.current.date(
        byAdding: .day, value: 30, to: Date())!
    @State var projectTitle: String = "Untitled Movie"
    @State var isShiftModeEnabled: Bool = false
    @State var projectCreatedDate: Date = Date()  // preserved across saves; never reset on re-save
    @State var productionInfo: ProductionInfo = ProductionInfo()
    // Only one production exists today (no UI yet to add/switch), but every scene already
    // carries a productionID pointing at it — see Production.defaultID in Models.swift.
    @State var productions: [Production] = [Production(id: Production.defaultID, name: "Untitled Movie")]

    // Auto-save: flip to true on any change; a debounced .onChange triggers the actual write
    @State var hasUnsavedChanges: Bool = false

    // MARK: UI / sheet state
    @State private var newSceneTitle:  String = ""
    @State private var newSceneNumber: String = ""
    @State private var newDuration:    String = ""
    @State private var newEstimate:    String = ""

    @State var showingAlert             = false
    @State var showingImportAlert       = false
    @State var showingImportConfirm     = false
    @State private var showingClearAllConfirmation = false
    @State private var showingUnscheduledSceneEditSheet = false

    @State var alertMessage:   String = ""
    @State var importMessage:  String = ""
    @State private var importedScenesCount = 0
    // Scenes parsed from a .fdx/.fountain import, staged until the user confirms via
    // the Import Script alert's "Import" button (or discarded on "Cancel").
    @State var pendingImportScenes: [Scene] = []

    // Unscheduled-scene editing
    @State private var editingUnscheduledScene:      Scene?
    @State private var editingUnscheduledSceneIndex: Int?

    // Appearance
    @AppStorage("CineSchedDarkMode") var isDarkMode: Bool = false
    // Schedule PDF export — defaults to black-and-white; some productions print this on
    // office printers where color washes out or costs more, so B&W stays the safe default.
    @AppStorage("CineSchedExportPDFColor") var exportPDFInColor: Bool = false
    @State private var showingExportPDFOptions = false
    @EnvironmentObject var recentFiles: RecentFilesStore
    /// The file this project was last saved to or loaded from — nil for a project that's
    /// never touched disk yet. "Save" writes here silently when set; "Save As…" always
    /// prompts and updates this to the newly chosen location. Persisted across launches
    /// (see setCurrentFileURL/restoreCurrentFileURL in ProjectStore.swift) — otherwise
    /// every first Save after relaunching the app would have nowhere remembered to save
    /// to and would silently fall back to acting like Save As.
    @State var currentFileURL: URL? = nil

    // Production Setup sheet
    @State private var showingProductionSetup = false
    @State private var showingConflictReport = false
    @State private var conflictReportResults: [ScheduleConflict] = []
    /// Set to trigger the calendar scrolling to a specific date — used when jumping to a
    /// conflict from the report. Reset to nil right after the calendar handles it.
    @State private var scrollToDate: Date? = nil
    /// Cached like sortedScenes — recomputed only on relevant changes rather than on every
    /// render, so the red-strip/warning-badge check doesn't re-scan the whole schedule on
    /// every interaction. This is the "autoscan": conflicts are recomputed automatically
    /// any time scenes, the schedule, or cast availability changes, with no need to
    /// manually trigger a scan — Scan for Conflicts… just opens the full report on demand.
    @State private var conflictDates: Set<Date> = []
    @State private var conflictSceneIDs: Set<UUID> = []

    // Boneyard sort — persisted so your preferred sort (e.g. Location) is still
    // applied the next time you open the project.
    enum BoneyardSort: String, CaseIterable { case defaultOrder, sceneNumber, location, intExt, cast, dayNight }
    @AppStorage("CineSchedBoneyardSort") private var boneyardSort: BoneyardSort = .defaultOrder

    // Collapsible sidebar sections — persisted so the layout you leave with is the
    // layout you come back to. Collapsing "Select Date Range" and "New Scene" frees
    // up vertical room for the Boneyard, which expands to fill whatever is left.
    @AppStorage("CineSchedDateRangeExpanded") private var isDateRangeExpanded: Bool = true
    @AppStorage("CineSchedNewSceneExpanded")  private var isNewSceneExpanded:  Bool = true

    // Scene multi-selection — shared between the Boneyard and the calendar so a selection
    // made in one place (e.g. ⇧-click a range) can be dragged or sent-to-day from either.
    // ⌘-click toggles, ⇧-click extends a range (in whatever order the current view shows),
    // and a selection of more than one scene moves as a group.
    @State private var selectedSceneIDs:   Set<UUID> = []
    @State private var lastSelectedSceneID: UUID?

    // Highlights the Boneyard while a scene dragged out of the calendar is hovering over it.
    @State private var isBoneyardDropTargeted = false

    // Highlights the whole window while a script file dragged in from Finder is hovering over it.
    @State private var isScriptDropTargeted = false

    // MARK: - Computed statistics

    private var scheduledDays: [ShootDay] { shootDays.filter { !$0.scenes.isEmpty } }
    private var totalScenes:   Int        { scheduledDays.reduce(0) { $0 + $1.scenes.count } }
    private var totalDuration: String     { formattedEighths(scheduledDays.reduce(0) { $0 + $1.totalDuration }) }
    private var totalEstTime:  String     { formattedTime(scheduledDays.reduce(0) { $0 + $1.totalEstimatedTime }) }

    // MARK: - Body

    // Sidebar visibility — tracked explicitly (rather than the default NavigationSplitView
    // behavior) so the calendar can show more detail on scene strips (cast) when the sidebar
    // is collapsed and there's more horizontal room to use.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private var isSidebarCollapsed: Bool { columnVisibility == .detailOnly }

    var body: some View {
        // Split into two chained expressions (`base` then the return below) rather than one
        // giant chain — even with the alert/drop logic pulled into their own ViewModifiers,
        // the type-checker still hit "unable to type-check this expression in reasonable
        // time" on the full chain in one piece. Splitting it here keeps each half small
        // enough for Swift to infer independently.
        let base =
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
                // Caps how wide the sidebar can be dragged. Without a max, the sidebar
                // was free to expand and eat into the calendar's width no matter how
                // wide the window was — which is why widening the window alone didn't
                // stop the day columns from getting squeezed.
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
        } detail: {
            detailView
        }
        // Lets a .fdx or .fountain file be dropped anywhere in the window to import it —
        // the same importScript(from:) path the toolbar's Import Script button uses, so
        // drag-and-drop and the file picker always agree on parsing/estimation behavior.
        // Pulled into its own ViewModifier (rather than inline .overlay/.dropDestination
        // calls here) because adding them directly to this already-long modifier chain
        // blew past the type-checker's time budget ("unable to type-check in reasonable
        // time") — isolating it into its own `body(content:)` keeps that inference local.
        .modifier(ScriptDropModifier(isTargeted: $isScriptDropTargeted, onDrop: handleScriptDrop))
        // The sidebar's open/close animation was racing against this window's custom
        // toolbar mid-slide, which crashed macOS's own layout system (a window-layout
        // watchdog killing the app after too many back-to-back relayouts). Turning off
        // the animation for this view means the sidebar now snaps open/closed instantly
        // instead of sliding — a little less polished, but there's no multi-frame
        // animation left for the toolbar to collide with.
        .transaction { $0.disablesAnimations = true }
        // Floor for the window itself: below this, the sidebar and the 7 calendar day
        // columns (95pt each, enough for the compact "Thu 07/09" fallback) no longer
        // fit without squishing or overlapping, so macOS won't let the window shrink
        // past this.
        .frame(minWidth: 1050, minHeight: 600)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .alert("Script Import",  isPresented: $showingImportAlert) { Button("OK") {} } message: { Text(importMessage) }
        // Pulled into its own ViewModifier — attaching this .alert inline here (like the
        // one above it) blew past the type-checker's time budget on this already-long
        // modifier chain, same issue the drag-and-drop work hit earlier.
        .modifier(ImportConfirmAlertModifier(
            isPresented: $showingImportConfirm,
            message: importMessage,
            onConfirm: confirmPendingScriptImport,
            onCancel: cancelPendingScriptImport
        ))
        .alert("CineSched",      isPresented: $showingAlert)        { Button("OK") {} } message: { Text(alertMessage) }

        return base
        .confirmationDialog("Clear All Scenes", isPresented: $showingClearAllConfirmation, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) { clearAllScenes() }
            Button("Cancel",    role: .cancel)      {}
        } message: {
            Text("This will clear all scenes, call sheets, and the project title. This action cannot be undone.")
        }
        .sheet(isPresented: $showingUnscheduledSceneEditSheet) { unscheduledEditSheet }
        .onChange(of: showingUnscheduledSceneEditSheet) { isShowing in
            if !isShowing { clearUnscheduledEditingState() }
        }
        .sheet(isPresented: $showingProductionSetup) {
            ProductionSetupSheet(
                productionInfo: $productionInfo,
                isPresented: $showingProductionSetup,
                onSave: { markDirty(); recomputeConflicts() },
                onCharacterRenamed: renameCastCharacter
            )
        }
        .sheet(isPresented: $showingConflictReport) {
            ConflictReportSheet(
                conflicts: conflictReportResults,
                onSelectDate: { date in
                    showingConflictReport = false
                    scrollToDate = date
                },
                onDismiss: { showingConflictReport = false }
            )
        }
        .onAppear {
            loadDefaultProject()
            restoreCurrentFileURL()
            recomputeSortedScenes()
            recomputeConflicts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .csNewProject)) { _ in
            showingClearAllConfirmation = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .csOpenProject)) { _ in
            showJSONOpenPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .csOpenRecentProject)) { note in
            guard let url = note.object as? URL else { return }
            loadProject(from: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .csImportScript)) { _ in
            showScriptOpenPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .csSaveProject)) { _ in
            saveProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .csSaveProjectAs)) { _ in
            showNativeSaveDialog()
        }
        .onReceive(NotificationCenter.default.publisher(for: .csExportSchedulePDF)) { _ in
            showSchedulePDFSavePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .csExportDaysOutOfDays)) { _ in
            showDaysOutOfDaysPDFSavePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .csExportContactSheet)) { _ in
            showContactSheetPDFSavePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .csOpenProductionSetup)) { _ in
            showingProductionSetup = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .csScanForConflicts)) { _ in
            conflictReportResults = ConflictScanner.scan(shootDays: shootDays, productionInfo: productionInfo)
            showingConflictReport = true
        }
        .onChange(of: allScenes) { _, _ in
            recomputeSortedScenes()
            pruneSelection()
            recomputeConflicts()
        }
        .onChange(of: boneyardSort) { _, _ in
            recomputeSortedScenes()
        }
        // Debounced auto-save: waits 2 seconds after the last change before writing
        .onChange(of: hasUnsavedChanges) { _, isDirty in
            guard isDirty else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                saveDefaultProject()
                hasUnsavedChanges = false
            }
        }
        .toolbar { mainToolbar }
    }

    /// Handles a .fdx/.fountain file dropped anywhere on the window, via the same
    /// importScript(from:) path the toolbar's Import Script button uses.
    private func handleScriptDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        let ext = url.pathExtension.lowercased()
        guard ext == "fdx" || ext == "fountain" else { return false }
        importScript(from: url)
        return true
    }

    // MARK: - Toolbar

    // Each button pairs an SF Symbol with its label via Label(...), so the icon stays
    // visible (and each button stays identifiable) even when the window is narrow and
    // macOS shrinks the toolbar down to icon-only. The .help() tooltip always leads with
    // the button's name, so hovering confirms what it is even in icon-only mode.
    //
    // Every item gets an explicit, fixed `id`. Without one, SwiftUI has to infer each
    // toolbar item's identity from its position/content, and re-derives that guess every
    // time this toolbar is rebuilt — which happens on every frame of the sidebar's
    // open/close animation. An unstable guess there is what triggered a macOS layout
    // crash ("Update Constraints in Window") when toggling the sidebar. A fixed id
    // removes the guesswork.
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(id: "new", placement: .automatic) {
            Button {
                showingClearAllConfirmation = true
            } label: {
                Label("New", systemImage: "calendar.badge.plus")
            }
            .foregroundColor(.red)
            .help("New — clear all scenes and start a new project")
        }

        ToolbarItem(id: "productionSetup", placement: .automatic) {
            Button {
                showingProductionSetup = true
            } label: {
                Label("Production Setup", systemImage: "calendar.and.person")
            }
            .help("Production Setup — company, director, cast, and crew")
        }

        ToolbarItem(id: "importScript", placement: .automatic) {
            Button {
                showScriptOpenPanel()
            } label: {
                Label("Import Script", systemImage: "document.badge.plus")
            }
            .help("Import Script — import scenes from a Final Draft .fdx or Fountain .fountain file")
        }

        ToolbarItem(id: "save", placement: .automatic) {
            Button {
                saveProject()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .help("Save — save project as a .json file")
        }

        ToolbarItem(id: "load", placement: .automatic) {
            Button {
                showJSONOpenPanel()
            } label: {
                Label("Load", systemImage: "folder.badge.plus")
            }
            .help("Load — load a saved project")
        }

        ToolbarItem(id: "exportPDF", placement: .automatic) {
            Button {
                showingExportPDFOptions = true
            } label: {
                Label("Export PDF", systemImage: "square.and.arrow.up")
            }
            .foregroundColor(.blue)
            .help("Export PDF — export the calendar schedule as a PDF")
            .popover(isPresented: $showingExportPDFOptions) {
                exportPDFOptionsPopover
            }
        }

        // This item's label text/icon both change with isDarkMode, but the id stays
        // fixed — so SwiftUI updates the existing button in place instead of treating
        // a mode switch as "remove one item, insert a different one."
        ToolbarItem(id: "appearanceToggle", placement: .automatic) {
            Button {
                isDarkMode.toggle()
            } label: {
                Label(isDarkMode ? "Light Mode" : "Dark Mode",
                      systemImage: isDarkMode ? "lightswitch.off" : "lightswitch.on")
            }
            .help(isDarkMode ? "Light Mode — switch to light appearance" : "Dark Mode — switch to dark appearance")
        }
    }

    // MARK: - Export PDF Options

    /// Shown before the actual save panel — defaults to black-and-white every time a project
    /// is opened fresh (the toggle itself persists between exports within a session via
    /// @AppStorage, but always starts unchecked for a reason: some productions print this on
    /// office printers where color washes out or simply costs more per page).
    private var exportPDFOptionsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export Schedule PDF").font(.headline)
            Toggle("Print in color", isOn: $exportPDFInColor)
                .toggleStyle(.checkbox)
            Text("Day scenes orange, night scenes blue, custom scenes green — matching the calendar on screen. Leave off for black-and-white.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
            HStack {
                Spacer()
                Button("Cancel") { showingExportPDFOptions = false }
                Button("Export…") {
                    showingExportPDFOptions = false
                    showSchedulePDFSavePanel()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        // The whole sidebar scrolls as one piece now. Previously only the Boneyard list
        // (at the bottom) had its own scroll view — if the title, date range, and new
        // scene sections above it took up more height than the sidebar had room for
        // (easy to hit in a shorter window, or with both sections expanded), the Boneyard
        // got squeezed down with nothing able to scroll it back into view. Now the whole
        // column scrolls together, so the Boneyard is always reachable.
        ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Movie Title", text: $projectTitle)
                .font(.title2)
                .padding(.bottom, 2)
                .onChange(of: projectTitle) { _ in markDirty() }

            Text("Shoot Days: \(shootDays.filter { !$0.scenes.isEmpty }.count)")
                .font(.subheadline).foregroundColor(.gray)
                .lineLimit(1)

            if let first = shootDays.first?.date, let last = shootDays.last?.date {
                Text("From \(formattedDate(first)) to \(formattedDate(last))")
                    .font(.subheadline).foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Divider().padding(.vertical)

            // Date range picker — collapsible to free up room for the Boneyard
            DisclosureGroup(isExpanded: $isDateRangeExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { _ in markDirty() }
                    DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                        .onChange(of: endDate) { _ in markDirty() }

                    Toggle(isOn: $isShiftModeEnabled) { Text("Shift Schedule") }
                        .toggleStyle(.switch)
                        .help("When enabled, changing the Start Date shifts all scenes on the calendar.")
                        .onChange(of: isShiftModeEnabled) { _ in markDirty() }

                    Button("Update Calendar") { updateShootDays(from: startDate, to: endDate) }
                }
                .padding(.top, 6)
            } label: {
                Text("Select Date Range").font(.headline)
            }

            Divider().padding(.vertical)

            // New Scene form — collapsible to free up room for the Boneyard
            DisclosureGroup(isExpanded: $isNewSceneExpanded) {
                NewSceneInputView(
                    newSceneTitle:  $newSceneTitle,
                    newSceneNumber: $newSceneNumber,
                    newDuration:    $newDuration,
                    newEstimate:    $newEstimate,
                    allScenes:      $allScenes,
                    onSceneAdded:   { markDirty() }
                )
                .padding(.top, 6)
            } label: {
                Text("New Scene").font(.headline)
            }

            Divider().padding(.vertical)

            // Boneyard header with sort menu
            HStack {
                Text("Boneyard").font(.headline)
                if !selectedSceneIDs.isEmpty {
                    Text("· \(selectedSceneIDs.count) selected")
                        .font(.caption).foregroundColor(.accentColor)
                    Button("Clear") { selectedSceneIDs = []; lastSelectedSceneID = nil }
                        .buttonStyle(.plain)
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Menu {
                    Button("Default Order")  { boneyardSort = .defaultOrder }
                    Button("Scene Number")   { boneyardSort = .sceneNumber }
                    Button("Location")       { boneyardSort = .location }
                    Button("INT / EXT")      { boneyardSort = .intExt }
                    Button("Cast")           { boneyardSort = .cast }
                    Button("Day / Night")    { boneyardSort = .dayNight }
                } label: {
                    HStack(spacing: 3) {
                        Text(boneyardSortLabel)
                            .font(.caption).foregroundColor(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Text("⌘-click or ⇧-click to select multiple, then drag as a group")
                .font(.caption2).foregroundColor(.secondary)

            boneyardList
        }
        .padding()
        }
        .background(
            isBoneyardDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear
        )
        // Attached to the whole sidebar's ScrollView — a direct, always-present child of
        // the NavigationSplitView sidebar slot — rather than nested inside the Boneyard's
        // own content. Nesting it deep inside the scrollable content never once registered
        // a hover/drop in this pane, no matter which drag-and-drop API was used; this tests
        // whether that was specifically about being buried inside the scroll content.
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            moveScenesToBoneyard(payload)
            return true
        } isTargeted: { targeted in
            isBoneyardDropTargeted = targeted
        }
        // A script file (.fdx/.fountain) dropped anywhere on this ScrollView needs its
        // own dropDestination here too, alongside the String one above — a dropDestination
        // further up the view tree (on the whole window) does not reliably receive drags
        // that land on a pane which already has its own dropDestination for a different
        // payload type, per the note above this same view had to be moved for the boneyard
        // drop to register reliably at all.
        .dropDestination(for: URL.self) { urls, _ in
            handleScriptDrop(urls)
        } isTargeted: { targeted in
            isScriptDropTargeted = targeted
        }
        .frame(minWidth: 300, maxHeight: .infinity)
    }

    // MARK: - Boneyard sort helpers

    /// Re-scans the schedule against Production Setup's cast availability. Cached into
    /// conflictDates/conflictSceneIDs (like sortedScenes) rather than recomputed on every
    /// render, and called from every place that could change the answer: loading a
    /// project, any calendar-side scene move, and saving Production Setup.
    private func recomputeConflicts() {
        let conflicts = ConflictScanner.scan(shootDays: shootDays, productionInfo: productionInfo)
        conflictDates = ConflictScanner.conflictDates(conflicts)
        conflictSceneIDs = ConflictScanner.conflictSceneIDs(conflicts)
    }

    private func pruneSelection() {
        let scheduledIDs = Set(shootDays.flatMap { $0.scenes.map(\.id) })
        let boneyardIDs  = Set(allScenes.map(\.id))
        selectedSceneIDs = selectedSceneIDs.intersection(scheduledIDs.union(boneyardIDs))
    }

    /// Renames a character everywhere it appears in scene cast lists — both unscheduled
    /// (Boneyard) scenes and every scheduled day — so a rename in Production Setup keeps
    /// matching up with the actor lookup used by cast lists and call sheets, instead of
    /// silently going stale the moment the character's name changes.
    private func renameCastCharacter(from oldName: String, to newName: String) {
        let old = oldName.trimmingCharacters(in: .whitespaces)
        let new = newName.trimmingCharacters(in: .whitespaces)
        guard !old.isEmpty, !new.isEmpty, old.caseInsensitiveCompare(new) != .orderedSame else { return }

        func renamed(_ cast: [String]) -> [String] {
            cast.map { $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0 }
        }

        for i in allScenes.indices {
            allScenes[i].cast = renamed(allScenes[i].cast)
        }
        for d in shootDays.indices {
            for s in shootDays[d].scenes.indices {
                shootDays[d].scenes[s].cast = renamed(shootDays[d].scenes[s].cast)
            }
            // A day's cast override (if manually edited) also stores raw character names,
            // so it needs the same rename applied to stay in sync.
            if let override = shootDays[d].callSheet.castOverride {
                shootDays[d].callSheet.castOverride = renamed(override)
            }
        }
        markDirty()
    }

    private func stripSceneNumber(_ title: String) -> String {
        let pattern = #"^\d+[A-Za-z]?\.\s*"#
        if let range = title.range(of: pattern, options: .regularExpression) {
            return String(title[range.upperBound...])
        }
        return title
    }

    /// Strips INT./EXT. prefix and scene number, returning just the location name.
    private func locationSortKey(_ title: String) -> String {
        let withoutNumber = stripSceneNumber(title)
        let pattern = #"^(INT\.|EXT\.)\s*"#
        if let range = withoutNumber.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            return String(withoutNumber[range.upperBound...])
        }
        return withoutNumber
    }

    /// Returns the INT/EXT prefix for sorting, or "ZZZ" to sort unknowns last.
    private func intExtSortKey(_ title: String) -> String {
        let withoutNumber = stripSceneNumber(title)
        if withoutNumber.uppercased().hasPrefix("INT.") { return "INT." }
        if withoutNumber.uppercased().hasPrefix("EXT.") { return "EXT." }
        return "ZZZ"
    }

    private var boneyardSortLabel: String {
        switch boneyardSort {
        case .defaultOrder: return "Default"
        case .sceneNumber:  return "Scene #"
        case .location:     return "Location"
        case .intExt:       return "INT/EXT"
        case .cast:         return "Cast"
        case .dayNight:     return "Day/Night"
        }
    }

    // MARK: - Boneyard scene navigation (Previous/Next in edit sheet)

    /// Position of the scene currently being edited within the *displayed* (sorted) Boneyard order.
    private var currentBoneyardPosition: Int? {
        guard let idx = editingUnscheduledSceneIndex else { return nil }
        return sortedScenes.firstIndex { $0.index == idx }
    }

    private func goToPreviousUnscheduledScene() {
        guard let pos = currentBoneyardPosition, pos > 0 else { return }
        let target = sortedScenes[pos - 1]
        editingUnscheduledSceneIndex = target.index
        editingUnscheduledScene      = target.scene
    }

    private func goToNextUnscheduledScene() {
        guard let pos = currentBoneyardPosition, pos < sortedScenes.count - 1 else { return }
        let target = sortedScenes[pos + 1]
        editingUnscheduledSceneIndex = target.index
        editingUnscheduledScene      = target.scene
    }

    /// Cached Boneyard ordering. This used to be a computed property, which meant every one
    /// of its many call sites (drag payload, selection range, position lookups, the list body
    /// itself) re-sorted the whole Boneyard — regex key extraction included — on every access,
    /// several times per render. That's what caused the lag when selecting strips. Now it's
    /// only recomputed when allScenes or boneyardSort actually change (see .onChange below).
    @State private var sortedScenes: [(index: Int, scene: Scene)] = []

    private func recomputeSortedScenes() {
        let indexed = allScenes.enumerated().map { (index: $0.offset, scene: $0.element) }
        switch boneyardSort {
        case .defaultOrder:
            sortedScenes = indexed
        case .sceneNumber:
            // Scenes with no number at all (blank) sort after every properly-numbered
            // scene, rather than before — an unnumbered scene isn't "scene zero".
            sortedScenes = indexed.sorted {
                let aBlank = $0.scene.sceneNumber.isEmpty
                let bBlank = $1.scene.sceneNumber.isEmpty
                if aBlank != bBlank { return !aBlank }
                return SceneNumberParser.sortsBefore($0.scene.sceneNumber, $1.scene.sceneNumber)
            }
        case .location:
            sortedScenes = indexed.sorted { locationSortKey($0.scene.title) < locationSortKey($1.scene.title) }
        case .intExt:
            sortedScenes = indexed.sorted {
                let a = intExtSortKey($0.scene.title)
                let b = intExtSortKey($1.scene.title)
                if a != b { return a < b }
                return locationSortKey($0.scene.title) < locationSortKey($1.scene.title)
            }
        case .cast:
            sortedScenes = indexed.sorted {
                let a = $0.scene.cast.sorted().first ?? "ZZZ"
                let b = $1.scene.cast.sorted().first ?? "ZZZ"
                return a < b
            }
        case .dayNight:
            sortedScenes = indexed.sorted {
                if $0.scene.dayNightType != $1.scene.dayNightType {
                    return $0.scene.dayNightType == .day
                }
                return locationSortKey($0.scene.title) < locationSortKey($1.scene.title)
            }
        }
    }

    // MARK: - Boneyard list

    // No ScrollView here — this used to have its own, but nesting it inside the
    // sidebar's single outer ScrollView (see sidebarView) meant two scroll areas
    // competing for the same scroll gesture. Now this is just a plain stack of rows,
    // and the sidebar's outer ScrollView carries the whole column, Boneyard included.
    private var boneyardList: some View {
        VStack(spacing: 0) {
                ForEach(sortedScenes, id: \.scene.id) { item in
                    HStack {
                        Circle().fill(item.scene.dayNightType.color).frame(width: 8, height: 8)
                        if !item.scene.sceneNumber.isEmpty {
                            Text(item.scene.sceneNumber)
                                .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        // A long scene title truncates with "…" instead of wrapping onto a
                        // second line, which used to push the D/N tag, duration, and delete
                        // button out of the row (or off it) when the sidebar was narrow.
                        Text(item.scene.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(item.scene.dayNightType == .day ? "D" : "N")
                            .font(.caption).foregroundColor(item.scene.dayNightType.color).fontWeight(.semibold)
                            .fixedSize()
                        Text("\(FractionParser.formatEighths(item.scene.duration)) / \(formattedTime(item.scene.estimatedTime))")
                            .lineLimit(1)
                            .fixedSize()
                        Button {
                            allScenes.remove(at: item.index)
                            markDirty()
                        } label: {
                            Image(systemName: "trash").foregroundColor(.red).help("Delete Scene")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 3).padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedSceneIDs.contains(item.scene.id) ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.001))
                    )
                    .onDrag { dragPayload(for: item.scene) }
                    .fastTooltip(item.scene.tooltipText)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            editingUnscheduledSceneIndex = item.index
                            editingUnscheduledScene      = item.scene
                            showingUnscheduledSceneEditSheet = true
                        }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 1).onEnded {
                            selectScene(item.scene.id)
                        }
                    )
                    .contextMenu {
                        Button("Edit Scene") {
                            editingUnscheduledSceneIndex = item.index
                            editingUnscheduledScene      = item.scene
                            showingUnscheduledSceneEditSheet = true
                        }
                        Button("Duplicate Scene") {
                            allScenes.append(Scene(
                                title:         item.scene.title + " (Copy)",
                                duration:      item.scene.duration,
                                estimatedTime: item.scene.estimatedTime,
                                dayNightType:  item.scene.dayNightType,
                                cast:          item.scene.cast,
                                summary:       item.scene.summary,
                                productionID:  item.scene.productionID,
                                sceneNumber:   item.scene.sceneNumber
                            ))
                            markDirty()
                        }
                        Divider()
                        Button("Delete Scene", role: .destructive) {
                            allScenes.remove(at: item.index)
                            markDirty()
                        }
                    }
                    Divider()
                }
        }
        // minHeight guarantees the Boneyard has some presence even when empty.
        .frame(minHeight: 60)
        .tooltipContainer()
    }

    // MARK: - Boneyard selection helpers

    /// Applies click / ⌘-click / ⇧-click semantics using the live modifier flags at tap time —
    /// SwiftUI's plain tap gesture has no modifier parameter on macOS, so we read them directly.
    private func selectScene(_ id: UUID) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedSceneIDs.contains(id) { selectedSceneIDs.remove(id) } else { selectedSceneIDs.insert(id) }
            lastSelectedSceneID = id
        } else if flags.contains(.shift), let anchor = lastSelectedSceneID,
                  let anchorIdx  = sortedScenes.firstIndex(where: { $0.scene.id == anchor }),
                  let targetIdx  = sortedScenes.firstIndex(where: { $0.scene.id == id }) {
            let range = anchorIdx < targetIdx ? anchorIdx...targetIdx : targetIdx...anchorIdx
            selectedSceneIDs.formUnion(range.map { sortedScenes[$0].scene.id })
        } else {
            selectedSceneIDs = [id]
            lastSelectedSceneID = id
        }
    }

    /// Builds the drag payload for a Boneyard row. If the dragged scene is part of a multi-scene
    /// selection, the whole selection (in current Boneyard sort order) rides along as a comma-
    /// separated list of scene IDs; otherwise it's treated as a fresh single-scene drag. The
    /// calendar's drop handling already accepts either a single ID or a comma-separated list.
    private func dragPayload(for scene: Scene) -> NSItemProvider {
        let ids: [UUID]
        if selectedSceneIDs.contains(scene.id), selectedSceneIDs.count > 1 {
            ids = sortedScenes.map(\.scene).filter { selectedSceneIDs.contains($0.id) }.map(\.id)
        } else {
            selectedSceneIDs   = [scene.id]
            lastSelectedSceneID = scene.id
            ids = [scene.id]
        }
        let payload = ids.map(\.uuidString).joined(separator: ",")
        return NSItemProvider(object: payload as NSString)
    }

    // MARK: - Detail / main area

    private var detailView: some View {
        VStack {
            toolbarRow
            CompactMonthCalendarView(
                shootDays:    $shootDays,
                assignScene:  assign,
                allScenes:    $allScenes,
                updateScene:  updateScene,
                removeScene:  removeScene,
                projectTitle: projectTitle,
                productionInfo: productionInfo,
                isSidebarCollapsed: isSidebarCollapsed,
                selectedSceneIDs: $selectedSceneIDs,
                lastSelectedSceneID: $lastSelectedSceneID,
                conflictDates: conflictDates,
                conflictSceneIDs: conflictSceneIDs,
                scrollToDate: $scrollToDate,
                onSceneChanged: { markDirty(); pruneSelection(); recomputeConflicts() },
                onCallSheetExport: { day in
                    showCallSheetPDFSavePanel(for: day)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        // Registered directly on this pane (not just once on the outer window in
        // ScriptDropModifier) for the same reason the sidebar needs its own copy: the
        // calendar underneath has its own onDrop delegates for reordering scenes, and a
        // dropDestination higher up the view tree doesn't reliably receive drags that land
        // on a pane which already has its own drop handling for a different payload type.
        .dropDestination(for: URL.self) { urls, _ in
            handleScriptDrop(urls)
        } isTargeted: { targeted in
            isScriptDropTargeted = targeted
        }
    }

    // MARK: - Toolbar row

    private var toolbarRow: some View {
        HStack {
            Text(projectTitle.isEmpty ? "Untitled Movie" : projectTitle)
                .font(.headline).fontWeight(.semibold)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 200)
                // Lowest priority in this row: if space runs out, the title is what
                // shrinks/truncates first — it already degrades gracefully with "…".
                .layoutPriority(0)

            Divider().frame(height: 20)

            // fixedSize() locks this group to its natural width instead of letting SwiftUI
            // compress it, and layoutPriority(1) makes it the last thing to give up space.
            // Together they guarantee the day/scene/time counts always render fully — the
            // title truncates before any of these three numbers would.
            HStack(spacing: 15) {
                statBadge(icon: "calendar", value: "\(scheduledDays.count)", label: "days",   color: .blue)
                statBadge(icon: "film",     value: "\(totalScenes)",          label: "scenes", color: .green)
                statBadge(icon: "clock",    value: totalEstTime,              label: nil,      color: .purple)
            }
            .fixedSize()
            .layoutPriority(1)

            Spacer()
        }
        .padding(.bottom)
    }

    private func statBadge(icon: String, value: String, label: String?, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).foregroundColor(color).font(.caption)
            Text(value)
                .font(.system(.body, design: .rounded)).fontWeight(.semibold).foregroundColor(color)
                .lineLimit(1)
            if let label = label {
                Text(label).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
        }
    }

    // MARK: - Unscheduled scene edit sheet

    @ViewBuilder
    private var unscheduledEditSheet: some View {
        if let idx = editingUnscheduledSceneIndex, idx < allScenes.count {
            SceneEditSheet(
                scene: $allScenes[idx],
                isPresented: $showingUnscheduledSceneEditSheet,
                onSave: { markDirty() },
                onDelete: {
                    if let i = editingUnscheduledSceneIndex { allScenes.remove(at: i) }
                    markDirty()
                    clearUnscheduledEditingState()
                },
                canGoPrevious: (currentBoneyardPosition ?? 0) > 0,
                canGoNext: currentBoneyardPosition.map { $0 < sortedScenes.count - 1 } ?? false,
                onPrevious: goToPreviousUnscheduledScene,
                onNext: goToNextUnscheduledScene,
                positionLabel: currentBoneyardPosition.map { "Scene \($0 + 1) of \(sortedScenes.count)" }
            )
        } else {
            VStack(spacing: 20) {
                Text("Error: Scene not found").font(.title2).foregroundColor(.red)
                Text("The scene may have been deleted.").font(.body).multilineTextAlignment(.center)
                Button("Close") {
                    showingUnscheduledSceneEditSheet = false
                    clearUnscheduledEditingState()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24).frame(width: 400)
        }
    }

    private func clearUnscheduledEditingState() {
        editingUnscheduledScene      = nil
        editingUnscheduledSceneIndex = nil
    }

    // MARK: - Scene management

    func assign(scene: Scene, to day: ShootDay) {
        if let idx = shootDays.firstIndex(where: { $0.id == day.id }) {
            shootDays[idx].scenes.append(scene)
            allScenes.removeAll { $0.id == scene.id }
            markDirty()
        }
    }

    func updateScene(_ updated: Scene, in dayId: UUID) {
        if let di = shootDays.firstIndex(where: { $0.id == dayId }),
           let si = shootDays[di].scenes.firstIndex(where: { $0.id == updated.id }) {
            shootDays[di].scenes[si] = updated
            markDirty()
        }
    }

    func removeScene(_ scene: Scene, from dayId: UUID) {
        if let di = shootDays.firstIndex(where: { $0.id == dayId }) {
            shootDays[di].scenes.removeAll { $0.id == scene.id }
            allScenes.append(scene)
            markDirty()
        }
    }

    /// Moves one or more scheduled scenes back into the Boneyard — used when a scene is
    /// dragged out of the calendar and dropped on the Boneyard. Same drag-payload format as
    /// everywhere else (comma-separated scene ids), so it also works if a future multi-select
    /// calendar drag is added. Unlike removeScene(_:from:), the caller doesn't already know
    /// which day each scene is on — the drop only carries scene ids — so this looks it up.
    func moveScenesToBoneyard(_ payload: String) {
        let ids = payload.components(separatedBy: ",").compactMap { UUID(uuidString: $0) }
        guard !ids.isEmpty else { return }

        var movedAny = false
        for id in ids {
            for dayIdx in shootDays.indices {
                if let sceneIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == id }) {
                    let scene = shootDays[dayIdx].scenes.remove(at: sceneIdx)
                    allScenes.append(scene)
                    movedAny = true
                    break
                }
            }
        }
        guard movedAny else { return }
        markDirty()
        pruneSelection()
        recomputeConflicts()
    }

    // MARK: - Calendar update (merge vs shift)

    private func updateShootDays(from newStart: Date, to newEnd: Date) {
        let cal            = Calendar.current
        let oldStart       = shootDays.first?.date ?? newStart
        let normOldStart   = cal.startOfDay(for: oldStart)
        let normNewStart   = cal.startOfDay(for: newStart)
        let normNewEnd     = cal.startOfDay(for: newEnd)
        let dayOffset      = cal.dateComponents([.day], from: normOldStart, to: normNewStart).day ?? 0

        let existingMap: [Date: ShootDay] = shootDays.reduce(into: [:]) {
            $0[cal.startOfDay(for: $1.date)] = $1
        }

        var updated: [ShootDay] = []
        var current = normNewStart
        while current <= normNewEnd {
            let day: ShootDay
            if isShiftModeEnabled {
                if let original = cal.date(byAdding: .day, value: -dayOffset, to: current),
                   let old = existingMap[original] {
                    day = ShootDay(date: current, scenes: old.scenes)
                } else {
                    day = ShootDay(date: current)
                }
            } else {
                day = existingMap[current] ?? ShootDay(date: current)
            }
            updated.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        shootDays = updated
        markDirty()
    }
}

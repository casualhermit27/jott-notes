import SwiftUI
import Combine

struct IOSRootView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("jott_hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @State private var selectedNote: Note?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @StateObject private var quickCapture = JottQuickCaptureCenter.shared
    @StateObject private var purchases = PurchaseManager.shared
    @State private var showRequestedNewNote = false
    @State private var showPaywall = false
    @State private var folderStack: [UUID] = []
    @State private var activeFilter: IOSLibraryFilter = .none
    @State private var showSettings = false
    private let syncTick = Timer.publish(every: 45, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            IOSLibraryView(
                selectedNote: $selectedNote,
                folderStack: $folderStack,
                activeFilter: $activeFilter,
                showSettings: $showSettings
            )
        } detail: {
            NavigationStack {
                if let note = selectedNote {
                    IOSDetailView(note: note, onDelete: { selectedNote = nil })
                        .id(note.id)
                } else {
                    IOSEmptyDetail()
                }
            }
        }
        .fullScreenCover(isPresented: $showPaywall) { IOSPaywallView() }
        .onReceive(NotificationCenter.default.publisher(for: .jottShowPaywall)) { _ in showPaywall = true }
        .onReceive(NotificationCenter.default.publisher(for: .jottOpenCapture)) { _ in quickCapture.requestCapture() }
        .onReceive(NotificationCenter.default.publisher(for: .jottOpenSearch)) { _ in
            NotificationCenter.default.post(name: .jottFocusSearch, object: nil)
        }
        .fullScreenCover(isPresented: $showRequestedNewNote) {
            IOSNewNoteComposerView(title: "New Note", folderId: nil, parentId: nil) { note in
                selectedNote = note
            }
        }
        .sheet(isPresented: $showSettings) { IOSSettingsView() }
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { if !$0 { hasSeenOnboarding = true } }
        )) {
            JottOnboardingV2 { hasSeenOnboarding = true }
            // swap to JottOnboardingV1 { hasSeenOnboarding = true } for the single-screen variant
        }
        .task { await NotificationManager.shared.requestPermission() }
        .task {
            try? await Task.sleep(for: .seconds(1))
            await purchases.refresh()
            // Don't block launch — locked state surfaces inline when user tries to act.
        }
        .onAppear { presentRequestedNewNoteIfNeeded() }
        .onReceive(quickCapture.$requestToken.dropFirst()) { _ in showRequestedNewNote = true }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { noteStore.refreshFromDisk(); presentRequestedNewNoteIfNeeded() }
        }
        .onReceive(syncTick) { _ in if scenePhase == .active { noteStore.refreshFromDisk() } }
        .onOpenURL { url in
            guard url.scheme == "jott" else { return }
            if url.host == "new" || url.path == "/new" { quickCapture.requestCapture() }
        }
    }

    private func presentRequestedNewNoteIfNeeded() {
        if quickCapture.consumePendingRequest() {
            showRequestedNewNote = true
        }
    }
}

private struct IOSEmptyDetail: View {
    @Environment(\.colorScheme) private var scheme
    private var ds: JottDS { JottDS(isDark: scheme == .dark) }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(ds.inkFaintest)
            Text("Select a note")
                .font(.jottBody(17, weight: .medium))
                .foregroundStyle(ds.inkFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ds.canvas.ignoresSafeArea())
    }
}

// Onboarding lives in IOSOnboarding.swift (JottOnboardingV1 / JottOnboardingV2)

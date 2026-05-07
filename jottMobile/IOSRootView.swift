import SwiftUI
import Combine

struct IOSRootView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedNote: Note?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @StateObject private var quickCapture = JottQuickCaptureCenter.shared
    @StateObject private var purchases = PurchaseManager.shared
    @State private var showRequestedNewNote = false
    @State private var showPaywall = false
    private let syncTick = Timer.publish(every: 45, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            IOSLibraryView(selectedNote: $selectedNote)
        } detail: {
            // Explicit NavigationStack in the detail column so that
            // navigationDestination(for: Note.self) works for subnote push.
            NavigationStack {
                if let note = selectedNote {
                    IOSDetailView(note: note, onDelete: { selectedNote = nil })
                        .id(note.id)
                } else {
                    IOSEmptyDetail()
                }
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            IOSPaywallView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .jottShowPaywall)) { _ in
            showPaywall = true
        }
        .fullScreenCover(isPresented: $showRequestedNewNote) {
            IOSNewNoteComposerView(
                title: "New Note",
                folderId: nil,
                parentId: nil
            ) { note in
                selectedNote = note
            }
        }
        .task {
            await NotificationManager.shared.requestPermission()
        }
        .onAppear {
            presentRequestedNewNoteIfNeeded()
        }
        .onReceive(quickCapture.$requestToken.dropFirst()) { _ in
            showRequestedNewNote = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                noteStore.refreshFromDisk()
                presentRequestedNewNoteIfNeeded()
            }
        }
        .onReceive(syncTick) { _ in
            if scenePhase == .active {
                noteStore.refreshFromDisk()
            }
        }
        .onOpenURL { url in
            guard url.scheme == "jott" else { return }
            if url.host == "new" || url.path == "/new" {
                quickCapture.requestCapture()
            }
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

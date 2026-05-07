import SwiftUI
import Combine

@MainActor
final class JottQuickCaptureCenter: ObservableObject {
    static let shared = JottQuickCaptureCenter()

    @Published private(set) var requestToken = UUID()

    private let appGroupID = "group.com.casualhermit.jott"
    private let pendingKey = "jott_mobile_pendingQuickCapture"
    private let consumedKey = "jott_mobile_consumedQuickCapture"
    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private init() {}

    func requestCapture() {
        let id = UUID().uuidString
        defaults.set(id, forKey: pendingKey)
        requestToken = UUID()
    }

    func consumePendingRequest() -> Bool {
        guard let pending = defaults.string(forKey: pendingKey),
              pending != defaults.string(forKey: consumedKey) else {
            return false
        }
        defaults.set(pending, forKey: consumedKey)
        return true
    }
}

struct IOSInstantCaptureSheet: View {
    let title: String
    let folderId: UUID?
    let parentId: UUID?
    let onCreate: (Note) -> Void

    @ObservedObject private var noteStore = NoteStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var blocks: [Block] = []

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }
    private var capturedPlainText: String {
        blocks
            .filter { $0.type != .table }
            .map(\.plainText)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ds.canvas.ignoresSafeArea()

                VStack(spacing: 12) {
                    captureSurface
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ds.inkMute)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? ds.accent : ds.inkFaintest)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.height(360), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var captureSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                    Image("JottMenuBar")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Jott")
                        .font(.jottBody(15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(jottRelativeDate(Date()))
                        .font(.jottMono(10))
                        .foregroundStyle(Color.white.opacity(0.44))
                        .tracking(0.4)
                }

                Spacer()

                if !capturedPlainText.isEmpty {
                    Text("\(capturedPlainText.split(whereSeparator: \.isWhitespace).count) words")
                        .font(.jottMono(10))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .tracking(0.4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            IOSBlockNoteEditor(
                blocks: $blocks,
                isDark: true,
                autoFocus: true
            )
            .frame(minHeight: 210)
            .background(Color.black)
        }
        .background(Color.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.28 : 0.12), radius: 24, x: 0, y: 12)
    }

    private func save() {
        guard canSave else { return }
        let clean = blocks.filter { $0.type != .table || !$0.tableHeaders.isEmpty }
        let note = Note(id: UUID(), blocks: clean, parentId: parentId, folderId: folderId)
        noteStore.upsertNote(note)
        onCreate(note)
        dismiss()
    }

    private var canSave: Bool {
        blocks.contains { b in
            b.type == .table ? !b.tableHeaders.isEmpty
                             : !b.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct IOSNewNoteComposerView: View {
    let title: String
    let folderId: UUID?
    let parentId: UUID?
    let onCreate: (Note) -> Void

    @ObservedObject private var noteStore = NoteStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var blocks: [Block] = []

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }

    var body: some View {
        NavigationStack {
            ZStack {
                ds.canvas.ignoresSafeArea()

                IOSBlockNoteEditor(
                    blocks: $blocks,
                    isDark: scheme == .dark,
                    autoFocus: true
                )
                .background(ds.canvas)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ds.inkMute)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? ds.accent : ds.inkFaintest)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let clean = blocks.filter { $0.type != .table || !$0.tableHeaders.isEmpty }
        guard !clean.isEmpty else { return }
        let note = Note(id: UUID(), blocks: clean, parentId: parentId, folderId: folderId)
        noteStore.upsertNote(note)
        onCreate(note)
        dismiss()
    }

    private var canSave: Bool {
        blocks.contains { b in
            b.type == .table ? !b.tableHeaders.isEmpty
                             : !b.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

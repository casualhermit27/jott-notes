import SwiftUI

struct IOSSettingsView: View {
    @ObservedObject private var noteStore = NoteStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("jott_aiUserContext") private var aiUserContext: String = ""
    @State private var editingAIContext = false
    @State private var aiContextDraft = ""
    @State private var isSyncing = false
    @State private var syncMessage: String? = nil

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }

    private var syncStatusLine: String {
        if isSyncing { return "Fetching latest notes..." }
        if let msg = syncMessage { return msg }
        let count = noteStore.allNotes().count
        if count == 0 { return "No notes yet" }
        return "\(count) note\(count == 1 ? "" : "s") synced"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ds.canvas.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {

                        // iCloud Sync
                        settingsSection(title: "SYNC") {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(ds.accentSoft)
                                        .frame(width: 36, height: 36)
                                    if isSyncing {
                                        ProgressView()
                                            .tint(ds.accent)
                                            .scaleEffect(0.75)
                                    } else {
                                        Image(systemName: "checkmark.icloud.fill")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(ds.accent)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(isSyncing ? "Syncing with iCloud..." : "iCloud Sync")
                                        .font(.jottBody(15, weight: .medium))
                                        .foregroundStyle(ds.ink)
                                    Text(syncStatusLine)
                                        .font(.jottCaption(12))
                                        .foregroundStyle(ds.inkFaint)
                                }

                                Spacer()

                                Button {
                                    Task { await forceSyncNow() }
                                } label: {
                                    Text("Sync")
                                        .font(.jottCaption(12, weight: .medium))
                                        .foregroundStyle(isSyncing ? ds.inkFaintest : ds.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(ds.accentSoft, in: Capsule())
                                        .overlay(Capsule().strokeBorder(ds.accent.opacity(isSyncing ? 0.0 : 0.18), lineWidth: 0.8))
                                }
                                .buttonStyle(.plain)
                                .disabled(isSyncing)
                            }
                        }

                        // AI Context
                        settingsSection(title: "AI CONTEXT") {
                            if editingAIContext {
                                VStack(alignment: .leading, spacing: 10) {
                                    TextEditor(text: $aiContextDraft)
                                        .font(.jottBody(14))
                                        .foregroundStyle(ds.ink)
                                        .scrollContentBackground(.hidden)
                                        .background(ds.canvas)
                                        .frame(minHeight: 80)
                                    HStack {
                                        Button("Cancel") {
                                            aiContextDraft = aiUserContext
                                            editingAIContext = false
                                        }
                                        .font(.jottBody(14))
                                        .foregroundStyle(ds.inkMute)
                                        Spacer()
                                        Button("Save") {
                                            aiUserContext = aiContextDraft
                                            NoteAIService.saveUserContext(aiContextDraft)
                                            editingAIContext = false
                                        }
                                        .font(.jottBody(14, weight: .semibold))
                                        .foregroundStyle(ds.accent)
                                    }
                                }
                            } else {
                                HStack(alignment: .top) {
                                    Text(aiUserContext.isEmpty ? "Not set" : aiUserContext)
                                        .font(.jottBody(14))
                                        .foregroundStyle(aiUserContext.isEmpty ? ds.inkFaint : ds.ink)
                                        .lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button("Edit") {
                                        aiContextDraft = aiUserContext
                                        editingAIContext = true
                                    }
                                    .font(.jottBody(14))
                                    .foregroundStyle(ds.accent)
                                }
                            }
                            Text("Included in every AI prompt so suggestions feel personal.")
                                .font(.jottCaption(12))
                                .foregroundStyle(ds.inkFaintest)
                                .padding(.top, 2)
                        }

                        // About
                        settingsSection(title: "ABOUT") {
                            HStack {
                                Text("Version")
                                    .font(.jottBody(15))
                                    .foregroundStyle(ds.ink)
                                Spacer()
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                                    .font(.jottMono(13))
                                    .foregroundStyle(ds.inkFaintest)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(ds.accent)
                }
            }
        }
    }

    // MARK: - Sync

    private func forceSyncNow() async {
        isSyncing = true
        syncMessage = nil
        noteStore.refreshFromDisk()
        try? await Task.sleep(for: .seconds(4))
        isSyncing = false
        let count = noteStore.allNotes().count
        syncMessage = count > 0
            ? "Last synced just now"
            : "Nothing in iCloud yet — open the Mac app once to push your notes"
    }

    // MARK: - Section card

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.jottMono(10, weight: .medium))
                .foregroundStyle(ds.inkFaintest)
                .tracking(0.6)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ds.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ds.hairline, lineWidth: 1))
        }
    }

}

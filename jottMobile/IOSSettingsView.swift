import SwiftUI
import RevenueCat

struct IOSSettingsView: View {
    @ObservedObject private var noteStore = NoteStore.shared
    @StateObject private var purchases = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("jott_aiUserContext") private var aiUserContext: String = ""
    @State private var editingAIContext = false
    @State private var aiContextDraft = ""
    @State private var isSyncing = false
    @State private var syncMessage: String? = nil
    @State private var syncSucceeded = false
    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage: String? = nil

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

                        // Upgrade
                        if !purchases.isProActive {
                            Button { showPaywall = true } label: {
                                HStack(spacing: 14) {
                                    Image("JottControlIcon")
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Upgrade to Jott Pro")
                                            .font(.jottBody(16, weight: .bold))
                                        Text("One-time \(purchases.offerings?.current?.lifetime?.localizedPriceString ?? "$12.99") — lifetime access")
                                            .font(.jottCaption(12))
                                            .opacity(0.82)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .opacity(0.7)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.52, green: 0.38, blue: 0.98),
                                            Color(red: 0.30, green: 0.18, blue: 0.82)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color(red: 0.38, green: 0.22, blue: 0.85).opacity(0.4), radius: 12, y: 5)
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task { await restorePurchases() }
                            } label: {
                                HStack {
                                    if isRestoring {
                                        ProgressView().tint(ds.inkFaint)
                                    } else {
                                        Text(restoreMessage ?? "Restore Purchase")
                                            .font(.jottCaption(13))
                                            .foregroundStyle(restoreMessage?.hasPrefix("No") == true ? .red : ds.inkFaint)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRestoring)
                        } else {
                            settingsSection(title: "SUBSCRIPTION") {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(ds.accentSoft)
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(ds.accent)
                                    }
                                    Text("Jott Pro — Lifetime")
                                        .font(.jottBody(15, weight: .medium))
                                        .foregroundStyle(ds.ink)
                                }
                            }
                        }

                        // iCloud Sync
                        settingsSection(title: "SYNC") {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(syncSucceeded ? Color.green.opacity(0.15) : ds.accentSoft)
                                        .frame(width: 36, height: 36)
                                        .animation(.easeInOut(duration: 0.4), value: syncSucceeded)

                                    if isSyncing {
                                        ProgressView()
                                            .tint(ds.accent)
                                            .scaleEffect(0.75)
                                            .transition(.opacity.combined(with: .scale(scale: 0.7)))
                                    } else if syncSucceeded {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.green)
                                            .transition(.asymmetric(
                                                insertion: .scale(scale: 0.4).combined(with: .opacity),
                                                removal: .scale(scale: 1.4).combined(with: .opacity)
                                            ))
                                    } else {
                                        Image(systemName: "checkmark.icloud.fill")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(ds.accent)
                                            .transition(.opacity)
                                    }
                                }
                                .animation(.spring(response: 0.45, dampingFraction: 0.62), value: isSyncing)
                                .animation(.spring(response: 0.45, dampingFraction: 0.62), value: syncSucceeded)

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
            .fullScreenCover(isPresented: $showPaywall) {
                IOSPaywallView()
            }
        }
    }

    private func restorePurchases() async {
        isRestoring = true
        restoreMessage = nil
        defer { isRestoring = false }
        do {
            try await purchases.restore()
            if purchases.isProActive {
                dismiss()
            } else {
                restoreMessage = "No previous purchase found."
            }
        } catch {
            restoreMessage = "Restore failed. Try again."
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

        withAnimation { syncSucceeded = true }
        try? await Task.sleep(for: .seconds(2.2))
        withAnimation(.easeInOut(duration: 0.5)) { syncSucceeded = false }
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

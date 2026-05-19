import SwiftUI
import RevenueCat
import MessageUI

struct IOSSettingsView: View {
    @ObservedObject private var noteStore = NoteStore.shared
    @ObservedObject private var purchases = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var isSyncing = false
    @State private var syncMessage: String? = nil
    @State private var syncSucceeded = false
    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage: String? = nil
    @State private var showFeedback = false
    @State private var showDebug = false

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

                        // Upgrade / Trial
                        if !purchases.isProActive {
                            Button { showPaywall = true } label: {
                                HStack(spacing: 14) {
                                    Image("JottAppIcon")
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        if TrialManager.shared.isActive {
                                            Text("\(TrialManager.shared.daysRemaining) days left in your free trial")
                                                .font(.jottBody(16, weight: .bold))
                                            Text("Upgrade to keep access forever")
                                                .font(.jottCaption(12))
                                                .opacity(0.82)
                                        } else {
                                            Text("Upgrade to Jott Pro")
                                                .font(.jottBody(16, weight: .bold))
                                            Text("One-time \(purchases.offerings?.current?.lifetime?.localizedPriceString ?? "$12.99") — lifetime access")
                                                .font(.jottCaption(12))
                                                .opacity(0.82)
                                        }
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
                                        ProgressView().tint(ds.accent).scaleEffect(0.75)
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

                        // Support
                        VStack(alignment: .leading, spacing: 0) {
                            Text("SUPPORT")
                                .font(.jottMono(10, weight: .medium))
                                .foregroundStyle(ds.inkFaintest)
                                .tracking(0.6)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)

                            HStack(spacing: 12) {
                                airButton(
                                    icon: "exclamationmark.bubble.fill",
                                    label: "Feedback",
                                    subtitle: "Report a bug",
                                    color: Color(red: 0.42, green: 0.28, blue: 0.88)
                                ) { showFeedback = true }

                                airButton(
                                    icon: "ladybug.fill",
                                    label: "Debug",
                                    subtitle: "RC ID & status",
                                    color: Color(red: 0.20, green: 0.60, blue: 0.40)
                                ) { showDebug = true }
                            }
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
            .fullScreenCover(isPresented: $showPaywall) { IOSPaywallView() }
            .sheet(isPresented: $showFeedback) { IOSFeedbackSheet() }
            .sheet(isPresented: $showDebug) { IOSDebugSheet() }
        }
    }

    // MARK: - Air button

    @ViewBuilder
    private func airButton(
        icon: String,
        label: String,
        subtitle: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.jottBody(15, weight: .semibold))
                        .foregroundStyle(ds.ink)
                    Text(subtitle)
                        .font(.jottCaption(12))
                        .foregroundStyle(ds.inkFaint)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ds.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ds.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sync

    private func restorePurchases() async {
        isRestoring = true
        restoreMessage = nil
        defer { isRestoring = false }
        do {
            try await purchases.restore()
            if purchases.isProActive { dismiss() }
            else { restoreMessage = "No previous purchase found." }
        } catch {
            restoreMessage = "Restore failed. Try again."
        }
    }

    private func forceSyncNow() async {
        isSyncing = true
        syncMessage = nil
        noteStore.refreshFromDisk()
        try? await Task.sleep(for: .seconds(4))
        isSyncing = false
        let count = noteStore.allNotes().count
        syncMessage = count > 0 ? "Last synced just now" : "Nothing in iCloud yet — open the Mac app once to push your notes"
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
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ds.surface))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ds.hairline, lineWidth: 1))
        }
    }
}

// MARK: - Feedback sheet

private struct IOSFeedbackSheet: View {
    @ObservedObject private var purchases = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var name = ""
    @State private var body_ = ""
    @State private var sending = false
    @State private var sent = false
    @State private var showMailComposer = false
    @State private var showMailUnavailable = false

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }
    private var canSend: Bool { !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var rcID: String { Purchases.shared.appUserID }

    var body: some View {
        NavigationStack {
            ZStack {
                ds.canvas.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Your name (optional)", text: $name)
                            .font(.jottBody(15))
                            .foregroundStyle(ds.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(ds.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(ds.hairline, lineWidth: 1))
                            .disabled(sent)

                        ZStack(alignment: .topLeading) {
                            if body_.isEmpty {
                                Text("What's the bug or feedback?")
                                    .font(.jottBody(15))
                                    .foregroundStyle(ds.inkFaintest)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 13)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $body_)
                                .font(.jottBody(15))
                                .foregroundStyle(ds.ink)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(minHeight: 120)
                                .disabled(sent)
                        }
                        .background(ds.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(ds.hairline, lineWidth: 1))

                        Button {
                            if MFMailComposeViewController.canSendMail() {
                                sending = true
                                showMailComposer = true
                            } else {
                                showMailUnavailable = true
                            }
                        } label: {
                            ZStack {
                                if sent {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("Sent!")
                                            .font(.jottBody(15, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                                } else if sending {
                                    ProgressView().tint(.white).scaleEffect(0.85)
                                        .transition(.opacity)
                                } else {
                                    HStack(spacing: 8) {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Send Feedback")
                                            .font(.jottBody(15, weight: .semibold))
                                    }
                                    .foregroundStyle(canSend ? .white : ds.inkFaintest)
                                    .transition(.opacity)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                sent ? Color.green : (canSend ? Color(red: 0.42, green: 0.28, blue: 0.88) : ds.surfaceAlt),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: sent)
                            .animation(.easeInOut(duration: 0.15), value: sending)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend || sending || sent)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(red: 0.42, green: 0.28, blue: 0.88))
                }
            }
            .sheet(isPresented: $showMailComposer) {
                MailComposerView(
                    subject: "Jott Feedback\(name.isEmpty ? "" : " from \(name)")",
                    body: body_ + "\n\n---\nRC ID: \(rcID)\nTrial: \(TrialManager.shared.isActive)\nPro: \(purchases.isProActive)",
                    recipient: "harshachaganti12@gmail.com"
                ) { didSend in
                    if didSend {
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                                sending = false; sent = true
                            }
                            Haptics.medium()
                        }
                    } else {
                        sending = false
                    }
                }
            }
            .alert("Mail Unavailable", isPresented: $showMailUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("No mail account is configured. Email harshachaganti12@gmail.com directly.")
            }
        }
    }
}

// MARK: - Debug sheet

private struct IOSDebugSheet: View {
    @ObservedObject private var purchases = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var copiedID = false

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }
    private var rcID: String { Purchases.shared.appUserID }

    var body: some View {
        NavigationStack {
            ZStack {
                ds.canvas.ignoresSafeArea()
                VStack(spacing: 12) {
                    debugSection(title: "REVENUECAT") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Customer ID")
                                .font(.jottMono(10, weight: .medium))
                                .foregroundStyle(ds.inkFaintest)
                                .tracking(0.4)
                            HStack(spacing: 10) {
                                Text(rcID)
                                    .font(.jottMono(12))
                                    .foregroundStyle(ds.inkFaint)
                                    .lineLimit(2)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = rcID
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { copiedID = true }
                                    Task {
                                        try? await Task.sleep(for: .seconds(1.8))
                                        withAnimation { copiedID = false }
                                    }
                                } label: {
                                    Image(systemName: copiedID ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(copiedID ? .green : ds.accent)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: copiedID)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    debugSection(title: "ACCESS") {
                        VStack(spacing: 10) {
                            debugRow("Trial active", value: TrialManager.shared.isActive
                                ? "Yes · \(TrialManager.shared.daysRemaining)d left" : "No",
                                     accent: TrialManager.shared.isActive, ds: ds)
                            Divider().background(ds.hairline)
                            debugRow("Pro active", value: purchases.isProActive ? "Yes" : "No",
                                     accent: purchases.isProActive, ds: ds)
                        }
                    }

                }
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Debug Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(red: 0.42, green: 0.28, blue: 0.88))
                }
            }
        }
    }

    @ViewBuilder
    private func debugSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.jottMono(10, weight: .medium))
                .foregroundStyle(ds.inkFaintest)
                .tracking(0.6)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ds.surface))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ds.hairline, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func debugRow(_ label: String, value: String, accent: Bool, ds: JottDS) -> some View {
        HStack {
            Text(label).font(.jottBody(14)).foregroundStyle(ds.ink)
            Spacer()
            Text(value)
                .font(.jottMono(13))
                .foregroundStyle(accent ? Color(red: 0.42, green: 0.28, blue: 0.88) : ds.inkFaintest)
        }
    }
}

// MARK: - Mail composer

private struct MailComposerView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let recipient: String
    let onDismiss: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDismiss: (Bool) -> Void
        init(onDismiss: @escaping (Bool) -> Void) { self.onDismiss = onDismiss }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
            onDismiss(result == .sent)
        }
    }
}

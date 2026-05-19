import SwiftUI
import AppKit
import RevenueCat

struct JottSettingsView: View {
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var purchases = PurchaseManager.shared
    @AppStorage("jott_autoPasteClipboard") private var autoPasteClipboard: Bool = false
    @AppStorage("jott_showHelpButton") private var showHelpButton: Bool = true
    @AppStorage("jott_hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @AppStorage("jott_hasSeenWelcome") private var hasSeenWelcome: Bool = false
    @State private var showPaywall = false
    @State private var showFeedback = false
    @State private var showDebug = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "gear")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Jott Settings")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: - Upgrade
                    if !purchases.isProActive {
                        Button { showPaywall = true } label: {
                            HStack(spacing: 12) {
                                Image("JottAppIcon")
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    if TrialManager.shared.isActive {
                                        Text("\(TrialManager.shared.daysRemaining) days left in your free trial")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                        Text("Upgrade to keep access forever")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .opacity(0.82)
                                    } else {
                                        Text("Upgrade to Jott Pro")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                        Text("One-time \(purchases.offerings?.current?.lifetime?.localizedPriceString ?? "$12.99") — lifetime access")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .opacity(0.82)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .opacity(0.7)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
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
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: Color(red: 0.38, green: 0.22, blue: 0.85).opacity(0.4), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                        sectionDivider
                    }

                    // MARK: - Clipboard
                    sectionHeader("CLIPBOARD", icon: "doc.on.clipboard")

                    Toggle(isOn: $autoPasteClipboard) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-paste on open")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("When enabled, copied content is automatically pasted into Jott when you open the bar.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    Text("Jott monitors the clipboard in the background to detect copied content when the bar opens.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    sectionDivider

                    // MARK: - Jott Bar
                    sectionHeader("JOTT BAR", icon: "capsule")

                    Toggle(isOn: $showHelpButton) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show ? shortcut button")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("Displays the ? help button in the Jott bar toolbar.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    Button("Replay Onboarding") {
                        hasSeenOnboarding = false
                        hasSeenWelcome = false
                    }
                    .controlSize(.small)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    sectionDivider

                    // MARK: - Notes Folder
                    sectionHeader("NOTES FOLDER", icon: "folder")

                    let hasWindowController = (NSApp.delegate as? AppDelegate)?.windowController != nil
                    Button("Choose Folder...") {
                        if let wc = (NSApp.delegate as? AppDelegate)?.windowController {
                            wc.viewModel.selectNotesFolder()
                        } else {
                            let alert = NSAlert()
                            alert.messageText = "Unable to open folder picker"
                            alert.informativeText = "Please try again in a moment."
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                    }
                    .disabled(!hasWindowController)
                    .controlSize(.small)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    sectionDivider

                    // MARK: - Support
                    sectionHeader("SUPPORT", icon: "bubble.left.and.bubble.right")

                    settingsRow(icon: "exclamationmark.bubble", label: "Send Feedback") {
                        showFeedback = true
                    }
                    .popover(isPresented: $showFeedback, arrowEdge: .trailing) {
                        MacFeedbackPopover()
                    }
                    .padding(.horizontal, 20)

                    Divider().padding(.horizontal, 20)

                    settingsRow(icon: "ladybug", label: "Debug Info") {
                        showDebug = true
                    }
                    .popover(isPresented: $showDebug, arrowEdge: .trailing) {
                        MacDebugPopover()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 420)
        .jottAppTypography()
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func settingsRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var sectionDivider: some View {
        Divider().padding(.horizontal, 20)
    }
}

// MARK: - Feedback popover (macOS)

private struct MacFeedbackPopover: View {
    @ObservedObject private var purchases = PurchaseManager.shared
    @State private var name = ""
    @State private var body_ = ""
    @State private var sending = false
    @State private var sent = false

    private var rcID: String { Purchases.shared.appUserID }
    private var canSend: Bool { !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send Feedback")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            TextField("Your name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .disabled(sent)

            ZStack(alignment: .topLeading) {
                if body_.isEmpty {
                    Text("What's the bug or feedback?")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $body_)
                    .font(.system(size: 12))
                    .frame(width: 280, height: 100)
                    .disabled(sent)
            }
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))

            Button {
                sendFeedback()
            } label: {
                ZStack {
                    if sent {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Sent!")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    } else if sending {
                        ProgressView().scaleEffect(0.7).transition(.opacity)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Send")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(canSend ? .white : Color.secondary)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    sent ? Color.green : (canSend ? Color(red: 0.42, green: 0.28, blue: 0.88) : Color.secondary.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: sent)
            }
            .buttonStyle(.plain)
            .disabled(!canSend || sending || sent)
        }
        .padding(16)
        .frame(width: 312)
    }

    private func sendFeedback() {
        guard canSend else { return }
        sending = true
        let subject = "Jott Feedback\(name.isEmpty ? "" : " from \(name)")"
        let body = body_ + "\n\n---\nRC ID: \(rcID)\nTrial: \(TrialManager.shared.isActive)\nPro: \(purchases.isProActive)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody    = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:harshachaganti12@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                sending = false; sent = true
            }
        }
    }
}

// MARK: - Debug popover (macOS)

private struct MacDebugPopover: View {
    @ObservedObject private var purchases = PurchaseManager.shared
    @State private var copiedID = false
    private var rcID: String { Purchases.shared.appUserID }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug Info")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text("REVENUECAT ID")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                HStack(spacing: 8) {
                    Text(rcID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(rcID, forType: .string)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { copiedID = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.8))
                            withAnimation { copiedID = false }
                        }
                    } label: {
                        Image(systemName: copiedID ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(copiedID ? .green : Color.secondary)
                            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: copiedID)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                Text("Trial active")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(TrialManager.shared.isActive ? "Yes · \(TrialManager.shared.daysRemaining)d left" : "No")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(TrialManager.shared.isActive ? Color(red: 0.42, green: 0.28, blue: 0.88) : .secondary)
            }

            HStack {
                Text("Pro active")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(purchases.isProActive ? "Yes" : "No")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(purchases.isProActive ? .green : .secondary)
            }

        }
        .padding(16)
        .frame(width: 280)
    }
}

#Preview {
    JottSettingsView()
}

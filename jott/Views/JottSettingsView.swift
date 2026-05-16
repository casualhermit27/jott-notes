import SwiftUI
import AppKit
import RevenueCat

struct JottSettingsView: View {
    @ObservedObject private var updates = UpdateManager.shared
    @StateObject private var purchases = PurchaseManager.shared
    @AppStorage("jott_autoPasteClipboard") private var autoPasteClipboard: Bool = false
    @AppStorage("jott_showHelpButton") private var showHelpButton: Bool = true
    @State private var showPaywall = false

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
                    .padding(.bottom, 16)

                    sectionDivider

                    // MARK: - Updates
                    sectionHeader("UPDATES", icon: "arrow.clockwise")

                    VStack(alignment: .leading, spacing: 8) {
                        Text(updates.updateChannel == "app_store" ? "Channel: App Store" : "Channel: Direct distribution (Sparkle)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Button("Check for Updates") {
                            updates.checkForUpdates()
                        }
                        .controlSize(.small)
                        .disabled(!updates.sparkleEnabled)
                    }
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
                }
            }
        }
        .frame(width: 420)
        .jottAppTypography()
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
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

#Preview {
    JottSettingsView()
}

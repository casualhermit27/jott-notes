import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct JottSettingsView: View {
    @ObservedObject private var updates = UpdateManager.shared
    @StateObject private var purchases = PurchaseManager.shared
    @AppStorage("jott_overlayPosition") private var overlayPosition: String = "center"
    @AppStorage("jott_aiUserContext") private var aiUserContext: String = ""
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
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Upgrade to Jott Pro")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text("$12.99")
                                    .font(.system(size: 12, weight: .medium))
                                    .opacity(0.8)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.48, green: 0.36, blue: 0.92), Color(red: 0.32, green: 0.22, blue: 0.78)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: Color(red: 0.38, green: 0.26, blue: 0.82).opacity(0.35), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                        sectionDivider
                    }

                    // MARK: - Position
                    sectionHeader("POSITION", icon: "rectangle.on.rectangle")
                    positionPicker
                    sectionDivider

                    // MARK: - Updates
                    sectionHeader("UPDATES", icon: "arrow.clockwise")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Updates")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
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

                    // MARK: - AI Context
                    sectionHeader("AI CONTEXT", icon: "sparkles")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Paste a short bio, topics you write about, or any personal info. Jott uses this to make inline AI suggestions more relevant to you.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $aiUserContext)
                                .font(.system(size: 12.5))
                                .scrollContentBackground(.hidden)
                                .frame(height: 72)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor).opacity(0.7))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1))
                                )

                            if aiUserContext.isEmpty {
                                Text("e.g. Software engineer, into climbing and cooking…")
                                    .font(.system(size: 12.5))
                                    .foregroundColor(.secondary.opacity(0.45))
                                    .padding(.top, 9)
                                    .padding(.leading, 9)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding(.horizontal, 20)

                        HStack {
                            Spacer()
                            Button("Import Text File…") {
                                importAIContextFromFile()
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 14)

                    sectionDivider

                    // MARK: - Notes Folder
                    sectionHeader("NOTES FOLDER", icon: "folder")

                    Button("Choose Folder...") {
                        if let wc = (NSApp.delegate as? AppDelegate)?.windowController {
                            wc.viewModel.selectNotesFolder()
                        }
                    }
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

    // MARK: - Sub-views

    private var positionPicker: some View {
        HStack(spacing: 8) {
            positionBtn("center",   icon: "squareshape.split.3x3",           label: "Center")
            positionBtn("topLeft",  icon: "rectangle.lefthalf.inset.filled",  label: "Top Left")
            positionBtn("topRight", icon: "rectangle.righthalf.inset.filled", label: "Top Right")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func positionBtn(_ value: String, icon: String, label: String) -> some View {
        Button { overlayPosition = value } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(overlayPosition == value ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(overlayPosition == value ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(overlayPosition == value ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1))
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

    private func importAIContextFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .plainText,
            .utf8PlainText,
            .text,
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown")
        ].compactMap { $0 }

        guard panel.runModal() == .OK,
              let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        aiUserContext = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    JottSettingsView()
}

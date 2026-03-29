//
//  jottApp.swift
//  jott
//
//  Created by Harsha on 22/03/26.
//

import SwiftUI
import AppKit
import Combine

@main
struct jottApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var menuBarStore = MenuBarStore()

    var body: some Scene {
        MenuBarExtra("jott", image: "JottMenuBar") {
            MenuBarContentView(appDelegate: appDelegate, menuBarStore: menuBarStore)
        }
        .menuBarExtraStyle(.window)

        Window("Jott Settings", id: "jott-settings") {
            JottSettingsView()
                .frame(minWidth: 380, minHeight: 280)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 320)
    }
}

// MARK: - Menu bar content

struct MenuBarContentView: View {
    let appDelegate: AppDelegate
    @ObservedObject var menuBarStore: MenuBarStore
    @Environment(\.openWindow) private var openWindow

    private let menuWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Jott")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { appDelegate.windowController?.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .medium))
                        Text("⌥ Space")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if !menuBarStore.recentNotes.isEmpty {
                Divider()

                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                ForEach(menuBarStore.recentNotes) { note in
                    Button(action: { appDelegate.windowController?.openNote(note) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "note.text")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            Text(note.text.components(separatedBy: "\n").first ?? note.text)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundColor(.primary)
                                .frame(width: menuWidth - 110, alignment: .leading)
                            Spacer(minLength: 0)
                            Text(shortDate(note.modifiedAt))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: menuWidth - 28)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                }

                Button(action: { appDelegate.windowController?.openAllNotes() }) {
                    Text("All Notes (\(menuBarStore.totalCount))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Button(action: {
                appDelegate.windowController?.toggleDarkMode()
                menuBarStore.refresh()
            }) {
                HStack {
                    Image(systemName: menuBarStore.isDarkMode ? "sun.max" : "moon")
                    Text(menuBarStore.isDarkMode ? "Light Mode" : "Dark Mode")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: { appDelegate.windowController?.viewModel.selectNotesFolder() }) {
                HStack {
                    Image(systemName: "folder")
                    Text("Choose Notes Folder...")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Button(action: { openWindow(id: "jott-settings") }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings...")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: { NSApp.terminate(nil) }) {
                Text("Quit")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: menuWidth)
        .onAppear {
            menuBarStore.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm a"
            return fmt.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}

// MARK: - MenuBarStore

@MainActor
final class MenuBarStore: ObservableObject {
    @Published var recentNotes: [Note] = []
    @Published var totalCount: Int = 0
    @Published var isDarkMode: Bool = UserDefaults.standard.bool(forKey: "jott_darkMode")

    func refresh() {
        let all = NoteStore.shared.allNotes()
        recentNotes = Array(all.prefix(3))
        totalCount = all.count
        isDarkMode = UserDefaults.standard.bool(forKey: "jott_darkMode")
    }
}

// MARK: - Bundle ext

extension Bundle {
    var appVersion: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: OverlayWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = OverlayWindowController()
        windowController?.preload()

        // Start clipboard monitor early
        _ = ClipboardMonitor.shared

        // Single shortcut: Option+Space
        HotkeyManager.shared.register { [weak self] in
            self?.windowController?.toggle()
        }

        Task {
            await NotificationManager.shared.requestPermission()
            await CalendarManager.shared.requestAccess()
            await CalendarManager.shared.requestRemindersAccess()
        }
    }
}

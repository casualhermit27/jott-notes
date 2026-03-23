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
    }
}

// MARK: - Menu bar content

struct MenuBarContentView: View {
    let appDelegate: AppDelegate
    @ObservedObject var menuBarStore: MenuBarStore

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("Jott")
                    .font(.headline)
                if let version = Bundle.main.appVersion {
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)

            // Recent notes
            if !menuBarStore.recentNotes.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    Text("RECENT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    ForEach(menuBarStore.recentNotes) { note in
                        Button(action: {
                            appDelegate.windowController?.openNote(note)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 16)
                                Text(note.text.components(separatedBy: "\n").first ?? note.text)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(shortDate(note.modifiedAt))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
            }

            Divider()

            Button(action: { appDelegate.windowController?.toggleDarkMode() }) {
                HStack {
                    Image(systemName: appDelegate.windowController?.isDarkMode ?? false ? "sun.max" : "moon")
                    Text(appDelegate.windowController?.isDarkMode ?? false ? "Light Mode" : "Dark Mode")
                }
            }
            .buttonStyle(.plain)
            .padding()

            Divider()

            Button(action: { appDelegate.windowController?.viewModel.selectNotesFolder() }) {
                HStack {
                    Image(systemName: "folder")
                    Text("Choose Notes Folder...")
                }
            }
            .buttonStyle(.plain)
            .padding()

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding()
        }
        .onAppear { menuBarStore.refresh() }
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

    func refresh() {
        recentNotes = Array(NoteStore.shared.allNotes().prefix(3))
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
        }
    }
}

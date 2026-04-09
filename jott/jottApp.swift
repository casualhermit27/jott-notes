//
//  jottApp.swift
//  jott
//
//  Created by Harsha on 22/03/26.
//

import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let jottThemeDidChange = Notification.Name("jottThemeDidChange")
}

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
    private var isDarkMode: Bool { menuBarStore.isDarkMode }
    private var appearanceSelection: Binding<Int> {
        Binding(
            get: { isDarkMode ? 1 : 0 },
            set: { newValue in
                appDelegate.setDarkMode(newValue == 1)
                menuBarStore.refresh()
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Jott")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { appDelegate.toggleOverlay() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .medium))
                        Text("⌥⌥")
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
                    Button(action: { appDelegate.openNote(note) }) {
                        HStack(spacing: 8) {
                            Image(systemName: menuNoteIcon(note))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            Text(menuNoteTitle(note))
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

                Button(action: { appDelegate.openAllNotes() }) {
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

            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)

                Picker("Appearance", selection: appearanceSelection) {
                    Label("Light", systemImage: "sun.max").tag(0)
                    Label("Dark", systemImage: "moon.stars").tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            Button(action: { appDelegate.selectNotesFolder() }) {
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
        .jottAppTypography()
        .onAppear {
            menuBarStore.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func isImageLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("![") && t.contains("](") && t.hasSuffix(")")
    }

    private func menuNoteTitle(_ note: Note) -> String {
        let lines = note.text.components(separatedBy: "\n")
        return lines.first { !isImageLine($0) && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? (lines.contains(where: { isImageLine($0) }) ? "(Image)" : (lines.first ?? note.text))
    }

    private func menuNoteIcon(_ note: Note) -> String {
        let lines = note.text.components(separatedBy: "\n")
        return lines.contains(where: { isImageLine($0) }) ? "photo" : "note.text"
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
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .jottThemeDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        NoteStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

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
    var libraryWindowController: LibraryWindowController?

    private func ensureWindowController() -> OverlayWindowController {
        if let controller = windowController {
            return controller
        }
        let controller = OverlayWindowController()
        windowController = controller
        return controller
    }

    private func ensureLibraryWindowController() -> LibraryWindowController {
        if let controller = libraryWindowController {
            return controller
        }
        let controller = LibraryWindowController(viewModel: ensureWindowController().viewModel)
        libraryWindowController = controller
        return controller
    }

    func toggleOverlay() {
        ensureWindowController().toggle()
    }

    func openNote(_ note: Note) {
        ensureWindowController().openNote(note)
    }

    func openAllNotes() {
        ensureLibraryWindowController().show()
    }

    func toggleDarkMode() {
        setDarkMode(!UserDefaults.standard.bool(forKey: "jott_darkMode"))
    }

    func setDarkMode(_ enabled: Bool) {
        if let windowController {
            windowController.setDarkMode(enabled)
        } else {
            UserDefaults.standard.set(enabled, forKey: "jott_darkMode")
        }
        NotificationCenter.default.post(name: .jottThemeDidChange, object: nil)
    }

    func selectNotesFolder() {
        ensureWindowController().viewModel.selectNotesFolder()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Telemetry.start()
        Telemetry.addBreadcrumb("Application launched", category: "lifecycle")
        UpdateManager.shared.start()

        ensureWindowController().preload()

        // Start clipboard monitor early
        _ = ClipboardMonitor.shared

        // Single shortcut: Option+Space
        HotkeyManager.shared.register { [weak self] in
            self?.toggleOverlay()
        }

        Task {
            await NotificationManager.shared.requestPermission()
            await CalendarManager.shared.requestAccess()
            await CalendarManager.shared.requestRemindersAccess()
        }
    }
}

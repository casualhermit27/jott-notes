//
//  jottApp.swift
//  jott
//
//  Created by Harsha on 22/03/26.
//

import SwiftUI
import AppKit

@main
struct jottApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("jott", image: "JottMenuBar") {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Jott")
                        .font(.headline)

                    if let version = Bundle.main.appVersion {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding()

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
        }
    }
}

extension Bundle {
    var appVersion: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: OverlayWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = OverlayWindowController()
        windowController?.preload()

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

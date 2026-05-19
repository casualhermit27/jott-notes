import SwiftUI
import UIKit
import Combine
import AppIntents

// MARK: - Haptics

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let jottShowPaywall = Notification.Name("jottShowPaywall")
    static let jottOpenCapture = Notification.Name("jottOpenCapture")
    static let jottOpenSearch = Notification.Name("jottOpenSearch")
    static let jottFocusSearch = Notification.Name("jottFocusSearch")
}

// MARK: - App Delegate

class JottAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        CloudKitSyncManager.shared.setupSubscription()
        setupShortcutItems()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            NoteStore.shared.refreshFromDisk()
            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("[Jott] Remote notification registration failed: \(error.localizedDescription)")
    }

    // MARK: - Quick Actions (App Icon Long Press)

    private func setupShortcutItems() {
        let captureItem = UIApplicationShortcutItem(
            type: "com.casualhermit.jott.capture",
            localizedTitle: "New Note",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(type: .compose),
            userInfo: nil
        )
        let searchItem = UIApplicationShortcutItem(
            type: "com.casualhermit.jott.search",
            localizedTitle: "Search",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(type: .search),
            userInfo: nil
        )
        UIApplication.shared.shortcutItems = [captureItem, searchItem]
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        switch shortcutItem.type {
        case "com.casualhermit.jott.capture":
            NotificationCenter.default.post(name: .jottOpenCapture, object: nil)
        case "com.casualhermit.jott.search":
            NotificationCenter.default.post(name: .jottOpenSearch, object: nil)
        default:
            break
        }
        completionHandler(true)
    }
}

// MARK: - App Entry Point

@main
struct JottIOSApp: App {
    @UIApplicationDelegateAdaptor(JottAppDelegate.self) var appDelegate
    @StateObject private var noteStore = NoteStore.shared

    init() {
        let apiKey = JottConfig.revenueCatAPIKey
        if apiKey.isEmpty {
            NSLog("[Jott] Warning: RevenueCat API key is missing. Add REVENUECAT_API_KEY to build settings or Info.plist.")
        } else {
            PurchaseManager.shared.configure(apiKey: apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(noteStore)
                .onReceive(noteStore.objectWillChange) { _ in
                    Task { @MainActor in
                        Self.pushWidgetData(from: noteStore)
                    }
                }
                .onAppear {
                    Self.pushWidgetData(from: noteStore)
                }
        }
    }

    @MainActor
    private static func pushWidgetData(from store: NoteStore) {
        let pinned = store.allNotes().first { $0.isPinned && $0.deletedAt == nil }
        if let note = pinned {
            let lines = note.plainText
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let body = lines.dropFirst().prefix(3).joined(separator: " · ")
            JottWidgetBridge.update(pinnedTitle: note.title,
                                    pinnedBody: body.isEmpty ? nil : body,
                                    modifiedAt: note.modifiedAt)
        } else {
            JottWidgetBridge.update(pinnedTitle: nil, pinnedBody: nil, modifiedAt: nil)
        }
    }
}

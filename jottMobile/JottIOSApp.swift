import SwiftUI
import UIKit
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

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [String: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
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
        }
    }
}

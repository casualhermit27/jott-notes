import SwiftUI
import UIKit

class JottAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        CloudKitSyncManager.shared.setupSubscription()
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
}

@main
struct JottIOSApp: App {
    @UIApplicationDelegateAdaptor(JottAppDelegate.self) var appDelegate
    @StateObject private var noteStore = NoteStore.shared

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(noteStore)
        }
    }
}

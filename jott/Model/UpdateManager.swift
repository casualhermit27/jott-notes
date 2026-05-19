import Foundation
import Combine

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    @Published private(set) var sparkleEnabled = false

    private override init() {
        super.init()
    }

    func start() {
        // Sparkle removed for App Store distribution. The App Store handles updates.
    }

    func checkForUpdates() {
        // No-op for App Store builds.
    }

    var updateChannel: String {
        (Bundle.main.object(forInfoDictionaryKey: "JottUpdateChannel") as? String)?.lowercased() ?? "app_store"
    }
}

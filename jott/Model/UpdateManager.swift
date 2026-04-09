import Foundation
import Combine
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    @Published private(set) var sparkleEnabled = false

    private var updaterController: SPUStandardUpdaterController?

    private override init() {
        super.init()
    }

    func start() {
        guard updaterController == nil else { return }
        guard shouldUseSparkle else {
            Telemetry.addBreadcrumb("Skipping Sparkle for App Store channel", category: "updates")
            return
        }

        guard let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedURLString),
              !feedURL.absoluteString.isEmpty else {
            Telemetry.captureMessage(
                "Sparkle disabled: SUFeedURL missing",
                level: .warning,
                data: ["channel": updateChannel]
            )
            return
        }

        Telemetry.addBreadcrumb(
            "Starting Sparkle updater",
            category: "updates",
            data: ["feed_url": feedURL.absoluteString]
        )

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        sparkleEnabled = true
    }

    func checkForUpdates() {
        guard sparkleEnabled, let updater = updaterController?.updater else {
            Telemetry.captureMessage(
                "Check for updates requested while Sparkle disabled",
                level: .info,
                data: ["channel": updateChannel]
            )
            return
        }
        updater.checkForUpdates()
    }

    var updateChannel: String {
        (Bundle.main.object(forInfoDictionaryKey: "JottUpdateChannel") as? String)?.lowercased() ?? "direct"
    }

    private var shouldUseSparkle: Bool {
        updateChannel != "app_store"
    }
}

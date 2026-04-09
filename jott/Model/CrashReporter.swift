import Foundation
import CryptoKit
import Sentry

enum TelemetryLevel {
    case info
    case warning
    case error
}

enum Telemetry {
    private static var isStarted = false
    static var isEnabled: Bool { isStarted }

    static func start() {
        guard !isStarted else { return }

        let env = ProcessInfo.processInfo.environment
        let configuredDSN = env["SENTRY_DSN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let dsn = configuredDSN, !dsn.isEmpty else {
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.enableAppHangTracking = true
            options.enableWatchdogTerminationTracking = true
            options.enableAutoSessionTracking = true
            options.sendDefaultPii = false
            options.environment = env["SENTRY_ENVIRONMENT"] ?? "production"

            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            options.releaseName = "com.casualhermit.jott@\(version)+\(build)"
        }

        isStarted = true
        addBreadcrumb("Telemetry started", category: "lifecycle")
    }

    static func addBreadcrumb(_ message: String, category: String, level: TelemetryLevel = .info, data: [String: Any] = [:]) {
        guard isStarted else { return }
        let crumb = Breadcrumb()
        crumb.level = sentryLevel(level)
        crumb.category = category
        crumb.message = message
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)
    }

    static func captureError(_ error: Error, context: String, data: [String: Any] = [:]) {
        guard isStarted else { return }
        SentrySDK.configureScope { scope in
            scope.setTag(value: context, key: "context")
            data.forEach { key, value in
                scope.setExtra(value: value, key: key)
            }
        }
        SentrySDK.capture(error: error)
    }

    static func captureMessage(_ message: String, level: TelemetryLevel = .warning, data: [String: Any] = [:]) {
        guard isStarted else { return }
        SentrySDK.configureScope { scope in
            data.forEach { key, value in
                scope.setExtra(value: value, key: key)
            }
        }
        SentrySDK.capture(message: message)
    }

    static func hashInput(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func recordNLPParseFailure(intent: String, input: String) {
        let inputHash = hashInput(input)
        captureMessage(
            "NLP parse fallback triggered",
            level: .info,
            data: [
                "intent": intent,
                "input_hash": inputHash,
                "input_length": input.count
            ]
        )

        addBreadcrumb(
            "NLP parse fallback",
            category: "nlp",
            data: [
                "intent": intent,
                "input_hash": inputHash
            ]
        )
    }

    private static func sentryLevel(_ level: TelemetryLevel) -> SentryLevel {
        switch level {
        case .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }
}

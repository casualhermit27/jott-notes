// No-op Telemetry stub for the iOS target.
// The macOS target has a real implementation backed by Sentry (CrashReporter.swift).
// On iOS, Sentry is not a dependency, so all calls are silently dropped.

import Foundation

enum TelemetryLevel {
    case info, warning, error
}

enum Telemetry {
    static var isEnabled: Bool { false }
    static func start() {}
    static func addBreadcrumb(_ message: String, category: String, level: TelemetryLevel = .info, data: [String: Any] = [:]) {}
    static func captureError(_ error: Error, context: String, data: [String: Any] = [:]) {}
    static func captureMessage(_ message: String, level: TelemetryLevel = .warning, data: [String: Any] = [:]) {}
    static func hashInput(_ input: String) -> String { "" }
    static func recordNLPParseFailure(intent: String, input: String) {}
}

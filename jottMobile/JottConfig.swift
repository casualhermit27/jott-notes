import Foundation

enum JottConfig {
    /// RevenueCat API key — injected at build time via the `REVENUECAT_API_KEY`
    /// environment variable or Xcode build setting. If missing, the app runs in
    /// a degraded mode (no purchases) and logs a warning.
    static var revenueCatAPIKey: String {
        // 1. Build-time injection (CI / xcconfig)
        if let envKey = ProcessInfo.processInfo.environment["REVENUECAT_API_KEY"],
           !envKey.isEmpty,
           !envKey.hasPrefix("$") { // ignore unexpanded Xcode variables
            return envKey
        }

        // 2. Runtime lookup in Info.plist (for manual injection)
        if let plistKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
           !plistKey.isEmpty {
            return plistKey
        }

        // 3. Deprecated hardcoded fallback — DO NOT commit real keys here.
        // This path exists only so the app compiles out-of-the-box for development.
        // Replace with your own test key or leave empty.
        return ""
    }

    static var hasRevenueCatKey: Bool { !revenueCatAPIKey.isEmpty }
}

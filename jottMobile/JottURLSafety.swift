import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum JottURLSafety {
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    /// Returns a sanitized URL if its scheme is whitelisted; otherwise nil.
    static func sanitizedURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else {
            return nil
        }
        return url
    }

    /// Opens the URL via NSWorkspace/UIApplication only if the scheme is whitelisted.
    static func openIfAllowed(_ string: String) {
        guard let url = sanitizedURL(string) else {
            NSLog("[Jott] Blocked attempt to open non-whitelisted URL: \(string.prefix(200))")
            return
        }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

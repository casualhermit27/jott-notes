import AppKit
import Foundation

/// Watches the system pasteboard for text changes.
/// When the user copies text, `pendingText` is set.
/// The overlay reads and clears it on open (opt-in: only used if user hits hotkey after copying).
@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private(set) var pendingText: String?
    private var pendingTextDate: Date?
    private var lastChangeCount: Int
    private var timer: Timer?

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        startMonitoring()
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.checkClipboard() }
        }
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingText = text
            pendingTextDate = Date()
        }
    }

    /// Returns and clears pending text only if it was copied within the last 60 seconds.
    func consume() -> String? {
        guard let t = pendingText,
              let date = pendingTextDate,
              Date().timeIntervalSince(date) < 60 else {
            pendingText = nil
            pendingTextDate = nil
            return nil
        }
        pendingText = nil
        pendingTextDate = nil
        return t
    }

    /// Clears without returning.
    func clear() {
        pendingText = nil
        pendingTextDate = nil
    }
}

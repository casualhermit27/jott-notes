import AppKit
import Foundation
import Combine

/// Watches the system pasteboard for text changes.
/// When the user copies text, `pendingText` is set.
/// The overlay reads and clears it on open (opt-in: only used if user hits hotkey after copying).
@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private(set) var pendingText: String?
    private var pendingTextDate: Date?
    private var lastObservedChangeCount: Int
    private var cancellables = Set<AnyCancellable>()

    private init() {
        lastObservedChangeCount = NSPasteboard.general.changeCount
        startMonitoring()
    }

    private func startMonitoring() {
        Timer.publish(every: 0.15, on: .main, in: .common)
            .autoconnect()
            .map { _ in NSPasteboard.general.changeCount }
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] newCount in
                guard let self else { return }
                guard newCount != self.lastObservedChangeCount else { return }
                self.lastObservedChangeCount = newCount

                let pb = NSPasteboard.general
                if let text = pb.string(forType: .string),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.pendingText = text
                    self.pendingTextDate = Date()
                }
            }
            .store(in: &cancellables)
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

#if DEBUG
    /// Test-only helper to seed clipboard state without touching NSPasteboard.
    func seedPendingTextForTesting(_ text: String?, copiedAt: Date?) {
        pendingText = text
        pendingTextDate = copiedAt
    }
#endif
}

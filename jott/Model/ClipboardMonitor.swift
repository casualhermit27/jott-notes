import AppKit
import Foundation
import Combine

enum ClipboardPendingKind: Equatable {
    case text
    case image
}

/// Watches the system pasteboard for text and image changes.
/// The overlay can offer recent content on open, but should only insert it after explicit user action.
@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private(set) var pendingText: String?
    private(set) var pendingKind: ClipboardPendingKind?
    private var pendingDate: Date?
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
                    self.pendingKind = .text
                    self.pendingDate = Date()
                } else if Self.containsImageContent(pb) {
                    self.pendingText = nil
                    self.pendingKind = .image
                    self.pendingDate = Date()
                } else {
                    self.clear()
                }
            }
            .store(in: &cancellables)
    }

    /// Returns and clears pending text only if it was copied within the last 60 seconds.
    func consume() -> String? {
        guard let t = peek() else { return nil }
        pendingText = nil
        pendingKind = nil
        pendingDate = nil
        return t
    }

    /// Returns pending text without clearing it, only if copied within the last 60 seconds.
    func peek() -> String? {
        guard peekKind() == .text else { return nil }
        return pendingText
    }

    /// Returns pending content kind without clearing it, only if copied within the last 60 seconds.
    func peekKind() -> ClipboardPendingKind? {
        guard let kind = pendingKind,
              let date = pendingDate,
              Date().timeIntervalSince(date) < 60 else {
            clear()
            return nil
        }
        return kind
    }

    /// Returns and clears pending content kind only if it was copied within the last 60 seconds.
    func consumeKind() -> ClipboardPendingKind? {
        guard let kind = peekKind() else { return nil }
        clear()
        return kind
    }

    /// Clears without returning.
    func clear() {
        pendingText = nil
        pendingKind = nil
        pendingDate = nil
    }

    private static func containsImageContent(_ pb: NSPasteboard) -> Bool {
        if NSImage(pasteboard: pb) != nil { return true }

        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.tiff"),
            NSPasteboard.PasteboardType("com.apple.pict")
        ]
        if imageTypes.contains(where: { pb.data(forType: $0) != nil }) {
            return true
        }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff"]
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            return urls.contains { imageExtensions.contains($0.pathExtension.lowercased()) }
        }
        return false
    }

#if DEBUG
    /// Test-only helper to seed clipboard state without touching NSPasteboard.
    func seedPendingTextForTesting(_ text: String?, copiedAt: Date?) {
        pendingText = text
        pendingKind = text == nil ? nil : .text
        pendingDate = copiedAt
    }
#endif
}

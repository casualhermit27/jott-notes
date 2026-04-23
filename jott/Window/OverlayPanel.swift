import AppKit
import SwiftUI

extension NSNotification.Name {
    static let overlayDidResignKey = NSNotification.Name("overlayDidResignKey")
}

/// Shared hosting view that accepts first mouse — single click works without pre-focusing the window.
class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class OverlayPanel: NSPanel {
    /// Set to true while a drag operation is targeting the panel so resignKey doesn't dismiss it.
    static var suppressResignKey = false

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [
                .borderless,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // Above the menu bar so the 420pt panel covers the notch area.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        hasShadow = false   // shadow is drawn by SwiftUI so it follows the card, not the full panel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func resignKey() {
        super.resignKey()
        guard !Self.suppressResignKey else { return }
        let hoverFrame = frame.insetBy(dx: -8, dy: -8)
        guard !hoverFrame.contains(NSEvent.mouseLocation) else { return }
        NotificationCenter.default.post(name: .overlayDidResignKey, object: nil)
    }
}

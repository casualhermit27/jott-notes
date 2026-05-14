import AppKit
import SwiftUI

extension NSNotification.Name {
    static let overlayDidResignKey = NSNotification.Name("overlayDidResignKey")
}

/// Shared hosting view that accepts first mouse — single click works without pre-focusing the window.
/// Intrinsic content size is suppressed so the hosting view never tries to auto-resize the window;
/// both OverlayPanel and FocusNotePanel always set their frames explicitly via setFrame().
class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Returning zero prevents the NSHostingView machinery from calling
    // updateAnimatedWindowSize during layout, which otherwise creates an infinite
    // layout-pass loop in AppKit (too many constraint update passes).
    override var intrinsicContentSize: NSSize { .zero }

    // NSHostingView.windowDidLayout calls updateAnimatedWindowSize, which calls
    // setFrame on our explicitly-managed panel. During an active layout pass this
    // triggers KVO → constraint invalidation → another layout pass → crash
    // ("too many Update Constraints passes"). We manage all frames explicitly so
    // updateAnimatedWindowSize must never run.
    @objc func windowDidLayout() {}
}

class OverlayPanel: NSPanel {
    /// Set to true while a drag operation is targeting the panel so resignKey doesn't dismiss it.
    static var suppressResignKey = false
    /// Set to true when the overlay is in locked mode — outside clicks do not dismiss.
    static var isLocked = false

    private var suppressSwiftUIResize = false

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        guard !suppressSwiftUIResize else { return }
        suppressSwiftUIResize = true
        defer { suppressSwiftUIResize = false }
        super.setFrame(frameRect, display: displayFlag)
    }

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
        guard !Self.isLocked else { return }
        let hoverFrame = frame.insetBy(dx: -2, dy: -2)
        guard !hoverFrame.contains(NSEvent.mouseLocation) else { return }
        NotificationCenter.default.post(name: .overlayDidResignKey, object: nil)
    }
}

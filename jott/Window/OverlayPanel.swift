import AppKit

extension NSNotification.Name {
    static let overlayDidResignKey = NSNotification.Name("overlayDidResignKey")
}

class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [
                .borderless,
                .nonactivatingPanel,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]
        isMovableByWindowBackground = true
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
        NotificationCenter.default.post(name: .overlayDidResignKey, object: nil)
    }
}

import AppKit
import SwiftUI

class LibraryWindowController: NSWindowController {
    let viewModel: OverlayViewModel

    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel

        let libraryView = LibraryView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: libraryView)
        hostingView.wantsLayer = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "Jott Library"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = NSColor.white

        super.init(window: window)

        // Keyboard shortcuts
        window.standardWindowButton(.closeButton)?.target = self
        window.standardWindowButton(.closeButton)?.action = #selector(windowShouldClose)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func windowShouldClose() {
        window?.close()
    }
}

import AppKit
import SwiftUI
import Combine

class LibraryWindowController: NSWindowController, NSWindowDelegate {
    let viewModel: OverlayViewModel
    private var hostingView: FirstMouseHostingView<LibraryView>?
    private var cancellables = Set<AnyCancellable>()
    private var isEnteringFullScreen = false

    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel

        let libraryView = LibraryView(viewModel: viewModel)
        let hostingView = FirstMouseHostingView(rootView: libraryView)
        hostingView.wantsLayer = true
        self.hostingView = hostingView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "Jott"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .automatic
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        super.init(window: window)
        window.delegate = self
        applyAppearance()

        viewModel.$isDarkMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyAppearance()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        applyAppearance()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    // NSWindowDelegate — full-screen lifecycle
    func windowWillEnterFullScreen(_ notification: Notification) {
        isEnteringFullScreen = true
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isEnteringFullScreen = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {}

    // Hide (not close) when the window loses key status — click outside dismisses it.
    func windowDidResignKey(_ notification: Notification) {
        guard !isEnteringFullScreen else { return }
        window?.orderOut(nil)
    }

    // Close button hides rather than closes so the controller is reused on next open.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {}

    private func applyAppearance() {
        let appearance = NSAppearance(named: viewModel.isDarkMode ? .darkAqua : .aqua)
        window?.appearance = appearance
        window?.contentView?.appearance = appearance
        hostingView?.appearance = appearance
    }
}

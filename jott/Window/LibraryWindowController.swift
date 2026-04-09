import AppKit
import SwiftUI
import Combine

class LibraryWindowController: NSWindowController, NSWindowDelegate {
    let viewModel: OverlayViewModel
    private var hostingView: NSHostingView<LibraryView>?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel

        let libraryView = LibraryView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: libraryView)
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
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // NSWindowDelegate — restore menu-bar-only mode when window closes
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let hasOtherWindows = NSApp.windows.contains {
                $0.isVisible && $0 !== self.window && $0.styleMask.contains(.titled)
            }
            if !hasOtherWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func applyAppearance() {
        let appearance = NSAppearance(named: viewModel.isDarkMode ? .darkAqua : .aqua)
        window?.appearance = appearance
        window?.contentView?.appearance = appearance
        hostingView?.appearance = appearance
    }
}

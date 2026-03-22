import AppKit
import SwiftUI
import Combine

class OverlayWindowController {
    let panel: OverlayPanel
    let viewModel: OverlayViewModel
    private var hostingView: NSHostingView<OverlayView>?
    private var cancellables = Set<AnyCancellable>()

    // Panel is fixed — never resizes. Card inside grows via SwiftUI.
    private let panelWidth:  CGFloat = 520
    private let panelHeight: CGFloat = 420

    var isDarkMode: Bool { viewModel.isDarkMode }

    init() {
        self.panel  = OverlayPanel()
        self.viewModel = OverlayViewModel()

        let hostingView = NSHostingView(rootView: OverlayView(viewModel: viewModel))
        hostingView.wantsLayer = true
        self.hostingView = hostingView
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(
            forName: .overlayDidResignKey, object: nil, queue: .main
        ) { [weak self] _ in self?.dismiss() }

        viewModel.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in v ? self?.show() : self?.dismiss() }
            .store(in: &cancellables)
    }

    func preload() {}

    private func panelFrame() -> CGRect {
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return .zero }
        let x    = screen.visibleFrame.midX - panelWidth / 2
        // Top of card at ~38% from top; panel is tall enough to fit everything below
        let topY = screen.visibleFrame.minY + screen.visibleFrame.height * 0.62
        return CGRect(x: x, y: topY - panelHeight, width: panelWidth, height: panelHeight)
    }

    func show() {
        panel.setFrame(panelFrame(), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        // Focus the text view directly — hosting view isn't focusable
        DispatchQueue.main.async { [weak self] in self?.focusTextView() }
    }

    private func focusTextView() {
        guard let hv = hostingView else { return }
        func findTextView(_ view: NSView) -> JottNSTextView? {
            if let tv = view as? JottNSTextView { return tv }
            for sub in view.subviews { if let tv = findTextView(sub) { return tv } }
            return nil
        }
        if let tv = findTextView(hv) { panel.makeFirstResponder(tv) }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }) { self.panel.orderOut(nil) }
    }

    func toggle() { viewModel.toggle() }
    func toggleDarkMode() { viewModel.toggleDarkMode() }

    /// Opens the overlay with a specific note already selected (from menubar recent notes).
    func openNote(_ note: Note) {
        viewModel.show()
        viewModel.selectedNote = note
    }
}

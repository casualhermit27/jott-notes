import AppKit
import SwiftUI
import Combine

class OverlayWindowController {
    let panel: OverlayPanel
    let viewModel: OverlayViewModel
    private var hostingView: FirstMouseHostingView<OverlayView>?
    private var cancellables = Set<AnyCancellable>()

    // Notch drop panel - fixed content width, anchored at top-center.
    private let panelHeight: CGFloat = 640
    private let notchPanelWidth: CGFloat = 460

    var isDarkMode: Bool { viewModel.isDarkMode }

    init() {
        self.panel  = OverlayPanel()
        self.viewModel = OverlayViewModel()

        let hostingView = FirstMouseHostingView(rootView: OverlayView(viewModel: viewModel))
        hostingView.wantsLayer = true
        self.hostingView = hostingView
        panel.contentView = hostingView
        applyAppearance()

        NotificationCenter.default.addObserver(
            forName: .overlayDidResignKey, object: nil, queue: .main
        ) { [weak self] _ in self?.dismiss() }

        viewModel.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in v ? self?.show() : self?.dismiss() }
            .store(in: &cancellables)

        viewModel.$isDarkMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyAppearance()
            }
            .store(in: &cancellables)
    }

    func preload() {
        applyAppearance()
        panel.setFrame(panelFrame(), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        hostingView?.layoutSubtreeIfNeeded()
    }

    private func applyAppearance() {
        // Notch panel is always pitch-black — force dark appearance.
        let appearance = NSAppearance(named: .darkAqua)
        panel.appearance = appearance
        panel.contentView?.appearance = appearance
        hostingView?.appearance = appearance
        hostingView?.rootView = OverlayView(viewModel: viewModel)
        hostingView?.needsLayout = true
    }

    private func panelFrame() -> CGRect {
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return .zero }
        // Use screen.frame (not visibleFrame) so the panel's top edge is flush
        // with the physical top of the screen, covering the notch within the fixed panel width.
        let sf = screen.frame
        let x = sf.midX - notchPanelWidth / 2
        let y = sf.maxY - panelHeight
        return CGRect(x: x, y: y, width: notchPanelWidth, height: panelHeight)
    }

    func show() {
        applyAppearance()
        NSApp.activate(ignoringOtherApps: true)

        // Ensure no leftover layer transforms from a previous animation.
        hostingView?.layer?.removeAllAnimations()
        hostingView?.layer?.transform = CATransform3DIdentity

        let target = panelFrame()
        var start = target
        start.origin.y = target.origin.y + panelHeight  // above screen

        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        // Animate the window frame down — window clips its own content so
        // the spring overshoot can never expose a gap at the top.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.54
            // steep deceleration curve: rushes out of notch, settles softly
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.08, 1.0, 0.24, 1.0)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(target, display: true)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        DispatchQueue.main.async { [weak self] in self?.focusTextView() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.focusTextView() }
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
        let current = panel.frame
        var exit = current
        exit.origin.y = current.origin.y + panelHeight  // slide back up into notch

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0.0, 1.0, 1.0)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(exit, display: true)
            panel.animator().alphaValue = 0
        }) { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    func toggle() { viewModel.toggle() }
    func toggleDarkMode() {
        viewModel.toggleDarkMode()
        applyAppearance()
    }

    func setDarkMode(_ enabled: Bool) {
        viewModel.setDarkMode(enabled)
        applyAppearance()
    }

    /// Opens the overlay with a specific note already selected (from menubar recent notes).
    func openNote(_ note: Note) {
        viewModel.show()
        viewModel.selectedNote = note
    }

    func openAllNotes() {
        viewModel.show()
        viewModel.activateCommandMode(.notes(query: ""))
    }
}

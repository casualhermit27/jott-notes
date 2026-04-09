import AppKit
import SwiftUI
import Combine

class OverlayWindowController {
    let panel: OverlayPanel
    let viewModel: OverlayViewModel
    private var hostingView: NSHostingView<OverlayView>?
    private var cancellables = Set<AnyCancellable>()

    // Panel height is fixed; width and position adapt to user preference.
    private let panelHeight: CGFloat = 540
    private var panelWidth: CGFloat { viewModel.panelDisplayWidth }

    var isDarkMode: Bool { viewModel.isDarkMode }

    init() {
        self.panel  = OverlayPanel()
        self.viewModel = OverlayViewModel()

        let hostingView = NSHostingView(rootView: OverlayView(viewModel: viewModel))
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
        let appearance = NSAppearance(
            named: viewModel.isDarkMode ? .darkAqua : .aqua
        )
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
        let sf = screen.visibleFrame
        let w = panelWidth
        let x: CGFloat
        let y: CGFloat
        switch viewModel.overlayPosition {
        case "topLeft":
            x = sf.minX + 16
            y = sf.maxY - panelHeight - 8
        case "topRight":
            x = sf.maxX - w - 16
            y = sf.maxY - panelHeight - 8
        default: // center
            x = sf.midX - w / 2
            y = sf.midY - panelHeight / 2
        }
        return CGRect(x: x, y: y, width: w, height: panelHeight)
    }

    func show() {
        applyAppearance()
        NSApp.activate(ignoringOtherApps: true)
        panel.setFrame(panelFrame(), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        // Scale up from 0.94 at the bar's anchor point — Spotlight entrance feel
        if let layer = hostingView?.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DConcat(
                CATransform3DMakeScale(0.94, 0.94, 1),
                CATransform3DMakeTranslation(0, 6, 0)
            )
            CATransaction.commit()

            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = layer.transform
            anim.toValue = CATransform3DIdentity
            anim.duration = JottMotion.panelDuration
            anim.timingFunction = JottMotion.panelEntranceTiming
            anim.isRemovedOnCompletion = true
            layer.add(anim, forKey: "entrance")

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = JottMotion.panelFadeDuration
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
        if let layer = hostingView?.layer {
            let exitTransform = CATransform3DConcat(
                CATransform3DMakeScale(0.96, 0.96, 1),
                CATransform3DMakeTranslation(0, 3, 0)
            )
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = CATransform3DIdentity
            anim.toValue = exitTransform
            anim.duration = JottMotion.panelDuration
            anim.timingFunction = JottMotion.panelExitTiming
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "exit")
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = JottMotion.panelFadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }) { [weak self] in
            self?.panel.orderOut(nil)
            self?.hostingView?.layer?.removeAllAnimations()
            self?.hostingView?.layer?.transform = CATransform3DIdentity
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

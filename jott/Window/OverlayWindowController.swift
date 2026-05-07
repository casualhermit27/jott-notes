import AppKit
import SwiftUI
import Combine

class OverlayWindowController {
    let panel: OverlayPanel
    let viewModel: OverlayViewModel
    private var hostingView: FirstMouseHostingView<OverlayView>?
    private var cancellables = Set<AnyCancellable>()
    private var dismissWorkItem: DispatchWorkItem?
    private var escMonitor: Any?

    // Notch drop panel - fixed content width, anchored at top-center.
    private let panelHeight: CGFloat = 640
    private let notchPanelWidth: CGFloat = 460
    private let notchOpenWidthAnimation = Animation.interpolatingSpring(
        mass: 1.05,
        stiffness: 195,
        damping: 25,
        initialVelocity: 0
    )
    private let notchOpenHeightAnimation = Animation.interpolatingSpring(
        mass: 1.05,
        stiffness: 175,
        damping: 24,
        initialVelocity: 0
    ).delay(0.045)
    private let notchOpenCornerAnimation = Animation.interpolatingSpring(
        mass: 1.06,
        stiffness: 160,
        damping: 24,
        initialVelocity: 0
    ).delay(0.075)
    private let notchOpenContentAnimation = Animation.easeOut(duration: 0.16).delay(0.18)
    private let notchCloseHeightAnimation = Animation.interpolatingSpring(
        mass: 0.86,
        stiffness: 286,
        damping: 32,
        initialVelocity: 0
    )
    private let notchCloseWidthAnimation = Animation.interpolatingSpring(
        mass: 0.86,
        stiffness: 318,
        damping: 35,
        initialVelocity: 0
    ).delay(0.04)
    private let notchCloseCornerAnimation = Animation.interpolatingSpring(
        mass: 0.86,
        stiffness: 340,
        damping: 38,
        initialVelocity: 0
    ).delay(0.075)
    private let notchCloseExitAnimation = Animation.interpolatingSpring(
        mass: 0.82,
        stiffness: 310,
        damping: 36,
        initialVelocity: 0
    )
    private let notchCloseContentAnimation = Animation.easeOut(duration: 0.055)

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
        ) { [weak self] _ in self?.viewModel.dismiss() }

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

        // Sync lock state to OverlayPanel so resignKey can respect it.
        viewModel.$isLocked
            .receive(on: DispatchQueue.main)
            .sink { OverlayPanel.isLocked = $0 }
            .store(in: &cancellables)

        // ESC always dismisses regardless of lock state.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // 53 = ESC
            self?.viewModel.isLocked = false
            self?.viewModel.dismiss()
            return nil
        }
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
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        applyAppearance()
        NSApp.activate(ignoringOtherApps: true)

        hostingView?.layer?.removeAllAnimations()
        hostingView?.layer?.transform = CATransform3DIdentity

        // Clip shape starts as a notch-sized bar.
        // Width expands immediately; height follows 60 ms later.
        viewModel.revealProgress = 0
        viewModel.revealWidthProgress = 0
        viewModel.revealHeightProgress = 0
        viewModel.revealCornerProgress = 0
        viewModel.revealContentProgress = 0
        viewModel.revealExitProgress = 0
        viewModel.revealSurfaceBiasProgress = 0
        panel.setFrame(panelFrame(), display: false)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(self.notchOpenWidthAnimation) {
                self.viewModel.revealProgress = 1
                self.viewModel.revealWidthProgress = 1
            }
            withAnimation(self.notchOpenHeightAnimation) {
                self.viewModel.revealHeightProgress = 1
            }
            withAnimation(self.notchOpenCornerAnimation) {
                self.viewModel.revealCornerProgress = 1
            }
            withAnimation(self.notchOpenContentAnimation) {
                self.viewModel.revealContentProgress = 1
            }
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
        dismissWorkItem?.cancel()

        withAnimation(notchCloseContentAnimation) {
            viewModel.revealContentProgress = 0
        }
        withAnimation(notchCloseExitAnimation) {
            viewModel.revealProgress = 0
            viewModel.revealExitProgress = 1
            viewModel.revealSurfaceBiasProgress = 1
        }
        withAnimation(notchCloseHeightAnimation) {
            viewModel.revealHeightProgress = 0
        }
        withAnimation(notchCloseWidthAnimation) {
            viewModel.revealWidthProgress = 0
        }
        withAnimation(notchCloseCornerAnimation) {
            viewModel.revealCornerProgress = 0
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.viewModel.revealProgress = 0
            self.viewModel.revealWidthProgress = 0
            self.viewModel.revealHeightProgress = 0
            self.viewModel.revealCornerProgress = 0
            self.viewModel.revealContentProgress = 0
            self.viewModel.revealExitProgress = 0
            self.viewModel.revealSurfaceBiasProgress = 0
            self.panel.alphaValue = 0
            self.panel.orderOut(nil)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46, execute: workItem)
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
        viewModel.activateCommandMode(.search(query: ""))
    }
}

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
    private let defaultCompactWidth: CGFloat = 178
    private let defaultCompactHeight: CGFloat = 32

    // One spring for open, one for close.
    // Everything — width, height, corners, content opacity — is derived from revealProgress alone.
    private let openSpring = Animation.interpolatingSpring(
        mass: 1.0, stiffness: 185, damping: 24, initialVelocity: 0.4
    )
    private let closeSpring = Animation.interpolatingSpring(
        mass: 0.85, stiffness: 305, damping: 33, initialVelocity: 0
    )

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
            .sink { [weak self] _ in self?.applyAppearance() }
            .store(in: &cancellables)

        viewModel.$isLocked
            .receive(on: DispatchQueue.main)
            .sink { OverlayPanel.isLocked = $0 }
            .store(in: &cancellables)

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
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
        let appearance = NSAppearance(named: .darkAqua)
        panel.appearance = appearance
        panel.contentView?.appearance = appearance
        hostingView?.appearance = appearance
        hostingView?.rootView = OverlayView(viewModel: viewModel)
        hostingView?.needsLayout = true
    }

    private func targetScreen() -> NSScreen? {
        if viewModel.focusedNote != nil {
            if #available(macOS 12.0, *) {
                return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
            }
            return NSScreen.main
        }
        return NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main
    }

    func panelFrame() -> CGRect {
        guard let screen = targetScreen() else { return .zero }
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

        if viewModel.focusedNote != nil {
            let notchW = handoffNotchWidth()
            let sideW: CGFloat = 62       // matches FocusNotePillController.sideW
            let pillCollapsedW = notchW + sideW * 2
            let pillExpandedW: CGFloat = 370  // matches FocusNotePillController.expandedW

            // Read pill state before onWillShow resets it.
            let startWidth  = viewModel.pillIsExpanded ? pillExpandedW : pillCollapsedW
            let startHeight = viewModel.pillCompactHeight  // 34 normal, 70 if hovering

            // Hide pill synchronously — same rendering pass, zero async gap.
            viewModel.onWillShow?()

            viewModel.revealCompactWidth  = startWidth
            viewModel.revealCompactHeight = startHeight
        } else {
            viewModel.revealCompactWidth  = defaultCompactWidth
            viewModel.revealCompactHeight = defaultCompactHeight
        }

        viewModel.revealProgress     = 0
        viewModel.revealExitProgress = 0

        panel.setFrame(panelFrame(), display: false)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)

        // Single spring drives everything: shape morph, content reveal, shadows.
        // No chained animations, no separate phases.
        withAnimation(openSpring) {
            viewModel.revealProgress = 1
        }

        DispatchQueue.main.async { [weak self] in self?.focusTextView() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.focusTextView() }
    }

    // Same notch detection logic as FocusNotePillController. Fallback matches fallbackNotchW=154.
    private func handoffNotchWidth() -> CGFloat {
        if #available(macOS 12.0, *),
           let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let w = rightArea.minX - leftArea.maxX
            if w > 80 { return w }
        }
        return 154
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

        // Snap compact target to pill's collapsed landing state (invisible while bar is open).
        if viewModel.focusedNote != nil {
            let notchW = handoffNotchWidth()
            let sideW: CGFloat  = 62   // matches FocusNotePillController.sideW
            let notchH: CGFloat = 34   // matches FocusNotePillController.notchH
            viewModel.revealCompactWidth  = notchW + sideW * 2
            viewModel.revealCompactHeight = notchH
        }

        withAnimation(closeSpring) {
            viewModel.revealProgress     = 0
            viewModel.revealExitProgress = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.viewModel.revealProgress        = 0
            self.viewModel.revealExitProgress    = 0
            self.viewModel.revealCompactWidth    = self.defaultCompactWidth
            self.viewModel.revealCompactHeight   = self.defaultCompactHeight
            self.panel.alphaValue = 0
            self.panel.orderOut(nil)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: workItem)
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

    func openNote(_ note: Note) {
        viewModel.show()
        viewModel.selectedNote = note
    }

    func openAllNotes() {
        viewModel.show()
        viewModel.activateCommandMode(.search(query: ""))
    }
}

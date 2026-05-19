import AppKit
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

class OverlayWindowController {
    let panel: OverlayPanel
    let viewModel: OverlayViewModel
    private var hostingView: FirstMouseHostingView<OverlayView>?
    private var cancellables = Set<AnyCancellable>()
    private var dismissWorkItem: DispatchWorkItem?
    private var escMonitor: Any?

    // Panel is always 460×640, centered on notch. Clip shape animates within it.
    private let panelHeight:          CGFloat = 640
    private let notchPanelWidth:      CGFloat = 460
    private let defaultCompactWidth:  CGFloat = 178
    private let defaultCompactHeight: CGFloat = 32
    // Extra height below the bar's visual bottom to keep Aa/mic buttons unclipped.
    private let floatingAllowance:    CGFloat = 116

    // Open: staggered springs. Width fires immediately, height+radius follow 60ms later.
    private let openSpring  = Animation.interpolatingSpring(
        mass: 1.0, stiffness: 130, damping: 21, initialVelocity: 1.0
    )
    // Close: smooth liquid morphy spring to match opening fluidity.
    private let closeSpring = Animation.interpolatingSpring(
        mass: 1.0, stiffness: 140, damping: 22, initialVelocity: 0.0
    )

    // Last height we animated to — used to skip no-op updates while the bar is open.
    private var lastExpandedHeight: CGFloat = 0

    var isDarkMode: Bool { viewModel.isDarkMode }

    init() {
        self.panel     = OverlayPanel()
        self.viewModel = OverlayViewModel()

        let hostingView = FirstMouseHostingView(rootView: OverlayView(viewModel: viewModel))
        hostingView.wantsLayer = true
        self.hostingView = hostingView
        panel.contentView = hostingView
        applyAppearance()

        NotificationCenter.default.addObserver(
            forName: .overlayDidResignKey, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.viewModel.dismiss() }
        }

        viewModel.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in v ? self?.show() : self?.dismiss() }
            .store(in: &cancellables)

        viewModel.$isDarkMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyAppearance(rebuildRootView: true) }
            .store(in: &cancellables)

        viewModel.$isLocked
            .receive(on: DispatchQueue.main)
            .sink { OverlayPanel.isLocked = $0 }
            .store(in: &cancellables)

        // Animate morphHeight when overlayExpandedHeight changes while open.
        // DispatchQueue.main.async reads the value AFTER the @Published change propagates.
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.viewModel.isVisible,
                          self.viewModel.contentVisible else { return }
                    let newH = self.viewModel.overlayExpandedHeight + self.floatingAllowance
                    guard abs(newH - self.lastExpandedHeight) > 1 else { return }
                    self.lastExpandedHeight = newH
                    withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 200, damping: 26)) {
                        self.viewModel.morphHeight = newH
                    }
                }
            }
            .store(in: &cancellables)

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.viewModel.isLocked = false
            self?.viewModel.dismiss()
            return nil
        }

        // Hide the panel during space transitions (e.g. Spotlight over fullscreen)
        // so the panel doesn't sit on top of the transition and cause a black screen.
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.panel.alphaValue > 0 else { return }
            self.panel.alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.viewModel.isVisible else { return }
                self.panel.alphaValue = 1
            }
        }
    }

    func preload() {
        applyAppearance()
        panel.setFrame(panelFrame(), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        hostingView?.layoutSubtreeIfNeeded()
    }

    private func applyAppearance(rebuildRootView: Bool = false) {
        let appearance = NSAppearance(named: .darkAqua)
        panel.appearance = appearance
        panel.contentView?.appearance = appearance
        hostingView?.appearance = appearance
        if rebuildRootView {
            hostingView?.rootView = OverlayView(viewModel: viewModel)
        }
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

        let targetWidth  = notchPanelWidth
        let targetHeight = viewModel.overlayExpandedHeight + floatingAllowance
        lastExpandedHeight = targetHeight

        if viewModel.focusedNote != nil {
            let notchW = handoffNotchWidth()
            let sideW: CGFloat  = 62
            let pillCollapsedW  = notchW + sideW * 2
            let pillExpandedW:   CGFloat = 370

            let startWidth  = viewModel.pillIsExpanded ? pillExpandedW : pillCollapsedW
            let startHeight = viewModel.pillCompactHeight

            viewModel.onWillShow?()

            viewModel.revealCompactWidth = startWidth
            viewModel.morphWidth  = startWidth
            viewModel.morphHeight = startHeight
            viewModel.morphRadius = 16
        } else {
            viewModel.morphWidth  = defaultCompactWidth
            viewModel.morphHeight = defaultCompactHeight
            viewModel.morphRadius = 16
        }
        viewModel.contentVisible = false

        panel.setFrame(panelFrame(), display: false)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif

        // Width springs open immediately — shape inhales.
        withAnimation(openSpring) {
            viewModel.morphWidth = targetWidth
        }
        // Height + radius follow 60ms later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            withAnimation(self.openSpring) {
                self.viewModel.morphHeight = targetHeight
                self.viewModel.morphRadius = 22
            }
        }
        // Content fades in as the morph settles, reaching full opacity near 0.63s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.viewModel.contentVisible = true
        }

        // Haptic feedback precisely when the open spring (stiffness 130) settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.61) {
            #if os(macOS)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            #endif
        }

        DispatchQueue.main.async         { [weak self] in self?.focusTextView() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.focusTextView() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) { [weak self] in self?.focusTextView() }
    }

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

    private weak var cachedTextView: NSTextView?

    private func focusTextView() {
        if let tv = cachedTextView, tv.window === panel {
            panel.makeFirstResponder(tv)
            return
        }
        guard let hv = hostingView else { return }
        func findTextView(_ view: NSView) -> NSTextView? {
            if let tv = view as? NSTextView, tv.isEditable {
                cachedTextView = tv
                return tv
            }
            for sub in view.subviews { if let tv = findTextView(sub) { return tv } }
            return nil
        }
        if let tv = findTextView(hv) {
            panel.makeFirstResponder(tv)
        }
    }

    func dismiss() {
        dismissWorkItem?.cancel()

        let compactW: CGFloat
        let compactH: CGFloat
        if viewModel.focusedNote != nil {
            let notchW: CGFloat = handoffNotchWidth()
            let sideW:  CGFloat = 62
            compactW = notchW + sideW * 2
            compactH = 34
        } else {
            compactW = defaultCompactWidth
            compactH = defaultCompactHeight
        }

        // Content hidden immediately — pill re-appears 360ms after close starts.
        viewModel.contentVisible = false

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        withAnimation(closeSpring) {
            viewModel.morphWidth  = compactW
            viewModel.morphHeight = compactH
            viewModel.morphRadius = 16
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.viewModel.morphWidth    = self.defaultCompactWidth
            self.viewModel.morphHeight   = self.defaultCompactHeight
            self.viewModel.morphRadius   = 16
            self.panel.alphaValue = 0
            self.panel.orderOut(nil)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: workItem)
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

import AppKit
import SwiftUI
import Combine

// MARK: - Panel

class FocusNotePanel: NSPanel {
    private var suppressSwiftUIResize = false

    // NSHostingView.updateAnimatedWindowSize calls setFrame during layout to resize
    // the window to SwiftUI's content size preference. This creates an infinite loop:
    // setFrame → layout → notification → windowDidLayout → updateAnimatedWindowSize → setFrame.
    // All frame management is explicit via setFrame/animator; re-entrant calls are wrong.
    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        guard !suppressSwiftUIResize else { return }
        suppressSwiftUIResize = true
        defer { suppressSwiftUIResize = false }
        super.setFrame(frameRect, display: displayFlag)
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        hasShadow = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

class FocusNotePillController {
    let panel: FocusNotePanel
    private var hosting: FirstMouseHostingView<FocusPillView>?
    private let viewModel: OverlayViewModel
    private let pillState = FocusPillState()
    private var cancellables = Set<AnyCancellable>()
    private var visibleFocusedNoteID: UUID?
    private var didPerformHoverHaptic = false
    private var barToPillWorkItem: DispatchWorkItem?

    private let notchH:    CGFloat = 34
    private let sideW:     CGFloat = 62
    private let hoverH:    CGFloat = 70
    private let expandedW: CGFloat = 370
    private let expandedH: CGFloat = 462
    private let fallbackNotchW: CGFloat = 154

    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel
        panel = FocusNotePanel()

        let hv = FirstMouseHostingView(rootView: FocusPillView(viewModel: viewModel, pillState: pillState, sideWidth: sideW))
        hv.wantsLayer = true
        hv.translatesAutoresizingMaskIntoConstraints = true
        hv.autoresizingMask = [.width, .height]
        hosting = hv
        panel.contentView = hv

        let dark = NSAppearance(named: .darkAqua)
        panel.appearance = dark
        hv.appearance = dark

        viewModel.$focusedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                if note == nil {
                    self.hidePill()
                } else if !self.viewModel.isVisible {
                    self.showPill()
                }
            }
            .store(in: &cancellables)

        // Bar-open is handled synchronously via viewModel.onWillShow (set below).
        // This sink only handles bar-close → schedule pill return.
        viewModel.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] barVisible in
                guard let self else { return }
                if !barVisible { self.schedulePillReturn() }
            }
            .store(in: &cancellables)

        // Wire the synchronous handoff hook so show() can hide the pill before the
        // overlay panel becomes visible — eliminating the async-tick gap.
        viewModel.onWillShow = { [weak self] in
            self?.hideForHandoff()
        }

        pillState.$isExpanded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in
                guard let self else { return }
                self.viewModel.pillIsExpanded = expanded
                // Compact height: always notchH — expanded pill's top strip is 34px.
                self.viewModel.pillCompactHeight = self.notchH
                guard self.panel.alphaValue > 0 else { return }
                self.animateFrame(
                    expanded: expanded,
                    duration: expanded ? 0.46 : 0.34
                )
            }
            .store(in: &cancellables)

        pillState.$isHovering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hovering in
                guard let self else { return }
                self.viewModel.pillCompactHeight = hovering ? self.hoverH : self.notchH
                guard self.panel.alphaValue > 0, !self.pillState.isExpanded else { return }
                if hovering && !self.didPerformHoverHaptic {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    self.didPerformHoverHaptic = true
                } else if !hovering {
                    self.didPerformHoverHaptic = false
                }
                self.animateFrame(
                    duration: hovering ? 0.22 : 0.18,
                    timing: CAMediaTimingFunction(controlPoints: 0.18, 0.86, 0.25, 1.0)
                )
            }
            .store(in: &cancellables)
    }

    private struct NotchMetrics {
        var screenFrame: CGRect
        var left: CGFloat
        var right: CGFloat

        var width: CGFloat { right - left }
        var centerX: CGFloat { (left + right) / 2 }
    }

    private func notchScreen() -> NSScreen? {
        if #available(macOS 12.0, *) {
            return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        }
        return NSScreen.main
    }

    private func notchMetrics() -> NotchMetrics? {
        guard let scr = notchScreen() else { return nil }
        let sf = scr.frame

        if #available(macOS 12.0, *),
           let leftArea = scr.auxiliaryTopLeftArea,
           let rightArea = scr.auxiliaryTopRightArea {
            let left = leftArea.maxX
            let right = rightArea.minX
            if right - left > 80 {
                return NotchMetrics(screenFrame: sf, left: left, right: right)
            }
        }

        let left = sf.midX - fallbackNotchW / 2
        return NotchMetrics(screenFrame: sf, left: left, right: left + fallbackNotchW)
    }

    private func notchOnlyFrame() -> CGRect {
        guard let metrics = notchMetrics() else { return .zero }
        return CGRect(
            x: metrics.left,
            y: metrics.screenFrame.maxY - notchH,
            width: metrics.width,
            height: notchH
        )
    }

    private func pillFrame(expanded: Bool? = nil) -> CGRect {
        guard let metrics = notchMetrics() else { return .zero }
        let sf = metrics.screenFrame
        let collapsedW = metrics.width + sideW * 2
        let collapsedX = metrics.left - sideW
        let isExpanded = expanded ?? pillState.isExpanded

        if isExpanded {
            return CGRect(
                x: metrics.centerX - expandedW / 2,
                y: sf.maxY - expandedH,
                width: expandedW,
                height: expandedH
            )
        } else {
            let height = pillState.isHovering ? hoverH : notchH
            return CGRect(x: collapsedX, y: sf.maxY - height, width: collapsedW, height: height)
        }
    }

    // Called by OverlayWindowController before opening so the overlay clip starts
    // at the real notch width instead of the default fallback.
    func notchWidth() -> CGFloat {
        notchMetrics()?.width ?? fallbackNotchW
    }

    private func showPill(fromBar: Bool = false) {
        barToPillWorkItem?.cancel()
        barToPillWorkItem = nil

        let noteID = viewModel.focusedNote?.id
        let isSameVisibleNote = panel.alphaValue > 0 && noteID == visibleFocusedNoteID
        visibleFocusedNoteID = noteID

        guard !isSameVisibleNote else {
            panel.orderFront(nil)
            return
        }

        didPerformHoverHaptic = false
        pillState.isExpanded = false
        pillState.isHovering = false

        if fromBar {
            let wasVisible = panel.alphaValue > 0
            panel.setFrame(pillFrame(expanded: false), display: false)
            panel.orderFront(nil)
            if wasVisible {
                // Pill was kept visible behind bar — just bring to front, no fade needed.
                panel.alphaValue = 1
            } else {
                // Pill was hidden (expanded handoff case) — fade in.
                panel.alphaValue = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.14
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.panel.animator().alphaValue = 1
                }
            }
        } else {
            panel.setFrame(notchOnlyFrame(), display: false)
            panel.alphaValue = 1
            panel.orderFront(nil)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.animateFrame(duration: 0.44, timing: CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.24, 1.0))
            }
        }
    }

    private func hidePill() {
        barToPillWorkItem?.cancel()
        barToPillWorkItem = nil
        visibleFocusedNoteID = nil
        didPerformHoverHaptic = false
        pillState.isExpanded = false
        pillState.isHovering = false
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    // Called synchronously from OverlayWindowController.show() before the overlay panel
    // becomes visible. For compact pill: keep visible behind bar — bar at progress=0
    // covers the exact same pixel footprint so there is no seam. For expanded pill:
    // hide instantly since its footprint doesn't match the bar's compact start shape.
    func hideForHandoff() {
        barToPillWorkItem?.cancel()
        barToPillWorkItem = nil
        didPerformHoverHaptic = false
        panel.setFrame(panel.frame, display: false)
        pillState.isHovering = false

        if pillState.isExpanded {
            // Expanded pill — hide immediately; bar starts at matching expanded dims.
            panel.alphaValue = 0
            panel.orderOut(nil)
            pillState.isExpanded = false
            visibleFocusedNoteID = nil
        } else {
            // Compact pill — keep visible. Bar opens on top, covering this surface.
            // visibleFocusedNoteID kept so schedulePillReturn uses isSameVisibleNote path.
            pillState.isExpanded = false
        }
    }

    private func schedulePillReturn() {
        barToPillWorkItem?.cancel()
        // Close spring (mass 0.85, stiffness 305) settles by ~0.28s. Fade pill in at 0.30s.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.viewModel.isVisible,
                  self.viewModel.focusedNote != nil else { return }
            self.showPill(fromBar: true)
        }
        barToPillWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36, execute: work)
    }

    private func animateFrame(
        expanded: Bool? = nil,
        duration: TimeInterval = 0.28,
        timing: CAMediaTimingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.86, 0.25, 1.0)
    ) {
        // Suppress mouse events during the frame animation. Changing the panel bounds
        // triggers SwiftUI tracking-area updates on every animation tick (because
        // proxy.size.height drives the surface height), which fires spurious onHover
        // enter/exit events and creates a hover oscillation loop.
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            panel.animator().setFrame(pillFrame(expanded: expanded), display: true)
        }, completionHandler: { [weak self] in
            self?.panel.ignoresMouseEvents = false
        })
    }
}

private let pillVoidBlack = Color(nsColor: NSColor(calibratedWhite: 0.015, alpha: 1.0))

private final class FocusPillState: ObservableObject {
    @Published var isExpanded = false
    @Published var isHovering = false
}

// MARK: - Root view

private struct FocusPillView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject var pillState: FocusPillState
    let sideWidth: CGFloat
    @State private var controlsRevealed = false
    @State private var textVisible = false
    @State private var shapeRadius: CGFloat = 16
    @State private var shapeBulge: CGFloat = 0
    @State private var shapeHeight: CGFloat = 34

    private var topHeight: CGFloat { 34 }
    private var pinPurple: Color { Color(red: 0.70, green: 0.55, blue: 1.0) }
    private var isCompact: Bool { !pillState.isExpanded }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LiquidNotchSurface(
                    bottomRadius: shapeRadius,
                    bottomBulge: shapeBulge
                )
                    .fill(pillVoidBlack)
                    .frame(height: pillState.isExpanded ? proxy.size.height : shapeHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .animation(.interpolatingSpring(mass: 0.92, stiffness: 170, damping: 27),
                               value: pillState.isExpanded)

                Rectangle()
                    .fill(pillVoidBlack)
                    .frame(height: 3)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                if pillState.isExpanded {
                    FocusPillExpandedContent(viewModel: viewModel, pillState: pillState, sideWidth: sideWidth)
                        .transition(.opacity)
                } else {
                    collapsedContent
                        .transition(.opacity)
                }
            }
        }
        .compositingGroup()
        .onAppear { revealControls() }
        .onChange(of: viewModel.focusedNote?.id) { _, _ in revealControls() }
        .colorScheme(.dark)
        .onHover { hovering in
            guard !pillState.isExpanded else { return }
            withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 220, damping: 26)) {
                pillState.isHovering = hovering
            }
        }
        .onChange(of: pillState.isHovering) { _, hovering in
            if hovering {
                // Match NSAnimationContext hover-in: duration 0.22s, same bezier.
                withAnimation(.timingCurve(0.18, 0.86, 0.25, 1.0, duration: 0.22)) {
                    shapeRadius = 20
                    shapeBulge  = 2.4
                    shapeHeight = 70
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                    withAnimation(.easeOut(duration: 0.14)) { textVisible = true }
                }
            } else {
                // Match NSAnimationContext hover-out: duration 0.18s, same bezier.
                // Hide text instantly so the collapsing surface clips cleanly — no
                // tall empty surface with mid-animation corners.
                textVisible = false
                withAnimation(.timingCurve(0.18, 0.86, 0.25, 1.0, duration: 0.18)) {
                    shapeRadius = 16
                    shapeBulge  = 0
                    shapeHeight = 34
                }
            }
        }
        .onChange(of: pillState.isExpanded) { _, expanded in
            withAnimation(.interpolatingSpring(mass: 0.92, stiffness: 170, damping: 27)) {
                shapeRadius = expanded ? 22 : (pillState.isHovering ? 20 : 16)
                shapeBulge  = expanded ? 0  : (pillState.isHovering ? 2.4 : 0)
                shapeHeight = expanded ? 34 : (pillState.isHovering ? 70 : 34)
            }
        }
    }

    private var collapsedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                iconGlyph(
                    systemName: "pin.fill",
                    accessibilityLabel: "Unpin focus note",
                    color: pinPurple,
                    opacity: 0.92
                )
                .frame(width: sideWidth, height: topHeight)
                .offset(x: controlsRevealed ? 0 : 16)
                .opacity(controlsRevealed ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.focusedNote = nil }

                Spacer(minLength: 0)

                iconGlyph(
                    systemName: "doc.text",
                    accessibilityLabel: "Open focus note",
                    color: .white,
                    opacity: 0.62
                )
                .frame(width: sideWidth, height: topHeight)
                .offset(x: controlsRevealed ? 0 : -16)
                .opacity(controlsRevealed ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { expandFocusNote() }
            }
            .frame(height: topHeight)

            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.36))
                Text(noteTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            .opacity(textVisible ? 1 : 0)
            .offset(y: textVisible ? 0 : -6)
            .allowsHitTesting(pillState.isHovering)
            .contentShape(Rectangle())
            .onTapGesture { expandFocusNote() }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.interpolatingSpring(mass: 0.82, stiffness: 220, damping: 24), value: controlsRevealed)
        .animation(.interpolatingSpring(mass: 0.82, stiffness: 185, damping: 29), value: pillState.isHovering)
        .contentShape(Rectangle())
    }

    private var noteTitle: String {
        viewModel.focusedNote?.blocks
            .first(where: { !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Focus Note"
    }

    private func iconGlyph(
        systemName: String,
        accessibilityLabel: String,
        color: Color,
        opacity: Double
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(color.opacity(opacity))
            .frame(width: sideWidth, height: topHeight)
            .accessibilityLabel(accessibilityLabel)
    }

    private func expandFocusNote() {
        guard !pillState.isExpanded else { return }
        withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 180, damping: 24)) {
            pillState.isExpanded = true
            pillState.isHovering = false
        }
    }

    private func revealControls() {
        controlsRevealed = false
        guard viewModel.focusedNote != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard isCompact, viewModel.focusedNote != nil else { return }
            withAnimation(.interpolatingSpring(mass: 0.78, stiffness: 230, damping: 21)) {
                controlsRevealed = true
            }
        }
    }
}

// MARK: - Shape: flat top, liquid bottom edge

private struct LiquidNotchSurface: Shape {
    var bottomRadius: CGFloat
    var bottomBulge: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, bottomBulge) }
        set {
            bottomRadius = newValue.first
            bottomBulge = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = max(1, rect.width)
        let h = max(1, rect.height)
        let r = min(bottomRadius, w / 2, h / 2)
        let bulge = min(bottomBulge, max(0, h - r) / 2)
        let bottomControlY = h - bulge

        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addArc(center: CGPoint(x: w - r, y: h - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addCurve(
            to: CGPoint(x: r, y: h),
            control1: CGPoint(x: w * 0.68, y: bottomControlY),
            control2: CGPoint(x: w * 0.32, y: bottomControlY)
        )
        p.addArc(center: CGPoint(x: r, y: h - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Expanded note editor

private struct FocusPillExpandedContent: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject var pillState: FocusPillState
    let sideWidth: CGFloat
    @State private var editingBlocks: [Block] = []
    @State private var saveTask: Task<Void, Never>?
    @State private var controlsEnabled = false
    @State private var showFormat = false
    @ObservedObject private var speech = SpeechManager.shared
    @State private var voicePrefix = ""

    private let pinPurple = Color(red: 0.70, green: 0.55, blue: 1.0)
    private let topHeight: CGFloat = 34
    private var note: Note? { viewModel.focusedNote }

    private var textBlocks: Binding<[Block]> {
        Binding(
            get: { editingBlocks.filter { $0.type != .table } },
            set: { newText in
                var merged = newText
                merged.append(contentsOf: editingBlocks.filter { $0.type == .table })
                editingBlocks = merged
            }
        )
    }

    private var tableIndices: [Int] {
        editingBlocks.indices.filter { editingBlocks[$0].type == .table }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(pinPurple.opacity(0.92))
                    .frame(width: sideWidth, height: topHeight)
                Spacer(minLength: 0)
                Image(systemName: "doc.text")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.white.opacity(0.62))
                    .frame(width: sideWidth, height: topHeight)
            }
            .frame(height: topHeight)

            HStack(spacing: 8) {
                Text(noteTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
                Spacer()
                Button {
                    guard controlsEnabled else { return }
                    withAnimation(.interpolatingSpring(mass: 0.88, stiffness: 190, damping: 25)) {
                        pillState.isExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!controlsEnabled)
                Button {
                    guard controlsEnabled else { return }
                    viewModel.focusedNote = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!controlsEnabled)
            }
            .frame(height: 34)
            .padding(.horizontal, 12)

            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    LibraryNoteTextEditor(blocks: textBlocks, isDark: true)
                        .frame(maxWidth: .infinity, minHeight: 160)
                    ForEach(tableIndices, id: \.self) { i in
                        LibraryStoredTableEditor(block: $editingBlocks[i])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: editingBlocks) { _, newBlocks in scheduleAutoSave(blocks: newBlocks) }

            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

            VStack(spacing: 0) {
                if showFormat {
                    PillFormatBar(blocks: $editingBlocks)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 4)
                }
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                            showFormat.toggle()
                        }
                    } label: {
                        Text("Aa")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(showFormat ? .white : .white.opacity(0.50))
                            .frame(width: 46, height: 32)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.90, pressedOpacity: 0.94))
                    Spacer()
                    pillMicButton
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            editingBlocks = note?.blocks ?? []
            controlsEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard pillState.isExpanded else { return }
                controlsEnabled = true
            }
        }
        .onChange(of: viewModel.focusedNote?.id) { _, _ in editingBlocks = note?.blocks ?? [] }
    }

    @ViewBuilder private var pillMicButton: some View {
        if speech.isRecording {
            Button(action: stopVoice) {
                HStack(spacing: 6) {
                    VoiceWaveformPill(level: speech.audioLevel)
                        .frame(width: 40, height: 18)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.82))
                }
                .frame(height: 32)
                .padding(.horizontal, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
            .transition(.opacity.animation(.easeInOut(duration: 0.08)))
        } else {
            Button(action: toggleVoice) {
                Image(systemName: "microphone.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.50))
                    .frame(width: 34, height: 32)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
                    )
            }
            .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.90, pressedOpacity: 0.94))
            .transition(.opacity.animation(.easeInOut(duration: 0.08)))
        }
    }

    private var noteTitle: String {
        note?.blocks
            .first(where: { !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Focus Note"
    }

    private func toggleVoice() {
        if speech.isRecording {
            stopVoice()
        } else {
            voicePrefix = ""
            speech.startRecording(
                onPartial: { partial in appendVoiceText(partial, isFinal: false) },
                onFinal: { final in
                    appendVoiceText(final, isFinal: true)
                    voicePrefix = ""
                }
            )
        }
    }

    private func stopVoice() {
        speech.stopRecording()
        voicePrefix = ""
    }

    private func appendVoiceText(_ text: String, isFinal: Bool) {
        guard !text.isEmpty else { return }
        if let lastIdx = editingBlocks.indices.last, editingBlocks[lastIdx].type == .paragraph {
            let prefix = voicePrefix.isEmpty ? "" : voicePrefix + " "
            editingBlocks[lastIdx].spans = [TextSpan(prefix + text)]
        } else {
            editingBlocks.append(Block(type: .paragraph, spans: [TextSpan(text)]))
        }
    }

    private func scheduleAutoSave(blocks: [Block]) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let note else { return }
            _ = viewModel.updateNote(note, blocks: blocks)
            if let updated = NoteStore.shared.note(for: note.id) {
                await MainActor.run { viewModel.focusedNote = updated }
            }
        }
    }
}

// MARK: - Pill format bar

private struct PillFormatBar: View {
    @Binding var blocks: [Block]

    var body: some View {
        HStack(spacing: 2) {
            fmtGroup {
                btn("B", bold: true)   { apply(.bold) }
                btn("I", italic: true) { apply(.italic) }
                btn("U", underline: true) { apply(.underline) }
                btn("S", strike: true) { apply(.strikethrough) }
            }
            sep
            fmtGroup {
                icon("list.bullet") { apply(.bulletList) }
                icon("list.number") { apply(.numberedList) }
                icon("checklist")   { apply(.taskList) }
                icon("text.quote")  { apply(.quote) }
            }
            sep
            fmtGroup {
                icon("chevron.left.forwardslash.chevron.right") { apply(.inlineCode) }
                icon("textformat.size") { apply(.heading) }
                tableMenu
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func fmtGroup<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 1) { c() }
    }

    private var sep: some View {
        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 13).padding(.horizontal, 3)
    }

    private var tableMenu: some View {
        Menu {
            Button("2 x 2") { insertTable(rows: 2, columns: 2) }
            Button("3 x 3") { insertTable(rows: 3, columns: 3) }
            Button("4 x 4") { insertTable(rows: 4, columns: 4) }
            Button("6 x 4") { insertTable(rows: 4, columns: 6) }
        } label: {
            Image(systemName: "tablecells")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func insertTable(rows: Int, columns: Int) {
        blocks.append(JottDraftTable(rows: rows, columns: columns).block)
    }

    private func apply(_ command: JottTextFormatCommand) {
        if let handler = JottTextFormattingRegistry.libraryFormatHandler,
           JottTextFormattingRegistry.activeTextView?.window != nil {
            if handler(command) { return }
        }
        if blocks.isEmpty {
            blocks.append(Block(type: .paragraph, spans: [TextSpan("")]))
        }
        switch command {
        case .bulletList:   blocks[0].type = .bulletItem
        case .numberedList: blocks[0].type = .numberedItem
        case .taskList:     blocks[0].type = .taskItem;   blocks[0].checked = false
        case .quote:        blocks[0].type = .quote
        case .heading:      blocks[0].type = .heading;    blocks[0].level = 1
        default: break
        }
    }

    private func btn(_ label: String, bold: Bool = false, italic: Bool = false,
                     underline: Bool = false, strike: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if bold      { Text(label).bold() }
                else if italic   { Text(label).italic() }
                else if underline { Text(label).underline() }
                else if strike   { Text(label).strikethrough() }
                else             { Text(label) }
            }
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.70))
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.92, pressedOpacity: 0.9))
    }

    private func icon(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.70))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.92, pressedOpacity: 0.9))
    }
}

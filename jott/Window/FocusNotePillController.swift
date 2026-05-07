import AppKit
import SwiftUI
import Combine

// MARK: - Panel

class FocusNotePanel: NSPanel {
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
        if #available(macOS 13.0, *) {
            hv.sizingOptions = []
        }
        hosting = hv
        panel.contentView = hv

        let dark = NSAppearance(named: .darkAqua)
        panel.appearance = dark
        hv.appearance = dark

        viewModel.$focusedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in note != nil ? self?.showPill() : self?.hidePill() }
            .store(in: &cancellables)

        pillState.$isExpanded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in
                guard let self, self.panel.alphaValue > 0 else { return }
                self.animateFrame(
                    expanded: expanded,
                    duration: expanded ? 0.46 : 0.34
                )
            }
            .store(in: &cancellables)

        pillState.$isHovering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hovering in
                guard let self, self.panel.alphaValue > 0,
                      !self.pillState.isExpanded else { return }
                if hovering && !self.didPerformHoverHaptic {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    self.didPerformHoverHaptic = true
                } else if !hovering {
                    self.didPerformHoverHaptic = false
                }
                self.hosting?.needsLayout = true
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
            return CGRect(x: collapsedX, y: sf.maxY - hoverH, width: collapsedW, height: hoverH)
        }
    }

    private func showPill() {
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
        panel.setFrame(notchOnlyFrame(), display: false)
        panel.alphaValue = 1
        panel.orderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.animateFrame(duration: 0.44, timing: CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.24, 1.0))
        }
    }

    private func hidePill() {
        visibleFocusedNoteID = nil
        didPerformHoverHaptic = false
        pillState.isExpanded = false
        pillState.isHovering = false
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    private func animateFrame(
        expanded: Bool? = nil,
        duration: TimeInterval = 0.28,
        timing: CAMediaTimingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.86, 0.25, 1.0)
    ) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            panel.animator().setFrame(pillFrame(expanded: expanded), display: true)
        }
    }
}

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

    private var topHeight: CGFloat { 34 }
    private var collapsedSurfaceHeight: CGFloat { pillState.isHovering ? 70 : topHeight }
    private var pinPurple: Color { Color(red: 0.70, green: 0.55, blue: 1.0) }
    private var isCompact: Bool { !pillState.isExpanded }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LiquidNotchSurface(
                    bottomRadius: pillState.isExpanded ? 18 : (pillState.isHovering ? 15 : 11),
                    bottomBulge: pillState.isExpanded ? 0 : (pillState.isHovering ? 2.4 : 0.6)
                )
                    .fill(Color.black)
                    .frame(height: pillState.isExpanded ? proxy.size.height : collapsedSurfaceHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .animation(.interpolatingSpring(mass: 0.92, stiffness: 170, damping: 27),
                               value: pillState.isExpanded)
                    .animation(.interpolatingSpring(mass: 0.82, stiffness: 185, damping: 29),
                               value: pillState.isHovering)

                Rectangle()
                    .fill(Color.black)
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
        .onAppear {
            revealControls()
        }
        .onChange(of: viewModel.focusedNote?.id) { _, _ in
            revealControls()
        }
        .colorScheme(.dark)
        .onHover { hovering in
            guard !pillState.isExpanded else { return }
            withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 220, damping: 26)) {
                pillState.isHovering = hovering
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
                    opacity: 0.92,
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
                    opacity: 0.62,
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
            .opacity(pillState.isHovering ? 1 : 0)
            .offset(y: pillState.isHovering ? 0 : -6)
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

        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addArc(center: CGPoint(x: w - r, y: h - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addCurve(
            to: CGPoint(x: r, y: h),
            control1: CGPoint(x: w * 0.68, y: h + bulge),
            control2: CGPoint(x: w * 0.32, y: h + bulge)
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
    @State private var newSubnoteText: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var controlsEnabled = false

    private let pinPurple = Color(red: 0.70, green: 0.55, blue: 1.0)
    private let topHeight: CGFloat = 34
    private var note: Note? { viewModel.focusedNote }
    private var subnotes: [Note] {
        guard let note else { return [] }
        return viewModel.subnotes(of: note.id)
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
                    pillState.isExpanded = false
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 18, height: 18)
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
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!controlsEnabled)
            }
            .frame(height: 34)
            .padding(.horizontal, 12)

            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

            LibraryNoteTextEditor(blocks: $editingBlocks, isDark: true)
                .frame(maxWidth: .infinity, minHeight: 180)
                .padding(.horizontal, 4)
                .onChange(of: editingBlocks) { _, newBlocks in scheduleAutoSave(blocks: newBlocks) }

            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

            subnotesSection
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

    private var subnotesSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SUBNOTES")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.28))
                .tracking(0.5)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ForEach(subnotes.prefix(3)) { subnote in
                HStack(spacing: 6) {
                    Circle().fill(Color.white.opacity(0.18)).frame(width: 3, height: 3)
                    Text(subnoteTitle(subnote))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
            }
            if subnotes.count > 3 {
                Text("+\(subnotes.count - 3) more")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.28))
                    .padding(.horizontal, 12)
            }

            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.28))
                TextField("New subnote...", text: $newSubnoteText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .textFieldStyle(.plain)
                    .onSubmit { commitSubnote() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var noteTitle: String {
        note?.blocks
            .first(where: { !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Focus Note"
    }

    private func subnoteTitle(_ subnote: Note) -> String {
        subnote.blocks
            .first(where: { !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Untitled"
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

    private func commitSubnote() {
        let text = newSubnoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let note else { return }
        viewModel.createSubnote(parentId: note.id, text: text)
        newSubnoteText = ""
    }
}

import SwiftUI

// MARK: - Notification

extension Notification.Name {
    static let jottOpenNoteInCanvas = Notification.Name("com.casualhermit.jott.openNoteInCanvas")
}

// MARK: - Canvas Root

private struct CanvasLayout {
    let positions: [UUID: CGPoint]
    let size: CGSize
}

private enum CanvasDragState: Equatable {
    case inactive
    case pressing
    case dragging(CGSize)

    var isDragging: Bool {
        if case .dragging = self { return true }
        return false
    }
    var isActive: Bool {
        switch self { case .inactive: return false; default: return true }
    }
}

struct ClusterCanvasView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject private var store = NoteStore.shared

    var selectedNoteId: UUID? = nil
    var onSelectNote: (Note) -> Void = { _ in }
    var onClearSelection: () -> Void = {}

    private var isDark: Bool { viewModel.isDarkMode }
    private let pagePadding: CGFloat = 60

    @State private var manualOffsets: [UUID: CGSize] = [:]
    @State private var draggedNoteId: UUID? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var hoveredNoteId: UUID? = nil
    @State private var sidebarNote: Note? = nil
    @State private var sidebarExpanded: Bool = false

    private var allNotes: [Note] { store.allNotes() }

    private func canvasLayout(for availableWidth: CGFloat) -> CanvasLayout {
        let notes = allNotes
        guard !notes.isEmpty else {
            return CanvasLayout(positions: [:], size: CGSize(width: availableWidth, height: 560))
        }

        var positions: [UUID: CGPoint] = [:]
        let goldenAngle: CGFloat = 2.399963
        let spiralStep: CGFloat = 52
        let cx: CGFloat = max(availableWidth / 2, pagePadding + 200)
        let cy: CGFloat = pagePadding + 120

        for (i, note) in notes.enumerated() {
            let fi = CGFloat(i)
            if fi == 0 {
                positions[note.id] = CGPoint(x: cx, y: cy)
            } else {
                let radius = spiralStep * sqrt(fi)
                let angle  = fi * goldenAngle
                positions[note.id] = CGPoint(
                    x: cx + radius * Foundation.cos(angle),
                    y: cy + radius * Foundation.sin(angle)
                )
            }
        }

        let xs = positions.values.map(\.x)
        let ys = positions.values.map(\.y)
        let canvasW = max(availableWidth, (xs.max() ?? 0) + pagePadding)
        let canvasH = max(560, (ys.max() ?? 0) + pagePadding * 2)
        return CanvasLayout(positions: positions, size: CGSize(width: canvasW, height: canvasH))
    }

    private func resolvedPositions(base: [UUID: CGPoint]) -> [UUID: CGPoint] {
        var result = base
        for (id, offset) in manualOffsets {
            guard let point = result[id] else { continue }
            result[id] = CGPoint(x: point.x + offset.width, y: point.y + offset.height)
        }
        if let dragId = draggedNoteId, let point = result[dragId] {
            result[dragId] = CGPoint(
                x: point.x + dragTranslation.width,
                y: point.y + dragTranslation.height
            )
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            canvasContent
            if let note = sidebarNote {
                CanvasNodeSidebar(
                    note: note,
                    isDark: isDark,
                    expanded: $sidebarExpanded,
                    onClose: {
                        withAnimation(JottMotion.content) { sidebarNote = nil }
                        onClearSelection()
                    },
                    onOpenFull: { onSelectNote(note) }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(JottMotion.content, value: sidebarNote?.id)
    }

    private var canvasContent: some View {
        GeometryReader { proxy in
            let layout = canvasLayout(for: proxy.size.width)
            let positions = resolvedPositions(base: layout.positions)

            ZStack(alignment: .topTrailing) {
                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(width: layout.size.width, height: layout.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(JottMotion.content) { sidebarNote = nil }
                                onClearSelection()
                            }

                        if allNotes.isEmpty {
                            emptyState
                                .frame(width: layout.size.width, height: layout.size.height)
                        } else {
                            ForEach(allNotes) { note in
                                if let position = positions[note.id] {
                                    CanvasNode(
                                        note: note,
                                        isDark: isDark,
                                        isSelected: selectedNoteId == note.id,
                                        onTap: {
                                            withAnimation(JottMotion.content) {
                                                sidebarNote = note
                                                sidebarExpanded = false
                                            }
                                            onSelectNote(note)
                                        },
                                        onDrag: { translation in
                                            draggedNoteId = note.id
                                            dragTranslation = translation
                                        },
                                        onDragEnd: { translation in
                                            let current = manualOffsets[note.id] ?? .zero
                                            if translation != .zero {
                                                manualOffsets[note.id] = CGSize(
                                                    width: current.width + translation.width,
                                                    height: current.height + translation.height
                                                )
                                            }
                                            draggedNoteId = nil
                                            dragTranslation = .zero
                                        },
                                        onEdit: { onSelectNote(note) },
                                        onHoverChange: { isHovered in
                                            hoveredNoteId = isHovered ? note.id : nil
                                        }
                                    )
                                    .position(position)
                                    .animation(
                                        draggedNoteId == note.id ? nil : JottMotion.connect,
                                        value: position
                                    )
                                    .zIndex(selectedNoteId == note.id ? 20
                                            : draggedNoteId == note.id ? 10
                                            : hoveredNoteId == note.id ? 5 : 0)
                                }
                            }
                        }
                    }
                }

                if !allNotes.isEmpty {
                    Button {
                        withAnimation(JottMotion.connect) { manualOffsets.removeAll() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Organize")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.primary.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(isDark ? Color.white.opacity(0.038) : Color.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.jottBorder.opacity(isDark ? 0.50 : 0.44), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 14)
                    .padding(.trailing, 16)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary.opacity(0.15))
            Text("No notes yet")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.24))
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

// MARK: - Note title helper

private extension Note {
    var noteFirstLine: String {
        text.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? "Untitled"
    }
}

// MARK: - Canvas Node Sidebar

private struct CanvasNodeSidebar: View {
    let note: Note
    let isDark: Bool
    @Binding var expanded: Bool
    let onClose: () -> Void
    let onOpenFull: () -> Void

    private var title: String { note.noteFirstLine }

    private var bodyText: String {
        let lines = note.text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard lines.count > 1 else { return "" }
        return lines.dropFirst().joined(separator: "\n")
    }

    private var accent: Color {
        let palette: [(Double, Double, Double)] = [
            (0.56, 0.44, 0.84), (0.36, 0.66, 0.82), (0.78, 0.50, 0.36),
            (0.40, 0.76, 0.58), (0.84, 0.46, 0.62), (0.58, 0.74, 0.36),
        ]
        let h = abs(note.id.uuidString.utf8.reduce(0) { ($0 &* 1_000_003) &+ Int($1) })
        let (r, g, b) = palette[h % palette.count]
        return Color(red: r, green: g, blue: b)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 3)

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Button(action: onOpenFull) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help("Open full note")

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.40))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().opacity(isDark ? 0.10 : 0.07)

            // Body
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if !bodyText.isEmpty {
                        Text(bodyText)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.primary.opacity(0.72))
                            .lineSpacing(3)
                            .lineLimit(expanded ? nil : 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !note.tags.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(note.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(accent.opacity(0.84))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(accent.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider().opacity(isDark ? 0.10 : 0.07)

            // Expand toggle
            Button {
                withAnimation(JottMotion.content) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                    Text(expanded ? "Collapse" : "Show more")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundColor(.secondary.opacity(0.42))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .frame(width: expanded ? 320 : 240)
        .background(isDark
            ? Color(red: 0.10, green: 0.08, blue: 0.14).opacity(0.98)
            : Color(red: 0.98, green: 0.98, blue: 0.99).opacity(0.98))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(isDark ? 0.09 : 0.06))
                .frame(width: 1)
        }
        .animation(JottMotion.content, value: expanded)
    }
}

// MARK: - Pane Divider (resize handle, shared with LibraryView)

struct PaneDivider: View {
    var isDark: Bool = false
    let onDrag: (CGFloat) -> Void
    let onEnd:  () -> Void

    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(isHovered
                  ? Color(red: 0.56, green: 0.44, blue: 0.84).opacity(0.28)
                  : Color.primary.opacity(isDark ? 0.10 : 0.07))
            .frame(width: 4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in onDrag(v.translation.width) }
                    .onEnded   { _ in onEnd() }
            )
            .onHover { h in
                withAnimation(JottMotion.micro) { isHovered = h }
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .animation(JottMotion.micro, value: isHovered)
    }
}

// MARK: - Canvas Node

struct CanvasNode: View {
    let note: Note
    let isDark: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnd: (CGSize) -> Void
    var onEdit: () -> Void = {}
    var onHoverChange: (Bool) -> Void = { _ in }

    @State private var hovered = false
    @GestureState private var dragState: CanvasDragState = .inactive

    private var accent: Color {
        let palette: [(Double, Double, Double)] = [
            (0.56, 0.44, 0.84), (0.36, 0.66, 0.82), (0.78, 0.50, 0.36),
            (0.40, 0.76, 0.58), (0.84, 0.46, 0.62), (0.58, 0.74, 0.36),
        ]
        let h = abs(note.id.uuidString.utf8.reduce(0) { ($0 &* 1_000_003) &+ Int($1) })
        let (r, g, b) = palette[h % palette.count]
        return Color(red: r, green: g, blue: b)
    }

    private var dotFill: Color {
        isSelected
            ? accent.opacity(isDark ? 0.92 : 0.80)
            : accent.opacity(isDark ? 0.46 : 0.38)
    }

    private var dotBorder: Color {
        isSelected
            ? Color.white.opacity(0.80)
            : accent.opacity(hovered ? 0.76 : 0.42)
    }

    private var noteTitle: String {
        note.text
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? "Untitled"
    }

    private var dot: some View {
        let sz: CGFloat = isSelected ? 14 : 10
        let radius: CGFloat = isSelected ? 4 : 3
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(dotFill)
            .frame(width: sz, height: sz)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(dotBorder, lineWidth: isSelected ? 2 : 1.5)
            )
            .shadow(color: accent.opacity(isSelected ? 0.55 : 0.12),
                    radius: isSelected ? 7 : 2, y: 0)
    }

    private var hoverTooltip: some View {
        Text(noteTitle)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(isDark ? .white.opacity(0.88) : Color(red: 0.20, green: 0.13, blue: 0.38))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isDark
                        ? Color(red: 0.15, green: 0.12, blue: 0.22).opacity(0.97)
                        : Color.white.opacity(0.97))
            )
            .overlay(Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1))
            .shadow(color: .black.opacity(isDark ? 0.38 : 0.10), radius: 6, y: 2)
            .fixedSize()
            .allowsHitTesting(false)
    }

    var body: some View {
        let isLifted = dragState.isActive
        let scale: CGFloat = isLifted ? 1.35 : hovered ? 1.28 : 1.0

        let holdToDrag = LongPressGesture(minimumDuration: 0.10)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($dragState) { value, state, _ in
                switch value {
                case .first(true):
                    state = .pressing
                case .second(true, let d):
                    state = .dragging(d?.translation ?? .zero)
                default:
                    break
                }
            }
            .onChanged { value in
                if case .second(true, let d) = value {
                    onDrag(d?.translation ?? .zero)
                }
            }
            .onEnded { value in
                if case .second(_, let d) = value { onDragEnd(d?.translation ?? .zero) }
                else { onDragEnd(.zero) }
            }

        ZStack {
            Color.clear.frame(width: 32, height: 32)
            dot
            if case .pressing = dragState {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(accent.opacity(0.50), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if hovered && !dragState.isDragging {
                hoverTooltip
                    .offset(y: -24)
                    .transition(.opacity.animation(.easeOut(duration: 0.08)))
            }
        }
        .scaleEffect(scale)
        .gesture(holdToDrag)
        .onTapGesture(count: 2) { onEdit() }
        .onTapGesture(count: 1) { onTap() }
        .contextMenu {
            Button { onEdit() } label: {
                Label("Open Note", systemImage: "arrow.right.square")
            }
        }
        .animation(JottMotion.micro, value: hovered)
        .animation(JottMotion.micro, value: isSelected)
        .animation(JottMotion.micro, value: isLifted)
        .onHover { h in
            withAnimation(JottMotion.micro) { hovered = h }
            onHoverChange(h)
            if h { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
    }
}

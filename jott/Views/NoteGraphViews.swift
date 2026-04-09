import SwiftUI

private extension Note {
    var jottGraphTitle: String {
        let lines = text.components(separatedBy: "\n")
        return lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "Untitled"
    }
}

private struct JottGraphPlacement: Identifiable {
    let note: Note
    let point: CGPoint

    var id: UUID { note.id }
}

private struct JottGraphCanvas: View {
    let notes: [Note]
    let selectedNote: Note?
    let isDarkMode: Bool
    let onSelect: (Note) -> Void

    private let nodeSize = CGSize(width: 18, height: 12)
    private let hitSize = CGSize(width: 34, height: 28)
    private let horizontalSpacing: CGFloat = 82
    private let verticalSpacing: CGFloat = 58

    var body: some View {
        GeometryReader { proxy in
            let placements = graphPlacements(in: proxy.size)
            let pointMap = Dictionary(uniqueKeysWithValues: placements.map { ($0.note.id, $0.point) })

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDarkMode ? Color.white.opacity(0.012) : Color.white.opacity(0.84))

                ForEach(placements) { placement in
                    JottGraphNodeButton(
                        note: placement.note,
                        isSelected: placement.note.id == selectedNote?.id,
                        isDarkMode: isDarkMode,
                        nodeSize: nodeSize,
                        hitSize: hitSize,
                        onTap: { onSelect(placement.note) }
                    )
                    .position(placement.point)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.jottBorder.opacity(0.50), lineWidth: 1)
            )
        }
    }

    private func orderedNotes() -> [Note] {
        let selectedID = selectedNote?.id
        return notes.sorted { lhs, rhs in
            if lhs.id == selectedID { return true }
            if rhs.id == selectedID { return false }
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    }

    private func graphPlacements(in size: CGSize) -> [JottGraphPlacement] {
        let ordered = orderedNotes()
        guard !ordered.isEmpty else { return [] }

        let horizontalPadding = max(28, hitSize.width / 2 + 8)
        let usableWidth = max(size.width - horizontalPadding * 2, horizontalSpacing)
        let maxColumns = max(1, Int(floor(usableWidth / horizontalSpacing)))
        let columnCount = min(maxColumns, max(1, Int(ceil(sqrt(Double(ordered.count))))))
        let rowCount = Int(ceil(Double(ordered.count) / Double(columnCount)))

        let totalWidth = CGFloat(max(0, columnCount - 1)) * horizontalSpacing
        let totalHeight = CGFloat(max(0, rowCount - 1)) * verticalSpacing
        let startX = (size.width - totalWidth) / 2
        let startY = (size.height - totalHeight) / 2

        return ordered.enumerated().map { index, note in
            let row = index / columnCount
            let column = index % columnCount
            let point = CGPoint(
                x: startX + CGFloat(column) * horizontalSpacing,
                y: startY + CGFloat(row) * verticalSpacing
            )
            return JottGraphPlacement(note: note, point: point)
        }
    }
}

struct JottNetworkGraphView: View {
    let notes: [Note]
    let selectedNote: Note?
    let isDarkMode: Bool
    let onSelect: (Note) -> Void

    var body: some View {
        JottGraphCanvas(
            notes: notes,
            selectedNote: selectedNote,
            isDarkMode: isDarkMode,
            onSelect: onSelect
        )
    }
}


private struct JottGraphNodeButton: View {
    let note: Note
    let isSelected: Bool
    let isDarkMode: Bool
    let nodeSize: CGSize
    let hitSize: CGSize
    let onTap: () -> Void

    @State private var hovered = false

    private var fillColor: Color {
        if isSelected {
            return isDarkMode
                ? Color(red: 0.56, green: 0.44, blue: 0.84).opacity(0.92)
                : Color(red: 0.56, green: 0.44, blue: 0.84).opacity(0.76)
        }

        return isDarkMode
            ? Color(red: 0.42, green: 0.32, blue: 0.68).opacity(0.72)
            : Color(red: 0.58, green: 0.48, blue: 0.86).opacity(0.58)
    }

    private var borderColor: Color {
        isSelected
            ? Color(red: 0.82, green: 0.76, blue: 0.98).opacity(0.88)
            : Color(red: 0.72, green: 0.64, blue: 0.94).opacity(hovered ? 0.78 : 0.52)
    }

    private var titleBubbleFill: Color {
        isDarkMode
            ? Color(red: 0.19, green: 0.16, blue: 0.28).opacity(0.96)
            : Color(red: 0.97, green: 0.95, blue: 0.995).opacity(0.98)
    }

    private var titleBubbleText: Color {
        isDarkMode
            ? Color(red: 0.93, green: 0.91, blue: 0.99)
            : Color(red: 0.33, green: 0.24, blue: 0.52)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fillColor)
                    .frame(width: nodeSize.width, height: nodeSize.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )

                if hovered {
                    Text(note.jottGraphTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(titleBubbleText)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(titleBubbleFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(borderColor.opacity(0.72), lineWidth: 1)
                        )
                        .fixedSize()
                        .offset(y: -28)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                }
            }
            .frame(width: hitSize.width, height: hitSize.height)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .scaleEffect(hovered ? 1.02 : 1.0)
        .animation(JottMotion.micro, value: hovered)
        .onHover { isHovering in
            withAnimation(JottMotion.micro) {
                hovered = isHovering
            }
        }
    }
}

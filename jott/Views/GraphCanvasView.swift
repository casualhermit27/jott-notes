import SwiftUI

// MARK: - Graph Canvas Root

struct GraphCanvasView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject private var store = NoteStore.shared

    private var isDark: Bool { viewModel.isDarkMode }
    private var allNotes: [Note] { store.allNotes() }
    private var clusters: [Cluster] { store.clusters }

    // MARK: Layout

    /// Deterministically positions every note on the 3600×2800 canvas.
    /// Clustered notes are laid out inside their cluster rect;
    /// unassigned notes occupy a dedicated region.
    private var nodePositions: [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]

        let headerH: CGFloat = 42
        let hPad:    CGFloat = 36
        let hStep:   CGFloat = 72
        let vStep:   CGFloat = 54

        for cluster in clusters {
            let clusterNotes = allNotes
                .filter { $0.clusterId == cluster.id }
                .sorted { $0.modifiedAt > $1.modifiedAt }
            let cols = max(1, Int(floor((cluster.width - hPad * 2 + hStep) / hStep)))
            for (i, note) in clusterNotes.enumerated() {
                let x = cluster.x + hPad + CGFloat(i % cols) * hStep
                let y = cluster.y + headerH + 18 + CGFloat(i / cols) * vStep
                result[note.id] = CGPoint(x: x, y: y)
            }
        }

        let unassigned = allNotes
            .filter { $0.clusterId == nil }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        let uCols: Int = 6
        let uH:   CGFloat = 90
        let uV:   CGFloat = 70
        let originX: CGFloat = 60
        let originY: CGFloat = 80
        for (i, note) in unassigned.enumerated() {
            let x = originX + CGFloat(i % uCols) * uH
            let y = originY + CGFloat(i / uCols) * uV
            result[note.id] = CGPoint(x: x, y: y)
        }

        return result
    }

    // MARK: Body

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            graphCanvas
        }
        .background(isDark
            ? Color(red: 0.095, green: 0.095, blue: 0.10)
            : Color(red: 0.972, green: 0.972, blue: 0.976))
    }

    // MARK: Canvas content

    private var graphCanvas: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: 3600, height: 2800)
                .contentShape(Rectangle())

            // Cluster frames
            ForEach(clusters) { cluster in
                GraphClusterFrame(cluster: cluster, isDark: isDark)
                    .frame(width: cluster.width, height: cluster.height)
                    .offset(x: cluster.x, y: cluster.y)
            }

            // Note nodes
            ForEach(allNotes) { note in
                if let pos = nodePositions[note.id] {
                    GraphNodeView(
                        note: note,
                        isSelected: false,
                        isDark: isDark
                    ) { }
                    .position(pos)
                }
            }

            // Empty state
            if allNotes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.secondary.opacity(0.18))
                    Text("No notes yet")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.28))
                    Text("Capture something and it will appear here.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.20))
                }
                .frame(width: 3600, height: 2800)
            }
        }
    }

}

// MARK: - Cluster Frame

private struct GraphClusterFrame: View {
    let cluster: Cluster
    let isDark: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cluster.tintColor.opacity(isDark ? 0.048 : 0.038))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(cluster.tintColor.opacity(0.22), lineWidth: 1)
                )

            HStack(spacing: 5) {
                Circle()
                    .fill(cluster.tintColor)
                    .frame(width: 6, height: 6)
                Text(cluster.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(cluster.tintColor.opacity(0.80))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Graph Node View

private struct GraphNodeView: View {
    let note: Note
    let isSelected: Bool
    let isDark: Bool
    let onTap: () -> Void

    @State private var hovered = false

    private let nodeW: CGFloat = 18
    private let nodeH: CGFloat = 12
    private let hitW:  CGFloat = 34
    private let hitH:  CGFloat = 28

    private var nodeFill: Color {
        isSelected
            ? Color(red: 0.56, green: 0.44, blue: 0.84).opacity(isDark ? 0.92 : 0.76)
            : Color(red: 0.56, green: 0.44, blue: 0.84).opacity(isDark ? 0.58 : 0.48)
    }

    private var nodeBorder: Color {
        isSelected
            ? Color(red: 0.82, green: 0.76, blue: 0.98).opacity(0.88)
            : Color(red: 0.72, green: 0.64, blue: 0.94).opacity(hovered ? 0.80 : 0.48)
    }

    private var bubbleFill: Color {
        isDark
            ? Color(red: 0.19, green: 0.16, blue: 0.28).opacity(0.96)
            : Color(red: 0.97, green: 0.95, blue: 0.995).opacity(0.98)
    }

    private var bubbleText: Color {
        isDark
            ? Color(red: 0.93, green: 0.91, blue: 0.99)
            : Color(red: 0.33, green: 0.24, blue: 0.52)
    }

    private var noteTitle: String {
        note.text
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? "Untitled"
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .top) {
                // Node box
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(nodeFill)
                    .frame(width: nodeW, height: nodeH)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(nodeBorder, lineWidth: 1)
                    )
                    .shadow(color: nodeFill.opacity(isSelected ? 0.45 : 0), radius: 4, y: 1)

                // Hover title bubble
                if hovered || isSelected {
                    Text(noteTitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(bubbleText)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(bubbleFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(nodeBorder.opacity(0.64), lineWidth: 1)
                        )
                        .fixedSize()
                        .offset(y: -26)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                }
            }
            .frame(width: hitW, height: hitH)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .scaleEffect(hovered ? 1.05 : 1.0)
        .animation(JottMotion.micro, value: hovered)
        .animation(JottMotion.micro, value: isSelected)
        .onHover { h in withAnimation(JottMotion.micro) { hovered = h } }
    }
}

// MARK: - Breadcrumb Bar

struct BreadcrumbBar: View {
    let crumbs: [Note]
    let isDark: Bool
    /// Called with the note and the index it occupied (trail will be trimmed to that index)
    let onSelect: (Note, Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.left.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.38))
                    .padding(.leading, 14)

                ForEach(Array(crumbs.enumerated()), id: \.element.id) { idx, note in
                    Button {
                        onSelect(note, idx)
                    } label: {
                        Text(crumbTitle(note))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(isDark
                                ? Color(red: 0.72, green: 0.64, blue: 0.94)
                                : Color(red: 0.42, green: 0.30, blue: 0.68))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(red: 0.56, green: 0.44, blue: 0.84)
                                        .opacity(isDark ? 0.14 : 0.07))
                            )
                    }
                    .buttonStyle(.plain)

                    if idx < crumbs.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.36))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(height: 36)
    }

    private func crumbTitle(_ note: Note) -> String {
        note.text
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? "Untitled"
    }
}

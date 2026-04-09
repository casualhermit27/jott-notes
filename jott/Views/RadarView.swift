import SwiftUI

// MARK: - Radar View

/// On-demand radial relationship view.
/// Appears when a note node is selected on the GraphCanvasView.
/// Center = selected note, surrounding = direct connections.
/// Clicking a surrounding node navigates to it and pushes the current note to breadcrumbs.
struct RadarView: View {
    let note: Note
    let connectedNotes: [Note]
    let isDark: Bool
    let onSelectNote: (Note) -> Void
    let onDismiss: () -> Void

    // Only show up to 10 connections to keep the radar uncluttered
    private var visibleConnections: [Note] { Array(connectedNotes.prefix(10)) }

    private let radarRadius:  CGFloat = 168
    private let canvasSize:   CGFloat = 520

    private var center: CGPoint { CGPoint(x: canvasSize / 2, y: canvasSize / 2) }

    var body: some View {
        ZStack {
            // ── Backdrop ────────────────────────────────────────────────────
            Rectangle()
                .fill(isDark
                    ? Color.black.opacity(0.42)
                    : Color.black.opacity(0.20))
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // ── Radar canvas ────────────────────────────────────────────────
            ZStack {
                // Outer ring hint
                Circle()
                    .strokeBorder(
                        Color(red: 0.56, green: 0.44, blue: 0.84).opacity(isDark ? 0.10 : 0.07),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 6])
                    )
                    .frame(width: radarRadius * 2, height: radarRadius * 2)

                // Spoke lines
                if !visibleConnections.isEmpty {
                    Canvas { ctx, size in
                        let c = CGPoint(x: size.width / 2, y: size.height / 2)
                        for i in 0 ..< visibleConnections.count {
                            let angle = spokeAngle(i)
                            let end = CGPoint(
                                x: c.x + cos(angle) * radarRadius,
                                y: c.y + sin(angle) * radarRadius
                            )
                            var path = Path()
                            path.move(to: c)
                            path.addLine(to: end)
                            ctx.stroke(
                                path,
                                with: .color(Color(red: 0.56, green: 0.44, blue: 0.84)
                                    .opacity(isDark ? 0.28 : 0.20)),
                                style: StrokeStyle(lineWidth: 1, lineCap: .round)
                            )
                        }
                    }
                    .frame(width: canvasSize, height: canvasSize)
                    .allowsHitTesting(false)
                }

                // Connected note nodes
                ForEach(Array(visibleConnections.enumerated()), id: \.element.id) { i, connected in
                    RadarSpokeNode(note: connected, isDark: isDark) {
                        onSelectNote(connected)
                    }
                    .offset(
                        x: cos(spokeAngle(i)) * radarRadius,
                        y: sin(spokeAngle(i)) * radarRadius
                    )
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.7, anchor: .center))
                            .animation(JottMotion.content.delay(Double(i) * 0.025))
                    )
                }

                // Center note card
                RadarCenterCard(note: note, isDark: isDark, onDismiss: onDismiss)
            }
            .frame(width: canvasSize, height: canvasSize)
        }
    }

    private func spokeAngle(_ index: Int) -> CGFloat {
        let total = max(1, visibleConnections.count)
        return CGFloat(index) / CGFloat(total) * 2 * .pi - .pi / 2
    }
}

// MARK: - Center Card

private struct RadarCenterCard: View {
    let note: Note
    let isDark: Bool
    let onDismiss: () -> Void

    @State private var hovered = false

    private var title: String {
        note.text
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? "Untitled"
    }

    private var preview: String {
        let lines = note.text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard lines.count > 1 else { return "" }
        return lines.dropFirst().prefix(2).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Circle()
                    .fill(Color(red: 0.56, green: 0.44, blue: 0.84).opacity(0.72))
                    .frame(width: 7, height: 7)
                    .padding(.trailing, 6)

                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(isDark ? .white.opacity(0.90) : Color(red: 0.20, green: 0.14, blue: 0.36))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.50))
                        .frame(width: 20, height: 20)
                        .background(
                            Circle().fill(Color.secondary.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, preview.isEmpty ? 13 : 8)

            if !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.60))
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            // Tags
            if !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 0.56, green: 0.44, blue: 0.84).opacity(0.72))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.56, green: 0.44, blue: 0.84).opacity(isDark ? 0.12 : 0.08))
                            )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 210)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDark
                    ? Color(red: 0.15, green: 0.13, blue: 0.22).opacity(0.98)
                    : Color(red: 0.99, green: 0.97, blue: 1.00).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Color(red: 0.56, green: 0.44, blue: 0.84).opacity(isDark ? 0.52 : 0.32),
                    lineWidth: 1.5
                )
        )
        .shadow(
            color: Color(red: 0.56, green: 0.44, blue: 0.84).opacity(isDark ? 0.22 : 0.10),
            radius: 18, y: 4
        )
        .scaleEffect(hovered ? 1.02 : 1.0)
        .animation(JottMotion.micro, value: hovered)
        .onHover { h in withAnimation(JottMotion.micro) { hovered = h } }
    }
}

// MARK: - Spoke Node

private struct RadarSpokeNode: View {
    let note: Note
    let isDark: Bool
    let onTap: () -> Void

    @State private var hovered = false

    private let nodeW: CGFloat = 18
    private let nodeH: CGFloat = 12
    private let hitW:  CGFloat = 36
    private let hitH:  CGFloat = 36

    private var title: String {
        note.text
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? "Untitled"
    }

    private var nodeFill: Color {
        Color(red: 0.56, green: 0.44, blue: 0.84).opacity(isDark ? 0.60 : 0.50)
    }

    private var nodeBorder: Color {
        Color(red: 0.72, green: 0.64, blue: 0.94).opacity(hovered ? 0.84 : 0.52)
    }

    private var labelFill: Color {
        isDark
            ? Color(red: 0.18, green: 0.15, blue: 0.26).opacity(0.95)
            : Color(red: 0.97, green: 0.95, blue: 1.00).opacity(0.97)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Always show label in radar (not just on hover)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(isDark
                        ? Color(red: 0.88, green: 0.84, blue: 0.98)
                        : Color(red: 0.33, green: 0.24, blue: 0.52))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(labelFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(nodeBorder.opacity(0.55), lineWidth: 1)
                    )
                    .fixedSize()

                // Node box
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(nodeFill)
                    .frame(width: nodeW, height: nodeH)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(nodeBorder, lineWidth: 1)
                    )
            }
            .frame(width: hitW, height: hitH)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .scaleEffect(hovered ? 1.08 : 1.0)
        .animation(JottMotion.micro, value: hovered)
        .onHover { h in withAnimation(JottMotion.micro) { hovered = h } }
    }
}

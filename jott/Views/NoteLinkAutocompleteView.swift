import SwiftUI

/// Inline [[ autocomplete dropdown shown inside JottCaptureView.
struct NoteLinkAutocompleteView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.linkCandidates.enumerated()), id: \.element.id) { idx, note in
                Button(action: { viewModel.selectLinkCandidate(note) }) {
                    HStack(spacing: 10) {
                        if idx == viewModel.selectedLinkIndex {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.jottGreen.opacity(0.8))
                                .frame(width: 3, height: 18)
                        } else {
                            Color.clear.frame(width: 3, height: 18)
                        }
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.jottGreen.opacity(0.75))
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(titleLine(note))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            if let snippet = snippetLine(note) {
                                Text(snippet)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if idx == viewModel.selectedLinkIndex {
                            Text("↵")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        idx == viewModel.selectedLinkIndex
                            ? Color.jottGreen.opacity(0.07)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .top).combined(with: .opacity))

                if idx < viewModel.linkCandidates.count - 1 {
                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.35)
                }
            }

            // Footer hint
            Divider().opacity(0.2)
            HStack(spacing: 0) {
                Text("↑↓")
                    .foregroundColor(.secondary.opacity(0.55))
                Text(" navigate  ")
                    .foregroundColor(.secondary.opacity(0.35))
                Text("↵")
                    .foregroundColor(.secondary.opacity(0.55))
                Text(" link  ")
                    .foregroundColor(.secondary.opacity(0.35))
                Text("esc")
                    .foregroundColor(.secondary.opacity(0.55))
                Text(" cancel")
                    .foregroundColor(.secondary.opacity(0.35))
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.08), value: viewModel.selectedLinkIndex)
        .animation(.spring(response: 0.18, dampingFraction: 0.88), value: viewModel.linkCandidates.map(\.id))
    }

    private func titleLine(_ note: Note) -> String {
        note.text.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? note.text
    }

    private func snippetLine(_ note: Note) -> String? {
        let lines = note.text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return nil }
        let s = String(lines[1].prefix(55))
        return s.isEmpty ? nil : s
    }
}

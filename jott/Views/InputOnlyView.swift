import SwiftUI

struct InputOnlyView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @FocusState private var isFocused: Bool
    @State private var textHeight: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Jott")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
                Text("⌘↵")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(12)
            .background(Color(nsColor: NSColor(white: 0.98, alpha: 1)))

            // Text input area - tall and spacious
            ZStack(alignment: .topLeading) {
                // Placeholder
                if viewModel.inputText.isEmpty {
                    Text("Type a note, reminder, or meeting...\n\nExamples:\n• remind me to call john tomorrow 3pm\n• meeting with sarah friday 2pm\n• buy milk #shopping")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.4))
                        .padding(14)
                        .allowsHitTesting(false)
                }

                // Text input - explicitly dark text
                TextEditor(text: $viewModel.inputText)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundColor(Color(nsColor: .black))
                    .accentColor(.jottGreen)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .white))
                    .focused($isFocused)
                    .onKeyPress(.escape) { viewModel.handleEscape(); return .handled }
                    .padding(14)
            }
            .frame(minHeight: 160)
            .background(Color(nsColor: .white))

            // Action bar
            HStack(spacing: 12) {
                Spacer()
                Button(action: { viewModel.handleEscape() }) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Button(action: { viewModel.dismiss() }) {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(minWidth: 60)
                        .padding(.vertical, 6)
                        .background(Color.jottGreen)
                        .cornerRadius(6)
                }
            }
            .padding(12)
            .background(Color(nsColor: NSColor(white: 0.98, alpha: 1)))

        }
        .background(Color(nsColor: .white))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .frame(width: adaptiveWidth())
        .scaleEffect(viewModel.isVisible ? 1.0 : 0.92)
        .opacity(viewModel.isVisible ? 1.0 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: viewModel.isVisible)
        .onAppear {
            isFocused = true
        }
        .onChange(of: viewModel.isVisible) { _, isVisible in
            if isVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
            }
        }
    }

    private func adaptiveWidth() -> CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 800
        let baseWidth: CGFloat = 420
        let maxWidth: CGFloat = min(screenWidth - 100, 600)

        // Expand based on text length
        let textLength = viewModel.inputText.count
        let expansion = min(CGFloat(textLength / 10) * 5, 180)

        return min(baseWidth + expansion, maxWidth)
    }
}

#Preview {
    InputOnlyView(viewModel: OverlayViewModel())
}

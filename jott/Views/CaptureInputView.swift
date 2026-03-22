import SwiftUI

struct CaptureInputView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $viewModel.inputText)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(nsColor: .black))
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .onKeyPress(.escape) { viewModel.handleEscape(); return .handled }
                .onKeyPress(.return) { return .ignored }
                .padding(20)
        }
        .background(Color(nsColor: .white))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 12)
        .frame(height: 280)
        .scaleEffect(viewModel.isVisible ? 1.0 : 0.92)
        .opacity(viewModel.isVisible ? 1.0 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isVisible)
        .onAppear { isFocused = true }
        .onChange(of: viewModel.isVisible) { _, isVisible in
            if isVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
        }
    }
}

#Preview {
    CaptureInputView(viewModel: OverlayViewModel())
}

import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        UnifiedJottView(viewModel: viewModel)
    }
}

#Preview {
    OverlayView(viewModel: OverlayViewModel())
}

import SwiftUI

struct SaveConfirmationView: View {
    @Binding var show: Bool

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.jottGreen)
                    .scaleEffect(show ? 1.0 : 0.5)
                    .opacity(show ? 1.0 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: show)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    SaveConfirmationView(show: .constant(true))
}

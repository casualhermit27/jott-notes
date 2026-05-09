import SwiftUI

// Flat top (bleeds into notch hardware), rounded bottom only — matches CSS
// border-top-left-radius:0 / border-top-right-radius:0 exactly.
// width + height + radius are all independently animatable so the controller
// can stagger them with separate withAnimation calls.
private struct JottNotchShape: Shape {
    var width:  CGFloat
    var height: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(width, height), radius) }
        set {
            width  = newValue.first.first
            height = newValue.first.second
            radius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = min(max(1, width),  rect.width)
        let h = min(max(1, height), rect.height)
        let r = min(radius, w / 2, h / 2)
        let x = (rect.width - w) / 2   // centered horizontally in the panel

        var path = Path()
        path.move(to:    CGPoint(x: x,     y: -2))  // bleed 2pt above rect — seals notch seam
        path.addLine(to: CGPoint(x: x + w, y: -2))
        path.addLine(to: CGPoint(x: x + w, y: h - r))
        path.addArc(
            center: CGPoint(x: x + w - r, y: h - r),
            radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: x + r, y: h))
        path.addArc(
            center: CGPoint(x: x + r, y: h - r),
            radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.addLine(to: CGPoint(x: x, y: -2))
        path.closeSubpath()
        return path
    }
}

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    // Pill icons at the compact dimensions — visible before content appears,
    // fades out when contentVisible flips true at 170ms.
    @ViewBuilder
    private var pinnedHandoffContent: some View {
        let pinPurple = Color(red: 0.70, green: 0.55, blue: 1.0)
        HStack(spacing: 0) {
            Image(systemName: "pin.fill")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(pinPurple.opacity(0.92))
                .frame(width: 62, height: 34)
            Spacer(minLength: 0)
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.white.opacity(0.62))
                .frame(width: 62, height: 34)
        }
        .frame(width: viewModel.revealCompactWidth, height: 34)
        .allowsHitTesting(false)
    }

    var body: some View {
        UnifiedJottView(viewModel: viewModel)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.black.opacity(0.22), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 3)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                if viewModel.focusedNote != nil {
                    pinnedHandoffContent
                        .opacity(viewModel.contentVisible ? 0 : 1)
                        .animation(.easeOut(duration: 0.12), value: viewModel.contentVisible)
                }
            }
            .clipShape(JottNotchShape(
                width:  viewModel.morphWidth,
                height: viewModel.morphHeight,
                radius: viewModel.morphRadius
            ))
    }
}

#Preview {
    OverlayView(viewModel: OverlayViewModel())
}

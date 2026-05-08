import SwiftUI

private struct NotchMorphVector: VectorArithmetic {
    var progress: Double = 0
    var exit: Double = 0
    var expandedHeight: Double = 0
    var compactWidth: Double = 0
    var compactHeight: Double = 0

    static var zero: NotchMorphVector { NotchMorphVector() }

    static func + (l: NotchMorphVector, r: NotchMorphVector) -> NotchMorphVector {
        NotchMorphVector(progress: l.progress + r.progress, exit: l.exit + r.exit,
                         expandedHeight: l.expandedHeight + r.expandedHeight,
                         compactWidth: l.compactWidth + r.compactWidth,
                         compactHeight: l.compactHeight + r.compactHeight)
    }
    static func - (l: NotchMorphVector, r: NotchMorphVector) -> NotchMorphVector {
        NotchMorphVector(progress: l.progress - r.progress, exit: l.exit - r.exit,
                         expandedHeight: l.expandedHeight - r.expandedHeight,
                         compactWidth: l.compactWidth - r.compactWidth,
                         compactHeight: l.compactHeight - r.compactHeight)
    }
    static func += (l: inout NotchMorphVector, r: NotchMorphVector) { l = l + r }
    static func -= (l: inout NotchMorphVector, r: NotchMorphVector) { l = l - r }

    mutating func scale(by rhs: Double) {
        progress *= rhs; exit *= rhs; expandedHeight *= rhs
        compactWidth *= rhs; compactHeight *= rhs
    }
    var magnitudeSquared: Double {
        progress*progress + exit*exit + expandedHeight*expandedHeight
        + compactWidth*compactWidth + compactHeight*compactHeight
    }
}

private struct NotchMorphShape: Shape {
    var progress: Double        // 0 = compact, 1 = full panel (spring can overshoot slightly)
    var exitProgress: Double    // 0→1 on close: drives lateral squish wobble
    var expandedHeight: CGFloat
    var compactWidth: CGFloat
    var compactHeight: CGFloat

    private let notchBottomR: CGFloat = 12
    private let panelBottomR: CGFloat = 8
    private let floatingControlsAllowance: CGFloat = 116

    var animatableData: NotchMorphVector {
        get { NotchMorphVector(progress: progress, exit: exitProgress,
                               expandedHeight: Double(expandedHeight),
                               compactWidth: Double(compactWidth),
                               compactHeight: Double(compactHeight)) }
        set {
            progress = newValue.progress
            exitProgress = newValue.exit
            expandedHeight = CGFloat(newValue.expandedHeight)
            compactWidth = CGFloat(newValue.compactWidth)
            compactHeight = CGFloat(newValue.compactHeight)
        }
    }

    func path(in rect: CGRect) -> Path {
        let p = max(0, min(1.02, progress))     // allow spring overshoot
        let pUnit = max(0, min(1, p))
        let exitUnit = max(0, min(1, exitProgress))

        // Width leads height, corner lags — derived from a single progress value.
        // The lag offsets replicate the old 0.045s / 0.075s spring delays.
        let heightP = max(0, (pUnit - 0.05) / 0.95)   // ~0.045s lag at 0.4s settle time
        let cornerP = max(0, (pUnit - 0.08) / 0.92)   // ~0.075s lag

        let heightT = CGFloat(min(1.018, heightP))     // bounded overshoot for spring feel
        let cornerT = CGFloat(pow(smoothstep(cornerP) * (1 - 0.10 * smoothstep(exitUnit)), 1.65))

        // Width leads via coupling: eased width pulls ahead as height rises
        let easedWidth = 1 - pow(1 - pUnit, 1.55)
        let coupling   = 0.36 * smoothstep(heightP)
        let rawWidthT  = CGFloat(pUnit + (easedWidth - pUnit) * coupling) + CGFloat(p - pUnit)
        let widthT     = max(0, rawWidthT)

        // Lateral wobble: peaks mid-transition, only active during exit squish
        let transitionPeak = CGFloat(sin(.pi * min(1, max(0, (pUnit + heightP) * 0.5))))
        let micro = 0.12
            * sin(CGFloat(pUnit) * .pi * 2.0 + CGFloat(heightP) * .pi * 0.65)
            * transitionPeak
        let exitBias = CGFloat(exitUnit) * CGFloat(sin(.pi * pUnit))
        let pull = (1.05 * exitBias + micro) * max(0, min(1, widthT))

        let notchW = max(1, min(compactWidth, rect.width))
        let notchH = max(1, min(compactHeight, rect.height))
        let w = notchW + (rect.width - notchW) * widthT
        let contentPressure = 2.4 * heightT * heightT  // subtle height bulge when content loads
        let baseH = notchH + (min(expandedHeight, rect.height) - notchH) * heightT
        let h = min(baseH + floatingControlsAllowance * heightT + contentPressure, rect.height)

        let x = (rect.width - w) / 2 + pull
        let cornerStretch = 0.55 * transitionPeak * (1 - 0.48 * CGFloat(smoothstep(exitUnit)))
        let br = min(notchBottomR + (panelBottomR - notchBottomR) * cornerT + cornerStretch, w/2, h/2)
        let c  = 0.447 + 0.04 * max(0, 1 - cornerT)
        let topShoulderFlex  = 0.62 * transitionPeak * (0.35 + 0.65 * CGFloat(pUnit))
                               * (1 - 0.48 * CGFloat(smoothstep(exitUnit)))
        let bottomDip = min(
            1.9,
            (0.45 * CGFloat(smoothstep(heightP)) + 1.28 * transitionPeak)
            * (0.72 + 0.28 * heightT) + micro
        )
        let bottomY  = min(h + max(0, bottomDip), rect.height)
        let topBleed = max(2.0, topShoulderFlex + 1.0)

        var path = Path()
        path.move(to: CGPoint(x: x, y: -topBleed))
        path.addLine(to: CGPoint(x: x + w, y: -topBleed))
        path.addLine(to: CGPoint(x: x + w, y: topShoulderFlex))
        path.addLine(to: CGPoint(x: x + w, y: h - br))
        path.addCurve(to: CGPoint(x: x + w - br, y: h),
                      control1: CGPoint(x: x + w, y: h - br * c),
                      control2: CGPoint(x: x + w - br * c, y: h))
        path.addCurve(to: CGPoint(x: x + br, y: h),
                      control1: CGPoint(x: x + w * 0.66, y: bottomY),
                      control2: CGPoint(x: x + w * 0.34, y: bottomY))
        path.addCurve(to: CGPoint(x: x, y: h - br),
                      control1: CGPoint(x: x + br * c, y: h),
                      control2: CGPoint(x: x, y: h - br * c))
        path.addLine(to: CGPoint(x: x, y: topShoulderFlex))
        path.addLine(to: CGPoint(x: x, y: -topBleed))
        path.closeSubpath()
        return path
    }

    private func smoothstep(_ value: Double) -> Double {
        let x = max(0, min(1, value))
        return x * x * (3 - 2 * x)
    }
}

// Fades the pinned handoff icons out as the bar opens (0→45% progress),
// and suppresses them entirely once the close animation starts.
private struct PinnedHandoffModifier: ViewModifier, Animatable {
    var progress: Double
    var exitProgress: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, exitProgress) }
        set { progress = newValue.first; exitProgress = newValue.second }
    }

    func body(content: Content) -> some View {
        let t = max(0.0, min(1.0, progress / 0.45))
        let openOpacity = 1.0 - t * t * (3 - 2 * t)
        // Kill the overlay immediately when the close animation begins.
        let exitSuppression = max(0.0, 1.0 - exitProgress * 8.0)
        return content.opacity(openOpacity * exitSuppression)
    }
}

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    private var p: Double { max(0, min(1, viewModel.revealProgress)) }
    private var exitInfluence: Double {
        max(0, min(1, viewModel.revealExitProgress)) * p
    }

    // Matches the collapsed pill layout: pin icon left, doc icon right.
    // Shown at progress=0 when transitioning from pinned state, fades out by ~45%.
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
        let morphShape = NotchMorphShape(
            progress: viewModel.revealProgress,
            exitProgress: viewModel.revealExitProgress,
            expandedHeight: viewModel.overlayExpandedHeight,
            compactWidth: viewModel.revealCompactWidth,
            compactHeight: viewModel.revealCompactHeight
        )

        UnifiedJottView(viewModel: viewModel)
            // Ambient occlusion: 3px gradient at top merges surface into menu bar hardware.
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.black.opacity(0.22), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 3)
                .allowsHitTesting(false)
            }
            // Pinned handoff: shows pill content at progress=0, fades as bar opens.
            // Only active when a focused note triggered the open.
            .overlay(alignment: .top) {
                if viewModel.focusedNote != nil {
                    pinnedHandoffContent
                        .modifier(PinnedHandoffModifier(
                            progress: viewModel.revealProgress,
                            exitProgress: viewModel.revealExitProgress
                        ))
                }
            }
            .clipShape(morphShape)
            .scaleEffect(1 - 0.014 * exitInfluence, anchor: .top)
            .offset(y: -7 * CGFloat(exitInfluence))
            .opacity(1 - 0.14 * exitInfluence)
    }
}

#Preview {
    OverlayView(viewModel: OverlayViewModel())
}

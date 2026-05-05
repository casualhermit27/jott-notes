import SwiftUI

private struct NotchMorphVector: VectorArithmetic {
    var width: Double = 0
    var height: Double = 0
    var corner: Double = 0
    var bias: Double = 0
    var content: Double = 0
    var exit: Double = 0
    var expandedHeight: Double = 0

    static var zero: NotchMorphVector { NotchMorphVector() }

    static func + (lhs: NotchMorphVector, rhs: NotchMorphVector) -> NotchMorphVector {
        NotchMorphVector(
            width: lhs.width + rhs.width,
            height: lhs.height + rhs.height,
            corner: lhs.corner + rhs.corner,
            bias: lhs.bias + rhs.bias,
            content: lhs.content + rhs.content,
            exit: lhs.exit + rhs.exit,
            expandedHeight: lhs.expandedHeight + rhs.expandedHeight
        )
    }

    static func - (lhs: NotchMorphVector, rhs: NotchMorphVector) -> NotchMorphVector {
        NotchMorphVector(
            width: lhs.width - rhs.width,
            height: lhs.height - rhs.height,
            corner: lhs.corner - rhs.corner,
            bias: lhs.bias - rhs.bias,
            content: lhs.content - rhs.content,
            exit: lhs.exit - rhs.exit,
            expandedHeight: lhs.expandedHeight - rhs.expandedHeight
        )
    }

    static func += (lhs: inout NotchMorphVector, rhs: NotchMorphVector) {
        lhs = lhs + rhs
    }

    static func -= (lhs: inout NotchMorphVector, rhs: NotchMorphVector) {
        lhs = lhs - rhs
    }

    mutating func scale(by rhs: Double) {
        width *= rhs
        height *= rhs
        corner *= rhs
        bias *= rhs
        content *= rhs
        exit *= rhs
        expandedHeight *= rhs
    }

    var magnitudeSquared: Double {
        width * width
        + height * height
        + corner * corner
        + bias * bias
        + content * content
        + exit * exit
        + expandedHeight * expandedHeight
    }
}

private struct NotchMorphShape: Shape {
    var widthProgress: Double
    var heightProgress: Double
    var cornerProgress: Double
    var surfaceBiasProgress: Double
    var contentProgress: Double
    var exitProgress: Double
    var expandedHeight: CGFloat

    private let notchW: CGFloat = 178
    private let notchH: CGFloat = 32
    private let notchBottomR: CGFloat = 12
    private let panelBottomR: CGFloat = 8
    private let floatingControlsAllowance: CGFloat = 116

    var animatableData: NotchMorphVector {
        get {
            NotchMorphVector(
                width: widthProgress,
                height: heightProgress,
                corner: cornerProgress,
                bias: surfaceBiasProgress,
                content: contentProgress,
                exit: exitProgress,
                expandedHeight: Double(expandedHeight)
            )
        }
        set {
            widthProgress = newValue.width
            heightProgress = newValue.height
            cornerProgress = newValue.corner
            surfaceBiasProgress = newValue.bias
            contentProgress = newValue.content
            exitProgress = newValue.exit
            expandedHeight = CGFloat(newValue.expandedHeight)
        }
    }

    func path(in rect: CGRect) -> Path {
        let widthUnit = clampedUnit(widthProgress)
        let heightUnit = clampedUnit(heightProgress)
        let cornerUnit = clampedUnit(cornerProgress)
        let biasUnit = clampedUnit(surfaceBiasProgress)
        let contentUnit = clampedUnit(contentProgress)
        let exitUnit = clampedUnit(exitProgress)

        let heightT = boundedProgress(heightProgress)
        let rawWidthT = coupledWidthProgress(widthUnit: widthUnit, heightUnit: heightUnit)
            + CGFloat(widthProgress - widthUnit)
        let widthT = max(0, rawWidthT)
        let cornerT = CGFloat(pow(cornerUnit * (1 - 0.10 * smoothstep(exitUnit)), 1.65))
        let biasPeak = CGFloat(sin(.pi * heightUnit))
        let transitionPeak = CGFloat(sin(.pi * min(1, max(0, (widthUnit + heightUnit) * 0.5))))
        let micro = 0.12
            * sin(CGFloat(widthUnit) * .pi * 2.0 + CGFloat(heightUnit) * .pi * 0.65)
            * transitionPeak

        let w = notchW + (rect.width - notchW) * widthT
        let contentPressure = 2.4 * CGFloat(smoothstep(contentUnit)) * CGFloat(smoothstep(heightUnit))
        let baseH = notchH + (min(expandedHeight, rect.height) - notchH) * heightT
        let h = min(baseH + floatingControlsAllowance * heightT + contentPressure, rect.height)
        let pull = (1.05 * CGFloat(biasUnit) * biasPeak + micro) * max(0, min(1, widthT))
        let x = (rect.width - w) / 2 + pull
        let cornerStretch = 0.55 * transitionPeak * (1 - 0.48 * CGFloat(smoothstep(exitUnit)))
        let br = min(notchBottomR + (panelBottomR - notchBottomR) * cornerT + cornerStretch, w / 2, h / 2)
        let c = 0.447 + 0.04 * max(0, 1 - cornerT)
        let topShoulderFlex = 0.62 * transitionPeak * (0.35 + 0.65 * CGFloat(widthUnit)) * (1 - 0.48 * CGFloat(smoothstep(exitUnit)))
        let bottomDip = min(
            1.9,
            (0.45 * CGFloat(smoothstep(heightUnit)) + 1.28 * transitionPeak)
            * (0.72 + 0.28 * CGFloat(smoothstep(contentUnit)))
            + micro
        )
        let bottomY = min(h + max(0, bottomDip), rect.height)
        let topBleed = max(2.0, topShoulderFlex + 1.0)

        var path = Path()
        path.move(to: CGPoint(x: x, y: -topBleed))
        path.addLine(to: CGPoint(x: x + w, y: -topBleed))
        path.addLine(to: CGPoint(x: x + w, y: topShoulderFlex))
        path.addLine(to: CGPoint(x: x + w, y: h - br))
        path.addCurve(
            to: CGPoint(x: x + w - br, y: h),
            control1: CGPoint(x: x + w, y: h - br * c),
            control2: CGPoint(x: x + w - br * c, y: h)
        )
        path.addCurve(
            to: CGPoint(x: x + br, y: h),
            control1: CGPoint(x: x + w * 0.66, y: bottomY),
            control2: CGPoint(x: x + w * 0.34, y: bottomY)
        )
        path.addCurve(
            to: CGPoint(x: x, y: h - br),
            control1: CGPoint(x: x + br * c, y: h),
            control2: CGPoint(x: x, y: h - br * c)
        )
        path.addLine(to: CGPoint(x: x, y: topShoulderFlex))
        path.addLine(to: CGPoint(x: x, y: -topBleed))
        path.closeSubpath()
        return path
    }

    private func clampedUnit(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private func boundedProgress(_ value: Double) -> CGFloat {
        CGFloat(max(0, min(1.018, value)))
    }

    private func smoothstep(_ value: Double) -> Double {
        let x = clampedUnit(value)
        return x * x * (3 - 2 * x)
    }

    private func coupledWidthProgress(widthUnit: Double, heightUnit: Double) -> CGFloat {
        let easedWidth = 1 - pow(1 - widthUnit, 1.55)
        let coupling = 0.36 * smoothstep(heightUnit)
        return CGFloat(widthUnit + (easedWidth - widthUnit) * coupling)
    }
}

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    private var exitProgress: Double {
        max(0, min(1, viewModel.revealExitProgress))
    }
    private var expandedSurfaceProgress: Double {
        max(0, min(1, max(viewModel.revealWidthProgress, viewModel.revealHeightProgress)))
    }
    private var exitInfluence: Double {
        exitProgress * expandedSurfaceProgress
    }

    var body: some View {
        UnifiedJottView(viewModel: viewModel)
            .clipShape(NotchMorphShape(
                widthProgress: viewModel.revealWidthProgress,
                heightProgress: viewModel.revealHeightProgress,
                cornerProgress: viewModel.revealCornerProgress,
                surfaceBiasProgress: viewModel.revealSurfaceBiasProgress,
                contentProgress: viewModel.revealContentProgress,
                exitProgress: viewModel.revealExitProgress,
                expandedHeight: viewModel.overlayExpandedHeight
            ))
            .scaleEffect(1 - 0.014 * exitInfluence, anchor: .top)
            .offset(y: -7 * CGFloat(exitInfluence))
            .opacity(1 - 0.14 * exitInfluence)
    }
}

#Preview {
    OverlayView(viewModel: OverlayViewModel())
}

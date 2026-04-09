import SwiftUI
import AppKit

enum JottMotion {
    static let panel = Animation.spring(response: 0.24, dampingFraction: 0.88)
    static let content = Animation.easeOut(duration: 0.14)
    static let micro = Animation.spring(response: 0.14, dampingFraction: 0.86)
    /// Used when a link is confirmed and nodes animate into their new graph positions.
    static let connect = Animation.spring(response: 0.42, dampingFraction: 0.80)

    static let panelDuration: CFTimeInterval = 0.24
    static let panelFadeDuration: TimeInterval = 0.20
    static let panelEntranceTiming = CAMediaTimingFunction(controlPoints: 0.18, 1.0, 0.28, 1.0)
    static let panelExitTiming = CAMediaTimingFunction(controlPoints: 0.5, 0.0, 1.0, 1.0)
}

enum JottTypography {
    static func ui(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func title(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func noteTitle(_ size: CGFloat = 15, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func noteBody(_ size: CGFloat = 12.5, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct JottAmbientBackdrop: View {
    var isDark: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)

            ZStack {
                LinearGradient(
                    colors: [Color.jottAmbientBase, Color.jottAmbientSecondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.jottOverlaySky.opacity(isDark ? 0.24 : 0.16))
                    .frame(width: width * 0.52, height: width * 0.52)
                    .blur(radius: 54)
                    .offset(x: width * 0.22, y: -height * 0.24)

                Circle()
                    .fill(Color.jottOverlayMintAccent.opacity(isDark ? 0.22 : 0.14))
                    .frame(width: width * 0.42, height: width * 0.42)
                    .blur(radius: 48)
                    .offset(x: -width * 0.24, y: height * 0.12)

                Circle()
                    .fill(Color.jottOverlayPeachAccent.opacity(isDark ? 0.18 : 0.12))
                    .frame(width: width * 0.34, height: width * 0.34)
                    .blur(radius: 42)
                    .offset(x: width * 0.14, y: height * 0.30)

                LinearGradient(
                    colors: [
                        Color.jottGlassHighlight.opacity(isDark ? 0.12 : 0.38),
                        .clear,
                        Color.black.opacity(isDark ? 0.16 : 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .compositingGroup()
        }
    }
}

private struct JottGlassPanelBackground: View {
    var cornerRadius: CGFloat
    var isDark: Bool
    var baseFill: Color
    var border: Color
    var accentColors: [Color]
    var material: NSVisualEffectView.Material?

    private var resolvedMaterial: NSVisualEffectView.Material {
        material ?? (isDark ? .hudWindow : .popover)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            VisualEffectBlur(material: resolvedMaterial, blendingMode: .behindWindow)

            shape
                .fill(baseFill)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(border.opacity(isDark ? 0.92 : 0.82), lineWidth: 1))
        .overlay(
            shape
                .strokeBorder(Color.white.opacity(isDark ? 0.08 : 0.28), lineWidth: 0.5)
        )
    }
}

// MARK: - Spotlight Hover Effect

extension View {
    func jottAppTypography() -> some View {
        self.font(JottTypography.ui())
    }

    func jottGlassPanel(
        cornerRadius: CGFloat = 16,
        isDark: Bool,
        baseFill: Color = .jottOverlaySurface,
        border: Color = .jottBorder,
        accentColors: [Color] = [
            .jottOverlaySky,
            .jottOverlayMintAccent,
            .jottOverlayPeachAccent,
        ],
        material: NSVisualEffectView.Material? = nil,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> some View {
        self
            .background(
                JottGlassPanelBackground(
                    cornerRadius: cornerRadius,
                    isDark: isDark,
                    baseFill: baseFill,
                    border: border,
                    accentColors: accentColors,
                    material: material
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func spotlightHover(scale: CGFloat = 0.98) -> some View {
        modifier(SpotlightHoverModifier(scale: scale))
    }
}

/// Smooth press — instant snap down, silky ease-out release. No bounce.
struct JottSquishyButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.94
    var pressedOpacity: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(
                configuration.isPressed
                    ? .easeIn(duration: 0.08)
                    : .timingCurve(0.34, 1.56, 0.64, 1.0, duration: 0.35),
                value: configuration.isPressed
            )
    }
}

/// Smooth pop — deeper press, floats back with a gentle overshoot via cubic curve
struct JottPopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(
                configuration.isPressed
                    ? .easeIn(duration: 0.07)
                    : .timingCurve(0.34, 1.56, 0.64, 1.0, duration: 0.40),
                value: configuration.isPressed
            )
    }
}

/// Jelly — kept for compatibility, same as squishy
typealias JottJellyButtonStyle = JottSquishyButtonStyle

struct SpotlightHoverModifier: ViewModifier {
    @State private var isHovered = false
    var scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .opacity(isHovered ? 0.9 : 1.0)
            .onHover { hovering in
                withAnimation(JottMotion.micro) {
                    isHovered = hovering
                }
            }
    }
}

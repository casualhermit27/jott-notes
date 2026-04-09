import SwiftUI
import AppKit

private func jottDynamicColor(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return dark
        default:
            return light
        }
    }
}

extension Color {
    static let tagColors: [Color] = [
        Color("jott-tag-mint"),
        Color("jott-tag-cream"),
        Color("jott-tag-periwinkle"),
        Color("jott-tag-blush"),
    ]

    static func tagColor(for tag: String) -> Color {
        tagColors[abs(tag.hashValue) % tagColors.count]
    }

    static var jottOverlaySurface: Color {
        Color(nsColor: jottDynamicColor(
            light: NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 0.54),
            dark: NSColor(srgbRed: 0.120, green: 0.132, blue: 0.160, alpha: 0.76)
        ))
    }

    static var jottOverlaySurfaceElevated: Color {
        Color(nsColor: jottDynamicColor(
            light: NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 0.66),
            dark: NSColor(srgbRed: 0.160, green: 0.172, blue: 0.205, alpha: 0.82)
        ))
    }

    static var jottGlassHighlight: Color {
        Color(nsColor: jottDynamicColor(
            light: NSColor(white: 1.0, alpha: 0.55),
            dark: NSColor(white: 1.0, alpha: 0.12)
        ))
    }

    static var jottAmbientBase: Color {
        Color(nsColor: jottDynamicColor(
            light: NSColor(srgbRed: 0.934, green: 0.953, blue: 0.952, alpha: 1.0),
            dark: NSColor(srgbRed: 0.075, green: 0.085, blue: 0.110, alpha: 1.0)
        ))
    }

    static var jottAmbientSecondary: Color {
        Color(nsColor: jottDynamicColor(
            light: NSColor(srgbRed: 0.962, green: 0.947, blue: 0.930, alpha: 1.0),
            dark: NSColor(srgbRed: 0.110, green: 0.100, blue: 0.125, alpha: 1.0)
        ))
    }

    static var jottOverlaySelectorAccent: Color {
        Color("jott-tag-periwinkle")
    }

    static var jottOverlayWarmAccent: Color {
        Color("jott-tag-cream")
    }

    static var jottOverlaySky: Color {
        Color(red: 0.345, green: 0.655, blue: 0.930)
    }

    static var jottOverlayMintAccent: Color {
        Color(red: 0.420, green: 0.860, blue: 0.730)
    }

    static var jottOverlayPeachAccent: Color {
        Color(red: 0.988, green: 0.675, blue: 0.560)
    }

    static var jottOverlayCoralAccent: Color {
        Color(red: 0.982, green: 0.470, blue: 0.150)
    }

    static var jottOverlayHoverFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(srgbRed: 0.84, green: 0.90, blue: 1.0, alpha: 0.08)
            default:
                return NSColor(srgbRed: 0.36, green: 0.40, blue: 0.52, alpha: 0.06)
            }
        })
    }

    static var jottOverlayShadow: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(white: 0.0, alpha: 0.28)
            default:
                return NSColor(white: 0.0, alpha: 0.045)
            }
        })
    }
}

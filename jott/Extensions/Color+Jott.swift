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
            light: NSColor(srgbRed: 0.965, green: 0.968, blue: 0.960, alpha: 0.58),
            dark: NSColor(srgbRed: 0.082, green: 0.090, blue: 0.112, alpha: 0.84)
        ))
    }

    static var jottOverlaySurfaceElevated: Color {
        Color(nsColor: jottDynamicColor(
            light: NSColor(srgbRed: 0.982, green: 0.982, blue: 0.972, alpha: 0.68),
            dark: NSColor(srgbRed: 0.105, green: 0.112, blue: 0.138, alpha: 0.88)
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
            light: NSColor(srgbRed: 0.908, green: 0.922, blue: 0.918, alpha: 1.0),
            dark: NSColor(srgbRed: 0.046, green: 0.052, blue: 0.070, alpha: 1.0)
        ))
    }

    static var jottAmbientSecondary: Color {
        Color(nsColor: jottDynamicColor(
            light: NSColor(srgbRed: 0.928, green: 0.912, blue: 0.892, alpha: 1.0),
            dark: NSColor(srgbRed: 0.070, green: 0.064, blue: 0.084, alpha: 1.0)
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
                return NSColor(srgbRed: 0.84, green: 0.90, blue: 1.0, alpha: 0.055)
            default:
                return NSColor(srgbRed: 0.28, green: 0.31, blue: 0.38, alpha: 0.055)
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

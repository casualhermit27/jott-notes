import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "jott-accent-green" asset catalog color resource.
    static let jottAccentGreen = DeveloperToolsSupport.ColorResource(name: "jott-accent-green", bundle: resourceBundle)

    /// The "jott-bar" asset catalog color resource.
    static let jottBar = DeveloperToolsSupport.ColorResource(name: "jott-bar", bundle: resourceBundle)

    /// The "jott-border" asset catalog color resource.
    static let jottBorder = DeveloperToolsSupport.ColorResource(name: "jott-border", bundle: resourceBundle)

    /// The "jott-cursor" asset catalog color resource.
    static let jottCursor = DeveloperToolsSupport.ColorResource(name: "jott-cursor", bundle: resourceBundle)

    /// The "jott-detail-background" asset catalog color resource.
    static let jottDetailBackground = DeveloperToolsSupport.ColorResource(name: "jott-detail-background", bundle: resourceBundle)

    /// The "jott-green" asset catalog color resource.
    static let jottGreen = DeveloperToolsSupport.ColorResource(name: "jott-green", bundle: resourceBundle)

    /// The "jott-input-text" asset catalog color resource.
    static let jottInputText = DeveloperToolsSupport.ColorResource(name: "jott-input-text", bundle: resourceBundle)

    /// The "jott-lavender" asset catalog color resource.
    static let jottLavender = DeveloperToolsSupport.ColorResource(name: "jott-lavender", bundle: resourceBundle)

    /// The "jott-link-bg" asset catalog color resource.
    static let jottLinkBg = DeveloperToolsSupport.ColorResource(name: "jott-link-bg", bundle: resourceBundle)

    /// The "jott-link-text" asset catalog color resource.
    static let jottLinkText = DeveloperToolsSupport.ColorResource(name: "jott-link-text", bundle: resourceBundle)

    /// The "jott-link-underline" asset catalog color resource.
    static let jottLinkUnderline = DeveloperToolsSupport.ColorResource(name: "jott-link-underline", bundle: resourceBundle)

    /// The "jott-meeting-accent" asset catalog color resource.
    static let jottMeetingAccent = DeveloperToolsSupport.ColorResource(name: "jott-meeting-accent", bundle: resourceBundle)

    /// The "jott-meeting-badge-bg" asset catalog color resource.
    static let jottMeetingBadgeBg = DeveloperToolsSupport.ColorResource(name: "jott-meeting-badge-bg", bundle: resourceBundle)

    /// The "jott-meeting-badge-fg" asset catalog color resource.
    static let jottMeetingBadgeFg = DeveloperToolsSupport.ColorResource(name: "jott-meeting-badge-fg", bundle: resourceBundle)

    /// The "jott-note-accent" asset catalog color resource.
    static let jottNoteAccent = DeveloperToolsSupport.ColorResource(name: "jott-note-accent", bundle: resourceBundle)

    /// The "jott-note-badge-bg" asset catalog color resource.
    static let jottNoteBadgeBg = DeveloperToolsSupport.ColorResource(name: "jott-note-badge-bg", bundle: resourceBundle)

    /// The "jott-note-badge-fg" asset catalog color resource.
    static let jottNoteBadgeFg = DeveloperToolsSupport.ColorResource(name: "jott-note-badge-fg", bundle: resourceBundle)

    /// The "jott-placeholder" asset catalog color resource.
    static let jottPlaceholder = DeveloperToolsSupport.ColorResource(name: "jott-placeholder", bundle: resourceBundle)

    /// The "jott-reminder-accent" asset catalog color resource.
    static let jottReminderAccent = DeveloperToolsSupport.ColorResource(name: "jott-reminder-accent", bundle: resourceBundle)

    /// The "jott-reminder-badge-bg" asset catalog color resource.
    static let jottReminderBadgeBg = DeveloperToolsSupport.ColorResource(name: "jott-reminder-badge-bg", bundle: resourceBundle)

    /// The "jott-reminder-badge-fg" asset catalog color resource.
    static let jottReminderBadgeFg = DeveloperToolsSupport.ColorResource(name: "jott-reminder-badge-fg", bundle: resourceBundle)

    /// The "jott-sage" asset catalog color resource.
    static let jottSage = DeveloperToolsSupport.ColorResource(name: "jott-sage", bundle: resourceBundle)

    /// The "jott-tag-blush" asset catalog color resource.
    static let jottTagBlush = DeveloperToolsSupport.ColorResource(name: "jott-tag-blush", bundle: resourceBundle)

    /// The "jott-tag-cream" asset catalog color resource.
    static let jottTagCream = DeveloperToolsSupport.ColorResource(name: "jott-tag-cream", bundle: resourceBundle)

    /// The "jott-tag-mint" asset catalog color resource.
    static let jottTagMint = DeveloperToolsSupport.ColorResource(name: "jott-tag-mint", bundle: resourceBundle)

    /// The "jott-tag-periwinkle" asset catalog color resource.
    static let jottTagPeriwinkle = DeveloperToolsSupport.ColorResource(name: "jott-tag-periwinkle", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "JottMenuBar" asset catalog image resource.
    static let jottMenuBar = DeveloperToolsSupport.ImageResource(name: "JottMenuBar", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "jott-accent-green" asset catalog color.
    static var jottAccentGreen: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottAccentGreen)
#else
        .init()
#endif
    }

    /// The "jott-bar" asset catalog color.
    static var jottBar: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottBar)
#else
        .init()
#endif
    }

    /// The "jott-border" asset catalog color.
    static var jottBorder: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottBorder)
#else
        .init()
#endif
    }

    /// The "jott-cursor" asset catalog color.
    static var jottCursor: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottCursor)
#else
        .init()
#endif
    }

    /// The "jott-detail-background" asset catalog color.
    static var jottDetailBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottDetailBackground)
#else
        .init()
#endif
    }

    /// The "jott-green" asset catalog color.
    static var jottGreen: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottGreen)
#else
        .init()
#endif
    }

    /// The "jott-input-text" asset catalog color.
    static var jottInputText: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottInputText)
#else
        .init()
#endif
    }

    /// The "jott-lavender" asset catalog color.
    static var jottLavender: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottLavender)
#else
        .init()
#endif
    }

    /// The "jott-link-bg" asset catalog color.
    static var jottLinkBg: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottLinkBg)
#else
        .init()
#endif
    }

    /// The "jott-link-text" asset catalog color.
    static var jottLinkText: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottLinkText)
#else
        .init()
#endif
    }

    /// The "jott-link-underline" asset catalog color.
    static var jottLinkUnderline: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottLinkUnderline)
#else
        .init()
#endif
    }

    /// The "jott-meeting-accent" asset catalog color.
    static var jottMeetingAccent: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottMeetingAccent)
#else
        .init()
#endif
    }

    /// The "jott-meeting-badge-bg" asset catalog color.
    static var jottMeetingBadgeBg: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottMeetingBadgeBg)
#else
        .init()
#endif
    }

    /// The "jott-meeting-badge-fg" asset catalog color.
    static var jottMeetingBadgeFg: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottMeetingBadgeFg)
#else
        .init()
#endif
    }

    /// The "jott-note-accent" asset catalog color.
    static var jottNoteAccent: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottNoteAccent)
#else
        .init()
#endif
    }

    /// The "jott-note-badge-bg" asset catalog color.
    static var jottNoteBadgeBg: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottNoteBadgeBg)
#else
        .init()
#endif
    }

    /// The "jott-note-badge-fg" asset catalog color.
    static var jottNoteBadgeFg: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottNoteBadgeFg)
#else
        .init()
#endif
    }

    /// The "jott-placeholder" asset catalog color.
    static var jottPlaceholder: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottPlaceholder)
#else
        .init()
#endif
    }

    /// The "jott-reminder-accent" asset catalog color.
    static var jottReminderAccent: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottReminderAccent)
#else
        .init()
#endif
    }

    /// The "jott-reminder-badge-bg" asset catalog color.
    static var jottReminderBadgeBg: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottReminderBadgeBg)
#else
        .init()
#endif
    }

    /// The "jott-reminder-badge-fg" asset catalog color.
    static var jottReminderBadgeFg: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottReminderBadgeFg)
#else
        .init()
#endif
    }

    /// The "jott-sage" asset catalog color.
    static var jottSage: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottSage)
#else
        .init()
#endif
    }

    /// The "jott-tag-blush" asset catalog color.
    static var jottTagBlush: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottTagBlush)
#else
        .init()
#endif
    }

    /// The "jott-tag-cream" asset catalog color.
    static var jottTagCream: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottTagCream)
#else
        .init()
#endif
    }

    /// The "jott-tag-mint" asset catalog color.
    static var jottTagMint: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottTagMint)
#else
        .init()
#endif
    }

    /// The "jott-tag-periwinkle" asset catalog color.
    static var jottTagPeriwinkle: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottTagPeriwinkle)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "jott-accent-green" asset catalog color.
    static var jottAccentGreen: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottAccentGreen)
#else
        .init()
#endif
    }

    /// The "jott-bar" asset catalog color.
    static var jottBar: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottBar)
#else
        .init()
#endif
    }

    /// The "jott-border" asset catalog color.
    static var jottBorder: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottBorder)
#else
        .init()
#endif
    }

    /// The "jott-cursor" asset catalog color.
    static var jottCursor: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottCursor)
#else
        .init()
#endif
    }

    /// The "jott-detail-background" asset catalog color.
    static var jottDetailBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottDetailBackground)
#else
        .init()
#endif
    }

    /// The "jott-green" asset catalog color.
    static var jottGreen: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottGreen)
#else
        .init()
#endif
    }

    /// The "jott-input-text" asset catalog color.
    static var jottInputText: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottInputText)
#else
        .init()
#endif
    }

    /// The "jott-lavender" asset catalog color.
    static var jottLavender: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottLavender)
#else
        .init()
#endif
    }

    /// The "jott-link-bg" asset catalog color.
    static var jottLinkBg: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottLinkBg)
#else
        .init()
#endif
    }

    /// The "jott-link-text" asset catalog color.
    static var jottLinkText: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottLinkText)
#else
        .init()
#endif
    }

    /// The "jott-link-underline" asset catalog color.
    static var jottLinkUnderline: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottLinkUnderline)
#else
        .init()
#endif
    }

    /// The "jott-meeting-accent" asset catalog color.
    static var jottMeetingAccent: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottMeetingAccent)
#else
        .init()
#endif
    }

    /// The "jott-meeting-badge-bg" asset catalog color.
    static var jottMeetingBadgeBg: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottMeetingBadgeBg)
#else
        .init()
#endif
    }

    /// The "jott-meeting-badge-fg" asset catalog color.
    static var jottMeetingBadgeFg: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottMeetingBadgeFg)
#else
        .init()
#endif
    }

    /// The "jott-note-accent" asset catalog color.
    static var jottNoteAccent: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottNoteAccent)
#else
        .init()
#endif
    }

    /// The "jott-note-badge-bg" asset catalog color.
    static var jottNoteBadgeBg: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottNoteBadgeBg)
#else
        .init()
#endif
    }

    /// The "jott-note-badge-fg" asset catalog color.
    static var jottNoteBadgeFg: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottNoteBadgeFg)
#else
        .init()
#endif
    }

    /// The "jott-placeholder" asset catalog color.
    static var jottPlaceholder: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottPlaceholder)
#else
        .init()
#endif
    }

    /// The "jott-reminder-accent" asset catalog color.
    static var jottReminderAccent: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottReminderAccent)
#else
        .init()
#endif
    }

    /// The "jott-reminder-badge-bg" asset catalog color.
    static var jottReminderBadgeBg: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottReminderBadgeBg)
#else
        .init()
#endif
    }

    /// The "jott-reminder-badge-fg" asset catalog color.
    static var jottReminderBadgeFg: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottReminderBadgeFg)
#else
        .init()
#endif
    }

    /// The "jott-sage" asset catalog color.
    static var jottSage: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottSage)
#else
        .init()
#endif
    }

    /// The "jott-tag-blush" asset catalog color.
    static var jottTagBlush: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottTagBlush)
#else
        .init()
#endif
    }

    /// The "jott-tag-cream" asset catalog color.
    static var jottTagCream: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottTagCream)
#else
        .init()
#endif
    }

    /// The "jott-tag-mint" asset catalog color.
    static var jottTagMint: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottTagMint)
#else
        .init()
#endif
    }

    /// The "jott-tag-periwinkle" asset catalog color.
    static var jottTagPeriwinkle: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .jottTagPeriwinkle)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    /// The "jott-accent-green" asset catalog color.
    static var jottAccentGreen: SwiftUI.Color { .init(.jottAccentGreen) }

    /// The "jott-bar" asset catalog color.
    static var jottBar: SwiftUI.Color { .init(.jottBar) }

    /// The "jott-border" asset catalog color.
    static var jottBorder: SwiftUI.Color { .init(.jottBorder) }

    /// The "jott-cursor" asset catalog color.
    static var jottCursor: SwiftUI.Color { .init(.jottCursor) }

    /// The "jott-detail-background" asset catalog color.
    static var jottDetailBackground: SwiftUI.Color { .init(.jottDetailBackground) }

    /// The "jott-green" asset catalog color.
    static var jottGreen: SwiftUI.Color { .init(.jottGreen) }

    /// The "jott-input-text" asset catalog color.
    static var jottInputText: SwiftUI.Color { .init(.jottInputText) }

    /// The "jott-lavender" asset catalog color.
    static var jottLavender: SwiftUI.Color { .init(.jottLavender) }

    /// The "jott-link-bg" asset catalog color.
    static var jottLinkBg: SwiftUI.Color { .init(.jottLinkBg) }

    /// The "jott-link-text" asset catalog color.
    static var jottLinkText: SwiftUI.Color { .init(.jottLinkText) }

    /// The "jott-link-underline" asset catalog color.
    static var jottLinkUnderline: SwiftUI.Color { .init(.jottLinkUnderline) }

    /// The "jott-meeting-accent" asset catalog color.
    static var jottMeetingAccent: SwiftUI.Color { .init(.jottMeetingAccent) }

    /// The "jott-meeting-badge-bg" asset catalog color.
    static var jottMeetingBadgeBg: SwiftUI.Color { .init(.jottMeetingBadgeBg) }

    /// The "jott-meeting-badge-fg" asset catalog color.
    static var jottMeetingBadgeFg: SwiftUI.Color { .init(.jottMeetingBadgeFg) }

    /// The "jott-note-accent" asset catalog color.
    static var jottNoteAccent: SwiftUI.Color { .init(.jottNoteAccent) }

    /// The "jott-note-badge-bg" asset catalog color.
    static var jottNoteBadgeBg: SwiftUI.Color { .init(.jottNoteBadgeBg) }

    /// The "jott-note-badge-fg" asset catalog color.
    static var jottNoteBadgeFg: SwiftUI.Color { .init(.jottNoteBadgeFg) }

    /// The "jott-placeholder" asset catalog color.
    static var jottPlaceholder: SwiftUI.Color { .init(.jottPlaceholder) }

    /// The "jott-reminder-accent" asset catalog color.
    static var jottReminderAccent: SwiftUI.Color { .init(.jottReminderAccent) }

    /// The "jott-reminder-badge-bg" asset catalog color.
    static var jottReminderBadgeBg: SwiftUI.Color { .init(.jottReminderBadgeBg) }

    /// The "jott-reminder-badge-fg" asset catalog color.
    static var jottReminderBadgeFg: SwiftUI.Color { .init(.jottReminderBadgeFg) }

    /// The "jott-sage" asset catalog color.
    static var jottSage: SwiftUI.Color { .init(.jottSage) }

    /// The "jott-tag-blush" asset catalog color.
    static var jottTagBlush: SwiftUI.Color { .init(.jottTagBlush) }

    /// The "jott-tag-cream" asset catalog color.
    static var jottTagCream: SwiftUI.Color { .init(.jottTagCream) }

    /// The "jott-tag-mint" asset catalog color.
    static var jottTagMint: SwiftUI.Color { .init(.jottTagMint) }

    /// The "jott-tag-periwinkle" asset catalog color.
    static var jottTagPeriwinkle: SwiftUI.Color { .init(.jottTagPeriwinkle) }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "jott-accent-green" asset catalog color.
    static var jottAccentGreen: SwiftUI.Color { .init(.jottAccentGreen) }

    /// The "jott-bar" asset catalog color.
    static var jottBar: SwiftUI.Color { .init(.jottBar) }

    /// The "jott-border" asset catalog color.
    static var jottBorder: SwiftUI.Color { .init(.jottBorder) }

    /// The "jott-cursor" asset catalog color.
    static var jottCursor: SwiftUI.Color { .init(.jottCursor) }

    /// The "jott-detail-background" asset catalog color.
    static var jottDetailBackground: SwiftUI.Color { .init(.jottDetailBackground) }

    /// The "jott-green" asset catalog color.
    static var jottGreen: SwiftUI.Color { .init(.jottGreen) }

    /// The "jott-input-text" asset catalog color.
    static var jottInputText: SwiftUI.Color { .init(.jottInputText) }

    /// The "jott-lavender" asset catalog color.
    static var jottLavender: SwiftUI.Color { .init(.jottLavender) }

    /// The "jott-link-bg" asset catalog color.
    static var jottLinkBg: SwiftUI.Color { .init(.jottLinkBg) }

    /// The "jott-link-text" asset catalog color.
    static var jottLinkText: SwiftUI.Color { .init(.jottLinkText) }

    /// The "jott-link-underline" asset catalog color.
    static var jottLinkUnderline: SwiftUI.Color { .init(.jottLinkUnderline) }

    /// The "jott-meeting-accent" asset catalog color.
    static var jottMeetingAccent: SwiftUI.Color { .init(.jottMeetingAccent) }

    /// The "jott-meeting-badge-bg" asset catalog color.
    static var jottMeetingBadgeBg: SwiftUI.Color { .init(.jottMeetingBadgeBg) }

    /// The "jott-meeting-badge-fg" asset catalog color.
    static var jottMeetingBadgeFg: SwiftUI.Color { .init(.jottMeetingBadgeFg) }

    /// The "jott-note-accent" asset catalog color.
    static var jottNoteAccent: SwiftUI.Color { .init(.jottNoteAccent) }

    /// The "jott-note-badge-bg" asset catalog color.
    static var jottNoteBadgeBg: SwiftUI.Color { .init(.jottNoteBadgeBg) }

    /// The "jott-note-badge-fg" asset catalog color.
    static var jottNoteBadgeFg: SwiftUI.Color { .init(.jottNoteBadgeFg) }

    /// The "jott-placeholder" asset catalog color.
    static var jottPlaceholder: SwiftUI.Color { .init(.jottPlaceholder) }

    /// The "jott-reminder-accent" asset catalog color.
    static var jottReminderAccent: SwiftUI.Color { .init(.jottReminderAccent) }

    /// The "jott-reminder-badge-bg" asset catalog color.
    static var jottReminderBadgeBg: SwiftUI.Color { .init(.jottReminderBadgeBg) }

    /// The "jott-reminder-badge-fg" asset catalog color.
    static var jottReminderBadgeFg: SwiftUI.Color { .init(.jottReminderBadgeFg) }

    /// The "jott-sage" asset catalog color.
    static var jottSage: SwiftUI.Color { .init(.jottSage) }

    /// The "jott-tag-blush" asset catalog color.
    static var jottTagBlush: SwiftUI.Color { .init(.jottTagBlush) }

    /// The "jott-tag-cream" asset catalog color.
    static var jottTagCream: SwiftUI.Color { .init(.jottTagCream) }

    /// The "jott-tag-mint" asset catalog color.
    static var jottTagMint: SwiftUI.Color { .init(.jottTagMint) }

    /// The "jott-tag-periwinkle" asset catalog color.
    static var jottTagPeriwinkle: SwiftUI.Color { .init(.jottTagPeriwinkle) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "JottMenuBar" asset catalog image.
    static var jottMenuBar: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .jottMenuBar)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "JottMenuBar" asset catalog image.
    static var jottMenuBar: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .jottMenuBar)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif


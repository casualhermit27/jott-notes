import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Folder Color Tag (pastel presets)

enum FolderColorTag: String, CaseIterable, Codable {
    case lavender, sky, sage, peach, butter, blush, mint, stone, rose, sand

    var color: Color {
        switch self {
        case .lavender: return Color(r: 0.76, g: 0.70, b: 0.94)
        case .sky:      return Color(r: 0.64, g: 0.82, b: 0.95)
        case .sage:     return Color(r: 0.70, g: 0.86, b: 0.74)
        case .peach:    return Color(r: 0.98, g: 0.78, b: 0.66)
        case .butter:   return Color(r: 0.98, g: 0.94, b: 0.64)
        case .blush:    return Color(r: 0.96, g: 0.74, b: 0.80)
        case .mint:     return Color(r: 0.68, g: 0.92, b: 0.84)
        case .stone:    return Color(r: 0.78, g: 0.78, b: 0.84)
        case .rose:     return Color(r: 0.94, g: 0.72, b: 0.76)
        case .sand:     return Color(r: 0.92, g: 0.86, b: 0.74)
        }
    }
}

// MARK: - Note Folder

struct NoteFolder: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var colorTag: FolderColorTag
    /// Optional hex override when user picks a custom pastel colour.
    var customColorHex: String?
    var createdAt: Date
    var modifiedAt: Date
    /// Parent folder id for nested folders (nil = root level).
    var parentId: UUID?

    init(id: UUID = UUID(), name: String,
         colorTag: FolderColorTag = .lavender,
         customColorHex: String? = nil,
         createdAt: Date = Date(),
         modifiedAt: Date = Date(),
         parentId: UUID? = nil) {
        self.id = id
        self.name = name
        self.colorTag = colorTag
        self.customColorHex = customColorHex
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.parentId = parentId
    }

    /// Resolved display colour — custom hex if set, else preset.
    var displayColor: Color {
        if let hex = customColorHex, let c = Color(hexString: hex) { return c }
        return colorTag.color
    }
}

extension NoteFolder {
    enum CodingKeys: String, CodingKey {
        case id, name, colorTag, customColorHex, createdAt, modifiedAt, parentId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        colorTag = (try? c.decode(FolderColorTag.self, forKey: .colorTag)) ?? .lavender
        customColorHex = try? c.decode(String.self, forKey: .customColorHex)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? createdAt
        parentId = try? c.decode(UUID.self, forKey: .parentId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(colorTag, forKey: .colorTag)
        try c.encodeIfPresent(customColorHex, forKey: .customColorHex)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(parentId, forKey: .parentId)
    }
}

// MARK: - Color hex helpers

extension Color {
    init?(hexString: String) {
        let h = hexString.trimmingCharacters(in: .alphanumerics.inverted)
        guard h.count == 6, let int = UInt64(h, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func toHexString() -> String? {
#if os(macOS)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "%02X%02X%02X",
                      Int(c.redComponent   * 255),
                      Int(c.greenComponent * 255),
                      Int(c.blueComponent  * 255))
#else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
#endif
    }
}

private extension Color {
    init(r: Double, g: Double, b: Double) { self.init(red: r, green: g, blue: b) }
}

import Foundation
import SwiftUI

struct Cluster: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var colorHex: String
    var isCollapsed: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Cluster",
        x: CGFloat = 60,
        y: CGFloat = 60,
        width: CGFloat = 300,
        height: CGFloat = 260,
        colorHex: String = "#5E6AD2",
        isCollapsed: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.x = x; self.y = y
        self.width = width; self.height = height
        self.colorHex = colorHex
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, x, y, width, height, colorHex, isCollapsed, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        x = try c.decode(CGFloat.self, forKey: .x)
        y = try c.decode(CGFloat.self, forKey: .y)
        width = try c.decode(CGFloat.self, forKey: .width)
        height = try c.decode(CGFloat.self, forKey: .height)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encode(isCollapsed, forKey: .isCollapsed)
        try c.encode(createdAt, forKey: .createdAt)
    }

    var tintColor: Color {
        Color.fromHex(colorHex)
    }

    // Palette used when creating new clusters (cycles by count)
    static let palette: [String] = [
        "#5E6AD2", // indigo
        "#26B5A0", // teal
        "#E27D5F", // coral
        "#B88DE0", // lavender
        "#5BA55B", // green
        "#E5A34C", // amber
    ]
}

extension Color {
    static func fromHex(_ hex: String) -> Color {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                   .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        return Color(
            red:   Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >>  8) / 255.0,
            blue:  Double( rgb & 0x0000FF       ) / 255.0
        )
    }
}

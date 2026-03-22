import SwiftUI

extension Color {
    // Primary sage/jott green tint
    static let jottGreen = Color(red: 0.58, green: 0.73, blue: 0.62)       // #94BAA0
    static let jottSage = Color(red: 0.72, green: 0.78, blue: 0.70)        // #B8C7B3
    static let jottLavender = Color(red: 0.76, green: 0.72, blue: 0.82)    // #C2B8D1

    // Tag chip colors (cycle through by tag hash)
    static let tagColors: [Color] = [
        Color(red: 0.88, green: 0.96, blue: 0.88),   // mint
        Color(red: 0.96, green: 0.92, blue: 0.84),   // cream
        Color(red: 0.86, green: 0.90, blue: 0.96),   // periwinkle
        Color(red: 0.96, green: 0.88, blue: 0.92),   // blush
    ]

    static func tagColor(for tag: String) -> Color {
        tagColors[abs(tag.hashValue) % tagColors.count]
    }
}

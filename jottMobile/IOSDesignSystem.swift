import SwiftUI

// MARK: - Design tokens (mirrors macOS JottDS exactly)

struct JottDS {
    let isDark: Bool

    var canvas:      Color { isDark ? Color(red: 0.095, green: 0.095, blue: 0.100) : Color(red: 0.985, green: 0.983, blue: 0.976) }
    var surface:     Color { isDark ? Color(red: 0.132, green: 0.132, blue: 0.140) : Color(red: 0.998, green: 0.996, blue: 0.992) }
    var surfaceAlt:  Color { isDark ? Color(red: 0.155, green: 0.155, blue: 0.165) : Color(red: 0.952, green: 0.950, blue: 0.944) }
    var hairline:    Color { isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.07) }
    var hairlineMid: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.12) }
    var ink:         Color { isDark ? Color(white: 0.95) : Color(red: 0.14, green: 0.14, blue: 0.15) }
    var inkMute:     Color { isDark ? Color(white: 0.68) : Color(red: 0.36, green: 0.36, blue: 0.39) }
    var inkFaint:    Color { isDark ? Color(white: 0.50) : Color(red: 0.52, green: 0.52, blue: 0.55) }
    var inkFaintest: Color { isDark ? Color(white: 0.38) : Color(red: 0.70, green: 0.70, blue: 0.73) }
    var accent:      Color { isDark ? Color(red: 0.58, green: 0.48, blue: 0.88) : Color(red: 0.42, green: 0.30, blue: 0.76) }
    var accentSoft:  Color { accent.opacity(isDark ? 0.14 : 0.10) }
    var accentRing:  Color { accent.opacity(isDark ? 0.52 : 0.42) }
}

// MARK: - Typography helpers

extension Font {
    static func jottTitle(_ size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func jottBody(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func jottCaption(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func jottMono(_ size: CGFloat = 10.5, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Animations (mirrors macOS JottMotion)

enum JottMotion {
    static let standard = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let micro    = Animation.spring(response: 0.18, dampingFraction: 0.86)
    static let content  = Animation.easeOut(duration: 0.16)
}

// MARK: - Date formatting

func jottShortDate(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM d"
    return fmt.string(from: date)
}

func jottMetaDate(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "d MMM"
    return fmt.string(from: date).uppercased()
}

func jottRelativeDate(_ date: Date) -> String {
    let fmt = RelativeDateTimeFormatter()
    fmt.unitsStyle = .abbreviated
    return fmt.localizedString(for: date, relativeTo: Date())
}

// MARK: - Note preview helper

func jottNotePreview(_ note: Note) -> (title: String, body: String) {
    let lines = note.text.components(separatedBy: "\n")
    let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

    func isPreviewNoise(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("![") ||
               t.hasPrefix("[") ||
               t.hasPrefix("http") ||
               MarkdownConverter.isPotentialMarkdownTableLine(t)
    }

    var previewLines: [String] = []
    var i = 0
    while i < lines.count {
        let t = lines[i].trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            i += 1
            continue
        }
        if MarkdownConverter.isPotentialMarkdownTableLine(t) {
            i += 1
            while i < lines.count, MarkdownConverter.isPotentialMarkdownTableLine(lines[i].trimmingCharacters(in: .whitespaces)) {
                i += 1
            }
            continue
        }
        if !isPreviewNoise(lines[i]) {
            previewLines.append(lines[i])
        }
        i += 1
    }

    let titleLine = previewLines.first ?? nonEmpty.first(where: { !isPreviewNoise($0) }) ?? ""

    var title = titleLine.trimmingCharacters(in: .whitespaces)
    while title.hasPrefix("#") { title = String(title.dropFirst()) }
    title = title.trimmingCharacters(in: .whitespaces)
    if title.isEmpty { title = note.text.contains("|") ? "Table" : "Untitled" }

    let bodyLines = previewLines.dropFirst().prefix(2)
    var body = bodyLines
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !isPreviewNoise($0) }
        .joined(separator: " ")
    if body.isEmpty, note.text.contains("|"), title != "Table" {
        body = "Table"
    }

    return (title, body)
}

// MARK: - Search highlight helper

/// Returns an AttributedString with all occurrences of `query` highlighted in `highlightColor`.
func highlightedAttributedString(
    _ text: String,
    matching query: String,
    size: CGFloat,
    weight: Font.Weight = .regular,
    baseColor: Color,
    highlightColor: Color
) -> AttributedString {
    var attributed = AttributedString(text)
    attributed.foregroundColor = baseColor
    attributed.font = .system(size: size, weight: weight)

    guard !query.isEmpty,
          let regex = try? NSRegularExpression(
              pattern: NSRegularExpression.escapedPattern(for: query),
              options: .caseInsensitive
          )
    else { return attributed }

    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    for match in matches {
        guard let range = Range(match.range, in: text),
              let attrLower = AttributedString.Index(range.lowerBound, within: attributed),
              let attrUpper = AttributedString.Index(range.upperBound, within: attributed)
        else { continue }
        attributed[attrLower..<attrUpper].foregroundColor = highlightColor
        attributed[attrLower..<attrUpper].font = .system(size: size, weight: .semibold)
    }
    return attributed
}

// MARK: - Tag chip

struct JottTagChip: View {
    let tag: String
    let ds: JottDS

    var body: some View {
        Text("#\(tag)")
            .font(.jottCaption(11, weight: .medium))
            .foregroundStyle(ds.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(ds.accentSoft, in: Capsule())
    }
}

// MARK: - Folder dot

struct JottFolderDot: View {
    let folder: NoteFolder

    var body: some View {
        Circle()
            .fill(folder.colorTag.color)
            .frame(width: 8, height: 8)
    }
}

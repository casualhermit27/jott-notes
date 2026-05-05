import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Block model

/// A parsed block with a stable ID (survives re-renders; useful for AI targeting).
struct MDBlock: Identifiable {
    let id = UUID()
    let kind: MDBlockKind
    /// Text content with block prefix stripped (e.g. "# " removed for headings).
    let content: String
}

enum MDBlockKind {
    case heading(level: Int)
    case bullet
    case taskItem(checked: Bool)
    case orderedItem(n: Int)
    case codeBlock(lang: String?)
    case blockquote
    case divider
    case table(headers: [String], rows: [[String]])
    case image(path: String, alt: String)
    case paragraph          // may contain inline image markdown
}

func jottDisplayBlocks(from blocks: [Block]) -> [Block] {
    var result: [Block] = []
    var i = 0

    while i < blocks.count {
        if let table = legacyTableBlock(startingAt: i, in: blocks) {
            result.append(table.block)
            i = table.nextIndex
            continue
        }

        result.append(blocks[i])
        i += 1
    }

    return result
}

private func legacyTableBlock(startingAt index: Int, in blocks: [Block]) -> (block: Block, nextIndex: Int)? {
    var lines: [String] = []
    var j = index

    while j < blocks.count, let line = legacyTableLine(from: blocks[j]) {
        lines.append(line)
        j += 1
    }

    guard let table = MarkdownConverter.parseTableComponents(lines) else { return nil }
    return (Block(type: .table, tableHeaders: table.headers, tableRows: table.rows), j)
}

private func legacyTableLine(from block: Block) -> String? {
    switch block.type {
    case .paragraph, .heading, .bulletItem, .numberedItem, .taskItem, .quote:
        let line = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MarkdownConverter.isPotentialMarkdownTableLine(line) else { return nil }
        return line
    default:
        return nil
    }
}

// MARK: - Block parser

func mdParseBlocks(_ raw: String) -> [MDBlock] {
    var result: [MDBlock] = []
    let lines = raw.components(separatedBy: "\n")
    var i = 0

    while i < lines.count {
        let line = lines[i]
        let t = line.trimmingCharacters(in: .whitespaces)

        // Fenced code block
        if t.hasPrefix("```") {
            let lang: String? = {
                let s = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                return s.isEmpty ? nil : s
            }()
            var code: [String] = []
            i += 1
            while i < lines.count {
                let cl = lines[i].trimmingCharacters(in: .whitespaces)
                if cl.hasPrefix("```") { i += 1; break }
                code.append(lines[i])
                i += 1
            }
            result.append(MDBlock(kind: .codeBlock(lang: lang),
                                  content: code.joined(separator: "\n")))
            continue
        }

        // Headings
        if t.hasPrefix("### ")      { result.append(MDBlock(kind: .heading(level: 3), content: String(t.dropFirst(4)))); i += 1; continue }
        if t.hasPrefix("## ")       { result.append(MDBlock(kind: .heading(level: 2), content: String(t.dropFirst(3)))); i += 1; continue }
        if t.hasPrefix("# ")        { result.append(MDBlock(kind: .heading(level: 1), content: String(t.dropFirst(2)))); i += 1; continue }

        // Divider
        if t == "---" || t == "***" || t == "___" { result.append(MDBlock(kind: .divider, content: "")); i += 1; continue }

        // Table
        if MarkdownConverter.isPotentialMarkdownTableLine(t) {
            var tableLines = [t]
            var j = i + 1
            while j < lines.count {
                let next = lines[j].trimmingCharacters(in: .whitespaces)
                guard MarkdownConverter.isPotentialMarkdownTableLine(next) else { break }
                tableLines.append(next)
                j += 1
            }
            if let table = mdParseTable(tableLines) {
                result.append(table)
                i = j
                continue
            }
        }

        // Blockquote
        if t.hasPrefix("> ") { result.append(MDBlock(kind: .blockquote, content: String(t.dropFirst(2)))); i += 1; continue }
        if t == ">"           { result.append(MDBlock(kind: .blockquote, content: "")); i += 1; continue }

        // Task items (must check before bullets)
        if t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") {
            let checked = !t.hasPrefix("- [ ] ")
            result.append(MDBlock(kind: .taskItem(checked: checked), content: String(t.dropFirst(6))))
            i += 1; continue
        }

        // Bullets
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") || t.hasPrefix("• ") {
            result.append(MDBlock(kind: .bullet, content: String(t.dropFirst(2)))); i += 1; continue
        }

        // Ordered list
        if let r = t.range(of: #"^\d+\. "#, options: .regularExpression) {
            let marker = String(t[r])
            let numStr = marker.split(separator: ".").first.map(String.init) ?? "1"
            let n = Int(numStr) ?? 1
            result.append(MDBlock(kind: .orderedItem(n: n), content: String(t[r.upperBound...]))); i += 1; continue
        }

        // Image: ![alt](path)
        if t.hasPrefix("!["), let parenOpen = t.firstIndex(of: "("), let parenClose = t.lastIndex(of: ")"),
           let bracketClose = t.firstIndex(of: "]"), bracketClose < parenOpen {
            let alt = String(t[t.index(t.startIndex, offsetBy: 2)..<bracketClose])
            let path = String(t[t.index(after: parenOpen)..<parenClose])
            result.append(MDBlock(kind: .image(path: path, alt: alt), content: path))
            i += 1; continue
        }

        // Empty line — skip
        if t.isEmpty { i += 1; continue }

        // Paragraph
        result.append(MDBlock(kind: .paragraph, content: line))
        i += 1
    }

    return result
}

private func mdParseTable(_ lines: [String]) -> MDBlock? {
    guard let table = MarkdownConverter.parseTableComponents(lines) else { return nil }
    return MDBlock(kind: .table(headers: table.headers, rows: table.rows), content: "")
}

// MARK: - Inline AttributedString renderer

/// Renders inline spans (bold, italic, underline, strikethrough, code, highlight, links)
/// as an AttributedString. Uses MarkdownConverter.parseInlineSpans as the source of truth.
func mdInlineAttributedString(
    _ text: String,
    baseFont: Font,
    baseColor: Color,
    codeBackground: Color = Color.secondary.opacity(0.12),
    baseSize: CGFloat = 15,
    baseWeight: Font.Weight = .regular,
    baseItalic: Bool = false
) -> AttributedString {
    let spans = MarkdownConverter.parseInlineSpans(text)
    var result = AttributedString()

    for span in spans {
        var s = AttributedString(span.text)
        s.foregroundColor = baseColor

        if span.code {
            s.font = .system(size: baseSize, design: .monospaced)
            s.backgroundColor = codeBackground
        } else {
            let w: Font.Weight = span.bold ? .bold : baseWeight
            var f = Font.system(size: baseSize, weight: w)
            if baseItalic || span.italic { f = f.italic() }
            s.font = f
        }
        if span.underline     { s.underlineStyle = .single }
        if span.strikethrough { s.strikethroughStyle = .single }
        if span.highlight     { s.backgroundColor = Color.yellow.opacity(0.38) }
        if let url = span.linkURL, let u = URL(string: url) { s.link = u }

        result.append(s)
    }

    return result.characters.isEmpty ? AttributedString(text) : result
}

// MARK: - Block renderer (SwiftUI)

struct MarkdownRichView<ParagraphContent: View>: View {
    let text: String
    let isDarkMode: Bool
    var onDoubleTap: (() -> Void)? = nil
    /// Caller-provided renderer for paragraph blocks (needed to access private types in DetailView).
    let paragraphContent: (String) -> ParagraphContent

    private var blocks: [MDBlock] { mdParseBlocks(text) }

    private var ink: Color { isDarkMode ? Color(white: 0.92) : Color("jott-input-text") }
    private var inkMute: Color { isDarkMode ? Color(white: 0.60) : Color(white: 0.42) }
    private var accent: Color { isDarkMode ? Color(red: 0.58, green: 0.50, blue: 0.92) : Color(red: 0.42, green: 0.30, blue: 0.76) }
    private var codeBG: Color { isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05) }
    private var quoteBorder: Color { accent.opacity(0.45) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in
                blockView(block)
                    .onTapGesture(count: 2) { onDoubleTap?() }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block.kind {

        case .heading(let level):
            let (size, weight): (CGFloat, Font.Weight) = level == 1 ? (19, .bold)
                : level == 2 ? (16, .semibold) : (14, .semibold)
            Text(mdInlineAttributedString(block.content,
                                         baseFont: .system(size: size, weight: weight),
                                         baseColor: ink,
                                         baseSize: size,
                                         baseWeight: weight))
                .font(.system(size: size, weight: weight))
                .padding(.top, level == 1 ? 6 : 2)
                .padding(.bottom, 2)

        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("·")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 12, alignment: .center)
                Text(mdInlineAttributedString(block.content,
                                             baseFont: .system(size: 15),
                                             baseColor: ink,
                                             codeBackground: codeBG,
                                             baseSize: 15))
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .taskItem(let checked):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(checked ? accent : inkMute)
                    .frame(width: 18, alignment: .center)
                Text(mdInlineAttributedString(block.content,
                                             baseFont: .system(size: 15),
                                             baseColor: checked ? inkMute : ink,
                                             codeBackground: codeBG,
                                             baseSize: 15))
                    .font(.system(size: 15))
                    .strikethrough(checked, color: inkMute)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .orderedItem(let n):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(inkMute)
                    .frame(width: 22, alignment: .trailing)
                Text(mdInlineAttributedString(block.content,
                                             baseFont: .system(size: 15),
                                             baseColor: ink,
                                             codeBackground: codeBG,
                                             baseSize: 15))
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .codeBlock:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(isDarkMode
                        ? Color(red: 0.75, green: 0.95, blue: 0.80)
                        : Color(red: 0.10, green: 0.40, blue: 0.20))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1))

        case .blockquote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(quoteBorder)
                    .frame(width: 2.5)
                    .clipShape(Capsule())
                Text(mdInlineAttributedString(block.content,
                                             baseFont: .system(size: 15).italic(),
                                             baseColor: inkMute,
                                             codeBackground: codeBG,
                                             baseSize: 15,
                                             baseItalic: true))
                    .font(.system(size: 15).italic())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)

        case .divider:
            Divider()
                .opacity(isDarkMode ? 0.20 : 0.15)
                .padding(.vertical, 4)

        case .table(let headers, let rows):
            MDTableView(headers: headers, rows: rows, isDarkMode: isDarkMode)

        case .image(let path, _):
            MDAttachmentImageView(path: path)

        case .paragraph:
            paragraphContent(block.content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MDAttachmentImageView: View {
    let path: String

    private var url: URL { NoteStore.shared.attachmentURL(for: path) }

    var body: some View {
        Group {
            #if os(macOS)
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 480)
                    .cornerRadius(6)
            } else {
                imagePlaceholder
            }
            #else
            if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .cornerRadius(6)
            } else {
                imagePlaceholder
            }
            #endif
        }
        .padding(.vertical, 4)
    }

    private var imagePlaceholder: some View {
        Label("Image not available", systemImage: "photo")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
    }
}

struct MDTableView: View {
    let headers: [String]
    let rows: [[String]]
    let isDarkMode: Bool

    private var border: Color { isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.10) }
    private var headerBG: Color { isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.035) }
    private var cellBG: Color { isDarkMode ? Color.white.opacity(0.025) : Color.white.opacity(0.65) }
    private var ink: Color { isDarkMode ? Color(white: 0.92) : Color("jott-input-text") }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        cell(header.isEmpty ? " " : header, isHeader: true)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<headers.count, id: \.self) { index in
                            cell(index < row.count ? row[index] : " ", isHeader: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(border, lineWidth: 1))
        }
        .padding(.vertical, 4)
    }

    private func cell(_ text: String, isHeader: Bool) -> some View {
        let cellWeight: Font.Weight = isHeader ? .semibold : .regular
        return Text(mdInlineAttributedString(text, baseFont: .system(size: 13, weight: cellWeight), baseColor: ink, baseSize: 13, baseWeight: cellWeight))
            .font(.system(size: 13, weight: isHeader ? .semibold : .regular))
            .lineLimit(nil)
            .frame(minWidth: 92, maxWidth: 180, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHeader ? headerBG : cellBG)
            .overlay(Rectangle().stroke(border, lineWidth: 0.5))
    }
}

// MARK: - Editor syntax highlighting

#if os(macOS)
extension NSTextStorage {
    /// Applies visual markdown syntax highlighting without changing the underlying string.
    /// Call this after every text change in JottNativeInput.
    func applyMarkdownHighlighting(baseFont: NSFont, baseColor: NSColor, isDark: Bool, ghostStart: Int? = nil) {
        guard length > 0 else { return }

        // Only operate on the real text, never the ghost suffix
        let realLength = ghostStart ?? length
        guard realLength > 0 else { return }

        let raw = (string as NSString).substring(to: realLength)
        let accent = isDark
            ? NSColor(srgbRed: 0.58, green: 0.50, blue: 0.92, alpha: 1)
            : NSColor(srgbRed: 0.42, green: 0.30, blue: 0.76, alpha: 1)
        let dimColor = isDark
            ? NSColor(white: 0.45, alpha: 1)
            : NSColor(white: 0.68, alpha: 1)
        let codeColor = isDark
            ? NSColor(srgbRed: 0.75, green: 0.95, blue: 0.80, alpha: 1)
            : NSColor(srgbRed: 0.10, green: 0.40, blue: 0.20, alpha: 1)
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)

        beginEditing()

        // Reset real text to base (leave ghost range untouched)
        let fullRange = NSRange(location: 0, length: realLength)
        addAttribute(.font, value: baseFont, range: fullRange)
        addAttribute(.foregroundColor, value: baseColor, range: fullRange)
        removeAttribute(.backgroundColor, range: fullRange)

        let lines = raw.components(separatedBy: "\n")
        var charOffset = 0
        let highlightBG = isDark
            ? NSColor(srgbRed: 0.80, green: 0.72, blue: 0.15, alpha: 0.35)
            : NSColor(srgbRed: 1.00, green: 0.92, blue: 0.20, alpha: 0.50)
        let hlRegex = try? NSRegularExpression(pattern: #"==(.+?)=="#)

        for line in lines {
            let lineLen = (line as NSString).length
            let t = line.trimmingCharacters(in: .whitespaces)
            let prefixLen: Int

            if t.hasPrefix("### ") { prefixLen = 4 }
            else if t.hasPrefix("## ") { prefixLen = 3 }
            else if t.hasPrefix("# ") { prefixLen = 2 }
            else { prefixLen = 0 }

            if prefixLen > 0 {
                // Dim the # prefix, enlarge + bold the heading text
                let hashRange = NSRange(location: charOffset, length: prefixLen)
                let textRange = NSRange(location: charOffset + prefixLen, length: lineLen - prefixLen)
                addAttribute(.foregroundColor, value: dimColor, range: hashRange)
                let headingSize: CGFloat = prefixLen == 2 ? baseFont.pointSize + 5
                    : prefixLen == 3 ? baseFont.pointSize + 2
                    : baseFont.pointSize + 1
                let headingFont = NSFont.systemFont(ofSize: headingSize, weight: prefixLen == 2 ? .bold : .semibold)
                addAttribute(.font, value: headingFont, range: textRange)
                addAttribute(.foregroundColor, value: baseColor, range: textRange)
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") || t.hasPrefix("• ") {
                // Dim bullet prefix, colour the dot
                let dashRange = NSRange(location: charOffset, length: 1)
                addAttribute(.foregroundColor, value: accent, range: dashRange)
            } else if t.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                let markerLength = (t as NSString).range(of: #"^\d+\. "#, options: .regularExpression).length
                addAttribute(.foregroundColor, value: dimColor, range: NSRange(location: charOffset, length: markerLength))
            } else if t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") {
                addAttribute(.foregroundColor, value: accent, range: NSRange(location: charOffset, length: min(6, lineLen)))
            } else if t.hasPrefix("> ") {
                // Dim blockquote marker, italicise body
                let gtRange = NSRange(location: charOffset, length: 2)
                addAttribute(.foregroundColor, value: dimColor, range: gtRange)
                let bodyRange = NSRange(location: charOffset + 2, length: max(0, lineLen - 2))
                addAttribute(.font, value: italicFont, range: bodyRange)
            }

            // Inline patterns within the line
            applyInlinePattern(#"\*\*(.+?)\*\*"#, in: line, lineOffset: charOffset,
                               markerAttr: (.foregroundColor, dimColor),
                               contentAttr: (.font, boldFont))
            applyInlinePattern(#"\*(.+?)\*"#, in: line, lineOffset: charOffset,
                               markerAttr: (.foregroundColor, dimColor),
                               contentAttr: (.font, italicFont))
            applyInlinePattern(#"`([^`]+)`"#, in: line, lineOffset: charOffset,
                               markerAttr: (.foregroundColor, dimColor),
                               contentAttr: (.font, monoFont),
                               contentColor: codeColor)
            applyInlinePattern(#"__(.+?)__"#, in: line, lineOffset: charOffset,
                               markerAttr: (.foregroundColor, dimColor),
                               contentAttr: (.underlineStyle, NSUnderlineStyle.single.rawValue))
            applyInlinePattern(#"~~(.+?)~~"#, in: line, lineOffset: charOffset,
                               markerAttr: (.foregroundColor, dimColor),
                               contentAttr: (.strikethroughStyle, NSUnderlineStyle.single.rawValue))
            if let hlRegex {
                let nsLine = line as NSString
                for m in hlRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                    let fullR = NSRange(location: charOffset + m.range.location, length: m.range.length)
                    let innerR = NSRange(location: charOffset + m.range(at: 1).location, length: m.range(at: 1).length)
                    addAttribute(.foregroundColor, value: dimColor, range: fullR)
                    addAttribute(.backgroundColor, value: highlightBG, range: innerR)
                    addAttribute(.foregroundColor, value: baseColor, range: innerR)
                }
            }

            // +1 for the newline character
            charOffset += lineLen + 1
        }

        endEditing()
    }

    private func applyInlinePattern(
        _ pattern: String,
        in line: String,
        lineOffset: Int,
        markerAttr: (NSAttributedString.Key, Any),
        contentAttr: (NSAttributedString.Key, Any),
        contentColor: NSColor? = nil
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))

        for match in matches {
            let fullRange = NSRange(location: lineOffset + match.range.location, length: match.range.length)
            let contentNSRange = match.range(at: 1)
            let contentRange = NSRange(location: lineOffset + contentNSRange.location, length: contentNSRange.length)

            // Dim the full match first (covers markers)
            addAttribute(markerAttr.0, value: markerAttr.1, range: fullRange)
            // Then apply content styling
            addAttribute(contentAttr.0, value: contentAttr.1, range: contentRange)
            if let cc = contentColor {
                addAttribute(.foregroundColor, value: cc, range: contentRange)
            }
        }
    }
}
#endif

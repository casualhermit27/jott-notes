import Foundation

// MARK: - MarkdownConverter

/// Converts between Markdown text and [Block].
///
/// parse()  – Markdown → [Block]   (source of truth ingestion / migration)
/// export() – [Block]  → Markdown  (copy, share, export)
enum MarkdownConverter {

    // MARK: - Export

    static func export(_ blocks: [Block]) -> String {
        blocks.map(\.markdown).joined(separator: "\n\n")
    }

    // MARK: - Spans → Markdown

    static func spansToMarkdown(_ spans: [TextSpan]) -> String {
        spans.map { span -> String in
            var s = span.text
            if span.code          { return "`\(s)`" }
            if span.bold && span.italic { return "***\(s)***" }
            if span.bold          { s = "**\(s)**" }
            if span.italic        { s = "*\(s)*" }
            if span.underline     { s = "__\(s)__" }
            if span.strikethrough { s = "~~\(s)~~" }
            if span.highlight     { s = "==\(s)==" }
            if let url = span.linkURL { return "[\(s)](\(url))" }
            return s
        }.joined()
    }

    // MARK: - Parse

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        let rawLines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < rawLines.count {
            let line = rawLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // ── Fenced code block ──────────────────────────────────────
            if trimmed.hasPrefix("```") {
                let lang: String? = {
                    let rest = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    return rest.isEmpty ? nil : rest
                }()
                var codeLines: [String] = []
                i += 1
                while i < rawLines.count {
                    let cl = rawLines[i]
                    if cl.trimmingCharacters(in: .whitespaces).hasPrefix("```") { i += 1; break }
                    codeLines.append(cl)
                    i += 1
                }
                blocks.append(Block(type: .codeBlock,
                                    language: lang,
                                    code: codeLines.joined(separator: "\n")))
                continue
            }

            // ── Divider ────────────────────────────────────────────────
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(Block(type: .divider))
                i += 1
                continue
            }

            // ── Heading ────────────────────────────────────────────────
            if trimmed.hasPrefix("#") {
                var level = 0
                var rest = trimmed
                while rest.hasPrefix("#") { level += 1; rest = String(rest.dropFirst()) }
                level = min(max(level, 1), 3)
                let text = rest.trimmingCharacters(in: .whitespaces)
                blocks.append(Block(type: .heading,
                                    spans: parseInlineSpans(text),
                                    level: level))
                i += 1
                continue
            }

            // ── Blockquote ─────────────────────────────────────────────
            if trimmed.hasPrefix(">") {
                let text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(Block(type: .quote, spans: parseInlineSpans(text)))
                i += 1
                continue
            }

            // ── Task item ─────────────────────────────────────────────
            if let (checked, text) = parseTaskItem(trimmed) {
                blocks.append(Block(type: .taskItem,
                                    spans: parseInlineSpans(text),
                                    checked: checked))
                i += 1
                continue
            }

            // ── Bullet item ───────────────────────────────────────────
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
               trimmed.hasPrefix("+ ") || trimmed.hasPrefix("• ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(Block(type: .bulletItem, spans: parseInlineSpans(text)))
                i += 1
                continue
            }

            // ── Numbered item ─────────────────────────────────────────
            if let text = parseNumberedItem(trimmed) {
                blocks.append(Block(type: .numberedItem, spans: parseInlineSpans(text)))
                i += 1
                continue
            }

            // ── Image ─────────────────────────────────────────────────
            if trimmed.hasPrefix("![") {
                let (alt, url) = parseImageMarkdown(trimmed)
                blocks.append(Block(type: .image, imageURL: url, imageAlt: alt))
                i += 1
                continue
            }

            // ── Table ─────────────────────────────────────────────────
            if isPotentialMarkdownTableLine(trimmed) {
                // Collect contiguous table-looking lines. Markdown allows
                // optional outer pipes, so "A | B" is valid table syntax too.
                var tableLines: [String] = [trimmed]
                var j = i + 1
                while j < rawLines.count {
                    let tl = rawLines[j].trimmingCharacters(in: .whitespaces)
                    if isPotentialMarkdownTableLine(tl) {
                        tableLines.append(tl)
                        j += 1
                    } else { break }
                }
                if let tableBlock = parseTable(tableLines) {
                    blocks.append(tableBlock)
                    i = j
                    continue
                }
            }

            // ── Empty line (paragraph separator) ─────────────────────
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // ── Paragraph (accumulate consecutive text lines) ─────────
            var paraLines: [String] = [trimmed]
            i += 1
            while i < rawLines.count {
                let next = rawLines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty { break }
                if isBlockStart(next) { break }
                paraLines.append(next)
                i += 1
            }
            let paraText = paraLines.joined(separator: " ")
            blocks.append(Block(type: .paragraph, spans: parseInlineSpans(paraText)))
        }

        return blocks
    }

    // MARK: - Private helpers

    private static func isBlockStart(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("#") ||
        trimmed.hasPrefix(">") ||
        trimmed.hasPrefix("```") ||
        trimmed.hasPrefix("- ") ||
        trimmed.hasPrefix("* ") ||
        trimmed.hasPrefix("+ ") ||
        trimmed.hasPrefix("• ") ||
        trimmed.hasPrefix("![") ||
        isPotentialMarkdownTableLine(trimmed) ||
        trimmed == "---" || trimmed == "***" || trimmed == "___" ||
        parseTaskItem(trimmed) != nil ||
        parseNumberedItem(trimmed) != nil
    }

    private static func parseTaskItem(_ s: String) -> (Bool, String)? {
        if s.hasPrefix("- [ ] ") { return (false, String(s.dropFirst(6))) }
        if s.hasPrefix("- [x] ") { return (true,  String(s.dropFirst(6))) }
        if s.hasPrefix("- [X] ") { return (true,  String(s.dropFirst(6))) }
        return nil
    }

    private static func parseNumberedItem(_ s: String) -> String? {
        // Matches "1. text", "12. text", etc.
        guard let dot = s.firstIndex(of: ".") else { return nil }
        let prefix = s[s.startIndex..<dot]
        guard prefix.allSatisfy(\.isNumber), !prefix.isEmpty else { return nil }
        let after = s[s.index(after: dot)...]
        guard after.hasPrefix(" ") else { return nil }
        return String(after.dropFirst())
    }

    private static func parseImageMarkdown(_ s: String) -> (alt: String, url: String) {
        // ![alt](url)
        guard let altStart = s.range(of: "!["),
              let altEnd   = s.range(of: "]("),
              let urlEnd   = s.lastIndex(of: ")") else { return ("", s) }
        let alt = String(s[s.index(altStart.upperBound, offsetBy: 0)..<altEnd.lowerBound])
        let urlRange = altEnd.upperBound..<urlEnd
        return (alt, String(s[urlRange]))
    }

    static func isPotentialMarkdownTableLine(_ line: String) -> Bool {
        containsUnescapedPipe(in: line.trimmingCharacters(in: .whitespaces))
    }

    static func parseTableComponents(_ lines: [String]) -> (headers: [String], rows: [[String]])? {
        guard lines.count >= 2 else { return nil }

        let headerCells = splitTableCells(lines[0])
        let separatorCells = splitTableCells(lines[1])
        guard !headerCells.isEmpty,
              !separatorCells.isEmpty,
              separatorCells.allSatisfy(isMarkdownTableSeparatorCell) else {
            return nil
        }

        let columnCount = max(headerCells.count, separatorCells.count)
        guard columnCount > 0 else { return nil }

        var headers = headerCells
        if headers.count < columnCount {
            headers += Array(repeating: "", count: columnCount - headers.count)
        }

        let rows = lines.dropFirst(2).map { line in
            normalizedRow(splitTableCells(line), columnCount: columnCount)
        }

        return (Array(headers.prefix(columnCount)), rows)
    }

    private static func parseTable(_ lines: [String]) -> Block? {
        guard let table = parseTableComponents(lines) else { return nil }
        return Block(type: .table, tableHeaders: table.headers, tableRows: table.rows)
    }

    private static func splitTableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.first == "|" {
            value.removeFirst()
        }
        if value.last == "|" {
            value.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var isEscaped = false

        for character in value {
            if isEscaped {
                if character == "|" {
                    current.append("|")
                } else {
                    current.append("\\")
                    current.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }

        if isEscaped {
            current.append("\\")
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func containsUnescapedPipe(in line: String) -> Bool {
        var isEscaped = false
        for character in line {
            if isEscaped {
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "|" {
                return true
            }
        }
        return false
    }

    private nonisolated static func isMarkdownTableSeparatorCell(_ cell: String) -> Bool {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        var body = trimmed
        if body.first == ":" {
            body.removeFirst()
        }
        if body.last == ":" {
            body.removeLast()
        }
        return body.count >= 3 && body.allSatisfy { $0 == "-" }
    }

    private static func normalizedRow(_ cells: [String], columnCount: Int) -> [String] {
        if cells.count < columnCount {
            return cells + Array(repeating: "", count: columnCount - cells.count)
        }
        return Array(cells.prefix(columnCount))
    }

    // MARK: - Inline span parser

    static func parseInlineSpans(_ text: String) -> [TextSpan] {
        guard !text.isEmpty else { return [TextSpan("")] }

        // Tokenize with a single regex covering all inline markup
        // Order matters: longer tokens first (*** before ** before *)
        let pattern =
            "(\\*\\*\\*(.+?)\\*\\*\\*)" +          // bold+italic
            "|(\\*\\*(.+?)\\*\\*)" +                // bold
            "|(__(.+?)__)" +                        // underline
            "|(\\*(.+?)\\*)" +                      // italic
            "|(_(.+?)_)" +                          // italic (alt)
            "|(~~(.+?)~~)" +                        // strikethrough
            "|(`(.+?)`)" +                          // inline code
            "|(==(.+?)==)" +                        // highlight
            "|(\\[(.+?)\\]\\((.+?)\\))" +           // [text](url)
            "|(\\!\\[(.+?)\\]\\((.+?)\\))"          // ![alt](url) — treat as link-text

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return [TextSpan(text)]
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)

        var spans: [TextSpan] = []
        var cursor = 0

        for match in matches {
            let matchStart = match.range.location

            // Append any plain text before this match
            if matchStart > cursor {
                let plain = nsText.substring(with: NSRange(location: cursor, length: matchStart - cursor))
                spans.append(TextSpan(plain))
            }

            // Determine which group fired
            if match.range(at: 1).location != NSNotFound {
                // ***bold+italic***
                let inner = nsText.substring(with: match.range(at: 2))
                spans.append(TextSpan(inner, bold: true, italic: true))
            } else if match.range(at: 3).location != NSNotFound {
                // **bold**
                let inner = nsText.substring(with: match.range(at: 4))
                spans.append(TextSpan(inner, bold: true))
            } else if match.range(at: 5).location != NSNotFound {
                // __underline__
                let inner = nsText.substring(with: match.range(at: 6))
                spans.append(TextSpan(inner, underline: true))
            } else if match.range(at: 7).location != NSNotFound {
                // *italic*
                let inner = nsText.substring(with: match.range(at: 8))
                spans.append(TextSpan(inner, italic: true))
            } else if match.range(at: 9).location != NSNotFound {
                // _italic_
                let inner = nsText.substring(with: match.range(at: 10))
                spans.append(TextSpan(inner, italic: true))
            } else if match.range(at: 11).location != NSNotFound {
                // ~~strikethrough~~
                let inner = nsText.substring(with: match.range(at: 12))
                spans.append(TextSpan(inner, strikethrough: true))
            } else if match.range(at: 13).location != NSNotFound {
                // `code`
                let inner = nsText.substring(with: match.range(at: 14))
                spans.append(TextSpan(inner, code: true))
            } else if match.range(at: 15).location != NSNotFound {
                // ==highlight==
                let inner = nsText.substring(with: match.range(at: 16))
                spans.append(TextSpan(inner, highlight: true))
            } else if match.range(at: 17).location != NSNotFound {
                // [text](url)
                let linkText = nsText.substring(with: match.range(at: 18))
                let url      = nsText.substring(with: match.range(at: 19))
                spans.append(TextSpan(linkText, linkURL: url))
            } else if match.range(at: 20).location != NSNotFound {
                // ![alt](url) — inside paragraph, treat as image link
                let alt = nsText.substring(with: match.range(at: 21))
                let url = nsText.substring(with: match.range(at: 22))
                spans.append(TextSpan(alt, linkURL: url))
            }

            cursor = match.range.location + match.range.length
        }

        // Remaining plain text
        if cursor < nsText.length {
            spans.append(TextSpan(nsText.substring(from: cursor)))
        }

        return spans.isEmpty ? [TextSpan(text)] : spans
    }
}

import Foundation

// MARK: - Inline text span

/// A run of text with optional formatting.  All formatting flags default to false
/// so JSON stays compact — only non-default values need to be stored.
struct TextSpan: Codable, Equatable, Hashable {
    var text:          String
    var bold:          Bool    = false
    var italic:        Bool    = false
    var underline:     Bool    = false
    var code:          Bool    = false
    var strikethrough: Bool    = false
    var highlight:     Bool    = false
    var linkURL:       String? = nil
    var noteRef:       UUID?   = nil   // backlink to another note

    private enum CodingKeys: String, CodingKey {
        case text
        case bold
        case italic
        case underline
        case code
        case strikethrough
        case highlight
        case linkURL
        case noteRef
    }

    init(_ text: String, bold: Bool = false, italic: Bool = false,
         underline: Bool = false,
         code: Bool = false, strikethrough: Bool = false,
         highlight: Bool = false,
         linkURL: String? = nil, noteRef: UUID? = nil) {
        self.text          = text
        self.bold          = bold
        self.italic        = italic
        self.underline     = underline
        self.code          = code
        self.strikethrough = strikethrough
        self.highlight     = highlight
        self.linkURL       = linkURL
        self.noteRef       = noteRef
    }

    var isPlain: Bool { !bold && !italic && !underline && !code && !strikethrough && !highlight && linkURL == nil && noteRef == nil }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try container.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        code = try container.decodeIfPresent(Bool.self, forKey: .code) ?? false
        strikethrough = try container.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
        highlight = try container.decodeIfPresent(Bool.self, forKey: .highlight) ?? false
        linkURL = try container.decodeIfPresent(String.self, forKey: .linkURL)
        noteRef = try container.decodeIfPresent(UUID.self, forKey: .noteRef)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        if bold { try container.encode(bold, forKey: .bold) }
        if italic { try container.encode(italic, forKey: .italic) }
        if underline { try container.encode(underline, forKey: .underline) }
        if code { try container.encode(code, forKey: .code) }
        if strikethrough { try container.encode(strikethrough, forKey: .strikethrough) }
        if highlight { try container.encode(highlight, forKey: .highlight) }
        try container.encodeIfPresent(linkURL, forKey: .linkURL)
        try container.encodeIfPresent(noteRef, forKey: .noteRef)
    }
}

// MARK: - Block type

enum BlockType: String, Codable, Equatable, CaseIterable {
    case paragraph
    case heading        // uses `level` (1, 2, 3)
    case bulletItem
    case numberedItem
    case taskItem
    case quote
    case codeBlock
    case table
    case divider
    case image
}

// MARK: - Block

/// A single content block.  Fields that don't apply to a block's type carry
/// their zero-value defaults and are harmless but compact in JSON.
struct Block: Identifiable, Codable, Equatable {
    var id:           UUID
    var type:         BlockType
    var spans:        [TextSpan]    // paragraph / heading / quote / list / task content
    var level:        Int           // heading level 1–3
    var checked:      Bool          // taskItem: whether ticked
    var tableHeaders: [String]      // table column headers
    var tableRows:    [[String]]    // table body rows
    var language:     String?       // codeBlock language hint
    var code:         String        // codeBlock body
    var imageURL:     String?
    var imageAlt:     String
    var meta:         [String: String]? // extensible plugin data

    init(
        id:           UUID              = UUID(),
        type:         BlockType,
        spans:        [TextSpan]        = [],
        level:        Int               = 1,
        checked:      Bool              = false,
        tableHeaders: [String]          = [],
        tableRows:    [[String]]        = [],
        language:     String?           = nil,
        code:         String            = "",
        imageURL:     String?           = nil,
        imageAlt:     String            = "",
        meta:         [String: String]? = nil
    ) {
        self.id           = id
        self.type         = type
        self.spans        = spans
        self.level        = level
        self.checked      = checked
        self.tableHeaders = tableHeaders
        self.tableRows    = tableRows
        self.language     = language
        self.code         = code
        self.imageURL     = imageURL
        self.imageAlt     = imageAlt
        self.meta         = meta
    }

    // MARK: Convenience

    /// Plain concatenated text of all spans (or code body for codeBlocks).
    var plainText: String {
        type == .codeBlock ? code : spans.map(\.text).joined()
    }

    /// Render block as Markdown.
    var markdown: String {
        switch type {
        case .paragraph:
            return MarkdownConverter.spansToMarkdown(spans)

        case .heading:
            let prefix = String(repeating: "#", count: max(1, min(level, 3)))
            return "\(prefix) \(MarkdownConverter.spansToMarkdown(spans))"

        case .bulletItem:
            return "- \(MarkdownConverter.spansToMarkdown(spans))"

        case .numberedItem:
            return "1. \(MarkdownConverter.spansToMarkdown(spans))"

        case .taskItem:
            return "- [\(checked ? "x" : " ")] \(MarkdownConverter.spansToMarkdown(spans))"

        case .quote:
            return "> \(MarkdownConverter.spansToMarkdown(spans))"

        case .codeBlock:
            let lang = language ?? ""
            return "```\(lang)\n\(code)\n```"

        case .table:
            guard !tableHeaders.isEmpty else { return "" }
            let header    = "| " + tableHeaders.joined(separator: " | ") + " |"
            let separator = "| " + tableHeaders.map { _ in "---" }.joined(separator: " | ") + " |"
            let rows      = tableRows.map { "| " + $0.joined(separator: " | ") + " |" }
            return ([header, separator] + rows).joined(separator: "\n")

        case .divider:
            return "---"

        case .image:
            return "![\(imageAlt)](\(imageURL ?? ""))"
        }
    }
}

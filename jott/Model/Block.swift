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
        case marks
        case link
        case bold
        case italic
        case underline
        case code
        case strikethrough
        case highlight
        case linkURL
        case noteRef
    }

    private enum LinkCodingKeys: String, CodingKey {
        case url
        case noteID
        case note_id
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
        let marks = Set((try container.decodeIfPresent([String].self, forKey: .marks) ?? []).map { $0.lowercased() })
        let legacyBold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        let legacyItalic = try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        let legacyUnderline = try container.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        let legacyCode = try container.decodeIfPresent(Bool.self, forKey: .code) ?? false
        let legacyStrikethrough = try container.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
        let legacyHighlight = try container.decodeIfPresent(Bool.self, forKey: .highlight) ?? false
        bold = marks.contains("bold") || legacyBold
        italic = marks.contains("italic") || legacyItalic
        underline = marks.contains("underline") || legacyUnderline
        code = marks.contains("inline_code") || marks.contains("code") || legacyCode
        strikethrough = marks.contains("strikethrough") || legacyStrikethrough
        highlight = marks.contains("highlight") || legacyHighlight
        linkURL = try container.decodeIfPresent(String.self, forKey: .linkURL)
        noteRef = try container.decodeIfPresent(UUID.self, forKey: .noteRef)
        if container.contains(.link) {
            let link = try container.nestedContainer(keyedBy: LinkCodingKeys.self, forKey: .link)
            linkURL = try link.decodeIfPresent(String.self, forKey: .url) ?? linkURL
            noteRef = try link.decodeIfPresent(UUID.self, forKey: .noteID)
                ?? link.decodeIfPresent(UUID.self, forKey: .note_id)
                ?? noteRef
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        var marks: [String] = []
        if bold { marks.append("bold") }
        if italic { marks.append("italic") }
        if underline { marks.append("underline") }
        if strikethrough { marks.append("strikethrough") }
        if code { marks.append("inline_code") }
        if highlight { marks.append("highlight") }
        if !marks.isEmpty { try container.encode(marks, forKey: .marks) }
        if linkURL != nil || noteRef != nil {
            var link = container.nestedContainer(keyedBy: LinkCodingKeys.self, forKey: .link)
            try link.encodeIfPresent(linkURL, forKey: .url)
            try link.encodeIfPresent(noteRef, forKey: .note_id)
        }
    }
}

// MARK: - Block type

enum BlockType: String, Codable, Equatable, CaseIterable {
    case paragraph
    case heading        // uses `level` (1, 2, 3)
    case bulletItem = "bullet_item"
    case numberedItem = "numbered_item"
    case taskItem = "task_item"
    case quote
    case codeBlock = "code_block"
    case table
    case divider
    case image
    case toggle

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "bulletItem": self = .bulletItem
        case "numberedItem": self = .numberedItem
        case "taskItem": self = .taskItem
        case "codeBlock": self = .codeBlock
        default:
            guard let type = BlockType(rawValue: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown block type: \(value)")
            }
            self = type
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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
    var children:     [Block]
    var props:        [String: String] // styling, metadata, plugin data

    var meta: [String: String]? {
        get { props.isEmpty ? nil : props }
        set { props = newValue ?? [:] }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case block_id
        case type
        case spans
        case richText
        case level
        case checked
        case tableHeaders
        case tableRows
        case language
        case code
        case imageURL
        case imageAlt
        case children
        case props
        case meta
    }

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
        children:     [Block]           = [],
        props:        [String: String]  = [:],
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
        self.children     = children
        self.props        = meta ?? props
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id)
            ?? c.decodeIfPresent(UUID.self, forKey: .block_id)
            ?? UUID()
        type = try c.decode(BlockType.self, forKey: .type)
        spans = try c.decodeIfPresent([TextSpan].self, forKey: .richText)
            ?? c.decodeIfPresent([TextSpan].self, forKey: .spans)
            ?? []
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
        checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        tableHeaders = try c.decodeIfPresent([String].self, forKey: .tableHeaders) ?? []
        tableRows = try c.decodeIfPresent([[String]].self, forKey: .tableRows) ?? []
        language = try c.decodeIfPresent(String.self, forKey: .language)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        imageAlt = try c.decodeIfPresent(String.self, forKey: .imageAlt) ?? ""
        children = try c.decodeIfPresent([Block].self, forKey: .children) ?? []
        props = try c.decodeIfPresent([String: String].self, forKey: .props)
            ?? c.decodeIfPresent([String: String].self, forKey: .meta)
            ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .block_id)
        try c.encode(type, forKey: .type)
        if !spans.isEmpty { try c.encode(spans, forKey: .richText) }
        if type == .heading { try c.encode(level, forKey: .level) }
        if type == .taskItem { try c.encode(checked, forKey: .checked) }
        if !tableHeaders.isEmpty { try c.encode(tableHeaders, forKey: .tableHeaders) }
        if !tableRows.isEmpty { try c.encode(tableRows, forKey: .tableRows) }
        try c.encodeIfPresent(language, forKey: .language)
        if !code.isEmpty { try c.encode(code, forKey: .code) }
        try c.encodeIfPresent(imageURL, forKey: .imageURL)
        if !imageAlt.isEmpty { try c.encode(imageAlt, forKey: .imageAlt) }
        if !children.isEmpty { try c.encode(children, forKey: .children) }
        if !props.isEmpty { try c.encode(props, forKey: .props) }
    }

    // MARK: Convenience

    /// Plain concatenated text of all spans (or code body for codeBlocks).
    var plainText: String {
        switch type {
        case .codeBlock:
            return code
        case .table:
            return (tableHeaders + tableRows.flatMap { $0 }).joined(separator: " ")
        case .image:
            return imageAlt
        default:
            return spans.map(\.text).joined()
        }
    }

    static func plainTextBlocks(from text: String) -> [Block] {
        let lines = text.components(separatedBy: .newlines)
        let blocks = lines.map { Block(type: .paragraph, spans: [TextSpan($0)]) }
        return blocks.isEmpty ? [Block(type: .paragraph, spans: [TextSpan("")])] : blocks
    }
}

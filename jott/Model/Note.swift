import Foundation

struct Note: Identifiable, Equatable, Hashable {
    var id: UUID
    var blocks: [Block]          // source of truth
    var links: [UUID]            // backlinks / outgoing note refs
    var tags: [String]
    let timestamp: Date
    var modifiedAt: Date
    var fileURL: URL?            // transient: not persisted
    var isPinned: Bool
    var clusterId: UUID?
    var parentId: UUID?
    var sortIndex: Int
    var folderId: UUID?
    var deletedAt: Date?

    /// Backward-compat shim: get exports blocks as Markdown, set re-parses Markdown into blocks.
    var text: String {
        get { MarkdownConverter.export(blocks) }
        set { blocks = MarkdownConverter.parse(newValue) }
    }

    /// Convenience title (first non-empty plain text from first block).
    var title: String {
        for block in blocks {
            let t = block.plainText.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return "Untitled"
    }

    init(id: UUID = UUID(),
         blocks: [Block],
         links: [UUID] = [],
         tags: [String] = [],
         timestamp: Date = Date(),
         modifiedAt: Date = Date(),
         fileURL: URL? = nil,
         isPinned: Bool = false,
         clusterId: UUID? = nil,
         parentId: UUID? = nil,
         sortIndex: Int = 0,
         folderId: UUID? = nil,
         deletedAt: Date? = nil) {
        self.id         = id
        self.blocks     = blocks
        self.links      = links
        self.tags       = tags
        self.timestamp  = timestamp
        self.modifiedAt = modifiedAt
        self.fileURL    = fileURL
        self.isPinned   = isPinned
        self.clusterId  = clusterId
        self.parentId   = parentId
        self.sortIndex  = sortIndex
        self.folderId   = folderId
        self.deletedAt  = deletedAt
    }

    /// Convenience: create a note from Markdown (used during migration and for new-note creation).
    init(id: UUID = UUID(),
         text: String,
         tags: [String] = [],
         timestamp: Date = Date(),
         modifiedAt: Date = Date(),
         fileURL: URL? = nil,
         isPinned: Bool = false,
         clusterId: UUID? = nil,
         parentId: UUID? = nil,
         sortIndex: Int = 0,
         folderId: UUID? = nil,
         deletedAt: Date? = nil) {
        self.id         = id
        self.blocks     = MarkdownConverter.parse(text)
        self.links      = []
        self.tags       = tags
        self.timestamp  = timestamp
        self.modifiedAt = modifiedAt
        self.fileURL    = fileURL
        self.isPinned   = isPinned
        self.clusterId  = clusterId
        self.parentId   = parentId
        self.sortIndex  = sortIndex
        self.folderId   = folderId
        self.deletedAt  = deletedAt
    }

    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Codable

extension Note: Codable {
    enum CodingKeys: String, CodingKey {
        case id, blocks, links, tags, timestamp, modifiedAt
        case isPinned, clusterId, parentId, sortIndex, folderId, deletedAt
        case text  // legacy fallback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self, forKey: .id)

        // Prefer blocks; fall back to legacy text field
        if let decodedBlocks = try? c.decode([Block].self, forKey: .blocks), !decodedBlocks.isEmpty {
            blocks = decodedBlocks
        } else {
            let legacyText = (try? c.decode(String.self, forKey: .text)) ?? ""
            blocks = MarkdownConverter.parse(legacyText)
        }

        links      = (try? c.decode([UUID].self, forKey: .links)) ?? []
        tags       = (try? c.decode([String].self, forKey: .tags)) ?? []
        timestamp  = (try? c.decode(Date.self, forKey: .timestamp)) ?? Date()
        modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? Date()
        isPinned   = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
        clusterId  = try? c.decode(UUID.self, forKey: .clusterId)
        parentId   = try? c.decode(UUID.self, forKey: .parentId)
        sortIndex  = (try? c.decode(Int.self, forKey: .sortIndex)) ?? 0
        folderId   = try? c.decode(UUID.self, forKey: .folderId)
        deletedAt  = try? c.decode(Date.self, forKey: .deletedAt)
        fileURL    = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,         forKey: .id)
        try c.encode(blocks,     forKey: .blocks)
        try c.encode(links,      forKey: .links)
        try c.encode(tags,       forKey: .tags)
        try c.encode(timestamp,  forKey: .timestamp)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(isPinned,   forKey: .isPinned)
        try c.encodeIfPresent(clusterId, forKey: .clusterId)
        try c.encodeIfPresent(parentId,  forKey: .parentId)
        try c.encode(sortIndex,  forKey: .sortIndex)
        try c.encodeIfPresent(folderId,  forKey: .folderId)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

import Foundation

struct Note: Identifiable, Equatable {
    var id: UUID
    var text: String
    var tags: [String]
    let timestamp: Date
    var modifiedAt: Date
    var fileURL: URL?           // transient: not persisted
    var isPinned: Bool
    var clusterId: UUID?        // which cluster (jar) this note belongs to
    var parentId: UUID?         // nil = root note; non-nil = subnote

    init(id: UUID = UUID(), text: String, tags: [String] = [],
         timestamp: Date = Date(), modifiedAt: Date = Date(),
         fileURL: URL? = nil, isPinned: Bool = false,
         clusterId: UUID? = nil, parentId: UUID? = nil) {
        self.id = id
        self.text = text
        self.tags = tags
        self.timestamp = timestamp
        self.modifiedAt = modifiedAt
        self.fileURL = fileURL
        self.isPinned = isPinned
        self.clusterId = clusterId
        self.parentId = parentId
    }

    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id }
}

extension Note: Codable {
    enum CodingKeys: String, CodingKey {
        case id, text, tags, timestamp, modifiedAt, isPinned, clusterId, parentId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,   forKey: .id)
        text       = try c.decode(String.self, forKey: .text)
        tags       = (try? c.decode([String].self, forKey: .tags)) ?? []
        timestamp  = (try? c.decode(Date.self, forKey: .timestamp)) ?? Date()
        modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? Date()
        isPinned   = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
        clusterId  = try? c.decode(UUID.self, forKey: .clusterId)
        parentId   = try? c.decode(UUID.self, forKey: .parentId)
        fileURL    = nil
    }
}

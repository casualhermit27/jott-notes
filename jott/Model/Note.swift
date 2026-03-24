import Foundation

struct Note: Identifiable, Equatable {
    var id: UUID
    var text: String
    var tags: [String]
    let timestamp: Date
    var modifiedAt: Date
    var fileURL: URL?           // transient: not persisted
    var linkedNoteIds: [UUID]   // UUIDs of notes this note links to
    var isPinned: Bool

    init(id: UUID = UUID(), text: String, tags: [String] = [],
         timestamp: Date = Date(), modifiedAt: Date = Date(),
         fileURL: URL? = nil, linkedNoteIds: [UUID] = [], isPinned: Bool = false) {
        self.id = id
        self.text = text
        self.tags = tags
        self.timestamp = timestamp
        self.modifiedAt = modifiedAt
        self.fileURL = fileURL
        self.linkedNoteIds = linkedNoteIds
        self.isPinned = isPinned
    }

    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id }
}

extension Note: Codable {
    enum CodingKeys: String, CodingKey {
        case id, text, tags, timestamp, modifiedAt, linkedNoteIds, isPinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,   forKey: .id)
        text         = try c.decode(String.self, forKey: .text)
        tags         = (try? c.decode([String].self, forKey: .tags)) ?? []
        timestamp    = (try? c.decode(Date.self, forKey: .timestamp)) ?? Date()
        modifiedAt   = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? Date()
        linkedNoteIds = (try? c.decode([UUID].self, forKey: .linkedNoteIds)) ?? []
        isPinned     = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
        fileURL      = nil
    }
}

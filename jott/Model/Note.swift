import Foundation

struct Note: Identifiable, Equatable {
    var id: UUID
    var text: String
    var tags: [String]
    let timestamp: Date
    var modifiedAt: Date
    var fileURL: URL?           // transient: not persisted
    var linkedNoteIds: [UUID]   // UUIDs of notes this note links to

    init(id: UUID = UUID(), text: String, tags: [String] = [],
         timestamp: Date = Date(), modifiedAt: Date = Date(),
         fileURL: URL? = nil, linkedNoteIds: [UUID] = []) {
        self.id = id
        self.text = text
        self.tags = tags
        self.timestamp = timestamp
        self.modifiedAt = modifiedAt
        self.fileURL = fileURL
        self.linkedNoteIds = linkedNoteIds
    }

    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id }
}

extension Note: Codable {
    enum CodingKeys: String, CodingKey {
        case id, text, tags, timestamp, modifiedAt, linkedNoteIds
    }
}

import Foundation

struct Note: Identifiable, Equatable {
    var id: UUID
    var text: String
    var tags: [String]
    let timestamp: Date
    var modifiedAt: Date
    var fileURL: URL?   // transient: not persisted

    init(id: UUID = UUID(), text: String, tags: [String] = [],
         timestamp: Date = Date(), modifiedAt: Date = Date(), fileURL: URL? = nil) {
        self.id = id
        self.text = text
        self.tags = tags
        self.timestamp = timestamp
        self.modifiedAt = modifiedAt
        self.fileURL = fileURL
    }

    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id }
}

extension Note: Codable {
    enum CodingKeys: String, CodingKey {
        case id, text, tags, timestamp, modifiedAt
    }
}

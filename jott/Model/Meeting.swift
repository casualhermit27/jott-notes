import Foundation

struct Meeting: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var participants: [String]
    var startTime: Date
    var duration: Int  // in minutes
    let createdAt: Date
    var tags: [String]
    var description: String?

    init(title: String, participants: [String], startTime: Date, duration: Int = 60, tags: [String] = []) {
        self.id = UUID()
        self.title = title
        self.participants = participants
        self.startTime = startTime
        self.duration = duration
        self.createdAt = Date()
        self.tags = tags
        self.description = nil
    }
}

import Foundation

struct Reminder: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var dueDate: Date
    var isCompleted: Bool
    let createdAt: Date
    var tags: [String]

    init(text: String, dueDate: Date, tags: [String] = []) {
        self.id = UUID()
        self.text = text
        self.dueDate = dueDate
        self.isCompleted = false
        self.createdAt = Date()
        self.tags = tags
    }
}

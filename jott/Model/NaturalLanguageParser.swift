import Foundation

enum ParsedContent {
    case note(text: String, tags: [String])
    case reminder(text: String, dueDate: Date, tags: [String])
    case meeting(title: String, participants: [String], startTime: Date, tags: [String])
}

struct NaturalLanguageParser {
    static func parse(_ input: String) -> ParsedContent {
        let lowercased = input.lowercased()

        // Check for reminder patterns
        if lowercased.contains("remind me") || lowercased.contains("remember to") || lowercased.contains("don't forget") {
            if let parsed = parseReminder(input) {
                return parsed
            }
        }

        // Check for meeting patterns
        if lowercased.contains("meeting with") || lowercased.contains("call with") ||
           lowercased.contains("sync with") || lowercased.contains("standup") ||
           lowercased.contains("@") {
            if let parsed = parseMeeting(input) {
                return parsed
            }
        }

        // Default to note
        let tags = extractTags(from: input)
        let cleanText = input.trimmingCharacters(in: .whitespaces)
        return .note(text: cleanText, tags: tags)
    }

    private static func parseReminder(_ input: String) -> ParsedContent? {
        var text = input
        var dueDate = Date().addingTimeInterval(3600) // default to 1 hour from now

        // Extract time references
        if let date = extractDate(from: input) {
            dueDate = date
        }

        // Clean up the text
        text = text
            .replacingOccurrences(of: "remind me to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "remind me ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "remember to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "don't forget to ", with: "", options: .caseInsensitive)

        // Remove date references from text
        text = removeDateReferences(from: text)
        text = text.trimmingCharacters(in: .whitespaces)

        let tags = extractTags(from: input)

        guard !text.isEmpty else { return nil }
        return .reminder(text: text, dueDate: dueDate, tags: tags)
    }

    private static func parseMeeting(_ input: String) -> ParsedContent? {
        var title = input
        var participants: [String] = []
        var startTime = Date().addingTimeInterval(3600)

        // Extract participants (after "with" or before "@")
        if let withRange = input.range(of: "with ", options: .caseInsensitive) {
            let afterWith = String(input[withRange.upperBound...])
            let parts = afterWith.split(separator: " ", maxSplits: 1)
            if let firstPart = parts.first {
                let name = String(firstPart).trimmingCharacters(in: CharacterSet(charactersIn: ",.!?"))
                participants.append(name)
            }
        }

        // Extract @ mentions
        let atPattern = "@(\\w+)"
        let regex = try? NSRegularExpression(pattern: atPattern, options: [])
        let nsInput = input as NSString
        let matches = regex?.matches(in: input, options: [], range: NSRange(location: 0, length: nsInput.length)) ?? []
        for match in matches {
            if match.numberOfRanges > 1 {
                let nameRange = match.range(at: 1)
                if let range = Range(nameRange, in: input) {
                    participants.append(String(input[range]))
                }
            }
        }

        // Extract time
        if let date = extractDate(from: input) {
            startTime = date
        }

        // Clean title
        title = input
            .replacingOccurrences(of: "meeting with ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "call with ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "sync with ", with: "", options: .caseInsensitive)

        title = removeDateReferences(from: title)
        title = title.split(separator: " ").prefix(5).joined(separator: " ")
        title = title.trimmingCharacters(in: .whitespaces)

        let tags = extractTags(from: input)

        guard !title.isEmpty else { return nil }
        return .meeting(title: title, participants: participants, startTime: startTime, tags: tags)
    }

    private static func extractDate(from text: String) -> Date? {
        let lowercased = text.lowercased()
        let now = Date()
        let calendar = Calendar.current

        // Tomorrow
        if lowercased.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        }

        // Days of week
        let daysOfWeek = ["monday": 1, "tuesday": 2, "wednesday": 3, "thursday": 4, "friday": 5, "saturday": 6, "sunday": 0]
        for (day, number) in daysOfWeek {
            if lowercased.contains(day) {
                let weekday = calendar.component(.weekday, from: now) - 1
                let daysAhead = (number - weekday + 7) % 7
                let daysToAdd = daysAhead == 0 ? 7 : daysAhead
                return calendar.date(byAdding: .day, value: daysToAdd, to: now)
            }
        }

        // Today
        if lowercased.contains("today") {
            return now
        }

        // Next week
        if lowercased.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        }

        // Extract time (like "3pm" or "14:30")
        if let timeDate = extractTime(from: text, baseDate: now) {
            return timeDate
        }

        return nil
    }

    private static func extractTime(from text: String, baseDate: Date) -> Date? {
        let calendar = Calendar.current
        let timePattern = "(\\d{1,2})(?::?(\\d{2}))?\\s*(am|pm|AM|PM)?"
        let regex = try? NSRegularExpression(pattern: timePattern, options: [])
        let nsText = text as NSString
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []

        guard let match = matches.first else { return nil }

        let hourRange = match.range(at: 1)
        let minuteRange = match.range(at: 2)
        let meridianRange = match.range(at: 3)

        guard let hourText = nsText.substring(with: hourRange) as? String,
              var hour = Int(hourText) else { return nil }

        let minute = minuteRange.length > 0 ? Int(nsText.substring(with: minuteRange)) ?? 0 : 0
        let meridian = meridianRange.length > 0 ? nsText.substring(with: meridianRange).lowercased() : nil

        if let meridian = meridian {
            if meridian == "pm" && hour != 12 {
                hour += 12
            } else if meridian == "am" && hour == 12 {
                hour = 0
            }
        }

        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute

        return calendar.date(from: components)
    }

    private static func extractTags(from text: String) -> [String] {
        var tags: [String] = []
        let pattern = "#(\\w+)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsText = text as NSString
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []

        for match in matches {
            if match.numberOfRanges > 1 {
                let tagRange = match.range(at: 1)
                let tag = nsText.substring(with: tagRange)
                tags.append(tag)
            }
        }

        return tags
    }

    private static func removeDateReferences(from text: String) -> String {
        var result = text
        let datePatterns = [
            "\\btomorrow\\b",
            "\\btoday\\b",
            "\\bmonday\\b", "\\btuesday\\b", "\\bwednesday\\b", "\\bthursday\\b", "\\bfriday\\b", "\\bsaturday\\b", "\\bsunday\\b",
            "\\bnext week\\b",
            "\\d{1,2}(?::?\\d{2})?\\s*(?:am|pm|AM|PM)"
        ]

        for pattern in datePatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        return result
    }
}

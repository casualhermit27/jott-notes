import Foundation

// MARK: - Recurrence

struct ParsedRecurrence: Equatable {
    enum Frequency { case daily, weekly, monthly, yearly }
    let frequency: Frequency
    let interval: Int       // 1 = every, 2 = every other, etc.
    let weekday: Int?       // EKWeekday rawValue (1=Sun…7=Sat), nil = no specific day

    var label: String {
        switch frequency {
        case .daily:
            return interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            if let wd = weekday {
                let names = [1:"Sunday",2:"Monday",3:"Tuesday",4:"Wednesday",
                             5:"Thursday",6:"Friday",7:"Saturday"]
                let dayName = names[wd] ?? "week"
                return interval == 1 ? "Every \(dayName)" : "Every \(interval) weeks on \(dayName)"
            }
            return interval == 1 ? "Every week" : "Every \(interval) weeks"
        case .monthly:
            return interval == 1 ? "Every month" : "Every \(interval) months"
        case .yearly:
            return interval == 1 ? "Every year" : "Every \(interval) years"
        }
    }
}

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

    static func extractDate(from text: String) -> Date? {
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

    static func extractTime(from text: String, baseDate: Date) -> Date? {
        let calendar = Calendar.current
        let timePattern = "(\\d{1,2})(?::?(\\d{2}))?\\s*(am|pm|AM|PM)?"
        let regex = try? NSRegularExpression(pattern: timePattern, options: [])
        let nsText = text as NSString
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []

        guard let match = matches.first else { return nil }

        let hourRange = match.range(at: 1)
        let minuteRange = match.range(at: 2)
        let meridianRange = match.range(at: 3)

        let hourText = nsText.substring(with: hourRange)
        guard var hour = Int(hourText) else { return nil }

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

    static func removeDateReferences(from text: String) -> String {
        var result = text
        let datePatterns = [
            "\\btomorrow\\b",
            "\\btoday\\b",
            "\\bmonday\\b", "\\btuesday\\b", "\\bwednesday\\b", "\\bthursday\\b", "\\bfriday\\b", "\\bsaturday\\b", "\\bsunday\\b",
            "\\bnext week\\b",
            // Absolute dates: "april 1 2026", "1 april 2026", "april 1", "1 april"
            "\\b(?:january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\\s+\\d{1,2}(?:\\s+\\d{4})?\\b",
            "\\b\\d{1,2}\\s+(?:january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)(?:\\s+\\d{4})?\\b",
            "\\d{1,2}(?::?\\d{2})?\\s*(?:am|pm|AM|PM)",
            // Recurrence keywords
            "\\bevery\\s+(?:other\\s+week|day|week|month|year|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b",
            "\\bevery\\s+\\d+\\s+(?:days?|weeks?|months?|years?)\\b",
            "\\b(?:daily|weekly|monthly|yearly|annually|biweekly|bi-weekly|fortnightly)\\b"
        ]

        for pattern in datePatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        return result
    }

    // MARK: - Recurrence detection

    static func extractRecurrence(from text: String) -> ParsedRecurrence? {
        let low = text.lowercased()

        // "every N days/weeks/months/years" — check before single-keyword patterns
        let numericPattern = #"every\s+(\d+)\s+(day|week|month|year)s?"#
        if let regex = try? NSRegularExpression(pattern: numericPattern),
           let m = regex.firstMatch(in: low, range: NSRange(low.startIndex..., in: low)) {
            let ns = low as NSString
            let n = Int(ns.substring(with: m.range(at: 1))) ?? 1
            switch ns.substring(with: m.range(at: 2)) {
            case "day":   return ParsedRecurrence(frequency: .daily,   interval: n, weekday: nil)
            case "week":  return ParsedRecurrence(frequency: .weekly,  interval: n, weekday: nil)
            case "month": return ParsedRecurrence(frequency: .monthly, interval: n, weekday: nil)
            case "year":  return ParsedRecurrence(frequency: .yearly,  interval: n, weekday: nil)
            default: break
            }
        }

        // "biweekly" / "bi-weekly" / "every other week" / "fortnightly"
        if low.contains("biweekly") || low.contains("bi-weekly") ||
           low.contains("every other week") || low.contains("fortnightly") {
            return ParsedRecurrence(frequency: .weekly, interval: 2, weekday: nil)
        }

        // "daily" / "every day"
        if low.contains("daily") ||
           low.range(of: #"\bevery\s+day\b"#, options: .regularExpression) != nil {
            return ParsedRecurrence(frequency: .daily, interval: 1, weekday: nil)
        }

        // "every monday/tuesday/..." — specific weekday
        let weekdayMap: [(String, Int)] = [
            ("sunday",1),("monday",2),("tuesday",3),("wednesday",4),
            ("thursday",5),("friday",6),("saturday",7)
        ]
        if low.range(of: #"\bevery\b"#, options: .regularExpression) != nil {
            for (name, num) in weekdayMap where low.contains(name) {
                return ParsedRecurrence(frequency: .weekly, interval: 1, weekday: num)
            }
        }

        // "weekly" / "every week"
        if low.contains("weekly") ||
           low.range(of: #"\bevery\s+week\b"#, options: .regularExpression) != nil {
            return ParsedRecurrence(frequency: .weekly, interval: 1, weekday: nil)
        }

        // "monthly" / "every month"
        if low.contains("monthly") ||
           low.range(of: #"\bevery\s+month\b"#, options: .regularExpression) != nil {
            return ParsedRecurrence(frequency: .monthly, interval: 1, weekday: nil)
        }

        // "yearly" / "annually" / "every year"
        if low.contains("yearly") || low.contains("annually") ||
           low.range(of: #"\bevery\s+year\b"#, options: .regularExpression) != nil {
            return ParsedRecurrence(frequency: .yearly, interval: 1, weekday: nil)
        }

        return nil
    }

    /// Parses "april 1", "1 april", "april 1 2026", "1 april 2026" into a Date.
    private static func extractAbsoluteDate(from lowercased: String) -> Date? {
        let months = ["january":1,"february":2,"march":3,"april":4,"may":5,"june":6,
                      "july":7,"august":8,"september":9,"october":10,"november":11,"december":12,
                      "jan":1,"feb":2,"mar":3,"apr":4,"jun":6,"jul":7,"aug":8,
                      "sep":9,"sept":9,"oct":10,"nov":11,"dec":12]

        // Pattern: "month day [year]"
        let pat1 = #"(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\s+(\d{1,2})(?:\s+(\d{4}))?"#
        // Pattern: "day month [year]"
        let pat2 = #"(\d{1,2})\s+(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)(?:\s+(\d{4}))?"#

        var month: Int?; var day: Int?; var year: Int?

        if let regex = try? NSRegularExpression(pattern: pat1, options: .caseInsensitive),
           let m = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)) {
            let ns = lowercased as NSString
            month = months[ns.substring(with: m.range(at: 1))]
            day   = Int(ns.substring(with: m.range(at: 2)))
            if m.range(at: 3).length > 0 { year = Int(ns.substring(with: m.range(at: 3))) }
        } else if let regex = try? NSRegularExpression(pattern: pat2, options: .caseInsensitive),
                  let m = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)) {
            let ns = lowercased as NSString
            day   = Int(ns.substring(with: m.range(at: 1)))
            month = months[ns.substring(with: m.range(at: 2))]
            if m.range(at: 3).length > 0 { year = Int(ns.substring(with: m.range(at: 3))) }
        }

        guard let m = month, let d = day else { return nil }
        let cal = Calendar.current
        let now = Date()
        var comps = DateComponents()
        comps.month = m; comps.day = d
        comps.year = year ?? cal.component(.year, from: now)
        // If no year specified and date is in the past, bump to next year
        if year == nil, let candidate = cal.date(from: comps), candidate < now {
            comps.year = comps.year! + 1
        }
        return cal.date(from: comps)
    }

    /// Parses plain event text ("Team lunch tomorrow at 3pm") into title + date.
    /// Combines day keyword + time so "tomorrow at 3pm" = day+1 at 3pm.
    static func parseForEvent(from text: String) -> (title: String, date: Date, hasExplicitDate: Bool) {
        let cal = Calendar.current
        let now = Date()
        var dayBase = now
        var foundDay = false
        var hasExplicit = false

        let low = text.lowercased()

        if low.contains("tomorrow") {
            dayBase = cal.date(byAdding: .day, value: 1, to: now) ?? now
            foundDay = true; hasExplicit = true
        } else if low.contains("today") {
            dayBase = now
            foundDay = true; hasExplicit = true
        } else if low.contains("next week") {
            dayBase = cal.date(byAdding: .weekOfYear, value: 1, to: now) ?? now
            foundDay = true; hasExplicit = true
        } else if let absDate = extractAbsoluteDate(from: low) {
            dayBase = absDate; foundDay = true; hasExplicit = true
        } else {
            let daysOfWeek: [(String, Int)] = [
                ("monday",2),("tuesday",3),("wednesday",4),("thursday",5),
                ("friday",6),("saturday",7),("sunday",1)
            ]
            for (name, num) in daysOfWeek where low.contains(name) {
                let current = cal.component(.weekday, from: now)
                let ahead = (num - current + 7) % 7
                dayBase = cal.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: now) ?? now
                foundDay = true; hasExplicit = true
                break
            }
        }

        var dayComps = cal.dateComponents([.year, .month, .day], from: dayBase)
        var date: Date
        if let timeDate = extractTime(from: text, baseDate: dayBase) {
            let timeComps = cal.dateComponents([.hour, .minute], from: timeDate)
            dayComps.hour = timeComps.hour
            dayComps.minute = timeComps.minute
            date = cal.date(from: dayComps) ?? dayBase
            hasExplicit = true
        } else if foundDay {
            dayComps.hour = 9; dayComps.minute = 0
            date = cal.date(from: dayComps) ?? dayBase
        } else {
            date = now.addingTimeInterval(3600)
        }

        var title = removeDateReferences(from: text)
        title = title.replacingOccurrences(of: #"\bat\b"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\bon\b"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"#\w+"#,  with: "", options: .regularExpression)
        title = title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        title = title.trimmingCharacters(in: .whitespaces)
        if title.isEmpty { title = text.trimmingCharacters(in: .whitespaces) }

        return (title: title, date: date, hasExplicitDate: hasExplicit)
    }
}

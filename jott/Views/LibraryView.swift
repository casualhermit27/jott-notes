import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var searchText: String = ""
    @State private var selectedItem: String?

    var filteredItems: [(date: String, items: [TimelineItem])] {
        var allItems: [TimelineItem] = []

        for note in viewModel.getAllNotes() {
            if searchText.isEmpty || note.text.lowercased().contains(searchText.lowercased()) {
                allItems.append(.note(note))
            }
        }

        for reminder in viewModel.getAllReminders() {
            if searchText.isEmpty || reminder.text.lowercased().contains(searchText.lowercased()) {
                allItems.append(.reminder(reminder))
            }
        }

        for meeting in viewModel.getAllMeetings() {
            if searchText.isEmpty || meeting.title.lowercased().contains(searchText.lowercased()) {
                allItems.append(.meeting(meeting))
            }
        }

        let grouped = Dictionary(grouping: allItems) { item -> String in
            let date = item.date
            let calendar = Calendar.current
            if calendar.isDateInToday(date) {
                return "Today"
            } else if calendar.isDateInYesterday(date) {
                return "Yesterday"
            } else if calendar.isDateInThisWeek(date) {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return formatter.string(from: date)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
        }

        let order = ["Today", "Yesterday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return grouped.sorted { a, b in
            let indexA = order.firstIndex(of: a.key) ?? Int.max
            let indexB = order.firstIndex(of: b.key) ?? Int.max
            return indexA < indexB
        }.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "note.text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.jottGreen)
                Text("Library")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
            }
            .padding(20)
            .background(Color(nsColor: NSColor(white: 0.99, alpha: 1)))

            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))

                TextField("Search notes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(.black)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(nsColor: NSColor(white: 0.96, alpha: 1)))
            .cornerRadius(8)
            .padding(16)

            // Timeline
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(filteredItems, id: \.date) { dateSection in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(dateSection.date)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                ForEach(Array(dateSection.items.enumerated()), id: \.element.id) { index, item in
                                    TimelineItemView(item: item)

                                    if index < dateSection.items.count - 1 {
                                        Divider()
                                            .padding(.vertical, 8)
                                    }
                                }
                            }
                        }
                    }

                    if filteredItems.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "note.text")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.2))
                            Text("No notes yet")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                }
                .padding(20)
            }
        }
        .background(Color(nsColor: .white))
    }
}

enum TimelineItem: Identifiable {
    case note(Note)
    case reminder(Reminder)
    case meeting(Meeting)

    var id: String {
        switch self {
        case .note(let note): return note.id.uuidString
        case .reminder(let reminder): return reminder.id.uuidString
        case .meeting(let meeting): return meeting.id.uuidString
        }
    }

    var date: Date {
        switch self {
        case .note(let note): return note.modifiedAt
        case .reminder(let reminder): return reminder.dueDate
        case .meeting(let meeting): return meeting.startTime
        }
    }
}

struct TimelineItemView: View {
    let item: TimelineItem

    var body: some View {
        HStack(spacing: 12) {
            // Icon + Type indicator
            VStack(alignment: .center, spacing: 4) {
                switch item {
                case .note:
                    Image(systemName: "note.text")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.jottGreen)
                case .reminder:
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                case .meeting:
                    Image(systemName: "calendar.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )

            // Content
            VStack(alignment: .leading, spacing: 4) {
                switch item {
                case .note(let note):
                    Text(note.text)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(2)

                case .reminder(let reminder):
                    Text(reminder.text)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(formatTime(reminder.dueDate))
                            .font(.system(size: 11, weight: .regular))
                    }
                    .foregroundColor(.secondary.opacity(0.6))

                case .meeting(let meeting):
                    Text(meeting.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(formatTime(meeting.startTime))
                            .font(.system(size: 11, weight: .regular))
                        if !meeting.participants.isEmpty {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.3))
                            Text(meeting.participants.joined(separator: ", "))
                                .font(.system(size: 11, weight: .regular))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: NSColor(white: 0.97, alpha: 1)))
        .cornerRadius(8)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

extension Calendar {
    func isDateInThisWeek(_ date: Date) -> Bool {
        let weekOfYear = component(.weekOfYear, from: Date())
        let dateWeekOfYear = component(.weekOfYear, from: date)
        return weekOfYear == dateWeekOfYear && component(.year, from: Date()) == component(.year, from: date)
    }
}

#Preview {
    LibraryView(viewModel: OverlayViewModel())
}

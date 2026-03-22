import SwiftUI

struct RemindersListView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var reminders: [Reminder] { viewModel.getAllReminders() }

    var body: some View {
        if reminders.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 32))
                    .foregroundColor(.blue.opacity(0.3))
                Text("No upcoming reminders")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(reminders.enumerated()), id: \.element.id) { index, reminder in
                        ReminderRowView(reminder: reminder) {
                            viewModel.selectedReminder = reminder
                        }

                        if index < reminders.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct ReminderRowView: View {
    let reminder: Reminder
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(reminder.isCompleted ? .blue : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(reminder.isCompleted ? .secondary : .primary)
                    .strikethrough(reminder.isCompleted)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(formatDate(reminder.dueDate))
                        .font(.system(size: 12, weight: .regular))
                }
                .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

#Preview {
    RemindersListView(viewModel: OverlayViewModel())
}

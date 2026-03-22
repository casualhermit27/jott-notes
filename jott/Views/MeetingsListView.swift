import SwiftUI

struct MeetingsListView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var meetings: [Meeting] { viewModel.getAllMeetings() }

    var body: some View {
        if meetings.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 32))
                    .foregroundColor(.orange.opacity(0.3))
                Text("No upcoming meetings")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                        MeetingRowView(meeting: meeting)
                            .onTapGesture { viewModel.selectedMeeting = meeting }

                        if index < meetings.count - 1 {
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

struct MeetingRowView: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .center, spacing: 2) {
                Text(formatTime(meeting.startTime))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)
                Text(formatDate(meeting.startTime))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .frame(width: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                if !meeting.participants.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                        Text(meeting.participants.joined(separator: ", "))
                            .font(.system(size: 12, weight: .regular))
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(meeting.duration)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("mins")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

#Preview {
    MeetingsListView(viewModel: OverlayViewModel())
}

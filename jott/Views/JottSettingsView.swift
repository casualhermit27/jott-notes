import SwiftUI
import EventKit

struct JottSettingsView: View {
    @ObservedObject private var cal = CalendarManager.shared
    @State private var selectedCalId:  String = UserDefaults.standard.string(forKey: "jott_calendarId")      ?? ""
    @State private var selectedListId: String = UserDefaults.standard.string(forKey: "jott_reminderListId") ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gear")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Jott Settings")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: - Apple Calendar
                    sectionHeader("CALENDAR", icon: "calendar")

                    if cal.isAuthorized {
                        connectedBadge
                        calendarPicker
                    } else {
                        connectButton("Connect Apple Calendar", icon: "calendar") {
                            Task { await CalendarManager.shared.requestAccess() }
                        }
                    }

                    sectionDivider

                    // MARK: - Apple Reminders
                    sectionHeader("REMINDERS", icon: "bell.fill")

                    if cal.isRemindersAuthorized {
                        connectedBadge
                        remindersPicker
                    } else {
                        connectButton("Connect Apple Reminders", icon: "bell") {
                            Task { await CalendarManager.shared.requestRemindersAccess() }
                        }
                    }

                    sectionDivider

                    // MARK: - Google Calendar / Outlook
                    sectionHeader("GOOGLE CALENDAR & OUTLOOK", icon: "globe")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Jott uses macOS Calendar as the bridge. Once your Google or Outlook account is connected to macOS, all its calendars appear automatically in the list above.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            externalButton("Google Calendar", icon: "g.circle.fill", color: Color(red: 0.85, green: 0.26, blue: 0.21)) {
                                openInternetAccounts()
                            }
                            externalButton("Outlook", icon: "envelope.fill", color: Color(red: 0.0, green: 0.47, blue: 0.83)) {
                                openInternetAccounts()
                            }
                        }

                        Text("Both buttons open System Settings → Internet Accounts where you can sign in.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    sectionDivider

                    // MARK: - Notes Folder
                    sectionHeader("NOTES FOLDER", icon: "folder")

                    Button("Choose Folder...") {
                        if let wc = (NSApp.delegate as? AppDelegate)?.windowController {
                            wc.viewModel.selectNotesFolder()
                        }
                    }
                    .controlSize(.small)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 420)
        .onAppear {
            selectedCalId  = UserDefaults.standard.string(forKey: "jott_calendarId")      ?? ""
            selectedListId = UserDefaults.standard.string(forKey: "jott_reminderListId") ?? ""
        }
    }

    // MARK: - Sub-views

    private var connectedBadge: some View {
        Label("Connected", systemImage: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.green)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    private var calendarPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Use calendar")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Picker("", selection: $selectedCalId) {
                Text("Default").tag("")
                ForEach(cal.availableCalendars, id: \.calendarIdentifier) { c in
                    HStack(spacing: 6) {
                        Circle().fill(Color(cgColor: c.cgColor)).frame(width: 8, height: 8)
                        Text(c.title)
                    }.tag(c.calendarIdentifier)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
            .onChange(of: selectedCalId) { cal.selectCalendar($0.isEmpty ? nil : $0) }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var remindersPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Use list")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Picker("", selection: $selectedListId) {
                Text("Default").tag("")
                ForEach(cal.availableReminderLists, id: \.calendarIdentifier) { r in
                    HStack(spacing: 6) {
                        Circle().fill(Color(cgColor: r.cgColor)).frame(width: 8, height: 8)
                        Text(r.title)
                    }.tag(r.calendarIdentifier)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
            .onChange(of: selectedListId) { cal.selectReminderList($0.isEmpty ? nil : $0) }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var sectionDivider: some View {
        Divider().padding(.horizontal, 20)
    }

    private func connectButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func externalButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func openInternetAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.internet-accounts") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    JottSettingsView()
}

import SwiftUI
import EventKit

struct JottSettingsView: View {
    @ObservedObject private var cal = CalendarManager.shared
    @ObservedObject private var updates = UpdateManager.shared
    @State private var selectedCalId:  String = UserDefaults.standard.string(forKey: "jott_calendarId")      ?? ""
    @State private var selectedListId: String = UserDefaults.standard.string(forKey: "jott_reminderListId") ?? ""
    @AppStorage("jott_overlayPosition") private var overlayPosition: String = "center"
    @AppStorage("jott_showCommandSuggestions") private var showCommandSuggestions: Bool = false

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

                    // MARK: - Position
                    sectionHeader("POSITION", icon: "rectangle.on.rectangle")
                    positionPicker
                    sectionDivider

                    // MARK: - Interface
                    sectionHeader("INTERFACE", icon: "slider.horizontal.3")
                    interfaceOptions
                    sectionDivider

                    // MARK: - Apple Calendar
                    sectionHeader("CALENDAR", icon: "calendar")
                    permissionStatusRow(
                        title: "Calendar permission",
                        statusText: permissionStatusText(for: .event),
                        isGranted: cal.isAuthorized,
                        actionTitle: permissionActionTitle(for: .event),
                        action: {
                            if isPermissionDenied(for: .event) {
                                cal.openCalendarPrivacySettings()
                            } else {
                                Task { await CalendarManager.shared.requestAccess() }
                            }
                        }
                    )

                    if cal.isAuthorized {
                        connectedBadge
                        calendarPicker
                    } else {
                        permissionBlock(
                            label: "Connect Apple Calendar",
                            icon: "calendar",
                            isLoading: cal.isRequestingCalendarAccess,
                            errorMessage: cal.authorizationErrorMessage,
                            connectAction: { Task { await CalendarManager.shared.requestAccess() } },
                            openSettingsAction: { cal.openCalendarPrivacySettings() }
                        )
                    }

                    sectionDivider

                    // MARK: - Apple Reminders
                    sectionHeader("REMINDERS", icon: "bell.fill")
                    permissionStatusRow(
                        title: "Reminders permission",
                        statusText: permissionStatusText(for: .reminder),
                        isGranted: cal.isRemindersAuthorized,
                        actionTitle: permissionActionTitle(for: .reminder),
                        action: {
                            if isPermissionDenied(for: .reminder) {
                                cal.openRemindersPrivacySettings()
                            } else {
                                Task { await CalendarManager.shared.requestRemindersAccess() }
                            }
                        }
                    )

                    if cal.isRemindersAuthorized {
                        connectedBadge
                        remindersPicker
                    } else {
                        permissionBlock(
                            label: "Connect Apple Reminders",
                            icon: "bell",
                            isLoading: cal.isRequestingRemindersAccess,
                            errorMessage: cal.authorizationErrorMessage,
                            connectAction: { Task { await CalendarManager.shared.requestRemindersAccess() } },
                            openSettingsAction: { cal.openRemindersPrivacySettings() }
                        )
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
                            externalButton("Google Calendar", icon: "g.circle.fill", color: .red) {
                                openInternetAccounts()
                            }
                            externalButton("Outlook", icon: "envelope.fill", color: .blue) {
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

                    // MARK: - Reliability
                    sectionHeader("RELIABILITY", icon: "shield")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Crash telemetry")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(Telemetry.isEnabled ? "Sentry active" : "Sentry not configured (set SentryDSN or SENTRY_DSN)")
                            .font(.system(size: 11))
                            .foregroundColor(Telemetry.isEnabled ? .green : .orange)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Updates")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(updates.updateChannel == "app_store" ? "Channel: App Store" : "Channel: Direct distribution (Sparkle)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Button("Check for Updates") {
                            updates.checkForUpdates()
                        }
                        .controlSize(.small)
                        .disabled(!updates.sparkleEnabled)
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
        .jottAppTypography()
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
            .accessibilityLabel("Connected")
            .accessibilityHint("Access is currently granted.")
    }

    private var positionPicker: some View {
        HStack(spacing: 8) {
            positionBtn("center",   icon: "squareshape.split.3x3",          label: "Center")
            positionBtn("topLeft",  icon: "rectangle.lefthalf.inset.filled",  label: "Top Left")
            positionBtn("topRight", icon: "rectangle.righthalf.inset.filled", label: "Top Right")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func positionBtn(_ value: String, icon: String, label: String) -> some View {
        Button { overlayPosition = value } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(overlayPosition == value ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(overlayPosition == value ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(overlayPosition == value ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var interfaceOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $showCommandSuggestions) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show command suggestions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Displays the Today, Calendar, Notes, Reminders, and Search row while typing slash commands.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
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
            .onChange(of: selectedCalId) { _, newValue in
                cal.selectCalendar(newValue.isEmpty ? nil : newValue)
            }
            .accessibilityLabel("Calendar selection")
            .accessibilityHint("Selects the default calendar used for new events.")
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
            .onChange(of: selectedListId) { _, newValue in
                cal.selectReminderList(newValue.isEmpty ? nil : newValue)
            }
            .accessibilityLabel("Reminder list selection")
            .accessibilityHint("Selects the default reminders list used for new reminders.")
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

    private func permissionBlock(
        label: String,
        icon: String,
        isLoading: Bool,
        errorMessage: String?,
        connectAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text("Requesting access…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
            }
            connectButton(label, icon: icon, action: connectAction)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 20)
                Button("Open Privacy Settings", action: openSettingsAction)
                    .controlSize(.small)
                    .padding(.horizontal, 20)
            }
        }
    }

    private func permissionStatusRow(
        title: String,
        statusText: String,
        isGranted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isGranted ? .green : .orange)
            }

            Spacer(minLength: 0)

            Button(actionTitle, action: action)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(statusText)
    }

    private func permissionStatusText(for type: EKEntityType) -> String {
        let status = EKEventStore.authorizationStatus(for: type)
        switch status {
        case .fullAccess, .authorized:
            return "Granted"
        case .denied, .restricted:
            return "Denied"
        case .writeOnly:
            return "Write-only"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private func permissionActionTitle(for type: EKEntityType) -> String {
        isPermissionDenied(for: type) ? "Open Settings" : "Request Access"
    }

    private func isPermissionDenied(for type: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: type)
        return status == .denied || status == .restricted
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

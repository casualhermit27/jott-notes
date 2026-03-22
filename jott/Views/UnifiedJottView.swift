import SwiftUI
import AppKit
import EventKit

// MARK: - Root View
// Panel is fixed 520×420 and transparent. The card inside grows/shrinks via SwiftUI.

struct UnifiedJottView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var showDetail: Bool {
        viewModel.selectedNote != nil || viewModel.selectedReminder != nil || viewModel.selectedMeeting != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if showDetail {
                    DetailView(viewModel: viewModel)
                        .frame(width: 520, height: 372)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .transition(.asymmetric(
                            insertion: .push(from: .trailing),
                            removal:   .push(from: .leading)
                        ))
                } else {
                    JottCaptureView(viewModel: viewModel)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .transition(.asymmetric(
                            insertion: .push(from: .leading),
                            removal:   .push(from: .trailing)
                        ))
                }
            }
            .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 10)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showDetail)

            Spacer() // transparent — fills the rest of the 420px panel
        }
        .frame(width: 520, height: 420) // matches fixed panel size exactly
        .colorScheme(.light)
    }
}

// MARK: - Colors

private let jottBarLight   = Color(red: 0.851, green: 0.851, blue: 0.851)  // #d9d9d9
private let jottBarDark    = Color(red: 0.13,  green: 0.13,  blue: 0.14)
private let jottCursorColor = NSColor(red: 0.447, green: 0.420, blue: 1.0, alpha: 1) // #726bff
private let jottPlaceholder = NSColor(red: 0.616, green: 0.616, blue: 0.616, alpha: 1) // #9d9d9d

// MARK: - Capture View

struct JottCaptureView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var command: JottCommand? {
        guard !viewModel.isForcedCreationMode else { return nil }
        return JottCommand(input: viewModel.inputText)
    }

    var body: some View {
        VStack(spacing: 0) {
            JottInputArea(viewModel: viewModel)
                .fixedSize(horizontal: false, vertical: true)

            if let cmd = command {
                Divider()
                    .opacity(0.12)
                    .transition(.opacity.animation(.easeOut(duration: 0.1)))
                JottCommandResults(command: cmd, viewModel: viewModel)
                    .frame(height: 300)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.97, anchor: .top)
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.36, dampingFraction: 0.78).delay(0.05)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))
                    ))
            }
        }
        .clipped()
        .background(jottBarLight)
        .animation(
            command != nil
                ? .spring(response: 0.36, dampingFraction: 0.82)
                : .easeOut(duration: 0.18),
            value: command != nil
        )
    }
}

// MARK: - Command detection

enum JottCommand: Equatable {
    case notes(query: String)
    case reminders(query: String)
    case meetings(query: String)
    case search(query: String)
    case open
    case calendar

    init?(input: String) {
        guard input.hasPrefix("/") else { return nil }
        let raw = input.dropFirst()
        let trimmed = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "notes" || trimmed.hasPrefix("notes ") {
            let q = trimmed.hasPrefix("notes ") ? String(raw.dropFirst(6)).trimmingCharacters(in: .whitespaces) : ""
            self = .notes(query: q)
        } else if trimmed == "open" {
            self = .open
        } else if trimmed == "calendar" || trimmed.hasPrefix("calendar") {
            self = .calendar
        } else if trimmed.hasPrefix("reminder") {
            let q = String(raw.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            self = .reminders(query: q)
        } else if trimmed.hasPrefix("meeting") {
            let q = String(raw.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            self = .meetings(query: q)
        } else if trimmed.hasPrefix("search ") {
            self = .search(query: String(raw.dropFirst(7)).trimmingCharacters(in: .whitespaces))
        } else {
            self = .notes(query: String(raw))
        }
    }
}

// MARK: - Type Badge Data

struct TypeBadgeInfo: Equatable {
    let label: String
    let bg: Color    // solid pastel
    let fg: Color    // dark tinted text
    let icon: String
}

func badgeInfo(for type: DetectedType, forced: Bool) -> TypeBadgeInfo? {
    switch type {
    case .note:
        guard forced else { return nil }
        return TypeBadgeInfo(
            label: "Note",
            bg: Color(red: 0.80, green: 0.95, blue: 0.86),   // soft sage mint
            fg: Color(red: 0.10, green: 0.44, blue: 0.24),
            icon: "doc.text")
    case .reminder:
        return TypeBadgeInfo(
            label: "Reminder",
            bg: Color(red: 0.83, green: 0.85, blue: 0.98),   // soft lavender
            fg: Color(red: 0.20, green: 0.24, blue: 0.74),
            icon: "bell")
    case .meeting:
        return TypeBadgeInfo(
            label: "Meeting",
            bg: Color(red: 0.99, green: 0.90, blue: 0.78),   // soft peach
            fg: Color(red: 0.62, green: 0.30, blue: 0.06),
            icon: "calendar")
    }
}

// MARK: - Main Input Area

struct JottInputArea: View {
    @ObservedObject var viewModel: OverlayViewModel
    @FocusState private var focused: Bool
    @State private var showFormat = false
    @State private var textHeight: CGFloat = 20   // will be overwritten by reportHeight on first render
    private let maxTextHeight: CGFloat = 110

    var badge: TypeBadgeInfo? {
        if let forced = viewModel.forcedType {
            return badgeInfo(for: forced, forced: true)
        }
        guard !viewModel.inputText.isEmpty, !viewModel.inputText.hasPrefix("/") else { return nil }
        return badgeInfo(for: viewModel.detectedType, forced: false)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Format bar — slides down from top
            if showFormat {
                JottFormatBar(viewModel: viewModel)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .transition(.push(from: .top).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 10) {

                // Type badge
                if let b = badge {
                    GradientTypeBadge(info: b)
                        .id(b.label)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity),
                            removal:   .scale(scale: 0.5, anchor: .leading).combined(with: .opacity)
                        ))
                }

                // Text editor — trailing padding reserves room for overlay controls
                JottNativeInput(
                    text: $viewModel.inputText,
                    placeholder: placeholderText,
                    isDark: viewModel.isDarkMode,
                    isFocused: focused,
                    onEscape: { viewModel.handleEscape() },
                    onBackspaceOnEmpty: { viewModel.clearForcedType() },
                    onHeightChange: { h in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                            textHeight = min(h, maxTextHeight)
                        }
                    }
                )
                .frame(height: textHeight)
                .padding(.trailing, 32) // reserve space for overlay controls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            // Trailing controls as overlay — never affect row height
            .overlay(alignment: .trailing) {
                VStack(alignment: .trailing, spacing: 4) {
                    // Format toggle
                    if !viewModel.inputText.isEmpty && !viewModel.inputText.hasPrefix("/") {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                showFormat.toggle()
                            }
                        } label: {
                            Image(systemName: showFormat ? "xmark" : "textformat")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(showFormat ? Color.accentColor.opacity(0.8) : .secondary.opacity(0.45))
                                .frame(width: 24, height: 24)
                                .background(showFormat ? Color.accentColor.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .scaleEffect(showFormat ? 1.0 : 0.95)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }

                    // Saved indicator
                    if viewModel.autoSaveStatus == "saved" {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.32, green: 0.78, blue: 0.54))
                            Text("Saved")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        .transition(.scale(scale: 0.5, anchor: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.26, dampingFraction: 0.62), value: viewModel.autoSaveStatus)
                .padding(.trailing, 14)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: badge)
        .onAppear { focused = true }
        .onChange(of: viewModel.isVisible) { _, visible in
            if visible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    focused = true
                    showFormat = false
                }
            }
        }
    }

    private var placeholderText: String {
        if let forced = viewModel.forcedType {
            switch forced {
            case .note:     return "what's on your mind..."
            case .reminder: return "remind me to..."
            case .meeting:  return "meeting title, with who..."
            }
        }
        return viewModel.inputText.hasPrefix("/") ? "" : "jott something down..."
    }
}

// MARK: - Type Badge

struct GradientTypeBadge: View {
    let info: TypeBadgeInfo
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: info.icon)
                .font(.system(size: 12, weight: .medium))
            Text(info.label)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.1)
        }
        .foregroundColor(info.fg)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(info.bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .scaleEffect(appeared ? 1.0 : 0.5)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.58)) {
                appeared = true
            }
        }
    }
}

// MARK: - Command Results

struct JottCommandResults: View {
    let command: JottCommand
    @ObservedObject var viewModel: OverlayViewModel

    var items: [TimelineItem] {
        switch command {
        case .notes(let q):
            let notes = q.isEmpty ? viewModel.getAllNotes() : viewModel.searchNotes(q)
            return notes.map { .note($0) }
        case .reminders(let q):
            let all = viewModel.getAllReminders()
            if q.isEmpty { return all.map { .reminder($0) } }
            return all.filter { $0.text.lowercased().contains(q.lowercased()) }.map { .reminder($0) }
        case .meetings(let q):
            let all = viewModel.getAllMeetings()
            if q.isEmpty { return all.map { .meeting($0) } }
            return all.filter { $0.title.lowercased().contains(q.lowercased()) }.map { .meeting($0) }
        case .search(let q):
            guard !q.isEmpty else { return [] }
            return viewModel.searchNotes(q).map { .note($0) }
        case .open:
            return []
        case .calendar:
            return []  // handled separately in body
        }
    }

    var label: String {
        switch command {
        case .notes:     return "NOTES"
        case .reminders: return "REMINDERS"
        case .meetings:  return "MEETINGS"
        case .search:    return "SEARCH"
        case .open:      return "ACTION"
        case .calendar:  return "CALENDAR"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Special handling for /open
            if case .open = command {
                JottOpenAction(viewModel: viewModel)
            } else if case .calendar = command {
                CalendarResultsView(viewModel: viewModel)
            } else {
                HStack {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.45))
                        .tracking(0.6)
                    Spacer()
                    Text("\(items.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.3))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                if items.isEmpty {
                    Text("Nothing here yet")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(items, id: \.id) { item in
                                JottRow(item: item, viewModel: viewModel)
                                    .transition(.asymmetric(
                                        insertion: .push(from: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                            }
                        }
                        .padding(.bottom, 6)
                        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: items.map(\.id))
                    }
                }
            }
        }
    }
}

// MARK: - Calendar Results View

struct CalendarResultsView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject private var calMgr = CalendarManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CALENDAR")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.45))
                    .tracking(0.6)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            if !calMgr.isAuthorized {
                VStack(spacing: 10) {
                    Text("Calendar access not granted")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.5))
                    Button(action: {
                        Task { await calMgr.requestAccess() }
                    }) {
                        Text("Connect Calendar")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color(red: 0.35, green: 0.72, blue: 0.50))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let events = calMgr.upcomingEvents()
                if events.isEmpty {
                    Text("No upcoming events")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(events, id: \.eventIdentifier) { event in
                                CalendarRow(event: event, viewModel: viewModel)
                            }
                        }
                        .padding(.bottom, 6)
                    }
                }
            }
        }
    }
}

// MARK: - Calendar Row

struct CalendarRow: View {
    let event: EKEvent
    @ObservedObject var viewModel: OverlayViewModel
    @State private var hovered = false
    @State private var imported = false

    var body: some View {
        HStack(spacing: 10) {
            // Calendar color dot
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(formatTime(event))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                    if let count = event.attendees?.count, count > 1 {
                        Text("\(count) attendees")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
            }
            Spacer()
            if hovered {
                Button(action: {
                    viewModel.importCalendarEvent(event)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { imported = true }
                }) {
                    Image(systemName: imported ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(imported ? Color(red: 0.32, green: 0.78, blue: 0.54) : .secondary.opacity(0.5))
                        .symbolEffect(.bounce, value: imported)
                        .scaleEffect(imported ? 1.15 : 1.0)
                        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: imported)
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            Group {
                if hovered {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.05))
                        .padding(.horizontal, 6)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { hovered = h } }
    }

    private func formatTime(_ event: EKEvent) -> String {
        if event.isAllDay { return "All day" }
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(event.startDate) {
            f.dateFormat = "h:mm a"
            return "Today \(f.string(from: event.startDate))"
        } else if cal.isDateInTomorrow(event.startDate) {
            f.dateFormat = "h:mm a"
            return "Tomorrow \(f.string(from: event.startDate))"
        } else {
            f.dateFormat = "EEE h:mm a"
            return f.string(from: event.startDate)
        }
    }
}

// MARK: - /open action view

struct JottOpenAction: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var hovered = false

    var body: some View {
        Button(action: { viewModel.openNotesFolder(); viewModel.dismiss() }) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.35, green: 0.72, blue: 0.50))
                    .frame(width: 18)
                Text("Open Notes Folder in Finder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.12))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Group {
                    if hovered {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                            .padding(.horizontal, 6)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { hovered = h } }
    }
}

// MARK: - Native Text Input (NSViewRepresentable for cursor color + clear background)

struct JottNativeInput: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isDark: Bool
    let isFocused: Bool
    let onEscape: () -> Void
    var onBackspaceOnEmpty: (() -> Void)? = nil
    var onHeightChange: ((CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        let tv = JottNSTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.insertionPointColor = jottCursorColor
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false

        scrollView.documentView = tv
        context.coordinator.scrollView = scrollView

        // Seed the initial height so JottInputArea starts at the correct size
        DispatchQueue.main.async { [weak tv] in
            guard let tv else { return }
            context.coordinator.reportHeight(from: tv)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? JottNSTextView else { return }
        if tv.string != text { tv.string = text }

        // Background is always light (#d9d9d9), so text is always dark
        let textColor = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        tv.font = .systemFont(ofSize: 17)
        tv.textColor = textColor
        tv.insertionPointColor = jottCursorColor
        tv.jottPlaceholder = placeholder
        tv.jottPlaceholderColor = jottPlaceholder

        if isFocused, tv.window?.firstResponder !== tv {
            tv.window?.makeFirstResponder(tv)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JottNativeInput
        weak var scrollView: NSScrollView?
        private var lastReportedHeight: CGFloat = 0
        init(_ p: JottNativeInput) { parent = p }

        func reportHeight(from tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            var h = lm.usedRect(for: tc).height
            // Fallback if layout hasn't run yet (e.g. immediately after makeNSView)
            if h <= 0, let font = tv.font {
                h = ceil(font.ascender - font.descender + font.leading)
            }
            guard h > 0, h != lastReportedHeight else { return }
            lastReportedHeight = h
            parent.onHeightChange?(h)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            reportHeight(from: tv)
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            if sel == #selector(NSResponder.deleteBackward(_:)), tv.string.isEmpty {
                parent.onBackspaceOnEmpty?()
                return true
            }
            return false
        }
    }
}

final class JottNSTextView: NSTextView {
    var jottPlaceholder: String = ""
    var jottPlaceholderColor: NSColor = .placeholderTextColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !jottPlaceholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 17),
            .foregroundColor: jottPlaceholderColor
        ]
        jottPlaceholder.draw(at: NSPoint(x: 0, y: 0), withAttributes: attrs)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        // Try image paste first
        if let image = NSImage(pasteboard: pb),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let filename = "img-\(Int(Date().timeIntervalSince1970)).png"
            let path = MainActor.assumeIsolated {
                NoteStore.shared.saveAttachment(data: pngData, filename: filename)
            }
            if let path {
                insertText("![](\(path))", replacementRange: selectedRange())
                return
            }
        }
        super.paste(sender)
    }
}

// MARK: - Format Bar

struct JottFormatBar: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                fmtGroup {
                    MFBtn("B", style: .bold)    { viewModel.inputText = "**\(viewModel.inputText)**" }
                    MFBtn("I", style: .italic)  { viewModel.inputText = "*\(viewModel.inputText)*" }
                    MFBtn("U", style: .plain)   { viewModel.inputText = "__\(viewModel.inputText)__" }
                    MFBtn("S", style: .strike)  { viewModel.inputText = "~~\(viewModel.inputText)~~" }
                }
                fmtSep
                fmtGroup {
                    MFIcon("list.bullet")  { viewModel.inputText = "• " + viewModel.inputText }
                    MFIcon("list.number")  { viewModel.inputText = "1. " + viewModel.inputText }
                    MFIcon("text.quote")   { viewModel.inputText = "> " + viewModel.inputText }
                }
                fmtSep
                fmtGroup {
                    MFIcon("chevron.left.forwardslash.chevron.right") { viewModel.inputText = "`\(viewModel.inputText)`" }
                    MFIcon("link")            { viewModel.inputText += " [text](url)" }
                    MFIcon("textformat.size") { viewModel.inputText = "# " + viewModel.inputText }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    private func fmtGroup<Content: View>(@ViewBuilder _ c: () -> Content) -> some View {
        HStack(spacing: 1) { c() }
    }
    private var fmtSep: some View {
        Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 14).padding(.horizontal, 4)
    }
    private enum FmtStyle { case bold, italic, strike, plain }

    private func MFBtn(_ lbl: String, style: FmtStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                switch style {
                case .bold:   Text(lbl).bold()
                case .italic: Text(lbl).italic()
                case .strike: Text(lbl).strikethrough()
                case .plain:  Text(lbl)
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func MFIcon(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: - Row

struct JottRow: View {
    let item: TimelineItem
    @ObservedObject var viewModel: OverlayViewModel
    @State private var hovered = false

    var accent: Color {
        switch item {
        case .note:     return Color(red: 0.35, green: 0.72, blue: 0.50)
        case .reminder: return Color(red: 0.40, green: 0.65, blue: 0.95)
        case .meeting:  return Color(red: 0.95, green: 0.58, blue: 0.22)
        }
    }
    var icon: String {
        switch item {
        case .note:     return "doc.text"
        case .reminder: return "bell"
        case .meeting:  return "calendar"
        }
    }
    var title: String {
        switch item {
        case .note(let n):     return n.text.components(separatedBy: "\n").first ?? n.text
        case .reminder(let r): return r.text
        case .meeting(let m):  return m.title
        }
    }
    var meta: String? {
        switch item {
        case .note(let n):
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
            return f.localizedString(for: n.modifiedAt, relativeTo: Date())
        case .reminder(let r):
            let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f.string(from: r.dueDate)
        case .meeting(let m):
            let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"
            let names = m.participants.prefix(2).joined(separator: ", ")
            return names.isEmpty ? f.string(from: m.startTime) : "\(names) · \(f.string(from: m.startTime))"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(viewModel.isDarkMode
                        ? Color(red: 0.92, green: 0.92, blue: 0.94)
                        : Color(red: 0.1, green: 0.1, blue: 0.12))
                    .lineLimit(1)
                if let m = meta {
                    Text(m)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer()

            // Open in editor button — only for notes, only on hover
            if hovered, case .note(let n) = item {
                Button(action: { viewModel.openNoteInEditor(n); viewModel.dismiss() }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

            // Copy button — notes only
            if hovered, case .note(let n) = item {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(n.text, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

            // Delete button — all types
            if hovered {
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        switch item {
                        case .note(let n):     viewModel.deleteNote(n.id)
                        case .reminder(let r): viewModel.deleteReminder(r.id)
                        case .meeting(let m):  viewModel.deleteMeeting(m.id)
                        }
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.red.opacity(0.45))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(hovered ? 0.45 : 0.18))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            Group {
                if hovered {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .padding(.horizontal, 6)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { hovered = h } }
        .animation(.spring(response: 0.24, dampingFraction: 0.65), value: hovered)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                switch item {
                case .note(let n):     viewModel.selectedNote = n
                case .reminder(let r): viewModel.selectedReminder = r
                case .meeting(let m):  viewModel.selectedMeeting = m
                }
            }
        }
    }
}

// MARK: - Compat stubs

struct FormatButton: View {
    let label: String; let isActive: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .bold))
                .foregroundColor(isActive ? .white : .secondary)
                .frame(width: 22, height: 22)
                .background(isActive ? Color.accentColor.opacity(0.8) : Color.clear)
                .cornerRadius(3)
        }.buttonStyle(.plain)
    }
}

struct FormatIconButton: View {
    let icon: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary).frame(width: 22, height: 22)
        }.buttonStyle(.plain)
    }
}

#Preview {
    UnifiedJottView(viewModel: OverlayViewModel())
}

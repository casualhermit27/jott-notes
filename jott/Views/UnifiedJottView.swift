import SwiftUI
import AppKit
import Combine
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
                        .transition(.asymmetric(
                            insertion: .push(from: .leading),
                            removal:   .push(from: .trailing)
                        ))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showDetail)

            Spacer() // transparent — fills the rest of the 420px panel
        }
        .frame(width: 520, height: 420) // matches fixed panel size exactly
        .colorScheme(viewModel.isDarkMode ? .dark : .light)
    }
}

// MARK: - Colors

private let jottBarLight   = Color(red: 0.851, green: 0.851, blue: 0.851)  // #d9d9d9
private let jottBarDark    = Color(red: 0.13,  green: 0.13,  blue: 0.14)
private let jottCursorColor = NSColor(red: 0.447, green: 0.420, blue: 1.0, alpha: 1) // #726bff
private let jottPlaceholder = NSColor(red: 0.616, green: 0.616, blue: 0.616, alpha: 1) // #9d9d9d
private let jottLinkHighlightText = NSColor(red: 0.36, green: 0.33, blue: 0.95, alpha: 1)
private let jottLinkHighlightBg = NSColor(red: 0.45, green: 0.42, blue: 1.0, alpha: 0.16)
private let jottLinkUnderline = NSColor(red: 0.36, green: 0.33, blue: 0.95, alpha: 0.35)

// MARK: - Capture View

struct JottCaptureView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var showFormat = false

    var command: JottCommand? {
        guard !viewModel.isForcedCreationMode else { return nil }
        return viewModel.currentCommand
    }

    var showingCreationPreview: Bool {
        guard !viewModel.inputText.isEmpty,
              !viewModel.isTypingNewCommand else { return false }
        return viewModel.commandCreationPreview() != nil
    }

    var body: some View {
        let hasContent = !viewModel.inputText.isEmpty && !viewModel.inputText.hasPrefix("/")
        let isSaved = !viewModel.autoSaveStatus.isEmpty

        let barColor    = viewModel.isDarkMode ? jottBarDark : jottBarLight
        let borderColor = viewModel.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.09)

        VStack(spacing: 4) {
            // Floating toolbar — bubbles up above the bar
            HStack(spacing: 6) {
                Spacer()
                if isSaved {
                    HStack(spacing: 3) {
                        Image(systemName: viewModel.feedbackIcon)
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 0.32, green: 0.78, blue: 0.54))
                        Text(viewModel.autoSaveStatus)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.primary.opacity(0.65))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(barColor)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.4, anchor: .bottom)
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.35, dampingFraction: 0.62)),
                        removal: .scale(scale: 0.4, anchor: .bottom)
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7))
                    ))
                }
                if hasContent {
                    // Format bar — floats left of Aa, morphs from it
                    if showFormat {
                        JottFormatBar(viewModel: viewModel)
                            .background(barColor)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.3, anchor: .trailing)
                                    .combined(with: .opacity)
                                    .animation(.spring(response: 0.38, dampingFraction: 0.62)),
                                removal: .scale(scale: 0.3, anchor: .trailing)
                                    .combined(with: .opacity)
                                    .animation(.spring(response: 0.25, dampingFraction: 0.72))
                            ))
                    }
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) {
                            showFormat.toggle()
                        }
                    } label: {
                        Text("Aa")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(showFormat ? Color.accentColor : .primary.opacity(0.65))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(showFormat ? Color.accentColor.opacity(0.18) : barColor)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(showFormat ? Color.accentColor.opacity(0.25) : borderColor, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.4, anchor: .bottom)
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.35, dampingFraction: 0.62)),
                        removal: .scale(scale: 0.4, anchor: .bottom)
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7))
                    ))
                }
            }
            .padding(.horizontal, 4)
            .frame(height: (hasContent || isSaved) ? nil : 0)
            .opacity((hasContent || isSaved) ? 1 : 0)
            .animation(.spring(response: 0.38, dampingFraction: 0.7), value: hasContent || isSaved)

            // The bar
            VStack(spacing: 0) {
                JottInputArea(viewModel: viewModel, showFormat: $showFormat)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.isLinkAutocompleting && !viewModel.linkCandidates.isEmpty {
                    Divider()
                        .opacity(0.12)
                        .transition(.opacity.animation(.easeOut(duration: 0.08)))
                    NoteLinkAutocompleteView(viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.97, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.28, dampingFraction: 0.78)),
                            removal: .opacity.animation(.easeOut(duration: 0.08))
                        ))
                } else if viewModel.isForcedCreationMode && showingCreationPreview {
                    Divider()
                        .opacity(0.12)
                        .transition(.opacity.animation(.easeOut(duration: 0.1)))
                    ItemCreationPreviewCard(viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeIn(duration: 0.12)),
                            removal:   .opacity.animation(.easeOut(duration: 0.08))
                        ))
                } else if viewModel.isSmartRecalling {
                    Divider()
                        .opacity(0.12)
                        .transition(.opacity.animation(.easeOut(duration: 0.1)))
                    SmartRecallView(viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeIn(duration: 0.12)),
                            removal: .opacity.animation(.easeOut(duration: 0.08))
                        ))
                } else if let cmd = command {
                    Divider()
                        .opacity(0.12)
                        .transition(.opacity.animation(.easeOut(duration: 0.1)))
                    if viewModel.commandMode == nil || viewModel.isTypingNewCommand {
                        JottCommandSuggestionBar(viewModel: viewModel)
                            .transition(.opacity.animation(.easeOut(duration: 0.1)))
                        Divider().opacity(0.07)
                    }
                    if showingCreationPreview {
                        ItemCreationPreviewCard(viewModel: viewModel)
                            .transition(.asymmetric(
                                insertion: .opacity.animation(.easeIn(duration: 0.12)),
                                removal:   .opacity.animation(.easeOut(duration: 0.08))
                            ))
                    } else {
                        JottCommandResults(command: cmd, viewModel: viewModel)
                            .frame(height: (cmd == .open || cmd == .today) ? nil : 260)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.97, anchor: .top)
                                    .combined(with: .opacity)
                                    .animation(.spring(response: 0.36, dampingFraction: 0.78).delay(0.05)),
                                removal: .opacity.animation(.easeOut(duration: 0.1))
                            ))
                    }
                }
            }
            .clipped()
            .background(viewModel.isDarkMode ? jottBarDark : jottBarLight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .animation(
                (viewModel.isLinkAutocompleting || command != nil)
                    ? .spring(response: 0.36, dampingFraction: 0.82)
                    : .easeOut(duration: 0.18),
                value: viewModel.isLinkAutocompleting || command != nil
            )
        }
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
    case inbox
    case today

    init?(input: String) {
        guard input.hasPrefix("/") else { return nil }
        let raw = input.dropFirst()
        let trimmed = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if trimmed == "today" || trimmed == "t" { self = .today; return }
        if trimmed.isEmpty || trimmed == "notes" || trimmed.hasPrefix("notes ") {
            let q = trimmed.hasPrefix("notes ") ? String(raw.dropFirst(6)).trimmingCharacters(in: .whitespaces) : ""
            self = .notes(query: q)
        } else if trimmed == "open" {
            self = .open
        } else if trimmed.hasPrefix("calendar") || trimmed.hasPrefix("calender") || trimmed == "cal" || trimmed == "c" {
            self = .calendar
        } else if trimmed.hasPrefix("reminder") || trimmed == "r" || trimmed == "rem" {
            let q = String(raw.dropFirst(trimmed.hasPrefix("reminder") ? 8 : 0)).trimmingCharacters(in: .whitespaces)
            self = .reminders(query: q)
        } else if trimmed.hasPrefix("meeting") || trimmed == "m" || trimmed == "meet" {
            let q = String(raw.dropFirst(trimmed.hasPrefix("meeting") ? 7 : 0)).trimmingCharacters(in: .whitespaces)
            self = .meetings(query: q)
        } else if trimmed.hasPrefix("search ") {
            self = .search(query: String(raw.dropFirst(7)).trimmingCharacters(in: .whitespaces))
        } else if trimmed == "inbox" || trimmed == "i" {
            self = .inbox
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
    @Binding var showFormat: Bool
    @ObservedObject private var speech = SpeechManager.shared
    @FocusState private var focused: Bool
    @State private var textHeight: CGFloat = 20   // will be overwritten by reportHeight on first render
    @State private var voicePrefix = ""
    private let maxTextHeight: CGFloat = 110

    var badge: TypeBadgeInfo? {
        if let forced = viewModel.forcedType {
            return badgeInfo(for: forced, forced: true)
        }
        if let mode = viewModel.commandMode {
            return badgeInfoForCommand(mode)
        }
        if viewModel.inputText.hasPrefix("/"), !viewModel.isForcedCreationMode {
            return commandBadge
        }
        guard !viewModel.inputText.isEmpty, !viewModel.inputText.hasPrefix("/") else { return nil }
        return badgeInfo(for: viewModel.detectedType, forced: false)
    }

    private func badgeInfoForCommand(_ cmd: JottCommand) -> TypeBadgeInfo {
        switch cmd {
        case .calendar:
            return TypeBadgeInfo(label: "Calendar", bg: Color(red: 0.78, green: 0.88, blue: 0.99),
                                 fg: Color(red: 0.10, green: 0.35, blue: 0.72), icon: "calendar")
        case .reminders:
            return TypeBadgeInfo(label: "Reminders", bg: Color(red: 0.83, green: 0.85, blue: 0.98),
                                 fg: Color(red: 0.20, green: 0.24, blue: 0.74), icon: "bell")
        case .meetings:
            return TypeBadgeInfo(label: "Meetings", bg: Color(red: 0.99, green: 0.90, blue: 0.78),
                                 fg: Color(red: 0.62, green: 0.30, blue: 0.06), icon: "person.2")
        case .notes:
            return TypeBadgeInfo(label: "Notes", bg: Color(red: 0.80, green: 0.95, blue: 0.86),
                                 fg: Color(red: 0.10, green: 0.44, blue: 0.24), icon: "note.text")
        case .open:
            return TypeBadgeInfo(label: "Open", bg: Color(red: 0.92, green: 0.92, blue: 0.95),
                                 fg: Color(red: 0.30, green: 0.30, blue: 0.42), icon: "folder")
        case .search:
            return TypeBadgeInfo(label: "Search", bg: Color(red: 0.92, green: 0.92, blue: 0.95),
                                 fg: Color(red: 0.30, green: 0.30, blue: 0.42), icon: "magnifyingglass")
        case .inbox:
            return TypeBadgeInfo(label: "Inbox", bg: Color(red: 0.92, green: 0.92, blue: 0.95),
                                 fg: Color(red: 0.30, green: 0.30, blue: 0.42), icon: "tray")
        case .today:
            return TypeBadgeInfo(label: "Today", bg: Color.yellow.opacity(0.2),
                                 fg: Color.orange, icon: "sun.max")
        }
    }

    private var commandBadge: TypeBadgeInfo? {
        guard let cmd = JottCommand(input: viewModel.inputText) else { return nil }
        return badgeInfoForCommand(cmd)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {

                // Type badge
                if let b = badge {
                    GradientTypeBadge(info: b)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity),
                            removal:   .scale(scale: 0.5, anchor: .leading).combined(with: .opacity)
                        ))
                }

                // Text editor — trailing padding reserves room for overlay controls
                JottNativeInput(
                    text: $viewModel.inputText,
                    linkCompletion: $viewModel.pendingLinkCompletionTitle,
                    viewModel: viewModel,
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
            .padding(.vertical, 18)
            // Trailing controls as overlay — never affect row height
            .overlay(alignment: .trailing) {
                VStack(alignment: .trailing, spacing: 4) {
                    // Mic button
                    Button(action: toggleVoice) {
                        ZStack {
                            Circle()
                                .fill(speech.isRecording
                                    ? Color(red: 0.98, green: 0.45, blue: 0.45).opacity(0.18)
                                    : Color(red: 0.72, green: 0.67, blue: 1.0).opacity(0.15))
                                .frame(width: 28, height: 28)
                            if speech.isRecording {
                                VoiceWaveformView(level: speech.audioLevel)
                                    .frame(width: 18, height: 14)
                            } else {
                                Image(systemName: "microphone.fill")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color(red: 0.55, green: 0.50, blue: 0.98).opacity(0.75))
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Active tag filter indicator
                    if let tag = viewModel.activeTagFilter {
                        Button(action: { viewModel.setTagFilter(nil) }) {
                            HStack(spacing: 3) {
                                Text("#\(tag)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color(red: 0.35, green: 0.72, blue: 0.50))
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.35, green: 0.72, blue: 0.50).opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.5, anchor: .trailing).combined(with: .opacity))
                    }

                    // Clipboard pre-fill indicator
                    if viewModel.clipboardPrefilled {
                        Button(action: { viewModel.clearClipboardPrefill() }) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text("from clipboard")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.5, anchor: .trailing).combined(with: .opacity))
                    }

                }
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
            } else {
                speech.stopRecording()
                voicePrefix = ""
            }
        }
    }

    private var placeholderText: String {
        if speech.isRecording { return "listening..." }
        if let forced = viewModel.forcedType {
            switch forced {
            case .note:     return "what's on your mind..."
            case .reminder: return "remind me to..."
            case .meeting:  return "meeting title, with who..."
            }
        }
        if let mode = viewModel.commandMode {
            switch mode {
            case .calendar:  return "event title, tomorrow at 3pm..."
            case .meetings:  return "meeting title, friday 2pm..."
            case .reminders: return "remind me to... by when?"
            case .notes:     return "search notes..."
            default:         return ""
            }
        }
        return viewModel.inputText.hasPrefix("/") ? "" : "Type or / for actions…"
    }

    private func toggleVoice() {
        if speech.isRecording {
            speech.stopRecording()
        } else {
            voicePrefix = viewModel.inputText
            speech.startRecording(
                onPartial: { partial in
                    let joined = voicePrefix.isEmpty ? partial : voicePrefix + " " + partial
                    viewModel.inputText = joined
                },
                onFinal: { final in
                    let joined = voicePrefix.isEmpty ? final : voicePrefix + " " + final
                    viewModel.inputText = joined
                    voicePrefix = ""
                }
            )
        }
    }
}

// MARK: - Voice Waveform

struct VoiceWaveformView: View {
    let level: Float   // 0–1 from RMS

    // Five bars with staggered idle-animation durations
    private let durations: [Double] = [0.40, 0.28, 0.35, 0.22, 0.38]
    private let multipliers: [CGFloat] = [0.55, 1.0, 0.75, 0.90, 0.60]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                Bar(level: CGFloat(level),
                    multiplier: multipliers[i],
                    duration: durations[i])
            }
        }
    }

    struct Bar: View {
        let level: CGFloat
        let multiplier: CGFloat
        let duration: Double
        @State private var idle = false

        // idle pulse height when quiet, grows with audio level
        private var height: CGFloat {
            let idleH: CGFloat = idle ? 5 : 2
            return max(idleH, level * 14 * multiplier + 2)
        }

        var body: some View {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.red.opacity(0.75))
                .frame(width: 2.5, height: height)
                .animation(.easeInOut(duration: 0.12), value: level)
                .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true), value: idle)
                .onAppear { idle = true }
        }
    }
}

// MARK: - Type Badge

struct GradientTypeBadge: View {
    let info: TypeBadgeInfo
    @State private var appeared = false
    @State private var bgColor: Color = .clear
    @State private var fgColor: Color = .clear
    @State private var icon: String = ""
    @State private var badgeScale: CGFloat = 1.0
    @State private var iconScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(bgColor)
                .frame(width: 22, height: 22)
            Image(systemName: icon.isEmpty ? info.icon : icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(fgColor)
                .scaleEffect(iconScale)
        }
        .scaleEffect(badgeScale * (appeared ? 1.0 : 0.4))
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            bgColor = info.bg
            fgColor = info.fg
            icon = info.icon
            withAnimation(.spring(response: 0.3, dampingFraction: 0.58)) {
                appeared = true
            }
        }
        .onChange(of: info) { _, newInfo in
            // Squish down — badge and icon compress at the peak
            withAnimation(.spring(response: 0.14, dampingFraction: 0.52)) {
                badgeScale = 0.78
                iconScale  = 0.55
            }
            // Swap icon + bleed new colors at the squish valley
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                icon   = newInfo.icon
                fgColor = newInfo.fg
                // Bg bleeds as it springs back — felt as a liquid pour
                withAnimation(.spring(response: 0.42, dampingFraction: 0.52)) {
                    bgColor    = newInfo.bg
                    badgeScale = 1.0
                    iconScale  = 1.0
                }
            }
        }
    }
}

// MARK: - Command Results

struct JottCommandResults: View {
    let command: JottCommand
    @ObservedObject var viewModel: OverlayViewModel

    var items: [TimelineItem] { viewModel.commandItems(for: command) }

    var label: String {
        switch command {
        case .notes:     return "NOTES"
        case .reminders: return "REMINDERS"
        case .meetings:  return "MEETINGS"
        case .search:    return "SEARCH"
        case .open:      return "ACTION"
        case .calendar:  return "CALENDAR"
        case .inbox:     return "INBOX"
        case .today:     return "TODAY"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Special handling for /open
            if case .open = command {
                JottOpenAction(viewModel: viewModel)
            } else if case .calendar = command {
                CalendarResultsView(viewModel: viewModel)
            } else if case .today = command {
                JottTodayView(viewModel: viewModel)
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
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    JottRow(item: item, viewModel: viewModel, isSelected: index == viewModel.selectedCommandIndex)
                                        .id(index)
                                        .transition(.opacity)
                                }
                            }
                            .padding(.bottom, 6)
                            .animation(.spring(response: 0.34, dampingFraction: 0.8), value: items.map(\.id))
                        }
                        .onChange(of: viewModel.selectedCommandIndex) { idx in
                            proxy.scrollTo(idx)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Command Suggestion Bar

struct CommandChip {
    let label: String
    let shorthand: String
    let icon: String
    let insert: String
}

let allCommandChips: [CommandChip] = [
    CommandChip(label: "Today",     shorthand: "/t",    icon: "sun.max",            insert: "/today"),
    CommandChip(label: "Calendar",  shorthand: "/c",    icon: "calendar",           insert: "/calendar"),
    CommandChip(label: "Notes",     shorthand: "/n",    icon: "note.text",           insert: "/notes"),
    CommandChip(label: "Reminders", shorthand: "/r",    icon: "bell",               insert: "/reminders"),
    CommandChip(label: "Meetings",  shorthand: "/m",    icon: "person.2",           insert: "/meetings"),
    CommandChip(label: "Search",    shorthand: "/s",    icon: "magnifyingglass",    insert: "/search "),
    CommandChip(label: "Open",      shorthand: "/open", icon: "folder",             insert: "/open"),
    CommandChip(label: "Inbox",     shorthand: "/i",    icon: "tray",               insert: "/inbox"),
]

struct JottCommandSuggestionBar: View {
    @ObservedObject var viewModel: OverlayViewModel

    private var chips: [CommandChip] {
        let query = viewModel.inputText.lowercased().dropFirst()   // drop "/"
        if query.isEmpty { return allCommandChips }
        return allCommandChips.filter {
            $0.label.lowercased().hasPrefix(query) ||
            String($0.shorthand.dropFirst()).hasPrefix(query) ||
            String($0.insert.dropFirst()).hasPrefix(query)
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.insert) { chip in
                    Button {
                        if let cmd = JottCommand(input: chip.insert) {
                            viewModel.activateCommandMode(cmd)
                            viewModel.inputText = ""
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: chip.icon)
                                .font(.system(size: 10, weight: .medium))
                            Text(chip.label)
                                .font(.system(size: 11, weight: .medium))
                            Text(chip.shorthand)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.45))
                        }
                        .foregroundColor(.secondary.opacity(0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.07))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
    }
}

// MARK: - Item Creation Preview Card

struct ItemCreationPreviewCard: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var showDatePicker = false

    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        let df = DateFormatter()
        let day: String
        if cal.isDateInToday(date)         { day = "Today" }
        else if cal.isDateInTomorrow(date) { day = "Tomorrow" }
        else { df.dateFormat = "EEE, MMM d"; day = df.string(from: date) }
        df.dateFormat = "h:mm a"
        return "\(day)  \(df.string(from: date))"
    }

    var body: some View {
        if let p = viewModel.commandCreationPreview() {
            let (iconName, accentColor): (String, Color) = {
                switch viewModel.commandMode {
                case .calendar:
                    return ("calendar.badge.plus", Color(red: 0.10, green: 0.35, blue: 0.72))
                case .meetings:
                    return ("person.2.fill", Color(red: 0.62, green: 0.30, blue: 0.06))
                case .reminders:
                    return ("bell.fill", Color(red: 0.20, green: 0.24, blue: 0.74))
                default:
                    return ("plus.circle", .secondary)
                }
            }()

            VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        Image(systemName: iconName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(accentColor)
                            .frame(width: 32, height: 32)
                            .background(accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(2)

                            // Tappable date/time pill → opens DatePicker popover
                            Button {
                                showDatePicker = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 10, weight: .medium))
                                    Text(formattedDate(p.date))
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(p.hasDate ? accentColor : .secondary.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(accentColor.opacity(p.hasDate ? 0.09 : 0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(accentColor.opacity(p.hasDate ? 0.22 : 0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                                VStack(spacing: 0) {
                                    DatePicker(
                                        "",
                                        selection: Binding(
                                            get: { viewModel.commandModeDateOverride ?? p.date },
                                            set: { viewModel.commandModeDateOverride = $0 }
                                        ),
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .datePickerStyle(.graphical)
                                    .labelsHidden()
                                    .padding(12)

                                    Divider().opacity(0.15)
                                    Button("Done") { showDatePicker = false }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(accentColor)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .frame(width: 300)
                            }

                            if let rec = p.recurrence {
                                HStack(spacing: 4) {
                                    Image(systemName: "repeat")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text(rec.label)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(accentColor.opacity(0.65))
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(accentColor.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(accentColor.opacity(0.12), lineWidth: 1)
                    )

                    HStack(spacing: 8) {
                        Image(systemName: "return")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.35))
                        Text("to create")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.25))
                        Text("esc to clear")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                }
            .padding(.horizontal, 20)
            .padding(.top, 20)
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

// MARK: - Smart Recall View

struct SmartRecallView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SUGGESTIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.45))
                    .tracking(0.6)
                Spacer()
                Text("\(viewModel.smartRecallResults.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            ForEach(Array(viewModel.smartRecallResults.enumerated()), id: \.element.id) { index, item in
                JottRow(item: item, viewModel: viewModel, isSelected: index == viewModel.selectedCommandIndex)
                    .id(index)
            }
        }
    }
}

// MARK: - Today View

struct JottTodayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    private let cal = Calendar.current

    var todayItems: [TimelineItem] {
        let reminders = viewModel.getAllReminders()
            .filter { !$0.isCompleted && cal.isDateInToday($0.dueDate) }
            .sorted { $0.dueDate < $1.dueDate }
            .map { TimelineItem.reminder($0) }
        let meetings = viewModel.getAllMeetings()
            .filter { cal.isDateInToday($0.startTime) }
            .sorted { $0.startTime < $1.startTime }
            .map { TimelineItem.meeting($0) }
        return reminders + meetings
    }

    var recentNotes: [TimelineItem] {
        Array(viewModel.getAllNotes().prefix(4).map { TimelineItem.note($0) })
    }

    var pendingItems: [TimelineItem] {
        let now = Date()
        return viewModel.getAllReminders()
            .filter { !$0.isCompleted && $0.dueDate < now && !cal.isDateInToday($0.dueDate) }
            .sorted { $0.dueDate > $1.dueDate }
            .prefix(3)
            .map { TimelineItem.reminder($0) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if todayItems.isEmpty && recentNotes.isEmpty && pendingItems.isEmpty {
                    Text("Nothing for today")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 40)
                } else {
                    if !todayItems.isEmpty {
                        sectionHeader("TODAY")
                        ForEach(Array(todayItems.enumerated()), id: \.element.id) { i, item in
                            JottRow(item: item, viewModel: viewModel, isSelected: false)
                        }
                    }
                    if !recentNotes.isEmpty {
                        sectionHeader("RECENT")
                        ForEach(Array(recentNotes.enumerated()), id: \.element.id) { i, item in
                            JottRow(item: item, viewModel: viewModel, isSelected: false)
                        }
                    }
                    if !pendingItems.isEmpty {
                        sectionHeader("PENDING")
                        ForEach(Array(pendingItems.enumerated()), id: \.element.id) { i, item in
                            JottRow(item: item, viewModel: viewModel, isSelected: false)
                        }
                    }
                }
            }
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.45))
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 2)
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
                    .foregroundColor(.primary)
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
    @Binding var linkCompletion: String?   // set to a note title to trigger [[completion]]
    let viewModel: OverlayViewModel
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
        context.coordinator.parent = self
        context.coordinator.attachIfNeeded(to: scrollView)

        if tv.string != text { tv.string = text }

        let textColor: NSColor = isDark
            ? NSColor(white: 0.92, alpha: 1)
            : NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        let placeholderColor: NSColor = isDark
            ? NSColor(white: 0.45, alpha: 1)
            : jottPlaceholder
        tv.font = .systemFont(ofSize: 17)
        tv.textColor = textColor
        tv.insertionPointColor = jottCursorColor
        tv.jottPlaceholder = placeholder
        tv.jottPlaceholderColor = placeholderColor
        context.coordinator.applyLinkHighlighting(to: tv)

        if isFocused, tv.window?.firstResponder !== tv {
            tv.window?.makeFirstResponder(tv)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JottNativeInput
        weak var scrollView: NSScrollView?
        private var lastReportedHeight: CGFloat = 0
        var isPerformingCompletion = false
        private var isApplyingAttributes = false
        private var completionSubscription: AnyCancellable?
        private static let linkRegex = try? NSRegularExpression(pattern: "\\[\\[[^\\]]+\\]\\]")
        init(_ p: JottNativeInput) { parent = p }

        func attachIfNeeded(to scrollView: NSScrollView) {
            self.scrollView = scrollView
            guard completionSubscription == nil else { return }

            completionSubscription = parent.viewModel.$pendingLinkCompletionTitle
                .receive(on: RunLoop.main)
                .sink { [weak self] title in
                    guard let self, let title else { return }
                    self.applyLinkCompletion(title)
                }
        }

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
            guard !isPerformingCompletion else { return }
            guard !isApplyingAttributes else { return }
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            reportHeight(from: tv)
            detectLinkTrigger(in: tv)
            applyLinkHighlighting(to: tv)
        }

        private func applyLinkCompletion(_ title: String) {
            guard let tv = scrollView?.documentView as? JottNSTextView else { return }

            let cursorPos = tv.selectedRange().location
            let nsStr = tv.string as NSString
            let beforeCursor = nsStr.substring(with: NSRange(location: 0, length: cursorPos))
            let range = (beforeCursor as NSString).range(of: "[[", options: .backwards)

            guard range.location != NSNotFound else {
                parent.linkCompletion = nil
                return
            }

            let completion = "[[\(title)]]"
            let replaceRange = NSRange(location: range.location, length: cursorPos - range.location)

            isPerformingCompletion = true
            if tv.shouldChangeText(in: replaceRange, replacementString: completion) {
                tv.replaceCharacters(in: replaceRange, with: completion)
                tv.didChangeText()
                let newPos = range.location + (completion as NSString).length
                tv.setSelectedRange(NSRange(location: newPos, length: 0))
            }
            isPerformingCompletion = false

            parent.text = tv.string
            parent.linkCompletion = nil
            reportHeight(from: tv)
            applyLinkHighlighting(to: tv)
        }

        func applyLinkHighlighting(to tv: NSTextView) {
            guard let textStorage = tv.textStorage else { return }
            let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
            guard fullRange.length > 0 else { return }

            isApplyingAttributes = true
            let selected = tv.selectedRange()
            textStorage.beginEditing()

            let baseAttrs: [NSAttributedString.Key: Any] = [
                .font: tv.font ?? NSFont.systemFont(ofSize: 17),
                .foregroundColor: tv.textColor ?? NSColor.textColor
            ]
            textStorage.setAttributes(baseAttrs, range: fullRange)

            if let regex = Self.linkRegex {
                let matches = regex.matches(in: tv.string, range: fullRange)
                for m in matches {
                    textStorage.addAttributes(
                        [
                            .foregroundColor: jottLinkHighlightText,
                            .backgroundColor: jottLinkHighlightBg,
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                            .underlineColor: jottLinkUnderline
                        ],
                        range: m.range
                    )
                }
            }

            textStorage.endEditing()
            tv.setSelectedRange(selected)
            isApplyingAttributes = false
        }

        private func detectLinkTrigger(in tv: NSTextView) {
            let cursorPos = tv.selectedRange().location
            guard cursorPos > 0 else {
                if parent.viewModel.isLinkAutocompleting { parent.viewModel.dismissLinkAutocomplete() }
                return
            }
            let beforeCursor = String((tv.string as NSString).substring(with: NSRange(location: 0, length: cursorPos)))
            if let bracketRange = beforeCursor.range(of: "[[", options: .backwards) {
                let query = String(beforeCursor[bracketRange.upperBound...])
                if !query.contains("]]") {
                    parent.viewModel.updateLinkQuery(query)
                    return
                }
                if query.hasSuffix("]]") {
                    let trimmed = String(query.dropLast(2))
                    if !trimmed.contains("]]") {
                        parent.viewModel.updateLinkQuery(trimmed)
                        return
                    }
                }
            }
            if parent.viewModel.isLinkAutocompleting {
                parent.viewModel.dismissLinkAutocomplete()
            }
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            // Intercept keys for [[ autocomplete
            if parent.viewModel.isLinkAutocompleting {
                if sel == #selector(NSResponder.moveDown(_:)) {
                    parent.viewModel.moveLinkSelection(by: 1)
                    return true
                }
                if sel == #selector(NSResponder.moveUp(_:)) {
                    parent.viewModel.moveLinkSelection(by: -1)
                    return true
                }
                if sel == #selector(NSResponder.insertTab(_:)) {
                    parent.viewModel.selectCurrentLinkCandidate()
                    return true
                }
                if sel == #selector(NSResponder.insertNewline(_:)) {
                    parent.viewModel.selectCurrentLinkCandidate()
                    return true
                }
                if sel == #selector(NSResponder.cancelOperation(_:)) {
                    parent.viewModel.dismissLinkAutocomplete()
                    return true
                }
            }
            // Shift+Enter → insert a literal newline (multi-line content)
            if sel == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                tv.insertText("\n", replacementRange: tv.selectedRange())
                return true
            }
            // Enter → create/save the item (command mode OR forced type)
            if sel == #selector(NSResponder.insertNewline(_:)),
               !parent.viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty,
               parent.viewModel.commandCreationPreview() != nil {
                let vm = parent.viewModel
                DispatchQueue.main.async { vm.createCurrentItem() }
                return true
            }
            // Smart Recall navigation
            if parent.viewModel.isSmartRecalling {
                let items = parent.viewModel.smartRecallResults
                if !items.isEmpty {
                    if sel == #selector(NSResponder.moveDown(_:)) {
                        let next = min(parent.viewModel.selectedCommandIndex + 1, items.count - 1)
                        parent.viewModel.selectedCommandIndex = next
                        return true
                    }
                    if sel == #selector(NSResponder.moveUp(_:)) {
                        let prev = max(parent.viewModel.selectedCommandIndex - 1, 0)
                        parent.viewModel.selectedCommandIndex = prev
                        return true
                    }
                    if sel == #selector(NSResponder.insertNewline(_:)) {
                        let idx = max(0, min(parent.viewModel.selectedCommandIndex, items.count - 1))
                        let vm = parent.viewModel
                        DispatchQueue.main.async {
                            switch items[idx] {
                            case .note(let n):     vm.selectedNote = n
                            case .reminder(let r): vm.selectedReminder = r
                            case .meeting(let m):  vm.selectedMeeting = m
                            }
                        }
                        return true
                    }
                    if sel == #selector(NSResponder.insertTab(_:)) {
                        let idx = max(0, min(parent.viewModel.selectedCommandIndex, items.count - 1))
                        let vm = parent.viewModel
                        DispatchQueue.main.async {
                            switch items[idx] {
                            case .note(let n):     vm.selectedNote = n
                            case .reminder(let r): vm.selectedReminder = r
                            case .meeting(let m):  vm.selectedMeeting = m
                            }
                        }
                        return true
                    }
                }
            }
            if parent.viewModel.currentCommand != nil {
                let items = parent.viewModel.currentCommandItems()
                if !items.isEmpty {
                    if sel == #selector(NSResponder.moveDown(_:)) {
                        parent.viewModel.moveCommandSelection(by: 1)
                        return true
                    }
                    if sel == #selector(NSResponder.moveUp(_:)) {
                        parent.viewModel.moveCommandSelection(by: -1)
                        return true
                    }
                    if sel == #selector(NSResponder.insertNewline(_:)) {
                        if parent.viewModel.inlineEditingId != nil {
                            parent.viewModel.saveInlineEdit()
                        } else {
                            parent.viewModel.startInlineEdit()
                            if parent.viewModel.inlineEditingId == nil {
                                parent.viewModel.openSelectedCommandItem()
                            }
                        }
                        return true
                    }
                }
            }
            // Cmd+D → mark selected reminder as done
            if sel == #selector(NSResponder.deleteToEndOfLine(_:)) {
                let items = !parent.viewModel.currentCommandItems().isEmpty
                    ? parent.viewModel.currentCommandItems()
                    : parent.viewModel.smartRecallResults
                guard !items.isEmpty else { return false }
                let idx = max(0, min(parent.viewModel.selectedCommandIndex, items.count - 1))
                if case .reminder(let r) = items[idx] {
                    parent.viewModel.markReminderDone(r.id)
                    return true
                }
                return false
            }
            // Tab-complete a /command suggestion → lock commandMode, clear input
            // Also works when already in a command mode (allows switching)
            if sel == #selector(NSResponder.insertTab(_:)),
               !parent.viewModel.isForcedCreationMode,
               parent.viewModel.inputText.hasPrefix("/") {
                let query = parent.viewModel.inputText.lowercased().dropFirst()
                let match = allCommandChips.first {
                    $0.label.lowercased().hasPrefix(query) ||
                    String($0.shorthand.dropFirst()).hasPrefix(query) ||
                    String($0.insert.dropFirst()).hasPrefix(query)
                }
                if let match, let cmd = JottCommand(input: match.insert) {
                    parent.viewModel.activateCommandMode(cmd)
                    tv.string = ""
                    tv.setSelectedRange(NSRange(location: 0, length: 0))
                    parent.text = ""
                    return true
                }
            }
            // If no command prefix, cycle type with Tab
            if sel == #selector(NSResponder.insertTab(_:)),
               !parent.viewModel.inputText.hasPrefix("/"),
               !parent.viewModel.inputText.isEmpty {
                let current = parent.viewModel.forcedTypeOverride ?? parent.viewModel.detectedType
                let next: DetectedType
                switch current {
                case .note:     next = .reminder
                case .reminder: next = .meeting
                case .meeting:  next = .note
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    parent.viewModel.forcedTypeOverride = next
                }
                return true
            }
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            if sel == #selector(NSResponder.deleteBackward(_:)), tv.string.isEmpty {
                if parent.viewModel.commandMode != nil {
                    parent.viewModel.clearCommandMode()
                } else {
                    parent.onBackspaceOnEmpty?()
                }
                return true
            }
            return false
        }
    }
}

final class JottNSTextView: NSTextView {
    var jottPlaceholder: String = ""
    var jottPlaceholderColor: NSColor = .placeholderTextColor

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.shift),
              !event.modifierFlags.contains(.option) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "b": wrapSelection(with: "**"); return true
        case "i": wrapSelection(with: "_");  return true
        case "u": wrapSelection(with: "__"); return true
        case "e": wrapSelection(with: "`");  return true   // Cmd+E → inline code
        default:  return super.performKeyEquivalent(with: event)
        }
    }

    private func wrapSelection(with marker: String) {
        let sel = selectedRange()
        if sel.length > 0 {
            let selected = (string as NSString).substring(with: sel)
            insertText("\(marker)\(selected)\(marker)", replacementRange: sel)
        } else {
            // No selection — insert paired markers and place cursor inside
            let pos = sel.location
            insertText("\(marker)\(marker)", replacementRange: sel)
            setSelectedRange(NSRange(location: pos + marker.count, length: 0))
        }
    }

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
        .fixedSize()
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
    var isSelected: Bool = false
    @State private var hovered = false
    @FocusState private var isInlineFocused: Bool

    var isDoneReminder: Bool {
        if case .reminder(let r) = item { return r.isCompleted }
        return false
    }

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
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(accent)
                    .frame(width: 18)
                if case .note(let n) = item, n.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.orange)
                        .offset(x: 6, y: -5)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                if case .note(let n) = item, viewModel.inlineEditingId == n.id {
                    TextField("", text: $viewModel.inlineEditText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(viewModel.isDarkMode
                            ? Color(red: 0.92, green: 0.92, blue: 0.94)
                            : Color(red: 0.1, green: 0.1, blue: 0.12))
                        .focused($isInlineFocused)
                        .onSubmit { viewModel.saveInlineEdit() }
                        .onExitCommand { viewModel.cancelInlineEdit() }
                        .onAppear { isInlineFocused = true }
                } else {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(viewModel.isDarkMode
                            ? Color(red: 0.92, green: 0.92, blue: 0.94)
                            : Color(red: 0.1, green: 0.1, blue: 0.12))
                        .lineLimit(1)
                    if let m = meta {
                        Text(m)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary.opacity(0.45))
                            .lineLimit(1)
                    }
                }
            }
            Spacer()

            // Complete button — reminders only, hover
            if hovered, case .reminder(let r) = item {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.markReminderDone(r.id)
                    }
                }) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 0.35, green: 0.72, blue: 0.50))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

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
                if hovered || isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.09) : Color.primary.opacity(0.07))
                        .padding(.horizontal, 6)
                }
            }
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(accent.opacity(0.85))
                    .frame(width: 3, height: 18)
                    .padding(.leading, 13)
                    .shadow(color: accent.opacity(0.4), radius: 4, x: 0, y: 0)
            }
        }
        .opacity(isDoneReminder ? 0.35 : 1.0)
        .animation(.easeOut(duration: 0.3), value: isDoneReminder)
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

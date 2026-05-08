import SwiftUI
import AppKit
import Combine
import EventKit

// Near-black surface (#0A0A0A). Pure black creates too-hard edge contrast against bright wallpapers.
private let jottNotchVoidBlack = Color(nsColor: NSColor(deviceWhite: 0.04, alpha: 1.0))

// Content opacity tied directly to the morph spring via Animatable.
// SwiftUI calls body(content:) with the per-frame interpolated progress value,
// so content genuinely resolves out of the expanding surface rather than cross-fading independently.
private struct ContentRevealModifier: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        // Content fades in from ~42% open so it overlaps slightly with
        // the pinned handoff icons fading out (which finish by ~45%).
        let x = max(0.0, min(1.0, (progress - 0.42) / 0.58))
        let opacity = x * x * (3 - 2 * x)  // smoothstep
        return content.opacity(opacity)
    }
}

enum JottTextFormatCommand: Equatable {
    case bold
    case italic
    case underline
    case strikethrough
    case highlight
    case inlineCode
    case link
    case heading
    case bulletList
    case numberedList
    case taskList
    case quote
    case codeBlock
    case table(rows: Int, columns: Int)
}

final class JottTextFormattingRegistry {
    static weak var activeTextView: NSTextView?
}

enum JottTextFormatting {
    @discardableResult
    static func apply(_ command: JottTextFormatCommand, fallbackText: inout String) -> Bool {
        if let tv = targetTextView(), apply(command, to: tv) { return true }
        return false
    }

    @discardableResult
    static func apply(_ command: JottTextFormatCommand) -> Bool {
        guard let tv = targetTextView() else { return false }
        return apply(command, to: tv)
    }

    static func applying(_ command: JottTextFormatCommand, to text: String) -> String {
        text
    }

    @discardableResult
    static func handleContinuationNewline(in tv: NSTextView) -> Bool {
        false
    }

    @discardableResult
    static func handleTab(in tv: NSTextView) -> Bool {
        return false
    }

    private static func targetTextView() -> NSTextView? {
        if let active = JottTextFormattingRegistry.activeTextView, active.window != nil {
            return active
        }
        if let active = JottNSTextView.activeTextView, active.window != nil {
            return active
        }
        return NSApp.keyWindow?.firstResponder as? NSTextView
    }

    @discardableResult
    static func apply(_ command: JottTextFormatCommand, to tv: NSTextView) -> Bool {
        JottTextFormattingRegistry.activeTextView = tv
        return false
    }
}

private extension AnyTransition {
    static var jottCaptureIn: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.97, anchor: .center)
                .combined(with: .opacity)
                .animation(JottMotion.panel),
            removal:  .scale(scale: 0.985, anchor: .center)
                .combined(with: .opacity)
                .animation(JottMotion.content)
        )
    }

    static var jottDetailIn: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 6)
                .combined(with: .scale(scale: 0.97, anchor: .top))
                .combined(with: .opacity)
                .animation(JottMotion.panel),
            removal: .offset(y: -4)
                .combined(with: .scale(scale: 0.985, anchor: .top))
                .combined(with: .opacity)
                .animation(JottMotion.content)
        )
    }

    static var jottDetailSwap: AnyTransition {
        .asymmetric(
            insertion: .offset(x: 4, y: 0).combined(with: .opacity)
                .animation(JottMotion.content),
            removal: .opacity.animation(JottMotion.content)
        )
    }

    static var jottDropdown: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.97, anchor: .top)
                .combined(with: .offset(y: 6))
                .combined(with: .opacity)
                .animation(JottMotion.panel),
            removal: .scale(scale: 0.985, anchor: .top)
                .combined(with: .offset(y: -4))
                .combined(with: .opacity)
                .animation(JottMotion.content)
        )
    }

    static var jottToolbarReveal: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.96, anchor: .trailing)
                .combined(with: .opacity)
                .animation(JottMotion.content),
            removal: .scale(scale: 0.98, anchor: .trailing)
                .combined(with: .opacity)
                .animation(JottMotion.content)
        )
    }
}


private struct VoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(1.0)
            .brightness(configuration.isPressed ? -0.07 : 0)
            .animation(JottMotion.micro, value: configuration.isPressed)
    }
}

// MARK: - Keyboard hint chip

private struct JottKbdChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.42))
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Color.secondary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 0.5)
            )
    }
}

// MARK: - Root View
// Panel is fixed 520×420 and transparent. The card inside grows/shrinks via SwiftUI.

struct UnifiedJottView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @StateObject private var purchases = PurchaseManager.shared
    @State private var showPaywall = false

    var showDetail: Bool {
        viewModel.selectedNote != nil || viewModel.selectedReminder != nil
    }

    private var sceneID: String {
        if let note = viewModel.selectedNote { return "note-\(note.id.uuidString)" }
        if let reminder = viewModel.selectedReminder { return "reminder-\(reminder.id.uuidString)" }
        return "capture"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if showDetail {
                    DetailView(viewModel: viewModel)
                        .frame(width: viewModel.panelDisplayWidth, height: 372)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .transition(.jottDetailIn)
                        .zIndex(1)
                } else {
                    JottCaptureView(viewModel: viewModel)
                        .transition(.jottCaptureIn)
                        .zIndex(0)
                }
            }
            .id(sceneID)
            .animation(JottMotion.panel, value: sceneID)
        }
        .frame(width: viewModel.panelDisplayWidth, height: 640, alignment: .top)
        .colorScheme(.dark)
        .jottAppTypography()
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .jottShowPaywall)) { _ in
            showPaywall = true
        }
    }
}

// MARK: - Colors

private let jottCursorColor = NSColor.jottCursor
private let jottPlaceholder = NSColor.jottPlaceholder

private extension View {
    func jottDetachedCard(
        cornerRadius: CGFloat = 12,
        background: Color = .jottOverlaySurface,
        border: Color = .jottBorder,
        isDark: Bool,
        accentColors: [Color] = [
            .jottOverlaySky,
            .jottOverlayMintAccent,
            .jottOverlayPeachAccent,
        ],
        innerShadowOpacity: Double = 0,
        innerHighlightOpacity: Double = 0
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return self
            .jottGlassPanel(
                cornerRadius: cornerRadius,
                isDark: isDark,
                baseFill: background,
                border: border,
                accentColors: accentColors
            )
            .overlay(
                Group {
                    if innerShadowOpacity > 0 {
                        shape
                            .strokeBorder(Color.black.opacity(innerShadowOpacity), lineWidth: 10)
                            .blur(radius: 8)
                            .offset(y: 1)
                            .blendMode(.multiply)
                            .mask(shape)
                    }
                }
            )
            .overlay(
                Group {
                    if innerHighlightOpacity > 0 {
                        shape
                            .strokeBorder(Color.white.opacity(innerHighlightOpacity), lineWidth: 5)
                            .blur(radius: 3)
                            .offset(y: -1)
                            .blendMode(.screen)
                            .mask(shape)
                    }
                }
            )
    }
}

// MARK: - Capture View

struct JottCaptureView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var showFormat = false
    @State private var showHelp = false
    @State private var dropdownReady = false
    @AppStorage("jott_hasSeenWelcome") private var hasSeenWelcome: Bool = false

    @ObservedObject private var speech = SpeechManager.shared
    @State private var voicePrefix = ""
    private var micFill: Color { Color(white: 0.92) }

    private func stopVoice() {
        speech.stopRecording()
        voicePrefix = ""
    }

    private func resetVoiceState() {
        speech.resetTransientState()
        voicePrefix = ""
    }

    private func toggleVoice() {
        if speech.isRecording {
            stopVoice()
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

    var command: JottCommand? {
        guard !viewModel.isForcedCreationMode else { return nil }
        return viewModel.currentCommand
    }


    var showingCreationPreview: Bool {
        guard !viewModel.inputText.isEmpty,
              !viewModel.isTypingNewCommand else { return false }
        return viewModel.commandCreationPreview() != nil
    }

    private func commandKind(_ cmd: JottCommand) -> String {
        switch cmd {
        case .reminders: return "reminders"
        case .search: return "search"
        case .open: return "open"
        case .calendar: return "calendar"
        case .inbox: return "recent"
        case .today: return "today"
        }
    }

    private var dropdownStateID: String {
        if viewModel.inputText == "?" {
            return "help"
        }
        if viewModel.isForcedCreationMode && showingCreationPreview {
            return "forced-preview"
        }
        // A fresh "/" should always reveal the command picker, even while switching
        // out of an existing command mode.
        if viewModel.inputText.hasPrefix("/"),
           !viewModel.isForcedCreationMode,
           (viewModel.commandMode == nil || viewModel.isTypingNewCommand) {
            return "slash-picker"
        }
        if let cmd = command {
            let kind = commandKind(cmd)
            if showingCreationPreview { return "command-preview-\(kind)" }
            if viewModel.commandMode == nil || viewModel.isTypingNewCommand {
                return "command-shell-\(kind)"
            }
            return "command-\(kind)"
        }
        if viewModel.inputText.isEmpty && viewModel.commandMode == nil && !viewModel.isForcedCreationMode {
            if !hasSeenWelcome { return "welcome" }
        }
        return "none"
    }

    private var showsDropdown: Bool {
        dropdownStateID != "none"
    }

    @ViewBuilder
    private var dropdownContent: some View {
        if viewModel.isForcedCreationMode && showingCreationPreview {
            ItemCreationPreviewCard(viewModel: viewModel)
        } else if let cmd = command {
            VStack(spacing: 0) {
                if showingCreationPreview {
                    ItemCreationPreviewCard(viewModel: viewModel)
                } else {
                    JottCommandResults(command: cmd, viewModel: viewModel)
                }
            }
            .frame(height: 300, alignment: .top)
        } else if dropdownStateID == "slash-picker" {
            JottSlashCommandPicker(viewModel: viewModel)
        } else if dropdownStateID == "help" {
            JottHelpPopover()
                .frame(maxWidth: .infinity)
        } else if dropdownStateID == "welcome" {
            JottWelcomeCard { hasSeenWelcome = true }
        }
    }

    @ViewBuilder private var toolbarRow: some View {
        let isSaved = !viewModel.autoSaveStatus.isEmpty
        HStack(spacing: 6) {
            Button { showHelp.toggle() } label: {
                Text("?")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.28))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                JottHelpPopover()
            }

            Spacer()
            // Lock state is shown between status and the right-side lock button so the
            // user always knows which mode is active.

            if isSaved {
                HStack(spacing: 3) {
                    Image(systemName: viewModel.feedbackIcon)
                        .font(.system(size: 9))
                        .foregroundColor(Color("jott-accent-green"))
                    Text(viewModel.autoSaveStatus)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.50))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())
                .transition(.asymmetric(
                    insertion: .offset(y: -3).combined(with: .opacity).animation(JottMotion.panel),
                    removal: .opacity.animation(JottMotion.content)
                ))
            }

            if viewModel.clipboardPrefilled {
                clipboardOfferButton
            }

            // Lock button — mirrors "?" on the left, always rightmost.
            Button { viewModel.isLocked.toggle() } label: {
                Image(systemName: viewModel.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(viewModel.isLocked ? Color.jottOverlayPeachAccent : .white.opacity(0.28))
                    .frame(width: 22, height: 22)
                    .background(viewModel.isLocked ? Color.jottOverlayPeachAccent.opacity(0.15) : Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(viewModel.isLocked ? "Locked — ESC or ⌥⌥ to dismiss" : "Unlocked — click to lock")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .colorScheme(.dark)
        .animation(JottMotion.content, value: isSaved || viewModel.clipboardPrefilled || viewModel.isLocked)
    }

    @ViewBuilder private var clipboardOfferButton: some View {
        Button(action: {
            if let textView = JottNSTextView.activeTextView,
               textView.insertTransfer(from: NSPasteboard.general) {
                textView.window?.makeFirstResponder(textView)
                viewModel.clearClipboardPrefill()
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: viewModel.pendingClipboardKind == .image ? "photo" : "doc.on.clipboard")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.40))
                Text(viewModel.pendingClipboardKind == .image ? "Use image" : "Use clipboard")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.50))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.07))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Insert clipboard content")
        .accessibilityHint("Adds the recent clipboard content to the note input.")
        .transition(.asymmetric(
            insertion: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity).animation(JottMotion.content),
            removal: .scale(scale: 0.98, anchor: .bottom).combined(with: .opacity).animation(JottMotion.content)
        ))
    }

    @ViewBuilder private var dropdownSection: some View {
        if showsDropdown && dropdownReady {
            ZStack {
                dropdownContent
                    .transition(.opacity.animation(JottMotion.content))
            }
            .colorScheme(.dark)
            .animation(JottMotion.content, value: dropdownStateID)
            .padding(.top, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black)
                    .padding(.top, 6)
            )
            .transition(.jottDropdown)
        }
    }

    @ViewBuilder private var floatingActions: some View {
        VStack(spacing: 6) {
            if showFormat {
                JottFormatBar(viewModel: viewModel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
                    )
                    .clipShape(Capsule())
                    .transition(.jottToolbarReveal)
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { showFormat.toggle() }
                } label: {
                    Text("Aa")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(showFormat ? .white : .white.opacity(0.50))
                        .frame(width: 46, height: 34)
                        .background(
                            Capsule()
                                .fill(Color.black)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.90, pressedOpacity: 0.94))
                .accessibilityLabel("Text formatting options")
                .accessibilityValue(showFormat ? "Expanded" : "Collapsed")

                micButton
            }
        }
        .padding(.top, 4)
        .colorScheme(.dark)
    }

    @ViewBuilder private var micButton: some View {
        Group {
            if speech.isRecording {
                HStack(spacing: 0) {
                    Button(action: stopVoice) {
                        VoiceWaveformPill(level: speech.audioLevel)
                            .frame(width: 76, height: 36)
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(VoiceButtonStyle())
                    .accessibilityLabel("Stop voice capture")

                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 0.5, height: 16)
                        .padding(.trailing, 1)

                    Button(action: stopVoice) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.82))
                            .frame(width: 30, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop voice capture")
                }
                .frame(width: 110, height: 36)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black)
                        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
                )
                .clipShape(Capsule(style: .continuous))
                .transition(.opacity.animation(.easeInOut(duration: 0.08)))
            } else {
                Button(action: toggleVoice) {
                    Image(systemName: "microphone.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.50))
                        .frame(width: 36, height: 36)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black)
                                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
                        )
                        .clipShape(Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(VoiceButtonStyle())
                .transition(.opacity.animation(.easeInOut(duration: 0.08)))
                .accessibilityLabel("Start voice capture")
            }
        }
        .animation(JottMotion.panel, value: speech.isRecording)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {

            // ── Black notch panel ──────────────────────────────────────────
            VStack(spacing: 0) {
                toolbarRow
                    .modifier(ContentRevealModifier(progress: viewModel.revealProgress))

                JottInputArea(viewModel: viewModel,
                              showFormat: $showFormat,
                              dropdownVisible: showsDropdown && dropdownReady,
                              onToggleVoice: toggleVoice,
                              micInside: false)
                    .modifier(ContentRevealModifier(progress: viewModel.revealProgress))
                    .colorScheme(.dark)
            }
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 8,
                    bottomTrailingRadius: 8,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(jottNotchVoidBlack)
            )

            // ── Dropdown — floats below input panel ────────────────────────
            dropdownSection
                .modifier(ContentRevealModifier(progress: viewModel.revealProgress))

            // ── Floating actions ───────────────────────────────────────────
            floatingActions
                .modifier(ContentRevealModifier(progress: viewModel.revealProgress))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(JottMotion.content) { dropdownReady = true }
            }
        }
        .onDisappear { dropdownReady = false }
        .onChange(of: viewModel.isVisible) { _, visible in
            if visible {
                resetVoiceState()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    guard viewModel.isVisible else { return }
                    withAnimation(JottMotion.content) { dropdownReady = true }
                }
            } else {
                dropdownReady = false
                resetVoiceState()
            }
        }
        .background(JottDropSurface(viewModel: viewModel))
    }
}

// MARK: - Command detection

enum JottCommand: Equatable {
    case reminders(query: String)
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
        if trimmed == "search" || trimmed == "s" || trimmed.hasPrefix("search ") || trimmed.hasPrefix("s ") {
            let query: String
            if trimmed.hasPrefix("search ") {
                query = String(raw.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("s ") {
                query = String(raw.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else {
                query = ""
            }
            self = .search(query: query)
        } else if trimmed == "recent" || trimmed == "recents" || trimmed == "r" {
            self = .inbox
        } else {
            return nil
        }
    }
}

// MARK: - Type Badge Data

struct TypeBadgeInfo: Equatable {
    let label: String
    let icon: String
    let tint: Color
}

func badgeInfo(for type: DetectedType, forced: Bool) -> TypeBadgeInfo? {
    switch type {
    case .note:
        guard forced else { return nil }
        return TypeBadgeInfo(
            label: "Note",
            icon: "doc.text",
            tint: .jottNoteAccent)
    case .reminder:
        return TypeBadgeInfo(
            label: "Reminder",
            icon: "bell",
            tint: .jottReminderAccent)
    }
}

// MARK: - Main Input Area

struct JottInputArea: View {
    @ObservedObject var viewModel: OverlayViewModel
    @Binding var showFormat: Bool
    var dropdownVisible: Bool = false
    var onToggleVoice: () -> Void = {}
    var micInside: Bool = true
    @ObservedObject private var speech = SpeechManager.shared
    @FocusState private var focused: Bool
    @State private var textHeight: CGFloat = 20
    @State private var hintIndex: Int = 0
    private let idleHints: [String] = [
        "Capture a thought…",
        "What's on your mind?",
        "Add a meeting note…",
        "Drop a quick idea…",
        "Log something…",
    ]

    // When dropdown is visible leave room for it; when not, fill the panel
    private var maxTextHeight: CGFloat { dropdownVisible ? 120 : 540 }

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
            return TypeBadgeInfo(label: "Calendar", icon: "calendar",
                                 tint: .jottReminderAccent)
        case .reminders:
            return TypeBadgeInfo(label: "Reminders", icon: "bell",
                                 tint: .jottReminderAccent)
        case .open:
            return TypeBadgeInfo(label: "Open", icon: "folder",
                                 tint: .secondary)
        case .search:
            return TypeBadgeInfo(label: "Search", icon: "magnifyingglass",
                                 tint: .jottOverlaySelectorAccent)
        case .inbox:
            return TypeBadgeInfo(label: "Recent", icon: "clock",
                                 tint: .secondary)
        case .today:
            return TypeBadgeInfo(label: "Today", icon: "sun.max",
                                 tint: .orange)
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
                            insertion: .opacity,
                            removal: .opacity
                        ))
                }

                // Text editor — trailing padding reserves room for overlay controls
                let showHintOverlay = viewModel.inputText.isEmpty
                    && !speech.isRecording
                    && viewModel.forcedType == nil
                    && viewModel.commandMode == nil

                ZStack(alignment: .topLeading) {
                    JottNativeInput(
                        text: $viewModel.inputText,
                        viewModel: viewModel,
                        placeholder: showHintOverlay ? "" : placeholderText,
                        isDark: true,  // panel is always black
                        isFocused: focused,
                        onEscape: { viewModel.handleEscape() },
                        onToggleFormatShortcut: toggleFormatBar,
                        onToggleVoiceShortcut: onToggleVoice,
                        onClearTagFilterShortcut: clearActiveTagFilter,
                        onClearClipboardShortcut: clearClipboardPrefill,
                        onBackspaceOnEmpty: { viewModel.clearForcedType() },
                        onHeightChange: { h in
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                                textHeight = min(h, maxTextHeight)
                            }
                        }
                    )

                    if showHintOverlay {
                        Text(idleHints[hintIndex])
                            .font(.system(size: 17))
                            .foregroundColor(Color(NSColor(white: 0.32, alpha: 1)))
                            .id(hintIndex)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: textHeight)
                .padding(.trailing, micInside ? 48 : 8)
                .animation(.easeInOut(duration: 0.45), value: hintIndex)
                .onChange(of: dropdownVisible) { _, visible in
                    withAnimation(JottMotion.content) {
                        textHeight = min(textHeight, visible ? 120 : 500)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
            // Trailing controls as overlay — never affect row height
            .overlay(alignment: .trailing) {
                VStack(alignment: .trailing, spacing: 4) {
                    // Inner mic — visible when not typing
                    if micInside {
                        Button(action: onToggleVoice) {
                            ZStack {
                                if speech.isRecording {
                                    VoiceListeningView(level: speech.audioLevel,
                                                       tint: Color(red: 0.447, green: 0.420, blue: 1.0))
                                        .frame(width: 44, height: 40)
                                        .transition(.scale(scale: 0.84).combined(with: .opacity))
                                } else {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(red: 0.447, green: 0.420, blue: 1.0))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "microphone.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                }
                            }
                            .frame(width: 40, height: 40)
                        }
                        .buttonStyle(VoiceButtonStyle())
                        .animation(JottMotion.panel, value: speech.isRecording)
                        .accessibilityLabel(speech.isRecording ? "Stop voice capture" : "Start voice capture")
                    }

                    // Active tag filter indicator
                    if let tag = viewModel.activeTagFilter {
                        Button(action: clearActiveTagFilter) {
                            HStack(spacing: 3) {
                                Text("#\(tag)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color("jott-green"))
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.jottOverlayMintAccent.opacity(0.20))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.jottOverlayMintAccent.opacity(0.22), lineWidth: 0.6))
                        }
                        .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.95, pressedOpacity: 0.94))
                        .accessibilityLabel("Clear tag filter")
                        .accessibilityValue(tag)
                        .accessibilityHint("Removes the active tag filter.")
                        .transition(.scale(scale: 0.96, anchor: .trailing).combined(with: .opacity).animation(JottMotion.content))
                    }


                }
                .padding(.trailing, 8)
            }

            if !viewModel.draftTables.isEmpty {
                VStack(spacing: 10) {
                    ForEach($viewModel.draftTables) { $table in
                        JottDraftTableEditor(table: $table)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)).animation(JottMotion.content))
            }

            if let error = speech.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(2)
                }
                .foregroundColor(.orange.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

        }
        .animation(JottMotion.content, value: badge)
        .onAppear { focused = true }
        .onReceive(Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()) { _ in
            guard viewModel.inputText.isEmpty,
                  !speech.isRecording,
                  viewModel.forcedType == nil,
                  viewModel.commandMode == nil
            else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                hintIndex = (hintIndex + 1) % idleHints.count
            }
        }
        .onChange(of: viewModel.isVisible) { _, visible in
            if visible {
                DispatchQueue.main.async {
                    focused = true
                    showFormat = false
                }
            }
        }
    }

    private var placeholderText: String {
        if speech.isRecording { return "listening..." }
        if let forced = viewModel.forcedType {
            switch forced {
            case .note:     return "what's on your mind..."
            case .reminder: return "remind me to..."
            }
        }
        if let mode = viewModel.commandMode {
            switch mode {
            case .calendar:  return "event title, tomorrow at 3pm..."
            case .reminders: return "remind me to... by when?"
            default:         return ""
            }
        }
        // idle state: SwiftUI overlay shows rotating hint, suppress native placeholder
        return ""
    }

    private func toggleFormatBar() {
        withAnimation(JottMotion.content) {
            showFormat.toggle()
        }
    }

    private func clearActiveTagFilter() {
        viewModel.setTagFilter(nil)
    }

    private func clearClipboardPrefill() {
        viewModel.clearClipboardPrefill()
    }

    private func useClipboardOffer() {
        if let textView = activeJottTextView(),
           textView.insertTransfer(from: NSPasteboard.general) {
            textView.window?.makeFirstResponder(textView)
            viewModel.clearClipboardPrefill()
            return
        }

        // Fallback for cases where SwiftUI moved focus before the native editor was found.
        viewModel.insertPendingClipboardText()
    }

    private func activeJottTextView() -> JottNSTextView? {
        if let active = JottNSTextView.activeTextView, active.window != nil {
            return active
        }
        if let keyWindowView = NSApp.keyWindow?.contentView,
           let textView = findJottTextView(in: keyWindowView) {
            return textView
        }
        if let mainWindowView = NSApp.mainWindow?.contentView,
           let textView = findJottTextView(in: mainWindowView) {
            return textView
        }
        return nil
    }

    private func findJottTextView(in view: NSView) -> JottNSTextView? {
        if let textView = view as? JottNSTextView {
            return textView
        }
        for subview in view.subviews {
            if let textView = findJottTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
}

private struct JottDraftTableEditor: View {
    @Binding var table: JottDraftTable
    @FocusState private var focusedCell: String?

    private let minColumnWidth: CGFloat = 110
    private let rowHeight: CGFloat = 34

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.headers.indices, id: \.self) { column in
                        tableCell(
                            text: Binding(
                                get: { table.headers[column] },
                                set: { table.headers[column] = $0 }
                            ),
                            id: "h-\(column)",
                            isHeader: true
                        )
                    }
                }

                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { column in
                            tableCell(
                                text: Binding(
                                    get: { value(row: row, column: column) },
                                    set: { setValue($0, row: row, column: column) }
                                ),
                                id: "\(row)-\(column)",
                                isHeader: false
                            )
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 5) {
                Button(action: addColumn) {
                    Image(systemName: "rectangle.grid.1x2")
                }
                Button(action: addRow) {
                    Image(systemName: "rectangle.grid.2x1")
                }
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white.opacity(0.42))
            .padding(5)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(6)
            .buttonStyle(.plain)
        }
    }

    private func tableCell(text: Binding<String>, id: String, isHeader: Bool) -> some View {
        TextField("", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: isHeader ? .semibold : .regular))
            .foregroundColor(.white.opacity(isHeader ? 0.90 : 0.82))
            .focused($focusedCell, equals: id)
            .padding(.horizontal, 10)
            .frame(minWidth: minColumnWidth, minHeight: rowHeight, alignment: .leading)
            .background(isHeader ? Color.white.opacity(0.075) : Color.white.opacity(0.035))
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(focusedCell == id ? 0.32 : 0.09), lineWidth: focusedCell == id ? 1.2 : 0.6)
            )
    }

    private func value(row: Int, column: Int) -> String {
        guard table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return "" }
        return table.rows[row][column]
    }

    private func setValue(_ value: String, row: Int, column: Int) {
        guard table.rows.indices.contains(row) else { return }
        while table.rows[row].count <= column {
            table.rows[row].append("")
        }
        table.rows[row][column] = value
    }

    private func addRow() {
        table.rows.append(Array(repeating: "", count: table.headers.count))
    }

    private func addColumn() {
        let next = table.headers.count + 1
        table.headers.append("Column \(next)")
        for index in table.rows.indices {
            table.rows[index].append("")
        }
    }
}

// MARK: - Voice Listening Blob

private struct VoiceBlobShape: Shape {
    var phase: Double
    var intensity: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(phase, intensity) }
        set {
            phase = newValue.first
            intensity = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let base = side * 0.31
        let lift = min(max(intensity, 0), 1)
        let points = 18

        var samples: [CGPoint] = []
        for i in 0..<points {
            let angle = Double(i) / Double(points) * Double.pi * 2
            let slowWave = sin(angle * 2.0 + phase * 0.95)
            let softWave = cos(angle * 3.0 - phase * 0.68)
            let asymmetry = sin(angle - 0.75) * 0.06
            let radius = base * (1.0 + asymmetry + slowWave * (0.055 + lift * 0.09) + softWave * (0.035 + lift * 0.06))
            samples.append(CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
        }

        var path = Path()
        guard let first = samples.first else { return path }
        path.move(to: first)

        for i in 0..<samples.count {
            let current = samples[i]
            let next = samples[(i + 1) % samples.count]
            let previous = samples[(i - 1 + samples.count) % samples.count]
            let afterNext = samples[(i + 2) % samples.count]
            let smoothing: CGFloat = 0.20
            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) * smoothing,
                y: current.y + (next.y - previous.y) * smoothing
            )
            let control2 = CGPoint(
                x: next.x - (afterNext.x - current.x) * smoothing,
                y: next.y - (afterNext.y - current.y) * smoothing
            )
            path.addCurve(to: next, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }
}

/// Bare organic blob with restrained audio-reactive motion. No container.
// MARK: - Voice Waveform Pill

struct VoiceWaveformPill: View {
    let level: Float
    @State private var smoothLevel: Float = 0

    private let barCount  = 20
    private let barWidth: CGFloat = 1.5

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let amp = Double(smoothLevel)

            Canvas { ctx, size in
                let usable = size.width - 16          // 8pt inset each side
                let gap    = (usable - barWidth * CGFloat(barCount)) / CGFloat(barCount - 1)
                let cy     = size.height / 2
                let maxH   = size.height * 0.72

                for i in 0..<barCount {
                    let x   = 8 + CGFloat(i) * (barWidth + gap)
                    let rel = Double(i) / Double(barCount - 1)   // 0…1

                    // organic multi-freq wave, each bar offset in phase
                    let ph   = t * 5.5 + rel * .pi * 3.2
                    let wave = sin(ph) * 0.55
                           + sin(ph * 1.73 + 1.1) * 0.27
                           + sin(ph * 2.91 + 2.4) * 0.18

                    // bell-curve envelope — taller in the middle
                    let norm = rel * 2 - 1
                    let env  = exp(-norm * norm * 1.6)

                    let idleH  = 2.0 + abs(wave) * 1.8
                    let activeH = amp * env * maxH * (0.22 + abs(wave) * 0.78)
                    let h = CGFloat(max(idleH, activeH))

                    let rect = CGRect(x: x, y: cy - h / 2, width: barWidth, height: h)
                    let alpha = 0.45 + 0.55 * env * amp
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(.white.opacity(alpha)))
                }
            }
        }
        .onChange(of: level) { _, v in
            let boosted = min(1, max(0, Double(v) * 2.4 + 0.06))
            withAnimation(.spring(response: 0.07, dampingFraction: 0.65)) {
                smoothLevel = Float(boosted)
            }
        }
    }
}

// MARK: - Voice Blob (legacy — used for inline mic)

struct VoiceListeningView: View {
    let level: Float   // 0–1 from RMS
    let tint: Color
    var showBackground: Bool = true
    var size: CGFloat = 40

    @State private var smoothLevel: Float = 0

    private func blobScale(at time: Double) -> CGFloat {
        let clamped = max(0, min(1, Double(smoothLevel)))
        return CGFloat(1.0 + sin(time * (1.25 + clamped * 1.8)) * (0.03 + clamped * 0.10))
    }

    private var blobOpacity: Double {
        0.82 + Double(max(0, min(1, smoothLevel))) * 0.16
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let clamped = max(0, min(1, Double(smoothLevel)))

            VoiceBlobShape(phase: t, intensity: clamped)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.98),
                            tint.opacity(0.86),
                            tint.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(blobOpacity)
                .scaleEffect(blobScale(at: t))
                .shadow(color: tint.opacity(0.22 + clamped * 0.16), radius: 5 + clamped * 4, x: 0, y: 1)
                .frame(width: size, height: size)
        }
        .onChange(of: level) { _, newVal in
            let boosted = min(1, max(0, newVal * 1.75 + 0.08))
            withAnimation(JottMotion.micro) { smoothLevel = boosted }
        }
    }
}

// MARK: - Type Badge

struct GradientTypeBadge: View {
    let info: TypeBadgeInfo
    private let badgeShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: info.icon)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundColor(info.tint.opacity(0.76))
            Text(info.label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(info.tint.opacity(0.86))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            badgeShape
                .fill(Color.clear)
        )
        .overlay(
            badgeShape
                .strokeBorder(info.tint.opacity(0.30), lineWidth: 0.8)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(info.label) type")
        .accessibilityHint("Indicates the detected content type.")
    }
}

// MARK: - Command Results

// MARK: - Shared results section header

private struct ResultsSectionHeader: View {
    let title: String
    let icon: String
    let accent: Color
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary.opacity(0.32))

            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.42))
                .tracking(1.2)

            Spacer()

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.32))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.06)
                .padding(.horizontal, 16)
        }
    }
}

// MARK: - Highlighted text (search query match coloring)

struct HighlightedText: View {
    let text: String
    let query: String
    var font: Font = .body
    var baseColor: Color = .primary.opacity(0.88)
    var highlightColor: Color = Color(red: 0.447, green: 0.420, blue: 1.0)

    private var segments: [(String, Bool)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [(text, false)] }
        let lowerText = text.lowercased()
        let lowerQ = q.lowercased()
        var result: [(String, Bool)] = []
        var idx = text.startIndex

        while idx < text.endIndex {
            if let range = lowerText.range(of: lowerQ, range: idx..<lowerText.endIndex) {
                if idx < range.lowerBound {
                    result.append((String(text[idx..<range.lowerBound]), false))
                }
                result.append((String(text[range]), true))
                idx = range.upperBound
            } else {
                result.append((String(text[idx...]), false))
                break
            }
        }
        return result.isEmpty ? [(text, false)] : result
    }

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.0)
            part.font = font
            part.foregroundColor = segment.1 ? highlightColor : baseColor
            if segment.1 {
                part.inlinePresentationIntent = .stronglyEmphasized
            }
            result.append(part)
        }
        return result
    }
}

// Shared 2-column note grid with scroll sync
private struct NoteGrid: View {
    let notes: [Note]
    @ObservedObject var viewModel: OverlayViewModel
    var selectedIndex: Int? = nil
    var highlightQuery: String? = nil

    private let spacing: CGFloat = 7

    private struct Placement: Identifiable {
        let index: Int
        let note: Note
        let style: JottNoteCardStyle

        var id: UUID { note.id }
    }

    private var placements: [Placement] {
        notes.enumerated().map { index, note in
            Placement(index: index, note: note, style: JottNoteCardStyle.recommended(for: note))
        }
    }

    private var columnPlacements: ([Placement], [Placement]) {
        var left: [Placement] = []
        var right: [Placement] = []
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0

        for placement in placements {
            if leftHeight <= rightHeight {
                left.append(placement)
                leftHeight += placement.style.height + spacing
            } else {
                right.append(placement)
                rightHeight += placement.style.height + spacing
            }
        }

        return (left, right)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    noteColumn(columnPlacements.0)
                    noteColumn(columnPlacements.1)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .animation(JottMotion.content, value: notes.map(\.id))
            }
            .onChange(of: selectedIndex) { _, idx in
                if let idx { withAnimation(JottMotion.content) { proxy.scrollTo(idx, anchor: .center) } }
            }
        }
    }

    @ViewBuilder
    private func noteColumn(_ items: [Placement]) -> some View {
        VStack(spacing: spacing) {
            ForEach(items) { item in
                JottNoteCard(
                    note: item.note,
                    viewModel: viewModel,
                    isSelected: item.index == selectedIndex,
                    cardStyle: item.style,
                    highlightQuery: highlightQuery
                )
                .id(item.index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

}

// MARK: - Search List (full-width cards)

private struct SearchTileGrid: View {
    let items: [TimelineItem]
    @ObservedObject var viewModel: OverlayViewModel
    var selectedIndex: Int
    var highlightQuery: String? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        SearchTile(item: item, viewModel: viewModel,
                                   isSelected: index == selectedIndex,
                                   highlightQuery: highlightQuery)
                            .id(index)
                    }
                }
                .padding(10)
                .animation(JottMotion.content, value: items.map(\.id))
            }
            .onChange(of: selectedIndex) { _, idx in
                withAnimation(JottMotion.content) { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }
}

private struct SearchTile: View {
    let item: TimelineItem
    @ObservedObject var viewModel: OverlayViewModel
    var isSelected: Bool = false
    var highlightQuery: String? = nil
    @State private var hovered = false

    private var accent: Color {
        switch item {
        case .note:     return .jottNoteAccent
        case .reminder: return .jottReminderAccent
        }
    }

    private var icon: String {
        switch item {
        case .note(let n): return n.isPinned ? "pin.fill" : "doc.text"
        case .reminder:    return "bell"
        }
    }

    private var typeLabel: String {
        switch item {
        case .note:     return "note"
        case .reminder: return "reminder"
        }
    }

    private var title: String {
        switch item {
        case .note(let n):     return n.text.components(separatedBy: "\n").first ?? n.text
        case .reminder(let r): return r.text
        }
    }

    private var timeAgo: String {
        switch item {
        case .note(let n):
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
            return f.localizedString(for: n.modifiedAt, relativeTo: Date())
        case .reminder(let r):
            let cal = Calendar.current
            if r.isCompleted { return "done" }
            if r.dueDate < Date() { return "overdue" }
            if cal.isDateInToday(r.dueDate) {
                let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: r.dueDate)
            }
            let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: r.dueDate)
        }
    }

    var body: some View {
        Button {
            withAnimation(JottMotion.content) {
                switch item {
                case .note(let n):     viewModel.selectedNote = n
                case .reminder(let r): viewModel.selectedReminder = r
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    if let q = highlightQuery, !q.isEmpty {
                        HighlightedText(text: title, query: q,
                                        font: .system(size: 13, weight: .medium),
                                        baseColor: .white.opacity(0.88))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 4) {
                        Text(typeLabel)
                            .foregroundColor(.white.opacity(0.28))
                        Text("·")
                            .foregroundColor(.white.opacity(0.18))
                        Text(timeAgo)
                            .foregroundColor(.white.opacity(0.28))
                    }
                    .font(.system(size: 11))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected || hovered
                          ? Color.white.opacity(0.08)
                          : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(JottMotion.micro) { hovered = h } }
    }
}

enum JottNoteCardStyle: Equatable {
    case feature
    case regular
    case compact

    var height: CGFloat {
        switch self {
        case .feature: return 282
        case .regular: return 188
        case .compact: return 136
        }
    }

    var titleLineLimit: Int {
        switch self {
        case .feature: return 3
        case .regular: return 2
        case .compact: return 2
        }
    }

    var bodyLineLimit: Int {
        switch self {
        case .feature: return 3
        case .regular: return 2
        case .compact: return 1
        }
    }

    var previewBodyTextLineLimit: Int {
        switch self {
        case .feature: return 3
        case .regular: return 2
        case .compact: return 0
        }
    }

    var previewLinkLimit: Int {
        switch self {
        case .feature: return 3
        case .regular: return 2
        case .compact: return 0
        }
    }

    var showBody: Bool {
        switch self {
        case .compact: return false
        case .feature, .regular: return true
        }
    }

    var previewThumbnailSide: CGFloat {
        switch self {
        case .feature: return 60
        case .regular: return 54
        case .compact: return 46
        }
    }

    var padding: CGFloat {
        switch self {
        case .feature: return 18
        case .regular, .compact: return 16
        }
    }

    static func recommended(for note: Note) -> JottNoteCardStyle {
        let trimmedLines = note.text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let hasImage = note.text.contains("![")
        let hasVideo = note.text.contains("youtube.com/watch")
            || note.text.contains("youtu.be/")
            || note.text.contains("vimeo.com/")
        let characterCount = note.text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let bodyLineCount = max(trimmedLines.count - 1, 0)
        let compactImageNote = hasImage && !hasVideo && characterCount < 110 && bodyLineCount == 0
        let imageOnlyNote = hasImage && !hasVideo && characterCount < 140 && bodyLineCount <= 1

        if compactImageNote {
            return .compact
        }

        if imageOnlyNote {
            return .regular
        }

        if hasImage || hasVideo || characterCount > 220 || bodyLineCount >= 3 {
            return .feature
        }

        if characterCount < 72 && bodyLineCount == 0 {
            return .compact
        }

        if characterCount < 110 && bodyLineCount <= 1 {
            return .compact
        }

        return .regular
    }
}

struct JottCommandResults: View {
    let command: JottCommand
    @ObservedObject var viewModel: OverlayViewModel

    var items: [TimelineItem] { viewModel.commandItems(for: command) }

    private var label: String {
        switch command {
        case .reminders: return "Reminders"
        case .search:    return "Search"
        case .open:      return "Action"
        case .calendar:  return "Calendar"
        case .inbox:     return "Recent"
        case .today:     return "Today"
        }
    }
    private var sectionIcon: String {
        switch command {
        case .reminders: return "bell"
        case .search:    return "magnifyingglass"
        case .open:      return "arrow.up.right.square"
        case .calendar:  return "calendar"
        case .inbox:     return "clock"
        case .today:     return "sun.max"
        }
    }
    private var sectionAccent: Color {
        switch command {
        case .reminders: return .jottReminderAccent
        default:         return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .open = command {
                JottOpenAction(viewModel: viewModel)
            } else if case .calendar = command {
                CalendarResultsView(viewModel: viewModel)
            } else if case .today = command {
                JottTodayView(viewModel: viewModel)
            } else {
                if case .search = command {
                    // no section header for search — clean list
                } else {
                    ResultsSectionHeader(title: label, icon: sectionIcon, accent: sectionAccent,
                                         count: items.isEmpty ? nil : items.count)
                }

                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: sectionIcon)
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(.secondary.opacity(0.22))
                        Text("Nothing here yet")
                            .font(.system(size: 12.5))
                            .foregroundColor(.secondary.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale(scale: 0.92, anchor: .center).combined(with: .opacity)
                        .animation(JottMotion.content))
                } else if case .search(let q) = command {
                    SearchTileGrid(items: items, viewModel: viewModel,
                                   selectedIndex: viewModel.selectedCommandIndex,
                                   highlightQuery: q.isEmpty ? nil : q)
                        .colorScheme(.dark)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    JottRow(item: item, viewModel: viewModel,
                                            isSelected: index == viewModel.selectedCommandIndex)
                                        .id(index)
                                }
                            }
                            .padding(.bottom, 6)
                            .animation(JottMotion.content, value: items.map(\.id))
                        }
                        .onChange(of: viewModel.selectedCommandIndex) { _, idx in
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
    let key: String
    let label: String
    let shorthand: String
    let icon: String
    let insert: String
    let accent: Color

    init(
        key: String,
        label: String,
        shorthand: String,
        icon: String,
        insert: String,
        accent: Color = .secondary
    ) {
        self.key = key
        self.label = label; self.shorthand = shorthand
        self.icon = icon; self.insert = insert
        self.accent = accent
    }
}

let allCommandChips: [CommandChip] = [
    CommandChip(
        key: "search",
        label: "Search",
        shorthand: "/s",
        icon: "magnifyingglass",
        insert: "/search ",
        accent: .jottOverlaySelectorAccent
    ),
    CommandChip(
        key: "today",
        label: "Today",
        shorthand: "/t",
        icon: "sun.max",
        insert: "/today",
        accent: .orange
    ),
    CommandChip(
        key: "recent",
        label: "Recent",
        shorthand: "/r",
        icon: "clock",
        insert: "/recent",
        accent: .secondary
    ),
]

private struct CommandRailButton: View {
    let chip: CommandChip
    let isActive: Bool
    let action: () -> Void
    @State private var hovered = false
    private let badgeShape = RoundedRectangle(cornerRadius: 7, style: .continuous)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: chip.icon)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundColor(iconColor)
                Text(chip.label)
                    .font(.system(size: 11, weight: isActive ? .medium : .regular))
                Text(chip.shorthand)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(shorthandColor)
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                badgeShape
                    .fill(backgroundColor)
            )
            .overlay(
                badgeShape
                    .strokeBorder(borderColor, lineWidth: isActive ? 0.9 : 0.7)
            )
            .contentShape(badgeShape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(JottMotion.micro) { hovered = isHovering }
        }
    }

    private var foregroundColor: Color {
        if isActive {
            return .primary.opacity(0.72)
        }
        if hovered {
            return .primary.opacity(0.58)
        }
        return .secondary.opacity(0.62)
    }

    private var iconColor: Color {
        if isActive { return chip.accent.opacity(0.74) }
        if hovered { return .secondary.opacity(0.58) }
        return .secondary.opacity(0.42)
    }

    private var shorthandColor: Color {
        if isActive { return chip.accent.opacity(0.48) }
        if hovered { return .secondary.opacity(0.42) }
        return .secondary.opacity(0.28)
    }

    private var backgroundColor: Color {
        if isActive { return chip.accent.opacity(0.045) }
        if hovered { return Color.jottOverlayHoverFill.opacity(0.45) }
        return Color.clear
    }

    private var borderColor: Color {
        if isActive {
            return chip.accent.opacity(0.34)
        }
        return hovered ? Color.jottBorder.opacity(0.34) : Color.jottBorder.opacity(0.16)
    }
}

struct JottSlashCommandPicker: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var hoveredKey: String? = nil

    private var filteredChips: [CommandChip] {
        let query = String(viewModel.inputText.dropFirst()).lowercased()
        if query.isEmpty { return allCommandChips }
        return allCommandChips.filter {
            $0.label.lowercased().hasPrefix(query) ||
            String($0.insert.dropFirst()).lowercased().hasPrefix(query) ||
            String($0.shorthand.dropFirst()).hasPrefix(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(filteredChips, id: \.key) { chip in
                Button {
                    if let cmd = JottCommand(input: chip.insert) {
                        viewModel.activateCommandMode(cmd)
                        viewModel.inputText = ""
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: chip.icon)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(chip.accent.opacity(0.75))
                            .frame(width: 20)
                        Text(chip.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.82))
                        Spacer()
                        Text(chip.shorthand)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.28))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(hoveredKey == chip.key ? Color.white.opacity(0.055) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in hoveredKey = h ? chip.key : nil }
            }
        }
        .padding(.vertical, 4)
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
                    return ("calendar.badge.plus", Color("jott-reminder-accent"))
                case .reminders:
                    return ("bell.fill", Color("jott-reminder-accent"))
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
                            .accessibilityLabel("Edit date and time")
                            .accessibilityValue(formattedDate(p.date))
                            .accessibilityHint("Opens a date and time picker.")
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
                    if calMgr.isRequestingCalendarAccess {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Button(action: {
                        Task { await calMgr.requestAccess() }
                    }) {
                        Text("Connect Calendar")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color("jott-green"))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    if let msg = calMgr.authorizationErrorMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("Open Privacy Settings") {
                            calMgr.openCalendarPrivacySettings()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color("jott-green"))
                    }
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
                    .foregroundColor(Color("jott-input-text"))
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
                    withAnimation(JottMotion.micro) { imported = true }
                }) {
                    Image(systemName: imported ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(imported ? Color("jott-accent-green") : .secondary.opacity(0.5))
                        .scaleEffect(imported ? 1.08 : 1.0)
                        .animation(JottMotion.micro, value: imported)
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.96).combined(with: .opacity).animation(JottMotion.content))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            Group {
                if hovered {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.jottOverlayHoverFill)
                        .padding(.horizontal, 6)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(JottMotion.micro) { hovered = h } }
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

    private var noteResults: [Note] {
        viewModel.smartRecallResults.compactMap {
            if case .note(let n) = $0 { return n } else { return nil }
        }
    }
    private var otherResults: [(Int, TimelineItem)] {
        viewModel.smartRecallResults.enumerated().compactMap {
            if case .note = $0.element { return nil }
            return ($0.offset, $0.element)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ResultsSectionHeader(title: "SUGGESTIONS", icon: "sparkles",
                                 accent: .secondary, count: viewModel.smartRecallResults.count)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if !noteResults.isEmpty {
                        NoteGrid(notes: noteResults, viewModel: viewModel,
                                 highlightQuery: viewModel.inputText.isEmpty ? nil : viewModel.inputText)
                            .colorScheme(.dark)
                    }
                    ForEach(otherResults, id: \.0) { index, item in
                        JottRow(item: item, viewModel: viewModel,
                                isSelected: index == viewModel.selectedCommandIndex)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }
}

// MARK: - Bar Note Card (compact 2-col card for Today view)

private struct JottBarNoteCard: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel

    private var title: String {
        note.text.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
    }

    private var preview: String {
        let lines = note.text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return "" }
        return lines.dropFirst().prefix(2).joined(separator: " ")
    }

    private var relativeTime: String {
        let interval = Date().timeIntervalSince(note.modifiedAt)
        if interval < 60       { return "now" }
        if interval < 3600     { return "\(Int(interval / 60))m" }
        if interval < 86400    { return "\(Int(interval / 3600))h" }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: note.modifiedAt)
    }

    var body: some View {
        Button(action: { viewModel.selectedNote = note }) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(relativeTime)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.40))
                    Spacer()
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange.opacity(0.55))
                    }
                }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.50))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(Color.jottOverlaySurface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.jottBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
        .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.97, pressedOpacity: 0.94))
    }
}

// MARK: - Today View

struct JottTodayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    private let cal = Calendar.current

    private var todayItems: [TimelineItem] {
        viewModel.getAllReminders()
            .filter { !$0.isCompleted && cal.isDateInToday($0.dueDate) }
            .sorted { $0.dueDate < $1.dueDate }
            .map { TimelineItem.reminder($0) }
    }

    private var recentNotes: [Note] {
        Array(viewModel.getAllNotes().prefix(4))
    }

    private var pendingItems: [TimelineItem] {
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else {
                    if !todayItems.isEmpty {
                        ResultsSectionHeader(title: "TODAY", icon: "sun.max",
                                             accent: .jottReminderAccent, count: todayItems.count)
                        ForEach(todayItems, id: \.id) { item in
                            JottRow(item: item, viewModel: viewModel, isSelected: false)
                        }
                    }
                    if !recentNotes.isEmpty {
                        ResultsSectionHeader(title: "RECENT", icon: "clock.arrow.circlepath",
                                             accent: .jottNoteAccent, count: recentNotes.count)
                        ForEach(recentNotes) { note in
                            JottRow(item: .note(note), viewModel: viewModel, isSelected: false)
                        }
                    }
                    if !pendingItems.isEmpty {
                        ResultsSectionHeader(title: "PENDING", icon: "exclamationmark.circle",
                                             accent: .jottReminderAccent, count: pendingItems.count)
                        ForEach(pendingItems, id: \.id) { item in
                            JottRow(item: item, viewModel: viewModel, isSelected: false)
                        }
                    }
                }
            }
            .padding(.bottom, 6)
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
                    .foregroundColor(Color("jott-green"))
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
                        .fill(Color.jottOverlayHoverFill)
                        .padding(.horizontal, 6)
                }
            }
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(JottMotion.micro) { hovered = h } }
    }
}

// MARK: - Native Text Input (NSViewRepresentable for cursor color + clear background)

private enum JottTransferPayload {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "webp", "bmp"]

    static func hasTransferContent(_ pb: NSPasteboard) -> Bool {
        if containsImageData(pb) { return true }
        if insertionText(from: pb) != nil { return true }
        return false
    }

    static func imageToken(from pb: NSPasteboard) -> String? {
        if let image = NSImage(pasteboard: pb), let token = attachmentToken(for: image) {
            return token
        }

        let rawTypes: [NSPasteboard.PasteboardType] = [
            .png,
            NSPasteboard.PasteboardType("public.png"),
            .tiff,
            NSPasteboard.PasteboardType("public.tiff"),
            NSPasteboard.PasteboardType("com.apple.pict"),
        ]

        for type in rawTypes {
            if let data = pb.data(forType: type),
               let image = NSImage(data: data),
               let token = attachmentToken(for: image) {
                return token
            }
        }

        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls where imageExtensions.contains(url.pathExtension.lowercased()) {
                if let image = NSImage(contentsOf: url),
                   let token = attachmentToken(for: image) {
                    return token
                }
            }
        }

        return nil
    }

    static func insertionText(from pb: NSPasteboard) -> String? {
        if let htmlData = pb.data(forType: NSPasteboard.PasteboardType(rawValue: "public.html")),
           let attrStr = try? NSAttributedString(
                data: htmlData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
           ) {
            let text = richTextToPlainText(attrStr).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        guard let pastedText = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !pastedText.isEmpty else {
            return nil
        }

        if looksLikeCode(pastedText) {
            return "```\n\(pastedText.trimmingCharacters(in: .newlines))\n```"
        }

        if isVideoURL(pastedText) {
            return pastedText
        }

        return normalizePastedText(pastedText)
    }

    static func merged(_ chunk: String, into current: String) -> String {
        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else { return current }
        guard !trimmedCurrent.isEmpty else { return chunk }

        if chunk.hasPrefix("![](") {
            let needsSeparator = !(current.last?.isWhitespace ?? true)
            return current + (needsSeparator ? " " : "") + chunk
        }

        if chunk.hasPrefix("http"), isVideoURL(chunk) {
            let prefix = current.hasSuffix("\n") ? "" : "\n"
            return current + prefix + chunk
        }

        let needsSeparator = !(current.last?.isWhitespace ?? true)
        return current + (needsSeparator ? " " : "") + chunk
    }

    private static func attachmentToken(for image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }

        let filename = "img-\(UUID().uuidString.lowercased()).png"
        guard let path = MainActor.assumeIsolated({ NoteStore.shared.saveAttachment(data: png, filename: filename) }) else {
            return nil
        }
        return "![](\(path))"
    }

    static func containsImageData(_ pb: NSPasteboard) -> Bool {
        if NSImage(pasteboard: pb) != nil {
            return true
        }

        let rawTypes: [NSPasteboard.PasteboardType] = [
            .png,
            NSPasteboard.PasteboardType("public.png"),
            .tiff,
            NSPasteboard.PasteboardType("public.tiff"),
            NSPasteboard.PasteboardType("com.apple.pict"),
        ]

        if rawTypes.contains(where: { pb.data(forType: $0) != nil }) {
            return true
        }

        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            return urls.contains { imageExtensions.contains($0.pathExtension.lowercased()) }
        }

        return false
    }

    static func richTextToPlainText(_ attrStr: NSAttributedString) -> String {
        var result = ""
        attrStr.enumerateAttributes(in: NSRange(location: 0, length: attrStr.length), options: []) { attrs, range, _ in
            var chunk = (attrStr.string as NSString).substring(with: range)
            guard !chunk.isEmpty else { return }

            let font = attrs[.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isStrike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
            let linkURL = (attrs[.link] as? URL)?.absoluteString
                ?? (attrs[.link] as? String)

            if let url = linkURL {
                chunk = "[\(chunk)](\(url))"
            } else if isBold && isItalic {
                chunk = "***\(chunk)***"
            } else if isBold {
                chunk = "**\(chunk)**"
            } else if isItalic {
                chunk = "*\(chunk)*"
            }

            if isStrike && linkURL == nil {
                chunk = "~~\(chunk)~~"
            }

            result += chunk
        }

        return normalizePastedText(result)
    }

    private static func normalizePastedText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\t", with: "    ")

        normalized = normalized.replacingOccurrences(
            of: #"(?m)^\s*\*\*\s*•\s*\*{2,}"#,
            with: "**",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?m)^\s*•\s*$"#,
            with: "",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?m)^\s*(\d+)\s+(?=\S)"#,
            with: "$1. ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?m)^\s*•\s+(?=\S)"#,
            with: "- ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?m)^(\*\*[^*\n]+?\*\*)(?=[A-Z0-9\[])+"#,
            with: "$1\n",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        let cleanedLines = normalized
            .components(separatedBy: "\n")
            .map { line in
                line.replacingOccurrences(of: #"[ ]{2,}"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"(?m)\s+$"#, with: "", options: .regularExpression)
            }
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed != "**" && trimmed != "•" && trimmed != "- **"
            }

        return cleanedLines
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isVideoURL(_ text: String) -> Bool {
        guard text.hasPrefix("http"), !text.contains(" ") else { return false }
        return text.contains("youtube.com/watch")
            || text.contains("youtu.be/")
            || text.contains("vimeo.com/")
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 3 else { return false }
        guard !text.hasPrefix("```") else { return false }

        let indented = lines.filter { $0.hasPrefix("\t") || $0.hasPrefix("    ") || $0.hasPrefix("  ") }
        if Double(indented.count) / Double(lines.count) >= 0.35 { return true }

        let tokens = ["func ", "class ", "def ", "import ", "const ", "let ", "var ",
                      "return ", "public ", "private ", "struct ", "enum ", "interface ",
                      "=>", "->", "===", "!==", "#{", "$(", ": {", ": ["]
        let hits = tokens.filter { text.contains($0) }.count
        return hits >= 3
    }
}

private struct JottDropSurface: NSViewRepresentable {
    @ObservedObject var viewModel: OverlayViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> JottDropReceivingView {
        let view = JottDropReceivingView()
        view.onPasteboardDrop = { pasteboard in
            context.coordinator.handleDrop(pasteboard)
        }
        return view
    }

    func updateNSView(_ nsView: JottDropReceivingView, context: Context) {
        context.coordinator.viewModel = viewModel
        nsView.onPasteboardDrop = { pasteboard in
            context.coordinator.handleDrop(pasteboard)
        }
    }

    final class Coordinator: NSObject {
        var viewModel: OverlayViewModel

        init(viewModel: OverlayViewModel) {
            self.viewModel = viewModel
        }

        func handleDrop(_ pasteboard: NSPasteboard) -> Bool {
            if let active = JottNSTextView.activeTextView,
               active.window != nil,
               active.insertTransfer(from: pasteboard) {
                return true
            }

            if let imageToken = JottTransferPayload.imageToken(from: pasteboard) {
                viewModel.inputText = JottTransferPayload.merged(imageToken, into: viewModel.inputText)
                viewModel.persistCurrentNoteDraftImmediately()
                return true
            }

            if let text = JottTransferPayload.insertionText(from: pasteboard) {
                viewModel.inputText = JottTransferPayload.merged(text, into: viewModel.inputText)
                return true
            }

            return false
        }
    }
}

final class JottDropReceivingView: NSView {
    var onPasteboardDrop: ((NSPasteboard) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .tiff, .png, .string, .fileURL,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.html"),
            NSPasteboard.PasteboardType("com.apple.pict")
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        OverlayPanel.suppressResignKey = true
        return JottTransferPayload.hasTransferContent(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        JottTransferPayload.hasTransferContent(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        OverlayPanel.suppressResignKey = false
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        OverlayPanel.suppressResignKey = false
        return onPasteboardDrop?(sender.draggingPasteboard) ?? false
    }
}

private extension NSAttributedString.Key {
    /// Marks ghost-text ranges in JottNativeInput so extractText can skip them.
    static let jottGhost = NSAttributedString.Key("com.jott.ghostText")
}

struct JottNativeInput: NSViewRepresentable {
    @Binding var text: String
    let viewModel: OverlayViewModel
    let placeholder: String
    let isDark: Bool
    let isFocused: Bool
    let onEscape: () -> Void
    var onToggleFormatShortcut: (() -> Void)? = nil
    var onToggleVoiceShortcut: (() -> Void)? = nil
    var onClearTagFilterShortcut: (() -> Void)? = nil
    var onClearClipboardShortcut: (() -> Void)? = nil
    var onBackspaceOnEmpty: (() -> Void)? = nil
    var onHeightChange: ((CGFloat) -> Void)? = nil
    /// Current AI ghost-text suggestion, shown greyed out after the cursor.
    var suggestion: String? = nil
    var onSuggestionAccepted: (() -> Void)? = nil
    var onSuggestionDismissed: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        let tv = JottNSTextView()
        tv.registerForDraggedTypes([
            .tiff, .png,
            .string,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.html"),
            NSPasteboard.PasteboardType("com.apple.pict"),
            .fileURL
        ])
        tv.delegate = context.coordinator
        tv.isRichText = true
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
        tv.onCommandShiftF = onToggleFormatShortcut
        tv.onCommandShiftM = onToggleVoiceShortcut
        tv.onCommandShiftK = onClearTagFilterShortcut
        tv.onCommandShiftX = onClearClipboardShortcut

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

        let textColor: NSColor = isDark ? NSColor(white: 0.92, alpha: 1) : NSColor.jottInputText
        let ghostColor: NSColor = isDark ? NSColor(white: 0.72, alpha: 0.42) : NSColor(white: 0.58, alpha: 0.72)
        let placeholderColor: NSColor = isDark
            ? NSColor(white: 0.32, alpha: 1)
            : NSColor(white: 0.74, alpha: 1)
        let editorFont = NSFont.systemFont(ofSize: 17)

        // Only reset content if the markup doesn't already match (avoids wiping inline images)
        let coord = context.coordinator

        // Extract current actual (non-ghost) markup for comparison
        let currentText = tv.textStorage.map { Coordinator.extractText(from: $0) } ?? tv.string
        if currentText != text {
            if text.isEmpty {
                tv.textStorage?.setAttributedString(NSAttributedString(string: ""))
                coord.ghostStart = nil
            } else {
                tv.textStorage?.setAttributedString(
                    Coordinator.attributedString(from: text, font: editorFont, textColor: textColor)
                )
                coord.ghostStart = nil
            }
            DispatchQueue.main.async { [weak tv] in
                guard let tv else { return }
                context.coordinator.reportHeight(from: tv)
            }
        }

        // Apply or remove ghost text at the end of storage
        let desiredGhost = suggestion ?? ""
        let currentGhost = coord.currentGhostText(in: tv)
        if currentGhost != desiredGhost {
            coord.setGhostText(desiredGhost, in: tv, ghostColor: ghostColor, font: editorFont)
        }

        tv.font = editorFont
        tv.textColor = textColor
        tv.insertionPointColor = jottCursorColor
        tv.jottPlaceholder = placeholder
        tv.jottPlaceholderColor = placeholderColor
        tv.onCommandShiftF = onToggleFormatShortcut
        tv.onCommandShiftM = onToggleVoiceShortcut
        tv.onCommandShiftK = onClearTagFilterShortcut
        tv.onCommandShiftX = onClearClipboardShortcut
        let vm = viewModel
        tv.onCmdReturn = { [weak vm] in
            guard let vm else { return }
            if vm.inlineEditingId != nil { vm.saveInlineEdit(); return }
            if !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               vm.commandCreationPreview() != nil {
                vm.createCurrentItem()
                return
            }
            let smartItems = vm.smartRecallResults
            if !smartItems.isEmpty {
                let idx = max(0, min(vm.selectedCommandIndex, smartItems.count - 1))
                switch smartItems[idx] {
                case .note(let n):     vm.selectedNote = n
                case .reminder(let r): vm.selectedReminder = r
                }
                return
            }
            let cmdItems = vm.currentCommandItems()
            if !cmdItems.isEmpty {
                vm.startInlineEdit()
                if vm.inlineEditingId == nil { vm.openSelectedCommandItem() }
            }
        }
        if isFocused, tv.window?.firstResponder !== tv {
            tv.window?.makeFirstResponder(tv)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JottNativeInput
        weak var scrollView: NSScrollView?
        private var lastReportedHeight: CGFloat = 0
        private var isApplyingAttributes = false
        private static let inlineImageRegex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#)
        init(_ p: JottNativeInput) { parent = p }

        func attachIfNeeded(to scrollView: NSScrollView) {
            self.scrollView = scrollView
        }

        // MARK: - Ghost text helpers

        /// UTF-16 offset where ghost text begins in the storage. nil = no ghost.
        var ghostStart: Int? = nil

        func currentGhostText(in tv: NSTextView) -> String {
            guard let gs = ghostStart, let storage = tv.textStorage, gs < storage.length else { return "" }
            return (storage.string as NSString).substring(from: gs)
        }

        func setGhostText(_ ghost: String, in tv: NSTextView,
                          ghostColor: NSColor, font: NSFont) {
            guard let storage = tv.textStorage else { return }
            // Strip any existing ghost
            if let gs = ghostStart, gs < storage.length {
                storage.deleteCharacters(in: NSRange(location: gs, length: storage.length - gs))
            }
            ghostStart = nil
            guard !ghost.isEmpty else { return }
            let gs = storage.length
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: ghostColor,
                .jottGhost: true
            ]
            storage.append(NSAttributedString(string: ghost, attributes: attrs))
            ghostStart = gs
        }

        func stripGhostText(from tv: NSTextView) {
            guard let gs = ghostStart, let storage = tv.textStorage, gs < storage.length else {
                ghostStart = nil
                return
            }
            storage.deleteCharacters(in: NSRange(location: gs, length: storage.length - gs))
            ghostStart = nil
        }

        func acceptGhostSuggestion(in tv: NSTextView) {
            guard let gs = ghostStart, let storage = tv.textStorage, gs < storage.length else { return }
            let ghostRange = NSRange(location: gs, length: storage.length - gs)
            // Re-attribute ghost run as real text (use text color from parent)
            let isDark = parent.isDark
            let realColor: NSColor = isDark ? NSColor(white: 0.92, alpha: 1) : NSColor.jottInputText
            storage.removeAttribute(.jottGhost, range: ghostRange)
            storage.addAttribute(.foregroundColor, value: realColor, range: ghostRange)
            ghostStart = nil
            parent.text = Self.extractText(from: storage)
            parent.onSuggestionAccepted?()
            tv.setSelectedRange(NSRange(location: storage.length, length: 0))
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

        private static func inlineAttachment(for path: String, font: NSFont) -> NSAttributedString? {
            let url = NoteStore.shared.attachmentURL(for: path)
            guard let image = NSImage(contentsOf: url) else { return nil }

            let maxSide: CGFloat = 34
            let origSize = image.size
            guard origSize.width > 0, origSize.height > 0 else { return nil }
            let scale = min(maxSide / origSize.width, maxSide / origSize.height, 1.0)
            let thumbSize = NSSize(width: origSize.width * scale, height: origSize.height * scale)
            let thumb = NSImage(size: thumbSize, flipped: false) { rect in
                image.draw(in: rect)
                return true
            }

            let attachment = ImageTextAttachment()
            attachment.attachmentPath = path
            attachment.image = thumb
            attachment.bounds = NSRect(x: 0, y: -6, width: thumbSize.width, height: thumbSize.height)

            let attrStr = NSMutableAttributedString(attachment: attachment)
            attrStr.addAttribute(.font, value: font, range: NSRange(location: 0, length: attrStr.length))
            return attrStr
        }

        static func attributedString(from markup: String, font: NSFont, textColor: NSColor) -> NSAttributedString {
            guard let regex = inlineImageRegex else {
                return NSAttributedString(
                    string: markup,
                    attributes: [.font: font, .foregroundColor: textColor]
                )
            }

            let nsText = markup as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let result = NSMutableAttributedString()
            let baseAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]

            var cursor = 0
            for match in regex.matches(in: markup, range: fullRange) {
                if match.range.location > cursor {
                    let plainRange = NSRange(location: cursor, length: match.range.location - cursor)
                    result.append(NSAttributedString(string: nsText.substring(with: plainRange), attributes: baseAttrs))
                }

                if let pathRange = Range(match.range(at: 2), in: markup) {
                    let path = String(markup[pathRange])
                    if let attachment = inlineAttachment(for: path, font: font) {
                        result.append(attachment)
                    }
                }

                cursor = match.range.location + match.range.length
            }

            if cursor < nsText.length {
                result.append(NSAttributedString(string: nsText.substring(from: cursor), attributes: baseAttrs))
            }

            return result
        }

        /// Converts the textStorage content back to markup, replacing ImageTextAttachments.
        /// Skips any ranges marked with .jottGhost (AI suggestion text).
        static func extractText(from storage: NSTextStorage) -> String {
            var result = ""
            storage.enumerateAttributes(
                in: NSRange(location: 0, length: storage.length), options: []
            ) { attrs, range, _ in
                // Skip ghost text
                if attrs[.jottGhost] != nil { return }
                if let att = attrs[.attachment] as? ImageTextAttachment {
                    result += "![](\(att.attachmentPath))"
                } else {
                    // Strip U+FFFC (object replacement char) from non-image attachment runs
                    let chunk = (storage.string as NSString).substring(with: range)
                    result += chunk.unicodeScalars
                        .filter { $0 != "\u{FFFC}" }
                        .map { String($0) }.joined()
                }
            }
            return result
        }

        func textView(_ tv: NSTextView,
                      shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            JottTextFormattingRegistry.activeTextView = tv
            // Strip ghost text before any real edit so extractText stays clean
            if ghostStart != nil {
                stripGhostText(from: tv)
                DispatchQueue.main.async { self.parent.onSuggestionDismissed?() }
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingAttributes else { return }
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            JottTextFormattingRegistry.activeTextView = tv
            parent.text = Self.extractText(from: storage)
            var hasInlineAttachment = false
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
                if value != nil {
                    hasInlineAttachment = true
                    stop.pointee = true
                }
            }
            if hasInlineAttachment {
                parent.viewModel.persistCurrentNoteDraftImmediately()
            }
            reportHeight(from: tv)
        }

        // MARK: - Smart list helpers

        /// Text on the current line before the cursor.
        private func lineTextBeforeCursor(in tv: NSTextView) -> (text: String, lineStart: Int) {
            let str = tv.string as NSString
            let cursor = tv.selectedRange().location
            let lineRange = str.lineRange(for: NSRange(location: cursor, length: 0))
            let len = cursor - lineRange.location
            let text = len > 0 ? str.substring(with: NSRange(location: lineRange.location, length: len)) : ""
            return (text, lineRange.location)
        }

        /// Returns the text to append after `\n` when Enter is pressed on a list line.
        /// Returns "" (empty) when the list item is blank → escapes the list.
        /// Returns nil when the line has no list pattern.
        private func listLineContinuation(in tv: NSTextView) -> String? {
            let (line, _) = lineTextBeforeCursor(in: tv)
            // Bullet prefixes — longest first so "    • " beats "  • " beats "• "
            for prefix in ["    • ", "  • ", "• "] {
                if line.hasPrefix(prefix) {
                    let rest = String(line.dropFirst(prefix.count))
                    return rest.trimmingCharacters(in: .whitespaces).isEmpty ? "" : prefix
                }
            }
            // Numbered list  "1. ", "12. " etc.
            if let match = line.range(of: #"^(\d+)\. "#, options: .regularExpression) {
                let numStr = String(line[match]).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                let rest = String(line[match.upperBound...])
                guard !rest.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
                if let n = Int(numStr) { return "\(n + 1). " }
            }
            return nil
        }

        /// Handles Tab when cursor is at/after a list trigger. Returns true if handled.
        /// - ". " or "." → "• " (level-1 bullet)
        /// - "> " or ">" → "  • " (level-2 bullet)
        /// - Existing bullet line → indent by two spaces
        @discardableResult
        private func applyListTab(in tv: NSTextView) -> Bool {
            let (line, lineStart) = lineTextBeforeCursor(in: tv)
            // Trigger: ". " or just "." at start of line → bullet
            if line == ". " || line == "." {
                let replRange = NSRange(location: lineStart, length: (line as NSString).length)
                tv.insertText("• ", replacementRange: replRange)
                return true
            }
            // Trigger: "> " or just ">" at start of line → indented bullet
            if line == "> " || line == ">" {
                let replRange = NSRange(location: lineStart, length: (line as NSString).length)
                tv.insertText("  • ", replacementRange: replRange)
                return true
            }
            // On an existing bullet line → add one level of indentation
            for prefix in ["  • ", "• "] {
                if line.hasPrefix(prefix) {
                    tv.insertText("  ", replacementRange: NSRange(location: lineStart, length: 0))
                    return true
                }
            }
            return false
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertTab(_:)), ghostStart != nil {
                acceptGhostSuggestion(in: tv)
                return true
            }
            if sel == #selector(NSResponder.cancelOperation(_:)), ghostStart != nil {
                stripGhostText(from: tv)
                parent.onSuggestionDismissed?()
                return true
            }
            // Enter or Shift+Enter → insert a newline, continuing list if on a list line
            if sel == #selector(NSResponder.insertNewline(_:)) ||
               sel == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                if JottTextFormatting.handleContinuationNewline(in: tv) { return true }
                tv.insertText("\n", replacementRange: tv.selectedRange())
                return true
            }
            // Smart Recall navigation
            if parent.viewModel.isSmartRecalling {
                let items = parent.viewModel.smartRecallResults
                if !items.isEmpty {
                    if sel == #selector(NSResponder.moveDown(_:)) ||
                       sel == #selector(NSResponder.moveRight(_:)) {
                        let next = min(parent.viewModel.selectedCommandIndex + 1, items.count - 1)
                        parent.viewModel.selectedCommandIndex = next
                        return true
                    }
                    if sel == #selector(NSResponder.moveUp(_:)) ||
                       sel == #selector(NSResponder.moveLeft(_:)) {
                        let prev = max(parent.viewModel.selectedCommandIndex - 1, 0)
                        parent.viewModel.selectedCommandIndex = prev
                        return true
                    }
                    if sel == #selector(NSResponder.insertTab(_:)) {
                        let idx = max(0, min(parent.viewModel.selectedCommandIndex, items.count - 1))
                        let vm = parent.viewModel
                        DispatchQueue.main.async {
                            switch items[idx] {
                            case .note(let n):     vm.selectedNote = n
                            case .reminder(let r): vm.selectedReminder = r
                            }
                        }
                        return true
                    }
                }
            }
            // Tab-complete a /command suggestion before result-opening handles Tab.
            // This keeps "/not<Tab>" as "Notes mode" instead of opening the first note result.
            if sel == #selector(NSResponder.insertTab(_:)),
               !parent.viewModel.isForcedCreationMode,
               parent.viewModel.inputText.hasPrefix("/"),
               (parent.viewModel.commandMode == nil || parent.viewModel.isTypingNewCommand) {
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
            if parent.viewModel.currentCommand != nil {
                let items = parent.viewModel.currentCommandItems()
                if !items.isEmpty {
                    if sel == #selector(NSResponder.moveDown(_:)) ||
                       sel == #selector(NSResponder.moveRight(_:)) {
                        parent.viewModel.moveCommandSelection(by: 1)
                        return true
                    }
                    if sel == #selector(NSResponder.moveUp(_:)) ||
                       sel == #selector(NSResponder.moveLeft(_:)) {
                        parent.viewModel.moveCommandSelection(by: -1)
                        return true
                    }
                    if sel == #selector(NSResponder.insertTab(_:)) {
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
            // Smart list triggers: ". <Tab>" → "• ", "> <Tab>" → "  • ", Tab on bullet → indent
            if sel == #selector(NSResponder.insertTab(_:)),
               tv.selectedRange().length == 0 {
                if JottTextFormatting.handleTab(in: tv) { return true }
            }
            // If no command prefix, cycle type with Tab
            if sel == #selector(NSResponder.insertTab(_:)),
               !parent.viewModel.inputText.hasPrefix("/"),
               !parent.viewModel.inputText.isEmpty {
                let current = parent.viewModel.forcedTypeOverride ?? parent.viewModel.detectedType
                let next: DetectedType
                switch current {
                case .note:     next = .reminder
                case .reminder: next = .note
                }
                withAnimation(JottMotion.content) {
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

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let gs = ghostStart else { return }
            let sel = tv.selectedRange()
            if sel.location > gs {
                tv.setSelectedRange(NSRange(location: gs, length: 0))
            }
        }
    }
}

/// NSTextAttachment subclass that carries its markup path so we can round-trip it.
final class ImageTextAttachment: NSTextAttachment {
    var attachmentPath: String = ""
}

final class JottNSTextView: NSTextView {
    static weak var activeTextView: JottNSTextView?

    var jottPlaceholder: String = ""
    var jottPlaceholderColor: NSColor = .placeholderTextColor
    var onCommandShiftF: (() -> Void)?
    var onCommandShiftM: (() -> Void)?
    var onCommandShiftK: (() -> Void)?
    var onCommandShiftX: (() -> Void)?
    var onCmdReturn: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            Self.activeTextView = self
            JottTextFormattingRegistry.activeTextView = self
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, Self.activeTextView === self {
            Self.activeTextView = nil
        }
        if resigned, JottTextFormattingRegistry.activeTextView === self {
            JottTextFormattingRegistry.activeTextView = nil
        }
        return resigned
    }

    // MARK: - Drag-and-drop (images / screenshot files)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        OverlayPanel.suppressResignKey = true
        return JottTransferPayload.hasTransferContent(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        JottTransferPayload.hasTransferContent(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        OverlayPanel.suppressResignKey = false
        super.draggingExited(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        OverlayPanel.suppressResignKey = false
        if insertTransfer(from: sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }

    @discardableResult
    func insertTransfer(from pb: NSPasteboard) -> Bool {
        if let imageToken = JottTransferPayload.imageToken(from: pb),
           insertImageToken(imageToken) {
            return true
        }

        if let insertedText = JottTransferPayload.insertionText(from: pb) {
            if isVideoURL(insertedText) {
                let sel = selectedRange()
                let currentText = string as NSString
                let needsLeadingNewline = sel.location > 0 && currentText.substring(to: sel.location).last != "\n"
                let needsTrailingNewline: Bool = {
                    let after = sel.location + sel.length
                    return after < currentText.length && currentText.substring(from: after).first != "\n"
                }()
                let prefix = needsLeadingNewline ? "\n" : ""
                let suffix = needsTrailingNewline ? "\n" : ""
                insertText("\(prefix)\(insertedText)\(suffix)", replacementRange: sel)
                return true
            }

            insertText(insertedText, replacementRange: selectedRange())
            return true
        }

        return false
    }

    private func insertImageToken(_ token: String) -> Bool {
        guard token.hasPrefix("![]("), token.hasSuffix(")") else { return false }
        let path = String(token.dropFirst(4).dropLast())
        let url = MainActor.assumeIsolated { NoteStore.shared.attachmentURL(for: path) }
        guard let image = NSImage(contentsOf: url) else { return false }
        return insertImage(image, attachmentPath: path)
    }

    private func insertImage(_ image: NSImage, attachmentPath: String? = nil) -> Bool {
        let path: String
        if let attachmentPath {
            path = attachmentPath
        } else {
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return false }
            let filename = "img-\(UUID().uuidString.lowercased()).png"
            guard let savedPath = MainActor.assumeIsolated({ NoteStore.shared.saveAttachment(data: png, filename: filename) }) else {
                return false
            }
            path = savedPath
        }

        // Keep pasted images as small inline objects inside the text flow.
        let maxW: CGFloat = 34
        let origSize = image.size
        let scale = min(maxW / max(origSize.width, 1), maxW / max(origSize.height, 1), 1.0)
        let thumbSize = NSSize(width: origSize.width * scale, height: origSize.height * scale)
        let thumb = NSImage(size: thumbSize, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }

        let attachment = ImageTextAttachment()
        attachment.attachmentPath = path
        attachment.image = thumb
        attachment.bounds = NSRect(x: 0, y: -6, width: thumbSize.width, height: thumbSize.height)

        // Wrap with current font so line metrics are preserved
        let attrStr = NSMutableAttributedString(attachment: attachment)
        let font = self.font ?? NSFont.systemFont(ofSize: 17)
        attrStr.addAttribute(.font, value: font,
                             range: NSRange(location: 0, length: attrStr.length))

        textStorage?.insert(attrStr, at: selectedRange().location)
        // Move cursor past the attachment
        setSelectedRange(NSRange(location: selectedRange().location + 1, length: 0))
        didChangeText()
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command),
           modifiers.contains(.shift),
           !modifiers.contains(.option),
           !modifiers.contains(.control) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f":
                onCommandShiftF?()
                return true
            case "m":
                onCommandShiftM?()
                return true
            case "k":
                onCommandShiftK?()
                return true
            case "x":
                onCommandShiftX?()
                return true
            default:
                break
            }
        }

        guard modifiers.contains(.command),
              !modifiers.contains(.shift),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return super.performKeyEquivalent(with: event)
        }
        // Cmd+Return → save/create current item
        if event.keyCode == 36 {
            if let handler = onCmdReturn { handler(); return true }
            return false
        }
        switch event.charactersIgnoringModifiers {
        case "b": JottTextFormatting.apply(.bold, to: self); return true
        case "i": JottTextFormatting.apply(.italic, to: self); return true
        case "u": JottTextFormatting.apply(.underline, to: self); return true
        case "e": JottTextFormatting.apply(.inlineCode, to: self); return true   // Cmd+E → inline code
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

    // 2pt wide cursor so the purple I-beam is clearly visible on the empty field
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var r = rect; r.size.width = 2.5
        super.drawInsertionPoint(in: r, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var r = rect
        if r.size.width <= 1 { r.size.width = 2.5 }
        super.setNeedsDisplay(r, avoidAdditionalLayout: flag)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if insertTransfer(from: pb) { return }
        // Don't let NSTextView paste raw NSTextAttachment for images — it produces
        // unrenderable ￼ in the markup. Just skip if it's image-only content.
        if JottTransferPayload.containsImageData(pb) { return }
        super.paste(sender)
    }

    private func richTextToPlainText(_ attrStr: NSAttributedString) -> String {
        JottTransferPayload.richTextToPlainText(attrStr)
    }

    private func isVideoURL(_ text: String) -> Bool {
        guard text.hasPrefix("http"), !text.contains(" ") else { return false }
        return text.contains("youtube.com/watch") ||
               text.contains("youtu.be/") ||
               text.contains("vimeo.com/")
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 3 else { return false }
        guard !text.hasPrefix("```") else { return false } // already wrapped

        // Strong signal: consistent indentation (tabs or 2/4-space indent)
        let indented = lines.filter { $0.hasPrefix("\t") || $0.hasPrefix("    ") || $0.hasPrefix("  ") }
        if Double(indented.count) / Double(lines.count) >= 0.35 { return true }

        // Code token density — 3+ distinct tokens = code
        let tokens = ["func ", "class ", "def ", "import ", "const ", "let ", "var ",
                      "return ", "public ", "private ", "struct ", "enum ", "interface ",
                      "=>", "->", "===", "!==", "#{", "$(", ": {", ": ["]
        let hits = tokens.filter { text.contains($0) }.count
        return hits >= 3
    }
}

// MARK: - Format Bar

struct JottFormatBar: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        HStack(spacing: 2) {
            fmtGroup {
                MFBtn("B", style: .bold, accessibilityLabel: "Bold") { apply(.bold) }
                MFBtn("I", style: .italic, accessibilityLabel: "Italic") { apply(.italic) }
                MFBtn("U", style: .underline, accessibilityLabel: "Underline") { apply(.underline) }
                MFBtn("S", style: .strike, accessibilityLabel: "Strikethrough") { apply(.strikethrough) }
            }
            fmtSep
            fmtGroup {
                MFIcon("list.bullet", accessibilityLabel: "Bulleted list") { apply(.bulletList) }
                MFIcon("list.number", accessibilityLabel: "Numbered list") { apply(.numberedList) }
                MFIcon("checklist", accessibilityLabel: "Task list") { apply(.taskList) }
                MFIcon("text.quote", accessibilityLabel: "Block quote") { apply(.quote) }
            }
            fmtSep
            fmtGroup {
                MFIcon("chevron.left.forwardslash.chevron.right", accessibilityLabel: "Inline code") { apply(.inlineCode) }
                MFIcon("link", accessibilityLabel: "Insert link") { apply(.link) }
                MFIcon("textformat.size", accessibilityLabel: "Heading") { apply(.heading) }
                tableMenu
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
        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 14).padding(.horizontal, 4)
    }
    private enum FmtStyle { case bold, italic, underline, strike, plain }

    private func apply(_ command: JottTextFormatCommand) {
        if case .table(let rows, let columns) = command {
            viewModel.insertDraftTable(rows: rows, columns: columns)
            return
        }
        var text = viewModel.inputText
        if !JottTextFormatting.apply(command, fallbackText: &text) {
            viewModel.inputText = text
        }
    }

    private var tableMenu: some View {
        Menu {
            ForEach([2, 3, 4, 5], id: \.self) { columns in
                Button("\(columns) columns x 3 rows") { apply(.table(rows: 3, columns: columns)) }
            }
            Divider()
            Button("2 x 2") { apply(.table(rows: 2, columns: 2)) }
            Button("4 x 4") { apply(.table(rows: 4, columns: 4)) }
            Button("6 x 4") { apply(.table(rows: 4, columns: 6)) }
        } label: {
            Image(systemName: "tablecells")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.75))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Insert table")
    }

    private func MFBtn(_ lbl: String, style: FmtStyle, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                switch style {
                case .bold:   Text(lbl).bold()
                case .italic: Text(lbl).italic()
                case .underline: Text(lbl).underline()
                case .strike: Text(lbl).strikethrough()
                case .plain:  Text(lbl)
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.primary.opacity(0.75))
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.92, pressedOpacity: 0.9))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Applies \(accessibilityLabel.lowercased()) formatting.")
    }
    private func MFIcon(_ icon: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.75))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.92, pressedOpacity: 0.9))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Applies \(accessibilityLabel.lowercased()) formatting.")
    }
}

// MARK: - Tag Suggestion View

struct JottTagSuggestionView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        let query = viewModel.tagQuery ?? ""
        let candidates = viewModel.tagCandidates(for: query)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("TAGS", systemImage: "number")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.45))
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(candidates, id: \.self) { tag in
                        Button { viewModel.completeTag(tag) } label: {
                            Text("#\(tag)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.jottAccentGreen)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.jottAccentGreen.opacity(0.09))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color.jottAccentGreen.opacity(0.2), lineWidth: 0.5))
                        }
                        .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.95, pressedOpacity: 0.94))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Welcome Card

struct JottWelcomeCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to Jott")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Quick-capture for notes & reminders")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 20, height: 20)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 7) {
                tipRow("⌥⌥", "Open Jott from anywhere")
                tipRow("Type anything", "Saves as a note instantly")
                tipRow("/today", "See today's reminders")
                tipRow("⌘⇧M", "Capture with your voice")
            }

            Button(action: onDismiss) {
                Text("Got it")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(Color.jottAccentGreen)
                    .clipShape(Capsule())
            }
            .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.96, pressedOpacity: 0.94))
        }
        .padding(18)
    }

    private func tipRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.72))
        }
    }
}

// MARK: - Help Popover

struct JottHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            helpSection("OPEN / CLOSE") {
                helpRow("⌥⌥", "Toggle overlay")
                helpRow("⎋", "Dismiss & save")
            }
            helpSection("CAPTURE") {
                helpRow("↵", "New line")
                helpRow("⌘↵", "Save / open")
                helpRow("⌘⇧M", "Voice input")
                helpRow("⌘⇧F", "Format bar (Aa)")
            }
            helpSection("COMMANDS") {
                helpRow("/today  or  /t", "Today's items")
                helpRow("/search  or  /s", "Search everything")
                helpRow("/recent  or  /r", "Recent notes")
            }
            helpSection("DETAIL VIEW") {
                helpRow("⌘O", "Open in editor")
                helpRow("⌘⌫", "Delete note")
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private func helpSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.4))
                .tracking(0.5)
            content()
        }
    }

    private func helpRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 0) {
            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.72))
            Spacer()
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
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

    private static let subnoteAccent = Color(red: 0.58, green: 0.50, blue: 0.92)

    var accent: Color {
        switch item {
        case .note(let n): return n.parentId != nil ? Self.subnoteAccent : .jottNoteAccent
        case .reminder:    return .jottReminderAccent
        }
    }
    var icon: String {
        switch item {
        case .note(let n): return n.parentId != nil ? "arrow.turn.down.right" : "doc.text"
        case .reminder:    return "bell"
        }
    }
    var title: String {
        switch item {
        case .note(let n):     return n.text.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? n.text
        case .reminder(let r): return r.text
        }
    }
    private func parentTitle(for note: Note) -> String? {
        guard let pid = note.parentId,
              let parent = NoteStore.shared.note(for: pid) else { return nil }
        return parent.text.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }
    var meta: String? {
        switch item {
        case .note(let n):
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
            return f.localizedString(for: n.modifiedAt, relativeTo: Date())
        case .reminder(let r):
            let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f.string(from: r.dueDate)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon container
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 18)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(accent.opacity(0.18))
                    )
                if case .note(let n) = item, n.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.orange)
                        .offset(x: 6, y: -5)
                }
            }

            // Type-specific content
            switch item {
            case .note(let n):
                if viewModel.inlineEditingId == n.id {
                    TextField("", text: $viewModel.inlineEditText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))
                        .focused($isInlineFocused)
                        .onSubmit { viewModel.saveInlineEdit() }
                        .onExitCommand { viewModel.cancelInlineEdit() }
                        .onAppear { isInlineFocused = true }
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        if let parent = parentTitle(for: n) {
                            HStack(spacing: 3) {
                                Text(parent)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Self.subnoteAccent.opacity(0.65))
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundColor(Self.subnoteAccent.opacity(0.4))
                            }
                        }
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if n.parentId == nil {
                            let preview = n.text.components(separatedBy: "\n")
                                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                                .dropFirst().first
                            if let preview, !preview.isEmpty {
                                Text(preview)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary.opacity(0.65))
                                    .lineLimit(1)
                            }
                        }
                    }
                }

            case .reminder:
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

            }

            Spacer(minLength: 0)

            // Contextual right badge — fades on hover to make room for action buttons
            if !hovered {
                switch item {
                case .note(let n):
                    if viewModel.inlineEditingId != n.id {
                        Text(shortRelativeTime(n.modifiedAt))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                            .transition(.opacity)
                    }
                case .reminder(let r):
                    reminderBadge(r)
                        .transition(.opacity)
                }
            }

            // Complete button — reminders only, hover
            if hovered, case .reminder(let r) = item {
                Button(action: {
                    withAnimation(JottMotion.content) {
                        viewModel.markReminderDone(r.id)
                    }
                }) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color("jott-green"))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.96).combined(with: .opacity).animation(JottMotion.content))
            }

            // Open in editor button — notes only, hover
            if hovered, case .note(let n) = item {
                Button(action: { viewModel.openNoteInEditor(n); viewModel.dismiss() }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.96).combined(with: .opacity).animation(JottMotion.content))
            }

            // Copy button — notes only, hover
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
                .transition(.scale(scale: 0.96).combined(with: .opacity).animation(JottMotion.content))
            }

            // Delete button — all types, hover
            if hovered {
                Button(action: {
                    withAnimation(JottMotion.content) {
                        switch item {
                        case .note(let n):     viewModel.deleteNote(n.id)
                        case .reminder(let r): viewModel.deleteReminder(r.id)
                        }
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.red.opacity(0.45))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.96).combined(with: .opacity).animation(JottMotion.content))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(hovered ? 0.45 : 0.18))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
                .padding(.horizontal, 6)
        )
        .opacity(isDoneReminder ? 0.35 : 1.0)
        .animation(JottMotion.content, value: isDoneReminder)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(JottMotion.micro) { hovered = h } }
        .animation(JottMotion.micro, value: hovered)
        .animation(JottMotion.content, value: isSelected)
        .onTapGesture {
            withAnimation(JottMotion.content) {
                switch item {
                case .note(let n):     viewModel.selectedNote = n
                case .reminder(let r): viewModel.selectedReminder = r
                }
            }
        }
    }

    private func reminderBadgeInfo(_ r: Reminder) -> (label: String, color: Color, isOverdue: Bool) {
        let cal = Calendar.current
        let isOverdue = r.dueDate < Date() && !r.isCompleted
        if isOverdue { return ("Overdue", .red, true) }
        if cal.isDateInToday(r.dueDate) {
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            return (f.string(from: r.dueDate), .orange, false)
        }
        if cal.isDateInTomorrow(r.dueDate) { return ("Tomorrow", .blue, false) }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return (f.string(from: r.dueDate), .secondary, false)
    }

    @ViewBuilder
    private func reminderBadge(_ r: Reminder) -> some View {
        let info = reminderBadgeInfo(r)
        HStack(spacing: 3) {
            Image(systemName: info.isOverdue ? "exclamationmark" : "clock")
                .font(.system(size: 8, weight: info.isOverdue ? .bold : .regular))
            Text(info.label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(info.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(info.color.opacity(info.isOverdue ? 0.12 : 0.08)))
    }

    private func shortRelativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var rowBackground: Color {
        if isSelected || hovered {
            return Color.jottOverlayHoverFill
        }
        return .clear
    }
}

// MARK: - Note Card (grid)

struct JottNoteCard: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel
    var isSelected: Bool = false
    var cardStyle: JottNoteCardStyle = .regular
    var onActivate: (() -> Void)? = nil
    var highlightQuery: String? = nil
    @State private var hovered = false
    @State private var thumbnail: NSImage?

    private var title: String {
        let lines = note.text.components(separatedBy: "\n")
        // Skip image-only lines for the card title, but allow text lines that also contain an inline image token.
        return lines.first { !isImageOnlyLine($0) && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? (lines.contains(where: { containsImageMarkup($0) }) ? "(Image)" : (lines.first ?? note.text))
    }
    private var bodyLines: [String] {
        let lines = note.text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // Skip the first non-image-only line (used as title) and pure image lines.
        var found = false
        return Array(lines.filter { line in
            if !found && !isImageOnlyLine(line) { found = true; return false }
            return !isImageOnlyLine(line)
        }.prefix(cardStyle.bodyLineLimit))
    }

    private var displayTitle: String {
        normalizedPreviewText(from: title)
    }

    private var previewBodyText: String? {
        let value = normalizedPreviewText(from: bodyLines.joined(separator: " "))
        return value.isEmpty ? nil : value
    }

    private var previewLinkTitles: [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for line in note.text.components(separatedBy: "\n") {
            for title in linkTitles(from: line) where !seen.contains(title) {
                seen.insert(title)
                ordered.append(title)
            }
        }

        return Array(ordered.prefix(cardStyle.previewLinkLimit))
    }

    private var effectiveTitleLineLimit: Int {
        let hasSupplementalPreview = previewBodyText != nil || !previewLinkTitles.isEmpty
        if hasSupplementalPreview {
            return cardStyle.titleLineLimit
        }
        switch cardStyle {
        case .feature: return 5
        case .regular: return 4
        case .compact: return 3
        }
    }

    private func containsImageMarkup(_ line: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#) else {
            return false
        }
        return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private func isImageOnlyLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: #"^!\[[^\]]*\]\(([^)]+)\)$"#) else {
            return false
        }
        return regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }
    /// Returns the path of the first attached image in the note, if any.
    private var firstImagePath: String? {
        let imagePattern = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#)
        let source = note.text
        if let regex = imagePattern,
           let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let pathRange = Range(match.range(at: 1), in: source) {
            return String(source[pathRange])
        }
        return nil
    }
    private var hasVideoLink: Bool {
        note.text.contains("youtube.com/watch") ||
        note.text.contains("youtu.be/") ||
        note.text.contains("vimeo.com/")
    }

    private var isDarkMode: Bool {
        true
    }

    private var cardFillColor: Color {
        if isDarkMode {
            return isSelected
                ? Color(red: 0.18, green: 0.18, blue: 0.20)
                : Color(red: 0.15, green: 0.15, blue: 0.17)
        }
        return isSelected
            ? Color.white
            : Color(red: 0.985, green: 0.985, blue: 0.99)
    }

    private var cardBorderColor: Color {
        if isSelected {
            return Color.primary.opacity(isDarkMode ? 0.28 : 0.12)
        }
        return isDarkMode
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }

    @ViewBuilder
    private var previewTextContent: some View {
        let titleFont: Font = cardStyle == .feature ? JottTypography.noteTitle(16, weight: .medium) : JottTypography.noteTitle()
        Group {
            if let q = highlightQuery, !q.isEmpty {
                HighlightedText(text: displayTitle, query: q, font: titleFont,
                                baseColor: .primary.opacity(0.88))
            } else {
                Text(displayTitle).font(titleFont).foregroundColor(.primary.opacity(0.88))
            }
        }
        .lineLimit(effectiveTitleLineLimit)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

        if cardStyle.showBody && (previewBodyText != nil || !previewLinkTitles.isEmpty) {
            Spacer().frame(height: 8)
            VStack(alignment: .leading, spacing: 6) {
                if let previewBodyText {
                    let bodyFont = JottTypography.noteBody()
                    let bodyBase = Color.secondary.opacity(isDarkMode ? 0.62 : 0.56)
                    Group {
                        if let q = highlightQuery, !q.isEmpty {
                            HighlightedText(text: previewBodyText, query: q,
                                            font: bodyFont, baseColor: bodyBase)
                        } else {
                            Text(previewBodyText).font(bodyFont).foregroundColor(bodyBase)
                        }
                    }
                    .lineLimit(cardStyle.previewBodyTextLineLimit)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !previewLinkTitles.isEmpty {
                    JottNotePreviewLinkRow(
                        titles: previewLinkTitles,
                        isDarkMode: isDarkMode,
                        style: cardStyle
                    )
                }
            }
        }
    }

    private func normalizedPreviewText(from raw: String) -> String {
        let linkStripped = stripWikiMarkup(from: raw)
        let imageStripped = stripImageMarkup(from: linkStripped)
        return imageStripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripWikiMarkup(from raw: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else {
            return raw
        }

        let range = NSRange(raw.startIndex..., in: raw)
        return regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "$1")
    }

    private func stripImageMarkup(from raw: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#) else {
            return raw
        }

        let range = NSRange(raw.startIndex..., in: raw)
        return regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
    }

    private func linkTitles(from raw: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else {
            return []
        }

        let nsRaw = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: nsRaw.length))
        return matches.compactMap { match in
            guard let titleRange = Range(match.range(at: 1), in: raw) else { return nil }
            let title = String(raw[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if note.isPinned {
                HStack {
                    Circle()
                        .fill(Color.jottOverlayPeachAccent.opacity(isDarkMode ? 0.82 : 0.68))
                        .frame(width: 5, height: 5)
                    Spacer(minLength: 0)
                }
                Spacer().frame(height: 10)
            } else {
                Spacer().frame(height: 4)
            }

            Spacer().frame(height: 8)

            if let img = thumbnail {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        previewTextContent
                    }

                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cardStyle.previewThumbnailSide, height: cardStyle.previewThumbnailSide)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.jottBorder.opacity(isDarkMode ? 0.70 : 0.55), lineWidth: 1)
                        )
                }
            } else {
                previewTextContent
            }

            if firstImagePath == nil && hasVideoLink {
                Spacer().frame(height: 10)

                Text("Video")
                    .font(JottTypography.ui(10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.42))
            }

            Spacer(minLength: 0)
        }
        .padding(cardStyle.padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: cardStyle.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorderColor, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if hovered {
                HStack(spacing: 6) {
                    JottNoteCardActionButton(
                        icon: "pencil",
                        foreground: .secondary.opacity(0.92),
                        background: isDarkMode
                            ? Color.white.opacity(0.12)
                            : Color.black.opacity(0.08)
                    ) {
                        withAnimation(JottMotion.content) {
                            viewModel.selectedNote = note
                            viewModel.startEditingNote(note)
                        }
                    }

                    JottNoteCardActionButton(
                        icon: "trash",
                        foreground: .red.opacity(0.92),
                        background: isDarkMode
                            ? Color.red.opacity(0.20)
                            : Color.red.opacity(0.14)
                    ) {
                        withAnimation(JottMotion.content) {
                            viewModel.deleteNote(note.id)
                        }
                    }
                }
                .padding(10)
                .transition(.scale(scale: 0.96).combined(with: .opacity).animation(JottMotion.micro))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            withAnimation(JottMotion.content) {
                if let onActivate {
                    onActivate()
                } else {
                    viewModel.selectedNote = note
                }
            }
        }
        .scaleEffect(hovered ? 0.992 : 1.0)
        .animation(JottMotion.micro, value: hovered)
        .animation(JottMotion.content, value: isSelected)
        .onHover { h in withAnimation(JottMotion.micro) { hovered = h } }
        .task(id: note.id) {
            guard let path = firstImagePath else { return }
            let url = NoteStore.shared.attachmentURL(for: path)
            if let img = NSImage(contentsOf: url) {
                thumbnail = img
            }
        }
    }
}

private struct JottNoteCardActionButton: View {
    let icon: String
    let foreground: Color
    let background: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(foreground)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovered ? background.opacity(1.18) : background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(hovered ? 0.16 : 0.08), lineWidth: 1)
                )
                .scaleEffect(hovered ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(JottMotion.micro, value: hovered)
        .onHover { isHovering in
            withAnimation(JottMotion.micro) {
                hovered = isHovering
            }
        }
    }
}

private struct JottNotePreviewLinkRow: View {
    let titles: [String]
    let isDarkMode: Bool
    let style: JottNoteCardStyle

    private var chipTextColor: Color {
        isDarkMode
            ? Color(red: 0.86, green: 0.80, blue: 1.0)
            : Color(red: 0.44, green: 0.29, blue: 0.76)
    }

    private var chipFill: Color {
        isDarkMode
            ? Color(red: 0.29, green: 0.23, blue: 0.43).opacity(0.78)
            : Color(red: 0.92, green: 0.88, blue: 0.98)
    }

    private var chipBorder: Color {
        isDarkMode
            ? Color(red: 0.60, green: 0.50, blue: 0.86).opacity(0.55)
            : Color(red: 0.68, green: 0.58, blue: 0.90).opacity(0.65)
    }

    private var chipMaxWidth: CGFloat {
        switch style {
        case .feature: return 240
        case .regular: return 180
        case .compact: return 160
        }
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(titles, id: \.self) { title in
                Text(title)
                    .font(JottTypography.ui(11, weight: .semibold))
                    .foregroundColor(chipTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: chipMaxWidth, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(chipFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(chipBorder, lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JottInlinePreviewText: View {
    let text: String
    let isDarkMode: Bool
    let style: JottNoteCardStyle
    let isTitle: Bool

    private enum Piece: Identifiable {
        case text(UUID, String)
        case link(UUID, String)

        var id: UUID {
            switch self {
            case .text(let id, _), .link(let id, _): return id
            }
        }
    }

    private var pieces: [Piece] {
        parsePieces(from: text)
    }

    private var textFont: Font {
        if isTitle {
            return style == .feature ? JottTypography.noteTitle(16, weight: .medium) : JottTypography.noteTitle()
        }
        return JottTypography.noteBody()
    }

    private var textColor: Color {
        isTitle
            ? .primary.opacity(0.88)
            : .secondary.opacity(isDarkMode ? 0.62 : 0.56)
    }

    private var chipTextColor: Color {
        isDarkMode
            ? Color(red: 0.86, green: 0.80, blue: 1.0)
            : Color(red: 0.44, green: 0.29, blue: 0.76)
    }

    private var chipFill: Color {
        isDarkMode
            ? Color(red: 0.29, green: 0.23, blue: 0.43).opacity(0.78)
            : Color(red: 0.92, green: 0.88, blue: 0.98)
    }

    private var chipBorder: Color {
        isDarkMode
            ? Color(red: 0.60, green: 0.50, blue: 0.86).opacity(0.55)
            : Color(red: 0.68, green: 0.58, blue: 0.90).opacity(0.65)
    }

    private var maxHeight: CGFloat {
        if isTitle {
            switch style {
            case .feature: return 82
            case .regular, .compact: return 62
            }
        }
        switch style {
        case .feature: return 60
        case .regular: return 46
        case .compact: return 40
        }
    }

    private var flowSpacing: CGFloat {
        isTitle ? 3 : 2
    }

    private var chipCornerRadius: CGFloat {
        isTitle ? 8 : 7
    }

    private var chipHorizontalPadding: CGFloat {
        isTitle ? 8 : 5
    }

    private var chipVerticalPadding: CGFloat {
        isTitle ? 4 : 2
    }

    var body: some View {
        FlowLayout(spacing: flowSpacing) {
            ForEach(pieces) { piece in
                switch piece {
                case .text(_, let value):
                    Text(value)
                        .font(textFont)
                        .foregroundColor(textColor)

                case .link(_, let value):
                    Text(value)
                        .font(isTitle ? JottTypography.noteBody(13, weight: .semibold) : JottTypography.ui(11, weight: .semibold))
                        .foregroundColor(chipTextColor)
                        .lineLimit(1)
                        .padding(.horizontal, chipHorizontalPadding)
                        .padding(.vertical, chipVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: chipCornerRadius, style: .continuous)
                                .fill(chipFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: chipCornerRadius, style: .continuous)
                                .strokeBorder(chipBorder, lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 1)
        .padding(.vertical, 2)
        .frame(maxHeight: maxHeight, alignment: .topLeading)
        .clipped()
    }

    private func parsePieces(from raw: String) -> [Piece] {
        guard !raw.isEmpty else { return [] }

        let nsRaw = raw as NSString
        let fullRange = NSRange(location: 0, length: nsRaw.length)
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else {
            return textPieces(from: raw)
        }

        var pieces: [Piece] = []
        var cursor = 0

        for match in regex.matches(in: raw, range: fullRange) {
            if match.range.location > cursor {
                let plainRange = NSRange(location: cursor, length: match.range.location - cursor)
                pieces.append(contentsOf: textPieces(from: nsRaw.substring(with: plainRange)))
            }

            if let titleRange = Range(match.range(at: 1), in: raw) {
                let title = String(raw[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    pieces.append(.link(UUID(), title))
                }
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsRaw.length {
            pieces.append(contentsOf: textPieces(from: nsRaw.substring(from: cursor)))
        }

        return pieces
    }

    private func textPieces(from raw: String) -> [Piece] {
        guard !raw.isEmpty else { return [] }
        guard let regex = try? NSRegularExpression(pattern: #"\S+"#) else {
            return [.text(UUID(), raw)]
        }

        let nsRaw = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: nsRaw.length))
        if matches.isEmpty { return [.text(UUID(), raw)] }

        return matches.map { match in
            .text(UUID(), nsRaw.substring(with: match.range))
        }
    }
}

// MARK: - Compat stubs

struct FormatButton: View {
    let label: String; let isActive: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .bold))
                .foregroundColor(isActive ? .primary.opacity(0.82) : .secondary)
                .frame(width: 22, height: 22)
                .background(isActive ? Color.jottOverlaySelectorAccent.opacity(0.32) : Color.clear)
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

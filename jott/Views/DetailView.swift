import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Rich content block parsing

private enum RichBlock {
    case text(String)
    case image(path: String, alt: String)
    case video(url: String, id: String, isYouTube: Bool)
    case file(path: String, name: String)   // local attachment: [name](attachments/…)
    case link(url: String, text: String)    // web link: [text](https://…) or bare https://…
}

private func parseRichBlocks(_ text: String) -> [RichBlock] {
    let lines = text.components(separatedBy: "\n")
    var blocks: [RichBlock] = []
    var textBuffer: [String] = []

    let imagePattern = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#)
    let linkPattern  = try? NSRegularExpression(pattern: #"^\[([^\]]*)\]\(([^)]+)\)$"#)

    func flushText() {
        guard !textBuffer.isEmpty else { return }
        blocks.append(.text(textBuffer.joined(separator: "\n")))
        textBuffer = []
    }

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Image markdown on its own line: ![alt](path)
        if let regex = imagePattern,
           let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let altRange  = Range(m.range(at: 1), in: line),
           let pathRange = Range(m.range(at: 2), in: line) {
            flushText()
            blocks.append(.image(path: String(line[pathRange]), alt: String(line[altRange])))
            continue
        }

        // Standalone link/file: [name](url-or-path)
        if let regex = linkPattern,
           let m = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let textRange = Range(m.range(at: 1), in: trimmed),
           let urlRange  = Range(m.range(at: 2), in: trimmed) {
            let linkText = String(trimmed[textRange])
            let linkURL  = String(trimmed[urlRange])
            flushText()
            if linkURL.hasPrefix("http://") || linkURL.hasPrefix("https://") {
                blocks.append(.link(url: linkURL, text: linkText))
            } else {
                blocks.append(.file(path: linkURL, name: linkText))
            }
            continue
        }

        // YouTube URL on its own line
        if let ytID = extractYouTubeID(trimmed) {
            flushText()
            blocks.append(.video(url: trimmed, id: ytID, isYouTube: true))
            continue
        }

        // Vimeo URL on its own line
        if let vimeoID = extractVimeoID(trimmed) {
            flushText()
            blocks.append(.video(url: trimmed, id: vimeoID, isYouTube: false))
            continue
        }

        // Bare http/https URL on its own line
        if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")),
           URL(string: trimmed) != nil {
            flushText()
            blocks.append(.link(url: trimmed, text: trimmed))
            continue
        }

        textBuffer.append(line)
    }
    flushText()
    return blocks
}

private func extractYouTubeID(_ s: String) -> String? {
    guard s.hasPrefix("http"), s.contains("youtu") else { return nil }
    guard let url = URL(string: s) else { return nil }
    if url.host == "youtu.be" {
        let id = url.lastPathComponent
        return id.isEmpty ? nil : id
    }
    if let comps = URLComponents(string: s),
       let v = comps.queryItems?.first(where: { $0.name == "v" })?.value,
       !v.isEmpty {
        return v
    }
    return nil
}

private func extractVimeoID(_ s: String) -> String? {
    guard s.hasPrefix("http"), s.contains("vimeo.com") else { return nil }
    guard let url = URL(string: s) else { return nil }
    let id = url.lastPathComponent
    return (!id.isEmpty && id.allSatisfy(\.isNumber)) ? id : nil
}

// MARK: - Attachment image

struct AttachmentImageView: View {
    let path: String
    let alt: String
    let providedImage: NSImage?
    @State private var nsImage: NSImage?
    @State private var hovered = false
    @State private var copied = false

    init(path: String, alt: String, initialImage: NSImage? = nil) {
        self.path = path
        self.alt = alt
        self.providedImage = initialImage
        _nsImage = State(initialValue: nil)
    }

    private func copyToClipboard(_ img: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        withAnimation(JottMotion.content) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(JottMotion.content) { copied = false }
        }
    }

    private func loadImage() {
        guard nsImage == nil && providedImage == nil else { return }
        let url = NoteStore.shared.attachmentURL(for: path)
        Task.detached(priority: .userInitiated) {
            let img = NSImage(contentsOf: url)
            await MainActor.run { nsImage = img }
        }
    }

    private var displayImage: NSImage? {
        providedImage ?? nsImage
    }

    var body: some View {
        Group {
            if let img = displayImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.jottBorder.opacity(0.35), lineWidth: 0.5)
                    )
                    .overlay(alignment: .topTrailing) {
                        if hovered {
                            Button(action: { copyToClipboard(img) }) {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)).animation(JottMotion.content))
                        }
                    }
                    .animation(JottMotion.micro, value: hovered)
                    .onHover { isHovering in
                        withAnimation(JottMotion.micro) { hovered = isHovering }
                    }
                    .onTapGesture { copyToClipboard(img) }
                    .contextMenu {
                        Button("Copy Image") { copyToClipboard(img) }
                    }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))
                    .frame(height: 80)
                    .overlay(
                        Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.45))
                    )
            }
        }
        .onAppear(perform: loadImage)
    }
}

// MARK: - Video embed card

struct VideoEmbedCard: View {
    let url: String
    let videoID: String
    let isYouTube: Bool
    @State private var thumbnail: NSImage?
    @State private var hovered = false

    var body: some View {
        Button(action: { URL(string: url).map { NSWorkspace.shared.open($0) } }) {
            ZStack {
                // Background / thumbnail
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 160)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 160)
                }

                // Subtle dark overlay so the play button is readable
                Color.black.opacity(0.18)

                // Play button
                Circle()
                    .fill(Color.black.opacity(hovered ? 0.72 : 0.55))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .offset(x: 2)
                    )
                    .scaleEffect(hovered ? 1.06 : 1.0)
                    .animation(JottMotion.micro, value: hovered)

                // Provider badge bottom-left
                VStack {
                    Spacer()
                    HStack {
                        Text(isYouTube ? "YouTube" : "Vimeo")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(isYouTube ? Color.red.opacity(0.82) : Color(red: 0.07, green: 0.38, blue: 0.69).opacity(0.9))
                            .clipShape(Capsule())
                            .padding(10)
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.jottBorder.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(JottMotion.micro) { hovered = isHovering }
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard isYouTube,
              let thumbURL = URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
        else { return }
        Task {
            if let data = try? Data(contentsOf: thumbURL),
               let img = NSImage(data: data) {
                await MainActor.run { thumbnail = img }
            }
        }
    }
}

// MARK: - Note rich content renderer

struct NoteRichContentView: View {
    let text: String
    let isDarkMode: Bool
    let onTap: () -> Void

    private var blocks: [RichBlock] { parseRichBlocks(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let t):
                    InlineLinkedTextBlock(text: t, isDarkMode: isDarkMode)
                        .onTapGesture(count: 2) { onTap() }

                case .image(let path, let alt):
                    AttachmentImageView(path: path, alt: alt)

                case .video(let url, let id, let isYT):
                    VideoEmbedCard(url: url, videoID: id, isYouTube: isYT)

                case .file(let path, let name):
                    FileAttachmentChip(path: path, name: name, isDark: isDarkMode)

                case .link(let url, let text):
                    LinkChip(url: url, text: text)
                }
            }
        }
    }
}

private struct InlineAttachmentImageToken: View {
    let path: String
    let alt: String
    let isExpanded: Bool
    let onTap: () -> Void
    @State private var nsImage: NSImage?

    private func loadImage() {
        guard nsImage == nil else { return }
        let url = NoteStore.shared.attachmentURL(for: path)
        Task.detached(priority: .userInitiated) {
            let img = NSImage(contentsOf: url)
            await MainActor.run { nsImage = img }
        }
    }

    private var tokenBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(srgbRed: 0.19, green: 0.20, blue: 0.24, alpha: 0.92)
            default:
                return NSColor.white.withAlphaComponent(0.96)
            }
        })
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if let nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.65))
                        )
                }
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tokenBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.jottBorder.opacity(isExpanded ? 0.9 : 0.55), lineWidth: isExpanded ? 1.5 : 1)
            )
            .rotationEffect(.degrees(-3.2))
            .padding(.horizontal, 3)
        }
        .buttonStyle(.plain)
        .onAppear(perform: loadImage)
    }
}

private struct ExpandedImagePreview: View {
    let path: String
    let alt: String
    let onTap: () -> Void
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let img = nsImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture { onTap() }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))
                    .frame(height: 80)
                    .overlay(
                        Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.45))
                    )
            }
        }
        .onAppear {
            let url = NoteStore.shared.attachmentURL(for: path)
            Task.detached(priority: .userInitiated) {
                let img = NSImage(contentsOf: url)
                await MainActor.run { nsImage = img }
            }
        }
    }
}

private struct InlineLinkedTextBlock: View {
    let text: String
    let isDarkMode: Bool

    @State private var expandedImagePath: String? = nil

    private enum Piece: Identifiable {
        case text(UUID, String)
        case image(UUID, String, String)

        var id: UUID {
            switch self {
            case .text(let id, _), .image(let id, _, _): return id
            }
        }
    }

    private var paragraphs: [[Piece]] {
        text.components(separatedBy: "\n").map(parseParagraph)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, pieces in
                if pieces.isEmpty {
                    Color.clear
                        .frame(height: 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        FlowLayout(spacing: 0, verticalAlignment: .center) {
                            ForEach(pieces) { piece in
                                switch piece {
                                case .text(_, let value):
                                    let trimmedValue = value.trimmingCharacters(in: .whitespaces)
                                    if (trimmedValue.hasPrefix("http://") || trimmedValue.hasPrefix("https://")),
                                       let url = URL(string: trimmedValue) {
                                        Button(action: { NSWorkspace.shared.open(url) }) {
                                            Text(value)
                                                .font(.system(size: 15))
                                                .foregroundColor(.accentColor)
                                                .underline(color: .accentColor.opacity(0.5))
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Text(value)
                                            .font(.system(size: 15))
                                            .foregroundColor(isDarkMode ? .white : Color("jott-input-text"))
                                    }

                                case .image(_, let path, let alt):
                                    InlineAttachmentImageToken(
                                        path: path,
                                        alt: alt,
                                        isExpanded: expandedImagePath == path,
                                        onTap: {
                                            withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
                                                expandedImagePath = expandedImagePath == path ? nil : path
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Expanded image preview — below the paragraph, no text reflow
                        ForEach(pieces) { piece in
                            if case .image(_, let p, let a) = piece, expandedImagePath == p {
                                ExpandedImagePreview(path: p, alt: a) {
                                    withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
                                        expandedImagePath = nil
                                    }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                            }
                        }
                    }
                }
            }
        }
    }

    private func parseParagraph(_ paragraph: String) -> [Piece] {
        guard !paragraph.isEmpty else { return [] }

        let nsParagraph = paragraph as NSString
        let fullRange = NSRange(location: 0, length: nsParagraph.length)
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) else {
            return textPieces(from: paragraph)
        }

        var pieces: [Piece] = []
        var cursor = 0

        for match in regex.matches(in: paragraph, range: fullRange) {
            if match.range.location > cursor {
                let plainRange = NSRange(location: cursor, length: match.range.location - cursor)
                let plainText = nsParagraph.substring(with: plainRange)
                pieces.append(contentsOf: textPieces(from: plainText))
            }

            if match.range(at: 2).location != NSNotFound,
               let pathRange = Range(match.range(at: 2), in: paragraph) {
                let path = String(paragraph[pathRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let alt: String
                if let altRange = Range(match.range(at: 1), in: paragraph) {
                    alt = String(paragraph[altRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    alt = ""
                }
                if !path.isEmpty {
                    pieces.append(.image(UUID(), path, alt))
                }
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsParagraph.length {
            let trailing = nsParagraph.substring(from: cursor)
            pieces.append(contentsOf: textPieces(from: trailing))
        }

        return pieces
    }

    private func textPieces(from chunk: String) -> [Piece] {
        guard !chunk.isEmpty else { return [] }
        guard let regex = try? NSRegularExpression(pattern: #"\S+\s*"#) else {
            return [.text(UUID(), chunk)]
        }

        let nsChunk = chunk as NSString
        let matches = regex.matches(in: chunk, range: NSRange(location: 0, length: nsChunk.length))
        if matches.isEmpty { return [.text(UUID(), chunk)] }

        return matches.map { match in
            .text(UUID(), nsChunk.substring(with: match.range))
        }
    }
}

private extension AnyTransition {
    static var detailContentSwap: AnyTransition {
        .asymmetric(
            insertion: .offset(x: 4, y: 0).combined(with: .opacity)
                .animation(JottMotion.content),
            removal: .opacity.animation(JottMotion.content)
        )
    }
}

// MARK: - Detail View

struct DetailView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var showFormat = false
    @State private var autoSaveTimer: Timer?
    @State private var showSubnoteInput = false

    private var detailContentID: String {
        if let note = viewModel.selectedNote { return "note-\(note.id.uuidString)" }
        if let reminder = viewModel.selectedReminder { return "reminder-\(reminder.id.uuidString)" }
        return "empty"
    }

    var body: some View {
        ZStack {
            JottAmbientBackdrop(isDark: viewModel.isDarkMode)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.jottOverlaySurface.opacity(viewModel.isDarkMode ? 0.86 : 0.74),
                    Color.jottDetailBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            VStack(spacing: 0) {
                DetailHeader(viewModel: viewModel, showSubnoteInput: $showSubnoteInput)

                Divider().opacity(0.1)

                if viewModel.isEditingNote {
                    NoteEditToolbarStrip(viewModel: viewModel, showFormat: $showFormat)
                        .transition(.asymmetric(
                            insertion: .offset(y: -3).combined(with: .opacity).animation(JottMotion.content),
                            removal: .opacity.animation(JottMotion.content)
                        ))
                    Divider().opacity(0.06)
                }

                ScrollView(showsIndicators: false) {
                    Group {
                        if let note = viewModel.selectedNote {
                            NoteDetailContent(note: note, viewModel: viewModel)
                                .id(note.id)
                        } else if let reminder = viewModel.selectedReminder {
                            ReminderDetailContent(reminder: reminder, viewModel: viewModel)
                        } else if let meeting = viewModel.selectedMeeting {
                            MeetingDetailContent(meeting: meeting, viewModel: viewModel)
                        }
                    }
                    .id(detailContentID)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .transition(.detailContentSwap)
                }

                if let note = viewModel.selectedNote, !viewModel.isEditingNote,
                   note.parentId == nil, showSubnoteInput {
                    Divider().opacity(0.07)
                    AddSubnoteRow(
                        parentNote: note,
                        viewModel: viewModel,
                        isDark: viewModel.isDarkMode,
                        onDismiss: {
                            withAnimation(JottMotion.content) { showSubnoteInput = false }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .transition(.asymmetric(
                        insertion: .offset(y: 6).combined(with: .opacity).animation(JottMotion.content),
                        removal: .offset(y: 4).combined(with: .opacity).animation(JottMotion.content)
                    ))
                }

                if let note = viewModel.selectedNote, !viewModel.isEditingNote {
                    NoteFooter(note: note, isDarkMode: viewModel.isDarkMode)
                        .transition(.opacity)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.jottBorder.opacity(0.9), lineWidth: 1)
        )
        .animation(JottMotion.content, value: detailContentID)
        .animation(JottMotion.content, value: viewModel.isEditingNote)
        .jottAppTypography()
        .onChange(of: viewModel.selectedNote?.id) { oldID, newID in
            if oldID != newID {
                viewModel.cancelEditingNote()
                showSubnoteInput = false
            }
        }
        .onChange(of: viewModel.editingNoteText) { _, _ in
            scheduleAutoSave()
        }
        .onDisappear {
            autoSaveTimer?.invalidate()
        }
    }

    private func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
            Task { @MainActor in
                if let note = viewModel.selectedNote {
                    viewModel.autoSaveEditedNote(note)
                }
            }
        }
    }
}

// MARK: - Note Edit Toolbar Strip

private struct NoteEditToolbarStrip: View {
    @ObservedObject var viewModel: OverlayViewModel
    @Binding var showFormat: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showFormat {
                NoteEditFormatBar(text: $viewModel.editingNoteText)
                    .transition(.asymmetric(
                        insertion: .offset(x: -6).combined(with: .opacity).animation(JottMotion.content),
                        removal: .opacity.animation(JottMotion.content)
                    ))
            }
            Spacer(minLength: 0)
            if !viewModel.autoSaveStatus.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: viewModel.feedbackIcon)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.45))
                    Text(viewModel.autoSaveStatus)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.45))
                }
                .transition(.opacity.animation(JottMotion.content))
            }
            Button {
                withAnimation(JottMotion.content) { showFormat.toggle() }
            } label: {
                Text("Aa")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(showFormat ? .primary.opacity(0.75) : .secondary.opacity(0.5))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(showFormat ? Color.jottOverlaySelectorAccent.opacity(0.18) : Color.clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        showFormat ? Color.jottOverlaySelectorAccent.opacity(0.35) : Color.secondary.opacity(0.18),
                        lineWidth: 1
                    ))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

// MARK: - Note Edit Format Bar

private struct NoteEditFormatBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 2) {
            fmtGroup {
                fmtBtn("B", isBold: true)     { text = "**\(text)**" }
                fmtBtn("I", isItalic: true)   { text = "*\(text)*" }
                fmtBtn("S", isStrike: true)   { text = "~~\(text)~~" }
            }
            fmtSep
            fmtGroup {
                fmtIcon("list.bullet")        { text = "• " + text }
                fmtIcon("list.number")        { text = "1. " + text }
                fmtIcon("text.quote")         { text = "> " + text }
            }
            fmtSep
            fmtGroup {
                fmtIcon("textformat.size")    { text = "# " + text }
                fmtIcon("link")               { text += "\n[text](url)" }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.jottOverlaySurface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.jottBorder, lineWidth: 1))
    }

    private func fmtGroup<Content: View>(@ViewBuilder _ c: () -> Content) -> some View {
        HStack(spacing: 1) { c() }
    }
    private var fmtSep: some View {
        Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 12).padding(.horizontal, 3)
    }

    private func fmtBtn(_ lbl: String, isBold: Bool = false, isItalic: Bool = false, isStrike: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isBold { Text(lbl).bold() }
                else if isItalic { Text(lbl).italic() }
                else if isStrike { Text(lbl).strikethrough() }
                else { Text(lbl) }
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fmtIcon(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header

private struct DetailHeader: View {
    @ObservedObject var viewModel: OverlayViewModel
    @Binding var showSubnoteInput: Bool
    @State private var showInfo = false

    var accentGreen: Color {
        .jottAccentGreen
    }

    var body: some View {
        HStack(spacing: 6) {
            // Back
            Button(action: {
                withAnimation(JottMotion.panel) {
                    if let note = viewModel.selectedNote, viewModel.isEditingNote {
                        viewModel.saveEditedNote(note)
                    }
                    viewModel.selectedNote     = nil
                    viewModel.selectedReminder = nil
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(red: 0.447, green: 0.420, blue: 1.0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(JottJellyButtonStyle())

            Spacer()

            if let note = viewModel.selectedNote {
                if viewModel.isEditingNote {
                    Text("editing")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.3))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(Capsule())
                } else {
                    // View mode — solid squishy icon buttons
                    iconBtn("pin\(note.isPinned ? ".fill" : "")", color: note.isPinned ? .orange : .secondary) {
                        viewModel.togglePin(note)
                    }
                    iconBtn("doc.on.doc", color: .secondary) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.text, forType: .string)
                    }
                    iconBtn("arrow.up.right.square", color: .secondary) {
                        viewModel.openNoteInEditor(note)
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    // Add subnote — root notes only
                    if note.parentId == nil {
                        Button(action: {
                            withAnimation(JottMotion.content) { showSubnoteInput.toggle() }
                        }) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(showSubnoteInput
                                    ? Color(red: 0.58, green: 0.50, blue: 0.92)
                                    : Color(red: 0.58, green: 0.50, blue: 0.92).opacity(0.55))
                                .frame(width: 26, height: 26)
                                .background(showSubnoteInput
                                    ? Color(red: 0.58, green: 0.50, blue: 0.92).opacity(0.18)
                                    : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.88, pressedOpacity: 0.75))
                        .help("Add subnote")
                    }

                    Button(action: { showInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.88, pressedOpacity: 0.85))
                    .popover(isPresented: $showInfo, arrowEdge: .top) {
                        NoteInfoPopover(note: note, viewModel: viewModel)
                    }

                    iconBtn("trash", color: .red) {
                        withAnimation(JottMotion.panel) {
                            viewModel.deleteNote(note.id)
                            viewModel.selectedNote = nil
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            } else if let _ = viewModel.selectedReminder {
                typeBadge("REMINDER", color: Color("jott-reminder-accent"))
            } else if let _ = viewModel.selectedMeeting {
                typeBadge("MEETING", color: Color("jott-meeting-accent"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func iconBtn(_ icon: String, color: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color.opacity(0.6))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.88, pressedOpacity: 0.75))
    }

    private func typeBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Info Popover (dates, tags, links)

private struct NoteInfoPopover: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel

    var wordCount: Int {
        note.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Metadata
            VStack(alignment: .leading, spacing: 6) {
                infoRow("Created",  value: formatDate(note.timestamp))
                infoRow("Modified", value: formatDate(note.modifiedAt))
                infoRow("Words",    value: "\(wordCount)  ·  \(max(1, wordCount / 200)) min read")
            }

            // Tags
            if !note.tags.isEmpty {
                Divider().opacity(0.15)
                popoverSection("TAGS") {
                    FlowLayout(spacing: 5) {
                        ForEach(note.tags, id: \.self) { tag in
                            Button {
                                viewModel.setTagFilter(tag)
                                viewModel.selectedNote = nil
                            } label: {
                                Text("#\(tag)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color("jott-green"))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color("jott-green").opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

        }
        .padding(14)
        .frame(width: 240)
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private func popoverSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.6)
            content()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Note footer (subtle one-liner)

private struct NoteFooter: View {
    let note: Note
    let isDarkMode: Bool

    private var wordCount: Int {
        note.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
    private var relativeDate: String {
        let interval = Date().timeIntervalSince(note.modifiedAt)
        if interval < 60       { return "just now" }
        if interval < 3600     { return "\(Int(interval / 60))m ago" }
        if interval < 86400    { return "\(Int(interval / 3600))h ago" }
        if interval < 604800   { return "\(Int(interval / 86400))d ago" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return fmt.string(from: note.modifiedAt)
    }

    var body: some View {
        HStack {
            Text("Modified \(relativeDate)  ·  \(wordCount) word\(wordCount == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(isDarkMode ? Color.white.opacity(0.03) : Color.black.opacity(0.025))
    }
}

// MARK: - File attachment chip

private struct FileAttachmentChip: View {
    let path: String
    let name: String
    let isDark: Bool
    @State private var hovered = false

    private var fileURL: URL { NoteStore.shared.attachmentURL(for: path) }

    private var fileIcon: String {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf":                        return "doc.text.fill"
        case "doc", "docx":               return "doc.fill"
        case "xls", "xlsx", "csv":        return "tablecells.fill"
        case "ppt", "pptx":               return "rectangle.stack.fill"
        case "zip", "gz", "tar", "rar":   return "archivebox.fill"
        case "mp3", "wav", "aac", "m4a", "flac": return "music.note"
        case "mp4", "mov", "avi", "mkv":  return "play.rectangle.fill"
        case "swift", "py", "js", "ts", "json", "sh", "rb", "go": return "chevron.left.forwardslash.chevron.right"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo.fill"
        default:                           return "doc.fill"
        }
    }

    var body: some View {
        Button(action: { NSWorkspace.shared.open(fileURL) }) {
            HStack(spacing: 7) {
                Image(systemName: fileIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.75) : .black.opacity(0.65))
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDark ? Color.white.opacity(hovered ? 0.09 : 0.055) : Color.black.opacity(hovered ? 0.07 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.jottBorder.opacity(hovered ? 0.7 : 0.45), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hovered = h } }
    }
}

// MARK: - Link chip

private struct LinkChip: View {
    let url: String
    let text: String
    @State private var hovered = false

    private var displayText: String {
        guard text == url, let u = URL(string: url) else { return text }
        return u.host ?? text
    }

    var body: some View {
        Button(action: { URL(string: url).map { NSWorkspace.shared.open($0) } }) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor.opacity(0.75))
                Text(displayText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor.opacity(0.85))
                    .lineLimit(1)
                    .underline(color: .accentColor.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(hovered ? 0.10 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(hovered ? 0.35 : 0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hovered = h } }
    }
}

// MARK: - Note Detail Content

struct NoteDetailContent: View {
    let note: Note
    @ObservedObject var viewModel: OverlayViewModel

    @State private var isDragTargeted = false

    private static let imageExtensions: Set<String> = [
        "jpg","jpeg","png","gif","webp","heic","bmp","tiff","svg"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isEditingNote {
                TextEditor(text: $viewModel.editingNoteText)
                    .font(.system(size: 15))
                    .foregroundColor(viewModel.isDarkMode ? .white : .black)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 200)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    NoteRichContentView(
                        text: note.text,
                        isDarkMode: viewModel.isDarkMode,
                        onTap: { viewModel.startEditingNote(note) }
                    )

                    // Only show subnote outliner for root notes
                    if note.parentId == nil {
                        SubnoteOutlinerView(
                            parentNote: note,
                            viewModel: viewModel,
                            isDark: viewModel.isDarkMode
                        )
                    }
                }
                .overlay {
                    if isDragTargeted {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.65),
                                          style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .background(Color.accentColor.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                VStack(spacing: 6) {
                                    Image(systemName: "arrow.down.to.line")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.accentColor.opacity(0.7))
                                    Text("Drop to attach")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.accentColor.opacity(0.7))
                                }
                            )
                            .allowsHitTesting(false)
                            .transition(.opacity.animation(.easeInOut(duration: 0.12)))
                    }
                }
                .onDrop(of: [UTType.fileURL.identifier, UTType.url.identifier],
                        isTargeted: $isDragTargeted) { providers in
                    handleDrop(providers)
                    return true
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in attachLocalFile(from: url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          let scheme = url.scheme,
                          scheme == "http" || scheme == "https" else { return }
                    Task { @MainActor in
                        appendText("\n[\(url.absoluteString)](\(url.absoluteString))")
                    }
                }
            }
        }
    }

    private func attachLocalFile(from url: URL) {
        let ext = url.pathExtension.lowercased()
        let isImage = Self.imageExtensions.contains(ext)
        guard let path = NoteStore.shared.saveFileAttachment(from: url) else { return }
        let name = url.lastPathComponent
        let mdLine = isImage
            ? "\n![\(name)](\(path))"
            : "\n[📎 \(name)](\(path))"
        appendText(mdLine)
    }

    private func appendText(_ addition: String) {
        let newText = note.text + addition
        viewModel.updateNote(note, text: newText)
        // Refresh selectedNote so the view re-renders with the new attachment
        viewModel.selectedNote = NoteStore.shared.note(for: note.id) ?? note
    }
}

// MARK: - Reminder Detail Content

struct ReminderDetailContent: View {
    let reminder: Reminder
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color("jott-reminder-accent"))
                Text(reminder.text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(viewModel.isDarkMode ? .white : .black)
            }

            HStack(spacing: 6) {
                Text(reminder.isCompleted ? "Completed" : "Pending")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(reminder.isCompleted ? .green : Color("jott-reminder-accent"))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((reminder.isCompleted ? Color.green : Color("jott-reminder-accent")).opacity(0.12))
                    .clipShape(Capsule())
                Text("Due \(formatDateTime(reminder.dueDate))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if !reminder.isCompleted {
                Divider().opacity(0.12)
                VStack(alignment: .leading, spacing: 6) {
                    Text("SNOOZE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                    HStack(spacing: 8) {
                        SnoozeButton(label: "30 min")       { viewModel.snoozeReminder(reminder, minutes: 30) }
                        SnoozeButton(label: "1 hour")       { viewModel.snoozeReminder(reminder, minutes: 60) }
                        SnoozeButton(label: "Tomorrow 9am") { viewModel.snoozeReminderToTomorrow(reminder) }
                    }
                }
            }
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Meeting Detail Content

struct MeetingDetailContent: View {
    let meeting: Meeting
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .foregroundColor(Color("jott-meeting-accent"))
                Text(meeting.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(viewModel.isDarkMode ? .white : .black)
            }

            HStack(spacing: 6) {
                Text("MEETING")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color("jott-meeting-accent"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color("jott-meeting-accent").opacity(0.12))
                    .clipShape(Capsule())

                Text(formatDateTime(meeting.startTime))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if !meeting.participants.isEmpty {
                Divider().opacity(0.12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("PARTICIPANTS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.6)

                    FlowLayout(spacing: 6) {
                        ForEach(meeting.participants, id: \.self) { participant in
                            Text(participant)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color("jott-meeting-accent"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color("jott-meeting-accent").opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if let description = meeting.description, !description.isEmpty {
                Divider().opacity(0.12)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.isDarkMode ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Snooze Button

struct SnoozeButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color("jott-reminder-accent"))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color("jott-reminder-accent").opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail Info Row (kept for any remaining callers)

struct DetailInfoRow: View {
    let label: String
    let value: String
    var isDarkMode: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(isDarkMode ? .white : .primary)
            Spacer()
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var verticalAlignment: VerticalAlignment = .top

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            rowH = max(rowH, s.height); x += s.width + spacing
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentRow: [(LayoutSubview, CGSize, CGFloat)] = []
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0

        func flushRow() {
            for (sv, size, originX) in currentRow {
                let yOffset: CGFloat
                switch verticalAlignment {
                case .center:
                    yOffset = (rowH - size.height) / 2
                case .bottom:
                    yOffset = rowH - size.height
                default:
                    yOffset = 0
                }

                sv.place(at: CGPoint(x: originX, y: y + yOffset), proposal: .unspecified)
            }

            y += rowH + spacing
            x = bounds.minX
            rowH = 0
            currentRow.removeAll(keepingCapacity: true)
        }

        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                flushRow()
            }

            currentRow.append((sv, size, x))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }

        if !currentRow.isEmpty {
            flushRow()
        }
    }
}

#Preview {
    DetailView(viewModel: OverlayViewModel())
}

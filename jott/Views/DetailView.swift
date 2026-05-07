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

        // Image token on its own line.
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
        Button(action: { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }) {
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

struct NoteBlockRichContentView: View {
    let blocks: [Block]
    let isDarkMode: Bool
    let onTap: () -> Void

    private var displayBlocks: [Block] { jottDisplayBlocks(from: blocks) }
    private var ink: Color { isDarkMode ? Color(white: 0.92) : Color("jott-input-text") }
    private var inkMute: Color { isDarkMode ? Color(white: 0.60) : Color(white: 0.42) }
    private var accent: Color { isDarkMode ? Color(red: 0.58, green: 0.50, blue: 0.92) : Color(red: 0.42, green: 0.30, blue: 0.76) }
    private var quoteBorder: Color { accent.opacity(0.45) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(displayBlocks.enumerated()), id: \.element.id) { index, block in
                blockView(block, orderedNumber: orderedNumber(at: index))
                    .onTapGesture(count: 2) { onTap() }
            }
        }
    }

    private func orderedNumber(at index: Int) -> Int? {
        guard displayBlocks.indices.contains(index),
              displayBlocks[index].type == .numberedItem else { return nil }

        var number = 1
        var i = index - 1
        while displayBlocks.indices.contains(i), displayBlocks[i].type == .numberedItem {
            number += 1
            i -= 1
        }
        return number
    }

    @ViewBuilder
    private func blockView(_ block: Block, orderedNumber: Int? = nil) -> some View {
        switch block.type {
        case .paragraph:
            BlockSpansText(spans: block.spans, font: .system(size: 15), color: ink)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .heading:
            let level = max(1, min(block.level, 3))
            let size: CGFloat = level == 1 ? 19 : level == 2 ? 16 : 14
            let weight: Font.Weight = level == 1 ? .bold : .semibold
            BlockSpansText(spans: block.spans, font: .system(size: size, weight: weight), color: ink)
                .padding(.top, level == 1 ? 6 : 2)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bulletItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("·")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 12, alignment: .center)
                BlockSpansText(spans: block.spans, font: .system(size: 15), color: ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .numberedItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(orderedNumber ?? 1).")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(inkMute)
                    .frame(width: 22, alignment: .trailing)
                BlockSpansText(spans: block.spans, font: .system(size: 15), color: ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .taskItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(block.checked ? accent : inkMute)
                    .frame(width: 16, alignment: .center)
                BlockSpansText(spans: block.spans, font: .system(size: 15), color: ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(quoteBorder)
                    .frame(width: 2.5)
                    .clipShape(Capsule())
                BlockSpansText(spans: block.spans, font: .system(size: 15).italic(), color: inkMute)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)

        case .codeBlock:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(isDarkMode
                        ? Color(red: 0.75, green: 0.95, blue: 0.80)
                        : Color(red: 0.10, green: 0.40, blue: 0.20))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1))

        case .table:
            MDTableView(headers: block.tableHeaders, rows: block.tableRows, isDarkMode: isDarkMode)

        case .divider:
            Divider()
                .opacity(isDarkMode ? 0.20 : 0.15)
                .padding(.vertical, 4)

        case .image:
            if let imageURL = block.imageURL, !imageURL.isEmpty {
                AttachmentImageView(path: imageURL, alt: block.imageAlt)
            }

        case .toggle:
            BlockSpansText(spans: block.spans, font: .system(size: 15), color: ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BlockSpansText: View {
    let spans: [TextSpan]
    let font: Font
    let color: Color

    var body: some View {
        text
            .font(font)
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var text: Text {
        let values = spans.isEmpty ? [TextSpan("")] : spans
        return values.reduce(Text("")) { partial, span in
            Text("\(partial)\(styledText(for: span))")
        }
    }

    private func styledText(for span: TextSpan) -> Text {
        if span.highlight {
            var attrStr = AttributedString(span.text)
            attrStr.backgroundColor = Color.yellow.opacity(0.40)
            if span.bold { attrStr.font = .system(size: 15, weight: .bold) }
            if span.italic { attrStr.font = Font.system(size: 15).italic() }
            if span.underline { attrStr.underlineStyle = .single }
            if span.strikethrough { attrStr.strikethroughStyle = .single }
            if span.code { attrStr.font = .system(size: 14, design: .monospaced) }
            return Text(attrStr)
        }
        var value = Text(span.text)
        if span.bold { value = value.bold() }
        if span.italic { value = value.italic() }
        if span.underline { value = value.underline() }
        if span.strikethrough { value = value.strikethrough() }
        if span.code { value = value.font(.system(size: 14, design: .monospaced)) }
        return value
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
                    let hasImages = pieces.contains { if case .image = $0 { return true }; return false }
                    VStack(alignment: .leading, spacing: 8) {
                        if hasImages {
                            FlowLayout(spacing: 0, verticalAlignment: .center) {
                                ForEach(pieces) { piece in
                                    piecView(piece)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(pieces) { piece in
                                piecView(piece)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

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

    @ViewBuilder
    private func piecView(_ piece: Piece) -> some View {
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
                    .foregroundColor(isDarkMode ? Color(white: 0.92) : Color("jott-input-text"))
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
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
        return [.text(UUID(), chunk)]
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
    @State private var showSubnoteInput = false
    @State private var autoSaveTimer: Timer?

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
                DetailHeader(viewModel: viewModel)

                Divider().opacity(0.1)

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
            .overlay(alignment: .bottom) {
                if let note = viewModel.selectedNote, !viewModel.isEditingNote,
                   note.parentId == nil, !showSubnoteInput {
                    let accent = Color(red: 0.58, green: 0.50, blue: 0.92)
                    Button { withAnimation(JottMotion.content) { showSubnoteInput = true } } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 14, weight: .medium))
                            Text("New Subnote")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(accent.opacity(0.22), lineWidth: 0.8))
                    }
                    .buttonStyle(JottSquishyButtonStyle(pressedScale: 0.94, pressedOpacity: 0.80))
                    .padding(.bottom, 16)
                    .transition(.opacity.animation(JottMotion.content))
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
        .onChange(of: viewModel.editingNoteBlocks) { _, _ in
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
                fmtBtn("B", isBold: true) { apply(.bold) }
                fmtBtn("I", isItalic: true) { apply(.italic) }
                fmtBtn("U", isUnderline: true) { apply(.underline) }
                fmtBtn("S", isStrike: true) { apply(.strikethrough) }
                fmtIcon("highlighter") { apply(.highlight) }
            }
            fmtSep
            fmtGroup {
                fmtIcon("list.bullet") { apply(.bulletList) }
                fmtIcon("list.number") { apply(.numberedList) }
                fmtIcon("checklist") { apply(.taskList) }
                fmtIcon("text.quote") { apply(.quote) }
            }
            fmtSep
            fmtGroup {
                fmtIcon("chevron.left.forwardslash.chevron.right") { apply(.inlineCode) }
                fmtIcon("textformat.size") { apply(.heading) }
                fmtIcon("link") { apply(.link) }
                tableMenu
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

    private func apply(_ command: JottTextFormatCommand) {
        var draft = text
        if !JottTextFormatting.apply(command, fallbackText: &draft) {
            text = draft
        }
    }

    private var tableMenu: some View {
        Menu {
            Button("2 x 2") { apply(.table(rows: 2, columns: 2)) }
            Button("3 x 3") { apply(.table(rows: 3, columns: 3)) }
            Button("4 x 4") { apply(.table(rows: 4, columns: 4)) }
            Button("6 x 4") { apply(.table(rows: 4, columns: 6)) }
        } label: {
            Image(systemName: "tablecells")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func fmtBtn(_ lbl: String, isBold: Bool = false, isItalic: Bool = false, isUnderline: Bool = false, isStrike: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isBold { Text(lbl).bold() }
                else if isItalic { Text(lbl).italic() }
                else if isUnderline { Text(lbl).underline() }
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
    @State private var showInfo = false

    var accentGreen: Color {
        .jottAccentGreen
    }

    var computedBackLabel: String {
        let isInSubnoteNav = viewModel.navigationStack.count > 1
        guard isInSubnoteNav, let parent = viewModel.navigationStack.dropLast().last else { return "Back" }
        let lines = parent.text.components(separatedBy: "\n")
        let firstLine = lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return firstLine.isEmpty ? "Back" : firstLine
    }

    var body: some View {
        HStack(spacing: 6) {
            // Back button — handle subnote navigation stack
            let isInSubnoteNav = viewModel.navigationStack.count > 1
            let backLabel = computedBackLabel

            Button(action: {
                withAnimation(JottMotion.panel) {
                    if let note = viewModel.selectedNote, viewModel.isEditingNote {
                        viewModel.saveEditedNote(note)
                    }
                    if isInSubnoteNav {
                        viewModel.popNavigation()
                    } else {
                        viewModel.selectedNote     = nil
                        viewModel.selectedReminder = nil
                    }
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text(backLabel.isEmpty ? "Back" : backLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
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
        Button(action: {
            if let target = URL(string: url) {
                NSWorkspace.shared.open(target)
            }
        }) {
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
    @State private var titleSuggestion: String? = nil
    @State private var titleTask: Task<Void, Never>? = nil

    private static let imageExtensions: Set<String> = [
        "jpg","jpeg","png","gif","webp","heic","bmp","tiff","svg"
    ]
    private static let inlineImageRegex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#)

    private var displayBlocks: [Block] {
        jottDisplayBlocks(from: note.blocks)
    }

    private var titleBlock: Block? {
        displayBlocks.first(where: isTitleCandidate)
    }

    private var bodyBlocks: [Block] {
        var bodyBlocks = displayBlocks
        if let titleIndex = bodyBlocks.firstIndex(where: { isTitleCandidate($0) }) {
            bodyBlocks.remove(at: titleIndex)
        }
        return bodyBlocks
    }

    private func isTitleCandidate(_ block: Block) -> Bool {
        switch block.type {
        case .paragraph, .heading:
            return !block.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isEditingNote {
                LibraryBlockEditor(blocks: $viewModel.editingNoteBlocks, isDarkMode: viewModel.isDarkMode)
                .frame(minHeight: 200)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    // Serif title — first non-empty text block, rendered from JSON blocks.
                    if let titleBlock {
                        let titleColor: Color = viewModel.isDarkMode ? Color(white: 0.92) : Color.primary.opacity(0.92)
                        BlockSpansText(
                            spans: titleBlock.spans,
                            font: .system(size: 22, weight: .regular, design: .serif),
                            color: titleColor
                        )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture(count: 2) { viewModel.startEditingNote(note) }
                    }

                    if !bodyBlocks.isEmpty {
                        NoteBlockRichContentView(
                            blocks: bodyBlocks,
                            isDarkMode: viewModel.isDarkMode,
                            onTap: { viewModel.startEditingNote(note) }
                        )
                    } else if titleBlock == nil {
                        NoteBlockRichContentView(
                            blocks: displayBlocks,
                            isDarkMode: viewModel.isDarkMode,
                            onTap: { viewModel.startEditingNote(note) }
                        )
                    }

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
        .onChange(of: viewModel.isEditingNote) { _, editing in
            if !editing { clearAI() }
        }
        .onChange(of: note.id) { _, _ in clearAI() }
    }

    // MARK: - AI helpers

    private func scheduleAI(for text: String) {
        // Title: 2s debounce
        titleTask?.cancel()
        titleTask = Task {
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            let result = await NoteAIService.shared.suggestTitle(for: text)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) { titleSuggestion = result }
            }
        }
    }

    private func clearAI() {
        titleTask?.cancel()
        titleSuggestion = nil
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
            ? "\n![\(name)](\(path))\n"
            : "\n[📎 \(name)](\(path))\n"
        appendText(mdLine)
    }

    private func appendText(_ addition: String) {
        let newText = note.text + addition
        viewModel.updateNote(note, text: newText)
        // Refresh selectedNote so the view re-renders with the new attachment
        viewModel.selectedNote = NoteStore.shared.note(for: note.id) ?? note
    }

    private func containsImageMarkup(_ line: String) -> Bool {
        guard let regex = Self.inlineImageRegex else { return false }
        return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }
}

// MARK: - Note Inline Editor (ghost-text autocomplete)

private struct NoteInlineEditor: NSViewRepresentable {
    @Binding var text: String
    var suggestion: String?
    var isDark: Bool
    var onTextChange: ((String) -> Void)?
    var onSuggestionAccepted: () -> Void
    var onSuggestionDismissed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.autohidesScrollers = true

        let tv = DetailNoteTextView()
        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.font = .systemFont(ofSize: 15)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.registerForDraggedTypes([.fileURL, .png, .tiff, .string])

        sv.documentView = tv
        context.coordinator.textView = tv
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? DetailNoteTextView else { return }
        let coord = context.coordinator
        coord.parent = self

        let textColor: NSColor = isDark
            ? .white.withAlphaComponent(0.90)
            : .black.withAlphaComponent(0.85)
        let ghostColor: NSColor = isDark
            ? NSColor(white: 0.72, alpha: 0.42)
            : NSColor(white: 0.58, alpha: 0.72)
        let font = NSFont.systemFont(ofSize: 15)

        let targetString = text + (suggestion ?? "")

        if tv.textStorage?.string != targetString {
            let savedSel = tv.selectedRange()

            let attrStr = NSMutableAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: textColor]
            )
            if let sug = suggestion, !sug.isEmpty {
                attrStr.append(NSAttributedString(
                    string: sug,
                    attributes: [.font: font, .foregroundColor: ghostColor]
                ))
                coord.ghostStart = text.utf16.count
            } else {
                coord.ghostStart = nil
            }

            tv.textStorage?.setAttributedString(attrStr)
            let clampedLoc = min(savedSel.location, text.utf16.count)
            tv.setSelectedRange(NSRange(location: clampedLoc, length: 0))
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteInlineEditor
        weak var textView: NSTextView?
        /// UTF-16 offset where ghost text starts in storage. nil when no ghost.
        var ghostStart: Int? = nil

        init(_ parent: NoteInlineEditor) { self.parent = parent }

        // Strip ghost before any user edit so textDidChange sees clean text.
        func textView(_ tv: NSTextView,
                      shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            JottTextFormattingRegistry.activeTextView = tv
            guard let gs = ghostStart else { return true }
            let totalLen = tv.textStorage?.length ?? 0
            if totalLen > gs {
                tv.textStorage?.deleteCharacters(in: NSRange(location: gs, length: totalLen - gs))
            }
            ghostStart = nil
            DispatchQueue.main.async { self.parent.onSuggestionDismissed() }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            JottTextFormattingRegistry.activeTextView = tv
            let newText = tv.string   // ghost already stripped by shouldChangeTextIn
            parent.text = newText
            parent.onTextChange?(newText)
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            // Tab → accept ghost text
            if sel == #selector(NSResponder.insertTab(_:)), let gs = ghostStart {
                guard let storage = tv.textStorage else { return false }
                let totalLen = storage.length
                let ghostLen = totalLen - gs
                if ghostLen > 0 {
                    let ghostText = (storage.string as NSString).substring(from: gs)
                    let realAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 15),
                        .foregroundColor: parent.isDark
                            ? NSColor.white.withAlphaComponent(0.90)
                            : NSColor.black.withAlphaComponent(0.85)
                    ]
                    storage.setAttributes(realAttrs, range: NSRange(location: gs, length: ghostLen))
                    ghostStart = nil
                    parent.text = storage.string
                    parent.onSuggestionAccepted()
                    tv.setSelectedRange(NSRange(location: storage.length, length: 0))
                    _ = ghostText  // silence unused warning
                }
                return true
            }
            // Escape → dismiss ghost
            if sel == #selector(NSResponder.cancelOperation(_:)), let gs = ghostStart {
                let totalLen = tv.textStorage?.length ?? 0
                if totalLen > gs {
                    tv.textStorage?.deleteCharacters(in: NSRange(location: gs, length: totalLen - gs))
                }
                ghostStart = nil
                parent.onSuggestionDismissed()
                return true
            }
            if sel == #selector(NSResponder.insertNewline(_:)) ||
               sel == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                if JottTextFormatting.handleContinuationNewline(in: tv) { return true }
                tv.insertText("\n", replacementRange: tv.selectedRange())
                return true
            }
            if sel == #selector(NSResponder.insertTab(_:)),
               JottTextFormatting.handleTab(in: tv) {
                return true
            }
            return false
        }

        // Keep cursor out of ghost region
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView, let gs = ghostStart else { return }
            let sel = tv.selectedRange()
            if sel.location > gs {
                tv.setSelectedRange(NSRange(location: gs, length: 0))
            }
        }
    }
}

// MARK: - AI Suggestion Chip

private struct AISuggestionChip: View {
    let label: String
    let icon: String
    let isDark: Bool
    let onApply: () -> Void
    let onDismiss: () -> Void

    private var accent: Color {
        isDark ? Color(red: 0.58, green: 0.50, blue: 0.92) : Color(red: 0.42, green: 0.30, blue: 0.76)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(accent.opacity(0.80))

            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(isDark ? Color.white.opacity(0.48) : Color.black.opacity(0.42))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Button("Apply") { onApply() }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(accent)
                .buttonStyle(.plain)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.22))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(isDark ? 0.07 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(accent.opacity(isDark ? 0.22 : 0.15), lineWidth: 0.5)
                )
        )
        .transition(.offset(y: -4).combined(with: .opacity))
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

// MARK: - Text view with image drag/drop support

final class DetailNoteTextView: NSTextView {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            JottTextFormattingRegistry.activeTextView = self
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, JottTextFormattingRegistry.activeTextView === self {
            JottTextFormattingRegistry.activeTextView = nil
        }
        return resigned
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              !modifiers.contains(.shift),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "b": JottTextFormatting.apply(.bold, to: self); return true
        case "i": JottTextFormatting.apply(.italic, to: self); return true
        case "u": JottTextFormatting.apply(.underline, to: self); return true
        case "e": JottTextFormatting.apply(.inlineCode, to: self); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if pb.types?.contains(.fileURL) == true || pb.types?.contains(.tiff) == true {
            return .copy
        }
        return .generic
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return insertTransfer(from: sender.draggingPasteboard)
    }

    @discardableResult
    func insertTransfer(from pb: NSPasteboard) -> Bool {
        if let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first {
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                _ = NoteStore.shared.saveAttachment(data: pngData, filename: "clipboard-\(UUID().uuidString).png")
                return true
            }
        }
        return false
    }
}

#Preview {
    DetailView(viewModel: OverlayViewModel())
}

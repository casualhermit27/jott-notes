import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Combine
import AVFoundation

// MARK: - Locked banner (trial ended)

struct IOSLockedBanner: View {
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .jottShowPaywall, object: nil)
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.710, green: 0.549, blue: 0.965))
                    Text("Your trial has ended")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Text("Your notes are safe and waiting.\nUnlock Jott to keep writing.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Text("Unlock Jott  ·  $12.99 one time")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Color(red: 0.545, green: 0.361, blue: 0.965),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 16)
            .background(
                Color(red: 0.545, green: 0.361, blue: 0.965).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 0.710, green: 0.549, blue: 0.965).opacity(0.20), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail view (read + edit)

struct IOSDetailView: View {
    let note: Note
    let onDelete: (() -> Void)?

    @ObservedObject private var noteStore: NoteStore
    @ObservedObject private var purchases = PurchaseManager.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var editBlocks: [Block] = []
    @State private var showDeleteConfirm = false
    @State private var showNewSubnote = false
    @State private var autosaveTask: Task<Void, Never>? = nil
    @State private var showTagEditor = false
    @State private var scrollOffset: CGFloat = 0
    @State private var liveNote: Note

    init(note: Note, onDelete: (() -> Void)? = nil) {
        self.note = note
        self.onDelete = onDelete
        self._noteStore = ObservedObject(wrappedValue: NoteStore.shared)
        self._liveNote = State(initialValue: note)
    }

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }

    private func refreshLiveNote() {
        if let updated = noteStore.allNotes().first(where: { $0.id == note.id }) {
            liveNote = updated
        }
    }

    var body: some View {
        ZStack {
            ds.canvas.ignoresSafeArea()
            Group {
                if isEditing {
                    editorView
                } else {
                    readView
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { refreshLiveNote() }
        .onReceive(noteStore.objectWillChange) { _ in
            DispatchQueue.main.async { refreshLiveNote() }
        }
        .onDisappear {
            autosaveTask?.cancel()
            if isEditing { commitEdit() }
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Move to Recently Deleted", role: .destructive) {
                noteStore.deleteNote(note.id)
                if let onDelete = onDelete {
                    onDelete()
                } else {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showNewSubnote) {
            IOSNewNoteComposerView(
                title: "New Subnote",
                folderId: liveNote.folderId,
                parentId: note.id
            ) { _ in
            }
        }
        .sheet(isPresented: $showTagEditor) {
            IOSTagEditorView(tags: liveNote.tags) { updatedTags in
                var updated = liveNote
                updated.tags = updatedTags
                updated.modifiedAt = Date()
                noteStore.upsertNote(updated)
            }
        }
        .navigationDestination(for: Note.self) { sub in
            IOSDetailView(note: sub)
        }
    }

    // MARK: - Read mode

    private var readView: some View {
        let subnotes = noteStore.allNotes().filter { $0.parentId == note.id }
        return ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    metadataStrip
                    Rectangle().fill(ds.hairline).frame(height: 1).padding(.horizontal, 20)

                    IOSBlockContentView(blocks: liveNote.blocks, isDark: scheme == .dark)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)

                    if !subnotes.isEmpty {
                        subnotesSection
                    } else {
                        Spacer().frame(height: 100)
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(of: proxy.frame(in: .named("detailScroll")).minY) { _, y in
                                scrollOffset = -y
                            }
                    }
                )
            }
            .onTapGesture(count: 2) { enterEditing() }
            .coordinateSpace(name: "detailScroll")

            if purchases.hasAccess {
                Button { showNewSubnote = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 17, weight: .medium))
                        Text("New Subnote")
                            .font(.jottBody(15, weight: .medium))
                    }
                    .foregroundStyle(ds.accent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(ds.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ds.accent.opacity(0.22), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 28)
            } else {
                IOSLockedBanner()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Metadata strip

    private var metadataStrip: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(jottMetaDate(liveNote.modifiedAt))
                    .font(.jottMono(10, weight: .medium))
                    .foregroundStyle(ds.inkFaintest)
                    .tracking(0.4)
                Text(jottRelativeDate(liveNote.modifiedAt))
                    .font(.jottMono(10))
                    .foregroundStyle(ds.inkFaintest)
                    .tracking(0.4)
            }
            if liveNote.isPinned {
                Text("PINNED")
                    .font(.jottMono(9, weight: .medium))
                    .foregroundStyle(ds.accent.opacity(0.45))
                    .tracking(0.6)
            }
            Spacer()
            Button { showTagEditor = true } label: {
                if liveNote.tags.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 10, weight: .medium))
                        Text("Tags")
                            .font(.jottCaption(11, weight: .medium))
                    }
                    .foregroundStyle(ds.inkFaintest)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ds.surfaceAlt, in: Capsule())
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(liveNote.tags, id: \.self) { tag in
                                JottTagChip(tag: tag, ds: ds)
                            }
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(ds.inkFaintest)
                        }
                    }
                    .frame(maxWidth: 180)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Subnotes section (only rendered when subnotes exist)

    @ViewBuilder
    private var subnotesSection: some View {
        let subnotes = noteStore.allNotes().filter { $0.parentId == note.id }

        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(ds.hairline).frame(height: 1).padding(.horizontal, 20)

            HStack {
                Text("SUBNOTES")
                    .font(.jottMono(10, weight: .medium))
                    .foregroundStyle(ds.inkFaintest)
                    .tracking(0.6)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ForEach(subnotes) { sub in
                NavigationLink(value: sub) {
                    SubnoteRow(note: sub, ds: ds)
                }
                .buttonStyle(.plain)

                if sub.id != subnotes.last?.id {
                    Rectangle().fill(ds.hairline).frame(height: 1).padding(.horizontal, 20)
                }
            }

            Spacer().frame(height: 100)
        }
    }

    // MARK: - Edit mode

    private var editorView: some View {
        IOSBlockNoteEditor(
            blocks: $editBlocks,
            isDark: scheme == .dark,
            autoFocus: true
        ) { newBlocks in
            scheduleAutosave(blocks: newBlocks)
        }
        .background(ds.canvas)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if !isEditing, scrollOffset > 80 {
                Text(jottNotePreview(liveNote).title)
                    .font(.jottBody(17, weight: .semibold))
                    .foregroundStyle(ds.ink)
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if isEditing {
                Button("Done") { commitEdit() }
                    .fontWeight(.semibold)
                    .foregroundStyle(ds.accent)
            } else {
                Button { enterEditing() } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(ds.inkMute)
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if !isEditing {
                Menu {
                    Button {
                        noteStore.togglePin(note.id)
                    } label: {
                        Label(liveNote.isPinned ? "Unpin" : "Pin",
                              systemImage: liveNote.isPinned ? "pin.slash" : "pin")
                    }
                    Button { shareNote() } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(ds.inkMute)
                }
            }
        }
    }

    // MARK: - Helpers

    private func enterEditing() {
        guard purchases.hasAccess else {
            NotificationCenter.default.post(name: .jottShowPaywall, object: nil)
            return
        }
        editBlocks = liveNote.blocks
        isEditing = true
    }

    private func commitEdit() {
        Haptics.success()
        var updated = liveNote
        let clean = editBlocks.filter { $0.type != .table || !$0.tableHeaders.isEmpty }
        guard !clean.isEmpty else { return }
        updated.blocks = clean
        updated.modifiedAt = Date()
        noteStore.upsertNote(updated)
        isEditing = false
    }

    private func scheduleAutosave(blocks newBlocks: [Block]) {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let clean = newBlocks.filter { $0.type != .table || !$0.tableHeaders.isEmpty }
            guard !clean.isEmpty else { return }
            var updated = liveNote
            updated.blocks = clean
            updated.modifiedAt = Date()
            await MainActor.run { noteStore.upsertNote(updated) }
        }
    }

    private func shareNote() {
        let items: [Any]
        if let url = noteStore.exportNoteAsMarkdown(liveNote) {
            items = [url]
        } else {
            items = [liveNote.text]
        }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

// MARK: - iOS block text editor (UITextView + format toolbar)

struct IOSBlockTextEditor: UIViewRepresentable {
    @Binding var blocks: [Block]
    let isDark: Bool
    var autoFocus: Bool = false
    var onBlocksChange: (([Block]) -> Void)?
    var onInsertTable: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.attributedText = context.coordinator.displayAttributedText(for: blocks)
        tv.typingAttributes = context.coordinator.defaultTypingAttributes()
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 80, right: 16)
        tv.keyboardDismissMode = .interactive
        context.coordinator.textView = tv

        let toolbar = IOSFormatToolbarView(coordinator: context.coordinator, isDark: isDark)
        tv.inputAccessoryView = toolbar

        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                tv.becomeFirstResponder()
            }
        }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        let proposed = context.coordinator.displayAttributedText(for: blocks)
        let textChanged = tv.attributedText.string != proposed.string
        let darkChanged = context.coordinator.lastIsDark != isDark
        if textChanged || darkChanged {
            let sel = tv.selectedRange
            tv.attributedText = proposed
            tv.typingAttributes = context.coordinator.defaultTypingAttributes()
            context.coordinator.lastIsDark = isDark
            let len = (tv.text as NSString).length
            if sel.upperBound <= len { tv.selectedRange = sel }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSBlockTextEditor
        weak var textView: UITextView?
        var lastIsDark: Bool?

        weak var micButton: UIButton?
        var micInkColor: UIColor = .gray
        var micActiveColor: UIColor = .systemPurple
        private var voiceStartLocation: Int? = nil
        private var voiceTextLength: Int = 0

        init(_ parent: IOSBlockTextEditor) { self.parent = parent }

        // MARK: - Attributed display

        func defaultTypingAttributes() -> [NSAttributedString.Key: Any] {
            [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: inkColor()]
        }

        private func inkColor() -> UIColor {
            UIColor(
                red:   parent.isDark ? 0.95 : 0.14,
                green: parent.isDark ? 0.95 : 0.14,
                blue:  parent.isDark ? 0.95 : 0.15,
                alpha: 1
            )
        }

        func displayAttributedText(for blocks: [Block]) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let color = inkColor()
            var number = 1
            for (i, block) in blocks.enumerated() {
                let blockAttr = NSMutableAttributedString()
                switch block.type {
                case .bulletItem:
                    number = 1
                    blockAttr.append(plain("• ", color: color))
                case .numberedItem:
                    blockAttr.append(plain("\(number). ", color: color))
                    number += 1
                case .taskItem:
                    number = 1
                    blockAttr.append(plain(block.checked ? "☑ " : "☐ ", color: color))
                case .quote:
                    number = 1
                    blockAttr.append(plain("❝ ", color: color))
                case .heading:
                    number = 1
                    blockAttr.append(plain(String(repeating: "#", count: max(1, block.level)) + " ", color: color))
                default:
                    number = 1
                }
                for span in block.spans.isEmpty ? [TextSpan("")] : block.spans {
                    blockAttr.append(attributed(span, color: color))
                }
                if i < blocks.count - 1 {
                    blockAttr.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: color]))
                }
                result.append(blockAttr)
            }
            return result
        }

        private func plain(_ text: String, color: UIColor) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: color])
        }

        private func attributed(_ span: TextSpan, color: UIColor) -> NSAttributedString {
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color, .font: fontFor(span)]
            if span.underline      { attrs[.underlineStyle]     = NSUnderlineStyle.single.rawValue }
            if span.strikethrough  { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if span.highlight      { attrs[.backgroundColor]    = UIColor.yellow.withAlphaComponent(0.35) }
            return NSAttributedString(string: span.text, attributes: attrs)
        }

        private func fontFor(_ span: TextSpan) -> UIFont {
            let size: CGFloat = 16
            if span.code { return UIFont.monospacedSystemFont(ofSize: size - 1, weight: .regular) }
            var traits: UIFontDescriptor.SymbolicTraits = []
            if span.bold   { traits.insert(.traitBold) }
            if span.italic { traits.insert(.traitItalic) }
            guard !traits.isEmpty else { return UIFont.systemFont(ofSize: size) }
            let base = UIFont.systemFont(ofSize: size, weight: span.bold ? .bold : .regular)
            let desc = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
            return UIFont(descriptor: desc, size: size)
        }

        // MARK: - Extract blocks from attributed text

        func extractBlocks(from attrText: NSAttributedString) -> [Block] {
            let fullText = attrText.string
            guard !fullText.isEmpty else { return [Block(type: .paragraph, spans: [TextSpan("")])] }
            var result: [Block] = []
            var charOffset = 0
            for line in fullText.components(separatedBy: "\n") {
                let lineLen = (line as NSString).length
                let lineRange = NSRange(location: charOffset, length: lineLen)
                charOffset += lineLen + 1
                var blockType: BlockType = .paragraph
                var prefixLen = 0
                var checked = false
                var level = 1
                if line.hasPrefix("• ") {
                    blockType = .bulletItem; prefixLen = 2
                } else if line.hasPrefix("☐ ") {
                    blockType = .taskItem; prefixLen = 2
                } else if line.hasPrefix("☑ ") {
                    blockType = .taskItem; prefixLen = 2; checked = true
                } else if line.hasPrefix("❝ ") {
                    blockType = .quote; prefixLen = 2
                } else if line.hasPrefix("## ") {
                    blockType = .heading; prefixLen = 3; level = 2
                } else if line.hasPrefix("# ") {
                    blockType = .heading; prefixLen = 2
                } else if let m = numberedPrefixLen(in: line) {
                    blockType = .numberedItem; prefixLen = m
                }
                let contentRange = NSRange(location: lineRange.location + prefixLen, length: max(0, lineRange.length - prefixLen))
                let spans = contentRange.length > 0 ? spansFrom(attrText, range: contentRange) : [TextSpan("")]
                switch blockType {
                case .taskItem:  result.append(Block(type: .taskItem, spans: spans, checked: checked))
                case .heading:   result.append(Block(type: .heading, spans: spans, level: level))
                default:         result.append(Block(type: blockType, spans: spans))
                }
            }
            // Detect image blocks embedded in paragraphs
            let final = result.flatMap { block -> [Block] in
                guard block.type == .paragraph, let span = block.spans.first, !span.text.isEmpty else { return [block] }
                let parsed = Block.parseImageMarkdown(in: span.text)
                return (parsed.count == 1 && parsed[0].type == .paragraph) ? [block] : parsed
            }
            return final.isEmpty ? [Block(type: .paragraph, spans: [TextSpan("")])] : final
        }

        private func numberedPrefixLen(in line: String) -> Int? {
            guard let match = try? NSRegularExpression(pattern: #"^\d+\. "#)
                .firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
            return match.range.length
        }

        private func spansFrom(_ attrText: NSAttributedString, range: NSRange) -> [TextSpan] {
            var spans: [TextSpan] = []
            attrText.enumerateAttributes(in: range, options: []) { attrs, r, _ in
                let text = (attrText.string as NSString).substring(with: r)
                var span = TextSpan(text)
                if let font = attrs[.font] as? UIFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    span.bold   = traits.contains(.traitBold)
                    span.italic = traits.contains(.traitItalic)
                    span.code   = traits.contains(.traitMonoSpace)
                }
                if let u = attrs[.underlineStyle]     as? Int, u != 0 { span.underline      = true }
                if let s = attrs[.strikethroughStyle] as? Int, s != 0 { span.strikethrough  = true }
                if attrs[.backgroundColor] != nil                       { span.highlight     = true }
                spans.append(span)
            }
            return spans.isEmpty ? [TextSpan("")] : spans
        }

        // MARK: - Inline format toggle (WYSIWYG)

        enum InlineFormat { case bold, italic, underline, strikethrough, highlight, code }

        func applyInlineFormat(_ format: InlineFormat) {
            guard let tv = textView else { return }
            let sel = tv.selectedRange
            guard let attrText = tv.attributedText, attrText.length > 0 else { return }
            let applyRange = sel.length > 0 ? sel : wordRangeAt(sel.location, in: tv)
            guard applyRange.length > 0 else { return }

            let result = NSMutableAttributedString(attributedString: attrText)
            let allOn = isFormatActive(format, in: result, range: applyRange)

            result.enumerateAttributes(in: applyRange, options: []) { attrs, r, _ in
                let font = (attrs[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 16)
                switch format {
                case .bold:
                    result.addAttribute(.font, value: toggleTrait(.traitBold, on: font, remove: allOn), range: r)
                case .italic:
                    result.addAttribute(.font, value: toggleTrait(.traitItalic, on: font, remove: allOn), range: r)
                case .underline:
                    result.addAttribute(.underlineStyle, value: allOn ? 0 : NSUnderlineStyle.single.rawValue, range: r)
                case .strikethrough:
                    result.addAttribute(.strikethroughStyle, value: allOn ? 0 : NSUnderlineStyle.single.rawValue, range: r)
                case .highlight:
                    if allOn { result.removeAttribute(.backgroundColor, range: r) }
                    else     { result.addAttribute(.backgroundColor, value: UIColor.yellow.withAlphaComponent(0.35), range: r) }
                case .code:
                    let newFont: UIFont = allOn
                        ? UIFont.systemFont(ofSize: font.pointSize)
                        : UIFont.monospacedSystemFont(ofSize: max(font.pointSize - 1, 13), weight: .regular)
                    result.addAttribute(.font, value: newFont, range: r)
                }
            }

            tv.attributedText = result
            tv.selectedRange = sel
            let updated = extractBlocks(from: result)
            parent.blocks = updated
            parent.onBlocksChange?(updated)
        }

        private func isFormatActive(_ format: InlineFormat, in attrText: NSAttributedString, range: NSRange) -> Bool {
            guard range.length > 0 else { return false }
            var allOn = true
            attrText.enumerateAttributes(in: range, options: []) { attrs, _, _ in
                let traits = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
                switch format {
                case .bold:          if !traits.contains(.traitBold)      { allOn = false }
                case .italic:        if !traits.contains(.traitItalic)    { allOn = false }
                case .underline:     if (attrs[.underlineStyle]     as? Int ?? 0) == 0 { allOn = false }
                case .strikethrough: if (attrs[.strikethroughStyle] as? Int ?? 0) == 0 { allOn = false }
                case .highlight:     if attrs[.backgroundColor] == nil    { allOn = false }
                case .code:          if !traits.contains(.traitMonoSpace) { allOn = false }
                }
            }
            return allOn
        }

        private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits, on font: UIFont, remove: Bool) -> UIFont {
            var traits = font.fontDescriptor.symbolicTraits
            if remove { traits.remove(trait) } else { traits.insert(trait) }
            let desc = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
            return UIFont(descriptor: desc, size: font.pointSize)
        }

        private func wordRangeAt(_ location: Int, in tv: UITextView) -> NSRange {
            let nsText = tv.text as NSString
            let len = nsText.length
            guard len > 0, location <= len else { return NSRange(location: location, length: 0) }
            var s = location, e = location
            let ws = CharacterSet.whitespaces
            while s > 0, !nsText.substring(with: NSRange(location: s-1, length: 1)).unicodeScalars.allSatisfy({ ws.contains($0) }) { s -= 1 }
            while e < len, !nsText.substring(with: NSRange(location: e, length: 1)).unicodeScalars.allSatisfy({ ws.contains($0) }) { e += 1 }
            return NSRange(location: s, length: e - s)
        }

        // MARK: - UITextViewDelegate

        func textViewDidChange(_ tv: UITextView) {
            let updated = extractBlocks(from: tv.attributedText)
            parent.blocks = updated
            parent.onBlocksChange?(updated)
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", range.length == 0 else { return true }
            return !handleReturn(in: tv)
        }

        // MARK: - Voice input

        func registerMicButton(_ btn: UIButton, inkColor: UIColor, activeColor: UIColor) {
            micButton = btn
            micInkColor = inkColor
            micActiveColor = activeColor
        }

        func toggleVoice() {
            Task { @MainActor in
                let sm = SpeechManager.shared
                if sm.isRecording {
                    sm.stopRecording()
                    self.micButton?.tintColor = self.micInkColor
                    let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                    self.micButton?.setImage(UIImage(systemName: "mic", withConfiguration: cfg), for: .normal)
                    self.voiceStartLocation = nil
                    self.voiceTextLength = 0
                } else {
                    guard let tv = self.textView else { return }
                    switch AVAudioApplication.shared.recordPermission {
                    case .denied:
                        return
                    case .undetermined:
                        AVAudioApplication.requestRecordPermission { granted in
                            guard granted else { return }
                            DispatchQueue.main.async {
                                self.voiceStartLocation = tv.selectedRange.location
                                self.voiceTextLength = 0
                                self.micButton?.tintColor = self.micActiveColor
                                let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                                self.micButton?.setImage(UIImage(systemName: "stop.circle.fill", withConfiguration: cfg), for: .normal)
                                sm.startRecording { [weak self] partial in
                                    self?.insertVoiceText(partial, isFinal: false)
                                } onFinal: { [weak self] final in
                                    self?.insertVoiceText(final, isFinal: true)
                                    let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                                    self?.micButton?.setImage(UIImage(systemName: "mic", withConfiguration: cfg), for: .normal)
                                    self?.micButton?.tintColor = self?.micInkColor
                                }
                            }
                        }
                        return
                    default:
                        break
                    }
                    self.voiceStartLocation = tv.selectedRange.location
                    self.voiceTextLength = 0
                    self.micButton?.tintColor = self.micActiveColor
                    let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                    self.micButton?.setImage(UIImage(systemName: "stop.circle.fill", withConfiguration: cfg), for: .normal)
                    sm.startRecording { [weak self] partial in
                        self?.insertVoiceText(partial, isFinal: false)
                    } onFinal: { [weak self] final in
                        self?.insertVoiceText(final, isFinal: true)
                        let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                        self?.micButton?.setImage(UIImage(systemName: "mic", withConfiguration: cfg), for: .normal)
                        self?.micButton?.tintColor = self?.micInkColor
                    }
                }
            }
        }

        private func insertVoiceText(_ text: String, isFinal: Bool) {
            guard let tv = textView, let start = voiceStartLocation else { return }
            let nsText = tv.text as NSString
            let totalLen = nsText.length
            let replaceStart = min(start, totalLen)
            let replaceLen = min(voiceTextLength, totalLen - replaceStart)
            guard let startPos = tv.position(from: tv.beginningOfDocument, offset: replaceStart),
                  let endPos = tv.position(from: tv.beginningOfDocument, offset: replaceStart + replaceLen),
                  let textRange = tv.textRange(from: startPos, to: endPos) else { return }
            let insert = isFinal ? text + " " : text
            tv.replace(textRange, withText: insert)
            voiceTextLength = isFinal ? 0 : (insert as NSString).length
            if isFinal { voiceStartLocation = nil }
            let updated = extractBlocks(from: tv.attributedText)
            parent.blocks = updated
            parent.onBlocksChange?(updated)
        }

        // MARK: - Line prefix toggle (attribute-preserving)

        func toggleLinePrefix(_ prefix: String) {
            guard let tv = textView else { return }
            let nsText = tv.text as NSString
            let cursor = tv.selectedRange.location
            let lineNSRange = currentLineTextRange(in: tv, cursor: cursor)
            let line = nsText.substring(with: lineNSRange)

            let existingPrefix = existingStructuralPrefix(in: line)
            let existingLen = (existingPrefix as NSString).length

            // Treat any "N. " as matching the "1. " toggle target
            let isNumberedTarget = (prefix == "1. ")
            let removingPrefix = isNumberedTarget ? (numberedPrefixLen(in: line) != nil) : line.hasPrefix(prefix)
            let newPrefix = removingPrefix ? "" : prefix
            let newPrefixLen = (newPrefix as NSString).length

            // Replace only the prefix portion — content attributes are preserved
            let replaceRange = NSRange(location: lineNSRange.location, length: existingLen)
            guard let pStart = tv.position(from: tv.beginningOfDocument, offset: replaceRange.location),
                  let pEnd   = tv.position(from: tv.beginningOfDocument, offset: replaceRange.location + replaceRange.length),
                  let pRange = tv.textRange(from: pStart, to: pEnd) else { return }
            tv.replace(pRange, withText: newPrefix)

            let contentOffset = max(0, cursor - lineNSRange.location - existingLen)
            let newCursor = lineNSRange.location + newPrefixLen + contentOffset
            tv.selectedRange = NSRange(location: min(newCursor, (tv.text as NSString).length), length: 0)

            let updated = extractBlocks(from: tv.attributedText)
            parent.blocks = updated
            parent.onBlocksChange?(updated)
        }

        private func existingStructuralPrefix(in line: String) -> String {
            for p in ["• ", "☐ ", "☑ ", "❝ ", "## ", "# "] where line.hasPrefix(p) { return p }
            if let len = numberedPrefixLen(in: line) { return (line as NSString).substring(to: len) }
            return ""
        }

        // MARK: - Return key

        @discardableResult
        private func handleReturn(in tv: UITextView) -> Bool {
            let nsText = tv.text as NSString
            let cursor = tv.selectedRange.location
            let lineRange = currentLineTextRange(in: tv, cursor: cursor)
            let line = nsText.substring(with: lineRange)

            if line.hasPrefix("• ") {
                let empty = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces).isEmpty
                if empty { replaceText(in: tv, range: NSRange(location: lineRange.location, length: 2), with: "") }
                else     { insertText("\n• ", in: tv) }
                return true
            }
            if line.hasPrefix("☐ ") || line.hasPrefix("☑ ") {
                let empty = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces).isEmpty
                if empty { replaceText(in: tv, range: NSRange(location: lineRange.location, length: 2), with: "") }
                else     { insertText("\n☐ ", in: tv) }
                return true
            }
            if line.hasPrefix("❝ ") {
                let empty = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces).isEmpty
                if empty { replaceText(in: tv, range: NSRange(location: lineRange.location, length: 2), with: "") }
                else     { insertText("\n❝ ", in: tv) }
                return true
            }
            if let num = numberedPrefixInfo(in: line) {
                let empty = (line as NSString).substring(from: num.length).trimmingCharacters(in: .whitespaces).isEmpty
                if empty { replaceText(in: tv, range: NSRange(location: lineRange.location, length: num.length), with: "") }
                else     { insertText("\n\(num.value + 1). ", in: tv) }
                return true
            }
            return false
        }

        private func numberedPrefixInfo(in line: String) -> (value: Int, length: Int)? {
            let ns = line as NSString
            guard let match = try? NSRegularExpression(pattern: #"^(\d+)\. "#)
                .firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return (Int(ns.substring(with: match.range(at: 1))) ?? 1, match.range.length)
        }

        private func currentLineTextRange(in tv: UITextView, cursor: Int) -> NSRange {
            let nsText = tv.text as NSString
            let length = nsText.length
            if cursor == length, length > 0, nsText.character(at: length - 1) == 10 {
                return NSRange(location: cursor, length: 0)
            }
            let safeCursor = min(max(cursor, 0), length)
            let fullLineRange = nsText.lineRange(for: NSRange(location: safeCursor, length: 0))
            let hasNewline = fullLineRange.length > 0 && nsText.character(at: NSMaxRange(fullLineRange) - 1) == 10
            return NSRange(location: fullLineRange.location, length: fullLineRange.length - (hasNewline ? 1 : 0))
        }

        private func insertText(_ text: String, in tv: UITextView) {
            let sel = tv.selectedRange
            replaceText(in: tv, range: sel, with: text)
            tv.selectedRange = NSRange(location: sel.location + (text as NSString).length, length: 0)
        }

        private func replaceText(in tv: UITextView, range: NSRange, with text: String) {
            guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                  let end   = tv.position(from: tv.beginningOfDocument, offset: range.location + range.length),
                  let tRange = tv.textRange(from: start, to: end) else { return }
            tv.replace(tRange, withText: text)
            let updated = extractBlocks(from: tv.attributedText)
            parent.blocks = updated
            parent.onBlocksChange?(updated)
        }

        func insertTable(rows: Int = 2, columns: Int = 2) { parent.onInsertTable?(rows, columns) }
        func dismissKeyboard() { textView?.resignFirstResponder() }

    }
}

// MARK: - Format toolbar (UIKit inputAccessoryView)

private final class IOSFormatToolbarView: UIView {
    private weak var coordinator: IOSBlockTextEditor.Coordinator?

    init(coordinator: IOSBlockTextEditor.Coordinator, isDark: Bool) {
        super.init(frame: CGRect(x: 0, y: 0, width: 100, height: 52))
        self.coordinator = coordinator
        autoresizingMask = [.flexibleWidth]
        clipsToBounds = true

        backgroundColor = isDark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 0.97)
            : UIColor(red: 0.97, green: 0.97, blue: 0.975, alpha: 0.97)

        let line = UIView()
        line.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.09)
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        scroll.alwaysBounceHorizontal = true
        scroll.isDirectionalLockEnabled = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 2
        row.alignment = .center
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: topAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),

            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        let inkMute = isDark
            ? UIColor(white: 0.68, alpha: 1)
            : UIColor(red: 0.36, green: 0.36, blue: 0.39, alpha: 1)
        let accentColor = isDark
            ? UIColor(red: 0.58, green: 0.48, blue: 0.88, alpha: 1)
            : UIColor(red: 0.42, green: 0.30, blue: 0.76, alpha: 1)

        addTextBtn(row, title: "B", weight: .bold,    color: inkMute, sel: #selector(bold))
        addTextBtn(row, title: "I", weight: .regular, italic: true,    color: inkMute, sel: #selector(italic))
        addTextBtn(row, title: "U", weight: .regular, underline: true, color: inkMute, sel: #selector(underline))
        addTextBtn(row, title: "S", weight: .regular, strike: true,    color: inkMute, sel: #selector(strike))
        addSeparator(row, isDark: isDark)
        addIconBtn(row, sf: "list.bullet",       color: inkMute,     sel: #selector(bullet))
        addIconBtn(row, sf: "list.number",       color: inkMute,     sel: #selector(numbered))
        addIconBtn(row, sf: "checklist",         color: inkMute,     sel: #selector(task))
        addIconBtn(row, sf: "text.quote",        color: inkMute,     sel: #selector(quote))
        addSeparator(row, isDark: isDark)
        addIconBtn(row, sf: "textformat.size",   color: inkMute,     sel: #selector(heading))
        addIconBtn(row, sf: "highlighter",       color: inkMute,     sel: #selector(highlight))
        addIconBtn(row, sf: "chevron.left.forwardslash.chevron.right", color: inkMute, sel: #selector(code))
        addIconBtn(row, sf: "tablecells",        color: accentColor, sel: #selector(table))
        addSeparator(row, isDark: isDark)
        let micBtn = addIconBtn(row, sf: "mic",  color: inkMute,     sel: #selector(mic))
        coordinator.registerMicButton(micBtn, inkColor: inkMute, activeColor: accentColor)
        addIconBtn(row, sf: "keyboard.chevron.compact.down", color: inkMute, sel: #selector(dismiss))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    private func addSeparator(_ stack: UIStackView, isDark: Bool) {
        let sep = UIView()
        sep.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.10)
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(sep)
        stack.setCustomSpacing(6, after: sep)
    }

    private func addTextBtn(_ stack: UIStackView, title: String, weight: UIFont.Weight, italic: Bool = false, underline: Bool = false, strike: Bool = false, color: UIColor, sel: Selector) {
        let btn = UIButton(type: .system)
        var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
        let baseFont = italic ? UIFont.italicSystemFont(ofSize: 15) : UIFont.systemFont(ofSize: 15, weight: weight)
        attrs[.font] = baseFont
        if underline { attrs[.underlineStyle]     = NSUnderlineStyle.single.rawValue }
        if strike    { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        btn.setAttributedTitle(NSAttributedString(string: title, attributes: attrs), for: .normal)
        btn.addTarget(self, action: sel, for: .touchUpInside)
        btn.backgroundColor = .clear
        btn.layer.cornerRadius = 7
        btn.layer.masksToBounds = true
        btn.widthAnchor.constraint(equalToConstant: 38).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 38).isActive = true
        stack.addArrangedSubview(btn)
    }

    @discardableResult
    private func addIconBtn(_ stack: UIStackView, sf: String, color: UIColor, sel: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        btn.setImage(UIImage(systemName: sf, withConfiguration: cfg), for: .normal)
        btn.tintColor = color
        btn.addTarget(self, action: sel, for: .touchUpInside)
        btn.backgroundColor = .clear
        btn.layer.cornerRadius = 7
        btn.layer.masksToBounds = true
        btn.widthAnchor.constraint(equalToConstant: 38).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 38).isActive = true
        stack.addArrangedSubview(btn)
        return btn
    }

    // MARK: - Actions

    @objc private func bold()      { coordinator?.applyInlineFormat(.bold)          }
    @objc private func italic()    { coordinator?.applyInlineFormat(.italic)        }
    @objc private func underline() { coordinator?.applyInlineFormat(.underline)     }
    @objc private func strike()    { coordinator?.applyInlineFormat(.strikethrough) }
    @objc private func highlight() { coordinator?.applyInlineFormat(.highlight)     }
    @objc private func code()      { coordinator?.applyInlineFormat(.code)          }
    @objc private func bullet()    { coordinator?.toggleLinePrefix("• ")  }
    @objc private func numbered()  { coordinator?.toggleLinePrefix("1. ") }
    @objc private func task()      { coordinator?.toggleLinePrefix("☐ ")  }
    @objc private func quote()     { coordinator?.toggleLinePrefix("❝ ")  }
    @objc private func heading()   { coordinator?.toggleLinePrefix("# ")  }
    @objc private func table()     { coordinator?.insertTable()            }
    @objc private func mic()       { coordinator?.toggleVoice()            }
    @objc private func dismiss()   { coordinator?.dismissKeyboard()        }
}

struct IOSBlockContentView: View {
    let blocks: [Block]
    let isDark: Bool

    private var ds: JottDS { JottDS(isDark: isDark) }
    private var displayBlocks: [Block] {
        let visible = blocks.filter { block in
            switch block.type {
            case .paragraph, .heading, .bulletItem, .numberedItem, .taskItem, .quote:
                return !block.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default:
                return true
            }
        }
        return visible.isEmpty ? [Block(type: .paragraph, spans: [TextSpan("")])] : visible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(displayBlocks.enumerated()), id: \.element.id) { index, block in
                blockView(block, orderedNumber: orderedNumber(at: index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    private func blockView(_ block: Block, orderedNumber: Int?) -> some View {
        switch block.type {
        case .heading:
            IOSSpansText(spans: block.spans, size: block.level == 1 ? 22 : 18, weight: .semibold, color: ds.ink)
                .padding(.top, 4)
        case .bulletItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(ds.accent).frame(width: 14)
                IOSSpansText(spans: block.spans, size: 15, weight: .regular, color: ds.ink)
            }
        case .numberedItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(orderedNumber ?? 1).")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(ds.inkMute)
                    .frame(width: 24, alignment: .trailing)
                IOSSpansText(spans: block.spans, size: 15, weight: .regular, color: ds.ink)
            }
        case .taskItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(block.checked ? ds.accent : ds.inkMute)
                    .frame(width: 18)
                IOSSpansText(spans: block.spans, size: 15, weight: .regular, color: ds.ink)
            }
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(ds.accent.opacity(0.42)).frame(width: 2)
                IOSSpansText(spans: block.spans, size: 15, weight: .regular, color: ds.inkMute)
            }
        case .table:
            IOSReadOnlyTableBlock(block: block, ds: ds)
        case .divider:
            Rectangle().fill(ds.hairlineMid).frame(height: 1).padding(.vertical, 4)
        default:
            IOSSpansText(spans: block.spans, size: 15, weight: .regular, color: ds.ink)
        }
    }
}

private struct IOSSpansText: View {
    let spans: [TextSpan]
    let size: CGFloat
    let weight: Font.Weight
    let color: Color

    var body: some View {
        Text(attributedText)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        for span in spans.isEmpty ? [TextSpan("")] : spans {
            var value = AttributedString(span.text)
            value.font = span.code ? .system(size: size - 1, design: .monospaced) : .system(size: size, weight: weight)
            value.foregroundColor = color
            if span.underline { value.underlineStyle = .single }
            if span.strikethrough { value.strikethroughStyle = .single }
            if span.highlight { value.backgroundColor = Color.yellow.opacity(0.35) }
            var intent: InlinePresentationIntent = []
            if span.italic { intent.insert(.emphasized) }
            if span.bold  { intent.insert(.stronglyEmphasized) }
            if !intent.isEmpty { value.inlinePresentationIntent = intent }
            result += value
        }
        return result
    }
}

private struct IOSReadOnlyTableBlock: View {
    let block: Block
    let ds: JottDS

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(block.tableHeaders.indices, id: \.self) { col in
                        tableCell(block.tableHeaders[col], isHeader: true)
                    }
                }
                ForEach(block.tableRows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(block.tableHeaders.indices, id: \.self) { col in
                            tableCell(cellValue(row: row, col: col), isHeader: false)
                        }
                    }
                }
            }
            .background(ds.surfaceAlt.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ds.hairlineMid, lineWidth: 0.8))
        }
    }

    private func tableCell(_ text: String, isHeader: Bool) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.jottBody(14, weight: isHeader ? .semibold : .regular))
            .foregroundStyle(isHeader ? ds.ink : ds.inkMute)
            .padding(.horizontal, 10)
            .frame(minWidth: 116, minHeight: 38, alignment: .leading)
            .background(isHeader ? ds.accentSoft : ds.surface)
            .overlay(Rectangle().stroke(ds.hairlineMid, lineWidth: 0.5))
    }

    private func cellValue(row: Int, col: Int) -> String {
        guard block.tableRows.indices.contains(row),
              block.tableRows[row].indices.contains(col) else { return "" }
        return block.tableRows[row][col]
    }
}

// MARK: - Subnote row

struct SubnoteRow: View {
    let note: Note
    let ds: JottDS

    var body: some View {
        let preview = jottNotePreview(note)
        HStack(spacing: 12) {
            Text("•")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ds.accent.opacity(0.50))
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ds.ink)
                    .lineLimit(1)
                if !preview.body.isEmpty {
                    Text(preview.body)
                        .font(.system(size: 12))
                        .foregroundStyle(ds.inkMute)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ds.inkFaintest)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Tag editor sheet

struct IOSTagEditorView: View {
    let initialTags: [String]
    let onSave: ([String]) -> Void

    @State private var tags: [String]
    @State private var newTag: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FocusState private var fieldFocused: Bool

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }
    private var trimmed: String { newTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    init(tags: [String], onSave: @escaping ([String]) -> Void) {
        self.initialTags = tags
        self.onSave = onSave
        self._tags = State(initialValue: tags)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ds.canvas.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    // Input row
                    HStack(spacing: 10) {
                        Image(systemName: "tag")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ds.accent)
                        TextField("Add tag", text: $newTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textFieldStyle(.plain)
                            .font(.jottBody(15))
                            .foregroundStyle(ds.ink)
                            .focused($fieldFocused)
                            .onSubmit { addTag() }
                        if !newTag.isEmpty {
                            Button(action: addTag) {
                                Text("Add")
                                    .font(.jottBody(14, weight: .semibold))
                                    .foregroundStyle(trimmed.isEmpty || tags.contains(trimmed) ? ds.inkFaintest : ds.accent)
                            }
                            .buttonStyle(.plain)
                            .disabled(trimmed.isEmpty || tags.contains(trimmed))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(ds.surface)
                    .overlay(Rectangle().fill(ds.hairline).frame(height: 1), alignment: .bottom)

                    if tags.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tag")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(ds.inkFaintest)
                            Text("No tags yet")
                                .font(.jottBody(15))
                                .foregroundStyle(ds.inkFaint)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 60)
                    } else {
                        List {
                            ForEach(tags, id: \.self) { tag in
                                HStack {
                                    Text("#\(tag)")
                                        .font(.jottBody(15))
                                        .foregroundStyle(ds.ink)
                                    Spacer()
                                }
                                .listRowBackground(ds.surface)
                            }
                            .onDelete { offsets in
                                tags.remove(atOffsets: offsets)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ds.inkMute)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(tags)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(ds.accent)
                }
            }
            .onAppear { fieldFocused = true }
        }
    }

    private func addTag() {
        let t = trimmed
        guard !t.isEmpty, !tags.contains(t) else { return }
        withAnimation { tags.append(t) }
        newTag = ""
    }
}

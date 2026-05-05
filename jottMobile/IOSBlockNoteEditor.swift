import SwiftUI

// MARK: - Block note editor (segmented: text segments interleaved with inline tables)

struct IOSBlockNoteEditor: View {
    @Binding var blocks: [Block]
    let isDark: Bool
    var autoFocus: Bool = false
    var onBlocksChange: (([Block]) -> Void)?

    private var ds: JottDS { JottDS(isDark: isDark) }

    // Each segment = one UITextView + the optional table that follows it
    @State private var segments: [TextSegment] = []
    @State private var scrollToID: UUID? = nil

    private struct TextSegment: Identifiable {
        var id: UUID = UUID()
        var text: String
        var tableBlock: Block?
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(segments.indices, id: \.self) { i in
                        IOSMarkdownEditor(
                            text: textBinding(i),
                            isDark: isDark,
                            autoFocus: autoFocus && i == 0,
                            onTextChange: { _ in syncBlocks() },
                            onInsertTable: { rows, cols in
                                insertTable(atSegment: i, rows: rows, cols: cols)
                            }
                        )
                        .frame(minHeight: i == 0 ? 220 : 80)

                        if let table = segments[i].tableBlock {
                            IOSInlineTableEditor(
                                block: tableBinding(id: table.id),
                                ds: ds,
                                onDelete: { deleteTable(id: table.id) }
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .id(table.id)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .onChange(of: scrollToID) {
                guard let id = scrollToID else { return }
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .bottom) }
                scrollToID = nil
            }
        }
        .onAppear { loadSegments() }
    }

    // MARK: - Segment loading

    private func loadSegments() {
        var segs: [TextSegment] = []
        var textBlocks: [Block] = []
        for block in blocks {
            if block.type == .table {
                segs.append(TextSegment(text: MarkdownConverter.export(textBlocks), tableBlock: block))
                textBlocks = []
            } else {
                textBlocks.append(block)
            }
        }
        segs.append(TextSegment(text: MarkdownConverter.export(textBlocks), tableBlock: nil))
        segments = segs
    }

    // MARK: - Sync to blocks binding

    private func syncBlocks() {
        var result: [Block] = []
        for seg in segments {
            result.append(contentsOf: MarkdownConverter.parse(seg.text))
            if let t = seg.tableBlock { result.append(t) }
        }
        blocks = result
        onBlocksChange?(result)
    }

    // MARK: - Bindings

    private func textBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < segments.count ? segments[i].text : "" },
            set: { if i < segments.count { segments[i].text = $0 } }
        )
    }

    private func tableBinding(id: UUID) -> Binding<Block> {
        Binding(
            get: {
                segments.first(where: { $0.tableBlock?.id == id })?.tableBlock
                    ?? Block(type: .table, tableHeaders: [], tableRows: [])
            },
            set: { newBlock in
                guard let i = segments.firstIndex(where: { $0.tableBlock?.id == id }) else { return }
                segments[i].tableBlock = newBlock
                syncBlocks()
            }
        )
    }

    // MARK: - Table insert / delete

    private func insertTable(atSegment i: Int, rows: Int, cols: Int) {
        guard i < segments.count else { return }
        let newTable = Self.makeTableBlock(rows: rows, columns: cols)
        // The current text segment becomes text-before + new table
        // A fresh empty text segment follows after the table
        segments[i].tableBlock = newTable
        let newSeg = TextSegment(text: "", tableBlock: nil)
        segments.insert(newSeg, at: i + 1)
        syncBlocks()
        scrollToID = newTable.id
    }

    private func deleteTable(id: UUID) {
        guard let i = segments.firstIndex(where: { $0.tableBlock?.id == id }) else { return }
        let nextText = (i + 1 < segments.count) ? segments[i + 1].text : ""
        let nextTable = (i + 1 < segments.count) ? segments[i + 1].tableBlock : nil
        // Merge the following text segment into this one, removing the table
        segments[i].text += nextText.isEmpty ? "" : (segments[i].text.isEmpty ? nextText : "\n\n" + nextText)
        segments[i].tableBlock = nextTable
        if i + 1 < segments.count { segments.remove(at: i + 1) }
        syncBlocks()
    }

    static func makeTableBlock(rows: Int = 2, columns: Int = 2) -> Block {
        let c = max(1, min(columns, 8)), r = max(1, min(rows, 12))
        return Block(
            type: .table,
            tableHeaders: (1...c).map { "Column \($0)" },
            tableRows: Array(repeating: Array(repeating: "", count: c), count: r)
        )
    }
}

// MARK: - Inline table editor

private struct IOSInlineTableEditor: View {
    @Binding var block: Block
    let ds: JottDS
    var onDelete: (() -> Void)?

    private let minColumnWidth: CGFloat = 116
    private let rowHeight: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: icon + spacer + action buttons
            HStack(spacing: 6) {
                Image(systemName: "tablecells")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ds.accent)
                Spacer()
                actionButton("+ Col", action: addColumn)
                actionButton("+ Row", action: addRow)
                Divider().frame(height: 16)
                Button(action: { onDelete?() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ds.inkFaint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(block.tableHeaders.indices, id: \.self) { col in
                            tableField(
                                text: Binding(
                                    get: { block.tableHeaders[col] },
                                    set: { block.tableHeaders[col] = $0 }
                                ),
                                isHeader: true
                            )
                        }
                    }
                    ForEach(block.tableRows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(block.tableHeaders.indices, id: \.self) { col in
                                tableField(
                                    text: Binding(
                                        get: { cellValue(row: row, col: col) },
                                        set: { setCellValue($0, row: row, col: col) }
                                    ),
                                    isHeader: false
                                )
                            }
                        }
                    }
                }
                .background(ds.surfaceAlt.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ds.hairlineMid, lineWidth: 0.8))
            }
        }
        .padding(12)
        .background(ds.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(ds.hairline, lineWidth: 0.8))
    }

    @ViewBuilder
    private func actionButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.jottCaption(12, weight: .semibold))
                .foregroundStyle(ds.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ds.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(ds.accent.opacity(0.20), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func tableField(text: Binding<String>, isHeader: Bool) -> some View {
        TextField(isHeader ? "Column" : "", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.jottBody(14, weight: isHeader ? .semibold : .regular))
            .foregroundStyle(isHeader ? ds.ink : ds.inkMute)
            .padding(.horizontal, 10)
            .frame(minWidth: minColumnWidth, minHeight: rowHeight, alignment: .leading)
            .background(isHeader ? ds.accentSoft : ds.surface)
            .overlay(Rectangle().stroke(ds.hairlineMid, lineWidth: 0.5))
    }

    private func cellValue(row: Int, col: Int) -> String {
        guard block.tableRows.indices.contains(row),
              block.tableRows[row].indices.contains(col) else { return "" }
        return block.tableRows[row][col]
    }

    private func setCellValue(_ value: String, row: Int, col: Int) {
        guard block.tableRows.indices.contains(row) else { return }
        while block.tableRows[row].count <= col { block.tableRows[row].append("") }
        block.tableRows[row][col] = value
    }

    private func addRow() {
        block.tableRows.append(Array(repeating: "", count: block.tableHeaders.count))
    }

    private func addColumn() {
        block.tableHeaders.append("Column \(block.tableHeaders.count + 1)")
        for i in block.tableRows.indices { block.tableRows[i].append("") }
    }
}

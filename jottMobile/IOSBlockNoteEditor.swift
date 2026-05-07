import SwiftUI

// IOSBlockNoteEditor: wraps IOSBlockTextEditor (direct block<->prefix, no markdown)
// and stacks inline table editors below the text area.

struct IOSBlockNoteEditor: View {
    @Binding var blocks: [Block]
    let isDark: Bool
    var autoFocus: Bool = false
    var onBlocksChange: (([Block]) -> Void)?

    private var ds: JottDS { JottDS(isDark: isDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IOSBlockTextEditor(
                blocks: textBlocksBinding,
                isDark: isDark,
                autoFocus: autoFocus,
                onBlocksChange: { _ in onBlocksChange?(blocks) },
                onInsertTable: { rows, cols in insertTable(rows: rows, cols: cols) }
            )

            ForEach(tableIndices, id: \.self) { i in
                IOSInlineTableEditor(
                    block: $blocks[i],
                    ds: ds,
                    onDelete: { deleteTable(id: blocks[i].id) }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Helpers

    private var tableIndices: [Int] {
        blocks.indices.filter { blocks[$0].type == .table }
    }

    private var textBlocksBinding: Binding<[Block]> {
        Binding(
            get: { blocks.filter { $0.type != .table } },
            set: { newText in
                let tables = blocks.filter { $0.type == .table }
                blocks = newText + tables
                onBlocksChange?(blocks)
            }
        )
    }

    private func insertTable(rows: Int, cols: Int) {
        let c = max(1, min(cols, 8)), r = max(1, min(rows, 12))
        let newTable = Block(
            type: .table,
            tableHeaders: (1...c).map { "Column \($0)" },
            tableRows: Array(repeating: Array(repeating: "", count: c), count: r)
        )
        blocks.append(newTable)
        onBlocksChange?(blocks)
    }

    private func deleteTable(id: UUID) {
        blocks.removeAll { $0.id == id }
        onBlocksChange?(blocks)
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

import SwiftUI

func jottDisplayBlocks(from blocks: [Block]) -> [Block] {
    var result: [Block] = []
    var index = 0

    while index < blocks.count {
        if let table = legacyTableBlock(startingAt: index, in: blocks) {
            result.append(table.block)
            index = table.nextIndex
        } else {
            result.append(blocks[index])
            index += 1
        }
    }

    return result
}

private func legacyTableBlock(startingAt index: Int, in blocks: [Block]) -> (block: Block, nextIndex: Int)? {
    var lines: [String] = []
    var cursor = index

    while cursor < blocks.count, let line = legacyTableLine(from: blocks[cursor]) {
        lines.append(line)
        cursor += 1
    }

    guard let table = parseLegacyTable(lines) else { return nil }
    return (Block(type: .table, tableHeaders: table.headers, tableRows: table.rows), cursor)
}

private func legacyTableLine(from block: Block) -> String? {
    switch block.type {
    case .paragraph, .heading, .bulletItem, .numberedItem, .taskItem, .quote:
        let line = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return isLegacyTableLine(line) ? line : nil
    default:
        return nil
    }
}

private func isLegacyTableLine(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|")
}

private func parseLegacyTable(_ lines: [String]) -> (headers: [String], rows: [[String]])? {
    guard lines.count >= 2 else { return nil }
    let headers = tableCells(from: lines[0])
    let separator = tableCells(from: lines[1])
    guard !headers.isEmpty,
          separator.count == headers.count,
          separator.allSatisfy(isSeparatorCell) else { return nil }

    let rows = lines.dropFirst(2).map { line -> [String] in
        var cells = tableCells(from: line)
        while cells.count < headers.count { cells.append("") }
        return Array(cells.prefix(headers.count))
    }
    return (headers, rows)
}

private func tableCells(from line: String) -> [String] {
    var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("|") { value.removeFirst() }
    if value.hasSuffix("|") { value.removeLast() }
    return value.split(separator: "|", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private func isSeparatorCell(_ cell: String) -> Bool {
    let trimmed = cell.trimmingCharacters(in: CharacterSet(charactersIn: " :-"))
    return trimmed.isEmpty && cell.contains("-")
}

struct MDTableView: View {
    let headers: [String]
    let rows: [[String]]
    let isDarkMode: Bool

    private var border: Color { isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.10) }
    private var headerBG: Color { isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.035) }
    private var cellBG: Color { isDarkMode ? Color.white.opacity(0.025) : Color.white.opacity(0.65) }
    private var ink: Color { isDarkMode ? Color(white: 0.92) : Color("jott-input-text") }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        cell(header.isEmpty ? " " : header, isHeader: true)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<headers.count, id: \.self) { index in
                            cell(index < row.count ? row[index] : " ", isHeader: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(border, lineWidth: 1))
        }
        .padding(.vertical, 4)
    }

    private func cell(_ text: String, isHeader: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: isHeader ? .semibold : .regular))
            .foregroundColor(ink)
            .lineLimit(nil)
            .frame(minWidth: 92, maxWidth: 180, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHeader ? headerBG : cellBG)
            .overlay(Rectangle().stroke(border, lineWidth: 0.5))
    }
}

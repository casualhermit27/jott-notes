import Foundation
import NaturalLanguage

// MARK: - Search Result

enum SearchResult: Identifiable {
    case rootNote(Note, score: Double)
    case subnote(Note, parent: Note, score: Double)

    var id: String {
        switch self {
        case .rootNote(let n, _):        return n.id.uuidString
        case .subnote(let n, _, _):      return n.id.uuidString
        }
    }

    var note: Note {
        switch self {
        case .rootNote(let n, _):    return n
        case .subnote(let n, _, _): return n
        }
    }

    var score: Double {
        switch self {
        case .rootNote(_, let s):    return s
        case .subnote(_, _, let s): return s
        }
    }

    var isSubnote: Bool {
        if case .subnote = self { return true }
        return false
    }

    var parentNote: Note? {
        if case .subnote(_, let p, _) = self { return p }
        return nil
    }
}

// MARK: - Search Mode

enum SearchMode: String, CaseIterable, Identifiable {
    case normal   = "Normal"
    case fuzzy    = "Fuzzy"
    case semantic = "Semantic"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .normal:   return "magnifyingglass"
        case .fuzzy:    return "sparkle.magnifyingglass"
        case .semantic: return "brain"
        }
    }

    var shortLabel: String {
        switch self {
        case .normal:   return "Normal"
        case .fuzzy:    return "Fuzzy"
        case .semantic: return "AI"
        }
    }
}

// MARK: - Search Engine

@MainActor
final class SearchEngine {
    static let shared = SearchEngine()

    // Cached sentence embeddings: note id → embedding vector
    private var embeddingCache: [UUID: [Double]] = [:]
    private var cacheVersion: Int = 0

    private init() {}

    /// Main entry point — returns ranked results across root notes + subnotes.
    func search(query: String, store: NoteStore, mode: SearchMode) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let allNotes = store.allNotes()
        var results: [SearchResult] = []

        switch mode {
        case .normal:
            results = normalSearch(query: q, notes: allNotes, store: store)
        case .fuzzy:
            results = fuzzySearch(query: q, notes: allNotes, store: store)
        case .semantic:
            results = semanticSearch(query: q, notes: allNotes, store: store)
        }

        // Sort by score descending, then by modified date
        return results.sorted {
            if abs($0.score - $1.score) > 0.01 { return $0.score > $1.score }
            return $0.note.modifiedAt > $1.note.modifiedAt
        }
    }

    // MARK: - Normal (exact substring)

    private func normalSearch(query: String, notes: [Note], store: NoteStore) -> [SearchResult] {
        let q = query.lowercased()
        var results: [SearchResult] = []

        for note in notes {
            let text = note.text.lowercased()
            let tagHit = note.tags.contains { $0.lowercased().contains(q) }

            if text.contains(q) || tagHit {
                let score = scoreNormal(query: q, note: note)
                if note.parentId == nil {
                    results.append(.rootNote(note, score: score))
                } else if let parent = store.note(for: note.parentId!) {
                    results.append(.subnote(note, parent: parent, score: score))
                }
            }
        }

        return results
    }

    private func scoreNormal(query: String, note: Note) -> Double {
        let text = note.text.lowercased()
        let q = query.lowercased()
        var score = 0.0
        // Title match gets higher score
        let firstLine = text.components(separatedBy: "\n").first ?? ""
        if firstLine.contains(q) { score += 1.0 }
        // Body match
        let occurrences = text.components(separatedBy: q).count - 1
        score += Double(occurrences) * 0.3
        if note.isPinned { score += 0.5 }
        return score
    }

    // MARK: - Fuzzy (bigram overlap + character matching)

    private func fuzzySearch(query: String, notes: [Note], store: NoteStore) -> [SearchResult] {
        let q = query.lowercased()
        var results: [SearchResult] = []
        let threshold = 0.18

        for note in notes {
            let text = noteSearchText(note)
            let score = fuzzyScore(query: q, text: text, note: note)
            guard score >= threshold else { continue }

            if note.parentId == nil {
                results.append(.rootNote(note, score: score))
            } else if let parent = store.note(for: note.parentId!) {
                results.append(.subnote(note, parent: parent, score: score))
            }
        }

        return results
    }

    private func fuzzyScore(query: String, text: String, note: Note) -> Double {
        // 1. Bigram similarity
        let bigramScore = bigramSimilarity(query, text)

        // 2. Sequential character match (fast subsequence check)
        let seqScore = sequenceMatchScore(query: query, in: text)

        // 3. Word prefix match
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        let prefixScore = words.contains { $0.hasPrefix(query) || $0.hasPrefix(query.prefix(3)) } ? 0.4 : 0.0

        var score = bigramScore * 0.5 + seqScore * 0.35 + prefixScore * 0.15
        if note.isPinned { score += 0.1 }
        return score
    }

    private func bigramSimilarity(_ a: String, _ b: String) -> Double {
        guard a.count >= 2, b.count >= 2 else {
            return b.contains(a) ? 0.5 : 0.0
        }
        let bigrams = { (s: String) -> Set<String> in
            var result = Set<String>()
            let chars = Array(s)
            for i in 0..<chars.count - 1 {
                result.insert(String(chars[i...i+1]))
            }
            return result
        }
        let qa = bigrams(a)
        let ba = bigrams(b)
        let intersection = qa.intersection(ba).count
        return Double(2 * intersection) / Double(qa.count + ba.count)
    }

    private func sequenceMatchScore(query: String, in text: String) -> Double {
        let qChars = Array(query)
        let tChars = Array(text)
        var qi = 0
        for ch in tChars {
            if qi < qChars.count && ch == qChars[qi] { qi += 1 }
        }
        return Double(qi) / Double(qChars.count)
    }

    // MARK: - Semantic (NLEmbedding cosine similarity)

    private func semanticSearch(query: String, notes: [Note], store: NoteStore) -> [SearchResult] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            // Fallback to fuzzy if model unavailable
            return fuzzySearch(query: query, notes: notes, store: store)
        }

        var results: [SearchResult] = []
        let threshold = 0.42  // cosine similarity threshold (0=identical, 2=opposite for NL distance)

        for note in notes {
            let text = noteSearchText(note)
            // NLEmbedding.distance returns cosine distance (0–2), lower = more similar
            let distance = embedding.distance(between: query, and: String(text.prefix(512)), distanceType: .cosine)
            let similarity = max(0, 1.0 - Double(distance) / 2.0)  // convert to 0-1 similarity
            guard similarity >= threshold else { continue }

            if note.parentId == nil {
                results.append(.rootNote(note, score: similarity))
            } else if let parent = store.note(for: note.parentId!) {
                results.append(.subnote(note, parent: parent, score: similarity))
            }
        }

        return results
    }

    // MARK: - Helpers

    private func noteSearchText(_ note: Note) -> String {
        let tags = note.tags.joined(separator: " ")
        return "\(note.text) \(tags)".lowercased()
    }
}

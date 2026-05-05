import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - NoteAIService
// On-device LLM via Apple Foundation Models (macOS 26+).
// Works everywhere: Jott bar, library sidebar, note detail editor.

actor NoteAIService {
    static let shared = NoteAIService()
    private init() {}

    private static let contextKey = "jott_aiUserContext"

    // MARK: - User context

    /// Paste your bio, interests, or any personal info here.
    /// Included as context in every prompt so suggestions feel relevant.
    static var userContext: String {
        UserDefaults.standard.string(forKey: contextKey) ?? ""
    }

    static func saveUserContext(_ text: String) {
        UserDefaults.standard.set(text, forKey: contextKey)
    }

    // MARK: - Availability

    private var isAvailable: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
#endif
        return false
    }

    // MARK: - Prompts

    private var contextHeader: String {
        let ctx = Self.userContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ctx.isEmpty else { return "" }
        return "About the user: \(ctx)\n\n"
    }

    /// Generate a 2–4 word title for the given note text.
    func suggestTitle(for text: String) async -> String? {
        guard isAvailable else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return nil }

        let prompt = """
        \(contextHeader)Write a 2-4 word title for this note. Output only the title, no quotes, no trailing punctuation:

        \(String(trimmed.prefix(500)))
        """

        return await run(prompt: prompt) { raw in
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
            return t.isEmpty ? nil : t
        }
    }

    /// Suggest the next 1–4 words as inline ghost text.
    func complete(after text: String) async -> String? {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > 5 else { return nil }
        let corpus = await buildAutocompleteCorpus()
        guard !corpus.tokens.isEmpty else { return nil }
        return suggestInlineCompletion(after: text, corpus: corpus)
    }

    // MARK: - Private

    private func run(prompt: String, transform: (String) -> String?) async -> String? {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                return transform(response.content)
            } catch {
                return nil
            }
        }
#endif
        return nil
    }

    private func buildAutocompleteCorpus() async -> AutocompleteCorpus {
        return await MainActor.run {
            let notes = NoteStore.shared.allNotes()
            let joinedNotes = notes
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(300)
                .map { $0.text }
                .joined(separator: "\n")
            let source = [Self.userContext, joinedNotes]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            return AutocompleteCorpus(source: source)
        }
    }

    private func suggestInlineCompletion(after text: String, corpus: AutocompleteCorpus) -> String? {
        let hasTrailingWhitespace = text.last?.isWhitespace ?? false
        let contextTokens = tokenize(text)
        guard !contextTokens.isEmpty else { return nil }

        if !hasTrailingWhitespace,
           let partial = currentPartialToken(in: text) {
            return completePartialWord(partial, contextTokens: contextTokens, corpus: corpus)
        }

        return predictNextWords(contextTokens: contextTokens, corpus: corpus)
    }

    private func predictNextWords(contextTokens: [String], corpus: AutocompleteCorpus) -> String? {
        var generated: [String] = []
        var workingContext = contextTokens.map { $0.lowercased() }
        let lastTyped = workingContext.last

        for _ in 0..<3 {
            guard let next = bestNextToken(for: workingContext, corpus: corpus, excluding: generated.map { $0.lowercased() }) else {
                break
            }
            if next.lowercased() == lastTyped, generated.isEmpty {
                break
            }
            generated.append(next)
            workingContext.append(next.lowercased())
            if next.count <= 2 { break }
        }

        let suggestion = generated.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return suggestion.isEmpty ? nil : suggestion
    }

    private func completePartialWord(_ partial: String, contextTokens: [String], corpus: AutocompleteCorpus) -> String? {
        let prefix = partial.lowercased()
        guard prefix.count >= 2 else { return nil }

        let previousContext = Array(contextTokens.dropLast()).map { $0.lowercased() }
        let ranked = rankedCandidates(for: previousContext, corpus: corpus)
        if let contextual = ranked.first(where: {
            $0.lowercased().hasPrefix(prefix) && $0.lowercased() != prefix
        }) {
            return String(contextual.dropFirst(prefix.count))
        }

        if let fallback = corpus.tokenFrequency
            .keys
            .sorted(by: { lhs, rhs in
                let lCount = corpus.tokenFrequency[lhs, default: 0]
                let rCount = corpus.tokenFrequency[rhs, default: 0]
                if lCount != rCount { return lCount > rCount }
                return lhs < rhs
            })
            .first(where: { candidate in
                let lowered = candidate.lowercased()
                return lowered.hasPrefix(prefix) && lowered != prefix
            }) {
            return String(fallback.dropFirst(prefix.count))
        }

        return nil
    }

    private func bestNextToken(for contextTokens: [String], corpus: AutocompleteCorpus, excluding excluded: [String]) -> String? {
        rankedCandidates(for: contextTokens, corpus: corpus)
            .first(where: { !excluded.contains($0.lowercased()) })
    }

    private func rankedCandidates(for contextTokens: [String], corpus: AutocompleteCorpus) -> [String] {
        let lowercasedContext = contextTokens.map { $0.lowercased() }
        let contextSizes = [3, 2, 1]

        for size in contextSizes {
            guard lowercasedContext.count >= size else { continue }
            let key = Array(lowercasedContext.suffix(size))
            if let matches = corpus.nextTokenFrequency[key] {
                return matches.sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return lhs.key < rhs.key
                }.map { $0.key }
            }
        }

        return corpus.tokenFrequency
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map { $0.key }
    }

    private func currentPartialToken(in text: String) -> String? {
        let trimmed = text.split(whereSeparator: \.isWhitespace).last.map(String.init)
        guard let trimmed else { return nil }
        let cleaned = trimmed.trimmingCharacters(in: .punctuationCharacters)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct AutocompleteCorpus {
    let tokens: [String]
    let tokenFrequency: [String: Int]
    let nextTokenFrequency: [[String]: [String: Int]]

    init(source: String) {
        let tokenList = source
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        self.tokens = tokenList

        var tokenFrequency: [String: Int] = [:]
        var nextTokenFrequency: [[String]: [String: Int]] = [:]

        for token in tokenList {
            tokenFrequency[token, default: 0] += 1
        }

        let lowered = tokenList.map { $0.lowercased() }
        for index in 0..<lowered.count {
            for contextSize in 1...3 {
                guard index >= contextSize else { continue }
                let key = Array(lowered[(index - contextSize)..<index])
                let next = tokenList[index]
                nextTokenFrequency[key, default: [:]][next, default: 0] += 1
            }
        }

        self.tokenFrequency = tokenFrequency
        self.nextTokenFrequency = nextTokenFrequency
    }
}

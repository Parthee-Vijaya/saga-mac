import Foundation

/// Pure-logic post-processor som anvender vocabulary-entries på en transcript.
///
/// Køres efter Canary-transkription og før mode-routing. Tager en transcript +
/// liste af aktive entries og returnerer den korrigerede transcript.
///
/// Designet uden afhængighed af UserDefaults eller ObservableObject for at være
/// nem at unit-teste isoleret.
public struct VocabularyPostProcessor: Sendable {
    public init() {}

    /// Anvend alle entries på `text` og returnér resultatet.
    /// Entries anvendes i listens rækkefølge — bruger kontrollerer prioritet
    /// ved at sortere i UI.
    public func apply(_ text: String, entries: [VocabularyEntry]) -> String {
        guard !entries.isEmpty else { return text }
        var result = text
        for entry in entries where entry.enabled && entry.isMeaningful {
            result = applyEntry(entry, to: result)
        }
        return result
    }

    /// Anvend en enkelt entry. Eksponeret internt for unit-tests.
    func applyEntry(_ entry: VocabularyEntry, to text: String) -> String {
        let pattern = escapeRegex(entry.pattern)
        let regexBody = entry.wholeWord
            ? "(?<![\\p{L}\\p{N}])\(pattern)(?![\\p{L}\\p{N}])"
            : pattern
        var options: NSRegularExpression.Options = []
        if !entry.caseSensitive {
            options.insert(.caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: regexBody, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: entry.replacement)
        )
    }

    private func escapeRegex(_ str: String) -> String {
        NSRegularExpression.escapedPattern(for: str)
    }
}

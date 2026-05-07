import Foundation

/// Pure-logic expander der erstatter trigger-fraser med multi-line expansions.
///
/// Køres efter vocabulary + filler-strip, før mode-routing. Tager en transcript
/// + liste af aktive snippets og returnerer den ekspanderede transcript.
///
/// Designet uden afhængighed af UserDefaults eller ObservableObject for at være
/// nem at unit-teste isoleret. SnippetStore eier persistens; SnippetExpander er
/// en ren funktion.
public struct SnippetExpander: Sendable {
    public init() {}

    /// Anvend alle snippets på `text` og returnér resultatet.
    public func apply(_ text: String, entries: [Snippet]) -> String {
        guard !entries.isEmpty else { return text }
        var result = text
        for snippet in entries where snippet.enabled && snippet.isMeaningful {
            result = applySnippet(snippet, to: result)
        }
        return result
    }

    /// Anvend en enkelt snippet. Eksponeret internt for unit-tests.
    func applySnippet(_ snippet: Snippet, to text: String) -> String {
        let trimmedTrigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrigger.isEmpty else { return text }

        // Match som hele frase med word boundaries — undgår at fx "min sig"
        // ved et tilfælde rammer "minsig...". Word boundaries i ICU-regex er
        // ustabile for danske tegn, så vi bruger explicit lookaround for
        // begin-of-string + whitespace + punktuation.
        let escaped = NSRegularExpression.escapedPattern(for: trimmedTrigger)
        var options: NSRegularExpression.Options = []
        if !snippet.caseSensitive {
            options.insert(.caseInsensitive)
        }

        // Pattern: trigger som hel frase, omsluttet af begin/end-of-string
        // eller whitespace/punktuation.
        let pattern = "(?<=^|[\\s,.;:!?])\(escaped)(?=$|[\\s,.;:!?])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        // Escape replacement-strengen for regex-template-syntaks ($1, \\, osv.)
        let safeExpansion = NSRegularExpression.escapedTemplate(for: snippet.expansion)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: safeExpansion)
    }
}

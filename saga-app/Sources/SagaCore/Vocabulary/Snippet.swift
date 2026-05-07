import Foundation

/// En voice-snippet — kort trigger-frase der erstattes med en længere
/// tekst-blok når den genkendes i transcript.
///
/// Eksempel: trigger "min sig" → expansion "Med venlig hilsen,\nParthee Vijaya".
///
/// Forskel fra VocabularyEntry: Vocabulary er ord-til-ord (rettelser),
/// Snippets er trigger-frase → multi-line tekstblok. Snippets kører efter
/// vocabulary + filler-strip, men før mode-routing.
public struct Snippet: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var trigger: String
    public var expansion: String
    public var caseSensitive: Bool
    public var enabled: Bool
    public var notes: String

    public init(
        id: UUID = UUID(),
        trigger: String,
        expansion: String,
        caseSensitive: Bool = false,
        enabled: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.caseSensitive = caseSensitive
        self.enabled = enabled
        self.notes = notes
    }

    /// True hvis snippet har et ikke-tomt trigger og en expansion der adskiller
    /// sig fra trigger.
    public var isMeaningful: Bool {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTrigger.isEmpty
            && !trimmedExpansion.isEmpty
            && trimmedTrigger != trimmedExpansion
    }
}

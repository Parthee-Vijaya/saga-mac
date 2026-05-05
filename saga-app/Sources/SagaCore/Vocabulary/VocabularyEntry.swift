import Foundation

/// En enkelt vocabulary-replacement-regel.
///
/// Bruges som post-processing efter Canary-transkription, før mode-routing.
/// Eksempel: ASR misforstår "xcodegen" som "x-code-jen" — bruger tilføjer
/// en entry der mapper "x-code-jen" → "xcodegen".
public struct VocabularyEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var pattern: String
    public var replacement: String
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var enabled: Bool

    /// Valgfri note — bruger kan dokumentere hvorfor reglen findes.
    public var notes: String

    public init(
        id: UUID = UUID(),
        pattern: String,
        replacement: String,
        caseSensitive: Bool = false,
        wholeWord: Bool = true,
        enabled: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.enabled = enabled
        self.notes = notes
    }

    /// True hvis pattern er ikke-tom og forskellig fra replacement —
    /// undgår no-op entries der bare koster compute.
    public var isMeaningful: Bool {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedPattern.isEmpty && trimmedPattern != trimmedReplacement
    }
}

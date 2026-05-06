import Foundation

/// Per-app override af Saga-adfærd. Når brugeren holder push-to-talk i fx
/// Mail, kan vi automatisk anvende "format" mode på transcript'et, så hver
/// dictation bliver poleret tekst i stedet for rå dansk.
public struct AppProfile: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var bundleIdentifier: String
    public var displayName: String

    /// Mode-ID der altid prepended som trigger på transcript før mode-routing.
    /// Eksempel: "format" → "ryd op: " prepended → ModeRouter matcher format-mode.
    /// nil = ingen forced mode (bruger styrer via egne triggers).
    public var forcedModeId: String?

    /// Stenograf-override:
    /// - nil: brug global setting
    /// - true: ALTID stenograf for denne app (skip alt LLM-routing)
    /// - false: ALDRIG stenograf for denne app (selv hvis global er ON)
    public var stenografOverride: Bool?

    /// Sprog-override: hvis sat, bruger Saga dette sprog til transkription
    /// i stedet for det globale activeLanguage. Værdien er rawValue af
    /// SagaLanguage (fx "danish", "english", "tamil"). nil = brug global.
    /// Eksempel: WhatsApp altid tamilsk, Slack altid engelsk.
    public var languageCode: String?

    /// Bruger-aktiveret. Disabled profiler ignoreres ved lookup.
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        forcedModeId: String? = nil,
        stenografOverride: Bool? = nil,
        languageCode: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.forcedModeId = forcedModeId
        self.stenografOverride = stenografOverride
        self.languageCode = languageCode
        self.enabled = enabled
    }
}

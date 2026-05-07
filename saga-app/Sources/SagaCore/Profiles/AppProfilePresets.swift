import Foundation

/// Pre-defined app-profil-forslag som brugeren kan tilføje med ét klik
/// uden at kende bundle-IDs eller skulle finde dem manuelt.
///
/// Hver preset er en sensible default — fx Mail → format-mode (rydder op
/// i tegnsætning), Slack → no mode (casual rå tekst), Xcode → vibecode.
/// Brugeren kan altid redigere efterfølgende.
public struct AppProfilePreset: Identifiable, Sendable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let displayName: String
    public let suggestedModeId: String?
    public let stenografOverride: Bool?
    public let icon: String  // SF Symbol
    public let rationale: String
}

public enum AppProfilePresets {
    /// Sorteret efter relevans/popularitet. Kan udvides over tid.
    public static let all: [AppProfilePreset] = [
        // === Email-apps → format-mode (rydder op i tone) ===
        AppProfilePreset(
            bundleIdentifier: "com.apple.mail",
            displayName: "Mail",
            suggestedModeId: "format",
            stenografOverride: nil,
            icon: "envelope.fill",
            rationale: "Formatér til email-tone — tegnsætning, store bogstaver, ingen fyldord"
        ),
        AppProfilePreset(
            bundleIdentifier: "com.microsoft.Outlook",
            displayName: "Outlook",
            suggestedModeId: "format",
            stenografOverride: nil,
            icon: "envelope.fill",
            rationale: "Formatér til email-tone"
        ),

        // === Notes / dokumenter → format-mode ===
        AppProfilePreset(
            bundleIdentifier: "com.apple.Notes",
            displayName: "Notes",
            suggestedModeId: "format",
            stenografOverride: nil,
            icon: "note.text",
            rationale: "Polér rå dictation til pænt skrevne noter"
        ),
        AppProfilePreset(
            bundleIdentifier: "com.apple.iWork.Pages",
            displayName: "Pages",
            suggestedModeId: "format",
            stenografOverride: nil,
            icon: "doc.text",
            rationale: "Formatér dictation til dokument-tekst"
        ),
        AppProfilePreset(
            bundleIdentifier: "com.microsoft.Word",
            displayName: "Word",
            suggestedModeId: "format",
            stenografOverride: nil,
            icon: "doc.text",
            rationale: "Formatér dictation til dokument-tekst"
        ),

        // === Chat / casual → stenograf (rå dictation, ingen LLM) ===
        AppProfilePreset(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            displayName: "Slack",
            suggestedModeId: nil,
            stenografOverride: true,
            icon: "bubble.left.and.bubble.right",
            rationale: "Stenograf — casual chat-tone uden LLM-cleanup"
        ),
        AppProfilePreset(
            bundleIdentifier: "com.discord.discord",
            displayName: "Discord",
            suggestedModeId: nil,
            stenografOverride: true,
            icon: "bubble.left.and.bubble.right",
            rationale: "Stenograf — casual chat"
        ),
        AppProfilePreset(
            bundleIdentifier: "com.apple.MobileSMS",
            displayName: "Beskeder",
            suggestedModeId: nil,
            stenografOverride: true,
            icon: "message.fill",
            rationale: "Stenograf — kort SMS-tone"
        ),
        AppProfilePreset(
            bundleIdentifier: "net.whatsapp.WhatsApp",
            displayName: "WhatsApp",
            suggestedModeId: nil,
            stenografOverride: true,
            icon: "message.fill",
            rationale: "Stenograf — casual chat"
        ),

        // === Code editors → vibecode-mode ===
        AppProfilePreset(
            bundleIdentifier: "com.apple.dt.Xcode",
            displayName: "Xcode",
            suggestedModeId: "vibecode",
            stenografOverride: nil,
            icon: "hammer.fill",
            rationale: "Vibecode — fortolkninger til kommentar/instruktion"
        ),
        AppProfilePreset(
            bundleIdentifier: "com.microsoft.VSCode",
            displayName: "VS Code",
            suggestedModeId: "vibecode",
            stenografOverride: nil,
            icon: "chevron.left.forwardslash.chevron.right",
            rationale: "Vibecode — fortolkninger til kommentar/instruktion"
        ),
        AppProfilePreset(
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            displayName: "Cursor",
            suggestedModeId: "vibecode",
            stenografOverride: nil,
            icon: "chevron.left.forwardslash.chevron.right",
            rationale: "Vibecode — instruktioner til AI"
        ),
        AppProfilePreset(
            bundleIdentifier: "com.anthropic.claudefordesktop",
            displayName: "Claude",
            suggestedModeId: nil,
            stenografOverride: true,
            icon: "sparkles",
            rationale: "Stenograf — direkte spørgsmål uden LLM-cleanup"
        ),

        // === LinkedIn (webapp i browser, men hvis du har desktop-app) ===
        AppProfilePreset(
            bundleIdentifier: "com.linkedin.LinkedIn",
            displayName: "LinkedIn",
            suggestedModeId: "linkedin",
            stenografOverride: nil,
            icon: "person.crop.square",
            rationale: "LinkedIn-mode — professionel post-tone"
        ),
    ]

    /// Filter ud presets brugeren ALLEREDE har en profil for.
    public static func unused(existing: [AppProfile]) -> [AppProfilePreset] {
        let existingIds = Set(existing.map { $0.bundleIdentifier })
        return all.filter { !existingIds.contains($0.bundleIdentifier) }
    }
}

import Foundation
import OSLog

/// Tager raw transcribed tekst og afgør om der er en mode-trigger;
/// hvis ja, sender den til LM Studio med system-prompt'en for den mode.
/// Hvis nej, returneres teksten uændret (pure dictation).
@MainActor
public final class ModeRouter {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "modes")

    public var modes: [Mode] = Mode.builtins
    public var enabled: Set<String> = Set(Mode.builtins.map { $0.id })

    public init() {}

    public func route(text: String, controller: SagaController) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let match = matchMode(in: trimmed) {
            log.info("Match: mode=\(match.mode.id), payload=\(match.payload.prefix(80))")
            return try await match.mode.run(payload: match.payload, controller: controller)
        }

        // Ingen mode → pure dictation
        return trimmed
    }

    private func matchMode(in text: String) -> (mode: Mode, payload: String)? {
        let lower = text.lowercased()
        for mode in modes where enabled.contains(mode.id) {
            for trigger in mode.triggers {
                if lower.hasPrefix(trigger.lowercased()) {
                    let payload = String(text.dropFirst(trigger.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,.:"))
                    return (mode, payload)
                }
            }
        }
        return nil
    }
}

public struct Mode: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let triggers: [String]
    public let systemPrompt: String
    public let temperature: Double

    public init(id: String, title: String, triggers: [String], systemPrompt: String, temperature: Double = 0.3) {
        self.id = id
        self.title = title
        self.triggers = triggers
        self.systemPrompt = systemPrompt
        self.temperature = temperature
    }

    @MainActor
    public func run(payload: String, controller: SagaController) async throws -> String {
        let result = try await controller.lmStudio.chat(
            system: systemPrompt,
            user: payload,
            temperature: temperature
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static let builtins: [Mode] = [
        Mode(
            id: "translate.en",
            title: "Oversæt til engelsk",
            triggers: ["oversæt til engelsk", "oversæt til engelsk:", "translate to english"],
            systemPrompt: "Oversæt brugerens danske tekst til naturligt engelsk. Returnér KUN den oversatte tekst, ingen forklaringer."
        ),
        Mode(
            id: "translate.da",
            title: "Oversæt til dansk",
            triggers: ["oversæt til dansk", "oversæt til dansk:"],
            systemPrompt: "Oversæt brugerens tekst til naturligt dansk. Returnér KUN den oversatte tekst, ingen forklaringer."
        ),
        Mode(
            id: "format",
            title: "Formatér dictation",
            triggers: ["formatér", "format", "ryd op:"],
            systemPrompt: "Du modtager rå dansk dictation. Tilføj tegnsætning, store bogstaver, ryd op i fyldord (\"øh\", gentagelser), men bevar betydning og stemme. Returnér KUN den polerede tekst."
        ),
        Mode(
            id: "summarize",
            title: "Opsummer",
            triggers: ["opsummer", "opsummér", "tl;dr"],
            systemPrompt: "Lav en kort dansk opsummering af brugerens tekst — max 3 punkter eller 2 sætninger. Returnér KUN opsummeringen."
        ),
        Mode(
            id: "vibecode",
            title: "Vibe-code prompt",
            triggers: ["kode:", "code:", "vibecode:"],
            systemPrompt: """
            Du er en prompt-engineer. Brugeren beskriver en feature på dansk. Lav en præcis,
            teknisk specifikation på engelsk til en AI-coding-agent (som Claude Code eller
            Lovable). Inkludér: 1) goal, 2) constraints, 3) acceptance criteria, 4) hint om
            tech-stack hvis relevant. Returnér KUN prompt'en, ingen forklaring rundt.
            """
        ),
        Mode(
            id: "linkedin",
            title: "LinkedIn-post",
            triggers: ["linkedin:", "linkedin-post:"],
            systemPrompt: """
            Lav et LinkedIn-opslag på dansk baseret på brugerens råudkast.
            Stil: professionel, men personlig og konkret. Max 1200 tegn. Brug enkelte
            line-breaks for læsbarhed. Slut ikke med hashtag-spam — max 3 relevante tags.
            Returnér KUN opslaget.
            """
        ),
    ]
}

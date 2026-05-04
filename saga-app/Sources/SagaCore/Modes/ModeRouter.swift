import Foundation
import OSLog

/// Tager raw transcribed tekst og afgør om der er en mode-trigger;
/// hvis ja, sender den til LM Studio med system-prompt'en for den mode.
/// Hvis nej, returneres teksten uændret (pure dictation).
@MainActor
public final class ModeRouter: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "modes")
    private let storageKey = "modeRouter.disabled"

    public var modes: [Mode] = Mode.builtins

    /// Sættet af mode-IDer brugeren har slået FRA. Default = ingen er fra.
    /// Gemmes i UserDefaults som komma-separeret string.
    @Published public private(set) var disabled: Set<String> = []

    /// Hvilken mode (hvis nogen) der lige nu kører — bruges af HUD.
    @Published public private(set) var activeMode: Mode? = nil

    public init() {
        loadDisabled()
    }

    public func isEnabled(_ mode: Mode) -> Bool {
        !disabled.contains(mode.id)
    }

    /// Tjek hurtigt om en tekst ville matche en mode — uden at kalde LM Studio.
    /// Bruges af UI til at vise hvilken mode der er ved at blive aktiveret.
    public func previewMatch(for text: String) -> Mode? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ReminderMode.matches(trimmed).matched {
            return Mode(id: "reminder", title: "Reminder", triggers: ReminderMode.triggers, systemPrompt: "")
        }
        return matchMode(in: trimmed)?.mode
    }

    public func setEnabled(_ enabled: Bool, for mode: Mode) {
        if enabled {
            disabled.remove(mode.id)
        } else {
            disabled.insert(mode.id)
        }
        persistDisabled()
    }

    public func route(text: String, controller: SagaController) async throws -> RouteResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return RouteResult(text: "", mode: nil) }

        // Reminder-mode er special-cased: håndteres af ReminderMode i stedet for
        // at gå gennem den generiske LLM-chat (kræver JSON-parsing + scheduling)
        let reminderMatch = ReminderMode.matches(trimmed)
        if reminderMatch.matched {
            log.info("Match: reminder, payload=\(reminderMatch.payload.prefix(80))")
            let reminderModeMarker = Mode(
                id: "reminder",
                title: "Reminder",
                triggers: ReminderMode.triggers,
                systemPrompt: ""
            )
            activeMode = reminderModeMarker
            defer { activeMode = nil }
            do {
                let confirmation = try await ReminderMode.run(payload: reminderMatch.payload, controller: controller)
                return RouteResult(text: confirmation, mode: reminderModeMarker)
            } catch {
                throw ModeError.lmStudioFailed(rawTranscript: trimmed, underlying: error)
            }
        }

        guard let match = matchMode(in: trimmed) else {
            // Ingen mode → pure dictation
            return RouteResult(text: trimmed, mode: nil)
        }

        log.info("Match: mode=\(match.mode.id), payload=\(match.payload.prefix(80))")
        activeMode = match.mode
        defer { activeMode = nil }

        do {
            let processed = try await match.mode.run(payload: match.payload, controller: controller)
            return RouteResult(text: processed, mode: match.mode)
        } catch {
            log.error("Mode \(match.mode.id) fejlede: \(error.localizedDescription, privacy: .public)")
            throw ModeError.lmStudioFailed(rawTranscript: trimmed, underlying: error)
        }
    }

    private func matchMode(in text: String) -> (mode: Mode, payload: String)? {
        let lower = text.lowercased()
        for mode in modes where !disabled.contains(mode.id) {
            for trigger in mode.triggers {
                if lower.hasPrefix(trigger.lowercased()) {
                    let payload = String(text.dropFirst(trigger.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,.:"))
                    return (mode, payload)
                }
            }
        }
        return nil
    }

    // MARK: - Persistence

    private func loadDisabled() {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        disabled = Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func persistDisabled() {
        let joined = disabled.sorted().joined(separator: ",")
        UserDefaults.standard.set(joined, forKey: storageKey)
    }
}

public struct RouteResult: Sendable {
    public let text: String
    public let mode: Mode?

    public var modeApplied: Bool { mode != nil }
}

public enum ModeError: Error, LocalizedError {
    case lmStudioFailed(rawTranscript: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .lmStudioFailed(_, let underlying):
            return "LM Studio fejlede: \(underlying.localizedDescription). Start LM Studio og prøv igen."
        }
    }

    /// Den rå tekst som fallback — Saga kan injecte det i stedet for at fejle helt.
    public var fallbackText: String? {
        switch self {
        case .lmStudioFailed(let raw, _): return raw
        }
    }
}

public struct Mode: Identifiable, Sendable, Hashable {
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

    public static func == (lhs: Mode, rhs: Mode) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

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

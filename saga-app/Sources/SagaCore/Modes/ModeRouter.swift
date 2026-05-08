import Foundation
import OSLog

/// Tager raw transcribed tekst og afgør om der er en mode-trigger;
/// hvis ja, sender den til LM Studio med system-prompt'en for den mode.
/// Hvis nej, returneres teksten uændret (pure dictation).
@MainActor
public final class ModeRouter: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "modes")
    private let disabledStorageKey = "modeRouter.disabled"
    private let customStorageKey = "modeRouter.custom"
    private let selectionReader = SelectionReader()

    /// Custom modes oprettet af brugeren. Persisteret som JSON i UserDefaults.
    @Published public private(set) var custom: [Mode] = []

    /// Alle modes — built-ins + custom. Custom kommer efter built-ins så
    /// trigger-matching tjekker built-ins først (mindre risiko for konflikt).
    public var modes: [Mode] {
        Mode.builtins + custom
    }

    /// Sættet af mode-IDer brugeren har slået FRA. Default = ingen er fra.
    /// Gemmes i UserDefaults som komma-separeret string.
    @Published public private(set) var disabled: Set<String> = []

    /// Hvilken mode (hvis nogen) der lige nu kører — bruges af HUD.
    @Published public private(set) var activeMode: Mode? = nil

    public init() {
        loadDisabled()
        loadCustom()
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
        if CalendarMode.matches(trimmed).matched {
            return Mode(id: "calendar", title: "Kalender", triggers: CalendarMode.triggers, systemPrompt: "")
        }
        if VisionMode.matches(trimmed).matched {
            return Mode(id: "vision", title: "Vision", triggers: VisionMode.triggers, systemPrompt: "")
        }
        if OdinMode.matches(trimmed).matched {
            return Mode(id: "odin", title: "Odin", triggers: OdinMode.triggers, systemPrompt: "")
        }
        // EditMode preview kræver kun trigger-match. Faktisk aktivering tjekker
        // også at der findes en selection — men her ved preview ved vi ikke om
        // brugeren har markeret noget endnu på tale-tidspunktet.
        if EditMode.matches(trimmed).matched {
            return Mode(id: "edit", title: "Edit", triggers: EditMode.triggers, systemPrompt: "")
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

        // Reminder-mode er special-cased
        let reminderMatch = ReminderMode.matches(trimmed)
        if reminderMatch.matched {
            log.info("Match: reminder, payload=\(reminderMatch.payload.prefix(80))")
            let marker = Mode(id: "reminder", title: "Reminder", triggers: ReminderMode.triggers, systemPrompt: "")
            activeMode = marker
            defer { activeMode = nil }
            do {
                let confirmation = try await ReminderMode.run(payload: reminderMatch.payload, controller: controller)
                return RouteResult(text: confirmation, mode: marker)
            } catch {
                throw ModeError.lmStudioFailed(rawTranscript: trimmed, underlying: error)
            }
        }

        // Calendar-mode er special-cased — opretter EKEvent direkte i Apple Kalender
        let calendarMatch = CalendarMode.matches(trimmed)
        if calendarMatch.matched {
            log.info("Match: calendar, payload=\(calendarMatch.payload.prefix(80))")
            let marker = Mode(id: "calendar", title: "Kalender", triggers: CalendarMode.triggers, systemPrompt: "")
            activeMode = marker
            defer { activeMode = nil }
            do {
                let confirmation = try await CalendarMode.run(payload: calendarMatch.payload, controller: controller)
                return RouteResult(text: confirmation, mode: marker)
            } catch {
                throw ModeError.lmStudioFailed(rawTranscript: trimmed, underlying: error)
            }
        }

        // Vision-mode er special-cased — kræver screen-capture + multi-modal LLM
        let visionMatch = VisionMode.matches(trimmed)
        if visionMatch.matched {
            log.info("Match: vision, payload=\(visionMatch.payload.prefix(80))")
            let marker = Mode(id: "vision", title: "Vision", triggers: VisionMode.triggers, systemPrompt: "")
            activeMode = marker
            defer { activeMode = nil }
            do {
                let description = try await VisionMode.run(payload: visionMatch.payload, controller: controller)
                return RouteResult(text: description, mode: marker)
            } catch {
                throw ModeError.lmStudioFailed(rawTranscript: trimmed, underlying: error)
            }
        }

        // Odin-mode er special-cased — kalder Odin RAG-daemon (port 3838) i stedet
        // for LM Studio og inserter top-3 hits ved cursor.
        let odinMatch = OdinMode.matches(trimmed)
        if odinMatch.matched {
            log.info("Match: odin, query=\(odinMatch.query.prefix(80))")
            let marker = Mode(id: "odin", title: "Odin", triggers: OdinMode.triggers, systemPrompt: "")
            activeMode = marker
            defer { activeMode = nil }
            do {
                let result = try await OdinMode.run(query: odinMatch.query, controller: controller)
                return RouteResult(text: result, mode: marker)
            } catch {
                throw ModeError.lmStudioFailed(rawTranscript: trimmed, underlying: error)
            }
        }

        // Edit-mode er special-cased — kræver markeret tekst i frontmost app.
        // Hvis trigger matches men selection er tom, falder vi tilbage til
        // normal mode-routing for at undgå at sende tom payload til LLM.
        let editMatch = EditMode.matches(trimmed)
        if editMatch.matched, let selection = selectionReader.currentSelection() {
            log.info("Match: edit, instruction=\(editMatch.instruction.prefix(80))")
            let marker = Mode(id: "edit", title: "Edit", triggers: EditMode.triggers, systemPrompt: "")
            activeMode = marker
            defer { activeMode = nil }
            do {
                let edited = try await EditMode.run(
                    selection: selection,
                    instruction: editMatch.instruction,
                    controller: controller
                )
                return RouteResult(text: edited, mode: marker)
            } catch {
                throw ModeError.lmStudioFailed(rawTranscript: trimmed, underlying: error)
            }
        }

        guard let match = matchMode(in: trimmed) else {
            // Ingen trigger matchede. Fallback: hvis transcripten LIGNER en
            // reminder/calendar-anmodning (heuristik på tids- og handlings-
            // keywords), spørg LLM. Canary mishører ofte trigger-fraser
            // (fx "mind mig om" → "Det regnede"), så streng prefix-match
            // alene er ikke pålidelig.
            if IntentClassifier.looksLikeIntent(trimmed) {
                let intent = await IntentClassifier.classify(trimmed, controller: controller)
                switch intent {
                case .reminder:
                    log.info("Intent-fallback: reminder")
                    let marker = Mode(id: "reminder", title: "Reminder", triggers: ReminderMode.triggers, systemPrompt: "")
                    activeMode = marker
                    defer { activeMode = nil }
                    do {
                        let confirmation = try await ReminderMode.run(payload: trimmed, controller: controller)
                        return RouteResult(text: confirmation, mode: marker)
                    } catch {
                        throw ModeError.lmStudioFailed(rawTranscript: trimmed, underlying: error)
                    }
                case .calendar:
                    log.info("Intent-fallback: calendar")
                    let marker = Mode(id: "calendar", title: "Kalender", triggers: CalendarMode.triggers, systemPrompt: "")
                    activeMode = marker
                    defer { activeMode = nil }
                    do {
                        let confirmation = try await CalendarMode.run(payload: trimmed, controller: controller)
                        return RouteResult(text: confirmation, mode: marker)
                    } catch {
                        throw ModeError.lmStudioFailed(rawTranscript: trimmed, underlying: error)
                    }
                case .dictation:
                    return RouteResult(text: trimmed, mode: nil)
                }
            }
            // Ingen heuristik-match → pure dictation
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

    // MARK: - Custom modes

    public func addCustom(_ mode: Mode) {
        // Forhindrer duplicate-IDer
        custom.removeAll { $0.id == mode.id }
        custom.append(mode)
        persistCustom()
        log.info("Custom mode tilføjet: \(mode.id, privacy: .public)")
    }

    public func updateCustom(_ mode: Mode) {
        if let idx = custom.firstIndex(where: { $0.id == mode.id }) {
            custom[idx] = mode
            persistCustom()
            log.info("Custom mode opdateret: \(mode.id, privacy: .public)")
        }
    }

    public func deleteCustom(id: String) {
        custom.removeAll { $0.id == id }
        disabled.remove(id)
        persistCustom()
        persistDisabled()
        log.info("Custom mode slettet: \(id, privacy: .public)")
    }

    public func isCustom(_ mode: Mode) -> Bool {
        custom.contains(where: { $0.id == mode.id })
    }

    /// Generér unique ID til en ny custom mode baseret på title.
    public func generateCustomID(from title: String) -> String {
        let slug = title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        var id = "custom.\(slug)"
        var counter = 1
        while custom.contains(where: { $0.id == id }) || Mode.builtins.contains(where: { $0.id == id }) {
            counter += 1
            id = "custom.\(slug)-\(counter)"
        }
        return id
    }

    // MARK: - Persistence

    private func loadDisabled() {
        let raw = UserDefaults.standard.string(forKey: disabledStorageKey) ?? ""
        disabled = Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func persistDisabled() {
        let joined = disabled.sorted().joined(separator: ",")
        UserDefaults.standard.set(joined, forKey: disabledStorageKey)
    }

    private func loadCustom() {
        guard let data = UserDefaults.standard.data(forKey: customStorageKey) else { return }
        do {
            custom = try JSONDecoder().decode([Mode].self, from: data)
        } catch {
            log.warning("Kunne ikke læse custom modes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistCustom() {
        do {
            let data = try JSONEncoder().encode(custom)
            UserDefaults.standard.set(data, forKey: customStorageKey)
        } catch {
            log.warning("Kunne ikke gemme custom modes: \(error.localizedDescription, privacy: .public)")
        }
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

public struct ModeExample: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var input: String
    public var output: String

    public init(id: UUID = UUID(), input: String = "", output: String = "") {
        self.id = id
        self.input = input
        self.output = output
    }

    /// Eksemplet er meningsfuldt kun hvis BÅDE input og output har indhold.
    public var isMeaningful: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct Mode: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let title: String
    public let triggers: [String]
    public let systemPrompt: String
    public let temperature: Double
    /// Multi-shot examples: input/output-par der gives LLM som few-shot
    /// learning. Default tom array (zero-shot). Kun meaningful examples
    /// (begge felter ikke-tomme) sendes til LLM.
    public let examples: [ModeExample]

    public init(
        id: String,
        title: String,
        triggers: [String],
        systemPrompt: String,
        temperature: Double = 0.3,
        examples: [ModeExample] = []
    ) {
        self.id = id
        self.title = title
        self.triggers = triggers
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.examples = examples
    }

    // Backwards-compat decode for modes gemt før examples-feltet eksisterede
    private enum CodingKeys: String, CodingKey {
        case id, title, triggers, systemPrompt, temperature, examples
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.triggers = try c.decode([String].self, forKey: .triggers)
        self.systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        self.temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.3
        self.examples = try c.decodeIfPresent([ModeExample].self, forKey: .examples) ?? []
    }

    @MainActor
    public func run(payload: String, controller: SagaController) async throws -> String {
        let meaningfulExamples = examples.filter { $0.isMeaningful }
        let result = try await controller.lmStudio.chat(
            system: systemPrompt,
            user: payload,
            temperature: temperature,
            maxTokens: 4000,
            examples: meaningfulExamples
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

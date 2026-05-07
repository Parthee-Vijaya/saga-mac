import Foundation
import OSLog

/// Reminder-mode: parser brugerens dansk-naturlige tekst via LM Studio for at
/// ekstrahere `{ trigger_iso8601, title, body }`, skemalægger via
/// ReminderEngine og returnerer en bekræftelses-tekst til cursor-injection.
@MainActor
public enum ReminderMode {
    private static let log = Logger(subsystem: "dk.parthee.saga", category: "reminder-mode")

    public static let triggers: [String] = [
        // Korrekt dansk
        "mind mig om",
        "mind mig om at",
        "mind mig på",
        // Canary ASR-mishør: "mind" tolkes ofte som "minde" eller "minder"
        "minde mig om",
        "minde mig om at",
        "minder mig om",
        "minder mig om at",
        // Alternative formuleringer
        "påmind mig om",
        "påmind mig",
        "påmindelse:",
        "reminder:",
        // Engelsk
        "remind me to",
        "remind me about",
    ]

    public static func matches(_ text: String) -> (matched: Bool, payload: String) {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for trigger in triggers {
            if lower.hasPrefix(trigger.lowercased()) {
                let payload = String(text.dropFirst(trigger.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:"))
                return (true, payload)
            }
        }
        return (false, text)
    }

    public static let systemPromptTemplate: String = """
    Du parser dansk reminder-tekst og returnerer KUN gyldig JSON i præcis dette format:
    {"trigger_iso8601": "YYYY-MM-DDTHH:MM", "title": "kort titel", "body": "evt. detaljer"}

    Regler:
    - trigger_iso8601 er ALTID i lokal tid (Europa/København), ingen tidszone-suffix
    - Hvis ikke andet specificeret: brug klokken 09:00 for "i morgen" eller weekend-dage
    - "i dag kl 14" → i dag (givet dato) kl 14:00
    - "i morgen kl 7:30" → i morgen kl 07:30
    - "om 10 minutter" → nu + 10 min
    - "på fredag" / "næste fredag" → næste forekomst af den ugedag
    - title bør være en kort imperativ ("Ring til Lars", "Send rapport", "Møde med Anna")
    - body kan være tom eller indeholde detaljer fra brugerens tekst
    - Hvis du ikke kan parse tidspunkt: returnér {"error": "kunne ikke forstå tidspunkt"}

    Aktuel dato/tid (lokal): %@

    Returnér KUN JSON. Ingen forklaring, ingen markdown-kodeblock, ingen ekstra tekst.
    """

    /// Kør parse + schedule. Returnerer confirmation-streng til cursor-injection.
    public static func run(payload: String, controller: SagaController) async throws -> String {
        guard !payload.isEmpty else {
            throw ReminderError.parseFailed("Tom reminder-payload")
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let nowString = isoFormatter.string(from: Date())
        let systemPrompt = String(format: systemPromptTemplate, nowString)

        // maxTokens 4000 — giver reasoning-modeller (gemma-4-26b-a4b,
        // gpt-oss-20b m.fl.) plads til BÅDE intern tænkning OG faktisk JSON-output.
        // Lav værdi (256) gjorde at reasoning brugte alle tokens og content endte
        // tom → modeError + fallback til rå-transkription.
        let raw = try await controller.lmStudio.chat(
            system: systemPrompt,
            user: payload,
            temperature: 0.1,
            maxTokens: 4000
        )
        log.debug("LLM raw: \(raw, privacy: .public)")

        let parsed = try parseLLMResponse(raw)
        let reminder = try await controller.reminders.schedule(
            title: parsed.title,
            body: parsed.body,
            fireAt: parsed.fireAt
        )

        return formatConfirmation(reminder)
    }

    private static func parseLLMResponse(_ raw: String) throws -> ParsedReminder {
        // Fjern evt. markdown-fences hvis modellen putter dem på trods af instruktioner
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw ReminderError.parseFailed("Kunne ikke konvertere til UTF-8")
        }

        // Først prøv error-shape
        if let errResp = try? JSONDecoder().decode(LLMErrorResponse.self, from: data) {
            throw ReminderError.parseFailed(errResp.error)
        }

        let resp = try JSONDecoder().decode(LLMReminderResponse.self, from: data)

        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        guard let fireAt = formatter.date(from: resp.trigger_iso8601) else {
            // Forsøg uden 'T' eller andre småafvigelser
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            guard let fireAt2 = formatter.date(from: resp.trigger_iso8601.replacingOccurrences(of: "T", with: " ")) else {
                throw ReminderError.parseFailed("Ugyldigt timestamp: \(resp.trigger_iso8601)")
            }
            return ParsedReminder(title: resp.title, body: resp.body ?? "", fireAt: fireAt2)
        }

        return ParsedReminder(title: resp.title, body: resp.body ?? "", fireAt: fireAt)
    }

    private static func formatConfirmation(_ reminder: ScheduledReminder) -> String {
        // Det er det Saga skriver tilbage ved cursor — eksplicit ift. hvor
        // påmindelsen er gemt så bruger ved hvad der er sket.
        let location: String
        switch reminder.backend {
        case .appleReminders:
            location = "Puttet reminder i Apple Reminders"
        case .localNotification:
            location = "Puttet reminder lokalt"
        }
        return "✓ \(location): \(reminder.title) \(reminder.formattedFireDate)"
    }
}

private struct LLMReminderResponse: Codable {
    let trigger_iso8601: String
    let title: String
    let body: String?
}

private struct LLMErrorResponse: Codable {
    let error: String
}

private struct ParsedReminder {
    let title: String
    let body: String
    let fireAt: Date
}

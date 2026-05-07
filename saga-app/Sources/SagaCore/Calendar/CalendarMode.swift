import Foundation
import OSLog

/// Calendar-mode: parser brugerens dansk-naturlige tekst via LM Studio for at
/// ekstrahere `{title, start_iso8601, end_iso8601, attendees, notes}`, opretter
/// EKEvent via CalendarEngine og returnerer en bekræftelses-tekst til
/// cursor-injection.
///
/// Parallel til ReminderMode — samme pattern (triggers + LLM-parse + engine.create).
/// Ikke @MainActor — kun engine-kald er @MainActor og await'es eksplicit.
public enum CalendarMode {
    private static let log = Logger(subsystem: "dk.parthee.saga", category: "calendar-mode")

    public static let triggers: [String] = [
        "book møde",
        "book et møde",
        "book mode",  // tolerance for stenograf-fejl
        "book en aftale",
        "kalender:",
        "møde med",
        "schedule meeting",
        "schedule a meeting",
    ]

    public static func matches(_ text: String) -> (matched: Bool, payload: String) {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for trigger in triggers {
            if lower.hasPrefix(trigger.lowercased()) {
                let payload = String(text.dropFirst(trigger.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:"))
                // "møde med" er specielt — payload skal beholde "med X" så LLM
                // ved hvem deltagerne er. Vi prepender derfor "møde med" tilbage.
                if trigger.lowercased() == "møde med" {
                    return (true, "møde med " + payload)
                }
                return (true, payload)
            }
        }
        return (false, text)
    }

    public static let systemPromptTemplate: String = """
    Du parser dansk kalender-tekst og returnerer KUN gyldig JSON i præcis dette format:
    {"title":"kort emne", "start_iso8601":"YYYY-MM-DDTHH:MM", "end_iso8601":"YYYY-MM-DDTHH:MM", "attendees":["navn1","navn2"], "notes":"evt. detaljer"}

    Regler:
    - Tider er ALTID i lokal tid (Europa/København), ingen tidszone-suffix
    - Hvis kun start angivet uden slut: end = start + 60 min
    - "i morgen kl 14 til 15" → start=morgen 14:00, end=morgen 15:00
    - "i morgen 14-15" eller "kl 14-15" → samme
    - "om 30 min" → nu + 30 min, end = start + 60 min
    - "på fredag" / "næste fredag" → næste forekomst af den ugedag, default 09:00 hvis intet kl
    - Hvis ikke andet specificeret: 09:00 for hele dag-events
    - title bør være kort emne (typisk efter "om" eller dagsorden, fx "Q3-status", "1:1 med Lars")
    - attendees: array af navne nævnt efter "med X" eller "med X og Y" — uden titler/efternavne
    - notes: evt. resterende detaljer (lokation, agenda)
    - Hvis du ikke kan parse: returnér {"error":"kunne ikke forstå tidspunkt eller titel"}

    Aktuel dato/tid (lokal): %@

    Returnér KUN JSON. Ingen forklaring, ingen markdown-kodeblock, ingen ekstra tekst.
    """

    /// Kør parse + create. Returnerer confirmation-streng til cursor-injection.
    public static func run(payload: String, controller: SagaController) async throws -> String {
        guard !payload.isEmpty else {
            throw CalendarError.parseFailed("Tom kalender-payload")
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let nowString = isoFormatter.string(from: Date())
        let systemPrompt = String(format: systemPromptTemplate, nowString)

        // maxTokens 4000 — giver reasoning-modeller (gemma-4-26b-a4b,
        // gpt-oss-20b m.fl.) plads til BÅDE intern tænkning OG faktisk JSON-output.
        let raw = try await controller.lmStudio.chat(
            system: systemPrompt,
            user: payload,
            temperature: 0.1,
            maxTokens: 4000
        )
        log.debug("LLM raw: \(raw, privacy: .public)")

        let parsed = try parseLLMResponse(raw)
        let event = try await controller.appleCalendar.createEvent(
            title: parsed.title,
            start: parsed.start,
            end: parsed.end,
            attendees: parsed.attendees,
            notes: parsed.notes
        )

        return formatConfirmation(event)
    }

    nonisolated static func parseLLMResponse(_ raw: String) throws -> ParsedEvent {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw CalendarError.parseFailed("Kunne ikke konvertere til UTF-8")
        }

        if let errResp = try? JSONDecoder().decode(LLMErrorResponse.self, from: data) {
            throw CalendarError.parseFailed(errResp.error)
        }

        let resp = try JSONDecoder().decode(LLMEventResponse.self, from: data)

        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let start = try parseDate(resp.start_iso8601, with: formatter)
        let end: Date
        if let endIso = resp.end_iso8601, !endIso.isEmpty {
            end = try parseDate(endIso, with: formatter)
        } else {
            // Default 60 min varighed hvis LLM ikke angav slut
            end = start.addingTimeInterval(3600)
        }

        return ParsedEvent(
            title: resp.title,
            start: start,
            end: end,
            attendees: resp.attendees ?? [],
            notes: resp.notes ?? ""
        )
    }

    nonisolated private static func parseDate(_ raw: String, with formatter: DateFormatter) throws -> Date {
        if let date = formatter.date(from: raw) {
            return date
        }
        // Forsøg uden 'T'
        let alt = DateFormatter()
        alt.calendar = formatter.calendar
        alt.timeZone = formatter.timeZone
        alt.locale = formatter.locale
        alt.dateFormat = "yyyy-MM-dd HH:mm"
        if let date = alt.date(from: raw.replacingOccurrences(of: "T", with: " ")) {
            return date
        }
        throw CalendarError.parseFailed("Ugyldigt timestamp: \(raw)")
    }

    private static func formatConfirmation(_ event: CreatedEvent) -> String {
        return "✓ Møde: \(event.formattedSummary)"
    }
}

private struct LLMEventResponse: Codable {
    let title: String
    let start_iso8601: String
    let end_iso8601: String?
    let attendees: [String]?
    let notes: String?
}

private struct LLMErrorResponse: Codable {
    let error: String
}

struct ParsedEvent: Equatable {
    let title: String
    let start: Date
    let end: Date
    let attendees: [String]
    let notes: String
}

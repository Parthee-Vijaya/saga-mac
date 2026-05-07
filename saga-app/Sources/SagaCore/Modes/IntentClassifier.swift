import Foundation
import OSLog

/// Klassificerer brugerens transcribed tekst til en handling-intent når
/// strenge trigger-matching fejler. Bruges som fallback i ModeRouter.
///
/// **Hvorfor:** Canary ASR mishører ofte danske trigger-fraser (fx
/// "mind mig om" → "Det regnede" eller "På jeg"). Strenge prefix-match
/// vil aldrig fange disse. Med LLM-classifier kan vi forstå intent
/// uafhængigt af præcis ordlyd.
///
/// **Performance:** Ekstra LLM-call koster ~1-3 sek for korte prompts.
/// Kører kun hvis transcripten indeholder tids- eller handlings-
/// keywords (heuristik-gate) — så pure dictation går direkte igennem.
public enum IntentClassifier {
    private static let log = Logger(subsystem: "dk.parthee.saga", category: "intent-classifier")

    public enum Intent: String, Codable, Sendable {
        case reminder
        case calendar
        case dictation
    }

    /// Heuristik: er transcripten kandidat til at være reminder/calendar?
    /// Hvis nej, spar LLM-callet og gå direkte til pure dictation.
    public static func looksLikeIntent(_ text: String) -> Bool {
        let lower = text.lowercased()

        // Tids-keywords (dansk + engelsk)
        let timeKeywords = [
            "i morgen", "i dag", "i aften", "i overmorgen",
            "tomorrow", "today", "tonight",
            "om en time", "om to timer", "om en uge",
            "næste uge", "næste mandag", "næste tirsdag", "næste onsdag",
            "næste torsdag", "næste fredag", "næste lørdag", "næste søndag",
            "på mandag", "på tirsdag", "på onsdag", "på torsdag",
            "på fredag", "på lørdag", "på søndag",
            "klokken", "kl.",
            " kl ",  // "kl 14" med spaces omkring
        ]

        // Handlings-keywords der typisk kombineres med tider
        let actionKeywords = [
            "ringe", "ringer", "kalde", "kalder",
            "møde", "møder", "møde med", "aftale", "aftaler",
            "huske", "husk", "huske at", "husk at",
            "send", "sende", "skrive", "skriv",
            "betale", "betal", "købe", "køb",
            "hente", "hent", "afhente",
            "book", "booke", "lav", "indkald",
            "schedule", "remind", "remember",
        ]

        // Match hvis BÅDE tids- OG handlings-keyword findes
        let hasTime = timeKeywords.contains { lower.contains($0) }
        let hasAction = actionKeywords.contains { lower.contains($0) }

        // Eller bare hvis der er klokkeslæt (kl + tal)
        let hasClockTime = lower.range(of: #"kl\.?\s*\d"#, options: .regularExpression) != nil

        return (hasTime && hasAction) || (hasClockTime && hasAction)
    }

    /// LLM-baseret intent-klassifikation. Returnerer .dictation hvis vi ikke
    /// er sikre, så routing falder gracefully tilbage til pure dictation.
    public static func classify(_ text: String, controller: SagaController) async -> Intent {
        let systemPrompt = """
        Du klassificerer dansk transcribed tekst til EN af tre intents og returnerer KUN et JSON-objekt:
        {"intent":"reminder"} | {"intent":"calendar"} | {"intent":"dictation"}

        Regler:
        - "reminder" hvis brugeren beder om en påmindelse eller huske-prompt på et tidspunkt
          (fx "ringe til mor i morgen kl 14", "huske at betale regning på fredag",
          "påmind mig om at sende rapport om en time"). Også hvis ASR har mishørt
          fraser som "Det regnede" / "På jeg ringer til mor" — fokus på
          intentionen (én-person handling med tidsangivelse).
        - "calendar" hvis brugeren beder om at booke et møde med ANDRE personer
          (fx "møde med Lars i morgen kl 14 til 15", "book aftale med Anna torsdag").
          Calendar har typisk navne + start+slut-tid + flere deltagere.
        - "dictation" hvis det er almindelig tekst der bare skal indsættes
          (fx "Hej Lars, tak for mødet i går"). Default til dictation hvis i tvivl.

        Returnér KUN JSON. Ingen forklaring, ingen markdown.
        """

        do {
            let raw = try await controller.lmStudio.chat(
                system: systemPrompt,
                user: text,
                temperature: 0.1,
                maxTokens: 4000
            )
            let cleaned = raw
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = cleaned.data(using: .utf8) else {
                log.warning("Intent-classifier: kunne ikke decode UTF-8")
                return .dictation
            }
            let resp = try JSONDecoder().decode(IntentResponse.self, from: data)
            log.info("Intent classified as: \(resp.intent.rawValue, privacy: .public)")
            return resp.intent
        } catch {
            log.warning("Intent-classifier fejlede: \(error.localizedDescription, privacy: .public) — defaulter til dictation")
            return .dictation
        }
    }
}

private struct IntentResponse: Codable {
    let intent: IntentClassifier.Intent
}

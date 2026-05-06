import Foundation
import OSLog

/// Inline AI-kommandoer: detektér en redigerings-instruktion i slutningen
/// af brugerens dictation, splitter content fra instruktion, og sender til
/// LM Studio for omformulering.
///
/// **Eksempel:**
///
///     Bruger dikterer: "Hej Lars, jeg har lavet et nyt design som du
///                       skal kigge på, skriv det som en formel email"
///     InlineEditMode detekterer trigger "skriv det som"
///     Splitter til:
///       content     = "Hej Lars, jeg har lavet et nyt design som du skal kigge på"
///       instruction = "skriv det som en formel email"
///     LM Studio omformulerer og resultatet paste'es.
///
/// Inspireret af Wispr Flow's inline AI-commands. Forskellen er at Saga
/// bruger eksplicitte trigger-fraser (suffix-style) i stedet for et magisk
/// kommando-prefix — det er mere naturligt at sige indholdet først og så
/// instruktionen til sidst på dansk.
public enum InlineEditMode {
    private static let log = Logger(subsystem: "dk.parthee.saga", category: "inline-edit")

    /// Trigger-fraser i suffix-position. Sorteret efter længde (længste
    /// først) så vi matcher mest-specifik frase frem for kortere prefix.
    public static let triggers: [String] = [
        "lav det om til",
        "skriv det om til",
        "skriv det som",
        "skriv om til",
        "lav det til",
        "formulér som",
        "formuler som",
        "som bullet points",
        "i punktopstilling",
        "som en email",
        "som email",
        "gør det mere formelt",
        "gør det mere casual",
        "gør det kortere",
        "gør det længere",
    ]

    /// Resultat af trigger-detection.
    public struct Match: Sendable, Equatable {
        public let content: String
        public let instruction: String
    }

    /// Detektér om transcripten indeholder en suffix-trigger. Returnerer
    /// `nil` hvis ingen trigger findes, ELLER hvis der ikke er meningsfuldt
    /// content før triggeren (det giver ingen mening at "redigere" intet).
    ///
    /// Strategi: build én alternation-regex af alle triggers (sorteret
    /// længste først, så regex-engine'en foretrækker længere triggers ved
    /// samme position), find ALLE matches, vælg sidste (suffix-position).
    /// Word-boundary håndteres via lookbehind for whitespace/punktuation.
    public static func detectInstruction(_ text: String) -> Match? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Sortér triggers længste først så alternation foretrækker længste match.
        let sorted = triggers.sorted { $0.count > $1.count }
        let escaped = sorted.map { NSRegularExpression.escapedPattern(for: $0) }
        // (?i) = case-insensitive. Lookbehind kræver fixed-length, så vi bruger
        // alternation: ^ ELLER whitespace/punktuation lige før.
        let pattern = "(?i)(?:^|(?<=[\\s,.;:!?]))(\(escaped.joined(separator: "|")))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsText = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Find alle matches og vælg den sidste (last-wins ved suffix-position).
        let matches = regex.matches(in: trimmed, range: fullRange)
        guard let last = matches.last else { return nil }

        let triggerLocation = last.range.location
        guard triggerLocation >= 0, triggerLocation <= nsText.length else { return nil }

        let contentRaw = nsText.substring(with: NSRange(location: 0, length: triggerLocation))
        let instructionRaw = nsText.substring(from: triggerLocation)

        let trimChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:"))
        let content = contentRaw.trimmingCharacters(in: trimChars)
        let instruction = instructionRaw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Meningsløst at "redigere" intet eller næsten intet content
        guard content.count >= 5 else { return nil }

        return Match(content: content, instruction: instruction)
    }

    /// Kør inline-edit: send content + instruktion til LM Studio og returnér
    /// det redigerede output. Genbruger samme system-prompt som EditMode.
    @MainActor
    public static func run(
        content: String,
        instruction: String,
        controller: SagaController
    ) async throws -> String {
        let systemPrompt = """
        Du er en præcis tekst-editor. Brugeren har dikteret en tekst og en \
        instruktion til hvordan teksten skal omformuleres. Returnér KUN den \
        omformulerede tekst — ingen forklaring, ingen anførselstegn omkring, \
        ingen 'her er resultatet'. Bevar betydningen med mindre brugeren \
        eksplicit beder om ændring. Skriv den færdige tekst direkte uden \
        lang analyse eller alternative versioner.
        """
        let userMessage = """
        Tekst:
        ---
        \(content)
        ---

        Instruktion: \(instruction)
        """

        log.info("InlineEditMode: instruktion=\"\(instruction.prefix(80), privacy: .public)\", content=\(content.count, privacy: .public) chars")

        // 4096 max_tokens — inline edits er typisk kortere end ⇧+⌥ voice-edit
        // (som kan være lange dokument-sektioner). Reasoning-modeller får stadig
        // plads til at tænke + producere content.
        let result = try await controller.lmStudio.chat(
            system: systemPrompt,
            user: userMessage,
            temperature: 0.3,
            maxTokens: 4096
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

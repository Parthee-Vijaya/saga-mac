import Foundation
import OSLog

/// Voice-edit-mode: brugeren har markeret tekst og siger en instruktion.
/// Saga læser selection via AXUIElement, sender selection + instruktion til
/// LM Studio, og returnerer den redigerede tekst som SagaController så
/// indsætter — den markerede tekst overskrives når der typed'es i stedet.
///
/// Special-cased ligesom Reminder/Vision: kræver runtime-tjek (har vi
/// selection?) før den må match'e, så vi ikke bruger LM Studio på tom payload.
public enum EditMode {
    private static let log = Logger(subsystem: "dk.parthee.saga", category: "edit-mode")

    /// Triggers brugeren kan sige FØR instruktionen.
    /// Eksempel: "ret: gør den her sætning mere formel"
    public static let triggers: [String] = [
        "ret:",
        "ret denne",
        "redigér:",
        "rediger:",
        "rewrite:",
        "edit:",
    ]

    public struct Match {
        public let matched: Bool
        public let instruction: String
    }

    /// Tjek kun selve trigger-matchet — kalderen er ansvarlig for at verificere
    /// at der findes en selection før EditMode aktiveres.
    public static func matches(_ text: String) -> Match {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for trigger in triggers {
            if lower.hasPrefix(trigger) {
                let payload = String(text.drop(while: { $0.isWhitespace }))
                let stripped = String(payload.dropFirst(trigger.count))
                let cleaned = stripped.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:"))
                return Match(matched: true, instruction: cleaned)
            }
        }
        return Match(matched: false, instruction: "")
    }

    /// Kør edit-mode: send selection + instruktion til LM Studio.
    @MainActor
    public static func run(
        selection: String,
        instruction: String,
        controller: SagaController
    ) async throws -> String {
        let safeInstruction = instruction.isEmpty ? "Forbedr og polér denne tekst." : instruction
        let systemPrompt = """
        Du er en præcis tekst-editor. Brugeren har markeret en tekst og bedt dig om \
        at redigere den. Returnér KUN den redigerede tekst — ingen forklaring, ingen \
        anførselstegn omkring, ingen 'her er resultatet'. Bevar tone og betydning \
        med mindre brugeren eksplicit beder om ændring. Skriv den færdige tekst \
        direkte uden lang analyse eller alternative versioner.
        """
        let userMessage = """
        Markeret tekst:
        ---
        \(selection)
        ---

        Instruktion: \(safeInstruction)
        """

        log.info("EditMode: instruktion=\"\(safeInstruction.prefix(80), privacy: .public)\", selection=\(selection.count, privacy: .public) chars")

        // Reasoning-modeller (gemma-thinking, deepseek-r1) kan bruge 1500-2000
        // tokens på reasoning før de når at producere content. Med 8192 har de
        // plads til både tænkning og det endelige svar selv på lange tekster.
        let result = try await controller.lmStudio.chat(
            system: systemPrompt,
            user: userMessage,
            temperature: 0.3,
            maxTokens: 8192
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation
import OSLog

/// Vision-mode: capturer aktiv skærm, sender til multi-modal LM Studio,
/// returnerer beskrivelse til cursor-injection.
@MainActor
public enum VisionMode {
    private static let log = Logger(subsystem: "dk.parthee.saga", category: "vision-mode")

    public static let triggers: [String] = [
        "hvad ser jeg",
        "hvad er det her",
        "beskriv skærmen",
        "beskriv det her",
        "vision:",
        "describe screen",
    ]

    /// Default-prompt hvis bruger ikke har noget specifikt påsat trigger-frasen
    private static let defaultPrompt = "Beskriv kort hvad der vises på dette skærmbillede. Svar på dansk."

    public static func matches(_ text: String) -> (matched: Bool, payload: String) {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for trigger in triggers {
            if lower.hasPrefix(trigger.lowercased()) {
                let payload = String(text.dropFirst(trigger.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:?"))
                return (true, payload)
            }
        }
        return (false, text)
    }

    public static func run(payload: String, controller: SagaController) async throws -> String {
        let prompt = payload.isEmpty ? defaultPrompt : payload

        guard controller.vision.hasPermission else {
            controller.vision.requestPermission()
            throw VisionError.permissionDenied
        }

        guard let imageData = await controller.vision.captureFrontmostWindow() else {
            throw VisionError.captureFailed
        }

        log.info("Captured \(imageData.count, privacy: .public) bytes PNG, prompt=\"\(prompt.prefix(80), privacy: .public)\"")

        // maxTokens 4000 — reasoning-modeller har plads til thinking + svar
        let response = try await controller.lmStudio.chatWithImage(
            system: "Du er en hjælpsom assistent der beskriver skærmbilleder kort og præcist. Svar altid på dansk medmindre brugeren spørger på et andet sprog.",
            userText: prompt,
            imagePNG: imageData,
            temperature: 0.3,
            maxTokens: 4000
        )

        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum VisionError: Error, LocalizedError {
    case permissionDenied
    case captureFailed
    case visionNotSupported(model: String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Skærmoptagelse mangler. Aktivér i System Settings → Privacy → Screen Recording → Saga."
        case .captureFailed:
            return "Kunne ikke capture skærmen. Prøv igen."
        case .visionNotSupported(let model):
            return "Modellen '\(model)' i LM Studio understøtter ikke vision. Load fx llava eller gemma-4-vision."
        }
    }
}

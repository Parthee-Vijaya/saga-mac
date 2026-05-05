import Foundation
import OSLog

/// State for én Companion-samtale fra "Hej Saga…" til "tak".
///
/// Holder messages-array i kronologisk orden plus en screenshot-cache.
/// Trim-logik forhindrer context-vinduet i at vokse uendeligt — ældre
/// turn-pairs droppes når token-count nærmer sig en grænse.
@MainActor
public final class CompanionSession: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "companion.session")

    @Published public private(set) var messages: [CompanionMessage] = []

    /// System-prompt der altid sendes som første message. Kan opdateres
    /// (fx for at injecte locale-specific instruktioner).
    public let systemPrompt: String

    /// Maks antal user/assistant-tur-par der bevares i context. Ældste droppes når grænsen nås.
    /// Default 6 = 12 messages = passende til ~4-8k token windows på de fleste lokale modeller.
    public let maxTurnPairs: Int

    public init(
        systemPrompt: String = CompanionSession.defaultSystemPrompt,
        maxTurnPairs: Int = 6
    ) {
        self.systemPrompt = systemPrompt
        self.maxTurnPairs = maxTurnPairs
    }

    /// Tilføj en user-tur (med valgfri screenshot for vision-context).
    public func appendUser(_ text: String, screenshot: Data? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(CompanionMessage(role: .user, content: trimmed, screenshotPNG: screenshot))
        trimIfNeeded()
        log.info("User-tur tilføjet, total messages: \(self.messages.count)")
    }

    /// Tilføj en færdig assistant-tur (akkumuleret fra streaming chunks).
    public func appendAssistant(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(CompanionMessage(role: .assistant, content: trimmed))
        log.info("Assistant-tur tilføjet, total messages: \(self.messages.count)")
    }

    /// Returner messages-array klar til at sende til LM Studio.
    /// Inkluderer system-prompt som første element.
    public func messagesForLLM() -> [CompanionMessage] {
        var out: [CompanionMessage] = [
            CompanionMessage(role: .system, content: systemPrompt)
        ]
        out.append(contentsOf: messages)
        return out
    }

    /// Reset til fresh state (nyt "Hej Saga"). Bevarer system-prompt.
    public func reset() {
        messages.removeAll()
    }

    /// True hvis brugerens seneste tur indikerer "afslut samtalen".
    /// Bruges af CompanionController til auto-end-of-session.
    public func userJustEndedSession() -> Bool {
        guard let last = messages.last, last.role == .user else { return false }
        let normalized = last.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return CompanionSession.endOfSessionPhrases.contains { normalized == $0 || normalized.hasPrefix($0 + " ") || normalized.hasSuffix(" " + $0) }
    }

    /// Trim ældste turn-pairs hvis vi er over `maxTurnPairs`. Beholder altid
    /// alle messages parvis (user + assistant) så context aldrig brækker.
    private func trimIfNeeded() {
        let userCount = messages.filter { $0.role == .user }.count
        guard userCount > maxTurnPairs else { return }

        let toRemove = userCount - maxTurnPairs
        var removedPairs = 0
        var newMessages: [CompanionMessage] = []
        var skipNextAssistant = false

        for message in messages {
            if message.role == .user, removedPairs < toRemove {
                removedPairs += 1
                skipNextAssistant = true
                continue
            }
            if skipNextAssistant, message.role == .assistant {
                skipNextAssistant = false
                continue
            }
            newMessages.append(message)
        }
        messages = newMessages
        log.info("Trimmed \(toRemove) tur-par fra session-history")
    }

    /// Default-system-prompt for Companion. Holdes kort så det passer
    /// inden for små context-windows (M2-M4 lokale modeller).
    public static let defaultSystemPrompt = """
    Du er Saga — en hjælpsom AI-assistent på brugerens Mac. Brugeren taler til \
    dig og du svarer i stemme. Hold svar korte, naturlige og til-sagen — typisk \
    1-3 sætninger. Du kan se hvad der står på brugerens skærm når et screenshot \
    er vedhæftet. Svar på dansk medmindre brugeren skifter sprog.
    """

    /// Frase-fragmenter der lukker en samtale ned uden yderligere LLM-tur.
    public static let endOfSessionPhrases: Set<String> = [
        "tak",
        "tak saga",
        "tak for hjælpen",
        "stop",
        "stop saga",
        "farvel",
        "thanks",
        "thanks saga",
        "thank you",
        "stop now",
        "goodbye",
        "bye saga",
        "bye",
    ]
}

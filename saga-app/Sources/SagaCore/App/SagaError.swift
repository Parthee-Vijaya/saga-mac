import AppKit
import Foundation

/// Structured fejl-repræsentation for brugerynlig feedback. Bruges side-by-side
/// med `SagaController.lastError: String?` indtil alle error-paths er migreret
/// til den nye form. Hver fejl har:
/// - `title`: kort overskrift (1-3 ord)
/// - `detail`: forklarende sætning (vises i UI)
/// - `recovery`: optional handling brugeren kan trigge med ét klik
///
/// Pattern: factory-funcs som `.micPermissionDenied()` returnerer en pre-bygget
/// `SagaError` med korrekt detail-tekst og recovery-action. Det centraliserer
/// strings + recovery-flows ét sted (i stedet for spredt rundt i SagaController).
public struct SagaError: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let recovery: Recovery?

    public init(title: String, detail: String, recovery: Recovery? = nil) {
        self.title = title
        self.detail = detail
        self.recovery = recovery
    }

    /// Mulig recovery-handling. View-laget kan vise en "Fix"-knap der trigger
    /// kind-specific behavior. Sendable så den kan krydse actor-grænser.
    public struct Recovery: Equatable, Sendable {
        public let label: String
        public let kind: Kind

        public enum Kind: Equatable, Sendable {
            case openURL(URL)
            case retry
        }

        public init(label: String, kind: Kind) {
            self.label = label
            self.kind = kind
        }
    }
}

// MARK: - Factory helpers

extension SagaError {
    public static func micPermissionDenied() -> Self {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        return SagaError(
            title: "Mikrofon-adgang",
            detail: "Saga skal have adgang til mikrofonen for at lytte. Aktivér i System Settings → Privacy & Security → Microphone.",
            recovery: Recovery(label: "Åbn System Settings", kind: .openURL(url))
        )
    }

    public static func micPermissionNotRequested() -> Self {
        SagaError(
            title: "Mikrofon-adgang",
            detail: "Saga venter på dit svar i mikrofon-permission-dialogen.",
            recovery: nil
        )
    }

    public static func axPermissionMissing() -> Self {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        return SagaError(
            title: "Accessibility-adgang",
            detail: "Saga skal have Accessibility for at indsætte tekst ved cursoren og lytte til hotkey-tastetryk.",
            recovery: Recovery(label: "Åbn System Settings", kind: .openURL(url))
        )
    }

    public static func speechRecognitionDenied() -> Self {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
        return SagaError(
            title: "Speech-permission",
            detail: "Wake-word kræver speech-recognition-permission. Aktivér i System Settings, eller slå wake-word fra.",
            recovery: Recovery(label: "Åbn System Settings", kind: .openURL(url))
        )
    }

    public static func asrModelLoading() -> Self {
        SagaError(
            title: "Indlæser ASR-model",
            detail: "Saga er stadig ved at indlæse Canary-modellen. Det tager ca. 10 sekunder ved første start.",
            recovery: nil
        )
    }

    public static func lmStudioUnreachable() -> Self {
        let url = URL(string: "https://lmstudio.ai/")!
        return SagaError(
            title: "LM Studio nede",
            detail: "Kunne ikke kontakte LM Studio på localhost. Mode-routing er deaktiveret indtil den kører igen.",
            recovery: Recovery(label: "Åbn lmstudio.ai", kind: .openURL(url))
        )
    }

    public static func selectionRequired() -> Self {
        SagaError(
            title: "Markér først",
            detail: "Markér tekst i en app før du holder ⇧+⌥. Uden markering bliver det normal dictation.",
            recovery: nil
        )
    }

    /// Vis en custom-string-fejl gennem SagaError-systemet uden mistage af info.
    /// Bruges som migrations-hjælper indtil alle `lastError = "..."`-paths er
    /// erstattet med specifikke factory-helpers.
    public static func generic(_ detail: String) -> Self {
        SagaError(title: "Fejl", detail: detail, recovery: nil)
    }
}

// MARK: - Recovery executor

extension SagaError.Recovery {
    /// Udfør recovery-action. Kald'es af UI'et når brugeren klikker på "Fix"-knappen.
    @MainActor
    public func execute() {
        switch kind {
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .retry:
            // Retry-handling er context-specifik — caller-siden skal håndtere det.
            // Vi gør ingenting her fordi vi ikke ved hvad der skal genstartes.
            break
        }
    }
}

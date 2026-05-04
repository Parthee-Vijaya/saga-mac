import AppKit
import Combine
import Foundation
import OSLog

/// Top-level orkestrator. Holder alle moduler og koordinerer hotkey → audio → transcribe → inject.
@MainActor
public final class SagaController: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "controller")

    public let menubar: MenubarController
    public let hud: RecordingHUDController
    public let hotkeys: HotkeyManager
    public let audio: AudioCapture
    public let cursor: CursorInjector
    public let sidecar: SidecarLauncher
    public let hviske: HviskeBridge
    public let lmStudio: LMStudioBridge
    public let modes: ModeRouter

    @Published public private(set) var state: SagaState = .idle

    public init() {
        self.menubar = MenubarController()
        self.hud = RecordingHUDController()
        self.hotkeys = HotkeyManager()
        self.audio = AudioCapture()
        self.cursor = CursorInjector()
        self.sidecar = SidecarLauncher()
        self.hviske = HviskeBridge()
        self.lmStudio = LMStudioBridge()
        self.modes = ModeRouter()
    }

    public func start() {
        log.info("Saga starter")
        menubar.attach(controller: self)
        hud.attach(controller: self)

        // Start sidecar (async, vi blocker ikke UI)
        Task { [sidecar, hviske] in
            do {
                let port = try await sidecar.startIfNeeded()
                hviske.update(port: port)
            } catch {
                self.log.error("Kunne ikke starte sidecar: \(error.localizedDescription)")
                self.menubar.show(error: "Hviske-sidecar kunne ikke starte. Kør scripts/setup.sh og prøv igen.")
            }
        }

        // Aktivér hotkey-listening (kræver AX-permission)
        hotkeys.onHoldStart = { [weak self] in self?.handleHoldStart() }
        hotkeys.onHoldEnd = { [weak self] in self?.handleHoldEnd() }
        hotkeys.startListening()
    }

    public func stop() {
        log.info("Saga stopper")
        hotkeys.stopListening()
        audio.stop()
        Task { await sidecar.shutdown() }
    }

    // MARK: - Recording lifecycle

    private func handleHoldStart() {
        guard state == .idle else { return }
        state = .recording
        hud.show()
        audio.start()
    }

    private func handleHoldEnd() {
        guard state == .recording else { return }
        state = .transcribing
        hud.update(state: .transcribing)

        let pcm = audio.stop()
        guard pcm.duration > 0.3 else {
            log.info("Optagelse for kort (\(pcm.duration)s) — ignorer")
            state = .idle
            hud.dismiss()
            return
        }

        Task { @MainActor in
            do {
                let transcript = try await hviske.transcribe(pcm: pcm)
                state = .routing
                hud.update(state: .routing)

                let result = try await modes.route(text: transcript.text, controller: self)

                cursor.type(result)
                state = .idle
                hud.dismiss()
            } catch {
                log.error("Pipeline fejlede: \(error.localizedDescription)")
                state = .idle
                hud.show(error: error)
            }
        }
    }
}

public enum SagaState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case routing
}

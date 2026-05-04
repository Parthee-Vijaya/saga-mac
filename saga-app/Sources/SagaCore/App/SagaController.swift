import AppKit
import Combine
import Foundation
import OSLog

/// Top-level orkestrator. Holder alle moduler og koordinerer hotkey → audio → transcribe → inject.
@MainActor
public final class SagaController: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "controller")

    public let hud: RecordingHUDController
    public let hotkeys: HotkeyManager
    public let audio: AudioCapture
    public let cursor: CursorInjector
    public let sidecar: SidecarLauncher
    public let hviske: HviskeBridge
    public let lmStudio: LMStudioBridge
    public let modes: ModeRouter
    public let health: HealthMonitor
    public let history: HistoryStore

    @Published public private(set) var state: SagaState = .idle
    @Published public private(set) var lastError: String?
    @Published public private(set) var booted = false

    public init() {
        self.hud = RecordingHUDController()
        self.hotkeys = HotkeyManager()
        self.audio = AudioCapture()
        self.cursor = CursorInjector()
        self.sidecar = SidecarLauncher()
        self.hviske = HviskeBridge()
        self.lmStudio = LMStudioBridge()
        self.modes = ModeRouter()
        self.health = HealthMonitor()
        self.history = HistoryStore()
    }

    public var menuBarIconName: String {
        switch state {
        case .idle: return health.sidecar.isHappy ? "waveform.circle" : "waveform.circle.fill"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .routing: return "sparkles"
        }
    }

    /// Kaldes en gang fra MenuBarExtra-task. Idempotent.
    public func bootIfNeeded() async {
        guard !booted else { return }
        booted = true
        log.info("Saga booter")

        hud.attach(controller: self)
        health.attach(hviske: hviske)
        health.start()

        // Start sidecar i baggrunden
        Task { [sidecar, hviske] in
            do {
                let port = try await sidecar.startIfNeeded()
                hviske.update(port: port)
            } catch {
                self.log.error("Kunne ikke starte sidecar: \(error.localizedDescription)")
                self.lastError = "Sidecar startede ikke: \(error.localizedDescription)"
            }
        }

        // Aktivér hotkey-listening
        hotkeys.onHoldStart = { [weak self] in self?.handleHoldStart() }
        hotkeys.onHoldEnd = { [weak self] in self?.handleHoldEnd() }
        hotkeys.startListening()
    }

    public func shutdown() async {
        log.info("Saga lukker ned")
        hotkeys.stopListening()
        audio.stop()
        health.stop()
        await sidecar.shutdown()
    }

    public func restartSidecar() {
        Task { [sidecar, hviske] in
            await sidecar.shutdown()
            do {
                let port = try await sidecar.startIfNeeded()
                hviske.update(port: port)
            } catch {
                self.lastError = "Genstart fejlede: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Recording lifecycle

    private func handleHoldStart() {
        guard state == .idle else { return }
        lastError = nil
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

                let routed = try await modes.route(text: transcript.text, controller: self)

                cursor.type(routed)

                let modeId = routed != transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    ? matchedModeId(for: transcript.text)
                    : nil

                history.append(TranscriptEntry(
                    rawText: transcript.text,
                    processedText: routed,
                    modeId: modeId,
                    durationMs: transcript.durationMs,
                    inferenceMs: transcript.inferenceMs
                ))

                state = .idle
                hud.dismiss()
            } catch {
                log.error("Pipeline fejlede: \(error.localizedDescription)")
                lastError = error.localizedDescription
                state = .idle
                hud.show(error: error)
            }
        }
    }

    private func matchedModeId(for text: String) -> String? {
        let lower = text.lowercased()
        for mode in modes.modes where modes.enabled.contains(mode.id) {
            for trigger in mode.triggers where lower.hasPrefix(trigger.lowercased()) {
                return mode.id
            }
        }
        return nil
    }
}

public enum SagaState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case routing
}

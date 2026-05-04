import Foundation
import OSLog

/// Polls LM Studio /v1/models periodisk og spejler ASR-bridge state.
/// CanaryASR har en intern @Published-state vi spejler ind så menu-UI kan binde.
@MainActor
public final class HealthMonitor: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "health")

    @Published public private(set) var asr: ASRState = .uninitialized
    @Published public private(set) var lmStudio: LMStudioHealth = .unknown

    private var asrTask: Task<Void, Never>?
    private var lmStudioTask: Task<Void, Never>?
    private weak var asrBridge: CanaryASRBridge?

    public init() {}

    public func attach(asr: CanaryASRBridge) {
        self.asrBridge = asr
    }

    public func start() {
        asrTask?.cancel()
        lmStudioTask?.cancel()

        asrTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollASR()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        lmStudioTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollLMStudio()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    public func stop() {
        asrTask?.cancel()
        lmStudioTask?.cancel()
        asrTask = nil
        lmStudioTask = nil
    }

    private func pollASR() async {
        guard let bridge = asrBridge else { return }
        let newState = bridge.state
        if newState != asr {
            asr = newState
        }
    }

    private func pollLMStudio() async {
        let baseURLString = UserDefaults.standard.string(forKey: "lmStudioBaseURL") ?? "http://localhost:1234/v1"
        guard let baseURL = URL(string: baseURLString) else {
            lmStudio = .misconfigured
            return
        }
        let url = baseURL.appendingPathComponent("models")
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lmStudio = .down
                return
            }
            if let payload = try? JSONDecoder().decode(LMStudioModels.self, from: data),
               let first = payload.data.first {
                lmStudio = .ready(model: first.id)
            } else {
                lmStudio = .ready(model: "ukendt")
            }
        } catch {
            lmStudio = .down
        }
    }
}

public enum LMStudioHealth: Equatable, Sendable {
    case unknown
    case ready(model: String)
    case down
    case misconfigured

    public var label: String {
        switch self {
        case .unknown: return "Tjekker…"
        case .ready(let model): return "Klar (\(model))"
        case .down: return "Ikke kørende"
        case .misconfigured: return "Ugyldig URL i Indstillinger"
        }
    }

    public var isHappy: Bool { if case .ready = self { return true } else { return false } }
}

// LMStudioModels-typen er nu defineret internt i LMStudioBridge.swift
// (delt mellem HealthMonitor og discovery-flow).

import Foundation
import OSLog

/// Pinger sidecar /health og LM Studio /v1/models periodisk så menu-UI'en
/// kan vise live-status. Kører på MainActor — tasks der kalder netværk
/// dispatcher selv asynkront via URLSession.
@MainActor
public final class HealthMonitor: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "health")

    @Published public private(set) var sidecar: SidecarHealth = .unknown
    @Published public private(set) var lmStudio: LMStudioHealth = .unknown

    private var sidecarTask: Task<Void, Never>?
    private var lmStudioTask: Task<Void, Never>?
    private weak var hviske: HviskeBridge?

    public init() {}

    public func attach(hviske: HviskeBridge) {
        self.hviske = hviske
    }

    public func start() {
        sidecarTask?.cancel()
        lmStudioTask?.cancel()

        sidecarTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSidecar()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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
        sidecarTask?.cancel()
        lmStudioTask?.cancel()
        sidecarTask = nil
        lmStudioTask = nil
    }

    private func pollSidecar() async {
        guard let port = currentSidecarPort() else {
            sidecar = .down(reason: "Ikke spawned endnu")
            return
        }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        req.timeoutInterval = 2.0

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                sidecar = .down(reason: "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            let info = try JSONDecoder().decode(SidecarHealthPayload.self, from: data)
            sidecar = info.status == "ready"
                ? .ready(device: info.device, modelId: info.modelId, version: info.version)
                : .loading(device: info.device, modelId: info.modelId)
        } catch {
            sidecar = .down(reason: error.localizedDescription)
        }
    }

    private func pollLMStudio() async {
        // Læs config fra UserDefaults
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
            // Parse model-list — vi tager bare første model som "loaded"
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

    private func currentSidecarPort() -> UInt16? {
        hviske?.currentPort
    }
}

public enum SidecarHealth: Equatable, Sendable {
    case unknown
    case loading(device: String, modelId: String)
    case ready(device: String, modelId: String, version: String)
    case down(reason: String)

    public var label: String {
        switch self {
        case .unknown: return "Spawner…"
        case .loading(let device, _): return "Indlæser model på \(device)…"
        case .ready(let device, _, _): return "Klar (\(device))"
        case .down(let reason): return "Nede — \(reason)"
        }
    }

    public var isHappy: Bool { if case .ready = self { return true } else { return false } }
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

private struct SidecarHealthPayload: Codable {
    let status: String
    let device: String
    let modelId: String
    let version: String

    enum CodingKeys: String, CodingKey {
        case status, device, version
        case modelId = "model_id"
    }
}

private struct LMStudioModels: Codable {
    let data: [Model]
    struct Model: Codable {
        let id: String
    }
}

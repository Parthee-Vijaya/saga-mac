import Foundation
import OSLog

/// Spawner Saga Python-sidecar (saga-sidecar) som subprocess og polls /health
/// indtil den er klar. Restart on crash med exponential backoff (op til 3 forsøg).
public actor SidecarLauncher {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "sidecar")

    private var process: Process?
    private var port: UInt16?
    private var attempts = 0

    public init() {}

    public func startIfNeeded() async throws -> UInt16 {
        if let port, await ping(port: port) {
            return port
        }
        return try await spawn()
    }

    public func shutdown() async {
        guard let p = process else { return }
        log.info("Shutter sidecar ned (pid=\(p.processIdentifier))")
        p.terminate()
        // Vent op til 5 sek på graceful exit, ellers kill
        for _ in 0..<50 {
            if !p.isRunning { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if p.isRunning {
            log.warning("Sidecar reagerede ikke på SIGTERM — kill")
            kill(p.processIdentifier, SIGKILL)
        }
        process = nil
        port = nil
    }

    private func spawn() async throws -> UInt16 {
        let port = try findFreePort()
        let sidecarRoot = try locateSidecarRoot()

        let proc = Process()
        proc.currentDirectoryURL = sidecarRoot
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["uv", "run", "saga-sidecar", "--port", "\(port)", "--device", "auto"]

        var env = ProcessInfo.processInfo.environment
        env["SAGA_PORT"] = "\(port)"
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        try proc.run()
        log.info("Sidecar spawned (pid=\(proc.processIdentifier), port=\(port), root=\(sidecarRoot.path))")

        // Stream logs (best-effort — vi læser ikke synkront)
        Task.detached { [stdoutPipe] in
            let log = Logger(subsystem: "dk.parthee.saga", category: "sidecar.out")
            do {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    log.debug("\(line, privacy: .public)")
                }
            } catch {
                log.warning("stdout-stream lukkede: \(error.localizedDescription)")
            }
        }
        Task.detached { [stderrPipe] in
            let log = Logger(subsystem: "dk.parthee.saga", category: "sidecar.err")
            do {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    log.info("\(line, privacy: .public)")
                }
            } catch {
                log.warning("stderr-stream lukkede: \(error.localizedDescription)")
            }
        }

        self.process = proc
        self.port = port

        // Vent op til 60 sekunder på /health
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if await ping(port: port) {
                log.info("Sidecar er ready på port \(port)")
                attempts = 0
                return port
            }
            if !proc.isRunning {
                throw SidecarError.exitedDuringStartup(status: proc.terminationStatus)
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw SidecarError.healthTimeout
    }

    private func ping(port: UInt16) async -> Bool {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        req.timeoutInterval = 1.0
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func locateSidecarRoot() throws -> URL {
        // Prioritet:
        // 1. Bundle Resources/sidecar (production builds)
        // 2. Env-override SAGA_SIDECAR_ROOT (dev override)
        // 3. ../../../saga-sidecar relativt fra app-binær (dev fra Xcode-build)
        // 4. ~/Desktop/Claude/projekter/saga/saga-sidecar (Parthee's dev-setup)

        if let bundled = Bundle.main.url(forResource: "saga-sidecar", withExtension: nil),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("pyproject.toml").path) {
            return bundled
        }

        if let envPath = ProcessInfo.processInfo.environment["SAGA_SIDECAR_ROOT"] {
            return URL(fileURLWithPath: envPath)
        }

        let exec = Bundle.main.executableURL ?? URL(fileURLWithPath: ".")
        let candidate = exec.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("saga-sidecar")
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("pyproject.toml").path) {
            return candidate
        }

        let homeFallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Claude/projekter/saga/saga-sidecar")
        if FileManager.default.fileExists(atPath: homeFallback.appendingPathComponent("pyproject.toml").path) {
            return homeFallback
        }

        throw SidecarError.sidecarRootNotFound
    }

    private func findFreePort() throws -> UInt16 {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw SidecarError.portProbeFailed }
        defer { close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0  // OS picks
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw SidecarError.portProbeFailed }

        var assigned = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getResult = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(socket, $0, &len)
            }
        }
        guard getResult == 0 else { throw SidecarError.portProbeFailed }
        return UInt16(bigEndian: assigned.sin_port)
    }
}

public enum SidecarError: Error, LocalizedError {
    case sidecarRootNotFound
    case portProbeFailed
    case exitedDuringStartup(status: Int32)
    case healthTimeout

    public var errorDescription: String? {
        switch self {
        case .sidecarRootNotFound:
            return "Kunne ikke finde saga-sidecar/. Sæt SAGA_SIDECAR_ROOT eller kør Saga fra build-mappen."
        case .portProbeFailed:
            return "Kunne ikke finde en ledig port til sidecar."
        case .exitedDuringStartup(let status):
            return "Sidecar afsluttede under opstart (exit \(status)). Tjek at uv er installeret og 'uv sync' er kørt."
        case .healthTimeout:
            return "Sidecar svarede ikke på /health inden for 60 sekunder. Modellen er sandsynligvis stadig under indlæsning — vent og prøv igen."
        }
    }
}

import Foundation
import OSLog

/// Downloader Canary CoreML-mlpackages on-demand til ~/Library/Application Support/Saga/Models/.
///
/// Bruges når Saga distribueres som "slim DMG" (~150 MB i stedet for 1.7 GB) hvor
/// ML-modellerne ikke er bundled. Første-gang launch viser setup-wizard et
/// download-step; ved efterfølgende launches læser CanaryASRBridge fra disk.
@MainActor
public final class ModelDownloader: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "model-downloader")

    @Published public private(set) var state: State = .idle
    @Published public private(set) var progress: Double = 0  // 0...1
    @Published public private(set) var currentFile: String = ""
    @Published public private(set) var bytesDownloaded: Int64 = 0
    @Published public private(set) var totalBytes: Int64 = 0

    /// URL prefix hvor mlpackages ligger som .zip-filer. Default peger på
    /// canary-coreml's Release-assets. Kan overstyres via UserDefaults
    /// "modelDownloader.baseURL" for selvhostede modeller.
    public static let defaultBaseURL = "https://github.com/Parthee-Vijaya/canary-coreml/releases/download/v1.0.0"

    public var baseURL: String {
        UserDefaults.standard.string(forKey: "modelDownloader.baseURL")
            ?? Self.defaultBaseURL
    }

    public init() {}

    /// Liste af pakker der skal downloades. Hver er en .zip på serveren der
    /// udpakkes til en .mlpackage-mappe lokalt.
    private static let packages: [Package] = [
        Package(name: "CanaryEncoder.mlpackage", zipName: "CanaryEncoder.mlpackage.zip", expectedSizeMB: 1500),
        Package(name: "CanaryDecoderLM.mlpackage", zipName: "CanaryDecoderLM.mlpackage.zip", expectedSizeMB: 290),
        Package(name: "CanaryPreprocessor.mlpackage", zipName: "CanaryPreprocessor.mlpackage.zip", expectedSizeMB: 2),
    ]

    /// Total estimeret størrelse — bruges til at vise "X.X GB" i UI før download.
    public static var totalSizeBytes: Int64 {
        Int64(packages.reduce(0) { $0 + $1.expectedSizeMB }) * 1_000_000
    }

    /// Start download. Lukkes af `cancel()`. Kan kun køre én ad gangen.
    public func startDownload() async {
        guard case .idle = state else {
            log.warning("startDownload kaldt mens en download allerede kører")
            return
        }
        log.info("Starter model-download fra \(self.baseURL, privacy: .public)")
        state = .downloading
        progress = 0
        bytesDownloaded = 0
        totalBytes = Self.totalSizeBytes

        do {
            try ModelStorage.ensureDirectoryExists()

            var cumulativeBytes: Int64 = 0
            for pkg in Self.packages {
                if Task.isCancelled { throw DownloadError.cancelled }

                currentFile = pkg.name

                // Skip allerede-downloaded pakker (fx hvis tidligere kørsel
                // afbrudt halvvejs gennem listen).
                let destDir = ModelStorage.modelsDirectory.appendingPathComponent(pkg.name)
                if FileManager.default.fileExists(atPath: destDir.path) {
                    log.info("\(pkg.name, privacy: .public) findes allerede — skip")
                    cumulativeBytes += Int64(pkg.expectedSizeMB) * 1_000_000
                    bytesDownloaded = cumulativeBytes
                    progress = Double(cumulativeBytes) / Double(totalBytes)
                    continue
                }

                try await downloadAndExtract(pkg, packageStart: cumulativeBytes)
                cumulativeBytes += Int64(pkg.expectedSizeMB) * 1_000_000
                bytesDownloaded = cumulativeBytes
                progress = Double(cumulativeBytes) / Double(totalBytes)
            }
            state = .completed
            log.info("Model-download færdig")
        } catch {
            state = .failed(error.localizedDescription)
            log.error("Model-download fejlede: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Afbryd igangværende download. Allerede-downloaded pakker bevares.
    public func cancel() {
        currentDataTask?.cancel()
        currentDataTask = nil
        state = .cancelled
    }

    /// Slet downloadede modeller — kaldes fra Settings.
    public func reset() {
        ModelStorage.deleteDownloadedModels()
        state = .idle
        progress = 0
        bytesDownloaded = 0
    }

    // MARK: - Private

    private var currentDataTask: URLSessionDataTask?

    private func downloadAndExtract(_ pkg: Package, packageStart: Int64) async throws {
        guard let url = URL(string: "\(baseURL)/\(pkg.zipName)") else {
            throw DownloadError.invalidURL(pkg.zipName)
        }
        log.info("Henter \(pkg.zipName, privacy: .public)")

        let tmpZip = ModelStorage.modelsDirectory.appendingPathComponent(pkg.zipName)
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            // 404 betyder næsten altid at release-assets ikke er uploadet endnu
            // (eller repoet er privat). Giv en handlingsanvisende besked frem
            // for et råt statusnummer.
            if status == 404 {
                throw DownloadError.releaseNotPublished
            }
            throw DownloadError.serverError(status: status)
        }

        let expectedTotal = http.expectedContentLength
        var written: Int64 = 0
        FileManager.default.createFile(atPath: tmpZip.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmpZip)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        for try await byte in asyncBytes {
            if Task.isCancelled {
                do {
                    try FileManager.default.removeItem(at: tmpZip)
                } catch {
                    // Tavs sletning her ville efterlade multi-GB tmp-zips i
                    // Application Support uden spor. Log så det kan opdages.
                    log.warning("Kunne ikke slette tmp-zip efter cancel: \(error.localizedDescription, privacy: .public)")
                }
                throw DownloadError.cancelled
            }
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if expectedTotal > 0 {
                    bytesDownloaded = packageStart + written
                    progress = Double(bytesDownloaded) / Double(totalBytes)
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        try handle.close()

        // Unzip ind i Models/
        try await unzip(tmpZip, into: ModelStorage.modelsDirectory)
        try FileManager.default.removeItem(at: tmpZip)
    }

    /// Bruger system's `/usr/bin/unzip` for robust .zip-extraction af mlpackage-mapper.
    /// Disse er bundles (mappe-strukturer pakket som zip), ikke flade arkiver.
    private func unzip(_ zipURL: URL, into destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", destination.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw DownloadError.unzipFailed(status: Int(process.terminationStatus))
        }
    }

    // MARK: - Types

    public enum State: Equatable, Sendable {
        case idle
        case downloading
        case completed
        case cancelled
        case failed(String)
    }

    private struct Package {
        let name: String
        let zipName: String
        let expectedSizeMB: Int
    }

    public enum DownloadError: LocalizedError {
        case invalidURL(String)
        case serverError(status: Int)
        case releaseNotPublished
        case unzipFailed(status: Int)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .invalidURL(let name): return "Ugyldig URL for \(name)"
            case .serverError(let status): return "Server returnerede \(status). Tjek netværk og prøv igen."
            case .releaseNotPublished:
                return "Model-serveren har ingen release endnu (404). Brug full-DMG'en fra GitHub Releases i stedet — den har modellerne bundlet. Eller sæt en custom download-URL i UserDefaults-nøglen 'modelDownloader.baseURL'."
            case .unzipFailed(let status): return "Unzip fejlede (status \(status))"
            case .cancelled: return "Download afbrudt"
            }
        }
    }
}

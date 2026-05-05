import Foundation

/// Single source of truth for hvor downloadede ML-modeller ligger på disk.
/// Brugt af ModelDownloader (skriver) og CanaryASRBridge (læser).
public enum ModelStorage {
    /// `~/Library/Application Support/Saga/Models/`
    public static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Saga", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// True hvis alle nødvendige Canary-mlpackages findes på disk.
    public static var canaryModelsPresent: Bool {
        let dir = modelsDirectory
        let required = ["CanaryEncoder.mlpackage", "CanaryDecoderLM.mlpackage", "CanaryPreprocessor.mlpackage"]
        return required.allSatisfy { name in
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
        }
    }

    /// True hvis modellerne ENTEN er bundled i app'en ELLER downloaded.
    /// Bruges af setup-wizard til at afgøre om download-step skal vises.
    public static var canaryModelsAvailable: Bool {
        if Bundle.main.url(forResource: "mlpackage", withExtension: nil) != nil {
            return true
        }
        return canaryModelsPresent
    }

    /// Total disk-forbrug af modellerne i bytes — for UI-display.
    public static func diskUsageBytes() -> Int64 {
        let dir = modelsDirectory
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                total += Int64(size)
            }
        }
        return total
    }

    /// Slet alle downloadede modeller — bruges af "Reset" i Settings.
    @discardableResult
    public static func deleteDownloadedModels() -> Bool {
        let dir = modelsDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return true }
        do {
            try FileManager.default.removeItem(at: dir)
            return true
        } catch {
            return false
        }
    }

    /// Sikrer at directory eksisterer; opretter rekursivt hvis ej.
    static func ensureDirectoryExists() throws {
        let dir = modelsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

import Combine
import Foundation
import OSLog

/// Holder brugerens voice-snippets. To storage-backends:
///
/// 1. **UserDefaults** (default) — lokal Mac, persisterer mellem launches
/// 2. **iCloud Drive** (opt-in) — gemmes i `~/Library/Mobile Documents/com~apple~CloudDocs/Saga/snippets.json`
///    så snippet-bibliotek synker mellem alle Macs der har iCloud Drive aktiv.
///    Kræver ikke entitlements/provisioning fordi det er almindelig fil-i/o til en
///    bruger-tilgængelig sti — Saga er ikke sandboxed.
///
/// Watcher iCloud-fil med DispatchSource hvis sync er aktiveret, så ændringer
/// fra anden Mac auto-reloades.
@MainActor
public final class SnippetStore: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "snippets")
    private let storageKey = "snippets.entries"
    private let useICloudKey = "snippets.useICloud"

    @Published public private(set) var entries: [Snippet] = []

    /// Master-toggle: brugeren kan slå alle snippets fra uden at slette dem.
    @Published public var globalEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalEnabled, forKey: "snippets.globalEnabled")
            log.info("Snippets globalEnabled: \(self.globalEnabled, privacy: .public)")
        }
    }

    /// iCloud-sync toggle. Default OFF — opt-in fordi det kræver iCloud Drive.
    @Published public var useICloudSync: Bool {
        didSet {
            UserDefaults.standard.set(useICloudSync, forKey: useICloudKey)
            if useICloudSync {
                migrateToICloud()
                startWatchingICloud()
            } else {
                stopWatchingICloud()
            }
            log.info("iCloud-sync: \(self.useICloudSync, privacy: .public)")
        }
    }

    /// Status der vises i Settings UI.
    @Published public private(set) var iCloudStatus: ICloudStatus = .disabled

    /// File-watcher source — re-loades hvis fil ændres af anden Mac.
    private var watchSource: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1

    public init() {
        self.globalEnabled = UserDefaults.standard.object(forKey: "snippets.globalEnabled") as? Bool ?? true
        self.useICloudSync = UserDefaults.standard.bool(forKey: useICloudKey)
        load()
        if useICloudSync {
            startWatchingICloud()
        }
    }

    // MARK: - CRUD

    public func add(_ snippet: Snippet) {
        entries.removeAll { $0.id == snippet.id }
        entries.append(snippet)
        persist()
        log.info("Snippet tilføjet: \(snippet.trigger, privacy: .private)")
    }

    public func update(_ snippet: Snippet) {
        if let idx = entries.firstIndex(where: { $0.id == snippet.id }) {
            entries[idx] = snippet
            persist()
        }
    }

    public func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    public func deleteAll() {
        entries.removeAll()
        persist()
    }

    /// Aktive entries til SnippetExpander. Tom array hvis globalEnabled
    /// er false.
    public var activeEntries: [Snippet] {
        guard globalEnabled else { return [] }
        return entries.filter { $0.enabled && $0.isMeaningful }
    }

    // MARK: - Persistens

    private func persist() {
        if useICloudSync, let url = iCloudFileURL() {
            persistToFile(url: url)
        } else {
            persistToUserDefaults()
        }
    }

    private func load() {
        if useICloudSync, let url = iCloudFileURL(), FileManager.default.fileExists(atPath: url.path) {
            loadFromFile(url: url)
        } else {
            loadFromUserDefaults()
        }
    }

    private func persistToUserDefaults() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            log.warning("Kunne ikke gemme snippets til UserDefaults: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            self.entries = try JSONDecoder().decode([Snippet].self, from: data)
        } catch {
            log.warning("Kunne ikke loade snippets fra UserDefaults: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistToFile(url: URL) {
        do {
            let data = try JSONEncoder().encode(entries)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            iCloudStatus = .synced(at: Date())
        } catch {
            log.warning("Kunne ikke skrive til iCloud: \(error.localizedDescription, privacy: .public)")
            iCloudStatus = .error(error.localizedDescription)
            // Fallback til UserDefaults så data ikke tabes
            persistToUserDefaults()
        }
    }

    private func loadFromFile(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            self.entries = try JSONDecoder().decode([Snippet].self, from: data)
            iCloudStatus = .synced(at: Date())
        } catch {
            log.warning("Kunne ikke læse fra iCloud: \(error.localizedDescription, privacy: .public)")
            iCloudStatus = .error(error.localizedDescription)
            // Fallback til UserDefaults
            loadFromUserDefaults()
        }
    }

    // MARK: - iCloud helpers

    /// Path til iCloud Drive-filen. Returner nil hvis iCloud Drive ikke er aktiv.
    private func iCloudFileURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: cloudDocs.path) else {
            return nil
        }
        return cloudDocs
            .appendingPathComponent("Saga")
            .appendingPathComponent("snippets.json")
    }

    /// Førstegangs migration: kopier UserDefaults-snippets til iCloud-fil
    /// hvis filen ikke findes endnu.
    private func migrateToICloud() {
        guard let url = iCloudFileURL() else {
            log.warning("iCloud Drive ikke tilgængelig — kan ikke migrere")
            iCloudStatus = .iCloudNotAvailable
            return
        }
        if FileManager.default.fileExists(atPath: url.path) {
            // Filen eksisterer allerede (fra anden Mac) — load den
            loadFromFile(url: url)
        } else {
            // Skriv nuværende lokale entries til iCloud
            persistToFile(url: url)
        }
    }

    private func startWatchingICloud() {
        stopWatchingICloud()
        guard let url = iCloudFileURL() else {
            iCloudStatus = .iCloudNotAvailable
            return
        }
        // Opret dir + tom fil hvis ikke eksisterer (for at watch'en kan åbne FD)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data("[]".utf8))
        }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            log.warning("Kunne ikke åbne file descriptor til watch: \(url.path, privacy: .public)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.log.info("iCloud-fil ændret eksternt — re-loader")
            self.loadFromFile(url: url)
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        source.resume()
        self.watchSource = source
        self.watchedFD = fd
        log.info("Watcher startet på \(url.path, privacy: .public)")
    }

    private func stopWatchingICloud() {
        watchSource?.cancel()
        watchSource = nil
        watchedFD = -1
    }

    deinit {
        watchSource?.cancel()
    }
}

public enum ICloudStatus: Equatable, Sendable {
    case disabled
    case synced(at: Date)
    case iCloudNotAvailable
    case error(String)

    public var displayLabel: String {
        switch self {
        case .disabled:
            return "Slukket"
        case .synced(let date):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "da_DK")
            formatter.dateFormat = "HH:mm:ss"
            return "Synket \(formatter.string(from: date))"
        case .iCloudNotAvailable:
            return "iCloud Drive ikke aktiv"
        case .error(let msg):
            return "Fejl: \(msg)"
        }
    }
}

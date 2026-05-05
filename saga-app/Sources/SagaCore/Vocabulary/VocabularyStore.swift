import Combine
import Foundation
import OSLog

/// Holder brugerens vocabulary-entries. Persisteres som JSON i UserDefaults
/// (samme mønster som ModeRouter.custom).
@MainActor
public final class VocabularyStore: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "vocabulary")
    private let storageKey = "vocabulary.entries"

    @Published public private(set) var entries: [VocabularyEntry] = []

    /// Master-toggle: brugeren kan slå hele vocabulary fra uden at slette entries.
    @Published public var globalEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalEnabled, forKey: "vocabulary.globalEnabled")
            log.info("Vocabulary globalEnabled: \(self.globalEnabled, privacy: .public)")
        }
    }

    public init() {
        self.globalEnabled = UserDefaults.standard.object(forKey: "vocabulary.globalEnabled") as? Bool ?? true
        load()
    }

    // MARK: - CRUD

    public func add(_ entry: VocabularyEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        persist()
        log.info("Vocabulary tilføjet: \(entry.pattern, privacy: .private)")
    }

    public func update(_ entry: VocabularyEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
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

    /// De entries der faktisk skal anvendes til en transkription —
    /// filtrerer disabled + meningsløse entries fra.
    public var activeEntries: [VocabularyEntry] {
        guard globalEnabled else { return [] }
        return entries.filter { $0.enabled && $0.isMeaningful }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            entries = try JSONDecoder().decode([VocabularyEntry].self, from: data)
        } catch {
            log.warning("Kunne ikke læse vocabulary: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            log.warning("Kunne ikke gemme vocabulary: \(error.localizedDescription, privacy: .public)")
        }
    }
}

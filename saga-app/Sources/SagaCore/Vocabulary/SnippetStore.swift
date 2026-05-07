import Combine
import Foundation
import OSLog

/// Holder brugerens voice-snippets. Persisteres som JSON i UserDefaults
/// (samme mønster som VocabularyStore).
@MainActor
public final class SnippetStore: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "snippets")
    private let storageKey = "snippets.entries"

    @Published public private(set) var entries: [Snippet] = []

    /// Master-toggle: brugeren kan slå alle snippets fra uden at slette dem.
    @Published public var globalEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalEnabled, forKey: "snippets.globalEnabled")
            log.info("Snippets globalEnabled: \(self.globalEnabled, privacy: .public)")
        }
    }

    public init() {
        self.globalEnabled = UserDefaults.standard.object(forKey: "snippets.globalEnabled") as? Bool ?? true
        load()
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
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            log.warning("Kunne ikke gemme snippets: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            self.entries = try JSONDecoder().decode([Snippet].self, from: data)
        } catch {
            log.warning("Kunne ikke loade snippets: \(error.localizedDescription, privacy: .public)")
        }
    }
}

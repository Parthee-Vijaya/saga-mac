import AppKit
import Combine
import Foundation
import OSLog

/// Holder bruger-definerede per-app profiler og slår op på frontmost-app
/// når SagaController har brug for det.
@MainActor
public final class AppProfileStore: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "profiles")
    private let storageKey = "appProfiles.entries"

    @Published public private(set) var profiles: [AppProfile] = []

    /// Master-toggle — slå hele per-app-system fra uden at slette profiler.
    @Published public var globalEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalEnabled, forKey: "appProfiles.globalEnabled")
        }
    }

    public init() {
        // Default ON — featuren er valgfri men non-disruptive (kun aktiv hvis
        // brugeren faktisk har oprettet en profil for current app).
        self.globalEnabled = UserDefaults.standard.object(forKey: "appProfiles.globalEnabled") as? Bool ?? true
        load()
    }

    // MARK: - Lookup

    /// Returnerer profilen der gælder for den frontmost app, eller nil hvis ingen.
    public func currentProfile() -> AppProfile? {
        guard globalEnabled else { return nil }
        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return nil
        }
        return profiles.first { $0.enabled && $0.bundleIdentifier == bundleId }
    }

    /// Returnerer bundleIdentifier + best-effort display name for frontmost-app.
    /// Bruges af "Tilføj profil for current app"-knap i Settings.
    public func frontmostAppInfo() -> (bundleId: String, displayName: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else { return nil }
        let name = app.localizedName ?? bundleId
        return (bundleId, name)
    }

    // MARK: - CRUD

    public func add(_ profile: AppProfile) {
        // Forhindrer duplicate bundleIdentifier — opdat eksisterende i stedet
        if let idx = profiles.firstIndex(where: { $0.bundleIdentifier == profile.bundleIdentifier }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        persist()
        log.info("Profil tilføjet: \(profile.bundleIdentifier, privacy: .public)")
    }

    public func update(_ profile: AppProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            persist()
        }
    }

    public func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    public func deleteAll() {
        profiles.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            profiles = try JSONDecoder().decode([AppProfile].self, from: data)
        } catch {
            log.warning("Kunne ikke læse profiler: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(profiles)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            log.warning("Kunne ikke gemme profiler: \(error.localizedDescription, privacy: .public)")
        }
    }
}

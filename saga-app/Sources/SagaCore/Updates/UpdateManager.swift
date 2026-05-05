import Foundation
import OSLog
import Sparkle

/// Tynd wrapper omkring Sparkle's `SPUStandardUpdaterController`.
///
/// Sparkle håndterer al kompleksitet (download, EdDSA-verifikation, restart-prompt).
/// Vi eksponerer bare `checkForUpdates()` til Settings-knappen, plus auto-check
/// toggle som @Published så SwiftUI kan binde til den.
@MainActor
public final class UpdateManager: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "updates")
    private let controller: SPUStandardUpdaterController

    @Published public var automaticChecksEnabled: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticChecksEnabled
        }
    }

    public var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }

    public var feedURL: URL? {
        controller.updater.feedURL
    }

    /// True hvis Sparkle er konfigureret med en rigtig EdDSA-nøgle (ikke placeholder).
    public static var isConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return !key.hasPrefix("REPLACE_WITH_") && !key.isEmpty
    }

    public init() {
        // startingUpdater: false så vi kan instantiere fra @MainActor-context;
        // kalder start() manuelt fra bootIfNeeded når app er klar.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.automaticChecksEnabled = controller.updater.automaticallyChecksForUpdates
    }

    /// Start updater (registrér scheduled checks). Kaldes fra SagaController.bootIfNeeded.
    /// Skipper helt hvis Sparkle ikke er konfigureret (SUPublicEDKey placeholder),
    /// for at undgå "The updater failed to start"-dialog ved hver app-launch.
    public func start() {
        guard Self.isConfigured else {
            log.info("Sparkle disabled: SUPublicEDKey er placeholder (sæt rigtig key i project.yml for at aktivere auto-update)")
            return
        }
        controller.startUpdater()
        log.info("Sparkle started, feedURL=\(self.feedURL?.absoluteString ?? "?", privacy: .public)")
    }

    /// Trigger manuel update-check. Sparkle viser sit eget UI (alert hvis up-to-date,
    /// download-prompt hvis ny version findes). No-op hvis Sparkle er deaktiveret.
    public func checkForUpdates() {
        guard Self.isConfigured else {
            log.warning("Manuel update-check ignoreret: Sparkle er ikke konfigureret")
            return
        }
        log.info("Manuel update-check trigget")
        controller.checkForUpdates(nil)
    }
}

import AppKit
import Combine
import SwiftUI
import OSLog

/// Status-bar-icon + dropdown menu. Reflekterer SagaController.state via icon-skift.
@MainActor
public final class MenubarController: NSObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "menubar")

    private var statusItem: NSStatusItem?
    private weak var controller: SagaController?
    private var cancellables: Set<AnyCancellable> = []

    public override init() {}

    public func attach(controller: SagaController) {
        self.controller = controller
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = icon(for: .idle)
            button.image?.isTemplate = true
            button.toolTip = "Saga"
        }
        item.menu = buildMenu()
        self.statusItem = item

        controller.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.statusItem?.button?.image = self?.icon(for: state)
            }
            .store(in: &cancellables)
    }

    public func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    public func show(error: String) {
        let alert = NSAlert()
        alert.messageText = "Saga"
        alert.informativeText = error
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: "Tilstand: Idle", action: nil, keyEquivalent: "")
        statusItem.identifier = NSUserInterfaceItemIdentifier("status")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Indstillinger…",
            action: #selector(openSettingsAction(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Afslut Saga",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openSettingsAction(_ sender: Any?) {
        openSettings()
    }

    private func icon(for state: SagaState) -> NSImage? {
        let symbolName: String
        switch state {
        case .idle: symbolName = "mic.slash"
        case .recording: symbolName = "mic.fill"
        case .transcribing: symbolName = "waveform"
        case .routing: symbolName = "sparkles"
        }
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Saga \(state)")
        return img
    }
}

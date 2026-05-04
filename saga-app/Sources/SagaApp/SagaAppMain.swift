import AppKit
import SwiftUI

@main
struct SagaAppMain: App {
    @NSApplicationDelegateAdaptor(SagaAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.controller)
        }
    }
}

@MainActor
final class SagaAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let controller = SagaController()

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in self.controller.start() }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in self.controller.stop() }
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in self.controller.menubar.openSettings() }
        return true
    }
}

import AppKit
import SwiftUI

@main
struct SagaAppMain: App {
    @NSApplicationDelegateAdaptor(SagaAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusView()
                .environmentObject(appDelegate.controller)
                .frame(width: 360)
        } label: {
            // Vi binder ikon-navnet via en tynd wrapper-view, så MenuBarExtra
            // re-evaluerer label når controller-state ændres
            MenuBarLabel()
                .environmentObject(appDelegate.controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.controller)
        }

        Window("Saga – Historik", id: "history") {
            HistoryWindow()
                .environmentObject(appDelegate.controller)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 640, height: 480)

    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject var controller: SagaController
    var body: some View {
        Image(systemName: controller.menuBarIconName)
    }
}

@MainActor
final class SagaAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let controller = SagaController()

    private var firstRunWindow: NSWindow?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await self.controller.bootIfNeeded()
            self.showFirstRunIfNeeded()
        }
    }

    @MainActor
    private func showFirstRunIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "firstRunComplete") else { return }
        guard firstRunWindow == nil else { return }

        let view = FirstRunWindow()
            .environmentObject(controller)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "Velkommen til Saga"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 560, height: 660))
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        firstRunWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

extension SagaAppDelegate: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            // Marker first-run done når wizard lukkes — også hvis bruger lukker
            // via X-knappen i stedet for "Kom i gang".
            UserDefaults.standard.set(true, forKey: "firstRunComplete")
            self.firstRunWindow = nil
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        // Synchronous shutdown så sidecar-procesen får SIGTERM før vi dør
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await self.controller.shutdown()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)
    }
}

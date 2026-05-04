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

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await self.controller.bootIfNeeded()
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

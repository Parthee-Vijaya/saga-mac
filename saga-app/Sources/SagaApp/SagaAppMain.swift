import AppKit
import SwiftUI

@main
struct SagaAppMain: App {
    @StateObject private var controller = SagaController()

    init() {
        // Start backend så snart app'en spawner — ikke vente på at popover åbnes
        // (kan ikke kalde StateObject-property i init, så vi triggers via .task)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusView()
                .environmentObject(controller)
                .frame(width: 360)
                .task { await controller.bootIfNeeded() }
        } label: {
            Label("Saga", systemImage: controller.menuBarIconName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(controller)
        }

        Window("Saga – Historik", id: "history") {
            HistoryWindow()
                .environmentObject(controller)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 640, height: 480)
    }
}

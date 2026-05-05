import AVFoundation
import AppKit
import SwiftUI

struct GeneralSettingsTab: View {
    @EnvironmentObject private var controller: SagaController
    @AppStorage("hotkey") private var hotkeyRaw: String = Hotkey.rightOption.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard("Mode") {
                    SettingsRow(
                        "Stenograf-mode",
                        subtitle: "Ren dictation. Springer alt LLM-routing over (modes, reminders, vision, document-analyse)."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { controller.stenografMode },
                            set: { controller.stenografMode = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }

                SettingsCard("Push-to-talk") {
                    SettingsRow(
                        "Hotkey",
                        subtitle: hotkeyHelp
                    ) {
                        Picker("", selection: $hotkeyRaw) {
                            ForEach(Hotkey.allCases, id: \.rawValue) { key in
                                Text(key.displayName).tag(key.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }

                SettingsCard("Permissions") {
                    PermissionsRow(
                        title: "Mikrofon",
                        granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                    )
                    Divider().padding(.vertical, 4)
                    PermissionsRow(
                        title: "Accessibility",
                        granted: AXIsProcessTrusted()
                    )
                    Divider().padding(.vertical, 4)
                    HStack {
                        Spacer()
                        Button("Åbn Privacy & Security…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onChange(of: hotkeyRaw) { _, _ in
            controller.hotkeys.stopListening()
            controller.hotkeys.startListening()
        }
    }

    private var hotkeyHelp: String {
        guard let key = Hotkey(rawValue: hotkeyRaw) else { return "" }
        switch key {
        case .fn:
            return "Apple's globe-tast. Virker IKKE på Logitech/3rd-party keyboards."
        case .rightOption, .leftOption:
            return "Universal — virker på alle keyboards inkl. Logitech MX, Magic Keyboard, USB."
        case .rightCommand, .rightControl:
            return "Sjældent brugt til normalt arbejde. Sikker hvis ⌥ er optaget."
        }
    }
}

struct PermissionsRow: View {
    let title: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(granted ? .green : .orange)
            Text(title).font(.system(size: 13))
            Spacer()
            Text(granted ? "Tilladt" : "Mangler")
                .font(.caption)
                .foregroundColor(granted ? .green : .orange)
        }
    }
}

import AVFoundation
import AppKit
import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var controller: SagaController

    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("Generelt", systemImage: "gearshape") }
            ModesSettingsTab()
                .tabItem { Label("Modes", systemImage: "wand.and.stars") }
            AboutTab()
                .tabItem { Label("Om", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}

struct GeneralSettingsTab: View {
    @EnvironmentObject private var controller: SagaController
    @AppStorage("hotkey") private var hotkeyRaw: String = Hotkey.rightOption.rawValue
    @AppStorage("lmStudioBaseURL") private var lmStudioBaseURL: String = "http://localhost:1234/v1"
    @AppStorage("lmStudioModel") private var lmStudioModel: String = "gemma-4-26b-a4b"

    var body: some View {
        Form {
            Section("Push-to-talk-tast") {
                Picker("Hotkey", selection: $hotkeyRaw) {
                    ForEach(Hotkey.allCases, id: \.rawValue) { key in
                        Text(key.displayName).tag(key.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Text(hotkeyHelp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("LM Studio") {
                LMStudioDiscoverySection(
                    baseURL: $lmStudioBaseURL,
                    model: $lmStudioModel
                )
                .environmentObject(controller)
            }
            Section("Permissions") {
                PermissionStatusRow(
                    title: "Mikrofon",
                    status: AVCaptureDevice.authorizationStatus(for: .audio).description
                )
                PermissionStatusRow(
                    title: "Accessibility",
                    status: AXIsProcessTrusted() ? "Tilladt" : "Mangler"
                )
                Button("Åbn Privacy & Security") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding()
        .onChange(of: hotkeyRaw) { _, _ in
            // Reload event-tap så ny hotkey aktiveres uden genstart
            controller.hotkeys.stopListening()
            controller.hotkeys.startListening()
        }
    }

    private var hotkeyHelp: String {
        guard let key = Hotkey(rawValue: hotkeyRaw) else { return "" }
        switch key {
        case .fn:
            return "Apple's globe-tast. Virker IKKE på Logitech/3rd-party keyboards — vælg Højre Option i stedet."
        case .rightOption, .leftOption:
            return "Universal — virker på alle keyboards inkl. Logitech MX, Magic Keyboard, USB-keyboards."
        case .rightCommand, .rightControl:
            return "Sjældent brugt til normalt arbejde. Sikker hvis du har Option-tasten optaget af noget andet."
        }
    }
}

struct LMStudioDiscoverySection: View {
    @EnvironmentObject private var controller: SagaController
    @Binding var baseURL: String
    @Binding var model: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    Task { await controller.discoverLMStudio() }
                } label: {
                    if controller.isDiscoveringLMStudio {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Søger…")
                        }
                    } else {
                        Label("Find LM Studio igen", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(controller.isDiscoveringLMStudio)

                Spacer()

                if !controller.discoveredEndpoints.isEmpty {
                    Text("\(controller.discoveredEndpoints.count) fundet")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            if !controller.discoveredEndpoints.isEmpty {
                ForEach(controller.discoveredEndpoints) { endpoint in
                    Button {
                        baseURL = endpoint.baseURL.absoluteString
                        if let firstModel = endpoint.models.first {
                            model = firstModel
                        }
                    } label: {
                        HStack {
                            Image(systemName: baseURL == endpoint.baseURL.absoluteString ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("localhost:\(endpoint.port)")
                                    .font(.system(size: 12, weight: .medium))
                                Text(endpoint.models.joined(separator: ", "))
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else if !controller.isDiscoveringLMStudio {
                Text("Ingen LM Studio fundet på localhost. Start LM Studio og klik 'Find igen'.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Divider().padding(.vertical, 4)

            TextField("Base URL", text: $baseURL)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
            TextField("Model", text: $model)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())

            Text("Saga scanner localhost-porte 1234, 1235, 8080, 5000, 11434, 8000 ved hver app-start. Bruges kun til mode-routing — pure dictation virker uden.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ModesSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Indbyggede modes")
                .font(.headline)
            ForEach(Mode.builtins) { mode in
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(mode.title).font(.body.bold())
                        Text(mode.triggers.joined(separator: " · "))
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            Spacer()
            Text("Custom modes kommer i M6.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("Saga").font(.system(size: 24, weight: .bold))
            Text("Version \(Bundle.main.shortVersion)")
                .foregroundColor(.secondary)
            Text("Mac-native voice assistant til dansk dictation og AI-modes.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Divider().padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 4) {
                Text("Drevet af NVIDIA Canary-1b-v2 (CC BY 4.0) → CoreML + lokal LM Studio.")
                Text("Ingen telemetri. Ingen cloud. Personlig brug.")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}

struct PermissionStatusRow: View {
    let title: String
    let status: String
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(status)
                .foregroundColor(status.contains("Tilladt") || status.contains("authorized") ? .green : .orange)
        }
    }
}

extension AVAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined: return "Ikke bestemt"
        case .restricted: return "Begrænset"
        case .denied: return "Nægtet"
        case .authorized: return "Tilladt"
        @unknown default: return "Ukendt"
        }
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?.?"
    }
}

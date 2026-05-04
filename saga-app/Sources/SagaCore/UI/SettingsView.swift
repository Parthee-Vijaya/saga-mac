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
    @AppStorage("lmStudioBaseURL") private var lmStudioBaseURL: String = "http://localhost:1234/v1"
    @AppStorage("lmStudioModel") private var lmStudioModel: String = "gemma-4-26b-a4b"
    @AppStorage("hviskeDevice") private var hviskeDevice: String = "auto"

    var body: some View {
        Form {
            Section("LM Studio") {
                TextField("Base URL", text: $lmStudioBaseURL)
                TextField("Model", text: $lmStudioModel)
                Text("Saga forventer LM Studio kører lokalt og eksponerer en OpenAI-kompatibel API.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("Hviske") {
                Picker("Device", selection: $hviskeDevice) {
                    Text("Auto").tag("auto")
                    Text("MPS (Apple GPU)").tag("mps")
                    Text("CPU (langsom)").tag("cpu")
                }
                Text("Skift kræver genstart af Saga.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                Button("Åbn System Settings → Privacy & Security") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding()
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
                Text("Drevet af Hviske v5.3 (CC BY-NC 4.0) og lokal LM Studio.")
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

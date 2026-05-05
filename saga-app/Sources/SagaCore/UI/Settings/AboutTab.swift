import SwiftUI

struct AboutTab: View {
    @EnvironmentObject private var controller: SagaController

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.40, green: 0.70, blue: 1.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                Text("Saga").font(.system(size: 24, weight: .bold))
                Text("Version \(Bundle.main.shortVersion)")
                    .foregroundColor(.secondary)
                Text("Mac-native voice assistant til dansk dictation.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Divider().padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Drevet af NVIDIA Canary-1b-v2 (CC BY 4.0) → CoreML.")
                    Text("Optionel mode-routing via lokal LM Studio.")
                    Text("Wake-word via Apples on-device speech recognition.")
                    Text("Ingen telemetri. Ingen cloud.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 12)

                HStack(spacing: 12) {
                    Link("GitHub", destination: URL(string: "https://github.com/Parthee-Vijaya/saga-mac")!)
                    Link("INSTALL", destination: URL(string: "https://github.com/Parthee-Vijaya/saga-mac/blob/main/docs/INSTALL.md")!)
                    Link("ROADMAP", destination: URL(string: "https://github.com/Parthee-Vijaya/saga-mac/blob/main/docs/ROADMAP.md")!)
                }
                .font(.caption)

                Divider().padding(.vertical, 8)

                UpdateCard().environmentObject(controller)
                ModelStorageCard().environmentObject(controller)
            }
            .padding(20)
        }
    }
}

// MARK: - Update card

struct UpdateCard: View {
    @EnvironmentObject private var controller: SagaController

    var body: some View {
        SettingsCard(
            "Auto-update",
            footer: "Sparkle henter signerede updates fra GitHub Releases. Kræver appcast.xml hosted (se docs/RELEASE.md)."
        ) {
            SettingsRow(
                "Tjek for opdateringer automatisk",
                subtitle: lastCheckSubtitle
            ) {
                Toggle("", isOn: Binding(
                    get: { controller.updates.automaticChecksEnabled },
                    set: { controller.updates.automaticChecksEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            Divider().padding(.vertical, 4)
            HStack {
                Spacer()
                Button {
                    controller.updates.checkForUpdates()
                } label: {
                    Label("Tjek nu", systemImage: "arrow.down.circle")
                }
            }
        }
    }

    private var lastCheckSubtitle: String {
        if let last = controller.updates.lastUpdateCheckDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Sidst tjekket \(formatter.localizedString(for: last, relativeTo: Date()))."
        }
        return "Ingen tjek udført endnu."
    }
}

// MARK: - Model storage card

struct ModelStorageCard: View {
    @EnvironmentObject private var controller: SagaController
    @State private var showResetConfirm: Bool = false

    var body: some View {
        SettingsCard(
            "Speech-modeller",
            footer: "Canary-modellerne fylder ~1.8 GB på disk. Ved slim-DMG installation downloades de første gang Saga starter."
        ) {
            HStack(spacing: 10) {
                Image(systemName: ModelStorage.canaryModelsAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(ModelStorage.canaryModelsAvailable ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ModelStorage.canaryModelsAvailable ? "Klar" : "Mangler")
                        .font(.system(size: 13, weight: .medium))
                    Text(diskUsageLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if ModelStorage.canaryModelsPresent {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Text("Slet")
                    }
                }
            }
            if case .downloading = controller.modelDownloader.state {
                Divider().padding(.vertical, 4)
                downloadProgress
            }
        }
        .confirmationDialog(
            "Slet downloadede modeller?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Slet", role: .destructive) {
                controller.modelDownloader.reset()
            }
            Button("Annuller", role: .cancel) {}
        } message: {
            Text("Du skal hente dem igen næste gang Saga starter.")
        }
    }

    private var diskUsageLabel: String {
        let bytes = ModelStorage.diskUsageBytes()
        if bytes == 0 {
            return ModelStorage.canaryModelsAvailable
                ? "Bundled i app"
                : "0 MB downloaded"
        }
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 {
            return String(format: "%.1f GB på disk", mb / 1000)
        }
        return String(format: "%.0f MB på disk", mb)
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Henter \(controller.modelDownloader.currentFile)")
                    .font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", controller.modelDownloader.progress * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.accentColor)
            }
            ProgressView(value: controller.modelDownloader.progress)
        }
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?.?"
    }
}

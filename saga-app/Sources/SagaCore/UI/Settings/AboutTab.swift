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

                StatsCard(statsStore: controller.stats).environmentObject(controller)
                UpdateCard().environmentObject(controller)
                ModelStorageCard().environmentObject(controller)
            }
            .padding(20)
        }
    }
}

// MARK: - Stats card

struct StatsCard: View {
    @EnvironmentObject private var controller: SagaController
    @ObservedObject var statsStore: TranscriptionStatsStore
    @State private var showResetConfirm: Bool = false

    var body: some View {
        SettingsCard(
            "Statistik",
            footer: "Akkumulerede tal siden første brug. Kun aggregerede counters — ingen tekst-indhold gemmes her."
        ) {
            let s = statsStore.stats
            VStack(alignment: .leading, spacing: 8) {
                StatsRow(label: "Ord transcribed", value: numberFormatter.string(from: NSNumber(value: s.totalWords)) ?? "0")
                Divider().padding(.vertical, 2)
                StatsRow(label: "Tegn transcribed", value: numberFormatter.string(from: NSNumber(value: s.totalCharacters)) ?? "0")
                Divider().padding(.vertical, 2)
                StatsRow(label: "Lyd-tid transcribed", value: formatDuration(s.totalAudioSeconds))
                Divider().padding(.vertical, 2)
                StatsRow(label: "Antal optagelser", value: numberFormatter.string(from: NSNumber(value: s.totalRecordings)) ?? "0")
                Divider().padding(.vertical, 2)
                StatsRow(
                    label: "Gennemsnitlig latens",
                    value: s.totalRecordings > 0
                        ? String(format: "%.0f ms (RTF %.2f)", s.averageInferenceSeconds * 1000, s.realTimeFactor)
                        : "—"
                )
                if let first = s.firstUsedAt {
                    Divider().padding(.vertical, 2)
                    StatsRow(label: "Siden", value: dateFormatter.string(from: first))
                }
                if s.totalRecordings > 0 {
                    Divider().padding(.vertical, 4)
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Text("Nulstil")
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Nulstil statistik?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Nulstil", role: .destructive) {
                statsStore.reset()
            }
            Button("Annuller", role: .cancel) {}
        } message: {
            Text("Alle akkumulerede tal sættes til 0. Kan ikke fortrydes.")
        }
    }

    private var numberFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        return f
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "da_DK")
        return f
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) sek" }
        if total < 3600 {
            let mins = total / 60
            let secs = total % 60
            return "\(mins) min \(secs) sek"
        }
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        return "\(hrs) t \(mins) min"
    }
}

private struct StatsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }
}

// MARK: - Update card

struct UpdateCard: View {
    @EnvironmentObject private var controller: SagaController

    var body: some View {
        SettingsCard(
            "Auto-update",
            footer: UpdateManager.isConfigured
                ? "Sparkle henter signerede updates fra GitHub Releases."
                : "Auto-update er deaktiveret indtil release-flow er sat op (SUPublicEDKey skal udskiftes — se docs/RELEASE.md)."
        ) {
            if UpdateManager.isConfigured {
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
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Deaktiveret. Du kan stadig hente nye versioner manuelt fra GitHub Releases.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
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

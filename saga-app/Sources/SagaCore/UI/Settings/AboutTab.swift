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
            }
            .padding(20)
        }
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?.?"
    }
}

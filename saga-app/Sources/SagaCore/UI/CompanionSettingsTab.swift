import AVFoundation
import SwiftUI

/// Settings-tab til Companion-mode (TTS-konfig først, conversation-toggle senere).
///
/// Sprint C1 scope: TTS engine-picker + voice-picker + ElevenLabs API-key i Keychain
/// + test-knap. Senere udvides med wake-word phrases, end-of-session-keywords, m.m.
struct CompanionSettingsTab: View {
    @EnvironmentObject private var controller: SagaController
    @State private var elevenLabsKeyDraft: String = ""
    @State private var keyEditing: Bool = false
    @State private var voiceCatalog: [ElevenLabsVoice] = []
    @State private var isFetchingVoices: Bool = false
    @State private var testRunning: Bool = false
    @State private var testStatus: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard(
                    "Stemme (Text-to-Speech)",
                    footer: "Saga skal kunne tale tilbage i Companion-mode. Apple er offline; ElevenLabs er cloud-baseret med højere kvalitet."
                ) {
                    SettingsRow(
                        "Engine",
                        subtitle: engineSubtitle
                    ) {
                        Picker("", selection: $controller.tts.preferredEngineID) {
                            Text("Apple (offline)").tag("apple")
                            Text("ElevenLabs (cloud)").tag("elevenlabs")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180)
                    }

                    if controller.tts.preferredEngineID == "apple" {
                        Divider().padding(.vertical, 4)
                        SettingsRow(
                            "Apple-stemme",
                            subtitle: "Vælg blandt installerede danske stemmer."
                        ) {
                            Picker("", selection: $controller.tts.appleVoiceID) {
                                ForEach(AppleTTSEngine.availableDanishVoices(), id: \.identifier) { voice in
                                    Text("\(voice.name) (\(qualityLabel(voice.quality)))")
                                        .tag(voice.identifier)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 220)
                        }
                    }
                }

                if controller.tts.preferredEngineID == "elevenlabs" {
                    SettingsCard(
                        "ElevenLabs",
                        footer: "API-key gemmes i din Keychain — aldrig i UserDefaults eller log-filer. Få den fra elevenlabs.io/app/settings/api-keys."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                if keyEditing {
                                    SecureField("Indsæt API-key", text: $elevenLabsKeyDraft)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.caption, design: .monospaced))
                                } else {
                                    Text(controller.tts.hasElevenLabsKey ? "•••••••• (gemt i Keychain)" : "Ingen key sat")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(controller.tts.hasElevenLabsKey ? .green : .secondary)
                                    Spacer()
                                }
                            }

                            HStack {
                                if keyEditing {
                                    Button("Annuller") {
                                        keyEditing = false
                                        elevenLabsKeyDraft = ""
                                    }
                                    Spacer()
                                    Button("Gem") {
                                        let trimmed = elevenLabsKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty {
                                            _ = KeychainStore.write(trimmed, for: KeychainKey.elevenLabsAPI)
                                            elevenLabsKeyDraft = ""
                                            keyEditing = false
                                            // Udløs UI-refresh — KeychainStore er ikke @Published
                                            controller.tts.objectWillChange.send()
                                            Task { await refreshVoiceCatalog() }
                                        }
                                    }
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(elevenLabsKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                                } else {
                                    Button(controller.tts.hasElevenLabsKey ? "Skift key" : "Tilføj key") {
                                        keyEditing = true
                                    }
                                    if controller.tts.hasElevenLabsKey {
                                        Button(role: .destructive) {
                                            _ = KeychainStore.delete(KeychainKey.elevenLabsAPI)
                                            voiceCatalog = []
                                            controller.tts.objectWillChange.send()
                                        } label: {
                                            Label("Fjern", systemImage: "trash")
                                        }
                                    }
                                    Spacer()
                                }
                            }

                            if controller.tts.hasElevenLabsKey {
                                Divider()
                                HStack {
                                    Text("Stemme")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                    Spacer()
                                    if isFetchingVoices {
                                        ProgressView().controlSize(.mini)
                                    }
                                    Button {
                                        Task { await refreshVoiceCatalog() }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Hent stemmer fra ElevenLabs")
                                }

                                if voiceCatalog.isEmpty {
                                    Text("Klik refresh for at hente listen — eller indsæt voice-ID manuelt.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("Voice-ID", text: $controller.tts.elevenLabsVoiceID)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.caption, design: .monospaced))
                                } else {
                                    Picker("", selection: $controller.tts.elevenLabsVoiceID) {
                                        ForEach(voiceCatalog) { voice in
                                            Text(voiceLabel(voice)).tag(voice.voiceID)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }

                SettingsCard(
                    "Test",
                    footer: testStatus ?? "Tryk for at høre Saga sige en kort frase med valgte engine + stemme."
                ) {
                    HStack {
                        Button {
                            runTest()
                        } label: {
                            if testRunning {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text("Taler…")
                                }
                            } else {
                                Label("Sig 'Hej, jeg er Saga'", systemImage: "speaker.wave.2.fill")
                            }
                        }
                        .disabled(testRunning)
                        Spacer()
                    }
                }

                SettingsCard(
                    "Privacy",
                    footer: nil
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        privacyLine(icon: "lock.fill", color: .green, text: "Apple TTS kører lokalt — intet forlader maskinen.")
                        if controller.tts.preferredEngineID == "elevenlabs" {
                            privacyLine(icon: "cloud.fill", color: .orange, text: "ElevenLabs sender Saga's svar-tekst til deres servere for at producere lyd. Audio fra dig sendes IKKE.")
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var engineSubtitle: String {
        switch controller.tts.preferredEngineID {
        case "elevenlabs":
            return controller.tts.hasElevenLabsKey
                ? "Cloud — premium kvalitet."
                : "Tilføj API-key herunder for at aktivere."
        default:
            return "Indbygget i macOS. Ingen netværk eller key krævet."
        }
    }

    private func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "premium"
        case .enhanced: return "enhanced"
        default: return "standard"
        }
    }

    private func voiceLabel(_ voice: ElevenLabsVoice) -> String {
        if let lang = voice.language {
            return "\(voice.name) — \(lang)"
        }
        return voice.name
    }

    private func privacyLine(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refreshVoiceCatalog() async {
        guard let key = KeychainStore.read(KeychainKey.elevenLabsAPI), !key.isEmpty else { return }
        isFetchingVoices = true
        defer { isFetchingVoices = false }
        voiceCatalog = await ElevenLabsVoiceCatalog.fetch(apiKey: key)
    }

    private func runTest() {
        testRunning = true
        testStatus = nil
        Task { @MainActor in
            await controller.tts.testSpeak()
            testRunning = false
            testStatus = controller.tts.lastUsedEngineID == "elevenlabs"
                ? "Brugte ElevenLabs."
                : "Brugte Apple TTS."
        }
    }
}

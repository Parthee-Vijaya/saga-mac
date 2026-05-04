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
            VoiceSettingsTab()
                .tabItem { Label("Stemme", systemImage: "mic") }
            ModesSettingsTab()
                .tabItem { Label("Modes", systemImage: "wand.and.stars") }
            RemindersSettingsTab()
                .tabItem { Label("Reminders", systemImage: "bell") }
            AboutTab()
                .tabItem { Label("Om", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 580)
    }
}

// MARK: - Reusable building blocks

/// En "card" der grupperer relateret indhold med titel + footer-hint.
struct SettingsCard<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
            )

            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Generelt

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

// MARK: - Stemme (LM Studio + Wake-word + ASR-info)

struct VoiceSettingsTab: View {
    @EnvironmentObject private var controller: SagaController
    @AppStorage("lmStudioBaseURL") private var lmStudioBaseURL: String = "http://localhost:1234/v1"
    @AppStorage("lmStudioModel") private var lmStudioModel: String = "gemma-4-26b-a4b"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard(
                    "Wake-word",
                    footer: "Saga lytter altid via Apples on-device speech recognition. Kræver permission. Default OFF."
                ) {
                    SettingsRow(
                        "Aktivér 'Hej Saga'",
                        subtitle: "Når du siger 'Hej Saga' starter optagelse i 6 sek automatisk."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { controller.wakeWordEnabled },
                            set: { controller.wakeWordEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    if controller.wakeWord.isListening {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Lytter")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    if let err = controller.wakeWord.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                }

                SettingsCard(
                    "LM Studio",
                    footer: "Bruges til mode-routing (oversæt, opsummer osv.). Pure dictation virker uden."
                ) {
                    LMStudioDiscoverySection(
                        baseURL: $lmStudioBaseURL,
                        model: $lmStudioModel
                    )
                    .environmentObject(controller)
                }
            }
            .padding(20)
        }
    }
}

struct LMStudioDiscoverySection: View {
    @EnvironmentObject private var controller: SagaController
    @Binding var baseURL: String
    @Binding var model: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                VStack(spacing: 6) {
                    ForEach(controller.discoveredEndpoints) { endpoint in
                        Button {
                            baseURL = endpoint.baseURL.absoluteString
                            if let firstModel = endpoint.models.first {
                                model = firstModel
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: baseURL == endpoint.baseURL.absoluteString ? "largecircle.fill.circle" : "circle")
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
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(baseURL == endpoint.baseURL.absoluteString
                                          ? Color.accentColor.opacity(0.08)
                                          : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !controller.isDiscoveringLMStudio {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Ingen LM Studio fundet på localhost.")
                        .font(.caption)
                }
                .foregroundColor(.orange)
                .padding(.vertical, 6)
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Manuel konfiguration")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                TextField("Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
            }
        }
    }
}

// MARK: - Modes

struct ModesSettingsTab: View {
    @EnvironmentObject private var controller: SagaController
    @State private var testInput: String = "oversæt til engelsk hej verden"
    @State private var testOutput: String = ""
    @State private var testRunning: Bool = false
    @State private var testError: String?
    @State private var showNewModeEditor: Bool = false
    @State private var editingMode: Mode? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !controller.modes.custom.isEmpty {
                    SettingsCard(
                        "Custom modes (\(controller.modes.custom.count))",
                        footer: "Egne triggers + system-prompts."
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(controller.modes.custom) { mode in
                                ModeRow(mode: mode, isCustom: true) {
                                    editingMode = mode
                                }
                                .environmentObject(controller)
                            }
                        }
                    }
                }

                SettingsCard(
                    "Indbyggede modes",
                    footer: "Tal med en trigger-frase foran for at aktivere. Slå fra for ren dictation."
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Mode.builtins) { mode in
                            ModeRow(mode: mode, isCustom: false, onEdit: nil)
                                .environmentObject(controller)
                        }
                    }
                }

                SettingsCard(
                    "Test mode",
                    footer: "Skriv en trigger + tekst og se LM Studio-output."
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Fx 'oversæt til engelsk hej verden'", text: $testInput, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                        HStack {
                            Button(testRunning ? "Kører…" : "Test") { runTest() }
                                .disabled(testRunning || testInput.trimmingCharacters(in: .whitespaces).isEmpty)
                            Spacer()
                            if let err = testError {
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            }
                        }
                        if !testOutput.isEmpty {
                            ScrollView {
                                Text(testOutput)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 80)
                            .padding(8)
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        showNewModeEditor = true
                    } label: {
                        Label("Ny custom mode", systemImage: "plus.circle.fill")
                    }
                    .controlSize(.regular)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showNewModeEditor) {
            CustomModeEditor()
                .environmentObject(controller)
        }
        .sheet(item: $editingMode) { mode in
            CustomModeEditor(existing: mode)
                .environmentObject(controller)
        }
    }

    private func runTest() {
        testRunning = true
        testError = nil
        testOutput = ""
        Task {
            defer { testRunning = false }
            do {
                let result = try await controller.modes.route(text: testInput, controller: controller)
                testOutput = result.text + (result.modeApplied ? "" : "  (ingen mode matchede)")
            } catch let err as ModeError {
                testError = err.errorDescription
            } catch {
                testError = error.localizedDescription
            }
        }
    }
}

struct ModeRow: View {
    @EnvironmentObject private var controller: SagaController
    let mode: Mode
    var isCustom: Bool = false
    var onEdit: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: Binding(
                get: { controller.modes.isEnabled(mode) },
                set: { controller.modes.setEnabled($0, for: mode) }
            )) { EmptyView() }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mode.title).font(.system(size: 13, weight: .medium))
                    if isCustom {
                        Text("CUSTOM")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18))
                            .foregroundColor(.accentColor)
                            .cornerRadius(3)
                    }
                }
                Text(mode.triggers.joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isCustom, let onEdit {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Reminders

struct RemindersSettingsTab: View {
    @EnvironmentObject private var controller: SagaController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard(
                    "Notifikations-adgang",
                    footer: "Saga skemalægger reminders som lokale macOS-notifikationer."
                ) {
                    HStack(spacing: 10) {
                        Image(systemName: controller.reminders.permissionGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundColor(controller.reminders.permissionGranted ? .green : .orange)
                        Text(controller.reminders.permissionGranted ? "Tilladt" : "Mangler")
                            .font(.system(size: 13))
                        Spacer()
                        if !controller.reminders.permissionGranted {
                            Button("Spørg") {
                                Task { _ = await controller.reminders.requestPermissionIfNeeded() }
                            }
                            .controlSize(.small)
                        }
                    }
                }

                SettingsCard(
                    "Skemalagte (\(controller.reminders.scheduled.count))",
                    footer: "Sig 'mind mig om at ringe til Lars i morgen kl 14' for at oprette en."
                ) {
                    if controller.reminders.scheduled.isEmpty {
                        HStack {
                            Spacer()
                            Text("Ingen kommende reminders")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 16)
                            Spacer()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(controller.reminders.scheduled) { reminder in
                                ReminderRow(reminder: reminder)
                                    .environmentObject(controller)
                            }
                            HStack {
                                Spacer()
                                Button("Ryd alt", role: .destructive) {
                                    controller.reminders.clearAll()
                                }
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct ReminderRow: View {
    @EnvironmentObject private var controller: SagaController
    let reminder: ScheduledReminder

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: reminder.hasFired ? "bell.slash" : "bell.fill")
                .foregroundColor(reminder.hasFired ? .secondary : Color(red: 0.20, green: 0.55, blue: 0.95))

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.system(size: 13, weight: .medium))
                Text(reminder.formattedFireDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !reminder.body.isEmpty {
                    Text(reminder.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                controller.reminders.cancel(id: reminder.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - About

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

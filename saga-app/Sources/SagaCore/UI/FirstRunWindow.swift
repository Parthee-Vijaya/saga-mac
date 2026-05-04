import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

/// Onboarding-vindue der vises ved første launch. Hjælper brugeren igennem
/// de tre setup-trin: hotkey-valg, mikrofon-permission, accessibility-permission.
/// LM Studio-detection kører i baggrunden og vises som status — ikke required.
public struct FirstRunWindow: View {
    @EnvironmentObject private var controller: SagaController
    @AppStorage("firstRunComplete") private var firstRunComplete: Bool = false
    @AppStorage("hotkey") private var hotkeyRaw: String = Hotkey.rightOption.rawValue

    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var hasAX: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    welcomeStep
                    hotkeyStep
                    permissionsStep
                    lmStudioStep
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            footer
        }
        .frame(width: 560, height: 660)
        .task { refresh() }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.55, blue: 0.95), Color(red: 0.4, green: 0.7, blue: 1.0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            Text("Velkommen til Saga")
                .font(.system(size: 22, weight: .bold))
            Text("Mac-native voice assistant til dansk dictation")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        StepCard(number: 1, title: "Sådan virker det", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                BulletText("Hold push-to-talk-tasten ned")
                BulletText("Tal en sætning på dansk")
                BulletText("Slip tasten — teksten indsættes ved cursor")
                Text("Alt kører lokalt på din Mac. Ingen audio forlader maskinen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var hotkeyStep: some View {
        StepCard(number: 2, title: "Vælg push-to-talk-tast", icon: "keyboard") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $hotkeyRaw) {
                    ForEach(Hotkey.allCases, id: \.rawValue) { key in
                        Text(key.displayName).tag(key.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: hotkeyRaw) { _, _ in
                    controller.hotkeys.stopListening()
                    controller.hotkeys.startListening()
                }

                if let key = Hotkey(rawValue: hotkeyRaw), key == .fn {
                    HelpHint(
                        text: "Fn / globe virker kun på Apple-keyboards. Hvis du bruger Logitech eller en anden producent, vælg Højre Option.",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
            }
        }
    }

    private var permissionsStep: some View {
        StepCard(number: 3, title: "Permissions", icon: "lock.shield") {
            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    title: "Mikrofon",
                    detail: micStatus == .authorized ? "Tilladt" : "Saga skal bruge mikrofonen til at lytte",
                    granted: micStatus == .authorized,
                    action: micStatus == .notDetermined ? {
                        controller.requestMicrophonePermissionIfNeeded()
                    } : {
                        controller.openMicrophoneSettings()
                    },
                    actionLabel: micStatus == .notDetermined ? "Tillad" : "Åbn Settings"
                )

                PermissionRow(
                    title: "Accessibility",
                    detail: hasAX ? "Tilladt" : "Bruges til at registrere push-to-talk-tasten og indsætte tekst",
                    granted: hasAX,
                    action: { controller.openAccessibilitySettings() },
                    actionLabel: hasAX ? "Skift" : "Åbn Settings"
                )

                if !hasAX {
                    HelpHint(
                        text: "I System Settings: find Saga i listen og toggle ON. Saga opdager det automatisk inden for 2 sekunder.",
                        icon: "info.circle.fill",
                        color: .blue
                    )
                }
            }
        }
    }

    private var lmStudioStep: some View {
        StepCard(number: 4, title: "LM Studio (valgfri)", icon: "cpu") {
            VStack(alignment: .leading, spacing: 10) {
                Text("LM Studio bruges kun til mode-routing (oversæt, opsummer osv.). Pure dictation virker uden.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                if controller.isDiscoveringLMStudio {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Søger efter LM Studio…")
                            .font(.system(size: 12))
                    }
                } else if let first = controller.discoveredEndpoints.first {
                    HelpHint(
                        text: "Fundet på localhost:\(first.port) med \(first.models.count) model(ler).",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                } else {
                    HStack(spacing: 8) {
                        HelpHint(
                            text: "Ingen LM Studio fundet. Du kan installere senere fra lmstudio.ai og klikke 'Find igen' i Indstillinger.",
                            icon: "info.circle",
                            color: .secondary
                        )
                        Spacer()
                        Button("Søg igen") {
                            Task { await controller.discoverLMStudio() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Spring over") {
                complete()
            }
            .buttonStyle(.borderless)
            Spacer()
            Button(canFinish ? "Kom i gang →" : "Granté permissions først") {
                complete()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(!canFinish)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var canFinish: Bool {
        micStatus == .authorized && hasAX
    }

    private func complete() {
        firstRunComplete = true
        // Find vinduet vi sidder i og luk det
        for win in NSApp.windows where win.contentViewController is NSHostingController<AnyView>
            || win.title == "Velkommen til Saga" {
            win.close()
        }
    }

    private func refresh() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        hasAX = AXIsProcessTrusted()
    }
}

// MARK: - Reusable subviews

struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.55, blue: 0.95).opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text("\(number)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.2, green: 0.55, blue: 0.95))
                }
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            content()
                .padding(.leading, 38)
        }
    }
}

struct BulletText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundColor(.secondary)
            Text(text).font(.system(size: 13))
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? .green : .secondary)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(actionLabel, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

struct HelpHint: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

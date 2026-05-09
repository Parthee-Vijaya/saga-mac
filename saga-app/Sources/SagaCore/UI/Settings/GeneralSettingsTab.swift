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
                    Divider().padding(.vertical, 4)
                    SettingsRow(
                        "Privacy-mode",
                        subtitle: "Når aktiv: stats, history og journal opdateres ikke. HUD viser shield-ikon. Ikke persisteret — slukker ved app-genstart."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { controller.privacyMode },
                            set: { controller.privacyMode = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }

                SettingsCard(
                    "Tekst-cleanup",
                    footer: "Saga's lokal-først tilgang: alle cleanup-pas kører uden LLM."
                ) {
                    SettingsRow(
                        "Strip pauseord",
                        subtitle: "Fjerner 'øh', 'altså', 'ligesom' osv. fra transkriberet tekst. Kører lokalt via regex."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { controller.stripFillerWords },
                            set: { controller.stripFillerWords = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }

                SettingsCard(
                    "Daily voice-journal",
                    footer: "Hver dictation appendes til ~/Saga-journal/YYYY-MM-DD.md med timestamp. Brugbar til reflective journaling og møde-noter samlet ét sted."
                ) {
                    SettingsRow(
                        "Aktivér daily journal",
                        subtitle: "Skriver alle transkriptioner til markdown-fil per dag. Default OFF."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { controller.journalEnabled },
                            set: { controller.journalEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    if controller.journalEnabled {
                        Divider().padding(.vertical, 4)
                        SettingsRow(
                            "Journal-mappe",
                            subtitle: controller.journal.directory.path
                        ) {
                            Button("Åbn") {
                                controller.journal.revealInFinder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                SettingsCard(
                    "Push-to-talk",
                    footer: hotkeyConflictWarning ?? "Hold tasten for at tale, slip for at indsætte. Live-test: tryk og hold tasten — preview-pillen tænder grøn når Saga kan se trykket."
                ) {
                    SettingsRow(
                        "Hotkey",
                        subtitle: hotkeyHelp
                    ) {
                        Picker("", selection: $hotkeyRaw) {
                            ForEach(Hotkey.allCases, id: \.rawValue) { key in
                                Label(key.displayName, systemImage: key.systemImage).tag(key.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    Divider().padding(.vertical, 4)
                    HotkeyLivePreview(
                        hotkeyRaw: hotkeyRaw,
                        isActive: controller.state == .recording
                    )
                    .environmentObject(controller)
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

    /// Konflikt-warning-tekst hvis brugeren har valgt en hotkey der kan
    /// kollidere med standard macOS-shortcuts.
    private var hotkeyConflictWarning: String? {
        guard let key = Hotkey(rawValue: hotkeyRaw) else { return nil }
        return key.systemConflictWarning
    }
}

/// Visuel preview-strip der lyser op når brugeren faktisk holder den
/// valgte hotkey nede. Bekræfter at CGEventTap fanger trykket korrekt
/// — brugeren ser øjeblikkelig feedback i stedet for at gætte.
struct HotkeyLivePreview: View {
    let hotkeyRaw: String
    let isActive: Bool

    @EnvironmentObject private var controller: SagaController

    var body: some View {
        let key = Hotkey(rawValue: hotkeyRaw) ?? .rightOption
        HStack(spacing: 10) {
            Text("Live-preview")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: key.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(key.keySymbol)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(isActive ? .green : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isActive ? Color.green.opacity(0.5) : Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.12), value: isActive)

            Text(isActive ? "Saga lytter ✓" : "Hold tasten for at teste")
                .font(.caption)
                .foregroundColor(isActive ? .green : .secondary)

            Spacer()
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

import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

/// Onboarding-vindue der vises ved første launch — single-step guided flow
/// inspireret af Superwhisper. 5 trin: Velkommen → Permissions → Mic-test →
/// Hotkey → LM Studio. Hvert trin har én klar handling.
public struct FirstRunWindow: View {
    @EnvironmentObject private var controller: SagaController
    @AppStorage("firstRunComplete") private var firstRunComplete: Bool = false
    @AppStorage("hotkey") private var hotkeyRaw: String = Hotkey.rightOption.rawValue

    @State private var step: WizardStep = .welcome
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var hasAX: Bool = false
    @State private var lmStudioEnabled: Bool = true

    public enum WizardStep: Int, CaseIterable {
        case welcome
        case permissions
        case micTest
        case hotkey
        case asrEngine
        case lmStudio
        case licenses

        var title: String {
            switch self {
            case .welcome: return "Velkommen til Saga"
            case .permissions: return "Lad os sætte permissions op"
            case .micTest: return "Test din mikrofon"
            case .hotkey: return "Vælg din push-to-talk-tast"
            case .asrEngine: return "Vælg dansk-engine"
            case .lmStudio: return "Vil du tilslutte LM Studio?"
            case .licenses: return "Licenser & privatliv"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            WizardProgressBar(currentStep: step.rawValue, totalSteps: WizardStep.allCases.count)
                .padding(.horizontal, SagaSpacing.xxl)
                .padding(.top, SagaSpacing.xl)

            // Step content
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, SagaSpacing.xxl)

            // Footer
            footer
                .padding(.horizontal, SagaSpacing.xxl)
                .padding(.bottom, SagaSpacing.xl)
                .padding(.top, SagaSpacing.lg)
        }
        .frame(width: 540, height: 620)
        .background(SagaColors.background)
        .preferredColorScheme(.dark)
        .task { refresh() }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            refresh()
            // Hvis bruger granter mic via system-prompt, advance auto fra
            // permissions-step (ellers føles det stuck)
        }
        .onAppear {
            if step == .micTest { controller.audio.start() }
        }
        .onDisappear {
            controller.audio.stop()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeContent
        case .permissions: permissionsContent
        case .micTest: micTestContent
        case .hotkey: hotkeyContent
        case .asrEngine: asrEngineContent
        case .lmStudio: lmStudioContent
        case .licenses: licensesContent
        }
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
        VStack(spacing: SagaSpacing.xl) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(SagaColors.accentGradient)
                .sagaShadow(.glow)

            VStack(spacing: SagaSpacing.sm) {
                Text(WizardStep.welcome.title)
                    .font(SagaTypography.display)
                    .foregroundColor(SagaColors.textPrimary)

                Text("Mac-native voice assistant til dansk dictation.\nAlt kører lokalt — ingen audio forlader din maskine.")
                    .font(SagaTypography.body)
                    .foregroundColor(SagaColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
        }
    }

    // MARK: - Permissions

    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: SagaSpacing.xl) {
            heading(WizardStep.permissions.title)

            VStack(spacing: SagaSpacing.lg) {
                NewPermissionRow(
                    icon: "mic.fill",
                    title: "Tillad mikrofon-adgang",
                    detail: micStatus == .authorized
                        ? "Tilladt"
                        : "Påkrævet for at fange tale til transkribering. Bruges kun under recording.",
                    granted: micStatus == .authorized,
                    action: micStatus == .notDetermined
                        ? { controller.requestMicrophonePermissionIfNeeded() }
                        : { controller.openMicrophoneSettings() },
                    actionLabel: micStatus == .notDetermined ? "Tillad" : "Åbn Settings"
                )

                NewPermissionRow(
                    icon: "accessibility",
                    title: "Tillad Accessibility-adgang",
                    detail: hasAX
                        ? "Tilladt"
                        : "Bruges til at registrere push-to-talk-tasten og indsætte tekst ved cursor. Kun aktiv ved behov.",
                    granted: hasAX,
                    action: { controller.openAccessibilitySettings() },
                    actionLabel: hasAX ? "Skift" : "Åbn Settings"
                )
            }

            if !hasAX {
                Text("I System Settings: find Saga i listen og toggle ON. Saga opdager det automatisk.")
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textTertiary)
            }

            Spacer()
        }
        .padding(.top, SagaSpacing.xl)
    }

    // MARK: - Mic test

    private var micTestContent: some View {
        VStack(alignment: .leading, spacing: SagaSpacing.xl) {
            VStack(alignment: .leading, spacing: SagaSpacing.sm) {
                heading(WizardStep.micTest.title)
                Text("Tal og se om bølgerne reagerer.\nIngen respons? Tjek din input-enhed i System Settings.")
                    .font(SagaTypography.body)
                    .foregroundColor(SagaColors.textSecondary)
                    .lineSpacing(2)
            }

            // Live waveform
            MicTestWaveform(levels: controller.audio.levelHistory)
                .frame(height: 140)
                .padding(SagaSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: SagaRadii.large)
                        .fill(SagaColors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: SagaRadii.large)
                                .strokeBorder(SagaColors.border, lineWidth: 1)
                        )
                )

            HStack(spacing: SagaSpacing.sm) {
                Image(systemName: "headphones")
                    .foregroundColor(SagaColors.accent)
                Text("System default")
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textSecondary)
            }

            Spacer()
        }
        .padding(.top, SagaSpacing.xl)
        .onAppear { controller.audio.start() }
        .onDisappear { controller.audio.stop() }
    }

    // MARK: - Hotkey

    private var hotkeyContent: some View {
        VStack(alignment: .leading, spacing: SagaSpacing.xl) {
            VStack(alignment: .leading, spacing: SagaSpacing.sm) {
                heading(WizardStep.hotkey.title)
                Text("Hold tasten ned mens du taler. Slip når du er færdig — så indsættes teksten ved cursor.")
                    .font(SagaTypography.body)
                    .foregroundColor(SagaColors.textSecondary)
                    .lineSpacing(2)
            }

            VStack(spacing: SagaSpacing.sm) {
                ForEach(Hotkey.allCases, id: \.rawValue) { key in
                    HotkeyOption(
                        hotkey: key,
                        isSelected: hotkeyRaw == key.rawValue
                    ) {
                        hotkeyRaw = key.rawValue
                        controller.hotkeys.stopListening()
                        controller.hotkeys.startListening()
                    }
                }
            }

            if let key = Hotkey(rawValue: hotkeyRaw), key == .fn {
                HStack(spacing: SagaSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(SagaColors.warning)
                    Text("Fn / globe virker kun på Apple-keyboards. Vælg Højre Option for Logitech og andre.")
                        .font(SagaTypography.caption)
                        .foregroundColor(SagaColors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.top, SagaSpacing.xl)
    }

    // MARK: - LM Studio

    private var lmStudioContent: some View {
        VStack(alignment: .leading, spacing: SagaSpacing.xl) {
            VStack(alignment: .leading, spacing: SagaSpacing.sm) {
                heading(WizardStep.lmStudio.title)
                Text("LM Studio kører store modeller lokalt og åbner Saga's modes (oversæt, opsummer, voice-edit, Companion). Pure dictation virker uden.")
                    .font(SagaTypography.body)
                    .foregroundColor(SagaColors.textSecondary)
                    .lineSpacing(2)
            }

            HStack(spacing: SagaSpacing.lg) {
                ChoiceCard(
                    icon: "waveform",
                    title: "Kun lokal dictation",
                    subtitle: "Hold ⌥, tal, slip. Ingen LLM nødvendig.",
                    isSelected: !lmStudioEnabled,
                    action: { lmStudioEnabled = false }
                )

                ChoiceCard(
                    icon: "cpu",
                    title: "Lokal + LM Studio",
                    subtitle: "Modes, voice-edit, Companion-samtaler.",
                    isSelected: lmStudioEnabled,
                    action: { lmStudioEnabled = true }
                )
            }

            if lmStudioEnabled {
                if controller.isDiscoveringLMStudio {
                    HStack(spacing: SagaSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Søger efter LM Studio…")
                            .font(SagaTypography.caption)
                            .foregroundColor(SagaColors.textSecondary)
                    }
                } else if let first = controller.discoveredEndpoints.first {
                    HStack(spacing: SagaSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(SagaColors.success)
                        Text("Fundet på localhost:\(first.port) med \(first.models.count) model(ler).")
                            .font(SagaTypography.caption)
                            .foregroundColor(SagaColors.textSecondary)
                    }
                } else {
                    HStack(spacing: SagaSpacing.sm) {
                        Image(systemName: "info.circle")
                            .foregroundColor(SagaColors.textTertiary)
                        Text("Ingen LM Studio fundet. Start den fra lmstudio.ai og klik 'Søg igen'.")
                            .font(SagaTypography.caption)
                            .foregroundColor(SagaColors.textSecondary)
                        Spacer()
                        Button("Søg igen") {
                            Task { await controller.discoverLMStudio() }
                        }
                        .buttonStyle(SagaButtonStyle.secondaryCompact)
                    }
                }
            }

            Spacer()
        }
        .padding(.top, SagaSpacing.xl)
    }

    // MARK: - ASR engine

    private var asrEngineContent: some View {
        VStack(alignment: .leading, spacing: SagaSpacing.lg) {
            heading(WizardStep.asrEngine.title)
            Text("Saga har to dansk-engines. Du kan altid skifte i Indstillinger → Stemme.")
                .font(SagaTypography.body)
                .foregroundColor(SagaColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: SagaSpacing.sm + 2) {
                EngineCard(
                    title: "Canary",
                    tagline: "25 EU-sprog · Apache 2.0",
                    description: "NVIDIA's multilingual ASR. Kommerciel-OK med attribution. ~1,8 GB download.",
                    isRecommended: true,
                    isSelected: controller.preferredDanishEngine == .canary,
                    onSelect: { controller.preferredDanishEngine = .canary }
                )
                EngineCard(
                    title: "Hviske",
                    tagline: "Dansk-først · CC BY-NC 4.0",
                    description: "syv.ai's Whisper-finetune. KUN privat brug. ~2,9 GB download.",
                    isRecommended: false,
                    isSelected: controller.preferredDanishEngine == .hviske,
                    onSelect: { controller.preferredDanishEngine = .hviske }
                )
            }

            if controller.preferredDanishEngine == .hviske {
                HStack(alignment: .top, spacing: SagaSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(SagaColors.warning)
                        .font(.system(size: 12))
                    Text("Ved at vælge Hviske accepterer du CC BY-NC 4.0. Modellen downloades først når du laver din første dansk-dictation.")
                        .font(SagaTypography.caption)
                        .foregroundColor(SagaColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, SagaSpacing.xs)
            }

            Spacer()
        }
        .padding(.top, SagaSpacing.xl)
    }

    // MARK: - Licenses

    private var licensesContent: some View {
        VStack(alignment: .leading, spacing: SagaSpacing.md) {
            heading(WizardStep.licenses.title)
            Text("Saga er privat. Ingen lyd forlader din Mac. Ingen telemetri.")
                .font(SagaTypography.body)
                .foregroundColor(SagaColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: SagaSpacing.sm) {
                LicenseRowSimple(name: "Saga", license: "MIT", note: "Open source — bidrag velkomne")
                LicenseRowSimple(name: "Canary-1b-v2 (NVIDIA)", license: "CC BY 4.0", note: "Kommerciel-OK med attribution")
                LicenseRowSimple(name: "Hviske-v3 (syv.ai)", license: "CC BY-NC 4.0", note: "Kun privat brug — opt-in")
                LicenseRowSimple(name: "Apple Speech (fallback)", license: "Apple SLA", note: "Indbygget i macOS")
                LicenseRowSimple(name: "LM Studio (valgfri)", license: "Tredjepart", note: "Saga sender kun til localhost")
            }
            .padding(.top, SagaSpacing.xs)

            Spacer()

            Text("Fuld liste i Indstillinger → Om.")
                .font(SagaTypography.caption)
                .foregroundColor(SagaColors.textTertiary)
        }
        .padding(.top, SagaSpacing.xl)
    }

    // MARK: - Heading + footer

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(SagaTypography.title)
            .foregroundColor(SagaColors.textPrimary)
    }

    private var footer: some View {
        VStack(spacing: SagaSpacing.sm) {
            Button(action: advance) {
                Text(primaryButtonLabel)
            }
            .buttonStyle(SagaButtonStyle.primary)
            .disabled(!canAdvance)
            .keyboardShortcut(.defaultAction)

            if step != .welcome && step != .licenses {
                Button("Spring over") {
                    advance()
                }
                .buttonStyle(SagaButtonStyle.ghost)
            }
        }
    }

    private var primaryButtonLabel: String {
        switch step {
        case .welcome: return "Kom i gang"
        case .permissions: return canAdvance ? "Fortsæt setup" : "Granté mikrofon først"
        case .micTest: return "Fortsæt"
        case .hotkey: return "Fortsæt"
        case .asrEngine: return "Fortsæt"
        case .lmStudio: return "Fortsæt"
        case .licenses: return "Færdig"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .welcome: return true
        case .permissions: return micStatus == .authorized  // AX kan skip'es
        case .micTest, .hotkey, .asrEngine, .lmStudio, .licenses: return true
        }
    }

    private func advance() {
        if let next = WizardStep(rawValue: step.rawValue + 1) {
            // Stop mic-recording når vi forlader micTest
            if step == .micTest { controller.audio.stop() }
            // Start mic-recording når vi entrer micTest
            if next == .micTest { controller.audio.start() }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                step = next
            }
        } else {
            complete()
        }
    }

    private func complete() {
        controller.audio.stop()
        firstRunComplete = true
        for win in NSApp.windows where win.title == "Velkommen til Saga" {
            win.close()
        }
    }

    private func refresh() {
        let newMic = AVCaptureDevice.authorizationStatus(for: .audio)
        let newAX = AXIsProcessTrusted()
        if newMic != micStatus { micStatus = newMic }
        if newAX != hasAX { hasAX = newAX }
    }
}

// MARK: - Reusable subviews

private struct NewPermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        HStack(spacing: SagaSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(granted ? SagaColors.success : SagaColors.accent)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill((granted ? SagaColors.success : SagaColors.accent).opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SagaTypography.bodyEmphasis)
                    .foregroundColor(SagaColors.textPrimary)
                Text(detail)
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SagaSpacing.md)

            Button(actionLabel, action: action)
                .buttonStyle(granted ? SagaButtonStyle.secondaryCompact : SagaButtonStyle.secondaryCompact)
        }
    }
}

private struct HotkeyOption: View {
    let hotkey: Hotkey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SagaSpacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? SagaColors.accent : SagaColors.textTertiary)
                Text(hotkey.displayName)
                    .font(SagaTypography.body)
                    .foregroundColor(SagaColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, SagaSpacing.lg)
            .padding(.vertical, SagaSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: SagaRadii.medium)
                    .fill(isSelected ? SagaColors.accentSubtle : SagaColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: SagaRadii.medium)
                            .strokeBorder(isSelected ? SagaColors.accentBorder : SagaColors.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SagaSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(isSelected ? SagaColors.accent : SagaColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, SagaSpacing.sm)

                VStack(alignment: .leading, spacing: SagaSpacing.xs) {
                    Text(title)
                        .font(SagaTypography.bodyEmphasis)
                        .foregroundColor(SagaColors.textPrimary)
                    Text(subtitle)
                        .font(SagaTypography.caption)
                        .foregroundColor(SagaColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SagaSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: SagaRadii.large)
                    .fill(isSelected ? SagaColors.accentSubtle : SagaColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: SagaRadii.large)
                            .strokeBorder(isSelected ? SagaColors.accentBorder : SagaColors.border, lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MicTestWaveform: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<levels.count, id: \.self) { idx in
                    Capsule()
                        .fill(SagaColors.accentGradient)
                        .frame(width: 4, height: barHeight(for: levels[idx], maxHeight: geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: levels)
        }
    }

    private func barHeight(for level: Float, maxHeight: CGFloat) -> CGFloat {
        let boosted = pow(CGFloat(level), 0.7)
        let scaled = max(4, boosted * maxHeight)
        return min(maxHeight, scaled)
    }
}

// MARK: - ASR engine + license helpers

/// Klikbart kort til engine-valg i first-run wizard. Selection-state vises
/// med accent-border + accent-glow. Anbefalet-flag vises som lille pill.
private struct EngineCard: View {
    let title: String
    let tagline: String
    let description: String
    let isRecommended: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: SagaSpacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? SagaColors.accent : SagaColors.textTertiary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: SagaSpacing.sm) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(SagaColors.textPrimary)
                        if isRecommended {
                            Text("ANBEFALET")
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.5)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(SagaColors.accent.opacity(0.18)))
                                .foregroundColor(SagaColors.accent)
                        }
                        Spacer()
                    }
                    Text(tagline)
                        .font(SagaTypography.caption)
                        .foregroundColor(SagaColors.textSecondary)
                    Text(description)
                        .font(SagaTypography.caption)
                        .foregroundColor(SagaColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(SagaSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SagaRadii.medium, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SagaRadii.medium, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .shadow(color: isSelected ? SagaColors.accent.opacity(0.18) : .clear, radius: 8, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.10), value: isHovered)
    }

    private var backgroundFill: Color {
        if isSelected { return SagaColors.accent.opacity(0.10) }
        if isHovered { return SagaColors.surface }
        return Color.white.opacity(0.02)
    }

    private var borderColor: Color {
        if isSelected { return SagaColors.accent.opacity(0.55) }
        if isHovered { return SagaColors.borderStrong }
        return SagaColors.border
    }
}

/// Kompakt license-row til first-run wizard. Mere kompakt end About-tabbens
/// LicenseCard — vi viser ikke links her (de er allerede tilgængelige i Om).
private struct LicenseRowSimple: View {
    let name: String
    let license: String
    let note: String

    var body: some View {
        HStack(alignment: .top, spacing: SagaSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(SagaColors.textPrimary)
                Text(note)
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textTertiary)
            }
            Spacer(minLength: SagaSpacing.sm)
            Text(license)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(SagaColors.textSecondary)
        }
    }
}

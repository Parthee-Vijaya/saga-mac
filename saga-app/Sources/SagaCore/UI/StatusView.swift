import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

/// MenuBarExtra-popover. Viser live system-status, kontrol-knapper og senest historik.
public struct StatusView: View {
    @EnvironmentObject private var controller: SagaController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    public init() {}

    // Læses én gang ved første brug — Info.plist-værdier ændrer sig ikke i runtime.
    static let shortVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }()
    static let buildNumber: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }()
    static let versionLabel: String = "v\(shortVersion) (\(buildNumber))"

    /// Disclosure-state for kollapsbare sektioner. Default: status er åbent
    /// (brugeren vil typisk se health-rows ved åbning), recent er kollapset.
    /// @AppStorage frem for @State — MenuBarExtra-content genskabes ved hver
    /// popover-åbning, så @State ville resette brugerens valg hver gang.
    @AppStorage("statusView.showSystemDetails") private var showSystemDetails: Bool = true
    @AppStorage("statusView.showRecent") private var showRecent: Bool = false

    public var body: some View {
        ZStack {
            // Aurora-glow BAGVED glasset — .ultraThinMaterial blurrer alt
            // visuelt bag sig (også sibling-views lavere i z-ordenen), så
            // glowen bliver glassets "indhold" at refraktere. Uden den er
            // blur usynlig mod en mørk desktop.
            AuroraGlowBackground()

            // Liquid Glass Pro-base (Design B): materiale + mørk blålig tint
            // + specular border (lysere top-kant) + dyb skygge. Audio-reactive
            // accent-border ligger OVENPÅ specular-stroken så recording-pulsen
            // stadig dominerer visuelt når den er aktiv.
            RoundedRectangle(cornerRadius: SagaRadii.large, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: SagaRadii.large, style: .continuous)
                        .fill(SagaColors.glassPanelTint)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SagaRadii.large, style: .continuous)
                        .strokeBorder(SagaColors.specularBorder, lineWidth: 1)
                )
                .overlay(
                    AudioReactiveBorder(audio: controller.audio, state: controller.state)
                )
                .overlay(
                    // Subtil accent-gradient i toppen — "lys ovenfra"-effekt
                    // der får panelet til at føles let, ikke trykket.
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [SagaColors.accent.opacity(0.06), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 60)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: SagaRadii.large, style: .continuous))
                    .allowsHitTesting(false)
                )
                .sagaShadow(.glassDepth)

            // Faktisk content
            VStack(alignment: .leading, spacing: 0) {
                header
                if let error = controller.recentError {
                    errorBanner(error)
                }
                sectionDivider
                statusDisclosure
                sectionDivider
                togglesSection
                sectionDivider
                recentDisclosure
                sectionDivider
                footer
            }
            .padding(.vertical, SagaSpacing.sm)
        }
        .padding(SagaSpacing.xs + 2)
        .preferredColorScheme(.dark)
    }

    /// Banner der viser SagaController.recentError med valgfri Fix-knap.
    /// Aktiverer SagaError-systemets recovery-flow (fx "Åbn System Settings"
    /// ved manglende mic-permission). Dismiss rydder både structured +
    /// string-fejlen via clearError().
    private func errorBanner(_ error: SagaError) -> some View {
        HStack(alignment: .top, spacing: SagaSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(SagaColors.warning)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SagaColors.textPrimary)
                Text(error.detail)
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let recovery = error.recovery {
                    Button(recovery.label) {
                        recovery.execute()
                        controller.clearError()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SagaColors.accent)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: SagaSpacing.xs)
            Button {
                controller.clearError()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(SagaColors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Afvis fejl")
        }
        .padding(.horizontal, SagaSpacing.lg)
        .padding(.vertical, SagaSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SagaRadii.small, style: .continuous)
                .fill(SagaColors.warning.opacity(0.10))
                .padding(.horizontal, SagaSpacing.sm)
        )
    }

    /// Inset-divider — træk ikke helt ud til kant, så glass-edges bevarer
    /// en ren kontur. Bruges i stedet for default .Divider() der spænder
    /// hele bredden.
    private var sectionDivider: some View {
        Rectangle()
            .fill(SagaColors.border)
            .frame(height: 0.5)
            .padding(.horizontal, SagaSpacing.md)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: SagaSpacing.md) {
            Image(systemName: stateIcon)
                .font(.system(size: 22))
                .foregroundStyle(stateColor)
                .symbolEffect(.pulse, isActive: controller.state == .recording)
                .symbolEffect(.variableColor.iterative, isActive: controller.state == .transcribing || controller.state == .routing)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: SagaSpacing.xs) {
                    Text("Saga")
                        .font(SagaTypography.bodyEmphasis)
                        .foregroundColor(SagaColors.textPrimary)
                    VersionLink()
                }
                Text(stateText)
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textSecondary)
            }
            Spacer()
            if controller.state == .idle {
                Image(systemName: "option")
                    .font(.system(size: 9))
                    .foregroundColor(SagaColors.textTertiary)
                Text("Hold ⌥ for at tale")
                    .font(.system(size: 10))
                    .foregroundColor(SagaColors.textSecondary)
            }
        }
        .padding(.horizontal, SagaSpacing.lg)
        .padding(.vertical, SagaSpacing.xs + 2)  // 6 = xs(4) + 2
    }

    private var stateIcon: String {
        switch controller.state {
        case .idle: return controller.health.asr.isHappy ? "checkmark.circle.fill" : "exclamationmark.circle"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .routing: return "sparkles"
        }
    }

    private var stateColor: Color {
        switch controller.state {
        case .idle: return controller.health.asr.isHappy ? SagaColors.success : SagaColors.warning
        case .recording: return SagaColors.danger
        case .transcribing: return SagaColors.accent
        case .routing: return SagaColors.accent
        }
    }

    // State-labels går gennem NSLocalizedString som proof-of-concept for
    // community-oversættelser (en.lproj findes allerede). Resten af UI'et
    // er hardcoded dansk indtil videre — se CONTRIBUTING.md → Localization.
    private var stateText: String {
        switch controller.state {
        case .idle:
            // recentError vises i errorBanner — undgå at duble fejlteksten her.
            if controller.recentError == nil, let err = controller.lastError { return err }
            if !controller.health.asr.isHappy {
                return NSLocalizedString("saga.state.loading_asr", value: "Indlæser ASR-model", comment: "Menubar-state mens CoreML-modellen loader")
            }
            return controller.stenografMode
                ? NSLocalizedString("saga.state.stenograf", value: "Klar · Stenograf-mode", comment: "Menubar-state: klar, stenograf-mode aktiv")
                : NSLocalizedString("saga.state.idle", value: "Klar", comment: "Menubar-state: klar til dictation")
        case .recording:
            return NSLocalizedString("saga.state.recording", value: "Lytter…", comment: "Menubar-state under optagelse")
        case .transcribing:
            return NSLocalizedString("saga.state.transcribing", value: "Transkriberer…", comment: "Menubar-state under transkribering")
        case .routing:
            return NSLocalizedString("saga.state.routing", value: "Tænker…", comment: "Menubar-state under LLM-routing")
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: SagaSpacing.sm) {
            HealthRow(
                title: "Canary (ASR)",
                detail: "\(controller.asr.modelLabel) · \(controller.health.asr.label)",
                ok: controller.health.asr.isHappy,
                action: ("Reload", { controller.reloadASR() })
            )
            HealthRow(
                title: "LM Studio (LLM)",
                detail: controller.health.lmStudio.label,
                ok: controller.health.lmStudio.isHappy,
                action: nil
            )
            PermissionInlineRow()
        }
        .padding(.horizontal, SagaSpacing.lg)
        .padding(.vertical, SagaSpacing.sm)
    }

    // MARK: - Quick toggles (Command Surface tiles)

    /// Tre tile-toggles til de hyppigst skiftende modes. Tile-format frem for
    /// pill — større klikflade, tydeligere on/off-state, matcher Command Surface-stil.
    /// Bindes direkte til SagaController's @Published properties.
    private var togglesSection: some View {
        HStack(spacing: SagaSpacing.xs + 2) {
            ControlTile(
                title: "Privacy",
                systemImage: "shield.lefthalf.filled",
                isOn: Binding(
                    get: { controller.privacyMode },
                    set: { controller.privacyMode = $0 }
                ),
                onColor: SagaColors.warning
            )
            ControlTile(
                title: "Stenograf",
                systemImage: "text.cursor",
                isOn: Binding(
                    get: { controller.stenografMode },
                    set: { controller.stenografMode = $0 }
                ),
                onColor: SagaColors.accent
            )
            ControlTile(
                title: "Wake-word",
                systemImage: "waveform.badge.mic",
                isOn: Binding(
                    get: { controller.wakeWordEnabled },
                    set: { controller.wakeWordEnabled = $0 }
                ),
                onColor: SagaColors.accent
            )
        }
        .padding(.horizontal, SagaSpacing.md)
        .padding(.vertical, SagaSpacing.sm)
    }

    // MARK: - Disclosure-wrappers

    /// Status-disclosure: åbnet by default fordi det er primær info brugeren
    /// kommer for. Klik på header for at kollapse/expand.
    private var statusDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureRowHeader(
                title: "System",
                isExpanded: showSystemDetails,
                onToggle: { withAnimation(.easeInOut(duration: 0.18)) { showSystemDetails.toggle() } }
            )
            if showSystemDetails {
                statusSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Recent-disclosure: lukket by default — recent transcripts er sekundær info
    /// (5×44pt fyldte før dropdown'en), kan stadig åbnes med ét klik.
    private var recentDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureRowHeader(
                title: "Seneste",
                badge: controller.history.entries.isEmpty ? nil : "\(controller.history.entries.count)",
                isExpanded: showRecent,
                onToggle: { withAnimation(.easeInOut(duration: 0.18)) { showRecent.toggle() } }
            )
            if showRecent {
                recentSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: SagaSpacing.xs + 2) {  // 6 = xs(4) + 2
            HStack {
                Text("Seneste")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SagaColors.textSecondary)
                Spacer()
                if !controller.history.entries.isEmpty {
                    Button("Se alle…") { openWindow(id: "history") }
                        .buttonStyle(.link)
                        .font(SagaTypography.caption)
                        .foregroundColor(SagaColors.accent)
                }
            }

            if controller.history.entries.isEmpty {
                Text("Ingen transkriptioner endnu.")
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textSecondary)
                    .padding(.vertical, SagaSpacing.xs)
            } else {
                VStack(alignment: .leading, spacing: SagaSpacing.xs) {
                    ForEach(controller.history.entries.prefix(5)) { entry in
                        HistoryRowCompact(entry: entry)
                    }
                }
            }
        }
        .padding(.horizontal, SagaSpacing.lg)
        .padding(.vertical, SagaSpacing.sm)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: SagaSpacing.xs + 2) {
            StatusFooterButton(
                title: "Indstillinger…",
                systemImage: "gearshape",
                action: { openSettings() }
            )
            Spacer()
            StatusFooterButton(
                title: "Document-analyse",
                systemImage: "doc.text.magnifyingglass",
                action: { openWindow(id: "documents") }
            )
            Spacer()
            StatusFooterButton(
                title: "Afslut",
                systemImage: "power",
                action: {
                    Task {
                        await controller.shutdown()
                        NSApp.terminate(nil)
                    }
                }
            )
        }
        .padding(.horizontal, SagaSpacing.md)
        .padding(.vertical, SagaSpacing.xs + 2)
    }
}

// MARK: - Subviews

/// Footer-knap med hover-state og pointing-hand cursor — matcher native macOS.
struct StatusFooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(title)
                    .font(SagaTypography.caption)
            }
            .foregroundColor(SagaColors.textPrimary)
            .padding(.horizontal, SagaSpacing.sm)
            .padding(.vertical, SagaSpacing.xs + 1)
            .background(
                RoundedRectangle(cornerRadius: SagaRadii.small, style: .continuous)
                    .fill(backgroundFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .pointingHandOnHover()
        .pressEvents(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.10), value: isPressed)
    }

    private var backgroundFill: Color {
        if isPressed { return SagaColors.surfaceElevated }
        if isHovered { return SagaColors.accentSubtle }
        return Color.clear
    }
}

/// Hjælper til at tracke press-state. SwiftUI's `Button` har ingen direct press-callback,
/// så vi bruger DragGesture(minimumDistance: 0) til at fange touch-down/up.
extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}

struct HealthRow: View {
    let title: String
    let detail: String
    let ok: Bool
    let action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: SagaSpacing.md) {
            // Glødende dot (Design B) — ok-state pulserer ikke, men gløder
            // blødt så "alt kører" føles levende.
            Circle()
                .fill(ok ? SagaColors.success : SagaColors.warning)
                .frame(width: 8, height: 8)
                .shadow(color: (ok ? SagaColors.success : SagaColors.warning).opacity(0.7), radius: 4)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SagaColors.textPrimary)
                Text(detail)
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderless)
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.accent)
            }
        }
    }
}

struct PermissionInlineRow: View {
    @EnvironmentObject private var controller: SagaController
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var hasAX = false

    private var hasMic: Bool { micStatus == .authorized }
    private var allOk: Bool { hasMic && hasAX }

    var body: some View {
        HStack(alignment: .top, spacing: SagaSpacing.md) {
            Circle()
                .fill(allOk ? SagaColors.success : SagaColors.warning)
                .frame(width: 8, height: 8)
                .shadow(color: (allOk ? SagaColors.success : SagaColors.warning).opacity(0.7), radius: 4)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text("Permissions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SagaColors.textPrimary)
                Text("Mikrofon: \(micLabel)  ·  Accessibility: \(hasAX ? "✓" : "—")")
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textSecondary)
            }
            Spacer()
            if !allOk {
                Menu("Fix") {
                    if micStatus == .notDetermined {
                        Button("Spørg om mikrofon-adgang") {
                            controller.requestMicrophonePermissionIfNeeded()
                        }
                    }
                    if !hasMic {
                        Button("Åbn Mikrofon-indstillinger") {
                            controller.openMicrophoneSettings()
                        }
                    }
                    if !hasAX {
                        Button("Åbn Accessibility-indstillinger") {
                            controller.openAccessibilitySettings()
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .font(SagaTypography.caption)
                .fixedSize()
            }
        }
        .task {
            refresh()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    private var micLabel: String {
        switch micStatus {
        case .authorized: return "✓"
        case .denied: return "nægtet"
        case .restricted: return "begrænset"
        case .notDetermined: return "ikke spurgt endnu"
        @unknown default: return "—"
        }
    }

    private func refresh() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        hasAX = AXIsProcessTrusted()
    }
}

struct HistoryRowCompact: View {
    let entry: TranscriptEntry

    var body: some View {
        HStack(alignment: .top, spacing: SagaSpacing.sm) {
            Image(systemName: entry.wasModeApplied ? "sparkles" : "text.cursor")
                .font(.system(size: 10))
                .foregroundColor(entry.wasModeApplied ? SagaColors.accent : SagaColors.textSecondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.processedText)
                    .font(.system(size: 12))
                    .foregroundColor(SagaColors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: SagaSpacing.xs + 2) {
                    Text(entry.timestamp, style: .time)
                        .font(.system(size: 9))
                        .foregroundColor(SagaColors.textTertiary)
                    if let mode = entry.modeId {
                        Text("·")
                            .foregroundColor(SagaColors.textTertiary)
                            .font(.system(size: 9))
                        Text(mode)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(SagaColors.textTertiary)
                    }
                    Text("·")
                        .foregroundColor(SagaColors.textTertiary)
                        .font(.system(size: 9))
                    Text(String(format: "%.2fs", Double(entry.durationMs) / 1000.0))
                        .font(.system(size: 9))
                        .foregroundColor(SagaColors.textTertiary)
                }
            }
        }
    }
}

/// Audio-reactive accent-border til glass-base. Observer audio.levelHistory
/// direkte (@ObservedObject) så SwiftUI re-evaluerer når levels opdaterer.
/// Idle: konstant 0.18 (subtil ring). Recording: 0.35→0.90 audio-reactive.
/// Transcribing/routing: 0.45 fast working-tilstand.
struct AudioReactiveBorder: View {
    @ObservedObject var audio: AudioCapture
    let state: SagaState

    var body: some View {
        RoundedRectangle(cornerRadius: SagaRadii.large, style: .continuous)
            .strokeBorder(SagaColors.accent.opacity(opacity), lineWidth: 1)
            .animation(.easeOut(duration: 0.22), value: opacity)
    }

    private var opacity: Double {
        switch state {
        case .idle:
            // Specular-stroken (Design B) er basis-kanten i idle — accent-laget
            // er helt slukket så glasset står rent. Tidligere 0.18 gav
            // dobbelt-border oveni specular.
            return 0.0
        case .recording:
            let recent = audio.levelHistory.suffix(5)
            guard !recent.isEmpty else { return 0.35 }
            let avg = recent.reduce(0, +) / Float(recent.count)
            let normalized = min(1.0, Double(avg) * 2.0)
            return 0.35 + normalized * 0.55
        case .transcribing, .routing:
            return 0.45
        }
    }
}

/// Tile-style toggle — Command Surface-tile fra menubar-redesign-plan'en.
/// Større klikflade end pill, tydeligere on/off, accent-glow når aktiv.
/// Layout: label uppercase top, ikon stort i midten, state-tekst bund.
/// Bindes til SagaController's @Published booleans.
struct ControlTile: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let onColor: Color

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: { isOn.toggle() }) {
            VStack(spacing: 4) {
                Text(title.uppercased())
                    .font(SagaTypography.label)
                    .tracking(0.5)
                    .foregroundColor(isOn ? onColor : SagaColors.textTertiary)
                    .lineLimit(1)
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isOn ? onColor : SagaColors.textPrimary)
                    .symbolEffect(.bounce, value: isOn)
                Text(isOn ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(isOn ? onColor.opacity(0.9) : SagaColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SagaSpacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: SagaRadii.medium, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SagaRadii.medium, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isOn ? 1 : 0.5)
            )
            .shadow(color: isOn ? onColor.opacity(0.25) : .clear, radius: 16, x: 0, y: 0)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .pointingHandOnHover()
        .pressEvents(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isOn)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.08), value: isPressed)
    }

    // Design B-værdier: frosted off-state (white .05), accent-tintet on-state
    // med bredere glow — matcher Liquid Glass Pro-mockupen.
    private var backgroundFill: Color {
        if isOn {
            return onColor.opacity(isHovered ? 0.22 : 0.16)
        }
        if isPressed { return SagaColors.surfaceElevated }
        if isHovered { return Color.white.opacity(0.09) }
        return Color.white.opacity(0.05)
    }

    private var borderColor: Color {
        if isOn { return onColor.opacity(0.55) }
        if isHovered { return SagaColors.borderStrong }
        return Color.white.opacity(0.10)
    }
}

/// Disclosure-header til kollapsbare sektioner. Klikbar HStack med chevron
/// der roterer 90° når åbent. Optional badge til at vise et antal.
struct DisclosureRowHeader: View {
    let title: String
    var badge: String? = nil
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: SagaSpacing.xs + 2) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(SagaColors.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(isHovered ? SagaColors.textPrimary : SagaColors.textSecondary)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(SagaColors.accent.opacity(0.18))
                        )
                        .foregroundColor(SagaColors.accent)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, SagaSpacing.lg)
            .padding(.vertical, SagaSpacing.xs + 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .pointingHandOnHover()
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
        .animation(.easeInOut(duration: 0.10), value: isHovered)
    }
}

/// Klikbar version-label i menubar-headeren. Åbner GitHub releases-siden
/// så brugeren kan læse changelog. Vi går til /releases (oversigt) frem for
/// /releases/tag/vX.Y.Z fordi seneste version ikke nødvendigvis er tagget
/// endnu under aktiv udvikling.
struct VersionLink: View {
    @State private var isHovered = false

    private static let releasesURL = URL(string: "https://github.com/Parthee-Vijaya/saga-mac/releases")!

    var body: some View {
        Button(action: openReleases) {
            Text(StatusView.versionLabel)
                .font(SagaTypography.caption)
                .foregroundColor(isHovered ? SagaColors.accent : SagaColors.textTertiary)
                .underline(isHovered, color: SagaColors.accent)
        }
        .buttonStyle(.plain)
        .help("Version \(StatusView.shortVersion) · Build \(StatusView.buildNumber) — klik for release notes")
        .onHover { hovering in isHovered = hovering }
        .pointingHandOnHover()
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func openReleases() {
        NSWorkspace.shared.open(Self.releasesURL)
    }
}

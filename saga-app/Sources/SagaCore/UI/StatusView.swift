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

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            statusSection
            Divider()
            togglesSection
            Divider()
            recentSection
            Divider()
            footer
        }
        .padding(.vertical, SagaSpacing.sm)
        .background(SagaColors.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: SagaSpacing.md) {
            Image(systemName: stateIcon)
                .font(.system(size: 22))
                .foregroundStyle(stateColor)
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

    private var stateText: String {
        switch controller.state {
        case .idle:
            if let err = controller.lastError { return err }
            if !controller.health.asr.isHappy { return "Indlæser ASR-model" }
            return controller.stenografMode ? "Klar · Stenograf-mode" : "Klar"
        case .recording: return "Lytter…"
        case .transcribing: return "Transkriberer…"
        case .routing: return "Tænker…"
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

    // MARK: - Quick toggles

    /// Tre quick-toggles til de hyppigst skiftende modes. Bindes direkte til
    /// SagaController's @Published properties — ændringer reflekteres øjeblikkeligt
    /// i Settings-vinduet og persisteres (eller ikke, jf. privacyMode der er
    /// session-only) gennem deres didSet-handlere på controlleren.
    private var togglesSection: some View {
        HStack(spacing: SagaSpacing.xs + 2) {
            QuickToggle(
                title: "Privacy",
                systemImage: "shield.lefthalf.filled",
                isOn: Binding(
                    get: { controller.privacyMode },
                    set: { controller.privacyMode = $0 }
                ),
                onColor: SagaColors.warning
            )
            QuickToggle(
                title: "Stenograf",
                systemImage: "text.cursor",
                isOn: Binding(
                    get: { controller.stenografMode },
                    set: { controller.stenografMode = $0 }
                ),
                onColor: SagaColors.accent
            )
            QuickToggle(
                title: "Wake-word",
                systemImage: "waveform.badge.mic",
                isOn: Binding(
                    get: { controller.wakeWordEnabled },
                    set: { controller.wakeWordEnabled = $0 }
                ),
                onColor: SagaColors.accent
            )
        }
        .padding(.horizontal, SagaSpacing.lg)
        .padding(.vertical, SagaSpacing.sm)
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
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
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
            Circle()
                .fill(ok ? SagaColors.success : SagaColors.warning)
                .frame(width: 8, height: 8)
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

/// Pill-style toggle til menubar-quick-actions. Mirror af SagaController's
/// @Published booleans (privacyMode, stenografMode, wakeWordEnabled). Bruger
/// onColor til at signalere mode-identitet (warning for privacy, accent for
/// resten). Off-state er minimal; on-state er accent-fyldt med subtil glow.
struct QuickToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let onColor: Color

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(SagaTypography.caption)
                    .lineLimit(1)
            }
            .foregroundColor(isOn ? onColor : SagaColors.textPrimary)
            .padding(.horizontal, SagaSpacing.sm + 2)
            .padding(.vertical, SagaSpacing.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: SagaRadii.small, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SagaRadii.small, style: .continuous)
                    .stroke(borderColor, lineWidth: isOn ? 1 : 0.5)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
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
        .pressEvents(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        )
        .animation(.easeInOut(duration: 0.15), value: isOn)
        .animation(.easeInOut(duration: 0.10), value: isHovered)
        .animation(.easeInOut(duration: 0.08), value: isPressed)
    }

    private var backgroundFill: Color {
        if isOn {
            return onColor.opacity(isHovered ? 0.22 : 0.15)
        }
        if isPressed { return SagaColors.surfaceElevated }
        if isHovered { return SagaColors.surface }
        return Color.clear
    }

    private var borderColor: Color {
        if isOn { return onColor.opacity(0.45) }
        if isHovered { return SagaColors.borderStrong }
        return SagaColors.border
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
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func openReleases() {
        NSWorkspace.shared.open(Self.releasesURL)
    }
}

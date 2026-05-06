import AppKit
import SwiftUI

/// Større HUD-overlay nederst på skærmen. Viser live waveform under recording,
/// shimmer under transcribing, og sparkle under routing. Lukker automatisk
/// efter dismiss().
@MainActor
public final class RecordingHUDController {
    private weak var controller: SagaController?
    private var window: NSWindow?
    private let model = RecordingHUDModel()
    private var escMonitor: Any?

    private let width: CGFloat = 460
    private let height: CGFloat = 175

    /// Kaldes når brugeren trykker esc mens recording — annullerer uden ASR.
    public var onCancel: (() -> Void)?

    public init() {}

    public func attach(controller: SagaController) {
        self.controller = controller
    }

    public func show() {
        model.state = .recording
        model.recordingStart = Date()
        model.errorMessage = nil
        model.activeMode = nil
        ensureWindow().orderFrontRegardless()
        installEscMonitor()
    }

    public func update(state: SagaState, activeMode: Mode? = nil) {
        switch state {
        case .recording:
            model.state = .recording
            if model.recordingStart == nil {
                model.recordingStart = Date()
            }
        case .transcribing:
            model.state = .transcribing
        case .routing:
            model.state = .routing
            model.activeMode = activeMode
        case .idle:
            model.state = .idle
            model.recordingStart = nil
            model.activeMode = nil
        }
    }

    public func dismiss() {
        window?.orderOut(nil)
        model.errorMessage = nil
        model.recordingStart = nil
        model.activeMode = nil
        removeEscMonitor()
    }

    /// Global keyDown-monitor for esc — kaldes mens recording er aktiv så
    /// brugeren kan annullere uden at trigge ASR. Fjernes ved dismiss.
    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }  // 53 = esc
            Task { @MainActor [weak self] in
                self?.onCancel?()
            }
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }

    public func show(error: Error) {
        model.errorMessage = error.localizedDescription
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.dismiss()
        }
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        guard let controller else {
            // Ikke attached endnu — opret minimalt
            let win = NSWindow()
            self.window = win
            return win
        }

        let view = RecordingHUDView(model: model, audio: controller.audio, hotkey: controller.hotkeys.hotkey)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let win = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .statusBar
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.contentView = host

        if let screen = NSScreen.main {
            let rect = screen.visibleFrame
            let x = rect.midX - width / 2
            let y = rect.minY + 100
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.window = win
        return win
    }
}

@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var state: HUDState = .idle
    @Published var errorMessage: String? = nil
    @Published var recordingStart: Date? = nil
    @Published var activeMode: Mode? = nil

    enum HUDState {
        case idle, recording, transcribing, routing
    }
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel
    @ObservedObject var audio: AudioCapture
    let hotkey: Hotkey

    var body: some View {
        ZStack {
            // Mørk solid baggrund + subtle border (dark-first, ignorerer system).
            // Bruger ultraThinMaterial under for at få en lille frost-effekt
            // mod skrivebordet.
            RoundedRectangle(cornerRadius: SagaRadii.xl, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: SagaRadii.xl, style: .continuous)
                        .fill(SagaColors.surfaceElevated.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SagaRadii.xl, style: .continuous)
                        .strokeBorder(SagaColors.border, lineWidth: 1)
                )
                .sagaShadow(.medium)

            VStack(spacing: SagaSpacing.sm) {
                statusLine
                visualizer
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                keyboardHints
            }
            .padding(.horizontal, SagaSpacing.xl)
            .padding(.vertical, SagaSpacing.md)
        }
        .padding(SagaSpacing.sm)
        .preferredColorScheme(.dark)
    }

    private var statusLine: some View {
        HStack(spacing: SagaSpacing.sm) {
            indicator
            Text(title)
                .font(SagaTypography.caption)
                .foregroundColor(SagaColors.textPrimary)
            Spacer(minLength: 0)
            if model.errorMessage == nil {
                timeBadge
            }
        }
    }

    private var keyboardHints: some View {
        HStack(spacing: SagaSpacing.lg) {
            Spacer()
            // Stop = release hotkey
            KeyboardPill(keys: [hotkey.keySymbol], label: model.state == .recording ? "Slip for at sende" : "Hold for at tale")
                .opacity(model.state == .idle || model.state == .recording ? 1 : 0.4)
            // Cancel = esc
            if model.state == .recording {
                KeyboardPill(keys: ["esc"], label: "Annuller")
            }
        }
    }

    @ViewBuilder
    private var timeBadge: some View {
        switch model.state {
        case .recording:
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let elapsed = model.recordingStart.map { context.date.timeIntervalSince($0) } ?? 0
                Text(formatTime(elapsed))
                    .font(SagaTypography.mono)
                    .monospacedDigit()
                    .foregroundColor(SagaColors.accent)
                    .padding(.horizontal, SagaSpacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(SagaColors.accentSubtle)
                    )
            }
        case .transcribing, .routing:
            if let start = model.recordingStart {
                Text(formatTime(Date().timeIntervalSince(start)) + " · " + (model.state == .routing ? "tænker" : "transskriberer"))
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textSecondary)
            } else {
                Text(subtitle)
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textSecondary)
            }
        case .idle:
            Text(subtitle)
                .font(SagaTypography.caption)
                .foregroundColor(SagaColors.textSecondary)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        let mins = Int(total) / 60
        let secs = Int(total) % 60
        let ds = Int((total - floor(total)) * 10)
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        }
        return String(format: "%d.%d s", secs, ds)
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.state {
        case .idle:
            Circle()
                .fill(SagaColors.textTertiary)
                .frame(width: 10, height: 10)
        case .recording:
            Circle()
                .fill(SagaColors.accent)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(SagaColors.accent.opacity(0.4), lineWidth: 5)
                        .scaleEffect(2.2)
                        .opacity(0.6)
                )
        case .transcribing:
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SagaColors.accent)
                .symbolEffect(.variableColor.iterative, isActive: true)
        case .routing:
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SagaColors.accent)
                .symbolEffect(.pulse, isActive: true)
        }
    }

    private var title: String {
        if model.errorMessage != nil { return "Saga – fejl" }
        switch model.state {
        case .idle: return "Saga"
        case .recording: return "Lytter…"
        case .transcribing: return "Transskriberer"
        case .routing:
            if let mode = model.activeMode {
                return "Mode: \(mode.title)"
            }
            return "Tænker"
        }
    }

    private var subtitle: String {
        if let err = model.errorMessage { return err }
        switch model.state {
        case .idle: return "Hold ⌥ for at tale"
        case .recording: return "Slip når du er færdig"
        case .transcribing: return "Canary kører lokalt"
        case .routing: return "LM Studio formaterer"
        }
    }

    @ViewBuilder
    private var visualizer: some View {
        switch model.state {
        case .recording:
            WaveformBars(levels: audio.levelHistory, accent: SagaColors.accent)
        case .transcribing:
            ShimmerBars(accent: SagaColors.accent)
        case .routing:
            ShimmerBars(accent: SagaColors.accent.opacity(0.8))
        case .idle:
            Capsule()
                .fill(SagaColors.textTertiary.opacity(0.4))
                .frame(height: 2)
        }
    }
}

// MARK: - Waveform-bars (live audio levels)

struct WaveformBars: View {
    let levels: [Float]
    let accent: Color

    /// Antal bar-elementer.
    private let barCount: Int = 36

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    barView(for: i, height: geo.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func barView(for index: Int, height: CGFloat) -> some View {
        let level = sampledLevel(at: index)
        // Boost lave levels visuelt så stille tale stadig giver synlige bars
        let boosted = pow(CGFloat(max(0.03, level)), 0.7)
        let barHeight = max(6, height * boosted)

        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent, accent.opacity(0.5)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 5, height: barHeight)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: barHeight)
    }

    private func sampledLevel(at barIndex: Int) -> Float {
        guard !levels.isEmpty else { return 0 }
        // Tag de seneste `barCount` levels (hale) — så bars rulles "fra højre"
        let tail = max(0, levels.count - barCount)
        let idx = tail + barIndex
        if idx < levels.count { return levels[idx] }
        return 0
    }
}

// MARK: - Shimmer-bars (under transcribe/route)

struct ShimmerBars: View {
    let accent: Color

    private let barCount: Int = 36

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let wave = sin(t * 2.4 + Double(i) * 0.35)
                        let amplitude = CGFloat(0.35 + 0.55 * (wave + 1) / 2)
                        let barHeight = max(6, geo.size.height * amplitude)

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.85), accent.opacity(0.35)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(width: 5, height: barHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

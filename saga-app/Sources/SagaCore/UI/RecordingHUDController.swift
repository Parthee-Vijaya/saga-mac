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

    private let width: CGFloat = 480
    private let height: CGFloat = 110

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
                        .fill(SagaColors.surfaceElevated.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SagaRadii.xl, style: .continuous)
                        .strokeBorder(SagaColors.border, lineWidth: 1)
                )
                .sagaShadow(.medium)

            // Kompakt 2-row Superwhisper-stil layout:
            // Row 1: full-width waveform/visualizer (tæt + horisontal, fylder bredden)
            // Row 2: logo venstre | timer center | keyboard-pills højre
            VStack(spacing: SagaSpacing.xs) {
                visualizer
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .padding(.top, SagaSpacing.sm)

                Divider()
                    .background(SagaColors.border)
                    .opacity(0.6)

                bottomBar
            }
            .padding(.horizontal, SagaSpacing.md)
            .padding(.vertical, SagaSpacing.sm)
        }
        .padding(SagaSpacing.sm)
        .preferredColorScheme(.dark)
    }

    private var bottomBar: some View {
        ZStack {
            // Edges: logo venstre, keyboard-pills højre
            HStack(spacing: SagaSpacing.md) {
                indicator
                Spacer()
                if model.state == .recording {
                    KeyboardPill(keys: [hotkey.keySymbol], label: "Stop")
                    KeyboardPill(keys: ["esc"], label: "Annuller")
                } else if model.state == .idle {
                    KeyboardPill(keys: [hotkey.keySymbol], label: "Hold for at tale")
                }
            }

            // Center: live timer eller status-text — eksplicit centeret via ZStack
            statusText
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var statusText: some View {
        switch model.state {
        case .recording:
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let elapsed = model.recordingStart.map { context.date.timeIntervalSince($0) } ?? 0
                Text(formatTime(elapsed))
                    .font(SagaTypography.mono)
                    .foregroundColor(SagaColors.accent)
                    .monospacedDigit()
            }
        default:
            Text(title)
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
            // Saga's lille trekant-logo (matcher Superwhisper's bottom-left logo)
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SagaColors.accentGradient)
        case .recording:
            Circle()
                .fill(SagaColors.accent)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(SagaColors.accent.opacity(0.4), lineWidth: 4)
                        .scaleEffect(2.2)
                        .opacity(0.6)
                )
        case .transcribing:
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SagaColors.accent)
                .symbolEffect(.variableColor.iterative, isActive: true)
        case .routing:
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
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
            // Hvid waveform under recording — matcher Superwhisper's clean look
            WaveformBars(levels: audio.levelHistory, accent: SagaColors.textPrimary)
        case .transcribing:
            ShimmerBars(accent: SagaColors.textPrimary.opacity(0.85))
        case .routing:
            ShimmerBars(accent: SagaColors.accent)
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

    /// Antal bar-elementer. Superwhisper-stil: mange tynde bars i stedet for
    /// få fede bars for et mere "audio-meter"-look.
    private let barCount: Int = 80
    private let barWidth: CGFloat = 1.5
    private let barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: barSpacing) {
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
        // Minimum 0.05 så stille tale stadig giver synlige bars (vis altid lidt aktivitet)
        let boosted = pow(CGFloat(max(0.05, level)), 0.65)
        // Bar-højden er centreret om midten — så de udvider sig op og ned
        let barHeight = max(2, height * boosted)

        Capsule(style: .continuous)
            .fill(accent)
            .frame(width: barWidth, height: barHeight)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: barHeight)
    }

    private func sampledLevel(at barIndex: Int) -> Float {
        guard !levels.isEmpty else { return 0 }
        // Sub-sample levels-arrayet for at matche barCount.
        // Hvis levels er kortere, repeat; hvis længere, downsample.
        let progress = Double(barIndex) / Double(max(1, barCount - 1))
        let levelIdx = Int(progress * Double(levels.count - 1))
        if levelIdx >= 0 && levelIdx < levels.count {
            return levels[levelIdx]
        }
        return 0
    }
}

// MARK: - Shimmer-bars (under transcribe/route)

struct ShimmerBars: View {
    let accent: Color

    private let barCount: Int = 80
    private let barWidth: CGFloat = 1.5
    private let barSpacing: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { geo in
                HStack(alignment: .center, spacing: barSpacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let wave = sin(t * 2.4 + Double(i) * 0.22)
                        let amplitude = CGFloat(0.2 + 0.65 * (wave + 1) / 2)
                        let barHeight = max(2, geo.size.height * amplitude)

                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.75))
                            .frame(width: barWidth, height: barHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

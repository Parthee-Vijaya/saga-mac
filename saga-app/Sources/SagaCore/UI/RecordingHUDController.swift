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

    private let width: CGFloat = 440
    private let height: CGFloat = 145

    public init() {}

    public func attach(controller: SagaController) {
        self.controller = controller
    }

    public func show() {
        model.state = .recording
        model.recordingStart = Date()
        model.errorMessage = nil
        ensureWindow().orderFrontRegardless()
    }

    public func update(state: SagaState) {
        switch state {
        case .recording:
            model.state = .recording
            if model.recordingStart == nil {
                model.recordingStart = Date()
            }
        case .transcribing:
            model.state = .transcribing
            // Bevar recordingStart så vi kan vise hvor lang optagelsen var
        case .routing: model.state = .routing
        case .idle:
            model.state = .idle
            model.recordingStart = nil
        }
    }

    public func dismiss() {
        window?.orderOut(nil)
        model.errorMessage = nil
        model.recordingStart = nil
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

        let view = RecordingHUDView(model: model, audio: controller.audio)
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

    enum HUDState {
        case idle, recording, transcribing, routing
    }
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel
    @ObservedObject var audio: AudioCapture

    var body: some View {
        ZStack {
            // Frosted glass-baggrund med subtil tint
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(borderColor.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(borderColor.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 6)

            VStack(spacing: 8) {
                statusLine
                visualizer
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .padding(8)
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            indicator
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
            Spacer(minLength: 0)
            if model.errorMessage == nil {
                timeBadge
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(accentColor.opacity(0.15))
                    )
            }
        case .transcribing, .routing:
            if let start = model.recordingStart {
                Text(formatTime(Date().timeIntervalSince(start)) + " · transskriberer")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
            } else {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        case .idle:
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
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
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 10, height: 10)
        case .recording:
            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(accentColor.opacity(0.35), lineWidth: 5)
                        .scaleEffect(2.2)
                        .opacity(0.6)
                )
        case .transcribing:
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accentColor)
                .symbolEffect(.variableColor.iterative, isActive: true)
        case .routing:
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accentColor)
                .symbolEffect(.pulse, isActive: true)
        }
    }

    private var title: String {
        if model.errorMessage != nil { return "Saga – fejl" }
        switch model.state {
        case .idle: return "Saga"
        case .recording: return "Lytter…"
        case .transcribing: return "Transskriberer"
        case .routing: return "Tænker"
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

    /// Saga's eneste accent: en mørkere himmelsblå. Konsistent på tværs af
    /// states — kun shape og bevægelse adskiller recording/transcribing/routing.
    private var accentColor: Color {
        Color(red: 0.20, green: 0.55, blue: 0.95)  // deep sky blue
    }

    private var borderColor: Color {
        switch model.state {
        case .idle: return .primary
        default: return accentColor
        }
    }

    @ViewBuilder
    private var visualizer: some View {
        switch model.state {
        case .recording:
            WaveformBars(levels: audio.levelHistory, accent: accentColor)
        case .transcribing:
            ShimmerBars(accent: accentColor)
        case .routing:
            ShimmerBars(accent: accentColor.opacity(0.8))
        case .idle:
            Capsule()
                .fill(Color.secondary.opacity(0.25))
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

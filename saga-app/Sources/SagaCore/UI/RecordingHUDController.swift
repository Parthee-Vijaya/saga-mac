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

    private let width: CGFloat = 500
    private let height: CGFloat = 165

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
        model.completionToast = nil
        removeEscMonitor()
    }

    /// Vis stats-toast i HUD i 1.5s og dismiss derefter. Bruges efter
    /// succesfulde transkriptioner i stedet for direkte dismiss().
    public func dismissWithToast(words: Int, latencyMs: Int, engine: String) {
        guard window != nil else {
            // HUD er allerede væk — bare normal cleanup
            dismiss()
            return
        }
        model.completionToast = RecordingHUDModel.CompletionToast(
            words: words,
            latencyMs: latencyMs,
            engine: engine
        )
        // Cleanup recording-state men behold vinduet synligt under toast
        model.recordingStart = nil
        model.activeMode = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.dismiss()
        }
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

        let view = RecordingHUDView(
            model: model,
            audio: controller.audio,
            controller: controller,
            hotkey: controller.hotkeys.hotkey
        )
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

        // Vælg skærmen hvor cursor er (multi-monitor awareness) i stedet for
        // NSScreen.main. Hvis cursor ikke kan findes på nogen skærm, fall back
        // til main. Bottom-margin 200pt så HUD sidder lidt højere — over dock
        // og dens shadow uanset om dock er stor eller skjult.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let rect = screen?.visibleFrame {
            let x = rect.midX - width / 2
            let y = rect.minY + 200
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
    @Published var completionToast: CompletionToast? = nil

    enum HUDState {
        case idle, recording, transcribing, routing
    }

    /// Stats vist i 1.5s toast efter en transkription er færdig.
    /// Erstatter waveform/partial-area så bruger kan se ord-tæller +
    /// latency + engine før HUD dismisses.
    struct CompletionToast: Equatable {
        let words: Int
        let latencyMs: Int
        let engine: String
    }
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel
    @ObservedObject var audio: AudioCapture
    @ObservedObject var controller: SagaController
    let hotkey: Hotkey

    /// Seneste partial-tekst Saga har vist — brugt til at detektere
    /// hvilke ord der er TILFØJET siden sidst, så vi kan highlighte dem.
    @State private var lastSeenPartial: String = ""

    /// Den nye suffix-del af partial-tekst der skal highlightes med accent-farve.
    /// Tom efter highlight-window udløber (~700ms efter sidste ord-ankomst).
    @State private var highlightedSuffix: String = ""

    /// Task der nulstiller highlightedSuffix efter delay. Cancellet hver gang
    /// nyt partial ankommer (så timer reset'es).
    @State private var highlightTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Frosted-glass HUD: rent .thinMaterial uden tint. Kun en tynd
            // accent-kant — opacity reagerer på audio-volume under recording.
            RoundedRectangle(cornerRadius: SagaRadii.xl, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    // Audio-reactive border: opacity scales fra 0.4 (stille)
                    // til 0.9 (taler højt). Idle/transcribing: fast 0.6.
                    RoundedRectangle(cornerRadius: SagaRadii.xl, style: .continuous)
                        .strokeBorder(SagaColors.accent.opacity(borderOpacity), lineWidth: 1.2)
                        .animation(.easeOut(duration: 0.18), value: borderOpacity)
                )
                // Soft drop shadow til afstandsfornemmelse fra skrivebord
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)

            // Layout (Superwhisper-stil):
            // Row 1 (kun under recording, hvis partial findes): live transcript
            // Row 2: full-width waveform/visualizer
            // Row 3: logo venstre | timer center | keyboard-pills højre
            VStack(spacing: SagaSpacing.xs) {
                if let toast = model.completionToast {
                    // Toast erstatter normal layout i 1.5s efter transcribe
                    completionToastView(toast)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if model.state == .recording, !controller.currentPartial.isEmpty {
                    // Live partial-transcript ovenover waveform. Auto-scroller
                    // til bunden + nye ord highlightes accent i ~700ms.
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(partialAttributedString)
                                .id("partialBottom")
                                .font(SagaTypography.caption)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, SagaSpacing.md)
                        }
                        .frame(maxHeight: 36)  // ~2 linjer caption-tekst
                        .padding(.top, SagaSpacing.sm)
                        .mask(
                            // Top-fade: øverste 40% af visible area fader fra
                            // 0 → 100% opacity. Sikrer "tekst kommer fra bunden"-feel
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .white.opacity(0.4), location: 0.25),
                                    .init(color: .white, location: 0.6),
                                    .init(color: .white, location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .onChange(of: controller.currentPartial) { _, newValue in
                            handlePartialChange(newValue)
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo("partialBottom", anchor: .bottom)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if model.completionToast == nil {
                    visualizer
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .padding(.top, SagaSpacing.sm)
                        .padding(.horizontal, 2)  // næsten kant-til-kant for waveform

                    Divider()
                        .background(SagaColors.border)
                        .opacity(0.6)

                    bottomBar
                        .padding(.horizontal, SagaSpacing.sm)
                }
            }
            .padding(.vertical, SagaSpacing.sm)
            .animation(.easeInOut(duration: 0.15), value: controller.currentPartial)
            .animation(.easeInOut(duration: 0.2), value: model.completionToast)
        }
        // Outer padding giver de små shadows plads til at fade rundt om HUD.
        // 12pt er nok når glow-radius er 6 (drop shadow er 12 men trækker mod y+4).
        .padding(SagaSpacing.md)
        .preferredColorScheme(.dark)
    }

    /// Toast-row der erstatter waveform/partial efter en succesfuld
    /// transkription. Viser ord-tæller, latency og engine-badge.
    private func completionToastView(_ toast: RecordingHUDModel.CompletionToast) -> some View {
        HStack(spacing: SagaSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SagaColors.success)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(toast.words) \(toast.words == 1 ? "ord" : "ord") indsat")
                    .font(SagaTypography.bodyEmphasis)
                    .foregroundColor(SagaColors.textPrimary)
                HStack(spacing: 6) {
                    Text(formatLatency(toast.latencyMs))
                        .font(SagaTypography.mono)
                        .foregroundColor(SagaColors.textSecondary)
                    Text("·")
                        .foregroundColor(SagaColors.textTertiary)
                    if !toast.engine.isEmpty {
                        EngineBadge(label: toast.engine)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, SagaSpacing.lg)
        .padding(.vertical, SagaSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomBar: some View {
        ZStack {
            // Edges: logo venstre, keyboard-pill højre.
            // Stop-pill er fjernet — slip af hotkey er den naturlige stop.
            // Kun esc-annuller-pill under recording (mindre kendt funktion).
            HStack(spacing: SagaSpacing.md) {
                indicator
                Spacer()
                if model.state == .recording {
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
            VStack(spacing: 3) {
                // Linje 1: timer
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let elapsed = model.recordingStart.map { context.date.timeIntervalSince($0) } ?? 0
                    Text(formatTime(elapsed))
                        .font(SagaTypography.mono)
                        .foregroundColor(SagaColors.textPrimary)
                        .monospacedDigit()
                }
                // Linje 2: engine + mic badges side om side
                // Privacy-mode: erstat engine-badge med shield-badge
                HStack(spacing: 4) {
                    if controller.privacyMode {
                        PrivacyBadge()
                    } else {
                        EngineBadge(label: controller.lastEngineLabel ?? activeEngineHint)
                    }
                    MicrophoneBadge(deviceName: audio.currentInputDeviceName)
                }
            }
        case .transcribing, .routing:
            VStack(spacing: 3) {
                // Linje 1: status + latency
                HStack(spacing: SagaSpacing.xs + 2) {
                    Text(title)
                        .font(SagaTypography.caption)
                        .foregroundColor(SagaColors.textSecondary)
                    if let ms = controller.lastTranscribeMs {
                        Text(formatLatency(ms))
                            .font(SagaTypography.mono)
                            .foregroundColor(SagaColors.textPrimary)
                            .monospacedDigit()
                    }
                }
                // Linje 2: engine-badge (hvis sat)
                if let engine = controller.lastEngineLabel {
                    EngineBadge(label: engine)
                }
            }
        case .idle:
            Text(title)
                .font(SagaTypography.caption)
                .foregroundColor(SagaColors.textSecondary)
        }
    }

    /// Saga's hint om hvilken engine VIL blive brugt — vises under recording
    /// før transcribe er startet. Baseret på activeLanguage.
    private var activeEngineHint: String {
        controller.activeLanguage.usesCanary ? "Canary" : "Apple Speech"
    }

    /// Build AttributedString hvor de nyeste ord (highlightedSuffix) har
    /// accent-farve, og resten har normal text-color. Hvis suffix ikke
    /// længere er suffix af current partial (fx pga. backtrack), render
    /// hele teksten i normal farve.
    private var partialAttributedString: AttributedString {
        let full = controller.currentPartial
        let suffix = highlightedSuffix

        guard !suffix.isEmpty, full.hasSuffix(suffix) else {
            var attr = AttributedString(full)
            attr.foregroundColor = SagaColors.textPrimary.opacity(0.95)
            return attr
        }

        let prefixEnd = full.index(full.endIndex, offsetBy: -suffix.count)
        let prefix = String(full[..<prefixEnd])

        var prefixAttr = AttributedString(prefix)
        prefixAttr.foregroundColor = SagaColors.textPrimary.opacity(0.95)

        var suffixAttr = AttributedString(suffix)
        suffixAttr.foregroundColor = SagaColors.accent

        prefixAttr.append(suffixAttr)
        return prefixAttr
    }

    /// Detect nye ord siden sidst og start highlight-window. Cancel evt.
    /// kørende reset-task så vinduet "forlænges" ved hver opdatering.
    private func handlePartialChange(_ newValue: String) {
        let common = lastSeenPartial.commonPrefix(with: newValue)
        let suffix = String(newValue.dropFirst(common.count))
        if !suffix.isEmpty, suffix != highlightedSuffix {
            highlightedSuffix = suffix
            highlightTask?.cancel()
            highlightTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.35)) {
                        highlightedSuffix = ""
                    }
                }
            }
        }
        lastSeenPartial = newValue
    }

    /// Audio-reactive border opacity: under recording følger den den seneste
    /// audio-level (rolling average af de sidste 5 samples) for at give HUD
    /// en "alive" pulserende kant. Andre states: fast 60% opacity.
    private var borderOpacity: Double {
        guard model.state == .recording else { return 0.6 }
        let recent = audio.levelHistory.suffix(5)
        guard !recent.isEmpty else { return 0.4 }
        let avg = recent.reduce(0, +) / Float(recent.count)
        // Map 0.0..0.5 → 0.35..0.95 (mild kompression af loud signals)
        let normalized = min(1.0, Double(avg) * 2.0)
        return 0.35 + normalized * 0.6
    }

    private func formatLatency(_ ms: Int) -> String {
        if ms >= 1000 {
            return String(format: "%.1fs", Double(ms) / 1000.0)
        }
        return "\(ms)ms"
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
            // Saga's lille logo (matcher Superwhisper's bottom-left logo)
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SagaColors.accentGradient)
        case .recording:
            // Rød pulserende dot — universel "REC"-indikator
            RecordingDot()
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
            // Idle: subtil "breathing" så HUD ikke ser død ud — capsule
            // pulserer mellem 30% og 60% opacity over 4 sek cycle
            BreathingBar()
        }
    }
}

// MARK: - Breathing-bar (idle state)

/// Subtil pulserende capsule — vises i HUD's visualizer-area når idle.
/// Signalerer at Saga er klar uden at tage opmærksomhed.
struct BreathingBar: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Capsule()
            .fill(SagaColors.textTertiary.opacity(0.35 + phase * 0.30))
            .frame(height: 2)
            .scaleEffect(x: 0.85 + phase * 0.15, y: 1.0, anchor: .center)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    phase = 1.0
                }
            }
    }
}

// MARK: - Waveform-bars (live audio levels)

struct WaveformBars: View {
    let levels: [Float]
    let accent: Color

    /// Antal bar-elementer. Tæt audio-meter-look som Superwhisper.
    private let barCount: Int = 100
    private let barWidth: CGFloat = 1.5
    private let barSpacing: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Subtil center-line der "anchorer" symmetrien
                Rectangle()
                    .fill(accent.opacity(0.18))
                    .frame(height: 0.5)

                HStack(alignment: .center, spacing: barSpacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        barView(for: i, height: geo.size.height)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask(
                // Fade-out i kanterne — bars i randen er svagere
                LinearGradient(
                    colors: [.clear, .white, .white, .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        }
    }

    @ViewBuilder
    private func barView(for index: Int, height: CGFloat) -> some View {
        let level = sampledLevel(at: index)
        // Per-bar deterministisk variation så hver bar har sin egen "personlighed"
        // — ikke alle bars har samme højde selv ved samme audio-level
        let variation = perBarVariation(at: index)
        let boosted = pow(CGFloat(max(0.05, level)), 0.6) * variation
        // Total bar-højde fordeles lige mellem top og bund (symmetrisk fra center)
        let halfHeight = max(1, (height * boosted) / 2)

        // Symmetrisk: hver bar består af to capsules der vokser fra center op + ned.
        // Lille mikro-variation per bar (top vs bund) for organisk audio-meter look.
        let topVariation = 0.92 + perBarMicroVariation(at: index, seed: 1.0) * 0.16
        let bottomVariation = 0.92 + perBarMicroVariation(at: index, seed: 2.0) * 0.16

        VStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(accent)
                .frame(width: barWidth, height: halfHeight * topVariation)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: halfHeight)
            Capsule(style: .continuous)
                .fill(accent.opacity(0.85))
                .frame(width: barWidth, height: halfHeight * bottomVariation)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: halfHeight)
        }
    }

    /// Mikro-variation 0..1 deterministisk per bar+seed til at skabe lille
    /// asymmetri mellem top og bund (organisk look).
    private func perBarMicroVariation(at index: Int, seed: Double) -> CGFloat {
        let noise = abs(sin(Double(index) * 7.331 + seed * 11.5) * 9999.0)
        let fractional = noise - floor(noise)
        return CGFloat(fractional)
    }

    /// Pseudo-random men deterministic variation per bar-index — giver waveform
    /// et naturligt "audio-spectrum"-look hvor bars ikke alle er ens høje.
    /// Bars i midten har lidt højere baseline; bars i kanten lidt lavere.
    private func perBarVariation(at index: Int) -> CGFloat {
        let normalized = Double(index) / Double(max(1, barCount - 1))
        // Center-bias: bars i midten får større variation
        let centerBias = 1.0 - abs(normalized - 0.5) * 0.6
        // Pseudo-random noise per index
        let noise = abs(sin(Double(index) * 12.9898) * 43758.5453)
        let fractional = noise - floor(noise)  // 0..1
        let randVariation = 0.65 + 0.35 * fractional  // 0.65..1.0
        return CGFloat(centerBias * randVariation)
    }

    private func sampledLevel(at barIndex: Int) -> Float {
        guard !levels.isEmpty else { return 0 }
        // Sub-sample levels-arrayet for at matche barCount med interpolation
        // mellem naboer for blødere overgange.
        let progress = Double(barIndex) / Double(max(1, barCount - 1))
        let exactIdx = progress * Double(levels.count - 1)
        let lowIdx = Int(exactIdx)
        let highIdx = min(lowIdx + 1, levels.count - 1)
        let frac = Float(exactIdx - Double(lowIdx))
        if lowIdx >= 0 && highIdx < levels.count {
            return levels[lowIdx] * (1 - frac) + levels[highIdx] * frac
        }
        return 0
    }
}

// MARK: - Recording dot (rød pulserende REC-indikator)

struct RecordingDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(SagaColors.danger.opacity(0.35))
                .frame(width: 18, height: 18)
                .scaleEffect(pulsing ? 1.2 : 0.8)
                .opacity(pulsing ? 0 : 0.7)
            Circle()
                .fill(SagaColors.danger)
                .frame(width: 9, height: 9)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Shimmer-bars (under transcribe/route)

struct ShimmerBars: View {
    let accent: Color

    private let barCount: Int = 100
    private let barWidth: CGFloat = 1.5
    private let barSpacing: CGFloat = 1.5

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
                .mask(
                    LinearGradient(
                        colors: [.clear, .white, .white, .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            }
        }
    }
}

// MARK: - Engine badge (vises ved siden af timer/status i HUD)

/// Lille badge der viser hvilken engine bliver brugt: "Canary" / "Apple
/// Speech" / "LM Studio". Lock-ikon signalerer at engine kører lokalt —
/// ingen audio/tekst sendes til skyen. Stiliseret som lille kapsel med
/// subtle accent-tint.
struct EngineBadge: View {
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 7, weight: .semibold))
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .foregroundColor(SagaColors.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(SagaColors.accent.opacity(0.12))
                .overlay(
                    Capsule().strokeBorder(SagaColors.accent.opacity(0.3), lineWidth: 0.5)
                )
        )
        .help("Kører lokalt på din Mac — ingen audio eller tekst sendes til skyen")
    }
}

// MARK: - Privacy badge

/// Erstatter EngineBadge når privacy-mode er aktivt. Viser shield-ikon
/// med tooltip om hvad det betyder.
struct PrivacyBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 8, weight: .semibold))
            Text("Privat")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .foregroundColor(SagaColors.warning)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(SagaColors.warning.opacity(0.15))
                .overlay(
                    Capsule().strokeBorder(SagaColors.warning.opacity(0.4), lineWidth: 0.5)
                )
        )
        .help("Privacy-mode aktivt — denne dictation gemmes ikke i historik, stats eller journal")
    }
}

// MARK: - Microphone badge

/// Lille badge der viser hvilken mikrofon Saga lytter til. Mic-ikon +
/// kort device-navn. Hjælpsom til at se om Saga bruger AirPods, built-in,
/// eller en USB-mic.
struct MicrophoneBadge: View {
    let deviceName: String

    /// Rens lange Apple-suffix-strings så de ikke fylder unødvendigt.
    /// "MacBook Pro Microphone" → "MacBook Pro"
    /// "External Microphone (USB)" → "External"
    private var cleanedLabel: String {
        deviceName
            .replacingOccurrences(of: " Microphone", with: "")
            .replacingOccurrences(of: " (built-in)", with: "")
            .replacingOccurrences(of: " (USB)", with: "")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            Image(systemName: "mic.fill")
                .font(.system(size: 7, weight: .semibold))
            Text(cleanedLabel)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 110, alignment: .leading)
        }
        .foregroundColor(SagaColors.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            // Brug RoundedRectangle (ikke Capsule) når 2 linjer — Capsule
            // giver underlig oval-form ved tall content. RoundedRectangle
            // wraps pænt om både 1 og 2 lines.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        )
        .help("Aktiv mikrofon: \(deviceName)")
    }
}

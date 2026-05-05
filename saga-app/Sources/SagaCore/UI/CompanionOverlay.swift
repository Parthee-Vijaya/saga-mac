import AppKit
import SwiftUI

/// Statisk-positioneret overlay for Companion-mode.
///
/// Til forskel fra `RecordingHUDController` (som er fokuseret på dictation-feedback)
/// viser denne en samtale-tilstand: hvad brugeren har sagt, hvad Saga svarer,
/// og hvilken state vi er i. Sprint C3 v1: bottom-center positionering, ikke
/// cursor-following. Cursor-following bubble kan komme i v2 hvis det viser sig
/// at være essentielt for use-casen.
@MainActor
public final class CompanionOverlayController {
    private weak var companion: CompanionController?
    private weak var audio: AudioCapture?
    private var window: NSWindow?

    private let width: CGFloat = 540
    private let height: CGFloat = 220

    public init() {}

    public func attach(companion: CompanionController, audio: AudioCapture) {
        self.companion = companion
        self.audio = audio
    }

    public func show() {
        ensureWindow()?.orderFrontRegardless()
    }

    public func dismiss() {
        window?.orderOut(nil)
    }

    private func ensureWindow() -> NSWindow? {
        if let window { return window }
        guard let companion, let audio else { return nil }

        let view = CompanionOverlayView(companion: companion, audio: audio)
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

        // Positionér nederst på den skærm hvor cursor er — undgår multi-monitor-fælder
        let screen = Self.screenForCursor() ?? NSScreen.main
        if let rect = screen?.visibleFrame {
            let x = rect.midX - width / 2
            // 60px over dock — over RecordingHUD's 100px så de ikke overlapper
            let y = rect.minY + 200
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.window = win
        return win
    }

    private static func screenForCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }
}

// MARK: - SwiftUI view

struct CompanionOverlayView: View {
    @ObservedObject var companion: CompanionController
    @ObservedObject var audio: AudioCapture

    var body: some View {
        ZStack {
            // Frosted glass-card med subtil accent-tint baseret på state
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(stateAccent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(stateAccent.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 10) {
                statusHeader
                visualizer
                    .frame(height: 50)
                captions
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .padding(8)
        .opacity(companion.state == .idle ? 0 : 1)
        .animation(.easeInOut(duration: 0.18), value: companion.state)
    }

    // MARK: - Header

    private var statusHeader: some View {
        HStack(spacing: 10) {
            stateIndicator
            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.9))
            Spacer()
            // Discrete "say tak/stop to end"-hint
            if companion.state == .listening {
                Text("Sig 'tak' for at afslutte")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch companion.state {
        case .listening:
            Circle()
                .fill(stateAccent)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(stateAccent.opacity(0.35), lineWidth: 5)
                        .scaleEffect(2.0)
                        .opacity(0.6)
                )
        case .transcribing:
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(stateAccent)
                .symbolEffect(.variableColor.iterative, isActive: true)
        case .thinking:
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(stateAccent)
                .symbolEffect(.pulse, isActive: true)
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(stateAccent)
                .symbolEffect(.variableColor, isActive: true)
        case .idle:
            Circle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 10, height: 10)
        }
    }

    private var headerTitle: String {
        switch companion.state {
        case .idle: return "Companion klar"
        case .listening: return "Lytter"
        case .transcribing: return "Transskriberer"
        case .thinking: return "Tænker"
        case .speaking: return "Taler"
        }
    }

    // MARK: - Visualizer

    @ViewBuilder
    private var visualizer: some View {
        switch companion.state {
        case .listening:
            WaveformBars(levels: audio.levelHistory, accent: stateAccent)
        case .transcribing, .thinking:
            ShimmerBars(accent: stateAccent.opacity(0.85))
        case .speaking:
            ShimmerBars(accent: stateAccent)
        case .idle:
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 2)
        }
    }

    // MARK: - Captions

    private var captions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !companion.currentUserPartial.isEmpty {
                userCaption
            }
            if !companion.currentAssistantBuffer.isEmpty {
                assistantCaption
            }
            if companion.currentUserPartial.isEmpty,
               companion.currentAssistantBuffer.isEmpty,
               companion.state == .listening {
                Text("Tal efter wake-word…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var userCaption: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.top, 2)
            Text(companion.currentUserPartial)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var assistantCaption: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundColor(stateAccent)
                .padding(.top, 2)
            Text(companion.currentAssistantBuffer)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Color

    /// Saga's accent — samme deep-sky-blue som RecordingHUD, så de føles som
    /// del af samme app uanset hvilken HUD der er aktiv.
    private var stateAccent: Color {
        Color(red: 0.20, green: 0.55, blue: 0.95)
    }
}

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
            // Mørk solid card med subtle frost — matcher RecordingHUD
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

            VStack(alignment: .leading, spacing: SagaSpacing.md) {
                statusHeader
                visualizer
                    .frame(height: 44)
                captions
                Spacer(minLength: 0)
                if companion.state == .listening {
                    HStack {
                        Spacer()
                        KeyboardPill(keys: ["sig 'tak'"], label: "for at afslutte")
                    }
                }
            }
            .padding(.horizontal, SagaSpacing.xl)
            .padding(.vertical, SagaSpacing.lg)
        }
        .padding(SagaSpacing.sm)
        .opacity(companion.state == .idle ? 0 : 1)
        .animation(.easeInOut(duration: 0.18), value: companion.state)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var statusHeader: some View {
        HStack(spacing: SagaSpacing.sm) {
            stateIndicator
            Text(headerTitle)
                .font(SagaTypography.bodyEmphasis)
                .foregroundColor(SagaColors.textPrimary)
            Spacer()
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch companion.state {
        case .listening:
            Circle()
                .fill(SagaColors.accent)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(SagaColors.accent.opacity(0.4), lineWidth: 5)
                        .scaleEffect(2.0)
                        .opacity(0.6)
                )
        case .transcribing:
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SagaColors.accent)
                .symbolEffect(.variableColor.iterative, isActive: true)
        case .thinking:
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SagaColors.accent)
                .symbolEffect(.pulse, isActive: true)
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SagaColors.accent)
                .symbolEffect(.variableColor, isActive: true)
        case .idle:
            Circle()
                .fill(SagaColors.textTertiary)
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
            WaveformBars(levels: audio.levelHistory, accent: SagaColors.accent)
        case .transcribing, .thinking:
            ShimmerBars(accent: SagaColors.accent.opacity(0.85))
        case .speaking:
            ShimmerBars(accent: SagaColors.accent)
        case .idle:
            Capsule()
                .fill(SagaColors.textTertiary.opacity(0.4))
                .frame(height: 2)
        }
    }

    // MARK: - Captions

    private var captions: some View {
        VStack(alignment: .leading, spacing: SagaSpacing.sm) {
            if let error = companion.lastError, !error.isEmpty {
                errorCaption(error)
            }
            if !companion.currentUserPartial.isEmpty {
                userCaption
            }
            if !companion.currentAssistantBuffer.isEmpty {
                assistantCaption
            }
            if companion.currentUserPartial.isEmpty,
               companion.currentAssistantBuffer.isEmpty,
               companion.lastError == nil,
               companion.state == .listening {
                Text("Tal efter wake-word…")
                    .font(SagaTypography.body)
                    .foregroundColor(SagaColors.textTertiary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorCaption(_ text: String) -> some View {
        HStack(alignment: .top, spacing: SagaSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(SagaColors.warning)
                .padding(.top, 2)
            Text(text)
                .font(SagaTypography.body)
                .foregroundColor(SagaColors.warning)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var userCaption: some View {
        HStack(alignment: .top, spacing: SagaSpacing.sm) {
            Image(systemName: "person.fill")
                .font(.system(size: 11))
                .foregroundColor(SagaColors.textSecondary)
                .padding(.top, 2)
            Text(companion.currentUserPartial)
                .font(SagaTypography.body)
                .foregroundColor(SagaColors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var assistantCaption: some View {
        HStack(alignment: .top, spacing: SagaSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundColor(SagaColors.accent)
                .padding(.top, 2)
            Text(companion.currentAssistantBuffer)
                .font(SagaTypography.body)
                .foregroundColor(SagaColors.textPrimary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

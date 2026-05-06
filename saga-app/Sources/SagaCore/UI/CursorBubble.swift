import AppKit
import SwiftUI

/// Lille floating bubble der følger musen — Clicky-inspireret.
///
/// Default OFF; opt-in via Settings → Companion → "Vis cursor-bubble".
/// Når aktiv viser den Companion's state (lytter/tænker/taler) som lille
/// ikon nær cursor, så brugeren ikke behøver at flytte fokus til status-bar
/// eller overlay'en for at se hvad Saga laver.
@MainActor
public final class CursorBubbleController {
    private weak var companion: CompanionController?
    private var window: NSWindow?
    private var mouseMonitor: Any?

    private let size: CGFloat = 56
    private let cursorOffset: CGFloat = 20  // afstand fra cursor til bubble

    /// User-facing toggle — persisteres i UserDefaults via Settings binding.
    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "companion.cursorBubble.enabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "companion.cursorBubble.enabled")
            if !newValue { dismiss() }
        }
    }

    public init() {}

    public func attach(companion: CompanionController) {
        self.companion = companion
    }

    public func show() {
        guard isEnabled else { return }
        ensureWindow()?.orderFrontRegardless()
        startMouseTracking()
    }

    public func dismiss() {
        stopMouseTracking()
        window?.orderOut(nil)
    }

    private func ensureWindow() -> NSWindow? {
        if let window { return window }
        guard let companion else { return nil }

        let view = CursorBubbleView(companion: companion)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: size, height: size)

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
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.contentView = host

        // Position bubble ved nuværende mouse-location ved show
        let mouse = NSEvent.mouseLocation
        win.setFrameOrigin(NSPoint(x: mouse.x + cursorOffset, y: mouse.y - size - cursorOffset))

        self.window = win
        return win
    }

    private func startMouseTracking() {
        guard mouseMonitor == nil else { return }
        // Global monitor: events i andre apps. Local monitor: events i Saga selv.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.repositionBubble(toMouseAt: NSEvent.mouseLocation)
            }
        }
    }

    private func stopMouseTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func repositionBubble(toMouseAt mouse: NSPoint) {
        guard let window else { return }
        // Placér bubble nede til højre for cursor med en lille offset.
        // Hvis det ville lægge bubblen uden for skærmen, flip til venstre/oppe.
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        var x = mouse.x + cursorOffset
        var y = mouse.y - size - cursorOffset

        // Højre kant — flip til venstre side af cursor
        if x + size > frame.maxX - 8 {
            x = mouse.x - size - cursorOffset
        }
        // Bund-kant — flip op over cursor
        if y < frame.minY + 8 {
            y = mouse.y + cursorOffset
        }
        // Top-kant — clamp
        if y + size > frame.maxY - 8 {
            y = frame.maxY - size - 8
        }
        // Venstre kant — clamp
        if x < frame.minX + 8 {
            x = frame.minX + 8
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct CursorBubbleView: View {
    @ObservedObject var companion: CompanionController

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(accent.opacity(0.18))
                )
                .overlay(
                    Circle()
                        .stroke(accent.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)

            stateIcon
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(accent)
        }
        .frame(width: 56, height: 56)
        .opacity(companion.state == .idle ? 0 : 1)
        .scaleEffect(companion.state == .idle ? 0.6 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: companion.state)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch companion.state {
        case .listening:
            Image(systemName: "mic.fill")
                .symbolEffect(.variableColor, isActive: true)
        case .transcribing:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: true)
        case .thinking:
            Image(systemName: "sparkles")
                .symbolEffect(.pulse, isActive: true)
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
                .symbolEffect(.variableColor, isActive: true)
        case .idle:
            Image(systemName: "circle")
        }
    }

    private var accent: Color {
        SagaColors.accent
    }
}

import AppKit
import SwiftUI

/// Lille flydende HUD-vindue som vises ved aktiv recording / transcribing.
/// Centeret nederst på skærmen, ingen titlebar, ikke-aktivér.
@MainActor
public final class RecordingHUDController {
    private weak var controller: SagaController?
    private var window: NSWindow?
    private var hostingView: NSHostingView<RecordingHUDView>?
    private let model = RecordingHUDModel()

    public init() {}

    public func attach(controller: SagaController) {
        self.controller = controller
    }

    public func show() {
        model.state = .recording
        model.errorMessage = nil
        ensureWindow().orderFrontRegardless()
    }

    public func update(state: SagaState) {
        switch state {
        case .recording: model.state = .recording
        case .transcribing: model.state = .transcribing
        case .routing: model.state = .routing
        case .idle: model.state = .idle
        }
    }

    public func dismiss() {
        window?.orderOut(nil)
        model.errorMessage = nil
    }

    public func show(error: Error) {
        model.errorMessage = error.localizedDescription
        // Lad fejlen blive vist i 3 sekunder
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.dismiss()
        }
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let view = RecordingHUDView(model: model)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 56)

        let win = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .statusBar
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.contentView = host

        if let screen = NSScreen.main {
            let rect = screen.visibleFrame
            let x = rect.midX - host.frame.width / 2
            let y = rect.minY + 80
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.window = win
        self.hostingView = host
        return win
    }
}

@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var state: HUDState = .idle
    @Published var errorMessage: String? = nil

    enum HUDState {
        case idle, recording, transcribing, routing
    }
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel

    var body: some View {
        HStack(spacing: 12) {
            indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        )
    }

    private var indicator: some View {
        Group {
            switch model.state {
            case .idle:
                Image(systemName: "mic.slash").foregroundColor(.secondary)
            case .recording:
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
                    .symbolEffect(.pulse, isActive: true)
            case .transcribing:
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                    .symbolEffect(.variableColor, isActive: true)
            case .routing:
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                    .symbolEffect(.pulse, isActive: true)
            }
        }
        .font(.system(size: 18))
        .frame(width: 24)
    }

    private var title: String {
        if model.errorMessage != nil { return "Fejl" }
        switch model.state {
        case .idle: return "Saga"
        case .recording: return "Lytter…"
        case .transcribing: return "Transkriberer…"
        case .routing: return "Tænker…"
        }
    }

    private var subtitle: String {
        if let error = model.errorMessage { return error }
        switch model.state {  // swiftlint:disable:next switch_case_alignment
        case .idle: return "Hold Fn for at tale"
        case .recording: return "Slip Fn når du er færdig"
        case .transcribing: return "Hviske kører"
        case .routing: return "LM Studio formaterer svar"
        }
    }
}

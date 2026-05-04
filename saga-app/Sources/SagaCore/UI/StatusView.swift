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

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            statusSection
            Divider()
            recentSection
            Divider()
            footer
        }
        .padding(.vertical, 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: stateIcon)
                .font(.system(size: 22))
                .foregroundStyle(stateColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Saga")
                    .font(.system(size: 14, weight: .semibold))
                Text(stateText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if controller.state == .idle {
                Image(systemName: "option")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("Hold ⌥ for at tale")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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
        case .idle: return controller.health.asr.isHappy ? .green : .orange
        case .recording: return .red
        case .transcribing: return .accentColor
        case .routing: return .purple
        }
    }

    private var stateText: String {
        switch controller.state {
        case .idle:
            if let err = controller.lastError { return err }
            return controller.health.asr.isHappy ? "Klar" : "Indlæser ASR-model"
        case .recording: return "Lytter…"
        case .transcribing: return "Transkriberer…"
        case .routing: return "Tænker…"
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Seneste")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if !controller.history.entries.isEmpty {
                    Button("Se alle…") { openWindow(id: "history") }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }

            if controller.history.entries.isEmpty {
                Text("Ingen transkriptioner endnu.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(controller.history.entries.prefix(5)) { entry in
                        HistoryRowCompact(entry: entry)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    openSettings()
                } label: {
                    Label("Indstillinger…", systemImage: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    openWindow(id: "documents")
                } label: {
                    Label("Document-analyse", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task {
                        await controller.shutdown()
                        NSApp.terminate(nil)
                    }
                } label: {
                    Label("Afslut", systemImage: "power")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Subviews

struct HealthRow: View {
    let title: String
    let detail: String
    let ok: Bool
    let action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
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
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(allOk ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text("Permissions")
                    .font(.system(size: 12, weight: .medium))
                Text("Mikrofon: \(micLabel)  ·  Accessibility: \(hasAX ? "✓" : "—")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
                .font(.system(size: 11))
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.wasModeApplied ? "sparkles" : "text.cursor")
                .font(.system(size: 10))
                .foregroundColor(entry.wasModeApplied ? .purple : .accentColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.processedText)
                    .font(.system(size: 12))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.timestamp, style: .time)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    if let mode = entry.modeId {
                        Text("·").foregroundColor(.secondary).font(.system(size: 9))
                        Text(mode)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text("·").foregroundColor(.secondary).font(.system(size: 9))
                    Text(String(format: "%.2fs", Double(entry.durationMs) / 1000.0))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

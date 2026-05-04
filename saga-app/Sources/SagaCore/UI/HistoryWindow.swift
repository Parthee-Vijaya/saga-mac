import AppKit
import SwiftUI

/// Fuld-vindue der viser hele transkriptionshistorikken. Kan åbnes via "Se alle…"
/// fra menu-popover'en. Indeholder søgning, eksport og clear-funktion.
public struct HistoryWindow: View {
    @EnvironmentObject private var controller: SagaController
    @State private var query = ""
    @State private var showClearConfirm = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            list
        }
        .frame(minWidth: 580, minHeight: 400)
        .alert("Slet hele historikken?", isPresented: $showClearConfirm) {
            Button("Annullér", role: .cancel) {}
            Button("Slet", role: .destructive) {
                controller.history.clear()
            }
        } message: {
            Text("\(controller.history.entries.count) transkriptioner slettes permanent.")
        }
    }

    private var filtered: [TranscriptEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return controller.history.entries }
        return controller.history.entries.filter {
            $0.rawText.lowercased().contains(q)
                || $0.processedText.lowercased().contains(q)
                || ($0.modeId ?? "").contains(q)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Søg i historik…", text: $query)
                .textFieldStyle(.plain)
            Spacer()
            Text("\(filtered.count) / \(controller.history.entries.count)")
                .font(.caption)
                .foregroundColor(.secondary)
            Button {
                showClearConfirm = true
            } label: {
                Label("Ryd alt", systemImage: "trash")
            }
            .disabled(controller.history.entries.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if filtered.isEmpty {
                    emptyState
                } else {
                    ForEach(filtered) { entry in
                        HistoryRowFull(entry: entry)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(query.isEmpty ? "Ingen transkriptioner endnu." : "Ingen match for \"\(query)\".")
                .font(.body)
                .foregroundColor(.secondary)
            if query.isEmpty {
                Text("Hold Fn-tasten og tal for at lave din første.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding()
    }
}

struct HistoryRowFull: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: entry.wasModeApplied ? "sparkles" : "text.cursor")
                    .foregroundColor(entry.wasModeApplied ? .purple : .accentColor)
                Text(entry.timestamp, format: .dateTime.day().month().hour().minute().second())
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                if let mode = entry.modeId {
                    Text(mode)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundColor(.purple)
                }
                Spacer()
                Text(detailLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            if entry.wasModeApplied {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledTextBlock(label: "Du sagde", text: entry.rawText, faded: true)
                    LabeledTextBlock(label: "Resultat", text: entry.processedText, faded: false)
                }
            } else {
                Text(entry.processedText)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .contextMenu {
            Button("Kopiér resultat") {
                copy(entry.processedText)
            }
            Button("Kopiér rå-transkription") {
                copy(entry.rawText)
            }
        }
    }

    private var detailLabel: String {
        let dur = Double(entry.durationMs) / 1000.0
        let inf = Double(entry.inferenceMs) / 1000.0
        return String(format: "%.2fs audio · %.2fs inference · rtf %.2f", dur, inf, entry.rtf)
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

struct LabeledTextBlock: View {
    let label: String
    let text: String
    let faded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(text)
                .font(.body)
                .foregroundColor(faded ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }
}

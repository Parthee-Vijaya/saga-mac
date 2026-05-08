import AppKit
import SwiftUI

/// Fuld-vindue der viser hele transkriptionshistorikken. Kan åbnes via "Se alle…"
/// fra menu-popover'en. Indeholder søgning (fuld-tekst over rå+resultat),
/// dato-filter, mode-filter og clear-funktion.
public struct HistoryWindow: View {
    @EnvironmentObject private var controller: SagaController
    @State private var query = ""
    @State private var dateFilter: DateFilter = .all
    @State private var modeFilter: String = "__all__"  // "__all__" / "__none__" / specific modeId
    @State private var showClearConfirm = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            filterBar
            Divider()
            list
        }
        .frame(minWidth: 640, minHeight: 460)
        .alert("Slet hele historikken?", isPresented: $showClearConfirm) {
            Button("Annullér", role: .cancel) {}
            Button("Slet", role: .destructive) {
                controller.history.clear()
            }
        } message: {
            Text("\(controller.history.entries.count) transkriptioner slettes permanent.")
        }
    }

    /// Unique mode-IDs i historikken — sorteret alfabetisk for picker.
    private var availableModes: [String] {
        let ids = controller.history.entries.compactMap { $0.modeId }
        return Array(Set(ids)).sorted()
    }

    private var filtered: [TranscriptEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()

        return controller.history.entries.filter { entry in
            // 1. Tekst-søgning
            if !q.isEmpty {
                let textMatches = entry.rawText.lowercased().contains(q)
                    || entry.processedText.lowercased().contains(q)
                    || (entry.modeId ?? "").contains(q)
                if !textMatches { return false }
            }

            // 2. Dato-filter
            if let cutoff = dateFilter.cutoff(from: now), entry.timestamp < cutoff {
                return false
            }

            // 3. Mode-filter
            switch modeFilter {
            case "__all__":
                break  // alle accepteres
            case "__none__":
                if entry.modeId != nil { return false }
            default:
                if entry.modeId != modeFilter { return false }
            }

            return true
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
                .font(.caption.monospacedDigit())
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

    private var filterBar: some View {
        HStack(spacing: 10) {
            // Dato-filter
            Picker("Periode", selection: $dateFilter) {
                ForEach(DateFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)

            // Mode-filter
            Picker("Mode", selection: $modeFilter) {
                Text("Alle modes").tag("__all__")
                Text("Kun rå dictation").tag("__none__")
                if !availableModes.isEmpty {
                    Divider()
                    ForEach(availableModes, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)

            Spacer()

            // Reset-knap (vises kun når et filter er aktivt)
            if dateFilter != .all || modeFilter != "__all__" || !query.isEmpty {
                Button("Nulstil filtre") {
                    query = ""
                    dateFilter = .all
                    modeFilter = "__all__"
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    enum DateFilter: String, CaseIterable, Hashable {
        case today
        case sevenDays
        case thirtyDays
        case all

        var label: String {
            switch self {
            case .today: return "I dag"
            case .sevenDays: return "Seneste 7 dage"
            case .thirtyDays: return "Seneste 30 dage"
            case .all: return "Alle"
            }
        }

        /// Cutoff-dato. Entries før denne filtreres væk. nil = ingen cutoff.
        func cutoff(from now: Date) -> Date? {
            let cal = Calendar.current
            switch self {
            case .today:
                return cal.startOfDay(for: now)
            case .sevenDays:
                return cal.date(byAdding: .day, value: -7, to: now)
            case .thirtyDays:
                return cal.date(byAdding: .day, value: -30, to: now)
            case .all:
                return nil
            }
        }
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

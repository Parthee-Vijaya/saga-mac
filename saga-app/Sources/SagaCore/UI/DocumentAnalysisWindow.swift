import AppKit
import SwiftUI

/// Vindue der viser document-analyse: vælg fil, se findings.
public struct DocumentAnalysisWindow: View {
    @EnvironmentObject private var controller: SagaController

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if controller.documents.isAnalyzing {
                analyzingView
            } else if let result = controller.documents.lastResult {
                resultView(result)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Document-analyse")
                    .font(.system(size: 16, weight: .semibold))
                Text("Find skjulte klausuler i kontrakter og vilkår")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                if let url = controller.documents.openFilePicker() {
                    Task { await controller.documents.analyze(url: url, controller: controller) }
                }
            } label: {
                Label("Vælg fil…", systemImage: "doc.badge.plus")
            }
            .controlSize(.large)
            .keyboardShortcut("o")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var analyzingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Analyserer dokument…")
                .foregroundColor(.secondary)
            Text("Kan tage 30-90 sek for længere kontrakter")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Ingen dokument analyseret endnu")
                .font(.body)
                .foregroundColor(.secondary)
            Text("Tryk 'Vælg fil…' for at analysere en kontrakt eller vilkår.\nUnderstøttede formater: PDF, DOCX, RTF, TXT.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func resultView(_ result: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary-bar
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.fileName)
                        .font(.system(size: 13, weight: .medium))
                    Text("\(result.charCount) tegn · \(result.chunkCount) sektion\(result.chunkCount == 1 ? "" : "er") · analyseret \(result.analyzedAt, format: .dateTime.hour().minute())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if result.hasFindings {
                    StatBadge(count: result.findings.count, label: "fund", color: .blue)
                    if result.highSeverityCount > 0 {
                        StatBadge(count: result.highSeverityCount, label: "høj alvor", color: .red)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.06))

            Divider()

            if let err = result.error {
                Text("Fejl: \(err)")
                    .foregroundColor(.red)
                    .padding()
            } else if !result.hasFindings {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("Ingen bemærkelsesværdige klausuler fundet")
                        .font(.body)
                    Text("Saga fandt intet at flagge i dette dokument.\nDet er ikke en garanti for at dokumentet er problemfrit — bare at LLM ikke fangede noget i kategorierne binding/fortrydelse/fornyelse/gebyr/opsigelse.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(result.findings) { finding in
                            FindingCard(finding: finding)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

struct StatBadge: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct FindingCard: View {
    let finding: Finding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: finding.categoryIcon)
                    .foregroundColor(severityColor)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(finding.title)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        SeverityPill(severity: finding.severity)
                        CategoryPill(category: finding.category)
                    }
                    Text(finding.explanation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !finding.quote.isEmpty {
                Text(finding.quote)
                    .font(.callout.italic())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(6)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(severityColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var severityColor: Color {
        switch finding.severity.lowercased() {
        case "høj": return .red
        case "medium": return .orange
        default: return .blue
        }
    }
}

struct SeverityPill: View {
    let severity: String

    var body: some View {
        Text(severity.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private var color: Color {
        switch severity.lowercased() {
        case "høj": return .red
        case "medium": return .orange
        default: return .blue
        }
    }
}

struct CategoryPill: View {
    let category: String

    var body: some View {
        Text(category.uppercased())
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .foregroundColor(.secondary)
            .cornerRadius(4)
    }
}

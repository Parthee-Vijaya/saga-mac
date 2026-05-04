import SwiftUI

/// Editor til at oprette eller redigere en custom Mode. Vises som sheet
/// fra ModesSettingsTab.
public struct CustomModeEditor: View {
    @EnvironmentObject private var controller: SagaController
    @Environment(\.dismiss) private var dismiss

    /// `nil` = opret ny mode. Eksisterende = redigér.
    let existing: Mode?

    @State private var title: String
    @State private var triggersText: String
    @State private var systemPrompt: String
    @State private var temperature: Double

    public init(existing: Mode? = nil) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _triggersText = State(initialValue: existing?.triggers.joined(separator: ", ") ?? "")
        _systemPrompt = State(initialValue: existing?.systemPrompt ?? "")
        _temperature = State(initialValue: existing?.temperature ?? 0.3)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                form
                    .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 580, height: 600)
    }

    private var header: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .foregroundColor(.accentColor)
            Text(existing == nil ? "Ny custom mode" : "Redigér mode")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Titel").font(.system(size: 12, weight: .medium))
                TextField("fx 'Tweet-format'", text: $title)
                    .textFieldStyle(.roundedBorder)
                Text("Vises i Settings og HUD når mode'en kører.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Trigger-fraser").font(.system(size: 12, weight: .medium))
                TextField("fx 'tweet:, twitter:, x:'", text: $triggersText)
                    .textFieldStyle(.roundedBorder)
                Text("Komma-separeret. Mode aktiveres når din dictation starter med en af dem.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("System-prompt").font(.system(size: 12, weight: .medium))
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(minHeight: 160)
                    .padding(6)
                    .background(Color.gray.opacity(0.06))
                    .cornerRadius(6)
                Text("Hvad LLM skal gøre med din tekst. Eksempel: 'Lav et tweet (max 280 tegn) på dansk baseret på input. Returnér KUN tweet-teksten.'")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(String(format: "%.2f", temperature))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Slider(value: $temperature, in: 0...1, step: 0.05)
                Text("Lav (0-0.3) = forudsigelig, høj (0.7-1) = kreativ.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if existing != nil {
                Button("Slet", role: .destructive) {
                    if let mode = existing {
                        controller.modes.deleteCustom(id: mode.id)
                    }
                    dismiss()
                }
            }
            Spacer()
            Button("Annullér") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(existing == nil ? "Opret" : "Gem") {
                save()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !parsedTriggers.isEmpty
            && !systemPrompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var parsedTriggers: [String] {
        triggersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        let id = existing?.id ?? controller.modes.generateCustomID(from: title)
        let mode = Mode(
            id: id,
            title: title.trimmingCharacters(in: .whitespaces),
            triggers: parsedTriggers,
            systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            temperature: temperature
        )
        if existing == nil {
            controller.modes.addCustom(mode)
        } else {
            controller.modes.updateCustom(mode)
        }
    }
}

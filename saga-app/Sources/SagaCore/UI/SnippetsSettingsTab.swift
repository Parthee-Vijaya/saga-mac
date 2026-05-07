import SwiftUI

/// Settings-tab til at administrere voice-snippets.
///
/// Snippets er trigger → tekstblok: sig "min sig" → indsæt "Med venlig
/// hilsen, Parthee Vijaya". Multi-line expansions tillades. Kører efter
/// vocabulary + filler-strip men før mode-routing.
struct SnippetsSettingsTab: View {
    @EnvironmentObject private var controller: SagaController
    @State private var showNewEntryEditor: Bool = false
    @State private var editingEntry: Snippet?
    @State private var showDeleteAllConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard(
                    "Master-toggle",
                    footer: "Slå alle snippets fra uden at slette dem."
                ) {
                    SettingsRow(
                        "Aktivér snippets",
                        subtitle: "Trigger-fraser udvides til tekstblokke under hver transkription."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { controller.snippets.globalEnabled },
                            set: { controller.snippets.globalEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }

                if controller.snippets.entries.isEmpty {
                    SettingsCard("Dine snippets") {
                        VStack(spacing: 8) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary.opacity(0.4))
                                .padding(.top, 8)
                            Text("Ingen snippets endnu")
                                .font(.system(size: 13, weight: .medium))
                            Text("Tilføj fx 'min sig' → din signatur, eller 'min mail' → din email-adresse.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                } else {
                    SettingsCard(
                        "Dine snippets (\(controller.snippets.entries.count))",
                        footer: "Klik på en række for at redigere."
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(controller.snippets.entries) { snippet in
                                SnippetRow(snippet: snippet) {
                                    editingEntry = snippet
                                }
                                .environmentObject(controller)
                                if snippet.id != controller.snippets.entries.last?.id {
                                    Divider().padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }

                HStack {
                    if !controller.snippets.entries.isEmpty {
                        Button(role: .destructive) {
                            showDeleteAllConfirm = true
                        } label: {
                            Label("Slet alle", systemImage: "trash")
                        }
                    }
                    Spacer()
                    Button {
                        showNewEntryEditor = true
                    } label: {
                        Label("Ny snippet", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .sheet(isPresented: $showNewEntryEditor) {
            SnippetEditor(snippet: Snippet(trigger: "", expansion: ""))
                .environmentObject(controller)
        }
        .sheet(item: $editingEntry) { snippet in
            SnippetEditor(snippet: snippet)
                .environmentObject(controller)
        }
        .confirmationDialog(
            "Slet alle snippets?",
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Slet alle", role: .destructive) {
                controller.snippets.deleteAll()
            }
            Button("Annuller", role: .cancel) {}
        } message: {
            Text("\(controller.snippets.entries.count) snippets fjernes permanent. Kan ikke fortrydes.")
        }
    }
}

// MARK: - Row

private struct SnippetRow: View {
    @EnvironmentObject private var controller: SagaController
    let snippet: Snippet
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { snippet.enabled },
                set: { newValue in
                    var updated = snippet
                    updated.enabled = newValue
                    controller.snippets.update(updated)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snippet.trigger)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(snippet.enabled ? .primary : .secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(previewExpansion)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if !snippet.notes.isEmpty {
                    Text(snippet.notes)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                controller.snippets.delete(id: snippet.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }

    private var previewExpansion: String {
        let firstLine = snippet.expansion.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        let truncated = firstLine.count > 40 ? String(firstLine.prefix(40)) + "…" : firstLine
        if snippet.expansion.contains("\n") {
            return "\(truncated) [+]"
        }
        return truncated
    }
}

// MARK: - Editor sheet

private struct SnippetEditor: View {
    @EnvironmentObject private var controller: SagaController
    @Environment(\.dismiss) private var dismiss

    @State private var trigger: String
    @State private var expansion: String
    @State private var caseSensitive: Bool
    @State private var enabled: Bool
    @State private var notes: String

    private let snippetId: UUID
    private let isExisting: Bool

    init(snippet: Snippet) {
        self.snippetId = snippet.id
        self.isExisting = !snippet.trigger.isEmpty
        _trigger = State(initialValue: snippet.trigger)
        _expansion = State(initialValue: snippet.expansion)
        _caseSensitive = State(initialValue: snippet.caseSensitive)
        _enabled = State(initialValue: snippet.enabled)
        _notes = State(initialValue: snippet.notes)
    }

    private var isValid: Bool {
        let t = trigger.trimmingCharacters(in: .whitespaces)
        let e = expansion.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && !e.isEmpty && t != e
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isExisting ? "Redigér snippet" : "Ny snippet")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Trigger", hint: "Frase brugeren skal sige (case-insensitive default).") {
                        TextField("min sig", text: $trigger)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    field("Expansion", hint: "Tekst der indsættes i stedet. Multi-line tilladt.") {
                        TextEditor(text: $expansion)
                            .font(.system(.body))
                            .frame(minHeight: 80, maxHeight: 200)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3))
                            )
                    }
                    Toggle("Case-sensitive", isOn: $caseSensitive)
                    Toggle("Aktiv", isOn: $enabled)
                    field("Note (valgfri)", hint: "Til dig selv — vises i listen.") {
                        TextField("Min email-signatur", text: $notes)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Divider()

            HStack {
                if isExisting {
                    Button(role: .destructive) {
                        controller.snippets.delete(id: snippetId)
                        dismiss()
                    } label: {
                        Label("Slet", systemImage: "trash")
                    }
                }
                Spacer()
                Button("Annuller") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isExisting ? "Gem" : "Opret") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 460)
    }

    @ViewBuilder
    private func field<Content: View>(
        _ title: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content()
            Text(hint).font(.caption).foregroundColor(.secondary)
        }
    }

    private func save() {
        let snippet = Snippet(
            id: snippetId,
            trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
            expansion: expansion,
            caseSensitive: caseSensitive,
            enabled: enabled,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if isExisting {
            controller.snippets.update(snippet)
        } else {
            controller.snippets.add(snippet)
        }
        dismiss()
    }
}

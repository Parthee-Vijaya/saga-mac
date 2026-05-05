import SwiftUI

/// Settings-tab til at administrere brugerens vocabulary-entries.
///
/// Vocabulary er en post-processing-regel: når Canary konsekvent misforstår
/// et bestemt ord (egennavn, akronym, tech-term), kan brugeren tilføje en
/// pattern → replacement-mapping her. Reglerne anvendes på rå transcript
/// før mode-routing.
struct VocabularySettingsTab: View {
    @EnvironmentObject private var controller: SagaController
    @State private var showNewEntryEditor: Bool = false
    @State private var editingEntry: VocabularyEntry?
    @State private var showDeleteAllConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard(
                    "Master-toggle",
                    footer: "Slå alle vocabulary-regler fra uden at slette dem. Praktisk til at sammenligne med/uden."
                ) {
                    SettingsRow(
                        "Aktivér ordforråd",
                        subtitle: "Anvender alle aktive entries på hver transkription."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { controller.vocabulary.globalEnabled },
                            set: { controller.vocabulary.globalEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }

                if controller.vocabulary.entries.isEmpty {
                    SettingsCard("Dine entries") {
                        VStack(spacing: 8) {
                            Image(systemName: "text.book.closed")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary.opacity(0.4))
                                .padding(.top, 8)
                            Text("Ingen entries endnu")
                                .font(.system(size: 13, weight: .medium))
                            Text("Tilføj egennavne, akronymer eller termer som ASR konsekvent misforstår.")
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
                        "Dine entries (\(controller.vocabulary.entries.count))",
                        footer: "Klik på en række for at redigere. Reglerne anvendes i listens rækkefølge."
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(controller.vocabulary.entries) { entry in
                                VocabularyEntryRow(entry: entry) {
                                    editingEntry = entry
                                }
                                .environmentObject(controller)
                                if entry.id != controller.vocabulary.entries.last?.id {
                                    Divider().padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }

                HStack {
                    if !controller.vocabulary.entries.isEmpty {
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
                        Label("Ny entry", systemImage: "plus.circle.fill")
                    }
                    .controlSize(.regular)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showNewEntryEditor) {
            VocabularyEntryEditor()
                .environmentObject(controller)
        }
        .sheet(item: $editingEntry) { entry in
            VocabularyEntryEditor(existing: entry)
                .environmentObject(controller)
        }
        .confirmationDialog(
            "Slet alle vocabulary-entries?",
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Slet alle", role: .destructive) {
                controller.vocabulary.deleteAll()
            }
            Button("Annuller", role: .cancel) {}
        } message: {
            Text("Dette kan ikke fortrydes.")
        }
    }
}

private struct VocabularyEntryRow: View {
    @EnvironmentObject private var controller: SagaController
    let entry: VocabularyEntry
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { newValue in
                    var updated = entry
                    updated.enabled = newValue
                    controller.vocabulary.update(updated)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            Button(action: onEdit) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.pattern)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(entry.enabled ? .primary : .secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(entry.replacement)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(entry.enabled ? .accentColor : .secondary)
                        }
                        HStack(spacing: 6) {
                            if entry.caseSensitive {
                                Text("Aa")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(3)
                            }
                            if entry.wholeWord {
                                Text("ord")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(3)
                            }
                            if !entry.notes.isEmpty {
                                Text(entry.notes)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                controller.vocabulary.delete(id: entry.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Slet denne entry")
        }
        .padding(.vertical, 8)
    }
}

/// Modal-editor til at oprette eller opdatere en VocabularyEntry.
struct VocabularyEntryEditor: View {
    @EnvironmentObject private var controller: SagaController
    @Environment(\.dismiss) private var dismiss

    @State private var pattern: String
    @State private var replacement: String
    @State private var caseSensitive: Bool
    @State private var wholeWord: Bool
    @State private var enabled: Bool
    @State private var notes: String

    private let editingId: UUID?

    init(existing: VocabularyEntry? = nil) {
        self.editingId = existing?.id
        _pattern = State(initialValue: existing?.pattern ?? "")
        _replacement = State(initialValue: existing?.replacement ?? "")
        _caseSensitive = State(initialValue: existing?.caseSensitive ?? false)
        _wholeWord = State(initialValue: existing?.wholeWord ?? true)
        _enabled = State(initialValue: existing?.enabled ?? true)
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var isEditing: Bool { editingId != nil }
    private var isValid: Bool {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedPattern.isEmpty && trimmedPattern != trimmedReplacement
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isEditing ? "Redigér entry" : "Ny entry")
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
                VStack(alignment: .leading, spacing: 16) {
                    fieldGroup(
                        title: "Pattern",
                        hint: "Ordet eller frasen ASR producerer (forkert)."
                    ) {
                        TextField("Fx \"x-code-jen\"", text: $pattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    fieldGroup(
                        title: "Replacement",
                        hint: "Hvad det skal erstattes med."
                    ) {
                        TextField("Fx \"xcodegen\"", text: $replacement)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack(spacing: 24) {
                        Toggle(isOn: $wholeWord) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kun hele ord").font(.system(size: 13))
                                Text("Anbefalet — undgår substring-match.")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Toggle(isOn: $caseSensitive) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Case-sensitiv").font(.system(size: 13))
                                Text("'API' ≠ 'api'.")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: $enabled) {
                        Text("Aktiv").font(.system(size: 13))
                    }

                    fieldGroup(
                        title: "Note (valgfri)",
                        hint: "Hvorfor reglen findes — kun til dig selv."
                    ) {
                        TextField("Fx \"projekt-navn fra arbejde\"", text: $notes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Divider()

            HStack {
                if isEditing, let editingId {
                    Button(role: .destructive) {
                        controller.vocabulary.delete(id: editingId)
                        dismiss()
                    } label: {
                        Label("Slet", systemImage: "trash")
                    }
                }
                Spacer()
                Button("Annuller") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Gem" : "Opret") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 500)
    }

    private func save() {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = VocabularyEntry(
            id: editingId ?? UUID(),
            pattern: trimmedPattern,
            replacement: trimmedReplacement,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            enabled: enabled,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if isEditing {
            controller.vocabulary.update(entry)
        } else {
            controller.vocabulary.add(entry)
        }
        dismiss()
    }

    @ViewBuilder
    private func fieldGroup<Content: View>(
        title: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content()
            Text(hint)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

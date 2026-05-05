import SwiftUI

struct ModesSettingsTab: View {
    @EnvironmentObject private var controller: SagaController
    @State private var testInput: String = "oversæt til engelsk hej verden"
    @State private var testOutput: String = ""
    @State private var testRunning: Bool = false
    @State private var testError: String?
    @State private var showNewModeEditor: Bool = false
    @State private var editingMode: Mode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !controller.modes.custom.isEmpty {
                    SettingsCard(
                        "Custom modes (\(controller.modes.custom.count))",
                        footer: "Egne triggers + system-prompts."
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(controller.modes.custom) { mode in
                                ModeRow(mode: mode, isCustom: true) {
                                    editingMode = mode
                                }
                                .environmentObject(controller)
                            }
                        }
                    }
                }

                SettingsCard(
                    "Indbyggede modes",
                    footer: "Tal med en trigger-frase foran for at aktivere. Slå fra for ren dictation."
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Mode.builtins) { mode in
                            ModeRow(mode: mode, isCustom: false, onEdit: nil)
                                .environmentObject(controller)
                        }
                    }
                }

                SettingsCard(
                    "Test mode",
                    footer: "Skriv en trigger + tekst og se LM Studio-output."
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Fx 'oversæt til engelsk hej verden'", text: $testInput, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                        HStack {
                            Button(testRunning ? "Kører…" : "Test") { runTest() }
                                .disabled(testRunning || testInput.trimmingCharacters(in: .whitespaces).isEmpty)
                            Spacer()
                            if let err = testError {
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            }
                        }
                        if !testOutput.isEmpty {
                            ScrollView {
                                Text(testOutput)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 80)
                            .padding(8)
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        showNewModeEditor = true
                    } label: {
                        Label("Ny custom mode", systemImage: "plus.circle.fill")
                    }
                    .controlSize(.regular)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showNewModeEditor) {
            CustomModeEditor()
                .environmentObject(controller)
        }
        .sheet(item: $editingMode) { mode in
            CustomModeEditor(existing: mode)
                .environmentObject(controller)
        }
    }

    private func runTest() {
        testRunning = true
        testError = nil
        testOutput = ""
        Task {
            defer { testRunning = false }
            do {
                let result = try await controller.modes.route(text: testInput, controller: controller)
                testOutput = result.text + (result.modeApplied ? "" : "  (ingen mode matchede)")
            } catch let err as ModeError {
                testError = err.errorDescription
            } catch {
                testError = error.localizedDescription
            }
        }
    }
}

struct ModeRow: View {
    @EnvironmentObject private var controller: SagaController
    let mode: Mode
    var isCustom: Bool = false
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: Binding(
                get: { controller.modes.isEnabled(mode) },
                set: { controller.modes.setEnabled($0, for: mode) }
            )) { EmptyView() }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mode.title).font(.system(size: 13, weight: .medium))
                    if isCustom {
                        Text("CUSTOM")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18))
                            .foregroundColor(.accentColor)
                            .cornerRadius(3)
                    }
                }
                Text(mode.triggers.joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isCustom, let onEdit {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

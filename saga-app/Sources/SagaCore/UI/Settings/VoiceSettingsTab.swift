import SwiftUI

struct VoiceSettingsTab: View {
    @EnvironmentObject private var controller: SagaController
    @AppStorage("lmStudioBaseURL") private var lmStudioBaseURL: String = "http://localhost:1234/v1"
    @AppStorage("lmStudioModel") private var lmStudioModel: String = "gemma-4-26b-a4b"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard(
                    "Wake-word",
                    footer: "Saga lytter altid via Apples on-device speech recognition. Kræver permission. Default OFF."
                ) {
                    SettingsRow(
                        "Aktivér 'Hej Saga'",
                        subtitle: "Når du siger 'Hej Saga' starter optagelse i 6 sek automatisk."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { controller.wakeWordEnabled },
                            set: { controller.wakeWordEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    if controller.wakeWord.isListening {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Lytter")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    if let err = controller.wakeWord.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                }

                SettingsCard(
                    "Auto-stop ved stilhed (VAD)",
                    footer: "Når aktiv stopper Saga optagelse automatisk efter et stykke stilhed — du behøver ikke holde hotkey hele tiden. Energi-baseret detection, kører lokalt."
                ) {
                    SettingsRow(
                        "Aktivér auto-stop",
                        subtitle: "Slut at holde hotkey nede. Slip når du er færdig — eller bare lad være med at sige mere."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { controller.vadAutoStopEnabled },
                            set: { controller.vadAutoStopEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    if controller.vadAutoStopEnabled {
                        Divider().padding(.vertical, 4)
                        SettingsRow(
                            "Stilheds-tærskel",
                            subtitle: "\(String(format: "%.1f", controller.vadSilenceDuration))s — hvor længe du skal være stille før Saga stopper."
                        ) {
                            Slider(
                                value: Binding(
                                    get: { controller.vadSilenceDuration },
                                    set: { controller.vadSilenceDuration = $0 }
                                ),
                                in: 0.5...3.0,
                                step: 0.1
                            )
                            .frame(width: 180)
                        }
                    }
                }

                SettingsCard(
                    "LM Studio",
                    footer: "Bruges til mode-routing (oversæt, opsummer osv.). Pure dictation virker uden."
                ) {
                    LMStudioDiscoverySection(
                        baseURL: $lmStudioBaseURL,
                        model: $lmStudioModel
                    )
                    .environmentObject(controller)
                }
            }
            .padding(20)
        }
    }
}

struct LMStudioDiscoverySection: View {
    @EnvironmentObject private var controller: SagaController
    @Binding var baseURL: String
    @Binding var model: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    Task { await controller.discoverLMStudio() }
                } label: {
                    if controller.isDiscoveringLMStudio {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Søger…")
                        }
                    } else {
                        Label("Find LM Studio igen", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(controller.isDiscoveringLMStudio)

                Spacer()

                if !controller.discoveredEndpoints.isEmpty {
                    Text("\(controller.discoveredEndpoints.count) fundet")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            if !controller.discoveredEndpoints.isEmpty {
                VStack(spacing: 6) {
                    ForEach(controller.discoveredEndpoints) { endpoint in
                        Button {
                            baseURL = endpoint.baseURL.absoluteString
                            // Bevar nuværende model hvis det er på det nye endpoint;
                            // ellers fald til første model. Forhindrer at endpoint-
                            // skift overstyrer brugerens model-valg.
                            if !endpoint.models.contains(model) {
                                model = endpoint.models.first ?? model
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: baseURL == endpoint.baseURL.absoluteString ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("localhost:\(endpoint.port)")
                                        .font(.system(size: 12, weight: .medium))
                                    Text(endpoint.models.joined(separator: ", "))
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(baseURL == endpoint.baseURL.absoluteString
                                          ? Color.accentColor.opacity(0.08)
                                          : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !controller.isDiscoveringLMStudio {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Ingen LM Studio fundet på localhost.")
                        .font(.caption)
                }
                .foregroundColor(.orange)
                .padding(.vertical, 6)
            }

            // Model-picker: vis alle modeller fra det aktive endpoint som
            // klikbare rækker, så brugeren hurtigt kan skifte mellem fx
            // nemotron-3-nano (hurtig), gpt-oss-20b (mellem), gemma-4-26b (stor).
            if let activeEndpoint = controller.discoveredEndpoints.first(where: {
                $0.baseURL.absoluteString == baseURL
            }), activeEndpoint.models.count > 1 {
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vælg model")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    ForEach(activeEndpoint.models, id: \.self) { modelName in
                        Button {
                            model = modelName
                            controller.lmStudio.configure(
                                baseURL: activeEndpoint.baseURL,
                                model: modelName
                            )
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: model == modelName ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(.accentColor)
                                Text(modelName)
                                    .font(.caption.monospaced())
                                Spacer()
                            }
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(model == modelName
                                          ? Color.accentColor.opacity(0.08)
                                          : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Manuel konfiguration")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                TextField("Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
            }
        }
    }
}

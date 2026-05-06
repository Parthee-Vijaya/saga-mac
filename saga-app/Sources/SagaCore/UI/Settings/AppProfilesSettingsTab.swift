import SwiftUI

/// Per-app overrides — fx "i Mail brug altid format-mode" eller "i Slack
/// hop direkte til stenograf-mode uden LLM".
struct AppProfilesSettingsTab: View {
    @EnvironmentObject private var controller: SagaController
    @State private var editingProfile: AppProfile?
    @State private var showAddSheet: Bool = false
    @State private var showDeleteAllConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsCard(
                    "Per-app profiler",
                    footer: "Saga tilpasser sig den frontmost app. Når du holder hotkey, læses profilen for den app du arbejder i."
                ) {
                    SettingsRow(
                        "Aktivér per-app profiler",
                        subtitle: "Når slået fra ignoreres alle profiler — Saga opfører sig som default."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { controller.appProfiles.globalEnabled },
                            set: { controller.appProfiles.globalEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }

                if controller.appProfiles.profiles.isEmpty {
                    SettingsCard("Dine profiler") {
                        VStack(spacing: 8) {
                            Image(systemName: "app.badge")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary.opacity(0.4))
                                .padding(.top, 8)
                            Text("Ingen profiler endnu")
                                .font(.system(size: 13, weight: .medium))
                            Text("Opret en profil for en specifik app for at få anderledes adfærd der.")
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
                        "Dine profiler (\(controller.appProfiles.profiles.count))",
                        footer: "Klik en række for at redigere."
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(controller.appProfiles.profiles) { profile in
                                AppProfileRow(profile: profile) {
                                    editingProfile = profile
                                }
                                .environmentObject(controller)
                                if profile.id != controller.appProfiles.profiles.last?.id {
                                    Divider().padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }

                HStack {
                    if !controller.appProfiles.profiles.isEmpty {
                        Button(role: .destructive) {
                            showDeleteAllConfirm = true
                        } label: {
                            Label("Slet alle", systemImage: "trash")
                        }
                    }
                    Spacer()
                    if let frontmost = controller.appProfiles.frontmostAppInfo() {
                        Button {
                            // Hurtig "Tilføj profil for current app" — pre-fyldt med frontmost
                            editingProfile = AppProfile(
                                bundleIdentifier: frontmost.bundleId,
                                displayName: frontmost.displayName
                            )
                        } label: {
                            Label("Profil for \(frontmost.displayName)", systemImage: "plus.circle")
                        }
                    } else {
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Ny profil", systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
            .padding(20)
        }
        .sheet(item: $editingProfile) { profile in
            AppProfileEditor(profile: profile)
                .environmentObject(controller)
        }
        .sheet(isPresented: $showAddSheet) {
            AppProfileEditor(profile: AppProfile(bundleIdentifier: "", displayName: ""))
                .environmentObject(controller)
        }
        .confirmationDialog(
            "Slet alle app-profiler?",
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Slet alle", role: .destructive) {
                controller.appProfiles.deleteAll()
            }
            Button("Annuller", role: .cancel) {}
        }
    }
}

private struct AppProfileRow: View {
    @EnvironmentObject private var controller: SagaController
    let profile: AppProfile
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { profile.enabled },
                set: { newValue in
                    var updated = profile
                    updated.enabled = newValue
                    controller.appProfiles.update(updated)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()

            Button(action: onEdit) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(profile.enabled ? .primary : .secondary)
                        HStack(spacing: 6) {
                            Text(profile.bundleIdentifier)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            if let modeId = profile.forcedModeId {
                                Text("→ \(modeId)")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                            if let stenograf = profile.stenografOverride {
                                Text(stenograf ? "stenograf" : "no-stenograf")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(3)
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
                controller.appProfiles.delete(id: profile.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

struct AppProfileEditor: View {
    @EnvironmentObject private var controller: SagaController
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var bundleIdentifier: String
    @State private var forcedModeId: String
    @State private var stenografChoice: StenografChoice
    @State private var languageChoice: LanguageChoice
    @State private var enabled: Bool

    private let profileId: UUID
    private let isExisting: Bool

    init(profile: AppProfile) {
        self.profileId = profile.id
        self.isExisting = !profile.displayName.isEmpty
        _displayName = State(initialValue: profile.displayName)
        _bundleIdentifier = State(initialValue: profile.bundleIdentifier)
        _forcedModeId = State(initialValue: profile.forcedModeId ?? "")
        _enabled = State(initialValue: profile.enabled)
        _stenografChoice = State(initialValue: StenografChoice.from(profile.stenografOverride))
        _languageChoice = State(initialValue: LanguageChoice.from(profile.languageCode))
    }

    enum LanguageChoice: Hashable, Identifiable {
        case useGlobal
        case override(SagaLanguage)

        var id: String {
            switch self {
            case .useGlobal: return "global"
            case .override(let lang): return lang.rawValue
            }
        }

        var label: String {
            switch self {
            case .useGlobal: return "Brug globalt sprog"
            case .override(let lang): return "\(lang.displayName) (\(lang.usesCanary ? "Canary" : "Apple"))"
            }
        }

        static func from(_ code: String?) -> LanguageChoice {
            guard let code, let lang = SagaLanguage(rawValue: code) else { return .useGlobal }
            return .override(lang)
        }

        var asCode: String? {
            switch self {
            case .useGlobal: return nil
            case .override(let lang): return lang.rawValue
            }
        }

        static var allCases: [LanguageChoice] {
            [.useGlobal] + SagaLanguage.allCases.map { .override($0) }
        }
    }

    enum StenografChoice: String, CaseIterable, Identifiable {
        case useGlobal = "global"
        case forceOn = "on"
        case forceOff = "off"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .useGlobal: return "Brug global indstilling"
            case .forceOn: return "Altid stenograf"
            case .forceOff: return "Aldrig stenograf"
            }
        }

        static func from(_ override: Bool?) -> StenografChoice {
            switch override {
            case nil: return .useGlobal
            case .some(true): return .forceOn
            case .some(false): return .forceOff
            }
        }

        var asOverride: Bool? {
            switch self {
            case .useGlobal: return nil
            case .forceOn: return true
            case .forceOff: return false
            }
        }
    }

    private var isValid: Bool {
        !bundleIdentifier.trimmingCharacters(in: .whitespaces).isEmpty &&
            !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isExisting ? "Redigér profil" : "Ny profil")
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
                    fieldGroup(title: "App", hint: "Navnet vist i Saga's UI.") {
                        TextField("Mail", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }
                    fieldGroup(title: "Bundle Identifier", hint: "Find via 'mdls -name kMDItemCFBundleIdentifier /Applications/<App>.app'") {
                        TextField("com.apple.mail", text: $bundleIdentifier)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    fieldGroup(title: "Forced mode", hint: "Mode-ID der altid anvendes på transcript før LLM-routing. Tom = ingen forcing.") {
                        Picker("", selection: $forcedModeId) {
                            Text("Ingen").tag("")
                            ForEach(allModeIds, id: \.self) { id in
                                Text(id).tag(id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    fieldGroup(title: "Stenograf-override", hint: "Override Saga's globale stenograf-toggle for denne specifikke app.") {
                        Picker("", selection: $stenografChoice) {
                            ForEach(StenografChoice.allCases) { choice in
                                Text(choice.label).tag(choice)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    fieldGroup(title: "Sprog-override", hint: "Tving et specifikt sprog når Saga aktiveres i denne app. Fx altid tamilsk i WhatsApp eller engelsk i Slack.") {
                        Picker("", selection: $languageChoice) {
                            ForEach(LanguageChoice.allCases) { choice in
                                Text(choice.label).tag(choice)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    Toggle("Aktiv", isOn: $enabled)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Divider()

            HStack {
                if isExisting {
                    Button(role: .destructive) {
                        controller.appProfiles.delete(id: profileId)
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
        .frame(width: 480, height: 480)
    }

    private var allModeIds: [String] {
        let builtins = Mode.builtins.map { $0.id }
        let custom = controller.modes.custom.map { $0.id }
        return builtins + custom
    }

    private func save() {
        let profile = AppProfile(
            id: profileId,
            bundleIdentifier: bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            forcedModeId: forcedModeId.isEmpty ? nil : forcedModeId,
            stenografOverride: stenografChoice.asOverride,
            languageCode: languageChoice.asCode,
            enabled: enabled
        )
        if isExisting {
            controller.appProfiles.update(profile)
        } else {
            controller.appProfiles.add(profile)
        }
        dismiss()
    }

    @ViewBuilder
    private func fieldGroup<Content: View>(title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
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

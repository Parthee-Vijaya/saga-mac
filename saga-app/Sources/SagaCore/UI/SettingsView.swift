import AVFoundation
import SwiftUI

/// Top-level settings vindue. Hver tab er en separat fil i Settings/-mappen
/// for at holde dette dokument fokuseret på TabView-strukturen og delte
/// building blocks (`SettingsCard`, `SettingsRow`).
public struct SettingsView: View {
    @EnvironmentObject private var controller: SagaController

    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("Generelt", systemImage: "gearshape") }
            VoiceSettingsTab()
                .tabItem { Label("Stemme", systemImage: "mic") }
            ModesSettingsTab()
                .tabItem { Label("Modes", systemImage: "wand.and.stars") }
            AppProfilesSettingsTab()
                .tabItem { Label("Apps", systemImage: "app.badge") }
            CompanionSettingsTab()
                .tabItem { Label("Companion", systemImage: "bubble.left.and.bubble.right") }
            VocabularySettingsTab()
                .tabItem { Label("Ordforråd", systemImage: "text.book.closed") }
            SnippetsSettingsTab()
                .tabItem { Label("Snippets", systemImage: "text.bubble") }
            RemindersSettingsTab()
                .tabItem { Label("Reminders", systemImage: "bell") }
            AboutTab()
                .tabItem { Label("Om", systemImage: "info.circle") }
        }
        .frame(width: 720, height: 680)
        .background(SagaColors.background)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Reusable building blocks

/// En "card" der grupperer relateret indhold med titel + footer-hint.
struct SettingsCard<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SagaSpacing.xs + 2) {
            Text(title)
                .font(SagaTypography.label)
                .foregroundColor(SagaColors.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, SagaSpacing.xs)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(SagaSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: SagaRadii.large)
                    .fill(SagaColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: SagaRadii.large)
                            .strokeBorder(SagaColors.border, lineWidth: 1)
                    )
            )

            if let footer {
                Text(footer)
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textTertiary)
                    .padding(.horizontal, SagaSpacing.xs)
                    .padding(.top, 2)
            }
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: SagaSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SagaTypography.bodyEmphasis)
                    .foregroundColor(SagaColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(SagaTypography.caption)
                        .foregroundColor(SagaColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: SagaSpacing.md)
            trailing()
        }
        .padding(.vertical, SagaSpacing.sm)
    }
}

extension AVAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined: return "Ikke bestemt"
        case .restricted: return "Begrænset"
        case .denied: return "Nægtet"
        case .authorized: return "Tilladt"
        @unknown default: return "Ukendt"
        }
    }
}

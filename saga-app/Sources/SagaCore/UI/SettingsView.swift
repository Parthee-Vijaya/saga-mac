import AVFoundation
import SwiftUI

/// Top-level settings vindue — Liquid Glass Pro-layout (Design B): venstre
/// sidebar med ikon+titel-navigation frem for macOS' top-TabView. Hver tab
/// er fortsat en separat fil i Settings/-mappen; denne fil ejer navigation
/// + delte building blocks (`SettingsCard`, `SettingsRow`).
public struct SettingsView: View {
    @EnvironmentObject private var controller: SagaController

    /// Persisteret så vinduet genåbner på samme tab.
    @AppStorage("settings.selectedTab") private var selectedTabRaw: String = SettingsTab.general.rawValue

    public init() {}

    enum SettingsTab: String, CaseIterable {
        case general, voice, modes, apps, companion, vocabulary, snippets, reminders, about

        var title: String {
            switch self {
            case .general: return "Generelt"
            case .voice: return "Stemme"
            case .modes: return "Modes"
            case .apps: return "Apps"
            case .companion: return "Companion"
            case .vocabulary: return "Ordforråd"
            case .snippets: return "Snippets"
            case .reminders: return "Reminders"
            case .about: return "Om"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .voice: return "mic"
            case .modes: return "wand.and.stars"
            case .apps: return "app.badge"
            case .companion: return "bubble.left.and.bubble.right"
            case .vocabulary: return "text.book.closed"
            case .snippets: return "text.bubble"
            case .reminders: return "bell"
            case .about: return "info.circle"
            }
        }
    }

    private var selectedTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRaw) ?? .general
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(SagaColors.border)
                .frame(width: 0.5)
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 680)
        .background(SagaColors.background)
        .preferredColorScheme(.dark)
    }

    /// Glas-sidebar: mørkere flade end content-området (mockup: rgba(0,0,0,.18)
    /// over panelet) med accent-tintet aktiv-state + inset-ring.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                SidebarButton(
                    title: tab.title,
                    icon: tab.icon,
                    isSelected: tab == selectedTab,
                    action: { selectedTabRaw = tab.rawValue }
                )
            }
            Spacer()
        }
        .padding(.horizontal, SagaSpacing.sm)
        .padding(.top, SagaSpacing.lg)
        .frame(width: 178)
        .background(Color.black.opacity(0.18))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general: GeneralSettingsTab()
        case .voice: VoiceSettingsTab()
        case .modes: ModesSettingsTab()
        case .apps: AppProfilesSettingsTab()
        case .companion: CompanionSettingsTab()
        case .vocabulary: VocabularySettingsTab()
        case .snippets: SnippetsSettingsTab()
        case .reminders: RemindersSettingsTab()
        case .about: AboutTab()
        }
    }
}

/// Sidebar-navigationsknap med Liquid Glass-aktiv-state: accent-tint +
/// inset-ring. Hover giver svag frost.
private struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SagaSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .foregroundColor(isSelected ? .white : SagaColors.textSecondary)
            .padding(.horizontal, SagaSpacing.sm + 2)
            .padding(.vertical, SagaSpacing.xs + 3)
            .background(
                RoundedRectangle(cornerRadius: SagaRadii.small, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SagaRadii.small, style: .continuous)
                    .strokeBorder(
                        isSelected ? SagaColors.accent.opacity(0.30) : .clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .pointingHandOnHover()
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var backgroundFill: Color {
        if isSelected { return SagaColors.accent.opacity(0.18) }
        if isHovered { return Color.white.opacity(0.06) }
        return .clear
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
                // Frosted card (Design B): white-tint frem for solid surface
                // så cards "svæver" på den mørke baggrund.
                RoundedRectangle(cornerRadius: SagaRadii.large, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: SagaRadii.large, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
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

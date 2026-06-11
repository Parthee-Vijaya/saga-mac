import AppKit
import SwiftUI

/// Saga design tokens — centraliseret farve/typografi/spacing.
///
/// Saga er **dark-mode-first**: appen ser identisk ud uanset systemets
/// Light/Dark Appearance. Vi bruger `.preferredColorScheme(.dark)` på alle
/// vinduer og hardcoder farver fra disse tokens i stedet for at bruge
/// `.primary`/`.secondary`/`.windowBackgroundColor` der følger systemet.
///
/// Designet er inspireret af Superwhisper: deep gray baggrund, sky-blue
/// accent, store rundede CTAs, frosted-glass panels.
public enum SagaColors {
    // MARK: - Backgrounds (mørkest → lysest)

    /// Bagvedliggende vindue-baggrund — den mørkeste flade.
    public static let background = Color(red: 0.08, green: 0.08, blue: 0.09)

    /// Panel/section-baggrund — fx Settings-card body.
    public static let surface = Color(red: 0.12, green: 0.12, blue: 0.14)

    /// Hævede flader — fx HUD'er, modals, overlays.
    public static let surfaceElevated = Color(red: 0.16, green: 0.16, blue: 0.18)

    /// Border på cards/HUDs — næsten usynlig, kun til at separere flader.
    public static let border = Color.white.opacity(0.08)

    /// Stærkere border ved hover/selected state.
    public static let borderStrong = Color.white.opacity(0.16)

    // MARK: - Text

    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.65)
    public static let textTertiary = Color.white.opacity(0.4)

    // MARK: - Accent (sky-blue)

    /// Primary accent — Superwhisper-matchet lys sky-blue.
    public static let accent = Color(red: 0.40, green: 0.70, blue: 1.0)

    /// Mørkere version af accent — bruges i gradients + hover states.
    public static let accentDeep = Color(red: 0.20, green: 0.55, blue: 0.95)

    /// Subtle baggrund-fill (knap-hover, selected card-fill).
    public static let accentSubtle = Color(red: 0.40, green: 0.70, blue: 1.0).opacity(0.15)

    /// Border til selected/active states.
    public static let accentBorder = Color(red: 0.40, green: 0.70, blue: 1.0).opacity(0.5)

    /// Standard accent-gradient (top-left til bottom-right).
    public static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Semantic states

    public static let success = Color(red: 0.30, green: 0.85, blue: 0.55)
    public static let warning = Color(red: 1.0, green: 0.75, blue: 0.30)
    public static let danger = Color(red: 1.0, green: 0.45, blue: 0.45)

    // MARK: - Liquid Glass Pro (Design B, valgt 2026-06-10)

    /// Panel-tint over .ultraThinMaterial — mørk blålig frem for ren grå,
    /// så glasset får dybde mod en hvilken som helst desktop-baggrund.
    public static let glassPanelTint = Color(red: 0.11, green: 0.125, blue: 0.165).opacity(0.72)

    /// Basis-glaskant (sider + bund).
    public static let glassBorder = Color.white.opacity(0.16)

    /// Specular highlight — lysere top-kant der simulerer lys ovenfra
    /// rammer glasoverfladen. Bruges som top-stop i specularBorder-gradienten.
    public static let glassSpecular = Color.white.opacity(0.32)

    /// Violet sekundær-glow til aurora-baggrunde (komplementerer accent-blå).
    public static let auroraViolet = Color(red: 0.545, green: 0.361, blue: 0.965)

    /// Border-gradient med specular top: lysere foroven, basis ved bund.
    /// Brug med .strokeBorder(SagaColors.specularBorder, lineWidth: 1).
    public static let specularBorder = LinearGradient(
        stops: [
            .init(color: glassSpecular, location: 0.0),
            .init(color: glassBorder, location: 0.25),
            .init(color: Color.white.opacity(0.10), location: 1.0),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// Typografi-presets. Brug `SagaTypography.heading` etc. i stedet for
/// `.font(.system(size: ...))` så vi har konsistent hierarki.
public enum SagaTypography {
    /// Display: store welcome-headings i wizard. ~28pt bold.
    public static let display = Font.system(size: 28, weight: .bold, design: .default)

    /// Title: section-overskrifter. ~22pt semibold.
    public static let title = Font.system(size: 22, weight: .semibold, design: .default)

    /// Heading: card-overskrifter. ~17pt semibold.
    public static let heading = Font.system(size: 17, weight: .semibold, design: .default)

    /// Body: brødtekst. 14pt regular.
    public static let body = Font.system(size: 14, weight: .regular, design: .default)

    /// Body emphasis: Settings-row-titler etc. 14pt medium.
    public static let bodyEmphasis = Font.system(size: 14, weight: .medium, design: .default)

    /// Caption: hjælpe-tekst, footers. 12pt regular.
    public static let caption = Font.system(size: 12, weight: .regular, design: .default)

    /// Caption emphasis: små labels. 11pt semibold uppercase.
    public static let label = Font.system(size: 11, weight: .semibold, design: .default)

    /// Mono: keyboard-pills, tal, kode. 12pt monospaced.
    public static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
}

/// Corner-radii. Brug `SagaRadii.large` etc. i stedet for hardcoded `cornerRadius: 16`.
public enum SagaRadii {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xl: CGFloat = 20
    /// Pill — bruges til keyboard-hints + andre kapsel-formede elementer.
    public static let pill: CGFloat = 999
}

/// Spacing scale. 4pt-baseret.
public enum SagaSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 32
}

/// Shadow-presets til hævede flader.
public struct SagaShadow: Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public static let subtle = SagaShadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
    public static let medium = SagaShadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
    public static let glow = SagaShadow(color: SagaColors.accent.opacity(0.3), radius: 24, x: 0, y: 0)

    /// Glød til status-dots i ok-state — gør "alt kører" levende uden støj.
    public static let successGlow = SagaShadow(color: SagaColors.success.opacity(0.7), radius: 4, x: 0, y: 0)

    /// Dyb panel-skygge til Liquid Glass-paneler (afstand fra desktop).
    public static let glassDepth = SagaShadow(color: .black.opacity(0.5), radius: 22, x: 0, y: 10)
}

/// Aurora-glow: to bløde radial-gradienter (accent-blå øverst-venstre, violet
/// nederst-højre) der lægges BAG et glas-panel. Giver glasset noget at
/// refraktere så blur-effekten bliver synlig selv mod mørk desktop.
public struct AuroraGlowBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            RadialGradient(
                colors: [SagaColors.accent.opacity(0.16), .clear],
                center: .init(x: 0.28, y: 0.18),
                startRadius: 0,
                endRadius: 260
            )
            RadialGradient(
                colors: [SagaColors.auroraViolet.opacity(0.13), .clear],
                center: .init(x: 0.75, y: 0.80),
                startRadius: 0,
                endRadius: 240
            )
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Liquid Glass Pro-panel: .ultraThinMaterial + mørk blålig tint +
    /// specular border (lysere top-kant) + dyb skygge. Design B's
    /// signatur-stack — brug på menubar-popover, HUD-agtige paneler og
    /// andre svævende flader.
    public func liquidGlassPanel(cornerRadius: CGFloat = SagaRadii.large) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(SagaColors.glassPanelTint)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(SagaColors.specularBorder, lineWidth: 1)
                )
                .sagaShadow(.glassDepth)
        )
    }
}

extension View {
    /// Anvend en `SagaShadow` på et view.
    public func sagaShadow(_ shadow: SagaShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }

    /// Vis pointing-hand-cursor ved hover. Bruger `NSCursor.set()` frem for
    /// push()/pop() — push/pop-stakken kan komme ud af balance ved hurtige
    /// mouse-moves over flere hover-områder, hvorefter cursoren hænger fast.
    /// set() er idempotent og kræver ingen balancering.
    public func pointingHandOnHover() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

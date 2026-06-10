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

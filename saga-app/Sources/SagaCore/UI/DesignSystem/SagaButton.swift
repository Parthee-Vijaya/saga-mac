import SwiftUI

/// Saga's button-stile inspireret af Superwhisper: store rundede full-width
/// CTAs i wizard + sheets, secondary til less-prominent actions, ghost til
/// "Spring over"-style links.
///
/// Brug via `.buttonStyle(SagaButtonStyle.primary)` etc.
public struct SagaButtonStyle: ButtonStyle {
    public enum Variant {
        case primary
        case secondary
        case ghost
        case destructive
    }

    public let variant: Variant
    public let fullWidth: Bool

    public init(variant: Variant, fullWidth: Bool = true) {
        self.variant = variant
        self.fullWidth = fullWidth
    }

    public static let primary = SagaButtonStyle(variant: .primary)
    public static let secondary = SagaButtonStyle(variant: .secondary)
    public static let ghost = SagaButtonStyle(variant: .ghost)
    public static let destructive = SagaButtonStyle(variant: .destructive)

    public static let primaryCompact = SagaButtonStyle(variant: .primary, fullWidth: false)
    public static let secondaryCompact = SagaButtonStyle(variant: .secondary, fullWidth: false)

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SagaTypography.bodyEmphasis)
            .foregroundColor(foreground(pressed: configuration.isPressed))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 44)
            .padding(.horizontal, fullWidth ? 0 : SagaSpacing.lg)
            .background(background(pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: SagaRadii.large)
                    .strokeBorder(borderColor(pressed: configuration.isPressed), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SagaRadii.large))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch variant {
        case .primary:
            SagaColors.accent
                .brightness(pressed ? -0.05 : 0)
        case .secondary:
            SagaColors.surfaceElevated
                .brightness(pressed ? 0.04 : 0)
        case .ghost:
            Color.clear
        case .destructive:
            SagaColors.danger.opacity(0.15)
        }
    }

    private func foreground(pressed: Bool) -> Color {
        switch variant {
        case .primary:
            return Color.black.opacity(0.9)
        case .secondary:
            return SagaColors.textPrimary
        case .ghost:
            return SagaColors.textSecondary
        case .destructive:
            return SagaColors.danger
        }
    }

    private func borderColor(pressed: Bool) -> Color {
        switch variant {
        case .primary:
            return Color.clear
        case .secondary:
            return SagaColors.border
        case .ghost:
            return Color.clear
        case .destructive:
            return SagaColors.danger.opacity(0.3)
        }
    }
}

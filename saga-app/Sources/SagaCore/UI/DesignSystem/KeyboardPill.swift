import SwiftUI

/// Inline keyboard-shortcut hint — pille-formet rounded-rectangle med
/// monospace font, brugt i HUD'er og overlays til at vise hvilke keys
/// der gør hvad.
///
/// Eksempler:
/// - `KeyboardPill(keys: ["⌥"], label: "Stop")`        → "[⌥] Stop"
/// - `KeyboardPill(keys: ["⇧", "⌥"], label: "Edit")`   → "[⇧+⌥] Edit"
/// - `KeyboardPill(keys: ["esc"], label: "Cancel")`    → "[esc] Cancel"
public struct KeyboardPill: View {
    public let keys: [String]
    public let label: String?

    public init(keys: [String], label: String? = nil) {
        self.keys = keys
        self.label = label
    }

    public var body: some View {
        HStack(spacing: SagaSpacing.xs) {
            ForEach(Array(keys.enumerated()), id: \.offset) { idx, key in
                if idx > 0 {
                    Text("+")
                        .font(SagaTypography.mono)
                        .foregroundColor(SagaColors.textTertiary)
                }
                Text(key)
                    .font(SagaTypography.mono)
                    .foregroundColor(SagaColors.textPrimary)
                    .padding(.horizontal, SagaSpacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: SagaRadii.small)
                            .fill(SagaColors.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: SagaRadii.small)
                                    .strokeBorder(SagaColors.border, lineWidth: 1)
                            )
                    )
            }
            if let label {
                Text(label)
                    .font(SagaTypography.caption)
                    .foregroundColor(SagaColors.textSecondary)
                    .padding(.leading, 2)
            }
        }
    }
}

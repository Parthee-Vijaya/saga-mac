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
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(SagaColors.textTertiary)
                }
                Text(key)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(SagaColors.textPrimary.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: SagaRadii.small)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: SagaRadii.small)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                            )
                    )
            }
            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(SagaColors.textSecondary)
                    .padding(.leading, 2)
            }
        }
    }
}

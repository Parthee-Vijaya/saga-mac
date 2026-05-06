import SwiftUI

/// Tynd progress-bar til top af wizard-screens. 3pt højde, accent-fyldt
/// fraktion baseret på `currentStep / totalSteps`. Animeret med spring
/// ved step-skift.
public struct WizardProgressBar: View {
    public let currentStep: Int
    public let totalSteps: Int

    public init(currentStep: Int, totalSteps: Int) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
    }

    private var fraction: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(min(currentStep + 1, totalSteps)) / Double(totalSteps)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(SagaColors.surfaceElevated)

                // Filled portion (accent gradient)
                Capsule()
                    .fill(SagaColors.accentGradient)
                    .frame(width: geo.size.width * fraction)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: fraction)
            }
        }
        .frame(height: 3)
    }
}

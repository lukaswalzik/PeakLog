import SwiftUI

enum AppTheme {
    static let cardCornerRadius: CGFloat = 16
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.11, green: 0.36, blue: 0.92),
            Color(red: 0.25, green: 0.21, blue: 0.82)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct StrongCardModifier: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func strongCard(padding: CGFloat = 14) -> some View {
        modifier(StrongCardModifier(padding: padding))
    }
}

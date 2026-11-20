import SwiftUI

/// Refined brand palette accents for Titiz controls.
enum TitizBrandColors {
    /// Broken burgundy (`#702D38`) brand accent requested for primary mode controls.
    static let burgundy = Color(red: 112.0 / 255.0, green: 45.0 / 255.0, blue: 56.0 / 255.0)
    /// Slightly lifted burgundy (`#8E3B49`) for crisp hairline strokes and icon contrast on dark surfaces.
    static let burgundyHighlight = Color(red: 142.0 / 255.0, green: 59.0 / 255.0, blue: 73.0 / 255.0)
    /// Soft translucent burgundy surface for unselected mode pills.
    static let burgundyTint = Color(red: 112.0 / 255.0, green: 45.0 / 255.0, blue: 56.0 / 255.0).opacity(0.24)
}

/// Groups interactive Liquid Glass controls on macOS 26+ so adjacent shapes blend authentically,
/// falling back cleanly on macOS 14–15 or when Reduce Transparency is enabled.
struct TitizGlassGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

private struct TitizGlassPillModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: Capsule()
                )
        } else if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.75))
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 0.5))
        }
    }
}

private struct TitizSurfaceCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color(nsColor: .textBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.75))
        }
    }
}

extension View {
    func titizGlassPill(interactive: Bool = false) -> some View {
        modifier(TitizGlassPillModifier(interactive: interactive))
    }

    func titizSurfaceCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(TitizSurfaceCardModifier(cornerRadius: cornerRadius))
    }
}

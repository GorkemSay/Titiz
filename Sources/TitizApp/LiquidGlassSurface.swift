import SwiftUI

/// Refined brand palette accents for Titiz controls.
enum TitizBrandColors {
    /// Broken burgundy (`#702D38`) brand accent requested for primary mode controls.
    static let burgundy = Color(red: 112.0 / 255.0, green: 45.0 / 255.0, blue: 56.0 / 255.0)
    /// Top tonal stop (`#803542`) used in vertical icon surfaces.
    static let burgundyTop = Color(red: 128.0 / 255.0, green: 53.0 / 255.0, blue: 66.0 / 255.0)
    /// Bottom tonal stop (`#58212B`) used in vertical icon surfaces.
    static let burgundyDeep = Color(red: 88.0 / 255.0, green: 33.0 / 255.0, blue: 43.0 / 255.0)
    /// Slightly lifted burgundy (`#8E3B49`) for crisp hairline strokes and icon contrast on dark surfaces.
    static let burgundyHighlight = Color(red: 142.0 / 255.0, green: 59.0 / 255.0, blue: 73.0 / 255.0)
    /// Soft translucent burgundy surface for unselected mode pills.
    static let burgundyTint = Color(red: 112.0 / 255.0, green: 45.0 / 255.0, blue: 56.0 / 255.0).opacity(0.24)
    /// Broken marble white (`#EFEAE1`) matching the custom app icon glyph.
    static let marbleWhite = Color(red: 239.0 / 255.0, green: 234.0 / 255.0, blue: 225.0 / 255.0)
    /// Highlighted marble white (`#F7F3EC`) for top inner bezel strokes and bright glyph sheen.
    static let marbleWhiteHighlight = Color(red: 247.0 / 255.0, green: 243.0 / 255.0, blue: 236.0 / 255.0)
}

/// Vector macOS squircle brand badge matching the bundled `AppIcon.icns` (`#702D38` tile + Ionic marble column `T`).
struct TitizLogoBadge: View {
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            TitizBrandColors.burgundyTop,
                            TitizBrandColors.burgundy,
                            TitizBrandColors.burgundyDeep
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                TitizBrandColors.marbleWhiteHighlight.opacity(0.26),
                                Color.black.opacity(0.22)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                )

            Canvas { context, canvasSize in
                let side = min(canvasSize.width, canvasSize.height)
                let masterScale = side / 824.0
                // Map bottom-up 1024x1024 master column coordinates (100...924 tile) directly into SwiftUI top-left space.
                context.translateBy(x: 0, y: side)
                context.scaleBy(x: masterScale, y: -masterScale)
                context.translateBy(x: -100, y: -100)

                let silhouette = Self.ionicColumnSilhouette()
                let marbleBottom = Color(red: 223.0 / 255.0, green: 215.0 / 255.0, blue: 202.0 / 255.0)
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: Color.black.opacity(0.32), radius: 1.0, x: 0, y: 0.8))
                    layer.fill(
                        silhouette,
                        with: .linearGradient(
                            Gradient(colors: [
                                TitizBrandColors.marbleWhiteHighlight,
                                TitizBrandColors.marbleWhite,
                                marbleBottom
                            ]),
                            startPoint: CGPoint(x: 512, y: 760),
                            endPoint: CGPoint(x: 512, y: 260)
                        ),
                        style: FillStyle(eoFill: false)
                    )
                }

                let carvedInk = Color(red: 104.0 / 255.0, green: 38.0 / 255.0, blue: 49.0 / 255.0)

                // Twin inward-curling Ionic spiral grooves + central eyes sized clearly for small UI scales.
                for mirrored in [false, true] {
                    context.fill(Self.voluteSpiralPath(mirrored: mirrored), with: .color(carvedInk.opacity(0.84)))
                    let cx: CGFloat = mirrored ? (1024 - 326) : 326
                    let eyeRect = CGRect(x: cx - 12, y: 672 - 12, width: 24, height: 24)
                    context.fill(Path(ellipseIn: eyeRect), with: .color(carvedInk.opacity(0.84)))
                }

                // Subtle 3 vertical flutes along shaft for legible miniature column texture
                let fluteCenters: [CGFloat] = [512 - 36, 512, 512 + 36]
                for fx in fluteCenters {
                    let rect = CGRect(x: fx - 9, y: 344, width: 18, height: 250)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 9),
                        with: .color(carvedInk.opacity(0.28))
                    )
                }
            }
            .clipShape(shape)
        }
        .frame(width: size, height: size)
    }

    private static func ionicColumnSilhouette() -> Path {
        let path = CGMutablePath()

        path.move(to: CGPoint(x: 438, y: 322))
        path.addLine(to: CGPoint(x: 586, y: 322))
        path.addCurve(to: CGPoint(x: 576, y: 616), control1: CGPoint(x: 586, y: 420), control2: CGPoint(x: 580, y: 530))
        path.addCurve(to: CGPoint(x: 698, y: 604), control1: CGPoint(x: 592, y: 644), control2: CGPoint(x: 642, y: 610))
        path.addLine(to: CGPoint(x: 698, y: 740))
        path.addLine(to: CGPoint(x: 326, y: 740))
        path.addLine(to: CGPoint(x: 326, y: 604))
        path.addCurve(to: CGPoint(x: 448, y: 616), control1: CGPoint(x: 382, y: 610), control2: CGPoint(x: 432, y: 644))
        path.addCurve(to: CGPoint(x: 438, y: 322), control1: CGPoint(x: 444, y: 530), control2: CGPoint(x: 438, y: 420))
        path.closeSubpath()

        let voluteR: CGFloat = 68
        path.addEllipse(in: CGRect(x: 326 - voluteR, y: 672 - voluteR, width: voluteR * 2, height: voluteR * 2))
        path.addEllipse(in: CGRect(x: 698 - voluteR, y: 672 - voluteR, width: voluteR * 2, height: voluteR * 2))
        path.addRoundedRect(in: CGRect(x: 324, y: 738, width: 376, height: 22), cornerWidth: 7, cornerHeight: 7)
        path.addRoundedRect(in: CGRect(x: 432, y: 612, width: 160, height: 22), cornerWidth: 11, cornerHeight: 11)
        path.addRoundedRect(in: CGRect(x: 424, y: 304, width: 176, height: 22), cornerWidth: 11, cornerHeight: 11)
        path.addRoundedRect(in: CGRect(x: 434, y: 284, width: 156, height: 22), cornerWidth: 7, cornerHeight: 7)
        path.addRoundedRect(in: CGRect(x: 396, y: 260, width: 232, height: 28), cornerWidth: 7, cornerHeight: 7)

        return Path(path)
    }

    private static func voluteSpiralPath(mirrored: Bool) -> Path {
        let center = CGPoint(x: 326, y: 672)
        var samples: [(point: CGPoint, halfWidth: CGFloat)] = []

        for i in 0..<12 {
            let t = CGFloat(i) / 12.0
            samples.append((CGPoint(x: 512 - t * (512 - 328), y: 724), 7.5))
        }

        let steps = 84
        let startAngle = CGFloat.pi * 0.5
        let totalSweep = CGFloat.pi * 2.0 * 1.65
        let rStart: CGFloat = 50.0
        let rEnd: CGFloat = 14.0

        for i in 0...steps {
            let u = CGFloat(i) / CGFloat(steps)
            let angle = startAngle + u * totalSweep
            let r = rStart * pow(rEnd / rStart, pow(u, 0.96))
            let pt = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            samples.append((pt, 7.5 - u * 3.0))
        }

        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []
        for idx in samples.indices {
            let p = samples[idx].point
            let prev = samples[max(0, idx - 1)].point
            let next = samples[min(samples.count - 1, idx + 1)].point
            let dx = next.x - prev.x
            let dy = next.y - prev.y
            let len = max(0.0001, hypot(dx, dy))
            let nx = -dy / len
            let ny = dx / len
            let w = samples[idx].halfWidth
            leftEdge.append(CGPoint(x: p.x + nx * w, y: p.y + ny * w))
            rightEdge.append(CGPoint(x: p.x - nx * w, y: p.y - ny * w))
        }

        func mapPoint(_ p: CGPoint) -> CGPoint {
            mirrored ? CGPoint(x: 1024 - p.x, y: p.y) : p
        }

        var out = Path()
        if let first = leftEdge.first {
            out.move(to: mapPoint(first))
            for p in leftEdge.dropFirst() { out.addLine(to: mapPoint(p)) }
            for p in rightEdge.reversed() { out.addLine(to: mapPoint(p)) }
            out.closeSubpath()
        }
        return out
    }
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

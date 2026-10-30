import SwiftUI

/// Connection roles use the system's vivid hues on dark backgrounds. In light mode
/// slightly deeper variants keep icons, wires and small labels readable on white.
enum MapPalette {
    static let data = adaptive(.systemTeal, light: NSColor(srgbRed: 0.0, green: 0.50, blue: 0.60, alpha: 1))
    // Purple, not red: red reads as an error state on an otherwise healthy connection.
    static let display = adaptive(.systemPurple, light: NSColor(srgbRed: 0.58, green: 0.26, blue: 0.80, alpha: 1))
    static let incoming = adaptive(.systemGreen, light: NSColor(srgbRed: 0.10, green: 0.55, blue: 0.24, alpha: 1))
    static let outgoing = adaptive(.systemOrange, light: NSColor(srgbRed: 0.78, green: 0.36, blue: 0.0, alpha: 1))
    /// Vivid system hues for graphics (wires, icons, tiles, bars), adapting to light and dark.
    /// Graphics need less contrast than text, so they stay saturated on a white canvas;
    /// colored text uses the deeper variants above.
    enum Graphic {
        static let data = Color(nsColor: .systemTeal)
        static let display = Color(nsColor: .systemPurple)
        static let incoming = Color(nsColor: .systemGreen)
        static let outgoing = Color(nsColor: .systemOrange)
    }
    /// The map canvas: the standard window background, so cards and glass sit on a familiar surface.
    static let canvas = Color(nsColor: .windowBackgroundColor)
    /// Cards are raised above the canvas: white in light mode, a lighter gray in dark mode.
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.075) : NSColor.white
    })
    private static func adaptive(_ dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

enum MapPowerStyle {
    static let incoming = MapPalette.incoming
    static let outgoing = MapPalette.outgoing
}

struct MapPowerBadge: View {
    var outgoing = false
    var detail: String? = nil
    var scale: CGFloat = 1
    var body: some View {
        let color = outgoing ? MapPowerStyle.outgoing : MapPowerStyle.incoming
        let text = (outgoing ? "Power out" : "Power in") + (detail.map { " · " + $0 } ?? "")
        Text(text)
            .font(.system(size: 11 * scale, weight: .medium)).monospacedDigit()
            .foregroundStyle(color).padding(.horizontal, 7 * scale).padding(.vertical, 3 * scale)
            .background(color.opacity(0.08), in: Capsule()).lineLimit(1)
    }
}

struct MapConnectionAppearance {
    var active = false
    var display = false
    var power = false
    var powerOutgoing = false
    var data = false
    var colors: [Color] {
        var result: [Color] = []
        if display { result.append(MapPalette.display) }
        if power { result.append(powerOutgoing ? MapPowerStyle.outgoing : MapPowerStyle.incoming) }
        if data { result.append(MapPalette.data) }
        return result.isEmpty && active ? [MapPalette.data] : result
    }
    var color: Color? { colors.first }
    var secondaryColor: Color? { colors.dropFirst().first }
}

/// Shared role indicators for device and port cards. Power is only host-port evidence.
struct MapFunctionIcons: View {
    var appearance: MapConnectionAppearance
    var scale: CGFloat = 1
    var body: some View {
        HStack(spacing: 6 * scale) {
            if appearance.data { Image(systemName: "arrow.left.arrow.right").foregroundStyle(MapPalette.Graphic.data).accessibilityLabel("Data") }
            if appearance.display { Image(systemName: "display").foregroundStyle(MapPalette.Graphic.display).accessibilityLabel("Display") }
            if appearance.power {
                Image(systemName: appearance.powerOutgoing ? "arrow.up" : "arrow.down")
                    .foregroundStyle(appearance.powerOutgoing ? MapPalette.Graphic.outgoing : MapPalette.Graphic.incoming)
                    .accessibilityLabel(appearance.powerOutgoing ? "Power out" : "Power in")
            }
        }.font(.system(size: 11 * scale, weight: .medium)).allowsHitTesting(false)
    }
}

/// Cards are content, not chrome: solid, quiet surfaces below the Liquid Glass control layer.
/// Connection roles are carried by the card's icons and wires, so the edge stays neutral and
/// only selection draws an accent ring.
struct MapCardSurface: ViewModifier {
    var selected = false
    var subdued = false
    var cornerRadius: CGFloat = 14
    var scale: CGFloat = 1
    var appearance = MapConnectionAppearance()
    var emphasized = true
    var select: (() -> Void)?
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @ViewState private var hovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
        let edge = Color(nsColor: .separatorColor)
        content
            .background {
                // An empty port is a quiet tag; a connection is a raised card.
                shape.fill(subdued ? Color.primary.opacity(hovered ? 0.08 : 0.05) : MapPalette.card)
                    .contentShape(shape).onTapGesture { select?() }
            }
            .overlay {
                if selected {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2.5).allowsHitTesting(false)
                } else if !subdued || contrast == .increased {
                    shape.strokeBorder(contrast == .increased || hovered ? Color.primary.opacity(0.3) : edge, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(subdued || colorScheme == .dark ? 0 : hovered ? 0.12 : 0.07), radius: hovered ? 6 : 3, y: 1)
            .opacity(emphasized ? 1 : 0.45)
            .onHover { hovered = $0 }
    }
}

/// The canvas: the window background with a quiet dot grid that pans and zooms with the map,
/// as in Freeform. It gives the floating glass controls real content to refract.
struct MapContentBackground: View {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var body: some View {
        Canvas { context, size in
            var spacing = 24 * scale
            while spacing < 12 { spacing *= 2 }  // keep the grid calm when zoomed far out
            let origin = CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
            let startX = origin.x - (origin.x / spacing).rounded(.down) * spacing
            let startY = origin.y - (origin.y / spacing).rounded(.down) * spacing
            var dots = Path()
            var y = startY
            while y < size.height {
                var x = startX
                while x < size.width { dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)); x += spacing }
                y += spacing
            }
            context.fill(dots, with: .color(Color(nsColor: .tertiaryLabelColor).opacity(0.55)))
        }
        .background(MapPalette.canvas)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Floating map controls are the one custom glass surface. The system adapts glass for
/// Reduce Transparency and Increase Contrast, so it is never removed manually.
struct MapControlSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: .capsule)
    }
}

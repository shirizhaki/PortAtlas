import SwiftUI

/// Preserve each connection role while giving small labels sufficient contrast
/// on light content surfaces. AppKit resolves the colors for the active appearance.
enum MapPalette {
    static let data = adaptive(.systemTeal, light: NSColor(srgbRed: 0.0, green: 0.42, blue: 0.50, alpha: 1))
    static let display = adaptive(.systemRed, light: NSColor(srgbRed: 0.80, green: 0.12, blue: 0.16, alpha: 1))
    static let incoming = adaptive(.systemGreen, light: NSColor(srgbRed: 0.0, green: 0.46, blue: 0.22, alpha: 1))
    static let outgoing = adaptive(.systemOrange, light: NSColor(srgbRed: 0.71, green: 0.285, blue: 0.0, alpha: 1))
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
        let text = (outgoing ? "Power out" : "Power in") + (scale >= 0.55 ? detail.map { " · " + $0 } ?? "" : "")
        Text(text)
            .font(.system(size: 11 * max(0.85, scale), weight: .medium)).monospacedDigit()
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
            if scale >= 0.55 {
                if appearance.data { Image(systemName: "arrow.left.arrow.right").foregroundStyle(MapPalette.data).accessibilityLabel("Data") }
                if appearance.display { Image(systemName: "display").foregroundStyle(MapPalette.display).accessibilityLabel("Display") }
                if appearance.power {
                    Image(systemName: appearance.powerOutgoing ? "arrow.up" : "arrow.down")
                        .foregroundStyle(appearance.powerOutgoing ? MapPowerStyle.outgoing : MapPowerStyle.incoming)
                        .accessibilityLabel(appearance.powerOutgoing ? "Power out" : "Power in")
                }
            }
        }.font(.system(size: 11 * max(0.85, scale), weight: .medium)).allowsHitTesting(false)
    }
}

/// Frosted content surfaces sit below the Liquid Glass control layer.
struct MapCardSurface: ViewModifier {
    var selected = false
    var subdued = false
    var cornerRadius: CGFloat = 16
    var scale: CGFloat = 1
    var appearance = MapConnectionAppearance()
    var emphasized = true
    var select: (() -> Void)?
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewState private var hovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
        content
            .background {
                ZStack {
                    if reduceTransparency || contrast == .increased {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        shape.fill(.regularMaterial)
                        shape.fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? (subdued ? 0.12 : 0.24) : (subdued ? 0.30 : 0.45)))
                        shape.strokeBorder(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.16 : 0.20), .white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                    }
                }.contentShape(shape).onTapGesture { select?() }
            }
            .overlay {
                shape.strokeBorder(appearance.color?.opacity(selected ? 1 : hovered ? 0.95 : emphasized ? 0.85 : 0.45) ?? (selected ? Color.accentColor : Color.primary.opacity(contrast == .increased ? 0.35 : hovered ? 0.25 : colorScheme == .light ? 0.18 : 0.08)), lineWidth: selected ? 2.5 : appearance.color != nil ? 1.5 : 1)
                    .allowsHitTesting(false)
                ForEach(Array(appearance.colors.dropFirst().enumerated()), id: \.offset) { index, color in
                    shape.inset(by: CGFloat(index + 1) * max(6 * scale, 3)).strokeBorder(color.opacity(selected ? 1 : emphasized ? 0.85 : 0.45), lineWidth: 1.5).allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(subdued ? 0.025 : hovered ? 0.10 : 0.065), radius: 8 * scale, y: 3 * scale)
            .onHover { hovered = $0 }
    }
}

/// Semantic AppKit materials allow the canvas and inspector to blend with the
/// desktop. These are content backgrounds, not additional Liquid Glass controls.
struct MapContentBackground: View {
    var inspector = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                Color(nsColor: inspector ? .controlBackgroundColor : .windowBackgroundColor)
            } else {
                DesktopMaterial(material: inspector ? .sidebar : .underWindowBackground)
                    .overlay(Color(nsColor: inspector ? .controlBackgroundColor : .windowBackgroundColor).opacity(inspector ? 0.36 : 0.18))
                    .overlay(inspector || colorScheme == .dark ? Color.clear : Color.black.opacity(0.035))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct DesktopMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.material = material
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

struct MapControlSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.15)))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
        }
    }
}

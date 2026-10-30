import SwiftUI
import PortAtlasCore

/// Top-down product views of each kind of Mac, drawn in a 280 × 250 design box.
/// The map is a plan view, so every Mac is seen from above with its front at the bottom.
enum MacArtworkGeometry {
    static let size = CGSize(width: 280, height: 250)

    /// The enclosure edge that ports sit on.
    static func body(_ product: MacProduct) -> CGRect {
        switch product {
        case .macBook: return CGRect(x: 10, y: 54, width: 260, height: 188)
        case .macMini: return CGRect(x: 50, y: 36, width: 180, height: 180)
        case .macStudio: return CGRect(x: 36, y: 22, width: 208, height: 208)
        case .macPro: return CGRect(x: 76, y: 8, width: 128, height: 234)
        case .iMac: return CGRect(x: 8, y: 170, width: 264, height: 14)
        case .desktop: return CGRect(x: 40, y: 30, width: 200, height: 190)
        }
    }
    static func cornerRadius(_ product: MacProduct) -> CGFloat {
        switch product {
        case .macBook: return 18
        case .macMini: return 36
        case .macStudio: return 32
        case .macPro: return 14
        case .iMac: return 6
        case .desktop: return 28
        }
    }

    /// Where a socket meets the enclosure edge.
    static func socket(product: MacProduct, side: PortSide, index: Int, count: Int, magSafe: Bool) -> CGPoint {
        let body = body(product)
        let fraction = CGFloat(index + 1) / CGFloat(max(1, count) + 1)
        switch side {
        case .left, .right:
            let y: CGFloat
            if product == .macBook {
                // Laptop side ports cluster toward the hinge, MagSafe nearest it.
                let spacing = min(22, (body.height * 0.5 - 36) / CGFloat(max(1, count - 1)))
                y = body.minY + (magSafe ? 16 : 38 + CGFloat(index) * spacing)
            } else {
                y = body.minY + body.height * (0.2 + 0.6 * fraction)
            }
            return CGPoint(x: side == .left ? body.minX : body.maxX, y: y)
        case .back, .front:
            // An iMac's ports are on the back of the display, to the right of its stand.
            let span: ClosedRange<CGFloat> = product == .iMac
                ? 194...258 : (body.minX + body.width * 0.2)...(body.maxX - body.width * 0.2)
            let x = span.lowerBound + (span.upperBound - span.lowerBound) * fraction
            return CGPoint(x: x, y: side == .back ? body.minY : body.maxY)
        }
    }
}

struct MacArtwork: View {
    let product: MacProduct
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / MacArtworkGeometry.size.width, size.height / MacArtworkGeometry.size.height)
            context.translateBy(x: (size.width - MacArtworkGeometry.size.width * unit) / 2,
                                y: (size.height - MacArtworkGeometry.size.height * unit) / 2)
            context.scaleBy(x: unit, y: unit)
            var painter = MacPainter(context: context, dark: context.environment.colorScheme == .dark)
            switch product {
            case .macBook: painter.macBook()
            case .macMini, .macStudio, .desktop: painter.box(product)
            case .macPro: painter.macPro()
            case .iMac: painter.iMac()
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }
    private var accessibilityLabel: String {
        switch product {
        case .macBook: return "MacBook seen from above, display at the top"
        case .macMini: return "Mac mini seen from above, front at the bottom"
        case .macStudio: return "Mac Studio seen from above, front at the bottom"
        case .macPro: return "Mac Pro seen from above, front at the bottom"
        case .iMac: return "iMac seen from above, display at the bottom"
        case .desktop: return "Mac seen from above, front at the bottom"
        }
    }
}

/// Shared materials: anodized aluminum, black glass and keys, tuned for each appearance.
private struct MacPainter {
    var context: GraphicsContext
    let dark: Bool

    private func rounded(_ rect: CGRect, _ radius: CGFloat) -> Path {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }
    private func linear(_ colors: [Color], _ from: CGPoint, _ to: CGPoint) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: from, endPoint: to)
    }
    private var aluminumTop: Color { Color(white: dark ? 0.80 : 0.975) }
    private var aluminumBottom: Color { Color(white: dark ? 0.60 : 0.86) }

    /// An aluminum slab with a soft shadow, a bright upper edge and a hairline outline.
    private func aluminum(_ shape: Path, in rect: CGRect) {
        var shadow = context
        shadow.addFilter(.shadow(color: .black.opacity(dark ? 0.55 : 0.16), radius: 14, x: 0, y: 8))
        shadow.fill(shape, with: .color(aluminumBottom))
        context.fill(shape, with: linear([aluminumTop, aluminumBottom], CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY)))
        // A broad, soft sheen from the upper left, as from a window light.
        var sheen = context
        sheen.clip(to: shape)
        sheen.fill(shape, with: .radialGradient(Gradient(colors: [.white.opacity(dark ? 0.16 : 0.5), .clear]),
                                                center: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.25),
                                                startRadius: 0, endRadius: max(rect.width, rect.height) * 0.8))
        context.stroke(shape, with: .color(.black.opacity(dark ? 0.45 : 0.18)), lineWidth: 0.7)
    }
    private func keycap(_ rect: CGRect) {
        let shape = rounded(rect, 2.2)
        context.fill(shape, with: linear([Color(white: 0.22), Color(white: 0.13)], CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY)))
        context.stroke(rounded(rect.insetBy(dx: 0.3, dy: 0.3), 2), with: .color(.white.opacity(0.09)), lineWidth: 0.5)
    }

    /// A rounded polygon, for the display, which leans away and so reads as a slight trapezoid.
    private func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        let count = points.count
        path.move(to: CGPoint(x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2))
        for index in 1...count {
            path.addArc(tangent1End: points[index % count], tangent2End: points[(index + 1) % count], radius: radius)
        }
        path.closeSubpath()
        return path
    }
    /// A display outline centered on the design box: top edge, bottom edge and their half widths.
    private func lid(top: CGFloat, bottom: CGFloat, topHalf: CGFloat, bottomHalf: CGFloat, radius: CGFloat) -> Path {
        let mid = MacArtworkGeometry.size.width / 2
        return roundedPolygon([CGPoint(x: mid - topHalf, y: top), CGPoint(x: mid + topHalf, y: top),
                               CGPoint(x: mid + bottomHalf, y: bottom), CGPoint(x: mid - bottomHalf, y: bottom)], radius: radius)
    }

    mutating func macBook() {
        // The open display leans away from the viewer, so its far (top) edge reads slightly wider.
        let rim = lid(top: 2, bottom: 51, topHalf: 131, bottomHalf: 119, radius: 7)
        context.fill(rim, with: linear([Color(white: dark ? 0.70 : 0.86), Color(white: dark ? 0.50 : 0.70)], CGPoint(x: 0, y: 2), CGPoint(x: 0, y: 51)))
        context.stroke(rim, with: .color(.black.opacity(dark ? 0.45 : 0.2)), lineWidth: 0.6)
        context.fill(lid(top: 3.6, bottom: 49.6, topHalf: 129.2, bottomHalf: 117.4, radius: 6), with: .color(Color(white: 0.03)))
        // The screen: a dimmed, abstract wallpaper with the menu bar, under glass.
        let screen = lid(top: 6.8, bottom: 46.6, topHalf: 124.4, bottomHalf: 113, radius: 3)
        var display = context
        display.clip(to: screen)
        display.fill(screen, with: linear([Color(red: 0.05, green: 0.10, blue: 0.30), Color(red: 0.16, green: 0.33, blue: 0.70), Color(red: 0.42, green: 0.66, blue: 0.86)],
                                          CGPoint(x: 20, y: 7), CGPoint(x: 260, y: 47)))
        var blobs = display
        blobs.addFilter(.blur(radius: 9))
        blobs.fill(Path(ellipseIn: CGRect(x: 60, y: 14, width: 120, height: 46)), with: .color(Color(red: 0.55, green: 0.42, blue: 0.95).opacity(0.55)))
        blobs.fill(Path(ellipseIn: CGRect(x: 170, y: -6, width: 110, height: 34)), with: .color(Color(red: 0.55, green: 0.85, blue: 0.95).opacity(0.45)))
        display.fill(Path(CGRect(x: 0, y: 6.8, width: 280, height: 3.4)), with: .color(.white.opacity(0.22)))
        display.fill(screen, with: linear([.white.opacity(0.10), .clear], CGPoint(x: 40, y: 7), CGPoint(x: 120, y: 47)))
        context.fill(Path(roundedRect: CGRect(x: 131, y: 6.4, width: 18, height: 4.4), cornerRadius: 2.2, style: .continuous), with: .color(Color(white: 0.03)))
        // The hinge, seen between the display and the deck.
        context.fill(rounded(CGRect(x: 40, y: 49, width: 200, height: 7), 3.5),
                     with: linear([Color(white: 0.12), Color(white: 0.28)], CGPoint(x: 0, y: 49), CGPoint(x: 0, y: 56)))

        let deck = MacArtworkGeometry.body(.macBook)
        aluminum(rounded(deck, 18), in: deck)
        context.stroke(rounded(deck.insetBy(dx: 1, dy: 1), 17), with: .color(.white.opacity(dark ? 0.25 : 0.9)), lineWidth: 0.8)

        // The keyboard on one grid: every row is 14.5 key units wide, so columns line up.
        let well = CGRect(x: 30, y: 66, width: 220, height: 102)
        context.fill(rounded(well, 8), with: .color(Color(white: 0.07)))
        context.stroke(rounded(well, 8), with: .color(.black.opacity(0.35)), lineWidth: 0.6)
        let inner = well.insetBy(dx: 4, dy: 4)
        let gap: CGFloat = 2.2
        let pitch = (inner.width + gap) / 14.5
        let keyHeight = (inner.height + gap) / 6 - gap
        func row(_ units: [CGFloat], _ index: Int) -> [CGRect] {
            var x = inner.minX, keys: [CGRect] = []
            let y = inner.minY + CGFloat(index) * (keyHeight + gap)
            for width in units {
                keys.append(CGRect(x: x, y: y, width: width * pitch - gap, height: keyHeight)); x += width * pitch
            }
            return keys
        }
        // Escape, twelve function keys and Touch ID; number, tab, caps lock and shift rows.
        let function = row([1.5] + Array(repeating: 1, count: 12) + [1], 0)
        function.forEach(keycap)
        if let touchID = function.last {
            context.stroke(Path(ellipseIn: touchID.insetBy(dx: touchID.width * 0.2, dy: touchID.height * 0.22)), with: .color(.white.opacity(0.14)), lineWidth: 0.6)
        }
        row(Array(repeating: 1, count: 13) + [1.5], 1).forEach(keycap)
        row([1.5] + Array(repeating: 1, count: 12) + [1], 2).forEach(keycap)
        row([1.75] + Array(repeating: 1, count: 11) + [1.75], 3).forEach(keycap)
        row([2.25] + Array(repeating: 1, count: 10) + [2.25], 4).forEach(keycap)
        // fn, control, option, command, space, command, option, then the inverted-T arrows.
        let bottom = row([1, 1, 1, 1.25, 5, 1.25, 1, 1, 1, 1], 5)
        bottom.prefix(7).forEach(keycap)
        let half = (keyHeight - 1.2) / 2
        let arrows = Array(bottom.suffix(3))
        keycap(CGRect(x: arrows[0].minX, y: arrows[0].maxY - half, width: arrows[0].width, height: half))
        keycap(CGRect(x: arrows[1].minX, y: arrows[1].minY, width: arrows[1].width, height: half))
        keycap(CGRect(x: arrows[1].minX, y: arrows[1].maxY - half, width: arrows[1].width, height: half))
        keycap(CGRect(x: arrows[2].minX, y: arrows[2].maxY - half, width: arrows[2].width, height: half))

        // Speaker grilles beside the keyboard.
        var grille = Path()
        for y in stride(from: CGFloat(70), through: 164, by: 3.4) {
            for x in [CGFloat(16.5), 19.9, 23.3, 255.6, 259, 262.4] { grille.addEllipse(in: CGRect(x: x, y: y, width: 1.1, height: 1.1)) }
        }
        context.fill(grille, with: .color(.black.opacity(dark ? 0.55 : 0.32)))

        // Glass trackpad: barely different from the deck, defined by its edge.
        let pad = CGRect(x: 74, y: 178, width: 132, height: 56)
        context.fill(rounded(pad, 7), with: linear([.white.opacity(dark ? 0.07 : 0.35), .black.opacity(dark ? 0.10 : 0.03)], CGPoint(x: pad.minX, y: pad.minY), CGPoint(x: pad.maxX, y: pad.maxY)))
        context.stroke(rounded(pad, 7), with: .color(.black.opacity(dark ? 0.35 : 0.14)), lineWidth: 0.7)
        context.stroke(rounded(pad.insetBy(dx: 0.9, dy: 0.9), 6.2), with: .color(.white.opacity(dark ? 0.12 : 0.7)), lineWidth: 0.5)
        // Lid-opening scoop at the front edge.
        context.fill(rounded(CGRect(x: 116, y: deck.maxY - 3.5, width: 48, height: 2.5), 1.25), with: .color(.black.opacity(dark ? 0.35 : 0.14)))
    }

    /// Mac mini, Mac Studio and other compact desktops: a rounded square seen from above.
    mutating func box(_ product: MacProduct) {
        let body = MacArtworkGeometry.body(product)
        let radius = MacArtworkGeometry.cornerRadius(product)
        aluminum(rounded(body, radius), in: body)
        context.stroke(rounded(body.insetBy(dx: 1, dy: 1), radius - 1), with: .color(.white.opacity(dark ? 0.25 : 0.9)), lineWidth: 0.8)
        // The machined top face sits just inside the rounded edge.
        let face = body.insetBy(dx: 7, dy: 7)
        context.stroke(rounded(face, radius - 6), with: .color(.black.opacity(dark ? 0.18 : 0.06)), lineWidth: 0.8)
        // Front status light.
        let light = CGRect(x: body.maxX - radius - 4, y: body.maxY - 6, width: 2.6, height: 2.6)
        context.fill(Path(ellipseIn: light), with: .color(.white.opacity(dark ? 0.9 : 0.95)))
        context.stroke(Path(ellipseIn: light), with: .color(.black.opacity(0.15)), lineWidth: 0.4)
    }

    mutating func macPro() {
        let body = MacArtworkGeometry.body(.macPro)
        aluminum(rounded(body, 14), in: body)
        // The lattice of the top vents, between the two handles.
        var lattice = Path()
        let area = CGRect(x: body.minX + 14, y: body.minY + 40, width: body.width - 28, height: body.height - 80)
        var row = 0
        for y in stride(from: area.minY, through: area.maxY, by: 6) {
            let offset: CGFloat = row % 2 == 0 ? 0 : 3.5
            for x in stride(from: area.minX + offset, through: area.maxX, by: 7) { lattice.addEllipse(in: CGRect(x: x, y: y, width: 3, height: 3)) }
            row += 1
        }
        context.fill(lattice, with: .color(.black.opacity(dark ? 0.45 : 0.22)))
        // Two stainless handles across the top.
        for y in [body.minY + 12, body.maxY - 26] {
            let handle = CGRect(x: body.minX + 12, y: y, width: body.width - 24, height: 14)
            context.fill(rounded(handle, 7), with: linear([Color(white: dark ? 0.9 : 1), Color(white: dark ? 0.5 : 0.72)], CGPoint(x: 0, y: handle.minY), CGPoint(x: 0, y: handle.maxY)))
            context.stroke(rounded(handle, 7), with: .color(.black.opacity(0.25)), lineWidth: 0.6)
        }
    }

    mutating func iMac() {
        // The stand's foot behind the display, then the display itself seen edge-on from above.
        let foot = CGRect(x: 98, y: 70, width: 84, height: 92)
        aluminum(rounded(foot, 16), in: foot)
        context.fill(rounded(CGRect(x: 124, y: 158, width: 32, height: 14), 3), with: .color(aluminumBottom))
        let display = MacArtworkGeometry.body(.iMac)
        aluminum(rounded(display, 6), in: display)
        context.stroke(rounded(display.insetBy(dx: 1, dy: 1), 5), with: .color(.white.opacity(dark ? 0.25 : 0.9)), lineWidth: 0.6)
        // The glass front of the display.
        context.fill(rounded(CGRect(x: display.minX + 2, y: display.maxY - 2.6, width: display.width - 4, height: 2.6), 1.3), with: .color(Color(white: 0.08)))
    }
}

/// Port openings in the enclosure and the plugs seated in them, drawn where cables meet the Mac.
/// Both are flat, in the map's card style: a plug is a small capsule with the cards' fill,
/// hairline edge and soft shadow, so it reads as part of the diagram rather than a photo.
enum PortDrawing {
    enum Kind { case usbC, magSafe, hdmi, usbA }

    /// Ports and plugs are drawn larger than true scale so they read at a glance.
    private static let emphasis: CGFloat = 1.4
    /// How far a plug reaches out from the enclosure; the cable starts there.
    static func plugLength(_ kind: Kind) -> CGFloat {
        switch kind {
        case .usbC: return 14 * emphasis
        case .magSafe: return 13 * emphasis
        case .hdmi, .usbA: return 15 * emphasis
        }
    }

    /// - Parameter led: The MagSafe plug's light color, when it is supplying power.
    static func draw(_ kind: Kind, at point: CGPoint, side: PortSide, plugged: Bool, led: Color?, scale: CGFloat, context: inout GraphicsContext) {
        let dark = context.environment.colorScheme == .dark
        context.translateBy(x: point.x, y: point.y)
        // Local +x points away from the Mac.
        let angle: Double = side == .left ? 180 : side == .back ? -90 : side == .front ? 90 : 0
        context.rotate(by: .degrees(angle)); context.scaleBy(x: scale * emphasis, y: scale * emphasis)

        // The opening: a flat slot just inside the enclosure edge.
        let slot: CGRect
        switch kind {
        case .usbC: slot = CGRect(x: -2.6, y: -4.2, width: 2.6, height: 8.4)
        case .magSafe: slot = CGRect(x: -2.6, y: -5.4, width: 2.6, height: 10.8)
        case .hdmi, .usbA: slot = CGRect(x: -3, y: -5, width: 3, height: 10)
        }
        let slotRadius: CGFloat = kind == .usbC || kind == .magSafe ? slot.width / 2 : 0.8
        context.fill(Path(roundedRect: slot, cornerRadius: slotRadius, style: .continuous), with: .color(.black.opacity(dark ? 0.6 : 0.5)))
        guard plugged else { return }

        // The plug: one capsule, styled like a map card.
        let body: CGRect, radius: CGFloat
        switch kind {
        case .usbC: body = CGRect(x: -0.8, y: -3.8, width: 14.8, height: 7.6); radius = 3.8
        case .magSafe: body = CGRect(x: -0.8, y: -5, width: 13.8, height: 10); radius = 3.2
        case .hdmi, .usbA: body = CGRect(x: -0.8, y: -4.6, width: 15.8, height: 9.2); radius = 2.6
        }
        let plug = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        var shadow = context
        shadow.addFilter(.shadow(color: .black.opacity(dark ? 0.35 : 0.1), radius: 1.6))
        let fill = dark ? Color(white: 0.27) : .white
        shadow.fill(plug, with: .color(fill))
        context.fill(plug, with: .color(fill))
        context.stroke(plug, with: .color(dark ? .white.opacity(0.14) : Color(nsColor: .separatorColor)), lineWidth: 0.6)
        if let led {
            context.fill(Path(ellipseIn: CGRect(x: 4.8, y: -1.3, width: 2.6, height: 2.6)), with: .color(led))
        }
    }
}

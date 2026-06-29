import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case global      = "Global"
    case geometry    = "Geometry"
    case subdivision = "Subdivision"
    case sprites     = "Sprites"
    case cycles      = "Cycles"
    case layers      = "Layers"
    case lights      = "Lights"
    case rendering   = "Rendering"

    var label: String { rawValue }

    var systemImage: String {
        switch self {
        case .global:      return "globe"
        case .geometry:    return "pentagon"
        case .subdivision: return "square.grid.3x3.fill"
        case .sprites:     return "square.stack.3d.up"   // unused — icon() handles sprites
        case .cycles:      return "arrow.2.circlepath"
        case .layers:      return "square.3.layers.3d"
        case .lights:      return "lightbulb"   // fallback only; icon() overrides
        case .rendering:   return "paintbrush"
        }
    }

    @ViewBuilder
    func icon() -> some View {
        switch self {
        case .sprites:
            RocketSpriteIcon()
                .frame(width: 16, height: 15)
        case .lights:
            TheatreSpotIcon()
                .frame(width: 16, height: 15)
        default:
            Image(systemName: systemImage)
                .font(.system(size: 11))
        }
    }

    var hasListPanel: Bool { true }
}

// MARK: - Theatre spotlight icon for the Lights tab

struct TheatreSpotIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                // Lamp body — circle representing the housing/lens, upper-left area
                p.addEllipse(in: CGRect(
                    x: w * 0.02, y: h * 0.18,
                    width: w * 0.55, height: h * 0.58
                ))
                // Mount arm — diagonal from top of body to upper-right (the truss connection)
                p.move(to:    CGPoint(x: w * 0.32, y: h * 0.18))
                p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.02))
                // Short crossbar at top of arm (the pipe/clamp)
                p.move(to:    CGPoint(x: w * 0.60, y: h * 0.02))
                p.addLine(to: CGPoint(x: w * 0.84, y: h * 0.02))
                // Upper beam ray — from right edge of circle going upper-right
                p.move(to:    CGPoint(x: w * 0.55, y: h * 0.30))
                p.addLine(to: CGPoint(x: w * 0.98, y: h * 0.02))
                // Lower beam ray — from right edge going lower-right
                p.move(to:    CGPoint(x: w * 0.55, y: h * 0.64))
                p.addLine(to: CGPoint(x: w * 0.98, y: h * 0.92))
            }
            .stroke(.primary, style: StrokeStyle(
                lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Rocket icon for the Sprites tab

struct RocketSpriteIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                // Full rocket silhouette — nose → body → fins → nozzle
                Path { path in
                    path.move(to:    CGPoint(x: w * 0.50, y: h * 0.02))  // nose tip
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.30))  // nose right
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.56))  // body right, fin root
                    path.addLine(to: CGPoint(x: w * 0.97, y: h * 0.80))  // right fin tip
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.72))  // right fin inner
                    path.addLine(to: CGPoint(x: w * 0.63, y: h * 0.72))  // nozzle right shoulder
                    path.addLine(to: CGPoint(x: w * 0.63, y: h * 0.90))  // nozzle right bottom
                    path.addLine(to: CGPoint(x: w * 0.37, y: h * 0.90))  // nozzle left bottom
                    path.addLine(to: CGPoint(x: w * 0.37, y: h * 0.72))  // nozzle left shoulder
                    path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.72))  // left fin inner
                    path.addLine(to: CGPoint(x: w * 0.03, y: h * 0.80))  // left fin tip
                    path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.56))  // body left, fin root
                    path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.30))  // nose left
                    path.closeSubpath()
                }
                .fill()

                // Porthole — punched out as a transparent hole
                Path { path in
                    path.addEllipse(in: CGRect(
                        x: w * 0.34, y: h * 0.35,
                        width: w * 0.32, height: h * 0.22
                    ))
                }
                .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .padding(0)
    }
}

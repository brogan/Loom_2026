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
                .frame(width: 16, height: 15)
                .clipped()
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
            ZStack {
                // Filled: vertical stem + circular lamp body
                Path { p in
                    p.addRoundedRect(
                        in: CGRect(x: w * 0.22, y: 0,
                                   width: w * 0.22, height: h * 0.44),
                        cornerSize: CGSize(width: w * 0.11, height: w * 0.11)
                    )
                    p.addEllipse(in: CGRect(
                        x: w * 0.04, y: h * 0.38,
                        width: w * 0.46, height: h * 0.46
                    ))
                }
                .fill(.primary)
                // Stroked: open-faced reflector housing — back wall + two diverging edges
                Path { p in
                    p.move(to:    CGPoint(x: w * 0.52, y: h * 0.30))
                    p.addLine(to: CGPoint(x: w * 0.52, y: h * 0.80))
                    p.move(to:    CGPoint(x: w * 0.52, y: h * 0.30))
                    p.addLine(to: CGPoint(x: w * 0.97, y: h * 0.08))
                    p.move(to:    CGPoint(x: w * 0.52, y: h * 0.80))
                    p.addLine(to: CGPoint(x: w * 0.97, y: h * 0.94))
                }
                .stroke(.primary, style: StrokeStyle(
                    lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
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

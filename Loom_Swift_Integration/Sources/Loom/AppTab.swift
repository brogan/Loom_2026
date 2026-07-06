import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case global      = "Global"
    case geometry    = "Geometry"
    case subdivision = "Subdivision"
    case sprites     = "Sprites"
    case cycles      = "Cycles"
    case layers      = "Layers"
    case lights      = "Lights"
    case audio       = "Audio"
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
        case .audio:       return "waveform"
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

// MARK: - Geometric Lifecycle subtabs (within the Subdivision tab)

enum LifecycleTab: String, CaseIterable {
    case involution  = "Inv"
    case ext         = "Ext"
    case evolution   = "Evo"
    case fulguration = "Ful"
    case dissolution = "Dis"

    var fullName: String {
        switch self {
        case .involution:  return "Involution"
        case .ext:         return "Extension"
        case .evolution:   return "Evolution"
        case .fulguration: return "Fulguration"
        case .dissolution: return "Dissolution"
        }
    }
}

// MARK: - Theatre spotlight icon for the Lights tab

struct TheatreSpotIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                // Closed housing — D-shape: arc swings left (clockwise:true = CCW on
                // screen in SwiftUI's Y-down system), closeSubpath draws the right face.
                p.move(to: CGPoint(x: w * 0.44, y: h * 0.12))
                p.addArc(
                    center:     CGPoint(x: w * 0.44, y: h * 0.50),
                    radius:     h * 0.38,
                    startAngle: .radians(-.pi / 2),
                    endAngle:   .radians(.pi / 2),
                    clockwise:  true
                )
                p.closeSubpath()   // straight line from arc bottom back to arc top

                // 4 beam lines angled ~15° downward (tan 15° ≈ 0.268)
                let dx = w * 0.40
                let dy = dx * 0.268
                for i in 0..<4 {
                    let y0 = h * (0.26 + CGFloat(i) * 0.150)
                    p.move(to:    CGPoint(x: w * 0.57, y: y0))
                    p.addLine(to: CGPoint(x: w * 0.57 + dx, y: y0 + dy))
                }
            }
            // No explicit colour — inherits .foregroundStyle so unselected tabs
            // appear secondary-grey, matching the surrounding SF Symbol icons.
            .stroke(style: StrokeStyle(
                lineWidth: 1.0, lineCap: .round, lineJoin: .round))
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

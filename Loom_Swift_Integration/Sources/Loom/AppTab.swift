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

    var label: String { self == .subdivision ? "Transform" : rawValue }

    /// SF Symbol names — no longer used by `icon()` (every tab now has a custom
    /// hand-designed icon below, sourced from ~/.loom_projects/icons/svgs/,
    /// 2026-07-09), kept here as a record of the previous mapping so it's easy to
    /// revert `icon()` to `Image(systemName: systemImage)` if ever needed.
    var systemImage: String {
        switch self {
        case .global:      return "globe"
        case .geometry:    return "pentagon"
        case .subdivision: return "square.grid.3x3.fill"
        case .sprites:     return "square.stack.3d.up"
        case .cycles:      return "arrow.2.circlepath"
        case .layers:      return "square.3.layers.3d"
        case .lights:      return "lightbulb"
        case .audio:       return "waveform"
        case .rendering:   return "paintbrush"
        }
    }

    @ViewBuilder
    func icon() -> some View {
        switch self {
        case .global:      GlobalTabIcon().frame(width: 16, height: 16)
        case .geometry:    GeometryTabIcon().frame(width: 16, height: 16)
        case .subdivision: TransformTabIcon().frame(width: 16, height: 16)
        case .sprites:     SpriteTabIcon().frame(width: 16, height: 16)
        case .cycles:      CycleTabIcon().frame(width: 16, height: 16)
        case .layers:      LayersTabIcon().frame(width: 16, height: 16)
        case .lights:      LightsTabIcon().frame(width: 16, height: 16)
        case .audio:       SoundTabIcon().frame(width: 16, height: 16)
        case .rendering:   RenderTabIcon().frame(width: 16, height: 16)
        }
    }

    var hasListPanel: Bool { true }
}


// MARK: - Legacy hand-drawn icons (preserved as a record, no longer referenced by
// icon() as of 2026-07-09 — see the custom Tab icon structs further below). Revert
// by pointing icon()'s .lights/.sprites cases back at these two, and the rest back
// at Image(systemName: systemImage).

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

// MARK: - Custom tab icons (2026-07-09)
//
// Hand-designed wireframe icons, one per main tab, sourced as unfilled/stroke-only
// SVG paths from a dedicated "icons" Loom project (~/.loom_projects/icons/svgs/)
// and mechanically converted to SwiftUI Path code: each icon's own path geometry
// was bounding-boxed and independently rescaled per axis (~12% margin) to fill
// the same 0...1 square, since the source SVGs were hand-drawn at inconsistent,
// mostly-landscape aspect ratios that read as flattened/too-wide when preserved —
// squaring them off gives every icon a consistent footprint in the (square)
// tab bar slot, matching how TheatreSpotIcon/RocketSpriteIcon above already draw
// (GeometryReader + fractional coordinates), just generated rather than hand-typed.
// Stroked, not filled, since none of the source shapes were filled.

struct CycleTabIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.2077, y: h * 0.4999))
                p.addCurve(to: CGPoint(x: w * 0.5001, y: h * 0.2077), control1: CGPoint(x: w * 0.2954, y: h * 0.4122), control2: CGPoint(x: w * 0.4124, y: h * 0.2954))
                p.move(to: CGPoint(x: w * 0.5001, y: h * 0.2077))
                p.addCurve(to: CGPoint(x: w * 0.7923, y: h * 0.4999), control1: CGPoint(x: w * 0.5877, y: h * 0.2954), control2: CGPoint(x: w * 0.7046, y: h * 0.4122))
                p.move(to: CGPoint(x: w * 0.7923, y: h * 0.4999))
                p.addCurve(to: CGPoint(x: w * 0.5001, y: h * 0.7923), control1: CGPoint(x: w * 0.7046, y: h * 0.5876), control2: CGPoint(x: w * 0.5877, y: h * 0.7046))
                p.move(to: CGPoint(x: w * 0.5001, y: h * 0.7923))
                p.addCurve(to: CGPoint(x: w * 0.2077, y: h * 0.4999), control1: CGPoint(x: w * 0.4124, y: h * 0.7046), control2: CGPoint(x: w * 0.2954, y: h * 0.5876))
                p.move(to: CGPoint(x: w * 0.1200, y: h * 0.5876))
                p.addCurve(to: CGPoint(x: w * 0.2077, y: h * 0.4999), control1: CGPoint(x: w * 0.1493, y: h * 0.5585), control2: CGPoint(x: w * 0.1785, y: h * 0.5292))
                p.move(to: CGPoint(x: w * 0.2077, y: h * 0.4999))
                p.addCurve(to: CGPoint(x: w * 0.2077, y: h * 0.7046), control1: CGPoint(x: w * 0.2077, y: h * 0.5585), control2: CGPoint(x: w * 0.2077, y: h * 0.6462))
                p.move(to: CGPoint(x: w * 0.8800, y: h * 0.4122))
                p.addCurve(to: CGPoint(x: w * 0.7923, y: h * 0.4999), control1: CGPoint(x: w * 0.8508, y: h * 0.4415), control2: CGPoint(x: w * 0.8216, y: h * 0.4708))
                p.move(to: CGPoint(x: w * 0.7923, y: h * 0.4999))
                p.addCurve(to: CGPoint(x: w * 0.7923, y: h * 0.2954), control1: CGPoint(x: w * 0.7923, y: h * 0.4415), control2: CGPoint(x: w * 0.7923, y: h * 0.3538))
                p.move(to: CGPoint(x: w * 0.5877, y: h * 0.8800))
                p.addCurve(to: CGPoint(x: w * 0.5001, y: h * 0.7923), control1: CGPoint(x: w * 0.5585, y: h * 0.8509), control2: CGPoint(x: w * 0.5293, y: h * 0.8216))
                p.move(to: CGPoint(x: w * 0.5001, y: h * 0.7923))
                p.addCurve(to: CGPoint(x: w * 0.7046, y: h * 0.7923), control1: CGPoint(x: w * 0.5585, y: h * 0.7923), control2: CGPoint(x: w * 0.6462, y: h * 0.7923))
                p.move(to: CGPoint(x: w * 0.4124, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.5001, y: h * 0.2077), control1: CGPoint(x: w * 0.4416, y: h * 0.1491), control2: CGPoint(x: w * 0.4708, y: h * 0.1784))
                p.move(to: CGPoint(x: w * 0.5001, y: h * 0.2077))
                p.addCurve(to: CGPoint(x: w * 0.2954, y: h * 0.2077), control1: CGPoint(x: w * 0.4416, y: h * 0.2077), control2: CGPoint(x: w * 0.3539, y: h * 0.2077))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        }
    }
}

struct GeometryTabIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.1200, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.1200), control1: CGPoint(x: w * 0.3813, y: h * 0.1200), control2: CGPoint(x: w * 0.6187, y: h * 0.1200))
                p.move(to: CGPoint(x: w * 0.8800, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.8800), control1: CGPoint(x: w * 0.8800, y: h * 0.3812), control2: CGPoint(x: w * 0.8800, y: h * 0.6188))
                p.move(to: CGPoint(x: w * 0.8800, y: h * 0.8800))
                p.addCurve(to: CGPoint(x: w * 0.1200, y: h * 0.8800), control1: CGPoint(x: w * 0.6187, y: h * 0.8800), control2: CGPoint(x: w * 0.3813, y: h * 0.8800))
                p.move(to: CGPoint(x: w * 0.1200, y: h * 0.8800))
                p.addCurve(to: CGPoint(x: w * 0.1200, y: h * 0.1200), control1: CGPoint(x: w * 0.1200, y: h * 0.6188), control2: CGPoint(x: w * 0.1200, y: h * 0.3812))
                p.move(to: CGPoint(x: w * 0.2629, y: h * 0.7370))
                p.addCurve(to: CGPoint(x: w * 0.5000, y: h * 0.2630), control1: CGPoint(x: w * 0.3420, y: h * 0.5790), control2: CGPoint(x: w * 0.4210, y: h * 0.4210))
                p.move(to: CGPoint(x: w * 0.5000, y: h * 0.2630))
                p.addCurve(to: CGPoint(x: w * 0.7370, y: h * 0.7370), control1: CGPoint(x: w * 0.5790, y: h * 0.4210), control2: CGPoint(x: w * 0.6580, y: h * 0.5790))
                p.move(to: CGPoint(x: w * 0.7370, y: h * 0.7370))
                p.addCurve(to: CGPoint(x: w * 0.2629, y: h * 0.7370), control1: CGPoint(x: w * 0.5790, y: h * 0.7370), control2: CGPoint(x: w * 0.4210, y: h * 0.7370))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        }
    }
}

struct GlobalTabIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.4993, y: h * 0.8800))
                p.addCurve(to: CGPoint(x: w * 0.8785, y: h * 0.5000), control1: CGPoint(x: w * 0.7086, y: h * 0.8800), control2: CGPoint(x: w * 0.8785, y: h * 0.7099))
                p.addCurve(to: CGPoint(x: w * 0.7231, y: h * 0.4997), control1: CGPoint(x: w * 0.8414, y: h * 0.5000), control2: CGPoint(x: w * 0.7539, y: h * 0.4997))
                p.addCurve(to: CGPoint(x: w * 0.4982, y: h * 0.7216), control1: CGPoint(x: w * 0.7231, y: h * 0.6232), control2: CGPoint(x: w * 0.6215, y: h * 0.7216))
                p.addCurve(to: CGPoint(x: w * 0.4993, y: h * 0.8800), control1: CGPoint(x: w * 0.4982, y: h * 0.7523), control2: CGPoint(x: w * 0.4993, y: h * 0.8430))
                p.closeSubpath()
                p.move(to: CGPoint(x: w * 0.8800, y: h * 0.5000))
                p.addCurve(to: CGPoint(x: w * 0.5008, y: h * 0.1200), control1: CGPoint(x: w * 0.8800, y: h * 0.2901), control2: CGPoint(x: w * 0.7103, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.4998, y: h * 0.2741), control1: CGPoint(x: w * 0.5008, y: h * 0.1572), control2: CGPoint(x: w * 0.4998, y: h * 0.2432))
                p.addCurve(to: CGPoint(x: w * 0.7231, y: h * 0.4997), control1: CGPoint(x: w * 0.6231, y: h * 0.2741), control2: CGPoint(x: w * 0.7231, y: h * 0.3761))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.5000), control1: CGPoint(x: w * 0.7539, y: h * 0.4997), control2: CGPoint(x: w * 0.8431, y: h * 0.5000))
                p.closeSubpath()
                p.move(to: CGPoint(x: w * 0.5003, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.1210, y: h * 0.5000), control1: CGPoint(x: w * 0.2909, y: h * 0.1200), control2: CGPoint(x: w * 0.1210, y: h * 0.2901))
                p.addCurve(to: CGPoint(x: w * 0.2750, y: h * 0.4979), control1: CGPoint(x: w * 0.1581, y: h * 0.5000), control2: CGPoint(x: w * 0.2441, y: h * 0.4979))
                p.addCurve(to: CGPoint(x: w * 0.4998, y: h * 0.2741), control1: CGPoint(x: w * 0.2750, y: h * 0.3743), control2: CGPoint(x: w * 0.3765, y: h * 0.2741))
                p.addCurve(to: CGPoint(x: w * 0.5003, y: h * 0.1200), control1: CGPoint(x: w * 0.4998, y: h * 0.2432), control2: CGPoint(x: w * 0.5003, y: h * 0.1572))
                p.closeSubpath()
                p.move(to: CGPoint(x: w * 0.1200, y: h * 0.5000))
                p.addCurve(to: CGPoint(x: w * 0.4993, y: h * 0.8800), control1: CGPoint(x: w * 0.1200, y: h * 0.7099), control2: CGPoint(x: w * 0.2898, y: h * 0.8800))
                p.addCurve(to: CGPoint(x: w * 0.4982, y: h * 0.7216), control1: CGPoint(x: w * 0.4993, y: h * 0.8430), control2: CGPoint(x: w * 0.4982, y: h * 0.7523))
                p.addCurve(to: CGPoint(x: w * 0.2750, y: h * 0.4979), control1: CGPoint(x: w * 0.3749, y: h * 0.7216), control2: CGPoint(x: w * 0.2750, y: h * 0.6214))
                p.addCurve(to: CGPoint(x: w * 0.1200, y: h * 0.5000), control1: CGPoint(x: w * 0.2441, y: h * 0.4979), control2: CGPoint(x: w * 0.1570, y: h * 0.5000))
                p.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        }
    }
}

struct LayersTabIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.1203, y: h * 0.3294))
                p.addCurve(to: CGPoint(x: w * 0.5408, y: h * 0.1200), control1: CGPoint(x: w * 0.2605, y: h * 0.2596), control2: CGPoint(x: w * 0.4006, y: h * 0.1898))
                p.move(to: CGPoint(x: w * 0.5408, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.8772, y: h * 0.3294), control1: CGPoint(x: w * 0.6529, y: h * 0.1898), control2: CGPoint(x: w * 0.7651, y: h * 0.2596))
                p.move(to: CGPoint(x: w * 0.8772, y: h * 0.3294))
                p.addCurve(to: CGPoint(x: w * 0.4567, y: h * 0.5389), control1: CGPoint(x: w * 0.7370, y: h * 0.3992), control2: CGPoint(x: w * 0.5968, y: h * 0.4691))
                p.move(to: CGPoint(x: w * 0.4567, y: h * 0.5389))
                p.addCurve(to: CGPoint(x: w * 0.1203, y: h * 0.3294), control1: CGPoint(x: w * 0.3446, y: h * 0.4691), control2: CGPoint(x: w * 0.2325, y: h * 0.3992))
                p.move(to: CGPoint(x: w * 0.1231, y: h * 0.4980))
                p.addCurve(to: CGPoint(x: w * 0.5436, y: h * 0.2884), control1: CGPoint(x: w * 0.2633, y: h * 0.4280), control2: CGPoint(x: w * 0.4034, y: h * 0.3582))
                p.move(to: CGPoint(x: w * 0.5436, y: h * 0.2884))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.4980), control1: CGPoint(x: w * 0.6557, y: h * 0.3582), control2: CGPoint(x: w * 0.7679, y: h * 0.4280))
                p.move(to: CGPoint(x: w * 0.8800, y: h * 0.4980))
                p.addCurve(to: CGPoint(x: w * 0.4595, y: h * 0.7074), control1: CGPoint(x: w * 0.7398, y: h * 0.5678), control2: CGPoint(x: w * 0.5996, y: h * 0.6376))
                p.move(to: CGPoint(x: w * 0.4595, y: h * 0.7074))
                p.addCurve(to: CGPoint(x: w * 0.1231, y: h * 0.4980), control1: CGPoint(x: w * 0.3474, y: h * 0.6376), control2: CGPoint(x: w * 0.2353, y: h * 0.5678))
                p.move(to: CGPoint(x: w * 0.1200, y: h * 0.6706))
                p.addCurve(to: CGPoint(x: w * 0.5405, y: h * 0.4611), control1: CGPoint(x: w * 0.2601, y: h * 0.6008), control2: CGPoint(x: w * 0.4003, y: h * 0.5309))
                p.move(to: CGPoint(x: w * 0.5405, y: h * 0.4611))
                p.addCurve(to: CGPoint(x: w * 0.8768, y: h * 0.6706), control1: CGPoint(x: w * 0.6526, y: h * 0.5309), control2: CGPoint(x: w * 0.7647, y: h * 0.6008))
                p.move(to: CGPoint(x: w * 0.8768, y: h * 0.6706))
                p.addCurve(to: CGPoint(x: w * 0.4563, y: h * 0.8800), control1: CGPoint(x: w * 0.7367, y: h * 0.7404), control2: CGPoint(x: w * 0.5965, y: h * 0.8102))
                p.move(to: CGPoint(x: w * 0.4563, y: h * 0.8800))
                p.addCurve(to: CGPoint(x: w * 0.1200, y: h * 0.6706), control1: CGPoint(x: w * 0.3443, y: h * 0.8102), control2: CGPoint(x: w * 0.2321, y: h * 0.7404))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        }
    }
}

struct LightsTabIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.3839, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.1200, y: h * 0.8733), control1: CGPoint(x: w * 0.2959, y: h * 0.3712), control2: CGPoint(x: w * 0.2080, y: h * 0.6221))
                p.move(to: CGPoint(x: w * 0.3839, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.7137, y: h * 0.8733), control1: CGPoint(x: w * 0.4939, y: h * 0.3712), control2: CGPoint(x: w * 0.6038, y: h * 0.6221))
                p.move(to: CGPoint(x: w * 0.5501, y: h * 0.1267))
                p.addCurve(to: CGPoint(x: w * 0.2863, y: h * 0.8800), control1: CGPoint(x: w * 0.4622, y: h * 0.3779), control2: CGPoint(x: w * 0.3742, y: h * 0.6288))
                p.move(to: CGPoint(x: w * 0.5501, y: h * 0.1267))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.8800), control1: CGPoint(x: w * 0.6601, y: h * 0.3779), control2: CGPoint(x: w * 0.7701, y: h * 0.6288))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        }
    }
}

struct RenderTabIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.3979, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.3979, y: h * 0.8800), control1: CGPoint(x: w * 0.3979, y: h * 0.3101), control2: CGPoint(x: w * 0.3979, y: h * 0.6901))
                p.move(to: CGPoint(x: w * 0.5879, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.5879, y: h * 0.8800), control1: CGPoint(x: w * 0.5879, y: h * 0.3101), control2: CGPoint(x: w * 0.5879, y: h * 0.6901))
                p.move(to: CGPoint(x: w * 0.1200, y: h * 0.5948))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.5948), control1: CGPoint(x: w * 0.3100, y: h * 0.5948), control2: CGPoint(x: w * 0.6900, y: h * 0.5948))
                p.move(to: CGPoint(x: w * 0.1200, y: h * 0.4047))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.4047), control1: CGPoint(x: w * 0.3100, y: h * 0.4047), control2: CGPoint(x: w * 0.6900, y: h * 0.4047))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        }
    }
}

struct SoundTabIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.2118, y: h * 0.3972))
                p.addCurve(to: CGPoint(x: w * 0.2118, y: h * 0.6252), control1: CGPoint(x: w * 0.2118, y: h * 0.5113), control2: CGPoint(x: w * 0.2118, y: h * 0.5113))
                p.move(to: CGPoint(x: w * 0.3376, y: h * 0.2516))
                p.addCurve(to: CGPoint(x: w * 0.3376, y: h * 0.7469), control1: CGPoint(x: w * 0.3376, y: h * 0.3755), control2: CGPoint(x: w * 0.3376, y: h * 0.6230))
                p.move(to: CGPoint(x: w * 0.4932, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.4932, y: h * 0.8800), control1: CGPoint(x: w * 0.4932, y: h * 0.4051), control2: CGPoint(x: w * 0.4932, y: h * 0.5951))
                p.move(to: CGPoint(x: w * 0.1205, y: h * 0.4800))
                p.addCurve(to: CGPoint(x: w * 0.1200, y: h * 0.5722), control1: CGPoint(x: w * 0.1203, y: h * 0.5108), control2: CGPoint(x: w * 0.1202, y: h * 0.5414))
                p.move(to: CGPoint(x: w * 0.7882, y: h * 0.3989))
                p.addCurve(to: CGPoint(x: w * 0.7882, y: h * 0.6269), control1: CGPoint(x: w * 0.7882, y: h * 0.5128), control2: CGPoint(x: w * 0.7882, y: h * 0.5128))
                p.move(to: CGPoint(x: w * 0.6624, y: h * 0.2555))
                p.addCurve(to: CGPoint(x: w * 0.6624, y: h * 0.7462), control1: CGPoint(x: w * 0.6624, y: h * 0.3782), control2: CGPoint(x: w * 0.6624, y: h * 0.6235))
                p.move(to: CGPoint(x: w * 0.8795, y: h * 0.4817))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.5739), control1: CGPoint(x: w * 0.8797, y: h * 0.5123), control2: CGPoint(x: w * 0.8798, y: h * 0.5431))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        }
    }
}

struct SpriteTabIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.1200, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.5000), control1: CGPoint(x: w * 0.3734, y: h * 0.2467), control2: CGPoint(x: w * 0.6267, y: h * 0.3733))
                p.move(to: CGPoint(x: w * 0.8800, y: h * 0.5000))
                p.addCurve(to: CGPoint(x: w * 0.1200, y: h * 0.8800), control1: CGPoint(x: w * 0.6267, y: h * 0.6267), control2: CGPoint(x: w * 0.3734, y: h * 0.7533))
                p.move(to: CGPoint(x: w * 0.1363, y: h * 0.3161))
                p.addCurve(to: CGPoint(x: w * 0.5406, y: h * 0.4951), control1: CGPoint(x: w * 0.2023, y: h * 0.3468), control2: CGPoint(x: w * 0.4746, y: h * 0.4644))
                p.move(to: CGPoint(x: w * 0.5406, y: h * 0.4951))
                p.addCurve(to: CGPoint(x: w * 0.1346, y: h * 0.6726), control1: CGPoint(x: w * 0.4746, y: h * 0.5257), control2: CGPoint(x: w * 0.2006, y: h * 0.6420))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        }
    }
}

struct TransformTabIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.4457, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.1200, y: h * 0.3099), control1: CGPoint(x: w * 0.3371, y: h * 0.1833), control2: CGPoint(x: w * 0.2285, y: h * 0.2466))
                p.move(to: CGPoint(x: w * 0.1200, y: h * 0.3099))
                p.addCurve(to: CGPoint(x: w * 0.4457, y: h * 0.5000), control1: CGPoint(x: w * 0.2285, y: h * 0.3734), control2: CGPoint(x: w * 0.3371, y: h * 0.4367))
                p.move(to: CGPoint(x: w * 0.4457, y: h * 0.5000))
                p.addCurve(to: CGPoint(x: w * 0.1200, y: h * 0.6901), control1: CGPoint(x: w * 0.3371, y: h * 0.5633), control2: CGPoint(x: w * 0.2285, y: h * 0.6266))
                p.move(to: CGPoint(x: w * 0.1200, y: h * 0.6901))
                p.addCurve(to: CGPoint(x: w * 0.4457, y: h * 0.8800), control1: CGPoint(x: w * 0.2285, y: h * 0.7534), control2: CGPoint(x: w * 0.3371, y: h * 0.8167))
                p.move(to: CGPoint(x: w * 0.8800, y: h * 0.1200))
                p.addCurve(to: CGPoint(x: w * 0.5543, y: h * 0.3099), control1: CGPoint(x: w * 0.7715, y: h * 0.1833), control2: CGPoint(x: w * 0.6628, y: h * 0.2466))
                p.move(to: CGPoint(x: w * 0.5543, y: h * 0.3099))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.5000), control1: CGPoint(x: w * 0.6628, y: h * 0.3734), control2: CGPoint(x: w * 0.7715, y: h * 0.4367))
                p.move(to: CGPoint(x: w * 0.8800, y: h * 0.5000))
                p.addCurve(to: CGPoint(x: w * 0.5543, y: h * 0.6901), control1: CGPoint(x: w * 0.7715, y: h * 0.5633), control2: CGPoint(x: w * 0.6628, y: h * 0.6266))
                p.move(to: CGPoint(x: w * 0.5543, y: h * 0.6901))
                p.addCurve(to: CGPoint(x: w * 0.8800, y: h * 0.8800), control1: CGPoint(x: w * 0.6628, y: h * 0.7534), control2: CGPoint(x: w * 0.7715, y: h * 0.8167))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
        }
    }
}

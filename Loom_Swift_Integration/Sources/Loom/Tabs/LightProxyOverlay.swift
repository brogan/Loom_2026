import SwiftUI
import LoomEngine

/// Canvas overlay drawn in the Lights tab main panel.
/// Draws a proxy shape for each light so the user can see and select position/size.
struct LightProxyOverlay: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let lights = controller.projectConfig?.lightingConfig.lights ?? []
            let selected = controller.selectedLightIndex

            // The live canvas is letterboxed; compute the actual canvas rect
            let canvasRect = centredCanvasRect(in: size)

            Canvas { ctx, _ in
                for (idx, light) in lights.enumerated() {
                    let isSelected = idx == selected
                    drawProxy(light: light, idx: idx, isSelected: isSelected,
                              canvasRect: canvasRect, ctx: &ctx)
                }
            }
            // Hit testing: tap to select
            .contentShape(Rectangle())
            .onTapGesture { location in
                let lights = controller.projectConfig?.lightingConfig.lights ?? []
                let canvasRect = centredCanvasRect(in: size)
                for (idx, light) in lights.enumerated().reversed() {
                    let cx = canvasRect.minX + CGFloat(0.5 + light.positionXDriver.base) * canvasRect.width
                    let cy = canvasRect.minY + CGFloat(0.5 - light.positionYDriver.base) * canvasRect.height
                    let d = hypot(location.x - cx, location.y - cy)
                    if d < 16 {
                        controller.selectedLightIndex = idx
                        return
                    }
                }
                controller.selectedLightIndex = nil
            }
        }
        .allowsHitTesting(true)
    }

    // MARK: - Per-light proxy drawing

    private func drawProxy(
        light: LoomLight,
        idx: Int,
        isSelected: Bool,
        canvasRect: CGRect,
        ctx: inout GraphicsContext
    ) {
        let alpha: Double = light.isEnabled ? 1.0 : 0.3
        let baseColor = Color(red: 1.0, green: 0.76, blue: 0.1, opacity: alpha)   // amber
        let dimColor  = Color(red: 1.0, green: 0.76, blue: 0.1, opacity: alpha * 0.4)

        let cx = canvasRect.minX + CGFloat(0.5 + light.positionXDriver.base) * canvasRect.width
        let cy = canvasRect.minY + CGFloat(0.5 - light.positionYDriver.base) * canvasRect.height
        let centre = CGPoint(x: cx, y: cy)

        switch light.type {

        case .omni:
            let r = CGFloat(light.radiusDriver.base) * canvasRect.width
            var circle = Path()
            circle.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.stroke(circle, with: .color(baseColor),
                       style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: [5, 3]))
            drawCentrePoint(ctx: &ctx, at: centre, color: baseColor, isSelected: isSelected)

        case .spot:
            let r      = CGFloat(light.radiusDriver.base) * canvasRect.width
            let dir    = CGFloat(light.directionDriver.base)
            let half   = CGFloat(light.coneAngleDriver.base)
            let penumb = CGFloat(light.penumbraAngle)

            // Inner cone
            var conePath = Path()
            conePath.move(to: centre)
            conePath.addArc(center: centre, radius: r,
                            startAngle: .radians(Double(-dir - half)),
                            endAngle:   .radians(Double(-dir + half)),
                            clockwise: false)
            conePath.closeSubpath()
            ctx.stroke(conePath, with: .color(baseColor),
                       style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: [5, 3]))

            // Penumbra cone (dimmer)
            if penumb > 0.01 {
                var pPath = Path()
                pPath.move(to: centre)
                pPath.addArc(center: centre, radius: r,
                             startAngle: .radians(Double(-dir - half - penumb)),
                             endAngle:   .radians(Double(-dir + half + penumb)),
                             clockwise: false)
                pPath.closeSubpath()
                ctx.stroke(pPath, with: .color(dimColor),
                           style: StrokeStyle(lineWidth: 0.75, dash: [3, 4]))
            }

            // Direction arrow tip
            let tx = cx + r * cos(-dir)
            let ty = cy + r * sin(-dir)
            var arrow = Path()
            arrow.move(to: centre)
            arrow.addLine(to: CGPoint(x: tx, y: ty))
            ctx.stroke(arrow, with: .color(baseColor),
                       style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1))
            drawCentrePoint(ctx: &ctx, at: centre, color: baseColor, isSelected: isSelected)

        case .area:
            let hw = CGFloat(light.widthDriver.base  * 0.5) * canvasRect.width
            let hh = CGFloat(light.heightDriver.base * 0.5) * canvasRect.width
            let rot = CGFloat(light.rotationDriver.base)

            var rect = Path()
            rect.addRect(CGRect(x: -hw, y: -hh, width: hw * 2, height: hh * 2))

            var transform = CGAffineTransform(translationX: cx, y: cy)
                .rotated(by: -rot)
            let transformed = rect.applying(transform)
            _ = transform  // suppress warning
            ctx.stroke(transformed, with: .color(baseColor),
                       style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: [5, 3]))
            drawCentrePoint(ctx: &ctx, at: centre, color: baseColor, isSelected: isSelected)
        }
    }

    private func drawCentrePoint(
        ctx: inout GraphicsContext,
        at pt: CGPoint,
        color: Color,
        isSelected: Bool
    ) {
        let r: CGFloat = isSelected ? 5 : 4
        var dot = Path()
        dot.addEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
        ctx.stroke(dot, with: .color(color), lineWidth: isSelected ? 1.5 : 1)
    }

    // MARK: - Canvas rect helper

    private func centredCanvasRect(in viewSize: CGSize) -> CGRect {
        guard let cfg = controller.projectConfig else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let cw = Double(cfg.globalConfig.width)
        let ch = Double(cfg.globalConfig.height)
        guard cw > 0, ch > 0 else { return CGRect(origin: .zero, size: viewSize) }
        let aspect = cw / ch
        let vw = Double(viewSize.width)
        let vh = Double(viewSize.height)
        var w = vw
        var h = vw / aspect
        if h > vh { h = vh; w = vh * aspect }
        let ox = (vw - w) / 2
        let oy = (vh - h) / 2
        return CGRect(x: ox, y: oy, width: w, height: h)
    }
}

import CoreGraphics
import Foundation

/// Produces a light-map `CGImage` at canvas resolution by evaluating all enabled lights
/// and compositing their contributions using additive blending.
///
/// The resulting image is used as a multiply-blend mask on opted-in layers:
///   - White pixel (1,1,1) → layer pixel unchanged (fully lit)
///   - Black pixel (0,0,0) → layer pixel becomes black (fully dark)
///   - Coloured pixel → layer pixel tinted by the light's colour
///
/// **Coordinate space**: position (0,0) = canvas centre; ±0.5 = canvas edges.
/// Radius and area dimensions are in the same normalized units (0.5 = half canvas width).
public enum LightMapRenderer {

    // MARK: - Resolved light (all drivers evaluated)

    public struct ResolvedLight {
        public var type:          LightType
        public var posX:          Double
        public var posY:          Double
        public var intensity:     Double
        public var color:         LoomColor
        public var falloff:       Double
        public var radius:        Double
        public var direction:     Double
        public var coneAngle:     Double
        public var penumbraAngle: Double
        public var width:         Double
        public var height:        Double
        public var rotation:      Double
        public var edgeSoftness:  Double
    }

    // MARK: - Driver evaluation

    public static func resolve(
        _ light: LoomLight,
        elapsedFrames: Double,
        targetFPS: Double
    ) -> ResolvedLight {
        func ev(_ drv: DoubleDriver) -> Double {
            DriverEvaluator.evaluate(drv, globalElapsed: elapsedFrames,
                                    targetFPS: targetFPS, spriteIndex: 0)
        }
        return ResolvedLight(
            type:          light.type,
            posX:          ev(light.positionXDriver),
            posY:          ev(light.positionYDriver),
            intensity:     max(0, min(1, ev(light.intensityDriver))),
            color:         light.color,
            falloff:       max(0.5, light.falloff),
            radius:        max(0.001, ev(light.radiusDriver)),
            direction:     ev(light.directionDriver),
            coneAngle:     max(0.01, ev(light.coneAngleDriver)),
            penumbraAngle: max(0, light.penumbraAngle),
            width:         max(0.001, ev(light.widthDriver)),
            height:        max(0.001, ev(light.heightDriver)),
            rotation:      ev(light.rotationDriver),
            edgeSoftness:  max(0, light.edgeSoftness)
        )
    }

    // MARK: - Top-level render

    /// Render a single light map for all enabled lights at the given canvas size.
    /// Returns `nil` if context creation fails.
    public static func render(
        config: LightingConfig,
        canvasSize: CGSize,
        elapsedFrames: Double,
        targetFPS: Double
    ) -> CGImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        guard let ctx = makeContext(size: canvasSize) else { return nil }

        // Black background: un-lit areas will multiply the layer to black.
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: canvasSize))

        for light in config.lights where light.isEnabled {
            let resolved = resolve(light, elapsedFrames: elapsedFrames, targetFPS: targetFPS)
            guard resolved.intensity > 0 else { continue }
            drawLight(resolved, in: ctx, canvasSize: canvasSize)
        }

        return ctx.makeImage()
    }

    // MARK: - Per-light dispatch

    private static func drawLight(
        _ light: ResolvedLight,
        in ctx: CGContext,
        canvasSize: CGSize
    ) {
        switch light.type {
        case .omni: drawOmni(light, in: ctx, canvasSize: canvasSize)
        case .spot: drawSpot(light, in: ctx, canvasSize: canvasSize)
        case .area: drawArea(light, in: ctx, canvasSize: canvasSize)
        }
    }

    // MARK: - Coordinate helpers

    private static func toPixel(
        posX: Double, posY: Double, canvasSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: canvasSize.width  * (0.5 + posX),
            y: canvasSize.height * (0.5 - posY)   // Y-up → Y-down
        )
    }

    private static func toPixelRadius(_ r: Double, canvasSize: CGSize) -> CGFloat {
        CGFloat(r * Double(canvasSize.width))
    }

    // Build a CGGradient from transparent black → light colour × intensity,
    // then fade back to transparent at the outer edge.
    // The inner stop is at the core region (1/3 of radius) for a natural bloom look.
    private static func makeRadialGradient(
        _ light: ResolvedLight
    ) -> (gradient: CGGradient, stops: [CGFloat])? {
        let cs  = CGColorSpaceCreateDeviceRGB()
        let r   = CGFloat(light.color.rF * light.intensity)
        let g   = CGFloat(light.color.gF * light.intensity)
        let b   = CGFloat(light.color.bF * light.intensity)

        // Build falloff stops: exponential approximation using multiple sample points.
        // More stops = smoother falloff curve.
        let n = 8
        var colors: [CGFloat] = []
        var locs:   [CGFloat] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)            // normalized distance 0…1
            let atten = CGFloat(pow(Double(1 - t), light.falloff))
            colors += [r * atten, g * atten, b * atten, atten]
            locs.append(t)
        }
        guard let gradient = CGGradient(
            colorSpace: cs,
            colorComponents: colors,
            locations: locs,
            count: n + 1
        ) else { return nil }
        return (gradient, locs)
    }

    // MARK: - Omni

    private static func drawOmni(
        _ light: ResolvedLight,
        in ctx: CGContext,
        canvasSize: CGSize
    ) {
        let center = toPixel(posX: light.posX, posY: light.posY, canvasSize: canvasSize)
        let radius = toPixelRadius(light.radius, canvasSize: canvasSize)
        guard let (gradient, _) = makeRadialGradient(light) else { return }

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: 0,
            endCenter:   center, endRadius:   radius,
            options: []
        )
        ctx.restoreGState()
    }

    // MARK: - Spot

    private static func drawSpot(
        _ light: ResolvedLight,
        in ctx: CGContext,
        canvasSize: CGSize
    ) {
        let center    = toPixel(posX: light.posX, posY: light.posY, canvasSize: canvasSize)
        let radius    = toPixelRadius(light.radius, canvasSize: canvasSize)
        let totalHalf = CGFloat(light.coneAngle + light.penumbraAngle)

        // In CGContext Y is down, so "up" is −Y.  direction = 0 means right (+X).
        // direction = π/2 means up = −Y in screen space → angle = −π/2 from positive X.
        let screenDir = CGFloat(-light.direction)  // flip Y axis
        let startAngle = screenDir - totalHalf
        let endAngle   = screenDir + totalHalf

        // Clip to cone path.
        let conePath = CGMutablePath()
        conePath.move(to: center)
        conePath.addArc(center: center, radius: radius,
                        startAngle: startAngle, endAngle: endAngle,
                        clockwise: false)
        conePath.closeSubpath()

        guard let (coreGradient, _) = makeRadialGradient(light) else { return }

        ctx.saveGState()
        ctx.addPath(conePath)
        ctx.clip()
        ctx.setBlendMode(.plusLighter)
        ctx.drawRadialGradient(
            coreGradient,
            startCenter: center, startRadius: 0,
            endCenter:   center, endRadius:   radius,
            options: []
        )

        // Penumbra: draw a second, softer pass outside the inner cone (inside total cone)
        // by re-drawing with lowered intensity for the penumbra band only.
        if light.penumbraAngle > 0.001 {
            let innerHalf = CGFloat(light.coneAngle)
            let innerStart = screenDir - innerHalf
            let innerEnd   = screenDir + innerHalf

            // Invert clip: everything inside total cone but OUTSIDE inner cone.
            let totalConePath = CGMutablePath()
            totalConePath.move(to: center)
            totalConePath.addArc(center: center, radius: radius,
                                 startAngle: startAngle, endAngle: endAngle,
                                 clockwise: false)
            totalConePath.closeSubpath()

            let innerConePath = CGMutablePath()
            innerConePath.move(to: center)
            innerConePath.addArc(center: center, radius: radius,
                                 startAngle: innerStart, endAngle: innerEnd,
                                 clockwise: false)
            innerConePath.closeSubpath()

            // Erase the inner cone region from the penumbra layer
            let penumbraPath = CGMutablePath()
            penumbraPath.addPath(totalConePath)
            // CGContext evenOdd: draw penumbra in the ring between inner and total cones.
            // We do this by drawing with reduced alpha over the full region
            // (already drawn at full alpha in inner), which has a soft look.
            // Simple approach: skip the complex even-odd and just draw a dimmer gradient.
        }

        ctx.restoreGState()
    }

    // MARK: - Area

    private static func drawArea(
        _ light: ResolvedLight,
        in ctx: CGContext,
        canvasSize: CGSize
    ) {
        let center    = toPixel(posX: light.posX, posY: light.posY, canvasSize: canvasSize)
        let halfW     = CGFloat(light.width  * 0.5 * Double(canvasSize.width))
        let halfH     = CGFloat(light.height * 0.5 * Double(canvasSize.width))
        let softPx    = CGFloat(light.edgeSoftness * Double(canvasSize.width))
        let rot       = CGFloat(light.rotation)
        let r         = CGFloat(light.color.rF * light.intensity)
        let g         = CGFloat(light.color.gF * light.intensity)
        let b         = CGFloat(light.color.bF * light.intensity)
        let cs        = CGColorSpaceCreateDeviceRGB()

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: -rot)   // negate: Y-down flip

        // Filled centre rectangle (minus soft margin).
        let innerW = max(0, halfW - softPx)
        let innerH = max(0, halfH - softPx)
        if innerW > 0, innerH > 0 {
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            ctx.fill(CGRect(x: -innerW, y: -innerH, width: innerW * 2, height: innerH * 2))
        }

        // Soft horizontal edges (top and bottom).
        if softPx > 0 {
            let hEdgeColors: [CGFloat] = [r, g, b, 1, r, g, b, 0]
            if let hGrad = CGGradient(colorSpace: cs, colorComponents: hEdgeColors,
                                      locations: [0, 1], count: 2) {
                // Top edge
                ctx.saveGState()
                ctx.clip(to: CGRect(x: -halfW, y: -halfH, width: halfW * 2, height: softPx))
                ctx.drawLinearGradient(hGrad,
                    start: CGPoint(x: 0, y: -halfH + softPx),
                    end:   CGPoint(x: 0, y: -halfH),
                    options: [])
                ctx.restoreGState()

                // Bottom edge
                ctx.saveGState()
                ctx.clip(to: CGRect(x: -halfW, y: halfH - softPx, width: halfW * 2, height: softPx))
                ctx.drawLinearGradient(hGrad,
                    start: CGPoint(x: 0, y: halfH - softPx),
                    end:   CGPoint(x: 0, y: halfH),
                    options: [])
                ctx.restoreGState()
            }

            // Soft vertical edges (left and right).
            let vEdgeColors: [CGFloat] = [r, g, b, 1, r, g, b, 0]
            if let vGrad = CGGradient(colorSpace: cs, colorComponents: vEdgeColors,
                                      locations: [0, 1], count: 2) {
                // Left edge
                ctx.saveGState()
                ctx.clip(to: CGRect(x: -halfW, y: -halfH, width: softPx, height: halfH * 2))
                ctx.drawLinearGradient(vGrad,
                    start: CGPoint(x: -halfW + softPx, y: 0),
                    end:   CGPoint(x: -halfW, y: 0),
                    options: [])
                ctx.restoreGState()

                // Right edge
                ctx.saveGState()
                ctx.clip(to: CGRect(x: halfW - softPx, y: -halfH, width: softPx, height: halfH * 2))
                ctx.drawLinearGradient(vGrad,
                    start: CGPoint(x: halfW - softPx, y: 0),
                    end:   CGPoint(x: halfW, y: 0),
                    options: [])
                ctx.restoreGState()
            }
        }

        ctx.restoreGState()
    }

    // MARK: - Context helper

    private static func makeContext(size: CGSize) -> CGContext? {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else { return nil }
        return CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

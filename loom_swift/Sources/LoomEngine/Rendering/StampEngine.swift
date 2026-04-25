import CoreGraphics
import Foundation

// MARK: - StampEngine

/// Places stamp images at positions determined by the polygon type.
///
/// Matches Scala's `StencilStampEngine` / `drawStenciled` dispatch:
///
/// - **`.point` polygons** — one stamp per point, no rotation, jitter in X and Y.
/// - **`.spline`, `.openSpline`, `.line` polygons** — stamps at intervals along the
///   edge geometry (no meander), with optional tangent rotation (`followTangent`).
///
/// Unlike `BrushStampEngine` there is no tinting, no masking, no pressure, and no
/// meander.  Stamps are full-RGBA PNGs composited source-over at uniform opacity.
enum StampEngine {

    /// Draw stamps onto `polygon` according to `config`.
    ///
    /// - Parameters:
    ///   - polygon:       World-space polygon; already transformed to pixel-offset space
    ///                    by `SpriteScene.applyTransform`.
    ///   - config:        Stencil/stamp configuration.
    ///   - context:       Drawing context with Y-flip pre-applied by `LoomEngine`.
    ///   - viewTransform: Adds canvas-centre offset to convert pixel-offsets to screen coords.
    ///   - stampImages:   Pre-loaded CGImages keyed by filename (from `stamps/`).
    ///   - opacityState:  Current palette-index state for stencil opacity animation.
    ///                    `nil` when the renderer's `opacityChange` is disabled.
    ///   - rng:           Generator for per-stamp scale, jitter, and opacity.
    static func draw<RNG: RandomNumberGenerator>(
        polygon:       Polygon2D,
        config:        StencilConfig,
        context:       CGContext,
        viewTransform: ViewTransform,
        stampImages:   [String: CGImage],
        opacityState:  PaletteIndexState? = nil,
        using rng:     inout RNG
    ) {
        let images: [CGImage] = config.stampNames.compactMap { stampImages[$0] }
        guard !images.isEmpty, !polygon.points.isEmpty else { return }

        switch polygon.type {
        case .point:
            drawAtPoints(polygon, images: images, config: config, context: context,
                         viewTransform: viewTransform, opacityState: opacityState, using: &rng)
        case .spline, .openSpline, .line:
            drawAlongEdges(polygon, images: images, config: config, context: context,
                           viewTransform: viewTransform, opacityState: opacityState, using: &rng)
        default:
            break
        }
    }

    // MARK: - Point stamps

    private static func drawAtPoints<RNG: RandomNumberGenerator>(
        _ polygon:      Polygon2D,
        images:         [CGImage],
        config:         StencilConfig,
        context:        CGContext,
        viewTransform:  ViewTransform,
        opacityState:   PaletteIndexState?,
        using rng:      inout RNG
    ) {
        let useOpacityPalette = config.opacityChange.enabled
                             && !config.opacityChange.sizePalette.isEmpty

        for (idx, worldPt) in polygon.points.enumerated() {
            let screen    = viewTransform.worldToScreen(worldPt)
            let randScale = Double.random(in: config.scaleMin...config.scaleMax, using: &rng)
            let opacity   = pickOpacity(config: config, usesPalette: useOpacityPalette,
                                        opacityState: opacityState, using: &rng)

            // Point stamps: tangentAngle = 0, followTangent = false (matches Scala stampAtPoint).
            // Jitter is applied independently in X and Y (no path tangent to define a normal).
            let jitterX = Double.random(in: config.perpendicularJitterMin...config.perpendicularJitterMax,
                                        using: &rng)
            let jitterY = Double.random(in: config.perpendicularJitterMin...config.perpendicularJitterMax,
                                        using: &rng)

            let img  = images[idx % images.count]
            let rect = stampRect(img, scale: randScale)

            context.saveGState()
            context.setAlpha(CGFloat(max(0, min(1, opacity))))
            context.translateBy(x: CGFloat(screen.x + jitterX), y: CGFloat(screen.y + jitterY))
            context.scaleBy(x: 1, y: -1)   // counter Y-flip: context is Y-flipped by LoomEngine
            context.draw(img, in: rect)
            context.restoreGState()
        }
    }

    // MARK: - Edge stamps

    /// Stamp images at regular intervals along the edge geometry of `polygon`.
    ///
    /// Equivalent to Scala's `StencilStampEngine.drawFullEdge`:
    /// - walks raw edge geometry (no meander perturbation)
    /// - random scale per stamp from [scaleMin, scaleMax]
    /// - perpendicular jitter along the path normal
    /// - optional tangent rotation when `config.followTangent` is true
    private static func drawAlongEdges<RNG: RandomNumberGenerator>(
        _ polygon:      Polygon2D,
        images:         [CGImage],
        config:         StencilConfig,
        context:        CGContext,
        viewTransform:  ViewTransform,
        opacityState:   PaletteIndexState?,
        using rng:      inout RNG
    ) {
        let edges = BrushEdge.extractEdges(from: [polygon], viewTransform: viewTransform)
        guard !edges.isEmpty else { return }

        let spacing           = max(1.0, config.stampSpacing)
        let useOpacityPalette = config.opacityChange.enabled
                             && !config.opacityChange.sizePalette.isEmpty
        var stampIdx = 0

        for edge in edges {
            guard edge.length > 0 else { continue }
            let numStamps = max(1, Int(edge.length / spacing))

            for i in 0...numStamps {
                let t        = numStamps <= 1 ? 0.0 : Double(i) / Double(numStamps)
                let tClamped = max(0.0, min(1.0, t))

                let (pos, angle) = PathPerturbation.sampleEdge(edge, t: tClamped)

                let scale   = Double.random(in: config.scaleMin...config.scaleMax, using: &rng)
                let opacity = pickOpacity(config: config, usesPalette: useOpacityPalette,
                                          opacityState: opacityState, using: &rng)

                // Perpendicular jitter: offset along the path normal (tangent + π/2).
                let jitter     = Double.random(in: config.perpendicularJitterMin...config.perpendicularJitterMax,
                                               using: &rng)
                let perpAngle  = angle + .pi / 2.0
                let stampX     = pos.x + jitter * cos(perpAngle)
                let stampY     = pos.y + jitter * sin(perpAngle)

                let img  = images[stampIdx % images.count]
                let rect = stampRect(img, scale: scale)
                stampIdx += 1

                context.saveGState()
                context.setAlpha(CGFloat(max(0, min(1, opacity))))
                context.translateBy(x: CGFloat(stampX), y: CGFloat(stampY))
                if config.followTangent {
                    // Negate angle: tangent is in screen-space (Y-down), but the context
                    // has a Y-flip applied, so rotation direction is inverted.
                    context.rotate(by: CGFloat(-angle))
                }
                context.scaleBy(x: 1, y: -1)   // counter Y-flip for image orientation
                context.draw(img, in: rect)
                context.restoreGState()
            }
        }
    }

    // MARK: - Helpers

    private static func stampRect(_ img: CGImage, scale: Double) -> CGRect {
        let w = CGFloat(img.width)  * CGFloat(scale)
        let h = CGFloat(img.height) * CGFloat(scale)
        return CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    }

    private static func pickOpacity<RNG: RandomNumberGenerator>(
        config:       StencilConfig,
        usesPalette:  Bool,
        opacityState: PaletteIndexState?,
        using rng:    inout RNG
    ) -> Double {
        guard usesPalette else { return 1.0 }
        let palette = config.opacityChange.sizePalette
        // SEQ / PING_PONG: use the stepped palette index driven by RenderStateEngine.
        // RAN: pick randomly each stamp (original behaviour).
        if config.opacityChange.kind == .sequential,
           let state = opacityState,
           state.index < palette.count {
            return palette[state.index]
        }
        return palette[Int.random(in: 0..<palette.count, using: &rng)]
    }
}

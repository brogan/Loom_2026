import CoreGraphics
import Foundation

// MARK: - BrushStampEngine

/// Places brush stamps along perturbed edge paths in FULL_PATH mode.
///
/// All coordinates are in screen space (top-left origin, Y-down), matching
/// the output of `BrushEdge.extractEdges` and `PerturbedPath.evaluate`.
/// The `context` must already have the Y-flip transform applied by `LoomEngine`.
enum BrushStampEngine {

    /// Stamp brush images along every edge in `edges`.
    ///
    /// - Parameters:
    ///   - edges:       Screen-space edges from `BrushEdge.extractEdges`.
    ///   - config:      Brush configuration, already scaled for quality.
    ///   - color:       Tint color applied to every stamp (renderer's `strokeColor`).
    ///   - context:     Drawing context with Y-flip pre-applied.
    ///   - elapsedFrames: Accumulated fractional frame count (= elapsed seconds × targetFPS),
    ///                    forwarded to the meander phase for frame-rate-independent animation.
    ///   - brushImages:   Pre-loaded stamp images, keyed by filename.
    static func drawFullPath(
        edges:         [BrushEdge],
        config:        BrushConfig,
        color:         LoomColor,
        context:       CGContext,
        elapsedFrames: Double,
        brushImages:   [String: CGImage],
        opacityMultiplier: Double = 1.0
    ) {
        let images = resolvedImages(config: config, brushImages: brushImages)
        guard !images.isEmpty else { return }
        guard !edges.isEmpty  else { return }

        let spacing = max(1.0, config.stampSpacing)

        for (edgeIndex, edge) in edges.enumerated() {
            let path = PathPerturbation.perturb(
                edge:          edge,
                config:        config.meander,
                edgeIndex:     edgeIndex,
                elapsedFrames: elapsedFrames,
                scaleMin:      config.scaleMin,
                scaleMax:      config.scaleMax
            )

            let numStamps = max(1, Int(path.length / spacing))
            var rng = StampRNG(seed: UInt64(bitPattern: Int64(edgeIndex) &* 6_364_136_223_846_793_005))

            for i in 0...numStamps {
                let t = numStamps <= 1 ? 0.0 : Double(i) / Double(numStamps)
                let (pos, angle, pathScale) = path.evaluate(t: t)

                drawStamp(
                    edge: edge,
                    stampIndex: i,
                    t: t,
                    position: pos,
                    angle: angle,
                    pathScale: pathScale,
                    config: config,
                    color: color,
                    context: context,
                    images: images,
                    rng: &rng,
                    opacityMultiplier: opacityMultiplier
                )
            }
        }
    }

    static func drawProgressiveStamps(
        agentIndex: Int,
        state: inout BrushProgressiveState,
        config: BrushConfig,
        color: LoomColor,
        context: CGContext,
        brushImages: [String: CGImage],
        opacityMultiplier: Double = 1.0
    ) {
        let images = resolvedImages(config: config, brushImages: brushImages)
        guard !images.isEmpty,
              state.agents.indices.contains(agentIndex)
        else { return }

        let spacing = max(1.0, config.stampSpacing)
        var agent = state.agents[agentIndex]
        var stampsDrawn = 0
        let stampsPerFrame = max(1, config.stampsPerFrame)

        while stampsDrawn < stampsPerFrame, !agent.completed {
            guard state.edges.indices.contains(agent.currentEdgeIndex),
                  state.paths.indices.contains(agent.currentEdgeIndex)
            else {
                agent.completed = true
                break
            }

            let edge = state.edges[agent.currentEdgeIndex]
            let path = state.paths[agent.currentEdgeIndex]
            let numStamps = max(1, Int(path.length / spacing))
            let t = max(0.0, min(1.0, agent.currentT))
            let stampIndex = max(0, min(numStamps, Int((t * Double(numStamps)).rounded())))
            let (pos, angle, pathScale) = path.evaluate(t: t)
            var rng = StampRNG(seed: stampSeed(edgeIndex: agent.currentEdgeIndex, stampIndex: stampIndex))

            drawStamp(
                edge: edge,
                stampIndex: stampIndex,
                t: t,
                position: pos,
                angle: angle,
                pathScale: pathScale,
                config: config,
                color: color,
                context: context,
                images: images,
                rng: &rng,
                opacityMultiplier: opacityMultiplier
            )
            stampsDrawn += 1

            agent.currentT += (1.0 / Double(numStamps)) * Double(agent.direction)
            if agent.currentT > 1.0 + 1e-9 || agent.currentT < -1e-9 {
                let nextEdge = agent.currentEdgeIndex + agent.direction
                if nextEdge < agent.edgeStartIndex || nextEdge > agent.edgeEndIndex {
                    agent.completed = true
                } else {
                    agent.currentEdgeIndex = nextEdge
                    agent.currentT = agent.direction > 0 ? 0.0 : 1.0
                }
            } else {
                agent.currentT = max(0.0, min(1.0, agent.currentT))
            }
        }

        state.agents[agentIndex] = agent
    }

    private static func resolvedImages(config: BrushConfig, brushImages: [String: CGImage]) -> [CGImage] {
        // Resolve brush images, preferring the pre-blurred variant when blurRadius > 0.
        // Blurred images are stored as "<filename>@<radius>" by LoomEngine at load time.
        config.brushNames.compactMap { name in
            if config.blurRadius > 0, let blurred = brushImages["\(name)@\(config.blurRadius)"] {
                return blurred
            }
            return brushImages[name]
        }
    }

    private static func drawStamp(
        edge: BrushEdge,
        stampIndex: Int,
        t: Double,
        position: Vector2D,
        angle: Double,
        pathScale: Double,
        config: BrushConfig,
        color: LoomColor,
        context: CGContext,
        images: [CGImage],
        rng: inout StampRNG,
        opacityMultiplier: Double = 1.0
    ) {
        // Base scale: when scaleAlongPath is true, use the per-path noise
        // envelope (pathScale).  When false (the common case), pick a random
        // value in [scaleMin, scaleMax] per stamp — matching Scala's behaviour
        // of Randomise.range(scaleMin, scaleMax) when the flag is off.
        let pressure = edge.pressure(at: t)
        let baseScale: Double
        if config.meander.scaleAlongPath {
            baseScale = pathScale
        } else {
            let lo = min(config.scaleMin, config.scaleMax)
            let hi = max(config.scaleMin, config.scaleMax)
            baseScale = rng.nextDouble() * (hi - lo) + lo
        }
        let pressureScale = 1.0 - config.pressureSizeInfluence
            + pressure * config.pressureSizeInfluence
        let finalScale = baseScale * pressureScale

        guard finalScale > 0 else { return }

        // Per-stamp random opacity in [opacityMin, opacityMax],
        // then further scaled by pressure influence.
        let randOpacity = rng.nextDouble() * (config.opacityMax - config.opacityMin)
            + config.opacityMin
        let pressureOpacity = 1.0 - config.pressureAlphaInfluence
            + pressure * config.pressureAlphaInfluence
        let finalOpacity = max(0.0, min(1.0, randOpacity * pressureOpacity * opacityMultiplier))

        // Perpendicular jitter.
        let jitterRange = config.perpendicularJitterMax - config.perpendicularJitterMin
        let jitter = rng.nextDouble() * jitterRange + config.perpendicularJitterMin
        let perpAngle = angle + .pi / 2.0
        let stampX = position.x + jitter * cos(perpAngle)
        let stampY = position.y + jitter * sin(perpAngle)

        // Choose brush image cyclically.
        let img = images[stampIndex % images.count]
        let imgW = CGFloat(img.width) * CGFloat(finalScale)
        let imgH = CGFloat(img.height) * CGFloat(finalScale)
        let rect = CGRect(x: -imgW / 2, y: -imgH / 2, width: imgW, height: imgH)

        context.saveGState()
        context.setAlpha(CGFloat(finalOpacity))
        context.translateBy(x: CGFloat(stampX), y: CGFloat(stampY))
        if config.followTangent {
            // Negate angle: tangent is computed in screen-space (Y-down), but
            // the context has a Y-flip applied, so CW and CCW are swapped.
            context.rotate(by: CGFloat(-angle))
        }
        // Tint via greyscale mask:
        // clip(to:mask:) treats the greyscale value as alpha (0=block, 255=allow),
        // which is the correct approach for brush PNGs with no alpha channel.
        context.clip(to: rect, mask: img)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.restoreGState()
    }

    private static func stampSeed(edgeIndex: Int, stampIndex: Int) -> UInt64 {
        let edge = UInt64(bitPattern: Int64(edgeIndex) &* 6_364_136_223_846_793_005)
        let stamp = UInt64(bitPattern: Int64(stampIndex) &* 1_442_695_040_888_963_407)
        return edge ^ stamp ^ 0x9E37_79B9_7F4A_7C15
    }
}

// MARK: - Deterministic per-stamp RNG

/// LCG random number generator seeded per-edge.
///
/// Uses the same multiplier/increment as `SeedRNG` in `SmoothNoise.swift` so
/// the statistical properties are consistent across the engine.
private struct StampRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed ^ 0x5DEECE66D
    }

    mutating func nextDouble() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(UInt32(state >> 33)) / Double(UInt32.max)
    }
}

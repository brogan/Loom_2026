import Foundation

/// Applies Dissolution passes to `[Polygon2D]` **after** all other pipeline stages.
///
/// Dissolution operates on polygon geometry directly (not on subdivision params).
/// Two modes:
///   - Entropy: vertices migrate toward a simpler target over time (centroid/smoothed/circle)
///   - Collapse: the form disappears at a trigger frame, optionally with a brief fade
///
/// Both modes are stateless and seekable: any frame can be evaluated without prior state.
public enum DissolutionEngine {

    public static func apply(
        polygons:      [Polygon2D],
        passes:        [DissolutionParams],
        elapsedFrames: Double,
        spriteIndex:   Int
    ) -> [Polygon2D] {
        var result = polygons
        for pass in passes where pass.enabled {
            result = applyPass(polygons: result, pass: pass,
                               elapsedFrames: elapsedFrames, spriteIndex: spriteIndex)
            if result.isEmpty { return [] }
        }
        return result
    }

    // MARK: - Per-pass

    private static func applyPass(
        polygons:      [Polygon2D],
        pass:          DissolutionParams,
        elapsedFrames: Double,
        spriteIndex:   Int
    ) -> [Polygon2D] {

        var effectiveFrames = elapsedFrames

        // ── Collapse ───────────────────────────────────────────────────────
        if pass.collapseEnabled {
            let collapseAt = firstCollapseFrame(for: pass, spriteIndex: spriteIndex)
            let fadeEnd    = Double(collapseAt + max(1, pass.collapseBriefDuration))

            switch pass.collapseEndMode {
            case .remove, .respawn:
                if pass.collapseMode == .instant {
                    if effectiveFrames >= Double(collapseAt) { return [] }
                } else {
                    if effectiveFrames >= fadeEnd { return [] }
                    if effectiveFrames >= Double(collapseAt) {
                        let progress = (effectiveFrames - Double(collapseAt))
                                     / Double(max(1, pass.collapseBriefDuration))
                        return polygons.map { shrinkToCentroid($0, progress: min(1.0, progress)) }
                    }
                }

            case .loop:
                let period = max(1.0, fadeEnd)
                effectiveFrames = effectiveFrames.truncatingRemainder(dividingBy: period)
                if pass.collapseMode == .instant {
                    if effectiveFrames >= Double(collapseAt) { return [] }
                } else {
                    if effectiveFrames >= fadeEnd { return [] }
                    if effectiveFrames >= Double(collapseAt) {
                        let progress = (effectiveFrames - Double(collapseAt))
                                     / Double(max(1, pass.collapseBriefDuration))
                        return polygons.map { shrinkToCentroid($0, progress: min(1.0, progress)) }
                    }
                }
            }
        }

        // ── Entropy ────────────────────────────────────────────────────────
        guard pass.entropyEnabled else { return polygons }
        let factor = entropyFactor(rate: pass.entropyRate, frames: effectiveFrames)
        guard factor > 1e-9 else { return polygons }
        return polygons.map { poly in
            applyEntropy(poly, factor: factor, target: pass.entropyTarget,
                         noise: pass.entropyNoise, seed: pass.entropySeed,
                         spriteIndex: spriteIndex, frames: effectiveFrames)
        }
    }

    // MARK: - Collapse trigger

    /// Frame at which collapse first fires, deterministically.
    private static func firstCollapseFrame(for pass: DissolutionParams, spriteIndex: Int) -> Int {
        switch pass.collapseTriggerType {
        case .frameCount:
            return max(1, pass.collapseTriggerFrameCount)
        case .probability:
            let p    = min(1.0, max(1e-9, pass.collapseTriggerProbability))
            let base = pass.entropySeed &+ spriteIndex &* 2_654_435_761
            for frame in 0 ..< 100_000 {
                let h = SubdivisionEngine.centreHash(seed: base ^ frame &* 1_231, cycle: frame & 0x7FFF_FFFF)
                if h < p { return frame }
            }
            return 100_000
        }
    }

    // MARK: - Entropy factor

    private static func entropyFactor(rate: Double, frames: Double) -> Double {
        let r = max(0, min(0.5, rate))
        return min(1.0, 1.0 - pow(max(0, 1.0 - r), frames))
    }

    // MARK: - Entropy application

    private static func applyEntropy(
        _ poly:       Polygon2D,
        factor:       Double,
        target:       EntropyTarget,
        noise:        Double,
        seed:         Int,
        spriteIndex:  Int,
        frames:       Double
    ) -> Polygon2D {
        switch poly.type {
        case .spline:
            return applyEntropySpline(poly, factor: factor, target: target,
                                      noise: noise, seed: seed,
                                      spriteIndex: spriteIndex, frames: frames)
        default:
            // For non-spline types, use simple uniform centroid shrink
            let c = BezierMath.centreSpline(poly.points)
            return poly.scaled(by: 1.0 - factor, around: c)
        }
    }

    private static func applyEntropySpline(
        _ poly:       Polygon2D,
        factor:       Double,
        target:       EntropyTarget,
        noise:        Double,
        seed:         Int,
        spriteIndex:  Int,
        frames:       Double
    ) -> Polygon2D {
        let pts = poly.points
        let n   = pts.count / 4
        guard n > 0 else { return poly }

        // Unique anchors at indices 0, 4, 8, … (start of each segment group)
        let anchors: [Vector2D] = (0 ..< n).map { pts[$0 * 4] }
        let c = BezierMath.centreSpline(pts)

        // Compute target position for each anchor
        let anchorTargets: [Vector2D]
        switch target {
        case .centroid:
            anchorTargets = anchors.map { _ in c }

        case .smoothed:
            anchorTargets = (0 ..< n).map { i in
                let prev = anchors[(i + n - 1) % n]
                let next = anchors[(i + 1) % n]
                return Vector2D.lerp(prev, next, t: 0.5)
            }

        case .circle:
            let meanR: Double = {
                let sum = anchors.reduce(0.0) { acc, a in
                    let dx = a.x - c.x; let dy = a.y - c.y
                    return acc + sqrt(dx*dx + dy*dy)
                }
                return sum / Double(max(1, n))
            }()
            anchorTargets = anchors.map { a in
                let dx = a.x - c.x; let dy = a.y - c.y
                let dist = sqrt(dx*dx + dy*dy)
                guard dist > 1e-9 else { return c }
                let s = meanR / dist
                return Vector2D(x: c.x + dx * s, y: c.y + dy * s)
            }
        }

        // Per-anchor displacement delta
        let frameSlot = Int(frames) & 0x7FFF_FFFF
        let deltas: [Vector2D] = (0 ..< n).map { i in
            let t = anchorTargets[i]
            var dx = (t.x - anchors[i].x) * factor
            var dy = (t.y - anchors[i].y) * factor
            if noise > 0 {
                let s  = (seed &+ spriteIndex &* 1_013 &+ i) & 0x7FFF_FFFF
                let hx = SubdivisionEngine.centreHash(seed: s,          cycle: frameSlot)
                let hy = SubdivisionEngine.centreHash(seed: s &+ 31_337, cycle: frameSlot)
                dx += (hx * 2.0 - 1.0) * noise
                dy += (hy * 2.0 - 1.0) * noise
            }
            return Vector2D(x: dx, y: dy)
        }

        // Apply: segment k = [anchor_k, cpOut_k, cpIn_{k+1}, anchor_{k+1}]
        // Control points follow their anchor rigidly.
        var newPts = pts
        for k in 0 ..< n {
            let d0   = deltas[k]
            let d1   = deltas[(k + 1) % n]
            let base = k * 4
            newPts[base + 0] = Vector2D(x: pts[base+0].x + d0.x, y: pts[base+0].y + d0.y)
            newPts[base + 1] = Vector2D(x: pts[base+1].x + d0.x, y: pts[base+1].y + d0.y)
            newPts[base + 2] = Vector2D(x: pts[base+2].x + d1.x, y: pts[base+2].y + d1.y)
            newPts[base + 3] = Vector2D(x: pts[base+3].x + d1.x, y: pts[base+3].y + d1.y)
        }
        return Polygon2D(points: newPts, type: poly.type,
                         pressures: poly.pressures,
                         pressureProfiles: poly.pressureProfiles,
                         visible: poly.visible)
    }

    // MARK: - Collapse shrink

    private static func shrinkToCentroid(_ poly: Polygon2D, progress: Double) -> Polygon2D {
        let c = BezierMath.centreSpline(poly.points)
        return poly.scaled(by: 1.0 - progress, around: c)
    }
}

import Foundation

/// Applies Dissolution passes to `[Polygon2D]` **after** all other pipeline stages.
///
/// Dissolution operates on polygon geometry directly (not on subdivision params).
/// Four mechanics, applied in this order within a pass:
///   - Collapse: the form disappears at a trigger frame, optionally with a brief shrink
///   - Entropy: vertices migrate toward a simpler target over time (centroid/smoothed/circle)
///   - Partial loss: a fraction of polygons in a subdivided set are pruned outright
///   - Drift: surviving polygons translate/rotate away from their original placement
///
/// All four are stateless and seekable: any frame can be evaluated without prior state.
///
/// Partial loss and drift are driven by the same two-track pattern as
/// `GenerationalEvolutionEngine` (see Specs/GeometricLifecycle.md §4.5): `dissolutionPhase`
/// (a `DoubleDriver`) is the "how much" track — an optional tweened progress value in
/// [0, 1], defaulting to a static 1.0 (fully applied) when its driver is disabled, so
/// enabling Partial Loss or Drift without touching the phase driver behaves exactly as
/// if they'd always been on. `dissolutionSeed`/`varySeedPerCycle` are the "which" track —
/// they seed which polygons/edges/directions are chosen, reusing
/// `GenerationalEvolutionEngine.revealCycleIndex`/`combineSeed` directly rather than
/// duplicating that logic.
public enum DissolutionEngine {

    public static func apply(
        polygons:      [Polygon2D],
        passes:        [DissolutionParams],
        elapsedFrames: Double,
        targetFPS:     Double = 30,
        spriteIndex:   Int
    ) -> [Polygon2D] {
        var result = polygons
        for pass in passes where pass.enabled {
            result = applyPass(polygons: result, pass: pass,
                               elapsedFrames: elapsedFrames, targetFPS: targetFPS, spriteIndex: spriteIndex)
            if result.isEmpty { return [] }
        }
        return result
    }

    // MARK: - Per-pass

    private static func applyPass(
        polygons:      [Polygon2D],
        pass:          DissolutionParams,
        elapsedFrames: Double,
        targetFPS:     Double,
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
                        return contract(polygons, progress: min(1.0, progress), pass: pass)
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
                        return contract(polygons, progress: min(1.0, progress), pass: pass)
                    }
                }
            }
        }

        // ── Entropy ────────────────────────────────────────────────────────
        var current = polygons
        if pass.entropyEnabled {
            let factor = entropyFactor(rate: pass.entropyRate, frames: effectiveFrames)
            if factor > 1e-9 {
                current = current.enumerated().map { idx, poly in
                    applyEntropy(poly, factor: factor, target: pass.entropyTarget,
                                 noise: pass.entropyNoise, seed: pass.entropySeed,
                                 spriteIndex: spriteIndex, frames: effectiveFrames,
                                 anchor: pass.contractionAnchor, anchorSeed: pass.dissolutionSeed,
                                 polygonIndex: idx)
                }
            }
        }

        // ── Partial loss ───────────────────────────────────────────────────
        if pass.partialLossEnabled, current.count > 1 {
            let phase = resolvePhase(pass, elapsedFrames: elapsedFrames, targetFPS: targetFPS, spriteIndex: spriteIndex)
            let threshold = phase * max(0, min(1, pass.partialLossMaxFraction))
            if threshold > 1e-9 {
                let seed = effectiveSeed(for: pass, elapsedFrames: elapsedFrames, targetFPS: targetFPS)
                current = current.enumerated().compactMap { idx, poly -> Polygon2D? in
                    let h = SubdivisionEngine.centreHash(seed: seed &+ idx &* 92_821, cycle: idx)
                    return h < threshold ? nil : poly
                }
            }
        }

        // ── Drift ──────────────────────────────────────────────────────────
        if pass.driftEnabled, !current.isEmpty {
            let phase = resolvePhase(pass, elapsedFrames: elapsedFrames, targetFPS: targetFPS, spriteIndex: spriteIndex)
            let seed  = effectiveSeed(for: pass, elapsedFrames: elapsedFrames, targetFPS: targetFPS)
            current = current.enumerated().map { idx, poly in
                applyDrift(poly, phase: phase, distance: pass.driftDistance, rotation: pass.driftRotation,
                          seed: seed, polygonIndex: idx)
            }
        }

        return current
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
        _ poly:         Polygon2D,
        factor:         Double,
        target:         EntropyTarget,
        noise:          Double,
        seed:           Int,
        spriteIndex:    Int,
        frames:         Double,
        anchor:         ContractionAnchor,
        anchorSeed:     Int,
        polygonIndex:   Int
    ) -> Polygon2D {
        switch poly.type {
        case .spline:
            return applyEntropySpline(poly, factor: factor, target: target,
                                      noise: noise, seed: seed,
                                      spriteIndex: spriteIndex, frames: frames)
        default:
            // For non-spline types, use simple uniform shrink toward the contraction anchor.
            let c = anchorPoint(for: poly, anchor: anchor, seed: anchorSeed, polygonIndex: polygonIndex)
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

    // MARK: - Contraction anchor

    /// The vertices of `poly` to pick an edge/vertex anchor from — every 4th point
    /// (the anchors) for spline-encoded types, or the raw point list otherwise.
    private static func vertices(of poly: Polygon2D) -> [Vector2D] {
        switch poly.type {
        case .spline, .openSpline:
            let n = poly.points.count / 4
            guard n > 0 else { return poly.points }
            return (0 ..< n).map { poly.points[$0 * 4] }
        default:
            return poly.points
        }
    }

    /// Resolves `anchor` to a concrete point on `poly`. `.edge`/`.vertex` pick a
    /// vertex deterministically via `seed`/`polygonIndex` (stable across frames).
    private static func anchorPoint(
        for poly:       Polygon2D,
        anchor:         ContractionAnchor,
        seed:           Int,
        polygonIndex:   Int
    ) -> Vector2D {
        switch anchor {
        case .centroid:
            return BezierMath.centreSpline(poly.points)
        case .vertex, .edge:
            let verts = vertices(of: poly)
            guard !verts.isEmpty else { return BezierMath.centreSpline(poly.points) }
            let h = SubdivisionEngine.centreHash(seed: seed &+ polygonIndex &* 7_919, cycle: polygonIndex)
            let i = min(verts.count - 1, Int(h * Double(verts.count)))
            let vertexA = verts[i]
            guard anchor == .edge, verts.count > 1 else { return vertexA }
            let vertexB = verts[(i + 1) % verts.count]
            return Vector2D.lerp(vertexA, vertexB, t: 0.5)
        }
    }

    /// Shrinks every polygon in `polygons` toward its contraction anchor by `progress`
    /// (0 = untouched, 1 = collapsed to the anchor point). Used by Collapse's Brief mode.
    private static func contract(_ polygons: [Polygon2D], progress: Double, pass: DissolutionParams) -> [Polygon2D] {
        polygons.enumerated().map { idx, poly in
            let c = anchorPoint(for: poly, anchor: pass.contractionAnchor, seed: pass.dissolutionSeed, polygonIndex: idx)
            return poly.scaled(by: 1.0 - progress, around: c)
        }
    }

    // MARK: - Driver evaluation (two-track pattern, mirrors GenerationalEvolutionEngine)

    /// `dissolutionPhase`'s evaluated progress in [0, 1], or a static 1.0 (fully
    /// applied) when its driver is disabled — mirrors `generationPhase`'s same
    /// disabled-means-static-full-effect default.
    private static func resolvePhase(
        _ pass:          DissolutionParams,
        elapsedFrames:   Double,
        targetFPS:       Double,
        spriteIndex:     Int
    ) -> Double {
        guard pass.dissolutionPhase.enabled else { return 1.0 }
        let raw = DriverEvaluator.evaluate(
            pass.dissolutionPhase,
            globalElapsed: elapsedFrames,
            targetFPS:     targetFPS,
            spriteIndex:   spriteIndex
        )
        return max(0, min(1.0, raw))
    }

    /// The seed actually in effect for `pass` — `dissolutionSeed` unchanged unless
    /// `varySeedPerCycle` is on and the phase driver is enabled, in which case it's
    /// combined with the current reveal cycle index. Reuses
    /// `GenerationalEvolutionEngine`'s cycle-counting and seed-mixing directly
    /// (same module) rather than duplicating them — see its `effectiveSeed` for the
    /// UI-facing rationale (live seed readout for reproducing a liked result).
    public static func effectiveSeed(
        for pass:        DissolutionParams,
        elapsedFrames:   Double,
        targetFPS:       Double
    ) -> Int {
        guard pass.varySeedPerCycle, pass.dissolutionPhase.enabled else { return pass.dissolutionSeed }
        let cycle = GenerationalEvolutionEngine.revealCycleIndex(
            for: pass.dissolutionPhase, elapsedFrames: elapsedFrames, targetFPS: targetFPS
        )
        return GenerationalEvolutionEngine.combineSeed(pass.dissolutionSeed, cycle)
    }

    // MARK: - Drift

    /// Per-polygon rigid drift: a fixed direction/rotation chosen once per polygon
    /// (seeded, stable across frames — a polygon always drifts the same way, it
    /// doesn't wander), magnitude scaled by `phase`.
    private static func applyDrift(
        _ poly:         Polygon2D,
        phase:          Double,
        distance:       Double,
        rotation:       Double,
        seed:           Int,
        polygonIndex:   Int
    ) -> Polygon2D {
        guard distance > 1e-9 || abs(rotation) > 1e-9 else { return poly }

        let angleRoll = SubdivisionEngine.centreHash(seed: seed &+ polygonIndex &* 15_121, cycle: polygonIndex)
        let angle     = angleRoll * 2.0 * .pi
        let dx        = cos(angle) * distance * phase
        let dy        = sin(angle) * distance * phase

        let rotRoll = SubdivisionEngine.centreHash(seed: seed &+ polygonIndex &* 22_801, cycle: polygonIndex &+ 1)
        let theta   = (rotRoll * 2.0 - 1.0) * rotation * phase

        var pts = poly.points
        if abs(theta) > 1e-9 {
            let centre = BezierMath.centreSpline(pts)
            let cosT = cos(theta), sinT = sin(theta)
            pts = pts.map { p in
                let rx = p.x - centre.x, ry = p.y - centre.y
                return Vector2D(x: centre.x + rx * cosT - ry * sinT,
                                y: centre.y + rx * sinT + ry * cosT)
            }
        }
        pts = pts.map { Vector2D(x: $0.x + dx, y: $0.y + dy) }

        return Polygon2D(points: pts, type: poly.type,
                         pressures: poly.pressures,
                         pressureProfiles: poly.pressureProfiles,
                         visible: poly.visible)
    }
}

import Foundation

/// Prototype of the generational (artificial-life) evolution mode described in
/// Specs/GeometricLifecycle.md §4.4. Only the extrude and split-and-displace
/// mutation operators are implemented — no fitness measure or lock/graft selection
/// yet (§4.4.5: validate the core generate loop on these two before adding the
/// riskier pieces). Closed polygons (`.spline`) only; open curves are future work.
public enum GenerationalEvolutionEngine {

    /// Runs every enabled `.generational` pass in `passes` in order, each processing
    /// the output of the previous. Non-`.generational` passes are ignored — they're
    /// handled by `EvolutionEngine.apply` earlier in the pipeline instead. Called from
    /// `SpriteScene` after Extension and before Dissolution (see `SpriteScene.swift`).
    ///
    /// Each pass's `generationPhase` driver (if enabled) is evaluated here to produce
    /// that pass's reveal position — see the per-pass `process(polygons:params:phase:)`
    /// below for what the phase means. Passes with the driver disabled fall back to
    /// their static `generationCount` (fully applied, no animation), unchanged from
    /// before this was added.
    public static func process(
        polygons:      [Polygon2D],
        passes:        [EvolutionParams],
        elapsedFrames: Double = 0,
        targetFPS:     Double = 30,
        spriteIndex:   Int    = 0
    ) -> [Polygon2D] {
        var result = polygons
        for pass in passes where pass.enabled && pass.operationType == .generational {
            let phase: Double
            if pass.generationPhase.enabled {
                let raw = DriverEvaluator.evaluate(
                    pass.generationPhase,
                    globalElapsed: elapsedFrames,
                    targetFPS:     targetFPS,
                    spriteIndex:   spriteIndex
                )
                phase = max(0, min(Double(pass.generationCount), raw))
            } else {
                phase = Double(pass.generationCount)
            }
            result = process(polygons: result, params: pass, phase: phase)
        }
        return result
    }

    /// Runs structural mutation up to `phase` generations, where `phase` is a
    /// continuous position in `[0, params.generationCount]`. `nil` (the default)
    /// applies the full `generationCount` statically, matching the engine's
    /// original (pre-animation) behavior — existing callers are unaffected.
    ///
    /// The integer part of `phase` is how many generations are fully applied, each
    /// applying exactly one operator to one eligible polygon. The fractional part
    /// scales the *next* generation's operator distance/displacement from 0 up to
    /// its full sampled value — the same target polygon, edge(s), and operator
    /// choice as phase crosses that generation's full-strength point, just growing
    /// in magnitude, so the mutation tweens into view rather than popping in.
    /// `params.operationType` is expected to be `.generational`; the caller (the
    /// `passes` overload above, or a test) is responsible for filtering.
    ///
    /// Deterministic and stateless in the architectural sense that matters (§4.4.4):
    /// given identical `polygons`, `params`, and `phase`, this always produces an
    /// identical result — the entire chain is recomputed from scratch on every
    /// call, nothing is incrementally mutated across rendered frames. It is *not*
    /// closed-form (O(N), not O(1)) because generation N genuinely depends on
    /// generation N−1's materialized geometry. Scrubbing `phase` backward or
    /// looping an oscillator driver "de-evolves" for free — there is no ratchet.
    public static func process(
        polygons: [Polygon2D],
        params:   EvolutionParams,
        phase:    Double? = nil
    ) -> [Polygon2D] {
        guard params.enabled, params.generationCount > 0 else { return polygons }
        let clampedPhase = max(0, min(Double(params.generationCount), phase ?? Double(params.generationCount)))
        guard clampedPhase > 0 else { return polygons }
        guard totalVertexCount(polygons) < params.maxVertexBudget else { return polygons }

        let fullGenerations = Int(clampedPhase)
        let partial = clampedPhase - Double(fullGenerations)

        var current = polygons
        for generation in 0..<fullGenerations {
            let next = applyGeneration(current, params: params, generation: generation, strength: 1.0)
            // A generation that would exceed budget is rejected outright — the
            // chain stops there rather than producing a partially-applied mutation.
            if totalVertexCount(next) > params.maxVertexBudget { return current }
            current = next
        }
        if partial > 1e-9, fullGenerations < params.generationCount {
            let next = applyGeneration(current, params: params, generation: fullGenerations, strength: partial)
            if totalVertexCount(next) <= params.maxVertexBudget {
                current = next
            }
        }
        return current
    }

    private static func totalVertexCount(_ polygons: [Polygon2D]) -> Int {
        polygons.reduce(0) { $0 + $1.points.count }
    }

    // MARK: - One generation

    private static func applyGeneration(
        _ polygons: [Polygon2D],
        params:     EvolutionParams,
        generation: Int,
        strength:   Double
    ) -> [Polygon2D] {
        let eligible = polygons.indices.filter { polygons[$0].type == .spline && polygons[$0].points.count >= 4 }
        guard !eligible.isEmpty else { return polygons }

        let seed = params.generationSeed
        let cycleBase = generation * 8

        let targetRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 1)
        let targetIdx  = eligible[min(eligible.count - 1, Int(targetRoll * Double(eligible.count)))]

        let totalWeight = max(params.extrudeWeight, 0) + max(params.splitWeight, 0)
        guard totalWeight > 0 else { return polygons }
        let opRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 2) * totalWeight

        if opRoll < params.extrudeWeight {
            return applyExtrude(polygons, targetIdx: targetIdx, params: params, cycleBase: cycleBase, strength: strength)
        } else {
            return applySplit(polygons, targetIdx: targetIdx, params: params, cycleBase: cycleBase, strength: strength)
        }
    }

    // MARK: - Extrude operator

    /// Extrudes a contiguous run of edges on the target polygon by an RPSR distance
    /// scaled by `strength` (1.0 = full sampled distance; the reveal tween holds
    /// the choice of target/edges/base-distance fixed and only scales magnitude —
    /// see `process(polygons:params:phase:)`), producing a run of neighboring quads
    /// (compound growth, same model as Extension's `.extrude` — see
    /// `ExtensionEngine.extrudeEdge`).
    private static func applyExtrude(
        _ polygons: [Polygon2D],
        targetIdx:  Int,
        params:     EvolutionParams,
        cycleBase:  Int,
        strength:   Double
    ) -> [Polygon2D] {
        let polygon  = polygons[targetIdx]
        let segCount = polygon.points.count / 4
        guard segCount > 0 else { return polygons }

        let seed = params.generationSeed
        let lo = min(params.extrudeRunLengthMin, params.extrudeRunLengthMax)
        let hi = max(params.extrudeRunLengthMin, params.extrudeRunLengthMax)
        let runLenRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 3)
        let runLength  = min(segCount, lo + Int(runLenRoll * Double(hi - lo + 1)))

        let startRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 4)
        let startSeg  = Int(startRoll * Double(segCount)) % segCount

        let distLo = min(params.extrudeDistanceMin, params.extrudeDistanceMax)
        let distHi = max(params.extrudeDistanceMin, params.extrudeDistanceMax)
        let distRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 5)
        let distance = (distLo + distRoll * (distHi - distLo)) * strength

        var additions: [Polygon2D] = []
        for offset in 0..<runLength {
            let segIdx = (startSeg + offset) % segCount
            if let quad = ExtensionEngine.extrudeEdge(polygon, segIdx: segIdx, distance: distance) {
                additions.append(quad)
            }
        }
        guard !additions.isEmpty else { return polygons }

        var result = polygons
        result.append(contentsOf: additions)
        return result
    }

    // MARK: - Split operator

    /// Splits one edge of the target polygon (de Casteljau, same primitive the
    /// geometry editor's edge-insert tool uses — see `BezierMath.split` and
    /// `AppController.splitPolygonSegment`), then displaces the new anchor point
    /// outward from the shape's centre by an RPSR distance scaled by `strength`
    /// (1.0 = full sampled displacement; see `process(polygons:params:phase:)`).
    /// Only the anchor moves; the flanking control points stay where the split
    /// placed them, which pulls the boundary into a rounded spike rather than a
    /// sharp discontinuity, and tweens smoothly from the undisplaced split point
    /// as strength grows from 0.
    private static func applySplit(
        _ polygons: [Polygon2D],
        targetIdx:  Int,
        params:     EvolutionParams,
        cycleBase:  Int,
        strength:   Double
    ) -> [Polygon2D] {
        var polygon  = polygons[targetIdx]
        let segCount = polygon.points.count / 4
        guard segCount > 0 else { return polygons }

        let seed = params.generationSeed
        let segRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 6)
        let segIdx  = Int(segRoll * Double(segCount)) % segCount

        let distLo = min(params.splitDisplacementMin, params.splitDisplacementMax)
        let distHi = max(params.splitDisplacementMin, params.splitDisplacementMax)
        let distRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 7)
        let distance = (distLo + distRoll * (distHi - distLo)) * strength

        let base = segIdx * 4
        let seg = Array(polygon.points[base..<(base + 4)])
        let (left, right) = BezierMath.split(seg: seg, t: 0.5)

        // Outward direction: from the shape's anchor-only centre (matches
        // Dissolution's `.centroid` entropy target) to the new split point.
        let centre    = BezierMath.centreSpline(polygon.points)
        let splitPt   = left[3]  // == right[0]
        let dir       = splitPt - centre
        let dirLength = dir.length
        guard dirLength > 1e-9 else { return polygons }
        let outward   = Vector2D(x: dir.x / dirLength, y: dir.y / dirLength)
        let displaced = Vector2D(x: splitPt.x + outward.x * distance,
                                  y: splitPt.y + outward.y * distance)

        var newPoints = polygon.points
        newPoints.replaceSubrange(base..<(base + 4), with: [
            left[0], left[1], left[2], displaced,
            displaced, right[1], right[2], right[3]
        ])
        polygon.points = newPoints

        var result = polygons
        result[targetIdx] = polygon
        return result
    }
}

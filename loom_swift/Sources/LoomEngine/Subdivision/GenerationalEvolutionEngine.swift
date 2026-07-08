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

            var effectivePass = pass
            effectivePass.generationSeed = effectiveSeed(
                for:           pass,
                elapsedFrames: elapsedFrames,
                targetFPS:     targetFPS
            )
            result = process(polygons: result, params: effectivePass, phase: phase)
        }
        return result
    }

    /// The seed actually in effect for `pass` at `elapsedFrames` — `generationSeed`
    /// unchanged unless `varySeedPerCycle` is on and the reveal driver is enabled, in
    /// which case it's combined with the current cycle index. Exposed publicly (not
    /// just used internally by `process(polygons:passes:...)` above) so the UI can
    /// display the live seed during playback — e.g. so a user watching an animated
    /// reveal can read off and note the seed of a result they like, then paste it
    /// into `generationSeed` (with `varySeedPerCycle` off) to reproduce it exactly.
    public static func effectiveSeed(
        for pass:        EvolutionParams,
        elapsedFrames:   Double,
        targetFPS:       Double
    ) -> Int {
        guard pass.varySeedPerCycle, pass.generationPhase.enabled else { return pass.generationSeed }
        let cycle = revealCycleIndex(for: pass.generationPhase, elapsedFrames: elapsedFrames, targetFPS: targetFPS)
        return combineSeed(pass.generationSeed, cycle)
    }

    /// How many times the reveal driver has completed a full cycle by
    /// `elapsedFrames`, aligned to the driver's *trough* (its minimum output,
    /// i.e. generation 0) rather than its raw internal wrap point. Aligning to the
    /// wrap point instead would flip the seed partway up the climb from generation
    /// 0 (a quarter-cycle after the trough for sine/triangle), producing a visible
    /// mid-climb glitch instead of a clean per-cycle variation.
    ///
    /// Only Oscillator and looping Keyframe modes have a well-defined "cycle" —
    /// Constant/Jitter/Noise and non-looping Keyframe return 0 (no variation),
    /// since there's no restart point to key off.
    public static func revealCycleIndex(
        for driver:      DoubleDriver,
        elapsedFrames:   Double,
        targetFPS:       Double
    ) -> Int {
        guard driver.enabled else { return 0 }
        switch driver.mode {
        case .oscillator:
            let fps = max(1, targetFPS)
            let t = elapsedFrames * driver.freqHz / fps + driver.phase
            let troughOffset: Double
            switch driver.wave {
            case .sine, .triangle: troughOffset = 0.75
            case .square:          troughOffset = 0.5
            case .sawtooth:        troughOffset = 0.0
            }
            return Int(floor(t - troughOffset))
        case .keyframe:
            guard driver.loopMode == .loop || driver.loopMode == .pingPong,
                  let lastFrame = driver.keyframes.map(\.frame).max(), lastFrame > 0
            else { return 0 }
            let period = driver.loopMode == .pingPong ? Double(lastFrame) * 2 : Double(lastFrame)
            return Int(floor(elapsedFrames / period))
        case .constant, .jitter, .noise:
            return 0
        }
    }

    /// Golden-ratio-based mix so adjacent cycle indices produce well-distributed,
    /// uncorrelated seeds rather than merely incrementing by one each cycle.
    static func combineSeed(_ seed: Int, _ cycleIndex: Int) -> Int {
        var h = UInt64(bitPattern: Int64(seed))
            ^ (UInt64(bitPattern: Int64(cycleIndex)) &* 0x9E3779B97F4A7C15)
        h ^= h >> 33; h &*= 0xff51afd7ed558ccd
        h ^= h >> 33; h &*= 0xc4ceb9fe1a85ec53
        h ^= h >> 33
        return Int(truncatingIfNeeded: h)
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

    // MARK: - Directional selection (Specs/GeometricLifecycle.md §14)

    /// Segment indices of `polygon` whose outward normal passes `selector` — every
    /// segment index when the selector is disabled, so behavior is byte-for-byte
    /// unchanged from before this existed (the roll that used to index `0..<segCount`
    /// directly now indexes this array, which equals `0..<segCount` in that case).
    /// Reused by both `applyExtrude` (run start point) and `applySplit` (split
    /// edge) so one directional constraint governs both operators consistently.
    /// Reuses `ExtensionEngine.outwardNormal` rather than recomputing the same
    /// edge-normal formula a third time.
    private static func eligibleSegments(of polygon: Polygon2D, selector: DirectionalSelector) -> [Int] {
        let segCount = polygon.points.count / 4
        guard segCount > 0 else { return [] }
        guard selector.enabled else { return Array(0..<segCount) }
        return (0..<segCount).filter { selector.accepts(ExtensionEngine.outwardNormal(of: polygon, segIdx: $0)) }
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

        let eligibleSegs = eligibleSegments(of: polygon, selector: params.directionalSelector)
        guard !eligibleSegs.isEmpty else { return polygons }

        let seed = params.generationSeed
        let lo = min(params.extrudeRunLengthMin, params.extrudeRunLengthMax)
        let hi = max(params.extrudeRunLengthMin, params.extrudeRunLengthMax)
        let runLenRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 3)
        let runLength  = min(segCount, lo + Int(runLenRoll * Double(hi - lo + 1)))

        // The run's *start* is restricted to an eligible (direction-filtered) edge;
        // it then grows contiguously from there exactly as before, which can spill
        // onto neighboring non-eligible edges as runLength grows past 1 — treated
        // as intentional (a run "growing from" a qualifying edge), not a leak.
        let startRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 4)
        let startSeg  = eligibleSegs[min(eligibleSegs.count - 1, Int(startRoll * Double(eligibleSegs.count)))]

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

        let eligibleSegs = eligibleSegments(of: polygon, selector: params.directionalSelector)
        guard !eligibleSegs.isEmpty else { return polygons }

        let seed = params.generationSeed
        let segRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 6)
        let segIdx  = eligibleSegs[min(eligibleSegs.count - 1, Int(segRoll * Double(eligibleSegs.count)))]

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

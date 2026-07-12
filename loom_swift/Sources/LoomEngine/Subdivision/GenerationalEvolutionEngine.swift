import Foundation

/// Prototype of the generational (artificial-life) evolution mode described in
/// Specs/GeometricLifecycle.md §4.4 — Extrude, Split, and the n-gon Graft operator
/// (§4.4.8) — no fitness measure or lock selection yet (§4.4.5). Closed polygons
/// (`.spline`) only, by default; `.openSpline` polygons also become eligible for
/// all three operators when `EvolutionParams.includeOpenCurves` is set (§4.4.6,
/// widened from Extrude-only to general). There's no principled single "outward"
/// for an open curve, so every operator independently picks one of an eligible
/// edge's two sides per instance — see `openCurveSafeOutward`, the shared helper
/// all three route through. `extrudeOpenCurveBothSides` additionally lets an
/// extruded edge grow on both sides at once — Extrude-specific, no Split/Graft
/// analogue.
public enum GenerationalEvolutionEngine {

    /// Per-side multiplier range for `EvolutionParams.extrudeAsymmetricSides` — each
    /// corner of an extruded edge independently sampled from this range and
    /// multiplied against the sampled distance. Centered on 1.0 so the average
    /// visual scale roughly matches the symmetric (disabled) case.
    private static let asymmetryRangeLo = 0.4
    private static let asymmetryRangeHi = 1.6

    /// Max angular deviation from perpendicular for
    /// `EvolutionParams.extrudeAngleRandomized`, degrees — ±45° gives the
    /// requested 45°–135° range measured from the edge itself.
    private static let angleRandomizationDegrees = 45.0

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
        spriteIndex:   Int    = 0,
        customPrimitives: [String: Polygon2D] = [:]
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
            result = process(polygons: result, params: effectivePass, phase: phase, customPrimitives: customPrimitives)
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
        phase:    Double? = nil,
        customPrimitives: [String: Polygon2D] = [:]
    ) -> [Polygon2D] {
        guard params.enabled, params.generationCount > 0 else { return polygons }
        let clampedPhase = max(0, min(Double(params.generationCount), phase ?? Double(params.generationCount)))
        guard clampedPhase > 0 else { return polygons }
        guard totalVertexCount(polygons) < params.maxVertexBudget else { return polygons }

        let fullGenerations = Int(clampedPhase)
        let partial = clampedPhase - Double(fullGenerations)

        var current = polygons
        for generation in 0..<fullGenerations {
            let next = applyGeneration(current, params: params, generation: generation, strength: 1.0, customPrimitives: customPrimitives)
            // A generation that would exceed budget is rejected outright — the
            // chain stops there rather than producing a partially-applied mutation.
            if totalVertexCount(next) > params.maxVertexBudget { return current }
            current = next
        }
        if partial > 1e-9, fullGenerations < params.generationCount {
            let next = applyGeneration(current, params: params, generation: fullGenerations, strength: partial, customPrimitives: customPrimitives)
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
        strength:   Double,
        customPrimitives: [String: Polygon2D] = [:]
    ) -> [Polygon2D] {
        let seed = params.generationSeed
        let cycleBase = generation * 8

        // Target is drawn once from a single eligible list, then the operator is
        // chosen; all three operators share that one target. `includeOpenCurves`
        // (Specs/GeometricLifecycle.md §4.4.6, widened to all three operators —
        // was Extrude-only) parameterizes the type filter itself rather than
        // branching into a separate code path per operator: when it's off (the
        // default), `typeOK` reduces to exactly `type == .spline`, byte-for-byte
        // identical to this engine's original closed-only-only behavior. Extrude,
        // Split, and Graft each independently handle the "no principled single
        // outward for an open curve" problem via `openCurveSafeOutward` below, so
        // none of them needs its own eligible-set carve-out anymore.
        let eligible = polygons.indices.filter {
            let typeOK = polygons[$0].type == .spline
                || (params.includeOpenCurves && polygons[$0].type == .openSpline)
            return typeOK && polygons[$0].points.count >= 4
        }
        guard !eligible.isEmpty else { return polygons }

        let targetRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 1)
        let targetIdx  = eligible[min(eligible.count - 1, Int(targetRoll * Double(eligible.count)))]

        let totalWeight = max(params.extrudeWeight, 0) + max(params.splitWeight, 0) + max(params.graftWeight, 0)
        guard totalWeight > 0 else { return polygons }
        let opRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 2) * totalWeight

        if opRoll < params.extrudeWeight {
            return applyExtrude(polygons, targetIdx: targetIdx, params: params, cycleBase: cycleBase, strength: strength)
        } else if opRoll < params.extrudeWeight + params.splitWeight {
            return applySplit(polygons, targetIdx: targetIdx, params: params, cycleBase: cycleBase, strength: strength)
        } else {
            return applyGraft(polygons, targetIdx: targetIdx, params: params, cycleBase: cycleBase, strength: strength, customPrimitives: customPrimitives)
        }
    }

    /// For a closed polygon, `ExtensionEngine.outwardNormal` unchanged — that
    /// formula's correctness as "outward" is a property of consistent polygon
    /// winding, and this doesn't touch it. For an open curve, there's no single
    /// principled "outward" (§4.4.6's original design note, from when only
    /// Extrude supported open curves) — randomly picks one of the two sides
    /// instead, matching Extrude's own established per-edge coin-flip exactly.
    /// `seed`/`cycle` are caller-supplied so each call site's roll stays
    /// independent of every other per-generation roll — see each caller's own
    /// comment for its specific salt/slot choice.
    private static func openCurveSafeOutward(
        of polygon: Polygon2D, segIdx: Int, seed: Int, cycle: Int
    ) -> Vector2D {
        let base = ExtensionEngine.outwardNormal(of: polygon, segIdx: segIdx)
        guard polygon.type == .openSpline, base != .zero else { return base }
        let sideRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycle)
        return sideRoll < 0.5 ? -base : base
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
    /// `ExtensionEngine.extrudeEdge`). By default each quad is rectangular
    /// (`extrudeAsymmetricSides` false) and extrudes exactly perpendicular to its
    /// edge (`extrudeAngleRandomized` false); either toggle, independently sampled
    /// per edge in the run, produces tapered/wedge quads and/or quads that lean up
    /// to ±45° from perpendicular instead.
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

        // §4.4.6: a closed polygon's segments wrap (segment segCount-1 is adjacent
        // to segment 0), so `(startSeg + offset) % segCount` is correct there — but
        // an open curve's segments don't: there's nothing "after" the last one. A
        // run is clamped to stop at the curve's end instead of wrapping onto its
        // start, which would otherwise extrude a bogus "adjacent" edge that isn't
        // actually adjacent to where the run started.
        let isOpenCurve = polygon.type == .openSpline
        let effectiveRunLength = isOpenCurve ? min(runLength, segCount - startSeg) : runLength

        var additions: [Polygon2D] = []
        for offset in 0..<effectiveRunLength {
            let segIdx = isOpenCurve ? (startSeg + offset) : (startSeg + offset) % segCount

            // Per-edge rolls for the two side toggles below, salted by `offset` so
            // each edge in the run gets an independent choice rather than the whole
            // run leaning uniformly one way. Salting the *seed* (not reusing a
            // cycleBase+N slot) guarantees these never collide with any existing
            // per-generation roll, including in generations that don't use these
            // toggles — see the file-level note in EvolutionParams.swift.
            let edgeSeed = seed &+ (offset &+ 1) &* 3_267_000_013

            var distanceA0: Double?
            var distanceA1: Double?
            if params.extrudeAsymmetricSides {
                let m0Roll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 0)
                let m1Roll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 1)
                distanceA0 = distance * (asymmetryRangeLo + m0Roll * (asymmetryRangeHi - asymmetryRangeLo))
                distanceA1 = distance * (asymmetryRangeLo + m1Roll * (asymmetryRangeHi - asymmetryRangeLo))
            }

            // §4.4.6 step 2: an open curve has no principled "outward" — each edge
            // independently picks one of its two sides via its own RPSR roll
            // (edgeSeed cycle 3), rather than always using outwardNormal's single
            // perpendicular the way a closed polygon does. Closed-polygon targets
            // never take this branch, so their one true-outward direction is
            // completely unaffected — `isOpenCurve` can only be true here when
            // `includeOpenCurves` was on in the first place (gates eligibility
            // upstream in applyGeneration).
            //
            // Step 3: when extrudeOpenCurveBothSides is also on, a second
            // independent per-edge roll (cycle 4) decides whether this edge
            // *additionally* extrudes its other side too — "one or more sides"
            // per §4.4.6. Both sides share the same angle-randomization offset
            // (a property of the edge, not of the individual quad) and the same
            // distanceA0/A1 asymmetry roll, computed once above.
            var direction: Vector2D?
            var secondDirection: Vector2D?
            let baseNormal = ExtensionEngine.outwardNormal(of: polygon, segIdx: segIdx)
            if baseNormal != .zero {
                var chosenNormal = baseNormal
                var otherNormal: Vector2D?
                if isOpenCurve {
                    let sideRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 3)
                    if sideRoll < 0.5 {
                        chosenNormal = -chosenNormal
                    }
                    if params.extrudeOpenCurveBothSides {
                        let bothSidesRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 4)
                        if bothSidesRoll < 0.5 {
                            otherNormal = -chosenNormal
                        }
                    }
                }
                if params.extrudeAngleRandomized {
                    let angleRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 2)
                    let angleOffsetDeg = (angleRoll * 2.0 - 1.0) * angleRandomizationDegrees
                    let angleRad = angleOffsetDeg * .pi / 180.0
                    chosenNormal = chosenNormal.rotated(by: angleRad)
                    otherNormal = otherNormal?.rotated(by: angleRad)
                }
                // Only override extrudeEdge's own internally-computed normal when
                // something actually changed it — keeps the untouched-toggles case
                // (closed polygon, angle randomization off) byte-for-byte identical
                // to before this step existed.
                if isOpenCurve || params.extrudeAngleRandomized {
                    direction = chosenNormal
                }
                secondDirection = otherNormal
            }

            if let quad = ExtensionEngine.extrudeEdge(polygon, segIdx: segIdx, distance: distance,
                                                       distanceA0: distanceA0, distanceA1: distanceA1,
                                                       direction: direction) {
                additions.append(quad)
            }
            if let secondDir = secondDirection,
               let quad2 = ExtensionEngine.extrudeEdge(polygon, segIdx: segIdx, distance: distance,
                                                        distanceA0: distanceA0, distanceA1: distanceA1,
                                                        direction: secondDir) {
                additions.append(quad2)
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
    /// outward by an RPSR distance scaled by `strength` (1.0 = full sampled
    /// displacement; see `process(polygons:params:phase:)`). "Outward" is from the
    /// shape's anchor-only centre for a closed polygon; for an open curve target
    /// (only reachable when `EvolutionParams.includeOpenCurves` is on), there's no
    /// principled centroid-relative direction, so each split instead randomly picks
    /// one of its edge's two perpendicular sides — see `openCurveSafeOutward`. By
    /// default only the anchor moves; the flanking control points stay where
    /// the split placed them, which pulls the boundary into a rounded spike rather
    /// than a sharp discontinuity, and tweens smoothly from the undisplaced split
    /// point as strength grows from 0. `splitBulgePinchMin/Max` (0–0 by default,
    /// no effect) additionally offsets those two flanking control points along the
    /// same outward direction — see the bulge/pinch comment below.
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

        // Split position along the edge (t-parameter), RPSR-sampled from
        // splitPositionMin/Max — 0.5–0.5 by default (always the exact midpoint,
        // original behavior). Clamped away from the extreme ends so a degenerate
        // near-zero-length sub-segment can't result. Salted seed (not a
        // cycleBase+N slot — all 8 are taken, see the roll-index notes on the
        // asymmetry/angle rolls above) so this can't collide with any existing
        // per-generation roll.
        let posLo = min(params.splitPositionMin, params.splitPositionMax)
        let posHi = max(params.splitPositionMin, params.splitPositionMax)
        let posSeed = seed &+ 444_444_437
        let posRoll = SubdivisionEngine.centreHash(seed: posSeed, cycle: cycleBase)
        let splitT = max(0.05, min(0.95, posLo + posRoll * (posHi - posLo)))

        let base = segIdx * 4
        let seg = Array(polygon.points[base..<(base + 4)])
        let (left, right) = BezierMath.split(seg: seg, t: splitT)

        // Outward direction: for a closed polygon, from the shape's anchor-only
        // centre (matches Dissolution's `.centroid` entropy target) to the new
        // split point — unchanged. For an open curve, there's no principled
        // centroid-relative "outward" the way there is for a closed polygon's
        // interior (§4.4.6) — the same per-edge random-side pick Extrude already
        // uses instead, via `openCurveSafeOutward`. Own salted seed (all 8
        // cycleBase slots are already taken — see the posSeed comment above),
        // cycleBase-folded so it still varies generation-to-generation.
        let splitPt = left[3]  // == right[0]
        let outward: Vector2D
        if polygon.type == .openSpline {
            let sideSeed = seed &+ 725_827_609
            outward = openCurveSafeOutward(of: polygon, segIdx: segIdx, seed: sideSeed, cycle: cycleBase)
            guard outward != .zero else { return polygons }
        } else {
            let centre    = BezierMath.centreSpline(polygon.points)
            let dir       = splitPt - centre
            let dirLength = dir.length
            guard dirLength > 1e-9 else { return polygons }
            outward = Vector2D(x: dir.x / dirLength, y: dir.y / dirLength)
        }
        let displaced = Vector2D(x: splitPt.x + outward.x * distance,
                                  y: splitPt.y + outward.y * distance)

        // Bulge/pinch: an additional offset applied only to the two control points
        // immediately flanking the new anchor, along the *inward* direction
        // (toward centre) for positive values. Fixed 2026-07-10: this was
        // originally applied along `outward` for positive values, which is
        // backwards from what "bulge"/"pinch" mean visually — verified by
        // rendering both signs (see the design-note update in
        // Specs/GeometricLifecycle.md §4.4.2). Pulling the flanking points
        // *toward* centre relative to their un-displaced split position is what
        // actually produces a fuller, flared, rounder base (a "bulge" — the base
        // widens into an S-curve before the point); pushing them *away* from
        // centre (toward/past the displaced-anchor chord) straightens the sides
        // into a cleaner, sharper point (a "pinch"). Uses cycleBase+0 — every
        // other per-generation roll in this file starts at cycleBase+1
        // (targetRoll) or higher, so this slot has been unused until now.
        let bulgeLo = min(params.splitBulgePinchMin, params.splitBulgePinchMax)
        let bulgeHi = max(params.splitBulgePinchMin, params.splitBulgePinchMax)
        var leftCP2  = left[2]
        var rightCP1 = right[1]
        if bulgeLo != 0 || bulgeHi != 0 {
            let bulgeRoll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleBase + 0)
            let bulge = (bulgeLo + bulgeRoll * (bulgeHi - bulgeLo)) * strength
            leftCP2  = Vector2D(x: leftCP2.x  - outward.x * bulge, y: leftCP2.y  - outward.y * bulge)
            rightCP1 = Vector2D(x: rightCP1.x - outward.x * bulge, y: rightCP1.y - outward.y * bulge)
        }

        var newPoints = polygon.points
        newPoints.replaceSubrange(base..<(base + 4), with: [
            left[0], left[1], leftCP2, displaced,
            displaced, rightCP1, right[2], right[3]
        ])
        polygon.points = newPoints

        var result = polygons
        result[targetIdx] = polygon
        return result
    }

    // MARK: - Graft operator (Specs/GeometricLifecycle.md §4.4.8)

    /// A distinct salt for Graft's own roll namespace (§4.4.8.6 step 2) — all
    /// eight `cycleBase + 0...7` slots on the un-salted `seed` are already spoken
    /// for by Extrude/Split (see the comments on those functions above), so Graft
    /// gets its own salted seed instead, exactly like `applySplit`'s `posSeed`.
    /// `centreHash` mixes `seed` multiplicatively before hashing, so a distinct
    /// additive salt produces an effectively independent hash stream regardless
    /// of which `cycle` values are reused on it — safe to use small fixed
    /// `cycleBase + 0/1/2/...` offsets here exactly as the un-salted rolls do,
    /// with `cycleBase` (not a bare constant) folded in so Graft's own rolls
    /// still vary generation-to-generation like every other operator's.
    private static let graftSeedSalt = 918_273_645

    /// Dispatches on `graftAttachmentMode` (§4.4.8.3). `.wholeEdge` and
    /// `.singlePoint` never run in the same generation for the same target, so
    /// the two implementations freely reuse the same `cycleBase + 0/1/2/...`
    /// roll-slot numbering on `graftSeed` without colliding — only one branch
    /// ever executes. `strength` (the reveal tween) grows the grafted piece from
    /// the attachment point outward as it climbs from 0 to 1 — see
    /// `applyRevealScale`, applied identically by all three attachment modes.
    private static func applyGraft(
        _ polygons: [Polygon2D],
        targetIdx:  Int,
        params:     EvolutionParams,
        cycleBase:  Int,
        strength:   Double,
        customPrimitives: [String: Polygon2D] = [:]
    ) -> [Polygon2D] {
        switch params.graftAttachmentMode {
        case .wholeEdge:
            return applyGraftWholeEdge(polygons, targetIdx: targetIdx, params: params, cycleBase: cycleBase, strength: strength, customPrimitives: customPrimitives)
        case .singlePoint:
            return applyGraftSinglePoint(polygons, targetIdx: targetIdx, params: params, cycleBase: cycleBase, strength: strength, customPrimitives: customPrimitives)
        case .partialEdge:
            return applyGraftPartialEdge(polygons, targetIdx: targetIdx, params: params, cycleBase: cycleBase, strength: strength, customPrimitives: customPrimitives)
        }
    }

    /// `.wholeEdge` attachment (§4.4.8.3 step 2): generates one Graft
    /// primitive (`GraftEngine.generatePrimitive`), then rigid-places it so one
    /// of its own edge sites lands exactly on the target polygon's chosen edge,
    /// reusing `AssemblyFulgurationEngine.place` directly rather than
    /// re-deriving the placement math. A rolled primitive with no edge-type
    /// attachment site (`n≤2`, a bare line — only point sites) is skipped for
    /// this generation, a no-op identical in shape to the existing "nothing
    /// eligible" guards elsewhere in this file; `.singlePoint` attachment
    /// below is what makes those primitives placeable too.
    private static func applyGraftWholeEdge(
        _ polygons: [Polygon2D],
        targetIdx:  Int,
        params:     EvolutionParams,
        cycleBase:  Int,
        strength:   Double,
        customPrimitives: [String: Polygon2D] = [:]
    ) -> [Polygon2D] {
        let polygon  = polygons[targetIdx]
        let segCount = polygon.points.count / 4
        guard segCount > 0 else { return polygons }

        let eligibleSegs = eligibleSegments(of: polygon, selector: params.directionalSelector)
        guard !eligibleSegs.isEmpty else { return polygons }

        let graftSeed = params.generationSeed &+ graftSeedSalt

        let segRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 0)
        let segIdx  = eligibleSegs[min(eligibleSegs.count - 1, Int(segRoll * Double(eligibleSegs.count)))]

        let base = segIdx * 4
        let a0 = polygon.points[base]
        let a1 = polygon.points[base + 3]
        let edgeVector = a1 - a0
        let edgeLength = edgeVector.length
        guard edgeLength > 1e-9 else { return polygons }
        let direction = Vector2D(x: edgeVector.x / edgeLength, y: edgeVector.y / edgeLength)
        // cycleBase+8 on graftSeed — free on every attachment mode (wholeEdge only
        // uses 0-5; singlePoint/partialEdge's own mode-specific rolls use 6/7).
        let outward = openCurveSafeOutward(of: polygon, segIdx: segIdx, seed: graftSeed, cycle: cycleBase + 8)
        guard outward != .zero else { return polygons }
        let mid = Vector2D(x: (a0.x + a1.x) / 2, y: (a0.y + a1.y) / 2)
        let targetSite = AttachmentSite(point: mid, direction: direction, outward: outward, length: edgeLength)

        // Own small namespace on graftSeed, distinct from GraftEngine's own
        // rollBase+0/1/2 (sides/distortionX/distortionY) below.
        let mirrorRoll     = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 1)
        let sourceSiteRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 2)

        let generated = GraftEngine.generatePrimitive(seed: graftSeed, rollBase: cycleBase + 3, params: params, customPrimitives: customPrimitives)
        let piece = generated.piece
        let pieceSites = AttachmentSiteExtractor.sites(of: piece)
        // §4.4.8.3: only a piece exposing at least one edge-type site (`.line`
        // n≥3, or a custom `.spline` prototype, 2026-07-12) has something
        // `.wholeEdge` can match a parent edge onto; `.openSpline` (n≤2, a bare
        // line, or a custom open-curve prototype) exposes only point-type
        // endpoint sites (`length == nil`), which `.wholeEdge` can't use.
        // Checking site *content* rather than `piece.type` directly is what
        // lets a custom `.spline` shape become eligible here without this
        // guard needing to know about `graftPrimitiveSource` at all.
        guard pieceSites.contains(where: { $0.length != nil }) else { return polygons }
        let sourceSiteIdx = min(pieceSites.count - 1, Int(sourceSiteRoll * Double(pieceSites.count)))
        let sourceSite = pieceSites[sourceSiteIdx]

        let mirror = mirrorRoll < 0.5
        let placed = AssemblyFulgurationEngine.place(
            piece, sourceSite: sourceSite, onto: targetSite,
            mirror: mirror, edgeMatching: params.graftEdgeMatching
        )
        let detailed = applyGraftEdgeDetailing(
            placed, rootSiteIdx: sourceSiteIdx, graftSeed: graftSeed, cycleBase: cycleBase, params: params
        )
        let revealed = applyRevealScale(detailed, anchor: targetSite.point, strength: strength)

        var result = polygons
        result.append(revealed)
        return result
    }

    /// `.singlePoint` attachment (§4.4.8.3 step 3): only one coordinate is
    /// shared, so unlike `.wholeEdge` the target `AttachmentSite`'s `outward`
    /// isn't the edge's own natural normal — it's that normal rotated by an
    /// RPSR-sampled `graftDepartureAngleMin/Max`, leaving departure direction
    /// free. `length: nil` (a point, not an edge) makes `.matchLength`
    /// naturally a no-op (see `AttachmentSite`'s own doc comment), so
    /// `AssemblyFulgurationEngine.place` is reused completely unmodified — the
    /// only thing that differs from `.wholeEdge` is how `targetSite` itself is
    /// built. Unlike `.wholeEdge`, every rolled primitive is placeable here
    /// (point-type sites work as well as edge-type ones), so there's no `n≤2`
    /// skip.
    private static func applyGraftSinglePoint(
        _ polygons: [Polygon2D],
        targetIdx:  Int,
        params:     EvolutionParams,
        cycleBase:  Int,
        strength:   Double,
        customPrimitives: [String: Polygon2D] = [:]
    ) -> [Polygon2D] {
        var polygon  = polygons[targetIdx]
        let segCount = polygon.points.count / 4
        guard segCount > 0 else { return polygons }

        let eligibleSegs = eligibleSegments(of: polygon, selector: params.directionalSelector)
        guard !eligibleSegs.isEmpty else { return polygons }

        let graftSeed = params.generationSeed &+ graftSeedSalt

        let segRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 0)
        let segIdx  = eligibleSegs[min(eligibleSegs.count - 1, Int(segRoll * Double(eligibleSegs.count)))]

        let base = segIdx * 4
        let a0 = polygon.points[base]
        let a1 = polygon.points[base + 3]
        let edgeVector = a1 - a0
        let edgeLength = edgeVector.length
        guard edgeLength > 1e-9 else { return polygons }
        // cycleBase+8 on graftSeed — free alongside this mode's own 6/7 (departure
        // angle / newlyInsertedPoint split position).
        let baseNormal = openCurveSafeOutward(of: polygon, segIdx: segIdx, seed: graftSeed, cycle: cycleBase + 8)
        guard baseNormal != .zero else { return polygons }
        let tangent = Vector2D(x: edgeVector.x / edgeLength, y: edgeVector.y / edgeLength)

        // §4.4.8.3: `.existingVertex` touches nothing on the parent — the
        // segment's own start anchor is the attachment point. `.newlyInsertedPoint`
        // splits the edge first (undisplaced — no bulge/pinch, those are
        // Split-operator-specific extras this doesn't need), reusing
        // `splitPositionMin/Max` directly rather than a parallel field, per
        // §4.4.8.3's own note that this "matches Split's existing behavior."
        let anchorPoint: Vector2D
        switch params.graftPointSource {
        case .existingVertex:
            anchorPoint = a0
        case .newlyInsertedPoint:
            let posLo = min(params.splitPositionMin, params.splitPositionMax)
            let posHi = max(params.splitPositionMin, params.splitPositionMax)
            let posRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 7)
            let splitT = max(0.05, min(0.95, posLo + posRoll * (posHi - posLo)))
            let seg = Array(polygon.points[base..<(base + 4)])
            let (left, right) = BezierMath.split(seg: seg, t: splitT)
            let splitPt = left[3]  // == right[0]
            var newPoints = polygon.points
            newPoints.replaceSubrange(base..<(base + 4), with: [
                left[0], left[1], left[2], splitPt,
                splitPt, right[1], right[2], right[3]
            ])
            polygon.points = newPoints
            anchorPoint = splitPt
        }

        // Departure direction: the edge's own outward normal, rotated by an
        // RPSR-sampled angle — 0–0 (default) always departs exactly outward,
        // matching Split's own undeviated default displacement direction.
        let angleLo = min(params.graftDepartureAngleMin, params.graftDepartureAngleMax)
        let angleHi = max(params.graftDepartureAngleMin, params.graftDepartureAngleMax)
        let angleRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 6)
        let angle = angleLo + angleRoll * (angleHi - angleLo)
        let departureDir = baseNormal.rotated(by: angle)

        let targetSite = AttachmentSite(point: anchorPoint, direction: tangent, outward: departureDir, length: nil)

        // Same roll-slot numbering as applyGraftWholeEdge — safe, see the
        // dispatcher's own comment on why the two never collide.
        let mirrorRoll     = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 1)
        let sourceSiteRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 2)

        let generated = GraftEngine.generatePrimitive(seed: graftSeed, rollBase: cycleBase + 3, params: params, customPrimitives: customPrimitives)
        let piece = generated.piece

        let pieceSites = AttachmentSiteExtractor.sites(of: piece)
        guard !pieceSites.isEmpty else { return polygons }
        let sourceSiteIdx = min(pieceSites.count - 1, Int(sourceSiteRoll * Double(pieceSites.count)))
        let sourceSite = pieceSites[sourceSiteIdx]

        let mirror = mirrorRoll < 0.5
        let placed = AssemblyFulgurationEngine.place(
            piece, sourceSite: sourceSite, onto: targetSite,
            mirror: mirror, edgeMatching: params.graftEdgeMatching
        )
        // Only an edge-type source site (a `.line` n-gon or a custom `.spline`
        // prototype, 2026-07-12) has a whole edge that is "the root" to
        // exclude; a bare endpoint site (`.openSpline`, n≤2 or a custom
        // open-curve prototype, `length == nil`) has no edge needing exclusion
        // from curvature/articulation. Checked via the site itself, not
        // `piece.type`, for the same reason as the `.wholeEdge`/`.partialEdge`
        // guards above.
        let rootSiteIdx = sourceSite.length != nil ? sourceSiteIdx : nil
        let detailed = applyGraftEdgeDetailing(
            placed, rootSiteIdx: rootSiteIdx, graftSeed: graftSeed, cycleBase: cycleBase, params: params
        )
        let revealed = applyRevealScale(detailed, anchor: targetSite.point, strength: strength)

        var result = polygons
        result[targetIdx] = polygon
        result.append(revealed)
        return result
    }

    /// `.partialEdge` attachment (§4.4.8.3 step 4): like `.wholeEdge`, the
    /// primitive's chosen edge site is matched exactly onto a target
    /// `AttachmentSite` — the only difference is that site now spans a
    /// sub-portion of the parent edge (`graftPartialPositionMin/Max` for
    /// where the span starts, `graftPartialSpanMin/Max` for how much of the
    /// *remaining* length it covers) rather than the edge's full length.
    /// Non-destructive to the parent, same as `.wholeEdge` — the sub-span is
    /// only ever used to compute `targetSite`, never written back into the
    /// parent's own points. Reuses the same `n≤2` edge-type-site requirement
    /// `.wholeEdge` has, for the same reason: a bare line (point sites only)
    /// has nothing to match a sub-edge onto.
    private static func applyGraftPartialEdge(
        _ polygons: [Polygon2D],
        targetIdx:  Int,
        params:     EvolutionParams,
        cycleBase:  Int,
        strength:   Double,
        customPrimitives: [String: Polygon2D] = [:]
    ) -> [Polygon2D] {
        let polygon  = polygons[targetIdx]
        let segCount = polygon.points.count / 4
        guard segCount > 0 else { return polygons }

        let eligibleSegs = eligibleSegments(of: polygon, selector: params.directionalSelector)
        guard !eligibleSegs.isEmpty else { return polygons }

        let graftSeed = params.generationSeed &+ graftSeedSalt

        let segRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 0)
        let segIdx  = eligibleSegs[min(eligibleSegs.count - 1, Int(segRoll * Double(eligibleSegs.count)))]

        let base = segIdx * 4
        let seg = Array(polygon.points[base..<(base + 4)])
        // cycleBase+8 on graftSeed — free alongside this mode's own 6/7 (partial
        // span position/span).
        let outward = openCurveSafeOutward(of: polygon, segIdx: segIdx, seed: graftSeed, cycle: cycleBase + 8)
        guard outward != .zero else { return polygons }

        // Sub-span of the parent edge: starts at t_start (own field, not
        // clamped to [0.05, 0.95] like Split's — there's no parent-topology
        // zero-length risk here since nothing is written back to the parent),
        // covers `span` of the *remaining* length from t_start to the edge's
        // own end. Default 0–0 / 1–1 reproduces `.wholeEdge`'s full span.
        let posLo = min(params.graftPartialPositionMin, params.graftPartialPositionMax)
        let posHi = max(params.graftPartialPositionMin, params.graftPartialPositionMax)
        let posRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 6)
        let tStart = max(0.0, min(1.0, posLo + posRoll * (posHi - posLo)))

        let spanLo = min(params.graftPartialSpanMin, params.graftPartialSpanMax)
        let spanHi = max(params.graftPartialSpanMin, params.graftPartialSpanMax)
        let spanRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 7)
        let span = max(0.0, min(1.0, spanLo + spanRoll * (spanHi - spanLo)))
        let tEnd = max(tStart, min(1.0, tStart + span * (1.0 - tStart)))

        let subStart = BezierMath.point(seg: seg, t: tStart)
        let subEnd   = BezierMath.point(seg: seg, t: tEnd)
        let subVector = subEnd - subStart
        let subLength = subVector.length
        guard subLength > 1e-9 else { return polygons }
        let direction = Vector2D(x: subVector.x / subLength, y: subVector.y / subLength)
        let mid = Vector2D(x: (subStart.x + subEnd.x) / 2, y: (subStart.y + subEnd.y) / 2)
        let targetSite = AttachmentSite(point: mid, direction: direction, outward: outward, length: subLength)

        let mirrorRoll     = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 1)
        let sourceSiteRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 2)

        let generated = GraftEngine.generatePrimitive(seed: graftSeed, rollBase: cycleBase + 3, params: params, customPrimitives: customPrimitives)
        let piece = generated.piece
        let pieceSites = AttachmentSiteExtractor.sites(of: piece)
        // Same site-content check as `.wholeEdge` above, not `piece.type ==
        // .line` — see its comment.
        guard pieceSites.contains(where: { $0.length != nil }) else { return polygons }
        let sourceSiteIdx = min(pieceSites.count - 1, Int(sourceSiteRoll * Double(pieceSites.count)))
        let sourceSite = pieceSites[sourceSiteIdx]

        let mirror = mirrorRoll < 0.5
        let placed = AssemblyFulgurationEngine.place(
            piece, sourceSite: sourceSite, onto: targetSite,
            mirror: mirror, edgeMatching: params.graftEdgeMatching
        )
        let detailed = applyGraftEdgeDetailing(
            placed, rootSiteIdx: sourceSiteIdx, graftSeed: graftSeed, cycleBase: cycleBase, params: params
        )
        let revealed = applyRevealScale(detailed, anchor: targetSite.point, strength: strength)

        var result = polygons
        result.append(revealed)
        return result
    }

    /// Tweens a fully-placed-and-detailed graft's reveal by scaling it toward
    /// `anchor` (`targetSite.point` — the exact coordinate `place()` already
    /// guarantees the piece is coincident with the parent at, regardless of
    /// attachment mode) as `strength` climbs from 0 to 1, mirroring how Extrude/
    /// Split already scale their own distance/displacement by `strength` (see
    /// `process(polygons:params:phase:)`) — Graft previously ignored `strength`
    /// entirely and popped in fully every time, a known gap from §4.4.8's own
    /// build order, closed here. 1.0 (an already-fully-revealed generation) is a
    /// no-op, so this has zero effect outside an active reveal tween. Applied as
    /// the very last step, after curvature/articulation, so detail geometry (bow
    /// amounts, joint displacement) is computed against the piece's true final
    /// size and then grows in step with everything else, rather than needing its
    /// own separate strength-awareness.
    private static func applyRevealScale(_ piece: Polygon2D, anchor: Vector2D, strength: Double) -> Polygon2D {
        guard strength < 1.0 - 1e-9 else { return piece }
        let s = max(0.0, strength)
        let scaledPoints = piece.points.map { p in
            Vector2D(x: anchor.x + (p.x - anchor.x) * s, y: anchor.y + (p.y - anchor.y) * s)
        }
        return Polygon2D(points: scaledPoints, type: piece.type,
                         pressures: piece.pressures, pressureProfiles: piece.pressureProfiles,
                         visible: piece.visible)
    }

    // MARK: - Edge curvature and articulation (§4.4.8.4)

    /// A distinct salt for curvature/articulation rolls, kept separate from
    /// `graftSeedSalt`'s own `cycleBase + 0...7` usage — that range means
    /// different things per attachment mode (`.wholeEdge` only uses 0-5;
    /// `.singlePoint`/`.partialEdge` also use 6/7 for their own mode-specific
    /// rolls) — so edge-detailing never has to reason about which slots a
    /// given mode already claimed; it gets its own independent hash stream.
    private static let graftDetailSeedSalt = 471_338_509

    /// Applies §4.4.8.4's curvature/articulation to every "free" edge of
    /// `placed` — every edge except `rootSiteIdx` (the specific index, into
    /// the pre-placement piece's own `AttachmentSiteExtractor.sites(of:)`
    /// list, of the site that was matched to the parent — `nil` when that
    /// site was point-type, which protects nothing extra since curvature only
    /// moves control points and articulation only inserts new interior
    /// points; a raw anchor is never itself relocated by either).
    ///
    /// A no-op — `placed` returned completely unchanged, still `.line`- or
    /// `.openSpline`-type exactly as `place()` produced it — unless at least
    /// one of curvature/articulation is actually configured, so every
    /// wholeEdge/singlePoint/partialEdge test using untouched defaults is
    /// unaffected; this only fires for presets that opt in.
    private static func applyGraftEdgeDetailing(
        _ placed:    Polygon2D,
        rootSiteIdx: Int?,
        graftSeed:   Int,
        cycleBase:   Int,
        params:      EvolutionParams
    ) -> Polygon2D {
        let curvatureOn = params.graftEdgeCurvatureProbability > 0
            && (params.graftEdgeCurvatureAmountMin != 0 || params.graftEdgeCurvatureAmountMax != 0)
        let articulationOn = max(params.graftArticulationCountMin, params.graftArticulationCountMax) > 0
            && (params.graftArticulationAmountMin != 0 || params.graftArticulationAmountMax != 0)
        guard curvatureOn || articulationOn else { return placed }

        // `.line` (closed, raw-vertex) pieces need converting to per-segment
        // control points before any one edge can be individually detailed;
        // `.openSpline` pieces (the `n≤2` line primitive) and `.spline` pieces
        // (a custom closed-shape prototype, 2026-07-12) are already
        // spline-encoded — `splineEdgeSites`' site ordering matches `.spline`'s
        // own segment ordering exactly, so `rootSiteIdx` (a site index) lines
        // up with `segIdx` (a segment index) here with no extra bookkeeping.
        let spline: Polygon2D
        switch placed.type {
        case .line:
            spline = Polygon2D(points: BezierMath.lineToSplinePoints(placed.points), type: .spline,
                               pressures: placed.pressures, pressureProfiles: placed.pressureProfiles,
                               visible: placed.visible)
        case .openSpline, .spline:
            spline = placed
        default:
            return placed
        }

        let segCount = spline.points.count / 4
        guard segCount > 0 else { return placed }

        let detailSeed = graftSeed &+ graftDetailSeedSalt
        var outputSegments: [[Vector2D]] = []
        outputSegments.reserveCapacity(segCount)

        for segIdx in 0..<segCount {
            let base = segIdx * 4
            let seg = Array(spline.points[base..<(base + 4)])
            guard segIdx != rootSiteIdx else {
                outputSegments.append(seg)
                continue
            }

            // Distinct per-edge namespace, same "salted seed" convention
            // `applyExtrude`'s per-edge rolls already use — safe regardless of
            // how many edges this piece has.
            let edgeSeed = detailSeed &+ (segIdx &+ 1) &* 2_971_215_073

            var jointCount = 0
            if articulationOn {
                let countLo = min(params.graftArticulationCountMin, params.graftArticulationCountMax)
                let countHi = max(params.graftArticulationCountMin, params.graftArticulationCountMax)
                let countRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 0)
                jointCount = max(0, countLo + Int(countRoll * Double(countHi - countLo + 1)))
            }

            // Articulation first — splits this edge into `jointCount + 1`
            // straight sub-segments with displaced interior joints; curvature
            // is then independently rolled per resulting sub-segment below,
            // so an articulated edge's pieces can each end up curved too.
            let subSegments = jointCount > 0
                ? articulatedSubSegments(of: seg, jointCount: jointCount, edgeSeed: edgeSeed, params: params)
                : [seg]

            for (subIdx, subSeg) in subSegments.enumerated() {
                outputSegments.append(curvedSegment(subSeg, edgeSeed: edgeSeed, subIdx: subIdx, params: params))
            }
        }

        let outputPoints = outputSegments.flatMap { $0 }
        return Polygon2D(points: outputPoints, type: spline.type,
                         pressures: spline.pressures, pressureProfiles: spline.pressureProfiles,
                         visible: spline.visible)
    }

    /// Subdivides one straight edge into `jointCount + 1` straight sub-segments,
    /// each interior joint sampled at an even `t` along the *original* edge
    /// (`BezierMath.point`, not a naive linear split — consistent with how
    /// `CurveRefinementEngine` samples insertion points) then displaced
    /// perpendicular to the edge's own chord direction, by `amount * edgeLength`
    /// (same edge-relative convention `curvedSegment` below uses for its own
    /// `bow`, rather than an absolute canvas-scale magnitude) — so articulation
    /// shrinks along with a piece scaled down via `graftScaleMin/Max`, instead
    /// of staying a fixed size regardless of how small the piece itself is.
    /// `.jitter`: independent RPSR sign and magnitude per joint. `.zigzag`: sign
    /// alternates deterministically joint-to-joint, magnitude still
    /// RPSR-sampled — the "zig zag" case from the original proposal. Both
    /// original endpoints (`seg[0]`/`seg[3]`) are carried through completely
    /// untouched.
    private static func articulatedSubSegments(
        of seg:     [Vector2D],
        jointCount: Int,
        edgeSeed:   Int,
        params:     EvolutionParams
    ) -> [[Vector2D]] {
        let a0 = seg[0], a1 = seg[3]
        let dx = a1.x - a0.x, dy = a1.y - a0.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 1e-9 else { return [seg] }
        let perp = Vector2D(x: -dy / len, y: dx / len)

        let amtLo = min(params.graftArticulationAmountMin, params.graftArticulationAmountMax)
        let amtHi = max(params.graftArticulationAmountMin, params.graftArticulationAmountMax)

        var anchors: [Vector2D] = [a0]
        for j in 1...jointCount {
            let t = Double(j) / Double(jointCount + 1)
            let basePos = BezierMath.point(seg: seg, t: t)
            let jointSeed = edgeSeed &+ (j &+ 1) &* 3_571_428_667

            let magRoll = SubdivisionEngine.centreHash(seed: jointSeed, cycle: 1)
            let magnitude = (amtLo + magRoll * (amtHi - amtLo)) * len
            let sign: Double
            switch params.graftArticulationPattern {
            case .jitter:
                let signRoll = SubdivisionEngine.centreHash(seed: jointSeed, cycle: 0)
                sign = signRoll < 0.5 ? -1.0 : 1.0
            case .zigzag:
                sign = (j % 2 == 1) ? 1.0 : -1.0
            }

            anchors.append(basePos + perp * (sign * magnitude))
        }
        anchors.append(a1)

        var segments: [[Vector2D]] = []
        segments.reserveCapacity(anchors.count - 1)
        for i in 0..<(anchors.count - 1) {
            let p0 = anchors[i], p3 = anchors[i + 1]
            segments.append([p0, Vector2D.lerp(p0, p3, t: 1.0 / 3.0), Vector2D.lerp(p0, p3, t: 2.0 / 3.0), p3])
        }
        return segments
    }

    /// RPSR chance (`graftEdgeCurvatureProbability`) of bowing one straight
    /// sub-segment's control points outward from its own chord — same
    /// `bow = amount * edgeLength` convention `ExtensionEngine.extrudeSegment`
    /// already uses for Extrude's outer face (a new call site, not new math).
    private static func curvedSegment(
        _ seg:     [Vector2D],
        edgeSeed:  Int,
        subIdx:    Int,
        params:    EvolutionParams
    ) -> [Vector2D] {
        guard params.graftEdgeCurvatureProbability > 0 else { return seg }
        let subSeed = edgeSeed &+ (subIdx &+ 1) &* 3_968_546_921
        let probRoll = SubdivisionEngine.centreHash(seed: subSeed, cycle: 0)
        guard probRoll < params.graftEdgeCurvatureProbability else { return seg }

        let a0 = seg[0], a1 = seg[3]
        let dx = a1.x - a0.x, dy = a1.y - a0.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 1e-9 else { return seg }
        let normal = Vector2D(x: -dy / len, y: dx / len)

        let amtLo = min(params.graftEdgeCurvatureAmountMin, params.graftEdgeCurvatureAmountMax)
        let amtHi = max(params.graftEdgeCurvatureAmountMin, params.graftEdgeCurvatureAmountMax)
        let amtRoll = SubdivisionEngine.centreHash(seed: subSeed, cycle: 1)
        let amount = amtLo + amtRoll * (amtHi - amtLo)
        let bow = amount * len

        let cp1 = Vector2D.lerp(a0, a1, t: 1.0 / 3.0) + normal * bow
        let cp2 = Vector2D.lerp(a0, a1, t: 2.0 / 3.0) + normal * bow
        return [a0, cp1, cp2, a1]
    }
}

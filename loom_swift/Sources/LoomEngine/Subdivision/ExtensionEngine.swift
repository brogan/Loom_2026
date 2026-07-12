import Foundation

public enum ExtensionEngine {

    private static let maxBranchesPerPolygon = 256

    public static func process(
        polygons:      [Polygon2D],
        paramSet:      [ExtensionParams],
        elapsedFrames: Double = 0,
        targetFPS:     Double = 24,
        spriteIndex:   Int    = 0
    ) -> [Polygon2D] {
        let active = paramSet.filter { $0.enabled }
        guard !active.isEmpty else { return polygons }

        var result = polygons
        for params in active {
            switch params.operationType {
            case .branch:
                let angle = DriverEvaluator.evaluate(params.branchAngle,
                                                      globalElapsed: elapsedFrames,
                                                      targetFPS: targetFPS,
                                                      spriteIndex: spriteIndex)
                // Only meaningful for `.line` geometry, but resolved unconditionally —
                // same cost as `angle` above, and keeps this a plain per-generation
                // evaluation rather than a conditional one. Driven (not a constant
                // `Double`) so a `.line` branch can unfold gradually: a ramp/oscillator
                // here grows the line from 0 to full length over time rather than
                // popping in at a fixed size every frame.
                let lineLength = DriverEvaluator.evaluate(params.branchLineLength,
                                                           globalElapsed: elapsedFrames,
                                                           targetFPS: targetFPS,
                                                           spriteIndex: spriteIndex)
                let maxDepth = max(1, min(8, params.branchDepth))
                // Reveals depth levels one at a time (2026-07-12) rather than the
                // whole tree popping in at once — same integer-plus-fractional
                // shape `GenerationalEvolutionEngine`'s `generationPhase` uses.
                // Disabled (default): falls back to the static `maxDepth`, i.e.
                // every level fully built, unchanged from before this existed.
                let structurePhase: Double
                if params.structurePhase.enabled {
                    let raw = DriverEvaluator.evaluate(params.structurePhase,
                                                        globalElapsed: elapsedFrames,
                                                        targetFPS: targetFPS,
                                                        spriteIndex: spriteIndex)
                    structurePhase = max(0, min(Double(maxDepth), raw))
                } else {
                    structurePhase = Double(maxDepth)
                }
                let fullDepth = Int(structurePhase)
                let partialDepth = structurePhase - Double(fullDepth)

                var additions: [Polygon2D] = []
                for polygon in polygons where polygon.type == .openSpline {
                    var budget = maxBranchesPerPolygon
                    let branches = branchPolygon(
                        polygon,
                        root:              polygon,
                        params:            params,
                        resolvedAngleDeg:  angle,
                        resolvedLineLength: lineLength,
                        cumulativeScale:   1.0,
                        depthIndex:        0,
                        maxDepth:          maxDepth,
                        fullDepth:         fullDepth,
                        partialDepth:      partialDepth,
                        budget:            &budget
                    )
                    additions.append(contentsOf: branches)
                }
                result.append(contentsOf: additions)

            case .extrude:
                let distance = DriverEvaluator.evaluate(params.extrusionDistance,
                                                         globalElapsed: elapsedFrames,
                                                         targetFPS: targetFPS,
                                                         spriteIndex: spriteIndex)
                // Reveals generations one at a time per edge (2026-07-12), same
                // convention as Branch above. Clamped to the engine's own hard
                // cap of 6 generations; `extrudePolygon` further clamps per edge
                // to that edge's own rolled `extrusionGenerationsMin/Max` count,
                // so a shorter tower finishes revealing sooner than a taller one.
                // Disabled (default): every edge's rolled generation count is
                // fully built immediately, unchanged from before this existed.
                let structurePhase: Double
                if params.structurePhase.enabled {
                    let raw = DriverEvaluator.evaluate(params.structurePhase,
                                                        globalElapsed: elapsedFrames,
                                                        targetFPS: targetFPS,
                                                        spriteIndex: spriteIndex)
                    structurePhase = max(0, min(6.0, raw))
                } else {
                    structurePhase = 6.0
                }
                var additions: [Polygon2D] = []
                for polygon in polygons
                where polygon.type == .spline
                   || (params.extrudeOpenCurves && polygon.type == .openSpline) {
                    additions.append(contentsOf: extrudePolygon(polygon, params: params, distance: distance,
                                                                 structurePhase: structurePhase))
                }
                result.append(contentsOf: additions)
            }
        }
        return result
    }

    // MARK: - Branch

    /// `depthIndex` is 0-based: how many levels deep this call is generating
    /// (0 = spawned directly from the root curve). `maxDepth` is the
    /// configured cap (`branchDepth`, clamped 1–8); `fullDepth`/`partialDepth`
    /// come from `structurePhase` — levels `< fullDepth` are fully built
    /// (`strength` 1.0), level `== fullDepth` is the currently-growing one
    /// (`strength` = `partialDepth`), anything beyond doesn't exist yet.
    private static func branchPolygon(
        _ polygon:          Polygon2D,
        root:               Polygon2D,
        params:             ExtensionParams,
        resolvedAngleDeg:   Double,
        resolvedLineLength: Double,
        cumulativeScale:    Double,
        depthIndex:         Int,
        maxDepth:           Int,
        fullDepth:          Int,
        partialDepth:       Double,
        budget:             inout Int
    ) -> [Polygon2D] {
        let segCount = polygon.points.count / 4
        guard segCount > 0, depthIndex < maxDepth, depthIndex <= fullDepth, budget > 0 else { return [] }
        guard root.points.count >= 4 else { return [] }
        let strength = depthIndex < fullDepth ? 1.0 : partialDepth
        guard strength > 1e-9 else { return [] }

        let rootStartAngle = atan2(root.points[1].y - root.points[0].y,
                                   root.points[1].x - root.points[0].x)

        let startPos = polygon.points[0]
        let startTangAngle = atan2(polygon.points[1].y - polygon.points[0].y,
                                   polygon.points[1].x - polygon.points[0].x)

        let endPos   = polygon.points[(segCount - 1) * 4 + 3]
        let endCP    = polygon.points[(segCount - 1) * 4 + 2]
        let endTangAngle = atan2(endPos.y - endCP.y, endPos.x - endCP.x)

        // `.endpointsOnly` (original behavior): just the two ends, seeds 0/1
        // exactly as before — fully backward compatible. `.anyAnchor` widens
        // this to every anchor point (every 4th point, `0...segCount`):
        // interior anchors reuse the same "outgoing tangent" formula as the
        // start endpoint above, applied to their own segment; the final
        // anchor reuses the existing end-of-curve formula unchanged. The
        // 256-branch budget already guards against the extra density, so no
        // new cap is needed.
        let anchors: [(pos: Vector2D, tangAngle: Double, seed: Int)]
        switch params.branchAnchorScope {
        case .endpointsOnly:
            anchors = [(startPos, startTangAngle, 0), (endPos, endTangAngle, 1)]
        case .anyAnchor:
            var list: [(pos: Vector2D, tangAngle: Double, seed: Int)] = []
            for i in 0..<segCount {
                let a0  = polygon.points[i * 4]
                let cp1 = polygon.points[i * 4 + 1]
                list.append((a0, atan2(cp1.y - a0.y, cp1.x - a0.x), i))
            }
            list.append((endPos, endTangAngle, segCount))
            anchors = list
        }

        let nextScale = cumulativeScale * params.branchScaleRatio
        let count     = max(1, params.branchCount)
        var branches: [Polygon2D] = []

        outer: for ep in anchors {
            for i in 0..<count {
                guard budget > 0 else { break outer }

                // `maxDepth - depthIndex` reproduces the old "remaining depth
                // countdown" value bit-for-bit (the seed salt this formula always
                // used), so existing saved projects' jitter/probability rolls are
                // completely unaffected by switching the recursion itself over to
                // a 0-based depth index for the new structurePhase reveal logic.
                let seedBase = params.branchSeed ^ ep.seed * 997 ^ i * 1009 ^ (maxDepth - depthIndex) * 1013

                if params.branchProbability < 1.0 - 1e-9 {
                    let roll = SubdivisionEngine.centreHash(seed: seedBase, cycle: 0)
                    if roll > params.branchProbability { continue }
                }

                let spreadFrac: Double = count == 1 ? 0.0
                    : (2.0 * Double(i) / Double(count - 1) - 1.0)
                let jitter: Double
                if params.branchAngleJitter > 0 {
                    jitter = (SubdivisionEngine.centreHash(seed: seedBase, cycle: 1) * 2 - 1)
                           * params.branchAngleJitter
                } else {
                    jitter = 0.0
                }

                let angleDeg = (count == 1 ? resolvedAngleDeg
                                           : resolvedAngleDeg * spreadFrac) + jitter
                let targetAngle = ep.tangAngle + angleDeg * (.pi / 180.0)

                // `structurePhase`'s reveal (2026-07-12): the currently-growing
                // level (`strength < 1`) uses a proportionally smaller
                // scale/length — since both `transformBranch` and `lineBranch`
                // already pivot around `ep.pos` regardless of scale, this alone
                // makes the branch visibly grow from its anchor point as
                // `strength` climbs to 1, the same trick Generational
                // Evolution's own Extrude operator already uses (scaling
                // `distance` by `strength`) rather than a separate post-hoc
                // anchor-relative tween.
                let branch: Polygon2D
                switch params.branchGeometry {
                case .rootCopy:
                    let rotation = targetAngle - rootStartAngle
                    branch = transformBranch(root, to: ep.pos, rotation: rotation, scale: nextScale * strength)
                case .line:
                    branch = lineBranch(
                        from: ep.pos, angle: targetAngle, length: nextScale * resolvedLineLength * strength,
                        curvatureAmountMin: params.branchCurvatureAmountMin,
                        curvatureAmountMax: params.branchCurvatureAmountMax,
                        seed: seedBase
                    )
                }
                branches.append(branch)
                budget -= 1

                if depthIndex + 1 < maxDepth {
                    let subs = branchPolygon(
                        branch, root: root, params: params,
                        resolvedAngleDeg:   resolvedAngleDeg,
                        resolvedLineLength: resolvedLineLength,
                        cumulativeScale:    nextScale,
                        depthIndex:         depthIndex + 1,
                        maxDepth:           maxDepth,
                        fullDepth:          fullDepth,
                        partialDepth:       partialDepth,
                        budget:             &budget
                    )
                    branches.append(contentsOf: subs)
                }
            }
        }
        return branches
    }

    /// Generates a `.line`-geometry branch: a single straight (or bowed) segment
    /// from `origin` toward `angle`, `length` long — not a copy of `root`.
    /// Curvature bows the segment's control points perpendicular to its own
    /// chord, `bow = amount * length` (same convention as `extrusionCurvature`/
    /// Graft's `graftEdgeCurvatureAmountMin/Max`). `curvatureAmountMin ==
    /// curvatureAmountMax` gives a fixed bow with no RNG roll at all — the
    /// degenerate case that also covers "no curvature" at 0–0 — `curvatureAmountMin
    /// != curvatureAmountMax` RPSR-samples the bow off `seed` (the same per-branch
    /// seed already used for jitter/probability, so this needs no extra seed
    /// plumbing).
    private static func lineBranch(
        from origin:           Vector2D,
        angle:                 Double,
        length:                Double,
        curvatureAmountMin:    Double,
        curvatureAmountMax:    Double,
        seed:                  Int
    ) -> Polygon2D {
        let dir = Vector2D(x: cos(angle), y: sin(angle))
        let end = Vector2D(x: origin.x + dir.x * length, y: origin.y + dir.y * length)
        let normal = Vector2D(x: -dir.y, y: dir.x)

        let amtLo = min(curvatureAmountMin, curvatureAmountMax)
        let amtHi = max(curvatureAmountMin, curvatureAmountMax)
        let bowAmount: Double
        if amtHi - amtLo < 1e-12 {
            bowAmount = amtLo
        } else {
            let roll = SubdivisionEngine.centreHash(seed: seed, cycle: 2)
            bowAmount = amtLo + roll * (amtHi - amtLo)
        }
        let bow = bowAmount * length

        let cp1 = Vector2D.lerp(origin, end, t: 1.0 / 3.0) + normal * bow
        let cp2 = Vector2D.lerp(origin, end, t: 2.0 / 3.0) + normal * bow

        return Polygon2D(points: [origin, cp1, cp2, end], type: .openSpline)
    }

    private static func transformBranch(
        _ root:    Polygon2D,
        to endPos: Vector2D,
        rotation:  Double,
        scale:     Double
    ) -> Polygon2D {
        let origin = root.points[0]
        let cosR = cos(rotation), sinR = sin(rotation)
        let pts = root.points.map { p -> Vector2D in
            let sx = (p.x - origin.x) * scale
            let sy = (p.y - origin.y) * scale
            return Vector2D(
                x: sx * cosR - sy * sinR + endPos.x,
                y: sx * sinR + sy * cosR + endPos.y
            )
        }
        return Polygon2D(points: pts, type: root.type, pressures: root.pressures)
    }

    // MARK: - Extrude

    private static func extrudePolygon(
        _ polygon:       Polygon2D,
        params:          ExtensionParams,
        distance:        Double,
        structurePhase:  Double
    ) -> [Polygon2D] {
        let segCount = polygon.points.count / 4
        guard segCount > 0 else { return [] }

        var segIndices: [Int]
        switch params.extrusionTarget {
        case .allEdges:    segIndices = Array(0..<segCount)
        case .longestEdge: segIndices = [longestSegmentIndex(polygon)]
        }
        if params.directionalSelector.enabled {
            segIndices = segIndices.filter { params.directionalSelector.accepts(outwardNormal(of: polygon, segIdx: $0)) }
        }

        var result: [Polygon2D] = []

        for segIdx in segIndices {
            let baseNormal = outwardNormal(of: polygon, segIdx: segIdx)
            guard baseNormal != .zero else { continue }

            // Independent per-edge rolls (2026-07-12): "towers" of varying height
            // and departure angle rather than one uniform count/direction applied
            // to every edge. Distinct salted seeds per roll, same "own namespace
            // per concern" convention used throughout this engine.
            let genSeed = params.extrusionSeed ^ (segIdx &* 2_654_435_761)
            let genLo   = min(params.extrusionGenerationsMin, params.extrusionGenerationsMax)
            let genHi   = max(params.extrusionGenerationsMin, params.extrusionGenerationsMax)
            let genRoll = SubdivisionEngine.centreHash(seed: genSeed, cycle: 0)
            let maxGenerations = max(1, min(6, genLo + Int(genRoll * Double(genHi - genLo + 1))))

            // Resolved once per edge and reused across all of that edge's own
            // generations, same as the plain outward normal already was — a
            // rotated departure direction, not just a fixed perpendicular. Most
            // useful for `extrudeOpenCurves`, where "outward" has no enclosed
            // interior to be relative to.
            let angleSeed = params.extrusionSeed ^ (segIdx &* 2_971_215_073)
            let angLo     = min(params.extrusionDepartureAngleMin, params.extrusionDepartureAngleMax)
            let angHi     = max(params.extrusionDepartureAngleMin, params.extrusionDepartureAngleMax)
            let angleDeg: Double
            if angHi - angLo < 1e-12 {
                angleDeg = angLo
            } else {
                let angleRoll = SubdivisionEngine.centreHash(seed: angleSeed, cycle: 0)
                angleDeg = angLo + angleRoll * (angHi - angLo)
            }
            let normal = baseNormal.rotated(by: angleDeg * .pi / 180.0)

            // `structurePhase`'s reveal (2026-07-12), clamped to this edge's own
            // rolled `maxGenerations` — a shorter tower finishes revealing sooner
            // than a taller one. Same integer-plus-fractional shape as Branch's
            // depth reveal above: full generations built at their normal
            // distance, the one currently-growing generation scaled by
            // `partialGen` instead — the same trick Generational Evolution's own
            // Extrude operator already uses (scaling `distance` by `strength`),
            // so the new floor visibly grows from its shared base edge rather
            // than popping in at full height.
            let edgePhase  = min(structurePhase, Double(maxGenerations))
            let fullGens   = Int(edgePhase)
            let partialGen = edgePhase - Double(fullGens)

            var currentPoly     = polygon
            var currentSegIdx   = segIdx
            var currentDistance = distance

            for generation in 0..<maxGenerations {
                let thisDistance: Double
                if generation < fullGens {
                    thisDistance = currentDistance
                } else if generation == fullGens, partialGen > 1e-9 {
                    thisDistance = currentDistance * partialGen
                } else {
                    break // this generation and beyond haven't started revealing yet
                }
                let ext = extrudeSegment(currentPoly, segIdx: currentSegIdx,
                                          distance: thisDistance, params: params,
                                          outwardNormal: normal)
                result.append(ext)
                currentPoly     = ext
                currentSegIdx   = 2  // outer face is always segment 2 in the extruded polygon
                currentDistance *= params.extrusionWidth
            }
        }
        return result
    }

    /// Extrude a single edge outward, returning the resulting 4-segment quad.
    /// Same math as the `.extrude` operation type above, exposed per-edge (rather
    /// than per-pass) so `GenerationalEvolutionEngine`'s extrude mutation operator
    /// (Specs/GeometricLifecycle.md §4.4.2) can extrude a contiguous *run* of edges
    /// as a set of neighboring quads sharing endpoints, reusing this rather than
    /// duplicating the outward-normal/bow/width math.
    static func extrudeEdge(
        _ polygon:   Polygon2D,
        segIdx:      Int,
        distance:    Double,
        width:       Double = 1.0,
        curvature:   Double = 0.0,
        distanceA0:  Double? = nil,
        distanceA1:  Double? = nil,
        direction:   Vector2D? = nil
    ) -> Polygon2D? {
        let segCount = polygon.points.count / 4
        guard segCount > 0, segIdx < segCount else { return nil }
        let normal = outwardNormal(of: polygon, segIdx: segIdx)
        guard normal != .zero else { return nil }
        let params = ExtensionParams(operationType: .extrude, extrusionWidth: width, extrusionCurvature: curvature)
        return extrudeSegment(polygon, segIdx: segIdx, distance: distance,
                               params: params, outwardNormal: direction ?? normal,
                               distanceA0: distanceA0, distanceA1: distanceA1)
    }

    private static func extrudeSegment(
        _ polygon:       Polygon2D,
        segIdx:          Int,
        distance:        Double,
        params:          ExtensionParams,
        outwardNormal:   Vector2D,
        distanceA0:      Double? = nil,
        distanceA1:      Double? = nil
    ) -> Polygon2D {
        let base = segIdx * 4
        guard base + 3 < polygon.points.count else {
            return Polygon2D(points: [], type: .spline)
        }
        let a0  = polygon.points[base]
        let cp1 = polygon.points[base + 1]
        let cp2 = polygon.points[base + 2]
        let a1  = polygon.points[base + 3]
        let nx  = outwardNormal.x, ny = outwardNormal.y
        // Per-corner distance override (GenerationalEvolutionEngine's asymmetric-
        // sides toggle, Specs/GeometricLifecycle.md §4.4.2); both default to the
        // shared `distance`, giving the original symmetric/rectangular quad.
        let dA0 = distanceA0 ?? distance
        let dA1 = distanceA1 ?? distance

        // Outer corners: width scaling around segment midpoint + normal offset
        let mx = (a0.x + a1.x) / 2, my = (a0.y + a1.y) / 2
        let w = params.extrusionWidth
        let oa0 = Vector2D(x: mx + (a0.x - mx) * w + nx * dA0,
                           y: my + (a0.y - my) * w + ny * dA0)
        let oa1 = Vector2D(x: mx + (a1.x - mx) * w + nx * dA1,
                           y: my + (a1.y - my) * w + ny * dA1)

        // Outer edge control points (oa1 → oa0 direction), bow in outward-normal direction
        let bow  = params.extrusionCurvature * sqrt((oa0.x - oa1.x) * (oa0.x - oa1.x)
                                                   + (oa0.y - oa1.y) * (oa0.y - oa1.y))
        let lp1  = Vector2D.lerp(oa1, oa0, t: 1.0 / 3.0)
        let lp2  = Vector2D.lerp(oa1, oa0, t: 2.0 / 3.0)
        let ocp1 = Vector2D(x: lp1.x + nx * bow, y: lp1.y + ny * bow)
        let ocp2 = Vector2D(x: lp2.x + nx * bow, y: lp2.y + ny * bow)

        // 4-segment closed polygon:
        // Seg 0 (inner): a0 → cp1 → cp2 → a1
        // Seg 1 (right wall): a1 → … → oa1
        // Seg 2 (outer): oa1 → ocp1 → ocp2 → oa0
        // Seg 3 (left wall): oa0 → … → a0
        let pts: [Vector2D] = [
            a0, cp1, cp2, a1,
            a1, Vector2D.lerp(a1, oa1, t: 1.0 / 3.0), Vector2D.lerp(a1, oa1, t: 2.0 / 3.0), oa1,
            oa1, ocp1, ocp2, oa0,
            oa0, Vector2D.lerp(oa0, a0, t: 1.0 / 3.0), Vector2D.lerp(oa0, a0, t: 2.0 / 3.0), a0
        ]
        return Polygon2D(points: pts, type: .spline, pressures: [])
    }

    // MARK: - Helpers

    /// Outward normal of segment `segIdx` — the edge-direction vector (segment's
    /// end anchor minus its start anchor) rotated 90°, normalized. `.zero` for a
    /// degenerate (zero-length) edge or an out-of-range index; callers should treat
    /// `.zero` as "no sensible direction, skip this edge" rather than a real
    /// direction pointing along `+x`. Shared by `extrudePolygon`, `extrudeEdge`,
    /// and `DirectionalSelector` filtering (Specs/GeometricLifecycle.md §14) —
    /// previously this exact formula was duplicated inline at each call site.
    static func outwardNormal(of polygon: Polygon2D, segIdx: Int) -> Vector2D {
        let base = segIdx * 4
        guard base >= 0, base + 3 < polygon.points.count else { return .zero }
        let a0 = polygon.points[base], a1 = polygon.points[base + 3]
        let dx = a1.x - a0.x, dy = a1.y - a0.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 1e-12 else { return .zero }
        return Vector2D(x: -dy / len, y: dx / len)
    }

    private static func longestSegmentIndex(_ polygon: Polygon2D) -> Int {
        let n = polygon.points.count / 4
        guard n > 0 else { return 0 }
        var maxSq = -1.0, best = 0
        for i in 0..<n {
            let a0 = polygon.points[i * 4], a1 = polygon.points[i * 4 + 3]
            let d = (a1.x - a0.x) * (a1.x - a0.x) + (a1.y - a0.y) * (a1.y - a0.y)
            if d > maxSq { maxSq = d; best = i }
        }
        return best
    }
}

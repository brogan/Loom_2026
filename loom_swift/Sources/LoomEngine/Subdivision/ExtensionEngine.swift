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
                var additions: [Polygon2D] = []
                for polygon in polygons where polygon.type == .openSpline {
                    var budget = maxBranchesPerPolygon
                    let branches = branchPolygon(
                        polygon,
                        root:             polygon,
                        params:           params,
                        resolvedAngleDeg: angle,
                        cumulativeScale:  1.0,
                        depth:            max(1, min(8, params.branchDepth)),
                        budget:           &budget
                    )
                    additions.append(contentsOf: branches)
                }
                result.append(contentsOf: additions)

            case .extrude:
                let distance = DriverEvaluator.evaluate(params.extrusionDistance,
                                                         globalElapsed: elapsedFrames,
                                                         targetFPS: targetFPS,
                                                         spriteIndex: spriteIndex)
                var additions: [Polygon2D] = []
                for polygon in polygons where polygon.type == .spline {
                    additions.append(contentsOf: extrudePolygon(polygon, params: params, distance: distance))
                }
                result.append(contentsOf: additions)
            }
        }
        return result
    }

    // MARK: - Branch

    private static func branchPolygon(
        _ polygon:        Polygon2D,
        root:             Polygon2D,
        params:           ExtensionParams,
        resolvedAngleDeg: Double,
        cumulativeScale:  Double,
        depth:            Int,
        budget:           inout Int
    ) -> [Polygon2D] {
        let segCount = polygon.points.count / 4
        guard segCount > 0, depth > 0, budget > 0 else { return [] }
        guard root.points.count >= 4 else { return [] }

        let rootStartAngle = atan2(root.points[1].y - root.points[0].y,
                                   root.points[1].x - root.points[0].x)

        let startPos = polygon.points[0]
        let startTangAngle = atan2(polygon.points[1].y - polygon.points[0].y,
                                   polygon.points[1].x - polygon.points[0].x)

        let endPos   = polygon.points[(segCount - 1) * 4 + 3]
        let endCP    = polygon.points[(segCount - 1) * 4 + 2]
        let endTangAngle = atan2(endPos.y - endCP.y, endPos.x - endCP.x)

        let endpoints: [(pos: Vector2D, tangAngle: Double, seed: Int)] = [
            (startPos, startTangAngle, 0),
            (endPos,   endTangAngle,   1)
        ]

        let nextScale = cumulativeScale * params.branchScaleRatio
        let count     = max(1, params.branchCount)
        var branches: [Polygon2D] = []

        outer: for ep in endpoints {
            for i in 0..<count {
                guard budget > 0 else { break outer }

                let seedBase = params.branchSeed ^ ep.seed * 997 ^ i * 1009 ^ depth * 1013

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
                let rotation    = targetAngle - rootStartAngle

                let branch = transformBranch(root, to: ep.pos, rotation: rotation, scale: nextScale)
                branches.append(branch)
                budget -= 1

                if depth > 1 {
                    let subs = branchPolygon(
                        branch, root: root, params: params,
                        resolvedAngleDeg: resolvedAngleDeg,
                        cumulativeScale:  nextScale,
                        depth:            depth - 1,
                        budget:           &budget
                    )
                    branches.append(contentsOf: subs)
                }
            }
        }
        return branches
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
        _ polygon: Polygon2D,
        params:    ExtensionParams,
        distance:  Double
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

        let maxGenerations = max(1, min(6, params.extrusionGenerations))
        var result: [Polygon2D] = []

        for segIdx in segIndices {
            let normal = outwardNormal(of: polygon, segIdx: segIdx)
            guard normal != .zero else { continue }

            var currentPoly     = polygon
            var currentSegIdx   = segIdx
            var currentDistance = distance

            for _ in 0..<maxGenerations {
                let ext = extrudeSegment(currentPoly, segIdx: currentSegIdx,
                                          distance: currentDistance, params: params,
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

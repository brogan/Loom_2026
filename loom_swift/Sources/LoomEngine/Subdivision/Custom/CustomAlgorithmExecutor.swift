import Foundation

/// Executes a CustomSubdivisionAlgorithm against an input polygon's anchor points.
public enum CustomAlgorithmExecutor {

    // MARK: - Public entry point

    public static func subdivide(
        points: [Vector2D],
        sidesTotal n: Int,
        algorithm: CustomSubdivisionAlgorithm,
        params: SubdivisionParams
    ) -> [Polygon2D] {
        guard n >= 3 else { return [] }

        let centroid = BezierMath.centreLine(points)

        // Phase 1 — evaluate all named points for every edge
        let allMaps: [[String: Vector2D]] = (0..<n).map { i in
            let start = points[i]
            let end   = points[(i + 1) % n]
            let prev  = points[(i + n - 1) % n]
            let next  = points[(i + 2) % n]
            return evaluatePoints(algorithm.points,
                                  start: start, end: end,
                                  prev: prev, next: next,
                                  centroid: centroid)
        }

        // Phase 2 — assemble per-edge child polygons
        var result: [Polygon2D] = []
        for i in 0..<n {
            let cur  = allMaps[i]
            let prev = allMaps[(i + n - 1) % n]
            let next = allMaps[(i + 1) % n]

            for childDef in algorithm.edgeChildren {
                let anchors = childDef.pointNames.compactMap { ref in
                    resolve(ref, current: cur, prev: prev, next: next)
                }
                guard anchors.count >= 3 else { continue }
                result.append(buildPolygon(anchors: anchors, params: params))
            }
        }

        // Phase 3 — optional global child (one vertex per edge)
        if let gName = algorithm.globalChildPointName, !gName.isEmpty {
            let globalAnchors = allMaps.compactMap { map -> Vector2D? in
                map[gName]
            }
            if globalAnchors.count >= 3 {
                result.append(buildPolygon(anchors: globalAnchors, params: params))
            }
        }

        return result
    }

    // MARK: - Point evaluation

    private static func evaluatePoints(
        _ namedPoints: [NamedPoint],
        start: Vector2D, end: Vector2D,
        prev: Vector2D, next: Vector2D,
        centroid: Vector2D
    ) -> [String: Vector2D] {
        var map: [String: Vector2D] = [
            "V.start": start,
            "V.end":   end,
            "C":       centroid
        ]
        let midpoint = Vector2D.lerp(start, end, t: 0.5)

        for np in namedPoints {
            map[np.name] = evaluate(np.primitive,
                                    start: start, end: end,
                                    prev: prev, next: next,
                                    centroid: centroid,
                                    midpoint: midpoint)
        }
        return map
    }

    private static func evaluate(
        _ prim: PointPrimitive,
        start: Vector2D, end: Vector2D,
        prev: Vector2D, next: Vector2D,
        centroid: Vector2D,
        midpoint: Vector2D
    ) -> Vector2D {
        switch prim.kind {
        case .vertexStart:
            return start
        case .vertexEnd:
            return end
        case .edgeFrac:
            return Vector2D.lerp(start, end, t: prim.t)
        case .edgeNormal:
            return Vector2D.lerp(start, end, t: prim.t) + perp(from: start, to: end) * prim.d
        case .edgePrevFrac:
            return Vector2D.lerp(prev, start, t: prim.t)
        case .edgePrevNormal:
            return Vector2D.lerp(prev, start, t: prim.t) + perp(from: prev, to: start) * prim.d
        case .edgeNextFrac:
            return Vector2D.lerp(end, next, t: prim.t)
        case .edgeNextNormal:
            return Vector2D.lerp(end, next, t: prim.t) + perp(from: end, to: next) * prim.d
        case .centroid:
            return centroid
        case .centroidOffset:
            let rad = prim.angle * .pi / 180.0
            return Vector2D(x: centroid.x + cos(rad) * prim.d,
                            y: centroid.y + sin(rad) * prim.d)
        case .midringInterp:
            return Vector2D.lerp(midpoint, centroid, t: prim.s)
        }
    }

    // MARK: - Reference resolution

    /// Resolve a point name reference from the current, previous, and next edge maps.
    /// Supports "NAME", "prev.NAME", and "next.NAME" forms.
    private static func resolve(
        _ ref: String,
        current: [String: Vector2D],
        prev: [String: Vector2D],
        next: [String: Vector2D]
    ) -> Vector2D? {
        if ref.hasPrefix("prev.") {
            let name = String(ref.dropFirst(5))
            return prev[name]
        }
        if ref.hasPrefix("next.") {
            let name = String(ref.dropFirst(5))
            return next[name]
        }
        return current[ref]
    }

    // MARK: - Polygon construction

    private static func buildPolygon(anchors: [Vector2D], params: SubdivisionParams) -> Polygon2D {
        let n = anchors.count
        let centre = BezierMath.centreLine(anchors)
        var pts: [Vector2D] = []
        pts.reserveCapacity(n * 4)
        for i in 0..<n {
            let from = anchors[i]
            let to   = anchors[(i + 1) % n]
            pts.append(contentsOf: params.connector(from: from, to: to, centre: centre))
        }
        return Polygon2D(points: pts, type: .spline)
    }

    // MARK: - Geometry helpers

    /// 90° CCW unit perpendicular of the from→to direction (inward for CCW-wound polygon).
    private static func perp(from a: Vector2D, to b: Vector2D) -> Vector2D {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 1e-10 else { return .zero }
        return Vector2D(x: -dy / len, y: dx / len)
    }
}

import Foundation

/// Central entry point for the Loom subdivision system.
///
/// Design improvements over Scala:
/// - Algorithm dispatch is type-safe (enum switch, no raw Int)
/// - Geometry is immutable (value types; no in-place mutation)
/// - Randomness is injectable via `RandomNumberGenerator`
/// - Bypass polygon types (openSpline, point, oval) pass through unchanged
/// - `process` implements the full multi-generation pipeline
public enum SubdivisionEngine {

    // MARK: - Single polygon subdivision

    /// Subdivide `polygon` using `params`, returning child polygons with
    /// visibility applied. Bypass types (openSpline, point, oval) are
    /// returned as-is in a single-element array.
    public static func subdivide<G: RandomNumberGenerator>(
        polygon: Polygon2D,
        params: SubdivisionParams,
        rng: inout G
    ) -> [Polygon2D] {
        guard !polygon.isBypassType else { return [polygon] }

        // LINE polygons: sidesTotal = vertex count; convert to spline for algorithm reuse.
        // Mirrors Scala: LINE_POLYGON → sidesTotal = points.length; getCenter = average of all pts.
        let pts: [Vector2D]
        let n: Int
        if polygon.type == .line {
            n = polygon.points.count
            guard n > 0 else { return [polygon] }
            pts = BezierMath.lineToSplinePoints(polygon.points)
        } else {
            pts = polygon.points
            n = pts.count / 4
            guard n > 0 else { return [polygon] }
        }

        // Optionally jitter the polygon centre (affects QUAD and TRI internal edges)
        let centre = jitteredCentre(
            pts: pts, enabled: params.ranMiddle, div: params.ranDiv, rng: &rng
        )

        let children = dispatch(
            points: pts,
            sidesTotal: n,
            centre: centre,
            params: params
        )

        let visible = applyVisibility(children, rule: params.visibilityRule, rng: &rng)
        return PolygonTransforms.apply(visible, params: params, rng: &rng)
    }

    // MARK: - Pipeline (multi-generation)

    /// Run a full subdivision pipeline: apply each generation in `paramSet`
    /// in sequence, pruning invisible polygons between generations.
    ///
    /// Bypass polygons are separated before processing and rejoined at the end.
    public static func process<G: RandomNumberGenerator>(
        polygons: [Polygon2D],
        paramSet: [SubdivisionParams],
        rng: inout G
    ) -> [Polygon2D] {
        let bypass   = polygons.filter { $0.isBypassType }
        var active   = polygons.filter { !$0.isBypassType }

        for params in paramSet {
            active = active.flatMap { subdivide(polygon: $0, params: params, rng: &rng) }
            // Prune: only visible polygons advance to the next generation
            active = active.filter { $0.visible }
        }

        return active + bypass
    }

    // MARK: - Algorithm dispatch

    private static func dispatch(
        points: [Vector2D],
        sidesTotal: Int,
        centre: Vector2D,
        params: SubdivisionParams
    ) -> [Polygon2D] {
        switch params.subdivisionType {
        case .quad:
            return subdivideQuad(points: points, sidesTotal: sidesTotal, params: params, centre: centre)
        case .quadBord:
            return subdivideQuadBord(points: points, sidesTotal: sidesTotal, params: params)
        case .quadBordEcho:
            return subdivideQuadBordEcho(points: points, sidesTotal: sidesTotal, params: params)
        case .quadBordDouble:
            return subdivideQuadBordDouble(points: points, sidesTotal: sidesTotal, params: params)
        case .quadBordDoubleEcho:
            return subdivideQuadBordDoubleEcho(points: points, sidesTotal: sidesTotal, params: params)
        case .tri:
            return subdivideTri(points: points, sidesTotal: sidesTotal, params: params, centre: centre)
        case .triBordA:
            return subdivideTriBordA(points: points, sidesTotal: sidesTotal, params: params)
        case .triBordAEcho:
            return subdivideTriBordAEcho(points: points, sidesTotal: sidesTotal, params: params)
        case .triBordB:
            return subdivideTriBordB(points: points, sidesTotal: sidesTotal, params: params)
        case .triBordBEcho:
            return subdivideTriBordBEcho(points: points, sidesTotal: sidesTotal, params: params)
        case .triBordC:
            return subdivideTriBordC(points: points, sidesTotal: sidesTotal, params: params)
        case .triBordCEcho:
            return subdivideTriBordCEcho(points: points, sidesTotal: sidesTotal, params: params)
        case .triStar:
            return subdivideTriStar(points: points, sidesTotal: sidesTotal, params: params)
        case .triStarFill:
            return subdivideTriStarFill(points: points, sidesTotal: sidesTotal, params: params)
        case .splitVert:
            return subdivideSplit(points: points, sidesTotal: sidesTotal, params: params, orientation: .vertical)
        case .splitHoriz:
            return subdivideSplit(points: points, sidesTotal: sidesTotal, params: params, orientation: .horizontal)
        case .splitDiag:
            return subdivideSplit(points: points, sidesTotal: sidesTotal, params: params, orientation: .diagonal)
        case .echo:
            return subdivideEcho(points: points, params: params)
        case .echoAbsCenter:
            return subdivideEchoAbsCenter(points: points, params: params)
        }
    }

    // MARK: - Visibility

    static func applyVisibility<G: RandomNumberGenerator>(
        _ polys: [Polygon2D],
        rule: VisibilityRule,
        rng: inout G
    ) -> [Polygon2D] {
        polys.enumerated().map { idx, poly in
            poly.withVisibility(isVisible(index: idx, total: polys.count, rule: rule, rng: &rng))
        }
    }

    private static func isVisible<G: RandomNumberGenerator>(
        index: Int,
        total: Int,
        rule: VisibilityRule,
        rng: inout G
    ) -> Bool {
        switch rule {
        case .all:           return true
        case .quads:         return true   // side count check deferred — all algorithms set correct types
        case .tris:          return true
        case .allButLast:    return index < total - 1
        case .alternateOdd:  return index % 2 != 0
        case .alternateEven: return index % 2 == 0
        case .firstHalf:     return index < total / 2
        case .secondHalf:    return index > total / 2
        case .everyThird:    return index % 3 == 0
        case .everyFourth:   return index % 4 == 0
        case .everyFifth:    return index % 5 == 0
        case .random1in2:    return Int.random(in: 0..<2,  using: &rng) == 1
        case .random1in3:    return Int.random(in: 0..<3,  using: &rng) == 1
        case .random1in5:    return Int.random(in: 0..<5,  using: &rng) == 1
        case .random1in7:    return Int.random(in: 0..<7,  using: &rng) == 1
        case .random1in10:   return Int.random(in: 0..<10, using: &rng) == 1
        }
    }

    // MARK: - Centre jitter

    /// Returns a jittered centre when `enabled`; otherwise the canonical anchor centre.
    /// Jitter range is ±(distance from centre to first anchor) / div.
    private static func jitteredCentre<G: RandomNumberGenerator>(
        pts: [Vector2D],
        enabled: Bool,
        div: Double,
        rng: inout G
    ) -> Vector2D {
        let centre = BezierMath.centreSpline(pts)
        guard enabled, pts.count >= 4 else { return centre }
        let dist  = centre.distance(to: pts[0])
        let third = dist / max(div, 1e-9)
        let x = Double.random(in: -third...third, using: &rng) + centre.x
        let y = Double.random(in: -third...third, using: &rng) + centre.y
        return Vector2D(x: x, y: y)
    }
}

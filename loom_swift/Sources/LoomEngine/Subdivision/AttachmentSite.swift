import Foundation

/// A point on a piece's boundary where another piece can be attached (§5.12.3):
/// `point` is the anchor, `direction` is the boundary's own direction there (an edge's
/// direction, or a curve endpoint's tangent), `outward` is the side a newly-attached
/// piece should be placed on.
///
/// Two constructors cover the two polygon representations `AssemblyPrimitiveKit`
/// produces — deliberately **not** `ExtensionEngine.outwardNormal`, which assumes the
/// 4-points-per-segment `.spline` encoding a shape only has *after* Subdivision; the
/// kit's closed pieces are plain `.line`-type polygons (raw vertex list) instead.
public struct AttachmentSite: Equatable, Sendable {
    public var point:     Vector2D
    public var direction: Vector2D
    public var outward:   Vector2D

    /// The edge's length, for a `.line`-polygon edge site; `nil` for a curve-endpoint
    /// site (a point has no length). `AssemblyEdgeMatching.matchLength` is a no-op
    /// when either site in a pairing has no length.
    public var length: Double?

    public init(point: Vector2D, direction: Vector2D, outward: Vector2D, length: Double? = nil) {
        self.point = point
        self.direction = direction
        self.outward = outward
        self.length = length
    }
}

public enum AttachmentSiteExtractor {

    /// All attachment sites exposed by a piece, dispatching on its `PolygonType`.
    /// Bypass/degenerate types (`.point`, `.oval`) expose none.
    public static func sites(of polygon: Polygon2D) -> [AttachmentSite] {
        switch polygon.type {
        case .line:
            return lineEdgeSites(polygon)
        case .openSpline:
            return openSplineEndpointSites(polygon)
        case .spline:
            return splineEdgeSites(polygon)
        case .point, .oval:
            return []
        }
    }

    // MARK: - .line (closed, straight-edged)

    private static func lineEdgeSites(_ polygon: Polygon2D) -> [AttachmentSite] {
        let pts = polygon.points
        let n = pts.count
        guard n >= 2 else { return [] }

        let centre = polygon.centroid
        var sites: [AttachmentSite] = []
        sites.reserveCapacity(n)

        for i in 0..<n {
            let a = pts[i]
            let b = pts[(i + 1) % n]
            let mid = Vector2D(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let dir = (b - a).normalized()
            guard dir != .zero else { continue }
            // Perpendicular to the edge, oriented away from the polygon's own centroid.
            var normal = Vector2D(x: -dir.y, y: dir.x)
            if normal.dot(mid - centre) < 0 { normal = -normal }
            sites.append(AttachmentSite(point: mid, direction: dir, outward: normal, length: a.distance(to: b)))
        }
        return sites
    }

    // MARK: - .spline (closed, curved — user-drawn shapes, 2026-07-12)

    /// One site per segment, same edge-midpoint/direction/outward math as
    /// `lineEdgeSites` above, but walking anchor points (every 4th point, the
    /// segment starts) instead of raw vertices, and using each segment's own
    /// anchor-to-anchor chord as "the edge" — bow is deliberately ignored for
    /// attachment purposes, the same convention `ExtensionEngine.outwardNormal`
    /// already uses for `.spline` segments elsewhere. Centroid via
    /// `BezierMath.centreSpline` (an anchor-only average) rather than
    /// `Polygon2D.centroid` (which would average in the bezier control points
    /// too, pulling it off-centre for a bowed shape).
    private static func splineEdgeSites(_ polygon: Polygon2D) -> [AttachmentSite] {
        let pts = polygon.points
        let n = pts.count / 4
        guard n >= 1, pts.count % 4 == 0 else { return [] }

        let anchors = (0..<n).map { pts[$0 * 4] }
        let centre = BezierMath.centreSpline(pts)
        var sites: [AttachmentSite] = []
        sites.reserveCapacity(n)

        for i in 0..<n {
            let a = anchors[i]
            let b = anchors[(i + 1) % n]
            let mid = Vector2D(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let dir = (b - a).normalized()
            guard dir != .zero else { continue }
            var normal = Vector2D(x: -dir.y, y: dir.x)
            if normal.dot(mid - centre) < 0 { normal = -normal }
            sites.append(AttachmentSite(point: mid, direction: dir, outward: normal, length: a.distance(to: b)))
        }
        return sites
    }

    // MARK: - .openSpline (endpoint + tangent)

    /// One site per curve endpoint. `outward` has no principled answer for a bare
    /// open curve (its own bounding-box centroid can sit on the curve itself, as it
    /// does for a straight line) — resolved by not trying to derive it geometrically:
    /// `outward` is `direction` rotated +90°, and the assembly algorithm's own seeded
    /// mirror roll (§5.12.4 step 3) supplies "or the other side," rather than this
    /// function needing its own seed.
    ///
    /// `length` is deliberately `nil` here, same as ever — an open curve's endpoint
    /// is a point, not an edge, and this function has no notion of a piece's
    /// provenance. `GenerationalEvolutionEngine`'s `.customSet` Graft path (2026-07-12)
    /// synthesizes a length for genuinely custom open-curve pieces itself, right at
    /// its own call site, specifically so the *generated* primitive path's `sides=1`
    /// degenerate fallback (also a bare two-point `.openSpline`, meaning "no
    /// meaningful primitive this roll") stays correctly ineligible for
    /// `.wholeEdge`/`.partialEdge` — see `openCurveEligibleSites` there.
    private static func openSplineEndpointSites(_ polygon: Polygon2D) -> [AttachmentSite] {
        let pts = polygon.points
        guard pts.count >= 4, pts.count % 4 == 0 else { return [] }

        let a0  = pts[0]
        let cp1 = pts[1]
        let cp2 = pts[pts.count - 2]
        let a1  = pts[pts.count - 1]

        let startDir = (cp1 - a0).normalized()
        let endDir   = (a1 - cp2).normalized()

        var sites: [AttachmentSite] = []
        if startDir != .zero {
            // Tangent pointing back out of the curve at its start.
            let dir = -startDir
            sites.append(AttachmentSite(point: a0, direction: dir, outward: dir.rotated(by: .pi / 2)))
        }
        if endDir != .zero {
            sites.append(AttachmentSite(point: a1, direction: endDir, outward: endDir.rotated(by: .pi / 2)))
        }
        return sites
    }
}

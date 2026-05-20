import Foundation

/// Pure Bézier and geometry utilities used by subdivision algorithms.
///
/// All methods operate on `[Vector2D]` using the 4-point-per-segment encoding:
///   `[anchor₀, control₁, control₂, anchor₁]`
public enum BezierMath {

    // MARK: - Curve evaluation

    /// Point on a cubic Bézier at parameter `t` ∈ [0, 1].
    /// Uses the standard de Casteljau algorithm.
    public static func point(
        _ p0: Vector2D, _ p1: Vector2D, _ p2: Vector2D, _ p3: Vector2D,
        t: Double
    ) -> Vector2D {
        let m1 = Vector2D.lerp(p0, p1, t: t)
        let m2 = Vector2D.lerp(p1, p2, t: t)
        let m3 = Vector2D.lerp(p2, p3, t: t)
        let m4 = Vector2D.lerp(m1, m2, t: t)
        let m5 = Vector2D.lerp(m2, m3, t: t)
        return Vector2D.lerp(m4, m5, t: t)
    }

    /// Point on a cubic Bézier segment (4-element slice) at parameter `t`.
    public static func point(seg: [Vector2D], t: Double) -> Vector2D {
        point(seg[0], seg[1], seg[2], seg[3], t: t)
    }

    // MARK: - De Casteljau split

    /// Split a cubic Bézier at `t` using de Casteljau.
    /// Returns `(left, right)` where each is a 4-element segment.
    public static func split(
        _ p0: Vector2D, _ p1: Vector2D, _ p2: Vector2D, _ p3: Vector2D,
        t: Double
    ) -> (left: [Vector2D], right: [Vector2D]) {
        let m1 = Vector2D.lerp(p0, p1, t: t)
        let m2 = Vector2D.lerp(p1, p2, t: t)
        let m3 = Vector2D.lerp(p2, p3, t: t)
        let m4 = Vector2D.lerp(m1, m2, t: t)
        let m5 = Vector2D.lerp(m2, m3, t: t)
        let m  = Vector2D.lerp(m4, m5, t: t)
        return (left: [p0, m1, m4, m], right: [m, m5, m3, p3])
    }

    /// Split a 4-element segment at `t`.
    public static func split(seg: [Vector2D], t: Double) -> (left: [Vector2D], right: [Vector2D]) {
        split(seg[0], seg[1], seg[2], seg[3], t: t)
    }

    // MARK: - Polygon geometry

    /// Average of the anchor points (every 4th point) of a spline polygon.
    /// Ignores control points, as in the Scala `getCenterSpline`.
    public static func centreSpline(_ pts: [Vector2D]) -> Vector2D {
        let n = pts.count / 4
        guard n > 0 else { return .zero }
        var sum = Vector2D.zero
        for i in 0..<n { sum = sum + pts[i * 4] }
        return sum.scaled(by: 1.0 / Double(n))
    }

    // MARK: - Segment utilities

    /// Reverse a 4-point segment: `[p0,p1,p2,p3]` → `[p3,p2,p1,p0]`.
    public static func reverseSegment(_ seg: [Vector2D]) -> [Vector2D] {
        [seg[3], seg[2], seg[1], seg[0]]
    }

    /// Extract `sidesTotal` segments of 4 points from a flat point array.
    public static func extractSides(_ pts: [Vector2D], sidesTotal: Int) -> [[Vector2D]] {
        (0..<sidesTotal).map { i in Array(pts[(i * 4)..<(i * 4 + 4)]) }
    }

    /// Average of all vertices in a line polygon (mirrors Scala `getCenter`).
    public static func centreLine(_ pts: [Vector2D]) -> Vector2D {
        guard !pts.isEmpty else { return .zero }
        let sum = pts.reduce(Vector2D.zero) { $0 + $1 }
        return sum.scaled(by: 1.0 / Double(pts.count))
    }

    /// Convert a flat vertex list (line polygon) to spline-encoding:
    /// each edge [V_i → V_{i+1}] becomes the degenerate bezier
    /// [V_i, lerp(V_i,V_{i+1},⅓), lerp(V_i,V_{i+1},⅔), V_{i+1}].
    /// The returned array has `vertices.count * 4` points and can be passed
    /// directly to any spline-based subdivision algorithm.
    public static func lineToSplinePoints(_ vertices: [Vector2D]) -> [Vector2D] {
        let n = vertices.count
        var pts = [Vector2D]()
        pts.reserveCapacity(n * 4)
        for i in 0..<n {
            let a = vertices[i]
            let b = vertices[(i + 1) % n]
            pts.append(a)
            pts.append(Vector2D.lerp(a, b, t: 1.0 / 3.0))
            pts.append(Vector2D.lerp(a, b, t: 2.0 / 3.0))
            pts.append(b)
        }
        return pts
    }

    /// Bézier connector from `from` to `to`.
    ///
    /// Control points are placed at parametric positions `cpRatios.x` / `cpRatios.y`
    /// along the segment, then displaced perpendicular to it by `cpNormalOffsets.x`
    /// and `cpNormalOffsets.y` (expressed as fractions of the segment length).
    ///
    /// When `normalizeToCentre` is true the positive normal direction points away
    /// from `centre`; otherwise it is the left-perpendicular (90° CCW) of the
    /// from→to direction vector.
    public static func connector(
        from: Vector2D, to: Vector2D,
        cpRatios: Vector2D,
        cpNormalOffsets: Vector2D = .zero,
        normalizeToCentre: Bool = false,
        centre: Vector2D = .zero
    ) -> [Vector2D] {
        let cp0 = Vector2D.lerp(from, to, t: cpRatios.x)
        let cp1 = Vector2D.lerp(from, to, t: cpRatios.y)

        guard cpNormalOffsets.x != 0 || cpNormalOffsets.y != 0 else {
            return [from, cp0, cp1, to]
        }

        let dx  = to.x - from.x
        let dy  = to.y - from.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 1e-12 else { return [from, cp0, cp1, to] }

        // Left-perpendicular unit vector (90° CCW of from→to).
        var nx = -dy / len
        var ny =  dx / len

        if normalizeToCentre {
            // Flip so positive offset points away from the polygon centroid.
            let midX = (from.x + to.x) * 0.5
            let midY = (from.y + to.y) * 0.5
            if nx * (midX - centre.x) + ny * (midY - centre.y) < 0 {
                nx = -nx; ny = -ny
            }
        }

        return [
            from,
            Vector2D(x: cp0.x + nx * cpNormalOffsets.x * len,
                     y: cp0.y + ny * cpNormalOffsets.x * len),
            Vector2D(x: cp1.x + nx * cpNormalOffsets.y * len,
                     y: cp1.y + ny * cpNormalOffsets.y * len),
            to
        ]
    }

    // MARK: - Scala-compatible edge split

    /// Split a cubic Bézier segment using the same proportional approach as
    /// Scala's `SplineQuad.getSubSides`.
    ///
    /// Unlike de Casteljau, this method guarantees that the sub-segment
    /// endpoints land at the **linear** interpolation of the anchor points
    /// (i.e. `B(0.5) == lerp(A, B, 0.5)` for every resulting sub-segment),
    /// regardless of how the original control points are spaced.
    ///
    /// De Casteljau is geometrically exact for curved splines, but for
    /// straight-line segments with non-uniformly-spaced control points it
    /// produces sub-segments whose `B(t=0.5)` does **not** equal the
    /// geometric anchor midpoint.  That deviation compoundsover successive
    /// subdivision levels and causes the visible grid distortion observed in
    /// 3+ level quad subdivision.
    ///
    /// - Returns: `(left, right)` where each is a 4-point segment.
    ///   The shared split point is `left[3] == right[0]`.
    public static func scalaSplit(
        _ A: Vector2D, _ AC: Vector2D, _ BC: Vector2D, _ B: Vector2D,
        t: Double
    ) -> (left: [Vector2D], right: [Vector2D]) {
        // Bezier evaluation at t (may differ from linear anchor midpoint for
        // non-uniformly parameterised segments)
        let Mb  = BezierMath.point(A, AC, BC, B, t: t)
        // Linear interpolation of the two anchor points
        let M   = Vector2D.lerp(A, B, t: t)
        // Offset from Bezier point to linear midpoint
        let dMb = M - Mb

        // Shift A and B by the same offset so the control-point proportions
        // are computed in a "corrected" space (matches Scala's A_Up / B_Up)
        let A_Up = A + dMb
        let B_Up = B + dMb

        // Scale original control points halfway toward their anchor
        // (Scala: AC_scaled = avg(A, AC), BC_scaled = avg(B, BC))
        let AC_h = Vector2D.lerp(A, AC, t: 0.5)
        let BC_h = Vector2D.lerp(B, BC, t: 0.5)

        // Distances used to compute the proportional control-point positions
        let dA_ACh = A.distance(to: AC_h)
        let dB_BCh = B.distance(to: BC_h)
        let dAUp_Mb = A_Up.distance(to: Mb)
        let dBUp_Mb = B_Up.distance(to: Mb)

        let perA = dAUp_Mb > 1e-12 ? dA_ACh / dAUp_Mb : 0
        let perB = dBUp_Mb > 1e-12 ? dB_BCh / dBUp_Mb : 0

        // Inner control points of the two sub-segments, referenced from M
        // (the geometric anchor midpoint) so that the split point is always
        // at the linear-interpolated edge midpoint regardless of how the
        // original control points are parameterised.
        let MAC = Vector2D.lerp(M, A_Up, t: perA)
        let MBC = Vector2D.lerp(M, B_Up, t: perB)

        return (
            left:  [A, AC_h, MAC, M],
            right: [M, MBC, BC_h, B]
        )
    }

    /// Convenience overload for a 4-element segment slice.
    public static func scalaSplit(seg: [Vector2D], t: Double) -> (left: [Vector2D], right: [Vector2D]) {
        scalaSplit(seg[0], seg[1], seg[2], seg[3], t: t)
    }

    /// Apply `insetTransform` around `centre` to every point in a flat array.
    public static func insetPoints(
        _ pts: [Vector2D],
        transform: InsetTransform,
        centre: Vector2D
    ) -> [Vector2D] {
        pts.map { transform.apply(to: $0, around: centre) }
    }
}

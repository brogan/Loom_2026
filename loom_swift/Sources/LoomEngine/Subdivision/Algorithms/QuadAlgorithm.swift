/// QUAD subdivision: N quadrilateral children, each sharing one split outer edge
/// and converging on the polygon centre.
///
/// Outer edges are split using `BezierMath.scalaSplit`, which replicates
/// Scala's `SplineQuad.getSubSides` proportional approach.  This ensures that
/// the split point of each sub-segment always lands at the **geometric** anchor
/// midpoint (linear interpolation), not the Bézier curve parameter midpoint.
///
/// For segments with non-uniformly-spaced control points (which arise after the
/// first subdivision level even from a symmetric input polygon), de Casteljau
/// at t=0.5 does NOT give the geometric midpoint, causing cumulative positional
/// errors that become visually large by the 3rd subdivision level.
/// `scalaSplit` avoids this by preserving the invariant `B(0.5) = lerp(A,B,0.5)`
/// in every resulting sub-segment at every level.
///
/// - Parameter centre: Pre-computed (and optionally jittered) polygon centre.
///   Pass `BezierMath.centreSpline(points)` when no jitter is needed.
func subdivideQuad(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams,
    centre: Vector2D
) -> [Polygon2D] {

    // centre passed in (may be jittered by ranMiddle)
    let sides  = BezierMath.extractSides(points, sidesTotal: sidesTotal)

    // Split each outer edge → (left half, right half)
    var lefts  = [[Vector2D]](repeating: [], count: sidesTotal)
    var rights = [[Vector2D]](repeating: [], count: sidesTotal)
    var splits = [Vector2D](repeating: .zero, count: sidesTotal)  // split points M_i

    for i in 0..<sidesTotal {
        let t = params.splitRatio(forSideIndex: i)
        let (l, r) = BezierMath.scalaSplit(seg: sides[i], t: t)
        lefts[i]  = l
        rights[i] = r
        splits[i] = l[3]  // the split point (Bezier point at t)
    }

    // Internal edges from each split point to the centre
    let cp = params.controlPointRatios
    let internalSides: [[Vector2D]] = splits.map { m in
        BezierMath.connector(from: m, to: centre, cpRatios: cp)
    }

    // Assemble N quads
    var polys = [Polygon2D]()
    polys.reserveCapacity(sidesTotal)

    for i in 0..<sidesTotal {
        let prev = (i + sidesTotal - 1) % sidesTotal

        // Side 0: first half of outer edge i  (A_i → M_i)
        let s0 = lefts[i]
        // Side 1: internal M_i → centre
        let s1 = internalSides[i]
        // Side 2: reversed internal M_{i-1} → centre becomes centre → M_{i-1}
        let s2 = BezierMath.reverseSegment(internalSides[prev])
        // Side 3: second half of outer edge i-1  (M_{i-1} → A_i)
        let s3 = rights[prev]

        let pts = s0 + s1 + s2 + s3
        polys.append(Polygon2D(points: pts, type: .spline))
    }

    return polys
}

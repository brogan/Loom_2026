/// TRI subdivision: N triangular children, each spanning one complete outer edge
/// and converging on the polygon centre via two internal edges.
/// - Parameter centre: Pre-computed (and optionally jittered) polygon centre.
func subdivideTri(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams,
    centre: Vector2D
) -> [Polygon2D] {

    // centre passed in (may be jittered by ranMiddle)
    let sides  = BezierMath.extractSides(points, sidesTotal: sidesTotal)
    let cp     = params.controlPointRatios

    // Build two internal edges per side:
    //   edge0: last anchor of side i → centre
    //   edge1: centre → first anchor of side i  (i.e. reversed A_i → centre)
    var polys = [Polygon2D]()
    polys.reserveCapacity(sidesTotal)

    for i in 0..<sidesTotal {
        let a0 = sides[i][0]  // first anchor of side i
        let a1 = sides[i][3]  // last anchor of side i

        // Internal edge a1 → centre
        let int0 = BezierMath.connector(from: a1, to: centre, cpRatios: cp)
        // Internal edge centre → a0 (reversed direction of a0 → centre)
        let int1 = BezierMath.connector(from: centre, to: a0, cpRatios: cp)

        // Triangle:
        //   Side 0: outer edge i  (a0 → a1, full bezier)
        //   Side 1: int0          (a1 → centre)
        //   Side 2: int1          (centre → a0)
        let pts = sides[i] + int0 + int1
        polys.append(Polygon2D(points: pts, type: .spline))
    }

    return polys
}

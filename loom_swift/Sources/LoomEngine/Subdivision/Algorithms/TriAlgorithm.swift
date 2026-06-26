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

    // Build two internal edges per side:
    //   edge0: last anchor of side i → centre
    //   edge1: centre → first anchor of side i  (i.e. reversed A_i → centre)
    var polys = [Polygon2D]()
    polys.reserveCapacity(sidesTotal)

    for i in 0..<sidesTotal {
        let a0 = sides[i][0]
        let a1 = sides[i][3]

        var int0 = params.connector(from: a1, to: centre, centre: centre)
        var int1 = params.connector(from: centre, to: a0, centre: centre)

        let sign = params.curvatureSign(forIndex: i)
        if sign != 0.0 {
            int0 = BezierMath.applyOuterBow(to: int0, sourceEdge: sides[i], sign: sign)
            int1 = BezierMath.applyOuterBow(to: int1, sourceEdge: sides[i], sign: sign)
        }

        let pts = sides[i] + int0 + int1
        polys.append(Polygon2D(points: pts, type: .spline))
    }

    return polys
}

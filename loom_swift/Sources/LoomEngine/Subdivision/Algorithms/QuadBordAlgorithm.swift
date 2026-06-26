// MARK: - Shared helpers

/// Inset all points of a spline polygon using insetTransform around its anchor centre.
private func insetSpline(points: [Vector2D], params: SubdivisionParams) -> [Vector2D] {
    let centre = BezierMath.centreSpline(points)
    return BezierMath.insetPoints(points, transform: params.insetTransform, centre: centre)
}

// MARK: - QUAD_BORD
//
// N border quads framing the polygon like a picture frame.
// Each quad: outer side i → right connector → reversed inner side i → left connector.

func subdivideQuadBord(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let outer = BezierMath.extractSides(points, sidesTotal: sidesTotal)
    let inner = BezierMath.extractSides(insetSpline(points: points, params: params), sidesTotal: sidesTotal)
    return buildBordQuads(outer: outer, inner: inner, sidesTotal: sidesTotal, params: params)
}

/// Build N border quads from parallel outer/inner side arrays.
private func buildBordQuads(
    outer: [[Vector2D]],
    inner: [[Vector2D]],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let cp = params.controlPointRatios
    var polys = [Polygon2D]()
    polys.reserveCapacity(sidesTotal)

    for i in 0..<sidesTotal {
        let o      = outer[i]
        let inn    = inner[i]
        let revInn = BezierMath.reverseSegment(inn)

        var s1 = BezierMath.connector(from: o[3],   to: inn[3], cpRatios: cp)
        var s3 = BezierMath.connector(from: inn[0],  to: o[0],  cpRatios: cp)

        let sign = params.curvatureSign(forIndex: i)
        if sign != 0.0 {
            s1 = BezierMath.applyOuterBow(to: s1, sourceEdge: o, sign: sign)
            s3 = BezierMath.applyOuterBow(to: s3, sourceEdge: o, sign: sign)
        }

        polys.append(Polygon2D(points: o + s1 + revInn + s3, type: .spline))
    }
    return polys
}

// MARK: - QUAD_BORD_ECHO

func subdivideQuadBordEcho(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let insetPts = insetSpline(points: points, params: params)
    let outer    = BezierMath.extractSides(points, sidesTotal: sidesTotal)
    let inner    = BezierMath.extractSides(insetPts, sidesTotal: sidesTotal)
    var polys    = buildBordQuads(outer: outer, inner: inner, sidesTotal: sidesTotal, params: params)
    polys.append(Polygon2D(points: insetPts, type: .spline))  // fill polygon
    return polys
}

// MARK: - QUAD_BORD_DOUBLE
//
// Each border quad is split at the midpoints of outer and inner beziers,
// producing 2N quads total (left half + right half per side).

func subdivideQuadBordDouble(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let outerSides = BezierMath.extractSides(points, sidesTotal: sidesTotal)
    let insetPts   = insetSpline(points: points, params: params)
    let innerSides = BezierMath.extractSides(insetPts, sidesTotal: sidesTotal)
    let cp         = params.controlPointRatios

    var polys = [Polygon2D]()
    polys.reserveCapacity(sidesTotal * 2)

    for i in 0..<sidesTotal {
        let t = params.splitRatio(forSideIndex: i)
        let (outerL, outerR) = BezierMath.split(seg: outerSides[i], t: t)
        let (innerL, innerR) = BezierMath.split(seg: innerSides[i], t: t)
        let outerMid = outerL[3]
        let innerMid = innerL[3]

        let sign = params.curvatureSign(forIndex: i)
        let src  = outerSides[i]

        var q1s1 = BezierMath.connector(from: outerMid,          to: innerMid,          cpRatios: cp)
        var q1s3 = BezierMath.connector(from: innerSides[i][0],  to: outerSides[i][0],  cpRatios: cp)
        var q2s1 = BezierMath.connector(from: outerSides[i][3],  to: innerSides[i][3],  cpRatios: cp)
        var q2s3 = BezierMath.connector(from: innerMid,           to: outerMid,          cpRatios: cp)

        if sign != 0.0 {
            q1s1 = BezierMath.applyOuterBow(to: q1s1, sourceEdge: src, sign: sign)
            q1s3 = BezierMath.applyOuterBow(to: q1s3, sourceEdge: src, sign: sign)
            q2s1 = BezierMath.applyOuterBow(to: q2s1, sourceEdge: src, sign: sign)
            q2s3 = BezierMath.applyOuterBow(to: q2s3, sourceEdge: src, sign: sign)
        }

        polys.append(Polygon2D(points: outerL + q1s1 + BezierMath.reverseSegment(innerL) + q1s3, type: .spline))
        polys.append(Polygon2D(points: outerR + q2s1 + BezierMath.reverseSegment(innerR) + q2s3, type: .spline))
    }
    return polys
}

// MARK: - QUAD_BORD_DOUBLE_ECHO

func subdivideQuadBordDoubleEcho(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let insetPts = insetSpline(points: points, params: params)
    var polys    = subdivideQuadBordDouble(points: points, sidesTotal: sidesTotal, params: params)
    polys.append(Polygon2D(points: insetPts, type: .spline))
    return polys
}

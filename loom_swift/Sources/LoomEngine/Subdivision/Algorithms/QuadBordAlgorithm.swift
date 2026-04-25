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
        let o = outer[i]
        let inn = inner[i]
        let revInn = BezierMath.reverseSegment(inn)

        // Side 0: outer side as-is
        let s0 = o
        // Side 1: right connector outer[i].end → inner[i].end
        let s1 = BezierMath.connector(from: o[3], to: inn[3], cpRatios: cp)
        // Side 2: reversed inner side i
        let s2 = revInn
        // Side 3: left connector inner[i].start → outer[i].start
        let s3 = BezierMath.connector(from: inn[0], to: o[0], cpRatios: cp)

        polys.append(Polygon2D(points: s0 + s1 + s2 + s3, type: .spline))
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

        // Quad 1 (left half):
        //   Side 0: left outer half
        //   Side 1: outerMid → innerMid connector
        //   Side 2: reversed left inner half (innerMid → inner[i].start)
        //   Side 3: inner[i].start → outer[i].start connector
        let q1s0 = outerL
        let q1s1 = BezierMath.connector(from: outerMid, to: innerMid, cpRatios: cp)
        let q1s2 = BezierMath.reverseSegment(innerL)
        let q1s3 = BezierMath.connector(from: innerSides[i][0], to: outerSides[i][0], cpRatios: cp)
        polys.append(Polygon2D(points: q1s0 + q1s1 + q1s2 + q1s3, type: .spline))

        // Quad 2 (right half):
        //   Side 0: right outer half
        //   Side 1: outer[i].end → inner[i].end connector
        //   Side 2: reversed right inner half (inner[i].end → innerMid)
        //   Side 3: innerMid → outerMid connector
        let q2s0 = outerR
        let q2s1 = BezierMath.connector(from: outerSides[i][3], to: innerSides[i][3], cpRatios: cp)
        let q2s2 = BezierMath.reverseSegment(innerR)
        let q2s3 = BezierMath.connector(from: innerMid, to: outerMid, cpRatios: cp)
        polys.append(Polygon2D(points: q2s0 + q2s1 + q2s2 + q2s3, type: .spline))
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

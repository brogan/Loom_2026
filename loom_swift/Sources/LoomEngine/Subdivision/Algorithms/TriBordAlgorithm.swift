// MARK: - TRI_BORD_A
//
// N corner triangles. Each triangle spans corner[i] and the midpoints of its
// two adjacent outer bezier sides (outerMid[i] and outerMid[i-1]).
// No inset polygon — midpoints taken directly from outer sides.

func subdivideTriBordA(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let sides = BezierMath.extractSides(points, sidesTotal: sidesTotal)
    let mids  = outerMidPoints(sides: sides, sidesTotal: sidesTotal, params: params)
    let cp    = params.controlPointRatios
    var polys = [Polygon2D]()
    polys.reserveCapacity(sidesTotal)

    for i in 0..<sidesTotal {
        let prev    = (i + sidesTotal - 1) % sidesTotal
        let corner  = sides[i][0]
        let midI    = mids[i]
        let midPrev = mids[prev]

        var s0 = BezierMath.connector(from: corner,  to: midI,    cpRatios: cp)
        var s1 = BezierMath.connector(from: midI,    to: midPrev, cpRatios: cp)
        var s2 = BezierMath.connector(from: midPrev, to: corner,  cpRatios: cp)

        let sign = params.curvatureSign(forIndex: i)
        if sign != 0.0 {
            s0 = BezierMath.applyOuterBow(to: s0, sourceEdge: sides[i],    sign: sign)
            s1 = BezierMath.applyOuterBow(to: s1, sourceEdge: sides[i],    sign: sign)
            s2 = BezierMath.applyOuterBow(to: s2, sourceEdge: sides[prev], sign: sign)
        }

        polys.append(Polygon2D(points: s0 + s1 + s2, type: .spline))
    }
    return polys
}

func subdivideTriBordAEcho(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    var polys   = subdivideTriBordA(points: points, sidesTotal: sidesTotal, params: params)
    let insetPts = bordInsetPoints(points: points, params: params)
    polys.append(Polygon2D(points: insetPts, type: .spline))
    return polys
}

// MARK: - TRI_BORD_B
//
// N side triangles. Each triangle spans one complete outer bezier side and
// converges on the midpoint of the corresponding inset bezier side.

func subdivideTriBordB(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let outerSides  = BezierMath.extractSides(points, sidesTotal: sidesTotal)
    let insetPts    = bordInsetPoints(points: points, params: params)
    let innerSides  = BezierMath.extractSides(insetPts, sidesTotal: sidesTotal)
    let insetMids   = innerMidPoints(sides: innerSides, sidesTotal: sidesTotal, params: params)
    let cp          = params.controlPointRatios
    var polys       = [Polygon2D]()
    polys.reserveCapacity(sidesTotal)

    for i in 0..<sidesTotal {
        let o    = outerSides[i]
        let iMid = insetMids[i]

        var s1 = BezierMath.connector(from: o[3], to: iMid, cpRatios: cp)
        var s2 = BezierMath.connector(from: iMid, to: o[0], cpRatios: cp)

        let sign = params.curvatureSign(forIndex: i)
        if sign != 0.0 {
            s1 = BezierMath.applyOuterBow(to: s1, sourceEdge: o, sign: sign)
            s2 = BezierMath.applyOuterBow(to: s2, sourceEdge: o, sign: sign)
        }

        polys.append(Polygon2D(points: o + s1 + s2, type: .spline))
    }
    return polys
}

func subdivideTriBordBEcho(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    var polys    = subdivideTriBordB(points: points, sidesTotal: sidesTotal, params: params)
    let insetPts = bordInsetPoints(points: points, params: params)
    polys.append(Polygon2D(points: insetPts, type: .spline))
    return polys
}

// MARK: - TRI_BORD_C
//
// 3N triangles. Each outer bezier side is split at parameter t, producing a
// midpoint M. Three triangles per side:
//   Tri 1 (left):   outer[i].start → M → inner[i].start
//   Tri 2 (centre): M → inner[i].end → inner[i].start  (using reversed inset side)
//   Tri 3 (right):  M → outer[i].end → inner[i].end

func subdivideTriBordC(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let outerSides = BezierMath.extractSides(points, sidesTotal: sidesTotal)
    let insetPts   = bordInsetPoints(points: points, params: params)
    let innerSides = BezierMath.extractSides(insetPts, sidesTotal: sidesTotal)
    let cp         = params.controlPointRatios
    var polys      = [Polygon2D]()
    polys.reserveCapacity(sidesTotal * 3)

    for i in 0..<sidesTotal {
        let t = params.splitRatio(forSideIndex: i)
        let (outerL, outerR) = BezierMath.split(seg: outerSides[i], t: t)
        let midpoint = outerL[3]
        let scaledStart = innerSides[i][0]
        let scaledEnd   = innerSides[i][3]

        let sign = params.curvatureSign(forIndex: i)
        let src  = outerSides[i]

        var t1s1 = BezierMath.connector(from: midpoint,          to: scaledStart,      cpRatios: cp)
        var t1s2 = BezierMath.connector(from: scaledStart,       to: outerSides[i][0], cpRatios: cp)
        var t2s0 = BezierMath.connector(from: midpoint,          to: scaledEnd,        cpRatios: cp)
        var t2s2 = BezierMath.connector(from: scaledStart,       to: midpoint,         cpRatios: cp)
        var t3s1 = BezierMath.connector(from: outerSides[i][3],  to: scaledEnd,        cpRatios: cp)
        var t3s2 = BezierMath.connector(from: scaledEnd,         to: midpoint,         cpRatios: cp)

        if sign != 0.0 {
            t1s1 = BezierMath.applyOuterBow(to: t1s1, sourceEdge: src, sign: sign)
            t1s2 = BezierMath.applyOuterBow(to: t1s2, sourceEdge: src, sign: sign)
            t2s0 = BezierMath.applyOuterBow(to: t2s0, sourceEdge: src, sign: sign)
            t2s2 = BezierMath.applyOuterBow(to: t2s2, sourceEdge: src, sign: sign)
            t3s1 = BezierMath.applyOuterBow(to: t3s1, sourceEdge: src, sign: sign)
            t3s2 = BezierMath.applyOuterBow(to: t3s2, sourceEdge: src, sign: sign)
        }

        polys.append(Polygon2D(points: outerL + t1s1 + t1s2, type: .spline))
        polys.append(Polygon2D(points: t2s0 + BezierMath.reverseSegment(innerSides[i]) + t2s2, type: .spline))
        polys.append(Polygon2D(points: outerR + t3s1 + t3s2, type: .spline))
    }
    return polys
}

func subdivideTriBordCEcho(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    var polys    = subdivideTriBordC(points: points, sidesTotal: sidesTotal, params: params)
    let insetPts = bordInsetPoints(points: points, params: params)
    polys.append(Polygon2D(points: insetPts, type: .spline))
    return polys
}

// MARK: - Private helpers

/// Midpoints on outer bezier sides at the split ratio.
private func outerMidPoints(
    sides: [[Vector2D]],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Vector2D] {
    (0..<sidesTotal).map { i in
        let t = params.splitRatio(forSideIndex: i)
        return BezierMath.point(seg: sides[i], t: t)
    }
}

/// Midpoints on inset (inner) bezier sides.
private func innerMidPoints(
    sides: [[Vector2D]],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Vector2D] {
    (0..<sidesTotal).map { i in
        let t = params.splitRatio(forSideIndex: i)
        return BezierMath.point(seg: sides[i], t: t)
    }
}

/// Scale a spline polygon's points using insetTransform around its anchor centre.
private func bordInsetPoints(points: [Vector2D], params: SubdivisionParams) -> [Vector2D] {
    let centre = BezierMath.centreSpline(points)
    return BezierMath.insetPoints(points, transform: params.insetTransform, centre: centre)
}

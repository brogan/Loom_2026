// MARK: - TRI_STAR
//
// N+1 polygons: N "spike" triangles + 1 inner polygon.
// Each spike triangle: outerAnchor[i] → insetMid[i-1] → insetMid[i].
// Inner polygon connects consecutive inset midpoints.

func subdivideTriStar(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let outerSides = BezierMath.extractSides(points, sidesTotal: sidesTotal)
    let centre     = BezierMath.centreSpline(points)
    let insetPts   = BezierMath.insetPoints(points, transform: params.insetTransform, centre: centre)
    let innerSides = BezierMath.extractSides(insetPts, sidesTotal: sidesTotal)
    let mids       = starInsetMidPoints(sides: innerSides, sidesTotal: sidesTotal, params: params)

    var polys = [Polygon2D]()
    polys.reserveCapacity(sidesTotal + 1)

    // N star triangles
    for i in 0..<sidesTotal {
        let prev      = (i + sidesTotal - 1) % sidesTotal
        let outerAnch = outerSides[i][0]
        let prevMid   = mids[prev]
        let currMid   = mids[i]

        var s0 = params.connector(from: outerAnch, to: prevMid,   centre: centre)
        var s1 = params.connector(from: prevMid,   to: currMid,   centre: centre)
        var s2 = params.connector(from: currMid,   to: outerAnch, centre: centre)

        let sign = params.curvatureSign(forIndex: i)
        if sign != 0.0 {
            s0 = BezierMath.applyOuterBow(to: s0, sourceEdge: outerSides[prev], sign: sign)
            s1 = BezierMath.applyOuterBow(to: s1, sourceEdge: outerSides[i],    sign: sign)
            s2 = BezierMath.applyOuterBow(to: s2, sourceEdge: outerSides[i],    sign: sign)
        }

        polys.append(Polygon2D(points: s0 + s1 + s2, type: .spline))
    }

    // 1 inner polygon
    polys.append(innerRingPoly(mids: mids, sidesTotal: sidesTotal, params: params))
    return polys
}

// MARK: - TRI_STAR_FILL
//
// 2N+1 polygons: N star tris + N fill tris + 1 inner polygon.
// Point list is reversed before processing (matches Scala SplineTriStarFill).

func subdivideTriStarFill(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let revPts     = points.reversed() as [Vector2D]
    let outerSides = BezierMath.extractSides(revPts, sidesTotal: sidesTotal)
    let centre     = BezierMath.centreSpline(revPts)
    let insetPts   = BezierMath.insetPoints(revPts, transform: params.insetTransform, centre: centre)
    let innerSides = BezierMath.extractSides(insetPts, sidesTotal: sidesTotal)
    let mids       = starInsetMidPoints(sides: innerSides, sidesTotal: sidesTotal, params: params)

    var polys = [Polygon2D]()
    polys.reserveCapacity(sidesTotal * 2 + 1)

    for i in 0..<sidesTotal {
        let prev      = (i + sidesTotal - 1) % sidesTotal
        let outerAnch = outerSides[i][0]
        let currMid   = mids[i]
        let prevMid   = mids[prev]

        var st0 = params.connector(from: outerAnch, to: currMid,   centre: centre)
        var st1 = params.connector(from: currMid,   to: prevMid,   centre: centre)
        var st2 = params.connector(from: prevMid,   to: outerAnch, centre: centre)

        var ft1 = params.connector(from: outerSides[i][3], to: currMid,   centre: centre)
        var ft2 = params.connector(from: currMid,          to: outerAnch, centre: centre)

        let sign = params.curvatureSign(forIndex: i)
        if sign != 0.0 {
            st0 = BezierMath.applyOuterBow(to: st0, sourceEdge: outerSides[i],    sign: sign)
            st1 = BezierMath.applyOuterBow(to: st1, sourceEdge: outerSides[i],    sign: sign)
            st2 = BezierMath.applyOuterBow(to: st2, sourceEdge: outerSides[prev], sign: sign)
            ft1 = BezierMath.applyOuterBow(to: ft1, sourceEdge: outerSides[i],    sign: sign)
            ft2 = BezierMath.applyOuterBow(to: ft2, sourceEdge: outerSides[i],    sign: sign)
        }

        polys.append(Polygon2D(points: st0 + st1 + st2, type: .spline))
        polys.append(Polygon2D(points: outerSides[i] + ft1 + ft2, type: .spline))
    }

    polys.append(innerRingPoly(mids: mids, sidesTotal: sidesTotal, params: params))
    return polys
}

// MARK: - Private helpers

/// Midpoints on inset bezier sides (used as star points).
private func starInsetMidPoints(
    sides: [[Vector2D]],
    sidesTotal: Int,
    params: SubdivisionParams
) -> [Vector2D] {
    (0..<sidesTotal).map { i in
        let t = params.splitRatio(forSideIndex: i)
        return BezierMath.point(seg: sides[i], t: t)
    }
}

/// Inner ring polygon connecting consecutive midpoints.
private func innerRingPoly(
    mids: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams
) -> Polygon2D {
    let ringCentre = BezierMath.centreLine(mids)
    var pts = [Vector2D]()
    pts.reserveCapacity(sidesTotal * 4)
    for i in 0..<sidesTotal {
        let next = (i + 1) % sidesTotal
        pts += params.connector(from: mids[i], to: mids[next], centre: ringCentre)
    }
    return Polygon2D(points: pts, type: .spline)
}

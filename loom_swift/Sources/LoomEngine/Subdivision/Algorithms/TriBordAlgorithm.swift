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
        let prev   = (i + sidesTotal - 1) % sidesTotal
        let corner = sides[i][0]
        let midI   = mids[i]
        let midPrev = mids[prev]

        let s0 = BezierMath.connector(from: corner, to: midI,    cpRatios: cp)
        let s1 = BezierMath.connector(from: midI,   to: midPrev, cpRatios: cp)
        let s2 = BezierMath.connector(from: midPrev, to: corner,  cpRatios: cp)
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

        // Side 0: outer bezier side
        let s0 = o
        // Side 1: outer[i].end → insetMid[i]
        let s1 = BezierMath.connector(from: o[3], to: iMid, cpRatios: cp)
        // Side 2: insetMid[i] → outer[i].start
        let s2 = BezierMath.connector(from: iMid, to: o[0], cpRatios: cp)
        polys.append(Polygon2D(points: s0 + s1 + s2, type: .spline))
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

        // Tri 1: left outer → midpoint → inner start → outer start
        let t1s0 = outerL
        let t1s1 = BezierMath.connector(from: midpoint,    to: scaledStart,          cpRatios: cp)
        let t1s2 = BezierMath.connector(from: scaledStart, to: outerSides[i][0],     cpRatios: cp)
        polys.append(Polygon2D(points: t1s0 + t1s1 + t1s2, type: .spline))

        // Tri 2: midpoint → inner end (reversed inset side) → inner start → midpoint
        let t2s0 = BezierMath.connector(from: midpoint,    to: scaledEnd,   cpRatios: cp)
        let t2s1 = BezierMath.reverseSegment(innerSides[i])
        let t2s2 = BezierMath.connector(from: scaledStart, to: midpoint,    cpRatios: cp)
        polys.append(Polygon2D(points: t2s0 + t2s1 + t2s2, type: .spline))

        // Tri 3: right outer → outer end → inner end → midpoint
        let t3s0 = outerR
        let t3s1 = BezierMath.connector(from: outerSides[i][3], to: scaledEnd, cpRatios: cp)
        let t3s2 = BezierMath.connector(from: scaledEnd,        to: midpoint,  cpRatios: cp)
        polys.append(Polygon2D(points: t3s0 + t3s1 + t3s2, type: .spline))
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

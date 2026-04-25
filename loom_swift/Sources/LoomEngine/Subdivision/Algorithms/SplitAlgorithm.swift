import Foundation

// MARK: - Split orientation

enum SplitOrientation {
    case vertical    // cut most-horizontal side pair → vertical split line
    case horizontal  // cut most-vertical side pair → horizontal split line
    case diagonal    // cut most-diagonal side pair
}

// MARK: - Public entry points

func subdivideSplit(
    points: [Vector2D],
    sidesTotal: Int,
    params: SubdivisionParams,
    orientation: SplitOrientation
) -> [Polygon2D] {

    let rotation = findBestSideOffset(points: points, sidesTotal: sidesTotal, orientation: orientation)
    let shifted  = rotateSideOffset(points, by: rotation, sidesTotal: sidesTotal)
    let sides    = BezierMath.extractSides(shifted, sidesTotal: sidesTotal)
    return performSplit(sides: sides, sidesTotal: sidesTotal, params: params)
}

// MARK: - Orientation search

/// Returns the side-index rotation that places the best-matching edge pair at indices 0 and N/2.
private func findBestSideOffset(
    points: [Vector2D],
    sidesTotal n: Int,
    orientation: SplitOrientation
) -> Int {
    guard n >= 3 else { return 0 }
    let half  = n / 2
    let sides = BezierMath.extractSides(points, sidesTotal: n)

    if n % 2 == 0 {
        var bestIdx   = 0
        var bestScore = -1.0
        for i in 0..<half {
            let dx_i = abs(sides[i][3].x - sides[i][0].x)
            let dy_i = abs(sides[i][3].y - sides[i][0].y)
            let dx_h = abs(sides[i + half][3].x - sides[i + half][0].x)
            let dy_h = abs(sides[i + half][3].y - sides[i + half][0].y)
            let score: Double
            switch orientation {
            case .vertical:   score = (dx_i + dx_h) / (dy_i + dy_h + 1e-9)
            case .horizontal: score = (dy_i + dy_h) / (dx_i + dx_h + 1e-9)
            case .diagonal:
                let dx = dx_i + dx_h; let dy = dy_i + dy_h
                score = min(dx, dy) / (max(dx, dy) + 1e-9)
            }
            if score > bestScore { bestScore = score; bestIdx = i }
        }
        return bestIdx
    } else {
        var bestIdx   = 0
        var bestScore = -1.0
        for k in 0..<n {
            let anchor  = sides[k][0]
            let oppSide = sides[(k + half) % n]
            let midX    = (oppSide[0].x + oppSide[3].x) / 2.0
            let midY    = (oppSide[0].y + oppSide[3].y) / 2.0
            let dx = abs(anchor.x - midX)
            let dy = abs(anchor.y - midY)
            let score: Double
            switch orientation {
            case .vertical:   score = dy / (dx + 1e-9)
            case .horizontal: score = dx / (dy + 1e-9)
            case .diagonal:   score = min(dx, dy) / (max(dx, dy) + 1e-9)
            }
            if score > bestScore { bestScore = score; bestIdx = k }
        }
        return bestIdx
    }
}

/// Rotate the flat point list by `sideOffset` sides.
private func rotateSideOffset(_ pts: [Vector2D], by sideOffset: Int, sidesTotal: Int) -> [Vector2D] {
    guard sideOffset > 0 else { return pts }
    let shift = sideOffset * 4
    return Array(pts[shift...]) + Array(pts[..<shift])
}

// MARK: - Split geometry

private func performSplit(
    sides: [[Vector2D]],
    sidesTotal n: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    if n % 2 == 0 {
        return splitEven(sides: sides, n: n, params: params)
    } else {
        return splitOdd(sides: sides, n: n, params: params)
    }
}

/// Even N: split sides[0] at t0 and sides[N/2] at tH.
private func splitEven(
    sides: [[Vector2D]],
    n: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let half = n / 2
    let t0   = params.lineRatios.x
    let tH   = params.continuous ? params.lineRatios.y : params.lineRatios.x
    let cp   = params.controlPointRatios

    let (left0,  right0)  = BezierMath.split(seg: sides[0],    t: t0)
    let (leftH,  rightH)  = BezierMath.split(seg: sides[half], t: tH)
    let mid0 = left0[3]
    let midH = leftH[3]

    // Poly 1: right0, sides[1..<half], leftH, connector(midH→mid0)
    var pts1 = right0
    for s in 1..<half { pts1 += sides[s] }
    pts1 += leftH
    pts1 += BezierMath.connector(from: midH, to: mid0, cpRatios: cp)

    // Poly 2: rightH, sides[half+1..<n], left0, connector(mid0→midH)
    var pts2 = rightH
    for s in (half + 1)..<n { pts2 += sides[s] }
    pts2 += left0
    pts2 += BezierMath.connector(from: mid0, to: midH, cpRatios: cp)

    return [
        Polygon2D(points: pts1, type: .spline),
        Polygon2D(points: pts2, type: .spline)
    ]
}

/// Odd N: split sides[N/2] at t. Poly 1 starts from anchor[0].
private func splitOdd(
    sides: [[Vector2D]],
    n: Int,
    params: SubdivisionParams
) -> [Polygon2D] {
    let half    = n / 2
    let t       = params.lineRatios.x
    let cp      = params.controlPointRatios
    let anchor0 = sides[0][0]

    let (leftH, rightH) = BezierMath.split(seg: sides[half], t: t)
    let midH = leftH[3]

    // Poly 1: sides[0..<half], leftH, connector(midH→anchor0)
    var pts1 = [Vector2D]()
    for s in 0..<half { pts1 += sides[s] }
    pts1 += leftH
    pts1 += BezierMath.connector(from: midH, to: anchor0, cpRatios: cp)

    // Poly 2: rightH, sides[half+1..<n], connector(anchor0→midH)
    var pts2 = rightH
    for s in (half + 1)..<n { pts2 += sides[s] }
    pts2 += BezierMath.connector(from: anchor0, to: midH, cpRatios: cp)

    return [
        Polygon2D(points: pts1, type: .spline),
        Polygon2D(points: pts2, type: .spline)
    ]
}

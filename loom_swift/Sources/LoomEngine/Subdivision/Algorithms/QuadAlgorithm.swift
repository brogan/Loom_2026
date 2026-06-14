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
        let (l, r): ([Vector2D], [Vector2D])
        if params.curveAwareSplit {
            // De Casteljau: split point lies on the Bézier curve at parameter t.
            // Preserves outer curvature but may drift on higher subdivision levels.
            (l, r) = BezierMath.split(seg: sides[i], t: t)
        } else {
            // Scala-compatible: split point is the linear lerp of the two anchors.
            // Avoids cumulative drift; straight edges stay straight.
            (l, r) = BezierMath.scalaSplit(seg: sides[i], t: t)
        }
        lefts[i]  = l
        rights[i] = r
        splits[i] = l[3]
    }

    // Internal edges from each split point to the centre.
    // When mirrorOuterCurvature is on, the control points on each internal edge
    // are offset to echo the curvature of the adjacent outer edge at that split point.
    var internalSides: [[Vector2D]] = splits.map { m in
        params.connector(from: m, to: centre, centre: centre)
    }

    if params.mirrorOuterCurvature {
        let sign: Double = params.invertCurvature ? -1.0 : 1.0
        for i in 0..<sidesTotal {
            // Apply curvatureSync gating.
            let applySign: Double
            switch params.curvatureSync {
            case "EVEN":      applySign = (i % 2 == 0) ? sign : 0.0
            case "ODD":       applySign = (i % 2 == 1) ? sign : 0.0
            case "ALTERNATE": applySign = (i % 2 == 0) ? sign : -sign
            default:          applySign = sign   // "ALL"
            }
            guard applySign != 0.0 else { continue }

            // Outer bow: deviation of the last CP before M_i from the A_i→M_i straight line.
            // lefts[i] = [A_i, cp1, cp2, M_i]; the bow is at cp2 (near M_i end).
            let a = lefts[i][0]; let m = lefts[i][3]
            let straightCP2 = Vector2D.lerp(a, m, t: 2.0 / 3.0)
            let bow = (lefts[i][2] - straightCP2) * applySign

            // Scale bow proportionally to internal edge length vs outer half-edge length.
            let outerLen = ((m.x-a.x)*(m.x-a.x) + (m.y-a.y)*(m.y-a.y)).squareRoot()
            let innerLen = ((centre.x-m.x)*(centre.x-m.x) + (centre.y-m.y)*(centre.y-m.y)).squareRoot()
            let scaledBow = outerLen > 1e-12 ? bow * (innerLen / outerLen) : bow

            // Apply to both control points of the internal edge [M, cp1, cp2, C].
            internalSides[i][1] = internalSides[i][1] + scaledBow
            internalSides[i][2] = internalSides[i][2] + scaledBow
        }
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

import Foundation

/// Post-subdivision polygon-level transforms controlled by `SubdivisionParams`.
///
/// Called by `SubdivisionEngine.subdivide` after the subdivision algorithm
/// and visibility rule have been applied.
///
/// ### PTW — whole-polygon transform (`polysTranformWhole`)
///
/// For each *visible* child polygon (subject to `pTW_probability`):
/// 1. Optionally jitter the pivot centre (`pTW_randomCentreDivisor`).
/// 2. Apply the deterministic `pTW_transform` (InsetTransform) around the pivot.
/// 3. Optionally add random translation (`pTW_randomTranslation`).
/// 4. Optionally apply random per-axis scale around the pivot (`pTW_randomScale`).
/// 5. Optionally apply random rotation around the pivot (`pTW_randomRotation`).
///
/// When `pTW_commonCentre` is true all polygons share a single pivot — the
/// average of all visible centroids.  Otherwise each polygon uses its own centroid.
///
/// ### PTP — per-point transform (`polysTransformPoints`)
///
/// For each visible child polygon (subject to `pTP_probability`), each point is
/// independently displaced by a random amount sampled from
/// `pTW_randomTranslationRange`.
enum PolygonTransforms {

    // MARK: - Public entry point

    /// Apply PTW and/or PTP transforms from `params` to `polygons`.
    ///
    /// Returns `polygons` unchanged if `params.polysTransform` is `false`.
    static func apply<G: RandomNumberGenerator>(
        _ polygons: [Polygon2D],
        params: SubdivisionParams,
        rng: inout G
    ) -> [Polygon2D] {
        guard params.polysTransform else { return polygons }

        var result = polygons

        if params.polysTranformWhole {
            result = applyWhole(result, params: params, rng: &rng)
        }

        if params.polysTransformPoints {
            result = applyPoints(result, params: params, rng: &rng)
        }

        return result
    }

    // MARK: - PTW

    private static func applyWhole<G: RandomNumberGenerator>(
        _ polygons: [Polygon2D],
        params: SubdivisionParams,
        rng: inout G
    ) -> [Polygon2D] {
        // Optionally compute one shared pivot for all polygons.
        let sharedPivot: Vector2D? = params.pTW_commonCentre
            ? commonCentre(polygons)
            : nil

        return polygons.map { poly in
            guard poly.visible else { return poly }
            guard Double.random(in: 0..<100, using: &rng) < params.pTW_probability else { return poly }

            let pivot = sharedPivot ?? poly.centroid
            return applyWholeToPoly(poly, pivot: pivot, params: params, rng: &rng)
        }
    }

    private static func applyWholeToPoly<G: RandomNumberGenerator>(
        _ poly: Polygon2D,
        pivot: Vector2D,
        params: SubdivisionParams,
        rng: inout G
    ) -> Polygon2D {
        // 1. Optionally jitter the pivot itself before any transform.
        //    Magnitude: ±(distance from pivot to first point / divisor).
        var effectivePivot = pivot
        if params.pTW_randomCentreDivisor > 0, !poly.points.isEmpty {
            let dist  = pivot.distance(to: poly.points[0])
            let range = dist / max(params.pTW_randomCentreDivisor, 1e-12)
            if range > 0 {
                let dx = Double.random(in: -range...range, using: &rng)
                let dy = Double.random(in: -range...range, using: &rng)
                effectivePivot = Vector2D(x: pivot.x + dx, y: pivot.y + dy)
            }
        }

        // 2. Deterministic inset transform (scale + translate + rotate around pivot).
        var pts = poly.points.map { params.pTW_transform.apply(to: $0, around: effectivePivot) }
        var result = Polygon2D(points: pts, type: poly.type,
                                pressures: poly.pressures, visible: poly.visible)

        // 3. Random translation.
        if params.pTW_randomTranslation {
            let tx = randomDouble(in: params.pTW_randomTranslationRange.x, using: &rng)
            let ty = randomDouble(in: params.pTW_randomTranslationRange.y, using: &rng)
            result = result.translated(by: Vector2D(x: tx, y: ty))
        }

        // 4. Random per-axis scale around the (jittered) pivot.
        if params.pTW_randomScale {
            let sx = randomDouble(in: params.pTW_randomScaleRange.x, using: &rng)
            let sy = randomDouble(in: params.pTW_randomScaleRange.y, using: &rng)
            result = result.scaled(by: Vector2D(x: sx, y: sy), around: effectivePivot)
        }

        // 5. Random rotation around the (jittered) pivot.
        if params.pTW_randomRotation {
            let angle = randomDouble(in: params.pTW_randomRotationRange, using: &rng)
            result = result.rotated(by: angle, around: effectivePivot)
        }

        return result
    }

    // MARK: - PTP

    private static func applyPoints<G: RandomNumberGenerator>(
        _ polygons: [Polygon2D],
        params: SubdivisionParams,
        rng: inout G
    ) -> [Polygon2D] {
        if let ts = params.ptpTransformSet, ts.hasAnyEnabled {
            // InnerControlPoints operates on the full array; handle it first so its
            // cross-polygon pairing sees unmodified anchor positions from the other transforms.
            var result = polygons

            // Per-polygon transforms (probability checked inside).
            result = result.map { poly in
                guard poly.visible else { return poly }
                guard Double.random(in: 0..<100, using: &rng) < params.pTP_probability
                else { return poly }
                return applyPTPTransformSet(poly, transformSet: ts)
            }

            // Full-array transform.
            if ts.innerControlPoints.enabled {
                result = applyInnerControlPointsToArray(result, config: ts.innerControlPoints)
            }

            return result
        }

        // Legacy: simple random-translation path.
        return polygons.map { poly in
            guard poly.visible else { return poly }
            guard Double.random(in: 0..<100, using: &rng) < params.pTP_probability else { return poly }

            let pts = poly.points.map { pt -> Vector2D in
                let tx = randomDouble(in: params.pTW_randomTranslationRange.x, using: &rng)
                let ty = randomDouble(in: params.pTW_randomTranslationRange.y, using: &rng)
                return pt.translated(by: Vector2D(x: tx, y: ty))
            }
            return Polygon2D(points: pts, type: poly.type,
                             pressures: poly.pressures, visible: poly.visible)
        }
    }

    // MARK: - Structured PTP (per-polygon transforms)

    /// Apply all per-polygon PTP transforms to a single polygon.
    ///
    /// `centreIndex` is derived from point count:
    ///  - 12 pts (3-sided TRI_STAR): index 4  (Scala: `val centreIndex = 4`)
    ///  - 16 pts (4-sided QUAD/TRI): index 8  (Scala: `val centreIndex = points.length/2`)
    ///
    /// `InnerControlPoints` is NOT applied here — it requires the full polygon array
    /// and is handled separately in `applyPoints`.
    private static func applyPTPTransformSet(_ poly: Polygon2D,
                                              transformSet ts: PTPTransformSet) -> Polygon2D {
        let n = poly.points.count
        guard n >= 12 else { return poly }
        let centreIndex = n == 12 ? 4 : n / 2
        guard centreIndex < n else { return poly }

        var pts = poly.points

        if ts.exteriorAnchors.enabled {
            applyExteriorAnchors(&pts, centreIndex: centreIndex, config: ts.exteriorAnchors)
        }
        if ts.centralAnchors.enabled {
            guard centreIndex >= 1 && centreIndex + 1 < n else { return poly }
            applyCentralAnchors(&pts, centreIndex: centreIndex, config: ts.centralAnchors,
                                numSidesPerPoly: n / 4)
        }
        if ts.outerControlPoints.enabled {
            applyOuterControlPoints(&pts, centreIndex: centreIndex, config: ts.outerControlPoints)
        }
        if ts.anchorsLinkedToCentre.enabled {
            applyAnchorsLinkedToCentre(&pts, centreIndex: centreIndex,
                                       config: ts.anchorsLinkedToCentre)
        }

        return Polygon2D(points: pts, type: poly.type,
                         pressures: poly.pressures, visible: poly.visible)
    }

    /// Spike exterior anchor pairs away from the centre reference point.
    ///
    /// Mirrors Scala `ExteriorAnchors.spike`:
    ///  - Collects all anchor endpoints (i%4==0 or i%4==3) into pairs.
    ///  - For each pair: `spikePos = lerp(pair[0], pts[centreIndex], spikeFactor)`.
    ///  - Negative spikeFactor → anchor moves away from centrePoint (outward spike).
    ///  - SYMMETRICAL type: both pair members set to spikePos.
    private static func applyExteriorAnchors(_ pts: inout [Vector2D],
                                              centreIndex: Int,
                                              config ea: ExteriorAnchorsTransform) {
        let n = pts.count
        let centre = pts[centreIndex]

        // Collect anchor indices (i%4==0 or i%4==3).
        var anchorIdx = [Int]()
        for i in 0..<n where i % 4 == 0 || i % 4 == 3 { anchorIdx.append(i) }
        guard !anchorIdx.isEmpty else { return }

        // Build pairs: [last, first] then [1,2], [3,4], ...
        var pairs = [(Int, Int)]()
        pairs.append((anchorIdx.last!, anchorIdx.first!))
        var k = 1
        while k < anchorIdx.count - 1 {
            pairs.append((anchorIdx[k], anchorIdx[k + 1]))
            k += 2
        }

        // Optionally filter by whichSpike setting.
        // CORNERS = only the first pair (the corner anchor); MIDDLES = all others.
        let activePairs: [(Int, Int)]
        switch ea.whichSpike {
        case "CORNERS":
            activePairs = pairs.isEmpty ? [] : [pairs[0]]
        case "MIDDLES":
            activePairs = pairs.count > 1 ? Array(pairs.dropFirst()) : []
        default: // "ALL"
            activePairs = pairs
        }

        for (i0, i1) in activePairs {
            let spikeFactor = ea.spikeFactor
            let spikePos    = Vector2D.lerp(pts[i0], centre, t: spikeFactor)
            let diff        = spikePos - pts[i0]

            switch ea.spikeAxis {
            case "X":
                let sp = Vector2D(x: spikePos.x, y: pts[i0].y)
                let d  = Vector2D(x: diff.x, y: 0)
                applySpike(&pts, i0: i0, i1: i1, spikePos: sp, diff: d, type: ea.spikeType)
            case "Y":
                let sp = Vector2D(x: pts[i0].x, y: spikePos.y)
                let d  = Vector2D(x: 0, y: diff.y)
                applySpike(&pts, i0: i0, i1: i1, spikePos: sp, diff: d, type: ea.spikeType)
            default: // "XY"
                applySpike(&pts, i0: i0, i1: i1, spikePos: spikePos, diff: diff,
                           type: ea.spikeType)
            }
        }
    }

    private static func applySpike(_ pts: inout [Vector2D],
                                    i0: Int, i1: Int,
                                    spikePos: Vector2D, diff: Vector2D,
                                    type spikeType: String) {
        switch spikeType {
        case "RIGHT":
            pts[i0] = spikePos
        case "LEFT":
            pts[i1] = spikePos
        default: // "SYMMETRICAL"
            pts[i0] = spikePos
            pts[i1] = spikePos
        }
        _ = diff  // used only when cpsFollow is true (not yet needed)
    }

    /// Tear central anchor pairs toward an outside reference point.
    ///
    /// Mirrors Scala `CentralAnchors.tearCentre`:
    ///  - Centre anchors: pts[centreIndex-1] and pts[centreIndex].
    ///  - Outside reference for TRI+DIAGONAL: midpoint(pts[0], pts[3]).
    ///  - `tearPos = lerp(centreAnchor, outsideRef, tearFactor)`.
    ///  - XY mode: both centre anchors set to tearPos.
    private static func applyCentralAnchors(_ pts: inout [Vector2D],
                                             centreIndex: Int,
                                             config ca: CentralAnchorsTransform,
                                             numSidesPerPoly: Int) {
        let a0 = pts[centreIndex - 1]  // first centre anchor
        let n  = pts.count

        // Compute outside reference (matches Scala's getOutsideRefs).
        let outsideRef: Vector2D
        if numSidesPerPoly == 3 {
            // TRI_STAR: diagonal = midpoint of pts[0] (outerAnch) and pts[3] (prevMid).
            switch ca.tearDirection {
            case "LEFT":
                outsideRef = pts[0]
            case "RIGHT":
                outsideRef = pts[3]
            default: // "DIAGONAL"
                outsideRef = Vector2D.lerp(pts[0], pts[3], t: 0.5)
            }
        } else {
            // QUAD: diagonal = pts[0]; left/right = adjacent split points.
            switch ca.tearDirection {
            case "LEFT":
                let nextIdx = min(centreIndex + 4, n - 1)
                outsideRef = pts[nextIdx]
            case "RIGHT":
                let prevIdx = max(centreIndex - 4, 0)
                outsideRef = pts[prevIdx]
            default: // "DIAGONAL"
                outsideRef = pts[0]
            }
        }

        let tearPos = Vector2D.lerp(a0, outsideRef, t: ca.tearFactor)
        let diff    = tearPos - a0

        switch ca.tearAxis {
        case "X":
            let tp = Vector2D(x: tearPos.x, y: a0.y)
            pts[centreIndex - 1] = tp
            pts[centreIndex]     = tp
        case "Y":
            let tp = Vector2D(x: a0.x, y: tearPos.y)
            pts[centreIndex - 1] = tp
            pts[centreIndex]     = tp
        default: // "XY"
            pts[centreIndex - 1] = tearPos
            pts[centreIndex]     = tearPos
        }

        if ca.cpsFollow {
            // Move control points flanking the centre: centreIndex-2 and centreIndex+1
            let ci2 = centreIndex - 2
            let ci1 = centreIndex + 1
            let mult = ca.cpsFollowMultiplier
            if ci2 >= 0 {
                pts[ci2] = pts[ci2].translated(by: Vector2D(x: diff.x * mult,
                                                             y: diff.y * mult))
            }
            if ci1 < n {
                pts[ci1] = pts[ci1].translated(by: Vector2D(x: diff.x * mult,
                                                             y: diff.y * mult))
            }
        }
    }

    // MARK: - OuterControlPoints

    /// Curves the two outer control points on each exterior edge of a subdivided polygon.
    ///
    /// Mirrors Scala `OuterControlPoints.curve`.
    /// For QUAD (16-pt): processes pairs at indices [1,2] and [13,14].
    /// For TRI  (12-pt): processes pair at indices [1,2].
    private static func applyOuterControlPoints(_ pts: inout [Vector2D],
                                                 centreIndex: Int,
                                                 config: OuterControlPointsTransform) {
        let n = pts.count
        // Outer edge control point pairs: (idx0, idx1) where anchor1=pts[idx0-1], anchor2=pts[idx1+1].
        let pairs: [(Int, Int)] = n == 12 ? [(1, 2)] : [(1, 2), (13, 14)]
        let centre = pts[centreIndex]

        for (i, (idx0, idx1)) in pairs.enumerated() {
            guard idx0 >= 1, idx1 + 1 < n else { continue }

            let anchor1 = pts[idx0 - 1]
            let anchor2 = pts[idx1 + 1]
            let mid = Vector2D.lerp(anchor1, anchor2, t: 0.5)

            var controlA = Vector2D.lerp(anchor1, anchor2, t: config.lineRatioX)
            var controlB = Vector2D.lerp(anchor1, anchor2, t: config.lineRatioY)

            if config.curveMode != "FROM_CENTRE" {
                // PERPENDICULAR mode: offset control points along a perpendicular to the edge.
                let centreToMid = mid - centre
                let orientation = vectorOrientation(centreToMid)
                // diffVectA = differenceBetweenTwoVectors(mid, controlA) = controlA - mid
                let diffVectA   = controlA - mid
                let matchPerp   = perpendicularMatchOrientation(diffVectA, orientation: orientation)
                let reversePerp = -matchPerp

                let mMin = config.curveMultiplierMin
                let mMax = config.curveMultiplierMax

                switch config.curveType {
                case "PINCH":
                    controlA = controlA + reversePerp * mMin
                    controlB = controlB + reversePerp * mMax
                case "PUFF_PINCH_PUFF_PINCH":
                    // Same behaviour for both pairs (Scala i%2 branches are identical here).
                    controlA = controlA + matchPerp   * mMin
                    controlB = controlB + reversePerp * mMax
                case "PUFF_PINCH_PINCH_PUFF":
                    if i % 2 == 0 {
                        controlA = controlA + matchPerp   * mMin
                        controlB = controlB + reversePerp * mMax
                    } else {
                        controlA = controlA + reversePerp * mMin
                        controlB = controlB + matchPerp   * mMax
                    }
                case "PINCH_PUFF_PINCH_PUFF":
                    // Same behaviour for both pairs.
                    controlA = controlA + reversePerp * mMin
                    controlB = controlB + matchPerp   * mMax
                case "PINCH_PUFF_PUFF_PINCH":
                    if i % 2 == 0 {
                        controlA = controlA + reversePerp * mMin
                        controlB = controlB + matchPerp   * mMax
                    } else {
                        controlA = controlA + matchPerp   * mMin
                        controlB = controlB + reversePerp * mMax
                    }
                default: // "PUFF"
                    controlA = controlA + matchPerp * mMin
                    controlB = controlB + matchPerp * mMax
                }

            } else {
                // FROM_CENTRE mode: lerp between absolute centre of exterior anchors and mid.
                let absCentre = exteriorAnchorsCentre(pts, centreIndex: centreIndex)
                let curveA    = Vector2D.lerp(absCentre, mid, t: config.curveFromCentreRatioX)
                let diffA     = curveA - absCentre
                controlA      = mid + diffA
                let curveB    = Vector2D.lerp(absCentre, mid, t: config.curveFromCentreRatioY)
                let diffB     = curveB - absCentre
                controlB      = mid + diffB
            }

            pts[idx0] = controlA
            pts[idx1] = controlB
        }
    }

    // MARK: - AnchorsLinkedToCentre

    /// Tears side anchor pairs toward a reference point.
    ///
    /// Mirrors Scala `AnchorsLinkedToCentre.tearSides`.
    /// For QUAD (16-pt, centreIndex=8): side anchors at pts[3,4] and pts[11,12];
    ///   adjacent controls at pts[2,5] and pts[10,13].
    private static func applyAnchorsLinkedToCentre(_ pts: inout [Vector2D],
                                                    centreIndex ci: Int,
                                                    config: AnchorsLinkedToCentreTransform) {
        let n = pts.count
        // Anchor pairs (by index into pts).
        let anchorPairs: [(Int, Int)]
        let controlPairs: [(Int, Int)]

        if n == 12 {
            // TRI (centreIndex=4)
            anchorPairs  = [(ci - 5, ci - 4), (n - 1, 0)]
            controlPairs = [(ci - 6, ci - 3), (n - 1, 0)]  // approximate: TRI control mapping
        } else {
            // QUAD (centreIndex=8): matches Scala getSideAnchorsQuad / getSideControlPointsQuad
            anchorPairs  = [(ci - 5, ci - 4), (ci + 3, ci + 4)]
            controlPairs = [(ci - 6, ci - 3), (ci + 2, ci + 5)]
        }

        for pairIdx in 0..<anchorPairs.count {
            let (a0idx, a1idx) = anchorPairs[pairIdx]
            let (c0idx, c1idx) = controlPairs[pairIdx]
            guard a0idx >= 0, a1idx < n, c0idx >= 0, c1idx < n else { continue }

            let anchor0 = pts[a0idx]

            // Compute reference point based on tearType.
            let ref: Vector2D
            switch config.tearType {
            case "TOWARDS_OPPOSITE_CORNER":
                if pairIdx == 0 {
                    // circularIndex(centreIndex+4, numSidesPerPoly*4) — for QUAD: (8+4) % 16 = 12
                    let idx = circularIndex(ci + 4, total: (n / 4) * 4)
                    ref = pts[idx]
                } else {
                    ref = pts[ci - 4]
                }
            case "TOWARDS_CENTRE":
                ref = pts[ci]
            default: // "TOWARDS_OUTSIDE_CORNER" and "RANDOM" (simplify RANDOM → outside corner)
                ref = pts[0]
            }

            let tearPos = Vector2D.lerp(anchor0, ref, t: config.tearFactor)
            let diff    = tearPos - anchor0

            pts[a0idx] = tearPos
            pts[a1idx] = tearPos

            if config.cpsFollow {
                let mult = config.cpsFollowMultiplier
                pts[c0idx] = pts[c0idx] + diff * mult
                pts[c1idx] = pts[c1idx] + diff * mult
            }
        }
    }

    // MARK: - InnerControlPoints (full-array)

    /// Curves inner control points on the internal subdivision lines.
    ///
    /// Mirrors Scala `InnerControlPoints.curveQuad` (`referToOuter=false` path).
    /// Operates on the full polygon array because each internal line is shared between
    /// two adjacent polygons; the pairing mirrors Scala's `getInnerControlPoints`.
    /// Only QUAD (16-pt) is currently supported.
    ///
    /// Buffer layout per polygon (QUAD, centreIndex=8):
    ///   buf[i*4+0] = pts[ci-3] = pts[5]   (outer inner cp A)
    ///   buf[i*4+1] = pts[ci-2] = pts[6]   (outer inner cp B)
    ///   buf[i*4+2] = pts[ci+1] = pts[9]   (inner inner cp A)
    ///   buf[i*4+3] = pts[ci+2] = pts[10]  (inner inner cp B)
    ///
    /// For internal line i the Scala pairs are:
    ///   controls[i*2][0]   = buf[i*4]                         (poly[i].pts[5])
    ///   controls[i*2][1]   = buf[circularIndex(i*4+7, tot)]   (poly[i+1].pts[10])
    ///   controls[i*2+1][0] = buf[i*4+1]                       (poly[i].pts[6])
    ///   controls[i*2+1][1] = buf[circularIndex(i*4+6, tot)]   (poly[i+1].pts[9])
    private static func applyInnerControlPointsToArray(
        _ polygons: [Polygon2D],
        config: InnerControlPointsTransform
    ) -> [Polygon2D] {
        guard !polygons.isEmpty else { return polygons }
        let n = polygons[0].points.count
        guard n == 16 else { return polygons }
        let ci = n / 2  // = 8

        let sidesTotal = polygons.count
        let tot        = sidesTotal * 4

        // Build flat buffer of inner control points from all polygons.
        var buffer = [Vector2D]()
        buffer.reserveCapacity(tot)
        for poly in polygons {
            let pts = poly.points
            guard pts.count > ci + 2 else { return polygons }
            buffer.append(pts[ci - 3])  // pts[5]
            buffer.append(pts[ci - 2])  // pts[6]
            buffer.append(pts[ci + 1])  // pts[9]
            buffer.append(pts[ci + 2])  // pts[10]
        }

        // Notional midpoints: lerp(pts[ci-3], pts[ci], 0.5) per polygon.
        let mids: [Vector2D] = polygons.map { poly in
            Vector2D.lerp(poly.points[ci - 3], poly.points[ci], t: 0.5)
        }

        // For the `referToOuter=false` path Scala uses hardcoded Range(-2, 2).
        let multMin = -2.0
        let multMax =  2.0

        // Process each internal line using cross-polygon pairing.
        for i in 0..<sidesTotal {
            let bufBase = i * 4
            let idxA0 = bufBase                              // poly[i].pts[5]
            let idxA1 = circularIndex(bufBase + 7, total: tot)  // poly[i+1].pts[10]
            let idxB0 = bufBase + 1                          // poly[i].pts[6]
            let idxB1 = circularIndex(bufBase + 6, total: tot)  // poly[i+1].pts[9]

            let mid = mids[i]
            // diffVect = differenceBetweenTwoVectors(control, mid) = mid - control
            let diffA = mid - buffer[idxA0]
            let diffB = mid - buffer[idxA1]
            let diffC = mid - buffer[idxB0]
            let diffD = mid - buffer[idxB1]
            // inverseVector = swap x,y (Scala Formulas.inverseVector)
            let invA = Vector2D(x: diffA.y, y: diffA.x)
            let invB = Vector2D(x: diffB.y, y: diffB.x)
            let invC = Vector2D(x: diffC.y, y: diffC.x)
            let invD = Vector2D(x: diffD.y, y: diffD.x)

            buffer[idxA0] = buffer[idxA0] + invA * multMin
            buffer[idxA1] = buffer[idxA1] + invB * multMax
            buffer[idxB0] = buffer[idxB0] + invC * multMin
            buffer[idxB1] = buffer[idxB1] + invD * multMax
        }

        // The cross-polygon writes above already implement the EVEN commonLine behaviour:
        // mids[i] (from polygon i) is used for both polygon i's pts[5,6] and
        // polygon[i+1]'s pts[9,10].  No additional commonLine post-processing needed
        // for the non-referToOuter path.

        // Write buffer back to polygon copies.
        return polygons.enumerated().map { (idx, poly) in
            guard poly.visible else { return poly }
            let base = idx * 4
            guard base + 3 < buffer.count, ci - 3 >= 0, ci + 2 < poly.points.count else {
                return poly
            }
            var pts = poly.points
            pts[ci - 3] = buffer[base]      // pts[5]
            pts[ci - 2] = buffer[base + 1]  // pts[6]
            pts[ci + 1] = buffer[base + 2]  // pts[9]
            pts[ci + 2] = buffer[base + 3]  // pts[10]
            return Polygon2D(points: pts, type: poly.type,
                             pressures: poly.pressures, visible: poly.visible)
        }
    }

    // MARK: - Vector helpers

    /// Quadrant of a vector: 0=+x+y, 1=+x-y, 2=-x-y, 3=-x+y.
    /// Matches Scala `Vector2D.getVectorOrientation`.
    private static func vectorOrientation(_ v: Vector2D) -> Int {
        if v.x >= 0 && v.y >= 0 { return 0 }
        if v.x >= 0 && v.y <= 0 { return 1 }
        if v.x <= 0 && v.y <= 0 { return 2 }
        return 3
    }

    /// Perpendicular of `v` (swap x,y) with signs forced to match `orientation` quadrant.
    /// Matches Scala `Formulas.perpendicularVectorMatchOrientation`.
    private static func perpendicularMatchOrientation(_ v: Vector2D, orientation: Int) -> Vector2D {
        var inv = Vector2D(x: v.y, y: v.x)  // swap x and y
        switch orientation {
        case 0:  // +x, +y → both positive
            if inv.x < 0 { inv.x = -inv.x }
            if inv.y < 0 { inv.y = -inv.y }
        case 1:  // +x, -y
            if inv.x < 0 { inv.x = -inv.x }
            if inv.y > 0 { inv.y = -inv.y }
        case 2:  // -x, -y → both negative
            if inv.x > 0 { inv.x = -inv.x }
            if inv.y > 0 { inv.y = -inv.y }
        default: // 3: -x, +y
            if inv.x > 0 { inv.x = -inv.x }
            if inv.y < 0 { inv.y = -inv.y }
        }
        return inv
    }

    /// Average position of exterior anchor points (i%4==0 or i%4==3, excluding centreIndex pair).
    /// Used for the FROM_CENTRE curve mode.
    private static func exteriorAnchorsCentre(_ pts: [Vector2D], centreIndex ci: Int) -> Vector2D {
        var sum = Vector2D.zero
        var count = 0
        for (i, p) in pts.enumerated() where i % 4 == 0 || i % 4 == 3 {
            if i == ci || i == ci - 1 { continue }
            sum = sum + p
            count += 1
        }
        guard count > 0 else { return Vector2D.zero }
        return sum * (1.0 / Double(count))
    }

    /// Modulo index that wraps into [0, total).  Matches Scala `Formulas.circularIndex`.
    private static func circularIndex(_ n: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        if n >= total { return n % total }
        if n < 0      { return total - (abs(n) % total) }
        return n
    }

    // MARK: - Helpers

    /// Arithmetic mean of all visible polygon centroids.
    private static func commonCentre(_ polygons: [Polygon2D]) -> Vector2D {
        let visible = polygons.filter { $0.visible }
        guard !visible.isEmpty else { return .zero }
        let sum = visible.reduce(Vector2D.zero) { acc, poly in
            Vector2D(x: acc.x + poly.centroid.x, y: acc.y + poly.centroid.y)
        }
        return sum.scaled(by: 1.0 / Double(visible.count))
    }

    private static func randomDouble<G: RandomNumberGenerator>(
        in range: FloatRange,
        using rng: inout G
    ) -> Double {
        guard range.min < range.max else { return range.min }
        return Double.random(in: range.min...range.max, using: &rng)
    }
}

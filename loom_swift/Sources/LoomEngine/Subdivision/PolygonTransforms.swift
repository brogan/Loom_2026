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
                               pressures: poly.pressures,
                               pressureProfiles: poly.pressureProfiles,
                               visible: poly.visible)

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
                return applyPTPTransformSet(poly, transformSet: ts, rng: &rng)
            }

            // Full-array transform.
            if ts.innerControlPoints.enabled {
                result = applyInnerControlPointsToArray(result, config: ts.innerControlPoints, rng: &rng)
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
                             pressures: poly.pressures,
                             pressureProfiles: poly.pressureProfiles,
                             visible: poly.visible)
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
    private static func applyPTPTransformSet<G: RandomNumberGenerator>(
        _ poly: Polygon2D,
        transformSet ts: PTPTransformSet,
        rng: inout G
    ) -> Polygon2D {
        let n = poly.points.count
        guard n >= 12 else { return poly }
        let centreIndex = n == 12 ? 4 : n / 2
        guard centreIndex < n else { return poly }

        var pts = poly.points

        if ts.exteriorAnchors.enabled {
            applyExteriorAnchors(&pts, centreIndex: centreIndex, config: ts.exteriorAnchors, rng: &rng)
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
                         pressures: poly.pressures,
                         pressureProfiles: poly.pressureProfiles,
                         visible: poly.visible)
    }

    /// Spike exterior anchor pairs away from the centre reference point.
    /// Implements randomSpike, RANDOM spikeType, cpsFollow, randomCpsFollow,
    /// cpsSqueeze, and randomCpsSqueeze. Mirrors Scala `ExteriorAnchors.spike`.
    private static func applyExteriorAnchors<G: RandomNumberGenerator>(
        _ pts: inout [Vector2D],
        centreIndex: Int,
        config ea: ExteriorAnchorsTransform,
        rng: inout G
    ) {
        let n = pts.count
        let centre = pts[centreIndex]

        // Collect anchor indices (i%4==0 or i%4==3).
        var anchorIdx = [Int]()
        for i in 0..<n where i % 4 == 0 || i % 4 == 3 { anchorIdx.append(i) }
        guard !anchorIdx.isEmpty else { return }

        // Collect CP indices (i%4==1 or i%4==2).
        var cpIdx = [Int]()
        for i in 0..<n where i % 4 == 1 || i % 4 == 2 { cpIdx.append(i) }

        // Build anchor pairs: wrap-around first, then consecutive.
        var anchorPairs = [(Int, Int)]()
        anchorPairs.append((anchorIdx.last!, anchorIdx.first!))
        var k = 1
        while k < anchorIdx.count - 1 {
            anchorPairs.append((anchorIdx[k], anchorIdx[k + 1]))
            k += 2
        }

        // Build CP pairs with identical pairing structure.
        var cpPairs = [(Int, Int)]()
        if cpIdx.count >= 2 {
            cpPairs.append((cpIdx.last!, cpIdx.first!))
            k = 1
            while k < cpIdx.count - 1 {
                cpPairs.append((cpIdx[k], cpIdx[k + 1]))
                k += 2
            }
        }

        // Determine active pair indices from whichSpike.
        let activePairIndices: [Int]
        switch ea.whichSpike {
        case "CORNERS":
            activePairIndices = anchorPairs.isEmpty ? [] : [0]
        case "MIDDLES":
            activePairIndices = anchorPairs.count > 1 ? Array(1..<anchorPairs.count) : []
        default: // "ALL"
            activePairIndices = Array(0..<anchorPairs.count)
        }

        for pairIdx in activePairIndices {
            let (i0, i1) = anchorPairs[pairIdx]

            // Spike factor (possibly random).
            let sf = ea.randomSpike
                ? randomDouble(in: ea.randomSpikeFactor, using: &rng)
                : ea.spikeFactor
            let spikePos = Vector2D.lerp(pts[i0], centre, t: sf)
            let diff     = spikePos - pts[i0]

            // Resolve spike type: RANDOM picks 0=SYMMETRICAL, 1=RIGHT, 2=LEFT per pair.
            let resolvedType: Int
            if ea.spikeType == "RANDOM" {
                resolvedType = Int.random(in: 0...2, using: &rng)
            } else {
                resolvedType = ea.spikeType == "RIGHT" ? 1 : (ea.spikeType == "LEFT" ? 2 : 0)
            }

            // Apply spike to anchor points.
            switch ea.spikeAxis {
            case "X":
                let sp = Vector2D(x: spikePos.x, y: pts[i0].y)
                eaApplyAnchorSpike(&pts, i0: i0, i1: i1, pos: sp, type: resolvedType, isX: true, isY: false)
            case "Y":
                let sp = Vector2D(x: pts[i0].x, y: spikePos.y)
                eaApplyAnchorSpike(&pts, i0: i0, i1: i1, pos: sp, type: resolvedType, isX: false, isY: true)
            default: // "XY"
                eaApplyAnchorSpike(&pts, i0: i0, i1: i1, pos: spikePos, type: resolvedType, isX: true, isY: true)
            }

            guard pairIdx < cpPairs.count else { continue }
            let (c0, c1) = cpPairs[pairIdx]

            // cpsFollow: translate matching CPs by diff * multiplier.
            if ea.cpsFollow {
                let mult = ea.randomCpsFollow
                    ? randomDouble(in: ea.randomCpsFollowRange, using: &rng)
                    : ea.cpsFollowMultiplier
                switch ea.spikeAxis {
                case "X":
                    eaApplyCpsFollow(&pts, c0: c0, c1: c1,
                                     diff: Vector2D(x: diff.x, y: 0), mult: mult,
                                     type: resolvedType, isX: true, isY: false)
                case "Y":
                    eaApplyCpsFollow(&pts, c0: c0, c1: c1,
                                     diff: Vector2D(x: 0, y: diff.y), mult: mult,
                                     type: resolvedType, isX: false, isY: true)
                default:
                    eaApplyCpsFollow(&pts, c0: c0, c1: c1, diff: diff, mult: mult,
                                     type: resolvedType, isX: true, isY: true)
                }
            }

            // cpsSqueeze: lerp the two CPs toward each other.
            // Applied after cpsFollow so squeeze operates on the post-follow positions.
            if ea.cpsSqueeze {
                let f = ea.randomCpsSqueeze
                    ? randomDouble(in: ea.randomCpsSqueezeRange, using: &rng)
                    : ea.cpsSqueezeFactor
                switch ea.spikeAxis {
                case "X":
                    eaApplyCpsSqueeze(&pts, c0: c0, c1: c1, factor: f, type: resolvedType, isX: true, isY: false)
                case "Y":
                    eaApplyCpsSqueeze(&pts, c0: c0, c1: c1, factor: f, type: resolvedType, isX: false, isY: true)
                default:
                    eaApplyCpsSqueeze(&pts, c0: c0, c1: c1, factor: f, type: resolvedType, isX: true, isY: true)
                }
            }
        }
    }

    // resolvedType: 0=SYMMETRICAL, 1=RIGHT, 2=LEFT
    private static func eaApplyAnchorSpike(_ pts: inout [Vector2D],
                                            i0: Int, i1: Int, pos: Vector2D,
                                            type resolvedType: Int,
                                            isX: Bool, isY: Bool) {
        switch resolvedType {
        case 1: // RIGHT — only i0
            if isX { pts[i0].x = pos.x }
            if isY { pts[i0].y = pos.y }
        case 2: // LEFT — only i1
            if isX { pts[i1].x = pos.x }
            if isY { pts[i1].y = pos.y }
        default: // SYMMETRICAL — both
            if isX { pts[i0].x = pos.x; pts[i1].x = pos.x }
            if isY { pts[i0].y = pos.y; pts[i1].y = pos.y }
        }
    }

    private static func eaApplyCpsFollow(_ pts: inout [Vector2D],
                                          c0: Int, c1: Int,
                                          diff: Vector2D, mult: Double,
                                          type resolvedType: Int,
                                          isX: Bool, isY: Bool) {
        let cP1X = pts[c0].x + diff.x * mult
        let cP1Y = pts[c0].y + diff.y * mult
        let cP2X = pts[c1].x + diff.x * mult
        let cP2Y = pts[c1].y + diff.y * mult

        switch resolvedType {
        case 1: // RIGHT — only c0
            if isX { pts[c0].x = cP1X }
            if isY { pts[c0].y = cP1Y }
        case 2: // LEFT — only c1
            if isX { pts[c1].x = cP2X }
            if isY { pts[c1].y = cP2Y }
        default: // SYMMETRICAL — both
            if isX { pts[c0].x = cP1X; pts[c1].x = cP2X }
            if isY { pts[c0].y = cP1Y; pts[c1].y = cP2Y }
        }
    }

    private static func eaApplyCpsSqueeze(_ pts: inout [Vector2D],
                                           c0: Int, c1: Int,
                                           factor: Double,
                                           type resolvedType: Int,
                                           isX: Bool, isY: Bool) {
        let sqA = Vector2D.lerp(pts[c0], pts[c1], t: factor)
        let sqB = Vector2D.lerp(pts[c1], pts[c0], t: factor)

        switch resolvedType {
        case 1: // RIGHT — c0 = sqA
            if isX { pts[c0].x = sqA.x }
            if isY { pts[c0].y = sqA.y }
        case 2: // LEFT — Scala quirk: XY uses sqA for c1; X/Y use sqB
            if isX && isY {
                pts[c1] = sqA
            } else {
                if isX { pts[c1].x = sqB.x }
                if isY { pts[c1].y = sqB.y }
            }
        default: // SYMMETRICAL — c0=sqA, c1=sqB
            if isX { pts[c0].x = sqA.x; pts[c1].x = sqB.x }
            if isY { pts[c0].y = sqA.y; pts[c1].y = sqB.y }
        }
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

    /// Curves the control points on internal subdivision lines (M→centre and C→M edges).
    ///
    /// Buffer layout per polygon (QUAD, centreIndex=8):
    ///   buf[i*4+0] = pts[5]  = pts[ci-3]  — first CP  of Side 1 (M_i → C)
    ///   buf[i*4+1] = pts[6]  = pts[ci-2]  — second CP of Side 1 (M_i → C)
    ///   buf[i*4+2] = pts[9]  = pts[ci+1]  — first CP  of Side 2 (C → M_{i-1})
    ///   buf[i*4+3] = pts[10] = pts[ci+2]  — second CP of Side 2 (C → M_{i-1})
    ///
    /// Internal line i is shared by poly[i] (as its Side 1) and poly[i+1] (as its Side 2).
    /// The four buffer slots that concern line i are:
    ///   idxA0 = i*4+0        → poly[i].pts[5]     M-end CP-1 of line i
    ///   idxB0 = i*4+1        → poly[i].pts[6]     M-end CP-2 of line i
    ///   idxB1 = (i*4+6)%tot  → poly[i+1].pts[9]   C-end CP-1 of line i
    ///   idxA1 = (i*4+7)%tot  → poly[i+1].pts[10]  C-end CP-2 of line i
    private static func applyInnerControlPointsToArray<G: RandomNumberGenerator>(
        _ polygons: [Polygon2D],
        config: InnerControlPointsTransform,
        rng: inout G
    ) -> [Polygon2D] {
        guard !polygons.isEmpty else { return polygons }
        let n = polygons[0].points.count
        guard n == 16 else { return polygons }
        let ci         = n / 2   // = 8
        let sidesTotal = polygons.count
        let tot        = sidesTotal * 4

        // Build flat buffer: [pts[5], pts[6], pts[9], pts[10]] per polygon.
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

        let isReferPath = config.referToOuter != "NONE"

        // Precompute per-polygon outer-edge CP deviations for referToOuter paths.
        // dev0[i] = (dev of pts[1] from lerp(pts[0],pts[3],⅓),
        //            dev of pts[2] from lerp(pts[0],pts[3],⅔))   — Side 0 of poly[i]
        // dev3[i] = same for Side 3 (pts[12..15])                 — Side 3 of poly[i]
        var dev0a = [Vector2D](repeating: .zero, count: sidesTotal)
        var dev0b = [Vector2D](repeating: .zero, count: sidesTotal)
        var dev3a = [Vector2D](repeating: .zero, count: sidesTotal)
        var dev3b = [Vector2D](repeating: .zero, count: sidesTotal)
        if isReferPath {
            for (i, poly) in polygons.enumerated() {
                let pts = poly.points
                dev0a[i] = pts[1]  - Vector2D.lerp(pts[0],  pts[3],  t: 1.0/3.0)
                dev0b[i] = pts[2]  - Vector2D.lerp(pts[0],  pts[3],  t: 2.0/3.0)
                dev3a[i] = pts[13] - Vector2D.lerp(pts[12], pts[15], t: 1.0/3.0)
                dev3b[i] = pts[14] - Vector2D.lerp(pts[12], pts[15], t: 2.0/3.0)
            }
        }

        // Process each internal line.
        for i in 0..<sidesTotal {
            // Per-line probability check.
            guard Double.random(in: 0..<100, using: &rng) < config.probability else { continue }

            let next    = (i + 1) % sidesTotal
            let bufBase = i * 4
            let idxA0   = bufBase                                   // poly[i].pts[5]
            let idxB0   = bufBase + 1                               // poly[i].pts[6]
            let idxB1   = circularIndex(bufBase + 6, total: tot)    // poly[next].pts[9]
            let idxA1   = circularIndex(bufBase + 7, total: tot)    // poly[next].pts[10]

            if !isReferPath {
                // ── NONE path: perpendicular-swap displacement ───────────────────
                // Midpoint of poly[i]'s internal line (used as displacement reference).
                let midI    = Vector2D.lerp(polygons[i].points[ci - 3],
                                            polygons[i].points[ci], t: 0.5)
                let midNext = Vector2D.lerp(polygons[next].points[ci - 3],
                                            polygons[next].points[ci], t: 0.5)

                // commonLine determines which mid to use for each half of the line.
                let (midForI, midForNext): (Vector2D, Vector2D)
                switch config.commonLine {
                case "ODD":
                    midForI = midNext;  midForNext = midNext
                case "RANDOM":
                    let m = Bool.random(using: &rng) ? midI : midNext
                    midForI = m;        midForNext = m
                case "NONE":
                    midForI = midI;     midForNext = midNext   // each side independent
                default: // EVEN
                    midForI = midI;     midForNext = midI
                }

                // User-controlled multipliers (or random range).
                let innerMult: Double
                let outerMult: Double
                if config.randomRatio {
                    innerMult = randomDouble(in: config.randomInnerRatio, using: &rng)
                    outerMult = randomDouble(in: config.randomOuterRatio, using: &rng)
                } else {
                    innerMult = config.innerRatio
                    outerMult = config.outerRatio
                }

                func displaced(_ cp: Vector2D, mid: Vector2D, mult: Double) -> Vector2D {
                    let diff = mid - cp
                    let inv  = Vector2D(x: diff.y, y: diff.x)   // swap x,y
                    return cp + inv * mult
                }

                buffer[idxA0] = displaced(buffer[idxA0], mid: midForI,    mult: innerMult)
                buffer[idxB0] = displaced(buffer[idxB0], mid: midForI,    mult: innerMult)
                buffer[idxA1] = displaced(buffer[idxA1], mid: midForNext, mult: outerMult)
                buffer[idxB1] = displaced(buffer[idxB1], mid: midForNext, mult: outerMult)

            } else {
                // ── referToOuter paths: FOLLOW / COUNTER / EXAGGERATE ───────────
                // Sign and scale factors.
                let signMult: Double
                switch config.referToOuter {
                case "COUNTER":    signMult = -1.0
                case "EXAGGERATE": signMult =  2.0
                default:           signMult =  1.0  // FOLLOW
                }

                // commonLine: which polygon's outer-edge curvature to reference.
                // ref0 drives the M-end CPs (idxA0, idxB0) on poly[i].
                // ref1 drives the C-end CPs (idxA1, idxB1) on poly[next].
                let (ref0, ref1): (Int, Int)
                switch config.commonLine {
                case "ODD":
                    ref0 = next;  ref1 = next
                case "RANDOM":
                    let pick = Bool.random(using: &rng) ? i : next
                    ref0 = pick;  ref1 = pick
                case "NONE":
                    ref0 = i;     ref1 = next   // each side uses its own outer edge
                default: // EVEN
                    ref0 = i;     ref1 = i
                }

                // ── M-end CPs (poly[i].pts[5,6]): derive from outer Side 0 of ref0. ──
                // Inner edge M_i→C anchors for poly[i]: pts[4]=M_i, pts[7]=C.
                do {
                    let polyPts = polygons[i].points
                    let edgeA   = polyPts[ci - 4]   // pts[4] = M_i anchor start
                    let edgeB   = polyPts[ci - 1]   // pts[7] = centre anchor end

                    let (dA, dB) = (dev0a[ref0], dev0b[ref0])
                    let pos1 = Vector2D.lerp(edgeA, edgeB, t: config.innerRatio)
                    let pos2 = Vector2D.lerp(edgeA, edgeB, t: config.outerRatio)

                    buffer[idxA0] = Vector2D(
                        x: pos1.x + dA.x * config.outerMultiplierX * signMult,
                        y: pos1.y + dA.y * config.outerMultiplierY * signMult)
                    buffer[idxB0] = Vector2D(
                        x: pos2.x + dB.x * config.outerMultiplierX * signMult,
                        y: pos2.y + dB.y * config.outerMultiplierY * signMult)
                }

                // ── C-end CPs (poly[next].pts[9,10]): derive from outer Side 3 of ref1. ──
                // Inner edge C→M_i anchors for poly[next]: pts[8]=C, pts[11]=M_i.
                do {
                    let nextPts = polygons[next].points
                    let edgeA   = nextPts[ci]       // pts[8] = centre anchor start
                    let edgeB   = nextPts[ci + 3]   // pts[11] = M_i anchor end

                    let (dA, dB) = (dev3a[ref1], dev3b[ref1])
                    let pos1 = Vector2D.lerp(edgeA, edgeB, t: config.innerRatio)
                    let pos2 = Vector2D.lerp(edgeA, edgeB, t: config.outerRatio)

                    buffer[idxB1] = Vector2D(
                        x: pos1.x + dA.x * config.innerMultiplierX * signMult,
                        y: pos1.y + dA.y * config.innerMultiplierY * signMult)
                    buffer[idxA1] = Vector2D(
                        x: pos2.x + dB.x * config.innerMultiplierX * signMult,
                        y: pos2.y + dB.y * config.innerMultiplierY * signMult)
                }
            }
        }

        // Write buffer back to polygon copies.
        return polygons.enumerated().map { (idx, poly) in
            guard poly.visible else { return poly }
            let base = idx * 4
            guard base + 3 < buffer.count, ci - 3 >= 0, ci + 2 < poly.points.count else {
                return poly
            }
            var pts = poly.points
            pts[ci - 3] = buffer[base]
            pts[ci - 2] = buffer[base + 1]
            pts[ci + 1] = buffer[base + 2]
            pts[ci + 2] = buffer[base + 3]
            return Polygon2D(points: pts, type: poly.type,
                             pressures: poly.pressures,
                             pressureProfiles: poly.pressureProfiles,
                             visible: poly.visible)
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

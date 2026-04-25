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
            return polygons.map { poly in
                guard poly.visible else { return poly }
                guard Double.random(in: 0..<100, using: &rng) < params.pTP_probability
                else { return poly }
                return applyPTPTransformSet(poly, transformSet: ts)
            }
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

    // MARK: - Structured PTP (ExteriorAnchors + CentralAnchors)

    /// Apply structured anchor transforms to a single polygon.
    ///
    /// Replicates Scala's `PointsTransform.transformPoints` which calls
    /// `ExteriorAnchors.transform` and `CentralAnchors.transform` on the child
    /// polygon array, each using a shared `centreIndex`.
    ///
    /// `centreIndex` is derived from point count:
    ///  - 12 pts (3-sided TRI_STAR): index 4  (Scala: `val centreIndex = 4`)
    ///  - 16 pts (4-sided QUAD/TRI): index 8  (Scala: `val centreIndex = points.length/2`)
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

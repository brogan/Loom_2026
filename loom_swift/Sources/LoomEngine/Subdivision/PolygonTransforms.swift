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
        polygons.map { poly in
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

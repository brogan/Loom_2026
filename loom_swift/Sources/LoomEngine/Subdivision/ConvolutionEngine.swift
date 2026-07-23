import Foundation

/// Convolution — see `ConvolutionParams` and Specs/Convolution.md for the full
/// design. This engine applies a continuous coordinate-space warp to every
/// point of an already-resolved polygon, unconditionally for both closed
/// polygons and open curves (there is no topology-dependent branching here,
/// unlike Extension/Evolution — the whole point of this stage is that a
/// coordinate remap doesn't care what the points are connected into).
public enum ConvolutionEngine {

    public static func process(
        polygons:      [Polygon2D],
        paramSet:      [ConvolutionParams],
        elapsedFrames: Double = 0,
        targetFPS:     Double = 24,
        spriteIndex:   Int    = 0
    ) -> [Polygon2D] {
        let active = paramSet.filter { $0.enabled }
        guard !active.isEmpty else { return polygons }

        var result = polygons
        for params in active {
            result = result.map { polygon in
                guard isWarpable(polygon) else { return polygon }
                return warp(polygon, params: params, elapsedFrames: elapsedFrames,
                            targetFPS: targetFPS, spriteIndex: spriteIndex)
            }
        }
        return result
    }

    /// Convolution warps every point in a genuine point-list shape identically.
    /// `.oval` (a 2-point centre+radii encoding) and `.point` (a single marker)
    /// don't have that property — every one of their points carries special
    /// meaning beyond "a coordinate on the shape" — so a naive point-wise remap
    /// would corrupt rather than distort them. `.line`, `.spline`, and
    /// `.openSpline` all share the flat, every-point-is-a-real-coordinate
    /// encoding this operates on safely.
    private static func isWarpable(_ polygon: Polygon2D) -> Bool {
        polygon.type != .oval && polygon.type != .point
    }

    private static func warp(
        _ polygon: Polygon2D,
        params: ConvolutionParams,
        elapsedFrames: Double,
        targetFPS: Double,
        spriteIndex: Int
    ) -> Polygon2D {
        switch params.operationType {
        case .torsion:
            let angleDeg = DriverEvaluator.evaluate(params.twistAmount,
                                                     globalElapsed: elapsedFrames,
                                                     targetFPS: targetFPS,
                                                     spriteIndex: spriteIndex)
            return applyTorsion(to: polygon, params: params, angle: angleDeg * .pi / 180.0)
        case .shear:
            let amount = DriverEvaluator.evaluate(params.shearAmount,
                                                   globalElapsed: elapsedFrames,
                                                   targetFPS: targetFPS,
                                                   spriteIndex: spriteIndex)
            return applyShear(to: polygon, params: params, amount: amount)
        }
    }

    // MARK: - Torsion

    /// Rotates each point around `centre` by an angle that grows with distance
    /// from it (falloff-dependent) — a spiral warp. Not curve-exact for a
    /// Bézier segment (a nonlinear per-point remap of anchors and control
    /// points is a standard, visually-correct approximation used by bend/twist
    /// deformers generally, not an exact transform of the underlying curve) —
    /// acceptable for gentle-to-moderate twist amounts; very large angles over
    /// long segments can show faceting at the approximation's limits.
    private static func applyTorsion(to polygon: Polygon2D, params: ConvolutionParams, angle: Double) -> Polygon2D {
        guard abs(angle) > 1e-12 else { return polygon }
        let centre = resolveCentre(params.twistCentre,
                                    customX: params.twistCentreCustomX,
                                    customY: params.twistCentreCustomY,
                                    polygon: polygon)
        let refRadius = max(params.twistReferenceRadius, 1e-6)

        let newPoints = polygon.points.map { p -> Vector2D in
            let r = p.distance(to: centre)
            let theta: Double
            switch params.twistFalloff {
            case .linear:   theta = angle * (r / refRadius)
            case .inverse:  theta = angle * exp(-r / refRadius)
            case .constant: theta = angle
            }
            return p.rotated(by: theta, around: centre)
        }
        return Polygon2D(points: newPoints, type: polygon.type,
                          pressures: polygon.pressures,
                          pressureProfiles: polygon.pressureProfiles,
                          visible: polygon.visible)
    }

    // MARK: - Shear

    /// Generalized shear along an arbitrary axis (not fixed to X/Y): points are
    /// displaced along `shearAxis` by an amount proportional to their distance
    /// from that axis, measured through `shearOrigin`. Shear is an affine
    /// transform, so — unlike Torsion — this is geometrically exact for every
    /// Bézier control point, not an approximation.
    private static func applyShear(to polygon: Polygon2D, params: ConvolutionParams, amount: Double) -> Polygon2D {
        guard abs(amount) > 1e-12 else { return polygon }
        let origin = resolveCentre(params.shearOrigin,
                                    customX: params.shearOriginCustomX,
                                    customY: params.shearOriginCustomY,
                                    polygon: polygon)
        let axisRad = params.shearAxis * .pi / 180.0
        let cosA = cos(axisRad)
        let sinA = sin(axisRad)

        let newPoints = polygon.points.map { p -> Vector2D in
            let d = p - origin
            // Rotate into shear-aligned frame: u = along axis, v = perpendicular.
            let u = d.x * cosA + d.y * sinA
            let v = -d.x * sinA + d.y * cosA
            let uSheared = u + amount * v
            // Rotate back.
            let newX = uSheared * cosA - v * sinA
            let newY = uSheared * sinA + v * cosA
            return Vector2D(x: origin.x + newX, y: origin.y + newY)
        }
        return Polygon2D(points: newPoints, type: polygon.type,
                          pressures: polygon.pressures,
                          pressureProfiles: polygon.pressureProfiles,
                          visible: polygon.visible)
    }

    // MARK: - Reference point resolution

    private static func resolveCentre(_ mode: ConvolutionCentre, customX: Double, customY: Double, polygon: Polygon2D) -> Vector2D {
        switch mode {
        case .centroid:
            return polygon.centroid
        case .boundingBox:
            guard !polygon.points.isEmpty else { return .zero }
            let xs = polygon.points.map(\.x)
            let ys = polygon.points.map(\.y)
            return Vector2D(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        case .custom:
            return Vector2D(x: customX, y: customY)
        }
    }
}

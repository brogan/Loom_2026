import Foundation

/// Convolution — see `ConvolutionParams` and Specs/Convolution.md for the full
/// design. This engine applies a continuous coordinate-space warp to every
/// point of an already-resolved geometry, unconditionally for both closed
/// polygons and open curves (there is no topology-dependent branching here,
/// unlike Extension/Evolution — the whole point of this stage is that a
/// coordinate remap doesn't care what the points are connected into).
///
/// Crucially, a sprite's resolved geometry is very often *many* `Polygon2D`
/// values at once (e.g. hundreds of small quads after several stacked
/// Subdivision passes) that together represent one coherent shape. Every
/// reference quantity a pass needs — the resolved centre for Torsion/Shear,
/// and the along-axis extent Bend's `bendOrigin` is measured against — is
/// therefore computed once across *all* warpable polygons' points for that
/// pass, not independently per polygon. Resolving it per polygon instead
/// (the original, buggy implementation) makes each small quad in a subdivided
/// mesh treat its own tiny local extent as if it were the whole shape's —
/// for Bend specifically this collapses the entire mesh toward a line along
/// the bend axis, regardless of where each quad actually sat, since every
/// quad's `sOrigin` ends up approximately equal to its own position.
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
            result = applyPass(to: result, params: params, elapsedFrames: elapsedFrames,
                                targetFPS: targetFPS, spriteIndex: spriteIndex)
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

    private static func applyPass(
        to polygons: [Polygon2D],
        params: ConvolutionParams,
        elapsedFrames: Double,
        targetFPS: Double,
        spriteIndex: Int
    ) -> [Polygon2D] {
        let allPoints = polygons.filter(isWarpable).flatMap(\.points)
        guard !allPoints.isEmpty else { return polygons }

        switch params.operationType {
        case .torsion:
            let angleDeg = DriverEvaluator.evaluate(params.twistAmount,
                                                     globalElapsed: elapsedFrames,
                                                     targetFPS: targetFPS,
                                                     spriteIndex: spriteIndex)
            let angle = angleDeg * .pi / 180.0
            guard abs(angle) > 1e-12 else { return polygons }
            let centre = resolveCentre(params.twistCentre,
                                        customX: params.twistCentreCustomX,
                                        customY: params.twistCentreCustomY,
                                        points: allPoints)
            return polygons.map { polygon in
                guard isWarpable(polygon) else { return polygon }
                return applyTorsion(to: polygon, params: params, angle: angle, centre: centre)
            }

        case .shear:
            let amount = DriverEvaluator.evaluate(params.shearAmount,
                                                   globalElapsed: elapsedFrames,
                                                   targetFPS: targetFPS,
                                                   spriteIndex: spriteIndex)
            guard abs(amount) > 1e-12 else { return polygons }
            let origin = resolveCentre(params.shearOrigin,
                                        customX: params.shearOriginCustomX,
                                        customY: params.shearOriginCustomY,
                                        points: allPoints)
            return polygons.map { polygon in
                guard isWarpable(polygon) else { return polygon }
                return applyShear(to: polygon, params: params, amount: amount, origin: origin)
            }

        case .bend:
            let curvature = DriverEvaluator.evaluate(params.bendCurvature,
                                                      globalElapsed: elapsedFrames,
                                                      targetFPS: targetFPS,
                                                      spriteIndex: spriteIndex)
            guard abs(curvature) > 1e-9 else { return polygons }
            let centre = resolveCentre(params.bendCentre,
                                        customX: params.bendCentreCustomX,
                                        customY: params.bendCentreCustomY,
                                        points: allPoints)
            let axisRad   = params.bendAxis * .pi / 180.0
            let alongDir  = Vector2D(x: cos(axisRad), y: sin(axisRad))
            let acrossDir = Vector2D(x: -sin(axisRad), y: cos(axisRad))
            let sValues = allPoints.map { ($0 - centre).dot(alongDir) }
            let sMin = sValues.min() ?? 0
            let sMax = sValues.max() ?? 0
            let sOrigin = sMin + (sMax - sMin) * params.bendOrigin
            return polygons.map { polygon in
                guard isWarpable(polygon) else { return polygon }
                return applyBend(to: polygon, curvature: curvature, centre: centre,
                                  alongDir: alongDir, acrossDir: acrossDir, sOrigin: sOrigin)
            }
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
    private static func applyTorsion(to polygon: Polygon2D, params: ConvolutionParams, angle: Double, centre: Vector2D) -> Polygon2D {
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
    /// from that axis, measured through `origin`. Shear is an affine
    /// transform, so — unlike Torsion — this is geometrically exact for every
    /// Bézier control point, not an approximation.
    private static func applyShear(to polygon: Polygon2D, params: ConvolutionParams, amount: Double, origin: Vector2D) -> Polygon2D {
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

    // MARK: - Bend

    /// Wraps a shape around a virtual circular arc — a 3D "bend deformer"
    /// brought into 2D. `alongDir` defines the "along" direction; points are
    /// carried along an arc of radius `1/curvature` as if the straight axis
    /// were being bent into that arc, with cross-sections (perpendicular to
    /// the axis) staying rigid — a straight line across the bend direction
    /// remains straight, just rotated, rather than shearing. `sOrigin` (an
    /// absolute along-axis coordinate, already resolved across the whole
    /// mesh and `bendOrigin`'s 0–1 position within it) is where curvature is
    /// centred: the point sitting exactly there stays fixed. Like Torsion,
    /// this is a standard visually-correct point-wise approximation for
    /// Bézier control points, not curve-exact.
    private static func applyBend(
        to polygon: Polygon2D,
        curvature: Double,
        centre: Vector2D,
        alongDir: Vector2D,
        acrossDir: Vector2D,
        sOrigin: Double
    ) -> Polygon2D {
        let radius = 1.0 / curvature
        let newPoints = polygon.points.map { p -> Vector2D in
            let d = p - centre
            let s = d.dot(alongDir) - sOrigin
            let t = d.dot(acrossDir)
            let theta = s * curvature
            let newAlong  = (radius - t) * sin(theta)
            let newAcross = radius - (radius - t) * cos(theta)
            return centre + newAlong * alongDir + newAcross * acrossDir
        }
        return Polygon2D(points: newPoints, type: polygon.type,
                          pressures: polygon.pressures,
                          pressureProfiles: polygon.pressureProfiles,
                          visible: polygon.visible)
    }

    // MARK: - Reference point resolution

    /// Resolved once per pass across every warpable polygon's points — see
    /// the type-level doc comment for why this must not be computed per
    /// individual polygon.
    private static func resolveCentre(_ mode: ConvolutionCentre, customX: Double, customY: Double, points: [Vector2D]) -> Vector2D {
        switch mode {
        case .centroid:
            guard !points.isEmpty else { return .zero }
            let sum = points.reduce(Vector2D.zero, +)
            return sum.scaled(by: 1.0 / Double(points.count))
        case .boundingBox:
            guard !points.isEmpty else { return .zero }
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            return Vector2D(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        case .custom:
            return Vector2D(x: customX, y: customY)
        }
    }
}

import Foundation

/// V1 Fulguration — see Specs/GeometricLifecycle.md §5.3–§5.5, §5.9.
///
/// A self-contained frame-cycle visibility gate: each pass alternates between a
/// hidden interval and a held/visible interval, both independently RPSR-resampled
/// per cycle from `cycleSeed` (combined with `spriteIndex`, so sprites sharing one
/// preset don't flash in lockstep). While visible, one rigid transform
/// (translation/scale/rotation) is sampled for the whole flash, and — in
/// `.growShrink` development mode — a scale envelope ramps the flash in and out at
/// the edges of its hold window using `Polygon2D.scaled(by:around:)` directly, the
/// same primitive Dissolution's Brief collapse already uses.
///
/// Stateless and seekable in the sense that matters (§5.9, same category as
/// Generational Evolution, §4.4.4): any frame is resolved from scratch by walking
/// cycles from index 0, not by incrementally advancing stored state. This walk is
/// O(cycles-so-far), not O(1) — each cycle's interval/hold is independently
/// resampled, so there's no fixed period to take a modular remainder against — and
/// is capped at `maxCycleScan` to match Collapse's probability-trigger scan cap.
public enum FulgurationEngine {

    public static func apply(
        polygons:      [Polygon2D],
        passes:        [FulgurationParams],
        elapsedFrames: Double,
        spriteIndex:   Int
    ) -> [Polygon2D] {
        var result = polygons
        for pass in passes where pass.enabled {
            result = applyPass(polygons: result, pass: pass, elapsedFrames: elapsedFrames, spriteIndex: spriteIndex)
            if result.isEmpty { return [] }
        }
        return result
    }

    // MARK: - Cycle scan

    private static let maxCycleScan = 100_000

    private enum Visibility {
        case hidden
        case visible(cycleIndex: Int, holdElapsed: Double, holdDuration: Double)
    }

    /// Walks cycles from index 0 (hidden interval, then held interval, repeating)
    /// until `elapsedFrames` falls within one of them. See the type-level doc for
    /// why this can't be a closed-form modular computation.
    private static func resolveVisibility(pass: FulgurationParams, elapsedFrames: Double, seed: Int) -> Visibility {
        var t = max(0, elapsedFrames)
        var cycleIndex = 0
        while cycleIndex < maxCycleScan {
            let interval = Double(sampleInterval(pass: pass, seed: seed, cycleIndex: cycleIndex))
            if t < interval { return .hidden }
            t -= interval
            let hold = Double(sampleHold(pass: pass, seed: seed, cycleIndex: cycleIndex))
            if t < hold { return .visible(cycleIndex: cycleIndex, holdElapsed: t, holdDuration: hold) }
            t -= hold
            cycleIndex += 1
        }
        return .hidden
    }

    // MARK: - Per-pass

    private static func applyPass(
        polygons:      [Polygon2D],
        pass:          FulgurationParams,
        elapsedFrames: Double,
        spriteIndex:   Int
    ) -> [Polygon2D] {
        guard !polygons.isEmpty else { return polygons }

        // Fold spriteIndex into the seed so sprites sharing one FulgurationParams
        // preset don't cycle in perfect lockstep — same constant Dissolution's
        // Collapse probability trigger already uses for the identical reason.
        let seed = pass.cycleSeed &+ spriteIndex &* 2_654_435_761

        switch resolveVisibility(pass: pass, elapsedFrames: elapsedFrames, seed: seed) {
        case .hidden:
            return []
        case .visible(let cycleIndex, let holdElapsed, let holdDuration):
            let factor = developmentFactor(pass: pass, holdElapsed: holdElapsed, holdDuration: holdDuration)
            guard factor > 1e-9 else { return [] }

            let transform = sampleTransform(pass: pass, seed: seed, cycleIndex: cycleIndex)
            let anchor = groupCentroid(polygons)
            let combinedScale = factor * transform.scale

            return polygons.map {
                applyRigidTransform($0, anchor: anchor, rotation: transform.rotation,
                                   scale: combinedScale, translation: transform.translation)
            }
        }
    }

    // MARK: - RPSR sampling

    /// Per-cycle roll indices: 0 = interval, 1 = hold, 2 = translation angle,
    /// 3 = translation magnitude, 4 = scale, 5 = rotation. 6–7 reserved.
    private static func sampleInterval(pass: FulgurationParams, seed: Int, cycleIndex: Int) -> Int {
        let lo = min(pass.intervalMin, pass.intervalMax)
        let hi = max(pass.intervalMin, pass.intervalMax)
        let roll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleIndex * 8 + 0)
        return max(1, lo + Int(roll * Double(hi - lo + 1)))
    }

    private static func sampleHold(pass: FulgurationParams, seed: Int, cycleIndex: Int) -> Int {
        let lo = min(pass.holdMin, pass.holdMax)
        let hi = max(pass.holdMin, pass.holdMax)
        let roll = SubdivisionEngine.centreHash(seed: seed, cycle: cycleIndex * 8 + 1)
        return max(1, lo + Int(roll * Double(hi - lo + 1)))
    }

    private struct SampledTransform {
        var translation: Vector2D
        var scale:       Double
        var rotation:    Double
    }

    private static func sampleTransform(pass: FulgurationParams, seed: Int, cycleIndex: Int) -> SampledTransform {
        let base = cycleIndex * 8
        let angleRoll = SubdivisionEngine.centreHash(seed: seed, cycle: base + 2)
        let magRoll   = SubdivisionEngine.centreHash(seed: seed, cycle: base + 3)
        let scaleRoll = SubdivisionEngine.centreHash(seed: seed, cycle: base + 4)
        let rotRoll   = SubdivisionEngine.centreHash(seed: seed, cycle: base + 5)

        let angle     = angleRoll * 2.0 * .pi
        let magnitude = magRoll * max(0, pass.translationRange)
        let translation = Vector2D(x: cos(angle) * magnitude, y: sin(angle) * magnitude)

        let scaleLo = min(pass.scaleMin, pass.scaleMax)
        let scaleHi = max(pass.scaleMin, pass.scaleMax)
        let scale   = scaleLo + scaleRoll * (scaleHi - scaleLo)

        let rotation = (rotRoll * 2.0 - 1.0) * pass.rotationRange

        return SampledTransform(translation: translation, scale: scale, rotation: rotation)
    }

    // MARK: - Development factor

    /// `.instant` is always fully on (1.0) for the whole hold window. `.growShrink`
    /// ramps 0→1 over the first `growInDuration` frames and 1→0 over the last
    /// `shrinkOutDuration`, clamped so the two never overlap (each capped to at most
    /// the hold duration, shrink capped further to what's left after grow-in).
    private static func developmentFactor(pass: FulgurationParams, holdElapsed: Double, holdDuration: Double) -> Double {
        guard pass.developmentMode == .growShrink else { return 1.0 }

        let growIn    = min(Double(max(0, pass.growInDuration)), holdDuration)
        let shrinkOut = min(Double(max(0, pass.shrinkOutDuration)), holdDuration - growIn)

        if growIn > 0, holdElapsed < growIn {
            return max(0, min(1, holdElapsed / growIn))
        }
        let shrinkStart = holdDuration - shrinkOut
        if shrinkOut > 0, holdElapsed >= shrinkStart {
            return max(0, min(1, (holdDuration - holdElapsed) / shrinkOut))
        }
        return 1.0
    }

    // MARK: - Geometry

    /// Unweighted average of each polygon's own centroid — the single shared anchor
    /// the whole flash's transform and development scale are applied around, so the
    /// group reads as one object growing/rotating/translating together rather than
    /// each polygon moving independently.
    private static func groupCentroid(_ polygons: [Polygon2D]) -> Vector2D {
        guard !polygons.isEmpty else { return .zero }
        var sumX = 0.0, sumY = 0.0
        for poly in polygons {
            let c = BezierMath.centreSpline(poly.points)
            sumX += c.x; sumY += c.y
        }
        let n = Double(polygons.count)
        return Vector2D(x: sumX / n, y: sumY / n)
    }

    private static func applyRigidTransform(
        _ poly:       Polygon2D,
        anchor:       Vector2D,
        rotation:     Double,
        scale:        Double,
        translation:  Vector2D
    ) -> Polygon2D {
        let cosT = cos(rotation), sinT = sin(rotation)
        let newPoints = poly.points.map { p -> Vector2D in
            let rx = p.x - anchor.x, ry = p.y - anchor.y
            let rotatedX = rx * cosT - ry * sinT
            let rotatedY = rx * sinT + ry * cosT
            return Vector2D(
                x: anchor.x + rotatedX * scale + translation.x,
                y: anchor.y + rotatedY * scale + translation.y
            )
        }
        return Polygon2D(points: newPoints, type: poly.type,
                         pressures: poly.pressures,
                         pressureProfiles: poly.pressureProfiles,
                         visible: poly.visible)
    }
}

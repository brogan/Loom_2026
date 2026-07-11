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
            // No blanket short-circuit on an empty intermediate result: a `.transform`
            // pass hidden mid-chain still correctly propagates emptiness on its own
            // (its guard returns the empty input unchanged), but a later `.assembly`
            // pass (§5.12) doesn't consume `polygons` at all, so it must still run
            // even if an earlier pass zeroed the chain out.
            result = applyPass(polygons: result, pass: pass, elapsedFrames: elapsedFrames, spriteIndex: spriteIndex)
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
        // Fold spriteIndex into the seed so sprites sharing one FulgurationParams
        // preset don't cycle in perfect lockstep — same constant Dissolution's
        // Collapse probability trigger already uses for the identical reason.
        let seed = pass.cycleSeed &+ spriteIndex &* 2_654_435_761

        switch pass.contentMode {
        case .transform:
            guard !polygons.isEmpty else { return polygons }
            return applyTransformPass(polygons: polygons, pass: pass, elapsedFrames: elapsedFrames, seed: seed)
        case .assembly:
            // Assembly mode (§5.12) replaces the sprite's geometry with pieces
            // sourced from AssemblyPrimitiveKit rather than transforming what's
            // already there — it doesn't consume `polygons` at all, so an empty
            // sprite (or a prior pass having zeroed it) doesn't block it.
            return applyAssemblyPass(pass: pass, elapsedFrames: elapsedFrames, seed: seed)
        }
    }

    // MARK: - .transform content mode (V1, §5.3–5.5)

    private static func applyTransformPass(
        polygons:      [Polygon2D],
        pass:          FulgurationParams,
        elapsedFrames: Double,
        seed:          Int
    ) -> [Polygon2D] {
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

    // MARK: - .assembly content mode (V3, §5.12)

    private static func applyAssemblyPass(
        pass:          FulgurationParams,
        elapsedFrames: Double,
        seed:          Int
    ) -> [Polygon2D] {
        switch resolveVisibility(pass: pass, elapsedFrames: elapsedFrames, seed: seed) {
        case .hidden:
            return []
        case .visible(let cycleIndex, let holdElapsed, let holdDuration):
            let pieces = AssemblyFulgurationEngine.assemble(pass: pass, seed: seed, cycleIndex: cycleIndex)
            guard !pieces.isEmpty else { return [] }
            return applyExit(pieces, pass: pass, seed: seed, cycleIndex: cycleIndex,
                             holdElapsed: holdElapsed, holdDuration: holdDuration)
        }
    }

    /// The last `exitDuration` frames of the hold window (§5.12.6). `.instant` needs
    /// no ramp at all — the hold window's own end (handled by `resolveVisibility`)
    /// already makes it disappear, so it's the implicit `default` here.
    private static func applyExit(
        _ pieces:      [Polygon2D],
        pass:          FulgurationParams,
        seed:          Int,
        cycleIndex:    Int,
        holdElapsed:   Double,
        holdDuration:  Double
    ) -> [Polygon2D] {
        let duration = Double(max(1, pass.exitDuration))
        let start = max(0, holdDuration - duration)
        guard holdElapsed >= start else { return pieces }
        let t = min(1, max(0, (holdElapsed - start) / duration))

        switch pass.exitMode {
        case .instant:
            return pieces

        case .shrink:
            let factor = 1 - t
            guard factor > 1e-9 else { return [] }
            let anchor = groupCentroid(pieces)
            return pieces.map { $0.scaled(by: factor, around: anchor) }

        case .offscreen:
            // `t` is always strictly < 1.0 here (`holdElapsed` is always strictly
            // < `holdDuration` inside the `.visible` case that reaches `applyExit` —
            // see `resolveVisibility`), so "fully offscreen" is never a distinct
            // state to branch on: the piece reaches maximum offset just as the hold
            // window's own natural end makes it disappear via `resolveVisibility`'s
            // `.hidden` case, exactly like every other exit mode. Direction chosen
            // once per cycle (seeded, distinct salt from AssemblyFulgurationEngine's
            // own rolls so the two never collide), magnitude large enough to clear
            // the ±0.5 normalized canvas well before that boundary.
            let angleRoll = SubdivisionEngine.centreHash(seed: seed &+ 4_111, cycle: cycleIndex)
            let angle = angleRoll * 2.0 * .pi
            let magnitude = 1.5 * t
            let translation = Vector2D(x: cos(angle) * magnitude, y: sin(angle) * magnitude)
            return pieces.map { poly in
                Polygon2D(points: poly.points.map { $0 + translation }, type: poly.type,
                         pressures: poly.pressures, pressureProfiles: poly.pressureProfiles,
                         visible: poly.visible)
            }

        case .shatter:
            // Same boundary note as `.offscreen` above — `t` never reaches 1.0 while
            // still `.visible`; pieces reach maximum scatter just as the hold window
            // ends naturally.
            return pieces.enumerated().map { index, poly in
                applyShatterDrift(poly, pass: pass, seed: seed &+ 8_231, cycleIndex: cycleIndex,
                                  pieceIndex: index, progress: t)
            }
        }
    }

    /// Per-piece rigid drift for `.shatter`, scaled by exit `progress` — same shape
    /// as Dissolution's own `applyDrift` (§6.6–§6.10: seeded direction/rotation per
    /// polygon, stable across frames, magnitude scaled by progress), reused as its
    /// own small function here since Dissolution's is private and this operates on
    /// Assembly's piece list rather than a sprite's resolved polygons.
    private static func applyShatterDrift(
        _ poly:       Polygon2D,
        pass:         FulgurationParams,
        seed:         Int,
        cycleIndex:   Int,
        pieceIndex:   Int,
        progress:     Double
    ) -> Polygon2D {
        let rollBase = cycleIndex * 97 + pieceIndex * 2

        let angleRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase)
        let angle = angleRoll * 2.0 * .pi
        let dx = cos(angle) * pass.shatterDistance * progress
        let dy = sin(angle) * pass.shatterDistance * progress

        let rotRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 1)
        let theta = (rotRoll * 2.0 - 1.0) * pass.shatterRotation * progress

        var pts = poly.points
        if abs(theta) > 1e-9 {
            let centre = BezierMath.centreSpline(pts)
            let cosT = cos(theta), sinT = sin(theta)
            pts = pts.map { p in
                let rx = p.x - centre.x, ry = p.y - centre.y
                return Vector2D(x: centre.x + rx * cosT - ry * sinT,
                                y: centre.y + rx * sinT + ry * cosT)
            }
        }
        pts = pts.map { Vector2D(x: $0.x + dx, y: $0.y + dy) }

        return Polygon2D(points: pts, type: poly.type,
                         pressures: poly.pressures,
                         pressureProfiles: poly.pressureProfiles,
                         visible: poly.visible)
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

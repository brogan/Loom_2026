import Foundation

/// Stateless computation of a `SpriteTransform` for a given draw cycle.
///
/// All four animation types are handled by a single entry point.
/// The function is pure (no mutable state) and injectable-RNG-ready for deterministic tests.
public enum TransformAnimator {

    // MARK: - Public entry point

    /// Compute the `SpriteTransform` for `animation` at `elapsedFrames` (fractional frame count).
    ///
    /// `elapsedFrames` is the wall-clock elapsed time multiplied by `targetFPS` — it is
    /// fractional so keyframe interpolation is smooth at any display frame rate.
    /// Keyframe `drawCycle` values in the XML are integer frame numbers at `targetFPS`;
    /// comparing them against `elapsedFrames` directly gives the correct timing.
    ///
    /// - Parameters:
    ///   - animation:     The sprite's animation specification.
    ///   - elapsedFrames: Fractional elapsed frame count (= `elapsedTime * targetFPS`).
    ///   - rng:           Consumed only for `.random` and `.jitterMorph`.
    public static func transform<RNG: RandomNumberGenerator>(
        for animation: SpriteAnimation,
        elapsedFrames: Double,
        using rng: inout RNG
    ) -> SpriteTransform {
        guard animation.enabled else { return .identity }
        switch animation.type {
        case .keyframe:
            return keyframeTransform(animation, elapsedFrames: elapsedFrames)
        case .random:
            return jitterTransform(animation, using: &rng)
        case .keyframeMorph:
            return keyframeTransform(animation, elapsedFrames: elapsedFrames)
        case .jitterMorph:
            return jitterMorphTransform(animation, using: &rng)
        }
    }

    // MARK: - Loop normalisation

    /// Map a fractional elapsed frame count onto a position within `[0, totalDraws)`.
    ///
    /// Returns a `Double` so callers can interpolate sub-frame positions within
    /// keyframe spans without truncation.
    static func normalizedElapsed(_ elapsed: Double, totalDraws: Int, loopMode: LoopMode) -> Double {
        guard totalDraws > 0 else { return elapsed }
        let total = Double(totalDraws)
        switch loopMode {
        case .loop:
            return elapsed.truncatingRemainder(dividingBy: total)
        case .once:
            return min(elapsed, total - 1)
        case .pingPong:
            // Period = (totalDraws-1)*2; forward pass then return pass.
            // e.g. totalDraws=4 → period=6: 0,1,2,3,2,1, 0,1,2,3,2,1,...
            let period = max(1.0, (total - 1.0) * 2.0)
            let n = elapsed.truncatingRemainder(dividingBy: period)
            return n < total ? n : period - n
        }
    }

    // MARK: - Keyframe interpolation

    private static func keyframeTransform(_ animation: SpriteAnimation, elapsedFrames: Double) -> SpriteTransform {
        let kfs = animation.keyframes
        guard !kfs.isEmpty else { return .identity }

        let n = normalizedElapsed(elapsedFrames, totalDraws: animation.totalDraws, loopMode: animation.loopMode)

        // Hold at last keyframe when past the end.
        if n >= Double(kfs.last!.drawCycle) {
            let last = kfs.last!
            return SpriteTransform(
                positionOffset: last.position,
                scale: last.scale,
                rotation: last.rotation,
                morphAmount: last.morphAmount
            )
        }

        // Hold at first keyframe before the sequence starts.
        if n <= Double(kfs.first!.drawCycle) {
            let first = kfs.first!
            return SpriteTransform(
                positionOffset: first.position,
                scale: first.scale,
                rotation: first.rotation,
                morphAmount: first.morphAmount
            )
        }

        // Find the spanning pair.
        var lo = kfs.first!
        var hi = kfs.last!
        for i in 0..<(kfs.count - 1) {
            if Double(kfs[i].drawCycle) <= n && Double(kfs[i + 1].drawCycle) >= n {
                lo = kfs[i]; hi = kfs[i + 1]
                break
            }
        }

        let span = Double(hi.drawCycle - lo.drawCycle)
        let rawT = span > 0 ? (n - Double(lo.drawCycle)) / span : 0.0
        let t = EasingMath.ease(rawT, type: lo.easing)

        return SpriteTransform(
            positionOffset: Vector2D.lerp(lo.position, hi.position, t: t),
            scale:          Vector2D.lerp(lo.scale,    hi.scale,    t: t),
            rotation:       lerp(lo.rotation, hi.rotation, t: t),
            morphAmount:    lerp(lo.morphAmount, hi.morphAmount, t: t)
        )
    }

    // MARK: - Jitter

    private static func jitterTransform<RNG: RandomNumberGenerator>(
        _ animation: SpriteAnimation,
        using rng: inout RNG
    ) -> SpriteTransform {
        let tx = randomDouble(in: animation.translationRange.x, using: &rng)
        let ty = randomDouble(in: animation.translationRange.y, using: &rng)
        let sx = randomDouble(in: animation.scaleRange.x, using: &rng)
        let sy = randomDouble(in: animation.scaleRange.y, using: &rng)
        let r  = randomDouble(in: animation.rotationRange, using: &rng)
        // Scale of 0 would collapse the sprite; treat zero-range scale as 1.
        let finalSX = animation.scaleRange.x.min == animation.scaleRange.x.max ? 1.0 : sx
        let finalSY = animation.scaleRange.y.min == animation.scaleRange.y.max ? 1.0 : sy
        return SpriteTransform(
            positionOffset: Vector2D(x: tx, y: ty),
            scale:          Vector2D(x: finalSX, y: finalSY),
            rotation:       r,
            morphAmount:    0
        )
    }

    private static func jitterMorphTransform<RNG: RandomNumberGenerator>(
        _ animation: SpriteAnimation,
        using rng: inout RNG
    ) -> SpriteTransform {
        let tx = randomDouble(in: animation.translationRange.x, using: &rng)
        let ty = randomDouble(in: animation.translationRange.y, using: &rng)
        let sx = randomDouble(in: animation.scaleRange.x, using: &rng)
        let sy = randomDouble(in: animation.scaleRange.y, using: &rng)
        let r  = randomDouble(in: animation.rotationRange, using: &rng)
        let ma = lerp(animation.morphMin, animation.morphMax,
                      t: Double.random(in: 0...1, using: &rng))
        let finalSX = animation.scaleRange.x.min == animation.scaleRange.x.max ? 1.0 : sx
        let finalSY = animation.scaleRange.y.min == animation.scaleRange.y.max ? 1.0 : sy
        return SpriteTransform(
            positionOffset: Vector2D(x: tx, y: ty),
            scale:          Vector2D(x: finalSX, y: finalSY),
            rotation:       r,
            morphAmount:    ma
        )
    }

    // MARK: - Helpers

    private static func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        a + (b - a) * t
    }

    private static func randomDouble<RNG: RandomNumberGenerator>(
        in range: FloatRange,
        using rng: inout RNG
    ) -> Double {
        guard range.min < range.max else { return range.min }
        return Double.random(in: range.min...range.max, using: &rng)
    }
}

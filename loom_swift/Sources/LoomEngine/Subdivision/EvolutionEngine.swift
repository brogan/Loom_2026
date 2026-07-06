import Foundation

/// Applies Evolution passes to `[SubdivisionParams]` **before** `SubdivisionEngine` runs.
///
/// All operations are fully stateless and seekable: the drift at frame N is computed
/// with a closed-form weighted sum, so any frame can be evaluated independently.
public enum EvolutionEngine {

    /// Modifies `params` in-place according to all enabled evolution passes.
    ///
    /// - Parameters:
    ///   - params:        Subdivision params to mutate (modified in-place).
    ///   - passes:        Ordered evolution passes to apply.
    ///   - elapsedFrames: Current playback position in frames.
    ///   - targetFPS:     Playback frame rate (used by DoubleDriver evaluation).
    ///   - spriteIndex:   Per-sprite offset for staggering.
    ///   - allSets:       All subdivision-param arrays keyed by set name, for convergence target lookup.
    public static func apply(
        params:        inout [SubdivisionParams],
        passes:        [EvolutionParams],
        elapsedFrames: Double,
        targetFPS:     Double,
        spriteIndex:   Int,
        allSets:       [String: [SubdivisionParams]]
    ) {
        for pass in passes where pass.enabled {
            switch pass.operationType {
            case .momentumDrift:
                applyMomentumDrift(params: &params, pass: pass,
                                   elapsedFrames: elapsedFrames)
            case .convergencePressure:
                applyConvergencePressure(params: &params, pass: pass,
                                         elapsedFrames: elapsedFrames,
                                         targetFPS: targetFPS,
                                         spriteIndex: spriteIndex,
                                         allSets: allSets)
            }
        }
    }

    // MARK: - Momentum drift

    /// Closed-form drift at frame N:
    ///   drift[N] = Σ noise(seed, N-k) × momentum^k   for k = 0 .. K
    /// where K = log(epsilon)/log(momentum), making the sum constant-time and seekable.
    private static func applyMomentumDrift(
        params:        inout [SubdivisionParams],
        pass:          EvolutionParams,
        elapsedFrames: Double
    ) {
        let frameN = Int(max(0, elapsedFrames))
        let drift  = computeDrift(atFrame: frameN, pass: pass)
        for i in params.indices {
            switch pass.driftTarget {
            case .lineRatioX:
                params[i].lineRatios.x = clamp01(params[i].lineRatios.x + drift)
            case .lineRatioY:
                params[i].lineRatios.y = clamp01(params[i].lineRatios.y + drift)
            case .lineRatioXY:
                params[i].lineRatios.x = clamp01(params[i].lineRatios.x + drift)
                params[i].lineRatios.y = clamp01(params[i].lineRatios.y + drift)
            case .cpNormalX:
                params[i].cpNormalOffsets.x += drift
            case .cpNormalY:
                params[i].cpNormalOffsets.y += drift
            case .insetScale:
                let s = max(0.01, params[i].insetTransform.scale.x + drift)
                params[i].insetTransform = InsetTransform(
                    translation: params[i].insetTransform.translation,
                    scale:       Vector2D(x: s, y: s),
                    rotation:    params[i].insetTransform.rotation
                )
            case .insetRotation:
                params[i].insetTransform = InsetTransform(
                    translation: params[i].insetTransform.translation,
                    scale:       params[i].insetTransform.scale,
                    rotation:    params[i].insetTransform.rotation + drift
                )
            }
        }
    }

    private static func computeDrift(atFrame N: Int, pass: EvolutionParams) -> Double {
        let momentum = max(0.0, min(0.9999, pass.driftMomentum))
        let maxK: Int
        if momentum > 1e-6 {
            // Sum terms until weight < 1e-4; cap at 1024 for very high momentum
            maxK = min(Int(ceil(-4.0 / log(momentum + 1e-15))), 1024)
        } else {
            maxK = 0
        }
        var drift = 0.0
        var weight = 1.0
        var totalWeight = 0.0
        for k in 0...maxK {
            let frame = N - k
            // Hash two inputs (seed xor'd with frame index) to get value in [0,1]
            let h = stableNoise(seed: pass.driftSeed, frame: frame,
                                frequency: pass.driftNoiseFrequency)
            drift       += (h * 2.0 - 1.0) * weight
            totalWeight += weight
            weight      *= momentum
            if weight < 1e-4 { break }
        }
        if totalWeight > 0 { drift /= totalWeight }
        return drift * pass.driftNoiseStrength
    }

    /// Deterministic value in [0, 1] for a given seed, frame, and frequency.
    private static func stableNoise(seed: Int, frame: Int, frequency: Double) -> Double {
        guard frame >= 0 else { return 0.5 }
        // Map the continuous frame×frequency position to an integer for the hash
        let bucket = Int(Double(frame) * frequency * 1000.0) & 0x7FFF_FFFF
        return SubdivisionEngine.centreHash(seed: seed ^ frame &* 1231, cycle: bucket)
    }

    // MARK: - Convergence pressure

    private static func applyConvergencePressure(
        params:        inout [SubdivisionParams],
        pass:          EvolutionParams,
        elapsedFrames: Double,
        targetFPS:     Double,
        spriteIndex:   Int,
        allSets:       [String: [SubdivisionParams]]
    ) {
        guard !pass.convergenceTargetSetName.isEmpty,
              let targetSetParams = allSets[pass.convergenceTargetSetName]
        else { return }
        let targetSet = targetSetParams

        let rawPressure = DriverEvaluator.evaluate(
            pass.convergencePressure,
            globalElapsed: elapsedFrames,
            targetFPS:     targetFPS,
            spriteIndex:   spriteIndex
        )
        let pressure = max(0.0, min(1.0, modifiedPressure(
            raw:           rawPressure,
            mode:          pass.convergenceMode,
            elapsedFrames: elapsedFrames,
            duration:      max(1.0, pass.convergenceDuration)
        )))
        guard pressure > 0 else { return }

        for i in params.indices {
            guard i < targetSet.count else { continue }
            let target = targetSet[i]
            params[i].lineRatios = Vector2D(
                x: lerp(params[i].lineRatios.x, target.lineRatios.x, t: pressure),
                y: lerp(params[i].lineRatios.y, target.lineRatios.y, t: pressure)
            )
            params[i].cpNormalOffsets = Vector2D(
                x: lerp(params[i].cpNormalOffsets.x, target.cpNormalOffsets.x, t: pressure),
                y: lerp(params[i].cpNormalOffsets.y, target.cpNormalOffsets.y, t: pressure)
            )
            let sScale = lerp(params[i].insetTransform.scale.x, target.insetTransform.scale.x, t: pressure)
            let sRot   = lerp(params[i].insetTransform.rotation, target.insetTransform.rotation, t: pressure)
            params[i].insetTransform = InsetTransform(
                translation: params[i].insetTransform.translation,
                scale:       Vector2D(x: sScale, y: sScale),
                rotation:    sRot
            )
        }
    }

    private static func modifiedPressure(
        raw:           Double,
        mode:          ConvergenceMode,
        elapsedFrames: Double,
        duration:      Double
    ) -> Double {
        switch mode {
        case .hold:
            return raw
        case .oscillate:
            // Ramps 0→1→0 over `duration` frames, then stays at 0
            let t = (elapsedFrames / duration).truncatingRemainder(dividingBy: 1.0)
            return raw * sin(t * .pi)
        case .loop:
            // Cycles 0→1→0→1… with period `duration`
            let t = (elapsedFrames / duration).truncatingRemainder(dividingBy: 1.0)
            return raw * (1.0 - cos(t * 2.0 * .pi)) * 0.5
        }
    }

    // MARK: - Helpers

    @inline(__always)
    private static func clamp01(_ v: Double) -> Double { max(0.0, min(1.0, v)) }

    @inline(__always)
    private static func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        a + (b - a) * t
    }
}

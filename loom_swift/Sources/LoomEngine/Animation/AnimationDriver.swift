import Foundation

// MARK: - WaveShape

public enum WaveShape: String, Codable, CaseIterable, Equatable, Sendable {
    case sine, triangle, square, sawtooth
}

// MARK: - Per-property keyframes

/// One keyframe on a scalar (Double) track.
public struct DoubleKeyframe: Codable, Equatable, Sendable {
    public var frame:  Int
    public var value:  Double
    public var easing: EasingType

    public init(frame: Int = 0, value: Double = 0, easing: EasingType = .linear) {
        self.frame = frame; self.value = value; self.easing = easing
    }
}

/// One keyframe on a 2-D vector track.
public struct VectorKeyframe: Codable, Equatable, Sendable {
    public var frame:  Int
    public var value:  Vector2D
    public var easing: EasingType

    public init(frame: Int = 0, value: Vector2D = .zero, easing: EasingType = .linear) {
        self.frame = frame; self.value = value; self.easing = easing
    }
}

// MARK: - DoubleDriver
//
// Produces a scalar value each frame.  The `mode` field selects the evaluation
// strategy; only the fields relevant to the selected mode matter.
//
// Modes:
//   constant   — fixed value (base).
//   jitter     — random in [base − range, base + range] per frame.
//                Seeded deterministically: same (seed, spriteIndex, frame) → same value.
//   noise      — smooth continuous random walk.  Random values are sampled at
//                every `period` global frames and smoothly interpolated between.
//   oscillator — periodic wave (sine / triangle / square / sawtooth).
//                freqHz = cycles per second at the project targetFPS.
//   keyframe   — interpolated between DoubleKeyframe entries keyed to global frame.

public struct DoubleDriver: Codable, Equatable, Sendable {

    public enum Mode: String, Codable, CaseIterable, Equatable, Sendable {
        case constant, jitter, noise, oscillator, keyframe
    }

    public var mode:      Mode      = .constant
    /// Centre / constant value.  Used by: constant, jitter, noise, oscillator.
    public var base:      Double    = 0
    /// Jitter: half-width of random window ([base − range, base + range]).
    public var range:     Double    = 0
    /// Noise / oscillator: peak excursion from base.
    public var amplitude: Double    = 0
    /// Noise: global frames between random sample points (smoothly interpolated).
    public var period:    Int       = 30
    /// Oscillator: cycles per second.
    public var freqHz:    Double    = 1.0
    /// Oscillator: 0–1 phase offset applied before wave evaluation.
    public var phase:     Double    = 0
    public var wave:      WaveShape = .sine
    /// Jitter / noise: deterministic seed.  Combine with spriteIndex at evaluation time.
    public var seed:      Int       = 0
    /// Keyframe: how the sequence repeats when global frame exceeds the last keyframe.
    public var loopMode:  LoopMode  = .loop
    public var keyframes: [DoubleKeyframe] = []

    public init(
        mode:      Mode         = .constant,
        base:      Double       = 0,
        range:     Double       = 0,
        amplitude: Double       = 0,
        period:    Int          = 30,
        freqHz:    Double       = 1.0,
        phase:     Double       = 0,
        wave:      WaveShape    = .sine,
        seed:      Int          = 0,
        loopMode:  LoopMode     = .loop,
        keyframes: [DoubleKeyframe] = []
    ) {
        self.mode = mode; self.base = base; self.range = range
        self.amplitude = amplitude; self.period = period
        self.freqHz = freqHz; self.phase = phase; self.wave = wave
        self.seed = seed; self.loopMode = loopMode; self.keyframes = keyframes
    }

    public static let zero     = DoubleDriver(mode: .constant, base: 0)
    public static let one      = DoubleDriver(mode: .constant, base: 1)

    public static func constant(_ v: Double) -> DoubleDriver {
        DoubleDriver(mode: .constant, base: v)
    }
}

// MARK: - VectorDriver
//
// Identical concept to DoubleDriver but for 2-D vector properties (position, scale).
// Oscillator supports independent X/Y frequencies for Lissajous and similar patterns.

public struct VectorDriver: Codable, Equatable, Sendable {

    public enum Mode: String, Codable, CaseIterable, Equatable, Sendable {
        case constant, jitter, noise, oscillator, keyframe
    }

    public var mode:      Mode      = .constant
    public var base:      Vector2D  = .zero
    public var range:     Vector2D  = .zero
    public var amplitude: Vector2D  = .zero
    public var period:    Int       = 30
    /// Independent X/Y frequency — allows Lissajous and orbital patterns.
    public var freqHz:    Vector2D  = Vector2D(x: 1, y: 1)
    public var phase:     Vector2D  = .zero
    public var wave:      WaveShape = .sine
    public var seed:      Int       = 0
    public var loopMode:  LoopMode  = .loop
    public var keyframes: [VectorKeyframe] = []

    public init(
        mode:      Mode           = .constant,
        base:      Vector2D       = .zero,
        range:     Vector2D       = .zero,
        amplitude: Vector2D       = .zero,
        period:    Int            = 30,
        freqHz:    Vector2D       = Vector2D(x: 1, y: 1),
        phase:     Vector2D       = .zero,
        wave:      WaveShape      = .sine,
        seed:      Int            = 0,
        loopMode:  LoopMode       = .loop,
        keyframes: [VectorKeyframe] = []
    ) {
        self.mode = mode; self.base = base; self.range = range
        self.amplitude = amplitude; self.period = period
        self.freqHz = freqHz; self.phase = phase; self.wave = wave
        self.seed = seed; self.loopMode = loopMode; self.keyframes = keyframes
    }

    public static let zero     = VectorDriver(mode: .constant, base: .zero)
    public static let identity = VectorDriver(mode: .constant, base: Vector2D(x: 1, y: 1))

    public static func constant(_ v: Vector2D) -> VectorDriver {
        VectorDriver(mode: .constant, base: v)
    }
}

// MARK: - DriverEvaluator

/// Stateless evaluation of DoubleDriver and VectorDriver at a given global elapsed frame count.
///
/// All evaluation is deterministic given the same (driver, globalElapsed, targetFPS, spriteIndex).
/// No mutable state is required or mutated.
public enum DriverEvaluator {

    // MARK: Double

    public static func evaluate(
        _ driver: DoubleDriver,
        globalElapsed: Double,
        targetFPS:     Double,
        spriteIndex:   Int
    ) -> Double {
        switch driver.mode {

        case .constant:
            return driver.base

        case .jitter:
            let v = hash(seed: driver.seed, spriteIndex: spriteIndex, frame: Int(globalElapsed))
            return driver.base + (v * 2 - 1) * driver.range

        case .noise:
            return valueNoise1D(
                base: driver.base, amplitude: driver.amplitude,
                period: max(1, driver.period), elapsed: globalElapsed,
                seed: driver.seed, spriteIndex: spriteIndex
            )

        case .oscillator:
            let fps = max(1, targetFPS)
            let t   = globalElapsed * driver.freqHz / fps + driver.phase
            return driver.base + driver.amplitude * wave(driver.wave, t: t)

        case .keyframe:
            guard !driver.keyframes.isEmpty else { return driver.base }
            return evalDoubleKFs(driver.keyframes,
                                 elapsed: globalElapsed, loop: driver.loopMode)
        }
    }

    // MARK: Vector

    public static func evaluate(
        _ driver: VectorDriver,
        globalElapsed: Double,
        targetFPS:     Double,
        spriteIndex:   Int
    ) -> Vector2D {
        switch driver.mode {

        case .constant:
            return driver.base

        case .jitter:
            let vx = hash(seed: driver.seed,      spriteIndex: spriteIndex, frame: Int(globalElapsed))
            let vy = hash(seed: driver.seed &+ 1, spriteIndex: spriteIndex, frame: Int(globalElapsed))
            return Vector2D(
                x: driver.base.x + (vx * 2 - 1) * driver.range.x,
                y: driver.base.y + (vy * 2 - 1) * driver.range.y
            )

        case .noise:
            let nx = valueNoise1D(base: driver.base.x, amplitude: driver.amplitude.x,
                                  period: max(1, driver.period), elapsed: globalElapsed,
                                  seed: driver.seed,      spriteIndex: spriteIndex)
            let ny = valueNoise1D(base: driver.base.y, amplitude: driver.amplitude.y,
                                  period: max(1, driver.period), elapsed: globalElapsed,
                                  seed: driver.seed &+ 1, spriteIndex: spriteIndex)
            return Vector2D(x: nx, y: ny)

        case .oscillator:
            let fps = max(1, targetFPS)
            let tx  = globalElapsed * driver.freqHz.x / fps + driver.phase.x
            let ty  = globalElapsed * driver.freqHz.y / fps + driver.phase.y
            return Vector2D(
                x: driver.base.x + driver.amplitude.x * wave(driver.wave, t: tx),
                y: driver.base.y + driver.amplitude.y * wave(driver.wave, t: ty)
            )

        case .keyframe:
            guard !driver.keyframes.isEmpty else { return driver.base }
            return evalVectorKFs(driver.keyframes,
                                 elapsed: globalElapsed, loop: driver.loopMode)
        }
    }

    // MARK: - Wave

    private static func wave(_ shape: WaveShape, t: Double) -> Double {
        let p = t - floor(t)   // normalised 0…1
        switch shape {
        case .sine:
            return sin(p * 2 * .pi)
        case .triangle:
            return p < 0.25 ? p * 4 : p < 0.75 ? 2 - p * 4 : p * 4 - 4
        case .square:
            return p < 0.5 ? 1.0 : -1.0
        case .sawtooth:
            return p * 2 - 1
        }
    }

    // MARK: - Value noise

    // Samples two random values at integer multiples of `period` and smoothly
    // interpolates between them — stateless 1-D value noise.
    private static func valueNoise1D(
        base: Double, amplitude: Double, period: Int,
        elapsed: Double, seed: Int, spriteIndex: Int
    ) -> Double {
        let sA = Int(elapsed) / period
        let sB = sA + 1
        let t  = smoothstep((elapsed - Double(sA * period)) / Double(period))
        let va = hash(seed: seed,      spriteIndex: spriteIndex, frame: sA)
        let vb = hash(seed: seed,      spriteIndex: spriteIndex, frame: sB)
        return base + (va + (vb - va) * t * 2 - 1) * amplitude
    }

    private static func smoothstep(_ t: Double) -> Double {
        let c = max(0, min(1, t))
        return c * c * (3 - 2 * c)
    }

    // MARK: - Deterministic hash

    // Maps (seed, spriteIndex, frame) → [0, 1) deterministically.
    // Uses a finalisation mix from Murmur3 / PCG.
    private static func hash(seed: Int, spriteIndex: Int, frame: Int) -> Double {
        var h = UInt64(bitPattern: Int64(seed)        &* 2_654_435_761)
              ^ UInt64(bitPattern: Int64(spriteIndex) &* 2_246_822_519)
              ^ UInt64(bitPattern: Int64(frame)       &* 1_640_531_513)
        h ^= h >> 33
        h &*= 0xff51afd7ed558ccd
        h ^= h >> 33
        h &*= 0xc4ceb9fe1a85ec53
        h ^= h >> 33
        return Double(h >> 11) / Double(1 << 53)
    }

    // MARK: - Shape (step evaluation)

    /// Evaluates a shape driver using step semantics: no interpolation between keyframes.
    /// Returns the integer index of the last keyframe whose frame number is ≤ the
    /// normalised elapsed time.  0 = base sprite; 1+ = spriteVariants[index−1].
    public static func evaluateShapeIndex(
        _ driver: DoubleDriver,
        globalElapsed: Double
    ) -> Int {
        switch driver.mode {
        case .constant:
            return max(0, Int(driver.base))
        case .keyframe:
            guard !driver.keyframes.isEmpty else { return max(0, Int(driver.base)) }
            let n = normalizeElapsed(globalElapsed,
                                     total: driver.keyframes.last!.frame,
                                     loop: driver.loopMode)
            // Step: walk keyframes in order, keep the last one whose frame ≤ n.
            var result = driver.keyframes.first!.value
            for kf in driver.keyframes {
                guard Double(kf.frame) <= n else { break }
                result = kf.value
            }
            return max(0, Int(result))
        default:
            return max(0, Int(driver.base))
        }
    }

    // MARK: - Keyframe helpers

    private static func normalizeElapsed(_ e: Double, total: Int, loop: LoopMode) -> Double {
        guard total > 0 else { return e }
        let t = Double(total)
        switch loop {
        case .loop:
            return e.truncatingRemainder(dividingBy: t)
        case .once:
            return min(e, t)
        case .pingPong:
            let period = t * 2
            let n = e.truncatingRemainder(dividingBy: period)
            return n <= t ? n : period - n
        }
    }

    private static func evalDoubleKFs(
        _ kfs: [DoubleKeyframe], elapsed: Double, loop: LoopMode
    ) -> Double {
        guard !kfs.isEmpty else { return 0 }
        guard kfs.count > 1 else { return kfs[0].value }
        let n = normalizeElapsed(elapsed, total: kfs.last!.frame, loop: loop)
        if n <= Double(kfs.first!.frame) { return kfs.first!.value }
        if n >= Double(kfs.last!.frame)  { return kfs.last!.value }
        for i in 0..<(kfs.count - 1) {
            let lo = kfs[i], hi = kfs[i + 1]
            guard Double(lo.frame) <= n, n <= Double(hi.frame) else { continue }
            let span = Double(hi.frame - lo.frame)
            let t    = EasingMath.ease(span > 0 ? (n - Double(lo.frame)) / span : 0, type: lo.easing)
            return lo.value + (hi.value - lo.value) * t
        }
        return kfs.last!.value
    }

    private static func evalVectorKFs(
        _ kfs: [VectorKeyframe], elapsed: Double, loop: LoopMode
    ) -> Vector2D {
        guard !kfs.isEmpty else { return .zero }
        guard kfs.count > 1 else { return kfs[0].value }
        let n = normalizeElapsed(elapsed, total: kfs.last!.frame, loop: loop)
        if n <= Double(kfs.first!.frame) { return kfs.first!.value }
        if n >= Double(kfs.last!.frame)  { return kfs.last!.value }
        for i in 0..<(kfs.count - 1) {
            let lo = kfs[i], hi = kfs[i + 1]
            guard Double(lo.frame) <= n, n <= Double(hi.frame) else { continue }
            let span = Double(hi.frame - lo.frame)
            let t    = EasingMath.ease(span > 0 ? (n - Double(lo.frame)) / span : 0, type: lo.easing)
            return Vector2D.lerp(lo.value, hi.value, t: t)
        }
        return kfs.last!.value
    }
}

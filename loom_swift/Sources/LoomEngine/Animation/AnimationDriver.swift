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

/// One keyframe on an RGBA colour track.
public struct ColorKeyframe: Codable, Equatable, Sendable {
    public var frame: Int
    public var value: LoomColor
    public var easing: EasingType

    public init(frame: Int = 0, value: LoomColor = .black, easing: EasingType = .linear) {
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
    /// When false the driver returns its neutral identity value; the engine skips evaluation.
    /// Default false for new drivers. Legacy projects infer true when non-trivial.
    public var enabled:   Bool      = false

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
        keyframes: [DoubleKeyframe] = [],
        enabled:   Bool         = false
    ) {
        self.mode = mode; self.base = base; self.range = range
        self.amplitude = amplitude; self.period = period
        self.freqHz = freqHz; self.phase = phase; self.wave = wave
        self.seed = seed; self.loopMode = loopMode; self.keyframes = keyframes
        self.enabled = enabled
    }

    public static let zero     = DoubleDriver(mode: .constant, base: 0)
    public static let one      = DoubleDriver(mode: .constant, base: 1)

    public static func constant(_ v: Double) -> DoubleDriver {
        DoubleDriver(mode: .constant, base: v)
    }

    private enum CodingKeys: String, CodingKey {
        case mode, base, range, amplitude, period, freqHz, phase, wave, seed, loopMode, keyframes, enabled
    }

    public init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        mode          = try c.decodeIfPresent(Mode.self,             forKey: .mode)      ?? .constant
        base          = try c.decodeIfPresent(Double.self,           forKey: .base)      ?? 0
        range         = try c.decodeIfPresent(Double.self,           forKey: .range)     ?? 0
        amplitude     = try c.decodeIfPresent(Double.self,           forKey: .amplitude) ?? 0
        period        = try c.decodeIfPresent(Int.self,              forKey: .period)    ?? 30
        freqHz        = try c.decodeIfPresent(Double.self,           forKey: .freqHz)    ?? 1.0
        phase         = try c.decodeIfPresent(Double.self,           forKey: .phase)     ?? 0
        wave          = try c.decodeIfPresent(WaveShape.self,        forKey: .wave)      ?? .sine
        seed          = try c.decodeIfPresent(Int.self,              forKey: .seed)      ?? 0
        loopMode      = try c.decodeIfPresent(LoopMode.self,         forKey: .loopMode)  ?? .loop
        keyframes     = try c.decodeIfPresent([DoubleKeyframe].self,  forKey: .keyframes) ?? []
        // Backward compat: if key absent, infer enabled from non-trivial configuration.
        if let stored = try c.decodeIfPresent(Bool.self, forKey: .enabled) {
            enabled = stored
        } else {
            enabled = (mode != .constant) || !keyframes.isEmpty
        }
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
    /// When false the driver returns its neutral identity value; the engine skips evaluation.
    /// Default false for new drivers. Legacy projects infer true when non-trivial.
    public var enabled:   Bool      = false

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
        keyframes: [VectorKeyframe] = [],
        enabled:   Bool           = false
    ) {
        self.mode = mode; self.base = base; self.range = range
        self.amplitude = amplitude; self.period = period
        self.freqHz = freqHz; self.phase = phase; self.wave = wave
        self.seed = seed; self.loopMode = loopMode; self.keyframes = keyframes
        self.enabled = enabled
    }

    public static let zero     = VectorDriver(mode: .constant, base: .zero)
    public static let identity = VectorDriver(mode: .constant, base: Vector2D(x: 1, y: 1))

    public static func constant(_ v: Vector2D) -> VectorDriver {
        VectorDriver(mode: .constant, base: v)
    }

    private enum CodingKeys: String, CodingKey {
        case mode, base, range, amplitude, period, freqHz, phase, wave, seed, loopMode, keyframes, enabled
    }

    public init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        mode          = try c.decodeIfPresent(Mode.self,              forKey: .mode)      ?? .constant
        base          = try c.decodeIfPresent(Vector2D.self,          forKey: .base)      ?? .zero
        range         = try c.decodeIfPresent(Vector2D.self,          forKey: .range)     ?? .zero
        amplitude     = try c.decodeIfPresent(Vector2D.self,          forKey: .amplitude) ?? .zero
        period        = try c.decodeIfPresent(Int.self,               forKey: .period)    ?? 30
        freqHz        = try c.decodeIfPresent(Vector2D.self,          forKey: .freqHz)    ?? Vector2D(x: 1, y: 1)
        phase         = try c.decodeIfPresent(Vector2D.self,          forKey: .phase)     ?? .zero
        wave          = try c.decodeIfPresent(WaveShape.self,         forKey: .wave)      ?? .sine
        seed          = try c.decodeIfPresent(Int.self,               forKey: .seed)      ?? 0
        loopMode      = try c.decodeIfPresent(LoopMode.self,          forKey: .loopMode)  ?? .loop
        keyframes     = try c.decodeIfPresent([VectorKeyframe].self,  forKey: .keyframes) ?? []
        // Backward compat: if key absent, infer enabled from non-trivial configuration.
        if let stored = try c.decodeIfPresent(Bool.self, forKey: .enabled) {
            enabled = stored
        } else {
            enabled = (mode != .constant) || !keyframes.isEmpty
        }
    }
}

// MARK: - ColorDriver

public struct ColorDriver: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Equatable, Sendable {
        case constant, keyframe, jitter, noise, oscillator
    }

    public var mode: Mode = .constant
    /// Color A — constant value, and the "from" color for blend modes.
    public var base:      LoomColor  = .black
    /// Color B — the "to" color for jitter, noise, and oscillator modes.
    public var colorB:    LoomColor  = .white
    /// Jitter: half-width of blend window around 0.5. 0.5 = full [0,1] swing.
    public var range:     Double     = 0.5
    /// Noise: peak blend excursion from 0.5. 0.5 = full [0,1] swing.
    public var amplitude: Double     = 0.5
    /// Noise: global frames between random sample points.
    public var period:    Int        = 30
    /// Oscillator: cycles per second.
    public var freqHz:    Double     = 1.0
    /// Oscillator: 0–1 phase offset.
    public var phase:     Double     = 0
    public var wave:      WaveShape  = .sine
    /// Jitter / noise: deterministic seed.
    public var seed:      Int        = 0
    public var loopMode:  LoopMode   = .loop
    public var keyframes: [ColorKeyframe] = []
    /// When false the driver returns its base colour; the engine skips evaluation.
    public var enabled:   Bool       = false

    public init(
        mode:      Mode            = .constant,
        base:      LoomColor       = .black,
        colorB:    LoomColor       = .white,
        range:     Double          = 0.5,
        amplitude: Double          = 0.5,
        period:    Int             = 30,
        freqHz:    Double          = 1.0,
        phase:     Double          = 0,
        wave:      WaveShape       = .sine,
        seed:      Int             = 0,
        loopMode:  LoopMode        = .loop,
        keyframes: [ColorKeyframe] = [],
        enabled:   Bool            = false
    ) {
        self.mode = mode; self.base = base; self.colorB = colorB
        self.range = range; self.amplitude = amplitude; self.period = period
        self.freqHz = freqHz; self.phase = phase; self.wave = wave
        self.seed = seed; self.loopMode = loopMode; self.keyframes = keyframes
        self.enabled = enabled
    }

    public static func constant(_ color: LoomColor) -> ColorDriver {
        ColorDriver(mode: .constant, base: color)
    }

    private enum CodingKeys: String, CodingKey {
        case mode, base, colorB, range, amplitude, period, freqHz, phase, wave, seed, loopMode, keyframes, enabled
    }

    public init(from decoder: Decoder) throws {
        let c     = try decoder.container(keyedBy: CodingKeys.self)
        mode      = try c.decodeIfPresent(Mode.self,            forKey: .mode)      ?? .constant
        base      = try c.decodeIfPresent(LoomColor.self,       forKey: .base)      ?? .black
        colorB    = try c.decodeIfPresent(LoomColor.self,       forKey: .colorB)    ?? .white
        range     = try c.decodeIfPresent(Double.self,          forKey: .range)     ?? 0.5
        amplitude = try c.decodeIfPresent(Double.self,          forKey: .amplitude) ?? 0.5
        period    = try c.decodeIfPresent(Int.self,             forKey: .period)    ?? 30
        freqHz    = try c.decodeIfPresent(Double.self,          forKey: .freqHz)    ?? 1.0
        phase     = try c.decodeIfPresent(Double.self,          forKey: .phase)     ?? 0
        wave      = try c.decodeIfPresent(WaveShape.self,       forKey: .wave)      ?? .sine
        seed      = try c.decodeIfPresent(Int.self,             forKey: .seed)      ?? 0
        loopMode  = try c.decodeIfPresent(LoopMode.self,        forKey: .loopMode)  ?? .loop
        keyframes = try c.decodeIfPresent([ColorKeyframe].self, forKey: .keyframes) ?? []
        if let stored = try c.decodeIfPresent(Bool.self, forKey: .enabled) {
            enabled = stored
        } else {
            enabled = (mode != .constant) || !keyframes.isEmpty
        }
    }
}

// MARK: - NameKeyframe / NameDriver

/// One keyframe on a name (String) track — used for subdivision-set and renderer-set drivers.
public struct NameKeyframe: Codable, Equatable, Sendable {
    public var frame: Int
    public var value: String

    public init(frame: Int = 0, value: String = "") {
        self.frame = frame
        self.value = value
    }
}

/// Selects a named configuration set (renderer set or subdivision-params set) each frame.
/// Nil return from `evaluateName` means "don't override; keep the sprite's static assignment".
public struct NameDriver: Codable, Equatable, Sendable {

    public enum Mode: String, Codable, CaseIterable, Equatable, Sendable {
        case constant, keyframe, jitter
    }

    public var mode:       Mode           = .constant
    /// Constant / fallback set name.
    public var base:       String         = ""
    /// Ordered set-name keyframes (step semantics — no interpolation).
    public var keyframes:  [NameKeyframe] = []
    /// Pool of set names for jitter mode.
    public var jitterPool: [String]       = []
    /// Deterministic random seed (jitter mode).
    public var seed:       Int            = 0
    /// Jitter hold duration in frames — the chosen set is held for this many frames before
    /// re-rolling. period=1 (default) re-rolls every frame; period=30 at 30 fps = ~1 switch/sec.
    public var period:     Int            = 1
    /// How the keyframe sequence repeats.
    public var loopMode:   LoopMode       = .loop
    /// When false the driver is bypassed.
    public var enabled:    Bool           = false

    public init(
        mode:       Mode           = .constant,
        base:       String         = "",
        keyframes:  [NameKeyframe] = [],
        jitterPool: [String]       = [],
        seed:       Int            = 0,
        period:     Int            = 1,
        loopMode:   LoopMode       = .loop,
        enabled:    Bool           = false
    ) {
        self.mode = mode; self.base = base; self.keyframes = keyframes
        self.jitterPool = jitterPool; self.seed = seed; self.period = period
        self.loopMode = loopMode; self.enabled = enabled
    }

    /// Disabled default — absent from JSON is equivalent to `.disabled`.
    public static let disabled = NameDriver()

    private enum CodingKeys: String, CodingKey {
        case mode, base, keyframes, jitterPool, seed, period, loopMode, enabled
    }

    public init(from decoder: Decoder) throws {
        let c      = try decoder.container(keyedBy: CodingKeys.self)
        mode       = try c.decodeIfPresent(Mode.self,           forKey: .mode)       ?? .constant
        base       = try c.decodeIfPresent(String.self,         forKey: .base)       ?? ""
        keyframes  = try c.decodeIfPresent([NameKeyframe].self, forKey: .keyframes)  ?? []
        jitterPool = try c.decodeIfPresent([String].self,       forKey: .jitterPool) ?? []
        seed       = try c.decodeIfPresent(Int.self,            forKey: .seed)       ?? 0
        period     = try c.decodeIfPresent(Int.self,            forKey: .period)     ?? 1
        loopMode   = try c.decodeIfPresent(LoopMode.self,       forKey: .loopMode)   ?? .loop
        enabled    = try c.decodeIfPresent(Bool.self,           forKey: .enabled)    ?? false
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
        spriteIndex:   Int,
        phaseOffset:   Double = 0
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
            let t   = globalElapsed * driver.freqHz / fps + driver.phase + phaseOffset
            return driver.base + driver.amplitude * wave(driver.wave, t: t)

        case .keyframe:
            guard !driver.keyframes.isEmpty else { return driver.base }
            guard globalElapsed >= Double(driver.keyframes.sorted { $0.frame < $1.frame }.first!.frame) else {
                return driver.base
            }
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
            guard globalElapsed >= Double(driver.keyframes.sorted { $0.frame < $1.frame }.first!.frame) else {
                return driver.base
            }
            return evalVectorKFs(driver.keyframes,
                                 elapsed: globalElapsed, loop: driver.loopMode)
        }
    }

    // MARK: Color

    public static func evaluate(
        _ driver: ColorDriver,
        globalElapsed: Double,
        targetFPS: Double = 60,
        spriteIndex: Int = 0
    ) -> LoomColor {
        switch driver.mode {
        case .constant:
            return driver.base
        case .keyframe:
            guard !driver.keyframes.isEmpty else { return driver.base }
            guard globalElapsed >= Double(driver.keyframes.sorted { $0.frame < $1.frame }.first!.frame) else {
                return driver.base
            }
            return evalColorKFs(driver.keyframes,
                                elapsed: globalElapsed,
                                loop: driver.loopMode)
        case .jitter:
            let h = hash(seed: driver.seed, spriteIndex: spriteIndex, frame: Int(globalElapsed))
            let t = clamp01(0.5 + (h * 2 - 1) * driver.range)
            return lerpColor(driver.base, driver.colorB, t: t)
        case .noise:
            let raw = valueNoise1D(base: 0.5, amplitude: driver.amplitude,
                                   period: max(1, driver.period), elapsed: globalElapsed,
                                   seed: driver.seed, spriteIndex: spriteIndex)
            return lerpColor(driver.base, driver.colorB, t: clamp01(raw))
        case .oscillator:
            let fps  = max(1, targetFPS)
            let tArg = globalElapsed * driver.freqHz / fps + driver.phase
            let blend = clamp01((wave(driver.wave, t: tArg) + 1) / 2)
            return lerpColor(driver.base, driver.colorB, t: blend)
        }
    }

    private static func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }

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
            let sorted = driver.keyframes.sorted { $0.frame < $1.frame }
            guard globalElapsed >= Double(sorted.first!.frame) else {
                return max(0, Int(driver.base))
            }
            let n = normalizeElapsed(globalElapsed,
                                     total: sorted.last!.frame,
                                     loop: driver.loopMode)
            // Step: walk keyframes in order, keep the last one whose frame ≤ n.
            var result = sorted.first!.value
            for kf in sorted {
                guard Double(kf.frame) <= n else { break }
                result = kf.value
            }
            return max(0, Int(result))
        default:
            return max(0, Int(driver.base))
        }
    }

    // MARK: - NameDriver evaluation

    /// Evaluates a `NameDriver` and returns the active set name, or `nil` to indicate
    /// "no override — keep the sprite's static assignment".
    ///
    /// - `.constant`: returns `base`; nil if base is empty.
    /// - `.keyframe`: step function — finds the last keyframe whose frame ≤ normalised
    ///   elapsed and returns its value; nil if value is empty.
    /// - `.jitter`:   deterministic pick from `jitterPool`; nil if pool is empty.
    public static func evaluateName(
        _ driver: NameDriver,
        globalElapsed: Double,
        spriteIndex: Int
    ) -> String? {
        switch driver.mode {

        case .constant:
            return driver.base.isEmpty ? nil : driver.base

        case .keyframe:
            guard !driver.keyframes.isEmpty else { return driver.base.isEmpty ? nil : driver.base }
            let sorted = driver.keyframes.sorted { $0.frame < $1.frame }
            guard globalElapsed >= Double(sorted.first!.frame) else {
                return driver.base.isEmpty ? nil : driver.base
            }
            // Inline normalizeElapsed logic (private on DriverEvaluator)
            let total = sorted.last!.frame
            let normalized: Double = {
                guard total > 0 else { return globalElapsed }
                let t = Double(total)
                switch driver.loopMode {
                case .loop:
                    return globalElapsed.truncatingRemainder(dividingBy: t)
                case .once:
                    return min(globalElapsed, t)
                case .pingPong:
                    let period = t * 2
                    let n = globalElapsed.truncatingRemainder(dividingBy: period)
                    return n <= t ? n : period - n
                }
            }()
            var result = sorted.first!.value
            for kf in sorted {
                guard Double(kf.frame) <= normalized else { break }
                result = kf.value
            }
            return result.isEmpty ? nil : result

        case .jitter:
            guard !driver.jitterPool.isEmpty else { return nil }
            let slowFrame = Int(globalElapsed) / max(1, driver.period)
            let h = hash(seed: driver.seed, spriteIndex: spriteIndex, frame: slowFrame)
            let idx = Int(h * Double(driver.jitterPool.count))
            let clamped = max(0, min(driver.jitterPool.count - 1, idx))
            let name = driver.jitterPool[clamped]
            return name.isEmpty ? nil : name
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
        let sorted = kfs.sorted { $0.frame < $1.frame }
        guard sorted.count > 1 else { return sorted[0].value }
        let n = normalizeElapsed(elapsed, total: sorted.last!.frame, loop: loop)
        if n <= Double(sorted.first!.frame) { return sorted.first!.value }
        if n >= Double(sorted.last!.frame)  { return sorted.last!.value }
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i], hi = sorted[i + 1]
            guard Double(lo.frame) <= n, n <= Double(hi.frame) else { continue }
            let span = Double(hi.frame - lo.frame)
            let t    = EasingMath.ease(span > 0 ? (n - Double(lo.frame)) / span : 0, type: lo.easing)
            return lo.value + (hi.value - lo.value) * t
        }
        return sorted.last!.value
    }

    private static func evalVectorKFs(
        _ kfs: [VectorKeyframe], elapsed: Double, loop: LoopMode
    ) -> Vector2D {
        guard !kfs.isEmpty else { return .zero }
        let sorted = kfs.sorted { $0.frame < $1.frame }
        guard sorted.count > 1 else { return sorted[0].value }
        let n = normalizeElapsed(elapsed, total: sorted.last!.frame, loop: loop)
        if n <= Double(sorted.first!.frame) { return sorted.first!.value }
        if n >= Double(sorted.last!.frame)  { return sorted.last!.value }
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i], hi = sorted[i + 1]
            guard Double(lo.frame) <= n, n <= Double(hi.frame) else { continue }
            let span = Double(hi.frame - lo.frame)
            let t    = EasingMath.ease(span > 0 ? (n - Double(lo.frame)) / span : 0, type: lo.easing)
            return Vector2D.lerp(lo.value, hi.value, t: t)
        }
        return sorted.last!.value
    }

    private static func evalColorKFs(
        _ kfs: [ColorKeyframe], elapsed: Double, loop: LoopMode
    ) -> LoomColor {
        guard !kfs.isEmpty else { return .black }
        guard kfs.count > 1 else { return kfs[0].value }
        let sorted = kfs.sorted { $0.frame < $1.frame }
        let n = normalizeElapsed(elapsed, total: sorted.last!.frame, loop: loop)
        if n <= Double(sorted.first!.frame) { return sorted.first!.value }
        if n >= Double(sorted.last!.frame)  { return sorted.last!.value }
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i], hi = sorted[i + 1]
            guard Double(lo.frame) <= n, n <= Double(hi.frame) else { continue }
            let span = Double(hi.frame - lo.frame)
            let t = EasingMath.ease(span > 0 ? (n - Double(lo.frame)) / span : 0, type: lo.easing)
            return lerpColor(lo.value, hi.value, t: t)
        }
        return sorted.last!.value
    }

    private static func lerpColor(_ a: LoomColor, _ b: LoomColor, t: Double) -> LoomColor {
        let c = max(0, min(1, t))
        func channel(_ x: Int, _ y: Int) -> Int {
            Int((Double(x) + (Double(y) - Double(x)) * c).rounded())
        }
        return LoomColor(
            r: channel(a.r, b.r),
            g: channel(a.g, b.g),
            b: channel(a.b, b.b),
            a: channel(a.a, b.a)
        )
    }
}

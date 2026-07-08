import Foundation

public enum EvolutionOperationType: String, Codable, CaseIterable, Equatable, Sendable {
    case momentumDrift       = "Momentum Drift"
    case convergencePressure = "Convergence Pressure"
    /// Structural mutation across generations (artificial life) — see
    /// Specs/GeometricLifecycle.md §4.4. Unlike the other two, this operates on
    /// materialized `[Polygon2D]` geometry, not `SubdivisionParams` fields, so it
    /// is a no-op in `EvolutionEngine.apply` and is instead dispatched by
    /// `GenerationalEvolutionEngine` at its own point in the render pipeline
    /// (after Extension, before Dissolution — see `SpriteScene.swift`).
    case generational        = "Generational"
}

public enum DriftTarget: String, Codable, CaseIterable, Equatable, Sendable {
    case lineRatioX    = "Line Ratio X"
    case lineRatioY    = "Line Ratio Y"
    case lineRatioXY   = "Line Ratio XY"
    case cpNormalX     = "CP Normal X"
    case cpNormalY     = "CP Normal Y"
    case insetScale    = "Inset Scale"
    case insetRotation = "Inset Rotation"
}

public enum ConvergenceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case hold      = "Hold"
    case oscillate = "Oscillate"
    case loop      = "Loop"
}

public struct EvolutionParams: Equatable, Codable, Sendable {
    public var name:          String
    public var enabled:       Bool
    public var operationType: EvolutionOperationType

    // Momentum drift (operationType == .momentumDrift)
    public var driftTarget:         DriftTarget
    public var driftMomentum:       Double   // 0–1; higher = smoother/slower changing drift
    public var driftNoiseStrength:  Double   // peak displacement amplitude
    public var driftNoiseFrequency: Double   // temporal noise rate (cycles per frame)
    public var driftSeed:           Int

    // Convergence pressure (operationType == .convergencePressure)
    public var convergenceTargetSetName: String
    public var convergencePressure:      DoubleDriver   // 0 = no effect, 1 = fully converged
    public var convergenceMode:          ConvergenceMode
    public var convergenceDuration:      Double         // frames for one oscillate/loop cycle

    // Generational (operationType == .generational) — see GenerationalEvolutionEngine.
    // Randomness (operator choice, target polygon, run length, distance) is drawn from
    // SubdivisionEngine.centreHash(seed:cycle:) keyed on generationSeed — deliberately
    // not DoubleDriver, which is a per-frame animation primitive; generation index is
    // a structural axis, not playback time.
    public var generationCount:       Int      // how many generations to run
    public var extrudeWeight:         Double   // relative selection weight; 0 excludes the operator
    public var splitWeight:           Double
    public var extrudeRunLengthMin:   Int      // contiguous edges extruded together, RPSR
    public var extrudeRunLengthMax:   Int
    public var extrudeDistanceMin:    Double   // RPSR outward distance
    public var extrudeDistanceMax:    Double
    public var splitDisplacementMin:  Double   // RPSR outward displacement of the new split anchor
    public var splitDisplacementMax:  Double
    public var generationSeed:        Int
    public var maxVertexBudget:       Int      // hard cap on total vertex count; required, not optional

    /// Restricts which edges the extrude/split operators may target by outward-
    /// normal direction (Specs/GeometricLifecycle.md §14) — e.g. "only the top
    /// edge(s)". Disabled by default: every edge is eligible, unchanged from
    /// before this existed. See `GenerationalEvolutionEngine.eligibleSegments`.
    public var directionalSelector: DirectionalSelector

    /// Optional per-frame animation of the reveal: maps playback time to a
    /// continuous position in [0, generationCount] via the standard DoubleDriver
    /// machinery (unlike the operator randomness above, this genuinely is playback
    /// time, so DoubleDriver is the right tool here). When `enabled` is false
    /// (the default), the full `generationCount` is always applied statically —
    /// existing behavior is unchanged. When enabled, the integer part of the
    /// evaluated value is how many generations are fully applied; the fractional
    /// part scales the in-progress generation's extrude/split magnitude from 0 to
    /// its full sampled distance, tweening that generation's mutation into view
    /// rather than having it pop in. See GenerationalEvolutionEngine.
    public var generationPhase: DoubleDriver

    /// When true and `generationPhase` is enabled, each full cycle of the reveal
    /// (each time it returns to generation 0 and climbs again) uses a different
    /// effective seed — derived from `generationSeed` combined with a cycle index,
    /// not `generationSeed` itself, which is left untouched. Has no effect when
    /// `generationPhase` is disabled (no cycles exist to vary between). See
    /// `GenerationalEvolutionEngine.revealCycleIndex`/`combineSeed`.
    public var varySeedPerCycle: Bool

    public init(
        name:                     String                  = "",
        enabled:                  Bool                    = true,
        operationType:            EvolutionOperationType  = .momentumDrift,
        driftTarget:              DriftTarget             = .lineRatioXY,
        driftMomentum:            Double                  = 0.85,
        driftNoiseStrength:       Double                  = 0.1,
        driftNoiseFrequency:      Double                  = 0.02,
        driftSeed:                Int                     = 0,
        convergenceTargetSetName: String                  = "",
        convergencePressure:      DoubleDriver            = .constant(0.5),
        convergenceMode:          ConvergenceMode         = .hold,
        convergenceDuration:      Double                  = 120.0,
        generationCount:          Int                     = 5,
        extrudeWeight:            Double                  = 1.0,
        splitWeight:              Double                  = 1.0,
        extrudeRunLengthMin:      Int                     = 1,
        extrudeRunLengthMax:      Int                     = 2,
        extrudeDistanceMin:       Double                  = 0.05,
        extrudeDistanceMax:       Double                  = 0.2,
        splitDisplacementMin:     Double                  = 0.05,
        splitDisplacementMax:     Double                  = 0.2,
        generationSeed:           Int                     = 0,
        maxVertexBudget:          Int                     = 512,
        generationPhase:          DoubleDriver            = DoubleDriver(),
        varySeedPerCycle:         Bool                    = false,
        directionalSelector:      DirectionalSelector     = DirectionalSelector()
    ) {
        self.name                     = name
        self.enabled                  = enabled
        self.operationType            = operationType
        self.driftTarget              = driftTarget
        self.driftMomentum            = driftMomentum
        self.driftNoiseStrength       = driftNoiseStrength
        self.driftNoiseFrequency      = driftNoiseFrequency
        self.driftSeed                = driftSeed
        self.convergenceTargetSetName = convergenceTargetSetName
        self.convergencePressure      = convergencePressure
        self.convergenceMode          = convergenceMode
        self.convergenceDuration      = convergenceDuration
        self.generationCount          = generationCount
        self.extrudeWeight            = extrudeWeight
        self.splitWeight              = splitWeight
        self.extrudeRunLengthMin      = extrudeRunLengthMin
        self.extrudeRunLengthMax      = extrudeRunLengthMax
        self.extrudeDistanceMin       = extrudeDistanceMin
        self.extrudeDistanceMax       = extrudeDistanceMax
        self.splitDisplacementMin     = splitDisplacementMin
        self.splitDisplacementMax     = splitDisplacementMax
        self.generationSeed           = generationSeed
        self.maxVertexBudget          = maxVertexBudget
        self.generationPhase          = generationPhase
        self.varySeedPerCycle         = varySeedPerCycle
        self.directionalSelector      = directionalSelector
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case name, enabled, operationType
        case driftTarget, driftMomentum, driftNoiseStrength, driftNoiseFrequency, driftSeed
        case convergenceTargetSetName, convergencePressure, convergenceMode, convergenceDuration
        case generationCount, extrudeWeight, splitWeight
        case extrudeRunLengthMin, extrudeRunLengthMax, extrudeDistanceMin, extrudeDistanceMax
        case splitDisplacementMin, splitDisplacementMax, generationSeed, maxVertexBudget
        case generationPhase, varySeedPerCycle, directionalSelector
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name                     = try c.decodeIfPresent(String.self,                  forKey: .name)                     ?? ""
        enabled                  = try c.decodeIfPresent(Bool.self,                    forKey: .enabled)                  ?? true
        operationType            = try c.decodeIfPresent(EvolutionOperationType.self,  forKey: .operationType)            ?? .momentumDrift
        driftTarget              = try c.decodeIfPresent(DriftTarget.self,             forKey: .driftTarget)              ?? .lineRatioXY
        driftMomentum            = try c.decodeIfPresent(Double.self,                  forKey: .driftMomentum)            ?? 0.85
        driftNoiseStrength       = try c.decodeIfPresent(Double.self,                  forKey: .driftNoiseStrength)       ?? 0.1
        driftNoiseFrequency      = try c.decodeIfPresent(Double.self,                  forKey: .driftNoiseFrequency)      ?? 0.02
        driftSeed                = try c.decodeIfPresent(Int.self,                     forKey: .driftSeed)                ?? 0
        convergenceTargetSetName = try c.decodeIfPresent(String.self,                  forKey: .convergenceTargetSetName) ?? ""
        convergencePressure      = try c.decodeIfPresent(DoubleDriver.self,            forKey: .convergencePressure)      ?? .constant(0.5)
        convergenceMode          = try c.decodeIfPresent(ConvergenceMode.self,         forKey: .convergenceMode)          ?? .hold
        convergenceDuration      = try c.decodeIfPresent(Double.self,                  forKey: .convergenceDuration)      ?? 120.0
        generationCount          = try c.decodeIfPresent(Int.self,                     forKey: .generationCount)          ?? 5
        extrudeWeight            = try c.decodeIfPresent(Double.self,                  forKey: .extrudeWeight)            ?? 1.0
        splitWeight              = try c.decodeIfPresent(Double.self,                  forKey: .splitWeight)              ?? 1.0
        extrudeRunLengthMin      = try c.decodeIfPresent(Int.self,                     forKey: .extrudeRunLengthMin)      ?? 1
        extrudeRunLengthMax      = try c.decodeIfPresent(Int.self,                     forKey: .extrudeRunLengthMax)      ?? 2
        extrudeDistanceMin       = try c.decodeIfPresent(Double.self,                  forKey: .extrudeDistanceMin)       ?? 0.05
        extrudeDistanceMax       = try c.decodeIfPresent(Double.self,                  forKey: .extrudeDistanceMax)       ?? 0.2
        splitDisplacementMin     = try c.decodeIfPresent(Double.self,                  forKey: .splitDisplacementMin)     ?? 0.05
        splitDisplacementMax     = try c.decodeIfPresent(Double.self,                  forKey: .splitDisplacementMax)     ?? 0.2
        generationSeed           = try c.decodeIfPresent(Int.self,                     forKey: .generationSeed)           ?? 0
        maxVertexBudget          = try c.decodeIfPresent(Int.self,                     forKey: .maxVertexBudget)          ?? 512
        generationPhase          = try c.decodeIfPresent(DoubleDriver.self,            forKey: .generationPhase)          ?? DoubleDriver()
        varySeedPerCycle         = try c.decodeIfPresent(Bool.self,                    forKey: .varySeedPerCycle)         ?? false
        directionalSelector      = try c.decodeIfPresent(DirectionalSelector.self,     forKey: .directionalSelector)      ?? DirectionalSelector()
    }
}

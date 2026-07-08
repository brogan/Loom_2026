import Foundation

public enum EntropyTarget: String, Codable, CaseIterable, Equatable, Sendable {
    case centroid = "centroid"
    case smoothed = "smoothed"
    case circle   = "circle"
}

public enum CollapseMode: String, Codable, CaseIterable, Equatable, Sendable {
    case instant = "instant"
    case brief   = "brief"
}

public enum CollapseTriggerType: String, Codable, CaseIterable, Equatable, Sendable {
    case frameCount  = "frameCount"
    case probability = "probability"
}

public enum CollapseEndMode: String, Codable, CaseIterable, Equatable, Sendable {
    case remove  = "remove"
    case loop    = "loop"
    case respawn = "respawn"
}

/// Where the simple uniform shrink used by non-spline entropy and collapse's
/// Brief mode scales toward. `.centroid` (default) keeps the shrink symmetric —
/// existing behavior. `.edge`/`.vertex` pick one edge midpoint / vertex per
/// polygon, chosen deterministically (seeded by `dissolutionSeed`, stable across
/// frames — a polygon always contracts toward the same point, it doesn't jump
/// around), so the shape visibly pulls to one side as it shrinks instead of
/// collapsing in place. Does not affect `.spline` entropy, which already has its
/// own richer per-anchor `entropyTarget` (centroid/smoothed/circle).
public enum ContractionAnchor: String, Codable, CaseIterable, Equatable, Sendable {
    case centroid = "centroid"
    case edge     = "edge"
    case vertex   = "vertex"
}

public struct DissolutionParams: Equatable, Codable, Sendable {

    public var name:    String = ""
    public var enabled: Bool   = true

    // Entropy
    public var entropyEnabled: Bool          = false
    public var entropyRate:    Double        = 0.005
    public var entropyTarget:  EntropyTarget = .smoothed
    public var entropyNoise:   Double        = 0.0
    public var entropySeed:    Int           = 0

    // Collapse
    public var collapseEnabled:            Bool                = false
    public var collapseMode:               CollapseMode        = .instant
    public var collapseBriefDuration:      Int                 = 6
    public var collapseTriggerType:        CollapseTriggerType = .frameCount
    public var collapseTriggerFrameCount:  Int                 = 120
    public var collapseTriggerProbability: Double              = 0.01
    public var collapseEndMode:            CollapseEndMode     = .loop

    // Two-track driver system (mirrors Evolution/GenerationalEvolutionEngine — see
    // Specs/GeometricLifecycle.md §4.5). `dissolutionPhase` is the "how much" track:
    // an optional per-frame animation of overall dissolution progress in [0, 1].
    // When its driver is disabled (default), Partial Loss and Drift below are
    // always applied at full strength — their own *Enabled flags gate them, not
    // phase — matching `generationPhase`'s default of "static, fully applied" when
    // its driver is off. `dissolutionSeed`/`varySeedPerCycle` are the "which" track:
    // seed all deterministic structural choices below (contraction anchor point,
    // which polygons are lost, per-polygon drift direction), optionally varying
    // per reveal cycle exactly like `generationSeed` does.
    public var dissolutionPhase: DoubleDriver = DoubleDriver()
    public var dissolutionSeed:  Int          = 0
    public var varySeedPerCycle: Bool         = false

    // Contraction anchor — see `ContractionAnchor` above.
    public var contractionAnchor: ContractionAnchor = .centroid

    // Partial loss — prunes a fraction of polygons from a subdivided set (rather
    // than the all-or-nothing vanish of Collapse). Fraction pruned = dissolutionPhase's
    // progress (or 1.0 if its driver is disabled) × partialLossMaxFraction, chosen
    // deterministically per polygon index. No-op when there's only one polygon —
    // pruning "a fraction of one shape" isn't meaningful; use Collapse for that.
    public var partialLossEnabled:     Bool   = false
    public var partialLossMaxFraction: Double = 0.3

    // Drift — per-polygon translation/rotation. Direction and rotation are chosen
    // deterministically per polygon index (stable across frames — each polygon
    // drifts one consistent way, it doesn't wander), magnitude scaled by
    // dissolutionPhase's progress (or full distance/rotation if its driver is off).
    public var driftEnabled:  Bool   = false
    public var driftDistance: Double = 0.05   // max per-polygon translation, canvas-normalized units
    public var driftRotation: Double = 0.0    // max per-polygon rotation, radians

    public init(name: String = "") {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case name, enabled
        case entropyEnabled, entropyRate, entropyTarget, entropyNoise, entropySeed
        case collapseEnabled, collapseMode, collapseBriefDuration
        case collapseTriggerType, collapseTriggerFrameCount, collapseTriggerProbability
        case collapseEndMode
        case dissolutionPhase, dissolutionSeed, varySeedPerCycle, contractionAnchor
        case partialLossEnabled, partialLossMaxFraction
        case driftEnabled, driftDistance, driftRotation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name    = (try? c.decodeIfPresent(String.self,  forKey: .name))    ?? ""
        enabled = (try? c.decodeIfPresent(Bool.self,    forKey: .enabled)) ?? true

        entropyEnabled = (try? c.decodeIfPresent(Bool.self,          forKey: .entropyEnabled)) ?? false
        entropyRate    = (try? c.decodeIfPresent(Double.self,         forKey: .entropyRate))    ?? 0.005
        entropyTarget  = (try? c.decodeIfPresent(EntropyTarget.self,  forKey: .entropyTarget))  ?? .smoothed
        entropyNoise   = (try? c.decodeIfPresent(Double.self,         forKey: .entropyNoise))   ?? 0.0
        entropySeed    = (try? c.decodeIfPresent(Int.self,            forKey: .entropySeed))    ?? 0

        collapseEnabled            = (try? c.decodeIfPresent(Bool.self,                 forKey: .collapseEnabled))            ?? false
        collapseMode               = (try? c.decodeIfPresent(CollapseMode.self,         forKey: .collapseMode))               ?? .instant
        collapseBriefDuration      = (try? c.decodeIfPresent(Int.self,                  forKey: .collapseBriefDuration))      ?? 6
        collapseTriggerType        = (try? c.decodeIfPresent(CollapseTriggerType.self,  forKey: .collapseTriggerType))        ?? .frameCount
        collapseTriggerFrameCount  = (try? c.decodeIfPresent(Int.self,                  forKey: .collapseTriggerFrameCount))  ?? 120
        collapseTriggerProbability = (try? c.decodeIfPresent(Double.self,               forKey: .collapseTriggerProbability)) ?? 0.01
        collapseEndMode            = (try? c.decodeIfPresent(CollapseEndMode.self,      forKey: .collapseEndMode))            ?? .loop

        dissolutionPhase    = (try? c.decodeIfPresent(DoubleDriver.self,       forKey: .dissolutionPhase))    ?? DoubleDriver()
        dissolutionSeed     = (try? c.decodeIfPresent(Int.self,                forKey: .dissolutionSeed))     ?? 0
        varySeedPerCycle    = (try? c.decodeIfPresent(Bool.self,               forKey: .varySeedPerCycle))    ?? false
        contractionAnchor   = (try? c.decodeIfPresent(ContractionAnchor.self,  forKey: .contractionAnchor))   ?? .centroid
        partialLossEnabled     = (try? c.decodeIfPresent(Bool.self,   forKey: .partialLossEnabled))     ?? false
        partialLossMaxFraction = (try? c.decodeIfPresent(Double.self, forKey: .partialLossMaxFraction)) ?? 0.3
        driftEnabled  = (try? c.decodeIfPresent(Bool.self,   forKey: .driftEnabled))  ?? false
        driftDistance = (try? c.decodeIfPresent(Double.self, forKey: .driftDistance)) ?? 0.05
        driftRotation = (try? c.decodeIfPresent(Double.self, forKey: .driftRotation)) ?? 0.0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name,    forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(entropyEnabled, forKey: .entropyEnabled)
        try c.encode(entropyRate,    forKey: .entropyRate)
        try c.encode(entropyTarget,  forKey: .entropyTarget)
        try c.encode(entropyNoise,   forKey: .entropyNoise)
        try c.encode(entropySeed,    forKey: .entropySeed)
        try c.encode(collapseEnabled,            forKey: .collapseEnabled)
        try c.encode(collapseMode,               forKey: .collapseMode)
        try c.encode(collapseBriefDuration,      forKey: .collapseBriefDuration)
        try c.encode(collapseTriggerType,        forKey: .collapseTriggerType)
        try c.encode(collapseTriggerFrameCount,  forKey: .collapseTriggerFrameCount)
        try c.encode(collapseTriggerProbability, forKey: .collapseTriggerProbability)
        try c.encode(collapseEndMode,            forKey: .collapseEndMode)
        try c.encode(dissolutionPhase,  forKey: .dissolutionPhase)
        try c.encode(dissolutionSeed,   forKey: .dissolutionSeed)
        try c.encode(varySeedPerCycle,  forKey: .varySeedPerCycle)
        try c.encode(contractionAnchor, forKey: .contractionAnchor)
        try c.encode(partialLossEnabled,     forKey: .partialLossEnabled)
        try c.encode(partialLossMaxFraction, forKey: .partialLossMaxFraction)
        try c.encode(driftEnabled,  forKey: .driftEnabled)
        try c.encode(driftDistance, forKey: .driftDistance)
        try c.encode(driftRotation, forKey: .driftRotation)
    }
}

import Foundation

public enum ExtensionOperationType: String, Codable, CaseIterable, Equatable, Sendable {
    case branch  = "Branch"
    case extrude = "Extrude"
}

/// Which anchor points on the open curve a `.branch` pass may spawn from
/// (Specs/GeometricLifecycle.md Phase 4, 2026-07-12 update).
public enum BranchAnchorScope: String, Codable, CaseIterable, Equatable, Sendable {
    /// Original behavior: only the curve's two endpoints.
    case endpointsOnly = "Endpoints Only"
    /// Every anchor point along the curve (every 4th point, `0...segCount`).
    case anyAnchor     = "Any Anchor"
}

/// What grows at each branch origin.
public enum BranchGeometry: String, Codable, CaseIterable, Equatable, Sendable {
    /// Original behavior: a scaled/rotated copy of the entire root curve.
    case rootCopy = "Root Copy"
    /// A single straight (or bowed) line segment — not a copy of root.
    case line     = "Line"
}

public enum ExtrusionTarget: String, Codable, CaseIterable, Equatable, Sendable {
    case allEdges    = "All Edges"
    case longestEdge = "Longest Edge"
}

public struct ExtensionParams: Equatable, Codable, Sendable {
    public var name:          String
    public var enabled:       Bool
    public var operationType: ExtensionOperationType

    // Branch settings (operationType == .branch)
    public var branchAngle:       DoubleDriver  // degrees from endpoint tangent
    public var branchAngleJitter: Double        // max random perturbation, degrees
    public var branchScaleRatio:  Double        // scale factor per depth level
    public var branchDepth:       Int           // recursion depth (engine caps at 8)
    public var branchCount:       Int           // branches per endpoint
    public var branchProbability: Double        // 0.0–1.0 spawn probability
    public var branchSeed:        Int           // deterministic seed
    public var branchAnchorScope: BranchAnchorScope  // where branches may originate
    public var branchGeometry:    BranchGeometry     // what grows at each origin

    /// Base length (canvas-normalized units) of a `.line`-geometry branch at
    /// depth 0, before `branchScaleRatio`'s per-depth decay. A `DoubleDriver`
    /// (not a plain `Double`) so the extension can be driven to unfold
    /// gradually over time — e.g. a ramp/oscillator grows the line from 0 to
    /// full length rather than popping in at a fixed size every frame, the
    /// same animated-parameter convention `branchAngle`/`extrusionDistance`
    /// already use. Ignored when `branchGeometry == .rootCopy`.
    public var branchLineLength:  DoubleDriver

    /// RPSR bow range (fraction of the line's own length, same
    /// `bow = amount * length` convention as `extrusionCurvature`/Graft's
    /// `graftEdgeCurvatureAmountMin/Max`) applied to a `.line`-geometry
    /// branch. 0–0 (default) = straight. Min == Max = a fixed bow amount;
    /// Min ≠ Max = randomized per branch off the same deterministic seed as
    /// jitter/probability. Ignored when `branchGeometry == .rootCopy`.
    public var branchCurvatureAmountMin: Double
    public var branchCurvatureAmountMax: Double

    // Extrusion settings (operationType == .extrude)
    public var extrusionDistance:    DoubleDriver
    public var extrusionWidth:       Double      // 1.0 = parallel, <1 = taper, >1 = flare
    public var extrusionCurvature:   Double      // bow on outer edge (fraction of edge length)
    public var extrusionTarget:      ExtrusionTarget

    /// RPSR range (per edge, independently rolled) of recursive outer-face
    /// extrusion levels — "towers" of varying height rather than one uniform
    /// count applied to every edge. Min == Max reproduces a fixed count (the
    /// original single-`Int` behavior, still the default: 1–1). Engine clamps
    /// the rolled value to 1–6 regardless of the configured range, same as the
    /// old field always did.
    public var extrusionGenerationsMin: Int
    public var extrusionGenerationsMax: Int

    /// Opt-in: also extrude `.openSpline` (open curve) segments, not just
    /// closed `.spline` polygons (2026-07-12). Off by default — existing
    /// projects extrude exactly the closed-polygon set they always did.
    /// `extrudeSegment`'s geometry (duplicate the edge's own curvature at an
    /// offset, wall-connect the endpoints) is already type-agnostic; enabling
    /// this on an open curve produces a new closed quad bridging two of the
    /// curve's own anchor points, the source curve left untouched — the
    /// natural open-curve complement to closed-polygon Extrude, not a
    /// different mechanism.
    public var extrudeOpenCurves: Bool

    /// RPSR angle range (degrees, per edge, independently rolled), rotating
    /// the extrusion direction away from the plain perpendicular outward
    /// normal. 0–0 (default) = straight outward, original behavior unchanged.
    /// Most useful for `extrudeOpenCurves`, where "outward" has no enclosed
    /// interior to be relative to — just one arbitrary consistent side — so an
    /// explicit offset gives real control over departure direction, the same
    /// idea as Graft's `graftDepartureAngleMin/Max`. Resolved once per edge and
    /// reused across that edge's own generations, same as the base normal
    /// already is.
    public var extrusionDepartureAngleMin: Double
    public var extrusionDepartureAngleMax: Double

    /// Deterministic seed for the per-edge generation-count and
    /// departure-angle rolls above. Change to get a different tower-height/
    /// departure-angle arrangement without altering other settings.
    public var extrusionSeed: Int

    /// Further restricts extrusionTarget's candidate edges by outward-normal
    /// direction (Specs/GeometricLifecycle.md §14) — e.g. "only the edge(s) facing
    /// up" on top of ".allEdges". Disabled by default (every candidate from
    /// extrusionTarget is eligible, unchanged from before this existed).
    public var directionalSelector: DirectionalSelector

    /// Reveals *structural* complexity gradually — Branch's depth levels, or
    /// Extrude's per-edge generation count — rather than popping in fully the
    /// moment the pass is enabled (2026-07-12). Disabled by default: falls back
    /// to the static `branchDepth`/`extrusionGenerationsMin/Max` behavior,
    /// unchanged from before this existed. Mirrors `GenerationalEvolutionEngine`
    /// `EvolutionParams.generationPhase`'s exact shape — an integer count of
    /// fully-revealed levels plus a fractional "currently growing" one, that
    /// partial level scaled from 0 to full size — reusing the same
    /// scale-by-strength trick already used for reveal there (and by
    /// Generational Evolution's own Extrude operator, which already scales its
    /// distance by `strength`) rather than a separate post-hoc anchor-relative
    /// tween: multiplying the effective scale/length/distance directly by the
    /// partial level's strength already grows it from the same anchor point the
    /// full-strength construction would use, with no extra geometry math
    /// needed. Branch clamps to `[0, branchDepth]`; Extrude clamps to `[0, 6]`
    /// (the hard generation cap) and then, per edge, to that edge's own rolled
    /// `extrusionGenerationsMin/Max` count — edges that rolled a shorter tower
    /// finish revealing sooner than edges that rolled a taller one.
    public var structurePhase: DoubleDriver

    public init(
        name:                String              = "",
        enabled:             Bool                = true,
        operationType:       ExtensionOperationType = .branch,
        branchAngle:         DoubleDriver        = .constant(45.0),
        branchAngleJitter:   Double              = 0.0,
        branchScaleRatio:    Double              = 0.6,
        branchDepth:         Int                 = 2,
        branchCount:         Int                 = 2,
        branchProbability:   Double              = 1.0,
        branchSeed:          Int                 = 0,
        branchAnchorScope:   BranchAnchorScope   = .endpointsOnly,
        branchGeometry:      BranchGeometry      = .rootCopy,
        branchLineLength:    DoubleDriver        = .constant(0.2),
        branchCurvatureAmountMin: Double         = 0.0,
        branchCurvatureAmountMax: Double         = 0.0,
        extrusionDistance:   DoubleDriver        = .constant(0.1),
        extrusionWidth:      Double              = 1.0,
        extrusionCurvature:  Double              = 0.0,
        extrusionGenerationsMin: Int             = 1,
        extrusionGenerationsMax: Int             = 1,
        extrudeOpenCurves:   Bool                = false,
        extrusionDepartureAngleMin: Double        = 0.0,
        extrusionDepartureAngleMax: Double        = 0.0,
        extrusionSeed:       Int                 = 0,
        extrusionTarget:     ExtrusionTarget     = .allEdges,
        directionalSelector: DirectionalSelector = DirectionalSelector(),
        structurePhase:      DoubleDriver        = DoubleDriver()
    ) {
        self.name                = name
        self.enabled             = enabled
        self.operationType       = operationType
        self.branchAngle         = branchAngle
        self.branchAngleJitter   = branchAngleJitter
        self.branchScaleRatio    = branchScaleRatio
        self.branchDepth         = branchDepth
        self.branchCount         = branchCount
        self.branchProbability   = branchProbability
        self.branchSeed          = branchSeed
        self.branchAnchorScope   = branchAnchorScope
        self.branchGeometry      = branchGeometry
        self.branchLineLength    = branchLineLength
        self.branchCurvatureAmountMin = branchCurvatureAmountMin
        self.branchCurvatureAmountMax = branchCurvatureAmountMax
        self.extrusionDistance   = extrusionDistance
        self.extrusionWidth      = extrusionWidth
        self.extrusionCurvature  = extrusionCurvature
        self.extrusionGenerationsMin = extrusionGenerationsMin
        self.extrusionGenerationsMax = extrusionGenerationsMax
        self.extrudeOpenCurves   = extrudeOpenCurves
        self.extrusionDepartureAngleMin = extrusionDepartureAngleMin
        self.extrusionDepartureAngleMax = extrusionDepartureAngleMax
        self.extrusionSeed       = extrusionSeed
        self.extrusionTarget     = extrusionTarget
        self.directionalSelector = directionalSelector
        self.structurePhase      = structurePhase
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case name, enabled, operationType
        case branchAngle, branchAngleJitter, branchScaleRatio
        case branchDepth, branchCount, branchProbability, branchSeed
        case branchAnchorScope, branchGeometry, branchLineLength
        case branchCurvatureAmountMin, branchCurvatureAmountMax
        case extrusionDistance, extrusionWidth, extrusionCurvature
        case extrusionTarget, directionalSelector
        case extrusionGenerationsMin, extrusionGenerationsMax
        /// Legacy key from before the Min/Max range existed (2026-07-12) — still
        /// decoded so existing saved projects' single generation count seeds both
        /// new fields identically; no longer written on encode.
        case extrusionGenerations
        case extrudeOpenCurves, extrusionDepartureAngleMin, extrusionDepartureAngleMax, extrusionSeed
        case structurePhase
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name               = try c.decodeIfPresent(String.self,                 forKey: .name)               ?? ""
        enabled            = try c.decodeIfPresent(Bool.self,                   forKey: .enabled)            ?? true
        operationType      = try c.decodeIfPresent(ExtensionOperationType.self, forKey: .operationType)      ?? .branch
        branchAngle        = try c.decodeIfPresent(DoubleDriver.self,           forKey: .branchAngle)        ?? .constant(45.0)
        branchAngleJitter  = try c.decodeIfPresent(Double.self,                 forKey: .branchAngleJitter)  ?? 0.0
        branchScaleRatio   = try c.decodeIfPresent(Double.self,                 forKey: .branchScaleRatio)   ?? 0.6
        branchDepth        = try c.decodeIfPresent(Int.self,                    forKey: .branchDepth)        ?? 2
        branchCount        = try c.decodeIfPresent(Int.self,                    forKey: .branchCount)        ?? 2
        branchProbability  = try c.decodeIfPresent(Double.self,                 forKey: .branchProbability)  ?? 1.0
        branchSeed         = try c.decodeIfPresent(Int.self,                    forKey: .branchSeed)         ?? 0
        branchAnchorScope  = try c.decodeIfPresent(BranchAnchorScope.self,      forKey: .branchAnchorScope)  ?? .endpointsOnly
        branchGeometry     = try c.decodeIfPresent(BranchGeometry.self,         forKey: .branchGeometry)     ?? .rootCopy
        branchLineLength   = try c.decodeIfPresent(DoubleDriver.self,           forKey: .branchLineLength)   ?? .constant(0.2)
        branchCurvatureAmountMin = try c.decodeIfPresent(Double.self, forKey: .branchCurvatureAmountMin) ?? 0.0
        branchCurvatureAmountMax = try c.decodeIfPresent(Double.self, forKey: .branchCurvatureAmountMax) ?? 0.0
        extrusionDistance    = try c.decodeIfPresent(DoubleDriver.self,    forKey: .extrusionDistance)    ?? .constant(0.1)
        extrusionWidth       = try c.decodeIfPresent(Double.self,          forKey: .extrusionWidth)       ?? 1.0
        extrusionCurvature   = try c.decodeIfPresent(Double.self,          forKey: .extrusionCurvature)   ?? 0.0
        // Legacy single-count key, still decoded as the fallback default for both
        // new range fields when they're absent (pre-2026-07-12 saved projects).
        let legacyGenerations = try c.decodeIfPresent(Int.self, forKey: .extrusionGenerations) ?? 1
        extrusionGenerationsMin = try c.decodeIfPresent(Int.self, forKey: .extrusionGenerationsMin) ?? legacyGenerations
        extrusionGenerationsMax = try c.decodeIfPresent(Int.self, forKey: .extrusionGenerationsMax) ?? legacyGenerations
        extrudeOpenCurves    = try c.decodeIfPresent(Bool.self,   forKey: .extrudeOpenCurves)   ?? false
        extrusionDepartureAngleMin = try c.decodeIfPresent(Double.self, forKey: .extrusionDepartureAngleMin) ?? 0.0
        extrusionDepartureAngleMax = try c.decodeIfPresent(Double.self, forKey: .extrusionDepartureAngleMax) ?? 0.0
        extrusionSeed        = try c.decodeIfPresent(Int.self,    forKey: .extrusionSeed)       ?? 0
        extrusionTarget      = try c.decodeIfPresent(ExtrusionTarget.self, forKey: .extrusionTarget)      ?? .allEdges
        directionalSelector  = try c.decodeIfPresent(DirectionalSelector.self, forKey: .directionalSelector) ?? DirectionalSelector()
        structurePhase       = try c.decodeIfPresent(DoubleDriver.self, forKey: .structurePhase) ?? DoubleDriver()
    }

    /// Manual (not synthesized): `CodingKeys` carries the decode-only
    /// `extrusionGenerations` legacy key, which has no matching stored
    /// property, so Swift can't synthesize `Encodable` — this omits it,
    /// writing only the current fields.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(operationType, forKey: .operationType)
        try c.encode(branchAngle, forKey: .branchAngle)
        try c.encode(branchAngleJitter, forKey: .branchAngleJitter)
        try c.encode(branchScaleRatio, forKey: .branchScaleRatio)
        try c.encode(branchDepth, forKey: .branchDepth)
        try c.encode(branchCount, forKey: .branchCount)
        try c.encode(branchProbability, forKey: .branchProbability)
        try c.encode(branchSeed, forKey: .branchSeed)
        try c.encode(branchAnchorScope, forKey: .branchAnchorScope)
        try c.encode(branchGeometry, forKey: .branchGeometry)
        try c.encode(branchLineLength, forKey: .branchLineLength)
        try c.encode(branchCurvatureAmountMin, forKey: .branchCurvatureAmountMin)
        try c.encode(branchCurvatureAmountMax, forKey: .branchCurvatureAmountMax)
        try c.encode(extrusionDistance, forKey: .extrusionDistance)
        try c.encode(extrusionWidth, forKey: .extrusionWidth)
        try c.encode(extrusionCurvature, forKey: .extrusionCurvature)
        try c.encode(extrusionGenerationsMin, forKey: .extrusionGenerationsMin)
        try c.encode(extrusionGenerationsMax, forKey: .extrusionGenerationsMax)
        try c.encode(extrudeOpenCurves, forKey: .extrudeOpenCurves)
        try c.encode(extrusionDepartureAngleMin, forKey: .extrusionDepartureAngleMin)
        try c.encode(extrusionDepartureAngleMax, forKey: .extrusionDepartureAngleMax)
        try c.encode(extrusionSeed, forKey: .extrusionSeed)
        try c.encode(extrusionTarget, forKey: .extrusionTarget)
        try c.encode(directionalSelector, forKey: .directionalSelector)
        try c.encode(structurePhase, forKey: .structurePhase)
    }
}

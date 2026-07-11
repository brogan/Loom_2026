import Foundation

/// How a Fulguration flash behaves within its held/visible window — see
/// Specs/GeometricLifecycle.md §5.5.
public enum FulgurationDevelopmentMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// On for the full hold duration, then off. Simplest possible, zero extra cost.
    case instant    = "instant"
    /// Scale ramps 0→1 over `growInDuration` at the start of the hold window and
    /// 1→0 over `shrinkOutDuration` at the end, around the flash's group centroid —
    /// using `Polygon2D.scaled(by:around:)` directly, the same primitive
    /// Dissolution's Brief collapse already calls.
    case growShrink = "growShrink"
}

/// What a Fulguration flash's content actually is — see Specs/GeometricLifecycle.md
/// §5.12. `.transform` is V1: a rigid transform of the sprite's own resolved geometry.
/// `.assembly` is V3: a combinatorial composite built from `AssemblyPrimitiveKit`
/// pieces, replacing the sprite's geometry for the hold window rather than
/// transforming it.
public enum FulgurationContentMode: String, Codable, CaseIterable, Equatable, Sendable {
    case transform = "transform"
    case assembly  = "assembly"
}

/// Assembly-mode piece placement (§5.12.4): whether an incoming piece keeps its own
/// native scale at the joint (`.preserveSize`, rougher/"found-object") or is rescaled
/// so its attachment site's length matches the target's exactly (`.matchLength`,
/// only meaningful between two polygon-edge sites — a no-op when either site is a
/// curve endpoint, which has no length).
public enum AssemblyEdgeMatching: String, Codable, CaseIterable, Equatable, Sendable {
    case preserveSize = "preserveSize"
    case matchLength  = "matchLength"
}

/// How an Assembly-mode flash disappears (§5.12.6). Fade intentionally excluded —
/// per-shape alpha independent of layer opacity isn't reliable in the current render
/// pipeline.
public enum FulgurationExitMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// Sudden disappearance — the hold window simply ends.
    case instant   = "instant"
    /// The whole composite scales toward its group centroid over `exitDuration`
    /// frames, using `Polygon2D.scaled(by:around:)`.
    case shrink    = "shrink"
    /// The whole composite translates past the canvas bounds over `exitDuration`
    /// frames, then is hidden.
    case offscreen = "offscreen"
    /// Each piece drifts independently over `exitDuration` frames — Dissolution's
    /// Drift math, applied per-piece to the assembly instead of a sprite's resolved
    /// polygons.
    case shatter   = "shatter"
}

/// V1 Fulguration: a self-contained frame-cycle trigger (§5.3), per-cycle rigid
/// transform variation (§5.4), and brief grow-in/shrink-out development (§5.5). No
/// dependency on any other sprite's state — see §5.6–§5.8 for the deferred V2
/// (threshold-relative/proximity triggers, pre-subdivision geometry variation).
public struct FulgurationParams: Equatable, Codable, Sendable {

    public var name:    String = ""
    public var enabled: Bool   = true

    // Frame-cycle trigger (§5.3). Each cycle's interval and hold are independently
    // RPSR-resampled — see FulgurationEngine's cycle-walk for why this can't reuse
    // Collapse's O(1) modular-period shortcut.
    public var intervalMin: Int = 30
    public var intervalMax: Int = 90
    public var holdMin:     Int = 6
    public var holdMax:     Int = 20
    public var cycleSeed:   Int = 0

    // Appearance transform variation (§5.4) — one rigid transform for the whole
    // flash per cycle, not per-polygon (that's Dissolution's Drift).
    public var translationRange: Double = 0.0
    public var scaleMin:         Double = 1.0
    public var scaleMax:         Double = 1.0
    public var rotationRange:    Double = 0.0

    // Development (§5.5) — .transform content mode only.
    public var developmentMode:    FulgurationDevelopmentMode = .instant
    public var growInDuration:     Int = 4
    public var shrinkOutDuration:  Int = 4

    // Content mode (§5.12): .transform is V1 (above); .assembly is V3, below.
    public var contentMode: FulgurationContentMode = .transform

    // Assembly (§5.12) — content mode == .assembly only.
    public var assemblyPieceCountMin: Int = 4
    public var assemblyPieceCountMax: Int = 8
    // Uniform per-piece size multiplier (RPSR-sampled per piece, independent of
    // Deform below), applied to AssemblyPrimitiveKit's fixed ~radius-0.5 base shape
    // before the per-axis deform. Defaults well below 1.0 — the base kit shapes are
    // canvas-scale on their own, which read as "quite large" with no size variation.
    public var assemblySizeMin:       Double = 0.15
    public var assemblySizeMax:       Double = 0.35
    public var assemblyDeformMin:     Double = 0.7
    public var assemblyDeformMax:     Double = 1.3
    public var assemblyEdgeMatching:  AssemblyEdgeMatching = .preserveSize
    public var exitMode:              FulgurationExitMode = .instant
    public var exitDuration:          Int = 10

    // .shatter exit only — per-piece drift, same shape as Dissolution's
    // driftDistance/driftRotation (§6.6–§6.10) but applied to the assembly's own
    // piece list rather than a sprite's resolved polygons.
    public var shatterDistance: Double = 0.3
    public var shatterRotation: Double = 0.5

    public init(name: String = "") {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case name, enabled
        case intervalMin, intervalMax, holdMin, holdMax, cycleSeed
        case translationRange, scaleMin, scaleMax, rotationRange
        case developmentMode, growInDuration, shrinkOutDuration
        case contentMode
        case assemblyPieceCountMin, assemblyPieceCountMax
        case assemblySizeMin, assemblySizeMax
        case assemblyDeformMin, assemblyDeformMax
        case assemblyEdgeMatching, exitMode, exitDuration
        case shatterDistance, shatterRotation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name    = (try? c.decodeIfPresent(String.self, forKey: .name))    ?? ""
        enabled = (try? c.decodeIfPresent(Bool.self,   forKey: .enabled)) ?? true

        intervalMin = (try? c.decodeIfPresent(Int.self, forKey: .intervalMin)) ?? 30
        intervalMax = (try? c.decodeIfPresent(Int.self, forKey: .intervalMax)) ?? 90
        holdMin     = (try? c.decodeIfPresent(Int.self, forKey: .holdMin))     ?? 6
        holdMax     = (try? c.decodeIfPresent(Int.self, forKey: .holdMax))     ?? 20
        cycleSeed   = (try? c.decodeIfPresent(Int.self, forKey: .cycleSeed))   ?? 0

        translationRange = (try? c.decodeIfPresent(Double.self, forKey: .translationRange)) ?? 0.0
        scaleMin         = (try? c.decodeIfPresent(Double.self, forKey: .scaleMin))         ?? 1.0
        scaleMax         = (try? c.decodeIfPresent(Double.self, forKey: .scaleMax))         ?? 1.0
        rotationRange    = (try? c.decodeIfPresent(Double.self, forKey: .rotationRange))    ?? 0.0

        developmentMode   = (try? c.decodeIfPresent(FulgurationDevelopmentMode.self, forKey: .developmentMode)) ?? .instant
        growInDuration    = (try? c.decodeIfPresent(Int.self, forKey: .growInDuration))    ?? 4
        shrinkOutDuration = (try? c.decodeIfPresent(Int.self, forKey: .shrinkOutDuration)) ?? 4

        contentMode = (try? c.decodeIfPresent(FulgurationContentMode.self, forKey: .contentMode)) ?? .transform

        assemblyPieceCountMin = (try? c.decodeIfPresent(Int.self, forKey: .assemblyPieceCountMin)) ?? 4
        assemblyPieceCountMax = (try? c.decodeIfPresent(Int.self, forKey: .assemblyPieceCountMax)) ?? 8
        assemblySizeMin       = (try? c.decodeIfPresent(Double.self, forKey: .assemblySizeMin))    ?? 0.15
        assemblySizeMax       = (try? c.decodeIfPresent(Double.self, forKey: .assemblySizeMax))    ?? 0.35
        assemblyDeformMin     = (try? c.decodeIfPresent(Double.self, forKey: .assemblyDeformMin))  ?? 0.7
        assemblyDeformMax     = (try? c.decodeIfPresent(Double.self, forKey: .assemblyDeformMax))  ?? 1.3
        assemblyEdgeMatching  = (try? c.decodeIfPresent(AssemblyEdgeMatching.self, forKey: .assemblyEdgeMatching)) ?? .preserveSize
        exitMode              = (try? c.decodeIfPresent(FulgurationExitMode.self, forKey: .exitMode)) ?? .instant
        exitDuration           = (try? c.decodeIfPresent(Int.self, forKey: .exitDuration)) ?? 10

        shatterDistance = (try? c.decodeIfPresent(Double.self, forKey: .shatterDistance)) ?? 0.3
        shatterRotation = (try? c.decodeIfPresent(Double.self, forKey: .shatterRotation)) ?? 0.5
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name,    forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(intervalMin, forKey: .intervalMin)
        try c.encode(intervalMax, forKey: .intervalMax)
        try c.encode(holdMin,     forKey: .holdMin)
        try c.encode(holdMax,     forKey: .holdMax)
        try c.encode(cycleSeed,   forKey: .cycleSeed)
        try c.encode(translationRange, forKey: .translationRange)
        try c.encode(scaleMin,         forKey: .scaleMin)
        try c.encode(scaleMax,         forKey: .scaleMax)
        try c.encode(rotationRange,    forKey: .rotationRange)
        try c.encode(developmentMode,    forKey: .developmentMode)
        try c.encode(growInDuration,     forKey: .growInDuration)
        try c.encode(shrinkOutDuration,  forKey: .shrinkOutDuration)
        try c.encode(contentMode, forKey: .contentMode)
        try c.encode(assemblyPieceCountMin, forKey: .assemblyPieceCountMin)
        try c.encode(assemblyPieceCountMax, forKey: .assemblyPieceCountMax)
        try c.encode(assemblySizeMin,       forKey: .assemblySizeMin)
        try c.encode(assemblySizeMax,       forKey: .assemblySizeMax)
        try c.encode(assemblyDeformMin,     forKey: .assemblyDeformMin)
        try c.encode(assemblyDeformMax,     forKey: .assemblyDeformMax)
        try c.encode(assemblyEdgeMatching,  forKey: .assemblyEdgeMatching)
        try c.encode(exitMode,     forKey: .exitMode)
        try c.encode(exitDuration, forKey: .exitDuration)
        try c.encode(shatterDistance, forKey: .shatterDistance)
        try c.encode(shatterRotation, forKey: .shatterRotation)
    }
}

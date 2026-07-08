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

    // Development (§5.5)
    public var developmentMode:    FulgurationDevelopmentMode = .instant
    public var growInDuration:     Int = 4
    public var shrinkOutDuration:  Int = 4

    public init(name: String = "") {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case name, enabled
        case intervalMin, intervalMax, holdMin, holdMax, cycleSeed
        case translationRange, scaleMin, scaleMax, rotationRange
        case developmentMode, growInDuration, shrinkOutDuration
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
    }
}

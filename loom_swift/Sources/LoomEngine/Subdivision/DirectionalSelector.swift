import Foundation

/// Which vector a `DirectionalSelector` tests a candidate edge/point against.
public enum DirectionalBasis: String, Codable, CaseIterable, Equatable, Sendable {
    /// A closed-polygon edge's outward normal (edge direction rotated 90°).
    case outwardNormal = "Outward Normal"
    /// An open curve's tangent (direction of travel) at a point.
    case tangent        = "Tangent"
}

/// Filters candidate edges/vertices/points by *direction* rather than position or
/// index — e.g. "only edges whose outward normal points within 20° of straight up"
/// selects whichever edge(s) of *any* polygon shape genuinely face that way, unlike
/// picking a specific edge index, which only works by coincidence for one known
/// shape. Shared across whichever modes need edge/vertex targeting (Extension,
/// Generational Evolution to start — see Specs/GeometricLifecycle.md §14), the same
/// way `DoubleDriver` and the two-track seed/phase pattern are shared primitives
/// rather than being reinvented per mode.
///
/// Disabled by default (`enabled = false`), in which case `accepts(_:)` always
/// returns `true` — every mode that adopts this keeps its existing unfiltered
/// behavior unless a user explicitly turns it on.
public struct DirectionalSelector: Equatable, Codable, Sendable {
    public var enabled:     Bool
    /// Target direction, radians, atan2 convention (`Vector2D.angle`): `0` = +x
    /// (east), `.pi / 2` = +y (up, since this engine's coordinate system is Y-up).
    public var targetAngle: Double
    /// Half-width of the acceptance cone, radians. E.g. `0.35` (~20°) accepts
    /// directions within ±20° of `targetAngle`.
    public var tolerance:   Double
    public var basis:       DirectionalBasis

    public init(
        enabled:     Bool              = false,
        targetAngle: Double            = .pi / 2,
        tolerance:   Double            = 0.35,
        basis:       DirectionalBasis  = .outwardNormal
    ) {
        self.enabled     = enabled
        self.targetAngle = targetAngle
        self.tolerance   = tolerance
        self.basis       = basis
    }

    /// True if `direction`'s angle falls within the acceptance cone around
    /// `targetAngle` — always true when `enabled` is false, or when `direction`
    /// has ~zero length (a degenerate edge has no direction to test, so it's not
    /// excluded by a directional filter; whatever produced it is responsible for
    /// its own degenerate-input handling).
    public func accepts(_ direction: Vector2D) -> Bool {
        guard enabled else { return true }
        let d = direction.normalized()
        guard d.length > 1e-9 else { return true }
        return abs(Self.angleDifference(d.angle, targetAngle)) <= tolerance
    }

    /// Signed difference `a - b`, wrapped to `(-π, π]`.
    private static func angleDifference(_ a: Double, _ b: Double) -> Double {
        var diff = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if diff > .pi  { diff -= 2 * .pi }
        if diff < -.pi { diff += 2 * .pi }
        return diff
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, targetAngle, tolerance, basis
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled     = (try? c.decodeIfPresent(Bool.self,             forKey: .enabled))     ?? false
        targetAngle = (try? c.decodeIfPresent(Double.self,           forKey: .targetAngle)) ?? .pi / 2
        tolerance   = (try? c.decodeIfPresent(Double.self,           forKey: .tolerance))   ?? 0.35
        basis       = (try? c.decodeIfPresent(DirectionalBasis.self, forKey: .basis))       ?? .outwardNormal
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled,     forKey: .enabled)
        try c.encode(targetAngle, forKey: .targetAngle)
        try c.encode(tolerance,   forKey: .tolerance)
        try c.encode(basis,       forKey: .basis)
    }
}

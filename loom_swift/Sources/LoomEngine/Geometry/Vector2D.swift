import Foundation

/// A 2D point or vector in world space.
/// Coordinate convention: origin at canvas centre, Y-up (mathematical).
public struct Vector2D: Equatable, Hashable, Codable, Sendable {

    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vector2D(x: 0, y: 0)

    // MARK: - Transforms (return new values)

    public func translated(by v: Vector2D) -> Vector2D {
        Vector2D(x: x + v.x, y: y + v.y)
    }

    /// Per-axis scale around the origin.
    public func scaled(by v: Vector2D) -> Vector2D {
        Vector2D(x: x * v.x, y: y * v.y)
    }

    /// Uniform scale around the origin.
    public func scaled(by factor: Double) -> Vector2D {
        Vector2D(x: x * factor, y: y * factor)
    }

    /// Rotation around the origin by angle in radians (counter-clockwise).
    public func rotated(by angle: Double) -> Vector2D {
        let c = cos(angle)
        let s = sin(angle)
        return Vector2D(x: x * c - y * s, y: x * s + y * c)
    }

    /// Rotation around an arbitrary centre point.
    public func rotated(by angle: Double, around centre: Vector2D) -> Vector2D {
        translated(by: Vector2D(x: -centre.x, y: -centre.y))
            .rotated(by: angle)
            .translated(by: centre)
    }

    // MARK: - Interpolation

    public static func lerp(_ a: Vector2D, _ b: Vector2D, t: Double) -> Vector2D {
        Vector2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    // MARK: - Geometry

    public var length: Double { sqrt(x * x + y * y) }

    public func distance(to other: Vector2D) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Operators

    public static func + (lhs: Vector2D, rhs: Vector2D) -> Vector2D {
        Vector2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Vector2D, rhs: Vector2D) -> Vector2D {
        Vector2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: Vector2D, rhs: Double) -> Vector2D {
        lhs.scaled(by: rhs)
    }

    public static func * (lhs: Double, rhs: Vector2D) -> Vector2D {
        rhs.scaled(by: lhs)
    }

    public static prefix func - (v: Vector2D) -> Vector2D {
        Vector2D(x: -v.x, y: -v.y)
    }
}

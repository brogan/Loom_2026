import Foundation

/// A 3D point or vector in world space.
public struct Vector3D: Equatable, Hashable, Codable, Sendable {

    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3D(x: 0, y: 0, z: 0)

    // MARK: - Transforms

    public func translated(by v: Vector3D) -> Vector3D {
        Vector3D(x: x + v.x, y: y + v.y, z: z + v.z)
    }

    public func scaled(by v: Vector3D) -> Vector3D {
        Vector3D(x: x * v.x, y: y * v.y, z: z * v.z)
    }

    public func scaled(by factor: Double) -> Vector3D {
        Vector3D(x: x * factor, y: y * factor, z: z * factor)
    }

    /// Rotation around the X axis (pitch).
    public func rotatedX(by angle: Double) -> Vector3D {
        let c = cos(angle), s = sin(angle)
        return Vector3D(x: x, y: y * c - z * s, z: y * s + z * c)
    }

    /// Rotation around the Y axis (yaw).
    public func rotatedY(by angle: Double) -> Vector3D {
        let c = cos(angle), s = sin(angle)
        return Vector3D(x: x * c + z * s, y: y, z: -x * s + z * c)
    }

    /// Rotation around the Z axis (roll).
    public func rotatedZ(by angle: Double) -> Vector3D {
        let c = cos(angle), s = sin(angle)
        return Vector3D(x: x * c - y * s, y: x * s + y * c, z: z)
    }

    // MARK: - Geometry

    public var length: Double { sqrt(x * x + y * y + z * z) }

    public func distance(to other: Vector3D) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        let dz = z - other.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    // MARK: - Operators

    public static func + (lhs: Vector3D, rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3D, rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static func * (lhs: Vector3D, rhs: Double) -> Vector3D {
        lhs.scaled(by: rhs)
    }

    public static prefix func - (v: Vector3D) -> Vector3D {
        Vector3D(x: -v.x, y: -v.y, z: -v.z)
    }
}

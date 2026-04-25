import Foundation

/// A 2D polygon in world space.
///
/// All transform methods return a new Polygon2D; the original is not modified.
///
/// Spline point encoding (type == .spline or .openSpline):
///   Points are stored in groups of 4 per Bézier segment:
///   [anchor_i, controlOut_i, controlIn_{i+1}, anchor_{i+1}]
///   points.count is always a multiple of 4.
public struct Polygon2D: Equatable, Codable, Sendable {

    public var points: [Vector2D]
    public var type: PolygonType

    /// Per-anchor pressure values (0.0–1.0). Used by brush/stencil stamping.
    /// Indexed by anchor position (one value per curve segment).
    /// Empty when pressure data is unavailable — treated as 1.0 throughout.
    public var pressures: [Double]

    public var visible: Bool

    public init(
        points: [Vector2D],
        type: PolygonType,
        pressures: [Double] = [],
        visible: Bool = true
    ) {
        self.points = points
        self.type = type
        self.pressures = pressures
        self.visible = visible
    }

    // MARK: - Computed properties

    public var pointCount: Int { points.count }

    /// Average of all points. Used as a rotation/scale centre in transform plugins.
    public var centroid: Vector2D {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(Vector2D.zero) { $0 + $1 }
        return sum.scaled(by: 1.0 / Double(points.count))
    }

    /// Convenience forwarding isBypassType from PolygonType.
    public var isBypassType: Bool { type.isBypassType }

    // MARK: - Transforms

    public func translated(by v: Vector2D) -> Polygon2D {
        Polygon2D(
            points: points.map { $0.translated(by: v) },
            type: type,
            pressures: pressures,
            visible: visible
        )
    }

    /// Per-axis scale around a centre point (default: world origin).
    public func scaled(by v: Vector2D, around centre: Vector2D = .zero) -> Polygon2D {
        Polygon2D(
            points: points.map { p in
                Vector2D(
                    x: (p.x - centre.x) * v.x + centre.x,
                    y: (p.y - centre.y) * v.y + centre.y
                )
            },
            type: type,
            pressures: pressures,
            visible: visible
        )
    }

    /// Uniform scale around a centre point (default: world origin).
    public func scaled(by factor: Double, around centre: Vector2D = .zero) -> Polygon2D {
        scaled(by: Vector2D(x: factor, y: factor), around: centre)
    }

    /// Rotation around a centre point (default: world origin), angle in radians.
    public func rotated(by angle: Double, around centre: Vector2D = .zero) -> Polygon2D {
        Polygon2D(
            points: points.map { $0.rotated(by: angle, around: centre) },
            type: type,
            pressures: pressures,
            visible: visible
        )
    }

    // MARK: - Visibility

    public func withVisibility(_ isVisible: Bool) -> Polygon2D {
        Polygon2D(points: points, type: type, pressures: pressures, visible: isVisible)
    }
}

/// A 3D polygon in world space.
///
/// All transform methods return a new Polygon3D; the original is not modified.
/// In the Scala engine, Shape3D used a shared point list across polygons
/// for transform efficiency. In Swift, Polygon3D is a self-contained value
/// type — the shared-point pattern is not needed given value-type copy semantics.
public struct Polygon3D: Equatable, Codable, Sendable {

    public var points: [Vector3D]
    public var type: PolygonType
    public var visible: Bool

    public init(points: [Vector3D], type: PolygonType, visible: Bool = true) {
        self.points = points
        self.type = type
        self.visible = visible
    }

    public var pointCount: Int { points.count }

    // MARK: - Transforms

    public func translated(by v: Vector3D) -> Polygon3D {
        Polygon3D(points: points.map { $0.translated(by: v) }, type: type, visible: visible)
    }

    public func scaled(by v: Vector3D) -> Polygon3D {
        Polygon3D(points: points.map { $0.scaled(by: v) }, type: type, visible: visible)
    }

    public func scaled(by factor: Double) -> Polygon3D {
        Polygon3D(points: points.map { $0.scaled(by: factor) }, type: type, visible: visible)
    }

    public func rotatedX(by angle: Double) -> Polygon3D {
        Polygon3D(points: points.map { $0.rotatedX(by: angle) }, type: type, visible: visible)
    }

    public func rotatedY(by angle: Double) -> Polygon3D {
        Polygon3D(points: points.map { $0.rotatedY(by: angle) }, type: type, visible: visible)
    }

    public func rotatedZ(by angle: Double) -> Polygon3D {
        Polygon3D(points: points.map { $0.rotatedZ(by: angle) }, type: type, visible: visible)
    }
}

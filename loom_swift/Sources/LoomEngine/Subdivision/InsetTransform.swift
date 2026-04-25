/// A scale / translate / rotate applied to create inset polygons (ECHO, BORD variants).
///
/// Corresponds to Scala `Transform2D(translation, scale, rotation)`.
/// `rotation` is in radians; `Vector2D(0,0)` rotation = no rotation.
public struct InsetTransform: Equatable, Codable, Sendable {

    public var translation: Vector2D
    public var scale: Vector2D
    public var rotation: Double  // radians

    public static let `default` = InsetTransform(
        translation: .zero,
        scale: Vector2D(x: 0.5, y: 0.5),
        rotation: 0
    )

    public init(translation: Vector2D, scale: Vector2D, rotation: Double) {
        self.translation = translation
        self.scale = scale
        self.rotation = rotation
    }

    // MARK: - Application

    /// Scale `point` around `centre`, add `translation`, then rotate around `centre`.
    ///
    /// Matches Scala's `Vector2D.transformAroundOffset(insetTransform, centre)`:
    ///   P' = centre + (P − centre) × scale + translation
    ///   then rotated by `rotation` around `centre`
    public func apply(to point: Vector2D, around centre: Vector2D) -> Vector2D {
        let x = (point.x - centre.x) * scale.x + centre.x + translation.x
        let y = (point.y - centre.y) * scale.y + centre.y + translation.y
        let result = Vector2D(x: x, y: y)
        guard rotation != 0 else { return result }
        return result.rotated(by: rotation, around: centre)
    }

    /// Scale `point` around the absolute origin.
    /// Used by ECHO_ABS_CENTER: `P' = P × scale`.
    public func applyAbsolute(to point: Vector2D) -> Vector2D {
        Vector2D(x: point.x * scale.x, y: point.y * scale.y)
    }
}

/// Computed animation state for one sprite at a single draw cycle.
///
/// Produced by `TransformAnimator`; consumed by the render pipeline to
/// position, scale, and rotate the sprite's geometry before rendering,
/// and to select a morph-target blend when the animation type is a morph variant.
public struct SpriteTransform: Equatable, Sendable {

    /// World-space translation offset applied after the sprite's base position.
    public var positionOffset: Vector2D

    /// Per-axis scale factor applied around the sprite's base position.
    public var scale: Vector2D

    /// Rotation in degrees (matches keyframe convention; convert to radians before applying).
    public var rotation: Double

    /// Morph blend amount.
    ///
    /// - `0` = base polygon geometry.
    /// - `1` = `morphTargets[0]`.
    /// - `1.5` = midpoint blend between `morphTargets[0]` and `morphTargets[1]`.
    /// - `2` = `morphTargets[1]`.
    /// Integer part selects the *from* target (0 = base); fractional part blends toward the next.
    public var morphAmount: Double

    public init(
        positionOffset: Vector2D = .zero,
        scale: Vector2D          = Vector2D(x: 1, y: 1),
        rotation: Double         = 0,
        morphAmount: Double      = 0
    ) {
        self.positionOffset = positionOffset
        self.scale          = scale
        self.rotation       = rotation
        self.morphAmount    = morphAmount
    }

    /// Identity transform — no translation, unit scale, no rotation, base geometry.
    public static let identity = SpriteTransform()
}

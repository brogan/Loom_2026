import CoreGraphics

/// Maps between world space and screen (pixel) space.
///
/// World space:  origin at canvas centre, Y-up.
/// Screen space: origin at top-left, Y-down (CGContext convention).
///
/// canvasSize is in pixels — pass width * qualityMultiple, height * qualityMultiple.
/// offset is a camera pan in world-space units (positive X pans right, positive Y pans up).
public struct ViewTransform: Equatable, Codable, Sendable {

    public var canvasSize: CGSize
    public var offset: Vector2D

    public init(canvasSize: CGSize, offset: Vector2D = .zero) {
        self.canvasSize = canvasSize
        self.offset = offset
    }

    // MARK: - Coordinate conversion

    /// World → screen.
    public func worldToScreen(_ v: Vector2D) -> CGPoint {
        CGPoint(
            x: canvasSize.width  / 2.0 + v.x + offset.x,
            y: canvasSize.height / 2.0 - v.y + offset.y   // Y flipped
        )
    }

    /// Screen → world (inverse of worldToScreen).
    public func screenToWorld(_ p: CGPoint) -> Vector2D {
        Vector2D(
            x:  p.x - canvasSize.width  / 2.0 - offset.x,
            y: -(p.y - canvasSize.height / 2.0 - offset.y) // Y flipped
        )
    }

    // MARK: - Convenience

    /// Canvas centre in screen space — always (width/2, height/2).
    public var screenCentre: CGPoint {
        CGPoint(x: canvasSize.width / 2.0, y: canvasSize.height / 2.0)
    }
}

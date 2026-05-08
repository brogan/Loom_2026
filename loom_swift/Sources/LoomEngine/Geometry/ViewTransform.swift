import CoreGraphics

/// Maps between world space and screen (pixel) space.
///
/// World space:  origin at canvas centre, Y-up.
/// Screen space: origin at top-left, Y-down (CGContext convention).
///
/// canvasSize is in pixels — pass width * qualityMultiple, height * qualityMultiple.
/// offset is a camera pan in world-space units (positive X pans right, positive Y pans up).
/// zoom is a scale factor applied around the canvas centre (1.0 = no zoom).
/// rotation is a clockwise canvas rotation in degrees (0 = no rotation).
public struct ViewTransform: Equatable, Codable, Sendable {

    public var canvasSize: CGSize
    public var offset:     Vector2D
    /// Camera zoom multiplier.  1.0 = normal, 2.0 = 2× magnification.
    public var zoom:       Double
    /// Canvas rotation in degrees (clockwise, around canvas centre).
    public var rotation:   Double

    public init(
        canvasSize: CGSize,
        offset:     Vector2D = .zero,
        zoom:       Double   = 1.0,
        rotation:   Double   = 0.0
    ) {
        self.canvasSize = canvasSize
        self.offset     = offset
        self.zoom       = zoom
        self.rotation   = rotation
    }

    // MARK: - Coordinate conversion

    /// World → screen.
    ///
    /// Pipeline: rotate → zoom → flip Y → canvas centre + pan offset.
    public func worldToScreen(_ v: Vector2D) -> CGPoint {
        let hw = canvasSize.width  / 2.0
        let hh = canvasSize.height / 2.0

        var wx = v.x, wy = v.y

        if rotation != 0 {
            let rad  = rotation * .pi / 180.0
            let cosR = cos(rad), sinR = sin(rad)
            (wx, wy) = (wx * cosR - wy * sinR, wx * sinR + wy * cosR)
        }

        // zoom and Y-flip
        return CGPoint(
            x: hw + wx * zoom + offset.x,
            y: hh - wy * zoom + offset.y
        )
    }

    /// Screen → world (inverse of worldToScreen).
    public func screenToWorld(_ p: CGPoint) -> Vector2D {
        let hw = canvasSize.width  / 2.0
        let hh = canvasSize.height / 2.0

        let ux = (p.x - hw - offset.x) / zoom
        let uy = -(p.y - hh - offset.y) / zoom

        if rotation == 0 { return Vector2D(x: ux, y: uy) }

        let rad  = -rotation * .pi / 180.0   // inverse rotation
        let cosR = cos(rad), sinR = sin(rad)
        return Vector2D(
            x: ux * cosR - uy * sinR,
            y: ux * sinR + uy * cosR
        )
    }

    // MARK: - Convenience

    /// Canvas centre in screen space — always (width/2, height/2).
    public var screenCentre: CGPoint {
        CGPoint(x: canvasSize.width / 2.0, y: canvasSize.height / 2.0)
    }
}

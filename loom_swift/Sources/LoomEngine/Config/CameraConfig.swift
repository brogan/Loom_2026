import Foundation

// MARK: - CameraConfig
//
// Project-level animated camera.  Each property is driven independently by any
// DoubleDriver or VectorDriver, evaluated against the engine's global elapsed
// frame count.
//
// Effects are applied in ViewTransform each frame:
//   pan      → ViewTransform.offset  (world-space pixel shift)
//   zoom     → ViewTransform.zoom    (scale factor; 1.0 = no zoom)
//   rotation → ViewTransform.rotation (degrees; canvas rotates around centre)

public struct CameraConfig: Codable, Equatable, Sendable {

    public var enabled:  Bool         = false
    /// World-space pan in pixels from canvas centre.
    public var pan:      VectorDriver = .zero
    /// Zoom multiplier.  1.0 = no change; 2.0 = 2× zoom in; 0.5 = zoom out.
    public var zoom:     DoubleDriver = DoubleDriver.constant(1.0)
    /// Canvas rotation in degrees around the canvas centre.
    public var rotation: DoubleDriver = .zero

    public init(
        enabled:  Bool         = false,
        pan:      VectorDriver = .zero,
        zoom:     DoubleDriver = DoubleDriver.constant(1.0),
        rotation: DoubleDriver = .zero
    ) {
        self.enabled  = enabled
        self.pan      = pan
        self.zoom     = zoom
        self.rotation = rotation
    }

    public static let disabled = CameraConfig()
}

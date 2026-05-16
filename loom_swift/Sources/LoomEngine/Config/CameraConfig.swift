import Foundation

// MARK: - CameraConfig
//
// Project-level animated camera.  Each property is driven independently by any
// DoubleDriver or VectorDriver, evaluated against the engine's global elapsed
// frame count.
//
// Effects are applied in ViewTransform each frame:
//   tracking → world-space point kept at the canvas centre
//   pan      → ViewTransform.offset  (world-space pixel shift)
//   zoom     → ViewTransform.zoom    (scale factor; 1.0 = no zoom)
//   rotation → ViewTransform.rotation (degrees; canvas rotates around centre)

public struct CameraConfig: Codable, Equatable, Sendable {

    public var enabled:  Bool         = false
    /// World-space point to keep centred before pan is added.
    public var tracking: VectorDriver = .zero
    /// World-space pan in pixels from canvas centre.
    public var pan:      VectorDriver = .zero
    /// Zoom multiplier.  1.0 = no change; 2.0 = 2× zoom in; 0.5 = zoom out.
    public var zoom:     DoubleDriver = DoubleDriver.constant(1.0)
    /// Canvas rotation in degrees around the canvas centre.
    public var rotation: DoubleDriver = .zero
    /// Controls the strength of the depth/parallax effect for sprites with non-zero depth.
    /// 0 = flat (no effect). ~0.003 is a gentle parallax; ~0.01 is dramatic.
    public var perspectiveStrength: Double = 0

    public init(
        enabled:             Bool         = false,
        tracking:            VectorDriver = .zero,
        pan:                 VectorDriver = .zero,
        zoom:                DoubleDriver = DoubleDriver.constant(1.0),
        rotation:            DoubleDriver = .zero,
        perspectiveStrength: Double       = 0
    ) {
        self.enabled             = enabled
        self.tracking            = tracking
        self.pan                 = pan
        self.zoom                = zoom
        self.rotation            = rotation
        self.perspectiveStrength = perspectiveStrength
    }

    public static let disabled = CameraConfig()

    private enum CodingKeys: String, CodingKey {
        case enabled, tracking, pan, zoom, rotation, perspectiveStrength
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled             = try c.decodeIfPresent(Bool.self,         forKey: .enabled)             ?? false
        tracking            = try c.decodeIfPresent(VectorDriver.self, forKey: .tracking)            ?? .zero
        pan                 = try c.decodeIfPresent(VectorDriver.self, forKey: .pan)                 ?? .zero
        zoom                = try c.decodeIfPresent(DoubleDriver.self, forKey: .zoom)                ?? .constant(1.0)
        rotation            = try c.decodeIfPresent(DoubleDriver.self, forKey: .rotation)            ?? .zero
        perspectiveStrength = try c.decodeIfPresent(Double.self,       forKey: .perspectiveStrength) ?? 0
    }
}

extension CameraConfig {
    var animationEndFrame: Int {
        guard enabled else { return 0 }
        return max(
            tracking.animationEndFrame,
            pan.animationEndFrame,
            zoom.animationEndFrame,
            rotation.animationEndFrame
        )
    }
}

private extension VectorDriver {
    var animationEndFrame: Int {
        guard mode == .keyframe else { return 0 }
        return keyframes.map(\.frame).max() ?? 0
    }
}

private extension DoubleDriver {
    var animationEndFrame: Int {
        guard mode == .keyframe else { return 0 }
        return keyframes.map(\.frame).max() ?? 0
    }
}

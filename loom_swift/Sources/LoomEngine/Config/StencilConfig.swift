import Foundation

// MARK: - StencilOpacityChange

/// Animated opacity change for stamp/stencil rendering.
///
/// When `enabled` is false all stamps draw at opacity 1.0.
public struct StencilOpacityChange: Equatable, Codable, Sendable {
    public var enabled:     Bool         = false
    public var kind:        ChangeKind   = .sequential
    public var motion:      ChangeMotion = .up
    public var cycle:       ChangeCycle  = .constant
    public var scale:       ChangeScale  = .poly
    public var sizePalette: [Double]     = []
    public var pauseMax:    Int          = 0

    public init() {}
}

// MARK: - StencilConfig

/// Parameters for `RendererMode.stamped` rendering.
///
/// Each point in the source geometry gets one stamp image placed at its
/// screen-space position.  Unlike `BrushConfig` there is no meander path,
/// no pressure, and no per-stamp random opacity range — opacity is driven
/// by the `opacityChange` animation palette (or 1.0 when disabled).
public struct StencilConfig: Equatable, Codable, Sendable {
    /// Filenames of stamp PNG images relative to `<project>/stamps/`.
    public var stampNames:             [String]              = ["default.png"]
    public var drawMode:               BrushDrawMode         = .fullPath
    public var stampSpacing:           Double                = 4.0
    public var spacingEasing:          String                = "LINEAR"
    /// When true the stamp is oriented toward the nearest point neighbour;
    /// when false stamps are placed upright (no rotation).
    public var followTangent:          Bool                  = true
    public var perpendicularJitterMin: Double                = -2.0
    public var perpendicularJitterMax: Double                = 2.0
    public var scaleMin:               Double                = 0.8
    public var scaleMax:               Double                = 1.2
    public var stampsPerFrame:         Int                   = 10
    public var agentCount:             Int                   = 1
    public var postCompletionMode:     PostCompletionMode    = .hold
    public var opacityChange:          StencilOpacityChange  = StencilOpacityChange()

    public init() {}

    /// Return a copy with all pixel-space values multiplied by `factor`.
    public func scaled(by factor: Double) -> StencilConfig {
        guard factor != 1.0 else { return self }
        var c = self
        c.stampSpacing           *= factor
        c.perpendicularJitterMin *= factor
        c.perpendicularJitterMax *= factor
        c.stampsPerFrame          = max(1, Int((Double(stampsPerFrame) * factor).rounded()))
        return c
    }
}

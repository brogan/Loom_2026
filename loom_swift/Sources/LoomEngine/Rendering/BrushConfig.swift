import Foundation

// MARK: - MeanderConfig

/// Controls perpendicular displacement of brush paths for a hand-drawn look.
public struct MeanderConfig: Equatable, Codable, Sendable {
    public var enabled:                 Bool   = false
    public var amplitude:               Double = 8.0    // max displacement in canvas pixels
    public var frequency:               Double = 0.03   // noise control-points per pixel
    public var samples:                 Int    = 24     // sample points along each edge
    public var seed:                    Int    = 0      // 0 = auto; >0 = fixed seed
    public var animated:                Bool   = false
    public var animSpeed:               Double = 0.01
    public var scaleAlongPath:          Bool   = false
    public var scaleAlongPathFrequency: Double = 0.05
    public var scaleAlongPathRange:     Double = 0.4

    public init() {}
}

// MARK: - DrawMode / PostCompletionMode

public enum BrushDrawMode: String, Codable, Sendable {
    case fullPath    = "FULL_PATH"
    case progressive = "PROGRESSIVE"
}

public enum PostCompletionMode: String, Codable, Sendable {
    case hold     = "HOLD"
    case loop     = "LOOP"
    case pingPong = "PING_PONG"
}

// MARK: - BrushConfig

/// All parameters for `RendererMode.brushed` stamping.
///
/// Pixel-space values (`stampSpacing`, `perpendicularJitter*`, `meanderConfig.amplitude`)
/// are stored at the logical (quality=1) scale.  `scaled(by:)` returns a copy adjusted
/// for the project's `qualityMultiple`.
public struct BrushConfig: Equatable, Codable, Sendable {
    /// Filenames of brush PNG images relative to `<project>/brushes/`.
    public var brushNames:              [String]          = ["default.png"]
    public var drawMode:                BrushDrawMode     = .fullPath
    public var stampSpacing:            Double            = 4.0
    public var spacingEasing:           String            = "LINEAR"
    public var followTangent:           Bool              = true
    public var perpendicularJitterMin:  Double            = -2.0
    public var perpendicularJitterMax:  Double            = 2.0
    public var scaleMin:                Double            = 0.8
    public var scaleMax:                Double            = 1.2
    public var opacityMin:              Double            = 0.6
    public var opacityMax:              Double            = 1.0
    public var stampsPerFrame:          Int               = 10
    public var agentCount:              Int               = 1
    public var postCompletionMode:      PostCompletionMode = .hold
    public var blurRadius:              Int               = 0
    public var meander:                 MeanderConfig     = MeanderConfig()
    public var pressureSizeInfluence:   Double            = 0.0
    public var pressureAlphaInfluence:  Double            = 0.0

    public init() {}

    /// Return a copy with all pixel-space values multiplied by `factor`.
    ///
    /// `blurRadius` is scaled so the lookup key matches the pre-blurred image stored
    /// by `LoomEngine.preblurBrushImages` at `logicalRadius * qualityMultiple`.
    /// This mirrors Scala's `BrushConfig.scalePixelValues` exactly.
    public func scaled(by factor: Double) -> BrushConfig {
        guard factor != 1.0 else { return self }
        var c = self
        c.stampSpacing           *= factor
        c.perpendicularJitterMin *= factor
        c.perpendicularJitterMax *= factor
        c.blurRadius              = Int((Double(blurRadius) * factor).rounded())
        c.stampsPerFrame          = max(1, Int((Double(stampsPerFrame) * factor).rounded()))
        c.meander.amplitude      *= factor
        c.meander.frequency      /= factor   // keep visual density constant at higher res
        c.meander.scaleAlongPathFrequency /= factor
        c.meander.samples         = max(4, Int((Double(meander.samples) * factor).rounded()))
        return c
    }
}

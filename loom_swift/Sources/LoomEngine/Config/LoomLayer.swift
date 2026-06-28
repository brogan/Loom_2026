import Foundation

/// Controls how a layer's offscreen buffer is managed between frames.
public enum LayerRedrawMode: String, Codable, CaseIterable, Sendable {
    /// Clear and redraw every frame. Default behaviour. (default)
    case full
    /// Draw once on the first frame; never redraw. For fully static background plates.
    case once
    /// Fade previous content toward the background colour, then draw the new frame on top.
    /// Produces ghost trails and motion-accumulation effects. Controlled by `accumulateFade`.
    case accumulate

    public var displayName: String {
        switch self {
        case .full:       return "Full"
        case .once:       return "Once"
        case .accumulate: return "Accumulate"
        }
    }
}

/// One compositing layer in a Loom project.
///
/// Layers form a stack (array order = bottom to top).  Each layer owns a set of
/// sprite sets by name.  At render time each layer is drawn to an offscreen
/// buffer with its own parallaxFactor applied to the camera offset, then
/// composited onto the main canvas with its blend mode and opacity.
///
/// Projects with no layers defined fall back to the legacy flat depth-sort path.
public struct LoomLayer: Codable, Equatable, Identifiable, Sendable {

    public var id:              UUID
    public var name:            String
    public var isVisible:       Bool
    /// Camera-offset parallax scale.  0 = layer is fixed; 1 = moves fully with camera.
    public var parallaxFactor:  Double
    public var opacity:         Double
    public var opacityDriver:   DoubleDriver
    public var blur:            Double
    public var blurDriver:      DoubleDriver
    public var blendMode:       LayerBlendMode
    /// Sprite-set names whose instances are composited into this layer.
    public var spriteSetNames:  [String]
    /// Controls how this layer's offscreen buffer is managed between frames.
    public var redrawMode:      LayerRedrawMode
    /// Fraction of previous frame content retained each frame in `.accumulate` mode.
    /// Range 0–1; typical values 0.90–0.99. Lower = faster fade. (0.95 = ~13 frame half-life at 30fps)
    public var accumulateFade:  Double

    public init(
        id:             UUID            = UUID(),
        name:           String          = "Layer",
        isVisible:      Bool            = true,
        parallaxFactor: Double          = 1.0,
        opacity:        Double          = 1.0,
        opacityDriver:  DoubleDriver    = .one,
        blur:           Double          = 0.0,
        blurDriver:     DoubleDriver    = .zero,
        blendMode:      LayerBlendMode  = .normal,
        spriteSetNames: [String]        = [],
        redrawMode:     LayerRedrawMode = .full,
        accumulateFade: Double          = 0.95
    ) {
        self.id             = id
        self.name           = name
        self.isVisible      = isVisible
        self.parallaxFactor = parallaxFactor
        self.opacity        = opacity
        self.opacityDriver  = opacityDriver
        self.blur           = blur
        self.blurDriver     = blurDriver
        self.blendMode      = blendMode
        self.spriteSetNames = spriteSetNames
        self.redrawMode     = redrawMode
        self.accumulateFade = accumulateFade
    }

    // MARK: - Codable (safe defaults for missing fields)

    private enum CodingKeys: String, CodingKey {
        case id, name, isVisible, parallaxFactor, opacity, opacityDriver
        case blur, blurDriver, blendMode, spriteSetNames
        case redrawMode, accumulateFade
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decodeIfPresent(UUID.self,             forKey: .id)             ?? UUID()
        name           = try c.decodeIfPresent(String.self,           forKey: .name)           ?? "Layer"
        isVisible      = try c.decodeIfPresent(Bool.self,             forKey: .isVisible)      ?? true
        parallaxFactor = try c.decodeIfPresent(Double.self,           forKey: .parallaxFactor) ?? 1.0
        opacity        = try c.decodeIfPresent(Double.self,           forKey: .opacity)        ?? 1.0
        opacityDriver  = try c.decodeIfPresent(DoubleDriver.self,     forKey: .opacityDriver)  ?? .one
        blur           = try c.decodeIfPresent(Double.self,           forKey: .blur)           ?? 0.0
        blurDriver     = try c.decodeIfPresent(DoubleDriver.self,     forKey: .blurDriver)     ?? .zero
        blendMode      = try c.decodeIfPresent(LayerBlendMode.self,   forKey: .blendMode)      ?? .normal
        spriteSetNames = try c.decodeIfPresent([String].self,         forKey: .spriteSetNames) ?? []
        redrawMode     = try c.decodeIfPresent(LayerRedrawMode.self,  forKey: .redrawMode)     ?? .full
        accumulateFade = try c.decodeIfPresent(Double.self,           forKey: .accumulateFade) ?? 0.95
    }
}

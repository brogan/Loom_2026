/// One compositing layer in a Loom project.
///
/// Layers form a stack (array order = bottom to top).  Each layer owns a set of
/// sprite sets by name.  At render time each layer is drawn to an offscreen
/// buffer with its own parallaxFactor applied to the camera offset, then
/// composited onto the main canvas with its blend mode and opacity.
///
/// Projects with no layers defined fall back to the legacy flat depth-sort path.
public struct LoomLayer: Codable, Equatable, Sendable {

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

    public init(
        name:           String         = "Layer",
        isVisible:      Bool           = true,
        parallaxFactor: Double         = 1.0,
        opacity:        Double         = 1.0,
        opacityDriver:  DoubleDriver   = .one,
        blur:           Double         = 0.0,
        blurDriver:     DoubleDriver   = .zero,
        blendMode:      LayerBlendMode = .normal,
        spriteSetNames: [String]       = []
    ) {
        self.name           = name
        self.isVisible      = isVisible
        self.parallaxFactor = parallaxFactor
        self.opacity        = opacity
        self.opacityDriver  = opacityDriver
        self.blur           = blur
        self.blurDriver     = blurDriver
        self.blendMode      = blendMode
        self.spriteSetNames = spriteSetNames
    }

    // MARK: - Codable (safe defaults for missing fields)

    private enum CodingKeys: String, CodingKey {
        case name, isVisible, parallaxFactor, opacity, opacityDriver
        case blur, blurDriver, blendMode, spriteSetNames
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name           = try c.decodeIfPresent(String.self,         forKey: .name)           ?? "Layer"
        isVisible      = try c.decodeIfPresent(Bool.self,           forKey: .isVisible)      ?? true
        parallaxFactor = try c.decodeIfPresent(Double.self,         forKey: .parallaxFactor) ?? 1.0
        opacity        = try c.decodeIfPresent(Double.self,         forKey: .opacity)        ?? 1.0
        opacityDriver  = try c.decodeIfPresent(DoubleDriver.self,   forKey: .opacityDriver)  ?? .one
        blur           = try c.decodeIfPresent(Double.self,         forKey: .blur)           ?? 0.0
        blurDriver     = try c.decodeIfPresent(DoubleDriver.self,   forKey: .blurDriver)     ?? .zero
        blendMode      = try c.decodeIfPresent(LayerBlendMode.self, forKey: .blendMode)      ?? .normal
        spriteSetNames = try c.decodeIfPresent([String].self,       forKey: .spriteSetNames) ?? []
    }
}

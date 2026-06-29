/// All configuration loaded from one `.loom_projects/<ProjectName>` directory.
///
/// `ProjectLoader` produces this struct by reading the nine XML files in
/// `configuration/`. `JSONConfigLoader` can serialise and restore it as JSON.
public struct ProjectConfig: Codable, Sendable {
    public var globalConfig:      GlobalConfig
    public var shapeConfig:       ShapeConfig
    public var polygonConfig:     PolygonConfig
    public var curveConfig:       CurveConfig
    public var ovalConfig:        OvalConfig
    public var pointConfig:       PointConfig
    public var subdivisionConfig: SubdivisionConfig
    public var renderingConfig:   RenderingConfig
    public var spriteConfig:      SpriteConfig
    /// Compositing layers (bottom to top).  Empty = legacy flat depth-sort render.
    public var layers:            [LoomLayer]
    /// Named sprite cycles (walk cycles, image sequences, etc.).  Empty = no cycles defined.
    public var cycles:            [SpriteCycle]
    /// Theatrical lighting configuration.  Default disabled = zero render overhead.
    public var lightingConfig:    LightingConfig

    public init(
        globalConfig: GlobalConfig           = .default,
        shapeConfig: ShapeConfig             = ShapeConfig(),
        polygonConfig: PolygonConfig         = PolygonConfig(),
        curveConfig: CurveConfig             = CurveConfig(),
        ovalConfig: OvalConfig               = OvalConfig(),
        pointConfig: PointConfig             = PointConfig(),
        subdivisionConfig: SubdivisionConfig = SubdivisionConfig(),
        renderingConfig: RenderingConfig     = RenderingConfig(),
        spriteConfig: SpriteConfig           = SpriteConfig(),
        layers: [LoomLayer]                  = [],
        cycles: [SpriteCycle]                = [],
        lightingConfig: LightingConfig       = LightingConfig()
    ) {
        self.globalConfig      = globalConfig
        self.shapeConfig       = shapeConfig
        self.polygonConfig     = polygonConfig
        self.curveConfig       = curveConfig
        self.ovalConfig        = ovalConfig
        self.pointConfig       = pointConfig
        self.subdivisionConfig = subdivisionConfig
        self.renderingConfig   = renderingConfig
        self.spriteConfig      = spriteConfig
        self.layers            = layers
        self.cycles            = cycles
        self.lightingConfig    = lightingConfig
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case globalConfig, shapeConfig, polygonConfig, curveConfig, ovalConfig
        case pointConfig, subdivisionConfig, renderingConfig, spriteConfig, layers, cycles
        case lightingConfig
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        globalConfig      = try c.decode(GlobalConfig.self,      forKey: .globalConfig)
        shapeConfig       = try c.decode(ShapeConfig.self,       forKey: .shapeConfig)
        polygonConfig     = try c.decode(PolygonConfig.self,     forKey: .polygonConfig)
        curveConfig       = try c.decode(CurveConfig.self,       forKey: .curveConfig)
        ovalConfig        = try c.decode(OvalConfig.self,        forKey: .ovalConfig)
        pointConfig       = try c.decode(PointConfig.self,       forKey: .pointConfig)
        subdivisionConfig = try c.decode(SubdivisionConfig.self, forKey: .subdivisionConfig)
        renderingConfig   = try c.decode(RenderingConfig.self,   forKey: .renderingConfig)
        spriteConfig      = try c.decode(SpriteConfig.self,      forKey: .spriteConfig)
        layers            = try c.decodeIfPresent([LoomLayer].self,    forKey: .layers)         ?? []
        cycles            = try c.decodeIfPresent([SpriteCycle].self,  forKey: .cycles)         ?? []
        lightingConfig    = try c.decodeIfPresent(LightingConfig.self, forKey: .lightingConfig) ?? LightingConfig()
    }
}

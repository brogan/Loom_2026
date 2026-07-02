import Foundation

/// A named scene within a project: its own timeline duration, markers, and sprite animation data.
/// The shared asset pools (geometry, subdivision, rendering, cycles, layers) remain at the
/// project level and are the same across all scenes.
public struct LoomScene: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var globalConfig: GlobalConfig
    public var spriteConfig: SpriteConfig

    public init(id: UUID = UUID(), name: String,
                globalConfig: GlobalConfig = .default,
                spriteConfig: SpriteConfig = SpriteConfig()) {
        self.id           = id
        self.name         = name
        self.globalConfig = globalConfig
        self.spriteConfig = spriteConfig
    }
}

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
    /// Named scenes. Each carries its own timeline (globalConfig) and sprite animation (spriteConfig).
    /// Empty only transiently — always has at least one entry after decode.
    public var scenes:            [LoomScene]
    /// ID of the scene whose globalConfig/spriteConfig are currently loaded into the top-level fields.
    public var activeSceneID:     UUID?

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
        lightingConfig: LightingConfig       = LightingConfig(),
        scenes: [LoomScene]                  = [],
        activeSceneID: UUID?                 = nil
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
        self.scenes            = scenes
        self.activeSceneID     = activeSceneID
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case globalConfig, shapeConfig, polygonConfig, curveConfig, ovalConfig
        case pointConfig, subdivisionConfig, renderingConfig, spriteConfig, layers, cycles
        case lightingConfig, scenes, activeSceneID
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
        scenes            = try c.decodeIfPresent([LoomScene].self,    forKey: .scenes)         ?? []
        activeSceneID     = try c.decodeIfPresent(UUID.self,           forKey: .activeSceneID)
        // Migration: legacy project with no scenes — create Scene 1 from the top-level config.
        if scenes.isEmpty {
            let defaultScene = LoomScene(name: "Scene 1", globalConfig: globalConfig, spriteConfig: spriteConfig)
            scenes        = [defaultScene]
            activeSceneID = defaultScene.id
        }
    }
}

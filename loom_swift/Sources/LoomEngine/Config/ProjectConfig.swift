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

    public init(
        globalConfig: GlobalConfig           = .default,
        shapeConfig: ShapeConfig             = ShapeConfig(),
        polygonConfig: PolygonConfig         = PolygonConfig(),
        curveConfig: CurveConfig             = CurveConfig(),
        ovalConfig: OvalConfig               = OvalConfig(),
        pointConfig: PointConfig             = PointConfig(),
        subdivisionConfig: SubdivisionConfig = SubdivisionConfig(),
        renderingConfig: RenderingConfig     = RenderingConfig(),
        spriteConfig: SpriteConfig           = SpriteConfig()
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
    }
}

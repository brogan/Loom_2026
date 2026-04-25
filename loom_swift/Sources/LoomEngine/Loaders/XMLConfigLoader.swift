import Foundation

/// Loads each Loom project config XML file into its corresponding Swift struct.
///
/// All methods are lenient: missing or malformed elements fall back to struct
/// defaults rather than throwing.  Structural parse failures (invalid XML) do throw.
public enum XMLConfigLoader {

    // MARK: - GlobalConfig

    public static func loadGlobalConfig(url: URL) throws -> GlobalConfig {
        let root = try parseXMLFile(url)
        return parseGlobalConfig(root)
    }

    public static func loadGlobalConfig(data: Data) throws -> GlobalConfig {
        let root = try parseXML(data: data)
        return parseGlobalConfig(root)
    }

    // MARK: - ShapeConfig

    public static func loadShapeConfig(url: URL) throws -> ShapeConfig {
        let root = try parseXMLFile(url)
        return parseShapeConfig(root)
    }

    public static func loadShapeConfig(data: Data) throws -> ShapeConfig {
        let root = try parseXML(data: data)
        return parseShapeConfig(root)
    }

    // MARK: - PolygonConfig

    public static func loadPolygonConfig(url: URL) throws -> PolygonConfig {
        let root = try parseXMLFile(url)
        return parsePolygonConfig(root)
    }

    public static func loadPolygonConfig(data: Data) throws -> PolygonConfig {
        let root = try parseXML(data: data)
        return parsePolygonConfig(root)
    }

    // MARK: - SubdivisionConfig

    public static func loadSubdivisionConfig(url: URL) throws -> SubdivisionConfig {
        let root = try parseXMLFile(url)
        return parseSubdivisionConfig(root)
    }

    public static func loadSubdivisionConfig(data: Data) throws -> SubdivisionConfig {
        let root = try parseXML(data: data)
        return parseSubdivisionConfig(root)
    }

    // MARK: - RenderingConfig

    public static func loadRenderingConfig(url: URL) throws -> RenderingConfig {
        let root = try parseXMLFile(url)
        return parseRenderingConfig(root)
    }

    public static func loadRenderingConfig(data: Data) throws -> RenderingConfig {
        let root = try parseXML(data: data)
        return parseRenderingConfig(root)
    }

    // MARK: - SpriteConfig

    public static func loadSpriteConfig(url: URL) throws -> SpriteConfig {
        let root = try parseXMLFile(url)
        return parseSpriteConfig(root)
    }

    public static func loadSpriteConfig(data: Data) throws -> SpriteConfig {
        let root = try parseXML(data: data)
        return parseSpriteConfig(root)
    }

    // MARK: - Private helpers

    private static func parseXMLFile(_ url: URL) throws -> XMLNode {
        let data = try Data(contentsOf: url)
        return try parseXML(data: data)
    }

    // MARK: GlobalConfig

    private static func parseGlobalConfig(_ root: XMLNode) -> GlobalConfig {
        var c = GlobalConfig()
        c.name               = root.childText("Name", default: c.name)
        c.width              = root.childInt("Width", default: c.width)
        c.height             = root.childInt("Height", default: c.height)
        c.qualityMultiple    = root.childInt("QualityMultiple", default: c.qualityMultiple)
        c.scaleImage         = root.childBool("ScaleImage", default: c.scaleImage)
        c.animating          = root.childBool("Animating", default: c.animating)
        c.drawBackgroundOnce = root.childBool("DrawBackgroundOnce", default: c.drawBackgroundOnce)
        c.fullscreen         = root.childBool("Fullscreen", default: c.fullscreen)
        c.borderColor        = root.childColor("BorderColor", default: c.borderColor)
        c.backgroundColor    = root.childColor("BackgroundColor", default: c.backgroundColor)
        c.overlayColor       = root.childColor("OverlayColor", default: c.overlayColor)
        c.backgroundImagePath = root.childText("BackgroundImage", default: c.backgroundImagePath)
        c.threeD             = root.childBool("ThreeD", default: c.threeD)
        c.cameraViewAngle    = root.childInt("CameraViewAngle", default: c.cameraViewAngle)
        c.subdividing        = root.childBool("Subdividing", default: c.subdividing)
        c.targetFPS          = root.childDouble("TargetFPS", default: c.targetFPS)
        return c
    }

    // MARK: ShapeConfig

    private static func parseShapeConfig(_ root: XMLNode) -> ShapeConfig {
        let libNode = root.child(named: "ShapeLibrary") ?? root
        let libName = libNode.attr("name") ?? ""
        let sets = libNode.children(named: "ShapeSet").map { parseShapeSet($0) }
        return ShapeConfig(library: ShapeLibrary(name: libName, shapeSets: sets))
    }

    private static func parseShapeSet(_ node: XMLNode) -> ShapeSet {
        let name   = node.attr("name") ?? ""
        let shapes = node.children(named: "Shape").map { parseShapeDef($0) }
        return ShapeSet(name: name, shapes: shapes)
    }

    private static func parseShapeDef(_ node: XMLNode) -> ShapeDef {
        let name = node.attr("name") ?? ""
        var def  = ShapeDef(name: name)

        if let src = node.child(named: "Source") {
            let typeStr = src.attr("type") ?? ""
            def.sourceType = ShapeSourceType(xmlName: typeStr)

            switch def.sourceType {
            case .polygonSet:
                // <Source type="POLYGON_SET" polygonSet="Name"/> (attribute form)
                // or <Source type="POLYGON_SET"><PolygonSet>Name</PolygonSet></Source>
                def.polygonSetName = src.attr("polygonSet")
                    ?? src.childText("PolygonSet")
            case .regularPolygon:
                // <Source type="REGULAR_POLYGON" sides="7"/>
                def.regularPolygonSides = Int(src.attr("sides") ?? "0") ?? 0
            case .openCurveSet:
                def.openCurveSetName = src.attr("openCurveSet")
                    ?? src.childText("OpenCurveSet")
            case .pointSet:
                def.pointSetName = src.attr("pointSet")
                    ?? src.childText("PointSet")
            case .ovalSet:
                def.ovalSetName = src.attr("ovalSet")
                    ?? src.childText("OvalSet")
            default:
                break
            }
        }

        if let spNode = node.child(named: "SubdivisionParamsSet") {
            def.subdivisionParamsSetName = spNode.attr("name") ?? ""
        }

        return def
    }

    // MARK: PolygonConfig

    private static func parsePolygonConfig(_ root: XMLNode) -> PolygonConfig {
        let libNode = root.child(named: "PolygonSetLibrary") ?? root
        let libName = libNode.attr("name") ?? ""
        let sets = libNode.children(named: "PolygonSet").map { parsePolygonSetDef($0) }
        return PolygonConfig(library: PolygonSetLibrary(name: libName, polygonSets: sets))
    }

    private static func parsePolygonSetDef(_ node: XMLNode) -> PolygonSetDef {
        let name = node.attr("name") ?? ""
        guard let src = node.child(named: "Source") else {
            return PolygonSetDef(name: name)
        }

        let sourceType = src.attr("type") ?? "file"

        if sourceType == "regular" {
            var p = RegularPolygonParams()
            p.totalPoints     = Int(src.childText("TotalPoints"))   ?? 4
            p.internalRadius  = Double(src.childText("InternalRadius")) ?? 0.5
            p.offset          = Double(src.childText("Offset"))         ?? 0.0
            p.scaleX          = Double(src.childText("ScaleX"))         ?? 1.0
            p.scaleY          = Double(src.childText("ScaleY"))         ?? 1.0
            p.rotationAngle   = Double(src.childText("RotationAngle"))  ?? 0.0
            p.transX          = Double(src.childText("TransX"))         ?? 0.5
            p.transY          = Double(src.childText("TransY"))         ?? 0.5
            p.positiveSynch   = (src.childText("PositiveSynch") == "true")
            p.synchMultiplier = Double(src.childText("SynchMultiplier")) ?? 1.0
            return PolygonSetDef(name: name, regularParams: p)
        }

        let folder   = src.childText("Folder", default: "polygonSet")
        let filename = src.childText("Filename")
        let typeStr  = src.childText("PolygonType", default: "SPLINE_POLYGON")
        let polyType = PolygonFileType(rawValue: typeStr) ?? .splinePolygon
        return PolygonSetDef(name: name, folder: folder, filename: filename, polygonType: polyType)
    }

    // MARK: CurveConfig

    public static func loadCurveConfig(url: URL) throws -> CurveConfig {
        let root = try parseXMLFile(url)
        return parseCurveConfig(root)
    }

    public static func loadCurveConfig(data: Data) throws -> CurveConfig {
        let root = try parseXML(data: data)
        return parseCurveConfig(root)
    }

    private static func parseCurveConfig(_ root: XMLNode) -> CurveConfig {
        let libNode = root.child(named: "OpenCurveSetLibrary") ?? root
        let libName = libNode.attr("name") ?? ""
        let sets    = libNode.children(named: "OpenCurveSet").map { parseOpenCurveSetDef($0) }
        return CurveConfig(library: OpenCurveSetLibrary(name: libName, curveSets: sets))
    }

    private static func parseOpenCurveSetDef(_ node: XMLNode) -> OpenCurveSetDef {
        let name = node.attr("name") ?? ""
        guard let src = node.child(named: "Source") else {
            return OpenCurveSetDef(name: name)
        }
        let folder   = src.childText("Folder", default: "curveSets")
        let filename = src.childText("Filename")
        return OpenCurveSetDef(name: name, folder: folder, filename: filename)
    }

    // MARK: OvalConfig

    public static func loadOvalConfig(url: URL) throws -> OvalConfig {
        let root = try parseXMLFile(url)
        return parseOvalConfig(root)
    }

    public static func loadOvalConfig(data: Data) throws -> OvalConfig {
        let root = try parseXML(data: data)
        return parseOvalConfig(root)
    }

    private static func parseOvalConfig(_ root: XMLNode) -> OvalConfig {
        let libNode = root.child(named: "OvalSetLibrary") ?? root
        let libName = libNode.attr("name") ?? ""
        let sets    = libNode.children(named: "OvalSet").map { parseOvalSetDef($0) }
        return OvalConfig(library: OvalSetLibrary(name: libName, ovalSets: sets))
    }

    private static func parseOvalSetDef(_ node: XMLNode) -> OvalSetDef {
        let name = node.attr("name") ?? ""
        guard let src = node.child(named: "Source") else {
            return OvalSetDef(name: name)
        }
        let folder   = src.childText("Folder", default: "ovalSets")
        let filename = src.childText("Filename")
        return OvalSetDef(name: name, folder: folder, filename: filename)
    }

    // MARK: PointConfig

    public static func loadPointConfig(url: URL) throws -> PointConfig {
        let root = try parseXMLFile(url)
        return parsePointConfig(root)
    }

    private static func parsePointConfig(_ root: XMLNode) -> PointConfig {
        let libNode = root.child(named: "PointSetLibrary") ?? root
        let libName = libNode.attr("name") ?? ""
        let sets    = libNode.children(named: "PointSet").map { parsePointSetDef($0) }
        return PointConfig(library: PointSetLibrary(name: libName, pointSets: sets))
    }

    private static func parsePointSetDef(_ node: XMLNode) -> PointSetDef {
        let name = node.attr("name") ?? ""
        guard let src = node.child(named: "Source") else {
            return PointSetDef(name: name)
        }
        let folder   = src.childText("Folder",   default: "pointSets")
        let filename = src.childText("Filename")
        return PointSetDef(name: name, folder: folder, filename: filename)
    }

    // MARK: SubdivisionConfig

    private static func parseSubdivisionConfig(_ root: XMLNode) -> SubdivisionConfig {
        let sets = root.children(named: "SubdivisionParamsSet").map { parseParamsSet($0) }
        return SubdivisionConfig(paramsSets: sets)
    }

    private static func parseParamsSet(_ node: XMLNode) -> SubdivisionParamsSet {
        let name   = node.attr("name") ?? ""
        let params = node.children(named: "SubdivisionParams").map { parseSubdivisionParams($0) }
        return SubdivisionParamsSet(name: name, params: params)
    }

    private static func parseSubdivisionParams(_ node: XMLNode) -> SubdivisionParams {
        let name = node.attr("name") ?? ""
        var p = SubdivisionParams(name: name)

        let typeStr = node.childText("SubdivisionType", default: "QUAD")
        p.subdivisionType = SubdivisionType(xmlName: typeStr) ?? .quad

        let ruleStr = node.childText("VisibilityRule", default: "ALL")
        p.visibilityRule = VisibilityRule(xmlName: ruleStr) ?? .all

        p.ranMiddle = node.childBool("RanMiddle", default: p.ranMiddle)
        p.ranDiv    = node.childDouble("RanDiv",   default: p.ranDiv)

        p.lineRatios         = node.childVec2("LineRatios",         default: p.lineRatios)
        p.controlPointRatios = node.childVec2("ControlPointRatios", default: p.controlPointRatios)
        p.continuous         = node.childBool("Continuous",         default: p.continuous)
        p.polysTransform     = node.childBool("PolysTransform",     default: p.polysTransform)
        p.polysTranformWhole = node.childBool("PolysTransformWhole",default: p.polysTranformWhole)
        p.pTW_probability    = node.childDouble("PTW_Probability",  default: p.pTW_probability)
        p.pTW_commonCentre   = node.childBool("PTW_CommonCentre",   default: p.pTW_commonCentre)
        p.polysTransformPoints = node.childBool("PolysTransformPoints", default: p.polysTransformPoints)
        p.pTP_probability    = node.childDouble("PTP_Probability",  default: p.pTP_probability)

        if let itNode = node.child(named: "InsetTransform") {
            p.insetTransform = parseInsetTransform(itNode)
        }

        // PTW random-mode flags
        p.pTW_randomTranslation = node.childBool("PTW_RandomTranslation", default: p.pTW_randomTranslation)
        p.pTW_randomScale       = node.childBool("PTW_RandomScale",       default: p.pTW_randomScale)
        p.pTW_randomRotation    = node.childBool("PTW_RandomRotation",    default: p.pTW_randomRotation)

        // PTW deterministic transform (same shape as InsetTransform)
        if let tNode = node.child(named: "PTW_Transform") {
            p.pTW_transform = parseInsetTransform(tNode)
        }

        p.pTW_randomCentreDivisor = node.childDouble("PTW_RandomCentreDivisor",
                                                      default: p.pTW_randomCentreDivisor)

        // PTW random ranges: <PTW_RandomTranslationRange><X min max/><Y min max/></…>
        if let rn = node.child(named: "PTW_RandomTranslationRange") {
            p.pTW_randomTranslationRange = parseVectorRange(rn)
        }
        if let rn = node.child(named: "PTW_RandomScaleRange") {
            p.pTW_randomScaleRange = parseVectorRange(rn)
        }
        // Rotation range lives as attributes on the element itself: <PTW_RandomRotationRange min max/>
        if let rn = node.child(named: "PTW_RandomRotationRange") {
            p.pTW_randomRotationRange = FloatRange(
                min: rn.doubleAttr("min"),
                max: rn.doubleAttr("max")
            )
        }

        // PTP structured transforms: <TransformSet><ExteriorAnchors .../><CentralAnchors .../></TransformSet>
        if let tsNode = node.child(named: "TransformSet") {
            p.ptpTransformSet = parseTransformSet(tsNode)
        }

        return p
    }

    private static func parseTransformSet(_ node: XMLNode) -> PTPTransformSet {
        var ts = PTPTransformSet()
        if let eaNode = node.child(named: "ExteriorAnchors") {
            ts.exteriorAnchors = parseExteriorAnchors(eaNode)
        }
        if let caNode = node.child(named: "CentralAnchors") {
            ts.centralAnchors = parseCentralAnchors(caNode)
        }
        return ts
    }

    private static func parseExteriorAnchors(_ node: XMLNode) -> ExteriorAnchorsTransform {
        return ExteriorAnchorsTransform(
            enabled:              (node.attr("enabled") ?? "false") == "true",
            probability:          node.childDouble("Probability",          default: 100),
            spikeFactor:          node.childDouble("SpikeFactor",          default: -0.3),
            whichSpike:           node.childText("WhichSpike",             default: "ALL"),
            spikeType:            node.childText("SpikeType",              default: "SYMMETRICAL"),
            spikeAxis:            node.childText("SpikeAxis",              default: "XY"),
            randomSpike:          node.childBool("RandomSpike",            default: false),
            randomSpikeFactor:    parseFloatRangeAttr(node, name: "RandomSpikeFactor",
                                                      defMin: -0.2, defMax: 0.2),
            cpsFollow:            node.childBool("CpsFollow",              default: false),
            cpsFollowMultiplier:  node.childDouble("CpsFollowMultiplier",  default: 2.0),
            randomCpsFollow:      node.childBool("RandomCpsFollow",        default: false),
            randomCpsFollowRange: parseFloatRangeAttr(node, name: "RandomCpsFollowRange",
                                                      defMin: -1.5, defMax: 1.5),
            cpsSqueeze:           node.childBool("CpsSqueeze",             default: false),
            cpsSqueezeFactor:     node.childDouble("CpsSqueezeFactor",     default: -0.2),
            randomCpsSqueeze:     node.childBool("RandomCpsSqueeze",       default: false),
            randomCpsSqueezeRange: parseFloatRangeAttr(node, name: "RandomCpsSqueezeRange",
                                                       defMin: -0.5, defMax: 0.5)
        )
    }

    private static func parseCentralAnchors(_ node: XMLNode) -> CentralAnchorsTransform {
        return CentralAnchorsTransform(
            enabled:              (node.attr("enabled") ?? "false") == "true",
            probability:          node.childDouble("Probability",          default: 100),
            tearFactor:           node.childDouble("TearFactor",           default: 0.2),
            tearAxis:             node.childText("TearAxis",               default: "XY"),
            tearDirection:        node.childText("TearDirection",          default: "DIAGONAL"),
            randomTear:           node.childBool("RandomTear",             default: false),
            randomTearFactor:     parseFloatRangeAttr(node, name: "RandomTearFactor",
                                                      defMin: -0.2, defMax: 0.2),
            cpsFollow:            node.childBool("CpsFollow",              default: false),
            cpsFollowMultiplier:  node.childDouble("CpsFollowMultiplier",  default: -7.0),
            randomCpsFollow:      node.childBool("RandomCpsFollow",        default: false),
            randomCpsFollowRange: parseFloatRangeAttr(node, name: "RandomCpsFollowRange",
                                                      defMin: -1.5, defMax: 1.5),
            allPointsFollow:      node.childBool("AllPointsFollow",        default: false),
            invertedFollow:       node.childBool("InvertedFollow",         default: false)
        )
    }

    private static func parseFloatRangeAttr(_ node: XMLNode, name: String,
                                             defMin: Double, defMax: Double) -> FloatRange {
        guard let child = node.child(named: name) else {
            return FloatRange(min: defMin, max: defMax)
        }
        return FloatRange(min: child.doubleAttr("min", default: defMin),
                          max: child.doubleAttr("max", default: defMax))
    }

    // MARK: - Range helpers

    private static func parseVectorRange(_ node: XMLNode) -> VectorRange {
        var x = FloatRange.zero
        var y = FloatRange.zero
        if let xn = node.child(named: "X") {
            x = FloatRange(min: xn.doubleAttr("min"), max: xn.doubleAttr("max"))
        }
        if let yn = node.child(named: "Y") {
            y = FloatRange(min: yn.doubleAttr("min"), max: yn.doubleAttr("max"))
        }
        return VectorRange(x: x, y: y)
    }

    private static func parseInsetTransform(_ node: XMLNode) -> InsetTransform {
        let translation = node.childVec2("Translation")
        let scale       = node.childVec2("Scale", default: Vector2D(x: 0.5, y: 0.5))
        // Rotation element uses x attribute as the angle in radians
        let rotation    = node.child(named: "Rotation").map { $0.doubleAttr("x") } ?? 0.0
        return InsetTransform(translation: translation, scale: scale, rotation: rotation)
    }

    // MARK: RenderingConfig

    private static func parseRenderingConfig(_ root: XMLNode) -> RenderingConfig {
        let libNode = root.child(named: "RendererSetLibrary") ?? root
        let libName = libNode.attr("name") ?? ""
        let sets = libNode.children(named: "RendererSet").map { parseRendererSet($0) }
        return RenderingConfig(library: RendererSetLibrary(name: libName, rendererSets: sets))
    }

    private static func parseRendererSet(_ node: XMLNode) -> RendererSet {
        let name = node.attr("name") ?? ""
        var pb   = RendererPlaybackConfig()
        if let pbNode = node.child(named: "PlaybackConfig") {
            let modeStr = pbNode.childText("Mode", default: "SEQUENTIAL")
            pb.mode = PlaybackMode(rawValue: modeStr) ?? .sequential
            pb.preferredRenderer         = pbNode.childText("PreferredRenderer")
            pb.preferredProbability      = pbNode.childDouble("PreferredProbability", default: 50.0)
            pb.modifyInternalParameters  = pbNode.childBool("ModifyInternalParameters")
        }
        let renderers = node.children(named: "Renderer").map { parseRenderer($0) }
        return RendererSet(name: name, playbackConfig: pb, renderers: renderers)
    }

    private static func parseRenderer(_ node: XMLNode) -> Renderer {
        let name        = node.attr("name") ?? ""
        let modeStr     = node.childText("Mode", default: "STROKED")
        let mode        = RendererMode(rawValue: modeStr) ?? .stroked
        let strokeWidth = node.childDouble("StrokeWidth", default: 1.0)
        let strokeColor = node.childColor("StrokeColor")
        let fillColor   = node.childColor("FillColor")
        let pointSize   = node.childDouble("PointSize", default: 2.0)
        let holdLength  = node.childInt("HoldLength", default: 1)
        let changes     = node.child(named: "Changes").map { parseRendererChanges($0) }
                          ?? RendererChanges()
        let brushConfig   = node.child(named: "BrushConfig").map   { parseBrushConfig($0) }
        let stencilConfig = node.child(named: "StencilConfig").map { parseStencilConfig($0) }
        return Renderer(name: name, mode: mode, strokeWidth: strokeWidth,
                        strokeColor: strokeColor, fillColor: fillColor,
                        pointSize: pointSize, holdLength: holdLength,
                        changes: changes, brushConfig: brushConfig,
                        stencilConfig: stencilConfig)
    }

    private static func parseBrushConfig(_ node: XMLNode) -> BrushConfig {
        var b = BrushConfig()

        if let namesNode = node.child(named: "BrushNames") {
            b.brushNames = namesNode.children(named: "Brush").map { $0.text ?? "" }.filter { !$0.isEmpty }
        }
        if let enabledNode = node.child(named: "BrushEnabled") {
            _ = enabledNode.childText("Enabled")   // stored per-brush in Scala; treat as global enable
        }

        b.drawMode               = BrushDrawMode(rawValue: node.childText("DrawMode", default: "FULL_PATH")) ?? .fullPath
        b.stampSpacing           = node.childDouble("StampSpacing",           default: 4.0)
        b.spacingEasing          = node.childText("SpacingEasing",            default: "LINEAR")
        b.followTangent          = node.childBool("FollowTangent",            default: true)
        b.perpendicularJitterMin = node.childDouble("PerpendicularJitterMin", default: -2.0)
        b.perpendicularJitterMax = node.childDouble("PerpendicularJitterMax", default:  2.0)
        b.scaleMin               = node.childDouble("ScaleMin",               default: 0.8)
        b.scaleMax               = node.childDouble("ScaleMax",               default: 1.2)
        b.opacityMin             = node.childDouble("OpacityMin",             default: 0.6)
        b.opacityMax             = node.childDouble("OpacityMax",             default: 1.0)
        b.stampsPerFrame         = node.childInt("StampsPerFrame",            default: 10)
        b.agentCount             = node.childInt("AgentCount",                default: 1)
        b.postCompletionMode     = PostCompletionMode(rawValue: node.childText("PostCompletionMode", default: "HOLD")) ?? .hold
        b.blurRadius             = node.childInt("BlurRadius",                default: 0)
        b.pressureSizeInfluence  = node.childDouble("PressureSizeInfluence",  default: 0.0)
        b.pressureAlphaInfluence = node.childDouble("PressureAlphaInfluence", default: 0.0)

        if let mc = node.child(named: "MeanderConfig") {
            b.meander.enabled                 = mc.childBool("Enabled",                  default: false)
            b.meander.amplitude               = mc.childDouble("Amplitude",              default: 8.0)
            b.meander.frequency               = mc.childDouble("Frequency",              default: 0.03)
            b.meander.samples                 = mc.childInt("Samples",                   default: 24)
            b.meander.seed                    = mc.childInt("Seed",                      default: 0)
            b.meander.animated                = mc.childBool("Animated",                 default: false)
            b.meander.animSpeed               = mc.childDouble("AnimSpeed",              default: 0.01)
            b.meander.scaleAlongPath          = mc.childBool("ScaleAlongPath",           default: false)
            b.meander.scaleAlongPathFrequency = mc.childDouble("ScaleAlongPathFrequency",default: 0.05)
            b.meander.scaleAlongPathRange     = mc.childDouble("ScaleAlongPathRange",    default: 0.4)
        }

        return b
    }

    private static func parseStencilConfig(_ node: XMLNode) -> StencilConfig {
        var s = StencilConfig()

        if let namesNode = node.child(named: "StencilNames") {
            s.stampNames = namesNode.children(named: "Stencil").map { $0.text ?? "" }.filter { !$0.isEmpty }
        }

        s.drawMode               = BrushDrawMode(rawValue: node.childText("DrawMode", default: "FULL_PATH")) ?? .fullPath
        s.stampSpacing           = node.childDouble("StampSpacing",           default: 4.0)
        s.spacingEasing          = node.childText("SpacingEasing",            default: "LINEAR")
        s.followTangent          = node.childBool("FollowTangent",            default: true)
        s.perpendicularJitterMin = node.childDouble("PerpendicularJitterMin", default: -2.0)
        s.perpendicularJitterMax = node.childDouble("PerpendicularJitterMax", default:  2.0)
        s.scaleMin               = node.childDouble("ScaleMin",               default: 0.8)
        s.scaleMax               = node.childDouble("ScaleMax",               default: 1.2)
        s.stampsPerFrame         = node.childInt("StampsPerFrame",            default: 10)
        s.agentCount             = node.childInt("AgentCount",                default: 1)
        s.postCompletionMode     = PostCompletionMode(rawValue: node.childText("PostCompletionMode", default: "HOLD")) ?? .hold

        if let oc = node.child(named: "OpacityChange") {
            s.opacityChange.enabled     = oc.boolAttr("enabled", default: false)
            s.opacityChange.kind        = ChangeKind(rawValue:   oc.childText("Kind",    default: "SEQ"))    ?? .sequential
            s.opacityChange.motion      = ChangeMotion(rawValue: oc.childText("Motion",  default: "UP"))     ?? .up
            s.opacityChange.cycle       = ChangeCycle(rawValue:  oc.childText("Cycle",   default: "CONSTANT")) ?? .constant
            s.opacityChange.scale       = ChangeScale(rawValue:  oc.childText("Scale",   default: "POLY"))   ?? .poly
            s.opacityChange.pauseMax    = oc.childInt("PauseMax", default: 0)
            if let sp = oc.child(named: "SizePalette") {
                s.opacityChange.sizePalette = sp.children(named: "Size").compactMap {
                    Double($0.text ?? "")
                }
            }
        }

        return s
    }

    // MARK: RendererChanges

    private static func parseRendererChanges(_ node: XMLNode) -> RendererChanges {
        let fill   = node.child(named: "FillColorChange").map   { parseFillColorChange($0) }
        let stroke = node.child(named: "StrokeColorChange").map { parseStrokeColorChange($0) }
        let width  = node.child(named: "StrokeWidthChange").map { parseStrokeWidthChange($0) }
        return RendererChanges(fillColor: fill, strokeColor: stroke, strokeWidth: width)
    }

    private static func parseChangeCommon(_ node: XMLNode)
        -> (enabled: Bool, kind: ChangeKind, motion: ChangeMotion,
            cycle: ChangeCycle, scale: ChangeScale, pauseMax: Int)
    {
        let enabled  = node.boolAttr("enabled", default: false)
        let kind     = ChangeKind(rawValue:   node.childText("Kind",   default: "RAN"))   ?? .random
        let motion   = ChangeMotion(rawValue: node.childText("Motion", default: "UP"))    ?? .up
        let cycle    = ChangeCycle(rawValue:  node.childText("Cycle",  default: "CONSTANT")) ?? .constant
        let scale    = ChangeScale(rawValue:  node.childText("Scale",  default: "POLY"))  ?? .poly
        let pauseMax = node.childInt("PauseMax")
        return (enabled, kind, motion, cycle, scale, pauseMax)
    }

    private static func parsePaletteColors(_ node: XMLNode) -> [LoomColor] {
        guard let palNode = node.child(named: "Palette") else { return [] }
        return palNode.children(named: "PaletteColor").map {
            LoomColor(r: $0.intAttr("r"), g: $0.intAttr("g"),
                      b: $0.intAttr("b"), a: $0.intAttr("a", default: 255))
        }
    }

    private static func parseSizePalette(_ node: XMLNode) -> [Double] {
        guard let palNode = node.child(named: "SizePalette") else { return [] }
        return palNode.children(named: "PaletteEntry").compactMap {
            Double($0.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func parseFillColorChange(_ node: XMLNode) -> FillColorChange {
        let c = parseChangeCommon(node)
        return FillColorChange(enabled: c.enabled, kind: c.kind, motion: c.motion,
                               cycle: c.cycle, scale: c.scale,
                               palette: parsePaletteColors(node), pauseMax: c.pauseMax)
    }

    private static func parseStrokeColorChange(_ node: XMLNode) -> StrokeColorChange {
        let c = parseChangeCommon(node)
        return StrokeColorChange(enabled: c.enabled, kind: c.kind, motion: c.motion,
                                 cycle: c.cycle, scale: c.scale,
                                 palette: parsePaletteColors(node), pauseMax: c.pauseMax)
    }

    private static func parseStrokeWidthChange(_ node: XMLNode) -> StrokeWidthChange {
        let c = parseChangeCommon(node)
        return StrokeWidthChange(enabled: c.enabled, kind: c.kind, motion: c.motion,
                                 cycle: c.cycle, scale: c.scale,
                                 sizePalette: parseSizePalette(node), pauseMax: c.pauseMax)
    }

    // MARK: SpriteConfig

    private static func parseSpriteConfig(_ root: XMLNode) -> SpriteConfig {
        let libNode = root.child(named: "SpriteLibrary") ?? root
        let libName = libNode.attr("name") ?? ""
        let sets = libNode.children(named: "SpriteSet").map { parseSpriteSet($0) }
        return SpriteConfig(library: SpriteLibrary(name: libName, spriteSets: sets))
    }

    private static func parseSpriteSet(_ node: XMLNode) -> SpriteSet {
        let name    = node.attr("name") ?? ""
        let sprites = node.children(named: "Sprite").map { parseSpriteDef($0) }
        return SpriteSet(name: name, sprites: sprites)
    }

    private static func parseSpriteDef(_ node: XMLNode) -> SpriteDef {
        let name = node.attr("name") ?? ""
        var def  = SpriteDef(name: name)

        if let shapeNode = node.child(named: "Shape") {
            def.shapeSetName = shapeNode.attr("shapeSet") ?? ""
            def.shapeName    = shapeNode.attr("name") ?? ""
        }
        if let rsNode = node.child(named: "RendererSet") {
            def.rendererSetName = rsNode.attr("name") ?? ""
        }
        if let posNode = node.child(named: "Position") {
            def.position = Vector2D(x: posNode.doubleAttr("x"), y: posNode.doubleAttr("y"))
        }
        if let scNode = node.child(named: "Scale") {
            def.scale = Vector2D(x: scNode.doubleAttr("x", default: 1),
                                 y: scNode.doubleAttr("y", default: 1))
        }
        def.rotation = node.childDouble("Rotation")
        if let animNode = node.child(named: "Animation") {
            def.animation = parseSpriteAnimation(animNode)
        }

        return def
    }

    // MARK: SpriteAnimation

    private static func parseSpriteAnimation(_ node: XMLNode) -> SpriteAnimation {
        let enabled  = node.boolAttr("enabled", default: false)
        let typeStr  = node.attr("type") ?? ""
        let type_    = AnimationType(rawValue: typeStr) ?? .random
        let loopStr  = node.attr("loopMode") ?? "LOOP"
        let loopMode = LoopMode(rawValue: loopStr) ?? .loop

        var anim = SpriteAnimation(
            enabled:    enabled,
            type:       type_,
            loopMode:   loopMode,
            totalDraws: node.childInt("TotalDraws")
        )

        // Transform ranges
        if let rn = node.child(named: "TranslationRange") {
            anim.translationRange = VectorRange(
                x: FloatRange(min: rn.doubleAttr("xMin"), max: rn.doubleAttr("xMax")),
                y: FloatRange(min: rn.doubleAttr("yMin"), max: rn.doubleAttr("yMax"))
            )
        }
        if let rn = node.child(named: "ScaleRange") {
            anim.scaleRange = VectorRange(
                x: FloatRange(min: rn.doubleAttr("xMin"), max: rn.doubleAttr("xMax")),
                y: FloatRange(min: rn.doubleAttr("yMin"), max: rn.doubleAttr("yMax"))
            )
        }
        if let rn = node.child(named: "RotationRange") {
            anim.rotationRange = FloatRange(min: rn.doubleAttr("min"), max: rn.doubleAttr("max"))
        }

        // Keyframes
        if let kfsNode = node.child(named: "Keyframes") {
            anim.keyframes = kfsNode.children(named: "Keyframe").map { kn in
                Keyframe(
                    drawCycle:   kn.intAttr("drawCycle"),
                    position:    Vector2D(x: kn.doubleAttr("posX"), y: kn.doubleAttr("posY")),
                    scale:       Vector2D(x: kn.doubleAttr("scaleX", default: 1),
                                          y: kn.doubleAttr("scaleY", default: 1)),
                    rotation:    kn.doubleAttr("rotation"),
                    easing:      EasingType(rawValue: kn.attr("easing") ?? "") ?? .linear,
                    morphAmount: kn.doubleAttr("morphAmount")
                )
            }
        }

        // Morph targets — morphMin/morphMax sit as attributes on <MorphTargets>
        if let mtNode = node.child(named: "MorphTargets") {
            anim.morphMin     = mtNode.doubleAttr("morphMin")
            anim.morphMax     = mtNode.doubleAttr("morphMax")
            anim.morphTargets = mtNode.children(named: "MorphTarget").map {
                MorphTargetRef(file: $0.attr("file") ?? "")
            }
        }

        return anim
    }
}

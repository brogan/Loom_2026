/// Resolved, runtime form of a `SpriteDef` with loaded geometry and live state.
///
/// Created by `SpriteScene` from a `ProjectConfig`.  All name-references in the
/// source config have been resolved to concrete values; polygon files have been
/// read from disk.
public struct SpriteInstance: Sendable {

    /// Name of the sprite set this instance belongs to.  Set by `SpriteScene.init`.
    public var spriteSetName: String = ""

    /// The original sprite definition from `sprites.xml`.
    public var def: SpriteDef

    /// Polygons loaded from the polygon-set file referenced by the sprite's shape.
    /// Empty when the source type is unsupported or the file was not found.
    public var basePolygons: [Polygon2D]

    /// Loaded morph-target geometry.  Parallel to `def.animation.morphTargets`;
    /// each inner array is one target's polygon set (same count and point layout as
    /// `basePolygons`).
    public var morphTargetPolygons: [[Polygon2D]]

    /// Resolved renderer set.  Falls back to a single default renderer when the
    /// named set is absent from the config.
    public var rendererSet: RendererSet

    /// Ordered subdivision parameters applied each frame.
    /// Empty when the shape has no subdivision params set, or when the params set
    /// name is "none".
    public var subdivisionParams: [SubdivisionParams]

    /// Ordered curve-refinement passes applied to `.openSpline` polygons each frame.
    /// Empty when the set has no curve-refinement entries.
    public var curveRefinementParams: [CurveRefinementParams]

    /// Ordered segment-extraction passes applied after curve refinement each frame.
    /// Empty when the set has no segment-extraction entries.
    public var segmentExtractionParams: [SegmentExtractionParams]

    /// Ordered extension passes (branching / edge extrusion) applied after segment extraction.
    /// Empty when the set has no extension entries.
    public var extensionParams: [ExtensionParams]

    /// Ordered convolution passes (torsion / shear) applied after Extension, before
    /// Generational Evolution. Empty when the set has no convolution entries.
    public var convolutionParams: [ConvolutionParams]

    /// Ordered evolution passes applied to subdivision params before SubdivisionEngine runs.
    /// Empty when the set has no evolution entries.
    public var evolutionParams: [EvolutionParams]

    /// Ordered fulguration passes (frame-cycle visibility/transform/development)
    /// applied to output polygons after Generational Evolution, before Dissolution.
    /// Empty when the set has no fulguration entries.
    public var fulgurationParams: [FulgurationParams]

    /// Ordered dissolution passes applied to output polygons after all other pipeline stages.
    /// Empty when the set has no dissolution entries.
    public var dissolutionParams: [DissolutionParams]

    /// Polygon sets for `SpriteDef.shapeSequence` cycling (parallel to
    /// `def.shapeSequence.shapeSetNames`).  Empty when no sequence is configured.
    public var sequencePolygons: [[Polygon2D]]

    /// Resolved geometry for each entry in `def.spriteVariants`.
    /// Parallel to `def.spriteVariants`; index 0 = first named variant.
    public var variantPolygons: [[Polygon2D]]

    /// Resolved renderer sets for each entry in `def.spriteVariants`.
    /// Parallel to `def.spriteVariants`; index 0 = first named variant.
    public var variantRendererSets: [RendererSet]

    /// Optional override image filename for each variant (mirrors `def.spriteVariants[i].imageFilename`).
    /// `nil` at index i means that variant uses its geometry/renderer set instead.
    /// Parallel to `variantPolygons`.
    public var variantImageFilenames: [String?]

    // MARK: SpriteCycle runtime data

    /// Polygon sets for each `SpriteCycleState` in the assigned cycle.
    /// Parallel to `cycle.states`. Empty when no cycle is assigned.
    public var cycleStatePolygons: [[Polygon2D]]

    /// Resolved renderer sets for each cycle state. `nil` = inherit sprite's renderer.
    /// Parallel to `cycleStatePolygons`.
    public var cycleStateRendererSets: [RendererSet?]

    /// Pre-loaded geometry for cycles referenced by the `cycleNameDriver`.
    /// Keyed by cycle name. Populated at scene init for any cycle name that
    /// appears in the driver's keyframes so geometry is ready at render time.
    public var driverCycleData: [String: CycleRenderData] = [:]

    /// Mutable per-frame state (updated by `SpriteScene.advance`).
    public var state: SpriteState

    public init(
        def: SpriteDef,
        basePolygons: [Polygon2D],
        morphTargetPolygons: [[Polygon2D]],
        rendererSet: RendererSet,
        subdivisionParams: [SubdivisionParams],
        curveRefinementParams: [CurveRefinementParams] = [],
        segmentExtractionParams: [SegmentExtractionParams] = [],
        extensionParams: [ExtensionParams] = [],
        convolutionParams: [ConvolutionParams] = [],
        evolutionParams: [EvolutionParams] = [],
        fulgurationParams: [FulgurationParams] = [],
        dissolutionParams: [DissolutionParams] = [],
        sequencePolygons: [[Polygon2D]] = [],
        variantPolygons: [[Polygon2D]] = [],
        variantRendererSets: [RendererSet] = [],
        variantImageFilenames: [String?] = [],
        cycleStatePolygons: [[Polygon2D]] = [],
        cycleStateRendererSets: [RendererSet?] = [],
        driverCycleData: [String: CycleRenderData] = [:],
        state: SpriteState
    ) {
        self.def                    = def
        self.basePolygons           = basePolygons
        self.morphTargetPolygons    = morphTargetPolygons
        self.rendererSet            = rendererSet
        self.subdivisionParams      = subdivisionParams
        self.curveRefinementParams   = curveRefinementParams
        self.segmentExtractionParams = segmentExtractionParams
        self.extensionParams         = extensionParams
        self.convolutionParams       = convolutionParams
        self.evolutionParams         = evolutionParams
        self.fulgurationParams       = fulgurationParams
        self.dissolutionParams       = dissolutionParams
        self.sequencePolygons        = sequencePolygons
        self.variantPolygons        = variantPolygons
        self.variantRendererSets    = variantRendererSets
        self.variantImageFilenames  = variantImageFilenames
        self.cycleStatePolygons     = cycleStatePolygons
        self.cycleStateRendererSets = cycleStateRendererSets
        self.driverCycleData        = driverCycleData
        self.state                  = state
    }
}

// MARK: - CycleRenderData

/// Pre-loaded geometry for one SpriteCycle, keyed by cycle name in
/// `SpriteInstance.driverCycleData`. Mirrors the per-state arrays on
/// `SpriteInstance` but scoped to a single named cycle.
public struct CycleRenderData: Sendable {
    public var statePolygons:     [[Polygon2D]]
    public var stateRendererSets: [RendererSet?]

    public init(statePolygons: [[Polygon2D]], stateRendererSets: [RendererSet?]) {
        self.statePolygons     = statePolygons
        self.stateRendererSets = stateRendererSets
    }
}

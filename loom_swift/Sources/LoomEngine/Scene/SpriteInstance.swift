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

    /// Polygon sets for `SpriteDef.shapeSequence` cycling (parallel to
    /// `def.shapeSequence.shapeSetNames`).  Empty when no sequence is configured.
    public var sequencePolygons: [[Polygon2D]]

    /// Resolved geometry for each entry in `def.spriteVariants`.
    /// Parallel to `def.spriteVariants`; index 0 = first named variant.
    public var variantPolygons: [[Polygon2D]]

    /// Resolved renderer sets for each entry in `def.spriteVariants`.
    /// Parallel to `def.spriteVariants`; index 0 = first named variant.
    public var variantRendererSets: [RendererSet]

    // MARK: SpriteCycle runtime data

    /// Polygon sets for each `SpriteCycleState` in the assigned cycle.
    /// Parallel to `cycle.states`. Empty when no cycle is assigned.
    public var cycleStatePolygons: [[Polygon2D]]

    /// Resolved renderer sets for each cycle state. `nil` = inherit sprite's renderer.
    /// Parallel to `cycleStatePolygons`.
    public var cycleStateRendererSets: [RendererSet?]

    /// Mutable per-frame state (updated by `SpriteScene.advance`).
    public var state: SpriteState

    public init(
        def: SpriteDef,
        basePolygons: [Polygon2D],
        morphTargetPolygons: [[Polygon2D]],
        rendererSet: RendererSet,
        subdivisionParams: [SubdivisionParams],
        sequencePolygons: [[Polygon2D]] = [],
        variantPolygons: [[Polygon2D]] = [],
        variantRendererSets: [RendererSet] = [],
        cycleStatePolygons: [[Polygon2D]] = [],
        cycleStateRendererSets: [RendererSet?] = [],
        state: SpriteState
    ) {
        self.def                    = def
        self.basePolygons           = basePolygons
        self.morphTargetPolygons    = morphTargetPolygons
        self.rendererSet            = rendererSet
        self.subdivisionParams      = subdivisionParams
        self.sequencePolygons       = sequencePolygons
        self.variantPolygons        = variantPolygons
        self.variantRendererSets    = variantRendererSets
        self.cycleStatePolygons     = cycleStatePolygons
        self.cycleStateRendererSets = cycleStateRendererSets
        self.state                  = state
    }
}

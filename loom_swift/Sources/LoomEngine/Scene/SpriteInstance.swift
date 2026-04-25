/// Resolved, runtime form of a `SpriteDef` with loaded geometry and live state.
///
/// Created by `SpriteScene` from a `ProjectConfig`.  All name-references in the
/// source config have been resolved to concrete values; polygon files have been
/// read from disk.
public struct SpriteInstance: Sendable {

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

    /// Mutable per-frame state (updated by `SpriteScene.advance`).
    public var state: SpriteState

    public init(
        def: SpriteDef,
        basePolygons: [Polygon2D],
        morphTargetPolygons: [[Polygon2D]],
        rendererSet: RendererSet,
        subdivisionParams: [SubdivisionParams],
        state: SpriteState
    ) {
        self.def                  = def
        self.basePolygons         = basePolygons
        self.morphTargetPolygons  = morphTargetPolygons
        self.rendererSet          = rendererSet
        self.subdivisionParams    = subdivisionParams
        self.state                = state
    }
}

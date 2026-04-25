/// Per-sprite mutable runtime state — updated each frame by `SpriteScene.advance`.
public struct SpriteState: Equatable, Sendable {

    /// Absolute frame counter.  Starts at 0; incremented at the end of each `advance`.
    /// Used for palette stepping and renderer hold-length counting.
    public var drawCycle: Int

    /// Accumulated wall-clock time in seconds since this sprite started animating.
    /// Used by `TransformAnimator` for time-based keyframe interpolation.
    public var elapsedTime: Double

    /// Fractional time (seconds) accumulated toward the next virtual frame boundary.
    /// When this reaches `1/targetFPS` the discrete per-frame events fire:
    /// renderer switching, palette stepping, and `drawCycle` increment.
    public var frameTimeAccumulator: Double

    /// Resolved animation transform for the current cycle.
    /// Computed at the beginning of `advance` before `drawCycle` is incremented.
    public var transform: SpriteTransform

    /// Index of the active renderer within the sprite's `RendererSet.renderers` array.
    public var activeRendererIndex: Int

    /// Frames remaining on the current renderer before the sequential playback advances.
    /// Decremented each `advance`; reset to `renderer.holdLength` when a new renderer
    /// becomes active.  Ignored in `.static`, `.random`, and `.all` modes.
    public var holdFramesRemaining: Int

    /// Palette-animation states — one element per renderer in the set.
    public var rendererAnimationStates: [RendererAnimationState]

    public init(
        drawCycle:               Int                      = 0,
        elapsedTime:             Double                   = 0.0,
        frameTimeAccumulator:    Double                   = 0.0,
        transform:               SpriteTransform          = .identity,
        activeRendererIndex:     Int                      = 0,
        holdFramesRemaining:     Int                      = 1,
        rendererAnimationStates: [RendererAnimationState] = []
    ) {
        self.drawCycle               = drawCycle
        self.elapsedTime             = elapsedTime
        self.frameTimeAccumulator    = frameTimeAccumulator
        self.transform               = transform
        self.activeRendererIndex     = activeRendererIndex
        self.holdFramesRemaining     = holdFramesRemaining
        self.rendererAnimationStates = rendererAnimationStates
    }

    // MARK: - Factory

    /// Build an initial state from a renderer set's configuration.
    public static func initial(for rendererSet: RendererSet) -> SpriteState {
        let animStates = rendererSet.renderers.map { r in
            RendererAnimationState.initial(for: r)
        }

        // STATIC mode: try to start on the named preferred renderer.
        let startIndex: Int
        if rendererSet.playbackConfig.mode == .static,
           !rendererSet.playbackConfig.preferredRenderer.isEmpty,
           let found = rendererSet.renderers.firstIndex(where: {
               $0.name == rendererSet.playbackConfig.preferredRenderer
           }) {
            startIndex = found
        } else {
            startIndex = 0
        }

        let safeIndex = rendererSet.renderers.isEmpty
            ? 0
            : min(startIndex, rendererSet.renderers.count - 1)

        let holdLength = rendererSet.renderers.isEmpty
            ? 1
            : rendererSet.renderers[safeIndex].holdLength

        return SpriteState(
            drawCycle:               0,
            transform:               .identity,
            activeRendererIndex:     safeIndex,
            holdFramesRemaining:     holdLength,
            rendererAnimationStates: animStates
        )
    }
}

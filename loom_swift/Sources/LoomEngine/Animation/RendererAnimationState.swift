/// Tracks the current palette-index position for one animated render parameter.
///
/// Used by `RenderStateEngine` to advance fill-colour, stroke-colour, and
/// stroke-width palettes independently.
public struct PaletteIndexState: Equatable, Sendable {

    /// Current palette index.
    public var index: Int

    /// Frames remaining before the index advances again (PAUSING cycle only).
    public var pauseRemaining: Int

    /// Advance direction for PING_PONG motion (+1 or −1).
    public var direction: Int

    public init(index: Int = 0, pauseRemaining: Int = 0, direction: Int = 1) {
        self.index          = index
        self.pauseRemaining = pauseRemaining
        self.direction      = direction
    }
}

/// Snapshot of the palette-index state for all animated render parameters
/// within a single `Renderer`.
///
/// `nil` means the corresponding change is absent or disabled — the parameter
/// stays at the renderer's static value.
public struct RendererAnimationState: Equatable, Sendable {

    public var fillColorState:      PaletteIndexState?
    public var strokeColorState:    PaletteIndexState?
    public var strokeWidthState:    PaletteIndexState?
    /// Non-nil when the renderer is `.stamped`/`.stenciled` and `opacityChange` is enabled.
    public var stencilOpacityState: PaletteIndexState?

    public init(
        fillColorState:      PaletteIndexState? = nil,
        strokeColorState:    PaletteIndexState? = nil,
        strokeWidthState:    PaletteIndexState? = nil,
        stencilOpacityState: PaletteIndexState? = nil
    ) {
        self.fillColorState      = fillColorState
        self.strokeColorState    = strokeColorState
        self.strokeWidthState    = strokeWidthState
        self.stencilOpacityState = stencilOpacityState
    }

    /// Build an initial (index = 0) state from a `RendererChanges` description.
    /// Use `initial(for:)` taking a full `Renderer` when stencil opacity animation is needed.
    public static func initial(for changes: RendererChanges) -> RendererAnimationState {
        RendererAnimationState(
            fillColorState:   changes.fillColor.map   { _ in PaletteIndexState() },
            strokeColorState: changes.strokeColor.map { _ in PaletteIndexState() },
            strokeWidthState: changes.strokeWidth.map { _ in PaletteIndexState() }
        )
    }

    /// Build an initial state from a full `Renderer`, including stencil opacity animation.
    public static func initial(for renderer: Renderer) -> RendererAnimationState {
        var state = initial(for: renderer.changes)
        if let sc = renderer.stencilConfig,
           sc.opacityChange.enabled,
           !sc.opacityChange.sizePalette.isEmpty {
            state.stencilOpacityState = PaletteIndexState()
        }
        return state
    }
}

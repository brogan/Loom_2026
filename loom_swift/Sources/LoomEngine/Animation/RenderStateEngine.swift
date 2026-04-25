import Foundation

/// Applies and advances `RendererAnimationState` for palette-driven render changes.
///
/// Two operations:
/// - `resolve` — return a copy of `renderer` with live palette values substituted.
/// - `advance` — return a new `RendererAnimationState` stepped one frame forward.
public enum RenderStateEngine {

    // MARK: - Resolve

    /// Return a copy of `renderer` with animated palette values applied from `state`.
    ///
    /// Fields whose corresponding change is absent, disabled, or has an out-of-range
    /// index are left at the renderer's static value.
    public static func resolve(
        renderer: Renderer,
        state: RendererAnimationState,
        changes: RendererChanges
    ) -> Renderer {
        var r = renderer

        if let change = changes.fillColor, change.enabled,
           let s = state.fillColorState, s.index < change.palette.count {
            r.fillColor = change.palette[s.index]
        }

        if let change = changes.strokeColor, change.enabled,
           let s = state.strokeColorState, s.index < change.palette.count {
            r.strokeColor = change.palette[s.index]
        }

        if let change = changes.strokeWidth, change.enabled,
           let s = state.strokeWidthState, s.index < change.sizePalette.count {
            r.strokeWidth = change.sizePalette[s.index]
        }

        return r
    }

    // MARK: - Advance

    /// Return a new `RendererAnimationState` stepped one frame forward.
    ///
    /// Pass `stencilConfig` for `.stamped`/`.stenciled` renderers so that
    /// the `opacityChange` palette index advances alongside stroke/fill changes.
    public static func advance<RNG: RandomNumberGenerator>(
        state: RendererAnimationState,
        changes: RendererChanges,
        stencilConfig: StencilConfig? = nil,
        using rng: inout RNG
    ) -> RendererAnimationState {
        let oc = stencilConfig?.opacityChange
        return RendererAnimationState(
            fillColorState:   advanceState(state.fillColorState,
                                           change: changes.fillColor,
                                           paletteCount: changes.fillColor?.palette.count ?? 0,
                                           using: &rng),
            strokeColorState: advanceState(state.strokeColorState,
                                           change: changes.strokeColor,
                                           paletteCount: changes.strokeColor?.palette.count ?? 0,
                                           using: &rng),
            strokeWidthState: advanceState(state.strokeWidthState,
                                           change: changes.strokeWidth,
                                           paletteCount: changes.strokeWidth?.sizePalette.count ?? 0,
                                           using: &rng),
            stencilOpacityState: advanceState(state.stencilOpacityState,
                                              change: oc,
                                              paletteCount: oc?.sizePalette.count ?? 0,
                                              using: &rng)
        )
    }

    // MARK: - Per-parameter advance

    private static func advanceState<C: ChangeProtocol, RNG: RandomNumberGenerator>(
        _ current: PaletteIndexState?,
        change: C?,
        paletteCount: Int,
        using rng: inout RNG
    ) -> PaletteIndexState? {
        guard let current, let change, change.isEnabled, paletteCount > 0 else {
            return current
        }

        // RAN kind: pick any index at random, ignoring motion.
        if change.changeKind == .random {
            let newIndex = Int.random(in: 0..<paletteCount, using: &rng)
            return PaletteIndexState(index: newIndex,
                                     pauseRemaining: current.pauseRemaining,
                                     direction: current.direction)
        }

        // PAUSING cycle: burn a pause frame if one is pending.
        if change.changeCycle == .pausing && current.pauseRemaining > 0 {
            return PaletteIndexState(index: current.index,
                                     pauseRemaining: current.pauseRemaining - 1,
                                     direction: current.direction)
        }

        // Step the index according to motion.
        var newIndex     = current.index
        var newDirection = current.direction

        switch change.changeMotion {
        case .up:
            newIndex = (current.index + 1) % paletteCount

        case .down:
            newIndex = (current.index - 1 + paletteCount) % paletteCount

        case .pingPong:
            let next = current.index + current.direction
            if next >= paletteCount {
                newDirection = -1
                newIndex = max(0, paletteCount - 2)
            } else if next < 0 {
                newDirection = +1
                newIndex = min(1, paletteCount - 1)
            } else {
                newIndex = next
            }
        }

        // PAUSING cycle: assign a new random pause after stepping.
        var newPause = 0
        if change.changeCycle == .pausing && change.pauseMaxValue > 0 {
            newPause = Int.random(in: 0...change.pauseMaxValue, using: &rng)
        }

        return PaletteIndexState(index: newIndex,
                                 pauseRemaining: newPause,
                                 direction: newDirection)
    }
}

// MARK: - Change protocol

/// Internal protocol so `advanceState` can be generic over the three change types.
private protocol ChangeProtocol {
    var isEnabled:     Bool         { get }
    var changeKind:    ChangeKind   { get }
    var changeMotion:  ChangeMotion { get }
    var changeCycle:   ChangeCycle  { get }
    var pauseMaxValue: Int          { get }
}

extension FillColorChange: ChangeProtocol {
    var isEnabled:     Bool         { enabled }
    var changeKind:    ChangeKind   { kind }
    var changeMotion:  ChangeMotion { motion }
    var changeCycle:   ChangeCycle  { cycle }
    var pauseMaxValue: Int          { pauseMax }
}

extension StrokeColorChange: ChangeProtocol {
    var isEnabled:     Bool         { enabled }
    var changeKind:    ChangeKind   { kind }
    var changeMotion:  ChangeMotion { motion }
    var changeCycle:   ChangeCycle  { cycle }
    var pauseMaxValue: Int          { pauseMax }
}

extension StrokeWidthChange: ChangeProtocol {
    var isEnabled:     Bool         { enabled }
    var changeKind:    ChangeKind   { kind }
    var changeMotion:  ChangeMotion { motion }
    var changeCycle:   ChangeCycle  { cycle }
    var pauseMaxValue: Int          { pauseMax }
}

extension StencilOpacityChange: ChangeProtocol {
    var isEnabled:     Bool         { enabled }
    var changeKind:    ChangeKind   { kind }
    var changeMotion:  ChangeMotion { motion }
    var changeCycle:   ChangeCycle  { cycle }
    var pauseMaxValue: Int          { pauseMax }
}

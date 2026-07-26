import Foundation

/// The `TransformDrivers` fields a Live-tab session can toggle on/off for a
/// staged sprite instance — see `LoomEngine.setDriverEnabled`.
public enum LiveDriverKey: String, CaseIterable, Sendable {
    case position, scale, rotation, morph, opacity, shape
    case subdivisionSet, rendererSet, cycleName

    /// This field's current `enabled` flag within `drivers`.
    public func enabled(in drivers: TransformDrivers) -> Bool {
        switch self {
        case .position:       return drivers.position.enabled
        case .scale:          return drivers.scale.enabled
        case .rotation:       return drivers.rotation.enabled
        case .morph:          return drivers.morph.enabled
        case .opacity:        return drivers.opacity.enabled
        case .shape:          return drivers.shape.enabled
        case .subdivisionSet: return drivers.subdivisionSet.enabled
        case .rendererSet:    return drivers.rendererSet.enabled
        case .cycleName:      return drivers.cycleName.enabled
        }
    }

    /// Whether this field differs from `TransformDrivers.identity` — i.e.
    /// whether the project's own sprite authoring actually set this driver
    /// up (enabled or not) rather than leaving it at its untouched default.
    /// Used by the Live tab to show only drivers relevant to a given sprite,
    /// rather than all 9 possible driver slots regardless of whether the
    /// project uses them.
    public func isConfigured(in drivers: TransformDrivers) -> Bool {
        let identity = TransformDrivers.identity
        switch self {
        case .position:       return drivers.position != identity.position
        case .scale:          return drivers.scale != identity.scale
        case .rotation:       return drivers.rotation != identity.rotation
        case .morph:          return drivers.morph != identity.morph
        case .opacity:        return drivers.opacity != identity.opacity
        case .shape:          return drivers.shape != identity.shape
        case .subdivisionSet: return drivers.subdivisionSet != identity.subdivisionSet
        case .rendererSet:    return drivers.rendererSet != identity.rendererSet
        case .cycleName:      return drivers.cycleName != identity.cycleName
        }
    }
}

// MARK: - Rate/Range application

public extension DoubleDriver {
    /// Applies the Live tab's generalized Rate/Range controls to this
    /// driver's mode-appropriate fields — `freqHz` (oscillator) or `period`
    /// (noise) for rate, `amplitude` (oscillator/noise) or `range` (jitter)
    /// for range — leaving fields the current mode doesn't use untouched.
    /// Shared by `LoomEngine.updateDoubleDriverRateRange` (the live path)
    /// and the Live tab's "save to sprite" action, which applies the
    /// identical mapping to a project's saved `SpriteDef` so the two stay
    /// in lockstep by construction rather than by convention.
    mutating func applyRateRange(rate: Double? = nil, range: Double? = nil) {
        if let rate {
            switch mode {
            case .oscillator: freqHz = max(0, rate)
            case .noise:      period = max(1, Int(rate.rounded()))
            default: break
            }
        }
        if let range {
            switch mode {
            case .oscillator, .noise: amplitude = max(0, range)
            case .jitter:             self.range = max(0, range)
            default: break
            }
        }
    }
}

public extension VectorDriver {
    /// Vector counterpart of `DoubleDriver.applyRateRange` — see its doc
    /// comment. Noise mode's `period` is a single shared value (not
    /// per-axis), so only `rateX` is consulted for it; `rateY` is ignored.
    mutating func applyRateRange(
        rateX: Double? = nil, rateY: Double? = nil, rangeX: Double? = nil, rangeY: Double? = nil
    ) {
        if rateX != nil || rateY != nil {
            switch mode {
            case .oscillator:
                if let rateX { freqHz.x = max(0, rateX) }
                if let rateY { freqHz.y = max(0, rateY) }
            case .noise:
                if let rateX { period = max(1, Int(rateX.rounded())) }
            default: break
            }
        }
        if rangeX != nil || rangeY != nil {
            switch mode {
            case .oscillator, .noise:
                if let rangeX { amplitude.x = max(0, rangeX) }
                if let rangeY { amplitude.y = max(0, rangeY) }
            case .jitter:
                if let rangeX { range.x = max(0, rangeX) }
                if let rangeY { range.y = max(0, rangeY) }
            default: break
            }
        }
    }
}

/// Errors raised by `LoomEngine`'s live-staging mutators
/// (`showSprite`/`updatePose`/`updateRendererSet`/`updateSubdivisionSet`/
/// `setDriverEnabled`) — see `LoomLiveV1Scope.md` §2.1.
public enum LiveStagingError: Error, LocalizedError, Sendable {
    case spriteNotFound(spriteSet: String, sprite: String)
    case instanceNotFound(String)
    case rendererSetNotFound(String)
    case subdivisionSetNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .spriteNotFound(let spriteSet, let sprite):
            return "Sprite '\(sprite)' not found in sprite set '\(spriteSet)'."
        case .instanceNotFound(let name):
            return "No staged instance named '\(name)'."
        case .rendererSetNotFound(let name):
            return "Renderer set '\(name)' not found."
        case .subdivisionSetNotFound(let name):
            return "Transform set '\(name)' not found."
        }
    }
}

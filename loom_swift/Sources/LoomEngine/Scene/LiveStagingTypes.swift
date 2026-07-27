import Foundation

/// Common shape of `DoubleDriver`/`VectorDriver`/`ColorDriver`/`NameDriver` —
/// each independently declares its own `enabled` flag with no shared
/// protocol; this lets the Live tab's engine mutators (`setDriverEnabled`)
/// operate generically over any of them via a `WritableKeyPath`, rather than
/// needing one method per driver value type.
public protocol AnyLiveDriver: Sendable {
    var enabled: Bool { get set }
}
extension DoubleDriver: AnyLiveDriver {}
extension VectorDriver: AnyLiveDriver {}
extension ColorDriver: AnyLiveDriver {}
extension NameDriver: AnyLiveDriver {}

// MARK: - Rate/Range application

public extension DoubleDriver {
    /// Applies the Live tab's generalized Rate/Range controls to this
    /// driver's mode-appropriate fields — `freqHz` (oscillator) or `period`
    /// (noise) for rate, `amplitude` (oscillator/noise) or `range` (jitter)
    /// for range — leaving fields the current mode doesn't use untouched.
    /// Shared by `LoomEngine.updateDoubleDriverRateRange` (the live path)
    /// and the Live tab's "save to sprite/set" actions, which apply the
    /// identical mapping to a project's saved config so the two stay in
    /// lockstep by construction rather than by convention.
    ///
    /// `phase` (0–1, oscillator's phase offset) applies unconditionally —
    /// unlike rate/range it isn't mode-gated, since jitter/noise simply
    /// don't read it (harmlessly stored, not evaluated). Used by BPM-linked
    /// musical rate (`LoomLiveV1Scope.md` §2.6) to align a cycle's start to
    /// a tapped downbeat; the plain manual Rate/Range sliders never pass it.
    mutating func applyRateRange(rate: Double? = nil, range: Double? = nil, phase: Double? = nil) {
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
        if let phase { self.phase = phase }
    }
}

public extension VectorDriver {
    /// Vector counterpart of `DoubleDriver.applyRateRange` — see its doc
    /// comment. Noise mode's `period` is a single shared value (not
    /// per-axis), so only `rateX` is consulted for it; `rateY` is ignored.
    mutating func applyRateRange(
        rateX: Double? = nil, rateY: Double? = nil, rangeX: Double? = nil, rangeY: Double? = nil,
        phaseX: Double? = nil, phaseY: Double? = nil
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
        if let phaseX { phase.x = phaseX }
        if let phaseY { phase.y = phaseY }
    }
}

public extension ColorDriver {
    /// `DoubleDriver.applyRateRange`'s counterpart for `ColorDriver` — same
    /// field names (`freqHz`/`period`/`amplitude`/`range`), same mode
    /// mapping. Only oscillator/noise/jitter are covered; `.sequential`/
    /// `.random` (palette-stepping modes) use `period`/`weights` for a
    /// different purpose and aren't addressed by this generalized control.
    mutating func applyRateRange(rate: Double? = nil, range: Double? = nil, phase: Double? = nil) {
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
        if let phase { self.phase = phase }
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

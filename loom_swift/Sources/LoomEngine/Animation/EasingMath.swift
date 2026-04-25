import Foundation

/// Pure easing functions for keyframe interpolation.
///
/// All functions accept a normalised progress value `t ∈ [0, 1]` and return
/// an eased value in the same range.  Values outside `[0, 1]` are not clamped —
/// callers are responsible for supplying a valid `t`.
public enum EasingMath {

    /// Apply `type` easing to a normalised progress value.
    public static func ease(_ t: Double, type: EasingType) -> Double {
        switch type {
        case .linear:          return t
        case .easeInQuad:      return easeInQuad(t)
        case .easeOutQuad:     return easeOutQuad(t)
        case .easeInOutQuad:   return easeInOutQuad(t)
        case .easeInCubic:     return easeInCubic(t)
        case .easeOutCubic:    return easeOutCubic(t)
        case .easeInOutCubic:  return easeInOutCubic(t)
        }
    }

    // MARK: - Quadratic

    private static func easeInQuad(_ t: Double) -> Double {
        t * t
    }

    private static func easeOutQuad(_ t: Double) -> Double {
        t * (2 - t)
    }

    private static func easeInOutQuad(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
    }

    // MARK: - Cubic

    private static func easeInCubic(_ t: Double) -> Double {
        t * t * t
    }

    private static func easeOutCubic(_ t: Double) -> Double {
        let u = t - 1
        return u * u * u + 1
    }

    private static func easeInOutCubic(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
    }
}

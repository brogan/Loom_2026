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
        case .easeInSine:      return easeInSine(t)
        case .easeOutSine:     return easeOutSine(t)
        case .easeInOutSine:   return easeInOutSine(t)
        case .easeInExpo:      return easeInExpo(t)
        case .easeOutExpo:     return easeOutExpo(t)
        case .easeInOutExpo:   return easeInOutExpo(t)
        case .easeInBack:      return easeInBack(t)
        case .easeOutBack:     return easeOutBack(t)
        case .easeInOutBack:   return easeInOutBack(t)
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

    // MARK: - Sine

    private static func easeInSine(_ t: Double) -> Double {
        1 - cos(t * .pi / 2)
    }

    private static func easeOutSine(_ t: Double) -> Double {
        sin(t * .pi / 2)
    }

    private static func easeInOutSine(_ t: Double) -> Double {
        -(cos(.pi * t) - 1) / 2
    }

    // MARK: - Exponential

    private static func easeInExpo(_ t: Double) -> Double {
        t == 0 ? 0 : pow(2, 10 * t - 10)
    }

    private static func easeOutExpo(_ t: Double) -> Double {
        t == 1 ? 1 : 1 - pow(2, -10 * t)
    }

    private static func easeInOutExpo(_ t: Double) -> Double {
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        return t < 0.5
            ? pow(2, 20 * t - 10) / 2
            : (2 - pow(2, -20 * t + 10)) / 2
    }

    // MARK: - Back (overshoot)

    private static let backC1: Double = 1.70158
    private static let backC2: Double = backC1 * 1.525
    private static let backC3: Double = backC1 + 1

    private static func easeInBack(_ t: Double) -> Double {
        backC3 * t * t * t - backC1 * t * t
    }

    private static func easeOutBack(_ t: Double) -> Double {
        let u = t - 1
        return 1 + backC3 * u * u * u + backC1 * u * u
    }

    private static func easeInOutBack(_ t: Double) -> Double {
        if t < 0.5 {
            let u = 2 * t
            return (u * u * ((backC2 + 1) * u - backC2)) / 2
        } else {
            let u = 2 * t - 2
            return (u * u * ((backC2 + 1) * u + backC2) + 2) / 2
        }
    }
}

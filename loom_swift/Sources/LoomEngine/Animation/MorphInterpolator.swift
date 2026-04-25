/// Blends polygon geometry between a base shape and one or two morph targets.
///
/// `morphAmount` encoding (matches `Keyframe.morphAmount`):
/// - `0`   → pure base geometry.
/// - `1`   → pure `targets[0]`.
/// - `1.5` → 50 % blend between `targets[0]` and `targets[1]`.
/// - `2`   → pure `targets[1]`.
///
/// The integer part of `morphAmount` selects the *from* source
/// (0 = base, 1 = targets[0], …) and the fractional part is the blend
/// fraction toward the next integer source.
///
/// Point counts must match between base and every target; mismatched
/// targets are silently ignored and the base is returned unchanged.
public enum MorphInterpolator {

    /// Interpolate polygon geometry according to `morphAmount`.
    ///
    /// - Parameters:
    ///   - base:        The unmodified base polygons.
    ///   - targets:     Ordered morph-target polygon arrays (same structure as `base`).
    ///   - morphAmount: Blend value in `[0, targets.count]`; clamped to that range.
    /// - Returns:       A new array of `Polygon2D` with interpolated point positions.
    ///                  `type`, `pressures`, and `visible` are preserved from `base`.
    public static func interpolate(
        base: [Polygon2D],
        targets: [[Polygon2D]],
        morphAmount: Double
    ) -> [Polygon2D] {
        guard !targets.isEmpty else { return base }

        let maxAmount = Double(targets.count)
        let clamped   = max(0, min(maxAmount, morphAmount))

        let phase = Int(clamped)
        let t     = clamped - Double(phase)

        // Determine `from` and `to` polygon arrays.
        let from: [Polygon2D]
        let to:   [Polygon2D]

        if phase == 0 {
            from = base
            to   = targets[0]
        } else if phase >= targets.count {
            // Fully at the last target.
            return targets[targets.count - 1]
        } else {
            from = targets[phase - 1]
            to   = targets[phase]
        }

        // t == 0: return `from` unchanged.
        guard t > 0 else { return from }

        // Blend point-by-point.  Mismatched polygon counts fall back to base.
        guard from.count == to.count else { return base }

        return zip(from, to).map { (f, tgt) -> Polygon2D in
            guard f.points.count == tgt.points.count else { return f }
            let blended = zip(f.points, tgt.points).map { (fp, tp) in
                Vector2D.lerp(fp, tp, t: t)
            }
            return Polygon2D(
                points:    blended,
                type:      f.type,
                pressures: f.pressures,
                visible:   f.visible
            )
        }
    }
}

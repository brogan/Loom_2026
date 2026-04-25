import Foundation

/// Generates a star/regular polygon from `RegularPolygonParams`.
///
/// Matches the Scala `PolygonCreator.makePolygon2DStar` algorithm:
///   - `totalPoints` outer tips alternating with `totalPoints` inner points
///     → `totalPoints * 2` vertices total.
///   - Outer radius = 0.5 (normalised coordinate space where ±0.5 fills the canvas).
///   - Inner radius = `internalRadius` (fraction of outer, i.e. `0.5 * internalRadius`
///     in the same space — Scala stores `internalRadius / 0.5 = internalRadius * 2`
///     as the `proportion` fed to `makePolygon2DStar`; here we invert that back).
///   - Vertices start at the top (12 o'clock) and proceed clockwise.
public enum RegularPolygonGenerator {

    public static func generate(params p: RegularPolygonParams) -> Polygon2D {
        let n           = p.totalPoints * 2   // total vertices
        let outerRadius = 0.5
        let innerRadius = outerRadius * p.internalRadius   // Scala: proportion = internalRadius*2, r/prop = 0.5/(internalRadius*2) = 0.25/internalRadius — but let's match exactly:
        // Scala: proportion = internalRadius * 2; r/prop = (0.5)/(internalRadius*2) = 0.25/internalRadius
        // Actually let's re-read: outer r = diameter/2 = 0.5; inner r = r/prop = 0.5 / (internalRadius*2) = 0.25 / internalRadius
        // Wait — "prop = 1/proportion" in Scala code, so inner r = r/prop = r * proportion = 0.5 * (internalRadius*2) = internalRadius
        // So inner radius = internalRadius. Let me verify: internalRadius=0.15 → inner r = 0.15, outer r = 0.5.
        let angIncDeg   = 360.0 / Double(n)
        let angInc      = angIncDeg * .pi / 180.0

        var combined = [Vector2D](repeating: .zero, count: n)

        // Even indices → outer ring, starting at top (angle = 0 → (0, -outerRadius))
        combined[0] = Vector2D(x: 0, y: -outerRadius)
        var i = 2
        while i < n {
            combined[i] = rotate(combined[i - 2], by: 2 * angInc)
            i += 2
        }

        // Odd indices → inner ring
        let innerR = p.internalRadius   // per derivation above
        let synchOffset = angInc * p.synchMultiplier * (p.positiveSynch ? 1 : -1)
        combined[1] = rotate(Vector2D(x: 0, y: -innerR), by: synchOffset)
        var j = 3
        while j < n {
            combined[j] = rotate(combined[j - 2], by: 2 * angInc)
            j += 2
        }

        var poly = Polygon2D(points: combined, type: .line)

        // Apply offset rotation (rotates the whole shape, not just start point)
        if p.offset != 0 { poly = rotatePolygon(poly, degrees: p.offset) }
        if p.scaleX != 1.0 || p.scaleY != 1.0 {
            poly = scalePolygon(poly, sx: p.scaleX, sy: p.scaleY)
        }
        if p.rotationAngle != 0 { poly = rotatePolygon(poly, degrees: p.rotationAngle) }
        let tx = p.transX - 0.5
        let ty = p.transY - 0.5
        if tx != 0 || ty != 0 { poly = translatePolygon(poly, dx: tx, dy: ty) }

        return poly
    }

    // MARK: - Private helpers

    private static func rotate(_ v: Vector2D, by radians: Double) -> Vector2D {
        let cos = Foundation.cos(radians)
        let sin = Foundation.sin(radians)
        return Vector2D(x: v.x * cos - v.y * sin,
                        y: v.x * sin + v.y * cos)
    }

    private static func rotatePolygon(_ poly: Polygon2D, degrees: Double) -> Polygon2D {
        let r = degrees * .pi / 180.0
        let pts = poly.points.map { rotate($0, by: r) }
        return Polygon2D(points: pts, type: poly.type, pressures: poly.pressures)
    }

    private static func scalePolygon(_ poly: Polygon2D, sx: Double, sy: Double) -> Polygon2D {
        let pts = poly.points.map { Vector2D(x: $0.x * sx, y: $0.y * sy) }
        return Polygon2D(points: pts, type: poly.type, pressures: poly.pressures)
    }

    private static func translatePolygon(_ poly: Polygon2D, dx: Double, dy: Double) -> Polygon2D {
        let pts = poly.points.map { Vector2D(x: $0.x + dx, y: $0.y + dy) }
        return Polygon2D(points: pts, type: poly.type, pressures: poly.pressures)
    }
}

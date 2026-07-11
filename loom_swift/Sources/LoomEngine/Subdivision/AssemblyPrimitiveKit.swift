import Foundation

/// The built-in piece kit for Assembly Fulguration (§5.12.2). Deliberately not
/// `RegularPolygonGenerator` — that generator produces *stars* (alternating outer/inner
/// radius tips via `RegularPolygonParams`); coercing it into a plain N-gon needs an
/// awkward degenerate case, so plain-N-gon generation is its own small function here.
public enum AssemblyPrimitiveKind: String, Codable, CaseIterable, Equatable, Sendable {
    case square
    case triangle
    case pentagon
    case line
}

public enum AssemblyPrimitiveKit {

    /// Generates one instance of `kind` at unit scale (roughly fills a radius-0.5
    /// circle), centered on the origin, before any per-instance deform is applied.
    public static func generate(_ kind: AssemblyPrimitiveKind) -> Polygon2D {
        switch kind {
        case .square:   return plainPolygon(sides: 4)
        case .triangle: return plainPolygon(sides: 3)
        case .pentagon: return plainPolygon(sides: 5)
        case .line:     return straightLine()
        }
    }

    /// Independent x/y scale applied to one piece instance so repeated draws of the
    /// same `AssemblyPrimitiveKind` don't look identical — a square becomes a
    /// rectangle or slight rhomboid, a triangle becomes scalene. Applied before
    /// attachment-site extraction, so alignment math sees the deformed edges directly.
    public static func deformed(_ poly: Polygon2D, scaleX: Double, scaleY: Double) -> Polygon2D {
        poly.scaled(by: Vector2D(x: scaleX, y: scaleY))
    }

    // MARK: - Generators

    /// `sides` vertices evenly spaced on a radius-0.5 circle, starting at the top,
    /// going clockwise (screen convention — Y-down when rendered, matching every other
    /// generator in this engine). `.line` type: straight edges, closed. Not `private`
    /// (was, until `GraftEngine` needed it) — called directly with an arbitrary
    /// `sides` by `GraftEngine.generatePrimitive` (§4.4.8), bypassing the closed
    /// `AssemblyPrimitiveKind` enum above so any n≥3 is reachable, not just 3/4/5.
    static func plainPolygon(sides: Int) -> Polygon2D {
        let radius = 0.5
        var pts: [Vector2D] = []
        pts.reserveCapacity(sides)
        for i in 0..<sides {
            let angle = -Double.pi / 2 + Double(i) * (2 * .pi / Double(sides))
            pts.append(Vector2D(x: cos(angle) * radius, y: sin(angle) * radius))
        }
        return Polygon2D(points: pts, type: .line)
    }

    /// A straight, open, 2-point segment encoded as a single `.openSpline` segment
    /// (`[a0, cp1, cp2, a1]`, control points collinear with the anchors so it renders
    /// dead straight) — reuses the spline representation so §5.12.3's attachment-site
    /// endpoint/tangent math applies uniformly, rather than needing a third polygon
    /// representation just for this one kind.
    private static func straightLine() -> Polygon2D {
        let a0 = Vector2D(x: -0.5, y: 0)
        let a1 = Vector2D(x: 0.5, y: 0)
        let cp1 = Vector2D.lerp(a0, a1, t: 1.0 / 3.0)
        let cp2 = Vector2D.lerp(a0, a1, t: 2.0 / 3.0)
        return Polygon2D(points: [a0, cp1, cp2, a1], type: .openSpline)
    }
}

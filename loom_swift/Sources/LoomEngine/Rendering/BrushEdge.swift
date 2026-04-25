import Foundation

// MARK: - BrushEdge

/// One segment of geometry along which brush stamps are placed.
///
/// For spline polygons each Bézier segment (4 points) is one edge.
/// For line polygons each pair of consecutive vertices is one edge.
public struct BrushEdge {
    public enum EdgeKind { case spline, line }
    public let kind:          EdgeKind
    /// 4 points for spline [a0, c0, c1, a1]; 2 points for line [p0, p1].
    public let points:        [Vector2D]
    /// Arc length in canvas pixels (screen space after viewTransform).
    public let length:        Double
    public let pressureStart: Double
    public let pressureEnd:   Double
}

// MARK: - BrushEdge extraction

extension BrushEdge {

    /// Extract all edges from `polygon` whose points have already been mapped to
    /// screen space by `viewTransform`.  Duplicate edges (shared by two polygons)
    /// are suppressed via a canonical-key set.
    static func extractEdges(
        from polygons: [Polygon2D],
        viewTransform: ViewTransform
    ) -> [BrushEdge] {
        var edges: [BrushEdge] = []
        var seen  = Set<String>()

        for poly in polygons where poly.visible {
            let pts = poly.points
            switch poly.type {

            case .spline, .openSpline:
                let segCount = pts.count / 4
                for i in 0..<segCount {
                    let a0 = viewTransform.worldToScreen(pts[i * 4    ])
                    let c0 = viewTransform.worldToScreen(pts[i * 4 + 1])
                    let c1 = viewTransform.worldToScreen(pts[i * 4 + 2])
                    let a1 = viewTransform.worldToScreen(pts[i * 4 + 3])
                    let key = canonicalKey(a0, a1)
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    let len = approximateSplineLength(a0, c0, c1, a1, samples: 10)
                    let ps  = i     < poly.pressures.count ? poly.pressures[i]     : 1.0
                    let pe  = (i+1) < poly.pressures.count ? poly.pressures[i + 1] : 1.0
                    let screenPts = [a0, c0, c1, a1]
                        .map { Vector2D(x: Double($0.x), y: Double($0.y)) }
                    edges.append(BrushEdge(kind: .spline, points: screenPts,
                                           length: len, pressureStart: ps, pressureEnd: pe))
                }

            case .line:
                let n = pts.count
                for i in 0..<n {
                    let p0 = viewTransform.worldToScreen(pts[i])
                    let p1 = viewTransform.worldToScreen(pts[(i + 1) % n])
                    let key = canonicalKey(p0, p1)
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    let len = hypot(p1.x - p0.x, p1.y - p0.y)
                    let screenPts = [p0, p1].map { Vector2D(x: Double($0.x), y: Double($0.y)) }
                    edges.append(BrushEdge(kind: .line, points: screenPts,
                                           length: len, pressureStart: 1.0, pressureEnd: 1.0))
                }

            default:
                break
            }
        }
        return edges
    }

    // MARK: - Private helpers

    private static func canonicalKey(_ a: CGPoint, _ b: CGPoint) -> String {
        let eps = 0.5
        func r(_ v: Double) -> Int { Int((v / eps).rounded()) }
        let ka = "\(r(Double(a.x))),\(r(Double(a.y)))"
        let kb = "\(r(Double(b.x))),\(r(Double(b.y)))"
        return ka < kb ? "\(ka)|\(kb)" : "\(kb)|\(ka)"
    }

    private static func approximateSplineLength(
        _ a0: CGPoint, _ c0: CGPoint, _ c1: CGPoint, _ a1: CGPoint,
        samples: Int
    ) -> Double {
        var total = 0.0
        var prev  = a0
        for i in 1...samples {
            let t  = Double(i) / Double(samples)
            let mt = 1.0 - t
            let x  = mt*mt*mt*Double(a0.x) + 3*mt*mt*t*Double(c0.x) + 3*mt*t*t*Double(c1.x) + t*t*t*Double(a1.x)
            let y  = mt*mt*mt*Double(a0.y) + 3*mt*mt*t*Double(c0.y) + 3*mt*t*t*Double(c1.y) + t*t*t*Double(a1.y)
            let pt = CGPoint(x: x, y: y)
            total += hypot(Double(pt.x - prev.x), Double(pt.y - prev.y))
            prev   = pt
        }
        return total
    }
}

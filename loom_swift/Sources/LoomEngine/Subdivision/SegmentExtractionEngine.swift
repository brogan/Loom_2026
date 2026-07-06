import Foundation

/// Breaks open-curve polygons into independent segment sub-curves.
///
/// Each pass applies extraction to every `.openSpline` polygon in turn.
/// Polygons of other types pass through unchanged.
/// Applies after `CurveRefinementEngine` in the Involution pipeline.
public enum SegmentExtractionEngine {

    // MARK: - Public entry point

    public static func process(
        polygons:      [Polygon2D],
        paramSet:      [SegmentExtractionParams],
        elapsedFrames: Double = 0,
        targetFPS:     Double = 24,
        spriteIndex:   Int    = 0
    ) -> [Polygon2D] {
        let active = paramSet.filter { $0.enabled }
        guard !active.isEmpty else { return polygons }

        var result: [Polygon2D] = []
        for polygon in polygons {
            guard polygon.type == .openSpline else { result.append(polygon); continue }
            var current = [polygon]
            for params in active {
                let fraction = resolvedFraction(params,
                                               elapsed: elapsedFrames,
                                               fps: targetFPS,
                                               spriteIndex: spriteIndex)
                current = current.flatMap { extractOne($0, params: params, drivenFraction: fraction) }
            }
            result.append(contentsOf: current)
        }
        return result
    }

    // MARK: - Single polygon, single pass

    private static func extractOne(
        _ polygon: Polygon2D,
        params: SegmentExtractionParams,
        drivenFraction: Double
    ) -> [Polygon2D] {
        let segCount = polygon.points.count / 4
        guard segCount > 0 else { return [polygon] }

        switch params.mode {
        case .all:
            return (0..<segCount).map { segmentPolygon(polygon, segIdx: $0) }

        case .alternate:
            let offset = params.alternateOffset ? 1 : 0
            let indices = (0..<segCount).filter { ($0 + offset) % 2 == 0 }
            return indices.isEmpty ? [polygon] : indices.map { segmentPolygon(polygon, segIdx: $0) }

        case .driven:
            let fraction = max(0, min(1, drivenFraction))
            let extractCount = Int((fraction * Double(segCount)).rounded())
            if extractCount == 0 { return [polygon] }
            var output: [Polygon2D] = (0..<extractCount).map { segmentPolygon(polygon, segIdx: $0) }
            if extractCount < segCount {
                output.append(joinedSegments(polygon, from: extractCount, through: segCount - 1))
            }
            return output
        }
    }

    // MARK: - Geometry helpers

    private static func segmentPolygon(_ polygon: Polygon2D, segIdx: Int) -> Polygon2D {
        let base = segIdx * 4
        let pts  = Array(polygon.points[base..<(base + 4)])
        let p: [Double] = segIdx < polygon.pressures.count ? [polygon.pressures[segIdx]] : []
        return Polygon2D(points: pts, type: .openSpline, pressures: p)
    }

    private static func joinedSegments(
        _ polygon: Polygon2D,
        from: Int,
        through to: Int
    ) -> Polygon2D {
        var pts: [Vector2D] = []
        for segIdx in from...to {
            let base = segIdx * 4
            pts.append(contentsOf: polygon.points[base..<(base + 4)])
        }
        let endIdx = min(to, polygon.pressures.count - 1)
        let p: [Double] = from <= endIdx ? Array(polygon.pressures[from...endIdx]) : []
        return Polygon2D(points: pts, type: .openSpline, pressures: p)
    }

    // MARK: - Driver resolution

    private static func resolvedFraction(
        _ params: SegmentExtractionParams,
        elapsed: Double,
        fps: Double,
        spriteIndex: Int
    ) -> Double {
        guard params.mode == .driven else { return 0 }
        return DriverEvaluator.evaluate(params.driver,
                                        globalElapsed: elapsed,
                                        targetFPS: fps,
                                        spriteIndex: spriteIndex)
    }
}

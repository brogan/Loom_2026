import Foundation

/// Refines open-curve polygons by inserting new anchor points along existing
/// Bézier segments, with optional displacement and control-point shaping.
///
/// This is the open-curve analogue of `SubdivisionEngine` — it handles
/// `.openSpline` polygons that pass through subdivision unchanged.
/// All other polygon types are returned as-is.
public enum CurveRefinementEngine {

    // MARK: - Public entry point

    public static func process(
        polygons:      [Polygon2D],
        paramSet:      [CurveRefinementParams],
        elapsedFrames: Double = 0,
        targetFPS:     Double = 24,
        spriteIndex:   Int    = 0
    ) -> [Polygon2D] {
        let active = paramSet.filter { $0.enabled }
        guard !active.isEmpty else { return polygons }
        return polygons.map { polygon in
            guard polygon.type == .openSpline else { return polygon }
            return refineAll(polygon, paramSet: active,
                             elapsedFrames: elapsedFrames,
                             targetFPS: targetFPS,
                             spriteIndex: spriteIndex)
        }
    }

    // MARK: - Pass pipeline

    private static func refineAll(
        _ polygon: Polygon2D,
        paramSet: [CurveRefinementParams],
        elapsedFrames: Double,
        targetFPS: Double,
        spriteIndex: Int
    ) -> Polygon2D {
        var result = polygon
        for params in paramSet {
            let resolved = resolveDrivers(params, elapsed: elapsedFrames,
                                          fps: targetFPS, spriteIndex: spriteIndex)
            result = refineOne(result, params: resolved, elapsedFrames: elapsedFrames)
        }
        return result
    }

    // MARK: - Single pass

    private static func refineOne(
        _ polygon: Polygon2D,
        params: CurveRefinementParams,
        elapsedFrames: Double
    ) -> Polygon2D {
        let segCount = polygon.points.count / 4
        guard segCount > 0, params.insertionCount > 0 else { return polygon }

        let polyBits = anchorBits(polygon.points[0])

        // Phase 1 — collect all anchor positions (original + inserted)
        struct AnchorInfo {
            var position:       Vector2D
            var isInserted:     Bool
            var insertionIndex: Int   // global index among inserted points
        }

        var infos = [AnchorInfo]()
        infos.reserveCapacity(segCount * (params.insertionCount + 1) + 1)
        var insertionIndex = 0

        for segIdx in 0..<segCount {
            let seg = Array(polygon.points[(segIdx * 4)..<(segIdx * 4 + 4)])

            // Original start anchor (never displaced)
            infos.append(AnchorInfo(position: seg[0], isInserted: false, insertionIndex: -1))

            // Inserted anchors sampled from the original Bézier
            let tVals = insertionTValues(
                count:    params.insertionCount,
                mode:     params.distributionMode,
                exponent: params.distributionExponent,
                reverse:  params.distributionReverse,
                seed:     params.distributionSeed ^ polyBits ^ segIdx
            )
            for t in tVals {
                infos.append(AnchorInfo(
                    position:       BezierMath.point(seg: seg, t: t),
                    isInserted:     true,
                    insertionIndex: insertionIndex
                ))
                insertionIndex += 1
            }
        }

        // Final endpoint (last anchor of last segment, never displaced)
        let lastSeg = Array(polygon.points[((segCount - 1) * 4)..<((segCount - 1) * 4 + 4)])
        infos.append(AnchorInfo(position: lastSeg[3], isInserted: false, insertionIndex: -1))

        // Phase 2 — displace inserted anchors perpendicularly
        var positions = infos.map { $0.position }
        if params.displacement != 0 {
            for i in 0..<infos.count where infos[i].isInserted {
                let tangent = approxTangent(positions: positions, at: i)
                let perp    = perpendicular(tangent)
                let amount  = displacementAmount(
                    params:        params,
                    polyBits:      polyBits,
                    pointIndex:    infos[i].insertionIndex,
                    elapsedFrames: elapsedFrames
                )
                positions[i] = positions[i] + perp.scaled(by: amount)
            }
        }

        // Phase 3 — build output Bézier control points
        let outputPoints = buildPoints(
            anchors:       positions,
            cpMode:        params.cpMode,
            cpNormalOffset: params.cpNormalOffset
        )

        // Phase 4 — build pressure profile
        let newSegCount = positions.count - 1
        let pressures   = buildPressures(
            count:        newSegCount,
            mode:         params.pressureMode,
            value:        params.pressureValue,
            originalPressures: polygon.pressures,
            insertionsPerSeg:  params.insertionCount
        )

        return Polygon2D(points: outputPoints, type: .openSpline, pressures: pressures)
    }

    // MARK: - Insertion t-values

    private static func insertionTValues(
        count:    Int,
        mode:     CurveDistributionMode,
        exponent: Double,
        reverse:  Bool,
        seed:     Int
    ) -> [Double] {
        guard count > 0 else { return [] }
        switch mode {
        case .linear:
            return (1...count).map { Double($0) / Double(count + 1) }

        case .exponential:
            let exp = max(0.01, exponent)
            var vals = (1...count).map { k in
                pow(Double(k) / Double(count + 1), exp)
            }
            if reverse { vals = vals.map { 1.0 - $0 }.sorted() }
            return vals

        case .random:
            // Deterministic from seed; sorted so insertions stay along the arc
            return (0..<count).map { k in
                SubdivisionEngine.centreHash(seed: seed, cycle: k)
            }.sorted()
        }
    }

    // MARK: - Lazy / jitter displacement

    private static func displacementAmount(
        params:        CurveRefinementParams,
        polyBits:      Int,
        pointIndex:    Int,
        elapsedFrames: Double
    ) -> Double {
        let s = params.lazySeed ^ polyBits ^ pointIndex
        switch params.displacementMode {
        case .jitter:
            let frame = Int(elapsedFrames)
            return (SubdivisionEngine.centreHash(seed: s, cycle: frame) * 2 - 1) * params.displacement

        case .lazy:
            let p  = Double(max(1, params.lazyPeriod))
            let st = elapsedFrames / p
            let iA = Int(st)
            let iB = iA + 1
            let tt = SubdivisionEngine.smoothstep(st - Double(iA))
            let dA = (SubdivisionEngine.centreHash(seed: s, cycle: iA) * 2 - 1) * params.displacement
            let dB = (SubdivisionEngine.centreHash(seed: s, cycle: iB) * 2 - 1) * params.displacement
            return dA + (dB - dA) * tt
        }
    }

    // MARK: - Geometric helpers

    private static func approxTangent(positions: [Vector2D], at i: Int) -> Vector2D {
        let n    = positions.count
        let prev = positions[max(0, i - 1)]
        let next = positions[min(n - 1, i + 1)]
        let dx   = next.x - prev.x
        let dy   = next.y - prev.y
        let len  = (dx * dx + dy * dy).squareRoot()
        guard len > 1e-12 else { return Vector2D(x: 1, y: 0) }
        return Vector2D(x: dx / len, y: dy / len)
    }

    private static func perpendicular(_ t: Vector2D) -> Vector2D {
        Vector2D(x: -t.y, y: t.x)
    }

    // MARK: - Control point construction

    private static func buildPoints(
        anchors:       [Vector2D],
        cpMode:        CurveRefinementCPMode,
        cpNormalOffset: Double
    ) -> [Vector2D] {
        let n = anchors.count
        guard n >= 2 else { return [] }
        let segCount = n - 1
        var pts = [Vector2D]()
        pts.reserveCapacity(segCount * 4)

        // Catmull-Rom tangent at anchor i
        func tangentAt(_ i: Int) -> Vector2D {
            let prev = anchors[max(0, i - 1)]
            let next = anchors[min(n - 1, i + 1)]
            return Vector2D(x: (next.x - prev.x) * 0.5,
                            y: (next.y - prev.y) * 0.5)
        }

        for i in 0..<segCount {
            let a0 = anchors[i]
            let a1 = anchors[i + 1]

            switch cpMode {
            case .straight:
                pts.append(a0)
                pts.append(Vector2D.lerp(a0, a1, t: 1.0 / 3.0))
                pts.append(Vector2D.lerp(a0, a1, t: 2.0 / 3.0))
                pts.append(a1)

            case .smooth:
                let t0 = tangentAt(i)
                let t1 = tangentAt(i + 1)
                pts.append(a0)
                pts.append(Vector2D(x: a0.x + t0.x / 3.0, y: a0.y + t0.y / 3.0))
                pts.append(Vector2D(x: a1.x - t1.x / 3.0, y: a1.y - t1.y / 3.0))
                pts.append(a1)

            case .bowed:
                let dx  = a1.x - a0.x
                let dy  = a1.y - a0.y
                let len = (dx * dx + dy * dy).squareRoot()
                let nx  = len > 1e-12 ? -dy / len : 0
                let ny  = len > 1e-12 ?  dx / len : 0
                let bow = cpNormalOffset * len
                let lp1 = Vector2D.lerp(a0, a1, t: 1.0 / 3.0)
                let lp2 = Vector2D.lerp(a0, a1, t: 2.0 / 3.0)
                pts.append(a0)
                pts.append(Vector2D(x: lp1.x + nx * bow, y: lp1.y + ny * bow))
                pts.append(Vector2D(x: lp2.x + nx * bow, y: lp2.y + ny * bow))
                pts.append(a1)
            }
        }
        return pts
    }

    // MARK: - Pressure

    private static func buildPressures(
        count:             Int,
        mode:              CurvePressureMode,
        value:             Double,
        originalPressures: [Double],
        insertionsPerSeg:  Int
    ) -> [Double] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let t = count > 1 ? Double(i) / Double(count - 1) : 0.5
            switch mode {
            case .constant:   return max(0, min(1, value))
            case .increasing: return max(0, min(1, t * value))
            case .decreasing: return max(0, min(1, (1.0 - t) * value))
            case .wave:       return max(0, min(1, (0.5 + 0.5 * sin(t * 2 * .pi)) * value))
            }
        }
    }

    // MARK: - Hash seed helper

    private static func anchorBits(_ v: Vector2D) -> Int {
        Int(bitPattern: UInt(v.x.bitPattern) ^ UInt(v.y.bitPattern &>> 3))
    }

    // MARK: - Driver resolution

    private static func resolveDrivers(
        _ params: CurveRefinementParams,
        elapsed: Double,
        fps: Double,
        spriteIndex: Int
    ) -> CurveRefinementParams {
        guard let d = params.drivers else { return params }
        var p = params
        func eval(_ drv: DoubleDriver) -> Double {
            DriverEvaluator.evaluate(drv, globalElapsed: elapsed, targetFPS: fps, spriteIndex: spriteIndex)
        }
        if d.displacement   != .zero { p.displacement   = eval(d.displacement) }
        if d.cpNormalOffset  != .zero { p.cpNormalOffset  = eval(d.cpNormalOffset) }
        return p
    }
}

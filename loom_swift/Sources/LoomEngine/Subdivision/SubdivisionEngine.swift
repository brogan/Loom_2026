import Foundation

/// Central entry point for the Loom subdivision system.
///
/// Design improvements over Scala:
/// - Algorithm dispatch is type-safe (enum switch, no raw Int)
/// - Geometry is immutable (value types; no in-place mutation)
/// - Randomness is injectable via `RandomNumberGenerator`
/// - Bypass polygon types (openSpline, point, oval) pass through unchanged
/// - `process` implements the full multi-generation pipeline
public enum SubdivisionEngine {

    // MARK: - Single polygon subdivision

    /// Subdivide `polygon` using `params`, returning child polygons with
    /// visibility applied. Bypass types (openSpline, point, oval) are
    /// returned as-is in a single-element array.
    public static func subdivide<G: RandomNumberGenerator>(
        polygon: Polygon2D,
        params: SubdivisionParams,
        rng: inout G
    ) -> [Polygon2D] {
        guard !polygon.isBypassType else { return [polygon] }

        // LINE polygons: sidesTotal = vertex count; convert to spline for algorithm reuse.
        // Mirrors Scala: LINE_POLYGON → sidesTotal = points.length; getCenter = average of all pts.
        let pts: [Vector2D]
        let n: Int
        if polygon.type == .line {
            n = polygon.points.count
            guard n > 0 else { return [polygon] }
            pts = BezierMath.lineToSplinePoints(polygon.points)
        } else {
            pts = polygon.points
            n = pts.count / 4
            guard n > 0 else { return [polygon] }
        }

        // Optionally jitter the polygon centre (affects QUAD and TRI internal edges)
        let centre = jitteredCentre(
            pts: pts, enabled: params.ranMiddle, div: params.ranDiv, rng: &rng
        )

        let children = dispatch(
            points: pts,
            sidesTotal: n,
            centre: centre,
            params: params
        )

        let pressureAwareChildren = propagatePressureIfNeeded(
            from: polygon,
            parentPoints: pts,
            sidesTotal: n,
            centre: centre,
            params: params,
            to: children,
            rng: &rng
        )

        let visible = applyVisibility(pressureAwareChildren, rule: params.visibilityRule, rng: &rng)
        return PolygonTransforms.apply(visible, params: params, rng: &rng)
    }

    // MARK: - Pipeline (multi-generation)

    /// Run a full subdivision pipeline: apply each generation in `paramSet`
    /// in sequence, pruning invisible polygons between generations.
    ///
    /// Bypass polygons are separated before processing and rejoined at the end.
    public static func process<G: RandomNumberGenerator>(
        polygons: [Polygon2D],
        paramSet: [SubdivisionParams],
        rng: inout G
    ) -> [Polygon2D] {
        let bypass   = polygons.filter { $0.isBypassType }
        var active   = polygons.filter { !$0.isBypassType }

        for params in paramSet {
            guard params.enabled else { continue }
            active = active.flatMap { subdivide(polygon: $0, params: params, rng: &rng) }
            // Prune: only visible polygons advance to the next generation
            active = active.filter { $0.visible }
        }

        return active + bypass
    }

    // MARK: - Algorithm dispatch

    private static func dispatch(
        points: [Vector2D],
        sidesTotal: Int,
        centre: Vector2D,
        params: SubdivisionParams
    ) -> [Polygon2D] {
        switch params.subdivisionType {
        case .quad:
            return subdivideQuad(points: points, sidesTotal: sidesTotal, params: params, centre: centre)
        case .quadBord:
            return subdivideQuadBord(points: points, sidesTotal: sidesTotal, params: params)
        case .quadBordEcho:
            return subdivideQuadBordEcho(points: points, sidesTotal: sidesTotal, params: params)
        case .quadBordDouble:
            return subdivideQuadBordDouble(points: points, sidesTotal: sidesTotal, params: params)
        case .quadBordDoubleEcho:
            return subdivideQuadBordDoubleEcho(points: points, sidesTotal: sidesTotal, params: params)
        case .tri:
            return subdivideTri(points: points, sidesTotal: sidesTotal, params: params, centre: centre)
        case .triBordA:
            return subdivideTriBordA(points: points, sidesTotal: sidesTotal, params: params)
        case .triBordAEcho:
            return subdivideTriBordAEcho(points: points, sidesTotal: sidesTotal, params: params)
        case .triBordB:
            return subdivideTriBordB(points: points, sidesTotal: sidesTotal, params: params)
        case .triBordBEcho:
            return subdivideTriBordBEcho(points: points, sidesTotal: sidesTotal, params: params)
        case .triBordC:
            return subdivideTriBordC(points: points, sidesTotal: sidesTotal, params: params)
        case .triBordCEcho:
            return subdivideTriBordCEcho(points: points, sidesTotal: sidesTotal, params: params)
        case .triStar:
            return subdivideTriStar(points: points, sidesTotal: sidesTotal, params: params)
        case .triStarFill:
            return subdivideTriStarFill(points: points, sidesTotal: sidesTotal, params: params)
        case .splitVert:
            return subdivideSplit(points: points, sidesTotal: sidesTotal, params: params, orientation: .vertical)
        case .splitHoriz:
            return subdivideSplit(points: points, sidesTotal: sidesTotal, params: params, orientation: .horizontal)
        case .splitDiag:
            return subdivideSplit(points: points, sidesTotal: sidesTotal, params: params, orientation: .diagonal)
        case .echo:
            return subdivideEcho(points: points, params: params)
        case .echoAbsCenter:
            return subdivideEchoAbsCenter(points: points, params: params)
        case .custom:
            guard let alg = params.customAlgorithm else { return [] }
            let anchors    = (0..<sidesTotal).map { points[$0 * 4] }
            let outerSides = BezierMath.extractSides(points, sidesTotal: sidesTotal)
            return CustomAlgorithmExecutor.subdivide(
                points: anchors,
                sidesTotal: sidesTotal,
                algorithm: alg,
                params: params,
                outerSides: outerSides
            )
        }
    }

    // MARK: - Visibility

    static func applyVisibility<G: RandomNumberGenerator>(
        _ polys: [Polygon2D],
        rule: VisibilityRule,
        rng: inout G
    ) -> [Polygon2D] {
        polys.enumerated().map { idx, poly in
            poly.withVisibility(isVisible(index: idx, total: polys.count, rule: rule, rng: &rng))
        }
    }

    private static func isVisible<G: RandomNumberGenerator>(
        index: Int,
        total: Int,
        rule: VisibilityRule,
        rng: inout G
    ) -> Bool {
        switch rule {
        case .all:           return true
        case .quads:         return true   // side count check deferred — all algorithms set correct types
        case .tris:          return true
        case .allButLast:    return index < total - 1
        case .alternateOdd:  return index % 2 != 0
        case .alternateEven: return index % 2 == 0
        case .firstHalf:     return index < total / 2
        case .secondHalf:    return index > total / 2
        case .everyThird:    return index % 3 == 0
        case .everyFourth:   return index % 4 == 0
        case .everyFifth:    return index % 5 == 0
        case .random1in2:    return Int.random(in: 0..<2,  using: &rng) == 1
        case .random1in3:    return Int.random(in: 0..<3,  using: &rng) == 1
        case .random1in5:    return Int.random(in: 0..<5,  using: &rng) == 1
        case .random1in7:    return Int.random(in: 0..<7,  using: &rng) == 1
        case .random1in10:   return Int.random(in: 0..<10, using: &rng) == 1
        }
    }

    // MARK: - Centre jitter

    /// Returns a jittered centre when `enabled`; otherwise the canonical anchor centre.
    /// Jitter range is ±(distance from centre to first anchor) / div.
    private static func jitteredCentre<G: RandomNumberGenerator>(
        pts: [Vector2D],
        enabled: Bool,
        div: Double,
        rng: inout G
    ) -> Vector2D {
        let centre = BezierMath.centreSpline(pts)
        guard enabled, pts.count >= 4 else { return centre }
        let dist  = centre.distance(to: pts[0])
        let third = dist / max(div, 1e-9)
        let x = Double.random(in: -third...third, using: &rng) + centre.x
        let y = Double.random(in: -third...third, using: &rng) + centre.y
        return Vector2D(x: x, y: y)
    }

    // MARK: - Pressure propagation

    private static func propagatePressureIfNeeded(
        from parent: Polygon2D,
        parentPoints: [Vector2D],
        sidesTotal: Int,
        centre: Vector2D,
        params: SubdivisionParams,
        to children: [Polygon2D],
        rng: inout some RandomNumberGenerator
    ) -> [Polygon2D] {
        switch params.pressureSubdivisionMode {
        case .none:
            return children
        case .spatial:
            return propagateSpatialPressure(
                from: parent,
                parentPoints: parentPoints,
                sidesTotal: sidesTotal,
                centre: centre,
                to: children
            )
        case .inheritPath:
            return propagateInheritedPathPressure(
                from: parent,
                sidesTotal: sidesTotal,
                to: children
            )
        case .random:
            return propagateRandomPressure(
                groups: params.pressureRandomGroups,
                to: children,
                rng: &rng
            )
        }
    }

    private static func propagateSpatialPressure(
        from parent: Polygon2D,
        parentPoints: [Vector2D],
        sidesTotal: Int,
        centre: Vector2D,
        to children: [Polygon2D]
    ) -> [Polygon2D] {
        guard sidesTotal > 0, hasPressureVariation(parent.pressures) || hasProfileVariation(parent.pressureProfiles) else {
            return children
        }

        let parentPressures = normalizedPressures(parent.pressures, count: sidesTotal)
        let centrePressure = parentPressures.reduce(0.0, +) / Double(parentPressures.count)
        let parentAnchors = (0..<sidesTotal).map { parentPoints[$0 * 4] }
        let scale = max(boundsDiagonal(parentAnchors), 1.0)
        let centreEpsilon = scale * 1e-8

        return children.map { child in
            let childAnchors: [Vector2D]
            switch child.type {
            case .spline:
                let childSideCount = child.points.count / 4
                guard childSideCount > 0 else { return child }
                childAnchors = (0..<childSideCount).map { child.points[$0 * 4] }
            case .line:
                guard !child.points.isEmpty else { return child }
                childAnchors = child.points
            default:
                return child
            }

            let childPressures = childAnchors.map { anchor in
                interpolatedPressure(
                    at: anchor,
                    parentAnchors: parentAnchors,
                    parentPressures: parentPressures,
                    centre: centre,
                    centrePressure: centrePressure,
                    centreEpsilon: centreEpsilon
                )
            }
            return Polygon2D(
                points: child.points,
                type: child.type,
                pressures: childPressures,
                pressureProfiles: spatialProfiles(
                    for: child,
                    parentAnchors: parentAnchors,
                    parentPressures: parentPressures,
                    parentProfiles: normalizedProfiles(parent.pressureProfiles, sideCount: sidesTotal)
                ),
                visible: child.visible
            )
        }
    }

    private static func propagateInheritedPathPressure(
        from parent: Polygon2D,
        sidesTotal: Int,
        to children: [Polygon2D]
    ) -> [Polygon2D] {
        guard sidesTotal > 0, hasPressureVariation(parent.pressures) || hasProfileVariation(parent.pressureProfiles) else {
            return children
        }

        let parentSamples = flattenedPressurePath(
            pressures: normalizedPressures(parent.pressures, count: sidesTotal),
            profiles: normalizedProfiles(parent.pressureProfiles, sideCount: sidesTotal)
        )
        guard parentSamples.count >= 2 else { return children }

        return children.map { child in
            let sideCount = childSideCount(child)
            guard sideCount > 0 else { return child }
            let profiles = pathProfiles(from: parentSamples, sideCount: sideCount, samplesPerSegment: 16)
            let pressures = profiles.map { $0.first ?? 1.0 }
            return Polygon2D(
                points: child.points,
                type: child.type,
                pressures: pressures,
                pressureProfiles: profiles,
                visible: child.visible
            )
        }
    }

    private static func propagateRandomPressure(
        groups: [Bool],
        to children: [Polygon2D],
        rng: inout some RandomNumberGenerator
    ) -> [Polygon2D] {
        let enabledGroups = SubdivisionParams.normalizedPressureRandomGroups(groups)
            .enumerated()
            .compactMap { $0.element ? $0.offset + 1 : nil }
        guard !enabledGroups.isEmpty else { return children }

        return children.map { child in
            let sideCount = childSideCount(child)
            guard sideCount > 0 else { return child }
            var profiles: [[Double]] = []
            profiles.reserveCapacity(sideCount)
            for _ in 0..<sideCount {
                let group = enabledGroups.randomElement(using: &rng) ?? 3
                profiles.append(randomPressureProfile(group: group, samples: 16, rng: &rng))
            }
            let pressures = profiles.map { $0.first ?? 1.0 }
            return Polygon2D(
                points: child.points,
                type: child.type,
                pressures: pressures,
                pressureProfiles: profiles,
                visible: child.visible
            )
        }
    }

    private static func hasPressureVariation(_ pressures: [Double]) -> Bool {
        guard !pressures.isEmpty else { return false }
        return pressures.contains { abs($0 - 1.0) > 1e-6 }
    }

    private static func hasProfileVariation(_ profiles: [[Double]]?) -> Bool {
        profiles?.contains { hasPressureVariation($0) } ?? false
    }

    private static func normalizedPressures(_ pressures: [Double], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !pressures.isEmpty else { return Array(repeating: 1.0, count: count) }
        if pressures.count == count { return pressures }
        if pressures.count > count { return Array(pressures.prefix(count)) }
        return pressures + Array(repeating: pressures.last ?? 1.0, count: count - pressures.count)
    }

    private static func normalizedProfiles(_ profiles: [[Double]]?, sideCount: Int) -> [[Double]]? {
        guard sideCount > 0, let profiles, !profiles.isEmpty else { return nil }
        var normalized = Array(profiles.prefix(sideCount))
        if normalized.count < sideCount {
            normalized += Array(repeating: normalized.last ?? [], count: sideCount - normalized.count)
        }
        return normalized.map { samples in
            guard samples.count >= 2 else { return [] }
            return samples.map { max(0.0, min(1.0, $0)) }
        }
    }

    private static func childSideCount(_ child: Polygon2D) -> Int {
        switch child.type {
        case .spline, .openSpline:
            return child.points.count / 4
        case .line:
            return child.points.count
        default:
            return 0
        }
    }

    private static func spatialProfiles(
        for child: Polygon2D,
        parentAnchors: [Vector2D],
        parentPressures: [Double],
        parentProfiles: [[Double]]?
    ) -> [[Double]]? {
        guard let parentProfiles, hasProfileVariation(parentProfiles) else { return nil }
        let sideCount = childSideCount(child)
        guard sideCount > 0 else { return nil }

        return (0..<sideCount).map { sideIndex in
            let samples = 16
            return (0..<samples).map { sampleIndex in
                let t = samples == 1 ? 0.0 : Double(sampleIndex) / Double(samples - 1)
                let point = childPoint(child, sideIndex: sideIndex, t: t)
                return interpolatedProfilePressure(
                    at: point,
                    parentAnchors: parentAnchors,
                    parentPressures: parentPressures,
                    parentProfiles: parentProfiles
                )
            }
        }
    }

    private static func childPoint(_ child: Polygon2D, sideIndex: Int, t: Double) -> Vector2D {
        switch child.type {
        case .spline, .openSpline:
            let start = sideIndex * 4
            guard start + 3 < child.points.count else { return .zero }
            return BezierMath.point(
                child.points[start],
                child.points[start + 1],
                child.points[start + 2],
                child.points[start + 3],
                t: t
            )
        case .line:
            guard !child.points.isEmpty else { return .zero }
            let start = child.points[sideIndex % child.points.count]
            let end = child.points[(sideIndex + 1) % child.points.count]
            return Vector2D.lerp(start, end, t: t)
        default:
            return .zero
        }
    }

    private static func interpolatedProfilePressure(
        at point: Vector2D,
        parentAnchors: [Vector2D],
        parentPressures: [Double],
        parentProfiles: [[Double]]
    ) -> Double {
        var bestPressure = 1.0
        var bestDistance = Double.greatestFiniteMagnitude
        let count = parentAnchors.count

        for index in 0..<count {
            let start = parentAnchors[index]
            let end = parentAnchors[(index + 1) % count]
            let edge = end - start
            let lengthSquared = edge.x * edge.x + edge.y * edge.y
            let rawT: Double
            if lengthSquared > 1e-16 {
                let fromStart = point - start
                rawT = (fromStart.x * edge.x + fromStart.y * edge.y) / lengthSquared
            } else {
                rawT = 0.0
            }
            let t = max(0.0, min(1.0, rawT))
            let projected = Vector2D.lerp(start, end, t: t)
            let distance = point.distance(to: projected)
            if distance < bestDistance {
                let fallbackStart = parentPressures[index]
                let fallbackEnd = parentPressures[(index + 1) % parentPressures.count]
                bestPressure = sampleProfile(
                    index < parentProfiles.count ? parentProfiles[index] : [],
                    at: t,
                    fallbackStart: fallbackStart,
                    fallbackEnd: fallbackEnd
                )
                bestDistance = distance
            }
        }

        return max(0.0, min(1.0, bestPressure))
    }

    private static func flattenedPressurePath(pressures: [Double], profiles: [[Double]]?) -> [Double] {
        guard !pressures.isEmpty else { return profiles?.flatMap { $0 } ?? [] }
        let count = pressures.count
        var samples: [Double] = []
        for index in 0..<count {
            if let profiles, index < profiles.count, profiles[index].count >= 2 {
                let profile = profiles[index]
                if samples.isEmpty {
                    samples += profile
                } else {
                    samples += profile.dropFirst()
                }
            } else {
                let p0 = pressures[index]
                let p1 = pressures[(index + 1) % count]
                let generated = (0..<16).map { sampleIndex in
                    let t = Double(sampleIndex) / 15.0
                    return p0 + (p1 - p0) * t
                }
                if samples.isEmpty {
                    samples += generated
                } else {
                    samples += generated.dropFirst()
                }
            }
        }
        return samples.map { max(0.0, min(1.0, $0)) }
    }

    private static func pathProfiles(from path: [Double], sideCount: Int, samplesPerSegment: Int) -> [[Double]] {
        guard sideCount > 0, path.count >= 2 else { return [] }
        return (0..<sideCount).map { sideIndex in
            (0..<samplesPerSegment).map { sampleIndex in
                let local = samplesPerSegment == 1 ? 0.0 : Double(sampleIndex) / Double(samplesPerSegment - 1)
                let t = (Double(sideIndex) + local) / Double(sideCount)
                return samplePath(path, at: t)
            }
        }
    }

    private static func samplePath(_ path: [Double], at t: Double) -> Double {
        guard !path.isEmpty else { return 1.0 }
        guard path.count >= 2 else { return path[0] }
        let wrapped = t - floor(t)
        let scaled = wrapped * Double(path.count - 1)
        let lower = Int(floor(scaled))
        let upper = min(path.count - 1, lower + 1)
        let local = scaled - Double(lower)
        return path[lower] + (path[upper] - path[lower]) * local
    }

    private static func sampleProfile(
        _ profile: [Double],
        at t: Double,
        fallbackStart: Double,
        fallbackEnd: Double
    ) -> Double {
        guard profile.count >= 2 else {
            return fallbackStart + (fallbackEnd - fallbackStart) * t
        }
        let scaled = max(0.0, min(1.0, t)) * Double(profile.count - 1)
        let lower = Int(floor(scaled))
        let upper = min(profile.count - 1, lower + 1)
        let local = scaled - Double(lower)
        return profile[lower] + (profile[upper] - profile[lower]) * local
    }

    private static func randomPressureProfile(
        group: Int,
        samples: Int,
        rng: inout some RandomNumberGenerator
    ) -> [Double] {
        let clampedGroup = max(1, min(5, group))
        let centre = Double(clampedGroup) / 5.0
        let low = max(0.05, centre - 0.14)
        let high = min(1.0, centre + 0.14)
        var current = Double.random(in: low...high, using: &rng)
        return (0..<samples).map { index in
            if index == 0 || index == samples - 1 {
                current = Double.random(in: low...high, using: &rng)
            } else {
                current += Double.random(in: -0.10...0.10, using: &rng)
            }
            return max(0.05, min(1.0, current))
        }
    }

    private static func interpolatedPressure(
        at point: Vector2D,
        parentAnchors: [Vector2D],
        parentPressures: [Double],
        centre: Vector2D,
        centrePressure: Double,
        centreEpsilon: Double
    ) -> Double {
        if point.distance(to: centre) <= centreEpsilon {
            return centrePressure
        }

        var bestPressure = parentPressures[0]
        var bestDistance = Double.greatestFiniteMagnitude
        let count = parentAnchors.count

        for index in 0..<count {
            let start = parentAnchors[index]
            let end = parentAnchors[(index + 1) % count]
            let edge = end - start
            let lengthSquared = edge.x * edge.x + edge.y * edge.y
            let rawT: Double
            if lengthSquared > 1e-16 {
                let fromStart = point - start
                rawT = (fromStart.x * edge.x + fromStart.y * edge.y) / lengthSquared
            } else {
                rawT = 0.0
            }
            let t = max(0.0, min(1.0, rawT))
            let projected = Vector2D.lerp(start, end, t: t)
            let distance = point.distance(to: projected)
            if distance < bestDistance {
                let p0 = parentPressures[index]
                let p1 = parentPressures[(index + 1) % parentPressures.count]
                bestPressure = p0 + (p1 - p0) * t
                bestDistance = distance
            }
        }

        return max(0.0, min(1.0, bestPressure))
    }

    private static func boundsDiagonal(_ points: [Vector2D]) -> Double {
        guard let first = points.first else { return 1.0 }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return hypot(maxX - minX, maxY - minY)
    }
}

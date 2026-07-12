import XCTest
@testable import LoomEngine

// MARK: - Fixture

private func makeSquare() -> Polygon2D {
    let cp = Vector2D(x: 0.25, y: 0.75)
    let corners = [
        Vector2D(x: 0, y: 0),
        Vector2D(x: 1, y: 0),
        Vector2D(x: 1, y: 1),
        Vector2D(x: 0, y: 1),
    ]
    var pts = [Vector2D]()
    for i in 0..<4 {
        pts += BezierMath.connector(from: corners[i], to: corners[(i + 1) % 4], cpRatios: cp)
    }
    return Polygon2D(points: pts, type: .spline)
}

/// A straight open curve along +x through `(0,0) → (1,0) → ... → (segments,0)`,
/// with collinear control points (no curvature) so every anchor's outgoing
/// tangent is exactly 0 radians — makes Branch's anchor-scope/geometry/curvature
/// expected values simple exact arithmetic rather than needing trig round-trips.
private func makeOpenLine(segments: Int = 2) -> Polygon2D {
    var pts = [Vector2D]()
    for i in 0..<segments {
        let a0 = Vector2D(x: Double(i), y: 0)
        let a1 = Vector2D(x: Double(i + 1), y: 0)
        pts += BezierMath.connector(from: a0, to: a1, cpRatios: Vector2D(x: 1.0 / 3.0, y: 2.0 / 3.0))
    }
    return Polygon2D(points: pts, type: .openSpline)
}

/// Minimal coverage for `ExtensionEngine` — no dedicated test file existed for this
/// mode before the directional-selector work (Specs/GeometricLifecycle.md §14), so
/// this focuses on the `outwardNormal` helper (factored out of three previously-
/// duplicated inline computations as part of that work) and the new directional
/// filter, rather than attempting full coverage of branch/extrude in one pass.
final class ExtensionEngineTests: XCTestCase {

    // MARK: - outwardNormal

    func testOutwardNormalsAreUnitLength() {
        let square = makeSquare()
        for i in 0..<4 {
            let n = ExtensionEngine.outwardNormal(of: square, segIdx: i)
            XCTAssertEqual(n.length, 1.0, accuracy: 1e-9)
        }
    }

    func testOutwardNormalsAreNinetyDegreesApartOnASquare() {
        let square = makeSquare()
        let normals = (0..<4).map { ExtensionEngine.outwardNormal(of: square, segIdx: $0) }
        for i in 0..<4 {
            let a = normals[i].angle
            let b = normals[(i + 1) % 4].angle
            var diff = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
            if diff > .pi  { diff -= 2 * .pi }
            if diff < -.pi { diff += 2 * .pi }
            XCTAssertEqual(abs(diff), .pi / 2, accuracy: 1e-6)
        }
    }

    func testOutwardNormalDegenerateEdgeReturnsZero() {
        let degenerate = Polygon2D(points: [
            Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0),
        ], type: .spline)
        XCTAssertEqual(ExtensionEngine.outwardNormal(of: degenerate, segIdx: 0), .zero)
    }

    func testOutwardNormalOutOfRangeIndexReturnsZero() {
        let square = makeSquare()
        XCTAssertEqual(ExtensionEngine.outwardNormal(of: square, segIdx: 99), .zero)
    }

    // MARK: - Directional selector integration (Specs/GeometricLifecycle.md §14)

    func testDirectionalSelectorRestrictsExtrudeToMatchingEdgeOnly() {
        let square = makeSquare()
        let targetNormal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)

        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        params.extrusionTarget = .allEdges
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: targetNormal.angle, tolerance: 0.2)

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        // Original square + exactly one extruded quad — its neighbors are 90°/180°
        // away, well outside a ±0.2 rad (~11°) tolerance.
        XCTAssertEqual(result.count, 2)
    }

    func testDirectionalSelectorExcludesAllEdgesWhenNoneMatch() {
        let square = makeSquare()
        let seg0Normal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)
        // Exactly between two adjacent segments' normals (90° apart on a square).
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg0Normal.angle + .pi / 4, tolerance: 0.1)

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result.count, 1, "no polygon should be added when no edge matches the directional filter")
    }

    func testDirectionalSelectorComposesWithLongestEdgeTarget() {
        // A rectangle (not a square) has an unambiguous longest edge, so this
        // exercises .longestEdge and the directional selector filtering it further.
        let cp = Vector2D(x: 0.25, y: 0.75)
        let corners = [
            Vector2D(x: 0, y: 0), Vector2D(x: 2, y: 0),
            Vector2D(x: 2, y: 1), Vector2D(x: 0, y: 1),
        ]
        var pts = [Vector2D]()
        for i in 0..<4 { pts += BezierMath.connector(from: corners[i], to: corners[(i + 1) % 4], cpRatios: cp) }
        let rect = Polygon2D(points: pts, type: .spline)

        // Segment 0 (bottom, length 2) is the longest edge.
        let seg0Normal = ExtensionEngine.outwardNormal(of: rect, segIdx: 0)

        var matching = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        matching.extrusionTarget = .longestEdge
        matching.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg0Normal.angle, tolerance: 0.1)
        XCTAssertEqual(ExtensionEngine.process(polygons: [rect], paramSet: [matching]).count, 2)

        var nonMatching = matching
        nonMatching.directionalSelector.targetAngle = seg0Normal.angle + .pi / 2
        XCTAssertEqual(ExtensionEngine.process(polygons: [rect], paramSet: [nonMatching]).count, 1,
                       "the longest edge doesn't face the required direction, so it should be excluded")
    }

    // MARK: - extrudeEdge asymmetric distance / direction override (2026-07-10)

    func testExtrudeEdgeDefaultsToSymmetricDistance() {
        let square = makeSquare()
        guard let quad = ExtensionEngine.extrudeEdge(square, segIdx: 0, distance: 0.2) else {
            return XCTFail("expected a quad")
        }
        // Seg 0 (inner) = a0,cp1,cp2,a1; Seg 2 (outer) = oa1,ocp1,ocp2,oa0 — see
        // ExtensionEngine.extrudeSegment's layout comment.
        let a0 = quad.points[0], a1 = quad.points[3]
        let oa1 = quad.points[8], oa0 = quad.points[11]
        XCTAssertEqual(a0.distance(to: oa0), a1.distance(to: oa1), accuracy: 1e-9,
                       "with no override, both corners extrude by the same distance")
    }

    func testExtrudeEdgeDistanceA0A1OverrideProducesAsymmetricCorners() {
        let square = makeSquare()
        guard let quad = ExtensionEngine.extrudeEdge(square, segIdx: 0, distance: 0.2,
                                                      distanceA0: 0.1, distanceA1: 0.3) else {
            return XCTFail("expected a quad")
        }
        let a0 = quad.points[0], a1 = quad.points[3]
        let oa1 = quad.points[8], oa0 = quad.points[11]
        XCTAssertEqual(a0.distance(to: oa0), 0.1, accuracy: 1e-9)
        XCTAssertEqual(a1.distance(to: oa1), 0.3, accuracy: 1e-9)
    }

    func testExtrudeEdgeDirectionOverrideTiltsAwayFromNormal() {
        let square = makeSquare()
        let normal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)
        let tilted = normal.rotated(by: 30.0 * .pi / 180.0)

        guard let straight = ExtensionEngine.extrudeEdge(square, segIdx: 0, distance: 0.2),
              let angled   = ExtensionEngine.extrudeEdge(square, segIdx: 0, distance: 0.2, direction: tilted)
        else { return XCTFail("expected quads") }

        // Inner edge (unchanged base edge) is identical either way; only the outer
        // corners move when direction is overridden.
        XCTAssertEqual(straight.points[0], angled.points[0])
        XCTAssertEqual(straight.points[3], angled.points[3])
        XCTAssertNotEqual(straight.points[11], angled.points[11], "oa0 should move when direction is tilted")
        XCTAssertNotEqual(straight.points[8],  angled.points[8],  "oa1 should move when direction is tilted")

        // Distance from the base edge is preserved — only the direction changed.
        let a0 = angled.points[0], a1 = angled.points[3]
        let oa1 = angled.points[8], oa0 = angled.points[11]
        XCTAssertEqual(a0.distance(to: oa0), 0.2, accuracy: 1e-9)
        XCTAssertEqual(a1.distance(to: oa1), 0.2, accuracy: 1e-9)
    }

    func testDirectionalSelectorDisabledMatchesAllEdgesBehavior() {
        let square = makeSquare()
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        params.extrusionTarget = .allEdges
        // Disabled (default) — must not filter anything, regardless of targetAngle.
        params.directionalSelector = DirectionalSelector(enabled: false, targetAngle: 0, tolerance: 0.001)

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 4, "all 4 edges should extrude when the selector is disabled")
    }

    // MARK: - Branch: anchor scope, geometry, curvature (2026-07-12)

    func testBranchAnchorScopeEndpointsOnlyMatchesOriginalBehavior() {
        // Default scope, depth 1 count 1: exactly 2 branches (start + end), the
        // original hardcoded behavior, unchanged.
        let line = makeOpenLine(segments: 2)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 1
        params.branchCount = 1
        params.branchScaleRatio = 1.0
        params.branchGeometry = .line
        params.branchLineLength = .constant(0.5)

        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 2, "endpointsOnly must spawn from exactly the 2 curve endpoints")

        let starts = Set(result.dropFirst().map { "\($0.points[0].x),\($0.points[0].y)" })
        XCTAssertEqual(starts, ["0.0,0.0", "2.0,0.0"], "branches must originate at the curve's start and end anchors only")
    }

    func testBranchAnchorScopeAnyAnchorSpawnsFromEveryAnchorPoint() {
        // 2-segment line has 3 anchors (0, 1, 2); anyAnchor must use all of them,
        // not just the 2 endpoints.
        let line = makeOpenLine(segments: 2)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 1
        params.branchCount = 1
        params.branchScaleRatio = 1.0
        params.branchAnchorScope = .anyAnchor
        params.branchGeometry = .line
        params.branchLineLength = .constant(0.5)

        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 3, "anyAnchor must spawn from all 3 anchor points on a 2-segment curve")

        let starts = Set(result.dropFirst().map { "\($0.points[0].x),\($0.points[0].y)" })
        XCTAssertEqual(starts, ["0.0,0.0", "1.0,0.0", "2.0,0.0"])
    }

    func testBranchGeometryLineProducesExactStraightSegment() {
        // angle 0 along a curve whose tangent is already 0 rad → branch travels
        // straight along +x. Straight line, no curvature: exact endpoint + collinear
        // control points.
        let line = makeOpenLine(segments: 1)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 1
        params.branchCount = 1
        params.branchScaleRatio = 1.0
        params.branchGeometry = .line
        params.branchLineLength = .constant(0.5)

        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 2)

        for branch in result.dropFirst() {
            XCTAssertEqual(branch.type, .openSpline)
            XCTAssertEqual(branch.points.count, 4)
            let start = branch.points[0], end = branch.points[3]
            XCTAssertEqual(end.x - start.x, 0.5, accuracy: 1e-9)
            XCTAssertEqual(end.y, start.y, accuracy: 1e-9)
            // No curvature (0–0 default): control points collinear with the chord.
            let expectedCp1 = Vector2D.lerp(start, end, t: 1.0 / 3.0)
            let expectedCp2 = Vector2D.lerp(start, end, t: 2.0 / 3.0)
            XCTAssertEqual(branch.points[1].distance(to: expectedCp1), 0, accuracy: 1e-9)
            XCTAssertEqual(branch.points[2].distance(to: expectedCp2), 0, accuracy: 1e-9)
        }
    }

    func testBranchGeometryRootCopyIsUnaffectedByNewFields() {
        // Regression: the default (rootCopy) geometry must produce exactly what it
        // did before these fields existed — a scaled/rotated copy of the whole root
        // curve, unaffected by branchLineLength/branchCurvatureAmount (irrelevant to
        // this geometry) or branchAnchorScope defaulting to endpointsOnly.
        let line = makeOpenLine(segments: 2)
        let params = ExtensionParams(operationType: .branch, branchAngle: .constant(0),
                                      branchScaleRatio: 0.5, branchDepth: 1, branchCount: 1)

        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 2)
        for branch in result.dropFirst() {
            XCTAssertEqual(branch.points.count, line.points.count, "rootCopy branches reproduce the whole root curve's point count")
        }
    }

    func testBranchCurvatureDefaultIsStraight() {
        let line = makeOpenLine(segments: 1)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 1
        params.branchCount = 1
        params.branchGeometry = .line
        params.branchLineLength = .constant(1.0)
        // branchCurvatureAmountMin/Max left at their 0.0/0.0 default.

        let branch = ExtensionEngine.process(polygons: [line], paramSet: [params])[1]
        let start = branch.points[0], end = branch.points[3]
        XCTAssertEqual(branch.points[1].distance(to: Vector2D.lerp(start, end, t: 1.0 / 3.0)), 0, accuracy: 1e-9)
        XCTAssertEqual(branch.points[2].distance(to: Vector2D.lerp(start, end, t: 2.0 / 3.0)), 0, accuracy: 1e-9)
    }

    func testBranchCurvatureFixedAmountBowsExactly() {
        // Min == Max: a fixed bow, no RNG roll at all.
        let line = makeOpenLine(segments: 1)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 1
        params.branchCount = 1
        params.branchScaleRatio = 1.0
        params.branchGeometry = .line
        params.branchLineLength = .constant(1.0)
        params.branchCurvatureAmountMin = 0.2
        params.branchCurvatureAmountMax = 0.2

        let branch = ExtensionEngine.process(polygons: [line], paramSet: [params])[1]
        let start = branch.points[0], end = branch.points[3]
        // Travelling along +x, the perpendicular normal is +y — bow = 0.2 * length(1.0) = 0.2.
        let expectedCp1 = Vector2D.lerp(start, end, t: 1.0 / 3.0) + Vector2D(x: 0, y: 0.2)
        let expectedCp2 = Vector2D.lerp(start, end, t: 2.0 / 3.0) + Vector2D(x: 0, y: 0.2)
        XCTAssertEqual(branch.points[1].distance(to: expectedCp1), 0, accuracy: 1e-9)
        XCTAssertEqual(branch.points[2].distance(to: expectedCp2), 0, accuracy: 1e-9)
    }

    func testBranchCurvatureRandomRangeStaysWithinBoundsAndVaries() {
        // Min != Max: RPSR-sampled per branch. Exercise across several seeds —
        // stays in range, is deterministic, and actually varies (isn't secretly
        // constant).
        var seenBows = Set<Double>()
        for seed in 0..<10 {
            let line = makeOpenLine(segments: 1)
            var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
            params.branchDepth = 1
            params.branchCount = 1
            params.branchScaleRatio = 1.0
            params.branchGeometry = .line
            params.branchLineLength = .constant(1.0)
            params.branchCurvatureAmountMin = -0.3
            params.branchCurvatureAmountMax = 0.3
            params.branchSeed = seed

            let a = ExtensionEngine.process(polygons: [line], paramSet: [params])[1]
            let b = ExtensionEngine.process(polygons: [line], paramSet: [params])[1]
            XCTAssertEqual(a, b, "same seed must reproduce the same random curvature (seed \(seed))")

            let start = a.points[0], end = a.points[3]
            let straightCp1 = Vector2D.lerp(start, end, t: 1.0 / 3.0)
            let bow = a.points[1].y - straightCp1.y
            XCTAssertGreaterThanOrEqual(bow, -0.3 - 1e-9, "seed \(seed)")
            XCTAssertLessThanOrEqual(bow, 0.3 + 1e-9, "seed \(seed)")
            seenBows.insert((bow * 1000).rounded() / 1000)
        }
        XCTAssertGreaterThan(seenBows.count, 1, "random curvature should actually vary across seeds")
    }

    func testBranchLineLengthDriverUnfoldsGradually() {
        // An oscillator driver on branchLineLength must actually change the
        // rendered length over elapsed time, not just at construction — the core
        // ask behind making this a DoubleDriver instead of a plain Double.
        let line = makeOpenLine(segments: 1)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 1
        params.branchCount = 1
        params.branchScaleRatio = 1.0
        params.branchGeometry = .line
        var driver = DoubleDriver()
        driver.mode = .oscillator
        driver.base = 0.1
        driver.amplitude = 0.1
        driver.freqHz = 1.0
        params.branchLineLength = driver

        // targetFPS 24 (default), freqHz 1 → t = elapsed/24. elapsed 0 → t=0 →
        // sin(0)=0 → length = base = 0.1. elapsed 6 → t=0.25 → sin(pi/2)=1 →
        // length = base + amplitude = 0.2.
        let early = ExtensionEngine.process(polygons: [line], paramSet: [params], elapsedFrames: 0)[1]
        let later = ExtensionEngine.process(polygons: [line], paramSet: [params], elapsedFrames: 6)[1]

        let earlyLength = early.points[0].distance(to: early.points[3])
        let laterLength = later.points[0].distance(to: later.points[3])
        XCTAssertEqual(earlyLength, 0.1, accuracy: 1e-9)
        XCTAssertEqual(laterLength, 0.2, accuracy: 1e-9)
        XCTAssertNotEqual(earlyLength, laterLength, "the line must unfold (change length) as elapsed time advances")
    }

    func testBranchGeometryLineRecursesFromItsOwnEndpoints() {
        // depth 2, root = (0,0)-(1,0), angle 0, length 0.5: each depth-1 branch
        // recurses from its *own* two anchors (start and end), same as rootCopy
        // branching already does — including the anchor it was itself just placed
        // at, which reproduces a duplicate overlapping segment at that spot (a
        // pre-existing characteristic of the recursion, not new to `.line`
        // geometry). The full expected multiset of (start, end) pairs is therefore
        // exact and enumerable, rather than a general "coincides with some parent"
        // check — precise geometry coverage, and avoids depending on the engine's
        // (unspecified) branch-then-recurse ordering.
        let line = makeOpenLine(segments: 1)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 2
        params.branchCount = 1
        params.branchScaleRatio = 1.0
        params.branchGeometry = .line
        params.branchLineLength = .constant(0.5)

        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        // 1 root + 2 depth-1 branches (root's start + end anchors), each with 2
        // depth-2 children of its own (its own start + end anchors) = 1 + 2 + 4.
        XCTAssertEqual(result.count, 1 + 2 + 4)

        func pair(_ p: Polygon2D) -> String {
            let s = p.points[0], e = p.points[3]
            return "\(s.x),\(s.y)->\(e.x),\(e.y)"
        }
        let actual = result.dropFirst().map(pair(_:)).sorted()
        let expected = [
            "0.0,0.0->0.5,0.0",   // depth-1, from root's start
            "0.0,0.0->0.5,0.0",   // depth-2, recursed from that branch's own start
            "0.5,0.0->1.0,0.0",   // depth-2, recursed from that branch's own end
            "1.0,0.0->1.5,0.0",   // depth-1, from root's end
            "1.0,0.0->1.5,0.0",   // depth-2, recursed from that branch's own start
            "1.5,0.0->2.0,0.0",   // depth-2, recursed from that branch's own end
        ].sorted()
        XCTAssertEqual(actual, expected)
    }

    // MARK: - Extrude: open curves, tower-height ranges, departure angle (2026-07-12)

    func testExtrudeOpenCurvesOffByDefaultLeavesOpenCurveUntouched() {
        let line = makeOpenLine(segments: 1)
        let params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        // extrudeOpenCurves left at its false default.
        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        XCTAssertEqual(result.count, 1, "an open curve must pass through untouched when extrudeOpenCurves is off")
    }

    func testExtrudeOpenCurvesOnBridgesTheEdgeIntoAClosedQuad() {
        // The core ask: duplicate one edge (preserving its own curvature) and
        // wall-connect the original curve's endpoints to the duplicate's — the
        // source curve is left completely untouched, exactly like closed-polygon
        // Extrude never mutates its source polygon either.
        let line = makeOpenLine(segments: 1)
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        params.extrudeOpenCurves = true

        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        XCTAssertEqual(result.count, 2, "original open curve + 1 bridging quad")
        XCTAssertEqual(result[0], line, "the source open curve must be left untouched")

        let quad = result[1]
        XCTAssertEqual(quad.type, .spline, "the bridging shape is a new closed polygon")
        XCTAssertEqual(quad.points.count, 16)
        // Inner face (seg 0) is the original edge's own 4 points, curvature included, verbatim.
        XCTAssertEqual(Array(quad.points[0..<4]), Array(line.points[0..<4]))
    }

    func testExtrudeGenerationsMinEqualsMaxReproducesFixedCountRegression() {
        // Min == Max: the exact old single-`extrusionGenerations` behavior.
        let square = makeSquare()
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.05))
        params.extrusionGenerationsMin = 3
        params.extrusionGenerationsMax = 3
        params.extrusionTarget = .longestEdge

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 3, "exactly 3 stacked generations on the one targeted edge, every run")
    }

    func testExtrudeGenerationsRangeProducesDistinctTowerHeightsPerEdge() {
        // Min != Max: each edge independently rolls its own generation count —
        // "distinct towers," not one uniform height applied to the whole pass.
        let square = makeSquare()
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.05))
        params.extrusionGenerationsMin = 1
        params.extrusionGenerationsMax = 4
        params.extrusionSeed = 7

        let a = ExtensionEngine.process(polygons: [square], paramSet: [params])
        let b = ExtensionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(a, b, "same seed must reproduce the same per-edge tower heights")

        // Each edge's chain starts with a quad whose inner face (points[0]) is one
        // of the original square's own anchors; every later quad in that chain has
        // its inner face at the previous quad's outer face instead (a new point,
        // not an original anchor) — this lets chain boundaries be read directly
        // off the output geometry rather than needing to replicate the RPSR roll.
        let originalAnchors = (0..<4).map { square.points[$0 * 4] }
        let quads = Array(a.dropFirst())

        var chainLengths: [Int] = []
        var currentLength = 0
        for quad in quads {
            let isChainStart = originalAnchors.contains { $0.distance(to: quad.points[0]) < 1e-9 }
            if isChainStart {
                if currentLength > 0 { chainLengths.append(currentLength) }
                currentLength = 1
            } else {
                currentLength += 1
            }
        }
        if currentLength > 0 { chainLengths.append(currentLength) }

        XCTAssertEqual(chainLengths.count, 4, "one chain per edge")
        for len in chainLengths {
            XCTAssertGreaterThanOrEqual(len, 1)
            XCTAssertLessThanOrEqual(len, 4)
        }
        XCTAssertGreaterThan(Set(chainLengths).count, 1,
                              "different edges should get different tower heights, not a uniform count")
    }

    func testExtrudeDepartureAngleDefaultMatchesPlainOutwardNormalRegression() {
        let square = makeSquare()
        let params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        let quad = ExtensionEngine.process(polygons: [square], paramSet: [params])[1]

        let normal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)
        let a1 = square.points[3]
        let expectedOa1 = a1 + normal * 0.1
        XCTAssertEqual(quad.points[7].distance(to: expectedOa1), 0, accuracy: 1e-9)
    }

    func testExtrudeDepartureAngleFixedRotatesOutwardDirectionExactly() {
        let square = makeSquare()
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        params.extrusionDepartureAngleMin = 90
        params.extrusionDepartureAngleMax = 90

        let quad = ExtensionEngine.process(polygons: [square], paramSet: [params])[1]
        let baseNormal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)
        let rotatedNormal = baseNormal.rotated(by: 90 * .pi / 180)
        let a1 = square.points[3]

        let expectedOa1 = a1 + rotatedNormal * 0.1
        XCTAssertEqual(quad.points[7].distance(to: expectedOa1), 0, accuracy: 1e-9)

        let unrotatedOa1 = a1 + baseNormal * 0.1
        XCTAssertGreaterThan(quad.points[7].distance(to: unrotatedOa1), 1e-6,
                              "a 90° departure offset must actually change the direction, not silently no-op")
    }

    func testExtrudeDepartureAngleRandomRangeStaysWithinBoundsAndVaries() {
        var seenAngles = Set<Int>()
        for seed in 0..<10 {
            let square = makeSquare()
            var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
            params.extrusionDepartureAngleMin = -45
            params.extrusionDepartureAngleMax = 45
            params.extrusionSeed = seed

            let a = ExtensionEngine.process(polygons: [square], paramSet: [params])
            let b = ExtensionEngine.process(polygons: [square], paramSet: [params])
            XCTAssertEqual(a, b, "same seed must reproduce the same random departure angle (seed \(seed))")

            let quad = a[1]
            let baseNormal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)
            let a1 = square.points[3]
            let oa1 = quad.points[7]
            let actualDir = Vector2D(x: (oa1.x - a1.x) / 0.1, y: (oa1.y - a1.y) / 0.1)

            let dot   = actualDir.x * baseNormal.x + actualDir.y * baseNormal.y
            let cross = baseNormal.x * actualDir.y - baseNormal.y * actualDir.x
            let angleBetweenDeg = atan2(cross, dot) * 180.0 / .pi

            XCTAssertLessThanOrEqual(abs(angleBetweenDeg), 45 + 1e-6, "seed \(seed)")
            seenAngles.insert(Int((angleBetweenDeg * 100).rounded()))
        }
        XCTAssertGreaterThan(seenAngles.count, 1, "random departure angle should actually vary across seeds")
    }

    // MARK: - structurePhase: gradual structural reveal (2026-07-12)

    private func enabledConstant(_ v: Double) -> DoubleDriver {
        var d = DoubleDriver.constant(v)
        d.enabled = true
        return d
    }

    func testBranchStructurePhaseZeroProducesNoBranches() {
        let line = makeOpenLine(segments: 1)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 2
        params.branchCount = 1
        params.branchScaleRatio = 1.0
        params.branchGeometry = .line
        params.branchLineLength = .constant(1.0)
        params.structurePhase = enabledConstant(0.0)

        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        XCTAssertEqual(result.count, 1, "phase 0: nothing has started revealing yet")
    }

    func testBranchStructurePhaseFractionalGrowsFirstLevelInSize() {
        let line = makeOpenLine(segments: 1)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 2
        params.branchCount = 1
        params.branchScaleRatio = 1.0
        params.branchGeometry = .line
        params.branchLineLength = .constant(1.0)
        params.structurePhase = enabledConstant(0.5)

        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 2, "only the first level's 2 branches (from the curve's 2 endpoints) exist so far")
        for branch in result.dropFirst() {
            XCTAssertEqual(branch.points[0].distance(to: branch.points[3]), 0.5, accuracy: 1e-9,
                            "at phase 0.5 the growing branch should be half its full length")
        }
    }

    func testBranchStructurePhaseIntegerFullyRevealsThatLevelWithNoneOfTheNext() {
        let line = makeOpenLine(segments: 1)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 2
        params.branchCount = 1
        params.branchScaleRatio = 1.0
        params.branchGeometry = .line
        params.branchLineLength = .constant(1.0)
        params.structurePhase = enabledConstant(1.0)

        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 2, "exactly level 1, fully grown, no level 2 yet at an exact integer phase")
        for branch in result.dropFirst() {
            XCTAssertEqual(branch.points[0].distance(to: branch.points[3]), 1.0, accuracy: 1e-9)
        }
    }

    func testBranchStructurePhaseFractionalPastOneGrowsSecondLevelWhileFirstStaysFull() {
        let line = makeOpenLine(segments: 1)
        var params = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        params.branchDepth = 2
        params.branchCount = 1
        params.branchScaleRatio = 1.0
        params.branchGeometry = .line
        params.branchLineLength = .constant(1.0)
        params.structurePhase = enabledConstant(1.5)

        let result = ExtensionEngine.process(polygons: [line], paramSet: [params])
        // 1 root + 2 (level 1, full) + 4 (level 2, growing: each level-1 branch's
        // own 2 endpoints spawn a child). Level 1 and level 2 branches are
        // interleaved in the output (each branch's own children are appended
        // immediately after it, before the next sibling), so classify by
        // measured length rather than assumed array position.
        let lengths = result.dropFirst().map { $0.points[0].distance(to: $0.points[3]) }
        XCTAssertEqual(lengths.count, 2 + 4)
        let full = lengths.filter { abs($0 - 1.0) < 1e-9 }
        let growing = lengths.filter { abs($0 - 0.5) < 1e-9 }
        XCTAssertEqual(full.count, 2, "level 1 must stay fully grown once phase has moved past it")
        XCTAssertEqual(growing.count, 4, "level 2 is the currently-growing level at phase 1.5")
    }

    func testBranchStructurePhaseDisabledMatchesFullDepthRegression() {
        let line = makeOpenLine(segments: 1)
        var withoutPhase = ExtensionParams(operationType: .branch, branchAngle: .constant(0))
        withoutPhase.branchDepth = 2
        withoutPhase.branchCount = 1
        withoutPhase.branchScaleRatio = 1.0
        withoutPhase.branchGeometry = .line
        withoutPhase.branchLineLength = .constant(1.0)
        // structurePhase left at its disabled default.

        var withPhaseAtMax = withoutPhase
        withPhaseAtMax.structurePhase = enabledConstant(2.0) // == branchDepth

        let a = ExtensionEngine.process(polygons: [line], paramSet: [withoutPhase])
        let b = ExtensionEngine.process(polygons: [line], paramSet: [withPhaseAtMax])
        XCTAssertEqual(a, b, "disabled structurePhase must reproduce the same result as an explicit phase pinned at full depth")
    }

    func testExtrudeStructurePhaseZeroProducesNoGenerations() {
        let square = makeSquare()
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.2))
        params.extrusionGenerationsMin = 3
        params.extrusionGenerationsMax = 3
        params.extrusionTarget = .longestEdge
        params.structurePhase = enabledConstant(0.0)

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result.count, 1, "phase 0: no generation has started revealing yet")
    }

    func testExtrudeStructurePhaseFractionalGrowsFirstGenerationInHeight() {
        let square = makeSquare()
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.2))
        params.extrusionGenerationsMin = 3
        params.extrusionGenerationsMax = 3
        params.extrusionTarget = .longestEdge
        params.structurePhase = enabledConstant(0.5)

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 1, "only the first generation exists so far")
        let quad = result[1]
        let a0 = quad.points[0], oa0 = quad.points[11]
        XCTAssertEqual(a0.distance(to: oa0), 0.2 * 0.5, accuracy: 1e-9,
                        "at phase 0.5 the growing generation's height should be half its full distance")
    }

    func testExtrudeStructurePhaseIntegerFullyRevealsThatGenerationWithNoneOfTheNext() {
        let square = makeSquare()
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.2))
        params.extrusionGenerationsMin = 3
        params.extrusionGenerationsMax = 3
        params.extrusionTarget = .longestEdge
        params.structurePhase = enabledConstant(1.0)

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 1)
        let quad = result[1]
        let a0 = quad.points[0], oa0 = quad.points[11]
        XCTAssertEqual(a0.distance(to: oa0), 0.2, accuracy: 1e-9)
    }

    func testExtrudeStructurePhaseClampsPerEdgeToItsOwnRolledMax() {
        // Fixed generation count of 1 (Min == Max): even a large structurePhase
        // can't reveal more than that edge's own rolled maximum.
        let square = makeSquare()
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.2))
        params.extrusionGenerationsMin = 1
        params.extrusionGenerationsMax = 1
        params.extrusionTarget = .longestEdge
        params.structurePhase = enabledConstant(5.0)

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 1, "clamped to this edge's own rolled max of 1 generation")
        let quad = result[1]
        let a0 = quad.points[0], oa0 = quad.points[11]
        XCTAssertEqual(a0.distance(to: oa0), 0.2, accuracy: 1e-9, "the one generation that exists should be fully grown")
    }

    func testExtrudeStructurePhaseDisabledMatchesFullGenerationsRegression() {
        let square = makeSquare()
        var withoutPhase = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.2))
        withoutPhase.extrusionGenerationsMin = 3
        withoutPhase.extrusionGenerationsMax = 3
        withoutPhase.extrusionTarget = .longestEdge
        // structurePhase left at its disabled default.

        var withPhaseAtMax = withoutPhase
        withPhaseAtMax.structurePhase = enabledConstant(6.0) // the engine's hard generation cap

        let a = ExtensionEngine.process(polygons: [square], paramSet: [withoutPhase])
        let b = ExtensionEngine.process(polygons: [square], paramSet: [withPhaseAtMax])
        XCTAssertEqual(a, b, "disabled structurePhase must reproduce the same result as an explicit phase pinned at the hard cap")
    }
}

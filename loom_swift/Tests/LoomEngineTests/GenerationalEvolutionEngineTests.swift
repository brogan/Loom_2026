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

/// An open curve of `segments` straight-ish segments laid end to end along +x,
/// same connector math as `makeSquare` but `.openSpline` and not closed back to
/// its start.
private func makeOpenCurve(segments: Int = 3) -> Polygon2D {
    let cp = Vector2D(x: 0.25, y: 0.75)
    var pts = [Vector2D]()
    for i in 0..<segments {
        let a = Vector2D(x: Double(i), y: 0)
        let b = Vector2D(x: Double(i + 1), y: 0)
        pts += BezierMath.connector(from: a, to: b, cpRatios: cp)
    }
    return Polygon2D(points: pts, type: .openSpline)
}

final class GenerationalEvolutionEngineTests: XCTestCase {

    private func totalVertexCount(_ polygons: [Polygon2D]) -> Int {
        polygons.reduce(0) { $0 + $1.points.count }
    }

    // MARK: - Disabled / zero generations

    func testDisabledReturnsInputUnchanged() {
        let square = makeSquare()
        var params = EvolutionParams(generationCount: 5)
        params.enabled = false
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result, [square])
    }

    func testZeroGenerationsReturnsInputUnchanged() {
        let square = makeSquare()
        let params = EvolutionParams(generationCount: 0)
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result, [square])
    }

    // MARK: - Extrude-only

    func testExtrudeOnlyAddsPolygonsEachGeneration() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 4,
            extrudeWeight: 1.0,
            splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            extrudeDistanceMin: 0.1, extrudeDistanceMax: 0.1,
            generationSeed: 42,
            maxVertexBudget: 10_000
        )
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        // Original polygon plus one quad per generation.
        XCTAssertEqual(result.count, 1 + 4)
        for poly in result {
            XCTAssertEqual(poly.type, .spline)
            XCTAssertEqual(poly.points.count % 4, 0)
        }
    }

    // MARK: - Split-only

    func testSplitOnlyGrowsTargetPolygonPointCountWithoutAddingPolygons() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 3,
            extrudeWeight: 0.0,
            splitWeight: 1.0,
            splitDisplacementMin: 0.1, splitDisplacementMax: 0.1,
            generationSeed: 7,
            maxVertexBudget: 10_000
        )
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result.count, 1, "split must not create new polygons")
        // Each split adds exactly one new anchor (+4 points: new anchor + 2 new controls
        // + the pre-existing far anchor duplicated into the second half-segment... net +4).
        XCTAssertEqual(result[0].points.count, square.points.count + 3 * 4)
    }

    func testSplitDisplacesNewAnchorOutwardFromCentre() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 1,
            extrudeWeight: 0.0,
            splitWeight: 1.0,
            splitDisplacementMin: 0.3, splitDisplacementMax: 0.3,
            generationSeed: 3,
            maxVertexBudget: 10_000
        )
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let centre = BezierMath.centreSpline(square.points)

        // Find the one anchor present in the result but not in the original square —
        // that's the newly-split, displaced point.
        let originalAnchors = Set((0..<(square.points.count / 4)).map { square.points[$0 * 4] })
        let resultAnchors = (0..<(result[0].points.count / 4)).map { result[0].points[$0 * 4] }
        let newAnchors = resultAnchors.filter { !originalAnchors.contains($0) }

        XCTAssertEqual(newAnchors.count, 1)
        guard let newAnchor = newAnchors.first else { return }
        // The un-displaced split point (edge midpoint-ish) is inside/on the square,
        // so its distance from centre should be less than the displaced anchor's.
        let undisplacedDistanceUpperBound = Vector2D(x: 1, y: 1).distance(to: .zero) // generous bound
        XCTAssertLessThan(centre.distance(to: newAnchor), undisplacedDistanceUpperBound)
        XCTAssertGreaterThan(centre.distance(to: newAnchor), 0.5,
                              "displaced anchor should sit further from centre than an undisplaced edge point would")
    }

    // MARK: - Extrude asymmetric sides / angle randomization (2026-07-10)

    func testExtrudeAsymmetricSidesOffChangesNothingFromDefault() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 3, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            extrudeDistanceMin: 0.1, extrudeDistanceMax: 0.1,
            generationSeed: 21, maxVertexBudget: 10_000
        )
        params.extrudeAsymmetricSides = false
        let withFlagOff = GenerationalEvolutionEngine.process(polygons: [square], params: params)

        var withoutFieldAtAll = params
        withoutFieldAtAll.extrudeAsymmetricSides = false
        withoutFieldAtAll.extrudeAngleRandomized = false
        let baseline = GenerationalEvolutionEngine.process(polygons: [square], params: withoutFieldAtAll)

        XCTAssertEqual(withFlagOff, baseline, "false is the default — no behavior change")
    }

    func testExtrudeAsymmetricSidesEnabledChangesResultVsDefault() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 3, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            extrudeDistanceMin: 0.15, extrudeDistanceMax: 0.15,
            generationSeed: 21, maxVertexBudget: 10_000
        )
        let symmetric = GenerationalEvolutionEngine.process(polygons: [square], params: params)

        params.extrudeAsymmetricSides = true
        let asymmetric = GenerationalEvolutionEngine.process(polygons: [square], params: params)

        XCTAssertNotEqual(symmetric, asymmetric)
        XCTAssertEqual(symmetric.count, asymmetric.count, "same target/run-length selection either way")
    }

    func testExtrudeAngleRandomizedEnabledChangesResultVsDefault() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 3, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            extrudeDistanceMin: 0.15, extrudeDistanceMax: 0.15,
            generationSeed: 5, maxVertexBudget: 10_000
        )
        let perpendicular = GenerationalEvolutionEngine.process(polygons: [square], params: params)

        params.extrudeAngleRandomized = true
        let angled = GenerationalEvolutionEngine.process(polygons: [square], params: params)

        XCTAssertNotEqual(perpendicular, angled)
    }

    func testExtrudeAsymmetricAndAngleAreDeterministic() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 4, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 2, extrudeRunLengthMax: 2,
            extrudeDistanceMin: 0.1, extrudeDistanceMax: 0.2,
            generationSeed: 17, maxVertexBudget: 10_000
        )
        params.extrudeAsymmetricSides = true
        params.extrudeAngleRandomized = true
        let a = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(a, b)
    }

    // MARK: - Split position range (2026-07-10)

    /// Which edge `applySplit` targets for a given seed doesn't depend on
    /// `splitPositionMin/Max`, so the same seed always targets the same edge
    /// across the position-range tests below — only *where* along that edge the
    /// split lands changes.
    private func splitTargetSegIdx(seed: Int, square: Polygon2D) -> Int {
        let segCount = square.points.count / 4
        let segRoll = SubdivisionEngine.centreHash(seed: seed, cycle: 6)  // cycleBase 0 + 6
        return min(segCount - 1, Int(segRoll * Double(segCount)))
    }

    func testSplitPositionDefaultAlwaysExactMidpoint() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 1, extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.0, splitDisplacementMax: 0.0,   // isolate position, no outward move
            generationSeed: 4, maxVertexBudget: 10_000
        )
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)[0]

        let segIdx = splitTargetSegIdx(seed: 4, square: square)
        let base = segIdx * 4
        let seg = Array(square.points[base..<(base + 4)])
        let expectedMidpoint = BezierMath.split(seg: seg, t: 0.5).left[3]

        let originalAnchors = Set((0..<(square.points.count / 4)).map { square.points[$0 * 4] })
        let newAnchors = (0..<(result.points.count / 4)).map { result.points[$0 * 4] }.filter { !originalAnchors.contains($0) }
        XCTAssertEqual(newAnchors.count, 1)
        guard let newAnchor = newAnchors.first else { return XCTFail("expected one new anchor") }
        XCTAssertEqual(newAnchor.distance(to: expectedMidpoint), 0, accuracy: 1e-9)
    }

    func testSplitPositionRangeMovesSplitPointOffMidpoint() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 1, extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.0, splitDisplacementMax: 0.0,
            generationSeed: 4, maxVertexBudget: 10_000
        )
        params.splitPositionMin = 0.15
        params.splitPositionMax = 0.15
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)[0]

        let segIdx = splitTargetSegIdx(seed: 4, square: square)
        let base = segIdx * 4
        let seg = Array(square.points[base..<(base + 4)])
        let expectedAtT = BezierMath.split(seg: seg, t: 0.15).left[3]
        let midpoint = BezierMath.split(seg: seg, t: 0.5).left[3]

        let originalAnchors = Set((0..<(square.points.count / 4)).map { square.points[$0 * 4] })
        let newAnchors = (0..<(result.points.count / 4)).map { result.points[$0 * 4] }.filter { !originalAnchors.contains($0) }
        XCTAssertEqual(newAnchors.count, 1)
        guard let newAnchor = newAnchors.first else { return XCTFail("expected one new anchor") }
        XCTAssertEqual(newAnchor.distance(to: expectedAtT), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(newAnchor.distance(to: midpoint), 1e-6)
    }

    func testSplitPositionExtremeRangeStaysClampedAwayFromEdgeEnds() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 1, extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.0, splitDisplacementMax: 0.0,
            generationSeed: 9, maxVertexBudget: 10_000
        )
        params.splitPositionMin = 0.0
        params.splitPositionMax = 0.0
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)[0]

        let segIdx = splitTargetSegIdx(seed: 9, square: square)
        let base = segIdx * 4
        let a0 = square.points[base]
        let seg = Array(square.points[base..<(base + 4)])
        let clampedPoint = BezierMath.split(seg: seg, t: 0.05).left[3]

        let originalAnchors = Set((0..<(square.points.count / 4)).map { square.points[$0 * 4] })
        let newAnchors = (0..<(result.points.count / 4)).map { result.points[$0 * 4] }.filter { !originalAnchors.contains($0) }
        XCTAssertEqual(newAnchors.count, 1)
        guard let newAnchor = newAnchors.first else { return XCTFail("expected one new anchor") }
        XCTAssertEqual(newAnchor.distance(to: clampedPoint), 0, accuracy: 1e-9,
                       "t=0 should clamp to 0.05, not land exactly on the edge's own start anchor")
        XCTAssertGreaterThan(newAnchor.distance(to: a0), 1e-6)
    }

    func testSplitPositionDeterministic() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 3, extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.05, splitDisplacementMax: 0.15,
            generationSeed: 6, maxVertexBudget: 10_000
        )
        params.splitPositionMin = 0.2
        params.splitPositionMax = 0.8
        let a = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(a, b)
    }

    // MARK: - Split bulge/pinch (2026-07-10)

    func testSplitBulgeDefaultRangeChangesNothing() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 1, extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.1, splitDisplacementMax: 0.1,
            generationSeed: 11, maxVertexBudget: 10_000
        )
        let baseline = GenerationalEvolutionEngine.process(polygons: [square], params: params)

        params.splitBulgePinchMin = 0.0
        params.splitBulgePinchMax = 0.0
        let explicit = GenerationalEvolutionEngine.process(polygons: [square], params: params)

        XCTAssertEqual(baseline, explicit)
    }

    /// Sign verified 2026-07-10 by rendering the actual curve geometry (not just
    /// reasoning about control-point offsets in the abstract) — positive bulge
    /// pulls the flanking control points *toward* centre relative to their
    /// un-displaced split position, which is what visually flares the base into a
    /// fuller, rounder bulge (an S-curve widening before the point). Moving them
    /// *away* from centre instead straightens the sides into a sharper point,
    /// which is what "pinch" (negative) should do — see the design-note update
    /// in Specs/GeometricLifecycle.md §4.4.2 for the render-based verification
    /// that caught this being backwards in the original implementation.
    func testSplitBulgePositiveMovesExactlyTwoFlankingControlPointsTowardCentre() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 1, extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.1, splitDisplacementMax: 0.1,
            generationSeed: 11, maxVertexBudget: 10_000
        )
        let baseline = GenerationalEvolutionEngine.process(polygons: [square], params: params)[0]

        params.splitBulgePinchMin = 0.05
        params.splitBulgePinchMax = 0.05
        let bulged = GenerationalEvolutionEngine.process(polygons: [square], params: params)[0]

        XCTAssertEqual(baseline.points.count, bulged.points.count)

        let centre = BezierMath.centreSpline(square.points)
        var moved: [(before: Vector2D, after: Vector2D)] = []
        for (b, u) in zip(baseline.points, bulged.points) where b.distance(to: u) > 1e-9 {
            moved.append((b, u))
        }
        XCTAssertEqual(moved.count, 2, "bulge should move exactly the two control points flanking the new anchor")
        for (before, after) in moved {
            XCTAssertEqual(before.distance(to: after), 0.05, accuracy: 1e-9)
            // Bulge (positive) pulls closer to centre than the un-bulged split
            // placed it — that's what flares the base, not pushes it outward.
            XCTAssertLessThan(centre.distance(to: after), centre.distance(to: before))
        }
    }

    func testSplitPinchNegativeMovesFlankingControlPointsAwayFromCentre() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 1, extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.1, splitDisplacementMax: 0.1,
            generationSeed: 11, maxVertexBudget: 10_000
        )
        let baseline = GenerationalEvolutionEngine.process(polygons: [square], params: params)[0]

        params.splitBulgePinchMin = -0.05
        params.splitBulgePinchMax = -0.05
        let pinched = GenerationalEvolutionEngine.process(polygons: [square], params: params)[0]

        let centre = BezierMath.centreSpline(square.points)
        var moved: [(before: Vector2D, after: Vector2D)] = []
        for (b, u) in zip(baseline.points, pinched.points) where b.distance(to: u) > 1e-9 {
            moved.append((b, u))
        }
        XCTAssertEqual(moved.count, 2)
        for (before, after) in moved {
            XCTAssertEqual(before.distance(to: after), 0.05, accuracy: 1e-9)
            // Pinch (negative) pushes further from centre than the un-pinched
            // split placed it — that's what straightens the sides into a point.
            XCTAssertGreaterThan(centre.distance(to: after), centre.distance(to: before))
        }
    }

    // MARK: - Open curves — side-extrude step 1 (§4.4.6, 2026-07-10)

    func testExtrudeIncludeOpenCurvesOffLeavesOpenCurveIneligible() {
        let curve = makeOpenCurve()
        var params = EvolutionParams(
            generationCount: 5, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            extrudeDistanceMin: 0.1, extrudeDistanceMax: 0.1,
            generationSeed: 3, maxVertexBudget: 10_000
        )
        params.includeOpenCurves = false
        let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
        XCTAssertEqual(result, [curve], "off (default): an open curve must stay untouched even as the only polygon present")
    }

    func testExtrudeIncludeOpenCurvesOnAddsQuadToOpenCurve() {
        let curve = makeOpenCurve()
        var params = EvolutionParams(
            generationCount: 1, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            extrudeDistanceMin: 0.1, extrudeDistanceMax: 0.1,
            generationSeed: 3, maxVertexBudget: 10_000
        )
        params.includeOpenCurves = true
        let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
        XCTAssertEqual(result.count, 2, "one quad should be added to the open curve")
        XCTAssertEqual(result[0], curve, "the original curve is left unmodified — only a new quad is appended")
        XCTAssertEqual(result[1].type, .spline, "the added extrusion is a closed quad, same as for closed-polygon targets")
    }

    /// Split gained open-curve support alongside Graft (this section, 2026-07-11)
    /// — geometry-exact: the displaced split point matches independently-replicated
    /// roll math, including the new `openCurveSafeOutward` per-edge side pick
    /// (`sideSeed = seed &+ 725_827_609`, `cycle: cycleBase`) that substitutes for
    /// the centroid-relative direction closed polygons use.
    func testSplitTargetsOpenCurveExactlyWhenIncludeOpenCurvesIsOn() {
        for seed in 0..<15 {
            let curve = makeOpenCurve()
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 1.0,
                splitDisplacementMin: 0.1, splitDisplacementMax: 0.1,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            params.includeOpenCurves = true
            let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
            guard result.count == 1 else { return XCTFail("seed \(seed): split never adds a polygon") }
            XCTAssertNotEqual(result[0], curve, "seed \(seed): the curve should have been split")

            let segCount = curve.points.count / 4
            let segRoll = SubdivisionEngine.centreHash(seed: seed, cycle: 6)  // cycleBase 0 + 6
            let segIdx  = min(segCount - 1, Int(segRoll * Double(segCount)))
            let base = segIdx * 4
            let seg = Array(curve.points[base..<(base + 4)])
            let splitPt = BezierMath.split(seg: seg, t: 0.5).left[3]  // default position, always the midpoint

            let sideSeed = seed &+ 725_827_609
            let sideRoll = SubdivisionEngine.centreHash(seed: sideSeed, cycle: 0)  // cycleBase 0
            let baseNormal = ExtensionEngine.outwardNormal(of: curve, segIdx: segIdx)
            let outward = sideRoll < 0.5 ? -baseNormal : baseNormal
            let expected = Vector2D(x: splitPt.x + outward.x * 0.1, y: splitPt.y + outward.y * 0.1)

            let newAnchor = result[0].points[base + 3]
            XCTAssertEqual(newAnchor.distance(to: expected), 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    func testSplitCanTargetEitherShapeInMixedSetWhenIncludeOpenCurvesIsOn() {
        // A closed polygon and an open curve both present, includeOpenCurves on —
        // Split should now be able to land on either, unlike before this section's
        // work when it was always closed-only regardless of the flag.
        let square = makeSquare()
        let curve = makeOpenCurve()
        var curveWasSplit = false
        var squareWasSplit = false
        for seedTry in 0..<40 {
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 1.0,
                splitDisplacementMin: 0.1, splitDisplacementMax: 0.1,
                generationSeed: seedTry, maxVertexBudget: 10_000
            )
            params.includeOpenCurves = true
            let result = GenerationalEvolutionEngine.process(polygons: [square, curve], params: params)
            if result.first(where: { $0.type == .openSpline })?.points.count != curve.points.count { curveWasSplit = true }
            if result.first(where: { $0.type == .spline })?.points.count != square.points.count { squareWasSplit = true }
        }
        XCTAssertTrue(curveWasSplit, "across 40 seeds, Split should target the open curve at least once")
        XCTAssertTrue(squareWasSplit, "across 40 seeds, Split should also still target the closed polygon at least once")
    }

    func testExtrudeOnOpenCurveNeverWrapsRunPastCurveEnd() {
        let segments = 3
        let curve = makeOpenCurve(segments: segments)
        for seedTry in 0..<40 {
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 1.0, splitWeight: 0.0,
                extrudeRunLengthMin: segments, extrudeRunLengthMax: segments,  // always requests the max possible run
                extrudeDistanceMin: 0.05, extrudeDistanceMax: 0.1,
                generationSeed: seedTry, maxVertexBudget: 10_000
            )
            params.includeOpenCurves = true

            // Replicate applyExtrude's own startSeg roll (cycleBase=0 for
            // generation 0, cycleBase+4 is the start-segment slot) to compute the
            // expected non-wrapped quad count independently of the implementation.
            let startRoll = SubdivisionEngine.centreHash(seed: seedTry, cycle: 4)
            let startSeg  = min(segments - 1, Int(startRoll * Double(segments)))
            let expectedQuads = segments - startSeg

            let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
            XCTAssertEqual(result.count, 1 + expectedQuads,
                           "seed \(seedTry): expected \(expectedQuads) non-wrapped quads (startSeg=\(startSeg), segments=\(segments))")
        }
    }

    func testExtrudeIncludeOpenCurvesIsDeterministic() {
        let curve = makeOpenCurve()
        var params = EvolutionParams(
            generationCount: 4, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 2,
            extrudeDistanceMin: 0.05, extrudeDistanceMax: 0.15,
            generationSeed: 11, maxVertexBudget: 10_000
        )
        params.includeOpenCurves = true
        let a = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
        let b = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
        XCTAssertEqual(a, b)
    }

    // MARK: - Open curves — side-extrude step 2: per-edge side roll (§4.4.6, 2026-07-10)

    func testExtrudeOpenCurveSideRollMatchesFormula() {
        // Single segment so segIdx/offset are unambiguous: a0=(0,0), a1=(1,0),
        // so outwardNormal is exactly (0,1) — easy to reason about by hand.
        let curve = makeOpenCurve(segments: 1)
        let normal = ExtensionEngine.outwardNormal(of: curve, segIdx: 0)
        let distance = 0.2

        for seedTry in 0..<20 {
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 1.0, splitWeight: 0.0,
                extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
                extrudeDistanceMin: distance, extrudeDistanceMax: distance,
                generationSeed: seedTry, maxVertexBudget: 10_000
            )
            params.includeOpenCurves = true
            let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
            guard result.count == 2 else { XCTFail("seed \(seedTry): expected a quad"); continue }

            let quad = result[1]
            let a0  = quad.points[0]   // seg0 inner start
            let oa0 = quad.points[11]  // seg2 outer end — see ExtensionEngine.extrudeSegment's layout

            // Replicates applyExtrude's own per-edge side roll (offset 0, so
            // edgeSeed = seed + 1*3_267_000_013) independently of the implementation.
            let edgeSeed = seedTry &+ (1 &* 3_267_000_013)
            let sideRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 3)
            let expectedDir = sideRoll < 0.5 ? Vector2D(x: -normal.x, y: -normal.y) : normal
            let expectedOA0 = Vector2D(x: a0.x + expectedDir.x * distance, y: a0.y + expectedDir.y * distance)

            XCTAssertEqual(oa0.distance(to: expectedOA0), 0, accuracy: 1e-9, "seed \(seedTry): side roll mismatch")
        }
    }

    func testExtrudeOpenCurveSideRollAppliesIndependentlyPerEdge() {
        let segments = 3
        let curve = makeOpenCurve(segments: segments)
        let distance = 0.2

        for seedTry in 0..<20 {
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 1.0, splitWeight: 0.0,
                extrudeRunLengthMin: segments, extrudeRunLengthMax: segments,
                extrudeDistanceMin: distance, extrudeDistanceMax: distance,
                generationSeed: seedTry, maxVertexBudget: 10_000
            )
            params.includeOpenCurves = true

            let startRoll = SubdivisionEngine.centreHash(seed: seedTry, cycle: 4)
            let startSeg  = min(segments - 1, Int(startRoll * Double(segments)))
            let expectedQuadCount = segments - startSeg

            let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
            XCTAssertEqual(result.count, 1 + expectedQuadCount, "seed \(seedTry)")

            for (offset, quad) in result.dropFirst().enumerated() {
                let segIdx = startSeg + offset
                let base   = segIdx * 4
                let a0     = curve.points[base]
                let normal = ExtensionEngine.outwardNormal(of: curve, segIdx: segIdx)

                let edgeSeed = seedTry &+ ((offset &+ 1) &* 3_267_000_013)
                let sideRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 3)
                let expectedDir = sideRoll < 0.5 ? Vector2D(x: -normal.x, y: -normal.y) : normal

                let quadA0  = quad.points[0]
                let quadOA0 = quad.points[11]
                XCTAssertEqual(quadA0.distance(to: a0), 0, accuracy: 1e-9,
                               "seed \(seedTry) offset \(offset): wrong edge targeted")

                let expectedOA0 = Vector2D(x: quadA0.x + expectedDir.x * distance,
                                           y: quadA0.y + expectedDir.y * distance)
                XCTAssertEqual(quadOA0.distance(to: expectedOA0), 0, accuracy: 1e-9,
                               "seed \(seedTry) offset \(offset): side roll mismatch")
            }
        }
    }

    func testExtrudeIncludeOpenCurvesDoesNotAffectClosedPolygonOutput() {
        // With only a closed polygon present, the new operator-first path (flag
        // on) must produce byte-for-byte the same result as the original
        // target-first path (flag off) — same eligible set either way, and
        // centreHash's roll values don't depend on which order they're read in.
        let square = makeSquare()
        var paramsOff = EvolutionParams(
            generationCount: 5, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 2,
            extrudeDistanceMin: 0.05, extrudeDistanceMax: 0.15,
            generationSeed: 21, maxVertexBudget: 10_000
        )
        paramsOff.includeOpenCurves = false
        var paramsOn = paramsOff
        paramsOn.includeOpenCurves = true

        let resultOff = GenerationalEvolutionEngine.process(polygons: [square], params: paramsOff)
        let resultOn  = GenerationalEvolutionEngine.process(polygons: [square], params: paramsOn)
        XCTAssertEqual(resultOff, resultOn, "with only a closed polygon present, the flag must have zero effect")
    }

    // MARK: - Open curves — side-extrude step 3: per-edge both-sides roll (§4.4.6, 2026-07-10)

    func testExtrudeOpenCurveBothSidesOffMatchesSingleSideBehavior() {
        // Explicitly false (default) must produce the exact same output as never
        // having set the field at all — i.e. identical to the step-2 single-side path.
        let curve = makeOpenCurve()
        var paramsExplicitOff = EvolutionParams(
            generationCount: 3, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 2,
            extrudeDistanceMin: 0.05, extrudeDistanceMax: 0.15,
            generationSeed: 8, maxVertexBudget: 10_000
        )
        paramsExplicitOff.includeOpenCurves = true
        paramsExplicitOff.extrudeOpenCurveBothSides = false

        let paramsUnset = paramsExplicitOff
        // (already false by default — this variable exists only to make the
        // "unset == explicitly false" intent readable at the call site below)
        let resultExplicit = GenerationalEvolutionEngine.process(polygons: [curve], params: paramsExplicitOff)
        let resultUnset     = GenerationalEvolutionEngine.process(polygons: [curve], params: paramsUnset)
        XCTAssertEqual(resultExplicit, resultUnset)
    }

    func testExtrudeOpenCurveBothSidesRollMatchesFormula() {
        // Single segment, single-edge run: exactly one or two quads depending on
        // the roll, easy to reason about geometrically by hand.
        let curve = makeOpenCurve(segments: 1)
        let normal = ExtensionEngine.outwardNormal(of: curve, segIdx: 0)
        let distance = 0.2

        for seedTry in 0..<20 {
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 1.0, splitWeight: 0.0,
                extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
                extrudeDistanceMin: distance, extrudeDistanceMax: distance,
                generationSeed: seedTry, maxVertexBudget: 10_000
            )
            params.includeOpenCurves = true
            params.extrudeOpenCurveBothSides = true

            let edgeSeed = seedTry &+ (1 &* 3_267_000_013)
            let sideRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 3)
            let primaryDir = sideRoll < 0.5 ? Vector2D(x: -normal.x, y: -normal.y) : normal
            let bothSidesRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 4)
            let expectsBothSides = bothSidesRoll < 0.5

            let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
            let expectedCount = expectsBothSides ? 3 : 2
            XCTAssertEqual(result.count, expectedCount,
                           "seed \(seedTry): bothSidesRoll=\(bothSidesRoll) should give \(expectedCount - 1) quad(s)")

            let a0 = curve.points[0]
            let primaryQuadOA0 = result[1].points[11]
            let expectedPrimaryOA0 = Vector2D(x: a0.x + primaryDir.x * distance, y: a0.y + primaryDir.y * distance)
            XCTAssertEqual(primaryQuadOA0.distance(to: expectedPrimaryOA0), 0, accuracy: 1e-9,
                           "seed \(seedTry): primary side mismatch")

            if expectsBothSides {
                let secondaryDir = Vector2D(x: -primaryDir.x, y: -primaryDir.y)
                let secondaryQuadOA0 = result[2].points[11]
                let expectedSecondaryOA0 = Vector2D(x: a0.x + secondaryDir.x * distance, y: a0.y + secondaryDir.y * distance)
                XCTAssertEqual(secondaryQuadOA0.distance(to: expectedSecondaryOA0), 0, accuracy: 1e-9,
                               "seed \(seedTry): secondary side should be the exact opposite of the primary")
            }
        }
    }

    func testExtrudeOpenCurveBothSidesAppliesIndependentlyPerEdge() {
        let segments = 4
        let curve = makeOpenCurve(segments: segments)
        let distance = 0.15

        for seedTry in 0..<20 {
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 1.0, splitWeight: 0.0,
                extrudeRunLengthMin: segments, extrudeRunLengthMax: segments,
                extrudeDistanceMin: distance, extrudeDistanceMax: distance,
                generationSeed: seedTry, maxVertexBudget: 10_000
            )
            params.includeOpenCurves = true
            params.extrudeOpenCurveBothSides = true

            let startRoll = SubdivisionEngine.centreHash(seed: seedTry, cycle: 4)
            let startSeg  = min(segments - 1, Int(startRoll * Double(segments)))
            var expectedQuadCount = 0
            for offset in 0..<(segments - startSeg) {
                let edgeSeed = seedTry &+ ((offset &+ 1) &* 3_267_000_013)
                let bothSidesRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 4)
                expectedQuadCount += bothSidesRoll < 0.5 ? 2 : 1
            }

            let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
            XCTAssertEqual(result.count, 1 + expectedQuadCount, "seed \(seedTry)")
        }
    }

    func testExtrudeOpenCurveBothSidesSharesAngleOffsetAcrossBothQuads() {
        let curve = makeOpenCurve(segments: 1)
        let normal = ExtensionEngine.outwardNormal(of: curve, segIdx: 0)
        let distance = 0.2

        for seedTry in 0..<20 {
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 1.0, splitWeight: 0.0,
                extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
                extrudeDistanceMin: distance, extrudeDistanceMax: distance,
                generationSeed: seedTry, maxVertexBudget: 10_000
            )
            params.includeOpenCurves = true
            params.extrudeOpenCurveBothSides = true
            params.extrudeAngleRandomized = true

            let edgeSeed = seedTry &+ (1 &* 3_267_000_013)
            let bothSidesRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 4)
            guard bothSidesRoll < 0.5 else { continue }  // only meaningful when both sides actually fire

            let sideRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 3)
            let primaryBase = sideRoll < 0.5 ? Vector2D(x: -normal.x, y: -normal.y) : normal
            // Matches GenerationalEvolutionEngine's private angleRandomizationDegrees
            // constant — not visible across the `private` boundary even via
            // @testable import, so mirrored here explicitly.
            let angleRandomizationDegreesForTests = 45.0
            let angleRoll = SubdivisionEngine.centreHash(seed: edgeSeed, cycle: 2)
            let angleRad  = (angleRoll * 2.0 - 1.0) * angleRandomizationDegreesForTests * .pi / 180.0
            let expectedPrimary   = primaryBase.rotated(by: angleRad)
            let expectedSecondary = Vector2D(x: -primaryBase.x, y: -primaryBase.y).rotated(by: angleRad)

            let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
            XCTAssertEqual(result.count, 3, "seed \(seedTry): expected both sides to fire given the precondition above")

            let a0 = curve.points[0]
            let primaryOA0   = result[1].points[11]
            let secondaryOA0 = result[2].points[11]
            let expectedPrimaryOA0   = Vector2D(x: a0.x + expectedPrimary.x * distance, y: a0.y + expectedPrimary.y * distance)
            let expectedSecondaryOA0 = Vector2D(x: a0.x + expectedSecondary.x * distance, y: a0.y + expectedSecondary.y * distance)

            XCTAssertEqual(primaryOA0.distance(to: expectedPrimaryOA0), 0, accuracy: 1e-9,
                           "seed \(seedTry): primary direction should use the shared angle offset")
            XCTAssertEqual(secondaryOA0.distance(to: expectedSecondaryOA0), 0, accuracy: 1e-9,
                           "seed \(seedTry): secondary direction should use the SAME angle offset as the primary, just the opposite base side")
        }
    }

    func testExtrudeOpenCurveBothSidesHasNoEffectOnClosedPolygon() {
        let square = makeSquare()
        var paramsBothSidesOff = EvolutionParams(
            generationCount: 5, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 2,
            extrudeDistanceMin: 0.05, extrudeDistanceMax: 0.15,
            generationSeed: 14, maxVertexBudget: 10_000
        )
        paramsBothSidesOff.includeOpenCurves = true
        paramsBothSidesOff.extrudeOpenCurveBothSides = false
        var paramsBothSidesOn = paramsBothSidesOff
        paramsBothSidesOn.extrudeOpenCurveBothSides = true

        let resultOff = GenerationalEvolutionEngine.process(polygons: [square], params: paramsBothSidesOff)
        let resultOn  = GenerationalEvolutionEngine.process(polygons: [square], params: paramsBothSidesOn)
        XCTAssertEqual(resultOff, resultOn, "with only a closed polygon present, extrudeOpenCurveBothSides must have zero effect")
    }

    // MARK: - Determinism

    func testSameSeedProducesIdenticalResult() {
        let square = makeSquare()
        let params = EvolutionParams(generationCount: 6, generationSeed: 99)
        let a = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(a, b)
    }

    func testDifferentSeedsCanProduceDifferentResults() {
        let square = makeSquare()
        var paramsA = EvolutionParams(generationCount: 6)
        paramsA.generationSeed = 1
        var paramsB = paramsA
        paramsB.generationSeed = 2

        let a = GenerationalEvolutionEngine.process(polygons: [square], params: paramsA)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: paramsB)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Budget cap

    func testVertexBudgetStopsGenerationEarly() {
        let square = makeSquare()
        let generous = EvolutionParams(
            generationCount: 20, extrudeWeight: 1.0, splitWeight: 0.0,
            generationSeed: 5, maxVertexBudget: 100_000
        )
        let capped = EvolutionParams(
            generationCount: 20, extrudeWeight: 1.0, splitWeight: 0.0,
            generationSeed: 5, maxVertexBudget: totalVertexCount([square]) + 16 * 2 // room for ~2 quads
        )
        let generousResult = GenerationalEvolutionEngine.process(polygons: [square], params: generous)
        let cappedResult   = GenerationalEvolutionEngine.process(polygons: [square], params: capped)

        XCTAssertLessThan(totalVertexCount(cappedResult), totalVertexCount(generousResult))
        XCTAssertLessThanOrEqual(totalVertexCount(cappedResult), capped.maxVertexBudget)
    }

    // MARK: - passes: pipeline wrapper (EvolutionParams.operationType filtering)

    func testPassesWrapperIgnoresNonGenerationalPasses() {
        let square = makeSquare()
        let momentumDrift = EvolutionParams(operationType: .momentumDrift)
        let result = GenerationalEvolutionEngine.process(polygons: [square], passes: [momentumDrift])
        XCTAssertEqual(result, [square], "non-.generational passes must be ignored, not crash or mutate")
    }

    func testPassesWrapperIgnoresDisabledGenerationalPass() {
        let square = makeSquare()
        var disabled = EvolutionParams(operationType: .generational, generationCount: 5)
        disabled.enabled = false
        let result = GenerationalEvolutionEngine.process(polygons: [square], passes: [disabled])
        XCTAssertEqual(result, [square])
    }

    func testPassesWrapperChainsMultipleGenerationalPasses() {
        let square = makeSquare()
        let passA = EvolutionParams(
            operationType: .generational, generationCount: 2,
            extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1, generationSeed: 1
        )
        let passB = EvolutionParams(
            operationType: .generational, generationCount: 3,
            extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1, generationSeed: 2
        )
        let chained  = GenerationalEvolutionEngine.process(polygons: [square], passes: [passA, passB])
        let sequential = GenerationalEvolutionEngine.process(
            polygons: GenerationalEvolutionEngine.process(polygons: [square], params: passA),
            params: passB
        )
        XCTAssertEqual(chained, sequential, "passes: should apply each pass to the previous pass's output, in order")
        // 2 + 3 generations of extrude-only, run length pinned to 1 quad each = 5 new polygons.
        XCTAssertEqual(chained.count, 1 + 5)
    }

    // MARK: - Tweened phase

    func testNilPhaseMatchesFullGenerationCount() {
        let square = makeSquare()
        let params = EvolutionParams(generationCount: 4, generationSeed: 3)
        let implicit = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let explicit = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 4.0)
        XCTAssertEqual(implicit, explicit, "omitting phase must match passing the full generationCount")
    }

    func testZeroPhaseReturnsInputUnchanged() {
        let square = makeSquare()
        let params = EvolutionParams(generationCount: 5, generationSeed: 3)
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 0)
        XCTAssertEqual(result, [square])
    }

    func testIntegerPhaseMatchesEquivalentGenerationCount() {
        let square = makeSquare()
        let fiveGen = EvolutionParams(generationCount: 5, generationSeed: 7)
        var twoGen  = fiveGen
        twoGen.generationCount = 2

        // Generation N's random draws depend only on (generationSeed, N), not on
        // generationCount — so phase=2 against a 5-generation config must match a
        // config whose generationCount is simply 2.
        let viaPhase = GenerationalEvolutionEngine.process(polygons: [square], params: fiveGen, phase: 2.0)
        let viaCount = GenerationalEvolutionEngine.process(polygons: [square], params: twoGen)
        XCTAssertEqual(viaPhase, viaCount)
    }

    func testFractionalPhaseScalesExtrudeDistance() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 1, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            extrudeDistanceMin: 0.2, extrudeDistanceMax: 0.2,
            generationSeed: 11, maxVertexBudget: 10_000
        )
        let full = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 1.0)
        let half = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 0.5)

        XCTAssertEqual(full.count, 2)
        XCTAssertEqual(half.count, 2, "a partially-tweened generation still adds its quad — just smaller")

        // Layout per ExtensionEngine.extrudeSegment: [a0,cp,cp,a1, a1,..,oa1, oa1,..,oa0, oa0,..,a0].
        // points[3] = a1 (inner/source edge), points[7] = oa1 (outer edge) — their
        // separation is exactly the extrusion distance when width == 1.0 (the default).
        let fullDistance = full[1].points[7].distance(to: full[1].points[3])
        let halfDistance = half[1].points[7].distance(to: half[1].points[3])

        XCTAssertEqual(fullDistance, 0.2, accuracy: 1e-9)
        XCTAssertEqual(halfDistance, 0.1, accuracy: 1e-9, "half phase through the generation should halve the distance")
    }

    func testFractionalPhaseScalesSplitDisplacement() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 1, extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.3, splitDisplacementMax: 0.3,
            generationSeed: 4, maxVertexBudget: 10_000
        )
        let centre = BezierMath.centreSpline(square.points)
        let full = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 1.0)
        let quarter = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 0.25)

        let originalAnchors = Set((0..<(square.points.count / 4)).map { square.points[$0 * 4] })
        func newAnchor(_ result: [Polygon2D]) -> Vector2D {
            let anchors = (0..<(result[0].points.count / 4)).map { result[0].points[$0 * 4] }
            return anchors.first { !originalAnchors.contains($0) }!
        }

        // Undisplaced split point sits at distance 0.5 from centre (see the
        // non-tweened split test in this file); full/quarter phase should displace
        // it outward by the full/quarter-scaled RPSR distance respectively.
        let fullDistance    = centre.distance(to: newAnchor(full))
        let quarterDistance = centre.distance(to: newAnchor(quarter))
        XCTAssertEqual(fullDistance,    0.8,  accuracy: 1e-9)
        XCTAssertEqual(quarterDistance, 0.575, accuracy: 1e-9, "0.5 + 0.3*0.25")
    }

    func testPassesWrapperEvaluatesEnabledGenerationPhaseDriver() {
        let square = makeSquare()
        var params = EvolutionParams(
            operationType: .generational, generationCount: 4,
            extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            generationSeed: 9
        )
        params.generationPhase = DoubleDriver(mode: .constant, base: 1.5, enabled: true)

        let viaPasses = GenerationalEvolutionEngine.process(polygons: [square], passes: [params])
        let viaDirect = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 1.5)
        XCTAssertEqual(viaPasses, viaDirect)
    }

    func testPassesWrapperFallsBackToFullCountWhenDriverDisabled() {
        let square = makeSquare()
        var params = EvolutionParams(operationType: .generational, generationCount: 3, generationSeed: 2)
        params.generationPhase.enabled = false

        let viaPasses = GenerationalEvolutionEngine.process(polygons: [square], passes: [params])
        let viaFull    = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(viaPasses, viaFull)
    }

    // MARK: - Vary seed per cycle

    func testRevealCycleIndexOscillatorAlignsWithTroughNotWrapPoint() {
        // fps=8, freqHz=1 -> period 8 frames. phase=0.75 puts the trough (generation 0)
        // at elapsedFrames=0, matching the "start at frame 0" setup from the Reveal
        // driver walkthrough. The seed must not flip until a full cycle has passed
        // *from the trough*, not at the wave's internal p=0 wrap (a quarter-cycle
        // earlier), or it would glitch mid-climb.
        let driver = DoubleDriver(mode: .oscillator, base: 2, amplitude: 2,
                                  freqHz: 1.0, phase: 0.75, wave: .sine, enabled: true)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 0, targetFPS: 8), 0)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 4, targetFPS: 8), 0,
                       "quarter-cycle in (partway up the climb) must still be cycle 0")
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 7.999, targetFPS: 8), 0)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 8, targetFPS: 8), 1,
                       "exactly one full cycle after the trough")
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 12, targetFPS: 8), 1)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 16, targetFPS: 8), 2)
    }

    func testRevealCycleIndexZeroWhenDriverDisabledOrNonLooping() {
        var disabled = DoubleDriver(mode: .oscillator, freqHz: 1.0, enabled: false)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: disabled, elapsedFrames: 100, targetFPS: 30), 0)

        let onceKeyframe = DoubleDriver(
            mode: .keyframe, loopMode: .once,
            keyframes: [DoubleKeyframe(frame: 0, value: 0), DoubleKeyframe(frame: 60, value: 5)],
            enabled: true
        )
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: onceKeyframe, elapsedFrames: 200, targetFPS: 30), 0,
                       "a one-shot (non-looping) keyframe track never restarts, so there's no cycle to key off")

        disabled.mode = .noise
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: disabled, elapsedFrames: 100, targetFPS: 30), 0)
    }

    func testRevealCycleIndexKeyframeLoop() {
        let driver = DoubleDriver(
            mode: .keyframe, loopMode: .loop,
            keyframes: [DoubleKeyframe(frame: 0, value: 0), DoubleKeyframe(frame: 60, value: 5)],
            enabled: true
        )
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 0,  targetFPS: 30), 0)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 59, targetFPS: 30), 0)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 60, targetFPS: 30), 1)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 125, targetFPS: 30), 2)
    }

    func testEffectiveSeedMatchesGenerationSeedWhenVaryingIsOff() {
        var params = EvolutionParams(operationType: .generational, generationSeed: 42)
        params.generationPhase = DoubleDriver(mode: .oscillator, freqHz: 1.0, enabled: true)
        params.varySeedPerCycle = false
        XCTAssertEqual(
            GenerationalEvolutionEngine.effectiveSeed(for: params, elapsedFrames: 999, targetFPS: 30),
            42
        )
    }

    func testEffectiveSeedMatchesGenerationSeedWhenDriverDisabledEvenIfVaryingIsOn() {
        var params = EvolutionParams(operationType: .generational, generationSeed: 42)
        params.varySeedPerCycle = true
        params.generationPhase.enabled = false
        XCTAssertEqual(
            GenerationalEvolutionEngine.effectiveSeed(for: params, elapsedFrames: 999, targetFPS: 30),
            42
        )
    }

    func testEffectiveSeedMatchesCombineSeedOfCurrentCycleWhenVaryingIsOn() {
        var params = EvolutionParams(operationType: .generational, generationSeed: 42)
        params.generationPhase = DoubleDriver(mode: .oscillator, base: 2, amplitude: 2,
                                              freqHz: 1.0, phase: 0.75, wave: .sine, enabled: true)
        params.varySeedPerCycle = true

        let cycle = GenerationalEvolutionEngine.revealCycleIndex(for: params.generationPhase, elapsedFrames: 12, targetFPS: 8)
        XCTAssertEqual(cycle, 1, "sanity check against testRevealCycleIndexOscillatorAlignsWithTroughNotWrapPoint")
        XCTAssertEqual(
            GenerationalEvolutionEngine.effectiveSeed(for: params, elapsedFrames: 12, targetFPS: 8),
            GenerationalEvolutionEngine.combineSeed(42, 1)
        )
    }

    func testVarySeedPerCycleProducesDifferentResultsAcrossCyclesAtSamePhase() {
        let square = makeSquare()
        var params = EvolutionParams(
            operationType: .generational, generationCount: 4,
            extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            generationSeed: 21
        )
        params.generationPhase = DoubleDriver(mode: .oscillator, base: 2, amplitude: 2,
                                              freqHz: 1.0, phase: 0.75, wave: .sine, enabled: true)
        params.varySeedPerCycle = true

        // elapsedFrames 4 and 12 are both a quarter-cycle past their respective
        // troughs (cycles 0 and 1 respectively — see testRevealCycleIndex... above),
        // so they evaluate to the *same* phase value but should mutate differently.
        let cycle0 = GenerationalEvolutionEngine.process(polygons: [square], passes: [params],
                                                          elapsedFrames: 4, targetFPS: 8)
        let cycle1 = GenerationalEvolutionEngine.process(polygons: [square], passes: [params],
                                                          elapsedFrames: 12, targetFPS: 8)
        XCTAssertNotEqual(cycle0, cycle1, "different cycles should mutate differently when varySeedPerCycle is on")

        // Same elapsedFrames called twice must still be fully deterministic.
        let cycle0Again = GenerationalEvolutionEngine.process(polygons: [square], passes: [params],
                                                               elapsedFrames: 4, targetFPS: 8)
        XCTAssertEqual(cycle0, cycle0Again)
    }

    func testVarySeedPerCycleHasNoEffectWhenDriverDisabled() {
        let square = makeSquare()
        var withVary = EvolutionParams(operationType: .generational, generationCount: 3, generationSeed: 5)
        withVary.varySeedPerCycle = true
        withVary.generationPhase.enabled = false

        var withoutVary = withVary
        withoutVary.varySeedPerCycle = false

        let a = GenerationalEvolutionEngine.process(polygons: [square], passes: [withVary],
                                                     elapsedFrames: 500, targetFPS: 30)
        let b = GenerationalEvolutionEngine.process(polygons: [square], passes: [withoutVary],
                                                     elapsedFrames: 500, targetFPS: 30)
        XCTAssertEqual(a, b, "varySeedPerCycle must be inert when the reveal driver itself is disabled")
    }

    func testSameCycleProducesSameResultRegardlessOfExactFrame() {
        let driver = DoubleDriver(mode: .oscillator, base: 2, amplitude: 2,
                                  freqHz: 1.0, phase: 0.75, wave: .sine, enabled: true)
        // elapsedFrames 4 and 4.5 are both within cycle 0 (see revealCycleIndex
        // tests above) — the cycle index (and therefore the effective seed) must
        // be identical even though the phase itself differs between them.
        XCTAssertEqual(
            GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 4,   targetFPS: 8),
            GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 4.5, targetFPS: 8)
        )
    }

    // MARK: - Directional selector (Specs/GeometricLifecycle.md §14)

    func testDirectionalSelectorRestrictsExtrudeTargetEdge() {
        let square = makeSquare()
        // Ground truth taken from the engine's own computed normal rather than an
        // assumed winding convention, so this test is correct regardless of which
        // way the fixture happens to wind.
        let seg0Normal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)

        var params = EvolutionParams(
            operationType: .generational, generationCount: 1,
            extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            generationSeed: 42, maxVertexBudget: 10_000
        )
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg0Normal.angle, tolerance: 0.2)

        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result.count, 2, "exactly one quad should be extruded, from the matching edge")
        let addedQuad = result[1]
        XCTAssertEqual(addedQuad.points[0], square.points[0], "extruded quad's inner face should coincide with segment 0")
        XCTAssertEqual(addedQuad.points[3], square.points[3])
    }

    func testDirectionalSelectorNoMatchLeavesPolygonUnchangedForExtrude() {
        let square = makeSquare()
        let seg0Normal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)
        // Exactly between two adjacent segments' normals (90° apart on a square) —
        // with a tight tolerance, no segment's normal falls inside the cone.
        var params = EvolutionParams(
            operationType: .generational, generationCount: 3,
            extrudeWeight: 1.0, splitWeight: 0.0,
            generationSeed: 42, maxVertexBudget: 10_000
        )
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg0Normal.angle + .pi / 4, tolerance: 0.05)

        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result, [square], "no edge matches the directional filter, so every generation should no-op")
    }

    func testDirectionalSelectorRestrictsSplitTargetEdge() {
        let square = makeSquare()
        let seg2Normal = ExtensionEngine.outwardNormal(of: square, segIdx: 2)

        var params = EvolutionParams(
            operationType: .generational, generationCount: 1,
            extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.1, splitDisplacementMax: 0.1,
            generationSeed: 7, maxVertexBudget: 10_000
        )
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg2Normal.angle, tolerance: 0.2)

        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result.count, 1, "split never adds polygons")
        let originalAnchors = Set((0..<4).map { square.points[$0 * 4] })
        let resultAnchors = (0..<(result[0].points.count / 4)).map { result[0].points[$0 * 4] }
        let newAnchors = resultAnchors.filter { !originalAnchors.contains($0) }
        XCTAssertEqual(newAnchors.count, 1, "exactly one split should have occurred")
    }

    func testDirectionalSelectorNoMatchLeavesPolygonUnchangedForSplit() {
        let square = makeSquare()
        let seg2Normal = ExtensionEngine.outwardNormal(of: square, segIdx: 2)
        var params = EvolutionParams(
            operationType: .generational, generationCount: 3,
            extrudeWeight: 0.0, splitWeight: 1.0,
            generationSeed: 7, maxVertexBudget: 10_000
        )
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg2Normal.angle + .pi / 4, tolerance: 0.05)

        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result, [square], "no edge matches the directional filter, so every generation should no-op")
    }

    // MARK: - Graft operator, §4.4.8.6 step 2 (.wholeEdge attachment)

    /// Replicates `applyGraft`'s segIdx-selection roll independently, mirroring
    /// `splitTargetSegIdx` above — needed to compute the analytically-known
    /// target edge for the coincidence check below, without needing to touch any
    /// of Graft's other (unrelated) rolls.
    private func graftTargetSegIdx(seed: Int, cycleBase: Int = 0, segCount: Int) -> Int {
        let graftSeed = seed &+ 918_273_645
        let segRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 0)
        return min(segCount - 1, Int(segRoll * Double(segCount)))
    }

    func testGraftAppendsOnePolygonPerGeneration() {
        for seed in 0..<20 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertEqual(result.count, 2, "seed \(seed)")
            XCTAssertEqual(result[1].type, .line, "seed \(seed): a Graft piece is AssemblyPrimitiveKit's raw .line encoding, not .spline")
        }
    }

    func testGraftedPieceEdgeCoincidesExactlyWithTargetEdgeMidpoint() {
        // `AssemblyFulgurationEngine.place` guarantees the chosen source site's
        // point lands exactly on the target site's point, regardless of which
        // site/mirror/edge-matching was rolled — re-extracting sites from the
        // *result* geometry and finding one within floating tolerance of the
        // analytically-known target edge midpoint is therefore a roll-independent
        // invariant, not something that requires replicating every roll.
        for seed in 0..<20 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed): expected a grafted piece") }

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let base = segIdx * 4
            let a0 = square.points[base]
            let a1 = square.points[base + 3]
            let expectedMid = Vector2D(x: (a0.x + a1.x) / 2, y: (a0.y + a1.y) / 2)

            let placedSites = AttachmentSiteExtractor.sites(of: result[1])
            let closest = placedSites.map { $0.point.distance(to: expectedMid) }.min() ?? .infinity
            XCTAssertEqual(closest, 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    func testGraftSkippedWhenPrimitiveDegeneratesToLine() {
        // n=1 forced — AssemblyPrimitiveKit's .line kind has only point-type
        // endpoint sites, no edge-type one, so .wholeEdge attachment has nothing
        // to match onto and this generation should no-op.
        for seed in 0..<10 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 1, graftSidesMax: 1, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertEqual(result, [square], "seed \(seed)")
        }
    }

    func testGraftIsDeterministic() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 3, extrudeWeight: 0.0, splitWeight: 0.0,
            graftSidesMin: 3, graftSidesMax: 6, graftDistortionMin: 0.7, graftDistortionMax: 1.3, graftWeight: 1.0,
            generationSeed: 11, maxVertexBudget: 10_000
        )
        let a = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(a, b)
    }

    func testGraftMatchLengthScalesEdgeToTargetLength() {
        // makeSquare's edges are all length 1.0; a plain n=4 primitive's own
        // edges are all shorter (~0.707, the diamond's side) and, being regular,
        // all equal — so scaling uniformly around the source site's point to
        // match one edge's length scales every edge by the same factor. Under
        // .matchLength every edge of the placed piece should end up at length
        // 1.0 (the target's); under .preserveSize, unchanged at the primitive's
        // own native length.
        let square = makeSquare()
        let piece = AssemblyPrimitiveKit.plainPolygon(sides: 4)
        let nativeEdgeLength = piece.points[0].distance(to: piece.points[1])
        XCTAssertGreaterThan(nativeEdgeLength, 0)
        XCTAssertNotEqual(nativeEdgeLength, 1.0, accuracy: 1e-6, "fixture assumption: native and target lengths must differ for this test to be meaningful")

        func placedEdgeLength(_ edgeMatching: AssemblyEdgeMatching) -> Double {
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: 5, maxVertexBudget: 10_000
            )
            params.graftEdgeMatching = edgeMatching
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            return result[1].points[0].distance(to: result[1].points[1])
        }

        XCTAssertEqual(placedEdgeLength(.preserveSize), nativeEdgeLength, accuracy: 1e-9)
        XCTAssertEqual(placedEdgeLength(.matchLength), 1.0, accuracy: 1e-9)
    }

    func testGraftNeverTargetsOpenCurveWhenMixedWithClosedPolygon() {
        for seed in 0..<25 {
            let square = makeSquare()
            let curve = makeOpenCurve()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square, curve], params: params)
            XCTAssertEqual(result.count, 3, "seed \(seed): graft should always find the closed polygon eligible")
            XCTAssertEqual(result[1], curve, "seed \(seed): the open curve itself must be untouched")
        }
    }

    /// Graft gained open-curve support alongside Split (this section, 2026-07-11)
    /// — `.wholeEdge` targets an open curve exactly like a closed polygon's edge,
    /// via the same roll-independent site-coincidence invariant the closed-polygon
    /// version of this test already uses (`place()` guarantees the source site's
    /// point lands exactly on the target's, regardless of which site/mirror/
    /// edge-matching was rolled) — only the segIdx roll needs replicating.
    func testGraftWholeEdgeTargetsOpenCurveWhenIncludeOpenCurvesIsOn() {
        for seed in 0..<20 {
            let curve = makeOpenCurve()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                includeOpenCurves: true,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed): expected a grafted piece on the open curve") }
            XCTAssertEqual(result[0], curve, "seed \(seed): .wholeEdge is non-destructive to the parent")

            let segCount = curve.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let base = segIdx * 4
            let a0 = curve.points[base]
            let a1 = curve.points[base + 3]
            let expectedMid = Vector2D(x: (a0.x + a1.x) / 2, y: (a0.y + a1.y) / 2)

            let placedSites = AttachmentSiteExtractor.sites(of: result[1])
            let closest = placedSites.map { $0.point.distance(to: expectedMid) }.min() ?? .infinity
            XCTAssertEqual(closest, 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    // MARK: - Graft: custom primitive source (2026-07-12)

    /// A simple closed pentagon ("house" shape) — distinctive enough that
    /// matching its exact point count/shape in the output proves the pipeline
    /// used *this* shape rather than a generated n-gon.
    private func customHouseShape() -> Polygon2D {
        let corners = [
            Vector2D(x: -0.1, y: 0), Vector2D(x: 0.1, y: 0), Vector2D(x: 0.1, y: 0.15),
            Vector2D(x: 0, y: 0.25), Vector2D(x: -0.1, y: 0.15),
        ]
        var pts = [Vector2D]()
        for i in 0..<5 {
            pts += BezierMath.connector(from: corners[i], to: corners[(i + 1) % 5],
                                        cpRatios: Vector2D(x: 1.0 / 3.0, y: 2.0 / 3.0))
        }
        return Polygon2D(points: pts, type: .spline)
    }

    func testGraftWholeEdgeAttachesACustomClosedShapeVerbatim() {
        // Before the .spline case existed on AttachmentSiteExtractor, this shape
        // would have exposed zero attachment sites and every generation would
        // have been silently skipped (result.count == 1 forever).
        let house = customHouseShape()
        for seed in 0..<15 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftPrimitiveSource: .customSet, graftCustomShapes: [GraftCustomShapeEntry(name: "house")],
                graftWeight: 1.0, generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(
                polygons: [square], params: params, customPrimitives: ["house": house]
            )
            guard result.count == 2 else { return XCTFail("seed \(seed): expected the custom shape to attach") }
            XCTAssertEqual(result[0], square, "seed \(seed): .wholeEdge is non-destructive to the parent")
            XCTAssertEqual(result[1].points.count, house.points.count,
                            "seed \(seed): the attached piece must be the custom shape, not a generated n-gon")

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let base = segIdx * 4
            let a0 = square.points[base], a1 = square.points[base + 3]
            let expectedMid = Vector2D(x: (a0.x + a1.x) / 2, y: (a0.y + a1.y) / 2)

            let placedSites = AttachmentSiteExtractor.sites(of: result[1])
            let closest = placedSites.map { $0.point.distance(to: expectedMid) }.min() ?? .infinity
            XCTAssertEqual(closest, 0, accuracy: 1e-9, "seed \(seed): custom shape must coincide with the target edge")
        }
    }

    func testGraftWholeEdgeAttachesACustomOpenCurveShape() {
        // Before openCurveEligibleSites existed, a custom .openSpline piece's
        // endpoint sites had length == nil, which .wholeEdge's edge-type-site
        // gate rejected outright — every generation silently no-op'd
        // (result.count == 1 forever), the exact bug reported for open-curve
        // custom Graft targets (2026-07-12).
        let curve = makeOpenCurve(segments: 2)
        for seed in 0..<15 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftPrimitiveSource: .customSet, graftCustomShapes: [GraftCustomShapeEntry(name: "curve")],
                graftWeight: 1.0, generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(
                polygons: [square], params: params, customPrimitives: ["curve": curve]
            )
            guard result.count == 2 else { return XCTFail("seed \(seed): expected the custom open curve to attach") }
            XCTAssertEqual(result[0], square, "seed \(seed): .wholeEdge is non-destructive to the parent")
            XCTAssertEqual(result[1].points.count, curve.points.count,
                            "seed \(seed): the attached piece must be the custom curve, not a generated primitive")
        }
    }

    func testGraftPartialEdgeAttachesACustomOpenCurveShape() {
        let curve = makeOpenCurve(segments: 2)
        for seed in 0..<15 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftPrimitiveSource: .customSet, graftCustomShapes: [GraftCustomShapeEntry(name: "curve")],
                graftWeight: 1.0, graftAttachmentMode: .partialEdge,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(
                polygons: [square], params: params, customPrimitives: ["curve": curve]
            )
            guard result.count == 2 else { return XCTFail("seed \(seed): expected the custom open curve to attach") }
        }
    }

    func testGraftGeneratedDegenerateLineStaysIneligibleForWholeEdgeEvenThoughCustomOpenCurvesNowAre() {
        // Regression: openCurveEligibleSites must be scoped to isCustomSourced —
        // the *generated* n=1 fallback (also a bare two-point .openSpline) must
        // keep no-oping for .wholeEdge, distinct from a genuine custom open curve.
        for seed in 0..<10 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 1, graftSidesMax: 1, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertEqual(result, [square], "seed \(seed)")
        }
    }

    func testGraftCustomPrimitivesParameterHasNoEffectWhenSourceIsGenerated() {
        // Regression: passing a non-empty customPrimitives cache must not alter
        // .generated (default) output at all.
        let house = customHouseShape()
        for seed in 0..<10 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let withCache    = GenerationalEvolutionEngine.process(polygons: [square], params: params, customPrimitives: ["house": house])
            let withoutCache = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertEqual(withCache, withoutCache, "seed \(seed)")
        }
    }

    func testGraftSinglePointTargetsOpenCurveWhenIncludeOpenCurvesIsOn() {
        for seed in 0..<15 {
            let curve = makeOpenCurve()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                includeOpenCurves: true,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint, graftPointSource: .existingVertex,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [curve], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed): expected a grafted piece on the open curve") }
            XCTAssertEqual(result[0], curve, "seed \(seed): .existingVertex must not touch the parent curve")

            let segCount = curve.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let expectedAnchor = curve.points[segIdx * 4]

            let placedSites = AttachmentSiteExtractor.sites(of: result[1])
            let closest = placedSites.map { $0.point.distance(to: expectedAnchor) }.min() ?? .infinity
            XCTAssertEqual(closest, 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    func testGraftCanTargetEitherShapeInMixedSetWhenIncludeOpenCurvesIsOn() {
        // .wholeEdge is non-destructive to whichever shape it targets, so
        // "which shape changed" can't tell targets apart here — replicate the
        // targetRoll (cycleBase+1) directly instead, same as `graftTargetSegIdx`
        // replicates the segIdx roll elsewhere in this file. Both polygons pass
        // the eligible-list filter (square is .spline, curve is .openSpline with
        // includeOpenCurves on, both ≥4 points), so `eligible == [0, 1]` exactly
        // matches the array's own indices.
        let square = makeSquare()
        let curve = makeOpenCurve()
        var curveWasGrafted = false
        var squareWasGrafted = false
        for seedTry in 0..<40 {
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                includeOpenCurves: true,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: seedTry, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square, curve], params: params)
            guard result.count == 3 else { continue }

            let targetRoll = SubdivisionEngine.centreHash(seed: seedTry, cycle: 1)  // cycleBase 0 + 1
            let targetIdx  = min(1, Int(targetRoll * 2.0))
            if targetIdx == 0 { squareWasGrafted = true } else { curveWasGrafted = true }
        }
        XCTAssertTrue(curveWasGrafted, "across 40 seeds, Graft should target the open curve at least once")
        XCTAssertTrue(squareWasGrafted, "across 40 seeds, Graft should also still target the closed polygon at least once")
    }

    func testGraftWeightZeroExcludesGraftFromSelection() {
        // graftSidesMin/Max forced to a shape (heptagon, 7 raw vertices) neither
        // Extrude (16-point .spline quads) nor Split (no new polygons) could ever
        // produce — with graftWeight left at 0 (default), no .line-type 7-point
        // polygon should ever appear across many seeds/generations.
        for seed in 0..<25 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 5, extrudeWeight: 1.0, splitWeight: 1.0,  // graftWeight defaults to 0.0
                graftSidesMin: 7, graftSidesMax: 7,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertFalse(result.contains { $0.type == .line && $0.points.count == 7 }, "seed \(seed)")
        }
    }

    // MARK: - Graft operator, §4.4.8.6 step 3 (.singlePoint attachment)

    func testGraftSinglePointExistingVertexIsNonDestructiveToParent() {
        for seed in 0..<20 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint, graftPointSource: .existingVertex,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertEqual(result.count, 2, "seed \(seed)")
            XCTAssertEqual(result[0], square, "seed \(seed): .existingVertex must not touch the parent's own points")
        }
    }

    func testGraftSinglePointNewlyInsertedPointMutatesParentBySplitting() {
        for seed in 0..<20 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint, graftPointSource: .newlyInsertedPoint,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertEqual(result.count, 2, "seed \(seed)")
            XCTAssertEqual(result[0].points.count, square.points.count + 4,
                            "seed \(seed): one segment split into two nets +4 points, same as Split")
            XCTAssertNotEqual(result[0], square, "seed \(seed)")
        }
    }

    func testGraftSinglePointExistingVertexCoincidesExactlyWithChosenAnchor() {
        for seed in 0..<20 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint, graftPointSource: .existingVertex,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed): expected a grafted piece") }

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let expectedAnchor = square.points[segIdx * 4]

            let placedSites = AttachmentSiteExtractor.sites(of: result[1])
            let closest = placedSites.map { $0.point.distance(to: expectedAnchor) }.min() ?? .infinity
            XCTAssertEqual(closest, 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    func testGraftSinglePointNewlyInsertedPointCoincidesExactlyWithSplitAnchor() {
        for seed in 0..<20 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint, graftPointSource: .newlyInsertedPoint,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed): expected a grafted piece") }

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let base = segIdx * 4
            let seg = Array(square.points[base..<(base + 4)])
            // default splitPositionMin/Max is 0.5–0.5, so the split is always
            // exactly at the midpoint — same convention Split itself uses.
            let expectedSplitPt = BezierMath.split(seg: seg, t: 0.5).left[3]

            // The parent's own new anchor must land exactly there too (undisplaced —
            // unlike Split, Graft's singlePoint attachment never moves the anchor).
            let newAnchors = (0..<(result[0].points.count / 4)).map { result[0].points[$0 * 4] }
                .filter { anchor in !(0..<4).contains { square.points[$0 * 4].distance(to: anchor) < 1e-9 } }
            XCTAssertEqual(newAnchors.count, 1, "seed \(seed)")
            if let newAnchor = newAnchors.first {
                XCTAssertEqual(newAnchor.distance(to: expectedSplitPt), 0, accuracy: 1e-9, "seed \(seed)")
            }

            let placedSites = AttachmentSiteExtractor.sites(of: result[1])
            let closest = placedSites.map { $0.point.distance(to: expectedSplitPt) }.min() ?? .infinity
            XCTAssertEqual(closest, 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    func testGraftSinglePointDefaultDepartureIsExactlyOutward() {
        // 0–0 (default) departure angle: the grafted piece departs along the
        // edge's own unrotated outward normal — verified by checking the piece's
        // centroid lies on the ray from the anchor along that exact normal.
        let square = makeSquare()
        for seed in 0..<10 {
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftDistortionMin: 1.0, graftDistortionMax: 1.0, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint, graftPointSource: .existingVertex,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed): expected a grafted piece") }

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let anchor = square.points[segIdx * 4]
            let expectedNormal = ExtensionEngine.outwardNormal(of: square, segIdx: segIdx)

            let offset = result[1].centroid - anchor
            XCTAssertGreaterThan(offset.length, 1e-6, "seed \(seed)")
            let cosAngle = offset.normalized().dot(expectedNormal)
            XCTAssertEqual(cosAngle, 1.0, accuracy: 1e-6, "seed \(seed)")
        }
    }

    func testGraftSinglePointDepartureAngleRotatesPlacementAroundAnchor() {
        let square = makeSquare()

        func centroidOffsetFromAnchor(angle: Double) -> Vector2D {
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint,
                graftDepartureAngleMin: angle, graftDepartureAngleMax: angle, graftPointSource: .existingVertex,
                generationSeed: 3, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: 3, segCount: segCount)
            let anchor = square.points[segIdx * 4]
            return result[1].centroid - anchor
        }

        let v0  = centroidOffsetFromAnchor(angle: 0)
        let vPi = centroidOffsetFromAnchor(angle: .pi)
        XCTAssertGreaterThan(v0.length, 1e-6)
        XCTAssertGreaterThan(vPi.length, 1e-6)
        let cosBetween = v0.normalized().dot(vPi.normalized())
        XCTAssertEqual(cosBetween, -1.0, accuracy: 1e-6, "a π departure-angle offset should place the piece diametrically opposite")
    }

    func testGraftSinglePointPlacesEvenWhenPrimitiveDegeneratesToLine() {
        // Unlike .wholeEdge, .singlePoint has no edge-type-site requirement — a
        // rolled n≤2 primitive (point-type sites only) is still placeable.
        for seed in 0..<10 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 1, graftSidesMax: 1, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertEqual(result.count, 2, "seed \(seed)")
            XCTAssertEqual(result[1].type, .openSpline, "seed \(seed)")
        }
    }

    func testGraftSinglePointIsDeterministic() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 3, extrudeWeight: 0.0, splitWeight: 0.0,
            graftSidesMin: 3, graftSidesMax: 6, graftDistortionMin: 0.7, graftDistortionMax: 1.3, graftWeight: 1.0,
            graftAttachmentMode: .singlePoint,
            graftDepartureAngleMin: -1.0, graftDepartureAngleMax: 1.0, graftPointSource: .newlyInsertedPoint,
            generationSeed: 11, maxVertexBudget: 10_000
        )
        let a = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(a, b)
    }

    // MARK: - Graft operator, §4.4.8.6 step 4 (.partialEdge attachment)

    /// Replicates `applyGraftPartialEdge`'s tStart/tEnd rolls independently —
    /// same idea as `graftTargetSegIdx` above, needed to compute the
    /// analytically-known sub-segment for the geometry-exact checks below.
    private func graftPartialSubSegment(
        seed: Int, cycleBase: Int = 0, square: Polygon2D, segIdx: Int,
        posLo: Double, posHi: Double, spanLo: Double, spanHi: Double
    ) -> (mid: Vector2D, length: Double) {
        let graftSeed = seed &+ 918_273_645
        let posRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 6)
        let tStart = max(0.0, min(1.0, posLo + posRoll * (posHi - posLo)))
        let spanRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: cycleBase + 7)
        let span = max(0.0, min(1.0, spanLo + spanRoll * (spanHi - spanLo)))
        let tEnd = max(tStart, min(1.0, tStart + span * (1.0 - tStart)))

        let base = segIdx * 4
        let seg = Array(square.points[base..<(base + 4)])
        let subStart = BezierMath.point(seg: seg, t: tStart)
        let subEnd   = BezierMath.point(seg: seg, t: tEnd)
        let mid = Vector2D(x: (subStart.x + subEnd.x) / 2, y: (subStart.y + subEnd.y) / 2)
        return (mid: mid, length: subStart.distance(to: subEnd))
    }

    func testGraftPartialEdgeDefaultReproducesWholeEdgeFullSpan() {
        // 0–0 position / 1–1 span (default) covers the whole edge, exactly
        // like .wholeEdge — same roll-independent site-coincidence invariant
        // used for the other two attachment modes' geometry-exact tests.
        for seed in 0..<20 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .partialEdge,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed): expected a grafted piece") }

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let base = segIdx * 4
            let a0 = square.points[base]
            let a1 = square.points[base + 3]
            let expectedMid = Vector2D(x: (a0.x + a1.x) / 2, y: (a0.y + a1.y) / 2)

            let placedSites = AttachmentSiteExtractor.sites(of: result[1])
            let closest = placedSites.map { $0.point.distance(to: expectedMid) }.min() ?? .infinity
            XCTAssertEqual(closest, 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    func testGraftPartialEdgeCoincidesExactlyWithNarrowedSubSegmentMidpoint() {
        for seed in 0..<20 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .partialEdge,
                graftPartialPositionMin: 0.1, graftPartialPositionMax: 0.4,
                graftPartialSpanMin: 0.2, graftPartialSpanMax: 0.5,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed): expected a grafted piece") }

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let expected = graftPartialSubSegment(
                seed: seed, square: square, segIdx: segIdx,
                posLo: 0.1, posHi: 0.4, spanLo: 0.2, spanHi: 0.5
            )

            let placedSites = AttachmentSiteExtractor.sites(of: result[1])
            let closest = placedSites.map { $0.point.distance(to: expected.mid) }.min() ?? .infinity
            XCTAssertEqual(closest, 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    func testGraftPartialEdgeMatchLengthScalesToSubSegmentLengthNotFullEdge() {
        // A narrowed span's sub-segment is strictly shorter than the full
        // (length-1.0) edge — under .matchLength, the placed piece's matched
        // edge should scale to that shorter sub-segment length, not the
        // parent's full edge length the way .wholeEdge's equivalent test does.
        let square = makeSquare()
        let seed = 5
        let posLo = 0.1, posHi = 0.1, spanLo = 0.3, spanHi = 0.3
        let segCount = square.points.count / 4
        let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
        let expected = graftPartialSubSegment(
            seed: seed, square: square, segIdx: segIdx,
            posLo: posLo, posHi: posHi, spanLo: spanLo, spanHi: spanHi
        )
        XCTAssertLessThan(expected.length, 1.0, "fixture assumption: the narrowed sub-segment must be shorter than the full unit edge")

        var params = EvolutionParams(
            generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
            graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
            graftAttachmentMode: .partialEdge,
            graftPartialPositionMin: posLo, graftPartialPositionMax: posHi,
            graftPartialSpanMin: spanLo, graftPartialSpanMax: spanHi,
            generationSeed: seed, maxVertexBudget: 10_000
        )
        params.graftEdgeMatching = .matchLength
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        guard result.count == 2 else { return XCTFail("expected a grafted piece") }

        let placedEdgeLength = result[1].points[0].distance(to: result[1].points[1])
        XCTAssertEqual(placedEdgeLength, expected.length, accuracy: 1e-9)
    }

    func testGraftPartialEdgeNonDestructiveToParent() {
        for seed in 0..<10 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .partialEdge,
                graftPartialPositionMin: 0.2, graftPartialPositionMax: 0.2,
                graftPartialSpanMin: 0.5, graftPartialSpanMax: 0.5,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertEqual(result.count, 2, "seed \(seed)")
            XCTAssertEqual(result[0], square, "seed \(seed): .partialEdge must not touch the parent's own points")
        }
    }

    func testGraftPartialEdgeSkippedWhenPrimitiveDegeneratesToLine() {
        for seed in 0..<10 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 1, graftSidesMax: 1, graftWeight: 1.0,
                graftAttachmentMode: .partialEdge,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertEqual(result, [square], "seed \(seed)")
        }
    }

    func testGraftPartialEdgeZeroSpanIsNoOp() {
        // span forced to exactly 0 collapses the sub-segment to a single
        // point (tEnd == tStart) — the same zero-length guard applyGraftWholeEdge
        // and applyGraftSinglePoint both already rely on for their own
        // degenerate cases should make this a no-op generation.
        for seed in 0..<10 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .partialEdge,
                graftPartialSpanMin: 0.0, graftPartialSpanMax: 0.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            XCTAssertEqual(result, [square], "seed \(seed)")
        }
    }

    func testGraftPartialEdgeIsDeterministic() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 3, extrudeWeight: 0.0, splitWeight: 0.0,
            graftSidesMin: 3, graftSidesMax: 6, graftDistortionMin: 0.7, graftDistortionMax: 1.3, graftWeight: 1.0,
            graftAttachmentMode: .partialEdge,
            graftPartialPositionMin: 0.0, graftPartialPositionMax: 0.6,
            graftPartialSpanMin: 0.2, graftPartialSpanMax: 0.8,
            generationSeed: 11, maxVertexBudget: 10_000
        )
        let a = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(a, b)
    }

    // MARK: - Graft operator, §4.4.8.6 step 5 (curvature + articulation)

    func testGraftEdgeDetailingIsNoOpByDefault() {
        // Untouched curvature/articulation defaults (all off) must leave the
        // placed piece exactly as .wholeEdge alone would have produced it —
        // still .line-type, never converted to .spline.
        for seed in 0..<10 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed)") }
            XCTAssertEqual(result[1].type, .line, "seed \(seed)")
            XCTAssertEqual(result[1].points.count, 4, "seed \(seed)")
        }
    }

    func testGraftCurvatureBowsFreeEdgesExactlyButLeavesRootStraight() {
        // probability 1.0 and a degenerate (min==max) amount range remove all
        // randomness from the curvature step itself, leaving only the
        // existing sourceSiteRoll (already independently replicated by other
        // step-2 tests) to identify which edge is "the root."
        for seed in 0..<15 {
            let square = makeSquare()
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            params.graftEdgeCurvatureProbability = 1.0
            params.graftEdgeCurvatureAmountMin = 0.2
            params.graftEdgeCurvatureAmountMax = 0.2

            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed)") }
            let placed = result[1]
            XCTAssertEqual(placed.type, .spline, "seed \(seed): curvature forces .line -> .spline conversion")
            let segCount = placed.points.count / 4
            XCTAssertEqual(segCount, 4, "seed \(seed)")

            let graftSeed = seed &+ 918_273_645
            let sourceRoll = SubdivisionEngine.centreHash(seed: graftSeed, cycle: 2)
            let rootIdx = min(3, Int(sourceRoll * 4))

            for i in 0..<segCount {
                let base = i * 4
                let a0 = placed.points[base], cp1 = placed.points[base + 1]
                let cp2 = placed.points[base + 2], a1 = placed.points[base + 3]
                let straightCp1 = Vector2D.lerp(a0, a1, t: 1.0 / 3.0)
                let straightCp2 = Vector2D.lerp(a0, a1, t: 2.0 / 3.0)

                if i == rootIdx {
                    XCTAssertEqual(cp1.distance(to: straightCp1), 0, accuracy: 1e-9, "seed \(seed) edge \(i) (root)")
                    XCTAssertEqual(cp2.distance(to: straightCp2), 0, accuracy: 1e-9, "seed \(seed) edge \(i) (root)")
                } else {
                    let dx = a1.x - a0.x, dy = a1.y - a0.y
                    let len = (dx * dx + dy * dy).squareRoot()
                    let normal = Vector2D(x: -dy / len, y: dx / len)
                    let bow = 0.2 * len
                    let expectedCp1 = straightCp1 + normal * bow
                    let expectedCp2 = straightCp2 + normal * bow
                    XCTAssertEqual(cp1.distance(to: expectedCp1), 0, accuracy: 1e-9, "seed \(seed) edge \(i)")
                    XCTAssertEqual(cp2.distance(to: expectedCp2), 0, accuracy: 1e-9, "seed \(seed) edge \(i)")
                    XCTAssertGreaterThan(cp1.distance(to: straightCp1), 1e-6, "seed \(seed) edge \(i): should actually be bowed")
                }
            }
        }
    }

    func testGraftArticulationProducesExactSegCountAndStaysClosed() {
        // jointCount fixed to 2 (min == max): 3 non-root edges each become 3
        // sub-segments, the root edge stays 1 — 3*3 + 1 = 10 total.
        for seed in 0..<15 {
            let square = makeSquare()
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            params.graftArticulationCountMin = 2
            params.graftArticulationCountMax = 2
            params.graftArticulationAmountMin = 0.05
            params.graftArticulationAmountMax = 0.15

            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed)") }
            let placed = result[1]
            XCTAssertEqual(placed.type, .spline, "seed \(seed)")
            let segCount = placed.points.count / 4
            XCTAssertEqual(segCount, 10, "seed \(seed)")

            for i in 0..<segCount {
                let thisEnd = placed.points[i * 4 + 3]
                let nextStart = placed.points[((i + 1) % segCount) * 4]
                XCTAssertEqual(thisEnd.distance(to: nextStart), 0, accuracy: 1e-9, "seed \(seed) join \(i)")
            }
        }
    }

    func testGraftArticulationOnOpenSplinePreservesCoincidenceWithParentAnchor() {
        // n=1 via .singlePoint/.existingVertex: the piece's source site is
        // point-type (no root edge to exclude), so its lone segment is fully
        // eligible for articulation — the parent-side coincidence invariant
        // (already proven edge-detailing-free by earlier step-3 tests) must
        // still hold once articulation is layered on, since articulation only
        // ever moves *interior* joints, never the two original endpoints.
        for seed in 0..<15 {
            let square = makeSquare()
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 1, graftSidesMax: 1, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint, graftPointSource: .existingVertex,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            params.graftArticulationCountMin = 2
            params.graftArticulationCountMax = 2
            params.graftArticulationAmountMin = 0.1
            params.graftArticulationAmountMax = 0.1

            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed)") }
            let placed = result[1]
            XCTAssertEqual(placed.type, .openSpline, "seed \(seed)")
            XCTAssertEqual(placed.points.count, 12, "seed \(seed): 1 edge, 2 joints -> 3 sub-segments")

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let expectedAnchor = square.points[segIdx * 4]

            let firstPoint = placed.points[0]
            let lastPoint  = placed.points[placed.points.count - 1]
            let closest = min(firstPoint.distance(to: expectedAnchor), lastPoint.distance(to: expectedAnchor))
            XCTAssertEqual(closest, 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    func testGraftArticulationZigZagAlternatesSignExactly() {
        // n=1, jointCount=2, degenerate (min==max) amount removes magnitude
        // randomness — only the deterministic zigzag sign pattern is left,
        // verifiable exactly against straight-chord interpolation (a
        // collinear-control-point cubic Bézier evaluates identically to
        // linear lerp at any t, so no piece-generation replication is needed).
        for seed in 0..<15 {
            let square = makeSquare()
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 1, graftSidesMax: 1, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint, graftPointSource: .existingVertex,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            params.graftArticulationCountMin = 2
            params.graftArticulationCountMax = 2
            params.graftArticulationAmountMin = 0.3
            params.graftArticulationAmountMax = 0.3
            params.graftArticulationPattern = .zigzag

            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed)") }
            let placed = result[1]
            guard placed.points.count == 12 else { return XCTFail("seed \(seed)") }

            let a0 = placed.points[0], a1 = placed.points[11]
            let joint1 = placed.points[3], joint2 = placed.points[7]

            let dx = a1.x - a0.x, dy = a1.y - a0.y
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 1e-9 else { continue }
            let perp = Vector2D(x: -dy / len, y: dx / len)

            let base1 = Vector2D.lerp(a0, a1, t: 1.0 / 3.0)
            let base2 = Vector2D.lerp(a0, a1, t: 2.0 / 3.0)
            // `a0`/`a1` here are read directly from the final placed geometry
            // (preserved exactly through detailing), so `perp` is computed
            // from literally the same inputs `articulatedSubSegments` itself
            // uses internally — no sign ambiguity to reconcile.
            let expectedJoint1 = base1 + perp * 0.3
            let expectedJoint2 = base2 + perp * (-0.3)
            XCTAssertEqual(joint1.distance(to: expectedJoint1), 0, accuracy: 1e-9, "seed \(seed)")
            XCTAssertEqual(joint2.distance(to: expectedJoint2), 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    func testGraftArticulationAmountIsEdgeLengthRelativeNotAbsolute() {
        // graftScaleMin/Max fixed well below 1 (0.2) makes the piece's own
        // edge length 0.2, not 1 — proving `graftArticulationAmountMin/Max`
        // scales the displacement by that edge length (`amount * len`, the
        // same convention `graftEdgeCurvatureAmountMin/Max` already uses)
        // rather than applying a fixed canvas-scale magnitude regardless of
        // how small the graft piece itself was scaled down to. Before this
        // was edge-relative, this test's expected joints would have used the
        // raw 0.3 amount directly (0.06 here is 0.3 * 0.2), a displacement
        // 5x the length of the entire piece it's supposedly detailing.
        for seed in 0..<15 {
            let square = makeSquare()
            var params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 1, graftSidesMax: 1, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint, graftPointSource: .existingVertex,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            params.graftScaleMin = 0.2
            params.graftScaleMax = 0.2
            params.graftArticulationCountMin = 2
            params.graftArticulationCountMax = 2
            params.graftArticulationAmountMin = 0.3
            params.graftArticulationAmountMax = 0.3
            params.graftArticulationPattern = .zigzag

            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            guard result.count == 2 else { return XCTFail("seed \(seed)") }
            let placed = result[1]
            guard placed.points.count == 12 else { return XCTFail("seed \(seed)") }

            let a0 = placed.points[0], a1 = placed.points[11]
            let joint1 = placed.points[3], joint2 = placed.points[7]

            let dx = a1.x - a0.x, dy = a1.y - a0.y
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 1e-9 else { continue }
            XCTAssertEqual(len, 0.2, accuracy: 1e-9, "seed \(seed): piece edge should be scaled to 0.2")
            let perp = Vector2D(x: -dy / len, y: dx / len)

            let base1 = Vector2D.lerp(a0, a1, t: 1.0 / 3.0)
            let base2 = Vector2D.lerp(a0, a1, t: 2.0 / 3.0)
            let expectedJoint1 = base1 + perp * (0.3 * len)
            let expectedJoint2 = base2 + perp * (-0.3 * len)
            XCTAssertEqual(joint1.distance(to: expectedJoint1), 0, accuracy: 1e-9, "seed \(seed)")
            XCTAssertEqual(joint2.distance(to: expectedJoint2), 0, accuracy: 1e-9, "seed \(seed)")
        }
    }

    func testGraftEdgeDetailingIsDeterministic() {
        let square = makeSquare()
        var params = EvolutionParams(
            generationCount: 3, extrudeWeight: 0.0, splitWeight: 0.0,
            graftSidesMin: 3, graftSidesMax: 6, graftDistortionMin: 0.7, graftDistortionMax: 1.3, graftWeight: 1.0,
            generationSeed: 11, maxVertexBudget: 10_000
        )
        params.graftEdgeCurvatureProbability = 0.6
        params.graftEdgeCurvatureAmountMin = 0.05
        params.graftEdgeCurvatureAmountMax = 0.2
        params.graftArticulationCountMin = 0
        params.graftArticulationCountMax = 3
        params.graftArticulationAmountMin = 0.02
        params.graftArticulationAmountMax = 0.1
        params.graftArticulationPattern = .zigzag

        let a = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(a, b)
    }

    // MARK: - includeOpenCurves legacy-key decode migration

    /// Existing saved projects (from before the Extrude-only toggle was
    /// generalized to all three operators) only ever wrote the old JSON key.
    /// Confirms they still load with open-curve support enabled rather than
    /// silently resetting to the new field's `false` default.
    func testIncludeOpenCurvesDecodesFromLegacyExtrudeKeyName() throws {
        let json = #"{ "name": "legacy", "extrudeIncludeOpenCurves": true }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EvolutionParams.self, from: json)
        XCTAssertTrue(decoded.includeOpenCurves)
    }

    func testIncludeOpenCurvesDefaultsFalseWhenNeitherKeyPresent() throws {
        let json = #"{ "name": "fresh" }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EvolutionParams.self, from: json)
        XCTAssertFalse(decoded.includeOpenCurves)
    }

    func testIncludeOpenCurvesPrefersNewKeyOverLegacyWhenBothPresent() throws {
        // A project re-saved by a build that writes the new key — the new key
        // should win even if a stale legacy key is also somehow still present.
        let json = #"{ "name": "resaved", "includeOpenCurves": false, "extrudeIncludeOpenCurves": true }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EvolutionParams.self, from: json)
        XCTAssertFalse(decoded.includeOpenCurves)
    }

    // MARK: - Graft reveal tween (strength)

    /// `process(polygons:params:phase:)` never actually produces `strength == 0`
    /// exactly through the public API (a `partial` of 0 short-circuits before
    /// `applyGeneration` is even called — see its own `guard partial > 1e-9`), so
    /// this compares an explicit half-strength phase against the fully-applied
    /// (strength 1.0) result instead: every point of the half-strength piece must
    /// sit exactly halfway between the anchor and the corresponding full-strength
    /// point — a roll-independent invariant (both runs share every roll except the
    /// final reveal-scale step, so point order/count/identity match exactly).
    func testGraftWholeEdgeRevealTweensExactlyAtHalfStrength() {
        for seed in 0..<10 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let fullResult = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            let halfResult = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 0.5)
            guard fullResult.count == 2, halfResult.count == 2 else { return XCTFail("seed \(seed)") }
            let fullPiece = fullResult[1], halfPiece = halfResult[1]
            guard fullPiece.points.count == halfPiece.points.count else {
                return XCTFail("seed \(seed): reveal tween must not change point structure")
            }

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let base = segIdx * 4
            let a0 = square.points[base], a1 = square.points[base + 3]
            let anchor = Vector2D(x: (a0.x + a1.x) / 2, y: (a0.y + a1.y) / 2)

            for i in 0..<fullPiece.points.count {
                let expectedHalf = Vector2D(x: anchor.x + (fullPiece.points[i].x - anchor.x) * 0.5,
                                             y: anchor.y + (fullPiece.points[i].y - anchor.y) * 0.5)
                XCTAssertEqual(halfPiece.points[i].distance(to: expectedHalf), 0, accuracy: 1e-9, "seed \(seed) point \(i)")
            }
        }
    }

    func testGraftSinglePointRevealTweensExactlyAtHalfStrength() {
        for seed in 0..<10 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
                graftAttachmentMode: .singlePoint, graftPointSource: .existingVertex,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let fullResult = GenerationalEvolutionEngine.process(polygons: [square], params: params)
            let halfResult = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 0.5)
            guard fullResult.count == 2, halfResult.count == 2 else { return XCTFail("seed \(seed)") }
            let fullPiece = fullResult[1], halfPiece = halfResult[1]
            guard fullPiece.points.count == halfPiece.points.count else {
                return XCTFail("seed \(seed): reveal tween must not change point structure")
            }

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let anchor = square.points[segIdx * 4]

            for i in 0..<fullPiece.points.count {
                let expectedHalf = Vector2D(x: anchor.x + (fullPiece.points[i].x - anchor.x) * 0.5,
                                             y: anchor.y + (fullPiece.points[i].y - anchor.y) * 0.5)
                XCTAssertEqual(halfPiece.points[i].distance(to: expectedHalf), 0, accuracy: 1e-9, "seed \(seed) point \(i)")
            }
        }
    }

    func testGraftRevealTweenIsDeterministic() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
            graftSidesMin: 4, graftSidesMax: 4, graftWeight: 1.0,
            generationSeed: 5, maxVertexBudget: 10_000
        )
        let a = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 0.3)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 0.3)
        XCTAssertEqual(a, b)
    }

    // MARK: - Graft: orientation control (2026-07-13)

    /// A single-segment open curve running straight up from local (0,0) to
    /// local (0,1) — an unambiguous "lowest" endpoint site (y=0) distinct from
    /// its "highest" one (y=1), used to prove which site `.lowestPoint`
    /// connector selection actually picks.
    private func verticalCurve() -> Polygon2D {
        Polygon2D(points: [
            Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0.33), Vector2D(x: 0, y: 0.67), Vector2D(x: 0, y: 1),
        ], type: .openSpline)
    }

    func testGraftConnectorSelectionLowestPointAlwaysUsesTheLowerEndpointRegardlessOfSeed() {
        let curve = verticalCurve()
        for seed in 0..<20 {
            let square = makeSquare()
            let params = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftPrimitiveSource: .customSet, graftCustomShapes: [GraftCustomShapeEntry(name: "curve")],
                graftWeight: 1.0, graftAttachmentMode: .singlePoint,
                graftConnectorSelection: .lowestPoint,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(
                polygons: [square], params: params, customPrimitives: ["curve": curve]
            )
            guard result.count == 2 else { return XCTFail("seed \(seed): expected the custom curve to attach") }

            let segCount = square.points.count / 4
            let segIdx = graftTargetSegIdx(seed: seed, segCount: segCount)
            let anchor = square.points[segIdx * 4]  // .existingVertex default: the segment's own start anchor

            // The curve's own local (0,0) point (its lowest site, index 0 in
            // `.points` — array position is preserved through place()'s
            // transform regardless of rotation/mirroring) must always be the
            // one coincident with the parent's anchor, never the local (0,1)
            // (highest) point at index 3.
            XCTAssertEqual(result[1].points[0].distance(to: anchor), 0, accuracy: 1e-6, "seed \(seed)")
        }
    }

    func testGraftOrientationAmountRotatesThePieceAroundItsAnchorByExactlyTheSampledFraction() {
        let curve = verticalCurve()
        for seed in 0..<10 {
            func run(orientation: Double) -> Polygon2D {
                let square = makeSquare()
                let params = EvolutionParams(
                    generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                    graftPrimitiveSource: .customSet, graftCustomShapes: [GraftCustomShapeEntry(name: "curve")],
                    graftWeight: 1.0, graftAttachmentMode: .singlePoint,
                    graftConnectorSelection: .lowestPoint,
                    graftOrientationAmountMin: orientation, graftOrientationAmountMax: orientation,
                    generationSeed: seed, maxVertexBudget: 10_000
                )
                let result = GenerationalEvolutionEngine.process(
                    polygons: [square], params: params, customPrimitives: ["curve": curve]
                )
                return result[1]
            }

            let base = run(orientation: 0.0)
            let rotated = run(orientation: 0.25)  // a quarter turn = 90°

            // Anchor (points[0], the lowest site) is unaffected by the extra
            // rotation — place() and applyOrientationRotation both pivot
            // exactly on it.
            XCTAssertEqual(base.points[0].distance(to: rotated.points[0]), 0, accuracy: 1e-6, "seed \(seed)")

            let anchor = base.points[0]
            let baseVec = base.points[3] - anchor
            let rotatedVec = rotated.points[3] - anchor
            XCTAssertEqual(baseVec.length, rotatedVec.length, accuracy: 1e-6,
                            "seed \(seed): a rotation must not change distances from the anchor")

            var angleDelta = (rotatedVec.angle - baseVec.angle).truncatingRemainder(dividingBy: 2 * .pi)
            if angleDelta > .pi { angleDelta -= 2 * .pi }
            if angleDelta < -.pi { angleDelta += 2 * .pi }
            XCTAssertEqual(abs(angleDelta), .pi / 2, accuracy: 1e-6, "seed \(seed): 0.25 turn must be exactly 90°")
        }
    }

    func testGraftOrientationDefaultRangeReproducesUnrotatedPlacementExactly() {
        // Regression: 0-0 (default) must be a complete no-op — applyOrientationRotation
        // never even runs its rotation math for the untouched default.
        let curve = verticalCurve()
        for seed in 0..<10 {
            let square = makeSquare()
            let paramsWithDefault = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftPrimitiveSource: .customSet, graftCustomShapes: [GraftCustomShapeEntry(name: "curve")],
                graftWeight: 1.0, graftAttachmentMode: .singlePoint,
                graftConnectorSelection: .lowestPoint,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let paramsExplicitZero = EvolutionParams(
                generationCount: 1, extrudeWeight: 0.0, splitWeight: 0.0,
                graftPrimitiveSource: .customSet, graftCustomShapes: [GraftCustomShapeEntry(name: "curve")],
                graftWeight: 1.0, graftAttachmentMode: .singlePoint,
                graftConnectorSelection: .lowestPoint,
                graftOrientationAmountMin: 0.0, graftOrientationAmountMax: 0.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let a = GenerationalEvolutionEngine.process(polygons: [square], params: paramsWithDefault, customPrimitives: ["curve": curve])
            let b = GenerationalEvolutionEngine.process(polygons: [square], params: paramsExplicitZero, customPrimitives: ["curve": curve])
            XCTAssertEqual(a, b, "seed \(seed)")
        }
    }

    // MARK: - Restrict targets to original geometry (2026-07-13)

    /// Edge midpoints of `makeSquare()`'s four fixed edges — used as a
    /// ground-truth set to check whether a grafted piece attached directly to
    /// the original square (one of its sites coincides with one of these) or
    /// to something else (a previously grafted piece) instead.
    private func squareEdgeMidpoints(_ square: Polygon2D) -> [Vector2D] {
        (0..<(square.points.count / 4)).map { i in
            let a0 = square.points[i * 4], a1 = square.points[i * 4 + 3]
            return Vector2D(x: (a0.x + a1.x) / 2, y: (a0.y + a1.y) / 2)
        }
    }

    private func coincidesWithAnyEdge(_ piece: Polygon2D, edgeMids: [Vector2D]) -> Bool {
        let sites = AttachmentSiteExtractor.sites(of: piece)
        return sites.contains { site in edgeMids.contains { site.point.distance(to: $0) < 1e-6 } }
    }

    func testRestrictTargetsToOriginalGeometryKeepsEveryGraftDirectlyOnTheOriginalPolygon() {
        // Custom Set with a .spline house shape, not the generated primitive
        // path: a generated Graft piece is AssemblyPrimitiveKit's raw .line
        // encoding (see testGraftAppendsOnePolygonPerGeneration), which never
        // passes `eligible`'s `type == .spline` filter regardless of this
        // toggle — so it could never demonstrate the restriction either way. A
        // custom .spline shape (like a real authored "tree") stays .spline once
        // placed and genuinely becomes eligible as a future target when
        // unrestricted, which is exactly the scenario this toggle addresses.
        //
        // Extrude/Split weight 0 — Graft only, so the original square is never
        // itself modified (in-place mutation is Extrude/Split's mechanism, not
        // Graft's) and stays exactly makeSquare() throughout. With only one
        // original polygon and restriction on, `eligible` is always just [0], so
        // every one of several generations' grafts must attach directly to it —
        // never to a piece appended by an earlier generation.
        let square = makeSquare()
        let house  = customHouseShape()
        let edgeMids = squareEdgeMidpoints(square)
        for seed in 0..<20 {
            let params = EvolutionParams(
                generationCount: 4, extrudeWeight: 0.0, splitWeight: 0.0,
                restrictTargetsToOriginalGeometry: true,
                graftPrimitiveSource: .customSet, graftCustomShapes: [GraftCustomShapeEntry(name: "house")],
                graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params, customPrimitives: ["house": house])
            XCTAssertEqual(result[0], square, "seed \(seed): the original must never itself be modified (extrude/split weight 0)")
            for (i, piece) in result.dropFirst().enumerated() {
                XCTAssertTrue(coincidesWithAnyEdge(piece, edgeMids: edgeMids),
                              "seed \(seed) piece \(i): every graft must attach directly to the original square when restricted")
            }
        }
    }

    func testWithoutRestrictionLaterGraftsCanLandOnPreviouslyGraftedPieces() {
        // Statistical existence check, the mirror image of the test above:
        // across enough seeds and generations, the *default* (unrestricted)
        // behavior must eventually produce at least one piece that does NOT
        // attach directly to the original — i.e. the exact grafted-onto-a-graft
        // symptom the restriction exists to prevent really does occur without it.
        let square = makeSquare()
        let house  = customHouseShape()
        let edgeMids = squareEdgeMidpoints(square)
        var foundOffOriginal = false
        seedLoop: for seed in 0..<200 {
            let params = EvolutionParams(
                generationCount: 6, extrudeWeight: 0.0, splitWeight: 0.0,
                graftPrimitiveSource: .customSet, graftCustomShapes: [GraftCustomShapeEntry(name: "house")],
                graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            let result = GenerationalEvolutionEngine.process(polygons: [square], params: params, customPrimitives: ["house": house])
            for piece in result.dropFirst() where !coincidesWithAnyEdge(piece, edgeMids: edgeMids) {
                foundOffOriginal = true
                break seedLoop
            }
        }
        XCTAssertTrue(foundOffOriginal, "without the restriction, at least one of many seeds/generations should graft onto a previously-grafted piece")
    }

    func testRestrictTargetsToOriginalGeometryDefaultFalseReproducesUnrestrictedBehaviorExactly() {
        let square = makeSquare()
        for seed in 0..<10 {
            let paramsDefault = EvolutionParams(
                generationCount: 4, extrudeWeight: 1.0, splitWeight: 1.0,
                graftSidesMin: 3, graftSidesMax: 6, graftWeight: 1.0,
                generationSeed: seed, maxVertexBudget: 10_000
            )
            var paramsExplicitFalse = paramsDefault
            paramsExplicitFalse.restrictTargetsToOriginalGeometry = false
            let a = GenerationalEvolutionEngine.process(polygons: [square], params: paramsDefault)
            let b = GenerationalEvolutionEngine.process(polygons: [square], params: paramsExplicitFalse)
            XCTAssertEqual(a, b, "seed \(seed)")
        }
    }
}

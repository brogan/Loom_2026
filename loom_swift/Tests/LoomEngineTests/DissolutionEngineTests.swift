import XCTest
@testable import LoomEngine

// MARK: - Fixtures

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

/// A straight-edged (non-spline) square — exercises DissolutionEngine's `default:`
/// branches (simple point-list handling used by non-spline entropy shrink,
/// contraction-anchor picking, and drift).
private func makeLineSquare(offsetX: Double = 0) -> Polygon2D {
    Polygon2D(points: [
        Vector2D(x: offsetX,       y: 0),
        Vector2D(x: offsetX + 1.0, y: 0),
        Vector2D(x: offsetX + 1.0, y: 1),
        Vector2D(x: offsetX,       y: 1),
    ], type: .line)
}

private func makeLineSquareSet(count: Int) -> [Polygon2D] {
    (0..<count).map { makeLineSquare(offsetX: Double($0) * 3.0) }
}

/// One straight-chord segment with a fixed perpendicular bow — isolates
/// open-curve entropy's curvature-relaxation step from its anchor-migration
/// step (a single segment has no interior anchor to migrate).
private func bowedSegment(_ p0: Vector2D, _ p1: Vector2D, bow: Double) -> [Vector2D] {
    let mid1 = Vector2D.lerp(p0, p1, t: 1.0 / 3.0)
    let mid2 = Vector2D.lerp(p0, p1, t: 2.0 / 3.0)
    let dx = p1.x - p0.x, dy = p1.y - p0.y
    let len = (dx * dx + dy * dy).squareRoot()
    let normal = Vector2D(x: -dy / len, y: dx / len)
    return [p0, mid1 + normal * bow, mid2 + normal * bow, p1]
}

/// A 2-segment open "zigzag" curve, (0,0) → (1,1) → (2,0), each segment bowed
/// by a fixed perpendicular offset — exercises both of open-curve entropy's
/// relaxations at once (interior anchor to migrate, plus bow to relax).
private func makeZigzagOpenCurve(bow: Double = 0.2) -> Polygon2D {
    let a0 = Vector2D(x: 0, y: 0), a1 = Vector2D(x: 1, y: 1), a2 = Vector2D(x: 2, y: 0)
    return Polygon2D(points: bowedSegment(a0, a1, bow: bow) + bowedSegment(a1, a2, bow: bow), type: .openSpline)
}

final class DissolutionEngineTests: XCTestCase {

    // MARK: - Baseline entropy / collapse regression (contraction-anchor refactor safety net)

    func testEntropyDisabledAndCollapseDisabledReturnsInputUnchanged() {
        let square = makeLineSquare()
        let pass = DissolutionParams()
        let result = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 100, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(result, [square])
    }

    func testEntropyCentroidAnchorShrinksNonSplineTowardCentroid() {
        let square = makeLineSquare()
        var pass = DissolutionParams()
        pass.entropyEnabled = true
        pass.entropyRate = 0.5
        let result = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 5, targetFPS: 30, spriteIndex: 0)
        let originalCentre = BezierMath.centreSpline(square.points)
        let resultCentre   = BezierMath.centreSpline(result[0].points)
        XCTAssertEqual(originalCentre.x, resultCentre.x, accuracy: 1e-9)
        XCTAssertEqual(originalCentre.y, resultCentre.y, accuracy: 1e-9)
        // Shrunk toward its own centre: every point moved closer to centre.
        for (orig, shrunk) in zip(square.points, result[0].points) {
            XCTAssertLessThan(originalCentre.distance(to: shrunk), originalCentre.distance(to: orig) + 1e-9)
        }
    }

    func testCollapseInstantRemovesAtTriggerFrame() {
        let square = makeSquare()
        var pass = DissolutionParams()
        pass.collapseEnabled = true
        pass.collapseMode = .instant
        pass.collapseTriggerType = .frameCount
        pass.collapseTriggerFrameCount = 10
        pass.collapseEndMode = .remove

        let before = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 9, targetFPS: 30, spriteIndex: 0)
        let at     = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 10, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(before, [square])
        XCTAssertEqual(at, [])
    }

    func testCollapseBriefCentroidShrinksThenRemoves() {
        let square = makeSquare()
        var pass = DissolutionParams()
        pass.collapseEnabled = true
        pass.collapseMode = .brief
        pass.collapseBriefDuration = 10
        pass.collapseTriggerType = .frameCount
        pass.collapseTriggerFrameCount = 10
        pass.collapseEndMode = .remove

        let midway = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 15, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(midway.count, 1)
        let centre = BezierMath.centreSpline(square.points)
        // Half-collapsed: strictly smaller than original, not yet gone.
        for (orig, shrunk) in zip(square.points, midway[0].points) {
            XCTAssertLessThan(centre.distance(to: shrunk), centre.distance(to: orig))
        }
        let gone = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 20, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(gone, [])
    }

    // MARK: - Contraction anchor

    func testEdgeAnchorBreaksSymmetryThatCentroidAnchorPreserves() {
        // A square's corners are all equidistant from its centroid, so a centroid-anchored
        // shrink preserves that symmetry at any progress. An off-centre edge-midpoint anchor
        // breaks it — the corners end up at different distances from centre — regardless of
        // which of the four edges the seed happens to pick (symmetric by construction).
        let square = makeLineSquare()
        var pass = DissolutionParams()
        pass.collapseEnabled = true
        pass.collapseMode = .brief
        pass.collapseBriefDuration = 10
        pass.collapseTriggerFrameCount = 0
        pass.collapseEndMode = .remove
        pass.contractionAnchor = .edge
        pass.dissolutionSeed = 7

        let result = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 5, targetFPS: 30, spriteIndex: 0)
        let centre = BezierMath.centreSpline(square.points)
        let distances = result[0].points.map { centre.distance(to: $0) }
        let allEqual = distances.allSatisfy { abs($0 - distances[0]) < 1e-6 }
        XCTAssertFalse(allEqual, "shrinking toward an off-centre edge anchor should break the square's point-to-centre symmetry")
    }

    func testVertexAnchorConvergesOnAnActualVertex() {
        // Collapse's Brief progress can't actually reach exactly 1.0 (fadeEnd triggers full
        // removal at that point), so use a very long duration and stop just short of it —
        // progress ≈ 0.999999, close enough that every point should sit within a tiny
        // epsilon of the anchor vertex.
        let square = makeLineSquare()
        var pass = DissolutionParams()
        pass.collapseEnabled = true
        pass.collapseMode = .brief
        pass.collapseBriefDuration = 1_000_000
        pass.collapseTriggerFrameCount = 0
        pass.collapseEndMode = .remove
        pass.contractionAnchor = .vertex
        pass.dissolutionSeed = 3

        let result = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 999_999, targetFPS: 30, spriteIndex: 0)
        let allPoints = result[0].points
        let first = allPoints[0]
        for p in allPoints {
            XCTAssertEqual(p.x, first.x, accuracy: 1e-3)
            XCTAssertEqual(p.y, first.y, accuracy: 1e-3)
        }
        XCTAssertTrue(square.points.contains { $0.distance(to: first) < 1e-3 },
                     "vertex-anchor collapse should converge on (near) one of the original vertices")
    }

    func testContractionAnchorDeterministicForSameSeed() {
        let square = makeLineSquare()
        var pass = DissolutionParams()
        pass.collapseEnabled = true
        pass.collapseMode = .brief
        pass.collapseBriefDuration = 10
        pass.collapseTriggerFrameCount = 0
        pass.collapseEndMode = .remove
        pass.contractionAnchor = .edge
        pass.dissolutionSeed = 11

        let a = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 5, targetFPS: 30, spriteIndex: 0)
        let b = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 5, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(a, b)
    }

    // MARK: - Partial loss

    func testPartialLossDisabledKeepsAllPolygons() {
        let set = makeLineSquareSet(count: 20)
        let pass = DissolutionParams()
        let result = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(result.count, set.count)
    }

    func testPartialLossSinglePolygonIsNoOp() {
        let square = makeLineSquare()
        var pass = DissolutionParams()
        pass.partialLossEnabled = true
        pass.partialLossMaxFraction = 1.0
        let result = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(result, [square], "a single polygon can't lose 'a fraction of itself' — use Collapse instead")
    }

    func testPartialLossZeroMaxFractionKeepsAll() {
        let set = makeLineSquareSet(count: 20)
        var pass = DissolutionParams()
        pass.partialLossEnabled = true
        pass.partialLossMaxFraction = 0.0
        let result = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(result.count, set.count)
    }

    func testPartialLossPrunesSomeButNotAllWhenPhaseDriverOff() {
        let set = makeLineSquareSet(count: 20)
        var pass = DissolutionParams()
        pass.partialLossEnabled = true
        pass.partialLossMaxFraction = 0.5
        pass.dissolutionSeed = 4
        // dissolutionPhase disabled (default) => static full-strength application,
        // matching generationPhase's disabled-means-static-full-effect default.
        let result = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertLessThan(result.count, set.count)
        XCTAssertGreaterThan(result.count, 0)
    }

    func testPartialLossZeroWhenPhaseDriverEvaluatesToZero() {
        let set = makeLineSquareSet(count: 20)
        var pass = DissolutionParams()
        pass.partialLossEnabled = true
        pass.partialLossMaxFraction = 1.0
        pass.dissolutionPhase = DoubleDriver(mode: .constant, base: 0, enabled: true)
        let result = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(result.count, set.count, "phase 0 => no loss, even with maxFraction 1.0")
    }

    func testPartialLossFullWhenPhaseDriverEvaluatesToOneAndMaxFractionOne() {
        let set = makeLineSquareSet(count: 20)
        var pass = DissolutionParams()
        pass.partialLossEnabled = true
        pass.partialLossMaxFraction = 1.0
        pass.dissolutionPhase = DoubleDriver(mode: .constant, base: 1, enabled: true)
        let result = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(result.count, 0, "phase 1 with maxFraction 1.0 => every polygon eligible for pruning")
    }

    func testPartialLossDeterministicForSameSeed() {
        let set = makeLineSquareSet(count: 20)
        var pass = DissolutionParams()
        pass.partialLossEnabled = true
        pass.partialLossMaxFraction = 0.5
        pass.dissolutionSeed = 9
        let a = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        let b = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(a, b)
    }

    func testPartialLossDifferentSeedsCanProduceDifferentResults() {
        let set = makeLineSquareSet(count: 20)
        var passA = DissolutionParams()
        passA.partialLossEnabled = true
        passA.partialLossMaxFraction = 0.5
        passA.dissolutionSeed = 1
        var passB = passA
        passB.dissolutionSeed = 2

        let a = DissolutionEngine.apply(polygons: set, passes: [passA], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        let b = DissolutionEngine.apply(polygons: set, passes: [passB], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Drift

    func testDriftDisabledReturnsUnchanged() {
        let set = makeLineSquareSet(count: 5)
        let pass = DissolutionParams()
        let result = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(result, set)
    }

    func testDriftTranslatesEachPolygonWithinDistanceBound() {
        let set = makeLineSquareSet(count: 5)
        var pass = DissolutionParams()
        pass.driftEnabled = true
        pass.driftDistance = 0.2
        pass.driftRotation = 0.0
        pass.dissolutionSeed = 13
        let result = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)

        for (orig, drifted) in zip(set, result) {
            let origCentre    = BezierMath.centreSpline(orig.points)
            let driftedCentre = BezierMath.centreSpline(drifted.points)
            XCTAssertLessThanOrEqual(origCentre.distance(to: driftedCentre), 0.2 + 1e-9)
        }
        // At least one polygon should actually have moved (vanishingly unlikely that
        // every seeded direction rolls to exactly zero distance).
        XCTAssertTrue(zip(set, result).contains { orig, drifted in
            BezierMath.centreSpline(orig.points).distance(to: BezierMath.centreSpline(drifted.points)) > 1e-6
        })
    }

    func testDriftZeroWhenPhaseDriverEvaluatesToZero() {
        let set = makeLineSquareSet(count: 5)
        var pass = DissolutionParams()
        pass.driftEnabled = true
        pass.driftDistance = 0.5
        pass.dissolutionPhase = DoubleDriver(mode: .constant, base: 0, enabled: true)
        let result = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(result, set)
    }

    func testDriftRotationOnlyPreservesCentroid() {
        let square = makeLineSquare()
        var pass = DissolutionParams()
        pass.driftEnabled = true
        pass.driftDistance = 0.0
        pass.driftRotation = .pi / 4
        pass.dissolutionSeed = 2
        let result = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)

        let origCentre    = BezierMath.centreSpline(square.points)
        let rotatedCentre = BezierMath.centreSpline(result[0].points)
        XCTAssertEqual(origCentre.x, rotatedCentre.x, accuracy: 1e-9)
        XCTAssertEqual(origCentre.y, rotatedCentre.y, accuracy: 1e-9)
    }

    func testDriftDeterministicForSameSeed() {
        let set = makeLineSquareSet(count: 5)
        var pass = DissolutionParams()
        pass.driftEnabled = true
        pass.driftDistance = 0.3
        pass.driftRotation = 0.2
        pass.dissolutionSeed = 17
        let a = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        let b = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(a, b)
    }

    // MARK: - effectiveSeed (two-track "which" plumbing)

    func testEffectiveSeedMatchesDissolutionSeedWhenVaryingIsOff() {
        var pass = DissolutionParams()
        pass.dissolutionSeed = 42
        pass.dissolutionPhase = DoubleDriver(mode: .oscillator, freqHz: 1.0, enabled: true)
        pass.varySeedPerCycle = false
        XCTAssertEqual(
            DissolutionEngine.effectiveSeed(for: pass, elapsedFrames: 999, targetFPS: 30),
            42
        )
    }

    func testEffectiveSeedMatchesDissolutionSeedWhenDriverDisabledEvenIfVaryingIsOn() {
        var pass = DissolutionParams()
        pass.dissolutionSeed = 42
        pass.varySeedPerCycle = true
        pass.dissolutionPhase.enabled = false
        XCTAssertEqual(
            DissolutionEngine.effectiveSeed(for: pass, elapsedFrames: 999, targetFPS: 30),
            42
        )
    }

    func testEffectiveSeedMatchesGenerationalEvolutionEngineCombineSeedWhenVaryingIsOn() {
        var pass = DissolutionParams()
        pass.dissolutionSeed = 42
        pass.dissolutionPhase = DoubleDriver(mode: .oscillator, base: 2, amplitude: 2,
                                             freqHz: 1.0, phase: 0.75, wave: .sine, enabled: true)
        pass.varySeedPerCycle = true

        let cycle = GenerationalEvolutionEngine.revealCycleIndex(for: pass.dissolutionPhase, elapsedFrames: 12, targetFPS: 8)
        XCTAssertEqual(
            DissolutionEngine.effectiveSeed(for: pass, elapsedFrames: 12, targetFPS: 8),
            GenerationalEvolutionEngine.combineSeed(42, cycle)
        )
    }

    func testVarySeedPerCycleProducesDifferentPartialLossAcrossCycles() {
        let set = makeLineSquareSet(count: 20)
        var pass = DissolutionParams()
        pass.partialLossEnabled = true
        pass.partialLossMaxFraction = 0.5
        pass.dissolutionSeed = 21
        pass.dissolutionPhase = DoubleDriver(mode: .oscillator, base: 2, amplitude: 2,
                                             freqHz: 1.0, phase: 0.75, wave: .sine, enabled: true)
        pass.varySeedPerCycle = true

        // elapsedFrames 4 and 12 are both a quarter-cycle past their respective troughs
        // (cycles 0 and 1) at targetFPS 8 — same phase value, different cycle index.
        let cycle0 = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 4, targetFPS: 8, spriteIndex: 0)
        let cycle1 = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 12, targetFPS: 8, spriteIndex: 0)
        XCTAssertNotEqual(cycle0, cycle1, "different reveal cycles should prune differently when varySeedPerCycle is on")

        let cycle0Again = DissolutionEngine.apply(polygons: set, passes: [pass], elapsedFrames: 4, targetFPS: 8, spriteIndex: 0)
        XCTAssertEqual(cycle0, cycle0Again)
    }

    // MARK: - apply(passes:) pipeline wrapper

    func testApplyIgnoresDisabledPass() {
        let square = makeLineSquare()
        var pass = DissolutionParams()
        pass.enabled = false
        pass.entropyEnabled = true
        pass.entropyRate = 0.9
        let result = DissolutionEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 100, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(result, [square])
    }

    func testApplyChainsMultiplePassesInOrder() {
        let set = makeLineSquareSet(count: 20)
        var lossPass = DissolutionParams()
        lossPass.partialLossEnabled = true
        lossPass.partialLossMaxFraction = 0.5
        lossPass.dissolutionSeed = 6

        var driftPass = DissolutionParams()
        driftPass.driftEnabled = true
        driftPass.driftDistance = 0.1
        driftPass.dissolutionSeed = 6

        let chained = DissolutionEngine.apply(polygons: set, passes: [lossPass, driftPass],
                                              elapsedFrames: 0, targetFPS: 30, spriteIndex: 0)
        let sequential = DissolutionEngine.apply(
            polygons: DissolutionEngine.apply(polygons: set, passes: [lossPass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0),
            passes: [driftPass], elapsedFrames: 0, targetFPS: 30, spriteIndex: 0
        )
        XCTAssertEqual(chained, sequential, "apply(passes:) should feed each pass the previous pass's output, in order")
        XCTAssertLessThan(chained.count, set.count, "loss pass should have pruned before drift ran")
    }

    // MARK: - Open-curve entropy: straightening, not shape-seeking (2026-07-12)

    func testOpenCurveEntropyDisabledLeavesUnchanged() {
        let curve = makeZigzagOpenCurve()
        let pass = DissolutionParams()
        let result = DissolutionEngine.apply(polygons: [curve], passes: [pass], elapsedFrames: 50, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(result, [curve])
    }

    func testOpenCurveEntropyEndpointsAreFixedPoints() {
        // The curve's own two true endpoints always map to themselves (target_0
        // == first, target_n == last), for any rate/frame/bow — they anchor the
        // straight line everything else migrates toward, so they can't move.
        let curve = makeZigzagOpenCurve()
        var pass = DissolutionParams()
        pass.entropyEnabled = true
        pass.entropyRate = 0.5

        let result = DissolutionEngine.apply(polygons: [curve], passes: [pass], elapsedFrames: 3, targetFPS: 30, spriteIndex: 0)[0]
        XCTAssertEqual(result.points[0], curve.points[0], "start anchor must be a fixed point")
        XCTAssertEqual(result.points[7], curve.points[7], "end anchor must be a fixed point")
    }

    func testOpenCurveEntropySingleSegmentRelaxesCurvatureExactly() {
        // n=1: no interior anchor to migrate (the curve's "straight line" already
        // passes through exactly its own 2 anchors), so this isolates the
        // curvature-relaxation step in isolation with a hand-computable exact
        // result: control points lerp toward their segment's own chord by
        // exactly `factor`, with no anchor drag involved at all.
        let a0 = Vector2D(x: 0, y: 0), a1 = Vector2D(x: 2, y: 0)
        let curve = Polygon2D(points: bowedSegment(a0, a1, bow: 0.3), type: .openSpline)

        var pass = DissolutionParams()
        pass.entropyEnabled = true
        pass.entropyRate = 0.5 // entropyFactor(rate: 0.5, frames: 1) == 0.5 exactly

        let result = DissolutionEngine.apply(polygons: [curve], passes: [pass], elapsedFrames: 1, targetFPS: 30, spriteIndex: 0)[0]

        XCTAssertEqual(result.points[0], a0, "endpoints never move")
        XCTAssertEqual(result.points[3], a1, "endpoints never move")

        let chordCp1 = Vector2D.lerp(a0, a1, t: 1.0 / 3.0)
        let chordCp2 = Vector2D.lerp(a0, a1, t: 2.0 / 3.0)
        let expectedCp1 = Vector2D.lerp(curve.points[1], chordCp1, t: 0.5)
        let expectedCp2 = Vector2D.lerp(curve.points[2], chordCp2, t: 0.5)
        XCTAssertEqual(result.points[1].distance(to: expectedCp1), 0, accuracy: 1e-9)
        XCTAssertEqual(result.points[2].distance(to: expectedCp2), 0, accuracy: 1e-9)
    }

    func testOpenCurveEntropyMiddleAnchorWeightedByChordLengthNotIndex() {
        // Unevenly-spaced anchors: a1 sits much closer (by chord length) to a0
        // than to a2. Arc-length weighting must place its target well off the
        // curve's own 50%-by-index point — proves the chord-length weighting is
        // actually being used, not a naive `i/n` split.
        let a0 = Vector2D(x: 0, y: 0), a1 = Vector2D(x: 1, y: 1), a2 = Vector2D(x: 4, y: 0)
        let curve = Polygon2D(points: bowedSegment(a0, a1, bow: 0) + bowedSegment(a1, a2, bow: 0), type: .openSpline)

        var pass = DissolutionParams()
        pass.entropyEnabled = true
        pass.entropyRate = 0.5 // factor == 0.5 exactly at frame 1

        let result = DissolutionEngine.apply(polygons: [curve], passes: [pass], elapsedFrames: 1, targetFPS: 30, spriteIndex: 0)[0]

        let d01 = a0.distance(to: a1), d12 = a1.distance(to: a2)
        let t1  = d01 / (d01 + d12)
        let target1 = Vector2D.lerp(a0, a2, t: t1)
        let expectedA1 = Vector2D.lerp(a1, target1, t: 0.5)

        // Middle anchor is shared: segment 0's end (points[3]) and segment 1's
        // start (points[4]).
        XCTAssertEqual(result.points[3].distance(to: expectedA1), 0, accuracy: 1e-9)
        XCTAssertEqual(result.points[4].distance(to: expectedA1), 0, accuracy: 1e-9)

        // Sanity: the naive index-based 50% point is a materially different
        // location, so this genuinely distinguishes the two weightings.
        let indexBasedTarget = Vector2D.lerp(a0, a2, t: 0.5)
        XCTAssertGreaterThan(target1.distance(to: indexBasedTarget), 0.1)
    }

    func testOpenCurveEntropyHighFactorNearlyStraightensCompletely() {
        let curve = makeZigzagOpenCurve()
        var pass = DissolutionParams()
        pass.entropyEnabled = true
        pass.entropyRate = 0.5 // max allowed rate; factor -> 1 as frames grow

        let result = DissolutionEngine.apply(polygons: [curve], passes: [pass], elapsedFrames: 50, targetFPS: 30, spriteIndex: 0)[0]

        let first = result.points[0], last = result.points[7]
        let dx = last.x - first.x, dy = last.y - first.y
        let len = (dx * dx + dy * dy).squareRoot()
        for p in result.points {
            // Perpendicular distance from p to the first→last line.
            let perp = abs((p.x - first.x) * dy - (p.y - first.y) * dx) / len
            XCTAssertLessThan(perp, 1e-4, "every point should sit almost exactly on the endpoint line once nearly fully entropied")
        }
    }

    // MARK: - entropyScaleDelta: generalized to both .spline and .openSpline (2026-07-12)

    func testEntropyScaleDeltaDefaultIsNoOpRegression() {
        let square = makeSquare()
        var withDefault = DissolutionParams()
        withDefault.entropyEnabled = true
        withDefault.entropyRate = 0.5
        withDefault.entropyTarget = .centroid
        // entropyScaleDelta left at its 0.0 default.
        var explicitZero = withDefault
        explicitZero.entropyScaleDelta = 0.0

        let a = DissolutionEngine.apply(polygons: [square], passes: [withDefault], elapsedFrames: 3, targetFPS: 30, spriteIndex: 0)
        let b = DissolutionEngine.apply(polygons: [square], passes: [explicitZero], elapsedFrames: 3, targetFPS: 30, spriteIndex: 0)
        XCTAssertEqual(a, b)
    }

    func testEntropyScaleDeltaShrinksClosedSplineAdditionally() {
        let square = makeSquare()
        var withoutScale = DissolutionParams()
        withoutScale.entropyEnabled = true
        withoutScale.entropyRate = 0.5
        withoutScale.entropyTarget = .centroid

        var withScale = withoutScale
        withScale.entropyScaleDelta = -0.5

        let base   = DissolutionEngine.apply(polygons: [square], passes: [withoutScale], elapsedFrames: 1, targetFPS: 30, spriteIndex: 0)[0]
        let scaled = DissolutionEngine.apply(polygons: [square], passes: [withScale],    elapsedFrames: 1, targetFPS: 30, spriteIndex: 0)[0]

        let c = BezierMath.centreSpline(square.points)
        let factor = 0.5 // entropyFactor(rate: 0.5, frames: 1)
        let expectedScale = 1.0 + factor * (-0.5)
        for (basePt, scaledPt) in zip(base.points, scaled.points) {
            let expected = c + (basePt - c) * expectedScale
            XCTAssertEqual(scaledPt.distance(to: expected), 0, accuracy: 1e-9)
        }
    }

    func testEntropyScaleDeltaGrowsOpenCurveAdditionally() {
        let curve = makeZigzagOpenCurve()
        var withoutScale = DissolutionParams()
        withoutScale.entropyEnabled = true
        withoutScale.entropyRate = 0.5

        var withScale = withoutScale
        withScale.entropyScaleDelta = 1.0 // grows

        let base   = DissolutionEngine.apply(polygons: [curve], passes: [withoutScale], elapsedFrames: 1, targetFPS: 30, spriteIndex: 0)[0]
        let scaled = DissolutionEngine.apply(polygons: [curve], passes: [withScale],    elapsedFrames: 1, targetFPS: 30, spriteIndex: 0)[0]

        let c = BezierMath.centreSpline(curve.points)
        let factor = 0.5
        let expectedScale = 1.0 + factor * 1.0
        for (basePt, scaledPt) in zip(base.points, scaled.points) {
            let expected = c + (basePt - c) * expectedScale
            XCTAssertEqual(scaledPt.distance(to: expected), 0, accuracy: 1e-9)
        }
    }
}

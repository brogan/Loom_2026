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
}

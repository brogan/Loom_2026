import XCTest
@testable import LoomEngine

// MARK: - Fixture

private func makeSquare(offsetX: Double = 0, offsetY: Double = 0) -> Polygon2D {
    Polygon2D(points: [
        Vector2D(x: offsetX,       y: offsetY),
        Vector2D(x: offsetX + 1.0, y: offsetY),
        Vector2D(x: offsetX + 1.0, y: offsetY + 1.0),
        Vector2D(x: offsetX,       y: offsetY + 1.0),
    ], type: .line)
}

final class FulgurationEngineTests: XCTestCase {

    /// A pass whose interval/hold are *fixed* (min == max), so cycle-boundary
    /// frames are exactly predictable regardless of seed/spriteIndex — RPSR
    /// sampling degenerates to the fixed value whenever `hi == lo` (see
    /// FulgurationEngine.sampleInterval/sampleHold). Used for all the timing tests
    /// below; transform-variation tests set their own ranges separately.
    private func fixedCyclePass(interval: Int = 10, hold: Int = 5, seed: Int = 0) -> FulgurationParams {
        var pass = FulgurationParams()
        pass.intervalMin = interval; pass.intervalMax = interval
        pass.holdMin     = hold;     pass.holdMax     = hold
        pass.cycleSeed   = seed
        return pass
    }

    // MARK: - Disabled / empty input

    func testDisabledPassReturnsInputUnchanged() {
        let square = makeSquare()
        var pass = fixedCyclePass()
        pass.enabled = false
        let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 100, spriteIndex: 0)
        XCTAssertEqual(result, [square])
    }

    func testEmptyPolygonsReturnsEmpty() {
        let pass = fixedCyclePass()
        let result = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 12, spriteIndex: 0)
        XCTAssertEqual(result, [])
    }

    // MARK: - Frame-cycle trigger boundaries

    func testHiddenBeforeIntervalElapses() {
        let square = makeSquare()
        let pass = fixedCyclePass(interval: 10, hold: 5)
        for f: Double in [0, 5, 9] {
            let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: f, spriteIndex: 0)
            XCTAssertEqual(result, [], "expected hidden at frame \(f)")
        }
    }

    func testVisibleDuringHoldWindow() {
        let square = makeSquare()
        let pass = fixedCyclePass(interval: 10, hold: 5)
        for f: Double in [10, 12, 14] {
            let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: f, spriteIndex: 0)
            XCTAssertEqual(result.count, 1, "expected visible at frame \(f)")
        }
    }

    func testHiddenAgainAtPeriodBoundary() {
        let square = makeSquare()
        let pass = fixedCyclePass(interval: 10, hold: 5)
        // period = interval + hold = 15; frame 15 starts the next cycle's hidden interval.
        let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 15, spriteIndex: 0)
        XCTAssertEqual(result, [])
    }

    func testSecondCycleVisibleWindow() {
        let square = makeSquare()
        let pass = fixedCyclePass(interval: 10, hold: 5)
        // cycle 1: hidden [15, 25), visible [25, 30).
        let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 27, spriteIndex: 0)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Determinism

    func testSameElapsedFramesProducesIdenticalResult() {
        let square = makeSquare()
        var pass = fixedCyclePass(interval: 10, hold: 5)
        pass.translationRange = 0.3
        pass.scaleMin = 0.5; pass.scaleMax = 1.5
        pass.rotationRange = 0.5
        let a = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 12, spriteIndex: 0)
        let b = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 12, spriteIndex: 0)
        XCTAssertEqual(a, b)
    }

    func testDifferentSpriteIndexProducesDifferentTransform() {
        let square = makeSquare()
        var pass = fixedCyclePass(interval: 10, hold: 100, seed: 7)
        pass.translationRange = 0.3
        let base = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 12, spriteIndex: 0)
        XCTAssertEqual(base.count, 1)

        var foundDifference = false
        for idx in 1...10 {
            let other = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 12, spriteIndex: idx)
            XCTAssertEqual(other.count, 1, "interval/hold are fixed, so every sprite index should still be visible")
            if other != base { foundDifference = true; break }
        }
        XCTAssertTrue(foundDifference, "different sprite indices should sample a different per-cycle transform")
    }

    // MARK: - Transform variation

    func testZeroTranslationRangeKeepsCentroidFixed() {
        let square = makeSquare()
        var pass = fixedCyclePass(interval: 10, hold: 5)
        pass.translationRange = 0
        let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 12, spriteIndex: 0)
        XCTAssertEqual(result.count, 1)
        let origCentre = BezierMath.centreSpline(square.points)
        let newCentre  = BezierMath.centreSpline(result[0].points)
        XCTAssertEqual(origCentre.x, newCentre.x, accuracy: 1e-9)
        XCTAssertEqual(origCentre.y, newCentre.y, accuracy: 1e-9)
    }

    func testTranslationStaysWithinRange() {
        let square = makeSquare()
        var pass = fixedCyclePass(interval: 10, hold: 5)
        pass.translationRange = 0.25
        let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 12, spriteIndex: 0)
        XCTAssertEqual(result.count, 1)
        let origCentre = BezierMath.centreSpline(square.points)
        let newCentre  = BezierMath.centreSpline(result[0].points)
        XCTAssertLessThanOrEqual(origCentre.distance(to: newCentre), 0.25 + 1e-9)
    }

    func testScaleAppliedExactlyWhenFixed() {
        let square = makeSquare()
        var pass = fixedCyclePass(interval: 10, hold: 5)
        pass.scaleMin = 2.0; pass.scaleMax = 2.0
        let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 12, spriteIndex: 0)
        XCTAssertEqual(result.count, 1)
        let centre = BezierMath.centreSpline(square.points)
        for (orig, scaled) in zip(square.points, result[0].points) {
            XCTAssertEqual(centre.distance(to: scaled), centre.distance(to: orig) * 2.0, accuracy: 1e-6)
        }
    }

    // MARK: - Development: instant vs. grow/shrink

    func testInstantModeFullyVisibleThroughoutHold() {
        let square = makeSquare()
        var pass = fixedCyclePass(interval: 10, hold: 10)
        pass.developmentMode = .instant
        for f: Double in [10, 15, 19] {
            let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: f, spriteIndex: 0)
            XCTAssertEqual(result, [square], "instant mode should be unscaled/untranslated throughout hold at frame \(f)")
        }
    }

    func testGrowShrinkStartsAtZeroAndRampsInLinearly() {
        let square = makeSquare()
        var pass = fixedCyclePass(interval: 10, hold: 10)
        pass.developmentMode   = .growShrink
        pass.growInDuration    = 4
        pass.shrinkOutDuration = 4
        let centre = BezierMath.centreSpline(square.points)

        // holdElapsed == 0 → factor 0 → nothing rendered yet.
        let atStart = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 10, spriteIndex: 0)
        XCTAssertEqual(atStart, [])

        // holdElapsed == 2 (of a 4-frame grow-in) → factor 0.5.
        let atHalf = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 12, spriteIndex: 0)
        XCTAssertEqual(atHalf.count, 1)
        for (orig, scaled) in zip(square.points, atHalf[0].points) {
            XCTAssertEqual(centre.distance(to: scaled), centre.distance(to: orig) * 0.5, accuracy: 1e-6)
        }

        // holdElapsed == 5 → past grow-in (4), before shrink-out start (10-4=6) → full size.
        let atMiddle = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 15, spriteIndex: 0)
        XCTAssertEqual(atMiddle, [square])
    }

    func testGrowShrinkRampsOutLinearlyAtEnd() {
        let square = makeSquare()
        var pass = fixedCyclePass(interval: 10, hold: 10)
        pass.developmentMode   = .growShrink
        pass.growInDuration    = 4
        pass.shrinkOutDuration = 4
        let centre = BezierMath.centreSpline(square.points)

        // holdElapsed == 8: shrink starts at holdDuration - shrinkOut = 6, so factor = (10-8)/4 = 0.5.
        let atShrinkHalf = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 18, spriteIndex: 0)
        XCTAssertEqual(atShrinkHalf.count, 1)
        for (orig, scaled) in zip(square.points, atShrinkHalf[0].points) {
            XCTAssertEqual(centre.distance(to: scaled), centre.distance(to: orig) * 0.5, accuracy: 1e-6)
        }
    }

    func testGrowShrinkDurationsClampToHoldWithoutOverlapOrCrash() {
        let square = makeSquare()
        var pass = fixedCyclePass(interval: 10, hold: 4)
        pass.developmentMode   = .growShrink
        pass.growInDuration    = 100 // exceeds the hold duration
        pass.shrinkOutDuration = 100
        for f: Double in [10, 11, 12, 13] {
            let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: f, spriteIndex: 0)
            XCTAssertTrue(result.isEmpty || result.count == 1)
        }
    }

    // MARK: - apply(passes:) chaining

    func testApplyChainsMultiplePassesAndShortCircuitsOnHidden() {
        let square = makeSquare()
        let passA = fixedCyclePass(interval: 10, hold: 100, seed: 1) // visible [10, 110)
        let passB = fixedCyclePass(interval: 1,  hold: 100, seed: 2) // visible [1, 101)

        let bothVisible = FulgurationEngine.apply(polygons: [square], passes: [passA, passB],
                                                  elapsedFrames: 12, spriteIndex: 0)
        XCTAssertEqual(bothVisible.count, 1, "both passes visible at frame 12 should still show geometry")

        let hiddenByFirst = FulgurationEngine.apply(polygons: [square], passes: [passA, passB],
                                                     elapsedFrames: 5, spriteIndex: 0)
        XCTAssertEqual(hiddenByFirst, [], "pass A hidden at frame 5 should short-circuit the whole chain")
    }

    // MARK: - Cap / performance sanity

    func testLargeElapsedFramesWithTightCycleCompletesWithoutHanging() {
        let square = makeSquare()
        let pass = fixedCyclePass(interval: 1, hold: 1)
        // ~2500 cycle-walk iterations at 5000 elapsed frames — well under the 100_000 cap.
        let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 5000, spriteIndex: 0)
        XCTAssertTrue(result.isEmpty || result.count == 1)
    }
}

import XCTest
@testable import LoomEngine

final class AnimationDriverTests: XCTestCase {

    func testDoubleKeyframeDriverHoldsBaseBeforeFirstKeyframe() {
        let driver = DoubleDriver(
            mode: .keyframe,
            base: 0,
            loopMode: .once,
            keyframes: [
                DoubleKeyframe(frame: 40, value: 20),
                DoubleKeyframe(frame: 100, value: 80)
            ]
        )

        XCTAssertEqual(
            DriverEvaluator.evaluate(driver, globalElapsed: 0, targetFPS: 30, spriteIndex: 0),
            0
        )
        XCTAssertEqual(
            DriverEvaluator.evaluate(driver, globalElapsed: 39, targetFPS: 30, spriteIndex: 0),
            0
        )
        XCTAssertEqual(
            DriverEvaluator.evaluate(driver, globalElapsed: 40, targetFPS: 30, spriteIndex: 0),
            20
        )
    }

    func testVectorKeyframeDriverHoldsBaseBeforeFirstKeyframe() {
        let driver = VectorDriver(
            mode: .keyframe,
            base: Vector2D(x: 3, y: 4),
            loopMode: .once,
            keyframes: [
                VectorKeyframe(frame: 25, value: Vector2D(x: 10, y: 20)),
                VectorKeyframe(frame: 50, value: Vector2D(x: 30, y: 40))
            ]
        )

        XCTAssertEqual(
            DriverEvaluator.evaluate(driver, globalElapsed: 24, targetFPS: 30, spriteIndex: 0),
            Vector2D(x: 3, y: 4)
        )
        XCTAssertEqual(
            DriverEvaluator.evaluate(driver, globalElapsed: 25, targetFPS: 30, spriteIndex: 0),
            Vector2D(x: 10, y: 20)
        )
    }

    func testOnceKeyframeDriverHoldsFinalValueAfterLastKeyframe() {
        let driver = DoubleDriver(
            mode: .keyframe,
            base: 0,
            loopMode: .once,
            keyframes: [
                DoubleKeyframe(frame: 10, value: 10),
                DoubleKeyframe(frame: 20, value: 30)
            ]
        )

        XCTAssertEqual(
            DriverEvaluator.evaluate(driver, globalElapsed: 50, targetFPS: 30, spriteIndex: 0),
            30
        )
    }

    // MARK: - ColorDriver .sequential

    private let threePaletteColors = [
        LoomColor(r: 255, g: 0,   b: 0,   a: 255),
        LoomColor(r: 0,   g: 255, b: 0,   a: 255),
        LoomColor(r: 0,   g: 0,   b: 255, a: 255),
    ]

    func testSequentialStepsThroughPaletteAtHoldCadence() {
        let driver = ColorDriver(mode: .sequential, period: 10, loopMode: .loop,
                                 palette: threePaletteColors, enabled: true)

        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 0), threePaletteColors[0])
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 9), threePaletteColors[0])
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 10), threePaletteColors[1])
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 20), threePaletteColors[2])
        // Loop mode wraps back to the first color after the last.
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 30), threePaletteColors[0])
    }

    func testSequentialOnceHoldsFinalColorPastEnd() {
        let driver = ColorDriver(mode: .sequential, period: 10, loopMode: .once,
                                 palette: threePaletteColors, enabled: true)

        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 1000), threePaletteColors[2])
    }

    func testSequentialPingPongBounces() {
        let driver = ColorDriver(mode: .sequential, period: 10, loopMode: .pingPong,
                                 palette: threePaletteColors, enabled: true)

        // Steps: 0, 1, 2, 1, 0, 1, 2, ...
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 0),  threePaletteColors[0])
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 10), threePaletteColors[1])
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 20), threePaletteColors[2])
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 30), threePaletteColors[1])
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 40), threePaletteColors[0])
    }

    func testSequentialEmptyPaletteReturnsBase() {
        let driver = ColorDriver(mode: .sequential, base: .black, enabled: true)
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 100), .black)
    }

    // MARK: - ColorDriver .random

    func testRandomIsDeterministicForFixedSeedAndSpriteIndex() {
        let driver = ColorDriver(mode: .random, period: 5, seed: 42,
                                 palette: threePaletteColors, enabled: true)

        let a = DriverEvaluator.evaluate(driver, globalElapsed: 123, spriteIndex: 7)
        let b = DriverEvaluator.evaluate(driver, globalElapsed: 123, spriteIndex: 7)
        XCTAssertEqual(a, b)
    }

    func testRandomHoldsPickForPeriodFrames() {
        let driver = ColorDriver(mode: .random, period: 10, seed: 1,
                                 palette: threePaletteColors, enabled: true)

        let first = DriverEvaluator.evaluate(driver, globalElapsed: 0)
        for f in stride(from: 0, to: 10, by: 1) {
            XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: Double(f)), first)
        }
    }

    func testRandomWeightedSkewsTowardHeavierIndex() {
        let driver = ColorDriver(mode: .random, period: 1, seed: 3,
                                 palette: threePaletteColors, weights: [90, 5, 5], enabled: true)

        var counts = [0, 0, 0]
        for f in 0..<2000 {
            let color = DriverEvaluator.evaluate(driver, globalElapsed: Double(f), spriteIndex: 0)
            counts[threePaletteColors.firstIndex(of: color)!] += 1
        }
        XCTAssertGreaterThan(counts[0], counts[1] * 3)
        XCTAssertGreaterThan(counts[0], counts[2] * 3)
    }

    func testRandomMismatchedWeightCountFallsBackToUniform() {
        let driver = ColorDriver(mode: .random, period: 1, seed: 5,
                                 palette: threePaletteColors, weights: [90, 5], enabled: true)

        for f in 0..<50 {
            let color = DriverEvaluator.evaluate(driver, globalElapsed: Double(f))
            XCTAssertTrue(threePaletteColors.contains(color))
        }
    }

    func testRandomEmptyPaletteReturnsBase() {
        let driver = ColorDriver(mode: .random, base: .black, enabled: true)
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 100), .black)
    }

    // MARK: - Interpolate toggle

    /// Mirrors the private channel-wise rounding in `DriverEvaluator.lerpColor`.
    private func expectedLerp(_ a: LoomColor, _ b: LoomColor, t: Double) -> LoomColor {
        func channel(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
        return LoomColor(r: channel(a.r, b.r), g: channel(a.g, b.g), b: channel(a.b, b.b), a: channel(a.a, b.a))
    }

    func testSequentialInterpolatesAcrossHoldPeriod() {
        let driver = ColorDriver(mode: .sequential, period: 10, loopMode: .loop,
                                 palette: threePaletteColors, interpolate: true, enabled: true)

        // Exactly at a hold boundary, output matches that step's color with no blend.
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 0),  threePaletteColors[0])
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 10), threePaletteColors[1])

        // Halfway through the hold window, output is the midpoint blend toward the next color.
        let halfway = DriverEvaluator.evaluate(driver, globalElapsed: 5)
        XCTAssertEqual(halfway, expectedLerp(threePaletteColors[0], threePaletteColors[1], t: 0.5))
    }

    func testSequentialInterpolateFalseKeepsAbruptSteps() {
        // Regression: default (interpolate: false) behavior must survive the refactor.
        let driver = ColorDriver(mode: .sequential, period: 10, loopMode: .loop,
                                 palette: threePaletteColors, enabled: true)
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 5), threePaletteColors[0])
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 9), threePaletteColors[0])
    }

    func testRandomInterpolatesAcrossHoldPeriod() {
        let driver = ColorDriver(mode: .random, period: 10, seed: 9,
                                 palette: threePaletteColors, interpolate: true, enabled: true)

        let current = DriverEvaluator.evaluate(driver, globalElapsed: 0, spriteIndex: 2)
        let next    = DriverEvaluator.evaluate(driver, globalElapsed: 10, spriteIndex: 2)
        let halfway = DriverEvaluator.evaluate(driver, globalElapsed: 5, spriteIndex: 2)
        XCTAssertEqual(halfway, expectedLerp(current, next, t: 0.5))
    }

    func testRandomInterpolateFalseKeepsAbruptSteps() {
        let driver = ColorDriver(mode: .random, period: 10, seed: 1,
                                 palette: threePaletteColors, enabled: true)
        let first = DriverEvaluator.evaluate(driver, globalElapsed: 0)
        XCTAssertEqual(DriverEvaluator.evaluate(driver, globalElapsed: 5), first)
    }
}

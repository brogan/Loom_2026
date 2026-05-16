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
}

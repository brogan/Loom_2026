import XCTest
import CoreGraphics
@testable import LoomEngine

// MARK: - Fixture helpers

private var fixtureDir052: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Test_052")
}

// MARK: - ExportFrameLoop tick-count tests

final class ExportFrameLoopTickTests: XCTestCase {

    func testTickCountAtFps30() {
        let loop  = ExportFrameLoop(fps: 30)
        var count = 0
        loop.start { _ in count += 1 }
        loop.run(frameCount: 30)
        XCTAssertEqual(count, 30)
    }

    func testTickCountAtFps24() {
        let loop  = ExportFrameLoop(fps: 24)
        var count = 0
        loop.start { _ in count += 1 }
        loop.run(frameCount: 24)
        XCTAssertEqual(count, 24)
    }

    func testZeroFramesProducesNoTicks() {
        let loop  = ExportFrameLoop(fps: 30)
        var count = 0
        loop.start { _ in count += 1 }
        loop.run(frameCount: 0)
        XCTAssertEqual(count, 0)
    }

    func testRunWithoutStartProducesNoTicks() {
        let loop  = ExportFrameLoop(fps: 30)
        var count = 0
        // Deliberately do NOT call start(onTick:)
        loop.run(frameCount: 10)
        XCTAssertEqual(count, 0)
    }

    func testStopPreventsSubsequentTicks() {
        let loop  = ExportFrameLoop(fps: 30)
        var count = 0
        loop.start { _ in count += 1 }
        loop.stop()
        loop.run(frameCount: 10)
        XCTAssertEqual(count, 0, "stop() should clear the callback so run() is a no-op")
    }
}

// MARK: - ExportFrameLoop delta-time tests

final class ExportFrameLoopDeltaTimeTests: XCTestCase {

    func testDeltaTimeAtFps30() {
        let loop     = ExportFrameLoop(fps: 30)
        var deltas   = [Double]()
        loop.start { dt in deltas.append(dt) }
        loop.run(frameCount: 30)
        XCTAssertEqual(deltas.count, 30)
        for dt in deltas {
            XCTAssertEqual(dt, 1.0 / 30, accuracy: 1e-12)
        }
    }

    func testDeltaTimeSumEquals1SecondAt30fps() {
        let loop  = ExportFrameLoop(fps: 30)
        var total = 0.0
        loop.start { dt in total += dt }
        loop.run(frameCount: 30)
        XCTAssertEqual(total, 1.0, accuracy: 1e-10,
                       "30 ticks × (1/30 s) should sum to exactly 1 second")
    }

    func testDeltaTimeSumEquals3SecondsAt24fps() {
        let loop  = ExportFrameLoop(fps: 24)
        var total = 0.0
        loop.start { dt in total += dt }
        loop.run(frameCount: 72)   // 3 seconds at 24 fps
        XCTAssertEqual(total, 3.0, accuracy: 1e-10)
    }

    func testDefaultFpsIs30() {
        let loop = ExportFrameLoop()
        XCTAssertEqual(loop.fps, 30)
    }

    /// Replacing the callback via a second start() call updates the receiver.
    func testReplacingCallbackViaStart() {
        let loop   = ExportFrameLoop(fps: 30)
        var firstCount  = 0
        var secondCount = 0
        loop.start { _ in firstCount += 1 }
        loop.start { _ in secondCount += 1 }   // replaces first
        loop.run(frameCount: 5)
        XCTAssertEqual(firstCount,  0)
        XCTAssertEqual(secondCount, 5)
    }
}

// MARK: - Engine init tests

final class EngineInitTests: XCTestCase {

    func testInitFromProjectDirectory() throws {
        XCTAssertNoThrow(try Engine(projectDirectory: fixtureDir052))
    }

    func testInitFromLoomEngine() throws {
        let loom   = try LoomEngine(projectDirectory: fixtureDir052)
        let engine = Engine(loomEngine: loom)
        XCTAssertEqual(engine.currentFrame, 0)
    }

    func testInitialFrameIsZero() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        XCTAssertEqual(engine.currentFrame, 0)
    }

    func testCanvasSizeForwarded() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        XCTAssertEqual(engine.canvasSize.width,  1080, accuracy: 0.1)
        XCTAssertEqual(engine.canvasSize.height, 1080, accuracy: 0.1)
    }

    func testGlobalConfigForwarded() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        XCTAssertEqual(engine.globalConfig.width,  1080)
        XCTAssertEqual(engine.globalConfig.height, 1080)
    }
}

// MARK: - Engine update / advance tests

final class EngineUpdateTests: XCTestCase {

    /// `deltaTime` is real elapsed seconds; `advance` converts it to project-frame
    /// units via `globalConfig.targetFPS` (see `Engine.update` doc comment). Passing
    /// exactly `1.0 / targetFPS` therefore advances exactly one project frame,
    /// *for this project's own fps* — the fixture's `targetFPS` is read here rather
    /// than hardcoded, since a literal `1.0/30` only gives +1 frame when the fixture
    /// happens to be authored at 30fps (Test_052 is not; it defaults to 24).
    func testUpdateAdvancesFrameCount() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        engine.update(deltaTime: 1.0 / engine.globalConfig.targetFPS)
        XCTAssertEqual(engine.currentFrame, 1)
    }

    func testThirtyUpdatesAdvancesThirtyFrames() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let dt = 1.0 / engine.globalConfig.targetFPS
        for _ in 0..<30 { engine.update(deltaTime: dt) }
        XCTAssertEqual(engine.currentFrame, 30)
    }

    /// Any deltaTime that sums (via `dt * targetFPS`) to the same whole number of
    /// project frames should land on that frame — not "any deltaTime is ignored":
    /// deltaTime is real time and genuinely scales frame advancement (see
    /// `Engine.update`'s doc comment). This checks two very different per-call
    /// deltas that both land exactly on frame 2 for this project's targetFPS.
    func testDeltaTimeSplitAcrossCallsStillReachesExpectedFrame() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let fps = engine.globalConfig.targetFPS
        engine.update(deltaTime: 0.0)
        engine.update(deltaTime: 2.0 / fps)
        XCTAssertEqual(engine.currentFrame, 2,
                       "0 seconds then 2 frames' worth of real time should land on frame 2")
    }
}

// MARK: - Engine render tests

final class EngineRenderTests: XCTestCase {

    func testMakeFrameReturnsNonNil() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        XCTAssertNotNil(engine.makeFrame())
    }

    func testMakeFrameDimensions() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let image  = try XCTUnwrap(engine.makeFrame())
        XCTAssertEqual(image.width,  1080)
        XCTAssertEqual(image.height, 1080)
    }

    func testDrawIntoDoesNotCrash() throws {
        let engine  = try Engine(projectDirectory: fixtureDir052)
        let w = 1080, h = 1080
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        defer { buf.deallocate() }
        buf.initialize(repeating: 255, count: w * h * 4)
        let ctx = CGContext(
            data: buf, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        engine.draw(into: ctx)  // must not crash
    }
}

// MARK: - Engine + ExportFrameLoop integration tests

final class EngineExportLoopIntegrationTests: XCTestCase {

    /// `ExportFrameLoop(fps:)` must match the driven project's own `targetFPS` for
    /// "N ticks == N project frames" to hold (each tick delivers `dt = 1/fps`, and
    /// `Engine.update` converts `dt` to project-frame units via the project's own
    /// `targetFPS` — see `Engine.update`'s doc comment). Test_052 has no explicit
    /// `TargetFPS` override and so defaults to 24, not 30.
    func testEngineAdvancesViaExportLoop() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let loop   = ExportFrameLoop(fps: engine.globalConfig.targetFPS)
        engine.start(with: loop)
        loop.run(frameCount: 30)
        XCTAssertEqual(engine.currentFrame, 30,
                       "ExportFrameLoop.run(30) should drive 30 Engine.update calls")
    }

    func testStopAfterLoopProducesNoFurtherAdvances() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let loop   = ExportFrameLoop(fps: engine.globalConfig.targetFPS)
        engine.start(with: loop)
        loop.run(frameCount: 10)
        engine.stop()
        loop.run(frameCount: 10)  // loop still has frames to deliver but engine stopped it
        // After stop(), Engine clears the active loop reference; the loop's callback is nil
        // so these extra run() calls are no-ops.
        XCTAssertEqual(engine.currentFrame, 10)
    }

    func testReplacingLoopStopsOldOne() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let loop1  = ExportFrameLoop(fps: engine.globalConfig.targetFPS)
        let loop2  = ExportFrameLoop(fps: engine.globalConfig.targetFPS)

        engine.start(with: loop1)
        loop1.run(frameCount: 5)

        engine.start(with: loop2)   // replaces loop1
        loop1.run(frameCount: 5)    // old loop — callback was cleared by start(with:)
        loop2.run(frameCount: 3)

        XCTAssertEqual(engine.currentFrame, 8,
                       "5 from loop1 before replace + 3 from loop2; second loop1.run is a no-op")
    }

    func testMakeFrameAfterExportLoopRun() throws {
        let engine = try Engine(projectDirectory: fixtureDir052)
        let loop   = ExportFrameLoop(fps: 30)
        engine.start(with: loop)
        loop.run(frameCount: 90)   // 3 simulated seconds
        engine.stop()
        XCTAssertNotNil(engine.makeFrame())
    }
}

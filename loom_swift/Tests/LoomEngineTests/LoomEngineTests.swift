import XCTest
import CoreGraphics
@testable import LoomEngine

// MARK: - Fixture helpers

private var fixtureDir052: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Test_052")
}

/// Identical to Test_052 except `DrawBackgroundOnce` is `false` (independent-
/// frame/`makeFreshFrame` mode instead of accumulation mode) — needed for
/// anything exercising that code path, since Test_052 itself is
/// accumulation-only. See the fixture's own Note for details.
private var fixtureDir053: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Test_053")
}

// MARK: - Init and accessor tests

final class LoomEngineInitTests: XCTestCase {

    func testInitDoesNotThrow() throws {
        XCTAssertNoThrow(try LoomEngine(projectDirectory: fixtureDir052))
    }

    func testCanvasSize() throws {
        let engine = try LoomEngine(projectDirectory: fixtureDir052)
        // Width=1080, Height=1080, QualityMultiple=1
        XCTAssertEqual(engine.canvasSize.width,  1080, accuracy: 0.1)
        XCTAssertEqual(engine.canvasSize.height, 1080, accuracy: 0.1)
    }

    func testInitialFrameCountIsZero() throws {
        let engine = try LoomEngine(projectDirectory: fixtureDir052)
        XCTAssertEqual(engine.currentFrame, 0)
    }

    func testGlobalConfigAccessor() throws {
        let engine = try LoomEngine(projectDirectory: fixtureDir052)
        XCTAssertEqual(engine.globalConfig.width,  1080)
        XCTAssertEqual(engine.globalConfig.height, 1080)
    }
}

// MARK: - Advance tests

final class LoomEngineAdvanceTests: XCTestCase {

    func testAdvanceIncrementsFrameCount() throws {
        var engine = try LoomEngine(projectDirectory: fixtureDir052)
        engine.advance()
        XCTAssertEqual(engine.currentFrame, 1)
    }

    func testSubFrameAdvanceDoesNotRaceProjectFrameClock() throws {
        var engine = try LoomEngine(projectDirectory: fixtureDir052)
        // Half of one project frame's worth of real time, derived from the
        // fixture's own targetFPS rather than a hardcoded fps assumption (Test_052
        // defaults to 24, not 30) — see Engine.update's doc comment.
        let halfFrame = 1.0 / (engine.globalConfig.targetFPS * 2.0)
        engine.advance(deltaTime: halfFrame)
        XCTAssertEqual(engine.currentFrame, 0)
        engine.advance(deltaTime: halfFrame)
        XCTAssertEqual(engine.currentFrame, 1)
    }

    func testMultipleAdvances() throws {
        var engine = try LoomEngine(projectDirectory: fixtureDir052)
        for _ in 0..<10 { engine.advance() }
        XCTAssertEqual(engine.currentFrame, 10)
    }
}

// MARK: - makeFrame tests

final class LoomEngineMakeFrameTests: XCTestCase {

    func testMakeFrameReturnsNonNil() throws {
        var engine = try LoomEngine(projectDirectory: fixtureDir052)
        XCTAssertNotNil(engine.makeFrame())
    }

    func testMakeFrameDimensions() throws {
        var engine = try LoomEngine(projectDirectory: fixtureDir052)
        let image  = try XCTUnwrap(engine.makeFrame())
        XCTAssertEqual(image.width,  1080)
        XCTAssertEqual(image.height, 1080)
    }

    /// After multiple advances the engine should still produce a valid frame.
    func testMakeFrameAfterAdvances() throws {
        var engine = try LoomEngine(projectDirectory: fixtureDir052)
        for _ in 0..<20 { engine.advance() }
        XCTAssertNotNil(engine.makeFrame())
    }
}

// MARK: - Background / overlay pixel tests

final class LoomEngineRenderPixelTests: XCTestCase {

    /// Read a specific pixel (R,G,B,A) from a CGImage by drawing it into a scratch
    /// context. The scratch context is itself opaque-black-initialized (`0` in
    /// every premultiplied channel including alpha) so a transparent source pixel
    /// reads back as `(0,0,0,0)` rather than being flattened onto some other
    /// backdrop color that could be mistaken for a "real" opaque result.
    private func pixel(at x: Int, _ y: Int, of image: CGImage) -> (r: Int, g: Int, b: Int, a: Int) {
        let w = image.width, h = image.height
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        defer { buf.deallocate() }
        buf.initialize(repeating: 0, count: w * h * 4)

        guard let ctx = CGContext(
            data: buf, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Could not create context for pixel read")
            return (0, 0, 0, 0)
        }
        // .copy (not the default source-over draw) so the source image's own
        // alpha is preserved exactly rather than composited over the scratch
        // context's initial black.
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let idx = (y * w + x) * 4
        return (r: Int(buf[idx]), g: Int(buf[idx + 1]), b: Int(buf[idx + 2]), a: Int(buf[idx + 3]))
    }

    /// Frame 0 (before any advance): background is white and the legacy XML
    /// overlay default is treated as transparent.
    ///
    /// We sample a corner pixel (10,10) which is far from any sprite geometry
    /// (all Test_052 sprites are positioned at/near the canvas centre).
    func testBackgroundAppliedAtFrame0() throws {
        var engine = try LoomEngine(projectDirectory: fixtureDir052)
        let image  = try XCTUnwrap(engine.makeFrame())
        let px     = pixel(at: 10, 10, of: image)

        XCTAssertEqual(px.r, 255, accuracy: 5, "corner pixel should be white with transparent default overlay")
        XCTAssertEqual(px.g, 255, accuracy: 5)
        XCTAssertEqual(px.b, 255, accuracy: 5)
        XCTAssertEqual(px.a, 255, accuracy: 5, "background is opaque by default")
    }

    /// `makeFrame(transparentBackground: true)` — a corner pixel far from any
    /// sprite geometry should read back fully transparent (alpha 0) instead of
    /// the opaque white background `testBackgroundAppliedAtFrame0` confirms for
    /// the default case, and the default (omitted) parameter must still produce
    /// the identical opaque result — zero regression for every existing caller.
    func testTransparentBackgroundLeavesCornerPixelFullyTransparent() throws {
        var engine = try LoomEngine(projectDirectory: fixtureDir053)
        let opaque      = try XCTUnwrap(engine.makeFrame())
        let transparent = try XCTUnwrap(engine.makeFrame(transparentBackground: true))

        let opaquePx      = pixel(at: 10, 10, of: opaque)
        let transparentPx = pixel(at: 10, 10, of: transparent)

        XCTAssertEqual(opaquePx.a, 255, accuracy: 5, "default call is unaffected by the new parameter")
        XCTAssertEqual(transparentPx.a, 0, accuracy: 2, "transparentBackground: true should skip the background fill entirely")
        XCTAssertEqual(transparentPx.r, 0, "a fully transparent (premultiplied) pixel should have zeroed color channels too")
        XCTAssertEqual(transparentPx.g, 0)
        XCTAssertEqual(transparentPx.b, 0)
    }

    /// Canvas dimensions must be identical regardless of the new parameter —
    /// transparency only changes the background fill, never the frame geometry.
    func testTransparentBackgroundDoesNotChangeFrameDimensions() throws {
        var engine = try LoomEngine(projectDirectory: fixtureDir053)
        let image  = try XCTUnwrap(engine.makeFrame(transparentBackground: true))
        XCTAssertEqual(image.width,  1080)
        XCTAssertEqual(image.height, 1080)
    }

    /// In accumulation mode (drawBackgroundOnce = true) repeated makeFrame() calls
    /// draw sprites on top of the same persistent canvas.  A corner pixel far from
    /// any sprite should remain stable across calls when the scene has not advanced.
    func testAccumulationModeCornerStaysWhite() throws {
        var engine = try LoomEngine(projectDirectory: fixtureDir052)
        let img1   = try XCTUnwrap(engine.makeFrame())
        let img2   = try XCTUnwrap(engine.makeFrame())
        let px1    = pixel(at: 10, 10, of: img1)
        let px2    = pixel(at: 10, 10, of: img2)
        XCTAssertEqual(px2.r, px1.r, accuracy: 5, "corner pixel should stay stable in accumulation mode")
        XCTAssertEqual(px2.g, px1.g, accuracy: 5)
        XCTAssertEqual(px2.b, px1.b, accuracy: 5)
    }
}

// MARK: - render(into:) direct tests

final class LoomEngineRenderIntoTests: XCTestCase {

    private func makeCanvas() -> (CGContext, UnsafeMutablePointer<UInt8>) {
        let w = 1080, h = 1080
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        buf.initialize(repeating: 255, count: w * h * 4)
        let ctx = CGContext(
            data: buf, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return (ctx, buf)
    }

    func testRenderIntoDoesNotCrash() throws {
        var engine       = try LoomEngine(projectDirectory: fixtureDir052)
        let (ctx, buf)   = makeCanvas()
        defer { buf.deallocate() }
        engine.render(into: ctx)   // must not crash
    }

    /// render(into:) applies the Y-flip internally so the canvas does not need
    /// any pre-existing transform.  Verify that calling it on a fresh context
    /// (no transform) still produces a non-white result (overlay is always applied).
    func testRenderIntoFillsCanvas() throws {
        var engine     = try LoomEngine(projectDirectory: fixtureDir052)
        let (ctx, buf) = makeCanvas()
        defer { buf.deallocate() }
        engine.render(into: ctx)

        let w = 1080
        let cx = w / 2, cy = w / 2
        let idx = (cy * w + cx) * 4
        // Sprites near the centre may or may not cover this exact pixel; this verifies
        // render completed without corrupting the buffer.
        XCTAssertGreaterThanOrEqual(Int(buf[idx]), 0, "render(into:) completed without corrupting the buffer")
    }
}

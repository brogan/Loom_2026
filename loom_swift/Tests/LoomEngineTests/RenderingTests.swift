import XCTest
import CoreGraphics
@testable import LoomEngine

// MARK: - Helpers

/// An RGBA-8 offscreen bitmap context.
///
/// The context is configured with a Y-flip transform so that `worldToScreen`
/// coordinates map directly to visible pixel positions:
///   user (sx, sy_top)  →  base CG (sx, height − sy_top)  →  buffer row (height − sy_top)
///
/// `pixel(sx:sy:)` reverses this: buffer row = height − sy_top.
/// Note that sy_top == 0 maps to base y == height (just outside the buffer);
/// use sy_top ∈ [1, height−1] for reliable pixel reads.
private final class TestCanvas {

    let width:  Int
    let height: Int
    let context: CGContext
    private let buffer: UnsafeMutablePointer<UInt8>

    init(width: Int = 100, height: Int = 100) {
        self.width  = width
        self.height = height
        let bytesPerRow = width * 4
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: height * bytesPerRow)
        buffer.initialize(repeating: 255, count: height * bytesPerRow)  // white

        context = CGContext(
            data: buffer,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // Apply Y-flip so (0,0) in user space = top-left, matching worldToScreen output.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
    }

    deinit { buffer.deallocate() }

    var viewTransform: ViewTransform {
        ViewTransform(canvasSize: CGSize(width: width, height: height))
    }

    /// Fill the entire canvas with `color`.
    func clear(with color: LoomColor = .white) {
        context.saveGState()
        context.resetClip()
        // Reset the CTM to base coordinates for a full clear
        context.concatenate(context.ctm.inverted())
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }

    /// Read the pixel at screen coordinate `(sx, sy_top)`.
    ///
    /// `sy_top` is measured from the top of the canvas (0 = top row).
    /// Returns `(r, g, b, a)` premultiplied values 0–255.
    func pixel(sx: Int, sy: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        // After Y-flip: user sy_top → base CG y = height - sy_top
        // Buffer row R corresponds to base CG y = R (row 0 = CG y=0 = bottom of context)
        let row = height - sy
        guard row >= 0, row < height, sx >= 0, sx < width else {
            return (0, 0, 0, 0)
        }
        let idx = (row * width + sx) * 4
        return (buffer[idx], buffer[idx + 1], buffer[idx + 2], buffer[idx + 3])
    }

    /// Returns true if every pixel in the canvas is white (255,255,255,255).
    var isAllWhite: Bool {
        let totalBytes = height * width * 4
        for i in 0..<totalBytes {
            if buffer[i] != 255 { return false }
        }
        return true
    }

    /// Returns true if any pixel in the canvas is NOT white.
    var hasAnyNonWhitePixel: Bool { !isAllWhite }
}

// MARK: - LoomColorCGTests

final class LoomColorCGTests: XCTestCase {

    func testBlackCGColor() {
        let c = LoomColor.black.cgColor
        let comps = c.components ?? []
        XCTAssertEqual(comps.count, 4)
        XCTAssertEqual(comps[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(comps[3], 1.0, accuracy: 0.001)
    }

    func testWhiteCGColor() {
        let c = LoomColor.white.cgColor
        let comps = c.components ?? []
        XCTAssertEqual(comps.count, 4)
        XCTAssertEqual(comps[0], 1.0, accuracy: 0.001)
        XCTAssertEqual(comps[1], 1.0, accuracy: 0.001)
        XCTAssertEqual(comps[2], 1.0, accuracy: 0.001)
        XCTAssertEqual(comps[3], 1.0, accuracy: 0.001)
    }

    func testArbitraryCGColor() {
        let c = LoomColor(r: 51, g: 102, b: 153, a: 204).cgColor
        let comps = c.components ?? []
        XCTAssertEqual(comps[0], 51.0  / 255.0, accuracy: 0.001)
        XCTAssertEqual(comps[1], 102.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(comps[2], 153.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(comps[3], 204.0 / 255.0, accuracy: 0.001)
    }
}

// MARK: - RenderEngineStrokedTests

final class RenderEngineStrokedTests: XCTestCase {

    // Canvas: 100×100.  World square ±40 units → screen (10,10)–(90,90).
    private func makeSquarePolygon() -> Polygon2D {
        // Line polygon: 4 corners, closed.
        let pts: [Vector2D] = [
            Vector2D(x: -40, y:  40),   // top-left in world (Y-up)
            Vector2D(x:  40, y:  40),   // top-right
            Vector2D(x:  40, y: -40),   // bottom-right
            Vector2D(x: -40, y: -40)    // bottom-left
        ]
        return Polygon2D(points: pts, type: .line)
    }

    func testStrokedPolygonProducesOutput() {
        let canvas = TestCanvas()
        let renderer = Renderer(mode: .stroked, strokeWidth: 2.0, strokeColor: .black)
        RenderEngine.draw(makeSquarePolygon(), renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)
        XCTAssertTrue(canvas.hasAnyNonWhitePixel, "stroked polygon must mark at least one pixel")
    }

    func testStrokedInteriorRemainsWhite() {
        let canvas = TestCanvas()
        let renderer = Renderer(mode: .stroked, strokeWidth: 1.0, strokeColor: .black)
        RenderEngine.draw(makeSquarePolygon(), renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)
        // Centre of canvas is well inside the square — should still be white
        let (r, g, b, _) = canvas.pixel(sx: 50, sy: 50)
        XCTAssertEqual(r, 255, "interior should be white (red)")
        XCTAssertEqual(g, 255, "interior should be white (green)")
        XCTAssertEqual(b, 255, "interior should be white (blue)")
    }

    func testInvisiblePolygonProducesNoOutput() {
        let canvas   = TestCanvas()
        var poly     = makeSquarePolygon()
        poly.visible = false
        let renderer = Renderer(mode: .stroked, strokeWidth: 2.0, strokeColor: .black)
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)
        XCTAssertTrue(canvas.isAllWhite, "invisible polygon must not mark any pixel")
    }

    func testEmptyPolygonProducesNoOutput() {
        let canvas   = TestCanvas()
        let poly     = Polygon2D(points: [], type: .line)
        let renderer = Renderer(mode: .stroked, strokeWidth: 2.0, strokeColor: .black)
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)
        XCTAssertTrue(canvas.isAllWhite, "empty polygon must not mark any pixel")
    }
}

// MARK: - RenderEngineFilledTests

final class RenderEngineFilledTests: XCTestCase {

    // Filled square ±40 world units, red fill.
    private func makeRedFilledSquare() -> (Polygon2D, Renderer) {
        let pts: [Vector2D] = [
            Vector2D(x: -40, y:  40),
            Vector2D(x:  40, y:  40),
            Vector2D(x:  40, y: -40),
            Vector2D(x: -40, y: -40)
        ]
        let poly     = Polygon2D(points: pts, type: .line)
        let renderer = Renderer(
            mode: .filled,
            strokeWidth: 1.0,
            strokeColor: .black,
            fillColor: LoomColor(r: 255, g: 0, b: 0, a: 255)
        )
        return (poly, renderer)
    }

    func testFilledPolygonProducesOutput() {
        let canvas = TestCanvas()
        let (poly, renderer) = makeRedFilledSquare()
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)
        XCTAssertTrue(canvas.hasAnyNonWhitePixel)
    }

    func testFilledCentrePixelIsFilledColor() {
        let canvas = TestCanvas()
        let (poly, renderer) = makeRedFilledSquare()
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)

        // Canvas centre (50,50) is inside the ±40 square → should be red.
        let (r, g, b, a) = canvas.pixel(sx: 50, sy: 50)
        XCTAssertGreaterThan(r, 200, "centre pixel should be red")
        XCTAssertLessThan(g, 50,  "centre pixel green should be near 0")
        XCTAssertLessThan(b, 50,  "centre pixel blue should be near 0")
        XCTAssertEqual(a, 255)
    }

    func testFilledOutsidePolygonIsWhite() {
        let canvas = TestCanvas()
        let (poly, renderer) = makeRedFilledSquare()
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)

        // Screen (5, 5) is outside the square (which starts at screen x=10, y=10).
        let (r, g, b, _) = canvas.pixel(sx: 5, sy: 5)
        XCTAssertEqual(r, 255)
        XCTAssertEqual(g, 255)
        XCTAssertEqual(b, 255)
    }

    func testFilledStrokedModeRendersFilledAndStroke() {
        let canvas = TestCanvas()
        let pts: [Vector2D] = [
            Vector2D(x: -40, y:  40),
            Vector2D(x:  40, y:  40),
            Vector2D(x:  40, y: -40),
            Vector2D(x: -40, y: -40)
        ]
        let poly     = Polygon2D(points: pts, type: .line)
        let renderer = Renderer(
            mode: .filledStroked,
            strokeWidth: 4.0,
            strokeColor: LoomColor(r: 0, g: 0, b: 255, a: 255),  // blue stroke
            fillColor: LoomColor(r: 255, g: 0, b: 0, a: 255)     // red fill
        )
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)

        // Interior should be red (fill)
        let (ri, gi, bi, _) = canvas.pixel(sx: 50, sy: 50)
        XCTAssertGreaterThan(ri, 200, "interior should be filled red")
        XCTAssertLessThan(gi, 50)
        XCTAssertLessThan(bi, 50)
    }
}

// MARK: - RenderEnginePointsTests

final class RenderEnginePointsTests: XCTestCase {

    func testPointsModeRendersAtAnchorLocations() {
        let canvas = TestCanvas()

        // A single-anchor line polygon at world origin → screen (50, 50).
        let poly     = Polygon2D(points: [Vector2D.zero], type: .line)
        let renderer = Renderer(
            mode: .points,
            strokeWidth: 1.0,
            strokeColor: LoomColor(r: 0, g: 0, b: 0, a: 255),
            pointSize: 10.0
        )
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)

        // The 10-pt diameter dot centred at screen (50,50) must produce non-white pixels.
        XCTAssertTrue(canvas.hasAnyNonWhitePixel)
        let (r, g, b, _) = canvas.pixel(sx: 50, sy: 50)
        XCTAssertLessThan(Int(r) + Int(g) + Int(b), 50, "centre of dot should be dark")
    }

    func testPointsModeSplineUsesAnchorsOnly() {
        // Spline with 2 segments (8 points). Anchors at indices 0 and 4.
        // Both anchors at world origin, so the entire spline is degenerate — but
        // anchors exist and should produce dots.
        let canvas = TestCanvas()
        let zero   = Vector2D.zero
        let pts    = [zero, zero, zero, zero,   // curve 0: all at origin
                      zero, zero, zero, zero]   // curve 1: all at origin
        let poly     = Polygon2D(points: pts, type: .spline)
        let renderer = Renderer(mode: .points, strokeColor: .black, pointSize: 8.0)
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)
        XCTAssertTrue(canvas.hasAnyNonWhitePixel)
    }

    func testBrushedAndStenciledModeProduceNoOutput() {
        let canvas   = TestCanvas()
        let pts      = [Vector2D(x: -40, y: 40), Vector2D(x: 40, y: 40),
                        Vector2D(x: 40, y: -40), Vector2D(x: -40, y: -40)]
        let poly     = Polygon2D(points: pts, type: .line)

        for mode in [RendererMode.brushed, .stenciled] {
            let renderer = Renderer(mode: mode, strokeColor: .black,
                                    fillColor: .black)
            RenderEngine.draw(poly, renderer: renderer,
                              into: canvas.context, transform: canvas.viewTransform)
        }
        XCTAssertTrue(canvas.isAllWhite, ".brushed and .stenciled are stubs — no output")
    }
}

// MARK: - RenderEngineSplineTests

final class RenderEngineSplineTests: XCTestCase {

    func testSplinePolygonProducesOutput() {
        let canvas = TestCanvas()

        // Build a square spline using BezierMath.connector.
        let cp = Vector2D(x: 0.25, y: 0.75)
        let corners: [Vector2D] = [
            Vector2D(x: -30, y:  30),
            Vector2D(x:  30, y:  30),
            Vector2D(x:  30, y: -30),
            Vector2D(x: -30, y: -30)
        ]
        var pts = [Vector2D]()
        for i in 0..<4 {
            pts += BezierMath.connector(from: corners[i],
                                        to:   corners[(i + 1) % 4],
                                        cpRatios: cp)
        }
        let poly     = Polygon2D(points: pts, type: .spline)
        let renderer = Renderer(mode: .stroked, strokeWidth: 2.0, strokeColor: .black)
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)
        XCTAssertTrue(canvas.hasAnyNonWhitePixel, "spline polygon must produce stroke output")
    }

    func testOpenSplinePolygonProducesOutput() {
        let canvas = TestCanvas()

        // Two-segment open spline: straight line from (-30,0) to (30,0).
        let cp   = Vector2D(x: 0.5, y: 0.5)
        let from = Vector2D(x: -30, y: 0)
        let to   = Vector2D(x:  30, y: 0)
        let pts  = BezierMath.connector(from: from, to: to, cpRatios: cp)
        let poly     = Polygon2D(points: pts, type: .openSpline)
        let renderer = Renderer(mode: .stroked, strokeWidth: 2.0, strokeColor: .black)
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)
        XCTAssertTrue(canvas.hasAnyNonWhitePixel, "open spline must produce stroke output")
    }
}

// MARK: - RenderEngineOvalTests

final class RenderEngineOvalTests: XCTestCase {

    func testOvalPolygonProducesOutput() {
        let canvas = TestCanvas()

        // Oval centred at origin, radius 20 in both axes.
        // pts[0] = centre (world 0,0 → screen 50,50)
        // pts[1] = radius endpoint (world 20,20 → screen 70,30)
        let pts: [Vector2D] = [
            Vector2D(x: 0,  y: 0),
            Vector2D(x: 20, y: 20)
        ]
        let poly     = Polygon2D(points: pts, type: .oval)
        let renderer = Renderer(mode: .stroked, strokeWidth: 2.0, strokeColor: .black)
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)
        XCTAssertTrue(canvas.hasAnyNonWhitePixel, "oval must produce stroke output")
    }

    func testFilledOval() {
        let canvas = TestCanvas()
        let pts: [Vector2D] = [
            Vector2D(x: 0,  y: 0),
            Vector2D(x: 20, y: 20)
        ]
        let poly = Polygon2D(points: pts, type: .oval)
        let renderer = Renderer(
            mode: .filled,
            fillColor: LoomColor(r: 0, g: 200, b: 0, a: 255)
        )
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas.context, transform: canvas.viewTransform)

        // Centre at screen (50,50) is inside the oval
        let (r, g, b, _) = canvas.pixel(sx: 50, sy: 50)
        XCTAssertLessThan(r, 50)
        XCTAssertGreaterThan(g, 150, "centre of filled oval should be green")
        XCTAssertLessThan(b, 50)
    }
}

// MARK: - ViewTransformRenderIntegrationTests

final class ViewTransformRenderIntegrationTests: XCTestCase {

    func testOffsetShiftsRenderedPolygon() {
        // Draw same polygon twice — once with zero offset, once with +40 x-offset.
        // With x-offset=40, the polygon shifts right; the left region should differ.

        let pts: [Vector2D] = [
            Vector2D(x: -10, y:  10),
            Vector2D(x:  10, y:  10),
            Vector2D(x:  10, y: -10),
            Vector2D(x: -10, y: -10)
        ]
        let poly     = Polygon2D(points: pts, type: .line)
        let renderer = Renderer(mode: .filled, fillColor: .black)

        // Centred render: fill covers screen (40,40)–(60,60)
        let canvas1 = TestCanvas()
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas1.context, transform: canvas1.viewTransform)

        // Shifted render: offset +40 world units → polygon now at screen (80,40)–(100,60)
        let canvas2 = TestCanvas()
        let shifted = ViewTransform(canvasSize: CGSize(width: 100, height: 100),
                                    offset: Vector2D(x: 40, y: 0))
        RenderEngine.draw(poly, renderer: renderer,
                          into: canvas2.context, transform: shifted)

        // Centre of canvas should be black (filled) in canvas1 but white (empty) in canvas2
        let (r1, _, _, _) = canvas1.pixel(sx: 50, sy: 50)
        let (r2, _, _, _) = canvas2.pixel(sx: 50, sy: 50)
        XCTAssertLessThan(Int(r1), 50, "canvas1 centre should be filled")
        XCTAssertEqual(r2, 255, "canvas2 centre should be empty after shift")
    }
}

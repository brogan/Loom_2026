import XCTest
import CoreGraphics
@testable import LoomEngine

final class DisplacementMapImageTests: XCTestCase {

    // MARK: - Sampling

    func testSampleAtOriginReturnsExactTopLeftCell() {
        // fx = u*width = 0 exactly when u = 0, so tx = 0 and no blending occurs.
        let map = DisplacementMapImage(width: 2, height: 2, grid: [0.1, 0.9, 0.2, 0.8])
        XCTAssertEqual(map.sample(u: 0, v: 0), 0.1, accuracy: 1e-9)
    }

    func testSampleWrapsSeamlessly() {
        let map = DisplacementMapImage(width: 2, height: 2, grid: [0.1, 0.9, 0.2, 0.8])
        // u = 1.0 wraps to exactly u = 0.0 (1.0 mod 1.0 = 0), same for many-cycles-deep offsets.
        XCTAssertEqual(map.sample(u: 1.0, v: 0), map.sample(u: 0.0, v: 0), accuracy: 1e-9)
        XCTAssertEqual(map.sample(u: 7.0, v: 0), map.sample(u: 0.0, v: 0), accuracy: 1e-9)
        XCTAssertEqual(map.sample(u: -1.0, v: 0), map.sample(u: 0.0, v: 0), accuracy: 1e-9)
    }

    func testSampleBilinearBlendsBetweenAdjacentCells() {
        // 2x1 grid: [0.0, 1.0]. u = 0.25 -> fx = 0.5 -> exactly halfway between
        // cell 0 and cell 1 -> expected 0.5.
        let map = DisplacementMapImage(width: 2, height: 1, grid: [0.0, 1.0])
        XCTAssertEqual(map.sample(u: 0.25, v: 0), 0.5, accuracy: 1e-9)
    }

    func testSampleOnEmptyGridReturnsNeutralGrey() {
        let map = DisplacementMapImage(width: 0, height: 0, grid: [])
        XCTAssertEqual(map.sample(u: 0.3, v: 0.7), 0.5, accuracy: 1e-9)
    }

    // MARK: - Loading

    func testLoadFromCGImageProducesExpectedGreyscaleValues() {
        // Build a 2x1 RGB image: solid black, solid white.
        let width = 2, height = 1
        var pixels: [UInt8] = [0, 0, 0, 255,   255, 255, 255, 255] // RGBA
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = ctx.makeImage() else {
            XCTFail("Failed to construct test CGImage")
            return
        }
        guard let map = DisplacementMapImage.load(from: cgImage) else {
            XCTFail("DisplacementMapImage.load returned nil")
            return
        }
        XCTAssertEqual(map.width, 2)
        XCTAssertEqual(map.height, 1)
        XCTAssertEqual(map.grid[0], 0.0, accuracy: 0.02)
        XCTAssertEqual(map.grid[1], 1.0, accuracy: 0.02)
    }
}

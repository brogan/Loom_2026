import XCTest
@testable import LoomEngine

/// §4.4.8.6 step 1: primitive generation + distortion proven in isolation, no
/// attachment logic exists yet.
final class GraftEngineTests: XCTestCase {

    private func params(sidesMin: Int, sidesMax: Int, distortionMin: Double = 1.0, distortionMax: Double = 1.0) -> EvolutionParams {
        var p = EvolutionParams()
        p.graftSidesMin = sidesMin
        p.graftSidesMax = sidesMax
        p.graftDistortionMin = distortionMin
        p.graftDistortionMax = distortionMax
        return p
    }

    // MARK: - n → primitive kind mapping

    func testSidesOneProducesLine() {
        let result = GraftEngine.generatePrimitive(seed: 1, rollBase: 0, params: params(sidesMin: 1, sidesMax: 1))
        XCTAssertEqual(result.sides, 1)
        XCTAssertEqual(result.piece.type, .openSpline)
        XCTAssertEqual(result.piece.points.count, 4)
    }

    func testSidesTwoDegeneratesToLine() {
        // No meaningful 2-sided closed polygon — n=2 resolves to the same line as n=1.
        let result = GraftEngine.generatePrimitive(seed: 1, rollBase: 0, params: params(sidesMin: 2, sidesMax: 2))
        XCTAssertEqual(result.sides, 2, "the *rolled* n is still reported as 2")
        XCTAssertEqual(result.piece.type, .openSpline, "but the generated shape is the line primitive")
        XCTAssertEqual(result.piece.points.count, 4)
    }

    func testSidesThreeProducesTriangle() {
        let result = GraftEngine.generatePrimitive(seed: 1, rollBase: 0, params: params(sidesMin: 3, sidesMax: 3))
        XCTAssertEqual(result.sides, 3)
        XCTAssertEqual(result.piece.type, .line)
        XCTAssertEqual(result.piece.points.count, 3)
    }

    func testSidesFourProducesQuad() {
        let result = GraftEngine.generatePrimitive(seed: 1, rollBase: 0, params: params(sidesMin: 4, sidesMax: 4))
        XCTAssertEqual(result.sides, 4)
        XCTAssertEqual(result.piece.points.count, 4)
    }

    func testSidesFiveProducesPentagon() {
        let result = GraftEngine.generatePrimitive(seed: 1, rollBase: 0, params: params(sidesMin: 5, sidesMax: 5))
        XCTAssertEqual(result.sides, 5)
        XCTAssertEqual(result.piece.points.count, 5)
    }

    func testSidesSixProducesHexagonBeyondTheFixedAssemblyKit() {
        // AssemblyPrimitiveKind only has square/triangle/pentagon/line — n=6 proves
        // GraftEngine really does call plainPolygon(sides:) directly rather than
        // being limited to that closed enum's cases.
        let result = GraftEngine.generatePrimitive(seed: 1, rollBase: 0, params: params(sidesMin: 6, sidesMax: 6))
        XCTAssertEqual(result.sides, 6)
        XCTAssertEqual(result.piece.type, .line)
        XCTAssertEqual(result.piece.points.count, 6)
    }

    func testSidesStayWithinConfiguredRangeAcrossManySeeds() {
        let p = params(sidesMin: 3, sidesMax: 7)
        for seedTry in 0..<50 {
            let result = GraftEngine.generatePrimitive(seed: seedTry, rollBase: 0, params: p)
            XCTAssertGreaterThanOrEqual(result.sides, 3, "seed \(seedTry)")
            XCTAssertLessThanOrEqual(result.sides, 7, "seed \(seedTry)")
        }
    }

    // MARK: - Distortion

    func testDefaultDistortionRangeIsNeutral() {
        let p = params(sidesMin: 4, sidesMax: 4)  // distortion defaults to 1–1
        let undistorted = AssemblyPrimitiveKit.plainPolygon(sides: 4)
        let result = GraftEngine.generatePrimitive(seed: 7, rollBase: 0, params: p)
        XCTAssertEqual(result.piece, undistorted)
    }

    func testDistortionAppliesIndependentXYScale() {
        let p = params(sidesMin: 4, sidesMax: 4, distortionMin: 2.0, distortionMax: 2.0)
        let undistorted = AssemblyPrimitiveKit.plainPolygon(sides: 4)
        let result = GraftEngine.generatePrimitive(seed: 7, rollBase: 0, params: p)
        for (orig, distorted) in zip(undistorted.points, result.piece.points) {
            XCTAssertEqual(distorted.x, orig.x * 2.0, accuracy: 1e-9)
            XCTAssertEqual(distorted.y, orig.y * 2.0, accuracy: 1e-9)
        }
    }

    func testDistortionVariesIndependentlyPerAxis() {
        // A square's vertices (plainPolygon(sides: 4)) land on a diamond — every
        // point has x==0 or y==0 — so a triangle is used here instead, which has
        // vertices with both nonzero x and y, to compare per-axis scale cleanly.
        let p = params(sidesMin: 3, sidesMax: 3, distortionMin: 0.5, distortionMax: 1.5)
        // Same seed, but x and y rolls come from different cycle offsets
        // (rollBase+1 vs rollBase+2), so unless the hash coincidentally produces
        // the same value twice, the two axes should differ.
        let result = GraftEngine.generatePrimitive(seed: 3, rollBase: 0, params: p)
        let undistorted = AssemblyPrimitiveKit.plainPolygon(sides: 3)
        guard let idx = undistorted.points.firstIndex(where: { abs($0.x) > 1e-6 && abs($0.y) > 1e-6 }) else {
            return XCTFail("fixture assumption broken: expected a point with nonzero x and y")
        }
        let scaleX = result.piece.points[idx].x / undistorted.points[idx].x
        let scaleY = result.piece.points[idx].y / undistorted.points[idx].y
        XCTAssertNotEqual(scaleX, scaleY, accuracy: 1e-9)
    }

    // MARK: - Determinism

    func testGeneratePrimitiveIsDeterministic() {
        let p = params(sidesMin: 3, sidesMax: 6, distortionMin: 0.7, distortionMax: 1.3)
        let a = GraftEngine.generatePrimitive(seed: 42, rollBase: 8, params: p)
        let b = GraftEngine.generatePrimitive(seed: 42, rollBase: 8, params: p)
        XCTAssertEqual(a, b)
    }

    func testDifferentRollBaseCanProduceDifferentResult() {
        let p = params(sidesMin: 3, sidesMax: 6, distortionMin: 0.7, distortionMax: 1.3)
        let a = GraftEngine.generatePrimitive(seed: 42, rollBase: 0, params: p)
        let b = GraftEngine.generatePrimitive(seed: 42, rollBase: 8, params: p)
        XCTAssertNotEqual(a, b)
    }
}

import XCTest
@testable import LoomEngine

/// §4.4.8.6 step 1: primitive generation + distortion proven in isolation, no
/// attachment logic exists yet.
final class GraftEngineTests: XCTestCase {

    private func params(
        sidesMin: Int, sidesMax: Int,
        distortionMin: Double = 1.0, distortionMax: Double = 1.0,
        scaleMin: Double = 1.0, scaleMax: Double = 1.0
    ) -> EvolutionParams {
        var p = EvolutionParams()
        p.graftSidesMin = sidesMin
        p.graftSidesMax = sidesMax
        p.graftDistortionMin = distortionMin
        p.graftDistortionMax = distortionMax
        p.graftScaleMin = scaleMin
        p.graftScaleMax = scaleMax
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

    // MARK: - Scale

    func testDefaultScaleRangeIsNeutral() {
        let p = params(sidesMin: 4, sidesMax: 4)  // scale defaults to 1-1
        let undistorted = AssemblyPrimitiveKit.plainPolygon(sides: 4)
        let result = GraftEngine.generatePrimitive(seed: 7, rollBase: 0, params: p)
        XCTAssertEqual(result.piece, undistorted)
    }

    func testScaleAppliesUniformMultiplier() {
        let p = params(sidesMin: 4, sidesMax: 4, scaleMin: 2.0, scaleMax: 2.0)
        let undistorted = AssemblyPrimitiveKit.plainPolygon(sides: 4)
        let result = GraftEngine.generatePrimitive(seed: 7, rollBase: 0, params: p)
        for (orig, scaled) in zip(undistorted.points, result.piece.points) {
            XCTAssertEqual(scaled.x, orig.x * 2.0, accuracy: 1e-9)
            XCTAssertEqual(scaled.y, orig.y * 2.0, accuracy: 1e-9)
        }
    }

    func testScaleComposesMultiplicativelyWithDistortion() {
        // Both fixed (equal min/max) so the combined factor is exactly predictable:
        // scale 2.0 * distortion 3.0 = 6.0 on every axis.
        let p = params(sidesMin: 4, sidesMax: 4, distortionMin: 3.0, distortionMax: 3.0, scaleMin: 2.0, scaleMax: 2.0)
        let undistorted = AssemblyPrimitiveKit.plainPolygon(sides: 4)
        let result = GraftEngine.generatePrimitive(seed: 11, rollBase: 0, params: p)
        for (orig, scaled) in zip(undistorted.points, result.piece.points) {
            XCTAssertEqual(scaled.x, orig.x * 6.0, accuracy: 1e-9)
            XCTAssertEqual(scaled.y, orig.y * 6.0, accuracy: 1e-9)
        }
    }

    func testScaleRangeStaysWithinConfiguredBoundsAcrossManySeeds() {
        let p = params(sidesMin: 4, sidesMax: 4, scaleMin: 0.5, scaleMax: 1.5)
        let undistorted = AssemblyPrimitiveKit.plainPolygon(sides: 4)
        // Distortion is neutral (1-1 default), so the ratio of any nonzero
        // coordinate directly reveals the sampled scale factor.
        guard let idx = undistorted.points.firstIndex(where: { abs($0.y) > 1e-6 }) else {
            return XCTFail("fixture assumption broken")
        }
        for seedTry in 0..<30 {
            let result = GraftEngine.generatePrimitive(seed: seedTry, rollBase: 0, params: p)
            let ratio = result.piece.points[idx].y / undistorted.points[idx].y
            XCTAssertGreaterThanOrEqual(ratio, 0.5 - 1e-9, "seed \(seedTry)")
            XCTAssertLessThanOrEqual(ratio, 1.5 + 1e-9, "seed \(seedTry)")
        }
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

    // MARK: - Custom primitive source (2026-07-12)

    private func customShape() -> Polygon2D {
        // An irregular closed shape — deliberately not a plain n-gon, to prove
        // the pipeline is using the *provided* shape rather than coincidentally
        // matching a generated one.
        Polygon2D(points: [
            Vector2D(x: 0, y: 0), Vector2D(x: 0.1, y: 0), Vector2D(x: 0.2, y: 0.05), Vector2D(x: 0.3, y: 0.1),
            Vector2D(x: 0.35, y: 0.15), Vector2D(x: 0.4, y: 0.3), Vector2D(x: 0.2, y: 0.4), Vector2D(x: 0.1, y: 0.35),
            Vector2D(x: -0.1, y: 0.3), Vector2D(x: -0.15, y: 0.2), Vector2D(x: -0.1, y: 0.1), Vector2D(x: -0.05, y: 0.05),
        ], type: .spline)
    }

    private func customParams(names: [String]) -> EvolutionParams {
        var p = EvolutionParams()
        p.graftPrimitiveSource = .customSet
        p.graftCustomShapes = names.map { GraftCustomShapeEntry(name: $0) }
        return p
    }

    func testCustomSetSourceUsesTheProvidedShapeVerbatimWhenNeutral() {
        let shape = customShape()
        let p = customParams(names: ["mine"])
        let result = GraftEngine.generatePrimitive(seed: 1, rollBase: 0, params: p, customPrimitives: ["mine": shape])
        // Scale/distortion default to 1–1 (neutral), so the piece should be the
        // custom shape exactly, not a generated n-gon.
        XCTAssertEqual(result.piece, shape)
        XCTAssertEqual(result.sides, shape.points.count / 4)
    }

    func testCustomSetSourceStillAppliesScaleAndDistortion() {
        let shape = customShape()
        var p = customParams(names: ["mine"])
        p.graftScaleMin = 2.0
        p.graftScaleMax = 2.0
        let result = GraftEngine.generatePrimitive(seed: 1, rollBase: 0, params: p, customPrimitives: ["mine": shape])
        for (orig, scaled) in zip(shape.points, result.piece.points) {
            XCTAssertEqual(scaled.x, orig.x * 2.0, accuracy: 1e-9)
            XCTAssertEqual(scaled.y, orig.y * 2.0, accuracy: 1e-9)
        }
    }

    func testCustomSetSourceFallsBackToGeneratedWhenNoNameResolves() {
        let p = customParams(names: ["doesNotExist"])
        let withCustom = GraftEngine.generatePrimitive(seed: 5, rollBase: 0, params: p, customPrimitives: [:])

        var generatedEquivalent = p
        generatedEquivalent.graftPrimitiveSource = .generated
        let expected = GraftEngine.generatePrimitive(seed: 5, rollBase: 0, params: generatedEquivalent)

        XCTAssertEqual(withCustom, expected, "an unresolved name must fall back to exactly the .generated result")
    }

    func testCustomSetSourceHasNoEffectWhenSourceIsGenerated() {
        // Regression: graftCustomShapes populated but graftPrimitiveSource left
        // at its .generated default must be a complete no-op.
        var p = EvolutionParams()
        p.graftCustomShapes = [GraftCustomShapeEntry(name: "mine")]
        let withNames = GraftEngine.generatePrimitive(seed: 3, rollBase: 0, params: p, customPrimitives: ["mine": customShape()])

        let withoutNames = GraftEngine.generatePrimitive(seed: 3, rollBase: 0, params: EvolutionParams())
        XCTAssertEqual(withNames, withoutNames)
    }

    func testCustomSetSourcePicksAmongMultipleNamesWithVariety() {
        let shapeA = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0.1, y: 0), Vector2D(x: 0.1, y: 0.1), Vector2D(x: 0, y: 0.1)], type: .spline)
        let shapeB = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0.2, y: 0), Vector2D(x: 0.1, y: 0.2)], type: .spline)
        let p = customParams(names: ["a", "b"])
        let primitives = ["a": shapeA, "b": shapeB]

        var seenSideCounts = Set<Int>()
        for seed in 0..<20 {
            let result = GraftEngine.generatePrimitive(seed: seed, rollBase: 0, params: p, customPrimitives: primitives)
            XCTAssertTrue(result.sides == shapeA.points.count / 4 || result.sides == shapeB.points.count / 4,
                          "seed \(seed): must pick one of the two provided shapes")
            seenSideCounts.insert(result.sides)
        }
        XCTAssertEqual(seenSideCounts.count, 2, "across enough seeds, both shapes should get picked at least once")
    }

    func testCustomSetSourceOnlyPicksAmongNamesThatActuallyResolve() {
        // "missing" never resolves; only "mine" should ever be picked, regardless
        // of which name the roll would have landed on.
        let shape = customShape()
        let p = customParams(names: ["missing", "mine"])
        for seed in 0..<20 {
            let result = GraftEngine.generatePrimitive(seed: seed, rollBase: 0, params: p, customPrimitives: ["mine": shape])
            XCTAssertEqual(result.sides, shape.points.count / 4, "seed \(seed)")
        }
    }

    func testCustomSetSourceIsDeterministic() {
        let shapeA = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0.1, y: 0), Vector2D(x: 0.1, y: 0.1), Vector2D(x: 0, y: 0.1)], type: .spline)
        let shapeB = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0.2, y: 0), Vector2D(x: 0.1, y: 0.2)], type: .spline)
        let p = customParams(names: ["a", "b"])
        let primitives = ["a": shapeA, "b": shapeB]
        let a = GraftEngine.generatePrimitive(seed: 9, rollBase: 3, params: p, customPrimitives: primitives)
        let b = GraftEngine.generatePrimitive(seed: 9, rollBase: 3, params: p, customPrimitives: primitives)
        XCTAssertEqual(a, b)
    }

    // MARK: - Per-shape probability (2026-07-13)

    func testProbabilityZeroExcludesAShapeEntirely() {
        let shapeA = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0.1, y: 0), Vector2D(x: 0.1, y: 0.1), Vector2D(x: 0, y: 0.1)], type: .spline)
        let shapeB = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0.2, y: 0), Vector2D(x: 0.1, y: 0.2)], type: .spline)
        var p = EvolutionParams()
        p.graftPrimitiveSource = .customSet
        p.graftCustomShapes = [
            GraftCustomShapeEntry(name: "a", probability: 0.0),
            GraftCustomShapeEntry(name: "b", probability: 1.0),
        ]
        let primitives = ["a": shapeA, "b": shapeB]
        for seed in 0..<20 {
            let result = GraftEngine.generatePrimitive(seed: seed, rollBase: 0, params: p, customPrimitives: primitives)
            XCTAssertEqual(result.sides, shapeB.points.count / 4, "seed \(seed): probability 0 must never be picked")
        }
    }

    func testUnequalProbabilityBiasesSelectionFrequency() {
        let shapeA = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0.1, y: 0), Vector2D(x: 0.1, y: 0.1), Vector2D(x: 0, y: 0.1)], type: .spline)
        let shapeB = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0.2, y: 0), Vector2D(x: 0.1, y: 0.2)], type: .spline)
        var p = EvolutionParams()
        p.graftPrimitiveSource = .customSet
        p.graftCustomShapes = [
            GraftCustomShapeEntry(name: "a", probability: 0.9),
            GraftCustomShapeEntry(name: "b", probability: 0.1),
        ]
        let primitives = ["a": shapeA, "b": shapeB]
        var aCount = 0
        let trials = 500
        for seed in 0..<trials {
            let result = GraftEngine.generatePrimitive(seed: seed, rollBase: 0, params: p, customPrimitives: primitives)
            if result.sides == shapeA.points.count / 4 { aCount += 1 }
        }
        // Not an exact 90/10 split (RPSR isn't a true uniform RNG over this small
        // a sample), but heavily biased toward "a" — comfortably clear of 50/50.
        XCTAssertGreaterThan(aCount, trials * 2 / 3, "a (weight 0.9) should be picked far more often than b (weight 0.1)")
    }

    func testEqualProbabilitiesMatchOldUniformPickExactly() {
        // Every entry left at its default probability (1.0) must reproduce the
        // exact same pick, seed for seed, as the old plain-uniform-index scheme —
        // i.e. this is a pure rename/generalization, not a behavior change for
        // any previously authored list.
        let shapeA = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0.1, y: 0), Vector2D(x: 0.1, y: 0.1), Vector2D(x: 0, y: 0.1)], type: .spline)
        let shapeB = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0.2, y: 0), Vector2D(x: 0.1, y: 0.2)], type: .spline)
        let primitives = ["a": shapeA, "b": shapeB]
        for seed in 0..<30 {
            let p = customParams(names: ["a", "b"])
            let result = GraftEngine.generatePrimitive(seed: seed, rollBase: 0, params: p, customPrimitives: primitives)
            let pickRoll = SubdivisionEngine.centreHash(seed: seed, cycle: 0)
            let expectedIdx = min(1, Int(pickRoll * 2.0))
            let expectedName = ["a", "b"][expectedIdx]
            XCTAssertEqual(result.sides, primitives[expectedName]!.points.count / 4, "seed \(seed)")
        }
    }
}

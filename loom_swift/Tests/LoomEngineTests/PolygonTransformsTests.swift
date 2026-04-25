import XCTest
@testable import LoomEngine

// MARK: - Helpers

/// A square spline polygon (4 sides × 4 points = 16 points).
/// Each side is a straight Bézier segment at ±1.
private func makeSquare(size: Double = 1.0) -> Polygon2D {
    let h = size
    return Polygon2D(
        points: [
            // Bottom edge (left → right)
            Vector2D(x: -h, y: -h), Vector2D(x: -h/3, y: -h),
            Vector2D(x:  h/3, y: -h), Vector2D(x:  h, y: -h),
            // Right edge (bottom → top)
            Vector2D(x:  h, y: -h), Vector2D(x:  h, y: -h/3),
            Vector2D(x:  h, y:  h/3), Vector2D(x:  h, y:  h),
            // Top edge (right → left)
            Vector2D(x:  h, y:  h), Vector2D(x:  h/3, y:  h),
            Vector2D(x: -h/3, y:  h), Vector2D(x: -h, y:  h),
            // Left edge (top → bottom)
            Vector2D(x: -h, y:  h), Vector2D(x: -h, y:  h/3),
            Vector2D(x: -h, y: -h/3), Vector2D(x: -h, y: -h),
        ],
        type: .spline,
        visible: true
    )
}

/// Base params with PTW disabled — use as a starting point to override specific fields.
private func baseParams() -> SubdivisionParams {
    SubdivisionParams(
        polysTransform:         false,
        polysTranformWhole:     false,
        pTW_probability:        100,
        pTW_commonCentre:       false,
        pTW_randomTranslation:  false,
        pTW_randomScale:        false,
        pTW_randomRotation:     false,
        pTW_transform:          InsetTransform(translation: .zero,
                                               scale: Vector2D(x: 1, y: 1),
                                               rotation: 0),
        pTW_randomCentreDivisor: 0,     // 0 = disabled
        pTW_randomTranslationRange: .zero,
        pTW_randomScaleRange:   .one,
        pTW_randomRotationRange: .zero,
        polysTransformPoints:   false,
        pTP_probability:        100
    )
}

// MARK: - polysTransform master switch

final class PolygonTransformsMasterSwitchTests: XCTestCase {

    func testDisabledMasterReturnsPolygonsUnchanged() {
        var params = baseParams()
        params.polysTransform     = false
        params.polysTranformWhole = true
        // Even with whole-polygon enabled, the master switch overrides.
        params.pTW_transform = InsetTransform(
            translation: Vector2D(x: 5, y: 5),
            scale: Vector2D(x: 1, y: 1),
            rotation: 0
        )

        let poly    = makeSquare()
        var rng     = SeededRNG52(seed: 1)
        let result  = PolygonTransforms.apply([poly], params: params, rng: &rng)

        XCTAssertEqual(result[0].points, poly.points)
    }

    func testEnabledMasterWithNothingActiveReturnsPolygonsUnchanged() {
        var params = baseParams()
        params.polysTransform     = true
        params.polysTranformWhole = false
        params.polysTransformPoints = false

        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        XCTAssertEqual(result[0].points, poly.points)
    }

    func testInvisiblePolygonPassesThroughUntouched() {
        var params = baseParams()
        params.polysTransform     = true
        params.polysTranformWhole = true
        params.pTW_transform = InsetTransform(
            translation: Vector2D(x: 10, y: 0),
            scale: Vector2D(x: 1, y: 1),
            rotation: 0
        )

        var poly     = makeSquare()
        poly         = Polygon2D(points: poly.points, type: poly.type, visible: false)
        var rng      = SeededRNG52(seed: 1)
        let result   = PolygonTransforms.apply([poly], params: params, rng: &rng)

        // Invisible polygon must not be transformed.
        XCTAssertEqual(result[0].points, poly.points)
    }
}

// MARK: - Deterministic PTW transform

final class PTWDeterministicTransformTests: XCTestCase {

    func testIdentityTransformLeavesPolygonUnchanged() {
        var params = baseParams()
        params.polysTransform     = true
        params.polysTranformWhole = true
        // pTW_transform is already identity (scale 1,1; translation 0,0; rotation 0)

        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        for (a, b) in zip(poly.points, result[0].points) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-10)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-10)
        }
    }

    func testScaleTransformShrinksPolygon() {
        var params = baseParams()
        params.polysTransform     = true
        params.polysTranformWhole = true
        params.pTW_transform = InsetTransform(
            translation: .zero,
            scale: Vector2D(x: 0.5, y: 0.5),
            rotation: 0
        )

        // Square centred at origin — scaling by 0.5 around centroid (0,0)
        // should halve all coordinates.
        let poly   = makeSquare(size: 2.0)
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        for (orig, xformed) in zip(poly.points, result[0].points) {
            XCTAssertEqual(xformed.x, orig.x * 0.5, accuracy: 1e-10)
            XCTAssertEqual(xformed.y, orig.y * 0.5, accuracy: 1e-10)
        }
    }

    func testTranslationTransformMovesPolygon() {
        var params = baseParams()
        params.polysTransform     = true
        params.polysTranformWhole = true
        params.pTW_transform = InsetTransform(
            translation: Vector2D(x: 3, y: -2),
            scale: Vector2D(x: 1, y: 1),
            rotation: 0
        )

        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        for (orig, xformed) in zip(poly.points, result[0].points) {
            XCTAssertEqual(xformed.x, orig.x + 3, accuracy: 1e-10)
            XCTAssertEqual(xformed.y, orig.y - 2, accuracy: 1e-10)
        }
    }

    func testRotationBy90DegreesAroundOrigin() {
        var params = baseParams()
        params.polysTransform     = true
        params.polysTranformWhole = true
        params.pTW_transform = InsetTransform(
            translation: .zero,
            scale: Vector2D(x: 1, y: 1),
            rotation: Double.pi / 2   // 90°
        )

        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        // After 90° rotation around origin: (x,y) → (-y, x).
        // Centroid of the square is at origin so the transform pivots around (0,0).
        for (orig, xformed) in zip(poly.points, result[0].points) {
            XCTAssertEqual(xformed.x, -orig.y, accuracy: 1e-10)
            XCTAssertEqual(xformed.y,  orig.x, accuracy: 1e-10)
        }
    }
}

// MARK: - PTW probability gate

final class PTWProbabilityTests: XCTestCase {

    func testZeroProbabilityNeverTransforms() {
        var params = baseParams()
        params.polysTransform     = true
        params.polysTranformWhole = true
        params.pTW_probability    = 0     // never
        params.pTW_transform = InsetTransform(
            translation: Vector2D(x: 99, y: 99),
            scale: Vector2D(x: 1, y: 1),
            rotation: 0
        )

        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        XCTAssertEqual(result[0].points, poly.points)
    }

    func test100ProbabilityAlwaysTransforms() {
        var params = baseParams()
        params.polysTransform     = true
        params.polysTranformWhole = true
        params.pTW_probability    = 100   // always
        params.pTW_transform = InsetTransform(
            translation: Vector2D(x: 5, y: 0),
            scale: Vector2D(x: 1, y: 1),
            rotation: 0
        )

        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        XCTAssertNotEqual(result[0].points, poly.points, "translation must have moved the polygon")
    }
}

// MARK: - PTW random translation

final class PTWRandomTranslationTests: XCTestCase {

    func testRandomTranslationMovesPolygon() {
        var params = baseParams()
        params.polysTransform         = true
        params.polysTranformWhole     = true
        params.pTW_randomTranslation  = true
        params.pTW_randomTranslationRange = VectorRange(
            x: FloatRange(min: 10, max: 10),   // deterministic: always +10
            y: FloatRange(min: -5, max: -5)    // deterministic: always -5
        )

        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        for (orig, xformed) in zip(poly.points, result[0].points) {
            XCTAssertEqual(xformed.x, orig.x + 10, accuracy: 1e-10)
            XCTAssertEqual(xformed.y, orig.y - 5,  accuracy: 1e-10)
        }
    }

    func testRandomTranslationWithinRange() {
        var params = baseParams()
        params.polysTransform         = true
        params.polysTranformWhole     = true
        params.pTW_randomTranslation  = true
        params.pTW_randomTranslationRange = VectorRange(
            x: FloatRange(min: -20, max: 20),
            y: FloatRange(min: -20, max: 20)
        )

        let poly  = makeSquare()
        // Run 30 times with different seeds; verify the centroid shifts by at most 20.
        for seed: UInt64 in 0..<30 {
            var rng   = SeededRNG52(seed: seed)
            let out   = PolygonTransforms.apply([poly], params: params, rng: &rng)
            let shift = out[0].centroid
            XCTAssertLessThanOrEqual(abs(shift.x), 20 + 1e-9)
            XCTAssertLessThanOrEqual(abs(shift.y), 20 + 1e-9)
        }
    }
}

// MARK: - PTW random scale

final class PTWRandomScaleTests: XCTestCase {

    func testDeterministicScaleDoubles() {
        var params = baseParams()
        params.polysTransform     = true
        params.polysTranformWhole = true
        params.pTW_randomScale    = true
        // Force scale to exactly 2×2 (min == max).
        params.pTW_randomScaleRange = VectorRange(
            x: FloatRange(min: 2, max: 2),
            y: FloatRange(min: 2, max: 2)
        )

        // Square centred at origin — scaling by 2 around centroid (0,0) doubles all coords.
        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        for (orig, xformed) in zip(poly.points, result[0].points) {
            XCTAssertEqual(xformed.x, orig.x * 2, accuracy: 1e-10)
            XCTAssertEqual(xformed.y, orig.y * 2, accuracy: 1e-10)
        }
    }
}

// MARK: - PTW random rotation

final class PTWRandomRotationTests: XCTestCase {

    func testDeterministic90DegreeRandomRotation() {
        var params = baseParams()
        params.polysTransform       = true
        params.polysTranformWhole   = true
        params.pTW_randomRotation   = true
        // Force rotation to exactly π/2 (min == max).
        let halfPi = Double.pi / 2
        params.pTW_randomRotationRange = FloatRange(min: halfPi, max: halfPi)

        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        // Centroid is (0,0) → rotation pivot is (0,0): (x,y) → (-y, x).
        for (orig, xformed) in zip(poly.points, result[0].points) {
            XCTAssertEqual(xformed.x, -orig.y, accuracy: 1e-10)
            XCTAssertEqual(xformed.y,  orig.x, accuracy: 1e-10)
        }
    }
}

// MARK: - PTW common centre

final class PTWCommonCentreTests: XCTestCase {

    func testCommonCentreIsAverageOfVisibleCentroids() {
        // Two squares at known positions; confirm that with common-centre enabled
        // they scale around their collective midpoint rather than each polygon's
        // own centroid.
        var params = baseParams()
        params.polysTransform     = true
        params.polysTranformWhole = true
        params.pTW_commonCentre   = true
        // Scale 0.5 will move each polygon toward the common pivot.
        params.pTW_transform = InsetTransform(
            translation: .zero,
            scale: Vector2D(x: 0.5, y: 0.5),
            rotation: 0
        )

        // Square A centred at (-10, 0), Square B centred at (+10, 0).
        // Common centre = (0, 0).
        // After scale-0.5 around (0,0), both squares' points halve their distance to origin.
        let polyA = makeSquare(size: 1).translated(by: Vector2D(x: -10, y: 0))
        let polyB = makeSquare(size: 1).translated(by: Vector2D(x:  10, y: 0))

        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([polyA, polyB], params: params, rng: &rng)

        // All result points should be at half their original distance from the origin.
        for (orig, xformed) in zip(polyA.points + polyB.points,
                                   result[0].points + result[1].points) {
            XCTAssertEqual(xformed.x, orig.x * 0.5, accuracy: 1e-10)
            XCTAssertEqual(xformed.y, orig.y * 0.5, accuracy: 1e-10)
        }
    }

    func testPerPolygonCentreDiffersFromCommon() {
        // Verify that the two modes produce different output for off-centre polygons.
        var paramsCommon = baseParams()
        paramsCommon.polysTransform     = true
        paramsCommon.polysTranformWhole = true
        paramsCommon.pTW_commonCentre   = true
        paramsCommon.pTW_transform = InsetTransform(
            translation: .zero, scale: Vector2D(x: 0.5, y: 0.5), rotation: 0
        )

        var paramsOwn = paramsCommon
        paramsOwn.pTW_commonCentre = false

        let poly1 = makeSquare(size: 1).translated(by: Vector2D(x: 5, y: 0))
        let poly2 = makeSquare(size: 1).translated(by: Vector2D(x: -5, y: 0))
        let polygons = [poly1, poly2]

        var rng1 = SeededRNG52(seed: 1)
        var rng2 = SeededRNG52(seed: 1)
        let withCommon = PolygonTransforms.apply(polygons, params: paramsCommon, rng: &rng1)
        let withOwn    = PolygonTransforms.apply(polygons, params: paramsOwn,    rng: &rng2)

        // The outputs should differ because the pivots differ.
        XCTAssertNotEqual(withCommon[0].points[0].x, withOwn[0].points[0].x,
                          "common-centre and per-polygon-centre must produce different positions")
    }
}

// MARK: - PTP per-point transform

final class PTPPerPointTransformTests: XCTestCase {

    func testPerPointTransformMovesEachPoint() {
        var params = baseParams()
        params.polysTransform       = true
        params.polysTransformPoints = true
        // Force deterministic +2 on x, 0 on y.
        params.pTW_randomTranslationRange = VectorRange(
            x: FloatRange(min: 2, max: 2),
            y: FloatRange(min: 0, max: 0)
        )

        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        for (orig, xformed) in zip(poly.points, result[0].points) {
            XCTAssertEqual(xformed.x, orig.x + 2, accuracy: 1e-10)
            XCTAssertEqual(xformed.y, orig.y,     accuracy: 1e-10)
        }
    }

    func testZeroPTPProbabilityLeavesPointsUnchanged() {
        var params = baseParams()
        params.polysTransform       = true
        params.polysTransformPoints = true
        params.pTP_probability      = 0
        params.pTW_randomTranslationRange = VectorRange(
            x: FloatRange(min: 10, max: 10),
            y: FloatRange(min: 10, max: 10)
        )

        let poly   = makeSquare()
        var rng    = SeededRNG52(seed: 1)
        let result = PolygonTransforms.apply([poly], params: params, rng: &rng)

        XCTAssertEqual(result[0].points, poly.points)
    }
}

// MARK: - SubdivisionEngine integration

final class PTWSubdivisionEngineIntegrationTests: XCTestCase {

    func testSubdivisionWithPTWDisabledMatchesBaseline() {
        // Baseline: no PTW.
        let params = SubdivisionParams(subdivisionType: .quad,
                                        polysTransform: false)
        let poly   = makeSquare(size: 10)

        var rng1 = SeededRNG52(seed: 42)
        var rng2 = SeededRNG52(seed: 42)
        let base = SubdivisionEngine.subdivide(polygon: poly, params: params, rng: &rng1)
        let same = SubdivisionEngine.subdivide(polygon: poly, params: params, rng: &rng2)

        XCTAssertEqual(base.count, same.count)
        for (a, b) in zip(base, same) {
            XCTAssertEqual(a.points, b.points)
        }
    }

    func testSubdivisionWithPTWTranslatesChildren() {
        // Enable PTW with a deterministic +5 translation so children are moved.
        var params = SubdivisionParams(
            subdivisionType: .quad,
            polysTransform: true,
            polysTranformWhole: true,
            pTW_probability: 100,
            pTW_transform: InsetTransform(
                translation: Vector2D(x: 5, y: 0),
                scale: Vector2D(x: 1, y: 1),
                rotation: 0
            )
        )

        // Baseline without PTW.
        var baseline = params
        baseline.polysTransform = false

        let poly = makeSquare(size: 10)

        var rng1 = SeededRNG52(seed: 7)
        var rng2 = SeededRNG52(seed: 7)
        let withPTW    = SubdivisionEngine.subdivide(polygon: poly, params: params, rng: &rng1)
        let withoutPTW = SubdivisionEngine.subdivide(polygon: poly, params: baseline, rng: &rng2)

        XCTAssertEqual(withPTW.count, withoutPTW.count,
                       "PTW must not change child count")

        // Every child polygon should be shifted +5 on x.
        for (shifted, original) in zip(withPTW, withoutPTW) {
            for (sp, op) in zip(shifted.points, original.points) {
                XCTAssertEqual(sp.x, op.x + 5, accuracy: 1e-9)
                XCTAssertEqual(sp.y, op.y,      accuracy: 1e-9)
            }
        }
    }

    func testSubdivisionWithPTWDeterministicForSameSeed() {
        var params = SubdivisionParams(
            subdivisionType: .quad,
            polysTransform: true,
            polysTranformWhole: true,
            pTW_probability: 70,
            pTW_randomTranslation: true,
            pTW_randomTranslationRange: VectorRange(
                x: FloatRange(min: -5, max: 5),
                y: FloatRange(min: -5, max: 5)
            )
        )

        let poly = makeSquare(size: 10)

        var rng1 = SeededRNG52(seed: 99)
        var rng2 = SeededRNG52(seed: 99)
        let run1 = SubdivisionEngine.subdivide(polygon: poly, params: params, rng: &rng1)
        let run2 = SubdivisionEngine.subdivide(polygon: poly, params: params, rng: &rng2)

        XCTAssertEqual(run1.count, run2.count)
        for (a, b) in zip(run1, run2) {
            for (pa, pb) in zip(a.points, b.points) {
                XCTAssertEqual(pa.x, pb.x, accuracy: 1e-10)
                XCTAssertEqual(pa.y, pb.y, accuracy: 1e-10)
            }
        }
    }
}

// MARK: - Seeded RNG for deterministic tests

/// A minimal xorshift64 deterministic RNG — same one used in AnimationEngineTests.
struct SeededRNG52: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

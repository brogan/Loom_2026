import XCTest
@testable import LoomEngine

// MARK: - Fixtures

private func makeSquare() -> Polygon2D {
    let cp = Vector2D(x: 0.25, y: 0.75)
    let corners = [
        Vector2D(x: 0, y: 0),
        Vector2D(x: 1, y: 0),
        Vector2D(x: 1, y: 1),
        Vector2D(x: 0, y: 1),
    ]
    var pts = [Vector2D]()
    for i in 0..<4 {
        pts += BezierMath.connector(from: corners[i], to: corners[(i + 1) % 4], cpRatios: cp)
    }
    return Polygon2D(points: pts, type: .spline)
}

private func makeOpenLine() -> Polygon2D {
    let a0 = Vector2D(x: 0, y: 0)
    let a1 = Vector2D(x: 1, y: 0)
    let pts = BezierMath.connector(from: a0, to: a1, cpRatios: Vector2D(x: 1.0 / 3.0, y: 2.0 / 3.0))
    return Polygon2D(points: pts, type: .openSpline)
}

final class ConvolutionEngineTests: XCTestCase {

    // MARK: - No-op guards

    func testEmptyParamSetIsNoOp() {
        let square = makeSquare()
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [])
        XCTAssertEqual(result, [square])
    }

    func testDisabledPassIsNoOp() {
        let square = makeSquare()
        let params = ConvolutionParams(enabled: false, operationType: .torsion,
                                        twistAmount: .constant(90))
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result, [square])
    }

    func testTorsionZeroAngleIsNoOp() {
        let square = makeSquare()
        let params = ConvolutionParams(operationType: .torsion, twistAmount: .constant(0))
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result, [square])
    }

    func testShearZeroAmountIsNoOp() {
        let square = makeSquare()
        let params = ConvolutionParams(operationType: .shear, shearAmount: .constant(0))
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result, [square])
    }

    // MARK: - Torsion

    func testTorsionConstantFalloffAppliesUniformRotation() {
        let square = makeSquare()
        let angleDeg = 40.0
        let params = ConvolutionParams(operationType: .torsion,
                                        twistCentre: .centroid,
                                        twistAmount: .constant(angleDeg),
                                        twistFalloff: .constant)
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [params])[0]

        let centre = square.centroid
        let angleRad = angleDeg * .pi / 180.0
        let expected = square.points.map { $0.rotated(by: angleRad, around: centre) }
        for (a, b) in zip(result.points, expected) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
    }

    func testTorsionPointAtCentreStaysAtCentre() {
        // A point exactly at the twist centre has r=0, so every falloff mode
        // (including .linear, whose theta grows with r) produces zero rotation
        // for it specifically — rotating a zero-radius point never moves it,
        // regardless of angle.
        let centre = Vector2D(x: 0.5, y: 0.5)
        let square = Polygon2D(points: [centre, centre, centre, centre], type: .spline)
        let params = ConvolutionParams(operationType: .torsion,
                                        twistCentre: .custom,
                                        twistCentreCustomX: centre.x,
                                        twistCentreCustomY: centre.y,
                                        twistAmount: .constant(90),
                                        twistFalloff: .linear)
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [params])[0]
        for p in result.points {
            XCTAssertEqual(p.x, centre.x, accuracy: 1e-9)
            XCTAssertEqual(p.y, centre.y, accuracy: 1e-9)
        }
    }

    // MARK: - Shear

    func testShearHorizontalAxis() {
        // axis = 0° is the classic horizontal shear: x' = x + amount*y, y' = y.
        let square = Polygon2D(points: [
            Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 1),
        ], type: .spline)
        let params = ConvolutionParams(operationType: .shear,
                                        shearAxis: 0,
                                        shearAmount: .constant(0.5),
                                        shearOrigin: .custom,
                                        shearOriginCustomX: 0, shearOriginCustomY: 0)
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [params])[0]
        let last = result.points[3]
        XCTAssertEqual(last.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(last.y, 1.0, accuracy: 1e-9)
    }

    func testShearVerticalAxis() {
        // axis = 90° is a vertical shear: x' = x, y' = y - amount*x.
        let point = Vector2D(x: 1, y: 0)
        let square = Polygon2D(points: [point, point, point, point], type: .spline)
        let params = ConvolutionParams(operationType: .shear,
                                        shearAxis: 90,
                                        shearAmount: .constant(0.5),
                                        shearOrigin: .custom,
                                        shearOriginCustomX: 0, shearOriginCustomY: 0)
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [params])[0]
        let p = result.points[0]
        XCTAssertEqual(p.x, 1.0, accuracy: 1e-9)
        XCTAssertEqual(p.y, -0.5, accuracy: 1e-9)
    }

    // MARK: - Applies to both open curves and closed polygons

    func testAppliesIdenticallyToOpenCurves() {
        let line = makeOpenLine()
        let params = ConvolutionParams(operationType: .shear,
                                        shearAxis: 0,
                                        shearAmount: .constant(0.3),
                                        shearOrigin: .custom,
                                        shearOriginCustomX: 0, shearOriginCustomY: 0)
        let result = ConvolutionEngine.process(polygons: [line], paramSet: [params])[0]
        XCTAssertEqual(result.type, .openSpline)
        // Every point sheared by the same formula as the closed-polygon case.
        for (orig, sheared) in zip(line.points, result.points) {
            XCTAssertEqual(sheared.x, orig.x + 0.3 * orig.y, accuracy: 1e-9)
            XCTAssertEqual(sheared.y, orig.y, accuracy: 1e-9)
        }
    }

    // MARK: - Multi-polygon coherence (regression: a subdivided mesh is one shape)

    func testBendTreatsMultiplePolygonsAsOneCoherentShape() {
        // Two small "quads" sitting at very different absolute positions along
        // the bend axis, mimicking two cells of a subdivided mesh (e.g. two of
        // the ~1000 quads produced by five stacked Quad subdivision passes).
        // The bend's along-axis extent must be resolved once across BOTH
        // polygons together, not per polygon — otherwise every quad computes
        // its own near-zero-width local extent and collapses toward itself
        // regardless of where it actually sits. This is the exact bug reported
        // from production: a finely subdivided square collapsed into a narrow
        // vertical spire under Bend.
        let polyA = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0),
                                        Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0)], type: .spline)
        let polyB = Polygon2D(points: [Vector2D(x: 10, y: 0), Vector2D(x: 10, y: 0),
                                        Vector2D(x: 10, y: 0), Vector2D(x: 10, y: 0)], type: .spline)
        let curvature = 0.05
        let params = ConvolutionParams(operationType: .bend,
                                        bendAxis: 0,
                                        bendCurvature: .constant(curvature),
                                        bendCentre: .custom,
                                        bendCentreCustomX: 0, bendCentreCustomY: 0,
                                        bendOrigin: 0.5)
        let result = ConvolutionEngine.process(polygons: [polyA, polyB], paramSet: [params])

        // Global extent across BOTH polygons is 0...10, so sOrigin = 5 —
        // each polygon's own point is 5 units from that shared origin, not 0
        // (which is what a per-polygon-local extent would wrongly compute).
        let radius = 1.0 / curvature
        let thetaA = (0.0 - 5.0) * curvature
        let thetaB = (10.0 - 5.0) * curvature
        let expectedA = Vector2D(x: radius * sin(thetaA), y: radius - radius * cos(thetaA))
        let expectedB = Vector2D(x: radius * sin(thetaB), y: radius - radius * cos(thetaB))

        XCTAssertEqual(result[0].points[0].x, expectedA.x, accuracy: 1e-9)
        XCTAssertEqual(result[0].points[0].y, expectedA.y, accuracy: 1e-9)
        XCTAssertEqual(result[1].points[0].x, expectedB.x, accuracy: 1e-9)
        XCTAssertEqual(result[1].points[0].y, expectedB.y, accuracy: 1e-9)

        // The two polygons must land meaningfully apart, not collapsed onto
        // (or near) each other — the visible symptom of the per-polygon bug.
        XCTAssertGreaterThan(result[0].points[0].distance(to: result[1].points[0]), 1.0)
    }

    func testTorsionCentroidResolvedAcrossWholeMeshNotPerPolygon() {
        // Same class of bug for Torsion's Centroid mode: two far-apart
        // polygons must share ONE combined centroid, not each rotate around
        // its own individual (and here, degenerately self-cancelling) centroid.
        let polyA = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0),
                                        Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0)], type: .spline)
        let polyB = Polygon2D(points: [Vector2D(x: 10, y: 0), Vector2D(x: 10, y: 0),
                                        Vector2D(x: 10, y: 0), Vector2D(x: 10, y: 0)], type: .spline)
        let params = ConvolutionParams(operationType: .torsion,
                                        twistCentre: .centroid,
                                        twistAmount: .constant(90),
                                        twistFalloff: .constant)
        let result = ConvolutionEngine.process(polygons: [polyA, polyB], paramSet: [params])

        let combinedCentroid = Vector2D(x: 5, y: 0)
        let expectedA = Vector2D(x: 0, y: 0).rotated(by: .pi / 2, around: combinedCentroid)
        XCTAssertEqual(result[0].points[0].x, expectedA.x, accuracy: 1e-9)
        XCTAssertEqual(result[0].points[0].y, expectedA.y, accuracy: 1e-9)
    }

    // MARK: - Displacement Map

    func testDisplacementMapUnresolvedNameIsNoOp() {
        let square = makeSquare()
        let params = ConvolutionParams(operationType: .displacementMap,
                                        displacementMapName: "missing.png",
                                        displacementStrength: .constant(1.0))
        // No entry for "missing.png" in the displacementMaps dictionary.
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [params], displacementMaps: [:])
        XCTAssertEqual(result, [square])
    }

    func testDisplacementMapZeroStrengthIsNoOp() {
        let square = makeSquare()
        let map = DisplacementMapImage(width: 2, height: 1, grid: [0.0, 1.0])
        let params = ConvolutionParams(operationType: .displacementMap,
                                        displacementMapName: "map.png",
                                        displacementStrength: .constant(0))
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [params],
                                                displacementMaps: ["map.png": map])
        XCTAssertEqual(result, [square])
    }

    func testDisplacementMapAppliesSignedDisplacementPerpendicularToAxis() {
        // Point sits exactly at the resolved centre, axis = 0°, so u = 0
        // exactly (no scroll) -> samples grid[0] = 0.0 (black) -> signed
        // brightness -1.0 -> displacement = -strength along acrossDir (0,1).
        let point = Vector2D(x: 0, y: 0)
        let poly = Polygon2D(points: [point, point, point, point], type: .spline)
        let map = DisplacementMapImage(width: 2, height: 1, grid: [0.0, 1.0])
        let strength = 0.3
        let params = ConvolutionParams(operationType: .displacementMap,
                                        displacementMapName: "map.png",
                                        displacementStrength: .constant(strength),
                                        displacementAxis: 0,
                                        displacementScale: 1.0,
                                        displacementScrollRate: .constant(0),
                                        displacementCentre: .custom,
                                        displacementCentreCustomX: 0, displacementCentreCustomY: 0,
                                        displacementOffsetU: 0, displacementOffsetV: 0)
        let result = ConvolutionEngine.process(polygons: [poly], paramSet: [params],
                                                displacementMaps: ["map.png": map])[0]
        XCTAssertEqual(result.points[0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(result.points[0].y, -strength, accuracy: 1e-9)
    }

    func testDisplacementMapInvertFlipsDirection() {
        let point = Vector2D(x: 0, y: 0)
        let poly = Polygon2D(points: [point, point, point, point], type: .spline)
        let map = DisplacementMapImage(width: 2, height: 1, grid: [0.0, 1.0])
        let strength = 0.3
        let params = ConvolutionParams(operationType: .displacementMap,
                                        displacementMapName: "map.png",
                                        displacementStrength: .constant(strength),
                                        displacementInvert: true,
                                        displacementAxis: 0,
                                        displacementScale: 1.0,
                                        displacementScrollRate: .constant(0),
                                        displacementCentre: .custom,
                                        displacementCentreCustomX: 0, displacementCentreCustomY: 0,
                                        displacementOffsetU: 0, displacementOffsetV: 0)
        let result = ConvolutionEngine.process(polygons: [poly], paramSet: [params],
                                                displacementMaps: ["map.png": map])[0]
        // Inverted: sampled 0.0 becomes 1.0 -> signed +1.0 -> +strength.
        XCTAssertEqual(result.points[0].y, strength, accuracy: 1e-9)
    }

    func testDisplacementMapScrollOffsetShiftsSamplePosition() {
        // scrollRate 1.0 cycle/sec, 12 of 24 frames elapsed -> offset = 0.5
        // tile, landing exactly on grid[1] (white, brightness 1.0).
        let point = Vector2D(x: 0, y: 0)
        let poly = Polygon2D(points: [point, point, point, point], type: .spline)
        let map = DisplacementMapImage(width: 2, height: 1, grid: [0.0, 1.0])
        let strength = 0.3
        let params = ConvolutionParams(operationType: .displacementMap,
                                        displacementMapName: "map.png",
                                        displacementStrength: .constant(strength),
                                        displacementAxis: 0,
                                        displacementScale: 1.0,
                                        displacementScrollRate: .constant(1.0),
                                        displacementCentre: .custom,
                                        displacementCentreCustomX: 0, displacementCentreCustomY: 0,
                                        displacementOffsetU: 0, displacementOffsetV: 0)
        let result = ConvolutionEngine.process(polygons: [poly], paramSet: [params],
                                                elapsedFrames: 12, targetFPS: 24,
                                                displacementMaps: ["map.png": map])[0]
        XCTAssertEqual(result.points[0].y, strength, accuracy: 1e-9)
    }

    func testDisplacementMapCentroidResolvedAcrossWholeMesh() {
        // Same coherence guarantee as Torsion/Bend: the reference centre for
        // Centroid mode must be resolved once across the whole polygon array,
        // not per individual polygon.
        let polyA = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0),
                                        Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0)], type: .spline)
        let polyB = Polygon2D(points: [Vector2D(x: 10, y: 0), Vector2D(x: 10, y: 0),
                                        Vector2D(x: 10, y: 0), Vector2D(x: 10, y: 0)], type: .spline)
        let map = DisplacementMapImage(width: 4, height: 1, grid: [0.0, 0.3, 0.6, 1.0])
        let scale = 3.0
        let params = ConvolutionParams(operationType: .displacementMap,
                                        displacementMapName: "map.png",
                                        displacementStrength: .constant(1.0),
                                        displacementAxis: 0,
                                        displacementScale: scale,
                                        displacementCentre: .centroid)
        let result = ConvolutionEngine.process(polygons: [polyA, polyB], paramSet: [params],
                                                displacementMaps: ["map.png": map])

        // Combined centroid across BOTH polygons is (5, 0) — not each
        // polygon's own degenerate, self-cancelling single-point centroid.
        // Default displacementOffsetU/V is 0.5 (the map's own middle sits at
        // centre), so it must be added here to match the engine.
        let centre = Vector2D(x: 5, y: 0)
        let uA = (polyA.points[0].x - centre.x) / scale + 0.5
        let uB = (polyB.points[0].x - centre.x) / scale + 0.5
        let expectedYA = (map.sample(u: uA, v: 0) - 0.5) * 2.0
        let expectedYB = (map.sample(u: uB, v: 0) - 0.5) * 2.0

        XCTAssertEqual(result[0].points[0].y, expectedYA, accuracy: 1e-9)
        XCTAssertEqual(result[1].points[0].y, expectedYB, accuracy: 1e-9)
        XCTAssertNotEqual(expectedYA, expectedYB)
    }

    func testDisplacementMapDefaultOffsetCentresTheMapOnCentre() {
        // Default displacementOffsetU/V is 0.5 — a point exactly at Centre
        // (u_raw = 0, v_raw = 0) should sample the map's own middle, not its
        // raw top-left pixel (0,0). Regression for the reported bug: a
        // feature meant to sit at a shape's centre appeared shifted toward
        // one corner because the un-offset default sampled u=0,v=0 (image
        // top-left) at the anchor point.
        let point = Vector2D(x: 0, y: 0)
        let poly = Polygon2D(points: [point, point, point, point], type: .spline)
        // 2x2 grid, distinct corners, so top-left (0.0) and middle (~0.375,
        // the bilinear blend of all four quadrants at u=v=0.5) are clearly different.
        let map = DisplacementMapImage(width: 2, height: 2, grid: [0.0, 0.5, 0.5, 1.0])
        let params = ConvolutionParams(operationType: .displacementMap,
                                        displacementMapName: "map.png",
                                        displacementStrength: .constant(1.0),
                                        displacementAxis: 0,
                                        displacementScale: 1.0,
                                        displacementCentre: .custom,
                                        displacementCentreCustomX: 0, displacementCentreCustomY: 0)
        // displacementOffsetU/V left at their default (0.5).
        let result = ConvolutionEngine.process(polygons: [poly], paramSet: [params],
                                                displacementMaps: ["map.png": map])[0]
        let expectedBrightness = map.sample(u: 0.5, v: 0.5)
        let expectedY = (expectedBrightness - 0.5) * 2.0
        XCTAssertEqual(result.points[0].y, expectedY, accuracy: 1e-9)
        // And confirm it's genuinely NOT sampling the raw top-left pixel.
        XCTAssertNotEqual(expectedBrightness, map.grid[0], accuracy: 1e-6)
    }

    func testDisplacementMapOffsetIsConfigurableAndWraps() {
        // Explicit offset shifts which part of the map lands at Centre;
        // offsets outside 0...1 wrap to their fractional part, same as scroll.
        let point = Vector2D(x: 0, y: 0)
        let poly = Polygon2D(points: [point, point, point, point], type: .spline)
        let map = DisplacementMapImage(width: 2, height: 1, grid: [0.0, 1.0])
        let baseParams: (Double, Double) -> ConvolutionParams = { offU, offV in
            ConvolutionParams(operationType: .displacementMap,
                               displacementMapName: "map.png",
                               displacementStrength: .constant(1.0),
                               displacementAxis: 0,
                               displacementScale: 1.0,
                               displacementCentre: .custom,
                               displacementCentreCustomX: 0, displacementCentreCustomY: 0,
                               displacementOffsetU: offU, displacementOffsetV: offV)
        }
        let resultAt0_25 = ConvolutionEngine.process(polygons: [poly], paramSet: [baseParams(0.25, 0)],
                                                      displacementMaps: ["map.png": map])[0]
        let resultAt1_25 = ConvolutionEngine.process(polygons: [poly], paramSet: [baseParams(1.25, 0)],
                                                      displacementMaps: ["map.png": map])[0]
        // 1.25 wraps to the same fractional position as 0.25.
        XCTAssertEqual(resultAt0_25.points[0].y, resultAt1_25.points[0].y, accuracy: 1e-9)
    }

    func testDisplacementMapWrapToggleControlsOutOfBoundsSampling() {
        // A point whose computed u lands outside [0, 1) (here u = 1.5).
        let point = Vector2D(x: 1.5, y: 0)
        let poly = Polygon2D(points: [point, point, point, point], type: .spline)
        let map = DisplacementMapImage(width: 2, height: 1, grid: [0.0, 1.0])
        let strength = 0.4
        func params(wrap: Bool) -> ConvolutionParams {
            ConvolutionParams(operationType: .displacementMap,
                               displacementMapName: "map.png",
                               displacementStrength: .constant(strength),
                               displacementAxis: 0,
                               displacementScale: 1.0,
                               displacementCentre: .custom,
                               displacementCentreCustomX: 0, displacementCentreCustomY: 0,
                               displacementOffsetU: 0, displacementOffsetV: 0,
                               displacementWrap: wrap)
        }
        let wrapped = ConvolutionEngine.process(polygons: [poly], paramSet: [params(wrap: true)],
                                                 displacementMaps: ["map.png": map])[0]
        let unwrapped = ConvolutionEngine.process(polygons: [poly], paramSet: [params(wrap: false)],
                                                   displacementMaps: ["map.png": map])[0]

        // Wrap on: u=1.5 wraps to 0.5, sampling the bilinear blend there.
        let expectedWrappedBrightness = map.sample(u: 0.5, v: 0)
        let expectedWrappedY = (expectedWrappedBrightness - 0.5) * 2.0 * strength
        XCTAssertEqual(wrapped.points[0].y, expectedWrappedY, accuracy: 1e-9)

        // Wrap off: outside the single placed tile -> neutral -> zero displacement.
        XCTAssertEqual(unwrapped.points[0].y, 0, accuracy: 1e-9)
        XCTAssertEqual(unwrapped.points[0].x, 1.5, accuracy: 1e-9)
    }

    // MARK: - Non-warpable types pass through unchanged

    func testOvalTypeIsUnaffected() {
        let oval = Polygon2D(points: [Vector2D(x: 0.5, y: 0.5), Vector2D(x: 0.8, y: 0.7)], type: .oval)
        let params = ConvolutionParams(operationType: .torsion, twistAmount: .constant(90))
        let result = ConvolutionEngine.process(polygons: [oval], paramSet: [params])[0]
        XCTAssertEqual(result, oval)
    }

    func testPointTypeIsUnaffected() {
        let marker = Polygon2D(points: [Vector2D(x: 0.2, y: 0.3)], type: .point)
        let params = ConvolutionParams(operationType: .shear, shearAmount: .constant(0.5))
        let result = ConvolutionEngine.process(polygons: [marker], paramSet: [params])[0]
        XCTAssertEqual(result, marker)
    }

    // MARK: - Centre resolution

    func testBoundingBoxCentreDiffersFromCentroidForSkewedPoints() {
        // Three points bunched near (0,0) and one far outlier pulls the
        // average (centroid) away from the bounding box's true geometric centre.
        let poly = Polygon2D(points: [
            Vector2D(x: 0, y: 0),
            Vector2D(x: 0.1, y: 0.1),
            Vector2D(x: 0.2, y: 0),
            Vector2D(x: 10, y: 0),
        ], type: .spline)
        XCTAssertNotEqual(poly.centroid.x, (0.0 + 10.0) / 2.0, accuracy: 1e-9)
        // Sanity: bounding-box centre for these x-values is exactly 5.0.
        let xs = poly.points.map(\.x)
        let bboxCentreX = (xs.min()! + xs.max()!) / 2.0
        XCTAssertEqual(bboxCentreX, 5.0, accuracy: 1e-9)
    }

    // MARK: - Bend

    func testBendZeroCurvatureIsNoOp() {
        let square = makeSquare()
        let params = ConvolutionParams(operationType: .bend, bendCurvature: .constant(0))
        let result = ConvolutionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result, [square])
    }

    func testBendMatchesClosedFormArcFormula() {
        // axis = 0°, centre = (0,0), origin = 0 (sOrigin = sMin = 0): a point at
        // (s, t) should map to (radius - t) * sin(s*curvature) along the axis and
        // radius - (radius - t) * cos(s*curvature) across it.
        let a = Vector2D(x: 0, y: 0)   // s=0, t=0 — the pinned origin point
        let b = Vector2D(x: 1, y: 0)   // s=1, t=0
        let poly = Polygon2D(points: [a, a, a, b], type: .spline)
        let curvature = 1.0
        let params = ConvolutionParams(operationType: .bend,
                                        bendAxis: 0,
                                        bendCurvature: .constant(curvature),
                                        bendCentre: .custom,
                                        bendCentreCustomX: 0, bendCentreCustomY: 0,
                                        bendOrigin: 0.0)
        let result = ConvolutionEngine.process(polygons: [poly], paramSet: [params])[0]

        // The pinned point (s=0) must stay exactly at the origin.
        XCTAssertEqual(result.points[0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(result.points[0].y, 0, accuracy: 1e-9)

        // s=1, t=0 with radius = 1/curvature = 1: expected = (sin(1), 1 - cos(1)).
        let radius = 1.0 / curvature
        let theta = 1.0 * curvature
        let expected = Vector2D(x: radius * sin(theta), y: radius - radius * cos(theta))
        XCTAssertEqual(result.points[3].x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(result.points[3].y, expected.y, accuracy: 1e-9)
    }

    func testBendKeepsCrossSectionsRigid() {
        // Two points sharing the same "along" position but different "across"
        // offsets (a straight cross-section) must stay the same distance apart
        // after bending — a bend deformer rotates cross-sections rigidly rather
        // than shearing them.
        let s = 0.7
        let pointNearAxis = Vector2D(x: s, y: 0.0)
        let pointOffAxis  = Vector2D(x: s, y: 0.2)
        let poly = Polygon2D(points: [pointNearAxis, pointNearAxis, pointNearAxis, pointOffAxis], type: .spline)
        let params = ConvolutionParams(operationType: .bend,
                                        bendAxis: 0,
                                        bendCurvature: .constant(1.3),
                                        bendCentre: .custom,
                                        bendCentreCustomX: 0, bendCentreCustomY: 0,
                                        bendOrigin: 0.0)
        let result = ConvolutionEngine.process(polygons: [poly], paramSet: [params])[0]
        let distanceBefore = pointNearAxis.distance(to: pointOffAxis)
        let distanceAfter  = result.points[0].distance(to: result.points[3])
        XCTAssertEqual(distanceAfter, distanceBefore, accuracy: 1e-9)
    }

    func testBendOriginShiftsWhichPointIsPinned() {
        // With bendOrigin = 1.0, the point at the far end of the shape's own
        // extent (sMax) is the one that stays fixed, not the near end.
        let a = Vector2D(x: 0, y: 0)
        let b = Vector2D(x: 1, y: 0)
        let poly = Polygon2D(points: [a, a, a, b], type: .spline)
        let params = ConvolutionParams(operationType: .bend,
                                        bendAxis: 0,
                                        bendCurvature: .constant(1.0),
                                        bendCentre: .custom,
                                        bendCentreCustomX: 0, bendCentreCustomY: 0,
                                        bendOrigin: 1.0)
        let result = ConvolutionEngine.process(polygons: [poly], paramSet: [params])[0]
        // Now b (s=1=sMax) is pinned exactly at (0,0) relative to itself...
        // its own local (s-sOrigin, t) is (0,0), so it maps to the centre.
        XCTAssertEqual(result.points[3].x, 0, accuracy: 1e-9)
        XCTAssertEqual(result.points[3].y, 0, accuracy: 1e-9)
    }

    // MARK: - Stacking passes (order matters — shear then torsion vs torsion then shear)

    func testStackedPassesApplyInListOrder() {
        let square = makeSquare()
        let shearFirst = ConvolutionParams(operationType: .shear, shearAxis: 0, shearAmount: .constant(0.5),
                                            shearOrigin: .custom, shearOriginCustomX: 0, shearOriginCustomY: 0)
        let torsionSecond = ConvolutionParams(operationType: .torsion, twistCentre: .custom,
                                               twistCentreCustomX: 0, twistCentreCustomY: 0,
                                               twistAmount: .constant(30), twistFalloff: .constant)

        let shearThenTorsion = ConvolutionEngine.process(polygons: [square], paramSet: [shearFirst, torsionSecond])[0]
        let torsionThenShear = ConvolutionEngine.process(polygons: [square], paramSet: [torsionSecond, shearFirst])[0]

        // Shear and rotation don't commute — reversing pass order must produce a
        // different result (confirms pass-list order is respected, not silently
        // normalized to some fixed internal order).
        XCTAssertNotEqual(shearThenTorsion, torsionThenShear)
    }
}

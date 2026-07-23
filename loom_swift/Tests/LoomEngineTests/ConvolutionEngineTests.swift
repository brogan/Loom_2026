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

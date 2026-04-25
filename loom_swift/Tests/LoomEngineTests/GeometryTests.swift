import XCTest
@testable import LoomEngine

final class GeometryTests: XCTestCase {

    // MARK: - Tolerance helper

    let eps = 1e-10

    func assertEq(_ a: Double, _ b: Double, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: 1e-10, msg, file: file, line: line)
    }

    func assertVec2(_ a: Vector2D, _ b: Vector2D, accuracy: Double = 1e-10,
                    _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, "x: \(msg)", file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, "y: \(msg)", file: file, line: line)
    }

    func assertVec3(_ a: Vector3D, _ b: Vector3D, accuracy: Double = 1e-10,
                    _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, "x: \(msg)", file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, "y: \(msg)", file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, "z: \(msg)", file: file, line: line)
    }

    // MARK: - Vector2D: arithmetic

    func testVector2DAddition() {
        let a = Vector2D(x: 1, y: 2)
        let b = Vector2D(x: 3, y: 4)
        assertVec2(a + b, Vector2D(x: 4, y: 6))
    }

    func testVector2DSubtraction() {
        let a = Vector2D(x: 5, y: 3)
        let b = Vector2D(x: 2, y: 1)
        assertVec2(a - b, Vector2D(x: 3, y: 2))
    }

    func testVector2DScalarMultiply() {
        let v = Vector2D(x: 2, y: -3)
        assertVec2(v * 2.0, Vector2D(x: 4, y: -6))
    }

    func testVector2DNegate() {
        let v = Vector2D(x: 1, y: -2)
        assertVec2(-v, Vector2D(x: -1, y: 2))
    }

    func testVector2DLength() {
        let v = Vector2D(x: 3, y: 4)
        assertEq(v.length, 5.0)
    }

    func testVector2DDistance() {
        let a = Vector2D(x: 0, y: 0)
        let b = Vector2D(x: 3, y: 4)
        assertEq(a.distance(to: b), 5.0)
    }

    func testVector2DZero() {
        assertVec2(Vector2D.zero, Vector2D(x: 0, y: 0))
    }

    // MARK: - Vector2D: transforms

    func testVector2DTranslate() {
        let v = Vector2D(x: 1, y: 2)
        let result = v.translated(by: Vector2D(x: 10, y: -5))
        assertVec2(result, Vector2D(x: 11, y: -3))
    }

    func testVector2DScaleUniform() {
        let v = Vector2D(x: 3, y: -4)
        assertVec2(v.scaled(by: 2.0), Vector2D(x: 6, y: -8))
    }

    func testVector2DScalePerAxis() {
        let v = Vector2D(x: 3, y: 4)
        assertVec2(v.scaled(by: Vector2D(x: 2, y: 0.5)), Vector2D(x: 6, y: 2))
    }

    func testVector2DRotate90() {
        // Rotating (1,0) by 90° CCW → (0,1)
        let v = Vector2D(x: 1, y: 0)
        let result = v.rotated(by: .pi / 2)
        assertVec2(result, Vector2D(x: 0, y: 1), accuracy: 1e-10)
    }

    func testVector2DRotate180() {
        // Rotating (1,0) by 180° → (-1,0)
        let v = Vector2D(x: 1, y: 0)
        let result = v.rotated(by: .pi)
        assertVec2(result, Vector2D(x: -1, y: 0), accuracy: 1e-10)
    }

    func testVector2DRotateAroundCentre() {
        // Rotating (2,0) by 90° CCW around (1,0) → (1,1)
        let v = Vector2D(x: 2, y: 0)
        let centre = Vector2D(x: 1, y: 0)
        let result = v.rotated(by: .pi / 2, around: centre)
        assertVec2(result, Vector2D(x: 1, y: 1), accuracy: 1e-10)
    }

    func testVector2DRotateRoundTrip() {
        let v = Vector2D(x: 3, y: 7)
        let roundTrip = v.rotated(by: .pi / 3).rotated(by: -.pi / 3)
        assertVec2(roundTrip, v, accuracy: 1e-10)
    }

    // MARK: - Vector2D: lerp

    func testLerpAtZero() {
        let a = Vector2D(x: 0, y: 0)
        let b = Vector2D(x: 10, y: 20)
        assertVec2(Vector2D.lerp(a, b, t: 0), a)
    }

    func testLerpAtOne() {
        let a = Vector2D(x: 0, y: 0)
        let b = Vector2D(x: 10, y: 20)
        assertVec2(Vector2D.lerp(a, b, t: 1), b)
    }

    func testLerpAtHalf() {
        let a = Vector2D(x: 0, y: 0)
        let b = Vector2D(x: 10, y: 20)
        assertVec2(Vector2D.lerp(a, b, t: 0.5), Vector2D(x: 5, y: 10))
    }

    // MARK: - Vector2D: value semantics

    func testVector2DValueSemantics() {
        let a = Vector2D(x: 1, y: 2)
        var b = a
        b = b.translated(by: Vector2D(x: 100, y: 100))
        // a must be unchanged
        assertVec2(a, Vector2D(x: 1, y: 2))
    }

    // MARK: - Vector3D: arithmetic

    func testVector3DAddition() {
        let a = Vector3D(x: 1, y: 2, z: 3)
        let b = Vector3D(x: 4, y: 5, z: 6)
        assertVec3(a + b, Vector3D(x: 5, y: 7, z: 9))
    }

    func testVector3DSubtraction() {
        let a = Vector3D(x: 4, y: 5, z: 6)
        let b = Vector3D(x: 1, y: 2, z: 3)
        assertVec3(a - b, Vector3D(x: 3, y: 3, z: 3))
    }

    func testVector3DScalarMultiply() {
        let v = Vector3D(x: 1, y: -2, z: 3)
        assertVec3(v * 3.0, Vector3D(x: 3, y: -6, z: 9))
    }

    func testVector3DNegate() {
        let v = Vector3D(x: 1, y: -2, z: 3)
        assertVec3(-v, Vector3D(x: -1, y: 2, z: -3))
    }

    func testVector3DLength() {
        let v = Vector3D(x: 1, y: 2, z: 2)
        assertEq(v.length, 3.0)
    }

    func testVector3DDistance() {
        let a = Vector3D(x: 0, y: 0, z: 0)
        let b = Vector3D(x: 1, y: 2, z: 2)
        assertEq(a.distance(to: b), 3.0)
    }

    // MARK: - Vector3D: rotations

    func testVector3DRotateX90() {
        // Rotating (0,1,0) by 90° around X → (0,0,1)
        let v = Vector3D(x: 0, y: 1, z: 0)
        let result = v.rotatedX(by: .pi / 2)
        assertVec3(result, Vector3D(x: 0, y: 0, z: 1), accuracy: 1e-10)
    }

    func testVector3DRotateY90() {
        // Rotating (1,0,0) by 90° around Y → (0,0,-1)
        let v = Vector3D(x: 1, y: 0, z: 0)
        let result = v.rotatedY(by: .pi / 2)
        assertVec3(result, Vector3D(x: 0, y: 0, z: -1), accuracy: 1e-10)
    }

    func testVector3DRotateZ90() {
        // Rotating (1,0,0) by 90° around Z → (0,1,0)
        let v = Vector3D(x: 1, y: 0, z: 0)
        let result = v.rotatedZ(by: .pi / 2)
        assertVec3(result, Vector3D(x: 0, y: 1, z: 0), accuracy: 1e-10)
    }

    func testVector3DRotateRoundTrip() {
        let v = Vector3D(x: 1, y: 2, z: 3)
        let result = v.rotatedX(by: 1.1).rotatedX(by: -1.1)
        assertVec3(result, v, accuracy: 1e-10)
    }

    // MARK: - PolygonType

    func testPolygonTypeRawValues() {
        XCTAssertEqual(PolygonType.line.rawValue, 0)
        XCTAssertEqual(PolygonType.spline.rawValue, 1)
        XCTAssertEqual(PolygonType.openSpline.rawValue, 2)
        XCTAssertEqual(PolygonType.point.rawValue, 3)
        XCTAssertEqual(PolygonType.oval.rawValue, 4)
    }

    func testPolygonTypeIsBypassType() {
        XCTAssertFalse(PolygonType.line.isBypassType)
        XCTAssertFalse(PolygonType.spline.isBypassType)
        XCTAssertTrue(PolygonType.openSpline.isBypassType)
        XCTAssertTrue(PolygonType.point.isBypassType)
        XCTAssertTrue(PolygonType.oval.isBypassType)
    }

    func testPolygonTypeAllCases() {
        XCTAssertEqual(PolygonType.allCases.count, 5)
    }

    func testPolygonTypeCodable() throws {
        let original = PolygonType.spline
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PolygonType.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Polygon2D: construction

    func testPolygon2DPointCount() {
        let poly = Polygon2D(
            points: [Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0), Vector2D(x: 0, y: 1)],
            type: .line
        )
        XCTAssertEqual(poly.pointCount, 3)
    }

    func testPolygon2DDefaultsVisible() {
        let poly = Polygon2D(points: [.zero], type: .point)
        XCTAssertTrue(poly.visible)
    }

    func testPolygon2DDefaultsPressuresEmpty() {
        let poly = Polygon2D(points: [.zero], type: .point)
        XCTAssertTrue(poly.pressures.isEmpty)
    }

    func testPolygon2DIsBypassType() {
        let line = Polygon2D(points: [.zero], type: .line)
        let pt   = Polygon2D(points: [.zero], type: .point)
        XCTAssertFalse(line.isBypassType)
        XCTAssertTrue(pt.isBypassType)
    }

    // MARK: - Polygon2D: centroid

    func testPolygon2DCentroidSquare() {
        let poly = Polygon2D(
            points: [
                Vector2D(x: -1, y: -1),
                Vector2D(x:  1, y: -1),
                Vector2D(x:  1, y:  1),
                Vector2D(x: -1, y:  1)
            ],
            type: .line
        )
        assertVec2(poly.centroid, Vector2D(x: 0, y: 0))
    }

    func testPolygon2DCentroidSinglePoint() {
        let poly = Polygon2D(points: [Vector2D(x: 3, y: 7)], type: .point)
        assertVec2(poly.centroid, Vector2D(x: 3, y: 7))
    }

    func testPolygon2DCentroidEmpty() {
        let poly = Polygon2D(points: [], type: .line)
        assertVec2(poly.centroid, Vector2D.zero)
    }

    // MARK: - Polygon2D: transforms

    func testPolygon2DTranslate() {
        let poly = Polygon2D(
            points: [Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0)],
            type: .line
        )
        let moved = poly.translated(by: Vector2D(x: 5, y: -3))
        assertVec2(moved.points[0], Vector2D(x: 5, y: -3))
        assertVec2(moved.points[1], Vector2D(x: 6, y: -3))
    }

    func testPolygon2DTranslatePreservesType() {
        let poly = Polygon2D(points: [.zero], type: .spline)
        XCTAssertEqual(poly.translated(by: .zero).type, .spline)
    }

    func testPolygon2DScaleUniform() {
        let poly = Polygon2D(
            points: [Vector2D(x: 2, y: 4)],
            type: .line
        )
        let scaled = poly.scaled(by: 3.0)
        assertVec2(scaled.points[0], Vector2D(x: 6, y: 12))
    }

    func testPolygon2DScaleAroundCentre() {
        // Square centred at origin, scale by 2 around (1,0)
        let poly = Polygon2D(
            points: [Vector2D(x: 1, y: 0), Vector2D(x: 3, y: 0)],
            type: .line
        )
        let scaled = poly.scaled(by: 2.0, around: Vector2D(x: 1, y: 0))
        assertVec2(scaled.points[0], Vector2D(x: 1, y: 0))
        assertVec2(scaled.points[1], Vector2D(x: 5, y: 0))
    }

    func testPolygon2DRotate90() {
        let poly = Polygon2D(
            points: [Vector2D(x: 1, y: 0)],
            type: .line
        )
        let rotated = poly.rotated(by: .pi / 2)
        assertVec2(rotated.points[0], Vector2D(x: 0, y: 1), accuracy: 1e-10)
    }

    func testPolygon2DRotatePreservesPressures() {
        let poly = Polygon2D(
            points: [Vector2D(x: 1, y: 0)],
            type: .spline,
            pressures: [0.5, 0.8]
        )
        let rotated = poly.rotated(by: .pi)
        XCTAssertEqual(rotated.pressures, [0.5, 0.8])
    }

    func testPolygon2DWithVisibility() {
        let poly = Polygon2D(points: [.zero], type: .line, visible: true)
        let hidden = poly.withVisibility(false)
        XCTAssertFalse(hidden.visible)
        XCTAssertTrue(poly.visible) // original unchanged
    }

    // MARK: - Polygon2D: value semantics

    func testPolygon2DValueSemantics() {
        let original = Polygon2D(
            points: [Vector2D(x: 1, y: 2)],
            type: .line
        )
        let moved = original.translated(by: Vector2D(x: 100, y: 100))
        // Original must be unchanged
        assertVec2(original.points[0], Vector2D(x: 1, y: 2))
        assertVec2(moved.points[0], Vector2D(x: 101, y: 102))
    }

    // MARK: - Polygon2D: Codable

    func testPolygon2DCodableRoundTrip() throws {
        let poly = Polygon2D(
            points: [Vector2D(x: 1.5, y: -2.5), Vector2D(x: 3.0, y: 4.0)],
            type: .spline,
            pressures: [0.75],
            visible: false
        )
        let data = try JSONEncoder().encode(poly)
        let decoded = try JSONDecoder().decode(Polygon2D.self, from: data)
        XCTAssertEqual(decoded, poly)
    }

    // MARK: - Polygon3D: transforms

    func testPolygon3DTranslate() {
        let poly = Polygon3D(
            points: [Vector3D(x: 1, y: 2, z: 3)],
            type: .line
        )
        let moved = poly.translated(by: Vector3D(x: 10, y: 20, z: 30))
        assertVec3(moved.points[0], Vector3D(x: 11, y: 22, z: 33))
    }

    func testPolygon3DRotateZPreservesType() {
        let poly = Polygon3D(points: [.zero], type: .spline)
        XCTAssertEqual(poly.rotatedZ(by: 1.0).type, .spline)
    }

    func testPolygon3DValueSemantics() {
        let original = Polygon3D(
            points: [Vector3D(x: 1, y: 2, z: 3)],
            type: .line
        )
        let scaled = original.scaled(by: 100.0)
        assertVec3(original.points[0], Vector3D(x: 1, y: 2, z: 3))
        assertVec3(scaled.points[0], Vector3D(x: 100, y: 200, z: 300))
    }

    // MARK: - ViewTransform: worldToScreen

    func testWorldToScreenOriginMapsToCanvasCentre() {
        let vt = ViewTransform(canvasSize: CGSize(width: 200, height: 100))
        let p = vt.worldToScreen(.zero)
        XCTAssertEqual(p.x, 100, accuracy: eps)
        XCTAssertEqual(p.y, 50,  accuracy: eps)
    }

    func testWorldToScreenYFlip() {
        // World Y-up: positive Y should map to smaller screen Y (Y-down).
        let vt = ViewTransform(canvasSize: CGSize(width: 200, height: 200))
        let above = vt.worldToScreen(Vector2D(x: 0, y: 10))
        let below = vt.worldToScreen(Vector2D(x: 0, y: -10))
        XCTAssertLessThan(above.y, below.y, "Positive world Y should map to smaller screen Y")
    }

    func testWorldToScreenKnownPoint() {
        let vt = ViewTransform(canvasSize: CGSize(width: 200, height: 100))
        // World (10, 20) → screen (100+10, 50-20) = (110, 30)
        let p = vt.worldToScreen(Vector2D(x: 10, y: 20))
        XCTAssertEqual(p.x, 110, accuracy: eps)
        XCTAssertEqual(p.y, 30,  accuracy: eps)
    }

    func testWorldToScreenWithOffset() {
        // Camera panned right by 5, up by 10
        let vt = ViewTransform(
            canvasSize: CGSize(width: 200, height: 100),
            offset: Vector2D(x: 5, y: 10)
        )
        // World origin → screen (100+0+5, 50-0+10) = (105, 60)
        let p = vt.worldToScreen(.zero)
        XCTAssertEqual(p.x, 105, accuracy: eps)
        XCTAssertEqual(p.y, 60,  accuracy: eps)
    }

    // MARK: - ViewTransform: screenToWorld (inverse)

    func testScreenToWorldCentreIsOrigin() {
        let vt = ViewTransform(canvasSize: CGSize(width: 200, height: 100))
        let w = vt.screenToWorld(CGPoint(x: 100, y: 50))
        XCTAssertEqual(w.x, 0, accuracy: eps)
        XCTAssertEqual(w.y, 0, accuracy: eps)
    }

    func testWorldToScreenInverse() {
        let vt = ViewTransform(
            canvasSize: CGSize(width: 1080, height: 1080),
            offset: Vector2D(x: 13, y: -7)
        )
        let world = Vector2D(x: 42.5, y: -17.3)
        let roundTrip = vt.screenToWorld(vt.worldToScreen(world))
        XCTAssertEqual(roundTrip.x, world.x, accuracy: eps)
        XCTAssertEqual(roundTrip.y, world.y, accuracy: eps)
    }

    func testScreenToWorldInverse() {
        let vt = ViewTransform(canvasSize: CGSize(width: 400, height: 300))
        let screen = CGPoint(x: 123, y: 87)
        let back = vt.worldToScreen(vt.screenToWorld(screen))
        XCTAssertEqual(back.x, screen.x, accuracy: eps)
        XCTAssertEqual(back.y, screen.y, accuracy: eps)
    }

    // MARK: - ViewTransform: screenCentre

    func testScreenCentre() {
        let vt = ViewTransform(canvasSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(vt.screenCentre.x, 200, accuracy: eps)
        XCTAssertEqual(vt.screenCentre.y, 150, accuracy: eps)
    }

    // MARK: - ViewTransform: Codable

    func testViewTransformCodableRoundTrip() throws {
        let vt = ViewTransform(
            canvasSize: CGSize(width: 1080, height: 1080),
            offset: Vector2D(x: 5, y: -10)
        )
        let data = try JSONEncoder().encode(vt)
        let decoded = try JSONDecoder().decode(ViewTransform.self, from: data)
        XCTAssertEqual(decoded, vt)
    }
}

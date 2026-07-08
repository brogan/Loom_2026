import XCTest
@testable import LoomEngine

// MARK: - Fixture

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

/// Minimal coverage for `ExtensionEngine` — no dedicated test file existed for this
/// mode before the directional-selector work (Specs/GeometricLifecycle.md §14), so
/// this focuses on the `outwardNormal` helper (factored out of three previously-
/// duplicated inline computations as part of that work) and the new directional
/// filter, rather than attempting full coverage of branch/extrude in one pass.
final class ExtensionEngineTests: XCTestCase {

    // MARK: - outwardNormal

    func testOutwardNormalsAreUnitLength() {
        let square = makeSquare()
        for i in 0..<4 {
            let n = ExtensionEngine.outwardNormal(of: square, segIdx: i)
            XCTAssertEqual(n.length, 1.0, accuracy: 1e-9)
        }
    }

    func testOutwardNormalsAreNinetyDegreesApartOnASquare() {
        let square = makeSquare()
        let normals = (0..<4).map { ExtensionEngine.outwardNormal(of: square, segIdx: $0) }
        for i in 0..<4 {
            let a = normals[i].angle
            let b = normals[(i + 1) % 4].angle
            var diff = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
            if diff > .pi  { diff -= 2 * .pi }
            if diff < -.pi { diff += 2 * .pi }
            XCTAssertEqual(abs(diff), .pi / 2, accuracy: 1e-6)
        }
    }

    func testOutwardNormalDegenerateEdgeReturnsZero() {
        let degenerate = Polygon2D(points: [
            Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0), Vector2D(x: 0, y: 0),
        ], type: .spline)
        XCTAssertEqual(ExtensionEngine.outwardNormal(of: degenerate, segIdx: 0), .zero)
    }

    func testOutwardNormalOutOfRangeIndexReturnsZero() {
        let square = makeSquare()
        XCTAssertEqual(ExtensionEngine.outwardNormal(of: square, segIdx: 99), .zero)
    }

    // MARK: - Directional selector integration (Specs/GeometricLifecycle.md §14)

    func testDirectionalSelectorRestrictsExtrudeToMatchingEdgeOnly() {
        let square = makeSquare()
        let targetNormal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)

        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        params.extrusionTarget = .allEdges
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: targetNormal.angle, tolerance: 0.2)

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        // Original square + exactly one extruded quad — its neighbors are 90°/180°
        // away, well outside a ±0.2 rad (~11°) tolerance.
        XCTAssertEqual(result.count, 2)
    }

    func testDirectionalSelectorExcludesAllEdgesWhenNoneMatch() {
        let square = makeSquare()
        let seg0Normal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)
        // Exactly between two adjacent segments' normals (90° apart on a square).
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg0Normal.angle + .pi / 4, tolerance: 0.1)

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result.count, 1, "no polygon should be added when no edge matches the directional filter")
    }

    func testDirectionalSelectorComposesWithLongestEdgeTarget() {
        // A rectangle (not a square) has an unambiguous longest edge, so this
        // exercises .longestEdge and the directional selector filtering it further.
        let cp = Vector2D(x: 0.25, y: 0.75)
        let corners = [
            Vector2D(x: 0, y: 0), Vector2D(x: 2, y: 0),
            Vector2D(x: 2, y: 1), Vector2D(x: 0, y: 1),
        ]
        var pts = [Vector2D]()
        for i in 0..<4 { pts += BezierMath.connector(from: corners[i], to: corners[(i + 1) % 4], cpRatios: cp) }
        let rect = Polygon2D(points: pts, type: .spline)

        // Segment 0 (bottom, length 2) is the longest edge.
        let seg0Normal = ExtensionEngine.outwardNormal(of: rect, segIdx: 0)

        var matching = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        matching.extrusionTarget = .longestEdge
        matching.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg0Normal.angle, tolerance: 0.1)
        XCTAssertEqual(ExtensionEngine.process(polygons: [rect], paramSet: [matching]).count, 2)

        var nonMatching = matching
        nonMatching.directionalSelector.targetAngle = seg0Normal.angle + .pi / 2
        XCTAssertEqual(ExtensionEngine.process(polygons: [rect], paramSet: [nonMatching]).count, 1,
                       "the longest edge doesn't face the required direction, so it should be excluded")
    }

    func testDirectionalSelectorDisabledMatchesAllEdgesBehavior() {
        let square = makeSquare()
        var params = ExtensionParams(operationType: .extrude, extrusionDistance: .constant(0.1))
        params.extrusionTarget = .allEdges
        // Disabled (default) — must not filter anything, regardless of targetAngle.
        params.directionalSelector = DirectionalSelector(enabled: false, targetAngle: 0, tolerance: 0.001)

        let result = ExtensionEngine.process(polygons: [square], paramSet: [params])
        XCTAssertEqual(result.count, 1 + 4, "all 4 edges should extrude when the selector is disabled")
    }
}

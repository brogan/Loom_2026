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

    // MARK: - extrudeEdge asymmetric distance / direction override (2026-07-10)

    func testExtrudeEdgeDefaultsToSymmetricDistance() {
        let square = makeSquare()
        guard let quad = ExtensionEngine.extrudeEdge(square, segIdx: 0, distance: 0.2) else {
            return XCTFail("expected a quad")
        }
        // Seg 0 (inner) = a0,cp1,cp2,a1; Seg 2 (outer) = oa1,ocp1,ocp2,oa0 — see
        // ExtensionEngine.extrudeSegment's layout comment.
        let a0 = quad.points[0], a1 = quad.points[3]
        let oa1 = quad.points[8], oa0 = quad.points[11]
        XCTAssertEqual(a0.distance(to: oa0), a1.distance(to: oa1), accuracy: 1e-9,
                       "with no override, both corners extrude by the same distance")
    }

    func testExtrudeEdgeDistanceA0A1OverrideProducesAsymmetricCorners() {
        let square = makeSquare()
        guard let quad = ExtensionEngine.extrudeEdge(square, segIdx: 0, distance: 0.2,
                                                      distanceA0: 0.1, distanceA1: 0.3) else {
            return XCTFail("expected a quad")
        }
        let a0 = quad.points[0], a1 = quad.points[3]
        let oa1 = quad.points[8], oa0 = quad.points[11]
        XCTAssertEqual(a0.distance(to: oa0), 0.1, accuracy: 1e-9)
        XCTAssertEqual(a1.distance(to: oa1), 0.3, accuracy: 1e-9)
    }

    func testExtrudeEdgeDirectionOverrideTiltsAwayFromNormal() {
        let square = makeSquare()
        let normal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)
        let tilted = normal.rotated(by: 30.0 * .pi / 180.0)

        guard let straight = ExtensionEngine.extrudeEdge(square, segIdx: 0, distance: 0.2),
              let angled   = ExtensionEngine.extrudeEdge(square, segIdx: 0, distance: 0.2, direction: tilted)
        else { return XCTFail("expected quads") }

        // Inner edge (unchanged base edge) is identical either way; only the outer
        // corners move when direction is overridden.
        XCTAssertEqual(straight.points[0], angled.points[0])
        XCTAssertEqual(straight.points[3], angled.points[3])
        XCTAssertNotEqual(straight.points[11], angled.points[11], "oa0 should move when direction is tilted")
        XCTAssertNotEqual(straight.points[8],  angled.points[8],  "oa1 should move when direction is tilted")

        // Distance from the base edge is preserved — only the direction changed.
        let a0 = angled.points[0], a1 = angled.points[3]
        let oa1 = angled.points[8], oa0 = angled.points[11]
        XCTAssertEqual(a0.distance(to: oa0), 0.2, accuracy: 1e-9)
        XCTAssertEqual(a1.distance(to: oa1), 0.2, accuracy: 1e-9)
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

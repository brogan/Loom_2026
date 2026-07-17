import XCTest
import Foundation
@testable import LoomEngine

final class EditableGeometryTests: XCTestCase {

    private func assertVec(_ actual: Vector2D, _ expected: Vector2D, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-10, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-10, file: file, line: line)
    }

    private func sampleSpline() -> Polygon2D {
        Polygon2D(
            points: [
                Vector2D(x: 0, y: 0),
                Vector2D(x: 0.2, y: 0),
                Vector2D(x: 0.8, y: 0),
                Vector2D(x: 1, y: 0),

                Vector2D(x: 1, y: 0),
                Vector2D(x: 1, y: 0.2),
                Vector2D(x: 0, y: 0.8),
                Vector2D(x: 0, y: 0)
            ],
            type: .spline,
            pressures: [0.25, 0.75],
            visible: true
        )
    }

    func testEditableClosedPolygonImportsClosedSplineWithSharedAnchors() throws {
        let editable = try EditableClosedPolygon(name: "Loop", polygon: sampleSpline())

        XCTAssertEqual(editable.segments.count, 2)
        XCTAssertEqual(editable.points.count, 6)
        XCTAssertEqual(editable.anchorIDs.count, 2)
        XCTAssertEqual(editable.segments[0].endAnchorID, editable.segments[1].startAnchorID)
        XCTAssertEqual(editable.segments[1].endAnchorID, editable.segments[0].startAnchorID)
        XCTAssertEqual(editable.pressures, [0.25, 0.75])
    }

    func testEditableClosedPolygonExportsRuntimeSplineEncoding() throws {
        let editable = try EditableClosedPolygon(name: "Loop", polygon: sampleSpline())

        let runtime = try editable.toPolygon2D()

        XCTAssertEqual(runtime.type, .spline)
        XCTAssertEqual(runtime.points.count, 8)
        XCTAssertEqual(runtime.pressures, [0.25, 0.75])
        assertVec(runtime.points[0], Vector2D(x: 0, y: 0))
        assertVec(runtime.points[3], Vector2D(x: 1, y: 0))
        assertVec(runtime.points[4], Vector2D(x: 1, y: 0))
        assertVec(runtime.points[7], Vector2D(x: 0, y: 0))
    }

    func testEditableRegularPolygonFactoryCreatesClosedSpline() throws {
        let editable = try EditableClosedPolygon(
            name: "Pentagon",
            regularPolygonSides: 5,
            centre: .zero,
            radius: 0.25
        )

        let runtime = try editable.toPolygon2D()

        XCTAssertEqual(editable.anchorIDs.count, 5)
        XCTAssertEqual(editable.segments.count, 5)
        XCTAssertEqual(runtime.type, .spline)
        XCTAssertEqual(runtime.points.count, 20)
        assertVec(runtime.points[0], Vector2D(x: 0, y: 0.25))
        XCTAssertEqual(
            editable.parametricSource,
            .regularPolygon(
                EditableRegularPolygonParameters(
                    sides: 5,
                    centre: .zero,
                    radius: 0.25,
                    innerRadius: 1.0,
                    scaleX: 1.0,
                    scaleY: 1.0,
                    rotationRadians: .pi / 2.0
                )
            )
        )
    }

    func testEditableRegularPolygonFactoryCreatesStarWhenInnerRadiusIsReduced() throws {
        let editable = try EditableClosedPolygon(
            name: "Star",
            regularPolygonSides: 5,
            centre: .zero,
            radius: 0.4,
            innerRadius: 0.5,
            scaleX: 2.0,
            scaleY: 1.0
        )

        let runtime = try editable.toPolygon2D()

        XCTAssertEqual(editable.anchorIDs.count, 10)
        XCTAssertEqual(editable.segments.count, 10)
        XCTAssertEqual(runtime.points.count, 40)
        assertVec(runtime.points[0], Vector2D(x: 0, y: 0.4))
        XCTAssertLessThan(runtime.points[3].distance(to: .zero), runtime.points[7].distance(to: .zero))
    }

    func testEditableRegularPolygonParametricSourceRoundTripsThroughJSON() throws {
        let editable = try EditableClosedPolygon(
            name: "Hexagon",
            regularPolygonSides: 6,
            centre: Vector2D(x: 0.1, y: -0.2),
            radius: 0.35,
            innerRadius: 0.45,
            scaleX: 1.2,
            scaleY: 0.8,
            rotationRadians: 0.25
        )
        let layer = EditableGeometryLayer(name: "Regular", polygons: [editable])
        let document = EditableGeometryDocument(name: "Parametric", layers: [layer], activeLayerID: layer.id)

        let decoded = try EditableGeometryJSONLoader.decode(
            from: EditableGeometryJSONLoader.encode(document)
        )

        XCTAssertEqual(decoded, document)
    }

    func testEditableOvalFactoryCreatesFourSegmentClosedSpline() throws {
        let editable = EditableClosedPolygon(
            name: "Oval",
            ovalCentre: .zero,
            radiusX: 0.3,
            radiusY: 0.2
        )

        let runtime = try editable.toPolygon2D()

        XCTAssertEqual(editable.anchorIDs.count, 4)
        XCTAssertEqual(editable.segments.count, 4)
        XCTAssertEqual(runtime.type, .spline)
        XCTAssertEqual(runtime.points.count, 16)
        // Note: the factory's "top"/"bottom" local variable names are misleading —
        // "top" is actually placed at y = centre.y - radiusY (below centre in this
        // Y-UP convention) and "bottom" at + radiusY (above). Purely a naming quirk
        // with no visual effect (an oval is symmetric regardless of which boundary
        // point is index 0); not fixed here since it's out of scope and risk-free
        // to leave. These expected values match what the factory actually emits.
        assertVec(runtime.points[0], Vector2D(x: 0, y: -0.2))
        assertVec(runtime.points[3], Vector2D(x: 0.3, y: 0))
        assertVec(runtime.points[15], Vector2D(x: 0, y: -0.2))
    }

    func testMovingSharedAnchorUpdatesEverySegmentReference() throws {
        var editable = try EditableClosedPolygon(name: "Loop", polygon: sampleSpline())
        let sharedAnchorID = editable.segments[0].endAnchorID

        editable.setPointPosition(id: sharedAnchorID, to: Vector2D(x: 2, y: 3))
        let runtime = try editable.toPolygon2D()

        assertVec(runtime.points[3], Vector2D(x: 2, y: 3))
        assertVec(runtime.points[4], Vector2D(x: 2, y: 3))
    }

    func testMovingAnchorMovesAttachedControlsBySameDelta() throws {
        let anchors = [
            Vector2D(x: -0.3, y: -0.3),
            Vector2D(x: 0.3, y: -0.3),
            Vector2D(x: 0.3, y: 0.3),
            Vector2D(x: -0.3, y: 0.3)
        ]
        var editable = try EditableClosedPolygon(name: "Box", anchors: anchors)
        let movedAnchorID = editable.segments[0].endAnchorID

        editable.moveAnchorWithAttachedControls(id: movedAnchorID, to: Vector2D(x: 0.0, y: 0.0))
        let runtime = try editable.toPolygon2D()

        assertVec(runtime.points[1], Vector2D(x: -0.1, y: -0.3))
        assertVec(runtime.points[2], Vector2D(x: -0.2, y: 0.0))
        assertVec(runtime.points[3], Vector2D(x: 0.0, y: 0.0))
        assertVec(runtime.points[4], Vector2D(x: 0.0, y: 0.0))
        assertVec(runtime.points[5], Vector2D(x: 0.0, y: 0.2))
        assertVec(runtime.points[6], Vector2D(x: 0.3, y: 0.1))
    }

    func testMovingControlPointLeavesAnchorsUntouched() throws {
        var editable = try EditableClosedPolygon(name: "Loop", polygon: sampleSpline())
        let controlID = editable.segments[0].controlOutID

        editable.setPointPosition(id: controlID, to: Vector2D(x: 0.4, y: 0.5))
        let runtime = try editable.toPolygon2D()

        assertVec(runtime.points[0], Vector2D(x: 0, y: 0))
        assertVec(runtime.points[1], Vector2D(x: 0.4, y: 0.5))
        assertVec(runtime.points[3], Vector2D(x: 1, y: 0))
    }

    func testTranslatingSegmentMovesEdgeAnchorsAndAttachedControls() throws {
        var editable = try EditableClosedPolygon(name: "Box", anchors: [
            Vector2D(x: -0.3, y: -0.3),
            Vector2D(x: 0.3, y: -0.3),
            Vector2D(x: 0.3, y: 0.3),
            Vector2D(x: -0.3, y: 0.3)
        ])

        editable.translateSegment(id: editable.segments[0].id, by: Vector2D(x: 0.1, y: 0.2))
        let runtime = try editable.toPolygon2D()

        assertVec(runtime.points[0], Vector2D(x: -0.2, y: -0.1))
        assertVec(runtime.points[1], Vector2D(x: 0.0, y: -0.1))
        assertVec(runtime.points[2], Vector2D(x: 0.2, y: -0.1))
        assertVec(runtime.points[3], Vector2D(x: 0.4, y: -0.1))
        assertVec(runtime.points[5], Vector2D(x: 0.4, y: 0.1))
        assertVec(runtime.points[14], Vector2D(x: -0.2, y: 0.1))
    }

    func testSegmentsTouchingSelectedSegmentIncludesAdjacentEdges() throws {
        let editable = try EditableClosedPolygon(name: "Box", anchors: [
            Vector2D(x: -0.3, y: -0.3),
            Vector2D(x: 0.3, y: -0.3),
            Vector2D(x: 0.3, y: 0.3),
            Vector2D(x: -0.3, y: 0.3)
        ])

        let affected = editable.segmentIDs(touchingSegmentIDs: [editable.segments[0].id])

        XCTAssertEqual(affected.count, 3)
        XCTAssertTrue(affected.contains(editable.segments[0].id))
        XCTAssertTrue(affected.contains(editable.segments[1].id))
        XCTAssertTrue(affected.contains(editable.segments[3].id))
        XCTAssertFalse(affected.contains(editable.segments[2].id))
    }

    func testResetControlsRestoresInferredSegmentPositions() throws {
        var editable = try EditableClosedPolygon(name: "Loop", anchors: [
            Vector2D(x: 0, y: 0),
            Vector2D(x: 0.6, y: 0),
            Vector2D(x: 0.6, y: 0.6)
        ])
        let segment = editable.segments[0]

        editable.setPointPosition(id: segment.controlOutID, to: Vector2D(x: 0.4, y: 0.5))
        editable.setPointPosition(id: segment.controlInID, to: Vector2D(x: 0.5, y: 0.4))
        editable.resetControlsToInferredPositions(segmentIDs: [segment.id])
        let runtime = try editable.toPolygon2D()

        assertVec(runtime.points[1], Vector2D(x: 0.2, y: 0))
        assertVec(runtime.points[2], Vector2D(x: 0.4, y: 0))
    }

    func testDeletingAnchorFromFourSidedPolygonKeepsClosedPolygonWithInferredReplacementEdge() throws {
        let anchors = [
            Vector2D(x: 0, y: 1),
            Vector2D(x: 1, y: 1),
            Vector2D(x: 1, y: 0),
            Vector2D(x: 0, y: 0)
        ]
        let editable = try EditableClosedPolygon(name: "Box", anchors: anchors)
        let deletedAnchor = editable.anchorIDs[1]

        guard case .closedPolygon(let result) = editable.deletingAnchor(id: deletedAnchor) else {
            return XCTFail("Expected a closed polygon after deleting one anchor from a four-sided polygon")
        }
        let runtime = try result.toPolygon2D()

        XCTAssertEqual(result.anchorIDs.count, 3)
        XCTAssertEqual(result.segments.count, 3)
        assertVec(runtime.points[0], Vector2D(x: 0, y: 1))
        assertVec(runtime.points[1], Vector2D(x: 1.0 / 3.0, y: 2.0 / 3.0))
        assertVec(runtime.points[2], Vector2D(x: 2.0 / 3.0, y: 1.0 / 3.0))
        assertVec(runtime.points[3], Vector2D(x: 1, y: 0))
    }

    func testDeletingAnchorFromTriangleCreatesOpenCurve() throws {
        let editable = try EditableClosedPolygon(name: "Triangle", anchors: [
            Vector2D(x: 0, y: 1),
            Vector2D(x: 1, y: 0),
            Vector2D(x: 0, y: 0)
        ])
        let preservedSegment = editable.segments[1]
        var adjusted = editable
        adjusted.setPointPosition(id: preservedSegment.controlOutID, to: Vector2D(x: 0.7, y: 0.8))
        adjusted.setPointPosition(id: preservedSegment.controlInID, to: Vector2D(x: 0.2, y: 0.4))

        guard case .openCurve(let curve) = adjusted.deletingAnchor(id: adjusted.anchorIDs[0]) else {
            return XCTFail("Expected an open curve after deleting one anchor from a triangle")
        }
        let runtime = try curve.toPolygon2D()

        XCTAssertEqual(curve.anchorIDs.count, 2)
        XCTAssertEqual(curve.segments.count, 1)
        XCTAssertEqual(runtime.type, .openSpline)
        assertVec(runtime.points[0], Vector2D(x: 1, y: 0))
        assertVec(runtime.points[1], Vector2D(x: 0.7, y: 0.8))
        assertVec(runtime.points[2], Vector2D(x: 0.2, y: 0.4))
        assertVec(runtime.points[3], Vector2D(x: 0, y: 0))
    }

    func testDeletingEdgeFromClosedPolygonCreatesOpenCurveAtDeletedBreak() throws {
        let editable = try EditableClosedPolygon(name: "Box", anchors: [
            Vector2D(x: 0, y: 1),
            Vector2D(x: 1, y: 1),
            Vector2D(x: 1, y: 0),
            Vector2D(x: 0, y: 0)
        ])

        let curve = try XCTUnwrap(editable.deletingSegment(id: editable.segments[0].id))
        let runtime = try curve.toPolygon2D()

        XCTAssertEqual(runtime.type, .openSpline)
        XCTAssertEqual(curve.segments.count, 3)
        assertVec(runtime.points[0], Vector2D(x: 1, y: 1))
        assertVec(runtime.points[11], Vector2D(x: 0, y: 1))
    }

    // MARK: - Open curve anchor/segment deletion (2026-07-16)

    /// A→B→C→D, three segments — the open-curve counterpart of the box
    /// fixture the closed-polygon deletion tests above use.
    private func fourAnchorOpenCurve() -> EditableOpenCurve {
        EditableOpenCurve(name: "Curve", anchors: [
            Vector2D(x: 0, y: 1),
            Vector2D(x: 1, y: 1),
            Vector2D(x: 1, y: 0),
            Vector2D(x: 0, y: 0),
        ])
    }

    func testDeletingFirstAnchorFromOpenCurveShortensFromTheStart() throws {
        let curve = fourAnchorOpenCurve()
        guard case .shortened(let result) = curve.deletingAnchor(id: curve.anchorIDs[0]) else {
            return XCTFail("Expected a shortened curve after deleting the first anchor")
        }
        let runtime = try result.toPolygon2D()

        XCTAssertEqual(result.anchorIDs.count, 3)
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(runtime.type, .openSpline)
        assertVec(runtime.points[0], Vector2D(x: 1, y: 1))
        assertVec(runtime.points[7], Vector2D(x: 0, y: 0))
    }

    func testDeletingLastAnchorFromOpenCurveShortensFromTheEnd() throws {
        let curve = fourAnchorOpenCurve()
        guard case .shortened(let result) = curve.deletingAnchor(id: curve.anchorIDs[3]) else {
            return XCTFail("Expected a shortened curve after deleting the last anchor")
        }
        let runtime = try result.toPolygon2D()

        XCTAssertEqual(result.anchorIDs.count, 3)
        XCTAssertEqual(result.segments.count, 2)
        assertVec(runtime.points[0], Vector2D(x: 0, y: 1))
        assertVec(runtime.points[7], Vector2D(x: 1, y: 0))
    }

    func testDeletingInteriorAnchorFromOpenCurveInterpolatesAcrossTheGap() throws {
        let curve = fourAnchorOpenCurve()
        guard case .shortened(let result) = curve.deletingAnchor(id: curve.anchorIDs[1]) else {
            return XCTFail("Expected a shortened curve after deleting an interior anchor")
        }
        let runtime = try result.toPolygon2D()

        XCTAssertEqual(result.anchorIDs.count, 3)
        XCTAssertEqual(result.segments.count, 2)
        // Straight-line interpolation between A(0,1) and C(1,0), same 1/3-2/3
        // control placement the closed-polygon interior case uses.
        assertVec(runtime.points[0], Vector2D(x: 0, y: 1))
        assertVec(runtime.points[1], Vector2D(x: 1.0 / 3.0, y: 2.0 / 3.0))
        assertVec(runtime.points[2], Vector2D(x: 2.0 / 3.0, y: 1.0 / 3.0))
        assertVec(runtime.points[3], Vector2D(x: 1, y: 0))
    }

    func testDeletingEitherAnchorOfATwoAnchorCurveEmptiesIt() throws {
        let curve = EditableOpenCurve(name: "Line", anchors: [Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 1)])
        XCTAssertEqual(curve.deletingAnchor(id: curve.anchorIDs[0]), .emptied)
        XCTAssertEqual(curve.deletingAnchor(id: curve.anchorIDs[1]), .emptied)
    }

    func testDeletingNonAnchorPointReturnsNil() throws {
        let curve = fourAnchorOpenCurve()
        let controlPointID = curve.segments[0].controlOutID
        XCTAssertNil(curve.deletingAnchor(id: controlPointID))
    }

    func testDeletingFirstSegmentFromOpenCurveShortensFromTheStart() throws {
        let curve = fourAnchorOpenCurve()
        guard case .shortened(let result) = curve.deletingSegment(id: curve.segments[0].id) else {
            return XCTFail("Expected a shortened curve after deleting the first segment")
        }
        let runtime = try result.toPolygon2D()

        XCTAssertEqual(result.segments.count, 2)
        assertVec(runtime.points[0], Vector2D(x: 1, y: 1))
        assertVec(runtime.points[7], Vector2D(x: 0, y: 0))
    }

    func testDeletingLastSegmentFromOpenCurveShortensFromTheEnd() throws {
        let curve = fourAnchorOpenCurve()
        guard case .shortened(let result) = curve.deletingSegment(id: curve.segments[2].id) else {
            return XCTFail("Expected a shortened curve after deleting the last segment")
        }
        let runtime = try result.toPolygon2D()

        XCTAssertEqual(result.segments.count, 2)
        assertVec(runtime.points[0], Vector2D(x: 0, y: 1))
        assertVec(runtime.points[7], Vector2D(x: 1, y: 0))
    }

    func testDeletingInteriorSegmentFromOpenCurveSplitsIntoTwoCurves() throws {
        let curve = fourAnchorOpenCurve()
        guard case .split(let first, let second) = curve.deletingSegment(id: curve.segments[1].id) else {
            return XCTFail("Expected a split after deleting an interior segment")
        }
        let firstRuntime = try first.toPolygon2D()
        let secondRuntime = try second.toPolygon2D()

        XCTAssertEqual(first.segments.count, 1)
        XCTAssertEqual(second.segments.count, 1)
        assertVec(firstRuntime.points[0], Vector2D(x: 0, y: 1))
        assertVec(firstRuntime.points[3], Vector2D(x: 1, y: 1))
        assertVec(secondRuntime.points[0], Vector2D(x: 1, y: 0))
        assertVec(secondRuntime.points[3], Vector2D(x: 0, y: 0))
        // Each half only carries the points it actually references.
        XCTAssertEqual(first.points.count, 4)
        XCTAssertEqual(second.points.count, 4)
    }

    func testDeletingTheOnlySegmentOfASingleSegmentCurveEmptiesIt() throws {
        let curve = EditableOpenCurve(name: "Line", anchors: [Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 1)])
        XCTAssertEqual(curve.deletingSegment(id: curve.segments[0].id), .emptied)
    }

    func testDeletingUnknownSegmentIDReturnsNil() throws {
        let curve = fourAnchorOpenCurve()
        XCTAssertNil(curve.deletingSegment(id: EditableGeometryID()))
    }

    // MARK: - Multi-select anchor/segment deletion (2026-07-19)

    private func pentagon() throws -> EditableClosedPolygon {
        try EditableClosedPolygon(name: "Pentagon", anchors: [
            Vector2D(x: 0, y: 1),
            Vector2D(x: 0.95, y: 0.31),
            Vector2D(x: 0.59, y: -0.81),
            Vector2D(x: -0.59, y: -0.81),
            Vector2D(x: -0.95, y: 0.31),
        ])
    }

    /// A→B→C→D→E, four segments — a longer open curve than
    /// `fourAnchorOpenCurve()` for tests where one deletion needs to split
    /// the curve and a later deletion needs to further modify one half.
    private func fiveAnchorOpenCurve() -> EditableOpenCurve {
        EditableOpenCurve(name: "Curve", anchors: [
            Vector2D(x: 0, y: 0),
            Vector2D(x: 1, y: 0),
            Vector2D(x: 2, y: 0),
            Vector2D(x: 3, y: 0),
            Vector2D(x: 4, y: 0),
        ])
    }

    func testDeletingTwoNonAdjacentAnchorsFromPentagonShrinksToTriangle() throws {
        let polygon = try pentagon()
        let ids: Set = [polygon.anchorIDs[0], polygon.anchorIDs[2]]

        guard case .closedPolygon(let result) = polygon.deletingAnchors(ids: ids) else {
            return XCTFail("Expected a smaller closed polygon")
        }
        XCTAssertEqual(result.anchorIDs.count, 3)
        XCTAssertEqual(result.segments.count, 3)
    }

    func testDeletingEnoughAnchorsFromSquareConvertsToOpenCurve() throws {
        let square = try EditableClosedPolygon(name: "Box", anchors: [
            Vector2D(x: 0, y: 1), Vector2D(x: 1, y: 1), Vector2D(x: 1, y: 0), Vector2D(x: 0, y: 0),
        ])
        let ids: Set = [square.anchorIDs[0], square.anchorIDs[1]]

        guard case .openCurve(let result) = square.deletingAnchors(ids: ids) else {
            return XCTFail("Expected conversion to an open curve")
        }
        XCTAssertEqual(result.anchorIDs.count, 2)
        XCTAssertEqual(result.segments.count, 1)
    }

    func testDeletingFourOfFiveAnchorsFromPentagonEmptiesIt() throws {
        let polygon = try pentagon()
        let ids = Set(polygon.anchorIDs.prefix(4))

        XCTAssertEqual(polygon.deletingAnchors(ids: ids), .emptied)
    }

    func testDeletingNoMatchingAnchorsFromPolygonLeavesItUnchanged() throws {
        let polygon = try pentagon()

        guard case .closedPolygon(let result) = polygon.deletingAnchors(ids: [EditableGeometryID()]) else {
            return XCTFail("Expected the original polygon back")
        }
        XCTAssertEqual(result, polygon)
    }

    func testDeletingTwoNonAdjacentSegmentsFromSquareProducesTwoOpenCurves() throws {
        let square = try EditableClosedPolygon(name: "Box", anchors: [
            Vector2D(x: 0, y: 1), Vector2D(x: 1, y: 1), Vector2D(x: 1, y: 0), Vector2D(x: 0, y: 0),
        ])
        let ids: Set = [square.segments[0].id, square.segments[2].id]

        guard case .replaced(let pieces) = square.deletingSegments(ids: ids) else {
            return XCTFail("Expected replacement pieces")
        }
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].segments.count, 1)
        XCTAssertEqual(pieces[1].segments.count, 1)
        let firstRuntime = try pieces[0].toPolygon2D()
        let secondRuntime = try pieces[1].toPolygon2D()
        // seg0 (A-B) deleted first turns the square into curve B-C-D-A; seg2
        // (originally C-D) is then interior to that curve and splits it into
        // B-C and D-A.
        assertVec(firstRuntime.points[0], Vector2D(x: 1, y: 1))
        assertVec(firstRuntime.points[3], Vector2D(x: 1, y: 0))
        assertVec(secondRuntime.points[0], Vector2D(x: 0, y: 0))
        assertVec(secondRuntime.points[3], Vector2D(x: 0, y: 1))
    }

    func testDeletingTwoAdjacentSegmentsFromSquareProducesOneShorterCurve() throws {
        let square = try EditableClosedPolygon(name: "Box", anchors: [
            Vector2D(x: 0, y: 1), Vector2D(x: 1, y: 1), Vector2D(x: 1, y: 0), Vector2D(x: 0, y: 0),
        ])
        let ids: Set = [square.segments[0].id, square.segments[1].id]

        guard case .replaced(let pieces) = square.deletingSegments(ids: ids) else {
            return XCTFail("Expected replacement pieces")
        }
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].segments.count, 2)
        let runtime = try pieces[0].toPolygon2D()
        assertVec(runtime.points[0], Vector2D(x: 1, y: 0))
        assertVec(runtime.points[7], Vector2D(x: 0, y: 1))
    }

    func testDeletingNoMatchingSegmentsFromPolygonIsUnchanged() throws {
        let polygon = try pentagon()
        XCTAssertEqual(polygon.deletingSegments(ids: [EditableGeometryID()]), .unchanged)
    }

    func testDeletingFirstAndLastAnchorFromOpenCurveShortensProgressively() throws {
        let curve = fourAnchorOpenCurve()
        let ids: Set = [curve.anchorIDs[0], curve.anchorIDs[3]]

        guard case .shortened(let result) = curve.deletingAnchors(ids: ids) else {
            return XCTFail("Expected a shortened curve")
        }
        XCTAssertEqual(result.anchorIDs.count, 2)
        XCTAssertEqual(result.segments.count, 1)
        let runtime = try result.toPolygon2D()
        assertVec(runtime.points[0], Vector2D(x: 1, y: 1))
        assertVec(runtime.points[3], Vector2D(x: 1, y: 0))
    }

    func testDeletingBothInteriorAnchorsFromOpenCurveInterpolatesTwice() throws {
        let curve = fourAnchorOpenCurve()
        let ids: Set = [curve.anchorIDs[1], curve.anchorIDs[2]]

        guard case .shortened(let result) = curve.deletingAnchors(ids: ids) else {
            return XCTFail("Expected a shortened curve")
        }
        XCTAssertEqual(result.anchorIDs.count, 2)
        XCTAssertEqual(result.segments.count, 1)
        let runtime = try result.toPolygon2D()
        // Straight line directly from A(0,1) to D(0,0) — both interior
        // anchors interpolated away in sequence.
        assertVec(runtime.points[0], Vector2D(x: 0, y: 1))
        assertVec(runtime.points[3], Vector2D(x: 0, y: 0))
    }

    func testDeletingSegmentsFromOpenCurveCanSplitThenShortenOnePiece() throws {
        let curve = fiveAnchorOpenCurve()
        let ids: Set = [curve.segments[1].id, curve.segments[3].id]

        guard case .replaced(let pieces) = curve.deletingSegments(ids: ids) else {
            return XCTFail("Expected replacement pieces")
        }
        XCTAssertEqual(pieces.count, 2)
        // seg[1] (B-C) is interior, splitting into [A-B] and [C-D-E]; seg[3]
        // (D-E) is then the terminal segment of the second piece, shortening
        // it to [C-D].
        let totalSegments = pieces.reduce(0) { $0 + $1.segments.count }
        XCTAssertEqual(totalSegments, 2)
        XCTAssertTrue(pieces.allSatisfy { $0.segments.count == 1 })
    }

    func testLayerDeletingAnchorsOnlyTouchesObjectsWithMatchingAnchors() throws {
        let untouchedPolygon = try pentagon()
        let targetPolygon = try EditableClosedPolygon(name: "Box", anchors: [
            Vector2D(x: 0, y: 1), Vector2D(x: 1, y: 1), Vector2D(x: 1, y: 0), Vector2D(x: 0, y: 0),
        ])
        let untouchedCurve = fourAnchorOpenCurve()
        let layer = EditableGeometryLayer(
            name: "Layer", polygons: [untouchedPolygon, targetPolygon], openCurves: [untouchedCurve]
        )

        let result = layer.deletingAnchors(ids: [targetPolygon.anchorIDs[0]])

        XCTAssertEqual(result.polygons.count, 2)
        XCTAssertTrue(result.polygons.contains(untouchedPolygon), "untouched polygon must be returned as-is")
        XCTAssertTrue(result.polygons.contains { $0.anchorIDs.count == 3 }, "target polygon should have lost one anchor")
        XCTAssertEqual(result.openCurves, [untouchedCurve])
    }

    func testLayerDeletingSegmentsMovesConvertedPolygonIntoOpenCurves() throws {
        let untouchedCurve = fourAnchorOpenCurve()
        let targetPolygon = try EditableClosedPolygon(name: "Box", anchors: [
            Vector2D(x: 0, y: 1), Vector2D(x: 1, y: 1), Vector2D(x: 1, y: 0), Vector2D(x: 0, y: 0),
        ])
        let layer = EditableGeometryLayer(
            name: "Layer", polygons: [targetPolygon], openCurves: [untouchedCurve]
        )

        let result = layer.deletingSegments(ids: [targetPolygon.segments[0].id])

        XCTAssertTrue(result.polygons.isEmpty, "the only polygon converted away entirely")
        XCTAssertEqual(result.openCurves.count, 2)
        XCTAssertTrue(result.openCurves.contains(untouchedCurve), "untouched curve must be returned as-is")
    }

    func testLayerDeletingAnchorsWithEmptySetIsANoOp() throws {
        let polygon = try pentagon()
        let layer = EditableGeometryLayer(name: "Layer", polygons: [polygon])
        XCTAssertEqual(layer.deletingAnchors(ids: []), layer)
    }

    func testLayerDeletingSegmentsWithEmptySetIsANoOp() throws {
        let polygon = try pentagon()
        let layer = EditableGeometryLayer(name: "Layer", polygons: [polygon])
        XCTAssertEqual(layer.deletingSegments(ids: []), layer)
    }

    func testClosingOpenCurveCreatesClosedPolygon() throws {
        let curve = EditableOpenCurve(name: "Curve", anchors: [
            Vector2D(x: 0, y: 1),
            Vector2D(x: 1, y: 0),
            Vector2D(x: 0, y: 0)
        ])

        let polygon = try XCTUnwrap(curve.closingToPolygon())
        let runtime = try polygon.toPolygon2D()

        XCTAssertEqual(runtime.type, .spline)
        XCTAssertEqual(polygon.segments.count, 3)
        assertVec(runtime.points[8], Vector2D(x: 0, y: 0))
        assertVec(runtime.points[11], Vector2D(x: 0, y: 1))
    }

    func testAnchorClicksBecomeEditableClosedPolygonWithInferredControls() throws {
        let anchors = [
            Vector2D(x: -0.2, y: -0.2),
            Vector2D(x: 0.3, y: 0.0),
            Vector2D(x: -0.2, y: 0.3)
        ]

        let editable = try EditableClosedPolygon(name: "Draft", anchors: anchors)
        let runtime = try editable.toPolygon2D()

        XCTAssertEqual(editable.segments.count, 3)
        XCTAssertEqual(editable.points.count, 9)
        assertVec(runtime.points[0], Vector2D(x: -0.2, y: -0.2))
        assertVec(runtime.points[1], Vector2D(x: -0.033333333333333354, y: -0.13333333333333333))
        assertVec(runtime.points[2], Vector2D(x: 0.1333333333333333, y: -0.06666666666666668))
        assertVec(runtime.points[3], Vector2D(x: 0.3, y: 0.0))
        assertVec(runtime.points[11], Vector2D(x: -0.2, y: -0.2))
    }

    func testDocumentEnsuresActiveLayer() {
        var document = EditableGeometryDocument(name: "Untitled")

        document.ensureActiveLayer()

        XCTAssertEqual(document.layers.count, 1)
        XCTAssertEqual(document.activeLayerID, document.layers.first?.id)
    }

    func testDuplicatingPolygonPreservesShapeWithFreshIDs() throws {
        let editable = try EditableClosedPolygon(name: "Loop", polygon: sampleSpline())

        let copy = editable.duplicated(name: "Loop Copy")
        let originalRuntime = try editable.toPolygon2D()
        let copiedRuntime = try copy.toPolygon2D()

        XCTAssertEqual(copy.name, "Loop Copy")
        XCTAssertNotEqual(copy.id, editable.id)
        XCTAssertTrue(Set(copy.points.map(\.id)).isDisjoint(with: Set(editable.points.map(\.id))))
        XCTAssertTrue(Set(copy.segments.map(\.id)).isDisjoint(with: Set(editable.segments.map(\.id))))
        XCTAssertEqual(copiedRuntime.points, originalRuntime.points)
        XCTAssertEqual(copiedRuntime.pressures, originalRuntime.pressures)
    }

    func testDuplicatingLayerDuplicatesContainedGeometry() throws {
        let polygon = try EditableClosedPolygon(name: "Loop", polygon: sampleSpline())
        let layer = EditableGeometryLayer(name: "Layer 1", isVisible: false, isEditable: false, polygons: [polygon])

        let copy = layer.duplicated(name: "Layer 1 Copy")

        XCTAssertEqual(copy.name, "Layer 1 Copy")
        XCTAssertEqual(copy.isVisible, layer.isVisible)
        XCTAssertEqual(copy.isEditable, layer.isEditable)
        XCTAssertNotEqual(copy.id, layer.id)
        XCTAssertEqual(copy.polygons.count, 1)
        XCTAssertNotEqual(copy.polygons[0].id, polygon.id)
        XCTAssertEqual(try copy.polygons[0].toPolygon2D().points, try polygon.toPolygon2D().points)
    }

    func testLayerJSONDecodingDefaultsMissingEditabilityToEditable() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy Layer",
          "isVisible": true,
          "polygons": []
        }
        """

        let layer = try JSONDecoder().decode(EditableGeometryLayer.self, from: Data(json.utf8))

        XCTAssertEqual(layer.id, id)
        XCTAssertTrue(layer.isEditable)
    }

    func testSnapshotCapturesDocumentAndSelection() throws {
        let polygon = try EditableClosedPolygon(name: "Loop", polygon: sampleSpline())
        let layer = EditableGeometryLayer(name: "Layer 1", polygons: [polygon])
        let document = EditableGeometryDocument(name: "Doc", layers: [layer])
        let selection = EditableGeometrySelection(
            layerID: layer.id,
            polygonIDs: [polygon.id],
            pointIDs: [polygon.segments[0].startAnchorID]
        )

        let snapshot = EditableGeometrySnapshot(document: document, selection: selection)

        XCTAssertEqual(snapshot.document.layers.first?.polygons.first?.id, polygon.id)
        XCTAssertTrue(snapshot.selection.polygonIDs.contains(polygon.id))
        XCTAssertTrue(snapshot.selection.pointIDs.contains(polygon.segments[0].startAnchorID))
    }

    func testHistoryKeepsTwentySnapshotsAndClearsRedoOnRecord() {
        var history = EditableGeometryHistory(limit: 20)
        for index in 0..<25 {
            let document = EditableGeometryDocument(name: "Doc \(index)")
            history.record(EditableGeometrySnapshot(document: document))
        }

        XCTAssertEqual(history.undoStack.count, 20)
        XCTAssertEqual(history.undoStack.first?.document.name, "Doc 5")

        let current = EditableGeometrySnapshot(document: EditableGeometryDocument(name: "Current"))
        XCTAssertNotNil(history.undo(current: current))
        XCTAssertEqual(history.redoStack.count, 1)

        history.record(EditableGeometrySnapshot(document: EditableGeometryDocument(name: "New")))
        XCTAssertTrue(history.redoStack.isEmpty)
    }

    func testRejectsNonSplineRuntimePolygon() {
        let line = Polygon2D(
            points: [Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0), Vector2D(x: 0, y: 1)],
            type: .line
        )

        XCTAssertThrowsError(try EditableClosedPolygon(name: "Line", polygon: line)) { error in
            XCTAssertEqual(error as? EditableGeometryError, .unsupportedPolygonType(.line))
        }
    }

    func testEditableGeometryJSONRoundTripIncludesSchemaMetadata() throws {
        let document = try EditableGeometryDocument.closedPolygonDocument(
            name: "JSON Doc",
            polygons: [sampleSpline()]
        )

        let data = try EditableGeometryJSONLoader.encode(document)
        let json = String(data: data, encoding: .utf8) ?? ""
        let decoded = try EditableGeometryJSONLoader.decode(from: data)

        XCTAssertTrue(json.contains("\"schema\" : \"loom.editableGeometry\""))
        XCTAssertTrue(json.contains("\"schemaVersion\" : 2"))
        XCTAssertEqual(decoded, document)
    }

    func testEditableGeometryJSONSaveLoadFile() throws {
        let document = try EditableGeometryDocument.closedPolygonDocument(
            name: "Saved Doc",
            polygons: [sampleSpline()]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("editable-geometry-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try EditableGeometryJSONLoader.save(document, to: url)
        let loaded = try EditableGeometryJSONLoader.load(url: url)

        XCTAssertEqual(loaded, document)
    }

    func testJSONEditableGeometryCanDriveSpriteScenePipeline() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-json-pipeline-\(UUID().uuidString)", isDirectory: true)
        let polygonDir = root.appendingPathComponent("polygonSets", isDirectory: true)
        try FileManager.default.createDirectory(at: polygonDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let document = try EditableGeometryDocument.closedPolygonDocument(
            name: "New_Polygon_Set",
            polygons: [sampleSpline()]
        )
        try EditableGeometryJSONLoader.save(document, to: polygonDir.appendingPathComponent("New_Polygon_Set.json"))

        let polygonSet = PolygonSetDef(
            name: "New_Polygon_Set",
            folder: "polygonSets",
            filename: "New_Polygon_Set.json",
            polygonType: .splinePolygon
        )
        let shape = ShapeDef(
            name: "New_Polygon_Set_Shape",
            sourceType: .polygonSet,
            polygonSetName: "New_Polygon_Set",
            subdivisionParamsSetName: "New_Polygon_Set_Subdivide"
        )
        let sprite = SpriteDef(
            name: "New_Polygon_Set_Sprite",
            shapeSetName: "New_Polygon_Set_Shapes",
            shapeName: "New_Polygon_Set_Shape",
            rendererSetName: "New_Polygon_Set_Renderers"
        )
        let config = ProjectConfig(
            shapeConfig: ShapeConfig(library: ShapeLibrary(shapeSets: [
                ShapeSet(name: "New_Polygon_Set_Shapes", shapes: [shape])
            ])),
            polygonConfig: PolygonConfig(library: PolygonSetLibrary(polygonSets: [polygonSet])),
            subdivisionConfig: SubdivisionConfig(paramsSets: [
                SubdivisionParamsSet(
                    name: "New_Polygon_Set_Subdivide",
                    params: [SubdivisionParams(name: "New_Polygon_Set_quad_1", subdivisionType: .quad)]
                )
            ]),
            renderingConfig: RenderingConfig(library: RendererSetLibrary(rendererSets: [
                RendererSet(name: "New_Polygon_Set_Renderers", renderers: [
                    Renderer(name: "New_Polygon_Set_Renderer", mode: .filled)
                ])
            ])),
            spriteConfig: SpriteConfig(library: SpriteLibrary(spriteSets: [
                SpriteSet(name: "New_Polygon_Set_Sprites", sprites: [sprite])
            ]))
        )

        let scene = try SpriteScene(config: config, projectDirectory: root)

        XCTAssertEqual(scene.instances.count, 1)
        XCTAssertEqual(scene.instances[0].basePolygons.count, 1)
        XCTAssertEqual(scene.instances[0].subdivisionParams.count, 1)
        XCTAssertEqual(scene.instances[0].rendererSet.renderers.count, 1)
    }

    func testJSONEditableGeometryLayerTargetDrivesSpriteScenePipeline() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-json-layer-pipeline-\(UUID().uuidString)", isDirectory: true)
        let polygonDir = root.appendingPathComponent("polygonSets", isDirectory: true)
        try FileManager.default.createDirectory(at: polygonDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let background = EditableGeometryLayer(
            name: "Background",
            polygons: [try EditableClosedPolygon(name: "Background Polygon", polygon: sampleSpline())]
        )
        let foreground = EditableGeometryLayer(
            name: "Foreground",
            polygons: [try EditableClosedPolygon(name: "Foreground Polygon", polygon: sampleSpline())]
        )
        let document = EditableGeometryDocument(
            name: "Layered_Set",
            layers: [background, foreground],
            activeLayerID: background.id
        )
        try EditableGeometryJSONLoader.save(document, to: polygonDir.appendingPathComponent("Layered_Set.json"))

        let fullSet = PolygonSetDef(
            name: "Layered_Set",
            folder: "polygonSets",
            filename: "Layered_Set.json",
            polygonType: .splinePolygon
        )
        let foregroundSet = PolygonSetDef(
            name: "Layered_Set_Foreground",
            folder: "polygonSets",
            filename: "Layered_Set.json",
            polygonType: .splinePolygon,
            editableLayerID: foreground.id,
            editableLayerName: foreground.name
        )
        let shape = ShapeDef(
            name: "Layered_Set_Foreground_Shape",
            sourceType: .polygonSet,
            polygonSetName: "Layered_Set_Foreground",
            subdivisionParamsSetName: "Layered_Set_Foreground_Subdivide"
        )
        let sprite = SpriteDef(
            name: "Layered_Set_Foreground_Sprite",
            shapeSetName: "Layered_Set_Foreground_Shapes",
            shapeName: "Layered_Set_Foreground_Shape",
            rendererSetName: "Layered_Set_Foreground_Renderers"
        )
        let config = ProjectConfig(
            shapeConfig: ShapeConfig(library: ShapeLibrary(shapeSets: [
                ShapeSet(name: "Layered_Set_Foreground_Shapes", shapes: [shape])
            ])),
            polygonConfig: PolygonConfig(library: PolygonSetLibrary(polygonSets: [fullSet, foregroundSet])),
            subdivisionConfig: SubdivisionConfig(paramsSets: [
                SubdivisionParamsSet(
                    name: "Layered_Set_Foreground_Subdivide",
                    params: [SubdivisionParams(name: "Layered_Set_Foreground_quad_1", subdivisionType: .quad)]
                )
            ]),
            renderingConfig: RenderingConfig(library: RendererSetLibrary(rendererSets: [
                RendererSet(name: "Layered_Set_Foreground_Renderers", renderers: [
                    Renderer(name: "Layered_Set_Foreground_Renderer", mode: .filled)
                ])
            ])),
            spriteConfig: SpriteConfig(library: SpriteLibrary(spriteSets: [
                SpriteSet(name: "Layered_Set_Foreground_Sprites", sprites: [sprite])
            ]))
        )

        let scene = try SpriteScene(config: config, projectDirectory: root)

        XCTAssertEqual(try document.runtimePolygons().count, 2)
        XCTAssertEqual(scene.instances.count, 1)
        XCTAssertEqual(scene.instances[0].basePolygons.count, 1)
    }

    func testJSONEditableOpenCurveLayerTargetDrivesSpriteScenePipeline() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-json-curve-layer-pipeline-\(UUID().uuidString)", isDirectory: true)
        let curveDir = root.appendingPathComponent("curveSets", isDirectory: true)
        try FileManager.default.createDirectory(at: curveDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let lineLayer = EditableGeometryLayer(
            name: "l",
            openCurves: [EditableOpenCurve(name: "Line", anchors: [
                Vector2D(x: 0, y: 0),
                Vector2D(x: 1, y: 0)
            ])]
        )
        let spiralLayer = EditableGeometryLayer(
            name: "spiral",
            openCurves: [EditableOpenCurve(name: "Spiral", anchors: [
                Vector2D(x: 0, y: 0),
                Vector2D(x: 1, y: 1),
                Vector2D(x: 0, y: 2)
            ])]
        )
        let document = EditableGeometryDocument(
            name: "line",
            layers: [lineLayer, spiralLayer],
            activeLayerID: lineLayer.id
        )
        try EditableGeometryJSONLoader.save(document, to: curveDir.appendingPathComponent("line.json"))

        let spiralSet = OpenCurveSetDef(
            name: "line_spiral",
            folder: "curveSets",
            filename: "line.json",
            editableLayerID: spiralLayer.id,
            editableLayerName: spiralLayer.name
        )
        let shape = ShapeDef(
            name: "line_spiral_Shape",
            sourceType: .openCurveSet,
            openCurveSetName: "line_spiral",
            subdivisionParamsSetName: ""
        )
        let sprite = SpriteDef(
            name: "line_spiral_Sprite",
            shapeSetName: "line_spiral_Shapes",
            shapeName: "line_spiral_Shape",
            rendererSetName: "line_spiral_Renderers"
        )
        let config = ProjectConfig(
            shapeConfig: ShapeConfig(library: ShapeLibrary(shapeSets: [
                ShapeSet(name: "line_spiral_Shapes", shapes: [shape])
            ])),
            curveConfig: CurveConfig(library: OpenCurveSetLibrary(curveSets: [spiralSet])),
            renderingConfig: RenderingConfig(library: RendererSetLibrary(rendererSets: [
                RendererSet(name: "line_spiral_Renderers", renderers: [
                    Renderer(name: "line_spiral_Renderer", mode: .stroked)
                ])
            ])),
            spriteConfig: SpriteConfig(library: SpriteLibrary(spriteSets: [
                SpriteSet(name: "line_spiral_Sprites", sprites: [sprite])
            ]))
        )

        let scene = try SpriteScene(config: config, projectDirectory: root)

        XCTAssertEqual(try document.runtimePolygons().count, 2)
        XCTAssertEqual(scene.instances.count, 1)
        XCTAssertEqual(scene.instances[0].basePolygons.count, 1)
        XCTAssertEqual(scene.instances[0].basePolygons.first?.type, .openSpline)
    }

    func testEditableGeometryJSONRejectsUnsupportedVersion() throws {
        let document = try EditableGeometryDocument.closedPolygonDocument(
            name: "JSON Doc",
            polygons: [sampleSpline()]
        )
        let file = EditableGeometryFile(schemaVersion: 999, document: document)
        let data = try JSONEncoder().encode(file)

        XCTAssertThrowsError(try EditableGeometryJSONLoader.decode(from: data)) { error in
            XCTAssertEqual(error as? EditableGeometryJSONError, .unsupportedVersion(999))
        }
    }

    func testDocumentRuntimePolygonsSkipsHiddenLayersAndPolygons() throws {
        let visiblePolygon = try EditableClosedPolygon(name: "Visible", polygon: sampleSpline())
        var hiddenPolygon = visiblePolygon
        hiddenPolygon.id = UUID()
        hiddenPolygon.name = "Hidden"
        hiddenPolygon.isVisible = false
        let visibleLayer = EditableGeometryLayer(
            name: "Visible Layer",
            polygons: [visiblePolygon, hiddenPolygon]
        )
        let hiddenLayer = EditableGeometryLayer(
            name: "Hidden Layer",
            isVisible: false,
            polygons: [visiblePolygon]
        )
        let document = EditableGeometryDocument(
            name: "Doc",
            layers: [visibleLayer, hiddenLayer],
            activeLayerID: visibleLayer.id
        )

        let runtime = try document.runtimePolygons()

        XCTAssertEqual(runtime.count, 1)
        XCTAssertEqual(runtime[0].type, .spline)
    }

    func testStandalonePointsRoundTripAndExportAsRuntimePoints() throws {
        let point = EditableStandalonePoint(
            name: "Stamp",
            position: Vector2D(x: 0.2, y: -0.3)
        )
        let layer = EditableGeometryLayer(name: "Layer", points: [point])
        let document = EditableGeometryDocument(name: "Points", layers: [layer], activeLayerID: layer.id)

        let data = try EditableGeometryJSONLoader.encode(document)
        let decoded = try EditableGeometryJSONLoader.decode(from: data)
        let runtime = try decoded.runtimePolygons()

        XCTAssertEqual(decoded.layers[0].points.count, 1)
        XCTAssertEqual(runtime.count, 1)
        XCTAssertEqual(runtime[0].type, .point)
        assertVec(runtime[0].points[0], Vector2D(x: 0.2, y: -0.3))
    }

    func testDocumentWeldGroupsMergeAndRoundTripThroughJSON() throws {
        let polygonA = try EditableClosedPolygon(name: "A", anchors: [
            Vector2D(x: 0, y: 0),
            Vector2D(x: 1, y: 0),
            Vector2D(x: 1, y: 1)
        ])
        let polygonB = try EditableClosedPolygon(name: "B", anchors: [
            Vector2D(x: 1, y: 0),
            Vector2D(x: 2, y: 0),
            Vector2D(x: 2, y: 1)
        ])
        let layer = EditableGeometryLayer(name: "Layer", polygons: [polygonA, polygonB])
        var document = EditableGeometryDocument(name: "Welded", layers: [layer], activeLayerID: layer.id)
        let firstID = polygonA.segments[0].endAnchorID
        let secondID = polygonB.segments[0].startAnchorID

        document.weldPoints([firstID, secondID])
        let data = try EditableGeometryJSONLoader.encode(document)
        let decoded = try EditableGeometryJSONLoader.decode(from: data)

        XCTAssertEqual(decoded.weldGroups.count, 1)
        XCTAssertEqual(decoded.weldedPointIDs(containing: firstID), Set([firstID, secondID]))
    }

    func testRelationalPointIDsIncludeWeldedAnchorsAndTheirAttachedControls() throws {
        let polygonA = try EditableClosedPolygon(name: "A", anchors: [
            Vector2D(x: 0, y: 0),
            Vector2D(x: 1, y: 0),
            Vector2D(x: 1, y: 1)
        ])
        let polygonB = try EditableClosedPolygon(name: "B", anchors: [
            Vector2D(x: 1, y: 0),
            Vector2D(x: 2, y: 0),
            Vector2D(x: 2, y: 1)
        ])
        let layer = EditableGeometryLayer(name: "Layer", polygons: [polygonA, polygonB])
        var document = EditableGeometryDocument(name: "Welded", layers: [layer], activeLayerID: layer.id)
        let firstID = polygonA.segments[0].endAnchorID
        let secondID = polygonB.segments[0].startAnchorID

        document.weldPoints([firstID, secondID])
        let relationalIDs = document.relationalPointIDs(startingWith: [firstID])

        XCTAssertTrue(relationalIDs.contains(firstID))
        XCTAssertTrue(relationalIDs.contains(secondID))
        XCTAssertTrue(relationalIDs.contains(polygonA.segments[0].controlInID))
        XCTAssertTrue(relationalIDs.contains(polygonA.segments[1].controlOutID))
        XCTAssertTrue(relationalIDs.contains(polygonB.segments[0].controlOutID))
        XCTAssertTrue(relationalIDs.contains(polygonB.segments[2].controlInID))
    }

    func testClosingOpenCurvePreservesPressureValues() throws {
        var curve = EditableOpenCurve(name: "Freehand", anchors: [
            Vector2D(x: 0, y: 0),
            Vector2D(x: 1, y: 0),
            Vector2D(x: 1, y: 1)
        ])
        curve.pressures = [0.2, 0.45, 0.8]

        let polygon = try XCTUnwrap(curve.closingToPolygon())

        XCTAssertEqual(polygon.segments.count, 3)
        XCTAssertEqual(polygon.pressures, [0.2, 0.45, 0.8])
    }

    func testClosingOpenCurveWithCoincidentEndpointsDoesNotAddZeroLengthSegment() throws {
        var curve = EditableOpenCurve(name: "Welded Freehand", anchors: [
            Vector2D(x: 0, y: 0),
            Vector2D(x: 1, y: 0),
            Vector2D(x: 1, y: 1),
            Vector2D(x: 0, y: 0)
        ])
        curve.pressures = [0.2, 0.45, 0.8, 0.3]

        let polygon = try XCTUnwrap(curve.closingToPolygon())

        XCTAssertEqual(polygon.segments.count, 3)
        XCTAssertEqual(polygon.pressures, [0.2, 0.45, 0.8])
        XCTAssertEqual(polygon.segments.last?.endAnchorID, polygon.anchorIDs.first)
    }

    func testClosedPolygonXMLPreservesPressureValues() throws {
        let poly = sampleSpline()
        let xml = XMLPolygonWriter.polygonSetXML([poly], name: "Pressure")

        XCTAssertTrue(xml.contains("pressure=\"0.250000\""))
        XCTAssertTrue(xml.contains("pressure=\"0.750000\""))

        let loaded = try XMLPolygonLoader.load(data: Data(xml.utf8), normalise: false)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].type, .spline)
        XCTAssertEqual(loaded[0].pressures, [0.25, 0.75])
    }

    func testOpenCurveXMLPreservesTerminalPressureValue() throws {
        let poly = Polygon2D(
            points: [
                Vector2D(x: 0, y: 0),
                Vector2D(x: 0.2, y: 0),
                Vector2D(x: 0.8, y: 0),
                Vector2D(x: 1, y: 0)
            ],
            type: .openSpline,
            pressures: [0.2, 0.9]
        )
        let xml = XMLPolygonWriter.polygonSetXML([poly], name: "OpenPressure")

        let loaded = try XMLPolygonLoader.load(data: Data(xml.utf8), normalise: false)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].type, .openSpline)
        XCTAssertEqual(loaded[0].pressures, [0.2, 0.9])
    }

    // MARK: - Selection inversion (2026-07-14)

    private func makeSelectionTestDocument() throws -> (
        document: EditableGeometryDocument, layerID: EditableGeometryID,
        polyA: EditableClosedPolygon, polyB: EditableClosedPolygon,
        curve: EditableOpenCurve, standalone: EditableStandalonePoint
    ) {
        let polyA = try EditableClosedPolygon(name: "A", anchors: [
            Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0), Vector2D(x: 1, y: 1), Vector2D(x: 0, y: 1),
        ])
        let polyB = try EditableClosedPolygon(name: "B", anchors: [
            Vector2D(x: 2, y: 0), Vector2D(x: 3, y: 0), Vector2D(x: 3, y: 1), Vector2D(x: 2, y: 1),
        ])
        let curve = EditableOpenCurve(name: "C", anchors: [Vector2D(x: 0, y: 2), Vector2D(x: 1, y: 2)])
        let standalone = EditableStandalonePoint(name: "P", position: Vector2D(x: 5, y: 5))
        let layer = EditableGeometryLayer(name: "Layer", polygons: [polyA, polyB], openCurves: [curve], points: [standalone])
        let document = EditableGeometryDocument(name: "Doc", layers: [layer])
        return (document, layer.id, polyA, polyB, curve, standalone)
    }

    func testInvertSelectionWithNothingSelectedSelectsAllPointsInLayer() throws {
        let (document, layerID, polyA, polyB, curve, standalone) = try makeSelectionTestDocument()
        let empty = EditableGeometrySelection(layerID: layerID)

        let inverted = document.invertedSelection(from: empty)

        let expectedCount = polyA.points.count + polyB.points.count + curve.points.count + 1
        XCTAssertEqual(inverted.pointIDs.count, expectedCount)
        XCTAssertEqual(inverted.polygonIDs, Set([polyA.id, polyB.id]))
        XCTAssertEqual(inverted.openCurveIDs, [curve.id])
        XCTAssertEqual(inverted.standalonePointIDs, [standalone.id])
        XCTAssertTrue(inverted.segmentIDs.isEmpty)
    }

    func testInvertSelectionOfEveryPointReturnsEmpty() throws {
        let (document, layerID, polyA, polyB, curve, standalone) = try makeSelectionTestDocument()
        let allPointIDs = Set(polyA.points.map(\.id) + polyB.points.map(\.id) + curve.points.map(\.id) + [standalone.id])
        let full = EditableGeometrySelection(
            layerID: layerID,
            polygonIDs: [polyA.id, polyB.id],
            openCurveIDs: [curve.id],
            standalonePointIDs: [standalone.id],
            pointIDs: allPointIDs
        )

        XCTAssertEqual(document.invertedSelection(from: full), .empty)
    }

    func testInvertSelectionOfSomePointsComplementsExactlyAndRebuildsContainerBookkeeping() throws {
        let (document, layerID, polyA, polyB, curve, standalone) = try makeSelectionTestDocument()
        // Every point of polyA selected — after inverting, polyA should have
        // no selected points and must drop out of `polygonIDs` entirely.
        let current = EditableGeometrySelection(
            layerID: layerID, polygonIDs: [polyA.id], pointIDs: Set(polyA.points.map(\.id))
        )

        let inverted = document.invertedSelection(from: current)

        let expectedPointIDs = Set(polyB.points.map(\.id) + curve.points.map(\.id) + [standalone.id])
        XCTAssertEqual(inverted.pointIDs, expectedPointIDs)
        XCTAssertFalse(inverted.polygonIDs.contains(polyA.id))
        XCTAssertTrue(inverted.polygonIDs.contains(polyB.id))
        XCTAssertEqual(inverted.openCurveIDs, [curve.id])
        XCTAssertEqual(inverted.standalonePointIDs, [standalone.id])
    }

    func testInvertSelectionInSegmentModeComplementsSegmentsAndStaysInSegmentMode() throws {
        let (document, layerID, polyA, polyB, curve, _) = try makeSelectionTestDocument()
        // Every one of polyA's segments selected — after inverting, none of
        // its segments remain selected, so it must drop out of `polygonIDs`.
        let allOfPolyASegments = Set(polyA.segments.map(\.id))
        let current = EditableGeometrySelection(layerID: layerID, polygonIDs: [polyA.id], segmentIDs: allOfPolyASegments)

        let inverted = document.invertedSelection(from: current)

        XCTAssertTrue(inverted.pointIDs.isEmpty, "must stay in segment mode, not switch to point mode")
        let allSegmentIDs = Set(polyA.segments.map(\.id) + polyB.segments.map(\.id) + curve.segments.map(\.id))
        XCTAssertEqual(inverted.segmentIDs, allSegmentIDs.subtracting(allOfPolyASegments))
        XCTAssertFalse(inverted.polygonIDs.contains(polyA.id), "every one of polyA's segments is now deselected")
        XCTAssertTrue(inverted.polygonIDs.contains(polyB.id))
        XCTAssertEqual(inverted.openCurveIDs, [curve.id])
    }

    func testInvertSelectionInWholeObjectModeComplementsPolygonsAndCurves() throws {
        let (document, layerID, polyA, polyB, curve, _) = try makeSelectionTestDocument()
        let current = EditableGeometrySelection(layerID: layerID, polygonIDs: [polyA.id])

        let inverted = document.invertedSelection(from: current)

        XCTAssertTrue(inverted.pointIDs.isEmpty)
        XCTAssertTrue(inverted.segmentIDs.isEmpty)
        XCTAssertEqual(inverted.polygonIDs, [polyB.id])
        XCTAssertEqual(inverted.openCurveIDs, [curve.id])
    }

    func testInvertSelectionTwiceReturnsToTheOriginalSelection() throws {
        let (document, layerID, polyA, _, _, _) = try makeSelectionTestDocument()
        let original = EditableGeometrySelection(
            layerID: layerID, polygonIDs: [polyA.id], pointIDs: Set(polyA.points.prefix(4).map(\.id))
        )

        let onceInverted  = document.invertedSelection(from: original)
        let twiceInverted = document.invertedSelection(from: onceInverted)

        XCTAssertEqual(twiceInverted.pointIDs, original.pointIDs)
        XCTAssertEqual(twiceInverted.polygonIDs, original.polygonIDs)
    }

    func testInvertSelectionWithUnknownLayerReturnsSelectionUnchanged() throws {
        let (document, _, _, _, _, _) = try makeSelectionTestDocument()
        let bogus = EditableGeometrySelection(layerID: EditableGeometryID(), pointIDs: [EditableGeometryID()])

        XCTAssertEqual(document.invertedSelection(from: bogus), bogus)
    }
}

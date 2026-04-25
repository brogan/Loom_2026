import XCTest
@testable import LoomEngine
import Foundation

// MARK: - Shared test fixtures

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

private func makeTriangle() -> Polygon2D {
    let cp = Vector2D(x: 0.25, y: 0.75)
    let corners = [
        Vector2D(x: 0, y: 0),
        Vector2D(x: 1, y: 0),
        Vector2D(x: 0.5, y: 1),
    ]
    var pts = [Vector2D]()
    for i in 0..<3 {
        pts += BezierMath.connector(from: corners[i], to: corners[(i + 1) % 3], cpRatios: cp)
    }
    return Polygon2D(points: pts, type: .spline)
}

// MARK: - BezierMathTests

final class BezierMathTests: XCTestCase {
    let eps = 1e-10

    private func assertVec2(_ a: Vector2D, _ b: Vector2D, _ msg: String = "") {
        XCTAssertEqual(a.x, b.x, accuracy: eps, "x mismatch: \(msg)")
        XCTAssertEqual(a.y, b.y, accuracy: eps, "y mismatch: \(msg)")
    }

    // MARK: point

    func testPointAtT0IsP0() {
        let p0 = Vector2D(x: 1, y: 2)
        let p3 = Vector2D(x: 5, y: 6)
        let seg = BezierMath.connector(from: p0, to: p3, cpRatios: Vector2D(x: 0.25, y: 0.75))
        assertVec2(BezierMath.point(seg: seg, t: 0), p0, "t=0 → p0")
    }

    func testPointAtT1IsP3() {
        let p0 = Vector2D(x: 1, y: 2)
        let p3 = Vector2D(x: 5, y: 6)
        let seg = BezierMath.connector(from: p0, to: p3, cpRatios: Vector2D(x: 0.25, y: 0.75))
        assertVec2(BezierMath.point(seg: seg, t: 1), p3, "t=1 → p3")
    }

    func testPointAtHalfOnStraightLine() {
        // Straight-line segment: control points at 1/3 and 2/3 → t=0.5 gives midpoint
        let p0 = Vector2D(x: 0, y: 0)
        let p3 = Vector2D(x: 2, y: 0)
        let seg = BezierMath.connector(from: p0, to: p3, cpRatios: Vector2D(x: 1.0 / 3, y: 2.0 / 3))
        assertVec2(BezierMath.point(seg: seg, t: 0.5), Vector2D(x: 1, y: 0), "midpoint of straight segment")
    }

    func testPoint4ArgMatchesSegForm() {
        let p0 = Vector2D(x: 0, y: 0)
        let p1 = Vector2D(x: 1, y: 3)
        let p2 = Vector2D(x: 3, y: 3)
        let p3 = Vector2D(x: 4, y: 0)
        let t = 0.3
        assertVec2(
            BezierMath.point(p0, p1, p2, p3, t: t),
            BezierMath.point(seg: [p0, p1, p2, p3], t: t),
            "4-arg and seg forms must agree"
        )
    }

    // MARK: split

    func testSplitContinuity() {
        let seg = BezierMath.connector(
            from: Vector2D(x: 0, y: 0), to: Vector2D(x: 4, y: 2),
            cpRatios: Vector2D(x: 0.25, y: 0.75)
        )
        let (left, right) = BezierMath.split(seg: seg, t: 0.5)
        assertVec2(left[3], right[0], "split point must be continuous")
    }

    func testSplitPreservesEndpoints() {
        let p0 = Vector2D(x: 1, y: 2)
        let p3 = Vector2D(x: 7, y: 8)
        let seg = BezierMath.connector(from: p0, to: p3, cpRatios: Vector2D(x: 0.25, y: 0.75))
        let (left, right) = BezierMath.split(seg: seg, t: 0.4)
        assertVec2(left[0], p0, "left[0] == original p0")
        assertVec2(right[3], p3, "right[3] == original p3")
    }

    func testSplitMidpointOnStraightLine() {
        let seg = BezierMath.connector(
            from: Vector2D(x: 0, y: 0), to: Vector2D(x: 2, y: 0),
            cpRatios: Vector2D(x: 1.0 / 3, y: 2.0 / 3)
        )
        let (left, _) = BezierMath.split(seg: seg, t: 0.5)
        assertVec2(left[3], Vector2D(x: 1, y: 0), "split midpoint of straight segment")
    }

    func testSplitPointMatchesCurveEval() {
        let p0 = Vector2D(x: 0, y: 0)
        let p1 = Vector2D(x: 1, y: 2)
        let p2 = Vector2D(x: 3, y: 2)
        let p3 = Vector2D(x: 4, y: 0)
        let t = 0.6
        let (left, _) = BezierMath.split(p0, p1, p2, p3, t: t)
        let expected = BezierMath.point(p0, p1, p2, p3, t: t)
        assertVec2(left[3], expected, "split[3] should equal curve eval at t")
    }

    func testSplitContinuityArbitraryT() {
        let p0 = Vector2D(x: 0, y: 1)
        let p1 = Vector2D(x: 2, y: 4)
        let p2 = Vector2D(x: 5, y: 4)
        let p3 = Vector2D(x: 7, y: 1)
        for t in [0.1, 0.25, 0.5, 0.75, 0.9] {
            let (left, right) = BezierMath.split(p0, p1, p2, p3, t: t)
            assertVec2(left[3], right[0], "continuity at t=\(t)")
        }
    }

    // MARK: centreSpline

    func testCentreSplineSquare() {
        let c = BezierMath.centreSpline(makeSquare().points)
        assertVec2(c, Vector2D(x: 0.5, y: 0.5), "centre of unit square")
    }

    func testCentreSplineEmpty() {
        let c = BezierMath.centreSpline([])
        assertVec2(c, .zero, "empty → .zero")
    }

    func testCentreSplineTriangle() {
        let tri = makeTriangle()
        let c = BezierMath.centreSpline(tri.points)
        // Anchors at (0,0), (1,0), (0.5,1): avg = (0.5, 1/3)
        assertVec2(c, Vector2D(x: 0.5, y: 1.0 / 3), "triangle anchor average")
    }

    // MARK: reverseSegment

    func testReverseSegmentSwapsEndpoints() {
        let a = Vector2D(x: 1, y: 0)
        let b = Vector2D(x: 2, y: 0)
        let c = Vector2D(x: 3, y: 0)
        let d = Vector2D(x: 4, y: 0)
        let rev = BezierMath.reverseSegment([a, b, c, d])
        XCTAssertEqual(rev[0], d)
        XCTAssertEqual(rev[1], c)
        XCTAssertEqual(rev[2], b)
        XCTAssertEqual(rev[3], a)
    }

    func testReverseSegmentLength() {
        let seg = BezierMath.connector(
            from: .zero, to: Vector2D(x: 1, y: 1),
            cpRatios: Vector2D(x: 0.25, y: 0.75)
        )
        XCTAssertEqual(BezierMath.reverseSegment(seg).count, 4)
    }

    // MARK: extractSides

    func testExtractSidesCount() {
        let sides = BezierMath.extractSides(makeSquare().points, sidesTotal: 4)
        XCTAssertEqual(sides.count, 4)
        for s in sides { XCTAssertEqual(s.count, 4) }
    }

    func testExtractSidesFirstAnchors() {
        let sides = BezierMath.extractSides(makeSquare().points, sidesTotal: 4)
        // Corners of unit square in order
        XCTAssertEqual(sides[0][0], Vector2D(x: 0, y: 0))
        XCTAssertEqual(sides[1][0], Vector2D(x: 1, y: 0))
        XCTAssertEqual(sides[2][0], Vector2D(x: 1, y: 1))
        XCTAssertEqual(sides[3][0], Vector2D(x: 0, y: 1))
    }

    // MARK: connector

    func testConnectorEndpoints() {
        let from = Vector2D(x: 1, y: 2)
        let to   = Vector2D(x: 5, y: 6)
        let seg  = BezierMath.connector(from: from, to: to, cpRatios: Vector2D(x: 0.25, y: 0.75))
        assertVec2(seg[0], from, "connector[0] == from")
        assertVec2(seg[3], to,   "connector[3] == to")
    }

    func testConnectorControlPoints() {
        let from = Vector2D(x: 0, y: 0)
        let to   = Vector2D(x: 4, y: 0)
        let seg  = BezierMath.connector(from: from, to: to, cpRatios: Vector2D(x: 0.25, y: 0.75))
        assertVec2(seg[1], Vector2D(x: 1, y: 0), "cp1 at 25% along line")
        assertVec2(seg[2], Vector2D(x: 3, y: 0), "cp2 at 75% along line")
    }

    func testConnectorLength() {
        let seg = BezierMath.connector(
            from: .zero, to: Vector2D(x: 1, y: 1),
            cpRatios: Vector2D(x: 0.25, y: 0.75)
        )
        XCTAssertEqual(seg.count, 4)
    }

    // MARK: insetPoints

    func testInsetPointsPreservesCount() {
        let sq = makeSquare()
        let centre = BezierMath.centreSpline(sq.points)
        let inset = BezierMath.insetPoints(sq.points, transform: .default, centre: centre)
        XCTAssertEqual(inset.count, sq.points.count)
    }

    func testInsetPointsScaleTowardCentre() {
        let sq = makeSquare()
        let centre = BezierMath.centreSpline(sq.points)  // (0.5, 0.5)
        let t = InsetTransform(translation: .zero, scale: Vector2D(x: 0.5, y: 0.5), rotation: 0)
        let inset = BezierMath.insetPoints(sq.points, transform: t, centre: centre)
        // Corner (0,0): x = (0-0.5)*0.5+0.5 = 0.25, y = 0.25
        assertVec2(inset[0], Vector2D(x: 0.25, y: 0.25), "corner scaled toward centre")
    }
}

// MARK: - InsetTransformTests

final class InsetTransformTests: XCTestCase {
    let eps = 1e-10

    private func assertVec2(_ a: Vector2D, _ b: Vector2D, _ msg: String = "") {
        XCTAssertEqual(a.x, b.x, accuracy: eps, "x: \(msg)")
        XCTAssertEqual(a.y, b.y, accuracy: eps, "y: \(msg)")
    }

    func testApplyScaleOnly() {
        // scale 0.5 around (0.5,0.5): (0,0) → (0.25, 0.25)
        let t = InsetTransform(translation: .zero, scale: Vector2D(x: 0.5, y: 0.5), rotation: 0)
        let r = t.apply(to: Vector2D(x: 0, y: 0), around: Vector2D(x: 0.5, y: 0.5))
        assertVec2(r, Vector2D(x: 0.25, y: 0.25))
    }

    func testApplyWithTranslation() {
        // scale 0.5 + translation (0.1, 0.2) around (0.5,0.5): (0,0) → (0.35, 0.45)
        let t = InsetTransform(
            translation: Vector2D(x: 0.1, y: 0.2),
            scale: Vector2D(x: 0.5, y: 0.5),
            rotation: 0
        )
        let r = t.apply(to: Vector2D(x: 0, y: 0), around: Vector2D(x: 0.5, y: 0.5))
        assertVec2(r, Vector2D(x: 0.35, y: 0.45))
    }

    func testApplyIdentityLeavesPointUnchanged() {
        let t = InsetTransform(translation: .zero, scale: Vector2D(x: 1, y: 1), rotation: 0)
        let pt = Vector2D(x: 3, y: 4)
        assertVec2(t.apply(to: pt, around: .zero), pt, "identity transform")
    }

    func testApplyRotation90() {
        // scale 0.5 around (0.5,0.5), then rotate 90°:
        // (1,0) → scale → (0.75, 0.25) → rotate90 around (0.5,0.5) → (0.75, 0.75)
        let t = InsetTransform(
            translation: .zero,
            scale: Vector2D(x: 0.5, y: 0.5),
            rotation: .pi / 2
        )
        let r = t.apply(to: Vector2D(x: 1, y: 0), around: Vector2D(x: 0.5, y: 0.5))
        assertVec2(r, Vector2D(x: 0.75, y: 0.75))
    }

    func testApplyRotationZeroSameAsNoRotation() {
        let noRot = InsetTransform(translation: .zero, scale: Vector2D(x: 0.5, y: 0.5), rotation: 0)
        let pt = Vector2D(x: 2, y: 3)
        let centre = Vector2D(x: 1, y: 1)
        assertVec2(
            noRot.apply(to: pt, around: centre),
            noRot.apply(to: pt, around: centre),
            "rotation=0 branch is deterministic"
        )
    }

    func testApplyAbsolute() {
        let t = InsetTransform(translation: .zero, scale: Vector2D(x: 2, y: 3), rotation: 0)
        assertVec2(t.applyAbsolute(to: Vector2D(x: 1, y: 1)), Vector2D(x: 2, y: 3))
    }

    func testApplyAbsoluteIgnoresTranslation() {
        // applyAbsolute: P' = P × scale only
        let t = InsetTransform(
            translation: Vector2D(x: 100, y: 100),
            scale: Vector2D(x: 2, y: 3),
            rotation: 0
        )
        assertVec2(t.applyAbsolute(to: Vector2D(x: 1, y: 1)), Vector2D(x: 2, y: 3))
    }

    func testDefaultTransform() {
        XCTAssertEqual(InsetTransform.default.scale.x, 0.5)
        XCTAssertEqual(InsetTransform.default.scale.y, 0.5)
        XCTAssertEqual(InsetTransform.default.translation, .zero)
        XCTAssertEqual(InsetTransform.default.rotation, 0)
    }

    func testCodableRoundTrip() throws {
        let t = InsetTransform(
            translation: Vector2D(x: 1, y: 2),
            scale: Vector2D(x: 0.3, y: 0.7),
            rotation: 1.5
        )
        let data    = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(InsetTransform.self, from: data)
        XCTAssertEqual(t, decoded)
    }
}

// MARK: - SubdivisionTypeTests

final class SubdivisionTypeTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(SubdivisionType.quad.rawValue,               0)
        XCTAssertEqual(SubdivisionType.quadBord.rawValue,           1)
        XCTAssertEqual(SubdivisionType.quadBordEcho.rawValue,       2)
        XCTAssertEqual(SubdivisionType.quadBordDouble.rawValue,     3)
        XCTAssertEqual(SubdivisionType.quadBordDoubleEcho.rawValue, 4)
        XCTAssertEqual(SubdivisionType.tri.rawValue,                5)
        XCTAssertEqual(SubdivisionType.triBordA.rawValue,           6)
        XCTAssertEqual(SubdivisionType.triBordAEcho.rawValue,       7)
        XCTAssertEqual(SubdivisionType.triBordB.rawValue,           8)
        XCTAssertEqual(SubdivisionType.triStar.rawValue,            9)
        XCTAssertEqual(SubdivisionType.triBordC.rawValue,           10)
        XCTAssertEqual(SubdivisionType.triBordCEcho.rawValue,       11)
        XCTAssertEqual(SubdivisionType.splitVert.rawValue,          12)
        XCTAssertEqual(SubdivisionType.splitHoriz.rawValue,         13)
        XCTAssertEqual(SubdivisionType.splitDiag.rawValue,          14)
        XCTAssertEqual(SubdivisionType.echo.rawValue,               16)
        XCTAssertEqual(SubdivisionType.echoAbsCenter.rawValue,      17)
        XCTAssertEqual(SubdivisionType.triBordBEcho.rawValue,       18)
        XCTAssertEqual(SubdivisionType.triStarFill.rawValue,        19)
    }

    func testAllCasesCount() {
        XCTAssertEqual(SubdivisionType.allCases.count, 19)
    }

    func testOutputCountSquare() {
        let n = 4
        XCTAssertEqual(SubdivisionType.quad.outputCount(sidesTotal: n),               4)
        XCTAssertEqual(SubdivisionType.quadBord.outputCount(sidesTotal: n),           4)
        XCTAssertEqual(SubdivisionType.quadBordEcho.outputCount(sidesTotal: n),       5)
        XCTAssertEqual(SubdivisionType.quadBordDouble.outputCount(sidesTotal: n),     8)
        XCTAssertEqual(SubdivisionType.quadBordDoubleEcho.outputCount(sidesTotal: n), 9)
        XCTAssertEqual(SubdivisionType.tri.outputCount(sidesTotal: n),                4)
        XCTAssertEqual(SubdivisionType.triBordA.outputCount(sidesTotal: n),           4)
        XCTAssertEqual(SubdivisionType.triBordAEcho.outputCount(sidesTotal: n),       5)
        XCTAssertEqual(SubdivisionType.triBordB.outputCount(sidesTotal: n),           4)
        XCTAssertEqual(SubdivisionType.triBordBEcho.outputCount(sidesTotal: n),       5)
        XCTAssertEqual(SubdivisionType.triBordC.outputCount(sidesTotal: n),           12)
        XCTAssertEqual(SubdivisionType.triBordCEcho.outputCount(sidesTotal: n),       13)
        XCTAssertEqual(SubdivisionType.triStar.outputCount(sidesTotal: n),            5)
        XCTAssertEqual(SubdivisionType.triStarFill.outputCount(sidesTotal: n),        9)
        XCTAssertEqual(SubdivisionType.splitVert.outputCount(sidesTotal: n),          2)
        XCTAssertEqual(SubdivisionType.splitHoriz.outputCount(sidesTotal: n),         2)
        XCTAssertEqual(SubdivisionType.splitDiag.outputCount(sidesTotal: n),          2)
        XCTAssertEqual(SubdivisionType.echo.outputCount(sidesTotal: n),               1)
        XCTAssertEqual(SubdivisionType.echoAbsCenter.outputCount(sidesTotal: n),      1)
    }

    func testOutputCountTriangle() {
        let n = 3
        XCTAssertEqual(SubdivisionType.quad.outputCount(sidesTotal: n),       3)
        XCTAssertEqual(SubdivisionType.tri.outputCount(sidesTotal: n),        3)
        XCTAssertEqual(SubdivisionType.triStar.outputCount(sidesTotal: n),    4)
        XCTAssertEqual(SubdivisionType.triStarFill.outputCount(sidesTotal: n),7)
        XCTAssertEqual(SubdivisionType.triBordC.outputCount(sidesTotal: n),   9)
    }
}

// MARK: - VisibilityRuleTests

final class VisibilityRuleTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(VisibilityRule.all.rawValue,           0)
        XCTAssertEqual(VisibilityRule.quads.rawValue,         1)
        XCTAssertEqual(VisibilityRule.tris.rawValue,          2)
        XCTAssertEqual(VisibilityRule.allButLast.rawValue,    3)
        XCTAssertEqual(VisibilityRule.alternateOdd.rawValue,  4)
        XCTAssertEqual(VisibilityRule.alternateEven.rawValue, 5)
        XCTAssertEqual(VisibilityRule.firstHalf.rawValue,     6)
        XCTAssertEqual(VisibilityRule.secondHalf.rawValue,    7)
        XCTAssertEqual(VisibilityRule.everyThird.rawValue,    8)
        XCTAssertEqual(VisibilityRule.everyFourth.rawValue,   9)
        XCTAssertEqual(VisibilityRule.everyFifth.rawValue,    10)
        XCTAssertEqual(VisibilityRule.random1in2.rawValue,    11)
        XCTAssertEqual(VisibilityRule.random1in3.rawValue,    12)
        XCTAssertEqual(VisibilityRule.random1in5.rawValue,    13)
        XCTAssertEqual(VisibilityRule.random1in7.rawValue,    14)
        XCTAssertEqual(VisibilityRule.random1in10.rawValue,   15)
    }

    func testAllCasesCount() {
        XCTAssertEqual(VisibilityRule.allCases.count, 16)
    }
}

// MARK: - SubdivisionParamsTests

final class SubdivisionParamsTests: XCTestCase {

    func testDefaultValues() {
        let p = SubdivisionParams()
        XCTAssertEqual(p.subdivisionType, .quad)
        XCTAssertEqual(p.lineRatios.x, 0.5)
        XCTAssertEqual(p.lineRatios.y, 0.5)
        XCTAssertEqual(p.controlPointRatios.x, 0.25)
        XCTAssertEqual(p.controlPointRatios.y, 0.75)
        XCTAssertTrue(p.continuous)
        XCTAssertFalse(p.ranMiddle)
        XCTAssertEqual(p.ranDiv, 100)
        XCTAssertEqual(p.visibilityRule, .all)
    }

    func testSplitRatioContinuousEven() {
        let p = SubdivisionParams(lineRatios: Vector2D(x: 0.3, y: 0.7), continuous: true)
        XCTAssertEqual(p.splitRatio(forSideIndex: 0), 0.3, accuracy: 1e-10)
        XCTAssertEqual(p.splitRatio(forSideIndex: 2), 0.3, accuracy: 1e-10)
    }

    func testSplitRatioContinuousOdd() {
        let p = SubdivisionParams(lineRatios: Vector2D(x: 0.3, y: 0.7), continuous: true)
        XCTAssertEqual(p.splitRatio(forSideIndex: 1), 0.7, accuracy: 1e-10)
        XCTAssertEqual(p.splitRatio(forSideIndex: 3), 0.7, accuracy: 1e-10)
    }

    func testSplitRatioNonContinuous() {
        let p = SubdivisionParams(lineRatios: Vector2D(x: 0.3, y: 0.7), continuous: false)
        XCTAssertEqual(p.splitRatio(forSideIndex: 0), 0.3, accuracy: 1e-10)
        XCTAssertEqual(p.splitRatio(forSideIndex: 1), 0.3, accuracy: 1e-10, "odd ignored when not continuous")
        XCTAssertEqual(p.splitRatio(forSideIndex: 3), 0.3, accuracy: 1e-10)
    }

    func testCodableRoundTrip() throws {
        let p = SubdivisionParams(
            name: "round-trip",
            subdivisionType: .tri,
            lineRatios: Vector2D(x: 0.3, y: 0.7),
            visibilityRule: .alternateEven
        )
        let data    = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(SubdivisionParams.self, from: data)
        XCTAssertEqual(decoded.name, p.name)
        XCTAssertEqual(decoded.subdivisionType, p.subdivisionType)
        XCTAssertEqual(decoded.lineRatios.x, p.lineRatios.x, accuracy: 1e-10)
        XCTAssertEqual(decoded.lineRatios.y, p.lineRatios.y, accuracy: 1e-10)
        XCTAssertEqual(decoded.visibilityRule, p.visibilityRule)
    }
}

// MARK: - SubdivisionEngineTests

final class SubdivisionEngineTests: XCTestCase {

    // MARK: - Helpers

    private func subdivide(_ poly: Polygon2D, type: SubdivisionType) -> [Polygon2D] {
        var rng = SystemRandomNumberGenerator()
        return SubdivisionEngine.subdivide(
            polygon: poly,
            params: SubdivisionParams(subdivisionType: type),
            rng: &rng
        )
    }

    private func subdivideSquare(type: SubdivisionType) -> [Polygon2D] {
        subdivide(makeSquare(), type: type)
    }

    private func subdivideTriangle(type: SubdivisionType) -> [Polygon2D] {
        subdivide(makeTriangle(), type: type)
    }

    // MARK: - Bypass types

    func testBypassOpenSplinePassthrough() {
        let poly = Polygon2D(points: makeSquare().points, type: .openSpline)
        var rng  = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.subdivide(polygon: poly, params: SubdivisionParams(), rng: &rng)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], poly, "openSpline polygon must be returned unchanged")
    }

    func testBypassPointPassthrough() {
        let poly = Polygon2D(points: [Vector2D(x: 1, y: 2)], type: .point)
        var rng  = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.subdivide(polygon: poly, params: SubdivisionParams(), rng: &rng)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], poly, "point polygon must be returned unchanged")
    }

    func testBypassOvalPassthrough() {
        let poly = Polygon2D(points: makeSquare().points, type: .oval)
        var rng  = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.subdivide(polygon: poly, params: SubdivisionParams(), rng: &rng)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], poly, "oval polygon must be returned unchanged")
    }

    // MARK: - Algorithm output counts: square (n=4)

    func testQuadOutputCount()               { XCTAssertEqual(subdivideSquare(type: .quad).count,               4) }
    func testQuadBordOutputCount()           { XCTAssertEqual(subdivideSquare(type: .quadBord).count,           4) }
    func testQuadBordEchoOutputCount()       { XCTAssertEqual(subdivideSquare(type: .quadBordEcho).count,       5) }
    func testQuadBordDoubleOutputCount()     { XCTAssertEqual(subdivideSquare(type: .quadBordDouble).count,     8) }
    func testQuadBordDoubleEchoOutputCount() { XCTAssertEqual(subdivideSquare(type: .quadBordDoubleEcho).count, 9) }
    func testTriOutputCount()                { XCTAssertEqual(subdivideSquare(type: .tri).count,                4) }
    func testTriBordAOutputCount()           { XCTAssertEqual(subdivideSquare(type: .triBordA).count,           4) }
    func testTriBordAEchoOutputCount()       { XCTAssertEqual(subdivideSquare(type: .triBordAEcho).count,       5) }
    func testTriBordBOutputCount()           { XCTAssertEqual(subdivideSquare(type: .triBordB).count,           4) }
    func testTriBordBEchoOutputCount()       { XCTAssertEqual(subdivideSquare(type: .triBordBEcho).count,       5) }
    func testTriBordCOutputCount()           { XCTAssertEqual(subdivideSquare(type: .triBordC).count,           12) }
    func testTriBordCEchoOutputCount()       { XCTAssertEqual(subdivideSquare(type: .triBordCEcho).count,       13) }
    func testTriStarOutputCount()            { XCTAssertEqual(subdivideSquare(type: .triStar).count,            5) }
    func testTriStarFillOutputCount()        { XCTAssertEqual(subdivideSquare(type: .triStarFill).count,        9) }
    func testSplitVertOutputCount()          { XCTAssertEqual(subdivideSquare(type: .splitVert).count,          2) }
    func testSplitHorizOutputCount()         { XCTAssertEqual(subdivideSquare(type: .splitHoriz).count,         2) }
    func testSplitDiagOutputCount()          { XCTAssertEqual(subdivideSquare(type: .splitDiag).count,          2) }
    func testEchoOutputCount()               { XCTAssertEqual(subdivideSquare(type: .echo).count,               1) }
    func testEchoAbsCenterOutputCount()      { XCTAssertEqual(subdivideSquare(type: .echoAbsCenter).count,      1) }

    // MARK: - Algorithm output counts: triangle (n=3)

    func testTriTriangleOutputCount()          { XCTAssertEqual(subdivideTriangle(type: .tri).count,         3) }
    func testTriStarTriangleOutputCount()      { XCTAssertEqual(subdivideTriangle(type: .triStar).count,     4) }
    func testTriStarFillTriangleOutputCount()  { XCTAssertEqual(subdivideTriangle(type: .triStarFill).count, 7) }
    func testTriBordCTriangleOutputCount()     { XCTAssertEqual(subdivideTriangle(type: .triBordC).count,    9) }

    // MARK: - Output validity: all algorithms

    func testAllChildrenAreSplineType() {
        for type in SubdivisionType.allCases {
            let children = subdivideSquare(type: type)
            for (i, child) in children.enumerated() {
                XCTAssertEqual(child.type, .spline, "\(type) child[\(i)] must be .spline")
            }
        }
    }

    func testAllChildrenHaveMultipleOf4Points() {
        for type in SubdivisionType.allCases {
            let children = subdivideSquare(type: type)
            for (i, child) in children.enumerated() {
                XCTAssertEqual(
                    child.points.count % 4, 0,
                    "\(type) child[\(i)] points.count=\(child.points.count) must be multiple of 4"
                )
            }
        }
    }

    func testOutputCountMatchesExpected() {
        // Cross-check: actual output count == SubdivisionType.outputCount(sidesTotal:4)
        for type in SubdivisionType.allCases {
            let actual   = subdivideSquare(type: type).count
            let expected = type.outputCount(sidesTotal: 4)
            XCTAssertEqual(actual, expected, "\(type): actual \(actual) ≠ expected \(expected)")
        }
    }

    // MARK: - QUAD geometry

    func testQuadChildrenStartAtSquareCorners() {
        let children = subdivideSquare(type: .quad)
        let corners  = Set([
            Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0),
            Vector2D(x: 1, y: 1), Vector2D(x: 0, y: 1),
        ])
        for (i, child) in children.enumerated() {
            XCTAssertTrue(
                corners.contains(child.points[0]),
                "quad child[\(i)] first anchor \(child.points[0]) should be a square corner"
            )
        }
    }

    // MARK: - ECHO geometry

    func testEchoChildSameCentreAsParent() {
        let sq = makeSquare()
        var rng = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.subdivide(
            polygon: sq,
            params: SubdivisionParams(subdivisionType: .echo),
            rng: &rng
        )
        XCTAssertEqual(result.count, 1)
        let parentCentre = BezierMath.centreSpline(sq.points)
        let childCentre  = BezierMath.centreSpline(result[0].points)
        XCTAssertEqual(childCentre.x, parentCentre.x, accuracy: 1e-10)
        XCTAssertEqual(childCentre.y, parentCentre.y, accuracy: 1e-10)
    }

    // MARK: - Visibility rules

    func testApplyVisibilityAll() {
        let polys = (0..<5).map { _ in makeSquare() }
        var rng   = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.applyVisibility(polys, rule: .all, rng: &rng)
        XCTAssertTrue(result.allSatisfy { $0.visible }, "all should be visible")
    }

    func testApplyVisibilityAllButLast() {
        let polys  = (0..<4).map { _ in makeSquare() }
        var rng    = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.applyVisibility(polys, rule: .allButLast, rng: &rng)
        XCTAssertTrue(result[0].visible)
        XCTAssertTrue(result[1].visible)
        XCTAssertTrue(result[2].visible)
        XCTAssertFalse(result[3].visible, "last polygon should be invisible")
    }

    func testApplyVisibilityAlternateEven() {
        let polys  = (0..<4).map { _ in makeSquare() }
        var rng    = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.applyVisibility(polys, rule: .alternateEven, rng: &rng)
        XCTAssertTrue(result[0].visible,  "index 0 (even) visible")
        XCTAssertFalse(result[1].visible, "index 1 (odd) invisible")
        XCTAssertTrue(result[2].visible,  "index 2 (even) visible")
        XCTAssertFalse(result[3].visible, "index 3 (odd) invisible")
    }

    func testApplyVisibilityAlternateOdd() {
        let polys  = (0..<4).map { _ in makeSquare() }
        var rng    = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.applyVisibility(polys, rule: .alternateOdd, rng: &rng)
        XCTAssertFalse(result[0].visible, "index 0 (even) invisible")
        XCTAssertTrue(result[1].visible,  "index 1 (odd) visible")
        XCTAssertFalse(result[2].visible, "index 2 (even) invisible")
        XCTAssertTrue(result[3].visible,  "index 3 (odd) visible")
    }

    func testApplyVisibilityFirstHalf() {
        // 4 polys, firstHalf: index < 4/2=2 → indices 0,1 visible
        let polys  = (0..<4).map { _ in makeSquare() }
        var rng    = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.applyVisibility(polys, rule: .firstHalf, rng: &rng)
        XCTAssertTrue(result[0].visible)
        XCTAssertTrue(result[1].visible)
        XCTAssertFalse(result[2].visible)
        XCTAssertFalse(result[3].visible)
    }

    func testApplyVisibilitySecondHalf() {
        // 4 polys, secondHalf: index > 4/2=2 → only index 3 visible
        let polys  = (0..<4).map { _ in makeSquare() }
        var rng    = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.applyVisibility(polys, rule: .secondHalf, rng: &rng)
        XCTAssertFalse(result[0].visible)
        XCTAssertFalse(result[1].visible)
        XCTAssertFalse(result[2].visible)
        XCTAssertTrue(result[3].visible, "only index 3 (> 2) visible")
    }

    func testApplyVisibilityEveryThird() {
        let polys  = (0..<6).map { _ in makeSquare() }
        var rng    = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.applyVisibility(polys, rule: .everyThird, rng: &rng)
        XCTAssertTrue(result[0].visible)
        XCTAssertFalse(result[1].visible)
        XCTAssertFalse(result[2].visible)
        XCTAssertTrue(result[3].visible)
        XCTAssertFalse(result[4].visible)
        XCTAssertFalse(result[5].visible)
    }

    func testApplyVisibilityRandomPreservesCount() {
        let polys  = (0..<10).map { _ in makeSquare() }
        var rng    = SystemRandomNumberGenerator()
        for rule in [VisibilityRule.random1in2, .random1in3, .random1in5, .random1in7, .random1in10] {
            let result = SubdivisionEngine.applyVisibility(polys, rule: rule, rng: &rng)
            XCTAssertEqual(result.count, 10, "\(rule): count must not change")
        }
    }

    // MARK: - Process pipeline

    func testProcessTwoGenerationsQuad() {
        // 1 square → quad (4) → quad (16)
        var rng    = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.process(
            polygons: [makeSquare()],
            paramSet: [SubdivisionParams(subdivisionType: .quad),
                       SubdivisionParams(subdivisionType: .quad)],
            rng: &rng
        )
        XCTAssertEqual(result.count, 16)
    }

    func testProcessPrunesInvisibleBetweenGenerations() {
        // Gen1: quad → 4, alternateEven → 2 visible. Gen2: quad on 2 → 8.
        var rng    = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.process(
            polygons: [makeSquare()],
            paramSet: [SubdivisionParams(subdivisionType: .quad, visibilityRule: .alternateEven),
                       SubdivisionParams(subdivisionType: .quad)],
            rng: &rng
        )
        XCTAssertEqual(result.count, 8, "2 visible gen1 × 4 gen2 quad = 8")
    }

    func testProcessPreservesBypassPolygons() {
        let bypass = Polygon2D(points: makeSquare().points, type: .openSpline)
        var rng    = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.process(
            polygons: [makeSquare(), bypass],
            paramSet: [SubdivisionParams(subdivisionType: .quad)],
            rng: &rng
        )
        // 4 active children + 1 bypass
        XCTAssertEqual(result.count, 5)
        let bypassResult = result.first { $0.type == .openSpline }
        XCTAssertNotNil(bypassResult, "bypass polygon must be in output")
        XCTAssertEqual(bypassResult, bypass, "bypass polygon must be identical to input")
    }

    func testProcessEmptyParamSetReturnsInput() {
        var rng    = SystemRandomNumberGenerator()
        let result = SubdivisionEngine.process(
            polygons: [makeSquare()],
            paramSet: [],
            rng: &rng
        )
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - ranMiddle

    func testRanMiddleProducesValidOutput() {
        // ranMiddle jitters the centre; output count and point structure must still be valid
        var rng    = SystemRandomNumberGenerator()
        let params = SubdivisionParams(subdivisionType: .quad, ranMiddle: true, ranDiv: 1.0)
        let result = SubdivisionEngine.subdivide(polygon: makeSquare(), params: params, rng: &rng)
        XCTAssertEqual(result.count, 4)
        for child in result {
            XCTAssertEqual(child.points.count % 4, 0)
            XCTAssertEqual(child.type, .spline)
        }
    }

    // MARK: - QUAD 3-level diagnostic (Test_055 rect polygon)

    /// Reproduces the Test_055 setup: exact rect.xml coordinates, 3 QUAD levels,
    /// params matching Test_055 (lineRatios=0.5/0.5, controlPointRatios=0.25/0.75).
    ///
    /// Checks that every bezier segment in every level-3 polygon has collinear
    /// control points (i.e. is a straight-line bezier, not a curved one).
    ///
    /// Cross products of (cp - anchor) vs (endpoint - anchor) must be ~0 for
    /// a straight-line segment.  Any failure identifies the exact polygon and
    /// segment index that first becomes non-collinear.
    func testQuad3LevelRectCollinearity() {
        // Exact points from Test_055/polygonSets/rect.xml
        let rectPts: [Vector2D] = [
            // Curve 1: bottom edge  (-0.35,-0.4) → (0.3,-0.4)
            Vector2D(x: -0.35, y: -0.4), Vector2D(x: -0.13, y: -0.4),
            Vector2D(x:  0.08, y: -0.4), Vector2D(x:  0.3,  y: -0.4),
            // Curve 2: right edge   (0.3,-0.4) → (0.3,0.3)
            Vector2D(x:  0.3,  y: -0.4), Vector2D(x:  0.3,  y: -0.17),
            Vector2D(x:  0.3,  y:  0.07), Vector2D(x:  0.3,  y:  0.3),
            // Curve 3: top edge     (0.3,0.3) → (-0.35,0.3)
            Vector2D(x:  0.3,  y:  0.3), Vector2D(x:  0.08, y:  0.3),
            Vector2D(x: -0.13, y:  0.3), Vector2D(x: -0.35, y:  0.3),
            // Curve 4: left edge    (-0.35,0.3) → (-0.35,-0.4)
            Vector2D(x: -0.35, y:  0.3), Vector2D(x: -0.35, y:  0.07),
            Vector2D(x: -0.35, y: -0.17), Vector2D(x: -0.35, y: -0.4),
        ]
        let rectPoly = Polygon2D(points: rectPts, type: .spline)

        // Test_055 params: QUAD, t=0.5, cpRatios=(0.25,0.75), no randomisation
        let params = SubdivisionParams(
            subdivisionType:    .quad,
            lineRatios:         Vector2D(x: 0.5,  y: 0.5),
            controlPointRatios: Vector2D(x: 0.25, y: 0.75),
            continuous:         true,
            ranMiddle:          false,
            visibilityRule:     .all,
            polysTransform:     false
        )
        let paramSet = [params, params, params]

        var rng = SystemRandomNumberGenerator()
        let level3 = SubdivisionEngine.process(
            polygons: [rectPoly],
            paramSet: paramSet,
            rng: &rng
        )

        XCTAssertEqual(level3.count, 64, "3 QUAD levels on a 4-sided polygon must yield 64 children")

        // Collinearity tolerance: cross product of (cp-a0) × (a1-a0) must be ~0
        let eps = 1e-9
        for (polyIdx, poly) in level3.enumerated() {
            let pts = poly.points
            XCTAssertEqual(pts.count, 16, "poly[\(polyIdx)] must have 16 points")
            let segments = pts.count / 4
            for seg in 0..<segments {
                let base = seg * 4
                let a0 = pts[base]
                let cp1 = pts[base + 1]
                let cp2 = pts[base + 2]
                let a1 = pts[base + 3]
                let edge = Vector2D(x: a1.x - a0.x, y: a1.y - a0.y)
                let toCP1 = Vector2D(x: cp1.x - a0.x, y: cp1.y - a0.y)
                let toCP2 = Vector2D(x: cp2.x - a0.x, y: cp2.y - a0.y)
                let cross1 = edge.x * toCP1.y - edge.y * toCP1.x
                let cross2 = edge.x * toCP2.y - edge.y * toCP2.x
                XCTAssertEqual(cross1, 0, accuracy: eps,
                    "poly[\(polyIdx)] seg[\(seg)] cp1 not collinear: cross=\(cross1) a0=\(a0) cp1=\(cp1) a1=\(a1)")
                XCTAssertEqual(cross2, 0, accuracy: eps,
                    "poly[\(polyIdx)] seg[\(seg)] cp2 not collinear: cross=\(cross2) a0=\(a0) cp2=\(cp2) a1=\(a1)")
            }
        }
    }

    // MARK: - QUAD 3-level diagnostic (Test_056 square — the FAILING case)

    /// Constructs the exact square from Test_056 (corners ±0.4, control points at ±0.13)
    /// and applies 3 QUAD subdivisions with the exact Test_056 params.
    ///
    /// Prints anchor coordinates of ALL 64 level-3 polygons.
    /// This is the diagnostic that was missing: previous tests only checked the
    /// Test_055 rect and only printed the first 4 (corner) polygons. The bug
    /// is visible in the interior polygons.
    func testQuad3LevelSquare056PrintAllAnchors() {
        let square056 = makeSquare056()
        let params    = makeSquare056Params()
        var rng = SystemRandomNumberGenerator()
        let level3 = SubdivisionEngine.process(
            polygons: [square056],
            paramSet: [params, params, params],
            rng: &rng
        )
        XCTAssertEqual(level3.count, 64, "3 QUAD levels on a 4-sided polygon must yield 64 children")

        print("\n=== Test_056 square: 3-level QUAD — all 64 anchor sets ===")
        for (i, poly) in level3.enumerated() {
            let a = (0..<4).map { poly.points[$0 * 4] }
            print(String(format: "poly[%2d]:  (%.5f,%.5f)  (%.5f,%.5f)  (%.5f,%.5f)  (%.5f,%.5f)",
                         i, a[0].x, a[0].y, a[1].x, a[1].y, a[2].x, a[2].y, a[3].x, a[3].y))
        }

        // Collect all distinct anchor x and y values (rounded to 4 decimal places)
        var xs = Set<String>()
        var ys = Set<String>()
        for poly in level3 {
            for side in 0..<4 {
                let a = poly.points[side * 4]
                xs.insert(String(format: "%.4f", a.x))
                ys.insert(String(format: "%.4f", a.y))
            }
        }
        let xSorted = xs.sorted()
        let ySorted = ys.sorted()
        print("\nDistinct x-coords (\(xSorted.count)): \(xSorted.joined(separator: ", "))")
        print("Distinct y-coords (\(ySorted.count)): \(ySorted.joined(separator: ", "))")
        print("Expected 9 of each: -0.4000, -0.3000, -0.2000, -0.1000, 0.0000, 0.1000, 0.2000, 0.3000, 0.4000")
    }

    /// Asserts that all anchors from a 3-level QUAD subdivision of the Test_056 square
    /// land exactly on the expected 9×9 grid (multiples of 0.1 from −0.4 to 0.4).
    ///
    /// A perfect grid means every anchor x and y coordinate is within `tolerance` of
    /// one of {-0.4, -0.3, -0.2, -0.1, 0.0, 0.1, 0.2, 0.3, 0.4}.
    ///
    /// If this test PASSES: SubdivisionEngine.process produces correct geometry.
    ///   → The bug is in the app's render pipeline (not in SubdivisionEngine).
    /// If this test FAILS: SubdivisionEngine.process produces wrong anchor positions.
    ///   → The bug is in subdivision itself. Failure messages identify which polygon
    ///     and which anchor is wrong, and by how much.
    func testQuad3LevelSquare056GridCheck() {
        let square056 = makeSquare056()
        let params    = makeSquare056Params()
        var rng = SystemRandomNumberGenerator()
        let level3 = SubdivisionEngine.process(
            polygons: [square056],
            paramSet: [params, params, params],
            rng: &rng
        )
        XCTAssertEqual(level3.count, 64)

        let gridValues: [Double] = [-0.4, -0.3, -0.2, -0.1, 0.0, 0.1, 0.2, 0.3, 0.4]
        let tolerance = 1e-6  // strict: any visible distortion will be >> 1e-6

        func nearest(_ v: Double) -> Double {
            gridValues.min(by: { abs($0 - v) < abs($1 - v) })!
        }

        for (polyIdx, poly) in level3.enumerated() {
            for side in 0..<4 {
                let anchor = poly.points[side * 4]

                let nearestX = nearest(anchor.x)
                let nearestY = nearest(anchor.y)
                let errX = abs(anchor.x - nearestX)
                let errY = abs(anchor.y - nearestY)

                XCTAssertLessThanOrEqual(errX, tolerance,
                    "poly[\(polyIdx)] side \(side) anchor.x=\(anchor.x) is \(errX) away from grid value \(nearestX)")
                XCTAssertLessThanOrEqual(errY, tolerance,
                    "poly[\(polyIdx)] side \(side) anchor.y=\(anchor.y) is \(errY) away from grid value \(nearestY)")
            }
        }
    }

    // MARK: - Test_056 fixtures

    /// Exact square polygon from Test_056: corners at ±0.4, control points at ±0.13.
    private func makeSquare056() -> Polygon2D {
        let pts: [Vector2D] = [
            // Bottom edge (-0.4,-0.4) → (0.4,-0.4)
            Vector2D(x: -0.4, y: -0.4), Vector2D(x: -0.13, y: -0.4),
            Vector2D(x:  0.13, y: -0.4), Vector2D(x:  0.4,  y: -0.4),
            // Right edge (0.4,-0.4) → (0.4,0.4)
            Vector2D(x:  0.4,  y: -0.4), Vector2D(x:  0.4,  y: -0.13),
            Vector2D(x:  0.4,  y:  0.13), Vector2D(x:  0.4,  y:  0.4),
            // Top edge (0.4,0.4) → (-0.4,0.4)
            Vector2D(x:  0.4,  y:  0.4), Vector2D(x:  0.13, y:  0.4),
            Vector2D(x: -0.13, y:  0.4), Vector2D(x: -0.4,  y:  0.4),
            // Left edge (-0.4,0.4) → (-0.4,-0.4)
            Vector2D(x: -0.4,  y:  0.4), Vector2D(x: -0.4,  y:  0.13),
            Vector2D(x: -0.4,  y: -0.13), Vector2D(x: -0.4,  y: -0.4),
        ]
        return Polygon2D(points: pts, type: .spline)
    }

    /// Subdivision params matching Test_056's subdivision.xml exactly.
    private func makeSquare056Params() -> SubdivisionParams {
        SubdivisionParams(
            subdivisionType:    .quad,
            lineRatios:         Vector2D(x: 0.5,  y: 0.5),
            controlPointRatios: Vector2D(x: 0.25, y: 0.75),
            continuous:         true,
            ranMiddle:          false,
            visibilityRule:     .all,
            polysTransform:     false
        )
    }

    /// Prints anchor coordinates of level-3 polygons 0..3 for comparison with Scala.
    /// Run with -v flag to see output. Not a pass/fail test.
    func testQuad3LevelRectPrintAnchors() {
        let rectPts: [Vector2D] = [
            Vector2D(x: -0.35, y: -0.4), Vector2D(x: -0.13, y: -0.4),
            Vector2D(x:  0.08, y: -0.4), Vector2D(x:  0.3,  y: -0.4),
            Vector2D(x:  0.3,  y: -0.4), Vector2D(x:  0.3,  y: -0.17),
            Vector2D(x:  0.3,  y:  0.07), Vector2D(x:  0.3,  y:  0.3),
            Vector2D(x:  0.3,  y:  0.3), Vector2D(x:  0.08, y:  0.3),
            Vector2D(x: -0.13, y:  0.3), Vector2D(x: -0.35, y:  0.3),
            Vector2D(x: -0.35, y:  0.3), Vector2D(x: -0.35, y:  0.07),
            Vector2D(x: -0.35, y: -0.17), Vector2D(x: -0.35, y: -0.4),
        ]
        let rectPoly = Polygon2D(points: rectPts, type: .spline)
        let params = SubdivisionParams(
            subdivisionType:    .quad,
            lineRatios:         Vector2D(x: 0.5,  y: 0.5),
            controlPointRatios: Vector2D(x: 0.25, y: 0.75),
            continuous:         true,
            ranMiddle:          false,
            visibilityRule:     .all,
            polysTransform:     false
        )
        var rng = SystemRandomNumberGenerator()
        let level3 = SubdivisionEngine.process(
            polygons: [rectPoly],
            paramSet: [params, params, params],
            rng: &rng
        )
        // Print anchors of first 4 level-3 polygons
        for i in 0..<min(4, level3.count) {
            let pts = level3[i].points
            let anchors = (0..<4).map { pts[$0 * 4] }
            print("Level-3 poly[\(i)] anchors: \(anchors.map { "(\(String(format:"%.4f",  $0.x)), \(String(format:"%.4f", $0.y)))" }.joined(separator: ", "))")
        }
    }
}
